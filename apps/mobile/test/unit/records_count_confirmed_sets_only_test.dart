import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Personal records and progress counted sets the client never confirmed.
//
// Editing a set writes a `workout_set_logs` row with `completed: false`
// (migration 104: a row "merely typed into"), and an empty weight is filled
// with the prescribed load. The PR, progression, volume and exercise-list reads
// did not filter on `completed`, so a 140 kg deadlift typed into and never done
// became the client's "Deadlift 140.0 kg" record, was plotted on Strength
// Progress, and counted toward the in-progress percentage.

const _uid = '00000000-0000-4000-8000-0000000000e9';

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

/// Answers like PostgREST, applying `completed=eq.true` when the read asks.
class _Server extends http.BaseClient {
  final rows = <Map<String, Object?>>[
    {'exercise_name': 'Deadlift', 'weight_kg': 100, 'reps': 5, 'completed': true,
     'logged_at': '2026-11-10T10:00:00+00:00'},
    {'exercise_name': 'Deadlift', 'weight_kg': 140, 'reps': 5, 'completed': false,
     'logged_at': '2026-11-12T10:00:00+00:00'},
  ];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final q = request.url.queryParameters;
    var out = rows;
    if (q['completed'] == 'eq.true') out = rows.where((r) => r['completed'] == true).toList();
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(out))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Server(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  test('a set never confirmed is not a personal record', () async {
    final prs = await WorkoutService().getPersonalRecords();
    expect(prs.single['weight_kg'], 100.0,
        reason: 'THE defect: an unconfirmed 140 kg set became the record');
  });

  test('volume counts confirmed sets only', () async {
    expect(await WorkoutService().getTotalVolumeLifted(), 500.0);
  });

  test("progression plots confirmed sets only", () async {
    final points = await WorkoutService().getExerciseProgression('Deadlift');
    expect(points.map((p) => p['max_weight']), everyElement(100.0));
  });
}
