import 'dart:convert';

import 'package:circle_fitness/features/dashboard/domain/dashboard_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/directory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The "Upcoming" panel (Directory's bell, and Activity's "Today & beyond")
// reads `upcomingClassesProvider` / `upcomingEventsProvider`. Three things
// were wrong with what it showed:
//
//   * `.order('scheduled_at')` sorts DESCENDING unless told otherwise
//     (postgrest-dart), so with `limit(5)` the panel listed the five classes
//     FURTHEST away, latest first — the next one never appeared once there
//     were more than five;
//   * "now" was a local time sent with no zone, which Postgres reads as UTC;
//   * every row read "Class · 0 spots" or "Event": the panel read `name` and
//     `capacity`, and `classes`/`events` have `title` and `max_capacity`
//     (001_full_ecosystem.sql).
//
// The fake server sorts, filters and limits as PostgREST does, by what the
// app sends.

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

/// Seven classes, one a day from tomorrow, and seven events likewise.
class _Server extends http.BaseClient {
  final _base = DateTime.now().toUtc();

  List<Map<String, Object?>> _rows(String col, String prefix) => [
        for (var d = 1; d <= 7; d++)
          {
            'id': '$prefix$d',
            'title': '$prefix day $d',
            col: _base.add(Duration(days: d)).toIso8601String(),
            'max_capacity': 20,
            'location': 'Studio',
          },
      ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/classes')) {
      return _answer(_rows('scheduled_at', 'Class'), 'scheduled_at', request);
    }
    if (path.endsWith('/events')) {
      return _answer(_rows('event_date', 'Event'), 'event_date', request);
    }
    return _json([], request);
  }

  /// `col=gte.<instant>` (zoneless read as UTC, as Postgres does), then
  /// `order=` and `limit=`.
  http.StreamedResponse _answer(
      List<Map<String, Object?>> rows, String col, http.BaseRequest r) {
    final q = r.url.queryParameters;
    var from = q[col]!.substring('gte.'.length);
    if (!from.endsWith('Z') && !RegExp(r'[+-]\d\d:\d\d$').hasMatch(from)) {
      from = '${from}Z';
    }
    final since = DateTime.parse(from);
    final kept = rows
        .where((x) => !DateTime.parse(x[col] as String).isBefore(since))
        .toList()
      ..sort((a, b) => (a[col] as String).compareTo(b[col] as String));
    final list = (q['order'] ?? '').contains('.desc') ? kept.reversed.toList() : kept;
    final limit = int.tryParse(q['limit'] ?? '');
    return _json(limit == null ? list : list.take(limit).toList(), r);
  }

  http.StreamedResponse _json(Object body, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  List<String> titles(List<Map<String, dynamic>> rows) =>
      rows.map((r) => r['title'] as String).toList();

  test('the panel\'s classes are the NEXT five, soonest first', () async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    expect(titles(await app.read(upcomingClassesProvider.future)),
        ['Class day 1', 'Class day 2', 'Class day 3', 'Class day 4', 'Class day 5'],
        reason: 'THE defect: days 7 to 3, and tomorrow\'s class missing');
  });

  test('the panel\'s events are the NEXT five, soonest first', () async {
    final app = ProviderContainer();
    addTearDown(app.dispose);
    expect(titles(await app.read(upcomingEventsProvider.future)),
        ['Event day 1', 'Event day 2', 'Event day 3', 'Event day 4', 'Event day 5']);
  });

  testWidgets('each row is named, with its capacity', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        upcomingClassesProvider.overrideWith((ref) async => [
              {'id': 'c1', 'title': 'Morning HIIT', 'max_capacity': 20,
               'scheduled_at': '2026-11-13T07:00:00Z'},
            ]),
        upcomingEventsProvider.overrideWith((ref) async => [
              {'id': 'e1', 'title': 'Sunset Run Club', 'location': 'Pier 4',
               'event_date': '2026-11-14T18:00:00Z'},
            ]),
      ],
      child: const MaterialApp(home: DirectoryScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.notifications_outlined).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Morning HIIT'), findsOneWidget,
        reason: 'THE defect: every class read "Class"');
    expect(find.text('20 spots'), findsOneWidget,
        reason: 'THE defect: every class read "0 spots"');
    expect(find.text('Sunset Run Club'), findsOneWidget,
        reason: 'THE defect: every event read "Event"');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
