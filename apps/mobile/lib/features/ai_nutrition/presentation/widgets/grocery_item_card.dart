import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/grocery_list.dart';

/// FIT-095 · one category of the built list.
///
/// ── THREE DEFECTS THE BOARD'S ONE WORD NAMES ───────────────────────────────
/// Every item on the board is `role="checkbox"`. The shipped row was none of
/// the things that implies:
///
///   1. **no `Semantics` at all** — a hand-drawn 22 dp circle and a tick icon.
///      A screen reader announced the item's name and nothing about whether it
///      was bought: no role, no state. The identical defect FIT-058's habit
///      row had, found independently;
///   2. the tap target was the row's own padding — `vertical: 6` around a
///      22 dp circle, about **34 dp**, under the 44 dp floor. FIT-100's
///      annotation measures the same class of defect in the same wave
///      (*"Toggle is 44px — the source has 32"*). Note that `TAP-G1` does
///      **not** catch this one: it looks for a tappable wrapping a fixed
///      `Container`, and this wraps a `Padding` whose height is implied. The
///      guard's reach is narrower than its name suggests;
///   3. **ticks were keyed by list index.** `_checkedItems` held `Set<int>`
///      of positions, and the card carries no `key`, so rebuilding the list
///      reuses this `State` by position. After "Rebuild the list" the same
///      indices point at different groceries — a tick put on *Spinach* stays
///      on whatever is now first. Keyed by the item's text, it cannot migrate.
class GroceryItemCard extends StatefulWidget {
  final String category;
  final List<String> items;

  const GroceryItemCard({
    super.key,
    required this.category,
    required this.items,
  });

  @override
  State<GroceryItemCard> createState() => _GroceryItemCardState();
}

class _GroceryItemCardState extends State<GroceryItemCard> {
  /// By TEXT, not by index — see defect 3.
  final Set<String> _checked = {};

  int get _checkedCount => widget.items.where(_checked.contains).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceDarkElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_basket_outlined,
                    color: AppColors.purple, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                widget.category,
                style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                groceryProgress(_checkedCount, widget.items.length),
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...widget.items.map((item) {
            final isChecked = _checked.contains(item);
            void toggle() => setState(() {
                  if (isChecked) {
                    _checked.remove(item);
                  } else {
                    _checked.add(item);
                  }
                });

            // Semantics OUTSIDE, gesture inside — the shape that makes `onTap:`
            // load-bearing. `excludeSemantics` drops the child's ACTIONS along
            // with its labels, so the tap has to be re-declared here or the row
            // announces a checkbox a reader cannot operate (F-20).
            return Semantics(
              checked: isChecked,
              label: groceryRowLabel(item),
              hint: groceryRowHint(checked: isChecked),
              excludeSemantics: true,
              onTap: toggle,
              child: GestureDetector(
                onTap: toggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isChecked
                              ? AppColors.success
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isChecked
                                ? AppColors.success
                                : AppColors.textTertiary,
                          ),
                        ),
                        child: isChecked
                            ? const Icon(Icons.check,
                                color: AppColors.white, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            color: isChecked
                                ? AppColors.textTertiary
                                : AppColors.white,
                            fontSize: 14,
                            decoration:
                                isChecked ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
