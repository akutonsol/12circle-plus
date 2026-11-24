import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-53b · Book a Call's two reads.
//
// At b7ec6ef `_load` (first load / refresh) and `_selectCoach` (switching
// coach) both ended a failed read in the error state — but `catch (_)`
// recorded nothing, so the outage was invisible. And the error state said
// "This is a connection problem" for EVERY failure, a server fault included.
//
// Now each failure is recorded under its own origin, the connection hint is
// shown only for a connection failure, and the legitimate absences — no
// coach, a coach with no slots — still render as themselves, unrecorded.

const _uid = '00000000-0000-4000-8000-0000000000b0';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

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

enum _Rels { fail, offline, none, two }

/// Relationships per [rels]; coach B's slots fail when [slotsBFail]; coach A
/// has [slotsA] open slots.
class _Server extends http.BaseClient {
  _Rels rels = _Rels.two;
  bool slotsBFail = false;
  int slotsA = 1;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/coach_client_relationships')) {
      switch (rels) {
        case _Rels.fail:
          body = {'message': 'SECRET_TABLE_X exploded', 'code': 'XX000'};
          status = 500;
        case _Rels.offline:
          throw const SocketException('offline');
        case _Rels.none:
          body = [];
        case _Rels.two:
          body = [
            {'coach_id': 'coach-a', 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-02T00:00:00Z'},
            {'coach_id': 'coach-b', 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-01T00:00:00Z'},
          ];
      }
    } else if (path.endsWith('/public_profiles')) {
      body = [
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
        {'id': 'coach-b', 'first_name': 'Blake', 'last_name': 'Ray', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
      ];
    } else if (path.endsWith('/coach_availability')) {
      if ((q['coach_id'] ?? '') == 'eq.coach-b' && slotsBFail) {
        body = {'message': 'SECRET_TABLE_X exploded', 'code': 'XX000'};
        status = 500;
      } else if ((q['coach_id'] ?? '') == 'eq.coach-a') {
        final at = DateTime.now().toUtc().add(const Duration(days: 2));
        body = [
          for (var i = 0; i < slotsA; i++)
            {'id': 'slot-$i', 'coach_id': 'coach-a', 'is_booked': false,
             'slot_time': at.add(Duration(hours: i)).toIso8601String(),
             'duration_minutes': 30, 'type': 'check_in'},
        ];
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

final _server = _Server();

Future<List<AppFailure>> _open(WidgetTester tester) async {
  final reported = <AppFailure>[];
  setFailureSink(reported.add);
  addTearDown(resetFailureSink);
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
  await tester.pumpAndSettle();
  return reported;
}

const _other = 'Try again in a moment. If it keeps happening, contact support.';
const _net = 'Check your connection and try again.';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    _server
      ..rels = _Rels.two
      ..slotsBFail = false
      ..slotsA = 1;
  });

  testWidgets('a failed first load is recorded, and not blamed on the connection',
      (tester) async {
    _server.rels = _Rels.fail;
    final reported = await _open(tester);
    expect(find.text("Couldn't load your bookings"), findsOneWidget);
    expect(reported.map((f) => f.origin), ['BookingScreen._load'],
        reason: 'THE defect: catch (_) recorded nothing');
    expect(reported.single.error, isA<PostgrestException>());
    expect(find.text(_other), findsOneWidget);
    expect(find.textContaining('connection problem'), findsNothing,
        reason: 'THE defect: every failure was called a connection problem');
    expect(find.textContaining('SECRET_TABLE_X'), findsNothing);
  });

  testWidgets('a failed first load that IS the connection says so', (tester) async {
    _server.rels = _Rels.offline;
    final reported = await _open(tester);
    expect(find.text("Couldn't load your bookings"), findsOneWidget);
    expect(reported.map((f) => f.origin), ['BookingScreen._load']);
    expect(find.text(_net), findsOneWidget);
    expect(find.text(_other), findsNothing);
  });

  testWidgets('a failed coach switch is recorded under its own origin', (tester) async {
    _server.slotsBFail = true;
    final reported = await _open(tester);
    expect(reported, isEmpty);
    await tester.tap(find.textContaining('Blake').first);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your bookings"), findsOneWidget);
    expect(reported.map((f) => f.origin), ['BookingScreen._selectCoach'],
        reason: 'THE defect: catch (_) recorded nothing');
    expect(find.text(_other), findsOneWidget);
  });

  testWidgets('retry after a failed load reaches the slots (positive control)',
      (tester) async {
    _server.rels = _Rels.fail;
    final reported = await _open(tester);
    _server.rels = _Rels.two;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your bookings"), findsNothing);
    expect(find.textContaining('Avery'), findsWidgets);
    expect(find.textContaining('No Slots'), findsNothing);
    expect(reported.length, 1, reason: 'only the first failure');
  });

  testWidgets('negative control: no coach is "No Coach Selected Yet", unrecorded',
      (tester) async {
    _server.rels = _Rels.none;
    final reported = await _open(tester);
    expect(find.text('No Coach Selected Yet'), findsOneWidget);
    expect(find.text("Couldn't load your bookings"), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('negative control: a coach with no slots is "No Slots", unrecorded',
      (tester) async {
    _server.slotsA = 0;
    final reported = await _open(tester);
    expect(find.textContaining('No Slots from'), findsOneWidget);
    expect(find.text("Couldn't load your bookings"), findsNothing);
    expect(reported, isEmpty);
  });
}
