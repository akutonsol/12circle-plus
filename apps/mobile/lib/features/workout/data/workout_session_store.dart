import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `workout_sessions`, in the shape the resume logic needs.
class WorkoutSessionRecord {
  final String id;
  final String userId;

  /// Id of the [Workout] this session was started from. May be empty for rows
  /// written before workout identity was persisted (migration 103).
  final String workoutId;
  final String workoutTitle;

  /// `in_progress` | `completed` | `abandoned`.
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int elapsedSeconds;

  /// Full workout definition as selected, so a resume can rebuild it without
  /// looking the workout up by title. Null for pre-migration rows.
  final Map<String, dynamic>? workoutSnapshot;

  /// When the client confirmed they warmed up for *this* session. Null until
  /// they do. Belongs to the session rather than to the Workout Zone screen, so
  /// a refresh restores the acknowledgement instead of re-asking (migration
  /// 105).
  final DateTime? warmupAcknowledgedAt;

  /// The set the client was last working on, by [WorkoutSet.id], and the
  /// exercise it belongs to. This is the session's own record of "where am I",
  /// stored rather than guessed, so a resume lands on the set the client
  /// actually left — including a later set they had deliberately skipped ahead
  /// to. Empty until the client moves within the workout (migration 107).
  final String currentExerciseId;
  final String currentSetId;

  const WorkoutSessionRecord({
    required this.id,
    required this.userId,
    required this.workoutId,
    required this.workoutTitle,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.elapsedSeconds = 0,
    this.workoutSnapshot,
    this.warmupAcknowledgedAt,
    this.currentExerciseId = '',
    this.currentSetId = '',
  });

  bool get isInProgress => status == WorkoutSessionStatus.inProgress;

  /// Whether the warm-up prompt has already been answered for this session.
  bool get warmupAcknowledged => warmupAcknowledgedAt != null;

  factory WorkoutSessionRecord.fromMap(Map<String, dynamic> row) =>
      WorkoutSessionRecord(
        id: row['id']?.toString() ?? '',
        userId: row['user_id']?.toString() ?? '',
        workoutId: row['workout_id']?.toString() ?? '',
        workoutTitle: row['workout_title']?.toString() ?? '',
        status: row['status']?.toString() ?? WorkoutSessionStatus.inProgress,
        startedAt: DateTime.tryParse(row['started_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: DateTime.tryParse(row['completed_at']?.toString() ?? ''),
        elapsedSeconds: (row['elapsed_seconds'] as num?)?.toInt() ?? 0,
        workoutSnapshot: row['workout_snapshot'] is Map
            ? Map<String, dynamic>.from(row['workout_snapshot'] as Map)
            : null,
        warmupAcknowledgedAt:
            DateTime.tryParse(row['warmup_acknowledged_at']?.toString() ?? ''),
        currentExerciseId: row['current_exercise_id']?.toString() ?? '',
        currentSetId: row['current_set_id']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'workout_id': workoutId,
        'workout_title': workoutTitle,
        'status': status,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'elapsed_seconds': elapsedSeconds,
        'workout_snapshot': workoutSnapshot,
        'warmup_acknowledged_at': warmupAcknowledgedAt?.toIso8601String(),
        'current_exercise_id': currentExerciseId,
        'current_set_id': currentSetId,
      };
}

abstract final class WorkoutSessionStatus {
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const abandoned = 'abandoned';
}

/// Persistence operations the session rules need.
///
/// This is a seam over the existing `workout_sessions` table, not a second
/// persistence mechanism — [SupabaseWorkoutSessionStore] is the only
/// implementation the app runs. It exists so the rules in
/// `WorkoutSessionManager` can be exercised deterministically in tests.
abstract class WorkoutSessionStore {
  /// Every `in_progress` session for [userId], newest first.
  Future<List<WorkoutSessionRecord>> inProgressSessions(String userId);

  Future<WorkoutSessionRecord> createSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    required Map<String, dynamic> workoutSnapshot,
  });

  /// Marks [sessionIds] `abandoned`. Rows and their set logs are preserved.
  Future<void> abandonSessions(Iterable<String> sessionIds);

  Future<void> completeSession({
    required String sessionId,
    required int durationSeconds,
    required int idleSeconds,
    required int caloriesBurned,
  });

  Future<void> saveElapsed(String sessionId, int elapsedSeconds);

  /// Records that the client answered the warm-up prompt for [sessionId].
  /// Idempotent: acknowledging an already-acknowledged session keeps the
  /// original timestamp, so the answer can't be "re-asked" by a second write.
  Future<void> acknowledgeWarmup(String sessionId);

  /// Replaces the stored workout definition for [sessionId].
  ///
  /// Called when the workout changes mid-session (an exercise swap), so what a
  /// refresh restores is the workout the client is actually doing rather than
  /// the one they started.
  Future<void> saveSnapshot(String sessionId, Map<String, dynamic> snapshot);

  /// Records which set the client is on, by identity.
  ///
  /// Written as they move through the workout so the position survives a
  /// refresh without being re-guessed from completion state.
  Future<void> saveCursor(
      String sessionId, String exerciseId, String setId);
}

/// Throws unless [owner] is the member signed in NOW.
///
/// P0-FL-59b: a workout outlives the moment it was opened — debounced saves, a
/// rest timer, a finish over four round-trips — and the server only asks that
/// the row carry the caller's own uid. So every workout write asks, right
/// before it is sent, whether the member who owns the workout is still here.
void requireWorkoutOwner(SupabaseClient db, String owner, String what) {
  if (db.auth.currentUser?.id != owner) {
    throw StateError('$what: the signed-in account changed');
  }
}

