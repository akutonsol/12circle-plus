import 'package:flutter/material.dart';

/// The weekly check-in's two choice rows.
///
/// Extracted from `daily_checkin_screen.dart` so their accessibility can be
/// asserted — the screen constructs a `CheckinService` in a field initializer
/// and loads from Supabase in `initState`, which no widget test can satisfy.
/// The same reason `plan_summary.dart`, `extendRest()`, `ZoneAction` and
/// `weekProgressFrom` were extracted.

const _brand   = Color(0xFFA855F7);
const _white   = Colors.white;
const _muted   = Color(0xFFCFC2D6);
const _primary = Color(0xFFDDB7FF);

// ── Mood Picker ───────────────────────────────────────────────────────────────
class MoodPicker extends StatelessWidget {
  final int selected;
  final List<String> emojis, labels;
  final ValueChanged<int> onTap;
  const MoodPicker({
    super.key,required this.selected, required this.emojis,
    required this.labels, required this.onTap});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: List.generate(5, (i) {
      final active = i + 1 == selected;
      // A-G8 class, but worse than an unnamed control: these five ANNOUNCED
      // nothing about being a choice and nothing about which one was made.
      // A screen reader read five emoji and five words with no role and no
      // selection, so a client could not tell what they had picked — on a form
      // they fill every week, whose whole purpose is to report how they feel.
      //
      // The name is the label already drawn ("Rough", "Meh", …), so no copy is
      // invented; `inMutuallyExclusiveGroup` + `selected` are the facts.
      // `excludeSemantics` keeps the emoji out of the announcement, and the tap
      // is re-declared because excluding drops the child's actions with it.
      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: active,
        button: true,
        label: labels[i],
        excludeSemantics: true,
        onTap: () => onTap(i + 1),
        child: GestureDetector(
        onTap: () => onTap(i + 1),
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 54, height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                ? _brand.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: active ? _brand : Colors.white.withValues(alpha: 0.1),
                width: active ? 2 : 1),
              boxShadow: active
                ? [BoxShadow(color: _brand.withValues(alpha: 0.35),
                    blurRadius: 12, spreadRadius: 1)]
                : null),
            child: Center(child: Text(emojis[i],
              style: TextStyle(fontSize: active ? 28 : 22)))),
          const SizedBox(height: 6),
          Text(labels[i],
            style: TextStyle(
              color: active ? _primary : _muted.withValues(alpha: 0.4),
              fontSize: 10, fontWeight: FontWeight.w600)),
        ])));
    }));
}

// ── Number Picker (Energy / Stress) ───────────────────────────────────────────
class NumberPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  /// What the five numbers are measuring — "Energy Level", "Stress Level".
  /// The section heading is already drawn above the row; it is repeated into
  /// each option's name because a screen reader announces one option at a
  /// time, and "3" on its own says nothing about what was rated.
  final String scale;
  const NumberPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: List.generate(5, (i) {
      final n = i + 1;
      final active = n == value;
      // Five numbered tiles that announced no role and no selection. The name
      // is built from the heading already on screen plus the number already
      // drawn, so nothing is invented.
      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: active,
        button: true,
        label: '$scale $n of 5',
        excludeSemantics: true,
        onTap: () => onChanged(n),
        child: GestureDetector(
        onTap: () => onChanged(n),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 58, height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: active
              ? LinearGradient(
                  colors: [_brand, const Color(0xFF7C3AED)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
            color: active ? null : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: active ? _brand : Colors.white.withValues(alpha: 0.08)),
            boxShadow: active
              ? [BoxShadow(color: _brand.withValues(alpha: 0.4),
                  blurRadius: 12, offset: const Offset(0, 4))]
              : null),
          child: Center(child: Text('$n',
            style: TextStyle(
              color: active ? _white : _muted.withValues(alpha: 0.45),
              fontSize: 18, fontWeight: FontWeight.w800))))));
    }));
}
