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

// Finishing a workout raises the summary dialog on the ROOT navigator, because
// that is where `showDialog` puts it by default. `/active-workout` lives inside
// a ShellRoute, which has a navigator of its own. So the dialog's exit, calling
// `Navigator.pop` with the SCREEN's context, popped the shell's navigator: the
// workout screen left and the dialog stayed, undismissable, on top of Home.
//
// Pumping the dialog alone cannot show that, and neither can a plain MaterialApp,
// which has one navigator. These run the real screen inside a ShellRoute, and only
// the network is substituted (see ec03_intake_false_completion_e2e_test.dart).

/// Answers every request with an empty list, so nothing can reach a real service.
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

/// The Zone runs a repeating animation, so `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openZone(WidgetTester tester, {required bool viaPush}) async {
  // The dialog is taller than the default test surface. See
  // workout_feedback_honesty_test.dart for why this is not a phone width.
  await tester.binding.setSurfaceSize(const Size(700, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Text('home screen')),
          GoRoute(
            path: '/active-workout',
            builder: (_, __) => const ActiveWorkoutScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      selectedWorkoutProvider
          .overrideWith((ref) => WorkoutService().getSampleWorkouts().first),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  // The Today card goes to the Zone and the Resume banner pushes it. The shell's
  // navigator holds a different stack for each, so both are exercised.
  viaPush ? router.push('/active-workout') : router.go('/active-workout');
  await _settle(tester);
}

Future<void> _finishWorkout(WidgetTester tester) async {
  await tester.tap(find.textContaining('Finish Early'));
  await _settle(tester);
  expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      // Unroutable, so the harness cannot touch QA even if the client were bypassed.
      url: 'http://127.0.0.1:1',
      anonKey: 'test-anon-key',
      httpClient: _EmptyClient(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
      ),
      debug: false,
    );
  });

  for (final viaPush in [false, true]) {
    group(viaPush ? 'entered by push' : 'entered by go', () {
      testWidgets('Skip closes the summary and lands on Home', (tester) async {
        await _openZone(tester, viaPush: viaPush);
        await _finishWorkout(tester);

        await tester.tap(find.text('Skip'));
        await _settle(tester);

        expect(find.byType(WorkoutCompleteDialog), findsNothing);
        expect(find.text('home screen'), findsOneWidget);
      });
    });
  }
}
