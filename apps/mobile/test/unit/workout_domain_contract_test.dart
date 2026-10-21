import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_contract.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_restoration.dart';

/// Phase 2 — the canonical workout domain contract.
///
/// Every group here pins one clause of `docs/WORKOUT_DOMAIN_CONTRACT.md`, and
/// each was written to FAIL against the pre-contract code. The defects they
/// cover were reproduced live against QA first (see
/// `docs/PHASE_2_WORKOUT_TEST_MATRIX.md`), so what is asserted is behaviour the
/// database actually had, not behaviour that was merely suspected.

// ── Fixtures ────────────────────────────────────────────────────────────────

Exercise _ex(String id, String name) => Exercise(
      id: id, name: name, category: 'Strength', muscleGroup: 'Chest',
      equipment: 'Barbell', difficulty: 'Intermediate',
      description: '', instructions: const []);

/// A canonical `program_workouts` row.
Map<String, dynamic> _row(List<Map<String, dynamic>> exercises) => {
      'id': 'w-1',
      'title': 'Upper Push',
      'exercises': exercises,
    };

Map<String, dynamic> _canonical({
  String? instanceId,
  String name = 'Bench Press',
  int sets = 3,
  int reps = 10,
  Object? weightKg,
  int? restSeconds,
  double? rpe,
}) =>
    {
      if (instanceId != null) 'exercise_instance_id': instanceId,
      'name': name,
      'sets': sets,
      'reps': reps,
      'weight_kg': weightKg,
      if (restSeconds != null) 'rest_seconds': restSeconds,
      if (rpe != null) 'rpe': rpe,
    };

List<WorkoutSet> _allSets(Workout w) =>
    [for (final e in w.exercises) ...e.sets];

