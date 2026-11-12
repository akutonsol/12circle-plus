import 'dart:convert';

import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:circle_fitness/features/coach/presentation/coach_availability_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Booking a call, and cancelling one from either side, writes the call and
// then tells the other party. The tell was inside the same `try` as the
// writes, so a failed notification after a SAVED booking or cancel was
// reported as a failure of the booking or cancel itself (N3's shape):
//
//   * "Could not book — please try again." for a call that WAS booked. The
//     screen did not re-read, so the slot was still offered, and a retry
//     booked the same slot a second time.
//   * "Could not cancel. Try again." for a call that WAS cancelled.
//
// The change is saved first; the notice to the other party is best-effort and
// reported, and the message names it only when it was sent.

const _uid = '00000000-0000-4000-8000-0000000b00c1';
const _coachId = 'coach-a';

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

/// Answers like PostgREST over one coach, one open slot and the client's
/// calls. A booking saves the call and takes the slot; a cancel frees both.
class _Server extends http.BaseClient {
  bool callWriteFails = false;
  bool notificationFails = false;
  final writes = <String>[];
  late String slotTime;
  bool slotOpen = true;
  final calls = <Map<String, Object?>>[];

  void reset() {
    callWriteFails = false;
    notificationFails = false;
    writes.clear();
    slotTime = DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String();
    slotOpen = true;
    calls.clear();
  }

  Map<String, Object?> get _slot => {
        'id': 'slot-1',
        'coach_id': _coachId,
        'slot_time': slotTime,
        'duration_minutes': 30,
        'type': 'check_in',
        'is_booked': !slotOpen,
      };

  Map<String, Object?> get _other => {
        ..._slot,
        'id': 'slot-2',
        'slot_time': DateTime.parse(slotTime).add(const Duration(days: 1)).toIso8601String(),
        'is_booked': false,
      };

