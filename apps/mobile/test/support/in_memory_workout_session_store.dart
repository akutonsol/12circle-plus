import 'package:circle_fitness/features/workout/data/workout_session_store.dart';

/// In-memory [WorkoutSessionStore] standing in for the Supabase table.
///
/// Mirrors the behaviours the session rules depend on: rows persist across
/// "restarts", `in_progress` sessions come back newest-first, and set logs are
/// keyed by session id so they stay attached to their session.
///
/// [restart] drops everything the app holds in RAM while keeping stored rows,
/// which is how the tests model closing and reopening the app.
class InMemoryWorkoutSessionStore implements WorkoutSessionStore {
  final List<Map<String, dynamic>> rows = [];
  final Map<String, List<Map<String, dynamic>>> setLogs = {};

  int _idCounter = 0;
  int _clockOffsetSeconds = 0;

  /// Distinct, monotonically increasing timestamps without real waiting, so
  /// "newest first" ordering is deterministic.
  DateTime _now() =>
      DateTime.utc(2026, 1, 1).add(Duration(seconds: _clockOffsetSeconds++));

  /// Simulates an app restart: stored rows survive, nothing else does.
  void restart() {}

  /// Seeds a session directly, for "an old incomplete workout already exists".
  String seedSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    String status = WorkoutSessionStatus.inProgress,
    Map<String, dynamic>? workoutSnapshot,
    DateTime? startedAt,
    int elapsedSeconds = 0,
    DateTime? warmupAcknowledgedAt,
    String currentExerciseId = '',
    String currentSetId = '',
  }) {
    final id = 'session-${++_idCounter}';
    rows.add({
      'id': id,
      'user_id': userId,
      'workout_id': workoutId,
      'workout_title': workoutTitle,
      'status': status,
      'started_at': (startedAt ?? _now()).toIso8601String(),
      'completed_at': null,
      'elapsed_seconds': elapsedSeconds,
      'workout_snapshot': workoutSnapshot,
      'warmup_acknowledged_at': warmupAcknowledgedAt?.toIso8601String(),
      'current_exercise_id': currentExerciseId,
      'current_set_id': currentSetId,
    });
    return id;
  }

  Map<String, dynamic>? rowById(String id) {
    for (final r in rows) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  List<Map<String, dynamic>> withStatus(String status) =>
      [for (final r in rows) if (r['status'] == status) r];

  /// Records a set against a session, the way the Workout Zone does.
  ///
  /// [setId] is the set's own identity, as the app writes it to
  /// `workout_set_logs.set_id`. Omitting it models a row written before
  /// migration 106, which the restore path has to fall back to matching by set
  /// number.
  void logSet(String sessionId, String exerciseId, int setNumber,
      {String? setId,
      int reps = 10,
      double weight = 20,
      double? rpe,
      String? notes,
      bool completed = true}) {
    final list = setLogs.putIfAbsent(sessionId, () => []);
    list.removeWhere(
        (s) => s['exercise_id'] == exerciseId && s['set_number'] == setNumber);
    list.add({
      'exercise_id': exerciseId,
      'set_id': setId,
      'set_number': setNumber,
      'reps': reps,
      'weight': weight,
      'rpe': rpe,
      'notes': notes,
      'completed': completed,
    });
  }

  /// Set logs grouped by exercise id, as `WorkoutService.getSessionCompletedSets`
  /// hands them to the restore path. Deliberately *unsorted* — restoration must
  /// not depend on the order rows come back in.
  Future<Map<String, List<Map<String, dynamic>>>> loadSetLogs(
      String sessionId) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in setLogs[sessionId] ?? const <Map<String, dynamic>>[]) {
      grouped
          .putIfAbsent(row['exercise_id'] as String, () => [])
          .add(Map<String, dynamic>.from(row));
    }
    return grouped;
  }

  List<Map<String, dynamic>> setsFor(String sessionId) =>
      List<Map<String, dynamic>>.from(setLogs[sessionId] ?? const []);

  @override
  Future<List<WorkoutSessionRecord>> inProgressSessions(String userId) async {
    final open = [
      for (final r in rows)
        if (r['user_id'] == userId &&
            r['status'] == WorkoutSessionStatus.inProgress)
          r,
    ]..sort((a, b) =>
        (b['started_at'] as String).compareTo(a['started_at'] as String));
    return [
      for (final r in open) WorkoutSessionRecord.fromMap(Map.from(r)),
    ];
  }

  @override
  Future<WorkoutSessionRecord> createSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    required Map<String, dynamic> workoutSnapshot,
  }) async {
    // Production enforces `workout_sessions_one_active_per_user` (a unique
    // partial index on user_id WHERE status = 'in_progress', migration 103).
    // Reproducing it here is what makes this double honest: without it a bug
    // that opens a second active session passes in tests and throws in the
    // app, which is exactly how the resume-the-wrong-workout defect survived.
    // Checked synchronously, with no await between the read and the insert:
    // a unique index is atomic, and a check-then-act that yields in between
    // would let exactly the concurrent insert this is meant to catch through.
    final open = [
      for (final r in rows)
        if (r['user_id'] == userId &&
            r['status'] == WorkoutSessionStatus.inProgress)
          r,
    ];
    if (open.isNotEmpty) {
      throw StateError(
          'duplicate key value violates unique constraint '
          '"workout_sessions_one_active_per_user" '
          '(user $userId already has active session ${open.first['id']})');
    }
    final id = seedSession(
      userId: userId,
      workoutId: workoutId,
      workoutTitle: workoutTitle,
      workoutSnapshot: workoutSnapshot,
    );
    return WorkoutSessionRecord.fromMap(Map.from(rowById(id)!));
  }

  @override
  Future<void> abandonSessions(Iterable<String> sessionIds) async {
    for (final id in sessionIds) {
      rowById(id)?['status'] = WorkoutSessionStatus.abandoned;
    }
  }

  @override
  Future<void> completeSession({
    required String sessionId,
    required int durationSeconds,
    required int idleSeconds,
    required int caloriesBurned,
  }) async {
    final row = rowById(sessionId);
    if (row == null) return;
    row['status'] = WorkoutSessionStatus.completed;
    row['completed_at'] = _now().toIso8601String();
    row['duration_seconds'] = durationSeconds;
    row['idle_seconds'] = idleSeconds;
    row['calories_burned'] = caloriesBurned;
  }

  @override
  Future<void> saveElapsed(String sessionId, int elapsedSeconds) async {
    rowById(sessionId)?['elapsed_seconds'] = elapsedSeconds;
  }

  @override
  Future<void> acknowledgeWarmup(String sessionId) async {
    final row = rowById(sessionId);
    if (row == null) return;
    // Set once: a repeat acknowledgement keeps the original answer, as the
    // production store's "only when null" filter does.
    row['warmup_acknowledged_at'] ??= _now().toIso8601String();
  }

  @override
  Future<void> saveSnapshot(String sessionId, Map<String, dynamic> snapshot) async {
    rowById(sessionId)?['workout_snapshot'] = snapshot;
  }

  @override
  Future<void> saveCursor(
      String sessionId, String exerciseId, String setId) async {
    final row = rowById(sessionId);
    if (row == null) return;
    row['current_exercise_id'] = exerciseId;
    row['current_set_id'] = setId;
  }
}
