import 'package:supabase_flutter/supabase_flutter.dart';

/// Module 18 — Women's Health data access (cycle logs, symptoms, settings).
class CycleService {
  final _db = Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  String _date(DateTime d) => d.toIso8601String().split('T').first;

  /// Writes refuse rather than no-op when there is no session (F-06): a
  /// silently discarded health log is indistinguishable from a saved one.
  String _requireUid() {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in — the cycle log was not saved.');
    return uid;
  }

  Future<Map<String, dynamic>?> getSettings() async {
    final uid = _uid;
    if (uid == null) return null;
    return await _db.from('cycle_settings').select().eq('user_id', uid).maybeSingle();
  }

  Future<void> saveSettings({int? cycleLength, int? periodLength}) async {
    final uid = _requireUid();
    await _db.from('cycle_settings').upsert({
      'user_id': uid,
      if (cycleLength != null) 'avg_cycle_length': cycleLength,
      if (periodLength != null) 'avg_period_length': periodLength,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Most recent logged periods (newest first).
  Future<List<Map<String, dynamic>>> getPeriods({int limit = 12}) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from('cycle_logs')
        .select()
        .eq('user_id', uid)
        .order('start_date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Logs a new period start (and optional end).
  Future<void> logPeriod({required DateTime start, DateTime? end}) async {
    final uid = _requireUid();
    await _db.from('cycle_logs').insert({
      'user_id': uid,
      'start_date': _date(start),
      if (end != null) 'end_date': _date(end),
    });
  }

  /// Marks the end date on the most recent period that has no end yet.
  /// Returns false when there was no period in progress to end (F-22).
  Future<bool> endCurrentPeriod(DateTime end) async {
    final uid = _requireUid();
    final open = await _db
        .from('cycle_logs')
        .select('id')
        .eq('user_id', uid)
        .isFilter('end_date', null)
        .order('start_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (open == null) return false;
    await _db.from('cycle_logs').update({'end_date': _date(end)}).eq('id', open['id']);
    return true;
  }

  /// Upserts today's symptom check-in.
  Future<void> logSymptoms({
    required DateTime date,
    required List<String> symptoms,
    int? energy,
    int? mood,
    String? flow,
    String? notes,
  }) async {
    final uid = _requireUid();
    await _db.from('cycle_symptoms').upsert({
      'user_id': uid,
      'log_date': _date(date),
      'symptoms': symptoms,
      if (energy != null) 'energy': energy,
      if (mood != null) 'mood': mood,
      if (flow != null) 'flow': flow,
      if (notes != null) 'notes': notes,
    }, onConflict: 'user_id,log_date');
  }

  Future<Map<String, dynamic>?> getSymptomsForDate(DateTime date) async {
    final uid = _uid;
    if (uid == null) return null;
    return await _db
        .from('cycle_symptoms')
        .select()
        .eq('user_id', uid)
        .eq('log_date', _date(date))
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getRecentSymptoms({int limit = 14}) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from('cycle_symptoms')
        .select()
        .eq('user_id', uid)
        .order('log_date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }
}
