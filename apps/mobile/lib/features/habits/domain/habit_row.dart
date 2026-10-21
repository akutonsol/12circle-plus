/// FIT-058 · a habit row.
///
/// ── THE BOARD ──────────────────────────────────────────────────────────────
///
///     10 minutes of walking        6 of 7 this week
///     Protein at breakfast         7 of 7 this week
///     2 litres of water            5 of 7 this week
///     Lights out by 11             3 of 7 this week
///
/// > *"**Tapping the row is the whole interaction** — no separate checkbox to
/// > hit — with **`role="checkbox"`** so the state is announced. The seven-bar
/// > week gives each habit context without a chart."*
///
/// ── FOUR DEFECTS, EACH NAMED BY THAT ONE SENTENCE ──────────────────────────
/// `habit_card.dart` shipped with:
///
///   1. a **32 × 32 circle** as the only tap target, not the row — and 32 is
///      under the 44 dp floor. FIT-100's annotation makes the same measurement
///      independently: *"Toggle is 44px — the source has 32."*;
///   2. **no `Semantics` at all.** A screen reader announced nothing about
///      whether a habit was done. There is no role, no state, no name;
///   3. a completed habit rendered a plain `Container` rather than a control,
///      so **it could not be un-toggled** — a one-way action with no way back,
///      on a screen whose whole content is a daily yes/no;
///   4. no weekly count on the row, which is the figure the board puts there.
///
/// The count is `completedDates`, which the model already carries.
library;

/// How many of the last seven days this habit was completed.
///
/// Counts distinct **days**, not entries: a habit logged twice on Tuesday is
/// one day, and `completedDates` is a raw list that can legitimately contain
/// both.
int completionsThisWeek(List<DateTime> completedDates, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final firstDay = today.subtract(const Duration(days: 6));
  final days = <String>{};
  for (final d in completedDates) {
    final day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(firstDay) || day.isAfter(today)) continue;
    days.add('${day.year}-${day.month}-${day.day}');
  }
  return days.length;
}

/// `6 of 7 this week` — the board's phrasing.
String weekLine(List<DateTime> completedDates, {DateTime? now}) =>
    '${completionsThisWeek(completedDates, now: now)} of 7 this week';

/// What a screen reader says for the row.
///
/// The name carries what the row shows — the habit and its week — and the
/// **state** is carried by the checkbox role rather than written into the name,
/// so a reader announces "checked"/"unchecked" in the user's own language
/// instead of an English word baked into a string.
String habitRowLabel(String name, List<DateTime> completedDates,
        {DateTime? now}) =>
    '$name, ${weekLine(completedDates, now: now)}';

/// What tapping the row will do, for the hint.
///
/// Both directions, because a completed habit could not be undone at all
/// before this — the completed state rendered a plain container.
String habitRowHint({required bool completedToday}) =>
    completedToday ? 'Mark as not done today' : 'Mark as done today';
