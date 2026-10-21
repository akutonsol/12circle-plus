// QA-CL-006 — resume must restore set identity, not just the workout.
//
// Reported: leaving an active workout and tapping "Resume Workout" brought the
// workout back, but not reliably the exact exercise/set the client was on. The
// app restored the workout *id* and then rebuilt where-you-are by walking
// lists, so a set was only ever as identifiable as its position — and any
// disturbance to that position (rows arriving in another order, a set number
// that isn't its index plus one, an exercise swapped mid-session) moved one
// set's weight, reps, RPE and notes onto another.
//
// The fix is identity. Every set carries an id; every logged row records the id
// of the set it belongs to; the session records the id of the set the client is
// on. These tests build exercises and sets whose values are unique enough that
// a set landing in the wrong place is visible rather than plausible, then push
// them through the whole journey — navigate away, persist, retrieve, refresh,
// resume — asserting the same logical entities come back.
//
// The acceptance case from the report, kept literal throughout:
//     Lower Body → Calf Raise → Set 3 → incomplete → 100 lb × 10 @ RPE 7
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_restoration.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';

import '../support/in_memory_workout_session_store.dart';

const _uid = 'user-1';

/// Weight is stored in kg; the report is in pounds. 100 lb, exactly.
const _kgPerLb = 0.45359237;
const _hundredLb = 100 * _kgPerLb;

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

/// Lower Body, as the report describes it: Back Squat then Calf Raise, three
/// sets each. Sets are built with no explicit id so the app assigns them, which
/// is exactly what happens for a coach-authored workout.
Workout _lowerBody() => Workout(
      id: 'w-lower',
      title: 'Lower Body',
      description: '',
      estimatedDuration: 50,
      difficulty: 'Intermediate',
      category: 'Strength',
      exercises: [
        WorkoutExercise(
          exercise: _exercise('ex-squat', 'Back Squat'),
          sets: [
            for (var n = 1; n <= 3; n++)
              WorkoutSet(setNumber: n, reps: 5, weightKg: 100.0 + n, restSeconds: 120),
          ],
        ),
        WorkoutExercise(
          exercise: _exercise('ex-calf', 'Calf Raise'),
          sets: [
            for (var n = 1; n <= 3; n++)
              WorkoutSet(setNumber: n, reps: 10, weightKg: 40.0 + n, restSeconds: 60),
          ],
        ),
      ],
    );

/// The set the report names, by identity.
WorkoutSet _setOf(Workout w, String exerciseId, int setNumber) => w.exercises
    .firstWhere((e) => e.exercise.id == exerciseId)
    .sets
    .firstWhere((s) => s.setNumber == setNumber);

/// Every set in the workout, in authored order.
Iterable<WorkoutSet> _allSets(Workout w) => w.exercises.expand((e) => e.sets);

