import '../data/models/workout_model.dart';
import '../data/workout_session_store.dart';
import 'workout_session_manager.dart';

/// Rebuilding an active workout session from storage.
///
/// In-memory state does not survive a browser refresh, so "which workout is the
/// client doing, and where in it are they" has to be answerable from the
/// database alone. This file is that answer: one place that reads the
/// authoritative session, rebuilds its workout, attaches the logged sets to the
/// sets they belong to *by identity*, and resolves the position to resume at.
///
/// Identity is the rule everything here follows. A [WorkoutSet] carries an id;
/// a logged row carries the id of the set it recorded; the two are matched on
/// that id. Nothing is attached by arrival order, nothing is renumbered, and no
/// list is reversed to compensate — a row that names no set the workout has is
/// left alone rather than pushed onto whichever slot is free.
///
/// Everything here is deterministic and free of Flutter/Supabase, so the rules
/// the app restores by are the rules the tests exercise.

/// A restore that could not be completed. Distinct from "there is no active
/// session": the session exists and must not be discarded, so the UI shows a
/// recovery state instead of an empty one.
class WorkoutRestorationFailure implements Exception {
  final String message;
  final Object? cause;
  const WorkoutRestorationFailure(this.message, [this.cause]);
  @override
  String toString() => 'WorkoutRestorationFailure: $message';
}

/// The exercise/set the client should land on when a session is restored.
///
/// Both the identities and the indices are carried: the ids are what the state
/// and the database agree on, the indices are only how far to scroll.
class WorkoutPosition {
  /// Identity of the exercise to resume on.
  final String exerciseId;

  /// Identity of the set to resume on — the authoritative answer to "which
  /// set", independent of where that set currently sits in a list.
  final String setId;

  /// Index into [Workout.exercises], for scrolling.
  final int exerciseIndex;

  /// Index into that exercise's `sets`, for scrolling.
  final int setIndex;

  /// True when every set in the workout is already completed; the ids and
  /// indices then point at the last set rather than at work remaining.
  final bool isComplete;

  const WorkoutPosition({
    required this.exerciseId,
    required this.setId,
    required this.exerciseIndex,
    required this.setIndex,
    this.isComplete = false,
  });

  /// The position of a workout with nothing in it to do.
  static const empty = WorkoutPosition(
    exerciseId: '',
    setId: '',
    exerciseIndex: 0,
    setIndex: 0,
    isComplete: true,
  );

  @override
  bool operator ==(Object other) =>
      other is WorkoutPosition &&
      other.exerciseId == exerciseId &&
      other.setId == setId &&
      other.exerciseIndex == exerciseIndex &&
      other.setIndex == setIndex &&
      other.isComplete == isComplete;

  @override
  int get hashCode =>
      Object.hash(exerciseId, setId, exerciseIndex, setIndex, isComplete);

  @override
  String toString() => 'WorkoutPosition($exerciseId / $setId '
      '@ $exerciseIndex.$setIndex, complete: $isComplete)';
}

/// Where a set sits in a workout, found by its id.
class WorkoutSetLocation {
  final WorkoutExercise exercise;
  final WorkoutSet set;
  final int exerciseIndex;
  final int setIndex;
  const WorkoutSetLocation(
      this.exercise, this.set, this.exerciseIndex, this.setIndex);
}

/// Finds the set with [setId], or null when the workout has no such set.
///
/// The one lookup the app uses to turn a stored identity back into a concrete
/// set, so a set id that no longer exists (an exercise swapped out mid-session)
/// is a clean miss rather than a wrong answer.
WorkoutSetLocation? locateSet(Workout workout, String setId) {
  if (setId.isEmpty) return null;
  for (var e = 0; e < workout.exercises.length; e++) {
    final sets = workout.exercises[e].sets;
    for (var s = 0; s < sets.length; s++) {
      if (sets[s].id == setId) {
        return WorkoutSetLocation(workout.exercises[e], sets[s], e, s);
      }
    }
  }
  return null;
}

