import 'models/exercise_model.dart';
import 'models/workout_model.dart';
import 'workout_contract.dart';

/// Conversion between a [Workout] and the canonical JSON of
/// `docs/WORKOUT_DOMAIN_CONTRACT.md` — the shape used by `program_workouts`
/// rows and by `workout_sessions.workout_snapshot`.
///
/// One codec serves both so a session snapshot and a coach-authored program
/// workout deserialize through exactly the same path. [workoutToSnapshot] is
/// lossless: it writes a `set_details` list alongside the exercise-level
/// summary, so a workout with per-set variation survives a round trip while a
/// `program_workouts` row (which has no `set_details`) keeps deserializing from
/// the summary.
///
/// Two things this codec will not do, both of them defects it was rewritten to
/// end:
///
///  * it does not guess. A value outside the canonical contract raises
///    [WorkoutContractViolation] naming the field — it is never replaced by a
///    plausible default. A fabricated `reps: 10` or `weight: 0` is a
///    prescription no coach wrote.
///  * it does not lose identity. Every exercise instance and every set is
///    written with its id and read back verbatim, so the entities a client was
///    working on survive a refresh. Ids are *minted* only where the source has
///    none — a row authored before ids existed — and a snapshot taken at
///    session start freezes that mint.

/// Rebuilds a [Workout] from a `program_workouts` row or a session snapshot.
///
/// Throws [WorkoutContractViolation] if the row is not canonical and cannot be
/// unambiguously read as canonical. Callers must surface that: converting it
/// into an empty workout is indistinguishable from "you have no program".
Workout programWorkoutToWorkout(Map<String, dynamic> w) =>
    decodeProgramWorkout(w).workout;

/// A decoded workout together with the legacy dialects that had to be
/// translated to read it.
///
/// The deviations are the migration signal: an empty list means every writer
/// that touched this row is emitting the canonical contract.
class DecodedWorkout {
  final Workout workout;
  final List<ContractDeviation> deviations;
  const DecodedWorkout(this.workout, this.deviations);
}

