/// The calendar day a workout happened on, as the person reading it lives it.
///
/// `completed_at` is a `timestamptz`, so the database returns a UTC instant and
/// the date before its `T` is the UTC day: an evening session west of UTC lands
/// on tomorrow, an early one east of UTC on yesterday. And "Today" measured in
/// elapsed hours calls 23:59 last night "Today" for the whole next morning.
/// Both are read here on local calendar days, the days `currentWorkoutStreak`
/// counts.
library;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// [timestamp]'s local calendar date as `yyyy-MM-dd`, or [timestamp] cut to
/// its first ten characters if it is not a timestamp — what the callers showed
/// before.
String localWorkoutDate(String timestamp) {
  final t = DateTime.tryParse(timestamp);
  if (t == null) {
    return timestamp.length >= 10 ? timestamp.substring(0, 10) : timestamp;
  }
  final d = t.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// "Today", "Yesterday", "N days ago" or "N weeks ago" for [timestamp], counted
/// in local calendar days, or null if it is not a timestamp.
String? workoutDaysAgo(String timestamp, {DateTime? now}) {
  final t = DateTime.tryParse(timestamp);
  if (t == null) return null;
  // Whole days between the two local dates, through UTC dates so a DST change
  // in between does not shorten one of them to 23 hours.
  final a = _day(t.toLocal());
  final b = _day(now ?? DateTime.now());
  final days = DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return '${(days / 7).round()} weeks ago';
}
