import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_text.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/meal_plan.dart';
import 'package:circle_fitness/features/ai_nutrition/presentation/meal_plan_screen.dart';
import 'package:circle_fitness/features/nutrition/domain/nutrition_provider.dart';

/// FIT-093 · what `/meal-plan` renders when the plan did not build.
///
/// `test/unit/meal_plan_outcome_test.dart` pins what the RULE says. This pins
/// what the screen DOES, because the defect was never in a rule — it was that
/// the screen rendered whatever string was in the slot, under a heading that
/// asserted it was a plan, with two working routes onward.
class _FixedMealPlan extends MealPlanNotifier {
  _FixedMealPlan(AiText initial) : super(_NullService()) {
    state = initial;
  }
}

/// The screen never reaches the service in these tests — the state is set
/// directly — so this only has to exist.
class _NullService implements AiNutritionService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the service must not be reached');
}

Future<void> _pump(WidgetTester tester, AiText planState) async {
  final router = GoRouter(
    initialLocation: '/meal-plan',
    routes: [
      GoRoute(path: '/meal-plan', builder: (_, __) => const MealPlanScreen()),
      GoRoute(
          path: '/grocery-list',
          builder: (_, __) => const Scaffold(body: Text('GROCERY'))),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      mealPlanNotifierProvider
          .overrideWith((ref) => _FixedMealPlan(planState)),
      nutritionGoalsProvider.overrideWith((ref) async =>
          {'calories': 1800, 'protein': 140, 'carbs': 180, 'fat': 60}),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failure is NOT rendered as the plan', (tester) async {
    await _pump(tester, const AiText.failed());

    expect(find.text('Your Meal Plan'), findsNothing,
        reason: 'the heading asserted that whatever followed was a plan; what '
            'followed was an apology');
    expect(find.text(mealPlanFailedTitle), findsOneWidget);
    expect(find.text(mealPlanTryAgainLabel), findsOneWidget,
        reason: 'FIT-093 has exactly one control and the screen had none');
  });

  testWidgets('a failure offers NO route to the grocery list', (tester) async {
    await _pump(tester, const AiText.failed());

    // Both gates were `mealPlan != null`, which a failure satisfied.
    expect(find.text('Grocery List'), findsNothing,
        reason: 'the app bar action');
    expect(find.text(mealPlanToGroceryLabel), findsNothing,
        reason: 'the button below the plan');
  });

  testWidgets('a real plan renders, and both routes come back', (tester) async {
    await _pump(tester, const AiText.ready('Mon: oats and eggs'));

    expect(find.text('Your Meal Plan'), findsOneWidget);
    expect(find.text('Mon: oats and eggs'), findsOneWidget);
    expect(find.text('Grocery List'), findsOneWidget);
    expect(find.text(mealPlanToGroceryLabel), findsOneWidget);
    // FIT-092's third control, which had no equivalent at all.
    expect(find.text(mealPlanRebuildLabel), findsOneWidget);
  });

  testWidgets('the route onward actually goes there', (tester) async {
    await _pump(tester, const AiText.ready('Mon: oats and eggs'));

    await tester.ensureVisible(find.text(mealPlanToGroceryLabel));
    await tester.tap(find.text(mealPlanToGroceryLabel));
    await tester.pumpAndSettle();

    expect(find.text('GROCERY'), findsOneWidget);
  });

  testWidgets('before anything is asked for, neither state shows',
      (tester) async {
    await _pump(tester, const AiText.idle());

    expect(find.text('Your Meal Plan'), findsNothing);
    expect(find.text(mealPlanFailedTitle), findsNothing,
        reason: 'not asking is not failing');
    expect(find.text('Generate Meal Plan'), findsOneWidget);
  });
}
