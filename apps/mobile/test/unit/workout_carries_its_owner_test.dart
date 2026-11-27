import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_workout_session_store.dart';

// P0-FL-59b · A-10: who a workout was read for travels with it, through every
// rebuild. What the entry points do with it is proven on the real screens in
// test/widget/workout_is_only_its_members_to_start_test.dart; this file names
// members that did not exist before, so it does not compile on 3f17006.

Workout _of(String? uid) {
  final w = Workout(
      id: 'w', title: 'W', description: 'd', estimatedDuration: 30, difficulty: 'x',
      category: 'c', coachId: 'coach', coachName: 'Coach', isCompleted: true,
      scheduledDate: DateTime(2026, 11, 25),
      exercises: WorkoutService().getSampleWorkouts().first.exercises);
  return uid == null ? w : w.asReadFor(uid);
}

WorkoutSessionRecord _session(String uid) => WorkoutSessionRecord(
    id: 's', userId: uid, workoutId: 'w', workoutTitle: 'W', status: 'in_progress',
    startedAt: DateTime(2026));

void main() {
  test("a workout read for A is A's; one read for nobody is anybody's", () {
    expect([_of('A').isFor('A'), _of('A').isFor('B'), _of('A').isFor(null)],
        [true, false, false]);
    expect([_of(null).isFor('A'), _of(null).isFor(null)], [true, true]);
    expect(WorkoutService().getSampleWorkouts().map((w) => w.readFor), everyElement(isNull));
  });

  test('tagging, and swapping an exercise, drop nothing', () {
    final w = _of('A');
    final swapped = w.replacingExerciseAt(
        0, w.exercises.first.replacedBy(w.exercises.first.exercise, instanceId: 'x'));
    expect(swapped.exercises.first.instanceId, 'x');
    for (final r in [w, swapped, swapped.asReadFor('A')]) {
      expect([
        r.readFor, r.id, r.title, r.description, r.estimatedDuration, r.difficulty, r.category,
        r.coachId, r.coachName, r.isCompleted, r.scheduledDate, r.exercises.length,
      ], [
        'A', 'w', 'W', 'd', 30, 'x', 'c', 'coach', 'Coach', true, DateTime(2026, 11, 25),
        w.exercises.length,
      ]);
    }
  });

  test("a session is never rebuilt from another member's program", () {
    final m = WorkoutSessionManager(InMemoryWorkoutSessionStore());
    expect(m.workoutForSession(_session('B'), candidates: [_of('A')]), isNull);
    expect(m.workoutForSession(_session('B'), candidates: [_of('A'), _of('B')])?.readFor, 'B');
    expect(m.workoutForSession(_session('B'), candidates: [_of(null)])?.readFor, 'B',
        reason: "matched for B's session, it is B's from then on");
  });

  test("a status is a status of its own member's workout", () {
    final statuses = {
      'w': {'status': 'in_progress', 'workout_id': 'w', 'user_id': 'A'}
    };
    expect(sessionStatusFor(statuses, _of('A')), isNotNull);
    expect(sessionStatusFor(statuses, _of(null)), isNotNull);
    expect(sessionStatusFor(statuses, _of('B')), isNull);
  });
}
