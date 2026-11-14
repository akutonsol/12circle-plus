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


const _leaveTitle = 'Leave this workout?';


// "Leave For Now" left the rest countdown running.
//
// `restTimerProvider` is app-wide. Pause and End Workout stop it
// (`_dismissRest`); Leave For Now did not. A client who completed a set (90 s
// rest) and left came back hours later to the overtime alarm, "Rest over. Get
// moving.", −5 points and −5 more every 20 s, and the whole absence booked as
// rest overrun — for time they had said they were not training (FIT-002).

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('[]')),
        200,
        headers: {'content-type': 'application/json'},
      );
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  testWidgets('Leave For Now stops a running rest', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      selectedWorkoutProvider.overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/home', routes: [
      ShellRoute(builder: (_, __, child) => Scaffold(body: child), routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('home screen')),
        GoRoute(path: '/active-workout', builder: (_, __) => const ActiveWorkoutScreen()),
      ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pump();
    router.go('/active-workout');
    await _settle(tester);

    // A set was completed: its 90-second rest is running.
    container.read(restTimerProvider.notifier).state =
        RestTimerState(DateTime.now().add(const Duration(seconds: 90)), 90);

    await tester.tap(find.byIcon(Icons.close).first);
    await _settle(tester);
    expect(find.text(_leaveTitle), findsOneWidget);
    await tester.tap(find.text('Leave For Now'));
    await _settle(tester);

    expect(find.text('home screen'), findsOneWidget);
    expect(container.read(restTimerProvider), isNull,
        reason: 'THE defect: the rest kept running while the client was away');
  });
}
