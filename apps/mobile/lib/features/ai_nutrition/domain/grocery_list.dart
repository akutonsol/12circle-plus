/// FIT-094 / FIT-095 · what `/grocery-list` is actually showing.
///
/// ── THE DEFECT, AND WHY IT IS INVISIBLE ────────────────────────────────────
/// `GroceryListNotifier` is a `StateNotifier<String?>`, and on failure it
/// writes the error **into the same slot as the list**:
///
/// ```dart
/// state = 'Error generating grocery list. Please try again.';
/// ```
///
/// The screen then parses that string. `_parseGroceryList` keeps only lines
/// that end in a colon or begin with a dash — the error string matches
/// neither — so it returns `[]` and the screen renders **its header over
/// nothing**. No error. No retry. No explanation. A failed request and a
/// successful one are the same screen, and the successful-looking one is
/// empty.
///
/// The design already says what should be there. **FIT-094 — "Grocery list —
/// the two blocked states"** declares states `failure` and `locked`, a
/// `ph-warning` icon, and exactly three controls: `Back`, **`Build a meal
/// plan`**, **`Try again`**. Neither blocked state is built, and neither
/// button exists — the dependency state says "Create Meal Plan" instead.
///
/// ── WHY THIS DOES NOT MATCH THE ERROR STRING ───────────────────────────────
/// The obvious fix is to compare against that sentence. This does not, because
/// the sentence is not the only way to get an empty list: a truncated or
/// reworded model response parses to nothing just as silently, and matching
/// one literal would leave that case rendering a blank screen forever.
///
/// The rule is the **observable** one: raw output that yields no categories is
/// a failure, whatever it says. That is strictly wider than the sentinel, and
/// it cannot drift when the error copy is reworded.
library;

/// One parsed category and its items — `Produce: - Spinach, 2 bags`.
class GroceryCategory {
  final String name;
  final List<String> items;
  const GroceryCategory(this.name, this.items);
}

/// What `/grocery-list` should be rendering.
sealed class GroceryOutcome {
  const GroceryOutcome();
}

/// No meal plan yet — the list has nothing to be built from. FIT-094's
/// `locked` state, whose control is `Build a meal plan`.
class GroceryNeedsMealPlan extends GroceryOutcome {
  const GroceryNeedsMealPlan();
}

/// A meal plan exists; the list has not been asked for yet.
class GroceryNotBuilt extends GroceryOutcome {
  const GroceryNotBuilt();
}

/// FIT-094's `failure` state. Reached when the request failed **or** when its
/// output cannot be read as a list — both of which produced a blank screen.
class GroceryFailed extends GroceryOutcome {
  const GroceryFailed();
}

class GroceryReady extends GroceryOutcome {
  final List<GroceryCategory> categories;
  const GroceryReady(this.categories);
}

/// `Produce:` opens a category; `- Spinach, 2 bags` adds to it.
///
/// Lifted out of `_GroceryListScreenState` unchanged in behaviour. It was
/// private to a `State`, so nothing could test the one function that decides
/// whether the screen has anything to show.
List<GroceryCategory> parseGroceryList(String raw) {
  final out = <GroceryCategory>[];
  String? current;
  var items = <String>[];

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.endsWith(':') && !trimmed.startsWith('-')) {
      if (current != null && items.isNotEmpty) {
        out.add(GroceryCategory(current, List<String>.from(items)));
        items = <String>[];
      }
      current = trimmed.replaceAll(':', '');
    } else if (trimmed.startsWith('-') && current != null) {
      items.add(trimmed.replaceFirst('- ', '').trim());
    }
  }
  if (current != null && items.isNotEmpty) {
    out.add(GroceryCategory(current, List<String>.from(items)));
  }
  return out;
}

/// The whole decision, in one place, so the screen cannot render a header over
/// nothing again.
/// [listFailed] is the notifier saying so outright — see `ai_text.dart`. The
/// empty-parse rule is kept as a **second** net: the request can succeed and
/// still return something unreadable, and that used to render as a blank.
GroceryOutcome groceryOutcome({
  required String? mealPlan,
  required String? rawList,
  bool listFailed = false,
}) {
  if (mealPlan == null) return const GroceryNeedsMealPlan();
  if (listFailed) return const GroceryFailed();
  if (rawList == null) return const GroceryNotBuilt();
  final categories = parseGroceryList(rawList);
  if (categories.isEmpty) return const GroceryFailed();
  return GroceryReady(categories);
}

// ── Copy. FIT-094 and FIT-095 name these; they are not invented here. ───────

/// FIT-094's `locked` control. The screen said "Create Meal Plan".
const groceryBuildMealPlanLabel = 'Build a meal plan';

/// FIT-094's `failure` control. The screen had no retry at all.
const groceryTryAgainLabel = 'Try again';

/// FIT-095's control. The screen said "Refresh".
const groceryRebuildLabel = 'Rebuild the list';

const groceryFailedTitle = 'That list did not come back';
const groceryFailedBody =
    'The request failed, or came back in a form we could not read.';

// ── The row ────────────────────────────────────────────────────────────────

/// What a screen reader says for a grocery row.
///
/// The board marks every item `role="checkbox"`, so the **state** rides on the
/// checkbox role rather than being written into the name — a reader then says
/// "checked" in the user's own language instead of an English word baked into
/// a string. This is the same rule `habit_row.dart` follows.
String groceryRowLabel(String item) => item;

String groceryRowHint({required bool checked}) =>
    checked ? 'Mark as not bought' : 'Mark as bought';

/// `2/9` — the count the card's header shows.
String groceryProgress(int checked, int total) => '$checked/$total';
