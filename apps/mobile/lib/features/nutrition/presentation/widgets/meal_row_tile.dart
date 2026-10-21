import 'package:flutter/material.dart';

import '../../domain/meal_row.dart';
import '../nutrition_palette.dart';

/// FIT-003 · one row of "What you ate".
///
/// The rules are in `domain/meal_row.dart`. What changed here and why:
///
/// The board draws `<name> / <Breakfast · 07:20> / <380>` — a **row**. This
/// shipped as a card: a 52 dp tinted icon, the name, `380 kcal`, three macro
/// **progress bars**, and an inert `more_horiz` with no name and no action.
/// The board's own annotation rejects that shape in as many words —
/// *"Macros read as three figures against their targets on one rule, not three
/// progress cards"* — and the middle line, the meal's type and time, **was not
/// rendered at all**, though `nutrition_logs` has carried `meal_type` and
/// `logged_at` since migration 012.
///
/// The per-meal macro bars are not replaced by per-meal figures: the board
/// puts the macros in the day's header, once, against the day's targets. A
/// meal's own macros have no target to read against.
class MealRowTile extends StatelessWidget {
  final Map<String, dynamic> meal;
  const MealRowTile({super.key, required this.meal});

  @override
  Widget build(BuildContext context) {
    final name = (meal['food_name'] as String?)?.trim();
    final detail = mealRowDetail(
      mealType: meal['meal_type'] as String?,
      loggedAt: DateTime.tryParse('${meal['logged_at']}'),
    );
    final kcal = mealCalories(meal['calories'] as num?);

    // A log with no name is not given one. "Meal" was the old fallback, and a
    // row reading "Meal · Breakfast · 07:20 · 380" tells the client nothing
    // they can act on.
    final shown = (name == null || name.isEmpty) ? null : name;
    if (shown == null) return const SizedBox.shrink();

    final label = mealRowLabel(
      name: shown,
      mealType: meal['meal_type'] as String?,
      loggedAt: DateTime.tryParse('${meal['logged_at']}'),
      calories: meal['calories'] as num?,
    );

    // The manifest declares these rows as `el: "button"`, and the board draws
    // no destination for one. This app has **no** edit or delete path for a
    // logged meal either — the card's old `more_horiz` opened nothing.
    //
    // So the row is NOT declared a button. Announcing an affordance with
    // nothing behind it is the defect FIT-016 and FIT-014 both carried; the
    // same reasoning that kept FIT-016's "More" inert and `enabled: false`
    // (OD-10) applies here, and the gap is recorded as **OD-23** rather than
    // wired to an invented destination.
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
          constraints: const BoxConstraints(minHeight: 44), // `tap` floor
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: nutGrey.withValues(alpha: 0.12))),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: nutWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(detail,
                          style: const TextStyle(color: nutGrey, fontSize: 12.5)),
                    ],
                  ]),
            ),
            const SizedBox(width: 12),
            // The board shows the number alone; `kcal` is carried once by the
            // header. The spoken label above restores it.
            Text(kcal,
                style: const TextStyle(
                    color: nutWhite, fontSize: 15, fontWeight: FontWeight.w500)),
          ]),
      ),
    );
  }
}

