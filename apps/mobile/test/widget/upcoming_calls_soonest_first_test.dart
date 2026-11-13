import 'dart:convert';

import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:circle_fitness/features/checkins/presentation/checkin_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Upcoming calls and open slots were listed furthest first.
//
// Every one of these reads asks for "from now on" with a bare
// `.order('scheduled_at')` / `.order('slot_time')`, and postgrest-dart's
// `order()` defaults to `ascending: false` — the opposite of the JS client
// (WKT-111 met the same default in `workout_service.dart`):
//
//   * /book-call listed open slots and the client's booked calls latest first;
//   * the coach's Manage Availability listed sessions, and the days of open
//     slots, latest first;
//   * /checkins "Upcoming Sessions" read `.limit(10)` of them — the TEN
//     FURTHEST — so a client with more than ten booked calls was not shown
//     the next ones at all.

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

/// Answers like PostgREST, including `order=` and `limit=`: rows come back
/// sorted by the columns and directions the request names, as the real server
/// sorts them, then cut to the limit.
class _Server extends http.BaseClient {
  late List<Map<String, Object?>> slots;
  late List<Map<String, Object?>> calls;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    List<Map<String, Object?>> answer(List<Map<String, Object?>> rows) {
      final sorted = _ordered(rows, q['order']);
      final limit = int.tryParse(q['limit'] ?? '');
      return limit == null ? sorted : sorted.take(limit).toList();
    }

    if (path.endsWith('/coach_availability')) return _json(answer(slots), 200, request);
    if (path.endsWith('/coaching_calls')) return _json(answer(calls), 200, request);
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

  static List<Map<String, Object?>> _ordered(
      List<Map<String, Object?>> rows, String? order) {
    final keys = [
      for (final part in (order ?? '').split(',').where((p) => p.isNotEmpty))
        (column: part.split('.')[0], asc: part.split('.')[1] == 'asc'),
    ];
    return [...rows]..sort((a, b) {
        for (final k in keys) {
          final c = (a[k.column] as Comparable).compareTo(b[k.column]);
          if (c != 0) return k.asc ? c : -c;
        }
        return 0;
      });
  }

  http.StreamedResponse _json(Object? body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

/// An instant [days] from now at 10:00 local, as the database returns it.
String _at(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + days, 10).toUtc().toIso8601String();
}

Map<String, Object?> _slot(String id, int days, String type) => {
      'id': id, 'coach_id': 'coach-a', 'slot_time': _at(days),
      'duration_minutes': 30, 'type': type, 'is_booked': false,
    };

Map<String, Object?> _call(String id, int days, String type, String client) => {
      'id': id, 'client_id': _uid, 'coach_id': 'coach-a',
      'availability_slot_id': null, 'scheduled_at': _at(days),
      'duration_minutes': 30, 'call_type': type, 'status': 'scheduled',
      'client': {'first_name': client, 'last_name': 'Park', 'avatar_url': null},
      'coach': {'first_name': 'Avery', 'last_name': 'Stone'},
    };

/// Whether [first] is drawn above [second].
bool _above(WidgetTester tester, Finder first, Finder second) =>
    tester.getTopLeft(first).dy < tester.getTopLeft(second).dy;

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

  // Tall enough that every card is built; the lists are lazy.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('/book-call', () {
    setUp(() {
      // Stored latest first; the read decides the order.
      server.slots = [_slot('s-late', 9, 'nutrition_review'), _slot('s-soon', 2, 'consultation')];
      server.calls = [_call('c-late', 8, 'other', 'Jo'), _call('c-soon', 1, 'check_in', 'Jo')];
    });

    testWidgets('the soonest open slot is listed first', (tester) async {
      tall(tester);
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
      await tester.pumpAndSettle();
      expect(_above(tester, find.text('Strategy Call'), find.text('Nutrition Review')), isTrue,
          reason: 'THE defect: postgrest-dart orders descending when `ascending` '
              'is omitted, so the slot nine days out came first');
    });

    testWidgets("the client's next call is listed first", (tester) async {
      tall(tester);
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
      await tester.pumpAndSettle();
      expect(_above(tester, find.text('Weekly Check-In'), find.text('Coaching Call')), isTrue);
    });
  });

  group("the coach's Manage Availability", () {
    setUp(() {
      server.slots = [_slot('s-late', 9, 'check_in'), _slot('s-soon', 2, 'check_in')];
      server.calls = [_call('c-late', 8, 'check_in', 'Late'), _call('c-soon', 1, 'check_in', 'Soon')];
    });

    testWidgets('the next session is listed first', (tester) async {
      tall(tester);
      await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
      await tester.pumpAndSettle();
      expect(_above(tester, find.text('Soon Park'), find.text('Late Park')), isTrue);
    });

    testWidgets("the soonest day's slots are listed first", (tester) async {
      tall(tester);
      await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
      await tester.pumpAndSettle();
      final n = DateTime.now();
      final soon = DateTime(n.year, n.month, n.day + 2);
      final late = DateTime(n.year, n.month, n.day + 9);
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      String label(DateTime d) => '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
      expect(_above(tester, find.text(label(soon)), find.text(label(late))), isTrue);
    });
  });

  group('/checkins Upcoming Sessions', () {
    setUp(() {
      server.slots = [];
      // Twelve booked calls: the two soonest are strategy sessions.
      server.calls = [
        for (var d = 3; d <= 12; d++) _call('c-$d', d, 'check_in', 'Jo'),
        _call('c-2', 2, 'consultation', 'Jo'),
        _call('c-1', 1, 'consultation', 'Jo'),
      ];
    });

    testWidgets('the next calls are shown, not the ten furthest', (tester) async {
      tall(tester);
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: CheckinScreen())));
      // The screen animates continuously, so it never settles; the reads are
      // answered within a few frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Strategy Session'), findsNWidgets(2),
          reason: 'THE defect: `.limit(10)` over a descending read kept the ten '
              'furthest calls and dropped the next two');
      expect(_above(tester, find.text('Strategy Session').first, find.text('Weekly Check-In').first),
          isTrue);
    });

    testWidgets('control: at most ten are listed', (tester) async {
      tall(tester);
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: CheckinScreen())));
      // The screen animates continuously, so it never settles; the reads are
      // answered within a few frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('10 APPTS'), findsOneWidget);
    });
  });
}