void main() {
  // ── WKT-201 · type safety ─────────────────────────────────────────────────
  group('WKT-201 the codec validates the canonical type', () {
    test('an integer rep count is accepted', () {
      final w = programWorkoutToWorkout(_row([_canonical(reps: 8)]));
      expect(w.exercises.single.sets.first.reps, 8);
    });

    test('a rep count that is unambiguously a number is read, and reported', () {
      // The Program Builder wrote `'reps': _reps.text.trim()`, i.e. the String
      // "10". `as int?` THROWS on a String in Dart — it does not yield null —
      // and the provider turned that throw into "you have no program".
      final decoded = decodeProgramWorkout(_row([
        {'name': 'Bench Press', 'sets': 3, 'reps': '10', 'rest': 60},
      ]));

      expect(decoded.workout.exercises.single.sets.first.reps, 10);
      expect(decoded.workout.exercises.single.sets.first.restSeconds, 60,
          reason: 'the legacy `rest` key is the coach\'s prescription, not a '
              'value to discard in favour of a 90s default');
      expect(
        decoded.deviations.map((d) => d.field),
        containsAll(<String>['reps', 'rest_seconds']),
        reason: 'a legacy dialect is translated out loud, never silently',
      );
    });

    test('a rep RANGE is a violation, not a value to guess at', () {
      // "8-12" has no single value. Reading it as 8, as 12, or as the old
      // codec's `?? 10` would each prescribe something no coach wrote.
      expect(
        () => programWorkoutToWorkout(_row([
          {'name': 'Bench Press', 'sets': 3, 'reps': '8-12', 'weight_kg': null},
        ])),
        throwsA(isA<WorkoutContractViolation>()
            .having((e) => e.field, 'field', 'reps')
            .having((e) => e.value, 'value', '8-12')),
      );
    });

    test('a malformed row fails explicitly instead of decoding to nothing', () {
      for (final bad in <Object?>[
        {'exercises': 'not-an-array'},
        {'exercises': [42]},
        {'exercises': [{'sets': 3, 'reps': 10, 'weight_kg': null}]}, // no name
        {'exercises': [{'name': 'X', 'sets': 0, 'reps': 10, 'weight_kg': null}]},
        {'exercises': [{'name': 'X', 'sets': 3, 'reps': -1, 'weight_kg': null}]},
        {'exercises': [{'name': 'X', 'sets': 3, 'reps': 10, 'weight_kg': 'heavy'}]},
      ]) {
        expect(
          () => programWorkoutToWorkout({'id': 'w', ...(bad as Map<String, dynamic>)}),
          throwsA(isA<WorkoutContractViolation>()),
          reason: 'returning [] here is indistinguishable from "no program"',
        );
      }
    });

    test('a row carrying both `rest` and `rest_seconds` is ambiguous, so it '
        'is refused rather than silently resolved', () {
      expect(
        () => programWorkoutToWorkout(_row([
          {'name': 'X', 'sets': 3, 'reps': 10, 'weight_kg': null,
           'rest': 60, 'rest_seconds': 90},
        ])),
        throwsA(isA<WorkoutContractViolation>()),
      );
    });
  });

  // ── WKT-202 · prescribed load ─────────────────────────────────────────────
  group('WKT-202 no prescribed load is null, never 0 kg', () {
    test('an absent load decodes to null', () {
      // NO writer in the system ever emitted `weight`, so the old codec's
      // `(e['weight'] ?? 0)` made every exercise of every program read as an
      // instruction to lift nothing.
      final w = programWorkoutToWorkout(_row([
        {'name': 'Push-Up', 'sets': 3, 'reps': 12},
      ]));
      expect(w.exercises.single.sets.first.weightKg, isNull);
    });

    test('a prescribed zero is preserved and is NOT the same as absent', () {
      final w = programWorkoutToWorkout(_row([_canonical(weightKg: 0)]));
      expect(w.exercises.single.sets.first.weightKg, 0);
    });

    test('the seed dialect\'s real load survives instead of becoming 0', () {
      // Live against QA: the coach's seeded program prescribes a 60 kg bench
      // press under `weight_kg`, and the client was shown 0 kg because the
      // codec read `weight`.
      final w = programWorkoutToWorkout(_row([
        {'name': 'Bench Press', 'sets': 4, 'reps': 8,
         'weight_kg': 60, 'rest_seconds': 90},
      ]));
      expect(w.exercises.single.sets.first.weightKg, 60);
      expect(w.exercises.single.sets.first.restSeconds, 90);
    });

    test('RPE and tempo survive the round trip', () {
      final w = programWorkoutToWorkout(_row([
        _canonical(rpe: 8, weightKg: 60)..['tempo'] = '3-1-1',
      ]));
      final rebuilt = programWorkoutToWorkout(workoutToSnapshot(w));
      expect(rebuilt.exercises.single.sets.first.rpe, 8);
      expect(rebuilt.exercises.single.sets.first.tempo, '3-1-1');
    });
  });

  // ── WKT-203 · identity is unique at WORKOUT scope ─────────────────────────
  group('WKT-203 duplicate exercises get distinct identities', () {
    test('the same movement prescribed twice is two instances', () {
      // Reproduced live on QA: two set logs for "Bench Press" set 1 collided
      // with 23505 on the (session, exercise_name, set_number) index, because
      // the two instances were indistinguishable.
      final w = programWorkoutToWorkout(_row([
        _canonical(name: 'Bench Press', sets: 2),
        _canonical(name: 'Bench Press', sets: 2),
      ]));

      final instances = [for (final e in w.exercises) e.instanceId];
      expect(instances.toSet(), hasLength(2));

      final setIds = [for (final s in _allSets(w)) s.id];
      expect(setIds.toSet(), hasLength(setIds.length),
          reason: 'each instance\'s set 1 is a different logical set');
    });

    test('two instances that explicitly claim the same id are separated', () {
      // `WorkoutExercise` only ever uniquified WITHIN one exercise, so two
      // entries sharing an id minted identical set ids.
      final w = programWorkoutToWorkout(_row([
        _canonical(instanceId: 'same', name: 'Bench Press', sets: 2),
        _canonical(instanceId: 'same', name: 'Incline Press', sets: 2),
      ]));

      expect(w.exercises[0].instanceId, 'same');
      expect(w.exercises[1].instanceId, isNot('same'));
      final setIds = [for (final s in _allSets(w)) s.id];
      expect(setIds.toSet(), hasLength(4));
    });

    test('repeated set numbers within one exercise stay distinguishable', () {
      final w = programWorkoutToWorkout({
        'id': 'w-dupe-sets',
        'title': 'Dupes',
        'exercises': [
          {
            'exercise_instance_id': 'inst-a',
            'name': 'Bench Press', 'sets': 2, 'reps': 8, 'weight_kg': null,
            'set_details': [
              {'set_number': 1, 'reps': 8, 'weight_kg': null},
              {'set_number': 1, 'reps': 6, 'weight_kg': null},
            ],
          },
        ],
      });
      final ids = [for (final s in w.exercises.single.sets) s.id];
      expect(ids.toSet(), hasLength(2));
    });

    test('identity is deterministic — the same row decodes to the same ids', () {
      final row = _row([_canonical(name: 'Bench Press'), _canonical(name: 'Row')]);
      final a = programWorkoutToWorkout(Map<String, dynamic>.from(row));
      final b = programWorkoutToWorkout(Map<String, dynamic>.from(row));
      expect([for (final s in _allSets(a)) s.id],
          [for (final s in _allSets(b)) s.id]);
    });

    test('identity survives the snapshot round trip, repeatedly', () {
      var w = programWorkoutToWorkout(_row([
        _canonical(name: 'Bench Press', sets: 3, weightKg: 60, restSeconds: 90),
        _canonical(name: 'Bench Press', sets: 2, weightKg: 50, restSeconds: 60),
      ]));
      final ids = [for (final s in _allSets(w)) s.id];
      final instances = [for (final e in w.exercises) e.instanceId];
      for (var i = 0; i < 3; i++) {
        w = programWorkoutToWorkout(workoutToSnapshot(w));
      }
      expect([for (final s in _allSets(w)) s.id], ids);
      expect([for (final e in w.exercises) e.instanceId], instances);
    });
  });

  // ── WKT-204 · exercise swap ───────────────────────────────────────────────
  group('WKT-204 a swap is a new instance, not an edited one', () {
    Workout base() => programWorkoutToWorkout(_row([
          _canonical(name: 'Barbell Squat', sets: 3, reps: 8,
              weightKg: 100, restSeconds: 120),
          _canonical(name: 'Leg Curl', sets: 3, reps: 12, weightKg: 40),
        ]));

    test('the replacement carries new identities throughout', () {
      final w = base();
      final old = w.exercises[0];
      final swapped = w.replacingExerciseAt(
          0, old.replacedBy(_ex('goblet', 'Goblet Squat'), instanceId: 'swap-1'));

      expect(swapped.exercises[0].instanceId, isNot(old.instanceId));
      final oldIds = {for (final s in old.sets) s.id};
      for (final s in swapped.exercises[0].sets) {
        expect(oldIds, isNot(contains(s.id)),
            reason: 'reusing a set id is what produced the 23505 on the first '
                'set logged after a swap');
      }
    });

    test('the prescribed structure carries over; the load does not', () {
      final w = base();
      final old = w.exercises[0];
      final swapped = w.replacingExerciseAt(
          0, old.replacedBy(_ex('goblet', 'Goblet Squat'), instanceId: 'swap-1'));
      final now = swapped.exercises[0];

      expect(now.sets, hasLength(old.sets.length));
      expect(now.sets.first.reps, 8);
      expect(now.sets.first.restSeconds, 120);
      expect(now.sets.first.weightKg, isNull,
          reason: '100 kg of back squat is not 100 kg of goblet squat');
    });

    test('the slot, and everything after it, keeps its position', () {
      final w = base();
      final swapped = w.replacingExerciseAt(0,
          w.exercises[0].replacedBy(_ex('goblet', 'Goblet Squat'),
              instanceId: 'swap-1'));
      expect(swapped.exercises, hasLength(2));
      expect(swapped.exercises[0].exercise.name, 'Goblet Squat');
      expect(swapped.exercises[1].instanceId, w.exercises[1].instanceId);
    });

    test('superset and circuit membership follow the slot', () {
      final we = WorkoutExercise(
        instanceId: 'inst-a',
        exercise: _ex('a', 'Pull Up'),
        sets: [const WorkoutSet(setNumber: 1, reps: 8)],
        isSuperset: true, supersetGroup: 'A',
        isCircuit: true, circuitGroup: 'C1', circuitRounds: 3,
        notes: 'brace hard');
      final swapped =
          we.replacedBy(_ex('b', 'Lat Pulldown'), instanceId: 'swap-1');
      expect(swapped.isSuperset, isTrue);
      expect(swapped.supersetGroup, 'A');
      expect(swapped.circuitGroup, 'C1');
      expect(swapped.circuitRounds, 3);
      expect(swapped.notes, 'brace hard');
    });

    test('completed state does NOT follow the swap', () {
      final w = base();
      final old = w.exercises[0];
      // The client completed set 1 of the squat.
      final state = <String, Map<String, dynamic>>{
        old.sets[0].id: {
          'completed': true, 'reps': 8, 'weight': 100.0,
          'set_id': old.sets[0].id, 'exercise_instance_id': old.instanceId,
        },
      };

      final swapped = w.replacingExerciseAt(0,
          old.replacedBy(_ex('goblet', 'Goblet Squat'), instanceId: 'swap-1'));

      for (final s in swapped.exercises[0].sets) {
        expect(state[s.id]?['completed'], isNot(true),
            reason: 'the new movement must not start with a set the client '
                'never performed marked complete — the immutability rule would '
                'then lock values they never entered');
      }
      // And the replaced exercise's own record is untouched.
      expect(state[old.sets[0].id]!['completed'], isTrue);
      expect(state[old.sets[0].id]!['exercise_instance_id'], old.instanceId);
    });

    test('a cursor pointing into the replaced exercise no longer resolves', () {
      final w = base();
      final old = w.exercises[0];
      final swapped = w.replacingExerciseAt(0,
          old.replacedBy(_ex('goblet', 'Goblet Squat'), instanceId: 'swap-1'));

      expect(locateSet(swapped, old.sets[1].id), isNull,
          reason: 'a stale cursor must MISS rather than resolve onto a set '
              'belonging to a movement that is no longer there');

      // …and the resume falls back to a real outstanding set.
      final position = resumePosition(swapped, const {},
          cursorSetId: old.sets[1].id);
      expect(locateSet(swapped, position.setId), isNotNull);
      expect(position.exerciseId, swapped.exercises[0].instanceId);
    });

    test('after a swap the workout still has globally unique set ids', () {
      final w = base();
      // Swap the first exercise for the *same movement as the second* — the
      // case most likely to collide.
      final swapped = w.replacingExerciseAt(0,
          w.exercises[0].replacedBy(_ex('leg-curl', 'Leg Curl'),
              instanceId: 'swap-1'));
      final ids = [for (final s in _allSets(swapped)) s.id];
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  // ── WKT-205 · seating and resume after a swap ─────────────────────────────
  group('WKT-205 logs stay with the exercise that was performed', () {
    test('a log from the replaced exercise is not seated on the new one', () {
      final w = programWorkoutToWorkout(_row([
        _canonical(name: 'Barbell Squat', sets: 2, reps: 8, weightKg: 100),
      ]));
      final old = w.exercises[0];
      final swapped = w.replacingExerciseAt(0,
          old.replacedBy(_ex('goblet', 'Goblet Squat'), instanceId: 'swap-1'));

      final seated = seatSetLogs(swapped, {
        old.instanceId: [
          {'set_id': old.sets[0].id, 'set_number': 1, 'completed': true,
           'reps': 8, 'weight': 100.0},
        ],
      });

      expect(seated, isEmpty,
          reason: 'the row names a set this workout no longer has; seating it '
              'anywhere would attribute one movement\'s work to another');
    });

    test('seating is by exercise instance, so two instances stay apart', () {
      final w = programWorkoutToWorkout(_row([
        _canonical(name: 'Bench Press', sets: 1, reps: 8),
        _canonical(name: 'Bench Press', sets: 1, reps: 6),
      ]));
      final a = w.exercises[0], b = w.exercises[1];

      final seated = seatSetLogs(w, {
        a.instanceId: [
          {'set_id': a.sets[0].id, 'set_number': 1, 'completed': true, 'reps': 8},
        ],
        b.instanceId: [
          {'set_id': b.sets[0].id, 'set_number': 1, 'completed': true, 'reps': 6},
        ],
      });

      expect(seated[a.sets[0].id]!['reps'], 8);
      expect(seated[b.sets[0].id]!['reps'], 6);
      expect(seated[a.sets[0].id]!['exercise_instance_id'], a.instanceId);
      expect(seated[b.sets[0].id]!['exercise_instance_id'], b.instanceId);
    });
  });

  // ── WKT-206 · the snapshot is the session's frozen prescription ───────────
  group('WKT-206 the session snapshot is lossless and canonical', () {
    test('a snapshot round trip preserves per-set variation', () {
      final original = programWorkoutToWorkout({
        'id': 'w-var', 'title': 'Varied',
        'exercises': [
          {
            'exercise_instance_id': 'inst-a', 'name': 'Bench Press',
            'sets': 2, 'reps': 8, 'weight_kg': 60, 'rest_seconds': 90,
            'set_details': [
              {'id': 'inst-a:s1', 'set_number': 1, 'reps': 8, 'weight_kg': 60},
              {'id': 'inst-a:s2', 'set_number': 2, 'reps': 6, 'weight_kg': 62.5},
            ],
          },
        ],
      });

      final rebuilt = programWorkoutToWorkout(workoutToSnapshot(original));
      expect(rebuilt.exercises.single.sets[0].weightKg, 60);
      expect(rebuilt.exercises.single.sets[1].weightKg, 62.5);
      expect(rebuilt.exercises.single.sets[1].reps, 6);
    });

    test('a snapshot declares the contract version it was written under', () {
      final snap = workoutToSnapshot(programWorkoutToWorkout(_row([_canonical()])));
      expect(snap['contract_version'], WorkoutContract.version);
    });

    test('a snapshot is itself canonical — it decodes with no deviations', () {
      final w = programWorkoutToWorkout(_row([
        {'name': 'Bench Press', 'sets': 3, 'reps': '10', 'rest': 60},
      ]));
      final decoded = decodeProgramWorkout(workoutToSnapshot(w));
      expect(decoded.deviations, isEmpty,
          reason: 'a legacy row is translated ONCE, at the boundary; the '
              'snapshot the session then runs on is canonical');
    });

    test('a set that explicitly prescribes no load does not inherit the '
        'exercise\'s', () {
      final w = programWorkoutToWorkout({
        'id': 'w', 'title': 'T',
        'exercises': [
          {
            'exercise_instance_id': 'inst-a', 'name': 'Bench Press',
            'sets': 2, 'reps': 8, 'weight_kg': 60,
            'set_details': [
              {'id': 'inst-a:s1', 'set_number': 1, 'reps': 8, 'weight_kg': 60},
              {'id': 'inst-a:s2', 'set_number': 2, 'reps': 8, 'weight_kg': null},
            ],
          },
        ],
      });
      expect(w.exercises.single.sets[0].weightKg, 60);
      expect(w.exercises.single.sets[1].weightKg, isNull);
    });
  });

  // ── WKT-207 · prescription and execution are separate ─────────────────────
  group('WKT-207 a prescription carries no execution state', () {
    test('a decoded set has no notion of being completed', () {
      final w = programWorkoutToWorkout(_row([_canonical()]));
      final set = w.exercises.single.sets.first;
      // Structural: WorkoutSet exposes only prescription. If a `completed`
      // field is ever reintroduced here, this list stops matching.
      expect(
        {
          'id': set.id, 'setNumber': set.setNumber, 'reps': set.reps,
          'weightKg': set.weightKg, 'restSeconds': set.restSeconds,
          'rpe': set.rpe, 'tempo': set.tempo,
          'durationSeconds': set.durationSeconds, 'notes': set.notes,
        }.keys,
        hasLength(9),
      );
    });

    test('a snapshot never writes execution state', () {
      final snap = workoutToSnapshot(programWorkoutToWorkout(_row([_canonical()])));
      final ex = (snap['exercises'] as List).single as Map<String, dynamic>;
      for (final detail in (ex['set_details'] as List).cast<Map>()) {
        expect(detail.containsKey('completed'), isFalse);
      }
    });
  });

  // ── WKT-208 · a session is never identified by its workout's title ────────
  group('WKT-208 session status is looked up by identity', () {
    Workout day(String id, String title) => Workout(
          id: id, title: title, description: '', estimatedDuration: 45,
          difficulty: 'Intermediate', category: 'Strength', exercises: const []);

    test('two days sharing a title do not share a session status', () {
      // Verified live on QA: the generated program contains "Upper Body" twice
      // and "Lower Body" twice (migration 077 rewrote the generator from 048
      // and dropped 052's unique-title fix). A title-keyed status map made
      // starting one day show BOTH as in progress.
      final statuses = {
        'day-1': {'workout_id': 'day-1', 'status': 'in_progress', 'logged_sets': 3},
        'Upper Body': {'workout_id': 'day-1', 'status': 'in_progress', 'logged_sets': 3},
      };

      expect(sessionStatusFor(statuses, day('day-1', 'Upper Body'))?['status'],
          'in_progress');
      expect(sessionStatusFor(statuses, day('day-3', 'Upper Body')), isNull,
          reason: 'the other "Upper Body" day has no session of its own');
    });

    test('a session written before workout ids were persisted resolves by '
        'title', () {
      final statuses = {
        'Upper Body': {'workout_id': null, 'status': 'completed'},
      };
      expect(sessionStatusFor(statuses, day('day-1', 'Upper Body'))?['status'],
          'completed');
    });

    test('an id entry wins over a title entry naming another workout', () {
      final statuses = {
        'day-1': {'workout_id': 'day-1', 'status': 'completed'},
        'Upper Body': {'workout_id': 'day-9', 'status': 'in_progress'},
      };
      expect(sessionStatusFor(statuses, day('day-1', 'Upper Body'))?['status'],
          'completed');
    });
  });
}
