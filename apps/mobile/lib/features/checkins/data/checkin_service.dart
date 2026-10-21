import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/checkin_known.dart';
import '../../../core/observability/app_failure.dart';

class CheckinService {
  final _supabase = Supabase.instance.client;

  Future<bool> saveDailyCheckin({
    required int mood,
    required int energy,
    required int stress,
    required double sleepHours,
    required bool workedOut,
    required bool hitWaterGoal,
    String? notes,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _supabase.from('checkins').insert({
        'user_id': userId,
        'mood': mood,
        'energy': energy,
        'stress_level': stress,
        'sleep_hours': sleepHours,
        'notes': notes ?? '',
        'checked_in_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      reportError('CheckinService.saveDailyCheckin', e);
      return false;
    }
  }

  /// CON-01: was `Future<bool>` with `catch (e) => false`, so a failed read
  /// was indistinguishable from "you have not checked in today".
  Future<CheckinKnown> hasCheckedInToday() async {
    final userId = _supabase.auth.currentUser?.id;
    // Signed out is a real answer, not a failure.
    if (userId == null) return CheckinKnown.notDone;
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      final data = await _supabase
          .from('checkins')
          .select('id')
          .eq('user_id', userId)
          .gte('checked_in_at', start.toIso8601String())
          .lt('checked_in_at', end.toIso8601String());
      return (data as List).isNotEmpty
          ? CheckinKnown.done
          : CheckinKnown.notDone;
    } catch (e) {
      return CheckinKnown.unknown;
    }
  }

  /// CON-01: same defect. A failed read here opens the form to someone who has
  /// already checked in, and `_submit` then writes a duplicate.
  Future<CheckinKnown> hasCheckedInThisWeek() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return CheckinKnown.notDone;
    try {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = start.add(const Duration(days: 7));
      final data = await _supabase
          .from('checkins')
          .select('id')
          .eq('user_id', userId)
          .eq('checkin_type', 'weekly')
          .gte('checked_in_at', start.toIso8601String())
          .lt('checked_in_at', end.toIso8601String());
      return (data as List).isNotEmpty
          ? CheckinKnown.done
          : CheckinKnown.notDone;
    } catch (e) {
      return CheckinKnown.unknown;
    }
  }

  Future<bool> saveWeeklyCheckin({
    required int mood,
    required int energy,
    required int stress,
    required double sleepHours,
    required bool workedOut,
    required bool hitWaterGoal,
    String? notes,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _supabase.from('checkins').insert({
        'user_id': userId,
        'mood': mood,
        'energy': energy,
        'stress_level': stress,
        'sleep_hours': sleepHours,
        'notes': notes ?? '',
        'checkin_type': 'weekly',
        'checked_in_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      reportError('CheckinService.saveWeeklyCheckin', e);
      return false;
    }
  }

  bool needsCoachAttention({required int energy, required int stress}) {
    return energy <= 2 || stress >= 4;
  }

  /// CON-01: was `Future<int>` returning `0` on failure — a number the screen
  /// cannot support, which is the class F-15 recorded. `null` is unknown.
  Future<int?> getCheckinStreak() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      final data = await _supabase
          .from('checkins')
          .select('checked_in_at')
          .eq('user_id', userId)
          .order('checked_in_at', ascending: false)
          .limit(30);
      if ((data as List).isEmpty) return 0;
      int streak = 0;
      DateTime checkDate = DateTime.now();
      for (final c in data) {
        final d = DateTime.parse(c['checked_in_at']);
        final day = DateTime(d.year, d.month, d.day);
        final check = DateTime(checkDate.year, checkDate.month, checkDate.day);
        final diff = check.difference(day).inDays;
        if (diff == 0 || diff == 1) {
          streak++;
          checkDate = day.subtract(const Duration(days: 1));
        } else break;
      }
      return streak;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getRecentCheckins({int limit = 7}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final data = await _supabase
          .from('checkins')
          .select()
          .eq('user_id', userId)
          .order('checked_in_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}
