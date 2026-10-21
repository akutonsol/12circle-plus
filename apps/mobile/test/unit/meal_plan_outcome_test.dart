import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/ai_nutrition/data/ai_nutrition_service.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_nutrition_provider.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/ai_text.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/grocery_list.dart';
import 'package:circle_fitness/features/ai_nutrition/domain/meal_plan.dart';

// FIT-093 · "Meal plan — it didn't build".
//
// The root defect: both AI notifiers were `StateNotifier<String?>`, and both
// wrote their error INTO the content slot. A nullable string has two states
// and the screens needed three, so "asked, and it failed" had nowhere to live
// and was stored as content.
//
// What that produced on `/meal-plan`: a section headed "Your Meal Plan" whose
// plan was `Error generating meal plan. Please try again.`, and — because the
// gate was `mealPlan != null`, which a failure satisfies — TWO enabled routes
// onward, each offering to build a shopping list out of it.

/// A service that fails the way the real one does when the request throws.
class _ThrowingService implements AiNutritionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw Exception('network');
}

/// And one that returns a plan, so "failed" is not the only outcome reachable.
class _GoodService implements AiNutritionService {
  @override
  Future<String> generateMealPlan({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
    required List<String> dietaryRestrictions,
    required int days,
  }) async =>
      'Mon: oats and eggs';

  @override
  Future<String> generateGroceryList({required String mealPlan}) async =>
      'Produce:\n- Spinach, 2 bags';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _generate(MealPlanNotifier n) => n.generateMealPlan(
      calories: 1800,
      protein: 140,
      carbs: 180,
      fat: 60,
      restrictions: const [],
      days: 7,
    );

void main() {
  // ── The root cause, at its source ────────────────────────────────────────
  //
  // These drive the notifier's own catch branch. Without them the fix is
  // untested where it actually lives: a mutation putting the error sentence
  // back into the content slot SURVIVED every test that built an `AiText` by
  // hand, because none of them ever ran `generateMealPlan`.
  group('the notifier never stores an error as content', () {
    test('a thrown request becomes a failure, carrying no text', () async {
      final n = MealPlanNotifier(_ThrowingService());
      await _generate(n);

      expect(n.state.failed, isTrue);
      expect(n.state.content, isNull,
          reason: 'this is the whole defect: the error sentence used to be '
              'stored here and rendered under the heading "Your Meal Plan"');
      expect(mealPlanOutcome(n.state), isA<MealPlanFailed>());
    });

    test('and a successful one is not a failure', () async {
      final n = MealPlanNotifier(_GoodService());
      await _generate(n);

      expect(n.state.failed, isFalse);
      expect(n.state.content, 'Mon: oats and eggs');
    });

    test('the grocery notifier fails the same way', () async {
      final n = GroceryListNotifier(_ThrowingService());
      await n.generateGroceryList('Mon: oats');

      expect(n.state.failed, isTrue);
      expect(n.state.content, isNull);
    });

    test('and succeeds the same way', () async {
      final n = GroceryListNotifier(_GoodService());
      await n.generateGroceryList('Mon: oats');

      expect(n.state.failed, isFalse);
      expect(n.state.content, contains('Spinach'));
    });
  });

  group('AiText keeps the three states apart', () {
    test('a failure is not content', () {
      const f = AiText.failed();
      expect(f.failed, isTrue);
      // The point of the type: there is nowhere to put an error string.
      expect(f.content, isNull);
      expect(f.isReady, isFalse);
    });

    test('idle is not a failure', () {
      expect(const AiText.idle().failed, isFalse);
      expect(const AiText.idle().content, isNull);
    });

    test('ready carries the text and is not a failure', () {
      expect(const AiText.ready('Mon: oats').content, 'Mon: oats');
      expect(const AiText.ready('Mon: oats').failed, isFalse);
    });
  });

  group('mealPlanOutcome', () {
    test('nothing asked for yet is not a failure', () {
      expect(mealPlanOutcome(const AiText.idle()), isA<MealPlanNotBuilt>());
    });

    test('a failure is FIT-093, not a plan', () {
      expect(mealPlanOutcome(const AiText.failed()), isA<MealPlanFailed>());
    });

    test('a plan is a plan, and carries its text', () {
      final o = mealPlanOutcome(const AiText.ready('Mon: oats and eggs'));
      expect(o, isA<MealPlanReady>());
      expect((o as MealPlanReady).plan, 'Mon: oats and eggs');
    });

    test('a blank plan is a failure, not a heading over an empty box', () {
      expect(mealPlanOutcome(const AiText.ready('   \n  ')),
          isA<MealPlanFailed>());
    });
  });

  // The cascade. Both routes onward were gated on `mealPlan != null`.
  group('canBuildGroceryList', () {
    test('a failed plan offers NO route to the grocery list', () {
      expect(canBuildGroceryList(mealPlanOutcome(const AiText.failed())),
          isFalse,
          reason: 'this is what let a shopping list be built from an error '
              'message — the app bar action and the button below shared the '
              'same `!= null` gate');
    });

    test('an unbuilt plan offers no route either', () {
      expect(
          canBuildGroceryList(mealPlanOutcome(const AiText.idle())), isFalse);
    });

    test('a real plan does', () {
      expect(
          canBuildGroceryList(mealPlanOutcome(const AiText.ready('Mon: oats'))),
          isTrue);
    });
  });

  group('the grocery screen honours an outright failure', () {
    test('a failed list is a failure even before parsing', () {
      expect(
        groceryOutcome(mealPlan: 'Mon: oats', rawList: null, listFailed: true),
        isA<GroceryFailed>(),
      );
    });

    test('but the unreadable-payload net still stands on its own', () {
      // The request can succeed and still return something unusable. Removing
      // either rule alone must not reopen the blank screen.
      expect(
        groceryOutcome(
            mealPlan: 'Mon: oats', rawList: 'Here you go!', listFailed: false),
        isA<GroceryFailed>(),
      );
    });

    test('the meal plan is still the first question asked', () {
      expect(groceryOutcome(mealPlan: null, rawList: null, listFailed: true),
          isA<GroceryNeedsMealPlan>(),
          reason: 'a failed list with no plan is still the locked state — the '
              'thing to do is build a plan, not retry the list');
    });
  });

  group('copy is FIT-092\'s and FIT-093\'s', () {
    test('the three controls the screen did not have', () {
      expect(mealPlanTryAgainLabel, 'Try building it again');
      expect(mealPlanToGroceryLabel, 'Turn this into a grocery list');
      expect(mealPlanRebuildLabel, 'Build a different plan');
    });
  });
}
