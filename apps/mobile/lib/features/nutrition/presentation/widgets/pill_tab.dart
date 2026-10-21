import 'package:flutter/material.dart';

/// The Log Meal sheet's mode selector — FIT-019's `Search` / `Scan` row.
///
/// Extracted from `meals_dashboard_screen.dart` so its accessibility can be
/// asserted: that screen reaches Supabase through four providers and builds the
/// sheet inside a modal, which no widget test can drive. `plan_summary.dart`,
/// `extendRest()`, `ZoneAction`, `weekProgressFrom`, `coachSectionFor` and the
/// check-in pickers were extracted for the same reason — a thing worth
/// asserting gets moved somewhere it can be.

const _white = Colors.white;
const _grey  = Color(0xFF888898);
const _brand = Color(0xFFA855F7);

class PillTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const PillTab(this.label, this.active, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    // F-22, and the same defect the check-in pickers had: three pills that are
    // ONE exclusive choice announced neither as buttons nor with a selection.
    // A screen reader read "Search Scan Barcode" with no way to tell which was
    // active — on the sheet where a client logs everything they eat.
    //
    // The name is the label already drawn, so no copy is invented; the role and
    // the selected state are facts about the widget.
    inMutuallyExclusiveGroup: true,
    selected: active,
    button: true,
    label: label,
    excludeSemantics: true,
    // `excludeSemantics` drops the child's ACTIONS along with its labels, so
    // the tap is re-declared here. Shipped once without this and produced a
    // node a screen reader could not press — see F-9.
    onTap: onTap,
    child: GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        gradient: active
          ? const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFA855F7)])
          : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: active
          ? [BoxShadow(
              color: _brand.withValues(alpha: 0.45),
              blurRadius: 14, spreadRadius: -2)]
          : null),
      alignment: Alignment.center,
      child: Text(label,
        style: TextStyle(
          color: active ? _white : _grey.withValues(alpha: 0.55),
          fontSize: 15, fontWeight: FontWeight.w700)))));
}
