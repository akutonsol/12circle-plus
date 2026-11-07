import 'dart:convert';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_save.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Finishing a workout got three things wrong, all after the point the client
// believes it is done.
//
//   * `logWorkout` ended in `catch (_) {}`, so the `logWritten` guard around it
//     could never be false. A failed log with no session behind it raised the
//     celebration over a workout that was filed nowhere.
//   * Retrying after `completeSession` failed wrote `workout_logs` again, because
//     the retry repeats the whole path. One workout counted twice.
//   * Nothing re-read what the workout changed. Streak, totals, score and today's
//     workout are not autoDispose and nothing ticks them, so Home and the Train
//     hub showed the figures from before the workout until the app restarted.
//
// These drive the real screen, signed in, with only the network substituted.

const _uid = '00000000-0000-4000-8000-0000000f1a15';

String _b64(Map<String, Object?> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// gotrue reads `sub` and `exp` from the body without a round-trip while the
/// token is unexpired, and never verifies the signature on the client.
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

/// The database, as far as finishing a workout can see it.
class _Backend extends http.BaseClient {
  bool logFails = false;
  bool sessionStartFails = false;
  bool sessionCompleteFails = false;
  int logInserts = 0;

  void reset() {
    logFails = false;
    sessionStartFails = false;
    sessionCompleteFails = false;
    logInserts = 0;
  }

  /// postgrest reads the request back off the response to parse it.
  http.StreamedResponse _reply(http.BaseRequest request, int status, Object body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  http.StreamedResponse _fail(http.BaseRequest request) =>
      _reply(request, 500, {'message': 'simulated failure', 'code': 'XX000'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';

    if (path.endsWith('/workout_logs') && request.method == 'POST') {
      if (logFails) return _fail(request);
      logInserts++;
      return _reply(request, 201, []);
    }
    if (path.endsWith('/workout_sessions')) {
      if (request.method == 'POST') {
        if (sessionStartFails) return _fail(request);
        return _reply(request, 201, {
          'id': 'session-1',
          'user_id': _uid,
          'workout_id': 'w1',
          'workout_title': 'Workout',
          'workout_snapshot': <String, dynamic>{},
          'status': 'in_progress',
          'elapsed_seconds': 0,
          'started_at': '2026-11-06T10:00:00Z',
        });
      }
      if (request.method == 'PATCH' && body.contains('"completed"') && sessionCompleteFails) {
        return _fail(request);
      }
    }
    return _reply(request, 200, []);
  }
}

late _Backend _backend;

/// The Zone runs a repeating animation, so `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openZone(WidgetTester t, ProviderContainer container) async {
  await t.binding.setSurfaceSize(const Size(700, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/active-workout',
    routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Text('home screen')),
          GoRoute(path: '/active-workout', builder: (_, __) => const ActiveWorkoutScreen()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(t);
  // Signed in, the Zone opens with its warm-up question.
  await t.tap(find.textContaining('Warmed Up'));
  await _settle(t);
}

ProviderContainer _container([List<Override> overrides = const []]) {
  final container = ProviderContainer(overrides: [
    selectedWorkoutProvider
        .overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _tapFinish(WidgetTester t) async {
  await t.tap(find.textContaining('Finish Early'));
  await _settle(t);
}

void main() {
  setUpAll(() async {
    _backend = _Backend();
    await Supabase.initialize(
      // Unroutable, and every request is answered by the client below.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _backend,
      authOptions: FlutterAuthClientOptions(
        localStorage: _SeededSession(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  setUp(() => _backend.reset());

  group('a workout is only "saved" when it was filed', () {
    testWidgets('the log fails and there is no session: no celebration, and it says so',
        (t) async {
      _backend
        ..logFails = true
        ..sessionStartFails = true;
      await _openZone(t, _container());
      // "Could not start this workout." sits over the button until it times out.
      await t.pump(const Duration(seconds: 5));
      await _settle(t);

      await _tapFinish(t);

      expect(find.byType(WorkoutCompleteDialog), findsNothing,
          reason: 'nothing recorded this workout anywhere');
      expect(find.text(workoutSaveFailedMessage), findsOneWidget);
      expect(find.text(workoutSaveRetryLabel), findsOneWidget);
    });

    testWidgets('the log fails but the session completes: still not filed', (t) async {
      _backend.logFails = true;
      await _openZone(t, _container());

      await _tapFinish(t);

      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(find.text(workoutSaveFailedMessage), findsOneWidget);
    });

    testWidgets('retrying after the log failed files it and celebrates', (t) async {
      _backend.logFails = true;
      await _openZone(t, _container());
      await _tapFinish(t);

      _backend.logFails = false;
      await t.tap(find.text(workoutSaveRetryLabel));
      await _settle(t);

      expect(_backend.logInserts, 1);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
    });

    testWidgets('retrying after the session failed does not file the log twice',
        (t) async {
      _backend.sessionCompleteFails = true;
      await _openZone(t, _container());
      await _tapFinish(t);
      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(_backend.logInserts, 1);

      _backend.sessionCompleteFails = false;
      await t.tap(find.text(workoutSaveRetryLabel));
      await _settle(t);

      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      expect(_backend.logInserts, 1, reason: 'one workout, one row');
    });
  });

  group('what the workout changed is read again', () {
    late Map<String, int> reads;
    late List<Override> overrides;
    late List<ProviderListenable<Object?>> providers;

    void counted<T>(String name, FutureProvider<T> provider, T value) {
      overrides.add(provider.overrideWith((ref) async {
        reads[name] = (reads[name] ?? 0) + 1;
        return value;
      }));
      providers.add(provider);
    }

    setUp(() {
      reads = {};
      overrides = [];
      providers = [];
      counted('total workouts', totalWorkoutCountProvider, 0);
      counted('workouts this week', weeklyWorkoutCountProvider, 0);
      counted('streak', currentStreakProvider, 0);
      counted('history', workoutHistoryProvider, const <Map<String, dynamic>>[]);
      counted('completion rate', completionRateProvider, 0.0);
      counted('personal records', personalRecordsProvider, const <Map<String, dynamic>>[]);
      counted('logged exercises', loggedExerciseNamesProvider, const <String>[]);
      counted('program adherence', programAdherenceProvider, 0.0);
      counted('today\'s score', todayScoreProvider, const <String, dynamic>{});
      counted('week scores', weekScoresProvider, const <Map<String, dynamic>>[]);
      counted('score', myScoreProvider, null);
      counted('score events', recentScoreEventsProvider, const <Map<String, dynamic>>[]);
      counted('badges', myBadgeIdsProvider, const <String>{});
      counted('today\'s workout', todaysWorkoutProvider, null);
      counted('assigned program', myAssignedProgramProvider, null);
    });

    Future<ProviderContainer> open(WidgetTester t) async {
      final container = _container(overrides);
      for (final p in providers) {
        container.listen<Object?>(p, (_, __) {});
      }
      await _openZone(t, container);
      return container;
    }

    testWidgets('after a workout is filed, every figure is fetched again', (t) async {
      await open(t);
      final before = Map.of(reads);
      expect(before.length, providers.length, reason: 'all are being watched');

      await _tapFinish(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);

      for (final name in before.keys) {
        expect(reads[name], greaterThan(before[name]!), reason: '$name is stale');
      }
    });

    testWidgets('after a save fails, nothing is re-read', (t) async {
      _backend.logFails = true;
      await open(t);
      final before = Map.of(reads);

      await _tapFinish(t);

      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(reads, before);
    });
  });
}
