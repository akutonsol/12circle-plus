import 'dart:convert';

import 'package:circle_fitness/features/coach/data/coach_relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// P0-FL-1: with no signed-in user, cancelCoach returned CoachingEnd.now()
// ("Coaching ended. Your coach has been notified.") and requestCoach returned
// normally (the marketplace then said "Request sent!") -- both without writing
// anything. A write that did not happen is not a success: both now throw.
//
// HOW TO SEE IT FAIL: on origin/main both calls complete without an error.

class _SignedOut extends LocalStorage {
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<bool> hasAccessToken() async => false;
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
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add('${request.method} ${request.url.path}');
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
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
        localStorage: _SignedOut(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  setUp(server.calls.clear);

  test('the harness is signed out', () {
    expect(Supabase.instance.client.auth.currentUser, isNull);
  });

  test('cancelCoach without a signed-in user throws, and writes nothing',
      () async {
    await expectLater(
        CoachRelationshipService()
            .cancelCoach('coach-1', 'client_cancelled', null),
        throwsA(isA<StateError>()),
        reason:
            'THE defect: it returned CoachingEnd.now() -- "Coaching ended."');
    expect(server.calls, isEmpty);
  });

  test('requestCoach without a signed-in user throws, and writes nothing',
      () async {
    await expectLater(CoachRelationshipService().requestCoach('coach-1'),
        throwsA(isA<StateError>()),
        reason:
            'THE defect: it returned normally and the marketplace said "Request sent!"');
    expect(server.calls, isEmpty);
  });
}
