// WKT-112 (QA-CL-003 / QA-CL-004) — active workout restoration after a refresh.
//
// Reported: a client mid-workout who refreshed the browser was shown the
// warm-up popup and then "No workout selected", and had to walk back through
// Browse Workouts → Train → pick Lower Body to reach a session that was still
// in progress the whole time. In-memory state does not survive a reload, and
// the Workout Zone read its absence as "there is no workout".
//
// These drive the production restore path — `WorkoutSessionRestorer` over the
// real `WorkoutSessionManager` — against an in-memory stand-in for the
// `workout_sessions` / `workout_set_logs` tables. A browser refresh is modelled
// the way it actually behaves: every object the app held is discarded and
// rebuilt, while stored rows remain.
//
// Cross-defect (QA-CL-002): restoration must also be order-authoritative, so
// the sets and exercises that come back are the ones that went in, in the same
// order, whatever order the rows arrive in.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_restoration.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';

import '../support/in_memory_workout_session_store.dart';

const _uid = 'user-1';

// ── The workout from the QA acceptance test ──────────────────────────────────

Exercise _exercise(String id, String name) => Exercise(
      id: id,
      name: name,
      category: 'Strength',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      difficulty: 'Intermediate',
      description: '',
      instructions: const ['Step one'],
    );

WorkoutExercise _threeSets(String id, String name, {double from = 60}) =>
    WorkoutExercise(
      exercise: _exercise(id, name),
      sets: [
        for (var i = 1; i <= 3; i++)
          WorkoutSet(setNumber: i, reps: 10, weightKg: from + i, restSeconds: 90),
      ],
    );

/// Lower Body: Back Squat, then Calf Raise. Exercise order matters — the client
/// stopped part-way through the *second* exercise.
Workout _lowerBody() => Workout(
      id: 'w-lower',
      title: 'Lower Body',
      description: 'Posterior chain and calves',
      estimatedDuration: 50,
      difficulty: 'Intermediate',
      category: 'Strength',
      coachName: 'Coach Sarah',
      exercises: [
        _threeSets('ex-squat', 'Back Squat', from: 100),
        _threeSets('ex-calf', 'Calf Raise', from: 40),
      ],
    );

final _upperBody = Workout(
  id: 'w-upper',
  title: 'Upper Body',
  description: '',
  estimatedDuration: 40,
  difficulty: 'Intermediate',
  category: 'Strength',
  exercises: [_threeSets('ex-bench', 'Bench Press', from: 70)],
);

/// The two Calf Raise sets the client confirmed, each uniquely identifiable so
/// a value landing on the wrong set is visible rather than plausible.
const _calfSet1 = {'weight': 42.5, 'reps': 12, 'rpe': 7.0, 'notes': 'felt easy'};
const _calfSet2 = {'weight': 47.5, 'reps': 10, 'rpe': 8.5, 'notes': 'slow eccentric'};

/// The identity of set [n] of [exerciseId], as the workout definition assigns
/// it. Restored state is keyed by this, so every assertion below names a set
/// rather than a slot.
String _setId(String exerciseId, int n) => WorkoutSet.mintId(exerciseId, n);

/// The restored state of one named set, or an empty map when nothing was
/// recorded against it.
Map<String, dynamic> _state(RestoredWorkoutSession r, String exerciseId, int n) =>
    r.setState[_setId(exerciseId, n)] ?? const {};

/// A store that fails its next session read, for the "restore could not
/// complete" path. Everything else delegates, so a retry succeeds.
class _FlakyStore implements WorkoutSessionStore {
  final InMemoryWorkoutSessionStore inner;
  bool failNextRead = true;
  _FlakyStore(this.inner);

