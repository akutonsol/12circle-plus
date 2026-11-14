import 'dart:convert';

import 'package:circle_fitness/features/booking/presentation/booking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Booking a coaching call wrote twice: INSERT coaching_calls, then
// `UPDATE coach_availability SET is_booked = true`. A client cannot write
// coach_availability (only the coach's policies allow it), so the second write
// matched zero rows: the slot was never marked booked, stayed on offer, and the
// next client booked it again. Migration 187 moves that into the database, which
// marks the slot itself and refuses a taken slot with 23505.
//
// The screen's side of it:
//   * book with ONE write -- no client write to coach_availability;
//   * a 23505 means the time was just taken: say so and re-read the slots,
//     instead of "Could not book — please try again." over a list that still
//     offers the taken time.
//
// HOW TO SEE IT FAIL: on main both tests fail -- the PATCH is sent, and the
// refusal reads as a generic failure with no re-read.

const _uid = '00000000-0000-4000-8000-00000000b00c';

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

/// One active coach with one free slot. `slotTaken` makes the call INSERT answer
/// the way Postgres does when the slot already holds a live call.
class _Server extends http.BaseClient {
  bool slotTaken = false;
  int slotReads = 0;
  final List<String> availabilityWrites = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/coach_client_relationships')) {
      body = [
        {'coach_id': 'coach-a', 'status': 'active', 'pending_at': null,
         'activated_at': '2026-10-01T00:00:00Z'},
      ];
    } else if (path.endsWith('/public_profiles')) {
      body = [
        {'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone', 'avatar_url': null,
         'coach_title': null, 'coach_bio': null, 'specialties': null},
      ];
    } else if (path.endsWith('/coach_availability')) {
      if (request.method == 'GET') {
        slotReads++;
        body = [
          {'id': 'slot-1', 'coach_id': 'coach-a', 'is_booked': false, 'type': 'check_in',
           'duration_minutes': 30,
           'slot_time': DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String()},
        ];
      } else {
        availabilityWrites.add('${request.method} ${request.url.query}');
      }
    } else if (path.endsWith('/coaching_calls') && request.method == 'POST') {
      if (slotTaken) {
        status = 409;
        body = {'code': '23505', 'details': null, 'hint': null,
                'message': 'that time has already been booked'};
      } else {
        status = 201;
        body = null;
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  final server = _Server();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: server,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(() {
    server.slotTaken = false;
    server.slotReads = 0;
    server.availabilityWrites.clear();
  });

  Future<void> bookTheSlot(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: BookingScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Book').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('booking is one write: the client never writes coach_availability',
      (tester) async {
    await bookTheSlot(tester);
    expect(tester.takeException(), isNull);
    expect(server.availabilityWrites, isEmpty,
        reason: 'THE defect: the client PATCHed is_booked, which RLS turns into a '
            'zero-row no-op -- the slot was never marked booked');
  });

  testWidgets('a slot someone has just taken is said, and the slots are re-read',
      (tester) async {
    server.slotTaken = true;
    await bookTheSlot(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('just taken'), findsOneWidget,
        reason: 'a taken slot read as "Could not book — please try again."');
    expect(server.slotReads, greaterThanOrEqualTo(2),
        reason: 'the list still offered the taken time');
  });

  test('only 23505 is a taken slot', () {
    expect(slotWasTaken(const PostgrestException(message: 'x', code: '23505')), isTrue);
    expect(slotWasTaken(const PostgrestException(message: 'x', code: '42501')), isFalse);
    expect(slotWasTaken(Exception('network')), isFalse);
  });
}
