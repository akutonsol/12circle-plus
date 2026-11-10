/// D7: the coach's "Current Streak" is a run of workout days that is still
/// going.
///
/// The client page counted consecutive days back from the client's most recent
/// workout and never compared that day with today, so three days in a row a
/// month ago still read "Current Streak 3d". A run now counts only if it
/// reaches today or yesterday — today not yet trained does not break it — the
/// rule the habit streak (`coach_program_service.dart`) already states.
///
/// Days are local calendar days. `completed_at` is a `timestamptz`, so the date
/// before its `T` is the UTC day, and an evening workout west of UTC lands on
/// tomorrow — which a comparison with today would then throw away.
library;

int currentWorkoutStreak(Iterable<String?> completedAt, {DateTime? now}) {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final days = <DateTime>{};
  for (final s in completedAt) {
    final t = DateTime.tryParse(s ?? '');
    if (t != null) days.add(day(t.toLocal()));
  }
  final today = day(now ?? DateTime.now());
  var check = days.contains(today)
      ? today
      : DateTime(today.year, today.month, today.day - 1);
  var streak = 0;
  while (days.contains(check)) {
    streak++;
    check = DateTime(check.year, check.month, check.day - 1);
  }
  return streak;
}
