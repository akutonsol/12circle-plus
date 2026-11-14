import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Workout History showed a failed read as "No workouts yet".
//
// `getWorkoutHistory` and `getSessionSetLogs` ended `catch (_) { return []; }`.
// Offline, Workout History said "No workouts yet — complete your first workout
// to see it here" and an expanded session "No per-set data recorded"; the
// screen's own "Could not load history" / "Failed to load sets" could never
// show. Same class as A-G5 in this file, and #52/#60/#82.

const _uid = '00000000-0000-4000-8000-0000000000ea';

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

/// Every read fails with a 500 (a 503 is retried with a timer).
class _Down extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'message': 'upstream down'}))), 500,
          request: request, headers: {'content-type': 'application/json'});
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Down(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('a failed history read is a failure, not "no workouts yet"', () async {
    await expectLater(WorkoutService().getWorkoutHistory(), throwsA(anything),
        reason: 'THE defect: it answered [] for a read that failed');
  });

  test("a failed read of a session's sets is a failure, not \"no per-set data\"", () async {
    await expectLater(WorkoutService().getSessionSetLogs('s1'), throwsA(anything));
  });
}