DecodedWorkout decodeProgramWorkout(Map<String, dynamic> w) {
  final workoutId = (w['id'] as String?) ?? '';
  final title = (w['title'] as String?) ?? 'Workout';
  final location = 'workout "${workoutId.isEmpty ? title : workoutId}"';

  final normalized =
      WorkoutContract.normalizeExercises(w['exercises'], workoutLocation: location);

  // Instance ids the row already carries are claimed first, so a mint for an
  // un-identified exercise can never collide with one that is identified.
  final taken = <String>{
    for (final e in normalized.exercises)
      if (WorkoutContract.optionalText(e, WorkoutContract.kInstanceId)
          case final id?)
        id,
  };

  final exercises = <WorkoutExercise>[];
  for (var i = 0; i < normalized.exercises.length; i++) {
    final e = normalized.exercises[i];
    final name = WorkoutContract.requireText(e, WorkoutContract.kName,
        location: '$location · exercise $i');
    final where = '$location · exercise $i "$name"';

    final instanceId =
        WorkoutContract.optionalText(e, WorkoutContract.kInstanceId) ??
            _mintInstanceId(name, i, taken);

    final sets = WorkoutContract.requireInt(e, WorkoutContract.kSets,
        location: where, min: 1);
    final reps = WorkoutContract.requireInt(e, WorkoutContract.kReps,
        location: where, min: 0);
    final weightKg = WorkoutContract.optionalNum(e, WorkoutContract.kWeightKg,
        location: where, min: 0);
    final rest = WorkoutContract.optionalInt(e, WorkoutContract.kRestSeconds,
        location: where, min: 0);
    final rpe = WorkoutContract.optionalNum(e, WorkoutContract.kRpe,
        location: where, min: 1, max: 10);
    final duration = WorkoutContract.optionalInt(
        e, WorkoutContract.kDurationSeconds,
        location: where, min: 1);
    final tempo = WorkoutContract.optionalText(e, WorkoutContract.kTempo);

    // Per-set detail is authoritative when the source carries it (session
    // snapshots); otherwise the sets are expanded from the summary
    // (`program_workouts` rows).
    final details = e[WorkoutContract.kSetDetails] as List?;
    final workoutSets = details != null
        ? [
            for (var s = 0; s < details.length; s++)
              _decodeSet(
                Map<String, dynamic>.from(details[s] as Map),
                index: s,
                instanceId: instanceId,
                location: '$where · set $s',
                fallbackReps: reps,
                fallbackWeightKg: weightKg,
                fallbackRest: rest,
                fallbackRpe: rpe,
                fallbackTempo: tempo,
                fallbackDuration: duration,
              ),
          ]
        : [
            for (var si = 0; si < sets; si++)
              WorkoutSet(
                id: WorkoutSet.mintId(instanceId, si + 1),
                setNumber: si + 1,
                reps: reps,
                weightKg: weightKg,
                restSeconds: rest,
                rpe: rpe,
                tempo: tempo,
                durationSeconds: duration,
              ),
          ];

    exercises.add(WorkoutExercise(
      instanceId: instanceId,
      exercise: Exercise(
        id: WorkoutContract.optionalText(e, WorkoutContract.kExerciseId) ??
            instanceId,
        name: name,
        category: (e['category'] as String?) ?? 'Strength',
        muscleGroup: (e['muscle_group'] as String?) ?? '',
        equipment: (e['equipment'] as String?) ?? '',
        difficulty: (e['difficulty'] as String?) ?? 'Intermediate',
        description: (e['description'] as String?) ?? '',
        instructions: List<String>.from(e['instructions'] as List? ?? []),
      ),
      sets: workoutSets,
      isSuperset: e['is_superset'] == true,
      supersetGroup: WorkoutContract.optionalText(e, 'superset_group'),
      isCircuit: e['is_circuit'] == true,
      circuitGroup: WorkoutContract.optionalText(e, 'circuit_group'),
      circuitRounds: WorkoutContract.optionalInt(e, 'circuit_rounds',
              location: where, min: 1) ??
          1,
      notes: WorkoutContract.optionalText(e, WorkoutContract.kNotes),
    ));
  }

  return DecodedWorkout(
    Workout(
      id: workoutId,
      title: title,
      description: (w['description'] as String?) ?? '',
      estimatedDuration: (w['estimated_minutes'] as num?)?.toInt() ?? 45,
      difficulty: (w['difficulty'] as String?) ?? 'Intermediate',
      category: (w['category'] as String?) ?? 'Strength',
      exercises: exercises,
      coachId: w['coach_id'] as String?,
      coachName: (w['coach_name'] as String?) ?? 'Your Coach',
    ),
    normalized.deviations,
  );
}

WorkoutSet _decodeSet(
  Map<String, dynamic> s, {
  required int index,
  required String instanceId,
  required String location,
  required int fallbackReps,
  required double? fallbackWeightKg,
  required int? fallbackRest,
  required double? fallbackRpe,
  required String? fallbackTempo,
  required int? fallbackDuration,
}) {
  final setNumber =
      WorkoutContract.optionalInt(s, WorkoutContract.kSetNumber,
              location: location, min: 1) ??
          index + 1;
  return WorkoutSet(
    // The stored id wins. Only a snapshot written before set ids existed
    // reaches the mint, and it mints the same id the live workout would have,
    // so its logs still find their sets.
    id: WorkoutContract.optionalText(s, WorkoutContract.kSetId) ??
        WorkoutSet.mintId(instanceId, setNumber),
    setNumber: setNumber,
    reps: WorkoutContract.optionalInt(s, WorkoutContract.kReps,
            location: location, min: 0) ??
        fallbackReps,
    // `containsKey` rather than `?? fallback`: a set that explicitly prescribes
    // null load means "no load for this set", which is not the same as saying
    // nothing and inheriting the exercise's.
    weightKg: s.containsKey(WorkoutContract.kWeightKg) &&
            s[WorkoutContract.kWeightKg] != null
        ? WorkoutContract.optionalNum(s, WorkoutContract.kWeightKg,
            location: location, min: 0)
        : (s.containsKey(WorkoutContract.kWeightKg) ? null : fallbackWeightKg),
    restSeconds: WorkoutContract.optionalInt(s, WorkoutContract.kRestSeconds,
            location: location, min: 0) ??
        fallbackRest,
    rpe: WorkoutContract.optionalNum(s, WorkoutContract.kRpe,
            location: location, min: 1, max: 10) ??
        fallbackRpe,
    tempo: WorkoutContract.optionalText(s, WorkoutContract.kTempo) ??
        fallbackTempo,
    durationSeconds: WorkoutContract.optionalInt(
            s, WorkoutContract.kDurationSeconds,
            location: location, min: 1) ??
        fallbackDuration,
    notes: WorkoutContract.optionalText(s, WorkoutContract.kNotes),
  );
}

