/// FIT-033 · "Check-in review — read and reply".
///
/// ── THE PRODUCT DECISION, IN THE BOARD'S OWN WORDS ─────────────────────────
/// > *"Six to review means the **flow matters more than the screen**: paged
/// > 1-of-6, and the primary action is **send and open next**. The insight is
/// > drawn from data she already has, and stated as a suggestion — the coach
/// > decides."*
///
/// So the queue is the feature. A coach with six pending check-ins should not
/// return to a list between each one.
///
/// ── WHAT SHIPPED ───────────────────────────────────────────────────────────
/// A single-check-in form — "Review Check-In", "Client Summary", "Your
/// Feedback", "Recommendations", "Submit Feedback" — with **no queue, no
/// position, no next**. `Back` was the only one of FIT-033's five declared
/// controls present.
///
/// ── THE FOUR STATS, AND WHY ONLY ONE OF THEM IS EXACT ──────────────────────
/// The board draws `Energy Steady`, `Sleep 5/7`, `Sessions 4/4`,
/// `Nutrition 92%`. Against `weekly_checkins` as it actually is:
///
/// | Board | Column | Verdict |
/// |---|---|---|
/// | `Nutrition 92%` | `compliance_percent` | **exact** |
/// | `Energy Steady` | `energy_level` 1–5 | **OD-16** — the 1–5 → Low/Steady/Strong mapping is an open owner decision, so the value is stated, not interpreted |
/// | `Sleep 5/7` | `sleep_hours` / `sleep_hours_avg` | **different statistic.** The board counts nights; the schema stores average hours. `5/7` cannot be derived from `7.2` |
/// | `Sessions 4/4` | — | **absent.** Completed-against-prescribed is not on the check-in, and joining a week's prescription to a session count is not something this row knows |
///
/// Two are rendered from what exists, one states its value under OD-16, and
/// one is omitted rather than invented. Recorded as **OD-24**.
library;

/// Where the open check-in sits in the coach's pending queue.
class ReviewPosition {
  /// Zero-based.
  final int index;
  final int total;

  const ReviewPosition({required this.index, required this.total});

  /// `1 of 6` — the board's phrasing, one-based for a human.
  String get line => '${index + 1} of $total';

  bool get hasNext => index + 1 < total;
}

/// Where `id` sits in `queue`, or null when it is not in it.
///
/// Null rather than a guessed position: a check-in that has left the queue —
/// reviewed in another tab, withdrawn — must not be drawn as `1 of 6` when it
/// is no longer one of them.
ReviewPosition? reviewPosition(List<Map<String, dynamic>> queue, String? id) {
  if (id == null || queue.isEmpty) return null;
  final i = queue.indexWhere((c) => c['id'] == id);
  if (i < 0) return null;
  return ReviewPosition(index: i, total: queue.length);
}

/// `Week 14 · 1 of 6`.
///
/// Each half is omitted when unknown rather than filled in, so an unqueued
/// check-in still shows its week and a check-in with no week number still
/// shows its position.
String reviewHeaderLine({int? weekNumber, ReviewPosition? position}) => [
      if (weekNumber != null && weekNumber > 0) 'Week $weekNumber',
      if (position != null) position.line,
    ].join(' · ');

/// The next check-in in the queue, or null when this is the last.
Map<String, dynamic>? nextInQueue(
    List<Map<String, dynamic>> queue, String? currentId) {
  final p = reviewPosition(queue, currentId);
  if (p == null || !p.hasNext) return null;
  return queue[p.index + 1];
}

/// The primary action's label.
///
/// The board writes `Send and open next`. On the **last** check-in there is no
/// next, and a button must not promise one — so it reads `Send`, which is the
/// package's own word (FIT-026 labels the chat composer's control exactly
/// that). Not invented vocabulary; the shorter of two words the package
/// already uses.
String primaryActionLabel(ReviewPosition? position) =>
    (position?.hasNext ?? false) ? 'Send and open next' : 'Send';

/// The heading above the client's own words.
///
/// The board writes **`She wrote`**, because Amara is its example. Applying a
/// pronoun to a real client would misgender them, and the package gives no
/// non-gendered alternative — so this says the same thing without one. The
/// same decision the check-in detail screen already made for
/// *"She usually replies within a day"*.
const clientWroteHeading = 'They wrote';

/// The heading above the coach's reply — the board's own words.
const coachReplyHeading = 'Your reply';

/// One stat on the review header.
class ReviewStat {
  final String label;

  /// What the data says. Never a placeholder — a stat with no value is not
  /// constructed at all.
  final String value;

  const ReviewStat({required this.label, required this.value});
}

String? _pct(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null) return null;
  final i = n.round();
  if (i < 0 || i > 100) return null;
  return '$i%';
}

/// The stats this check-in can actually support, in the board's order.
///
/// Returns only what the row knows. An absent column produces no stat rather
/// than a dash, a zero or a guess — a coach reading `Sleep 0/7` would act on
/// a number nobody recorded.
List<ReviewStat> reviewStats(Map<String, dynamic> row) {
  final out = <ReviewStat>[];

  // `Energy Steady` on the board. OD-16: the 1–5 → Low/Steady/Strong mapping
  // is an open owner decision about what a coach is being TOLD, so the value
  // is stated and not interpreted. Identical treatment to FIT-004 and
  // FIT-023, and a test asserts the three words are not produced.
  final energy = row['energy_level'] ?? row['energy'];
  final e = energy is num ? energy : num.tryParse('${energy ?? ''}');
  if (e != null && e >= 1 && e <= 5) {
    out.add(ReviewStat(label: 'Energy', value: '${e.round()} of 5'));
  }

  // `Sleep 5/7` on the board — nights. The schema stores average hours, which
  // is a different statistic and cannot be converted into it. What exists is
  // shown, labelled for what it is.
  final sleep = row['sleep_hours'] ?? row['sleep_hours_avg'];
  final s = sleep is num ? sleep : num.tryParse('${sleep ?? ''}');
  if (s != null && s > 0) {
    final txt = s == s.roundToDouble()
        ? s.round().toString()
        : s.toStringAsFixed(1);
    out.add(ReviewStat(label: 'Sleep', value: '$txt h avg'));
  }

  // `Sessions 4/4` is not on this row in any form — see OD-24. Omitted.

  // `Nutrition 92%` — the one that maps exactly.
  final nutrition = _pct(row['compliance_percent']);
  if (nutrition != null) {
    out.add(ReviewStat(label: 'Nutrition', value: nutrition));
  }

  return out;
}

/// The client's own words on the check-in, or null when they wrote none.
String? clientNote(Map<String, dynamic> row) {
  final n = (row['notes'] as String?)?.trim();
  return (n == null || n.isEmpty) ? null : n;
}

/// `Amara Osei`, assembled from the joined profile — or null.
///
/// A review screen that cannot name whose check-in it is showing has a worse
/// problem than a missing label, so the caller is expected to handle null
/// rather than be handed `Client`.
String? clientName(Map<String, dynamic> row) {
  final p = row['user_profiles'];
  if (p is! Map) return null;
  final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  return n.isEmpty ? null : n;
}
