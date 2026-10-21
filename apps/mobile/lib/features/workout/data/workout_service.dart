import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/exercise_model.dart';
import 'models/workout_model.dart';
import 'models/workout_log_model.dart';

class WorkoutService {
  // Resolved on use, not in the constructor: the sample workout/exercise
  // catalogue below needs no client, so constructing the service must not
  // require an initialised Supabase instance.
  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _uid => _supabase.auth.currentUser?.id;

  // ── Sample data (fallback when no assigned program) ───────────────────────

  List<Exercise> getSampleExercises() => [
    Exercise(id: '1', name: 'Barbell Squat', category: 'Strength', muscleGroup: 'Legs', equipment: 'Barbell', difficulty: 'Intermediate', description: 'A compound lower body exercise.', instructions: ['Stand with feet shoulder-width apart', 'Lower your body until thighs are parallel', 'Drive through heels to stand']),
    Exercise(id: '2', name: 'Bench Press', category: 'Strength', muscleGroup: 'Chest', equipment: 'Barbell', difficulty: 'Intermediate', description: 'A compound upper body push exercise.', instructions: ['Lie on bench with feet flat', 'Grip bar slightly wider than shoulders', 'Lower bar to chest then press up']),
    Exercise(id: '3', name: 'Deadlift', category: 'Strength', muscleGroup: 'Back', equipment: 'Barbell', difficulty: 'Advanced', description: 'A fundamental compound pulling exercise.', instructions: ['Stand with feet hip-width apart', 'Hinge at hips and grip the bar', 'Drive hips forward to stand tall']),
    Exercise(id: '4', name: 'Pull Up', category: 'Strength', muscleGroup: 'Back', equipment: 'Bodyweight', difficulty: 'Intermediate', description: 'Upper body pulling movement.', instructions: ['Hang from bar with overhand grip', 'Pull chest to bar', 'Lower with control']),
    Exercise(id: '5', name: 'Dumbbell Lunges', category: 'Strength', muscleGroup: 'Legs', equipment: 'Dumbbells', difficulty: 'Beginner', description: 'Unilateral lower body exercise.', instructions: ['Hold dumbbells at sides', 'Step forward and lower back knee', 'Push back to start']),
    Exercise(id: '6', name: 'Plank', category: 'Core', muscleGroup: 'Core', equipment: 'Bodyweight', difficulty: 'Beginner', description: 'Isometric core stability exercise.', instructions: ['Start in push-up position', 'Hold body in straight line', 'Breathe steadily throughout']),
    Exercise(id: '7', name: 'Hip Thrust', category: 'Strength', muscleGroup: 'Glutes', equipment: 'Barbell', difficulty: 'Intermediate', description: 'Glute isolation exercise.', instructions: ['Sit against bench with bar over hips', 'Drive hips up to full extension', 'Squeeze glutes at top']),
    Exercise(id: '8', name: 'Romanian Deadlift', category: 'Strength', muscleGroup: 'Hamstrings', equipment: 'Barbell', difficulty: 'Intermediate', description: 'Hamstring focused hinge movement.', instructions: ['Stand with feet hip-width', 'Hinge forward keeping back flat', 'Feel stretch in hamstrings then return']),
  ];