  void bookedCall() {
    slotOpen = false;
    calls.add({
      'id': 'call-1',
      'client_id': _uid,
      'coach_id': _coachId,
      'availability_slot_id': 'slot-1',
      'scheduled_at': slotTime,
      'duration_minutes': 30,
      'call_type': 'check_in',
      'status': 'scheduled',
      'client': {'first_name': 'Jo', 'last_name': 'Park', 'avatar_url': null},
    });
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final m = request.method;
    if (m != 'GET') writes.add('$m $path');
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;

    if (path.endsWith('/notifications')) {
      return notificationFails
          ? _json({'message': 'notification insert failed'}, 500, request)
          : _json([], 201, request);
    }
    if (path.endsWith('/coaching_calls')) {
      if (m == 'GET') return _json(calls.where((c) => c['status'] == 'scheduled').toList(), 200, request);
      if (callWriteFails) return _json({'message': 'offline'}, 503, request);
      if (m == 'POST') bookedCall();
      if (m == 'PATCH') {
        for (final c in calls) {
          c['status'] = 'cancelled';
        }
      }
      return _json([], m == 'POST' ? 201 : 200, request);
    }
    if (path.endsWith('/coach_availability')) {
      // A second slot stays open, so the screen stays on its slot list (with
      // none open it shows a different state, which this file is not about).
      if (m == 'GET') return _json([if (slotOpen) _slot, _other], 200, request);
      if (m == 'PATCH' && calls.every((c) => c['status'] != 'scheduled')) slotOpen = true;
      return _json([], 200, request);
    }
    if (path.endsWith('/coach_client_relationships')) {
      return _json([
        {'coach_id': _coachId, 'status': 'active', 'pending_at': null, 'activated_at': '2026-10-01T00:00:00Z'},
      ], 200, request);
    }
    if (path.endsWith('/public_profiles')) {
      return _json([
        {'id': _coachId, 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
      ], 200, request);
    }
    if (path.endsWith('/user_profiles')) {
      return _json(single ? {'first_name': 'Jo', 'last_name': 'Park'} : [], 200, request);
    }
    // award_points and anything else: an empty success.
    return _json(single ? {} : [], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = _Server()..reset();
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

  setUp(() => server.reset());

  // Tall enough that every card is built; the lists are lazy.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  int posts(String table) =>
      server.writes.where((w) => w == 'POST /rest/v1/$table').length;

  group('the client books a call', () {
    Future<void> book(WidgetTester tester) async {
      tall(tester);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: BookingScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Book'), findsNWidgets(2), reason: 'premise: two open slots');
      await tester.tap(find.text('Book').first);
      await tester.pumpAndSettle();
    }

    testWidgets('a failed notice to the coach does not undo a saved booking',
        (tester) async {
      server.notificationFails = true;
      await book(tester);

      expect(posts('coaching_calls'), 1, reason: 'premise: the call was saved');
      expect(find.text('Could not book — please try again.'), findsNothing,
          reason: 'THE defect: the call IS booked; only the notice failed');
      expect(find.text('Call booked!'), findsOneWidget);
      expect(find.text('Call booked! Your coach has been notified.'), findsNothing,
          reason: 'the coach was not notified');
    });

    testWidgets('the booked slot is no longer offered, so it cannot be booked twice',
        (tester) async {
      server.notificationFails = true;
      await book(tester);

      expect(find.text('Book'), findsOneWidget,
          reason: 'the screen kept offering a slot it had just booked; a '
              'retry inserted a second call for it');
      expect(find.text('Confirmed'), findsOneWidget);
      expect(posts('coaching_calls'), 1);
    });

    testWidgets('control: a booking that notified the coach says so', (tester) async {
      await book(tester);
      expect(find.text('Call booked! Your coach has been notified.'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('control: a booking that failed says so, and tells nobody',
        (tester) async {
      server.callWriteFails = true;
      await book(tester);
      expect(find.text('Could not book — please try again.'), findsOneWidget);
      expect(posts('notifications'), 0);
    });
  });

  group('the client cancels a call', () {
    Future<void> cancel(WidgetTester tester) async {
      server.bookedCall();
      tall(tester);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: BookingScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsOneWidget, reason: 'premise: one booked call');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel session'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed notice to the coach does not undo a saved cancel',
        (tester) async {
      server.notificationFails = true;
      await cancel(tester);

      expect(server.writes, contains('PATCH /rest/v1/coaching_calls'));
      expect(find.text('Could not cancel. Try again.'), findsNothing,
          reason: 'THE defect: the call IS cancelled; only the notice failed');
      expect(find.text('Session cancelled.'), findsOneWidget);
      expect(find.text('Confirmed'), findsNothing,
          reason: 'the cancelled call is no longer shown as booked');
    });

    testWidgets('control: a cancel that failed says so', (tester) async {
      server.callWriteFails = true;
      await cancel(tester);
      expect(find.text('Could not cancel. Try again.'), findsOneWidget);
      expect(posts('notifications'), 0);
    });
  });

  group('the coach cancels a session', () {
    Future<void> cancel(WidgetTester tester) async {
      server.bookedCall();
      tall(tester);
      await tester.pumpWidget(const MaterialApp(home: CoachAvailabilityScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Jo Park'), findsOneWidget, reason: 'premise: one booked session');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel session'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed notice to the client does not undo a saved cancel',
        (tester) async {
      server.notificationFails = true;
      await cancel(tester);

      expect(server.writes, contains('PATCH /rest/v1/coaching_calls'));
      expect(find.text('Could not cancel. Try again.'), findsNothing,
          reason: 'THE defect: the session IS cancelled; only the notice failed');
      expect(find.text('Session cancelled.'), findsOneWidget);
      expect(find.text('Session cancelled — client notified.'), findsNothing,
          reason: 'the client was not notified');
      expect(find.text('Jo Park'), findsNothing);
    });

    testWidgets('control: a cancel that notified the client says so', (tester) async {
      await cancel(tester);
      expect(find.text('Session cancelled — client notified.'), findsOneWidget);
    });

    testWidgets('control: a cancel that failed says so', (tester) async {
      server.callWriteFails = true;
      await cancel(tester);
      expect(find.text('Could not cancel. Try again.'), findsOneWidget);
      expect(posts('notifications'), 0);
    });
  });
}