/// Attaches logged set rows to the sets they belong to, keyed by set id.
///
/// [logs] arrives grouped by whatever the log row called its exercise
/// (`exercise_instance_id`, else `exercise_id`, else the name for older rows)
/// and in no guaranteed order. Each
/// row is matched to a set in [workout]:
///
///  1. by `set_id`, the identity written with the row — the only match that is
///     immune to reordering, renumbering and partial loads;
///  2. failing that (rows written before set ids existed) by the row's own
///     `set_number` within the exercise it names, which is a stored ordinal,
///     not a list position.
///
/// Arrival order is never consulted. A row naming a set this workout does not
/// have is skipped rather than seated on the next free slot: the workout is
/// authoritative about which sets exist, and inventing a home for an orphan row
/// is what shifts every later set. The row itself is untouched in the database.
///
/// Each returned entry carries `set_id`, `exercise_instance_id` and
/// `set_number`, so a
/// consumer holding one set's state never has to ask where it came from.
Map<String, Map<String, dynamic>> seatSetLogs(
  Workout workout,
  Map<String, List<Map<String, dynamic>>> logs,
) {
  // Both keys point at the same exercise: rows carry an id when they have one
  // and fall back to the name, and a session predating exercise ids only ever
  // wrote the name.
  final byExerciseKey = <String, WorkoutExercise>{};
  for (final we in workout.exercises) {
    // Instance first — it is the identity. The library id and the name are
    // fallbacks for rows written before instances existed, and are registered
    // with putIfAbsent so a later instance can never steal an earlier one's key.
    byExerciseKey[we.instanceId] = we;
    byExerciseKey.putIfAbsent(we.exercise.id, () => we);
    byExerciseKey.putIfAbsent(we.exercise.name, () => we);
  }

  final seated = <String, Map<String, dynamic>>{};
  for (final entry in logs.entries) {
    final exercise = byExerciseKey[entry.key];
    for (final log in entry.value) {
      final set = _matchSet(workout, exercise, log);
      if (set == null) continue;
      seated[set.id] = {
        ...?seated[set.id],
        ...log,
        'set_id': set.id,
        'set_number': set.setNumber,
        if (exercise != null) 'exercise_instance_id': exercise.instanceId,
      };
    }
  }
  return seated;
}

/// The set a logged row recorded: by its stored id, else by its stored set
/// number within the exercise it names. Never by where it arrived in the list.
WorkoutSet? _matchSet(
  Workout workout,
  WorkoutExercise? exercise,
  Map<String, dynamic> log,
) {
  final setId = log['set_id']?.toString();
  if (setId != null && setId.isNotEmpty) {
    final located = locateSet(workout, setId);
    if (located != null) return located.set;
  }
  final number = (log['set_number'] as num?)?.toInt();
  if (exercise == null || number == null) return null;
  for (final s in exercise.sets) {
    if (s.setNumber == number) return s;
  }
  return null;
}

/// The set the client should resume on.
///
/// The session's own cursor is the authority when it still names a set that
/// exists and is outstanding — that is the position the client actually left,
/// which is not always the earliest unfinished set (they may have skipped ahead
/// to a later set deliberately). It is only ignored when it has gone stale: the
/// set was swapped out of the workout, or it has since been completed.
///
/// The fallback is derived by walking [Workout.exercises] and each exercise's
/// sets in authored order and taking the first outstanding one. Deriving rather
/// than trusting a stale number means a resumed workout can never disagree with
/// the sets it is showing. Nothing here sorts, reverses or renumbers.
WorkoutPosition resumePosition(
  Workout workout,
  Map<String, Map<String, dynamic>> setState, {
  String? cursorSetId,
}) {
  final cursor = locateSet(workout, cursorSetId ?? '');
  if (cursor != null && setState[cursor.set.id]?['completed'] != true) {
    return WorkoutPosition(
      exerciseId: cursor.exercise.instanceId,
      setId: cursor.set.id,
      exerciseIndex: cursor.exerciseIndex,
      setIndex: cursor.setIndex,
    );
  }

  WorkoutPosition? last;
  for (var e = 0; e < workout.exercises.length; e++) {
    final we = workout.exercises[e];
    for (var s = 0; s < we.sets.length; s++) {
      final set = we.sets[s];
      final done = setState[set.id]?['completed'] == true;
      final here = WorkoutPosition(
        exerciseId: we.instanceId,
        setId: set.id,
        exerciseIndex: e,
        setIndex: s,
        isComplete: done,
      );
      if (!done) {
        return WorkoutPosition(
          exerciseId: here.exerciseId,
          setId: here.setId,
          exerciseIndex: e,
          setIndex: s,
        );
      }
      last = here;
    }
  }
  // Nothing outstanding — either the workout is finished or it has no sets.
  return last ?? WorkoutPosition.empty;
}

