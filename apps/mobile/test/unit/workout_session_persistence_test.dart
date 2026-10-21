// WKT-100 … WKT-108 — active workout session persistence & resume determinism.
//
// Covers the reported defect: after entering a set and leaving the Workout
// Zone, the Resume card could name a different workout than the one that was
// started, and stale in-progress sessions from earlier workouts were never
// closed.
//
// These drive the real production rules (`WorkoutSessionManager`) against an
// in-memory stand-in for the `workout_sessions` table, so the behaviour under
// test is the behaviour that ships.
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';

import '../support/in_memory_workout_session_store.dart';

const _uid = 'user-1';

// The two workouts from the reported workflow. Built directly rather than via
// WorkoutService so the tests don't depend on a Supabase client.
Workout _workout(String id, String title, {String exerciseName = 'Barbell Squat'}) =>
    Workout(
      id: id,
      title: title,
      description: 'desc',
      estimatedDuration: 45,
      difficulty: 'Intermediate',
      category: 'Strength',
      coachName: 'Coach Sarah',
      exercises: [
        WorkoutExercise(
          exercise: Exercise(
            id: 'ex-$id',
            name: exerciseName,
            category: 'Strength',
            muscleGroup: 'Legs',
            equipment: 'Barbell',
            difficulty: 'Intermediate',
            description: '',
            instructions: const ['Step one'],
          ),
          sets: [
            WorkoutSet(setNumber: 1, reps: 8, weightKg: 60, restSeconds: 90),
            WorkoutSet(setNumber: 2, reps: 8, weightKg: 62.5, restSeconds: 90),
          ],
        ),
      ],
    );

final _fullBody = _workout('1', 'Full Body Strength');

/// A two-set exercise the WKT-109 session-scoping tests address by identity.
WorkoutExercise _exerciseNamed(String exerciseId) => WorkoutExercise(
      exercise: Exercise(
        id: exerciseId,
        name: 'Exercise $exerciseId',
        category: 'Strength',
        muscleGroup: 'Legs',
        equipment: 'Barbell',
        difficulty: 'Intermediate',
        description: '',
        instructions: const [],
      ),
      sets: [
        for (var n = 1; n <= 2; n++)
          WorkoutSet(setNumber: n, reps: 8, weightKg: 60, restSeconds: 90),
      ],
    );

final _scoped = Workout(
  id: 'w-scoped',
  title: 'Scoped',
  description: '',
  estimatedDuration: 30,
  difficulty: 'Intermediate',
  category: 'Strength',
  exercises: [_exerciseNamed('ex-1'), _exerciseNamed('ex-2')],
);

WorkoutSet _scopedSet(String exerciseId, int n) => _scoped.exercises
    .firstWhere((e) => e.exercise.id == exerciseId)
    .sets
    .firstWhere((s) => s.setNumber == n);
final _lowerBody = _workout('2', 'Lower Body', exerciseName: 'Hip Thrust');

