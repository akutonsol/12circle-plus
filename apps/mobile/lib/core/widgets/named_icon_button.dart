import 'package:flutter/material.dart';

/// A tappable whose entire visible content is an icon, done correctly.
///
/// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
/// The same four-line mistake was being made in every feature: a bare
/// `GestureDetector` around an `Icon`. Two defects in one widget — a screen
/// reader announces **nothing** (F-22), and the target is whatever the chip
/// happens to be, typically 36 dp, under the 44 dp floor F-6 was raised about.
///
/// Fixing it site by site was producing near-identical private widgets in four
/// features (`ZoneAction`, `IntakeBackButton`, a header action in messaging, a
/// back control in classes). This is the one place that shape should live.
///
/// ── THE THREE THINGS IT GETS RIGHT ─────────────────────────────────────────
/// **`container: true`** — the control is its own semantics node, so it cannot
/// swallow adjacent unbounded text. F-9 measured a page where exactly that had
/// happened: the intake header merged into the back button and the resulting
/// node covered the whole 411 × 914 dp screen.
///
/// **`onTap` passed to the `Semantics` as well as the `GestureDetector`** —
/// `excludeSemantics: true` drops the child's *actions* along with its labels.
/// Without this the node announces as a button a screen reader **cannot
/// press**, which is worse than the unnamed control it replaced. That shipped
/// once, and was caught only by reading the real semantics tree on-device.
///
/// **A 44 dp target around an unchanged chip** — the design's `tap` component
/// is a 44 dp *target*, not a 44 dp box, so the hit area grows and the
/// decoration does not.
///
/// The [label] is not this widget's to choose. Callers pass the authoritative
/// package's own word ("Back", "Close", "Refresh", "End session") — a name
/// invented for convenience is product copy, and a *wrong* name is not a
/// smaller version of a missing one.
class NamedIconButton extends StatelessWidget {
  /// The accessible name. Required, because the entire point is that this
  /// control cannot ship without one.
  final String label;

  /// The visible chip. Its size is preserved; only the target grows.
  final Widget child;

  final VoidCallback? onTap;

  /// Minimum tap target. 44 is the floor; callers do not normally change it.
  final double minTarget;

  const NamedIconButton({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
    this.minTarget = 44,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        container: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints:
                BoxConstraints(minWidth: minTarget, minHeight: minTarget),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
}
