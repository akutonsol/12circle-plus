import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The workout list decided "Completed" from programSessionStatusProvider, which
// keeps the newest completed session for a workout id from ANY time. When a
// coach assigns the same program again (program_workouts ids are reused), every
// day finished in the earlier block showed "Completed · <old date>" with AGAIN,
// while Today and the Train hub -- which use program_schedule.dart's rule (done
// only if completed at or after this assignment) -- said it was not done.
//
// HOW TO SEE IT FAIL: on main the card shows AGAIN for a workout this
// assignment has not completed.

class _MemoryStore extends GotrueAsyncStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> getItem({required String key}) async => _m[key];
  @override
  Future<void> setItem({required String key, required String value}) async => _m[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _m.remove(key);
}

Workout _day({required bool completedInThisAssignment}) => Workout(
      id: 'pw-1', title: 'Lower Body', description: '', estimatedDuration: 45,
      difficulty: 'Intermediate', category: 'Strength', exercises: const [],
      isCompleted: completedInThisAssignment);

Future<void> _pump(WidgetTester t, Workout w) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(900, 2400);
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      assignedWorkoutsProvider.overrideWith((ref) async => [w]),
      // An older block of the same program finished this workout id.
      programSessionStatusProvider.overrideWith((ref) async => {
            'pw-1': {'status': 'completed', 'completed_at': '2026-01-05T10:00:00Z'},
          }),
      coachAdjustmentProvider.overrideWith((ref) async => null),
    ],
    child: const MaterialApp(home: WorkoutListScreen()),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// The list starts timers (animations); unmount and let them run out.
Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryStore(),
        detectSessionInUri: false,
      ),
      debug: false,
    );
  });

  testWidgets('a day finished only in an EARLIER assignment is not "Completed"', (t) async {
    await _pump(t, _day(completedInThisAssignment: false));
    expect(find.text('AGAIN'), findsNothing,
        reason: 'THE defect: the old block made this assignment\'s day read as done');
    expect(find.text('START'), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('a day finished in this assignment is Completed (positive control)', (t) async {
    await _pump(t, _day(completedInThisAssignment: true));
    expect(find.text('AGAIN'), findsOneWidget);
    await _unmount(t);
  });
}
