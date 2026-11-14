import 'dart:io';

import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';
import 'package:circle_fitness/features/workout/presentation/zone_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Resuming from the Workouts list, the Directory or Home lost swapped sets.
//
// Those entry points set the PROGRAM's workout and went to the Workout Zone,
// which resumed the open session with it and seated the logged sets against it.
// A client who had swapped Barbell Squat for Goblet Squat (new `swap-…` ids,
// kept in the session's snapshot) and logged three sets came back to Barbell
// Squat with nothing logged; the sets were missing from the finish totals too.
// The Train hub and the resume banner already bind the session's own workout.

Workout _w(String id, String title) => Workout(
      id: id, title: title, description: '', estimatedDuration: 45,
      difficulty: 'intermediate', category: 'strength', exercises: const []);

final _program = _w('w1', 'Leg Day');
final _snapshot = _w('w1', 'Leg Day (as the session holds it, with the swap)');

class _Manager extends Fake implements WorkoutSessionManager {
  @override
  Workout? workoutForSession(WorkoutSessionRecord session, {Iterable<Workout> candidates = const []}) =>
      _snapshot;
}

WorkoutSessionRecord _session(String workoutId) => WorkoutSessionRecord(
      id: 's1', userId: 'u1', workoutId: workoutId, workoutTitle: 'Leg Day',
      status: 'in_progress', startedAt: DateTime(2026, 11, 13, 9), elapsedSeconds: 600,
      currentExerciseId: '', currentSetId: '');

Future<Workout?> _select(WidgetTester tester, WorkoutSessionRecord? open) async {
  Workout? selected;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activeSessionProvider.overrideWith((ref) async => open),
      workoutSessionManagerProvider.overrideWithValue(_Manager()),
      assignedWorkoutsProvider.overrideWith((ref) async => [_program]),
    ],
    child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      selected = ref.watch(selectedWorkoutProvider);
      return TextButton(
          onPressed: () => selectWorkoutForZone(ref, _program), child: const Text('resume'));
    })),
  ));
  await tester.tap(find.text('resume'));
  await tester.pumpAndSettle();
  return selected;
}

void main() {
  testWidgets("resuming an open session lands on the session's own workout", (tester) async {
    final selected = await _select(tester, _session('w1'));
    expect(selected?.title, _snapshot.title,
        reason: "THE defect: the program's workout was used, so swapped sets had nowhere to go");
  });

  testWidgets('with no open session, the tapped workout is started', (tester) async {
    final selected = await _select(tester, null);
    expect(selected?.title, _program.title);
  });

  testWidgets("an open session for another workout does not hijack this one", (tester) async {
    final selected = await _select(tester, _session('other'));
    expect(selected?.title, _program.title);
  });

  test('guard: no resume entry point sets the program workout directly', () {
    // Source guard over the three entry points this fixes.
    for (final p in [
      'lib/features/workout/presentation/workout_list_screen.dart',
      'lib/features/dashboard/presentation/directory_screen.dart',
      'lib/features/home/presentation/home_screen.dart',
    ]) {
      final src = File(p).readAsStringSync();
      expect(RegExp(r"selectedWorkoutProvider\.notifier\)\.state = (workout|inProgress|w);\s*\n\s*context\.go\('/active-workout'\)")
          .hasMatch(src), isFalse, reason: p);
    }
  });
}
