import 'dart:convert';

import 'package:circle_fitness/features/classes/data/live_class_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Module 13 -- "full -> waitlisted; a cancellation hands the seat to the earliest
// waitlisted booking" -- ran in the client, where RLS defeats every step:
//   * the confirmed count reads class_bookings, of which a client sees only its
//     OWN rows, so it was 0 or 1 and a booking was never waitlisted;
//   * `classes.current_enrolled` and another user's booking are not
//     client-writable, so the enrolment sync and the promotion matched zero rows
//     -- and the promotion, for a caller who could see the waitlist, still told
//     that user "You're In!".
// Migration 188 moves all of it into the database. The client asks for a seat and
// believes the answer.
//
// The fake answers like PostgREST over that database: the booking comes back
// with the status the server decided, and a waitlisted booking of someone else
// is readable (as it is to the class's coach) so the old promotion path is
// exercised.
//
// HOW TO SEE IT FAIL: on main the first test gets 'confirmed' for a booking the
// server waitlisted, and the second sees writes to `classes`, to another user's
// booking and a "You're In!" notification.

const _uid = '00000000-0000-4000-8000-00000000c1a5';

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

class _Server extends http.BaseClient {
  /// What the database decides for a booking request.
  String decided = 'waitlisted';
  final List<String> writes = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final q = request.url.queryParameters;
    final table = path.split('/').last;
    Object? body = [];
    var status = 200;
    if (request.method != 'GET') {
      writes.add('${request.method} $table ${request.url.query}');
    }
    if (table == 'class_bookings' && request.method == 'POST') {
      status = 201;
      // `.single()` asks for one object (Accept: vnd.pgrst.object+json), as
      // PostgREST then returns it; otherwise a list.
      final one = (request.headers['Accept'] ?? request.headers['accept'] ?? '')
          .contains('vnd.pgrst.object');
      body = one ? {'status': decided} : [{'status': decided}];
    } else if (table == 'class_bookings' && request.method == 'GET') {
      // A waitlisted booking that is not ours (readable, e.g., to the class's coach).
      body = (q['status'] ?? '') == 'eq.waitlisted'
          ? [
              {'id': 'other-booking', 'user_id': 'someone-else'},
            ]
          : [];
    } else if (table == 'classes' && request.method == 'GET') {
      body = {'max_capacity': 20};
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

  setUp(() => server.writes.clear());

  test("booking returns the server's decision, waitlisted included", () async {
    server.decided = 'waitlisted';
    expect(await LiveClassService().bookClass('class-1'), 'waitlisted',
        reason: 'THE defect: the client counted only its own bookings and '
            'reported a full class as confirmed');
    server.decided = 'confirmed';
    expect(await LiveClassService().bookClass('class-1'), 'confirmed');
  });

  test('booking and cancelling write only the caller\'s own booking', () async {
    await LiveClassService().bookClass('class-1');
    await LiveClassService().cancelBooking('class-1');
    expect(server.writes.where((w) => !w.contains(' class_bookings ')), isEmpty,
        reason: 'writes to classes (current_enrolled) or notifications are the '
            'database\'s job; from a client they match zero rows or tell a '
            'waitlisted user they are in: ${server.writes}');
    expect(server.writes.where((w) => w.contains('other-booking')), isEmpty,
        reason: 'a client cannot promote another user\'s booking');
    expect(server.writes.where((w) => w.startsWith('PATCH')).single,
        contains('user_id=eq.$_uid'),
        reason: 'the cancel is scoped to the caller');
  });
}