/// Serializes a [Workout] into the canonical contract, for
/// `workout_sessions.workout_snapshot`.
Map<String, dynamic> workoutToSnapshot(Workout workout) => {
      'id': workout.id,
      'title': workout.title,
      'description': workout.description,
      'estimated_minutes': workout.estimatedDuration,
      'difficulty': workout.difficulty,
      'category': workout.category,
      'contract_version': WorkoutContract.version,
      if (workout.coachId != null) 'coach_id': workout.coachId,
      if (workout.coachName != null) 'coach_name': workout.coachName,
      'exercises': [
        for (final (i, we) in workout.exercises.indexed)
          {
            WorkoutContract.kInstanceId: we.instanceId,
            WorkoutContract.kExerciseId: we.exercise.id,
            WorkoutContract.kName: we.exercise.name,
            WorkoutContract.kPosition: i,
            'category': we.exercise.category,
            'muscle_group': we.exercise.muscleGroup,
            'equipment': we.exercise.equipment,
            'difficulty': we.exercise.difficulty,
            'description': we.exercise.description,
            'instructions': we.exercise.instructions,
            // Exercise-level summary, so a reader that never looks at
            // `set_details` still sees a sensible prescription.
            WorkoutContract.kSets: we.sets.isEmpty ? 1 : we.sets.length,
            WorkoutContract.kReps: we.sets.isEmpty ? 0 : we.sets.first.reps,
            WorkoutContract.kWeightKg:
                we.sets.isEmpty ? null : we.sets.first.weightKg,
            WorkoutContract.kRestSeconds:
                we.sets.isEmpty ? null : we.sets.first.restSeconds,
            WorkoutContract.kRpe: we.sets.isEmpty ? null : we.sets.first.rpe,
            WorkoutContract.kTempo:
                we.sets.isEmpty ? null : we.sets.first.tempo,
            WorkoutContract.kDurationSeconds:
                we.sets.isEmpty ? null : we.sets.first.durationSeconds,
            // Lossless per-set detail.
            WorkoutContract.kSetDetails: [
              for (final s in we.sets)
                {
                  // Written first and read back first: this is what makes the
                  // set the client left off on the same set they come back to.
                  WorkoutContract.kSetId: s.id,
                  WorkoutContract.kSetNumber: s.setNumber,
                  WorkoutContract.kReps: s.reps,
                  WorkoutContract.kWeightKg: s.weightKg,
                  WorkoutContract.kRestSeconds: s.restSeconds,
                  WorkoutContract.kRpe: s.rpe,
                  WorkoutContract.kTempo: s.tempo,
                  WorkoutContract.kDurationSeconds: s.durationSeconds,
                  WorkoutContract.kNotes: s.notes,
                },
            ],
            'is_superset': we.isSuperset,
            'superset_group': we.supersetGroup,
            'is_circuit': we.isCircuit,
            'circuit_group': we.circuitGroup,
            'circuit_rounds': we.circuitRounds,
            WorkoutContract.kNotes: we.notes,
          },
      ],
    };

/// Identity for an exercise instance a source row never gave one.
///
/// Derived from the exercise's name so re-reading the same program row mints
/// the same id even after a coach reorders the list; the position is only a
/// tie-breaker between two instances that would otherwise collide. Once a
/// session snapshots the workout, this id is stored and never minted again.
String _mintInstanceId(String name, int index, Set<String> taken) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final base = slug.isEmpty ? 'ex-${index + 1}' : 'ex-$slug';
  return WorkoutExercise.uniqueId(base, taken);
}
