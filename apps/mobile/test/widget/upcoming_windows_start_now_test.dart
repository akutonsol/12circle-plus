import 'dart:convert';

import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// "From now on" began at the wrong instant.
//
// `coach_availability.slot_time` and `coaching_calls.scheduled_at` are
// timestamptz, written as UTC (`slotTime.toUtc()` in the coach's Add Slot sheet;
// a booking copies `slot_time`). Five reads asked for "from now" with
// `.gte(col, DateTime.now().toIso8601String())` — local time with no zone, which
// Postgres reads as UTC. West of UTC "now" was hours in the past:
//
//   * /book-call offered open slots that had already started, and listed calls
//     that were over as upcoming;
//   * the coach's Manage Availability listed past slots and past sessions;
//   * /checkins "Upcoming Sessions" listed calls that had finished.
//
// East of UTC the next hours of slots and calls were hidden instead.
//
// HOW TO SEE IT FAIL: the wire-format test fails on the old code in any zone.
// The screen tests need an offset: run with `TZ=America/New_York`.

const _uid = '00000000-0000-4000-8000-0000000c0a11';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// The token is read, never verified client-side.
String _jwt() {
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': _uid, 'role': 'authenticated', 'exp': exp, 'aud': 'authenticated'})}.'
      'not-verified-client-side';
}

class _SeededSession extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 315360000,
        'refresh_token': 'test-refresh',
        'user': {
          'id': _uid,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

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


DateTime _asPostgres(String v) {
  final zoned = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
  return DateTime.parse(zoned ? v : '${v}Z').toUtc();
}

bool _zoned(String v) => v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);

/// Answers like PostgREST, applying `gte.` / `lt.` on the timestamp columns as
/// Postgres does and `order=` as the server sorts.
class _Server extends http.BaseClient {
  List<Map<String, Object?>> slots = [];
  List<Map<String, Object?>> calls = [];
  final List<String> bounds = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final qa = request.url.queryParametersAll;
    List<Map<String, Object?>> answer(List<Map<String, Object?>> rows, String col) {
      final f = qa[col] ?? const <String>[];
      bounds.addAll(f);
      final kept = [
        for (final r in rows)
          if (f.every((x) {
            final at = _asPostgres(r[col] as String);
            final dot = x.indexOf('.');
            final b = _asPostgres(x.substring(dot + 1));
            return switch (x.substring(0, dot)) {
              'gte' => !at.isBefore(b),
              'lt' => at.isBefore(b),
              _ => true,
            };
          }))
            r,
      ]..sort((a, b) => (a[col] as String).compareTo(b[col] as String));
      return kept;
    }

    if (path.endsWith('/coach_availability')) return _json(answer(slots, 'slot_time'), 200, request);
    if (path.endsWith('/coaching_calls')) return _json(answer(calls, 'scheduled_at'), 200, request);
    if (path.endsWith('/coach_client_relationships')) {
      return _json([
        {'coach_id': 'coach-a', 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-01T00:00:00Z'},
      ], 200, request);
    }
    if (path.endsWith('/public_profiles')) {
      return _json([
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
      ], 200, request);
    }
    return _json(single ? null : [], 200, request);
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// The UTC instant [hours] from now, as the database returns it.
String _in(int hours) => DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, Object?> _slot(String id, int hours, String type) => {
      'id': id, 'coach_id': 'coach-a', 'slot_time': _in(hours),
      'duration_minutes': 30, 'type': type, 'is_booked': false,
    };

Map<String, Object?> _call(String id, int hours, String type, String client) => {
      'id': id, 'client_id': _uid, 'coach_id': 'coach-a',
      'availability_slot_id': null, 'scheduled_at': _in(hours),
      'duration_minutes': 30, 'call_type': type, 'status': 'scheduled',
      'client': {'first_name': client, 'last_name': 'Park', 'avatar_url': null},
      'coach': {'first_name': 'Avery', 'last_name': 'Stone'},
    };

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  setUp(() {
    server.bounds.clear();
    // Two hours ago (over) and three hours from now (next).
    server.slots = [_slot('s-past', -2, 'nutrition_review'), _slot('s-next', 3, 'consultation')];
    server.calls = [_call('c-past', -2, 'other', 'Past'), _call('c-next', 3, 'check_in', 'Next')];
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('every "from now" bound is sent as a zoned instant', (tester) async {
    tall(tester);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: CheckinScreen())));
    await frames(tester);
    expect(server.bounds, isNotEmpty);
    final zoneless = [
      for (final b in server.bounds)
        if (!_zoned(b.substring(b.indexOf('.') + 1))) b,
    ];
    expect(zoneless, isEmpty,
        reason: 'THE defect: a zoneless bound is read by Postgres as UTC, so "now" '
            'moved by the user\'s offset');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('/book-call offers only slots that have not started', (tester) async {
    tall(tester);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Strategy Call'), findsWidgets, reason: 'the next slot is offered');
    expect(find.text('Nutrition Review'), findsNothing,
        reason: 'a slot that started two hours ago was still offered (west of UTC)');
    expect(find.text('Weekly Check-In'), findsWidgets);
    expect(find.text('Coaching Call'), findsNothing,
        reason: 'a call that is over was listed as upcoming');
  });

  testWidgets("the coach's Manage Availability lists only sessions to come", (tester) async {
    tall(tester);
    await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Next Park'), findsOneWidget);
    expect(find.text('Past Park'), findsNothing,
        reason: 'a session two hours over was listed as upcoming (west of UTC)');
  });

  testWidgets('/checkins Upcoming Sessions lists only calls to come', (tester) async {
    tall(tester);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: CheckinScreen())));
    await frames(tester);
    expect(find.text('Weekly Check-In'), findsWidgets);
    expect(find.text('Coaching Call'), findsNothing,
        reason: 'a call two hours over was listed as upcoming (west of UTC)');
    await tester.pumpWidget(const SizedBox());
  });
}
