import 'dart:io';

import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/home/presentation/home_screen.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';
import 'package:circle_fitness/features/nutrition/presentation/meals_dashboard_screen.dart';
import 'package:circle_fitness/features/scoring/domain/score_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A logged meal left the other screens as they were.
//
// Three providers held today's nutrition totals (`nutritionTotalsProvider` on
// Meals, a private one on Nutrition, `todayNutritionProvider` for Activity), and
// each log path refreshed only its own. Nothing re-read Home's week bars
// (`weeklyActivityProvider`) or the score a meal earns (`todayScoreProvider`,
// the Wellness Pulse "NUTRITION" figure). None of them dispose, so they stayed
// stale until the app restarted.

void main() {
  test("Meals' totals are the shared totals, so one refresh reaches every screen", () {
    expect(identical(nutritionTotalsProvider, todayNutritionProvider), isTrue,
        reason: 'THE defect: separate providers, each refreshed only by its own screen');
  });

  test('a logged meal re-reads totals, Home\'s week bars and the score', () async {
    final builds = <String, int>{};
    Future<T> counted<T>(String k, T v) async {
      builds[k] = (builds[k] ?? 0) + 1;
      return v;
    }

    final c = ProviderContainer(overrides: [
      todayNutritionProvider.overrideWith((ref) => counted('totals', const <String, double>{})),
      weeklyActivityProvider.overrideWith((ref) => counted('week bars', List.filled(7, 0.0))),
      todayScoreProvider.overrideWith((ref) => counted('today score', const <String, dynamic>{})),
      weekScoresProvider.overrideWith((ref) => counted('week scores', const <Map<String, dynamic>>[])),
      myScoreProvider.overrideWith((ref) => counted('my score', null)),
      recentScoreEventsProvider.overrideWith((ref) => counted('score events', const <Map<String, dynamic>>[])),
    ]);
    addTearDown(c.dispose);
    for (final p in <ProviderListenable<Object?>>[
      todayNutritionProvider, weeklyActivityProvider, todayScoreProvider,
      weekScoresProvider, myScoreProvider, recentScoreEventsProvider,
    ]) {
      c.listen<Object?>(p, (_, __) {});
    }
    await Future<void>.delayed(Duration.zero);
    final before = Map.of(builds);

    refreshAfterMealLogged(c.invalidate);
    await c.read(todayNutritionProvider.future);
    await c.read(weeklyActivityProvider.future);
    await c.read(todayScoreProvider.future);
    await c.read(weekScoresProvider.future);
    await c.read(myScoreProvider.future);
    await c.read(recentScoreEventsProvider.future);

    for (final k in before.keys) {
      expect(builds[k], before[k]! + 1, reason: '$k was not read again after a meal');
    }
  });

  test('guard: both meal-log paths refresh through refreshAfterMealLogged', () {
    for (final p in [
      'lib/features/nutrition/presentation/meals_dashboard_screen.dart',
      'lib/features/nutrition/presentation/nutrition_screen.dart',
    ]) {
      expect(File(p).readAsStringSync(), contains('refreshAfterMealLogged(ref.invalidate)'),
          reason: p);
    }
  });
}