void main() {
  late InMemoryWorkoutSessionStore store;
  setUp(() => store = InMemoryWorkoutSessionStore());

  WorkoutSessionRestorer afterRefresh() => WorkoutSessionRestorer(
        manager: WorkoutSessionManager(store),
        loadSetLogs: store.loadSetLogs,
      );

  /// Start Lower Body and leave the client part-way through Calf Raise set 3:
  /// calf sets 1 and 2 confirmed, set 3 typed in at 100 lb × 10 @ RPE 7 but
  /// never confirmed — the exact state the report describes leaving.
  Future<WorkoutSessionRecord> leaveMidCalfRaiseSet3() async {
    final manager = WorkoutSessionManager(store);
    final workout = _lowerBody();
    final session = await manager.startWorkout(userId: _uid, workout: workout);

    for (var n = 1; n <= 3; n++) {
      final set = _setOf(workout, 'ex-squat', n);
      store.logSet(session.id, 'ex-squat', n,
          setId: set.id, reps: 5, weight: 100.0 + n, rpe: 6.0 + n);
    }
    for (var n = 1; n <= 2; n++) {
      final set = _setOf(workout, 'ex-calf', n);
      store.logSet(session.id, 'ex-calf', n,
          setId: set.id, reps: 12 - n, weight: 40.0 + n, rpe: 7.0 + n,
          notes: 'calf note $n');
    }
    // Set 3: values entered, not confirmed. The app writes a row for an edited
    // set too — that is what makes an incomplete set restorable at all.
    final open = _setOf(workout, 'ex-calf', 3);
    store.logSet(session.id, 'ex-calf', 3,
        setId: open.id,
        reps: 10,
        weight: _hundredLb,
        rpe: 7.0,
        completed: false);
    await manager.saveCursor(
        sessionId: session.id, exerciseId: 'ex-calf', setId: open.id);
    await manager.saveElapsed(session.id, 918);
    return session;
  }

  // ── TEST 1 — every set is identifiable at all ─────────────────────────────
  group('QA-CL-006 a set has an identity of its own', () {
    test('every set in a workout carries a unique, non-empty id', () {
      final workout = _lowerBody();
      final ids = [for (final s in _allSets(workout)) s.id];

      expect(ids.where((id) => id.isEmpty), isEmpty,
          reason: 'a set with no id can only be named by its position');
      expect(ids.toSet(), hasLength(ids.length),
          reason: 'two sets sharing an id are one set as far as logs go');
    });

    test('the same definition built twice mints the same ids', () {
      // Identity has to be reproducible: a workout rebuilt from its definition
      // on another device, or after a reload, must name its sets the same way
      // or the logs written against them stop matching.
      expect([for (final s in _allSets(_lowerBody())) s.id],
          [for (final s in _allSets(_lowerBody())) s.id]);
    });

    test('a set keeps the id it was given rather than being renumbered', () {
      final we = WorkoutExercise(
        exercise: _exercise('ex-calf', 'Calf Raise'),
        sets: [
          WorkoutSet(id: 'set-authored-3', setNumber: 3, reps: 10, weightKg: 45),
          WorkoutSet(setNumber: 1, reps: 10, weightKg: 45),
        ],
      );

      expect(we.sets[0].id, 'set-authored-3',
          reason: 'an id the source supplied is authoritative');
      expect(we.sets[0].setNumber, 3,
          reason: 'and its set number is not rewritten to match its position');
      expect(we.sets[1].id, isNot('set-authored-3'));
    });

    test('sets with a repeated set number still get distinct identities', () {
      final we = WorkoutExercise(
        exercise: _exercise('ex-calf', 'Calf Raise'),
        sets: [
          WorkoutSet(setNumber: 1, reps: 10, weightKg: 45),
          WorkoutSet(setNumber: 1, reps: 8, weightKg: 50),
        ],
      );

      expect(we.sets[0].id, isNot(we.sets[1].id));
    });

    test('a set can be found by its id, and a foreign id finds nothing', () {
      final workout = _lowerBody();
      final target = _setOf(workout, 'ex-calf', 3);

      final located = locateSet(workout, target.id);
      expect(located, isNotNull);
      expect(located!.set.id, target.id);
      expect(located.exercise.exercise.name, 'Calf Raise');
      expect(located.set.setNumber, 3);

      expect(locateSet(workout, 'set-from-another-workout'), isNull);
      expect(locateSet(workout, ''), isNull);
    });
  });

  // ── TEST 2 — identity survives persistence and retrieval ──────────────────
  group('QA-CL-006 identity survives the snapshot round trip', () {
    test('exercise and set ids come back exactly as they went in', () {
      final original = _lowerBody();

      final rebuilt = programWorkoutToWorkout(workoutToSnapshot(original));

      expect([for (final e in rebuilt.exercises) e.exercise.id],
          [for (final e in original.exercises) e.exercise.id]);
      expect([for (final s in _allSets(rebuilt)) s.id],
          [for (final s in _allSets(original)) s.id],
          reason: 'set identity is stored, not re-derived on the way back');
      expect([for (final s in _allSets(rebuilt)) s.setNumber],
          [for (final s in _allSets(original)) s.setNumber]);
    });

    test('a snapshot round trip is stable however often it is repeated', () {
      // A session is re-snapshotted whenever the workout changes mid-session;
      // ids drifting on each pass would orphan the logs written before it.
      var w = _lowerBody();
      final ids = [for (final s in _allSets(w)) s.id];
      for (var i = 0; i < 3; i++) {
        w = programWorkoutToWorkout(workoutToSnapshot(w));
      }
      expect([for (final s in _allSets(w)) s.id], ids);
    });

    test('a workout whose sets are reordered keeps each set\'s identity', () {
      final original = _lowerBody();
      final snapshot = workoutToSnapshot(original);
      // Someone reverses the stored set list — the pathological case the
      // report calls out. Identity must not follow the new positions.
      final calf = (snapshot['exercises'] as List)[1] as Map<String, dynamic>;
      calf['set_details'] = (calf['set_details'] as List).reversed.toList();

      final rebuilt = programWorkoutToWorkout(snapshot);
      final rebuiltCalf = rebuilt.exercises[1];

      expect([for (final s in rebuiltCalf.sets) s.id],
          [for (final s in original.exercises[1].sets.reversed) s.id],
          reason: 'each set carried its own id into its new position');
      for (final s in rebuiltCalf.sets) {
        expect(s.id, endsWith(':s${s.setNumber}'),
            reason: 'id and set number stayed together');
      }
    });

    test('an exercise without an id is identified once and then stored', () {
      // A `program_workouts` row authored before exercise ids existed. The id
      // is minted from the name, so the *same* row mints the same id, and the
      // snapshot then freezes it.
      final row = {
        'id': 'w-legacy',
        'title': 'Legacy',
        'exercises': [
          {'name': 'Calf Raise', 'sets': 3, 'reps': 10, 'weight': 45},
        ],
      };

      final first = programWorkoutToWorkout(Map<String, dynamic>.from(row));
      final second = programWorkoutToWorkout(Map<String, dynamic>.from(row));

      expect(first.exercises.first.exercise.id, isNotEmpty);
      expect(first.exercises.first.exercise.id,
          second.exercises.first.exercise.id,
          reason: 'the mint is deterministic, not a counter');
      expect([for (final s in _allSets(first)) s.id],
          [for (final s in _allSets(second)) s.id]);

      // And once snapshotted it is read back rather than minted again.
      final stored = programWorkoutToWorkout(workoutToSnapshot(first));
      expect(stored.exercises.first.exercise.id,
          first.exercises.first.exercise.id);
    });

    test('two unnamed exercises do not collapse into one identity', () {
      final rebuilt = programWorkoutToWorkout({
        'id': 'w-dupe',
        'title': 'Dupe',
        'exercises': [
          {'name': 'Calf Raise', 'sets': 2, 'reps': 10},
          {'name': 'Calf Raise', 'sets': 2, 'reps': 12},
        ],
      });

      final ids = [for (final e in rebuilt.exercises) e.exercise.id];
      expect(ids.toSet(), hasLength(2));
      final setIds = [for (final s in _allSets(rebuilt)) s.id];
      expect(setIds.toSet(), hasLength(setIds.length),
          reason: 'sets of same-named exercises must stay distinguishable');
    });
  });

  // ── TEST 3 — logs attach to the set they recorded ─────────────────────────
  group('QA-CL-006 a logged row is attached by set identity', () {
    test('rows arriving in any order land on their own sets', () {
      final workout = _lowerBody();
      final calf = workout.exercises[1];
      final rows = [
        for (var n = 3; n >= 1; n--)
          {
            'set_id': calf.sets[n - 1].id,
            'set_number': n,
            'weight': 40.0 + n,
            'notes': 'note $n',
            'completed': true,
          },
      ];

      final seated = seatSetLogs(workout, {'ex-calf': rows});

      for (var n = 1; n <= 3; n++) {
        final state = seated[calf.sets[n - 1].id]!;
        expect(state['weight'], 40.0 + n, reason: 'set $n weight');
        expect(state['notes'], 'note $n', reason: 'set $n notes');
        expect(state['set_number'], n);
      }
    });

    test('set numbers that are not 1..N still attach correctly', () {
      // The case list position can never handle: an exercise whose sets are
      // numbered 1, 2 and 5. Index-based seating puts set 5 on the third slot
      // and calls it set 3.
      final workout = Workout(
        id: 'w-gap',
        title: 'Gap',
        description: '',
        estimatedDuration: 20,
        difficulty: 'Intermediate',
        category: 'Strength',
        exercises: [
          WorkoutExercise(
            exercise: _exercise('ex-calf', 'Calf Raise'),
            sets: [
              for (final n in [1, 2, 5])
                WorkoutSet(setNumber: n, reps: 10, weightKg: 45),
            ],
          ),
        ],
      );
      final five = _setOf(workout, 'ex-calf', 5);

      final seated = seatSetLogs(workout, {
        'ex-calf': [
          {'set_id': five.id, 'set_number': 5, 'weight': 99.0, 'completed': true},
        ],
      });

      expect(seated[five.id]!['weight'], 99.0);
      expect(seated[five.id]!['set_number'], 5);
      expect(seated.keys, [five.id],
          reason: 'sets 1 and 2 were never logged and must stay untouched');
    });

    test('a row for a set the workout no longer has is not re-homed', () {
      // The exercise was swapped out mid-session. Its logs still exist, and
      // must not be pushed onto whatever set is now in that position.
      final workout = _lowerBody();

      final seated = seatSetLogs(workout, {
        'ex-legpress': [
          {'set_id': 'ex-legpress:s1', 'set_number': 1, 'weight': 180.0},
        ],
      });

      expect(seated, isEmpty,
          reason: 'the workout is authoritative about which sets exist');
    });

    test('a row written before set ids existed falls back to its set number', () {
      final workout = _lowerBody();
      final calf = workout.exercises[1];

      final seated = seatSetLogs(workout, {
        'ex-calf': [
          {'set_number': 3, 'weight': _hundredLb, 'reps': 10, 'rpe': 7.0},
          {'set_number': 1, 'weight': 41.0, 'reps': 12},
        ],
      });

      expect(seated[calf.sets[2].id]!['weight'], _hundredLb);
      expect(seated[calf.sets[0].id]!['weight'], 41.0);
      expect(seated[calf.sets[1].id], isNull,
          reason: 'set 2 was never logged, and no row slid into it');
    });

    test('a legacy row keyed by exercise name still finds its exercise', () {
      final workout = _lowerBody();
      final calf = workout.exercises[1];

      final seated = seatSetLogs(workout, {
        'Calf Raise': [
          {'set_number': 2, 'weight': 42.0, 'completed': true},
        ],
      });

      expect(seated[calf.sets[1].id]!['weight'], 42.0);
    });

    test('seated state says which set and exercise it belongs to', () {
      final workout = _lowerBody();
      final target = _setOf(workout, 'ex-calf', 3);

      final seated = seatSetLogs(workout, {
        'ex-calf': [
          {'set_id': target.id, 'set_number': 3, 'weight': _hundredLb},
        ],
      });

      expect(seated[target.id]!['set_id'], target.id);
      expect(seated[target.id]!['exercise_instance_id'], 'ex-calf',
          reason: 'seated state names the exercise *instance*, which is the '
              'identity; the library exercise id is a recorded attribute');
      expect(seated[target.id]!['set_number'], 3);
    });
  });

  // ── TEST 4 — the acceptance journey from the report ───────────────────────
  group('QA-CL-006 Calf Raise set 3 is the same set after Resume Workout', () {
    test('the exact state described is what comes back', () async {
      final started = await leaveMidCalfRaiseSet3();

      final restored = (await afterRefresh().restore(_uid))!;
      final position = restored.position;
      final located = locateSet(restored.workout, position.setId)!;

      // Lower Body → Calf Raise → Set 3 → incomplete → 100 lb × 10 @ RPE 7.
      expect(restored.workout.title, 'Lower Body');
      expect(located.exercise.exercise.name, 'Calf Raise');
      expect(located.set.setNumber, 3);

      final state = restored.setState[position.setId]!;
      expect(state['completed'], isNot(isTrue), reason: 'still incomplete');
      expect(state['weight'], closeTo(_hundredLb, 1e-9), reason: '100 lb');
      expect(state['reps'], 10);
      expect(state['rpe'], 7.0);

      // And it is the same session, not a new one.
      expect(restored.sessionId, started.id);
    });

    test('the set is the same logical entity before and after', () async {
      final before = _lowerBody();
      await leaveMidCalfRaiseSet3();

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.position.setId, _setOf(before, 'ex-calf', 3).id,
          reason: 'the id the client left on is the id they come back to');
      expect(restored.position.exerciseId, 'ex-calf');
    });

    test('restoring twice — leave, return, leave, return — is identical',
        () async {
      await leaveMidCalfRaiseSet3();

      final first = (await afterRefresh().restore(_uid))!;
      final second = (await afterRefresh().restore(_uid))!;

      expect(second.position, first.position);
      expect(second.setState, first.setState);
      expect(second.sessionId, first.sessionId);
    });

    test('every required piece of session state comes back', () async {
      final started = await leaveMidCalfRaiseSet3();

      final restored = (await afterRefresh().restore(_uid))!;
      final calf3 = _setOf(restored.workout, 'ex-calf', 3);
      final state = restored.setState[calf3.id]!;

      // Session
      expect(restored.sessionId, started.id);
      expect(restored.workout.id, 'w-lower');
      expect(restored.startedAt, started.startedAt);
      expect(restored.elapsedSeconds, 918);
      expect(restored.warmupAcknowledged, isFalse);
      // Exercise: identity and order
      expect([for (final e in restored.workout.exercises) e.exercise.id],
          ['ex-squat', 'ex-calf']);
      // Set: identity, order, completion and values
      expect(state['set_id'], calf3.id);
      expect(state['set_number'], 3);
      expect(state['completed'], isNot(isTrue));
      expect(state['weight'], closeTo(_hundredLb, 1e-9));
      expect(state['reps'], 10);
      expect(state['rpe'], 7.0);
      // Current exercise and current set
      expect(restored.position.exerciseId, 'ex-calf');
      expect(restored.position.setId, calf3.id);
      // Notes, on the set that carried one
      expect(restored.setState[_setOf(restored.workout, 'ex-calf', 2).id]!['notes'],
          'calf note 2');
    });

    test('confirmed sets come back confirmed, with their own values', () async {
      await leaveMidCalfRaiseSet3();

      final restored = (await afterRefresh().restore(_uid))!;

      for (var n = 1; n <= 3; n++) {
        final squat = restored.setState[_setOf(restored.workout, 'ex-squat', n).id]!;
        expect(squat['completed'], isTrue, reason: 'squat set $n');
        expect(squat['weight'], 100.0 + n, reason: 'squat set $n weight');
        expect(squat['rpe'], 6.0 + n, reason: 'squat set $n RPE');
      }
      for (var n = 1; n <= 2; n++) {
        final calf = restored.setState[_setOf(restored.workout, 'ex-calf', n).id]!;
        expect(calf['completed'], isTrue, reason: 'calf set $n');
        expect(calf['weight'], 40.0 + n, reason: 'calf set $n weight');
        expect(calf['notes'], 'calf note $n', reason: 'calf set $n notes');
      }
    });

    test('the Workout Zone hydrates onto the same set identities', () async {
      await leaveMidCalfRaiseSet3();
      final restored = (await afterRefresh().restore(_uid))!;

      // What activeWorkoutRestorationProvider does on hydration.
      final live = ActiveWorkoutNotifier()..beginSession(restored.sessionId);
      live.restoreSeated(restored.setState);
      final calf3 = _setOf(restored.workout, 'ex-calf', 3);

      expect(live.isSetCompleted(calf3.id), isFalse);
      expect(live.setData(calf3.id)['reps'], 10);
      expect(live.setData(calf3.id)['rpe'], 7.0);
      // The confirmed sets are locked, exactly as they were before leaving.
      final calf2 = _setOf(restored.workout, 'ex-calf', 2);
      expect(live.setSetData(calf2, {'weight': 999.0}), isFalse);
      expect(live.setData(calf2.id)['weight'], 42.0);
      // And the open set still takes the client's next entry.
      expect(live.setSetData(calf3, {'reps': 11}, exerciseInstanceId: 'ex-calf'), isTrue);
      expect(live.setData(calf3.id)['reps'], 11);
    });

    test('the provider hydration path lands on the same set too', () async {
      await leaveMidCalfRaiseSet3();
      final container = ProviderContainer(overrides: [
        restoringUserIdProvider.overrideWithValue(_uid),
        workoutSessionRestorerProvider.overrideWithValue(afterRefresh()),
      ]);
      addTearDown(container.dispose);

      final restored =
          await container.read(activeWorkoutRestorationProvider.future);

      final selected = container.read(selectedWorkoutProvider)!;
      final calf3 = _setOf(selected, 'ex-calf', 3);
      expect(restored!.position.setId, calf3.id);

      final notifier = container.read(activeWorkoutProvider.notifier);
      expect(notifier.setData(calf3.id)['reps'], 10);
      expect(notifier.isSetCompleted(calf3.id), isFalse);
      expect(notifier.completedSetCount, 5,
          reason: 'three squat sets and two calf sets were confirmed');
    });
  });

  // ── TEST 5 — the session's own record of where the client is ──────────────
  group('QA-CL-006 the current exercise and set are stored, not guessed', () {
    test('the cursor is written to the session and read back', () async {
      final started = await leaveMidCalfRaiseSet3();
      final calf3 = _setOf(_lowerBody(), 'ex-calf', 3);

      final row = await WorkoutSessionManager(store).activeSession(_uid);

      expect(row!.id, started.id);
      expect(row.currentExerciseId, 'ex-calf');
      expect(row.currentSetId, calf3.id);
    });

    test('a client who skipped ahead resumes where they were, not at the gap',
        () async {
      // Nothing is logged for squat set 2, but the client had deliberately
      // moved on to calf set 1. The derived answer would drag them backwards.
      final manager = WorkoutSessionManager(store);
      final workout = _lowerBody();
      final session = await manager.startWorkout(userId: _uid, workout: workout);
      final squat1 = _setOf(workout, 'ex-squat', 1);
      final calf1 = _setOf(workout, 'ex-calf', 1);
      store.logSet(session.id, 'ex-squat', 1, setId: squat1.id);
      await manager.saveCursor(
          sessionId: session.id, exerciseId: 'ex-calf', setId: calf1.id);

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.position.setId, calf1.id);
      expect(restored.position.exerciseId, 'ex-calf');
    });

    test('a cursor naming a set that has since been completed is ignored',
        () async {
      final manager = WorkoutSessionManager(store);
      final workout = _lowerBody();
      final session = await manager.startWorkout(userId: _uid, workout: workout);
      final squat1 = _setOf(workout, 'ex-squat', 1);
      store.logSet(session.id, 'ex-squat', 1, setId: squat1.id);
      await manager.saveCursor(
          sessionId: session.id, exerciseId: 'ex-squat', setId: squat1.id);

      final restored = (await afterRefresh().restore(_uid))!;

      expect(restored.position.setId, _setOf(workout, 'ex-squat', 2).id,
          reason: 'a stale cursor gives way to the first outstanding set');
    });

    test('a cursor naming a set that no longer exists is ignored', () {
      final workout = _lowerBody();

      final position = resumePosition(workout, const {},
          cursorSetId: 'ex-legpress:s1');

      expect(position.setId, _setOf(workout, 'ex-squat', 1).id,
          reason: 'a swapped-out set can never be resumed onto');
    });

    test('with no cursor the first outstanding set is the answer', () {
      final workout = _lowerBody();
      final done = {
        for (final s in workout.exercises[0].sets) s.id: {'completed': true},
        _setOf(workout, 'ex-calf', 1).id: {'completed': true},
      };

      final position = resumePosition(workout, done);

      expect(position.setId, _setOf(workout, 'ex-calf', 2).id);
      expect(position.exerciseIndex, 1);
      expect(position.setIndex, 1);
      expect(position.isComplete, isFalse);
    });

    test('a set typed into but not confirmed is still the outstanding one', () {
      final workout = _lowerBody();
      final target = _setOf(workout, 'ex-calf', 3);
      final state = {
        for (final s in _allSets(workout))
          if (s.id != target.id) s.id: {'completed': true},
        target.id: {'weight': _hundredLb, 'reps': 10, 'rpe': 7.0},
      };

      final position = resumePosition(workout, state);

      expect(position.setId, target.id);
      expect(position.isComplete, isFalse);
    });

    test('a finished workout reports complete rather than a phantom set', () {
      final workout = _lowerBody();
      final done = {
        for (final s in _allSets(workout)) s.id: {'completed': true},
      };

      final position = resumePosition(workout, done);

      expect(position.isComplete, isTrue);
      expect(position.setId, _setOf(workout, 'ex-calf', 3).id);
    });
  });

  // ── TEST 6 — the cursor moves forward as sets are confirmed ───────────────
  group('QA-CL-006 confirming a set moves the cursor forward', () {
    test('the next set of the same exercise takes the cursor', () {
      final workout = _lowerBody();
      final squat1 = _setOf(workout, 'ex-squat', 1);

      final next = advancePosition(
          workout, {squat1.id: {'completed': true}}, squat1.id);

      expect(next.setId, _setOf(workout, 'ex-squat', 2).id);
      expect(next.isComplete, isFalse);
    });

    test('finishing an exercise carries the cursor into the next one', () {
      final workout = _lowerBody();
      final squat3 = _setOf(workout, 'ex-squat', 3);
      final state = {
        for (final s in workout.exercises[0].sets) s.id: {'completed': true},
      };

      final next = advancePosition(workout, state, squat3.id);

      expect(next.exerciseId, 'ex-calf');
      expect(next.setId, _setOf(workout, 'ex-calf', 1).id);
    });

    test('a client who skipped ahead is not dragged back to an open set', () {
      // Calf set 1 is confirmed while squat set 2 is still open — deliberately
      // left. The cursor must go on to calf set 2, not back to the squat.
      final workout = _lowerBody();
      final calf1 = _setOf(workout, 'ex-calf', 1);
      final state = {
        _setOf(workout, 'ex-squat', 1).id: {'completed': true},
        calf1.id: {'completed': true},
      };

      final next = advancePosition(workout, state, calf1.id);

      expect(next.setId, _setOf(workout, 'ex-calf', 2).id);
    });

    test('the last set falls back to whatever is still open earlier', () {
      final workout = _lowerBody();
      final calf3 = _setOf(workout, 'ex-calf', 3);
      final open = _setOf(workout, 'ex-squat', 2);
      final state = {
        for (final s in _allSets(workout))
          if (s.id != open.id) s.id: {'completed': true},
      };

      final next = advancePosition(workout, state, calf3.id);

      expect(next.setId, open.id,
          reason: 'nothing follows the last set, so unfinished work wins');
      expect(next.isComplete, isFalse);
    });

    test('a finished workout leaves the cursor on the set just confirmed', () {
      final workout = _lowerBody();
      final calf3 = _setOf(workout, 'ex-calf', 3);
      final state = {
        for (final s in _allSets(workout)) s.id: {'completed': true},
      };

      final next = advancePosition(workout, state, calf3.id);

      expect(next.setId, calf3.id);
      expect(next.isComplete, isTrue);
    });

    test('advancing from a set the workout no longer has still names a set', () {
      final workout = _lowerBody();

      final next = advancePosition(workout, const {}, 'ex-legpress:s1');

      expect(next.setId, _setOf(workout, 'ex-squat', 1).id);
    });
  });

  // ── TEST 7 — identity holds when the workout changes under the session ────
  group('QA-CL-006 identity holds across a mid-session change', () {
    test('a swap keeps the untouched exercise\'s sets and their values',
        () async {
      final manager = WorkoutSessionManager(store);
      final workout = _lowerBody();
      final session = await manager.startWorkout(userId: _uid, workout: workout);
      for (var n = 1; n <= 3; n++) {
        store.logSet(session.id, 'ex-squat', n,
            setId: _setOf(workout, 'ex-squat', n).id, weight: 100.0 + n);
      }

      // Calf Raise is swapped for Leg Press; Back Squat is untouched.
      final swapped = Workout(
        id: workout.id,
        title: workout.title,
        description: workout.description,
        estimatedDuration: workout.estimatedDuration,
        difficulty: workout.difficulty,
        category: workout.category,
        exercises: [
          workout.exercises[0],
          WorkoutExercise(
            exercise: _exercise('ex-legpress', 'Leg Press'),
            sets: [
              for (var n = 1; n <= 3; n++)
                WorkoutSet(setNumber: n, reps: 12, weightKg: 150),
            ],
          ),
        ],
      );
      await manager.saveSnapshot(session.id, swapped);

      final restored = (await afterRefresh().restore(_uid))!;

      expect([for (final e in restored.workout.exercises) e.exercise.name],
          ['Back Squat', 'Leg Press']);
      for (var n = 1; n <= 3; n++) {
        final set = _setOf(restored.workout, 'ex-squat', n);
        expect(set.id, _setOf(workout, 'ex-squat', n).id,
            reason: 'the surviving exercise keeps its set identities');
        expect(restored.setState[set.id]!['weight'], 100.0 + n);
      }
      expect(restored.position.exerciseId, 'ex-legpress',
          reason: 'the outstanding work is now the new exercise');
    });

    test('re-entering the same workout resumes the same session and sets',
        () async {
      final started = await leaveMidCalfRaiseSet3();
      final calf3 = _setOf(_lowerBody(), 'ex-calf', 3);

      // Tapping into Lower Body again from Train.
      final resumed = await WorkoutSessionManager(store)
          .startWorkout(userId: _uid, workout: _lowerBody());

      expect(resumed.id, started.id, reason: 'the same session, not a new one');
      expect(resumed.currentSetId, calf3.id,
          reason: 'and it still knows which set the client is on');

      final restored = (await afterRefresh().restore(_uid))!;
      expect(restored.setState[calf3.id]!['reps'], 10);
    });
  });
}
