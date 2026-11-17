import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-1 (journeys 12 and 5): ending an UNPAID coaching relationship
// reported "Coaching ended. Your coach has been notified." whether or not the
// relationship changed. The update had no `.select()` and no row check, so a
// 0-row update (RLS refusal, already ended, wrong coach) still notified the
// coach -- "A client ended coaching" -- and returned CoachingEnd.now().
// approveRequest/declineRequest already refuse a 0-row answer (QAX-ERR-02);
// this holds cancelCoach to the same rule.
//
// HOW TO SEE IT FAIL: on origin/main the 0-row case returns normally and
// POSTs to /notifications.

const _uid = '00000000-0000-4000-8000-0000000e0dc1';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt() {
  final exp =
      DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
          1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({
        'sub': _uid,
        'role': 'authenticated',
        'exp': exp,
        'aud': 'authenticated'
      })}.'
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

/// No paid subscription; the relationship PATCH matches [patchRows] rows.
class _Server extends http.BaseClient {
  List<Map<String, Object?>> patchRows = [];
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    Object? body = [];
    var status = 200;
    if (path.endsWith('/coach_client_relationships') &&
        request.method == 'PATCH') {
      calls.add('PATCH relationship ${request.url.query}');
      body = patchRows;
    } else if (path.endsWith('/notifications') && request.method == 'POST') {
      calls.add('POST notifications');
      status = 201;
      body = null;
    } else if (request.headers['Accept']?.contains('vnd.pgrst.object') ??
        false) {
      body = {'first_name': 'Ana', 'last_name': 'Lee'};
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))), status,
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
    server.calls.clear();
    server.patchRows = [];
  });

  test('a 0-row update throws and the coach is NOT notified', () async {
    server.patchRows = []; // RLS refused / already ended / wrong coach
    await expectLater(
        CoachRelationshipService()
            .cancelCoach('coach-1', 'client_cancelled', null),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('nothing was changed'))),
        reason:
            'THE defect: nothing changed, and the client was told coaching ended');
    expect(server.calls.where((c) => c.startsWith('PATCH relationship')),
        hasLength(1));
    expect(server.calls, isNot(contains('POST notifications')),
        reason:
            'the coach was told "A client ended coaching" for a change that never happened');
  });

  test('the update asks for the changed rows back', () async {
    server.patchRows = [
      {'id': 'rel-1'},
    ];
    await CoachRelationshipService()
        .cancelCoach('coach-1', 'client_cancelled', null);
    final patch =
        server.calls.firstWhere((c) => c.startsWith('PATCH relationship'));
    expect(patch, contains('select=id'));
  });

  test(
      'a 1-row update ends coaching now and notifies the coach (positive control)',
      () async {
    server.patchRows = [
      {'id': 'rel-1'},
    ];
    final end = await CoachRelationshipService()
        .cancelCoach('coach-1', 'client_cancelled', null);
    expect(end.scheduled, isFalse);
    expect(end.describe(), 'Coaching ended. Your coach has been notified.');
    expect(server.calls, contains('POST notifications'));
  });
}
