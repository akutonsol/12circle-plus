import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/ai_nutrition/domain/grocery_list.dart';

/// FIT-094 · the two blocked states.
///
/// The defect these pin is a screen that looked EMPTY when it had failed.
/// `GroceryListNotifier` writes its error into the same `String?` the list
/// lives in, and the parser keeps only lines ending in `:` or starting with
/// `-` — so the error was dropped and the screen drew a header over nothing.
void main() {
  const plan = 'Mon: chicken and rice';

  group('parseGroceryList', () {
    test('reads categories and their items', () {
      final out = parseGroceryList('''
Produce:
- Spinach, 2 bags
- Bananas, 7
Protein:
- Eggs, 18
''');
      expect(out.map((c) => c.name), ['Produce', 'Protein']);
      expect(out.first.items, ['Spinach, 2 bags', 'Bananas, 7']);
      expect(out.last.items, ['Eggs, 18']);
    });

    test('a category with no items is not a category', () {
      // The trailing-category branch is guarded on `items.isNotEmpty`; a
      // heading alone must not produce an empty card.
      expect(parseGroceryList('Produce:\nProtein:\n- Eggs, 18').map((c) => c.name),
          ['Protein']);
    });

    test('the error sentence parses to nothing — which is the whole defect',
        () {
      expect(parseGroceryList('Error generating grocery list. Please try again.'),
          isEmpty);
    });
  });

  group('groceryOutcome', () {
    test('no meal plan is the locked state, not an empty list', () {
      expect(groceryOutcome(mealPlan: null, rawList: null),
          isA<GroceryNeedsMealPlan>());
      // Even with a list already in hand: the dependency is what is missing.
      expect(groceryOutcome(mealPlan: null, rawList: 'Produce:\n- Eggs, 18'),
          isA<GroceryNeedsMealPlan>());
    });

    test('a plan with no list yet is not a failure', () {
      expect(groceryOutcome(mealPlan: plan, rawList: null),
          isA<GroceryNotBuilt>());
    });

    test('the error string is a FAILURE, not a blank screen', () {
      expect(
        groceryOutcome(
            mealPlan: plan,
            rawList: 'Error generating grocery list. Please try again.'),
        isA<GroceryFailed>(),
      );
    });

    test('output that parses to nothing is a failure too', () {
      // Wider than matching the error sentence on purpose: a truncated or
      // reworded model response is just as unreadable, and used to render the
      // same blank. Matching one literal would leave this case broken.
      expect(groceryOutcome(mealPlan: plan, rawList: 'Here is your list!'),
          isA<GroceryFailed>());
      expect(groceryOutcome(mealPlan: plan, rawList: '   \n\n  '),
          isA<GroceryFailed>());
    });

    test('a readable list is ready, and carries its categories', () {
      final o = groceryOutcome(
          mealPlan: plan, rawList: 'Produce:\n- Spinach, 2 bags\n- Bananas, 7');
      expect(o, isA<GroceryReady>());
      expect((o as GroceryReady).categories.single.items.length, 2);
    });
  });

  group('copy is the board\'s, not invented here', () {
    test('FIT-094 and FIT-095 name these three controls', () {
      // The screen said "Create Meal Plan", had no retry at all, and said
      // "Refresh".
      expect(groceryBuildMealPlanLabel, 'Build a meal plan');
      expect(groceryTryAgainLabel, 'Try again');
      expect(groceryRebuildLabel, 'Rebuild the list');
    });
  });

  group('the row', () {
    test('the hint says what the tap will do, in both directions', () {
      expect(groceryRowHint(checked: false), 'Mark as bought');
      expect(groceryRowHint(checked: true), 'Mark as not bought');
    });

    test('state is NOT written into the name — the checkbox role carries it',
        () {
      // Same rule as habit_row.dart: a reader then announces "checked" in the
      // user's own language instead of an English word baked into a string.
      expect(groceryRowLabel('Spinach, 2 bags'), 'Spinach, 2 bags');
      expect(groceryRowLabel('Spinach, 2 bags').toLowerCase(),
          isNot(contains('checked')));
    });

    test('progress counts checked over total', () {
      expect(groceryProgress(2, 9), '2/9');
    });
  });
}
