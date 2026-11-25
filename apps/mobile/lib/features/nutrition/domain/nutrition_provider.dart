import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';
import '../data/nutrition_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../coach/domain/coach_ecosystem_provider.dart'
    show todayScoreProvider, weekScoresProvider;
import '../../home/presentation/home_screen.dart' show weeklyActivityProvider;
import '../../scoring/domain/score_provider.dart'
    show myScoreProvider, recentScoreEventsProvider;

final nutritionServiceProvider = Provider<NutritionService>((ref) => NutritionService());

/// P0-FL-59e · the member each answer (or failure) below was read for, kept
/// with the answer itself. Riverpod carries the previous member's value (and
/// failure) through a re-read, and invalidated before an account change is
/// flushed it is `AsyncData(isLoading)`: its kind says nothing about whose it
/// is. Nobody's (not read by [readForMember]) is not the signed-in member's.
final _readFor = Expando<({String? uid})>();

/// Reads for the member signed in NOW, as the read starts, and again as soon
/// as someone else is (A -> B -> A within one flush is no change to
/// [currentUserProvider], but what was read in between is not A's).
Future<T> readForMember<T extends Object>(
    Ref ref, Future<T> Function() read) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final auth = Supabase.instance.client.auth;
  final uid = auth.currentUser?.id;
  final sub = auth.onAuthStateChange.listen((_) {
    if (auth.currentUser?.id != uid) ref.invalidateSelf();
  },
      onError: (Object e, StackTrace s) =>
          reportError('readForMember.onAuthStateChange', e, s));
  ref.onDispose(sub.cancel);
  try {
    final answer = await read();
    _readFor[answer] = (uid: uid);
    return answer;
  } catch (e) {
    _readFor[e] = (uid: uid);
    rethrow;
  }
}

/// What of [read] is the signed-in member's: their value (kept through their
/// own refresh, and through one that fails), and their own failure. A screen
/// that draws it watches the signed-in uid too: the provider does not notify a
/// refresh in flight that becomes the next member's read.
({T? value, Object? error, bool busy}) ownRead<T extends Object>(
    AsyncValue<T> read) {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  bool mine(Object answer) {
    final reader = _readFor[answer];
    return reader != null && reader.uid == uid;
  }

  final value = read.hasValue ? read.requireValue : null;
  final error = read.error;
  return (
    value: value != null && mine(value) ? value : null,
    error: error != null && mine(error) ? error : null,
    busy: read.isLoading,
  );
}

/// Today's calories and macros — the one read every screen shows them from
/// (Nutrition, Meals, Activity). There were three providers of the same
/// figures, and each log path refreshed only its own.
final todayNutritionProvider = FutureProvider<Map<String, double>>((ref) =>
    readForMember(ref, ref.watch(nutritionServiceProvider).getTodayTotals));

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
///
/// A failed read is an ERROR, not the defaults. It used to `catch (_)` and
/// return the defaults, so a client whose coach set 1500 kcal / 160 g protein
/// was shown "x / 2000 kcal", a 120 g protein ring and protein advice built on
/// 120 g -- with nothing saying the plan had not loaded (error contract: a
/// failed read is never shown as data). The screens show that the targets
/// could not be loaded. "No plan assigned" (row == null) still returns the
/// defaults: whether to show them is a product decision this does not touch.
// QAX-SES-01: recomputed for whoever is signed in now, not whoever was.
final nutritionGoalsProvider = FutureProvider<Map<String, double>>(
    (ref) => readForMember(ref, _activeGoals));

Future<Map<String, double>> _activeGoals() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return {..._defaultGoals};
  final row = await Supabase.instance.client
      .from('client_nutrition_plans')
      .select('calories_target, protein_g, carbs_g, fat_g')
      .eq('client_id', userId)
      .eq('is_active', true)
      .maybeSingle();
  if (row == null) return {..._defaultGoals};
  return {
    'calories': (row['calories_target'] as num?)?.toDouble() ?? _defaultGoals['calories']!,
    'protein':  (row['protein_g']       as num?)?.toDouble() ?? _defaultGoals['protein']!,
    'carbs':    (row['carbs_g']         as num?)?.toDouble() ?? _defaultGoals['carbs']!,
    'fat':      (row['fat_g']           as num?)?.toDouble() ?? _defaultGoals['fat']!,
  };
}

const _defaultGoals = {
  'calories': 2000.0,
  'protein':  120.0,
  'carbs':    220.0,
  'fat':      65.0,
};
