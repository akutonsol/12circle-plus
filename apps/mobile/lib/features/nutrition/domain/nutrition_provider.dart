import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/nutrition_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart'
    show todayScoreProvider, weekScoresProvider;
import '../../home/presentation/home_screen.dart' show weeklyActivityProvider;
import '../../scoring/domain/score_provider.dart'
    show myScoreProvider, recentScoreEventsProvider;

final nutritionServiceProvider = Provider<NutritionService>((ref) => NutritionService());

/// Today's calories and macros — the one read every screen shows them from
/// (Nutrition, Meals, Activity). There were three providers of the same
/// figures, and each log path refreshed only its own.
final todayNutritionProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.watch(nutritionServiceProvider).getTodayTotals();
});

/// Re-reads everything a logged meal changes, wherever it was logged.
///
/// None of these dispose and nothing else ticks them, so after a meal Home's
/// week bars, its NUTRITION score and the other nutrition screen's totals
/// stayed as they were until the app restarted (the workout-finish path does
/// the same for what a workout changes).
void refreshAfterMealLogged(void Function(ProviderOrFamily) invalidate) {
  invalidate(todayNutritionProvider);
  invalidate(weeklyActivityProvider);
  invalidate(todayScoreProvider);
  invalidate(weekScoresProvider);
  invalidate(myScoreProvider);
  invalidate(recentScoreEventsProvider);
}

/// Returns the active coach-assigned macro goals for the current user.
/// Falls back to sensible defaults if no plan has been assigned.
final nutritionGoalsProvider = FutureProvider<Map<String, double>>((ref) async {
  // QAX-SES-01: recompute for whoever is signed in now, not whoever was.
  ref.watch(currentUserProvider);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return _defaultGoals;
  try {
    final row = await Supabase.instance.client
        .from('client_nutrition_plans')
        .select('calories_target, protein_g, carbs_g, fat_g')
        .eq('client_id', userId)
        .eq('is_active', true)
        .maybeSingle();
    if (row == null) return _defaultGoals;
    return {
      'calories': (row['calories_target'] as num?)?.toDouble() ?? _defaultGoals['calories']!,
      'protein':  (row['protein_g']       as num?)?.toDouble() ?? _defaultGoals['protein']!,
      'carbs':    (row['carbs_g']         as num?)?.toDouble() ?? _defaultGoals['carbs']!,
      'fat':      (row['fat_g']           as num?)?.toDouble() ?? _defaultGoals['fat']!,
    };
  } catch (_) {
    return _defaultGoals;
  }
});

const _defaultGoals = {
  'calories': 2000.0,
  'protein':  120.0,
  'carbs':    220.0,
  'fat':      65.0,
};
