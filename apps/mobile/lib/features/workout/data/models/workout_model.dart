import 'exercise_model.dart';

/// One prescribed set: what the client is being asked to do.
///
/// Prescription only. There is no `completed` flag and no logged result here —
/// what actually happened lives in `workout_set_logs`, attached by [id]. Mixing
/// the two is what let a resumed workout show sets as finished that had only
/// been typed into, and what let a swapped-in exercise inherit another
/// movement's completion state.
class WorkoutSet {
  /// Stable identity for this set, unique within its **workout**.
  ///
  /// This — not the set's position in a list, and not its ordinal — is what
  /// logged results are attached to and what a resumed session looks a set up
  /// by. It is assigned once (see [WorkoutExercise] and [Workout]) and then
  /// carried through the session snapshot and `workout_set_logs.set_id`, so the
  /// set a client filled in before navigating away is the same logical set
  /// afterwards even if the surrounding list is reordered, grown, or partially
  /// loaded.
  ///
  /// Empty only for a set built outside a [WorkoutExercise]; putting it in one
  /// assigns an id.
  final String id;

  /// The set's place in its exercise, as authored: "Set 3". Display and sort
  /// order, never identity — two workouts both have a "Set 3".
  final int setNumber;
  final int reps;

  /// Prescribed load in kilograms, or null when nothing prescribes one.
  ///
  /// Null and zero are different answers. Null is "no load prescribed" and the
  /// client shows an absence; zero is a prescribed zero (bodyweight). Every
  /// pre-contract writer omitted load entirely and the codec read that as
  /// `0.0`, so every exercise of every program told the client to lift nothing.
  final double? weightKg;

  final int? restSeconds;
  final double? rpe;
  final String? tempo;

  /// Prescribed work duration for timed movements (plank, carry), or null.
  final int? durationSeconds;

  final String? notes;

  const WorkoutSet({
    String? id,
    required this.setNumber,
    required this.reps,
    this.weightKg,
    this.restSeconds,
    this.rpe,
    this.tempo,
    this.durationSeconds,
    this.notes,
  }) : id = id ?? '';

  /// The same set under an assigned identity.
  WorkoutSet withId(String id) => WorkoutSet(
        id: id,
        setNumber: setNumber,
        reps: reps,
        weightKg: weightKg,
        restSeconds: restSeconds,
        rpe: rpe,
        tempo: tempo,
        durationSeconds: durationSeconds,
        notes: notes,
      );

  /// This set's prescribed *structure*, stripped of everything that belongs to
  /// the movement it was prescribed for.
  ///
  /// Used when an exercise is swapped: the client keeps their sets, reps, rest
  /// and tempo, but not the identity, and not the load — 100 kg of back squat
  /// is not 100 kg of goblet squat, and carrying it across would prescribe a
  /// weight no one chose. Per-set notes go too; they are commentary on the
  /// movement being replaced.
  WorkoutSet asStructureForNewMovement() => WorkoutSet(
        setNumber: setNumber,
        reps: reps,
        restSeconds: restSeconds,
        rpe: rpe,
        tempo: tempo,
        durationSeconds: durationSeconds,
      );

  /// The id minted for an un-identified set.
  ///
  /// Derived from the exercise *instance* it belongs to and its authored set
  /// number — both durable — rather than from its index, so re-reading the same
  /// definition mints the same id and the same set keeps its logs. Minting
  /// happens once, when a workout is built; retrieval reads the stored id.
  static String mintId(String instanceId, int setNumber) =>
      '$instanceId:s$setNumber';
}

/// One prescribed exercise *instance* — one slot in a workout.
///
/// [instanceId] is the identity; [exercise] is a reference to the library entry
/// the slot currently points at. They are deliberately different things: a
/// workout may legitimately contain the same movement twice (two instances, one
/// library exercise), and swapping a movement replaces the library reference
/// while creating a *new* instance.
class WorkoutExercise {
  /// Identity of this slot in the workout. Immutable for the life of the
  /// instance; a swap mints a new one.
  final String instanceId;