/// The set to move the cursor to once [completedSetId] has been confirmed.
///
/// Walks forward from that set in authored order and takes the first one with
/// nothing recorded against it. Forward, not from the top: a client who
/// deliberately started at a later exercise must not be thrown back to an
/// earlier set they chose to leave open. Only when nothing after it is
/// outstanding does it fall back to the first outstanding set anywhere, and
/// when the whole workout is done it stays put — the cursor always names a set
/// that exists.
WorkoutPosition advancePosition(
  Workout workout,
  Map<String, Map<String, dynamic>> setState,
  String completedSetId,
) {
  final from = locateSet(workout, completedSetId);
  if (from == null) return resumePosition(workout, setState);

  var passed = false;
  for (var e = 0; e < workout.exercises.length; e++) {
    final we = workout.exercises[e];
    for (var s = 0; s < we.sets.length; s++) {
      final set = we.sets[s];
      if (!passed) {
        passed = set.id == completedSetId;
        continue;
      }
      if (setState[set.id]?['completed'] == true) continue;
      return WorkoutPosition(
        exerciseId: we.instanceId,
        setId: set.id,
        exerciseIndex: e,
        setIndex: s,
      );
    }
  }

  // Nothing left after it — anything still open earlier, or stay here.
  final earlier = resumePosition(workout, setState);
  if (!earlier.isComplete) return earlier;
  return WorkoutPosition(
    exerciseId: from.exercise.instanceId,
    setId: from.set.id,
    exerciseIndex: from.exerciseIndex,
    setIndex: from.setIndex,
    isComplete: true,
  );
}

/// An active session rebuilt from storage, with everything needed to put the
/// client back exactly where they left off.
class RestoredWorkoutSession {
  final WorkoutSessionRecord session;

  /// The workout as it was when the session started (or as it was last
  /// re-snapshotted), so exercise identity and order match what the client saw.
  final Workout workout;

  /// Logged sets keyed by set id — the shape the Workout Zone's in-memory state
  /// uses, and the same identity the database recorded them under.
  final Map<String, Map<String, dynamic>> setState;

  /// Where to resume: the session's cursor when it still holds, otherwise the
  /// first outstanding set.
  final WorkoutPosition position;

  const RestoredWorkoutSession({
    required this.session,
    required this.workout,
    required this.setState,
    required this.position,
  });

  String get sessionId => session.id;
  int get elapsedSeconds => session.elapsedSeconds;
  DateTime get startedAt => session.startedAt;
  bool get warmupAcknowledged => session.warmupAcknowledged;
}

/// Reads back the sets logged against a session, keyed by exercise id.
typedef SetLogLoader = Future<Map<String, List<Map<String, dynamic>>>> Function(
    String sessionId);

/// Workouts a pre-snapshot session can be matched against.
typedef WorkoutCandidateLoader = Future<List<Workout>> Function();

/// Restores the one active workout session for a user.
///
/// The startup/refresh path: ask for the authoritative session, rebuild its
/// workout, load its sets, and resolve the resume position. It never returns a
/// half-restored session — a session that exists but can't be rebuilt raises
/// [WorkoutRestorationFailure] so the client is offered recovery rather than an
/// empty screen, and the session row is left untouched and still resumable.
class WorkoutSessionRestorer {
  final WorkoutSessionManager _manager;
  final SetLogLoader _loadSetLogs;
  final WorkoutCandidateLoader _candidates;

  const WorkoutSessionRestorer({
    required WorkoutSessionManager manager,
    required SetLogLoader loadSetLogs,
    WorkoutCandidateLoader candidates = _noCandidates,
  })  : _manager = manager,
        _loadSetLogs = loadSetLogs,
        _candidates = candidates;

  static Future<List<Workout>> _noCandidates() async => const [];

  /// The restored active session, or null when [userId] genuinely has none.
  Future<RestoredWorkoutSession?> restore(String userId) async {
    final WorkoutSessionRecord? session;
    try {
      session = await _manager.activeSession(userId);
    } catch (e) {
      // A failed lookup is not an answer: treating it as "no workout" is what
      // discards an active session.
      throw WorkoutRestorationFailure('Could not read your active workout.', e);
    }
    if (session == null) return null;

    final Workout? workout;
    try {
      // The session's own snapshot is tried first and on its own. Loading the
      // candidate list means reading the client's whole assigned program, and
      // a program that cannot be read must not take a snapshot-backed session
      // down with it — the snapshot is exactly what makes a session
      // restorable without the program.
      workout = _manager.workoutForSession(session) ??
          _manager.workoutForSession(session, candidates: await _candidates());
    } catch (e) {
      throw WorkoutRestorationFailure('Could not rebuild your workout.', e);
    }
    if (workout == null) {
      throw WorkoutRestorationFailure(
          'Could not rebuild your workout. It may no longer be available.');
    }

    final Map<String, List<Map<String, dynamic>>> logs;
    try {
      logs = await _loadSetLogs(session.id);
    } catch (e) {
      // Restoring the workout without its sets would show completed sets as
      // outstanding and invite the client to redo them.
      throw WorkoutRestorationFailure('Could not load your logged sets.', e);
    }

    final setState = seatSetLogs(workout, logs);
    return RestoredWorkoutSession(
      session: session,
      workout: workout,
      setState: setState,
      position: resumePosition(workout, setState,
          cursorSetId: session.currentSetId),
    );
  }
}
