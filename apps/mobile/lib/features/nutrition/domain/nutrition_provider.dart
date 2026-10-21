import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/nutrition_service.dart';
import '../../auth/domain/auth_provider.dart';

final nutritionServiceProvider = Provider<NutritionService>((ref) => NutritionService());

final todayNutritionProvider = FutureProvider<Map<String, double>>((ref) async {
  return ref.watch(nutritionServiceProvider).getTodayTotals();
});

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
