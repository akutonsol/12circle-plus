import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// The workout clock was saved only on pause, Leave For Now and dispose.
//
// A browser refresh or an app kill runs none of them, so 40 minutes into a
// session with no pause the clock restored at 0:00, and the finished workout
// recorded only the time after the refresh (duration, minutes, calories). The
// Zone now checkpoints elapsed time every 30 s of training.

const _uid = '00000000-0000-4000-8000-0000000000ec';

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

class _Offline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final single = request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(single ? null : []))), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

class _Store extends Fake implements WorkoutSessionStore {
  final saved = <int>[];
  WorkoutSessionRecord? open;

  @override
  Future<List<WorkoutSessionRecord>> inProgressSessions(String userId) async =>
      open == null ? [] : [open!];

  @override
  Future<WorkoutSessionRecord> createSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    required Map<String, dynamic> workoutSnapshot,
  }) async =>
      open = WorkoutSessionRecord(
          id: 's1', userId: userId, workoutId: workoutId, workoutTitle: workoutTitle,
          status: 'in_progress', startedAt: DateTime.now(), elapsedSeconds: 0,
          workoutSnapshot: workoutSnapshot, currentExerciseId: '', currentSetId: '');

  @override
  Future<void> abandonSessions(Iterable<String> sessionIds) async {}
  @override
  Future<void> saveElapsed(String sessionId, int elapsedSeconds) async => saved.add(elapsedSeconds);
  @override
  Future<void> acknowledgeWarmup(String sessionId) async {}
  @override
  Future<void> saveSnapshot(String sessionId, Map<String, dynamic> snapshot) async {}
  @override
  Future<void> saveCursor(String sessionId, String exerciseId, String setId) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _Offline(),
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets('the clock is saved while training, not only on leaving', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedWorkoutProvider.overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
        workoutSessionStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: ActiveWorkoutScreen()),
    ));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(store.open, isNotNull, reason: 'the Zone opened a session');
    // Nothing has been paused, left or closed: a refresh now would lose the clock.
    expect(store.saved.where((s) => s >= 30), isNotEmpty,
        reason: 'THE defect: 40 s in, no elapsed time had been saved');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
