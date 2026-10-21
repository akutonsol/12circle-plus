/// Reads a `workout_sessions` row in the shape the coach surfaces already
/// consume.
///
/// ── WHY A TRANSLATION AND NOT A REWRITE ────────────────────────────────────
/// Three coach surfaces read `workout_logs` for other users. RLS denies that —
/// `003:193` is owner-only and no coach clause exists in any of the 131
/// migrations — and an RLS-filtered SELECT answers `200` with `[]`, so they
/// reported a confident permanent zero rather than failing. They now read
/// `workout_sessions`, which a coach **is** authorized to read.
///
/// The two tables agree on `user_id`, `workout_title` and `completed_at`. They
/// disagree on exactly one field the call sites consume: `duration_minutes`
/// against `duration_seconds`. Translating at the boundary keeps the four
/// render sites untouched, which is what makes this a data-source fix rather
/// than a UI change — and keeps the diff small enough to read.
Map<String, dynamic> sessionAsWorkoutLog(Map<String, dynamic> row) => {
      ...row,
      'duration_minutes': minutesFromSeconds(row['duration_seconds']),
    };

/// Whole minutes, rounded.
///
/// A null or absent `duration_seconds` is **0 minutes**, which is what the old
/// column's `?? 0` produced for a missing value — this is not the place to
/// change that, and a session with no recorded duration is not a session of
/// unknown length the UI can express.
int minutesFromSeconds(Object? seconds) {
  final n = seconds is num ? seconds : null;
  if (n == null || n <= 0) return 0;
  return (n / 60).round();
}