void main() {
  late InMemoryWorkoutSessionStore store;
  late WorkoutSessionManager manager;

  setUp(() {
    store = InMemoryWorkoutSessionStore();
    manager = WorkoutSessionManager(store);
  });

  // ── WKT-100 — the reported workflow, end to end ────────────────────────────
  group('WKT-100 start → log a set → leave → return → resume the same workout', () {
    test('the full reported journey stays on Full Body Strength', () async {
      // 1. Start Full Body Strength.
      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      expect(started.workoutTitle, 'Full Body Strength');
      expect(started.workoutId, '1');
      expect(started.id, isNotEmpty);

      // 2. Enter a set for the first exercise.
      store.logSet(started.id, 'ex-1', 1, reps: 8, weight: 60);

      // 3. Leave the Workout Zone (the screen is disposed; nothing else runs).
      await manager.saveElapsed(started.id, 95);

      // 4-5. Return to Train — Resume still names Full Body Strength...
      final resumable = await manager.activeSession(_uid);
      expect(resumable, isNotNull);
      expect(resumable!.id, started.id, reason: 'same session id');
      expect(resumable.workoutTitle, 'Full Body Strength');

      // ...and it resolves to that exact workout, not a title guess.
      final workout = manager.workoutForSession(resumable);
      expect(workout, isNotNull);
      expect(workout!.id, '1');
      expect(workout.title, 'Full Body Strength');

      // 6. The entered set is still attached to the session.
      final sets = store.setsFor(resumable.id);
      expect(sets, hasLength(1));
      expect(sets.single['set_number'], 1);
      expect(sets.single['reps'], 8);
      expect(sets.single['weight'], 60);
    });

    test('re-entering the Zone resumes rather than opening a second session',
        () async {
      final first = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(first.id, 'ex-1', 1);

      // Re-entering the Workout Zone runs startWorkout again.
      final second = await manager.startWorkout(userId: _uid, workout: _fullBody);

      expect(second.id, first.id, reason: 'the same session is resumed');
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
      expect(store.setsFor(first.id), hasLength(1),
          reason: 'entered sets survive re-entry');
    });

    test('elapsed time is restored on resume', () async {
      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      await manager.saveElapsed(started.id, 372);

      final resumed = await manager.activeSession(_uid);
      expect(resumed!.elapsedSeconds, 372);
    });
  });

  // ── WKT-101 — app restart ──────────────────────────────────────────────────
  group('WKT-101 relaunching the app restores the same incomplete session', () {
    test('same session id, workout and sets after a restart', () async {
      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(started.id, 'ex-1', 1, reps: 8, weight: 60);

      // 7. Restart: everything held in memory is gone; only stored rows remain.
      store.restart();
      final freshManager = WorkoutSessionManager(store);

      // 8. The same incomplete session comes back.
      final restored = await freshManager.activeSession(_uid);
      expect(restored, isNotNull);
      expect(restored!.id, started.id);
      expect(restored.workoutTitle, 'Full Body Strength');
      expect(freshManager.workoutForSession(restored)!.id, '1');
      expect(store.setsFor(restored.id), hasLength(1));
    });

    test('the workout is rebuilt from the session, with no list to match against',
        () async {
      // An AI-generated workout exists in no list at all — title matching, the
      // old resume strategy, could never have restored this.
      final oneOff = _workout('ai-2026-01-01', 'AI Session', exerciseName: 'Pull Up');
      final started = await manager.startWorkout(userId: _uid, workout: oneOff);

      store.restart();
      final restored = await WorkoutSessionManager(store).activeSession(_uid);
      expect(restored!.id, started.id);
      final workout = manager.workoutForSession(restored, candidates: const []);

      expect(workout, isNotNull);
      expect(workout!.id, 'ai-2026-01-01');
      expect(workout.title, 'AI Session');
      expect(workout.exercises.single.exercise.name, 'Pull Up');
      expect(workout.exercises.single.sets, hasLength(2));
    });
  });

  // ── WKT-102 — switching workouts ───────────────────────────────────────────
  group('WKT-102 starting a different workout switches the active session', () {
    test('the new workout becomes active and the old one does not replace it',
        () async {
      // 1-2. Full Body Strength, with a set entered.
      final full = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(full.id, 'ex-1', 1);

      // 9. Start a different workout.
      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      expect(lower.id, isNot(full.id), reason: 'a new session, not the old one');

      // 10. The new workout is what Resume now offers.
      final active = await manager.activeSession(_uid);
      expect(active!.id, lower.id);
      expect(active.workoutTitle, 'Lower Body');
      expect(manager.workoutForSession(active)!.id, '2');

      // 11. The old incomplete session is closed, not competing.
      expect(store.rowById(full.id)!['status'], WorkoutSessionStatus.abandoned);
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });

    test('switching back opens a fresh session rather than the abandoned one',
        () async {
      final full = await manager.startWorkout(userId: _uid, workout: _fullBody);
      await manager.startWorkout(userId: _uid, workout: _lowerBody);
      final backToFull =
          await manager.startWorkout(userId: _uid, workout: _fullBody);

      expect(backToFull.id, isNot(full.id));
      expect(backToFull.workoutTitle, 'Full Body Strength');
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });

    test('sets stay with the session they were entered against', () async {
      final full = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(full.id, 'ex-1', 1, reps: 8, weight: 60);

      final lower = await manager.startWorkout(userId: _uid, workout: _lowerBody);
      store.logSet(lower.id, 'ex-2', 1, reps: 12, weight: 80);

      expect(store.setsFor(full.id), hasLength(1));
      expect(store.setsFor(full.id).single['weight'], 60);
      expect(store.setsFor(lower.id), hasLength(1));
      expect(store.setsFor(lower.id).single['weight'], 80);
    });
  });

  // ── WKT-103 — completion ───────────────────────────────────────────────────
  group('WKT-103 completing a workout clears it from Resume but keeps history', () {
    test('Resume disappears and the session lands in history', () async {
      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      store.logSet(started.id, 'ex-1', 1);

      // 12. Complete the workout.
      await manager.completeSession(
        sessionId: started.id,
        durationSeconds: 1800,
        idleSeconds: 120,
        caloriesBurned: 240,
      );

      // 13. Resume is gone.
      expect(await manager.activeSession(_uid), isNull);
      expect(store.withStatus(WorkoutSessionStatus.inProgress), isEmpty);

      // 14. The completed workout remains, with its data intact.
      final completed = store.withStatus(WorkoutSessionStatus.completed);
      expect(completed, hasLength(1));
      expect(completed.single['id'], started.id);
      expect(completed.single['workout_title'], 'Full Body Strength');
      expect(completed.single['duration_seconds'], 1800);
      expect(completed.single['calories_burned'], 240);
      expect(store.setsFor(started.id), hasLength(1),
          reason: 'logged sets are history, not scratch state');
    });

    test('a completed session is never resurrected by starting a new workout',
        () async {
      final done = await manager.startWorkout(userId: _uid, workout: _fullBody);
      await manager.completeSession(
        sessionId: done.id,
        durationSeconds: 600,
        idleSeconds: 0,
        caloriesBurned: 80,
      );

      final next = await manager.startWorkout(userId: _uid, workout: _fullBody);
      expect(next.id, isNot(done.id));
      expect(store.rowById(done.id)!['status'], WorkoutSessionStatus.completed);
    });

    test('completing survives a restart as history', () async {
      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      await manager.completeSession(
        sessionId: started.id,
        durationSeconds: 900,
        idleSeconds: 0,
        caloriesBurned: 120,
      );

      store.restart();
      final fresh = WorkoutSessionManager(store);
      expect(await fresh.activeSession(_uid), isNull);
      expect(store.withStatus(WorkoutSessionStatus.completed), hasLength(1));
    });
  });

  // ── WKT-104 — the edge case that produced the bug ──────────────────────────
  group('WKT-104 an old incomplete workout exists before a new one is started', () {
    test('the pre-existing session does not become the newly started workout',
        () async {
      // A stale session from days ago — the "Started 1586h ago" case.
      final staleId = store.seedSession(
        userId: _uid,
        workoutId: '2',
        workoutTitle: 'Lower Body',
        startedAt: DateTime.utc(2025, 11, 1),
      );

      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);

      expect(started.id, isNot(staleId));
      expect(started.workoutTitle, 'Full Body Strength');

      final active = await manager.activeSession(_uid);
      expect(active!.id, started.id);
      expect(active.workoutTitle, 'Full Body Strength',
          reason: 'the stale Lower Body session must not surface as active');
      expect(store.rowById(staleId)!['status'], WorkoutSessionStatus.abandoned);
    });

    test('several stale sessions are all closed by one start', () async {
      final stale = [
        for (var i = 0; i < 4; i++)
          store.seedSession(
            userId: _uid,
            workoutId: 'old-$i',
            workoutTitle: 'Old Workout $i',
            startedAt: DateTime.utc(2025, 11, i + 1),
          ),
      ];

      await manager.startWorkout(userId: _uid, workout: _fullBody);

      for (final id in stale) {
        expect(store.rowById(id)!['status'], WorkoutSessionStatus.abandoned);
      }
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });

    test('reading the active session collapses pre-existing duplicates', () async {
      // Rows written before the fix: two in-progress sessions at once.
      final older = store.seedSession(
        userId: _uid, workoutId: '2', workoutTitle: 'Lower Body',
        startedAt: DateTime.utc(2025, 11, 1));
      final newer = store.seedSession(
        userId: _uid, workoutId: '1', workoutTitle: 'Full Body Strength',
        startedAt: DateTime.utc(2025, 12, 1));

      final active = await manager.activeSession(_uid);
      expect(active!.id, newer, reason: 'the most recent wins');

      // And the answer is stable from here on.
      expect(store.rowById(older)!['status'], WorkoutSessionStatus.abandoned);
      expect(await manager.activeSession(_uid), isNotNull);
      expect((await manager.activeSession(_uid))!.id, newer);
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });

    test('a stale session belonging to the same workout is resumed, not duplicated',
        () async {
      final staleId = store.seedSession(
        userId: _uid,
        workoutId: '1',
        workoutTitle: 'Full Body Strength',
        startedAt: DateTime.utc(2025, 11, 1),
      );
      store.logSet(staleId, 'ex-1', 1, reps: 8, weight: 60);

      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);

      expect(started.id, staleId, reason: 'resume, not a new session');
      expect(store.setsFor(staleId), hasLength(1));
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
    });
  });

  // ── WKT-105 — one active session, always ───────────────────────────────────
  group('WKT-105 there is never more than one active session', () {
    test('a long sequence of starts leaves exactly one in progress', () async {
      for (var i = 0; i < 6; i++) {
        await manager.startWorkout(
          userId: _uid,
          workout: i.isEven ? _fullBody : _lowerBody,
        );
        expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1));
      }
    });

    test('another user\'s active session is untouched', () async {
      final otherId = store.seedSession(
        userId: 'user-2', workoutId: '2', workoutTitle: 'Lower Body');

      await manager.startWorkout(userId: _uid, workout: _fullBody);

      expect(store.rowById(otherId)!['status'], WorkoutSessionStatus.inProgress);
      expect(await manager.activeSession('user-2'), isNotNull);
    });

    test('no active session when nothing has been started', () async {
      expect(await manager.activeSession(_uid), isNull);
    });
  });

  // ── WKT-106 — session ↔ workout identity ───────────────────────────────────
  group('WKT-106 a session identifies its workout by id, not by title', () {
    test('two workouts sharing a title are still distinct sessions', () async {
      final a = _workout('a', 'Full Body Strength');
      final b = _workout('b', 'Full Body Strength', exerciseName: 'Deadlift');

      final first = await manager.startWorkout(userId: _uid, workout: a);
      final second = await manager.startWorkout(userId: _uid, workout: b);

      expect(second.id, isNot(first.id));
      expect(second.workoutId, 'b');
      expect(manager.workoutForSession(second)!.exercises.single.exercise.name,
          'Deadlift');
    });

    test('a legacy session with no workout id still resolves by title', () async {
      final legacyId = store.seedSession(
        userId: _uid, workoutId: '', workoutTitle: 'Full Body Strength');

      final session = (await manager.activeSession(_uid))!;
      expect(session.id, legacyId);
      expect(session.workoutSnapshot, isNull);

      final workout =
          manager.workoutForSession(session, candidates: [_fullBody, _lowerBody]);
      expect(workout, isNotNull);
      expect(workout!.title, 'Full Body Strength');
    });

    test('a legacy session resumes rather than duplicating', () async {
      final legacyId = store.seedSession(
        userId: _uid, workoutId: '', workoutTitle: 'Full Body Strength');

      final started = await manager.startWorkout(userId: _uid, workout: _fullBody);
      expect(started.id, legacyId);
    });

    test('an unresolvable session reports null instead of a wrong workout',
        () async {
      store.seedSession(
        userId: _uid, workoutId: 'gone', workoutTitle: 'Deleted Workout');
      final session = (await manager.activeSession(_uid))!;

      expect(
        manager.workoutForSession(session, candidates: [_fullBody, _lowerBody]),
        isNull,
        reason: 'better no workout than the wrong one',
      );
    });
  });

  // ── WKT-107 — snapshot round trip ──────────────────────────────────────────
  group('WKT-107 the workout snapshot round-trips losslessly', () {
    test('structure, exercises and per-set values survive', () async {
      final original = _fullBody;
      final restored = programWorkoutToWorkout(workoutToSnapshot(original));

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.description, original.description);
      expect(restored.estimatedDuration, original.estimatedDuration);
      expect(restored.difficulty, original.difficulty);
      expect(restored.category, original.category);
      expect(restored.coachName, original.coachName);
      expect(restored.exercises, hasLength(original.exercises.length));

      final re = restored.exercises.single;
      final oe = original.exercises.single;
      expect(re.exercise.id, oe.exercise.id);
      expect(re.exercise.name, oe.exercise.name);
      expect(re.exercise.equipment, oe.exercise.equipment);
      expect(re.exercise.instructions, oe.exercise.instructions);
      expect(re.sets, hasLength(2));
      // Per-set variation is preserved — the uniform sets/reps/weight shape
      // alone would have flattened set 2 to set 1's weight.
      expect(re.sets[0].weightKg, 60);
      expect(re.sets[1].weightKg, 62.5);
      expect(re.sets[1].setNumber, 2);
      expect(re.sets[0].restSeconds, 90);
    });

    test('superset and circuit grouping survives', () {
      final grouped = Workout(
        id: '3', title: 'Circuit', description: '', estimatedDuration: 40,
        difficulty: 'Advanced', category: 'Strength',
        exercises: [
          WorkoutExercise(
            exercise: Exercise(id: 'e1', name: 'Pull Up', category: 'Strength',
              muscleGroup: 'Back', equipment: 'Bodyweight',
              difficulty: 'Intermediate', description: '', instructions: const []),
            sets: [WorkoutSet(setNumber: 1, reps: 8, weightKg: 0)],
            isSuperset: true, supersetGroup: 'A'),
          WorkoutExercise(
            exercise: Exercise(id: 'e2', name: 'Plank', category: 'Core',
              muscleGroup: 'Core', equipment: 'Bodyweight',
              difficulty: 'Beginner', description: '', instructions: const []),
            sets: [WorkoutSet(setNumber: 1, reps: 45, weightKg: 0)],
            isCircuit: true, circuitGroup: 'C1', circuitRounds: 3),
        ],
      );

      final restored = programWorkoutToWorkout(workoutToSnapshot(grouped));
      expect(restored.exercises[0].isSuperset, isTrue);
      expect(restored.exercises[0].supersetGroup, 'A');
      expect(restored.exercises[1].isCircuit, isTrue);
      expect(restored.exercises[1].circuitGroup, 'C1');
      expect(restored.exercises[1].circuitRounds, 3);
    });

    test('a program_workouts row without set_details still deserializes', () {
      final workout = programWorkoutToWorkout({
        'id': 'pw-1',
        'title': 'Coach Plan Day 1',
        'estimated_minutes': 55,
        'exercises': [
          {'exercise_id': 'e1', 'name': 'Squat', 'sets': 3, 'reps': 10,
           'weight': 40, 'rest_seconds': 60},
        ],
      });

      expect(workout.title, 'Coach Plan Day 1');
      expect(workout.estimatedDuration, 55);
      // Unchanged legacy defaults for rows that carry no difficulty/category.
      expect(workout.difficulty, 'Intermediate');
      expect(workout.category, 'Strength');
      expect(workout.coachName, 'Your Coach');
      expect(workout.exercises.single.sets, hasLength(3));
      expect(workout.exercises.single.sets.every((s) => s.reps == 10), isTrue);
      expect(workout.exercises.single.sets[2].setNumber, 3);
    });
  });

  // ── WKT-108 — the sample workouts the workflow uses ────────────────────────
  group('WKT-108 sample workouts carry the ids sessions key on', () {
    test('Full Body Strength has a stable, non-empty id', () {
      final samples = WorkoutService().getSampleWorkouts();
      final full = samples.firstWhere((w) => w.title == 'Full Body Strength');
      expect(full.id, isNotEmpty);
      expect(samples.map((w) => w.id).toSet(), hasLength(samples.length),
          reason: 'ids must be unique or sessions collide');
    });
  });

  // ── WKT-109 — in-memory set state is scoped to its session ────────────────
  group('WKT-109 entered sets belong to one session', () {
    test('re-entering the same session keeps what was typed', () {
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      final set = _scopedSet('ex-1', 1);
      notifier.setSetData(set, {'reps': 8, 'weight': 60.0}, exerciseInstanceId: 'ex-1');

      // Leaving and coming back to the same session.
      notifier.beginSession('session-1');

      expect(notifier.sessionId, 'session-1');
      expect(notifier.setData(set.id)['reps'], 8);
      expect(notifier.setData(set.id)['weight'], 60.0);
    });

    test('switching session clears the previous workout\'s sets', () {
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.setSetData(_scopedSet('ex-1', 1), {'reps': 8, 'weight': 60.0},
          exerciseInstanceId: 'ex-1');

      notifier.beginSession('session-2');

      expect(notifier.sessionId, 'session-2');
      expect(notifier.state, isEmpty,
          reason: "a new session must not inherit another workout's sets");
    });

    test('restored logs land under the current session only', () {
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.restoreFromLogs(_scoped, {
        'ex-1': [
          {'completed': true, 'set_number': 1, 'reps': 8, 'weight': 60.0},
        ],
      });
      expect(notifier.state.keys, [_scopedSet('ex-1', 1).id]);

      notifier.beginSession('session-2');
      expect(notifier.state, isEmpty);

      notifier.restoreFromLogs(_scoped, {
        'ex-2': [
          {'completed': true, 'set_number': 1, 'reps': 12, 'weight': 80.0},
        ],
      });
      expect(notifier.state.keys, [_scopedSet('ex-2', 1).id]);
    });

    test('completing resets the binding so the next start is clean', () {
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.setSetData(_scopedSet('ex-1', 1), {'reps': 8}, exerciseInstanceId: 'ex-1');

      notifier.reset();

      expect(notifier.sessionId, isNull);
      expect(notifier.state, isEmpty);

      // The same id can be started again after a reset and still clears.
      notifier.beginSession('session-1');
      expect(notifier.state, isEmpty);
    });
  });
}
