import 'package:flutter/material.dart';

import '../../../../core/widgets/named_icon_button.dart';

/// The intake flow's back control.
///
/// ── WHAT IT REPLACES ───────────────────────────────────────────────────────
/// Three copies of the same defect in `intake_flow_screen.dart` — `_AppBar`
/// (40 dp), `_IntakeStepBar` (36 dp) and `_ProfileInfoPage`'s header (36 dp).
/// Each was a bare `GestureDetector` around an `Icon`: **no accessible name**,
/// so a screen reader announced nothing, and **under the 44 dp target floor**
/// that F-6 was raised about. This is the first thing a new user touches.
///
/// ── AND WHY IT SETS `container: true` ──────────────────────────────────────
/// F-9 measured the intake welcome page on `emulator-5554` as **one merged
/// accessibility node**, and recorded that the same whole-screen clickable node
/// was **still present on page 2**: `411.4 × 914.3 dp, clickable=true, "Your
/// Profile\nTell us a little about yourself."`. The page's header text had no
/// semantics boundary of its own, so it was absorbed into the only actionable
/// node on the page — this button — and that node's rect grew to the whole
/// screen. A screen reader then offered the entire page as a single "Your
/// Profile, Tell us a little about yourself" button.
///
/// `container: true` forces this control to be its own node, which stops it
/// swallowing anything adjacent. `excludeSemantics: true` stops the icon
/// leaking into the announcement.
///
/// ── AND WHY `onTap` IS PASSED TWICE ────────────────────────────────────────
/// `excludeSemantics: true` drops the child's semantics **including its
/// actions**, so the `GestureDetector`'s tap never reaches the tree. The first
/// version of this widget did exactly that and produced a node announced as a
/// button that a screen reader could not activate — measured on-device as
/// `44x44 tap=false label="Back"`. Handing `onTap` to the `Semantics` as well
/// puts the action back. The device probe now asserts the action, not just the
/// name.
///
/// "Back" is the authoritative package's own word for this control (FIT-027
/// declares it); nothing here is invented.
class IntakeBackButton extends StatelessWidget {
  /// The visible chip's size. The sites it replaces drew 40 and 36; the TARGET
  /// is always at least 44 either way.
  final double size;
  final Widget chip;
  final VoidCallback? onTap;

  const IntakeBackButton({
    super.key,
    required this.chip,
    required this.onTap,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) => NamedIconButton(
        // FIT-027 declares "Back" (138 declarations across the package).
        label: 'Back',
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: chip),
      );
}
