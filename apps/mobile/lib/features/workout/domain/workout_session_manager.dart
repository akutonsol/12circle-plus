import '../data/models/workout_model.dart';
import '../data/workout_session_store.dart';
import '../data/workout_snapshot.dart';

/// The single authority on "which workout session is active".
///
/// Every rule about session identity lives here, so there is exactly one place
/// that decides whether starting a workout resumes an existing session or opens
/// a new one:
///
///  * starting a workout activates exactly one session, with a stable id;
///  * that session records the exact workout it was started from;
///  * starting a *different* workout abandons the previous session rather than
///    leaving two competing "active" rows behind;
///  * re-entering the same workout resumes the same session, keeping its sets;
///  * completing archives the session so it stops being resumable.
///
/// Abandoning never deletes: superseded sessions keep their rows and their set
/// logs, and completed history is untouched.
class WorkoutSessionManager {
  final WorkoutSessionStore _store;
  const WorkoutSessionManager(this._store);

  /// Activates the session for [workout], resuming the existing one when the
  /// user is re-entering the same workout.
  ///
  /// Any other in-progress session is abandoned first, so afterwards exactly
  /// one session is in progress for [userId].
  Future<WorkoutSessionRecord> startWorkout({
    required String userId,
    required Workout workout,
  }) async {
    final open = await _store.inProgressSessions(userId);
    final existing = _matchWorkout(open, workout);

    // Everything that isn't the session we're about to run is superseded.
    final supersededIds = [
      for (final s in open)
        if (s.id != existing?.id) s.id,
    ];
    await _store.abandonSessions(supersededIds);

    if (existing != null) return existing;

    return _store.createSession(
      userId: userId,
      workoutId: workout.id,
      workoutTitle: workout.title,
      workoutSnapshot: workoutToSnapshot(workout),
    );
  }

  /// The one active session, or null. Defensive against a database that still
  /// holds pre-migration duplicates: the newest wins and the rest are closed,
  /// so the answer is stable from the next read onward.
  Future<WorkoutSessionRecord?> activeSession(String userId) async {
    final open = await _store.inProgressSessions(userId);
    if (open.isEmpty) return null;
    final current = open.first;
    if (open.length > 1) {
      await _store.abandonSessions([
        for (final s in open.skip(1)) s.id,
      ]);
    }
    return current;
  }

  /// Rebuilds the workout a session was started from.
  ///
  /// Prefers the snapshot stored with the session, so a workout that is no
  /// longer in any list (AI-generated, or since edited) still resumes exactly
  /// as it was. Falls back to matching [candidates] for sessions written before
  /// snapshots existed.
  Workout? workoutForSession(
    WorkoutSessionRecord session, {
    Iterable<Workout> candidates = const [],
  }) {
    final snapshot = session.workoutSnapshot;
    if (snapshot != null && snapshot.isNotEmpty) {
      return programWorkoutToWorkout(snapshot);
    }
    for (final w in candidates) {
      if (session.workoutId.isNotEmpty && w.id == session.workoutId) return w;
    }
    for (final w in candidates) {
      if (w.title == session.workoutTitle) return w;
    }
    return null;
  }

  Future<void> completeSession({
    required String sessionId,
    required int durationSeconds,
    required int idleSeconds,
    required int caloriesBurned,
  }) =>
      _store.completeSession(
        sessionId: sessionId,
        durationSeconds: durationSeconds,
        idleSeconds: idleSeconds,
        caloriesBurned: caloriesBurned,
      );

  Future<void> abandonSession(String sessionId) =>
      _store.abandonSessions([sessionId]);

  Future<void> saveElapsed(String sessionId, int elapsedSeconds) =>
      _store.saveElapsed(sessionId, elapsedSeconds);

  /// Records the client's warm-up answer against the session, so restoring the
  /// session restores the answer with it.
  Future<void> acknowledgeWarmup(String sessionId) =>
      _store.acknowledgeWarmup(sessionId);

  /// Re-snapshots [workout] onto [sessionId] after the client changes it
  /// mid-session, keeping the stored definition and the running workout the
  /// same shape.
  Future<void> saveSnapshot(String sessionId, Workout workout) =>
      _store.saveSnapshot(sessionId, workoutToSnapshot(workout));

  /// Records the exercise and set the client is currently on, by identity, so
  /// a refresh restores the position instead of re-deriving one.
  Future<void> saveCursor({
    required String sessionId,
    required String exerciseId,
    required String setId,
  }) =>
      _store.saveCursor(sessionId, exerciseId, setId);

  /// Identity is the workout id; the title is only a fallback for sessions
  /// written before ids were persisted. Matching on title alone is what let an
  /// unrelated session be mistaken for the selected workout.
  WorkoutSessionRecord? _matchWorkout(
    List<WorkoutSessionRecord> open,
    Workout workout,
  ) {
    if (workout.id.isNotEmpty) {
      for (final s in open) {
        if (s.workoutId == workout.id) return s;
      }
    }
    for (final s in open) {
      if (s.workoutId.isEmpty && s.workoutTitle == workout.title) return s;
    }
    return null;
  }
}