  @override
  Future<List<WorkoutSessionRecord>> inProgressSessions(String userId) async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('network down');
    }
    return inner.inProgressSessions(userId);
  }

  @override
  Future<WorkoutSessionRecord> createSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    required Map<String, dynamic> workoutSnapshot,
  }) =>
      inner.createSession(
        userId: userId,
        workoutId: workoutId,
        workoutTitle: workoutTitle,
        workoutSnapshot: workoutSnapshot,
      );

  @override
  Future<void> abandonSessions(Iterable<String> ids) => inner.abandonSessions(ids);

  @override
  Future<void> completeSession({
    required String sessionId,
    required int durationSeconds,
    required int idleSeconds,
    required int caloriesBurned,
  }) =>
      inner.completeSession(
        sessionId: sessionId,
        durationSeconds: durationSeconds,
        idleSeconds: idleSeconds,
        caloriesBurned: caloriesBurned,
      );

  @override
  Future<void> saveElapsed(String id, int seconds) => inner.saveElapsed(id, seconds);

  @override
  Future<void> acknowledgeWarmup(String id) => inner.acknowledgeWarmup(id);

  @override
  Future<void> saveSnapshot(String id, Map<String, dynamic> snapshot) =>
      inner.saveSnapshot(id, snapshot);

  @override
  Future<void> saveCursor(String id, String exerciseId, String setId) =>
      inner.saveCursor(id, exerciseId, setId);
}

