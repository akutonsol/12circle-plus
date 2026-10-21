import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-client adherence snapshot for the coach Compliance Dashboard (Module 30).
/// Pure aggregation — reads existing data (daily_scores, workout_logs,
/// weekly_checkins, action_items, goals). No new tables, no writes.
class ComplianceSummary {
  final String clientId;
  final String name;
  final String? avatarUrl;

  /// Mean of `total_score` (0-100) across the last 7 days.
  final double avgScore;

  /// Workout sessions logged this week.
  final int workoutsThisWeek;

  /// Days since the most recent weekly check-in (null = never).
  final int? daysSinceCheckin;

  /// Action-item completion (0.0–1.0). null when none assigned.
  final double? actionCompletion;

  /// Active goals currently on pace toward target.
  final int goalsOnTrack;
  final int goalsTotal;

  ComplianceSummary({
    required this.clientId,
    required this.name,
    this.avatarUrl,
    required this.avgScore,
    required this.workoutsThisWeek,
    required this.daysSinceCheckin,
    required this.actionCompletion,
    required this.goalsOnTrack,
    required this.goalsTotal,
  });

  /// Composite 0–100 adherence score, weighted across the signals we have.
  /// Each sub-signal degrades gracefully when there's no data for it.
  double get compliance {
    // Daily score: already 0-100.
    final scorePart = avgScore.clamp(0, 100);
    // Workouts: target ~4/week.
    final workoutPart = ((workoutsThisWeek / 4) * 100).clamp(0, 100).toDouble();
    // Check-in recency: full credit within 7 days, zero by 21+.
    final double checkinPart;
    if (daysSinceCheckin == null) {
      checkinPart = 0;
    } else if (daysSinceCheckin! <= 7) {
      checkinPart = 100;
    } else if (daysSinceCheckin! >= 21) {
      checkinPart = 0;
    } else {
      checkinPart = (100 - ((daysSinceCheckin! - 7) / 14) * 100);
    }
    // Action items: completion rate, neutral (skipped) when none assigned.
    final actionPart = actionCompletion == null ? null : actionCompletion! * 100;

    final parts = <double>[
      scorePart.toDouble(),
      workoutPart,
      checkinPart,
      if (actionPart != null) actionPart,
    ];
    final sum = parts.fold<double>(0, (a, b) => a + b);
    return sum / parts.length;
  }

  /// on-track ≥ 75, at-risk 50–74, off-track < 50.
  String get status {
    final c = compliance;
    if (c >= 75) return 'on_track';
    if (c >= 50) return 'at_risk';
    return 'off_track';
  }
}

class ComplianceService {
  final _db = Supabase.instance.client;

  /// Build the compliance roster for the signed-in coach's active clients.
  Future<List<ComplianceSummary>> getRoster() async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return [];

    // 1. Active clients of this coach.
    final rels = await _db
        .from('coach_client_relationships')
        .select('client_id')
        .eq('coach_id', coachId)
        .eq('status', 'active');
    final clientIds =
        (rels as List).map((r) => r['client_id'] as String).toList();
    if (clientIds.isEmpty) return [];

    // 2. Profiles.
    final profiles = await _db
        .from('user_profiles')
        .select('id, first_name, last_name, avatar_url')
        .inFilter('id', clientIds);
    final profileMap = {
      for (final p in profiles as List) p['id'] as String: p,
    };

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 6));
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    // 3. Batched aggregate sources (one query each, filtered to the cohort).
    final scores = await _db
        .from('daily_scores')
        .select('user_id, total_score, score_date')
        .inFilter('user_id', clientIds)
        .gte('score_date', weekAgo.toIso8601String().split('T')[0]);

    // `workout_sessions`, not `workout_logs`: the latter has no coach-read
    // policy (003:193, owner-only) and an RLS-filtered SELECT returns 200 + [],
    // so every client's adherence read as zero completed workouts. The former
    // is coach-readable by 100_rls_harden_client_data.sql. `status` is filtered
    // because an abandoned session is not an adherence event.
    final workouts = await _db
        .from('workout_sessions')
        .select('user_id, completed_at')
        .inFilter('user_id', clientIds)
        .eq('status', 'completed')
        .gte('completed_at',
            DateTime(weekStart.year, weekStart.month, weekStart.day)
                .toIso8601String());

    final checkins = await _db
        .from('weekly_checkins')
        .select('user_id, created_at')
        .inFilter('user_id', clientIds)
        .order('created_at', ascending: false);

    final actions = await _db
        .from('action_items')
        .select('client_id, status')
        .inFilter('client_id', clientIds);

    final goals = await _db
        .from('goals')
        .select('client_id, status, type, start_value, current_value, target_value')
        .inFilter('client_id', clientIds)
        .eq('status', 'active');

    // 4. Fold per client.
    final summaries = <ComplianceSummary>[];
    for (final cid in clientIds) {
      final p = profileMap[cid] as Map<String, dynamic>?;
      final name = p == null
          ? 'Client'
          : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

      // avg score
      final myScores = (scores as List)
          .where((s) => s['user_id'] == cid)
          .map((s) => (s['total_score'] as num?)?.toDouble() ?? 0)
          .toList();
      final avg = myScores.isEmpty
          ? 0.0
          : myScores.reduce((a, b) => a + b) / myScores.length;

      // workouts this week
      final wkts =
          (workouts as List).where((w) => w['user_id'] == cid).length;

      // last check-in
      final myCheckins =
          (checkins as List).where((c) => c['user_id'] == cid).toList();
      int? daysSince;
      if (myCheckins.isNotEmpty) {
        final last = DateTime.tryParse(myCheckins.first['created_at'] as String);
        if (last != null) daysSince = now.difference(last).inDays;
      }

      // action completion
      final myActions =
          (actions as List).where((a) => a['client_id'] == cid).toList();
      double? actionRate;
      if (myActions.isNotEmpty) {
        final done =
            myActions.where((a) => a['status'] == 'completed').length;
        actionRate = done / myActions.length;
      }

      // goals on track
      final myGoals =
          (goals as List).where((g) => g['client_id'] == cid).toList();
      int onTrack = 0;
      for (final g in myGoals) {
        if (_goalOnTrack(g as Map<String, dynamic>)) onTrack++;
      }

      summaries.add(ComplianceSummary(
        clientId: cid,
        name: name.isEmpty ? 'Client' : name,
        avatarUrl: p?['avatar_url'] as String?,
        avgScore: avg,
        workoutsThisWeek: wkts,
        daysSinceCheckin: daysSince,
        actionCompletion: actionRate,
        goalsOnTrack: onTrack,
        goalsTotal: myGoals.length,
      ));
    }

    // Worst adherence first — that's who the coach acts on.
    summaries.sort((a, b) => a.compliance.compareTo(b.compliance));
    return summaries;
  }

  /// A goal is "on track" once it's at least 50% of the way to target —
  /// a lightweight heuristic (no per-goal timeline data required).
  bool _goalOnTrack(Map<String, dynamic> g) {
    final start = (g['start_value'] as num?)?.toDouble();
    final current = (g['current_value'] as num?)?.toDouble();
    final target = (g['target_value'] as num?)?.toDouble();
    if (start == null || current == null || target == null) return false;
    final span = target - start;
    if (span == 0) return current == target;
    final progress = (current - start) / span; // works for up or down goals
    return progress >= 0.5;
  }
}
