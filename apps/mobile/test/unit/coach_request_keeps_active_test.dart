import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A coaching request must never demote the client's current coach.
//
// `requestCoach` upserts `{status: 'pending'}` on `(client_id, coach_id)`. Over
// an ACTIVE row that is an update from active to pending, and nothing stops it:
// 113's update policy lets a client amend their own row, its integrity trigger
// guards the parties and provenance but not the status, and 151 only audits.
// The coach then loses the client from their roster and `is_active_coach_of`,
// the client loses coach-guided access, and the screen says "Request sent!".
//
// The marketplace offers "Request to Connect" on every card until its status
// read arrives (and for good if that read fails), so the client's own coach
// was one tap away from being demoted.

const _uid = '00000000-0000-4000-8000-00000000c0a1';

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

/// Answers like PostgREST. The client's row with the coach has [existing]
/// status (null: no row).
class _Server extends http.BaseClient {
  String? existing;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET') {
      writes.add('${request.method} $path');
      return _json([], 201, request);
    }
    if (path.endsWith('/coach_client_relationships')) {
      return _json([
        if (existing != null) {'status': existing},
      ], 200, request);
    }
    return _json([], 200, request);
  }

  http.StreamedResponse _json(Object body, int status, http.BaseRequest r) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: r, headers: {'content-type': 'application/json'});
}

void main() {
  late _Server server;
  const relationships = 'POST /rest/v1/coach_client_relationships';

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

  setUp(() => server.writes.clear());

  test('requesting the coach you already have writes nothing', () async {
    server.existing = 'active';

    Object? error;
    try {
      await CoachRelationshipService().requestCoach('coach-1');
    } catch (e) {
      error = e;
    }
    expect(server.writes, isNot(contains(relationships)),
        reason: 'an upsert here moves the active row back to pending');
    expect(server.writes, isEmpty, reason: 'nor is the coach told of a request');
    expect(error, isA<StateError>(),
        reason: 'the screen must not say "Request sent!"');
  });

  group('every other request still goes through', () {
    for (final status in [null, 'pending', 'cancelled', 'declined']) {
      test('existing row: ${status ?? 'none'}', () async {
        server.existing = status;
        await CoachRelationshipService().requestCoach('coach-1');
        expect(server.writes, contains(relationships));
      });
    }
  });
}
