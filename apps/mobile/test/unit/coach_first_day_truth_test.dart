import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_program_service.dart';
import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// A client's first day is a chain of coach actions — the request, the approval,
// then the first program, nutrition targets and habits — and each one reported
// something other than what happened:
//
//   * N3: every one wrote its change, then a notification, in one `await`
//     chain. A failed notification threw AFTER the change was saved, so the
//     coach (or the requesting client) read "Couldn't assign…" for something
//     that was assigned, and was sent back to do it again.
//   * N4: approving or declining a request updated nothing when the row was
//     filtered out (RLS, or already answered), and said "Client accepted!".
//
// The rules are the repository's own: a save stays a save when only what
// follows it fails (C5), and a write that matched no row is not a success
// (QAX-ERR-02).

const _uid = '00000000-0000-4000-8000-0000000010d4';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// See workout_finish_truth's sibling harnesses: the token is read, never verified.
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

/// Answers like PostgREST. `notifications` inserts fail; a relationship
/// update matches [relationshipRows] rows.
class _Server extends http.BaseClient {
  int relationshipRows = 1;
  final writes = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET') writes.add('${request.method} $path');
    if (path.endsWith('/notifications')) {
      return _json({'message': 'notification insert failed'}, 500, request);
    }
    if (request.method == 'PATCH' && path.endsWith('/coach_client_relationships')) {
      return _json([
        for (var i = 0; i < relationshipRows; i++) {'id': 'rel-$i'},
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
    server.writes.clear();
    server.relationshipRows = 1;
  });

  group('N3 a saved change stays saved when only its notification fails', () {
    test('assigning a program', () async {
      await CoachProgramService().assignProgram('program-1', 'client-1');
      expect(server.writes, contains('POST /rest/v1/workout_program_assignments'));
    });

    test('setting nutrition targets', () async {
      await CoachProgramService().assignNutritionPlan('client-1',
          calories: 2000, protein: 150, carbs: 200, fat: 60);
      expect(server.writes, contains('POST /rest/v1/rpc/assign_nutrition_plan'));
    });

    test('assigning habits', () async {
      await CoachProgramService().assignHabits('client-1', [
        {'name': 'Water', 'target_value': 8},
      ]);
      expect(server.writes, contains('POST /rest/v1/client_habits'));
    });

    test('a client requesting a coach', () async {
      await CoachRelationshipService().requestCoach('coach-1');
      expect(server.writes, contains('POST /rest/v1/coach_client_relationships'));
    });

    test('approving a request', () async {
      await CoachRelationshipService().approveRequest('rel-1', 'client-1');
    });

    test('declining a request', () async {
      await CoachRelationshipService().declineRequest('rel-1', 'client-1');
    });
  });

  group('N4 answering a request that matched no row is not a success', () {
    test('approve', () async {
      server.relationshipRows = 0;
      await expectLater(
          CoachRelationshipService().approveRequest('rel-gone', 'client-1'),
          throwsA(anything),
          reason: '"Client accepted!" over a request nothing accepted');
      expect(server.writes.where((w) => w.contains('notifications')), isEmpty,
          reason: 'and the client is not told they were accepted');
    });

    test('decline', () async {
      server.relationshipRows = 0;
      await expectLater(
          CoachRelationshipService().declineRequest('rel-gone', 'client-1'),
          throwsA(anything));
      expect(server.writes.where((w) => w.contains('notifications')), isEmpty);
    });
  });
}
