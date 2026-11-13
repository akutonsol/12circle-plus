import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Finishing a workout saves it over several network round-trips, then resets
// the screen's sets, clears the selected workout ("Clearing the selection is
// what makes completion final") and re-reads every figure the workout changed.
// Its own comments say the screen can be left while the save is in flight —
// /active-workout sits inside the shell, so any tab does it.
//
// Every one of those steps ran through `ref` AFTER the awaits. Riverpod 2.6
// throws `StateError('Cannot use "ref" after the widget was disposed.')`
// (`flutter_riverpod-2.6.1/lib/src/consumer.dart:550`), so once the screen was
// gone the first `ref.read` threw and nothing after it happened:
//
//   * the finished workout stayed selected — re-entering the Zone then started
//     a fresh session for it, the resurrection `_leaveFinishedWorkout` exists
//     to prevent;
//   * no figure was re-read: streak, this week, score and the program stayed
//     as they were before the workout until the app restarted.
//
// The work now goes through the app's ProviderContainer, captured before the
// first await; it outlives the screen.

const _uid = '00000000-0000-4000-8000-0000000f1ea5';

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
/// Answers like the backend, and holds the session-complete request open until
/// the test releases it — the save in flight while the client leaves.
class _Backend extends http.BaseClient {
  Completer<void>? hold;

  http.StreamedResponse _reply(http.BaseRequest request, int status, Object body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request ? request.body : '';
    if (path.endsWith('/workout_logs') && request.method == 'POST') {
      return _reply(request, 201, []);
    }
    if (path.endsWith('/workout_sessions')) {
      if (request.method == 'POST') {
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
      if (request.method == 'PATCH' &&
          (body.contains('"completed"') || body.contains('"abandoned"')) &&
          hold != null) {
        await hold!.future;
      }
    }
    return _reply(request, 200, []);
  }
}

late _Backend _backend;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    _backend = _Backend();
    await Supabase.initialize(
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

  setUp(() => _backend.hold = null);

  late Map<String, int> reads;

  /// Opens the Zone on a sample workout, with the streak and this week's count
  /// counted so a re-read can be seen.
  Future<(ProviderContainer, GoRouter)> open(WidgetTester t) async {
    reads = {};
    Override counted(String name, FutureProvider<int> p) => p.overrideWith((ref) async {
          reads[name] = (reads[name] ?? 0) + 1;
          return 0;
        });
    final container = ProviderContainer(overrides: [
      selectedWorkoutProvider
          .overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
      counted('streak', currentStreakProvider),
      counted('this week', weeklyWorkoutCountProvider),
      counted('total', totalWorkoutCountProvider),
    ]);
    addTearDown(container.dispose);
    for (final p in [currentStreakProvider, weeklyWorkoutCountProvider, totalWorkoutCountProvider]) {
      container.listen<Object?>(p, (_, __) {});
    }

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
    await t.tap(find.textContaining('Warmed Up'));
    await _settle(t);
    return (container, router);
  }

  /// Taps Finish, leaves for Home while the save is held, then lets it finish.
  Future<ProviderContainer> finishThenLeave(WidgetTester t) async {
    final (container, router) = await open(t);
    _backend.hold = Completer<void>();
    await t.tap(find.textContaining('Finish Early'));
    await t.pump(const Duration(milliseconds: 100));

    router.go('/home');
    await _settle(t);
    expect(find.text('home screen'), findsOneWidget, reason: 'premise: the Zone is gone');

    _backend.hold!.complete();
    await _settle(t);
    return container;
  }

  testWidgets('a workout finished while leaving is no longer selected', (t) async {
    final container = await finishThenLeave(t);
    expect(t.takeException(), isNull,
        reason: 'THE defect: `ref` was used after the screen was disposed');
    expect(container.read(selectedWorkoutProvider), isNull,
        reason: 'a finished workout left selected is started again on re-entry');
  });

  testWidgets("a workout finished while leaving re-reads what it changed", (t) async {
    final container = await finishThenLeave(t);
    t.takeException();
    expect(reads['streak'], greaterThan(1), reason: 'the streak stayed stale');
    expect(reads['this week'], greaterThan(1));
    expect(reads['total'], greaterThan(1));
    expect(container.read(activeWorkoutProvider), isEmpty,
        reason: 'the finished sets were not reset');
  });

  testWidgets('a workout ended while leaving is no longer selected', (t) async {
    // "End session" → "End Workout" closes the session, then clears the
    // selection — through `ref`, after the await.
    final (container, router) = await open(t);
    _backend.hold = Completer<void>();
    await t.tap(find.bySemanticsLabel('End session'));
    await _settle(t);
    await t.tap(find.text('End Workout'));
    await t.pump(const Duration(milliseconds: 100));

    router.go('/home');
    await _settle(t);
    _backend.hold!.complete();
    await _settle(t);

    expect(t.takeException(), isNull);
    expect(container.read(selectedWorkoutProvider), isNull,
        reason: 'an ended workout left selected is started again on re-entry');
  });

  testWidgets('control: a workout finished on the screen is cleared and re-read', (t) async {
    final (container, _) = await open(t);
    await t.tap(find.textContaining('Finish Early'));
    await _settle(t);
    expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
    expect(reads['streak'], greaterThan(1));
    expect(container.read(activeWorkoutProvider), isEmpty);
  });
}
