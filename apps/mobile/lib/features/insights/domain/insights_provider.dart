import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';

/// Aggregated, real performance data for the Insights screen.
class InsightsData {
  final int todayScore;            // today's 12 Circle total (0-100)
  final double weekAvg;            // 7-day average total
  final double trendPct;           // % change today vs the week's average
  final List<int> last7;           // daily totals, oldest→newest
  final int workoutPts, nutritionPts, habitsPts, checkinPts, communityPts;
  final int workoutsThisWeek;
  final int? energy;               // latest check-in 1-5
  final double? sleepHours;
  final int? stress;               // 1-5
  final double? weightKg;
  final DateTime? lastCheckin;

  InsightsData({
    required this.todayScore,
    required this.weekAvg,
    required this.trendPct,
    required this.last7,
    required this.workoutPts,
    required this.nutritionPts,
    required this.habitsPts,
    required this.checkinPts,
    required this.communityPts,
    required this.workoutsThisWeek,
    this.energy,
    this.sleepHours,
    this.stress,
    this.weightKg,
    this.lastCheckin,
  });

  static InsightsData empty() => InsightsData(
        todayScore: 0, weekAvg: 0, trendPct: 0, last7: const [],
        workoutPts: 0, nutritionPts: 0, habitsPts: 0, checkinPts: 0,
        communityPts: 0, workoutsThisWeek: 0,
      );
}

final insightsProvider = FutureProvider<InsightsData>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  if (uid == null) return InsightsData.empty();

  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 6));
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  final today = now.toIso8601String().split('T')[0];

  try {
    final scores = await db
        .from('daily_scores')
        .select()
        .eq('user_id', uid)
        .gte('score_date', weekAgo.toIso8601String().split('T')[0])
        .order('score_date');
    final rows = List<Map<String, dynamic>>.from(scores);

    int t(Map<String, dynamic> r, String k) => (r[k] as num?)?.toInt() ?? 0;

    final totals = rows.map((r) => t(r, 'total_score')).toList();
    final weekAvg = totals.isEmpty ? 0.0 : totals.reduce((a, b) => a + b) / totals.length;
    final todayRow = rows.where((r) => r['score_date'] == today).toList();
    final todayScore = todayRow.isNotEmpty ? t(todayRow.first, 'total_score') : 0;
    final trend = weekAvg == 0 ? 0.0 : ((todayScore - weekAvg) / weekAvg) * 100;

    // Today's category breakdown (fallback to most recent row).
    final ref0 = todayRow.isNotEmpty ? todayRow.first : (rows.isNotEmpty ? rows.last : <String, dynamic>{});

    final checkin = await db
        .from('weekly_checkins')
        .select('energy_level, sleep_hours, stress_level, weight_kg, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final workouts = await db
        .from('workout_logs')
        .select('id')
        .eq('user_id', uid)
        .gte('completed_at',
            DateTime(weekStart.year, weekStart.month, weekStart.day).toIso8601String());

    return InsightsData(
      todayScore: todayScore,
      weekAvg: weekAvg,
      trendPct: trend,
      last7: totals,
      workoutPts: t(ref0, 'workout_points'),
      nutritionPts: t(ref0, 'nutrition_points'),
      habitsPts: t(ref0, 'habits_points'),
      checkinPts: t(ref0, 'checkin_points'),
      communityPts: t(ref0, 'community_points'),
      workoutsThisWeek: (workouts as List).length,
      energy: (checkin?['energy_level'] as num?)?.toInt(),
      sleepHours: (checkin?['sleep_hours'] as num?)?.toDouble(),
      stress: (checkin?['stress_level'] as num?)?.toInt(),
      weightKg: (checkin?['weight_kg'] as num?)?.toDouble(),
      lastCheckin: checkin?['created_at'] != null
          ? DateTime.tryParse(checkin!['created_at'] as String)
          : null,
    );
  } catch (_) {
    return InsightsData.empty();
  }
});
