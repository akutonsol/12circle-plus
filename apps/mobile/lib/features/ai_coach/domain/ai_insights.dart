import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../coach/domain/coach_ecosystem_provider.dart'
    show todayScoreProvider, weekScoresProvider;
import '../../scoring/domain/score_provider.dart' show myScoreProvider;
import '../../workout/domain/workout_provider.dart'
    show currentStreakProvider, weeklyWorkoutCountProvider, assignedWorkoutsProvider;
import '../../workout/domain/plan_summary.dart' show todaysSession;

/// AI-Guided coaching content, derived from the client's real activity data
/// (score breakdown, streak, weekly history, assigned plan). This is the
/// "system generates AI suggestions / reviews / insights" layer of CM-003 — the
/// conversational AI coach (ai-coach edge function) sits on top of this.

class AiSuggestion {
  final IconData icon;
  final String title;
  final String body;
  const AiSuggestion(this.icon, this.title, this.body);
}

/// 1–3 personalized suggestions for today, based on what the client has and
/// hasn't done yet (workout/nutrition/habit points) plus streak momentum.
final aiDailySuggestionsProvider = Provider<List<AiSuggestion>>((ref) {
  final score     = ref.watch(todayScoreProvider).valueOrNull ?? const {};
  final workout   = (score['workout_points']   as int?) ?? 0;
  final nutrition = (score['nutrition_points'] as int?) ?? 0;
  final habits    = (score['habits_points']    as int?) ?? 0;
  final streak    = ref.watch(currentStreakProvider).valueOrNull ?? 0;
  final assigned  = ref.watch(assignedWorkoutsProvider).valueOrNull ?? const [];
  // Today's session by Home's own rule (`todaysSession`: scheduled for today
  // and not yet done). This took the plan's first workout, so on a Wednesday
  // Home said "Lower Body" while the briefing said "Upper Body" — and it named
  // a workout on rest days and after the day's session was finished.
  final todayTitle = todaysSession(assigned)?.title;

  final out = <AiSuggestion>[];
  if (streak >= 3) {
    out.add(AiSuggestion(Icons.local_fire_department_rounded, '$streak-day streak',
        'Keep the chain alive — log something today so you don\'t reset it.'));
  }
  if (workout == 0) {
    out.add(AiSuggestion(Icons.fitness_center_rounded, 'Train today',
        todayTitle != null
            ? 'Your plan has "$todayTitle". Knock it out to earn workout points.'
            : 'No workout logged yet — even 15 focused minutes counts.'));
  }
  if (nutrition == 0) {
    out.add(const AiSuggestion(Icons.restaurant_rounded, 'Log your meals',
        'Track today\'s food to stay on your calorie and protein targets.'));
  }
  if (habits == 0) {
    out.add(const AiSuggestion(Icons.checklist_rounded, 'Complete your habits',
        'Tick off your daily habits — small wins compound fast.'));
  }
  if (out.isEmpty) {
    out.add(const AiSuggestion(Icons.verified_rounded, 'All caught up',
        'You\'ve hit workout, nutrition, and habits today. Elite consistency!'));
  }
  return out.take(3).toList();
});

class AiWeeklyReview {
  final String headline;
  final int workouts;
  final int activeDays;
  final int avgScore;
  const AiWeeklyReview({
    required this.headline,
    required this.workouts,
    required this.activeDays,
    required this.avgScore,
  });
}

/// A review of the current week derived from daily scores + workout count.
final aiWeeklyReviewProvider = Provider<AiWeeklyReview>((ref) {
  final week     = ref.watch(weekScoresProvider).valueOrNull ?? const [];
  final workouts = ref.watch(weeklyWorkoutCountProvider).valueOrNull ?? 0;
  var activeDays = 0;
  var sum = 0;
  for (final d in week) {
    final t = (d['total_score'] as int?) ?? 0;
    sum += t;
    if (t > 0) activeDays++;
  }
  final avg = week.isEmpty ? 0 : (sum / week.length).round();
  final headline = activeDays >= 5
      ? 'Outstanding week — you showed up consistently.'
      : activeDays >= 3
          ? 'Solid week. A couple more active days and you\'re elite.'
          : activeDays >= 1
              ? 'A start — aim for 3+ active days next week.'
              : 'Fresh week ahead. Let\'s get the first session in.';
  return AiWeeklyReview(
      headline: headline, workouts: workouts, activeDays: activeDays, avgScore: avg);
});

/// A progress insight headline derived from today's score + overall standing.
final aiProgressInsightProvider = Provider<String>((ref) {
  final s     = ref.watch(myScoreProvider).valueOrNull;
  final cycle = (s?['current_cycle_score'] as num?)?.toInt() ?? 0;
  final rank  = s?['rank'] as String? ?? 'Bronze';
  final level = (s?['level'] as num?)?.toInt() ?? 1;
  final today = ref.watch(todayScoreProvider).valueOrNull ?? const {};
  final total = (today['total_score'] as int?) ?? 0;

  if (total >= 70) {
    return 'Top-tier day ($total pts). You\'re $rank · Level $level with '
        '$cycle pts this cycle — keep compounding.';
  }
  if (total >= 40) {
    return 'On track ($total pts today). Finish your workout to climb toward '
        'Level ${level + 1}.';
  }
  if (cycle > 0) {
    return 'You\'re $rank · Level $level. Log a workout or meal to build '
        'today\'s score.';
  }
  return 'Let\'s start strong — your first actions today set the tone for '
      'the week.';
});