  List<Workout> getSampleWorkouts() {
    final ex = getSampleExercises();
    return [
      Workout(id: '1', title: 'Full Body Strength', description: 'A complete full body workout targeting all major muscle groups.', estimatedDuration: 45, difficulty: 'Intermediate', category: 'Strength', coachName: 'Coach Sarah', exercises: [
        WorkoutExercise(exercise: ex[0], sets: [WorkoutSet(setNumber: 1, reps: 8, weightKg: 60, restSeconds: 90), WorkoutSet(setNumber: 2, reps: 8, weightKg: 60, restSeconds: 90), WorkoutSet(setNumber: 3, reps: 8, weightKg: 60, restSeconds: 90)]),
        WorkoutExercise(exercise: ex[1], sets: [WorkoutSet(setNumber: 1, reps: 10, weightKg: 50, restSeconds: 90), WorkoutSet(setNumber: 2, reps: 10, weightKg: 50, restSeconds: 90)]),
        WorkoutExercise(exercise: ex[5], sets: [WorkoutSet(setNumber: 1, reps: 30, weightKg: 0, restSeconds: 60), WorkoutSet(setNumber: 2, reps: 30, weightKg: 0, restSeconds: 60)]),
      ]),
      Workout(id: '2', title: 'Glute and Hamstring Focus', description: 'Target your posterior chain with this focused lower body session.', estimatedDuration: 50, difficulty: 'Intermediate', category: 'Strength', coachName: 'Coach Sarah', exercises: [
        WorkoutExercise(exercise: ex[6], sets: [WorkoutSet(setNumber: 1, reps: 12, weightKg: 80, restSeconds: 90), WorkoutSet(setNumber: 2, reps: 12, weightKg: 80, restSeconds: 90), WorkoutSet(setNumber: 3, reps: 12, weightKg: 80, restSeconds: 90)]),
        WorkoutExercise(exercise: ex[7], sets: [WorkoutSet(setNumber: 1, reps: 10, weightKg: 60, restSeconds: 90), WorkoutSet(setNumber: 2, reps: 10, weightKg: 60, restSeconds: 90)]),
      ]),
      // Example with superset
      Workout(id: '3', title: 'Upper Body + Core Circuit', description: 'Superset and circuit combo for upper body and core.', estimatedDuration: 40, difficulty: 'Advanced', category: 'Strength', coachName: 'Coach Sarah', exercises: [
        WorkoutExercise(exercise: ex[2], sets: [WorkoutSet(setNumber: 1, reps: 5, weightKg: 100, restSeconds: 120), WorkoutSet(setNumber: 2, reps: 5, weightKg: 100, restSeconds: 120)]),
        WorkoutExercise(exercise: ex[3], sets: [WorkoutSet(setNumber: 1, reps: 8, weightKg: 0, restSeconds: 60), WorkoutSet(setNumber: 2, reps: 8, weightKg: 0, restSeconds: 60)], isSuperset: true, supersetGroup: 'A'),
        WorkoutExercise(exercise: ex[1], sets: [WorkoutSet(setNumber: 1, reps: 10, weightKg: 40, restSeconds: 60), WorkoutSet(setNumber: 2, reps: 10, weightKg: 40, restSeconds: 60)], isSuperset: true, supersetGroup: 'A'),
        WorkoutExercise(exercise: ex[5], sets: [WorkoutSet(setNumber: 1, reps: 45, weightKg: 0, restSeconds: 30), WorkoutSet(setNumber: 2, reps: 45, weightKg: 0, restSeconds: 30), WorkoutSet(setNumber: 3, reps: 45, weightKg: 0, restSeconds: 30)], isCircuit: true, circuitGroup: 'C1', circuitRounds: 3),
        WorkoutExercise(exercise: ex[4], sets: [WorkoutSet(setNumber: 1, reps: 12, weightKg: 15, restSeconds: 30), WorkoutSet(setNumber: 2, reps: 12, weightKg: 15, restSeconds: 30), WorkoutSet(setNumber: 3, reps: 12, weightKg: 15, restSeconds: 30)], isCircuit: true, circuitGroup: 'C1', circuitRounds: 3),
      ]),
    ];
  }

  // ── Session management ────────────────────────────────────────────────────

