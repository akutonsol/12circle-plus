import 'package:supabase_flutter/supabase_flutter.dart';

class CoachProgramService {
  final _db = Supabase.instance.client;

  // ── Program Intelligence (Dynamic Program Builder) ───────
  /// Deterministic plan for a strategy: mesocycles + per-week targets. Null if 093 absent.
  Future<Map<String, dynamic>?> planProgram(Map<String, dynamic> strategy) async {
    try {
      final res = await _db.rpc('plan_program', params: {'p_strategy': strategy});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  /// Create an engine-generated program from a plan, snapshot v1, return its id.
  Future<String?> createEngineProgram(
      Map<String, dynamic> strategy, Map<String, dynamic> plan, {String? name}) async {
    try {
      final prog = await createProgram({
        'name': name ?? '${strategy['program_type'] ?? 'Program'} · ${strategy['duration_weeks'] ?? 12}wk',
        'description': 'Engine-generated (${strategy['progression_model'] ?? 'linear'}).',
        'strategy': strategy, 'plan': plan, 'engine_generated': true,
      });
      final id = prog['id'] as String;
      await _db.rpc('snapshot_program_version', params: {'p_program_id': id, 'p_reason': 'initial'});
      return id;
    } catch (_) { return null; }
  }

  /// Materialize one week's workouts by reusing build_workout per session.
  ///
  /// **Errors propagate.** This used to swallow every failure into `null`, and
  /// the engine's own failure mode was worse than silent: an empty selection
  /// was written as a workout with no exercises and reported as a successful
  /// materialization. Migration 119 makes an empty selection raise; swallowing
  /// that here would put the silence straight back.
  Future<Map<String, dynamic>?> materializeWeek(
      String programId, int week, Map<String, dynamic> context) async {
    final res = await _db.rpc('materialize_program_week',
        params: {'p_program_id': programId, 'p_week': week, 'p_context': context});
    return res is Map ? res.cast<String, dynamic>() : null;
  }

  // ── Coaching Communication Engine ────────────────────────
  /// Assemble a weekly review + create a draft communication. Returns the
  /// deterministic brief + communication_id (text filled by generate step).
  Future<Map<String, dynamic>?> createWeeklyReview(String subjectId, String programId, int week) async {
    try {
      final res = await _db.rpc('create_weekly_review',
          params: {'p_subject': subjectId, 'p_program': programId, 'p_week': week});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  /// Ask the LLM to phrase the brief into coach + client text (grounded).
  Future<Map<String, dynamic>?> generateCommunication(String communicationId) async {
    try {
      final res = await _db.functions.invoke('generate-communication',
          body: {'communication_id': communicationId});
      final d = res.data;
      if (d is Map) return d.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  Future<bool> updateCommunication(String id, String clientText, String coachText) async {
    try {
      await _db.rpc('update_communication',
          params: {'p_id': id, 'p_client_text': clientText, 'p_coach_text': coachText});
      return true;
    } catch (_) { return false; }
  }

  Future<bool> sendCommunication(String id) async {
    try {
      await _db.rpc('send_communication', params: {'p_id': id});
      return true;
    } catch (_) { return false; }
  }

  // ── Predictive Intelligence Engine ───────────────────────
  /// Deterministic outlook for a client: goal progress, predicted finish,
  /// confidence, plateau/injury/adherence risk, recovery forecast, alerts.
  Future<Map<String, dynamic>?> predictClient(String subjectId, {String? programId}) async {
    try {
      final res = await _db.rpc('predict_client',
          params: {'p_subject': subjectId, if (programId != null) 'p_program': programId});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  /// Compute + persist a prediction (history for prediction-vs-reality).
  Future<Map<String, dynamic>?> recordPrediction(String subjectId, {String? programId}) async {
    try {
      final res = await _db.rpc('record_prediction',
          params: {'p_subject': subjectId, if (programId != null) 'p_program': programId});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  // ── Continuous Coaching Engine ───────────────────────────
  /// Record a completed week's structured feedback (upsert by program+week).
  Future<bool> submitWeeklyFeedback(String programId, int week, Map<String, dynamic> data) async {
    try {
      await _db.from('weekly_feedback').upsert(
        {'program_id': programId, 'week': week, ...data},
        onConflict: 'program_id,week');
      return true;
    } catch (_) { return false; }
  }

  /// Deterministic coaching evaluation for a week's feedback → recommended action.
  Future<Map<String, dynamic>?> evaluateWeek(String programId, int week) async {
    try {
      final res = await _db.rpc('evaluate_week', params: {'p_program_id': programId, 'p_week': week});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  /// Apply regeneration to FUTURE weeks (completed locked). Returns status +
  /// diff + version, or pending_approval if the change needs coach sign-off.
  Future<Map<String, dynamic>?> regenerateProgram(String programId, int week,
      {bool approved = false}) async {
    try {
      final res = await _db.rpc('regenerate_program',
          params: {'p_program_id': programId, 'p_week': week, 'p_approved': approved});
      if (res is Map) return res.cast<String, dynamic>();
      return null;
    } catch (_) { return null; }
  }

  // ── Programs ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getMyPrograms() async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return [];
    final data = await _db
        .from('workout_programs')
        .select('*, program_workouts(count)')
        .eq('coach_id', coachId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> createProgram(Map<String, dynamic> data) async {
    final coachId = _db.auth.currentUser?.id;
    return await _db.from('workout_programs').insert({
      ...data,
      'coach_id': coachId,
    }).select().single();
  }

  Future<void> addWorkoutToProgram(String programId, Map<String, dynamic> workout) async {
    await _db.from('program_workouts').insert({
      ...workout,
      'program_id': programId,
    });
  }

  Future<List<Map<String, dynamic>>> getProgramWorkouts(String programId) async {
    final data = await _db
        .from('program_workouts')
        .select()
        .eq('program_id', programId)
        .order('week_number')
        .order('sort_order');
    return List<Map<String, dynamic>>.from(data);
  }

  // ── Program Builder edits (Module 31) ────────────────────
  Future<void> updateProgram(String programId, Map<String, dynamic> data) async {
    await _db.from('workout_programs').update(data).eq('id', programId);
  }

  Future<void> deleteProgram(String programId) async {
    // program_workouts cascade-delete via the FK ON DELETE CASCADE.
    await _db.from('workout_programs').delete().eq('id', programId);
  }

  Future<void> updateWorkout(String workoutId, Map<String, dynamic> data) async {
    await _db.from('program_workouts').update(data).eq('id', workoutId);
  }

  Future<void> deleteWorkout(String workoutId) async {
    await _db.from('program_workouts').delete().eq('id', workoutId);
  }

  // ── Assign program to client ─────────────────────────────
  Future<void> assignProgram(String programId, String clientId) async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return;
    // Deactivate any existing assignment
    await _db.from('workout_program_assignments')
        .update({'status': 'replaced'})
        .eq('client_id', clientId)
        .eq('status', 'active');
    await _db.from('workout_program_assignments').insert({
      'program_id': programId,
      'client_id': clientId,
      'coach_id': coachId,
      'start_date': DateTime.now().toIso8601String().split('T')[0],
      'current_week': 1,
      'status': 'active',
    });
    await _db.from('notifications').insert({
      'recipient_id': clientId,
      'type': 'program_assigned',
      'title': 'New Workout Program',
      'body': 'Your coach has assigned you a new workout program. Check your training tab!',
      'read': false,
    });
  }

  // ── Client reads their assigned program ──────────────────
  Future<Map<String, dynamic>?> getMyAssignedProgram() async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return null;
    final assignment = await _db
        .from('workout_program_assignments')
        .select('*, workout_programs(*)')
        .eq('client_id', clientId)
        .eq('status', 'active')
        .maybeSingle();
    if (assignment == null) return null;
    final programId = assignment['program_id'] as String;
    final workouts = await getProgramWorkouts(programId);
    return {...assignment, 'workouts': workouts};
  }

  // ── Today's workout for client ───────────────────────────
  Future<Map<String, dynamic>?> getTodaysWorkout() async {
    final program = await getMyAssignedProgram();
    if (program == null) return null;
    final workouts = program['workouts'] as List<Map<String, dynamic>>? ?? [];
    final currentWeek = program['current_week'] as int? ?? 1;
    final today = _dayName(DateTime.now().weekday);
    final todayWorkout = workouts.where((w) =>
      w['week_number'] == currentWeek && w['day_of_week'] == today
    ).firstOrNull;
    return todayWorkout;
  }

  String _dayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  // ── Assign nutrition plan ────────────────────────────────
  Future<void> assignNutritionPlan(String clientId, {
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    int? waterOz,
    String? notes,
  }) async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return;
    // One RPC, not deactivate-then-insert. The two statements used to run
    // independently, so a failure between them left the client with NO active
    // plan — and every reader answers that with the hard-coded default macros
    // rather than an error (I-NUT-04). `assign_nutrition_plan` (migration 131)
    // supersedes and inserts in one transaction, under the partial unique
    // index that makes two active rows impossible. coach_id is taken from
    // auth.uid() inside the function, so it is not passed here.
    await _db.rpc('assign_nutrition_plan', params: {
      'p_client_id': clientId,
      'p_calories_target': calories,
      'p_protein_g': protein,
      'p_carbs_g': carbs,
      'p_fat_g': fat,
      'p_water_target_oz': waterOz,
      'p_notes': notes,
    });
    await _db.from('notifications').insert({
      'recipient_id': clientId,
      'type': 'nutrition_assigned',
      'title': 'Nutrition Plan Updated',
      'body': 'Your coach has set your nutrition targets. Check your nutrition tab!',
      'read': false,
    });
  }

  /// Coach: the active nutrition plan for a specific client (to pre-fill the sheet).
  Future<Map<String, dynamic>?> getClientNutritionPlan(String clientId) async {
    return await _db
        .from('client_nutrition_plans')
        .select()
        .eq('client_id', clientId)
        .eq('is_active', true)
        .maybeSingle();
  }

  /// Coach: the active habits assigned to a specific client (to pre-fill the sheet).
  Future<List<Map<String, dynamic>>> getClientHabits(String clientId) async {
    final rows = await _db
        .from('client_habits')
        .select()
        .eq('client_id', clientId)
        .eq('is_active', true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getMyNutritionPlan() async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return null;
    return await _db
        .from('client_nutrition_plans')
        .select()
        .eq('client_id', clientId)
        .eq('is_active', true)
        .maybeSingle();
  }

  // ── Assign habits ────────────────────────────────────────
  Future<void> assignHabits(String clientId, List<Map<String, dynamic>> habits) async {
    final coachId = _db.auth.currentUser?.id;
    // Refuse rather than no-op: the caller would otherwise announce "Habits assigned!".
    if (coachId == null) throw StateError('Not signed in — habits were not assigned.');
    await _db.from('client_habits')
        .update({'is_active': false})
        .eq('client_id', clientId)
        .eq('is_active', true);
    final rows = habits.map((h) => {
      ...h,
      'client_id': clientId,
      'coach_id': coachId,
      'is_active': true,
    }).toList();
    await _db.from('client_habits').insert(rows);
    await _db.from('notifications').insert({
      'recipient_id': clientId,
      'type': 'habits_assigned',
      'title': 'Habits Assigned',
      'body': 'Your coach has set your daily habit targets. Start tracking today!',
      'read': false,
    });
  }

  Future<List<Map<String, dynamic>>> getMyHabits() async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return [];
    final habits = await _db
        .from('client_habits')
        .select()
        .eq('client_id', clientId)
        .eq('is_active', true)
        .order('assigned_at');
    return List<Map<String, dynamic>>.from(habits);
  }

  // ── Log habit completion ─────────────────────────────────
  Future<void> logHabit(String habitId, {double value = 1, bool completed = true}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    final today = DateTime.now().toIso8601String().split('T')[0];
    await _db.from('habit_logs').upsert({
      'habit_id': habitId,
      'user_id': userId,
      'logged_date': today,
      'value': value,
      'completed': completed,
      'logged_at': DateTime.now().toIso8601String(),
    }, onConflict: 'habit_id,logged_date');
  }

  Future<List<Map<String, dynamic>>> getTodayHabitLogs() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    final today = DateTime.now().toIso8601String().split('T')[0];
    final data = await _db
        .from('habit_logs')
        .select()
        .eq('user_id', userId)
        .eq('logged_date', today);
    return List<Map<String, dynamic>>.from(data);
  }

  // Returns current streak per habit_id, calculated from the last 90 days of logs.
  Future<Map<String, int>> getHabitStreaks() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return {};
    final since = DateTime.now().subtract(const Duration(days: 90));
    final data = await _db
        .from('habit_logs')
        .select('habit_id, logged_date, completed')
        .eq('user_id', userId)
        .gte('logged_date', since.toIso8601String().split('T')[0])
        .order('logged_date', ascending: false);

    final logs = List<Map<String, dynamic>>.from(data);
    final completedDates = <String, Set<String>>{};
    for (final log in logs) {
      if (log['completed'] == true) {
        final id = log['habit_id'] as String;
        final date = log['logged_date'] as String;
        completedDates.putIfAbsent(id, () => {}).add(date);
      }
    }

    String fmt(DateTime d) => d.toIso8601String().split('T')[0];

    final result = <String, int>{};
    for (final entry in completedDates.entries) {
      int streak = 0;
      var check = DateTime.now();
      // If today not completed yet, start from yesterday
      if (!entry.value.contains(fmt(check))) {
        check = check.subtract(const Duration(days: 1));
      }
      while (entry.value.contains(fmt(check))) {
        streak++;
        check = check.subtract(const Duration(days: 1));
      }
      result[entry.key] = streak;
    }
    return result;
  }

  Future<void> addCustomHabit({
    required String name,
    required String emoji,
    required String category,
    required int targetValue,
    required String unit,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    await _db.from('client_habits').insert({
      'client_id': userId,
      'name': name,
      'emoji': emoji,
      'category': category,
      'target_value': targetValue,
      'unit': unit,
      'is_active': true,
    });
  }

  /// Coach: has this client PAID for a plan with me? True if there's an active
  /// coach/package subscription or a paid one-time package payment between us.
  /// Coaches can only assign work once this is true.
  Future<bool> clientHasPaidPlan(String clientId) async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return false;
    try {
      final sub = await _db
          .from('subscriptions')
          .select('id')
          .eq('user_id', clientId)
          .eq('coach_id', coachId)
          .inFilter('kind', ['coach', 'package_monthly'])
          .inFilter('status', ['active', 'trialing'])
          .limit(1)
          .maybeSingle();
      if (sub != null) return true;
      final pay = await _db
          .from('payments')
          .select('id')
          .eq('user_id', clientId)
          .eq('coach_id', coachId)
          .eq('kind', 'package')
          .eq('status', 'paid')
          .limit(1)
          .maybeSingle();
      return pay != null;
    } catch (_) {
      return false;
    }
  }
}
