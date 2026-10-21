import '../data/models/workout_model.dart';

/// FIT-014 · the "This week" rows.
///
/// ── WHERE THE RULES COME FROM ──────────────────────────────────────────────
/// The board's markup for the frame, read directly rather than from the
/// manifest's flattened labels:
///
/// ```html
/// <button type="button" class="tap row">
///   <span class="met" style="color: var(--green);"><i class="ph ph-check"></i></span>
///   <span><span class="ttl" style="color: var(--grey);">Upper body — push</span>
///         <span class="bds">Monday · 44 min</span></span>
///   <span class="mic">Done</span>
/// </button>
/// ```
///
/// Four things in that one line were wrong in the shipped rows:
///
///   1. the detail reads **`Monday`**, the full day. The rows abbreviated it,
///      so `Thu · 30 min` sat next to a `THU` chip saying the same word twice;
///   2. today's chip is a **`pill`** — `Now`, violet-muted fill, violet text,
///      and `.pill` carries **no** `text-transform`, so it is `Now` and not
///      `NOW`. The other chips are `.mic`, which **is** uppercased in CSS, so
///      `Done` / `Thu` / `Sat` do render as `DONE` / `THU` / `SAT`;
///   3. an upcoming row draws a **hollow ring** (`inset 0 0 0 1px var(--dim)`).
///      The rows drew nothing, so upcoming sessions had no marker at all;
///   4. every row is a `<button>`. They were `Semantics(button: true)` with no
///      action — the same false affordance FIT-016's session rows carried.
///
/// Held here rather than in the widget so each rule can be tested without a
/// harness, and so a mutation to any of them has somewhere to land.
enum WeekRowKind {
  /// Completed — green check, grey title, `Done`.
  done,

  /// Scheduled for today — filled violet dot, `Now` in a pill.
  today,

  /// Scheduled for another day — hollow ring, the abbreviated day.
  scheduled,

  /// No date on the workout. No marker and no chip: the row says what it
  /// knows, which is a title and possibly a duration.
  undated,
}

const _fullDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

WeekRowKind weekRowKind(Workout w, {DateTime? now}) {
  if (w.isCompleted) return WeekRowKind.done;
  final when = w.scheduledDate;
  if (when == null) return WeekRowKind.undated;
  return isSameDay(when, now ?? DateTime.now())
      ? WeekRowKind.today
      : WeekRowKind.scheduled;
}

/// `Monday · 44 min`, `Today · 48 min`, or just `30 min` when undated.
///
/// A completed session keeps its own day — the board's first row is `Monday`,
/// not `Today`, because that is when it happened.
String weekRowDetail(Workout w, {DateTime? now}) {
  final when = w.scheduledDate;
  final parts = <String>[];
  if (when != null) {
    parts.add(isSameDay(when, now ?? DateTime.now())
        ? 'Today'
        : _fullDays[when.weekday - 1]);
  }
  if (w.estimatedDuration > 0) parts.add('${w.estimatedDuration} min');
  return parts.join(' · ');
}

/// The chip's text, in the case the board writes it. `null` when there is no
/// chip — an undated workout has nothing to say here.
///
/// `Done` and the day abbreviations are `.mic`, which is uppercased by the
/// stylesheet; `Now` is a `.pill`, which is not. [weekRowChipIsUppercase] says
/// which, so the caller does not have to know the CSS.
String? weekRowChip(Workout w, {DateTime? now}) {
  switch (weekRowKind(w, now: now)) {
    case WeekRowKind.done:
      return 'Done';
    case WeekRowKind.today:
      return 'Now';
    case WeekRowKind.scheduled:
      return _shortDays[w.scheduledDate!.weekday - 1];
    case WeekRowKind.undated:
      return null;
  }
}

bool weekRowChipIsUppercase(Workout w, {DateTime? now}) =>
    weekRowKind(w, now: now) != WeekRowKind.today;

/// The accessible name, in the shape the manifest declares it:
/// `Upper body — push Monday · 44 min Done`.
///
/// The chip is spelled as it is READ, not as it is drawn — a screen reader
/// announcing `DONE` letter by letter would be the cost of matching the CSS.
String weekRowLabel(Workout w, {DateTime? now}) {
  final detail = weekRowDetail(w, now: now);
  final chip = weekRowChip(w, now: now);
  return [w.title, if (detail.isNotEmpty) detail, if (chip != null) chip]
      .join(' ');
}