void main() {
  late InMemoryWorkoutSessionStore store;

  /// The app as it exists right now. Calling this again models a browser
  /// refresh: brand-new manager and restorer (nothing survives in RAM) reading
  /// the same stored rows.
  WorkoutSessionRestorer afterRefresh({
    SetLogLoader? loadSetLogs,
    WorkoutCandidateLoader? candidates,
    WorkoutSessionStore? backing,
  }) =>
      WorkoutSessionRestorer(
        manager: WorkoutSessionManager(backing ?? store),
        loadSetLogs: loadSetLogs ?? store.loadSetLogs,
        candidates: candidates ?? () async => const [],
      );

  /// Start Lower Body, complete all three squat sets and the first two calf
  /// sets, and leave calf set 3 outstanding — the QA acceptance state.
  Future<WorkoutSessionRecord> startPartialLowerBody({int elapsed = 372}) async {
    final manager = WorkoutSessionManager(store);
    final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());
    for (var n = 1; n <= 3; n++) {
      store.logSet(session.id, 'ex-squat', n,
          setId: _setId('ex-squat', n), reps: 5, weight: 100.0 + n);
    }
    store.logSet(session.id, 'ex-calf', 1,
        setId: _setId('ex-calf', 1),
        reps: _calfSet1['reps'] as int,
        weight: _calfSet1['weight'] as double,
        rpe: _calfSet1['rpe'] as double,
        notes: _calfSet1['notes'] as String);
    store.logSet(session.id, 'ex-calf', 2,
        setId: _setId('ex-calf', 2),
        reps: _calfSet2['reps'] as int,
        weight: _calfSet2['weight'] as double,
        rpe: _calfSet2['rpe'] as double,
        notes: _calfSet2['notes'] as String);
    await manager.saveElapsed(session.id, elapsed);
    return session;
  }

  setUp(() => store = InMemoryWorkoutSessionStore());

  // ── TEST 1 — the QA acceptance journey ────────────────────────────────────
  group('WKT-112 an active workout is restored across a browser refresh', () {
    test('the session is found and rebuilt without any Browse/Select step',
        () async {
      final started = await startPartialLowerBody();

      final restored = await afterRefresh().restore(_uid);

      expect(restored, isNotNull,
          reason: 'an in-progress session must survive the reload');
      expect(restored!.sessionId, started.id, reason: 'same session id');
      expect(restored.workout.id, 'w-lower');
      expect(restored.workout.title, 'Lower Body');
      // Rebuilt from the session's own snapshot — no workout list was consulted,
      // which is what makes the restore independent of Train/Browse.
      expect(restored.session.workoutId, 'w-lower');
    });

    test('the workout comes back with the same exercises in the same order',
        () async {
      await startPartialLowerBody();
      final original = _lowerBody();

      final restored = (await afterRefresh().restore(_uid))!;

      expect([for (final e in restored.workout.exercises) e.exercise.id],
          [for (final e in original.exercises) e.exercise.id]);
      expect([for (final e in restored.workout.exercises) e.exercise.name],
          ['Back Squat', 'Calf Raise']);
      for (var i = 0; i < original.exercises.length; i++) {
        expect([for (final s in restored.workout.exercises[i].sets) s.setNumber],
            [1, 2, 3],
            reason: 'set numbering is authoritative for exercise $i');
      }
    });

    test('the client resumes at Calf Raise set 3, not exercise 1 set 1', () async {
      await startPartialLowerBody();

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.position.setId, _setId('ex-calf', 3),
          reason: 'the outstanding set is Calf Raise set 3, by identity');
      expect(restored.position.exerciseId, 'ex-calf');
      expect(restored.position.exerciseIndex, 1);
      expect(restored.position.setIndex, 2);
      expect(restored.position.isComplete, isFalse);
      expect(restored.workout.exercises[restored.position.exerciseIndex]
          .exercise.name, 'Calf Raise');
      expect(restored.workout.exercises[1].sets[restored.position.setIndex]
          .setNumber, 3);
    });

    test('completed sets stay completed and the outstanding set stays open',
        () async {
      await startPartialLowerBody();

      final restored = (await afterRefresh().restore(_uid))!;

      expect(_state(restored, 'ex-calf', 1)['completed'], isTrue);
      expect(_state(restored, 'ex-calf', 2)['completed'], isTrue);
      expect(_state(restored, 'ex-calf', 3)['completed'], isNot(isTrue),
          reason: 'set 3 was never confirmed, so it must come back editable');
      expect([
        for (var n = 1; n <= 3; n++) _state(restored, 'ex-squat', n)['completed'],
      ], [true, true, true]);
    });

    test('weight, reps, RPE and notes come back on their own sets', () async {
      await startPartialLowerBody();

      final restored = (await afterRefresh().restore(_uid))!;

      for (final (n, expected) in [(1, _calfSet1), (2, _calfSet2)]) {
        final actual = _state(restored, 'ex-calf', n);
        expect(actual['weight'], expected['weight'], reason: 'set $n weight');
        expect(actual['reps'], expected['reps'], reason: 'set $n reps');
        expect(actual['rpe'], expected['rpe'], reason: 'set $n RPE');
        expect(actual['notes'], expected['notes'], reason: 'set $n notes');
      }
    });

    test('the session clock survives the reload', () async {
      final started = await startPartialLowerBody(elapsed: 372);

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.elapsedSeconds, 372);
      expect(restored.startedAt, started.startedAt,
          reason: 'the session timestamp is the one it was created with');
    });

    test('restoring twice is stable — leaving and returning changes nothing',
        () async {
      await startPartialLowerBody();

      final first = (await afterRefresh().restore(_uid))!;
      final second = (await afterRefresh().restore(_uid))!;

      expect(second.sessionId, first.sessionId);
      expect(second.position, first.position);
      expect(second.setState, first.setState);
    });
  });

  // ── TEST 2 — ordering is authoritative (QA-CL-002 cross-defect) ───────────
  group('WKT-112 restored order does not depend on row arrival order', () {
    test('rows arriving newest-first still seat on their own sets', () async {
      final manager = WorkoutSessionManager(store);
      final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());
      // Logged 3, 2, 1 — the shape a descending query hands back.
      store.logSet(session.id, 'ex-calf', 3,
          setId: _setId('ex-calf', 3), reps: 8, weight: 52.5, notes: 'third');
      store.logSet(session.id, 'ex-calf', 2,
          setId: _setId('ex-calf', 2), reps: 10, weight: 47.5, notes: 'second');
      store.logSet(session.id, 'ex-calf', 1,
          setId: _setId('ex-calf', 1), reps: 12, weight: 42.5, notes: 'first');

      final restored = (await afterRefresh().restore(_uid))!;

      expect([for (var n = 1; n <= 3; n++) _state(restored, 'ex-calf', n)['notes']],
          ['first', 'second', 'third']);
      expect([for (var n = 1; n <= 3; n++) _state(restored, 'ex-calf', n)['weight']],
          [42.5, 47.5, 52.5]);
    });

    test('a gap stays a gap instead of shifting later sets up', () async {
      final manager = WorkoutSessionManager(store);
      final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());
      store.logSet(session.id, 'ex-squat', 1, setId: _setId('ex-squat', 1));
      store.logSet(session.id, 'ex-squat', 3,
          setId: _setId('ex-squat', 3), notes: 'third');

      final restored = (await afterRefresh().restore(_uid))!;

      expect(_state(restored, 'ex-squat', 1)['completed'], isTrue);
      expect(_state(restored, 'ex-squat', 2), isEmpty,
          reason: 'set 2 was skipped and stays skipped');
      expect(_state(restored, 'ex-squat', 3)['notes'], 'third');
      expect(restored.position.setId, _setId('ex-squat', 2),
          reason: 'the outstanding set is the gap, not the end of the list');
    });

    test('a mid-session exercise swap is restored as the swapped workout',
        () async {
      final manager = WorkoutSessionManager(store);
      final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());

      // The Workout Zone re-snapshots after a swap.
      final swapped = _lowerBody();
      swapped.exercises[1] = WorkoutExercise(
        exercise: _exercise('ex-legpress', 'Leg Press'),
        sets: swapped.exercises[1].sets,
      );
      await manager.saveSnapshot(session.id, swapped);

      final restored = (await afterRefresh().restore(_uid))!;

      expect([for (final e in restored.workout.exercises) e.exercise.name],
          ['Back Squat', 'Leg Press'],
          reason: 'restoring the workout they started would lose the swap');
    });
  });

  // ── TEST 3 — no active workout is a different answer from "unknown" ───────
  group('WKT-112 no active workout', () {
    test('nothing in progress restores to null — the genuine empty state',
        () async {
      expect(await afterRefresh().restore(_uid), isNull);
    });

    test('a completed session is not resurrected', () async {
      final manager = WorkoutSessionManager(store);
      final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());
      await manager.completeSession(
          sessionId: session.id, durationSeconds: 900, idleSeconds: 0, caloriesBurned: 120);

      expect(await afterRefresh().restore(_uid), isNull);
    });

    test('an abandoned session is not resurrected', () async {
      final manager = WorkoutSessionManager(store);
      final session = await manager.startWorkout(userId: _uid, workout: _lowerBody());
      await manager.abandonSession(session.id);

      expect(await afterRefresh().restore(_uid), isNull);
    });

    test('another user\'s in-progress session is not restored', () async {
      await WorkoutSessionManager(store)
          .startWorkout(userId: 'someone-else', workout: _lowerBody());

      expect(await afterRefresh().restore(_uid), isNull);
    });
  });

  // ── TEST 4 — the warm-up belongs to the session ──────────────────────────
  group('WKT-112 warm-up acknowledgement is session state', () {
    test('a freshly started session has not acknowledged the warm-up', () async {
      final started = await startPartialLowerBody();
      expect(started.warmupAcknowledged, isFalse);

      final restored = (await afterRefresh().restore(_uid))!;
      expect(restored.warmupAcknowledged, isFalse,
          reason: 'the prompt has not been answered, so it should be shown');
    });

    test('an acknowledgement survives the refresh', () async {
      final started = await startPartialLowerBody();
      await WorkoutSessionManager(store).acknowledgeWarmup(started.id);

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.warmupAcknowledged, isTrue,
          reason: 'a client three sets in must not be asked to warm up again');
      expect(restored.session.warmupAcknowledgedAt, isNotNull);
    });

    test('acknowledging twice keeps the original answer', () async {
      final started = await startPartialLowerBody();
      final manager = WorkoutSessionManager(store);
      await manager.acknowledgeWarmup(started.id);
      final first = (await afterRefresh().restore(_uid))!.session.warmupAcknowledgedAt;

      await manager.acknowledgeWarmup(started.id);
      final second = (await afterRefresh().restore(_uid))!.session.warmupAcknowledgedAt;

      expect(second, first);
    });

    test('resuming the same workout keeps the acknowledgement', () async {
      final started = await startPartialLowerBody();
      final manager = WorkoutSessionManager(store);
      await manager.acknowledgeWarmup(started.id);

      // Re-entering the Zone runs startWorkout again.
      final resumed = await WorkoutSessionManager(store)
          .startWorkout(userId: _uid, workout: _lowerBody());

      expect(resumed.id, started.id);
      expect(resumed.warmupAcknowledged, isTrue);
    });

    test('starting a different workout asks again', () async {
      final started = await startPartialLowerBody();
      await WorkoutSessionManager(store).acknowledgeWarmup(started.id);

      final other = await WorkoutSessionManager(store)
          .startWorkout(userId: _uid, workout: _upperBody);

      expect(other.id, isNot(started.id));
      expect(other.warmupAcknowledged, isFalse,
          reason: 'a new session is a new warm-up');
    });
  });

  // ── TEST 5 — failures are recoverable, never silent ──────────────────────
  group('WKT-112 a session that cannot be restored is not discarded', () {
    test('a session whose workout cannot be rebuilt raises rather than '
        'reporting no workout', () async {
      // Pre-snapshot row with no matching workout in any list.
      store.seedSession(
          userId: _uid, workoutId: 'w-gone', workoutTitle: 'Deleted Workout');

      await expectLater(
          afterRefresh().restore(_uid), throwsA(isA<WorkoutRestorationFailure>()));
      expect(store.withStatus(WorkoutSessionStatus.inProgress), hasLength(1),
          reason: 'the session row is untouched and still resumable');
    });

    test('a failed set-log read does not resume an emptied workout', () async {
      await startPartialLowerBody();

      final restorer = afterRefresh(
          loadSetLogs: (_) async => throw StateError('read failed'));

      await expectLater(
          restorer.restore(_uid), throwsA(isA<WorkoutRestorationFailure>()));
    });

    test('a failed session lookup is not read as "no active workout"', () async {
      await startPartialLowerBody();
      final flaky = _FlakyStore(store);

      await expectLater(afterRefresh(backing: flaky).restore(_uid),
          throwsA(isA<WorkoutRestorationFailure>()));
    });

    test('retrying after a transient failure restores the session', () async {
      final started = await startPartialLowerBody();
      final flaky = _FlakyStore(store);

      await expectLater(afterRefresh(backing: flaky).restore(_uid),
          throwsA(isA<WorkoutRestorationFailure>()));

      // The retry the recovery state offers.
      final restored = await afterRefresh(backing: flaky).restore(_uid);
      expect(restored, isNotNull);
      expect(restored!.sessionId, started.id);
      expect(restored.position.setId, _setId('ex-calf', 3));
    });

    test('a pre-snapshot session is matched against the client\'s workouts',
        () async {
      store.seedSession(
          userId: _uid, workoutId: 'w-lower', workoutTitle: 'Lower Body');

      final restored = await afterRefresh(
          candidates: () async => [_lowerBody(), _upperBody]).restore(_uid);

      expect(restored, isNotNull);
      expect(restored!.workout.title, 'Lower Body');
    });
  });

  // ── TEST 6 — the derived resume position ─────────────────────────────────
  group('WKT-112 resume position is derived from completion state', () {
    test('a session with nothing logged starts at exercise 1, set 1', () {
      final position = resumePosition(_lowerBody(), const {});
      expect(position.setId, _setId('ex-squat', 1));
      expect(position.isComplete, isFalse);
    });

    test('a fully completed workout reports complete', () {
      final done = {
        for (final e in _lowerBody().exercises)
          for (final s in e.sets) s.id: {'completed': true},
      };
      final position = resumePosition(_lowerBody(), done);

      expect(position.isComplete, isTrue);
      expect(position.setId, _setId('ex-calf', 3),
          reason: 'the last set of the last exercise');
    });

    test('a set that was typed into but never confirmed is still outstanding', () {
      final typed = {
        _setId('ex-squat', 1): {'completed': true},
        _setId('ex-squat', 2): {'weight': 105.0, 'reps': 5}, // entered, not confirmed
      };
      expect(resumePosition(_lowerBody(), typed).setId, _setId('ex-squat', 2));
    });
  });

  // ── TEST 7 — the provider hydrates the state the Workout Zone reads ──────
  group('WKT-112 restoring hydrates the app state', () {
    ProviderContainer containerFor(WorkoutSessionRestorer restorer) {
      final container = ProviderContainer(overrides: [
        restoringUserIdProvider.overrideWithValue(_uid),
        workoutSessionRestorerProvider.overrideWithValue(restorer),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('the selected workout and the entered sets come back together',
        () async {
      final started = await startPartialLowerBody();
      final container = containerFor(afterRefresh());

      final restored = await container.read(activeWorkoutRestorationProvider.future);

      expect(restored, isNotNull);
      // The Workout Zone reads these two; before the fix both were empty after
      // a refresh, which is what produced "No workout selected".
      final selected = container.read(selectedWorkoutProvider);
      expect(selected, isNotNull);
      expect(selected!.title, 'Lower Body');
      expect([for (final e in selected.exercises) e.exercise.id],
          ['ex-squat', 'ex-calf']);

      final notifier = container.read(activeWorkoutProvider.notifier);
      expect(notifier.sessionId, started.id);
      expect(notifier.isSetCompleted(_setId('ex-calf', 2)), isTrue);
      expect(notifier.isSetCompleted(_setId('ex-calf', 3)), isFalse);
      expect(notifier.setData(_setId('ex-calf', 2))['notes'], _calfSet2['notes']);
    });

    test('with no active session nothing is hydrated', () async {
      final container = containerFor(afterRefresh());

      expect(await container.read(activeWorkoutRestorationProvider.future), isNull);
      expect(container.read(selectedWorkoutProvider), isNull);
      expect(container.read(activeWorkoutProvider), isEmpty);
    });

    test('a failed restore surfaces as an error, not as an empty workout',
        () async {
      await startPartialLowerBody();
      final container = containerFor(
          afterRefresh(loadSetLogs: (_) async => throw StateError('down')));

      await expectLater(container.read(activeWorkoutRestorationProvider.future),
          throwsA(isA<WorkoutRestorationFailure>()));
      expect(container.read(selectedWorkoutProvider), isNull,
          reason: 'a half-restored workout must never reach the Zone');
    });

    test('a signed-out app restores nothing', () async {
      await startPartialLowerBody();
      final container = ProviderContainer(overrides: [
        restoringUserIdProvider.overrideWithValue(null),
        workoutSessionRestorerProvider.overrideWithValue(afterRefresh()),
      ]);
      addTearDown(container.dispose);

      expect(await container.read(activeWorkoutRestorationProvider.future), isNull);
    });
  });

  // ── TEST 8 — the restored state is what the Workout Zone shows ───────────
  group('WKT-112 restored state hydrates the Workout Zone', () {
    test('the in-memory notifier and the restore agree on every set', () async {
      await startPartialLowerBody();
      final restored = (await afterRefresh().restore(_uid))!;

      // Exactly what activeWorkoutRestorationProvider does on hydration.
      final live = ActiveWorkoutNotifier()..beginSession(restored.sessionId);
      live.restoreSeated(restored.setState);

      expect(live.sessionId, restored.sessionId);
      expect(live.isSetCompleted(_setId('ex-calf', 1)), isTrue);
      expect(live.isSetCompleted(_setId('ex-calf', 2)), isTrue);
      expect(live.isSetCompleted(_setId('ex-calf', 3)), isFalse);
      expect(live.setData(_setId('ex-calf', 2))['weight'], _calfSet2['weight']);
      expect(live.setData(_setId('ex-calf', 2))['notes'], _calfSet2['notes']);
      expect(resumePosition(restored.workout, live.state), restored.position);
    });

    test('a restored completed set is immutable; the open one is editable',
        () async {
      await startPartialLowerBody();
      final restored = (await afterRefresh().restore(_uid))!;
      final live = ActiveWorkoutNotifier()..beginSession(restored.sessionId);
      live.restoreSeated(restored.setState);
      final calf = restored.workout.exercises[1];

      // Set 2 is a recorded result — an ordinary edit must not rewrite it.
      expect(live.setSetData(calf.sets[1], {'weight': 999.0}), isFalse);
      expect(live.setData(_setId('ex-calf', 2))['weight'], _calfSet2['weight']);

      // Set 3 is where they left off, and takes their next entry.
      expect(live.setSetData(calf.sets[2], {'weight': 50.0, 'reps': 8},
          exerciseInstanceId: 'ex-calf'), isTrue);
      expect(live.setData(_setId('ex-calf', 3))['weight'], 50.0);
      expect(live.isSetCompleted(_setId('ex-calf', 3)), isFalse);
    });
  });
}