  /// The library movement this instance currently prescribes.
  final Exercise exercise;

  /// The exercise's sets in authored order, every one of them carrying an id.
  final List<WorkoutSet> sets;

  final bool isSuperset;
  final String? supersetGroup;
  final bool isCircuit;
  final String? circuitGroup;
  final int circuitRounds;
  final String? notes;

  WorkoutExercise({
    String? instanceId,
    required this.exercise,
    required List<WorkoutSet> sets,
    this.isSuperset = false,
    this.supersetGroup,
    this.isCircuit = false,
    this.circuitGroup,
    this.circuitRounds = 1,
    this.notes,
  })  : instanceId =
            (instanceId != null && instanceId.isNotEmpty) ? instanceId : exercise.id,
        sets = _identify(
            (instanceId != null && instanceId.isNotEmpty)
                ? instanceId
                : exercise.id,
            sets);

  /// Guarantees every set has an id, so no caller downstream has to fall back
  /// to a list index to say which set it means.
  ///
  /// A set that already carries one keeps it — ids restored from a snapshot are
  /// authoritative and must survive the round trip. The rest are minted from
  /// the instance and the set number; a workout that repeats a set number gets
  /// a suffix rather than two sets sharing an identity. Uniqueness *across* the
  /// whole workout is finished by [Workout].
  static List<WorkoutSet> _identify(String instanceId, List<WorkoutSet> sets) {
    final taken = <String>{for (final s in sets) if (s.id.isNotEmpty) s.id};
    return [
      for (final s in sets)
        if (s.id.isNotEmpty)
          s
        else
          s.withId(uniqueId(WorkoutSet.mintId(instanceId, s.setNumber), taken)),
    ];
  }

  /// [candidate] if free, else `candidate-2`, `candidate-3`… Registers the
  /// result in [taken].
  static String uniqueId(String candidate, Set<String> taken) {
    var id = candidate;
    for (var n = 2; !taken.add(id); n++) {
      id = '$candidate-$n';
    }
    return id;
  }

  /// The set with this id, or null when it does not belong to this exercise.
  WorkoutSet? setById(String setId) {
    for (final s in sets) {
      if (s.id == setId) return s;
    }
    return null;
  }

  /// This slot, filled by a different movement.
  ///
  /// The replacement is a **new instance**: a fresh [instanceId] and, because
  /// the sets are rebuilt without ids, a fresh identity for every set. That is
  /// what stops the new movement inheriting the replaced one's completion
  /// state, and what stops its first logged set colliding with a row already
  /// written under the old set's identity.
  ///
  /// Carried over: the position (the caller puts it back in the same slot), the
  /// prescribed structure (sets, reps, rest, RPE, tempo, duration), superset and
  /// circuit membership, and the exercise-level coaching note. Not carried: any
  /// identity, any load, and any per-set note.
  WorkoutExercise replacedBy(Exercise replacement, {required String instanceId}) =>
      WorkoutExercise(
        instanceId: instanceId,
        exercise: replacement,
        sets: [for (final s in sets) s.asStructureForNewMovement()],
        isSuperset: isSuperset,
        supersetGroup: supersetGroup,
        isCircuit: isCircuit,
        circuitGroup: circuitGroup,
        circuitRounds: circuitRounds,
        notes: notes,
      );

  /// The same instance under a different identity, used when a workout finds
  /// two slots claiming the same one.
  WorkoutExercise withInstanceId(String newInstanceId) => WorkoutExercise(
        instanceId: newInstanceId,
        exercise: exercise,
        sets: sets,
        isSuperset: isSuperset,
        supersetGroup: supersetGroup,
        isCircuit: isCircuit,
        circuitGroup: circuitGroup,
        circuitRounds: circuitRounds,
        notes: notes,
      );