/// Production store, backed by the existing Supabase `workout_sessions` table.
class SupabaseWorkoutSessionStore implements WorkoutSessionStore {
  final SupabaseClient _db;
  SupabaseWorkoutSessionStore([SupabaseClient? db])
      : _db = db ?? Supabase.instance.client;

  /// The member each session was read or created for, by session id. Every
  /// session the app holds came through this store, so a write against one
  /// made after the account changed is refused here whoever asks for it
  /// (P0-FL-59b) — the row would match nothing, and report success.
  final Map<String, String> _owners = {};

  void _requireOwner(Iterable<String> sessionIds, String what) {
    for (final id in sessionIds) {
      final owner = _owners[id];
      if (owner != null) requireWorkoutOwner(_db, owner, what);
    }
  }

  WorkoutSessionRecord _remember(Map row, String userId) {
    final record = WorkoutSessionRecord.fromMap(Map<String, dynamic>.from(row));
    _owners[record.id] = userId;
    return record;
  }

  @override
  Future<List<WorkoutSessionRecord>> inProgressSessions(String userId) async {
    // Asked as anybody else, this answers "none" — and "none" is what opens a
    // new session.
    requireWorkoutOwner(_db, userId, 'reading the active workout');
    final rows = await _db
        .from('workout_sessions')
        .select()
        .eq('user_id', userId)
        .eq('status', WorkoutSessionStatus.inProgress)
        .order('started_at', ascending: false);
    return [
      for (final row in (rows as List)) _remember(row as Map, userId),
    ];
  }

  @override
  Future<WorkoutSessionRecord> createSession({
    required String userId,
    required String workoutId,
    required String workoutTitle,
    required Map<String, dynamic> workoutSnapshot,
  }) async {
    requireWorkoutOwner(_db, userId, 'starting a workout');
    final row = await _db
        .from('workout_sessions')
        .insert({
          'user_id': userId,
          'workout_id': workoutId,
          'workout_title': workoutTitle,
          'workout_snapshot': workoutSnapshot,
          'status': WorkoutSessionStatus.inProgress,
          // started_at is deliberately not sent: the column defaults to the
          // database's now(), which is UTC, monotonic across sessions and
          // immune to the device's clock and timezone. A client-sent
          // DateTime.now().toIso8601String() carries no zone marker, so
          // Postgres read it as UTC and stored a UTC-5 client's session five
          // hours in the past — which is how a *newer* session could sort
          // older than the one it superseded.
          'elapsed_seconds': 0,
        })
        .select()
        .single();
    return _remember(row, userId);
  }

  @override
  Future<void> abandonSessions(Iterable<String> sessionIds) async {
    final ids = sessionIds.toList();
    if (ids.isEmpty) return;
    _requireOwner(ids, 'ending a workout');
    final rows = await _db
        .from('workout_sessions')
        .update({'status': WorkoutSessionStatus.abandoned})
        .inFilter('id', ids)
        .select('id');
    // RLS filters silently: fewer rows than asked for means a session is still
    // in progress, and must not be reported as ended.
    if (rows.length < ids.length) {
      throw StateError('ending a workout: ${rows.length} of ${ids.length} '
          'sessions were updated');
    }
  }

  @override
  Future<void> completeSession({
    required String sessionId,
    required int durationSeconds,
    required int idleSeconds,
    required int caloriesBurned,
  }) async {
    _requireOwner([sessionId], 'completing a workout');
    final rows = await _db.from('workout_sessions').update({
      'status': WorkoutSessionStatus.completed,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'duration_seconds': durationSeconds,
      'idle_seconds': idleSeconds,
      'calories_burned': caloriesBurned,
    }).eq('id', sessionId).select('id');
    // A completion that matched no row completed nothing: the coach never sees
    // the session and it stays in progress. It used to count as done.
    if (rows.isEmpty) {
      throw StateError('completing a workout: no session was updated');
    }
  }

  @override
  Future<void> saveElapsed(String sessionId, int elapsedSeconds) async {
    _requireOwner([sessionId], 'saving the workout clock');
    await _db
        .from('workout_sessions')
        .update({'elapsed_seconds': elapsedSeconds})
        .eq('id', sessionId);
  }

  @override
  Future<void> acknowledgeWarmup(String sessionId) async {
    _requireOwner([sessionId], 'recording the warm-up');
    // Filtered on "not already set" so a repeat call is a no-op rather than a
    // fresh timestamp.
    await _db
        .from('workout_sessions')
        .update({
          'warmup_acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId)
        .isFilter('warmup_acknowledged_at', null);
  }

  @override
  Future<void> saveSnapshot(String sessionId, Map<String, dynamic> snapshot) async {
    _requireOwner([sessionId], 'saving a swapped workout');
    final rows = await _db
        .from('workout_sessions')
        .update({'workout_snapshot': snapshot})
        .eq('id', sessionId)
        .select('id');
    // Nothing stored: the replaced exercise would be back on the next reload,
    // after the client was told it was swapped.
    if (rows.isEmpty) {
      throw StateError('saving a swapped workout: no session was updated');
    }
  }

  @override
  Future<void> saveCursor(
      String sessionId, String exerciseId, String setId) async {
    _requireOwner([sessionId], 'saving the workout position');
    await _db.from('workout_sessions').update({
      'current_exercise_id': exerciseId,
      'current_set_id': setId,
    }).eq('id', sessionId);
  }
}
