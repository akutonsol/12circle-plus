/// FIT-018 · "Session complete — rewarding, not celebratory".
///
/// ── THE BOARD ──────────────────────────────────────────────────────────────
///
///     Lower body, done.
///     Fourth session this week. That's your best block since March.
///
///     51 min Duration    18 Sets logged    4.2 t Volume
///
///     Hip thrust at 70 kg is a new best. Nadia will see it in your week.
///
///     How did it feel?
///     [ Easy ]  [ Right ]  [ Hard ]
///     [        Done        ]
///
/// > *"One real fact rather than a score: the personal best is stated because
/// > it happened, and the effort question is asked while it's fresh — it's what
/// > the coach reads next week. No confetti."*
///
/// ── WHY THIS ANCHOR WAS CARRIED AS COMPLETE WHEN IT IS NOT BUILT ───────────
/// All four of its declared interactions are ONE WORD — `Easy`, `Right`,
/// `Hard`, `Done` — and the old measurement matched one-word labels as
/// substrings. `Done` found `abandoned`, `Right` found `Alignment.centerRight`.
/// `Easy` and `Hard` appear **nowhere in `lib`**. It measured 4/4 and was 0/4.
/// See QA_EVIDENCE §3as.
///
/// ── THE EFFORT QUESTION, AND WHY THE ENCODING IS SAFE ──────────────────────
/// `workout_feedback.difficulty` is `int CHECK (difficulty BETWEEN 1 AND 5)`.
/// The board asks one question with three answers, so three map onto five.
///
/// That is **not** OD-16's shape. OD-16 is about interpreting a number the
/// client did not choose — deciding that a stored `3` means "Steady" is a
/// judgement about them. This is the opposite direction: the client picks the
/// word, and the column stores it. Nothing is inferred.
///
/// `1 / 3 / 5` uses the extremes and the middle, is reversible, and nothing in
/// the app reads this column today — verified, not assumed — so no existing
/// reading changes meaning.
library;

enum SessionEffort {
  easy(label: 'Easy', difficulty: 1),
  right(label: 'Right', difficulty: 3),
  hard(label: 'Hard', difficulty: 5);

  const SessionEffort({required this.label, required this.difficulty});

  /// The board's word.
  final String label;

  /// What `workout_feedback.difficulty` stores.
  final int difficulty;
}

/// The board's question, verbatim.
const effortQuestion = 'How did it feel?';

/// The board's primary action.
const sessionDoneLabel = 'Done';

/// Reads a stored `difficulty` back as the word the client chose.
///
/// Null for a value this app never writes — a `2` or a `4` did not come from
/// this question, and guessing which word it was nearest would invent an
/// answer the client never gave.
SessionEffort? effortFromDifficulty(int? difficulty) {
  for (final e in SessionEffort.values) {
    if (e.difficulty == difficulty) return e;
  }
  return null;
}

/// `Lower body, done.`
///
/// The board titles FIT-016's session `Lower body — strength` and this one
/// `Lower body, done.` — the qualifier after the em dash is dropped, because
/// what is being said is that a session finished, not which variant it was.
/// A title with no em dash is used whole rather than cut at some other mark.
String sessionDoneTitle(String? workoutTitle) {
  final t = workoutTitle?.trim();
  if (t == null || t.isEmpty) return 'Session done.';
  final head = t.split(' — ').first.trim();
  return '${head.isEmpty ? t : head}, done.';
}

/// One figure and its caption — the board reads them as a value above a word.
class SessionStat {
  final String value;
  final String unit;
  final String label;

  const SessionStat({
    required this.value,
    this.unit = '',
    required this.label,
  });

  /// What a screen reader says: `51 min Duration`. The visible form is a
  /// number stacked over a word, which announces as two fragments.
  String get spoken => [value, if (unit.isNotEmpty) unit, label].join(' ');
}

/// `51 min Duration`, `18 Sets logged`, `4.2 t Volume`.
///
/// Each is omitted when the session does not support it. A workout that was
/// bodyweight throughout has no volume, and `0.0 t Volume` on a finished
/// session is a worse answer than three stats being two.
List<SessionStat> sessionStats({
  required int elapsedSeconds,
  required int setsLogged,
  required double volumeKg,
}) =>
    [
      if (elapsedSeconds >= 60)
        SessionStat(
            value: '${elapsedSeconds ~/ 60}', unit: 'min', label: 'Duration'),
      if (setsLogged > 0)
        SessionStat(value: '$setsLogged', label: 'Sets logged'),
      if (volumeKg > 0)
        SessionStat(
            value: (volumeKg / 1000).toStringAsFixed(1),
            unit: 't',
            label: 'Volume'),
    ];

/// Total load moved: every logged set's reps times its weight.
///
/// A set with no weight contributes nothing rather than counting as zero
/// reps — bodyweight work is real work, but this figure is about load, and
/// the board labels it `Volume` in tonnes.
double sessionVolumeKg(Iterable<({int reps, double? weightKg})> sets) {
  var total = 0.0;
  for (final s in sets) {
    final kg = s.weightKg;
    if (kg == null || kg <= 0 || s.reps <= 0) continue;
    total += kg * s.reps;
  }
  return total;
}
