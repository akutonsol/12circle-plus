/// `weekly_checkins.compliance_percent`, DERIVED rather than asked.
///
/// Three readers show this number — the coach's "Nutrition %" chip, the AI-coach
/// prompt and the check-in notification — and nothing ever wrote it, so all three
/// showed `?`. Self-reported compliance is the least reliable figure a member can
/// give, and the app already holds the real one, so it is computed at submit
/// (decision-log 2026-10-25, PD-B02 second half). The locked FIT-004 frame gains no
/// field.
///
/// Definition: of the days of the check-in week that have STARTED (Monday through
/// [now], at most seven), the share on which the calories logged are within ±10 % of
/// the active plan's target, as a whole percent. A day with nothing logged is a miss,
/// not a skip — that is the signal. `null` — never `0` — when there is no usable
/// target or no log at all that week, because "we cannot tell" and "0 % adherent" are
/// different statements and the readers already render `null` honestly.
const double kComplianceTolerance = 0.10;

int? nutritionCompliancePercent({
  required Iterable<({DateTime at, num calories})> logs,
  required num? target,
  required DateTime weekStart,
  required DateTime now,
}) {
  if (target == null || target <= 0) return null;

  // Calendar-day arithmetic, never `Duration(days: n)`: a Duration step lands on
  // the wrong date across a DST change (see weeklyStreak in checkin_known.dart).
  DateTime day(int i) => DateTime(weekStart.year, weekStart.month, weekStart.day + i);
  final today = DateTime(now.year, now.month, now.day);

  final byDay = <DateTime, double>{};
  var anyLogged = false;
  for (final l in logs) {
    final d = DateTime(l.at.year, l.at.month, l.at.day);
    byDay[d] = (byDay[d] ?? 0) + l.calories.toDouble();
    anyLogged = true;
  }
  if (!anyLogged) return null;

  var elapsed = 0;
  var hit = 0;
  for (var i = 0; i < 7; i++) {
    final d = day(i);
    if (d.isAfter(today)) break;
    elapsed++;
    final cal = byDay[d] ?? 0;
    if ((cal - target).abs() <= target * kComplianceTolerance) hit++;
  }
  if (elapsed == 0) return null;
  return (hit * 100 / elapsed).round();
}
