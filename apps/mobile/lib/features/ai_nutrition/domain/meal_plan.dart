/// FIT-092 · the built plan · FIT-093 · "Meal plan — it didn't build".
///
/// ── WHAT THE SCREEN DID WITH A FAILURE ─────────────────────────────────────
/// `MealPlanNotifier` wrote its error into the plan, and `meal_plan_screen`
/// rendered whatever was there:
///
/// ```dart
/// if (mealPlan != null) ...[
///   const Text('Your Meal Plan', …),          // a heading
///   Text(mealPlan, …),                        // "Error generating meal plan."
///   … 'Generate Grocery List'                 // and a way forward
/// ]
/// ```
///
/// So a failed request produced a screen headed **Your Meal Plan** whose plan
/// was an apology, plus **two** enabled routes onward — one in the app bar,
/// one below — each of which tried to build a shopping list out of it.
///
/// FIT-093 is a designed screen. It has one control: `Try building it again`.
library;

import 'ai_text.dart';

sealed class MealPlanOutcome {
  const MealPlanOutcome();
}

/// Targets not submitted yet — FIT-091's `gate`.
class MealPlanNotBuilt extends MealPlanOutcome {
  const MealPlanNotBuilt();
}

/// FIT-093. Not a plan, and not an empty one either.
class MealPlanFailed extends MealPlanOutcome {
  const MealPlanFailed();
}

/// FIT-092.
class MealPlanReady extends MealPlanOutcome {
  final String plan;
  const MealPlanReady(this.plan);
}

MealPlanOutcome mealPlanOutcome(AiText state) {
  if (state.failed) return const MealPlanFailed();
  final plan = state.content;
  // Whitespace-only output is not a plan. It would otherwise render as the
  // heading over a blank box, which is the grocery defect in another skin.
  if (plan == null || plan.trim().isEmpty) {
    return state.isReady ? const MealPlanFailed() : const MealPlanNotBuilt();
  }
  return MealPlanReady(plan);
}

/// Whether `/grocery-list` can be reached from here at all.
///
/// This is the cascade: the app-bar action and the button below were both
/// gated on `mealPlan != null`, which a failure satisfied.
bool canBuildGroceryList(MealPlanOutcome outcome) => outcome is MealPlanReady;

// ── Copy. FIT-092 and FIT-093 name these. ──────────────────────────────────

/// FIT-093's only control. No retry existed on this screen.
const mealPlanTryAgainLabel = 'Try building it again';

/// FIT-092's control. The screen said "Generate Grocery List".
const mealPlanToGroceryLabel = 'Turn this into a grocery list';

/// FIT-092's control. The screen had no way to ask for a different plan
/// without scrolling back up to the same "Generate Meal Plan" button.
const mealPlanRebuildLabel = 'Build a different plan';

const mealPlanFailedTitle = 'That plan did not build';
const mealPlanFailedBody =
    'Nothing was saved. Your targets are still set — try again.';
