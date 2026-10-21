import 'package:flutter/material.dart';

import '../../domain/coach_surface.dart';

/// The tab's tap target, so a test measures the box that carries the floor.
Key coachTabTargetKey(CoachSurface s) => ValueKey('coach-tab-${s.name}');

/// FIT-102 … FIT-110 · the two tabs every `/ai-coach` anchor carries.
///
/// Extracted from `ai_coach_screen.dart` so it can be tested. The screen
/// itself reaches Supabase on build — eight intelligence cards, each loading —
/// so a widget test of the whole screen asserts nothing about the tabs and
/// everything about the harness. `MealRowTile` was extracted for the same
/// reason after N6: a test that cannot reach the widget ends up asserting
/// against source instead, which proves the code was written, not that it
/// renders.
class CoachSurfaceTabs extends StatelessWidget {
  final CoachSurface selected;
  final ValueChanged<CoachSurface> onSelect;

  final Color background;
  final Color accent;
  final Color border;
  final Color selectedText;
  final Color unselectedText;

  const CoachSurfaceTabs({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.background,
    required this.accent,
    required this.border,
    required this.selectedText,
    required this.unselectedText,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: background,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Row(
          children: CoachSurface.values.map((s) {
            final isSelected = selected == s;
            return Expanded(
              // Semantics outside, gesture inside. `excludeSemantics` drops
              // the child's ACTIONS along with its labels, so `onTap` has to
              // be declared here too or the tab announces itself as something
              // a screen reader cannot press (F-20).
              child: Semantics(
                selected: isSelected,
                inMutuallyExclusiveGroup: true,
                button: true,
                label: s.label,
                excludeSemantics: true,
                onTap: () => onSelect(s),
                child: GestureDetector(
                  onTap: () => onSelect(s),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    // Keyed so a test can measure THIS box. Measuring by
                    // `find.ancestor(… GestureDetector)` reported 590 dp — an
                    // enclosing detector, not the tab — and passed happily
                    // with the floor removed.
                    key: coachTabTargetKey(s),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? accent : border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                    ),
                    child: Text(
                      s.label,
                      style: TextStyle(
                        color: isSelected ? selectedText : unselectedText,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}