  /// The same instance with these sets.
  WorkoutExercise withSets(List<WorkoutSet> replacement) => WorkoutExercise(
        instanceId: instanceId,
        exercise: exercise,
        sets: replacement,
        isSuperset: isSuperset,
        supersetGroup: supersetGroup,
        isCircuit: isCircuit,
        circuitGroup: circuitGroup,
        circuitRounds: circuitRounds,
        notes: notes,
      );
}

class Workout {
  final String id;
  final String title;
  final String description;
  final int estimatedDuration;
  final String difficulty;
  final String category;

  /// The workout's exercise instances in prescribed order. Every instance id
  /// and every set id in here is unique **across the whole workout**.
  final List<WorkoutExercise> exercises;

  final String? coachId;
  final String? coachName;
  final bool isCompleted;
  final DateTime? scheduledDate;

  Workout({
    required this.id,
    required this.title,
    required this.description,
    required this.estimatedDuration,
    required this.difficulty,
    required this.category,
    required List<WorkoutExercise> exercises,
    this.coachId,
    this.coachName,
    this.isCompleted = false,
    this.scheduledDate,
  }) : exercises = _uniquifyAcrossWorkout(exercises);

  /// Makes instance and set identity unique at **workout** scope.
  ///
  /// Uniquifying within one exercise is not enough: two slots prescribing the
  /// same movement carry the same `exercise.id`, mint the same instance id, and
  /// therefore mint the same set ids — so one block's set 1 and the other's are
  /// the same logical set, and each overwrites the other's log.
  ///
  /// The first occurrence keeps what it has, so ids restored from storage are
  /// never disturbed; only a genuine collision is renamed, deterministically, so
  /// re-reading the same rows produces the same answer.
  static List<WorkoutExercise> _uniquifyAcrossWorkout(
      List<WorkoutExercise> exercises) {
    final takenInstances = <String>{};
    final takenSets = <String>{};
    final out = <WorkoutExercise>[];

    for (final we in exercises) {
      final instanceId =
          WorkoutExercise.uniqueId(we.instanceId, takenInstances);
      var resolved = instanceId == we.instanceId ? we : we.withInstanceId(instanceId);

      // Sets are checked against every id already handed out in this workout,
      // not just this exercise's own.
      final sets = <WorkoutSet>[];
      var changed = false;
      for (final s in resolved.sets) {
        if (takenSets.add(s.id)) {
          sets.add(s);
          continue;
        }
        final fresh = WorkoutExercise.uniqueId(
            WorkoutSet.mintId(instanceId, s.setNumber), takenSets);
        sets.add(s.withId(fresh));
        changed = true;
      }
      if (changed) resolved = resolved.withSets(sets);
      out.add(resolved);
    }
    return out;
  }

  /// This workout with [replacement] in slot [index].
  ///
  /// The one place a swap is performed, so the identity rules in
  /// [WorkoutExercise.replacedBy] cannot be bypassed by a caller assembling the
  /// list by hand.
  Workout replacingExerciseAt(int index, WorkoutExercise replacement) {
    final list = List<WorkoutExercise>.from(exercises);
    list[index] = replacement;
    return Workout(
      id: id,
      title: title,
      description: description,
      estimatedDuration: estimatedDuration,
      difficulty: difficulty,
      category: category,
      exercises: list,
      coachId: coachId,
      coachName: coachName,
      isCompleted: isCompleted,
      scheduledDate: scheduledDate,
    );
  }
}

class WorkoutProgram {
  final String id;
  final String title;
  final String description;
  final int durationWeeks;
  final int daysPerWeek;
  final String difficulty;
  final List<Workout> workouts;
  final String? coachId;
  final String? coachName;

  WorkoutProgram({
    required this.id,
    required this.title,
    required this.description,
    required this.durationWeeks,
    required this.daysPerWeek,
    required this.difficulty,
    required this.workouts,
    this.coachId,
    this.coachName,
  });
}