  Future<void> logWorkout(WorkoutLog log) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _supabase.from('workout_logs').insert({
        'user_id': uid,
        'workout_title': log.workoutTitle,
        'duration_minutes': log.durationMinutes ?? 0,
        'calories_burned': log.caloriesBurned ?? 0,
        'category': log.category ?? 'Strength',
        'notes': log.notes ?? '',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Records what the client did on one set.
  ///
  /// **The identity of a logged set is `(session_id, set_id)` and nothing
  /// else.** It is not the exercise's name, and it is not the set number.
  /// Those are recorded *attributes* of what was performed — useful for
  /// history and PR lookups, meaningless as a key:
  ///
  ///  * a workout may prescribe the same movement twice, so two sets can
  ///    legitimately share a name and a set number;
  ///  * swapping an exercise changes the name while the client is mid-session,
  ///    so a name-keyed update matches nothing, falls through to an insert, and
  ///    collides with the row already written under that set's identity
  ///    (`uq_workout_set_logs_set_identity`, 23505).
  ///
  /// Keying on `set_id` — the identity migration 106 introduced and migration
  /// 120 made the only one — removes both. rpe/notes/tempo are always written
  /// (null when blank) so an edit can clear them. Errors propagate so the
  /// caller can surface them; a swallowed save is a lost set.
  Future<void> saveSetLog({
    required String sessionId,
    required String exerciseName,
    /// The exercise *instance* this set belongs to — identity of the slot in
    /// the workout, not of the library movement.
    required String exerciseInstanceId,
    /// Reference to the library exercise performed. A recorded attribute.
    String? libraryExerciseId,
    /// Identity of the set this row records, from the workout definition.
    required String setId,
    required int setNumber,
    required int reps,
    required double weightKg,
    double? rpe,
    String? notes,
    String? tempo,
    // Whether the client confirmed this set. A row is written for an edited
    // set too, so this is what separates a recorded result from a set that is
    // merely filled in (migration 104).
    required bool completed,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    if (setId.isEmpty) {
      // Refused rather than written under a guessed key. A row with no
      // identity cannot be read back onto its set, and inserting one would
      // resurrect exactly the ordinal-keyed behaviour this replaced.
      throw ArgumentError.value(
          setId, 'setId', 'a set log must carry the identity of the set it records');
    }
    final cleanNotes = (notes != null && notes.isNotEmpty) ? notes : null;
    final payload = {
      'exercise_name': exerciseName,
      'exercise_instance_id': exerciseInstanceId,
      'exercise_id': libraryExerciseId,
      'set_number': setNumber,
      'reps': reps,
      'weight_kg': weightKg,
      'rpe': rpe,
      'notes': cleanNotes,
      'tempo': tempo,
      'completed': completed,
    };
    // Update-or-insert on the identity. Done as update-then-insert rather than
    // a PostgREST upsert so it works against databases where the partial unique
    // index on (session_id, set_id) cannot serve as an ON CONFLICT target.
    final existing = await _supabase
        .from('workout_set_logs')
        .update(payload)
        .eq('session_id', sessionId)
        .eq('set_id', setId)
        .select('id');
    if ((existing as List).isEmpty) {
      await _supabase.from('workout_set_logs').insert({
        ...payload,
        'session_id': sessionId,
        'user_id': uid,
        'set_id': setId,
      });
    }
  }

  /// Returns {exerciseInstanceId: [{set_id, set_number, completed, reps,
  /// weight, rpe, notes}]} for every set logged in a session, so resuming restores what the
  /// client entered *and* which sets they actually confirmed.
  ///
  /// `set_id` is the set's own identity and is what the restore path attaches
  /// a row by; `set_number` is carried alongside it for rows written before
  /// migration 106, and for display. Grouping is by `exercise_instance_id`, so
  /// a workout prescribing the same movement twice keeps the two instances'
  /// sets apart.
  ///
  /// Rows written before migration 104 have no completion flag; they are read
  /// as completed, which is how the app has always treated them.
  ///
  /// Read errors propagate. Returning an empty map for a failed read is
  /// indistinguishable from "this session has no sets", which would show a
  /// resumed workout as untouched and invite the client to redo logged work;
  /// the restore path turns a raised error into a recovery state instead.
  Future<Map<String, List<Map<String, dynamic>>>> getSessionCompletedSets(String sessionId) async {
    final rows = await _supabase
        .from('workout_set_logs')
        .select()
        .eq('session_id', sessionId)
        // Ascending explicitly: postgrest-dart's `order` defaults to
        // DESCENDING (unlike the JS client), which is what made a resumed
        // workout come back set 3, 2, 1 and re-seat each set's
        // weight/reps/RPE/notes onto the wrong row.
        .order('set_number', ascending: true);
    final result = <String, List<Map<String, dynamic>>>{};
    for (final row in (rows as List)) {
      // Instance identity first; the library id and the name are the
      // pre-instance fallbacks, in that order.
      final exId = row['exercise_instance_id'] as String? ??
          row['exercise_id'] as String? ??
          row['exercise_name'] as String? ??
          '';
      result.putIfAbsent(exId, () => []).add({
        'completed': row['completed'] != false,
        'reps': row['reps'],
        'weight': row['weight_kg'],
        'rpe': row['rpe'],
        'notes': row['notes'],
        'set_id': row['set_id'],
        'set_number': row['set_number'],
        'exercise_instance_id': row['exercise_instance_id'],
      });
    }
    return result;
  }

  // ── History ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWorkoutHistory({int limit = 20}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final data = await _supabase
          .from('workout_sessions')
          .select()
          .eq('user_id', uid)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getSessionSetLogs(String sessionId) async {
    try {
      final data = await _supabase
          .from('workout_set_logs')
          .select()
          .eq('session_id', sessionId)
          // Ascending explicitly — see getSessionCompletedSets: the default is
          // descending, which showed a past session's sets in reverse.
          .order('exercise_name', ascending: true)
          .order('set_number', ascending: true);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) { return []; }
  }

  // ── Progression data for a single exercise ────────────────────────────────

  /// Returns list of {date, max_weight, total_volume, sets_count} sorted by date asc.
  Future<List<Map<String, dynamic>>> getExerciseProgression(String exerciseName) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _supabase
          .from('workout_set_logs')
          .select('weight_kg, reps, logged_at')
          .eq('user_id', uid)
          .eq('exercise_name', exerciseName)
          // Explicit direction — the default is descending. The rows are
          // regrouped by date and re-sorted below, so this only makes the
          // stated "sorted by date asc" contract true of the query as well.
          .order('logged_at', ascending: true);
      final grouped = <String, Map<String, dynamic>>{};
      for (final row in (rows as List)) {
        final date = (row['logged_at'] as String).substring(0, 10);
        final weight = (row['weight_kg'] as num?)?.toDouble() ?? 0.0;
        final reps = (row['reps'] as int?) ?? 0;
        if (!grouped.containsKey(date)) {
          grouped[date] = {'date': date, 'max_weight': 0.0, 'total_volume': 0.0, 'sets_count': 0};
        }
        grouped[date]!['max_weight'] = (grouped[date]!['max_weight'] as double) < weight
            ? weight : grouped[date]!['max_weight'];
        grouped[date]!['total_volume'] = (grouped[date]!['total_volume'] as double) + weight * reps;
        grouped[date]!['sets_count'] = (grouped[date]!['sets_count'] as int) + 1;
      }
      return grouped.values.toList()..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    } catch (_) { return []; }
  }

  /// Returns all distinct exercise names this user has logged
  Future<List<String>> getLoggedExerciseNames() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _supabase
          .from('workout_set_logs')
          .select('exercise_name')
          .eq('user_id', uid);
      final names = (rows as List).map((r) => r['exercise_name'] as String? ?? '').toSet().toList();
      names.sort();
      return names;
    } catch (_) { return []; }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  // A-G5 (root cause). `train_hub_screen` already renders
  // `error: (_, __) => '—'` for these tiles, with the note: "Showing '0' told
  // the member their streak was broken when the app had simply failed to ask."
  //
  // That arm could never run. This catch turned the failure into `0` before it
  // reached the FutureProvider, so the AsyncValue was always `AsyncData(0)` —
  // the repair had been made at the presentation layer, over a service that
  // destroyed the signal it needed. A-G5 has been green while guarding a
  // branch nothing could reach.
  //
  // A signed-out user is still `0`: that is a real answer, not a failure.

  Future<int> getWeeklyWorkoutCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final data = await _supabase
        .from('workout_logs')
        .select('id')
        .eq('user_id', uid)
        .gte('completed_at', start.toIso8601String());
    return (data as List).length;
  }

  Future<int> getCurrentStreak() async {
    final uid = _uid;
    if (uid == null) return 0;
    final data = await _supabase
        .from('workout_logs')
        .select('completed_at')
        .eq('user_id', uid)
        .order('completed_at', ascending: false)
        .limit(30);
    if ((data as List).isEmpty) return 0;
    int streak = 0;
    DateTime checkDate = DateTime.now();
    for (final log in data) {
      final logDate = DateTime.parse(log['completed_at']);
      final logDay = DateTime(logDate.year, logDate.month, logDate.day);
      final checkDay = DateTime(checkDate.year, checkDate.month, checkDate.day);
      final diff = checkDay.difference(logDay).inDays;
      if (diff == 0 || diff == 1) {
        streak++;
        checkDate = logDay.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  Future<int> getTotalWorkoutCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final data = await _supabase.from('workout_logs').select('id').eq('user_id', uid);
    return (data as List).length;
  }

  /// Completion rate over last 30 days: completed / (completed + abandoned)
  Future<double> getCompletionRate() async {
    final uid = _uid;
    if (uid == null) return 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final rows = await _supabase
        .from('workout_sessions')
        .select('status')
        .eq('user_id', uid)
        .gte('started_at', cutoff)
        .inFilter('status', ['completed', 'abandoned']);
    final all = (rows as List);
    if (all.isEmpty) return 0;
    final completed = all.where((r) => r['status'] == 'completed').length;
    return completed / all.length;
  }

  /// Program adherence: workouts done this week / target days per week
  Future<double> getProgramAdherence({int targetDaysPerWeek = 4}) async {
    final count = await getWeeklyWorkoutCount();
    return (count / targetDaysPerWeek).clamp(0.0, 1.0);
  }

  Future<List<Map<String, dynamic>>> getPersonalRecords() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final data = await _supabase
          .from('workout_set_logs')
          .select('exercise_name, weight_kg, reps')
          .eq('user_id', uid)
          .gt('weight_kg', 0);
      final rows = List<Map<String, dynamic>>.from(data as List);
      final prs = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final name = row['exercise_name'] as String;
        final weight = (row['weight_kg'] as num).toDouble();
        if (!prs.containsKey(name) || weight > (prs[name]!['weight_kg'] as double)) {
          prs[name] = {'exercise_name': name, 'weight_kg': weight, 'reps': row['reps']};
        }
      }
      return prs.values.toList()
        ..sort((a, b) => (b['weight_kg'] as double).compareTo(a['weight_kg'] as double));
    } catch (_) { return []; }
  }

  Future<double> getTotalVolumeLifted() async {
    final uid = _uid;
    if (uid == null) return 0;
    final data = await _supabase
        .from('workout_set_logs')
        .select('weight_kg, reps')
        .eq('user_id', uid);
    double total = 0;
    for (final row in (data as List)) {
      total += ((row['weight_kg'] as num?)?.toDouble() ?? 0) * ((row['reps'] as int?) ?? 0);
    }
    return total;
  }

  // ── Coach: client stats ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getClientWorkoutStats(String coachId) async {
    try {
      final rows = await _supabase
          .from('coach_client_workout_stats')
          .select()
          .eq('coach_id', coachId);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getClientPersonalRecords(String clientId) async {
    try {
      final data = await _supabase
          .from('workout_set_logs')
          .select('exercise_name, weight_kg, reps')
          .eq('user_id', clientId)
          .gt('weight_kg', 0);
      final rows = List<Map<String, dynamic>>.from(data as List);
      final prs = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final name = row['exercise_name'] as String;
        final weight = (row['weight_kg'] as num).toDouble();
        if (!prs.containsKey(name) || weight > (prs[name]!['weight_kg'] as double)) {
          prs[name] = {'exercise_name': name, 'weight_kg': weight, 'reps': row['reps']};
        }
      }
      return prs.values.toList()
        ..sort((a, b) => (b['weight_kg'] as double).compareTo(a['weight_kg'] as double));
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getClientRecentSessions(String clientId, {int limit = 10}) async {
    try {
      final data = await _supabase
          .from('workout_sessions')
          .select()
          .eq('user_id', clientId)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) { return []; }
  }
}
