import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/domain/coach_name.dart';
import '../data/models/checkin_model.dart';

/// FIT-023 · Check-in hub — "`/checkins` · status and history".
///
/// The pure half: how a week of check-in history reads, and what the screen is
/// allowed to say when the read fails.
///
/// ── THE ROW THE ANCHOR DRAWS ───────────────────────────────────────────────
/// `Week 13 · Energy steady · Nadia replied`. Three parts, and only two of them
/// can be built from this repository's data without a decision:
///
///   * `Week 13` — `WeeklyCheckin.weekNumber`.
///   * `Nadia replied` — `feedback.coachName`, or the package's own
///     "Awaiting reply" (FIT-025's screen name) when there is none.
///   * `Energy steady` — **not built.** The stored value is 1–5. Turning it
///     into Low / Steady / Strong means choosing thresholds on a number a coach
///     reads, which is the same decision FIT-004's difficulty mapping is
///     blocked on (OD-16). The row reports `Energy 3 of 5` instead — the exact
///     phrasing already used for these controls' accessible names — which
///     states the data without interpreting it.
///
/// ── AND THE RULE ───────────────────────────────────────────────────────────
/// Same as FIT-005 and FIT-027, because it is the same defect class: **a failed
/// history read must never be drawn as "no history".** Under a heading that
/// says history, an absence is an answer — it tells a client who has checked in
/// for thirteen weeks that they never have.
enum CheckinHistoryState { loading, failed, empty, data }

typedef CheckinHistory = ({
  CheckinHistoryState state,
  List<WeeklyCheckin> weeks,
});

/// How many weeks the hub lists.
const checkinHistoryLimit = 6;

/// Derives the history section from the read.
///
/// Matches on the STATE, never on `.valueOrNull` — an error's value and an
/// empty result's value are the same null at the call site, which is how the
/// `/profile` "No coach assigned yet" collapse worked.
CheckinHistory historyFrom(AsyncValue<List<WeeklyCheckin>> source,
    {int limit = checkinHistoryLimit}) {
  return switch (source) {
    AsyncError() => (state: CheckinHistoryState.failed, weeks: const []),
    AsyncValue(:final List<WeeklyCheckin> value) => value.isEmpty
        ? (state: CheckinHistoryState.empty, weeks: const [])
        : (
            state: CheckinHistoryState.data,
            weeks: value.take(limit).toList(),
          ),
    _ => (state: CheckinHistoryState.loading, weeks: const []),
  };
}

/// `Week 13`.
String weekLabel(WeeklyCheckin c) => 'Week ${c.weekNumber}';

/// The reply half of the row.
///
/// `Nadia replied` when a coach has, `Awaiting reply` when not — the latter
/// being FIT-025's own screen name, so neither is invented.
///
/// A submitted check-in with no feedback and a **pending** one are different
/// things, and the row says so: nothing has been sent yet, so nobody is
/// awaiting anything.
String? replyLabel(WeeklyCheckin c) {
  final coach = c.feedback?.coachName.trim();
  if (coach != null && coach.isNotEmpty) return '$coach replied';
  if (c.feedback != null) return 'Replied';
  return c.status == CheckinStatus.pending ? null : 'Awaiting reply';
}

/// The energy part of the row, stated rather than interpreted.
///
/// Returns null when the week carries no energy answer — a row that says
/// "Energy 0 of 5" would be reporting a value nobody gave.
String? energyLabel(WeeklyCheckin c) {
  final answer = c.responses
      .where((r) => r.questionId.toLowerCase().contains('energy'))
      .map((r) => r.answer)
      .firstOrNull;
  final value = switch (answer) {
    final int i => i,
    final double d => d.round(),
    final String s => int.tryParse(s),
    _ => null,
  };
  if (value == null || value < 1 || value > 5) return null;
  return 'Energy $value of 5';
}

/// The whole row: `Week 13 · Energy 3 of 5 · Nadia replied`.
String historyLine(WeeklyCheckin c) => [
      weekLabel(c),
      energyLabel(c),
      replyLabel(c),
    ].whereType<String>().join(' · ');

/// The already-shipped failure lines.
///
/// `Could not load [noun]` is the pattern this repository renders in fifteen
/// files. A bespoke sentence for this screen would be new product copy and
/// would need OD-8.
const checkinHistoryFailure = 'Could not load check-ins';
const checkinSessionsFailure = 'Could not load sessions';

// ── FIT-004 · Check-In — "Private and intentional, not a database form" ──────

/// The submit button's label.
///
/// The anchor draws **"Send to Nadia"** — the client's coach, by name. The name
/// is real data (`assignedCoachProvider` → `public_profiles.first_name`), so
/// using it invents nothing. What must not happen is the two failure modes
/// either side of it:
///
///   * naming a coach the client does not have, and
///   * naming one when the read **failed**, which is the `/profile`
///     "No coach assigned yet" collapse turned inside out.
///
/// So the name is used only when it is loaded and non-empty. Everything else —
/// loading, failed, no coach, a coach with no first name — falls back to
/// `Submit Check-In`, the label this screen already ships. A client with no
/// coach is not shown a button addressed to nobody.
String checkinSubmitLabel(AsyncValue<Map<String, dynamic>?> coach) =>
    coachAddressed(coach,
        withName: (name) => 'Send to $name',
        // The label this screen already ships. A client with no coach is not
        // shown a button addressed to nobody.
        fallback: 'Submit Check-In');

// ── FIT-024 / FIT-025 · Check-in detail ──────────────────────────────────────

// The check-in the client opened is held by `selectedCheckinProvider` in
// `checkin_provider.dart`, which already existed and is what `CheckinCard`
// sets. A second provider of the same name was briefly declared here; see the
// correction recorded in docs/QA_EVIDENCE.md.

/// The board draws the answers as **label-value rows** — "quick to scan, and
/// they hold at large Dynamic Type where a table wouldn't".
typedef CheckinAnswer = ({String label, String value});

/// The answers, in the board's order, skipping anything the week does not
/// carry.
///
/// **Energy is stated, not interpreted.** The board writes "Steady"; the stored
/// value is 1–5, and mapping one to the other is OD-16 — the same decision
/// FIT-023's history row leaves alone. A row that is not there is better than a
/// row that guesses.
List<CheckinAnswer> checkinAnswers(WeeklyCheckin c) {
  Object? raw(String id) => c.responses
      .where((r) => r.questionId == id)
      .map((r) => r.answer)
      .firstOrNull;

  int? scale(String id) {
    final v = raw(id);
    final n = switch (v) {
      final int i => i,
      final double d => d.round(),
      final String s => int.tryParse(s),
      _ => null,
    };
    return (n == null || n < 1 || n > 5) ? null : n;
  }

  final out = <CheckinAnswer>[];
  final energy = scale('energy');
  if (energy != null) out.add((label: 'Energy', value: '$energy of 5'));

  final sleep = raw('sleep_hours_avg');
  final hours = switch (sleep) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
  if (hours != null) {
    // "5 of 7 nights" on the board counts nights; this product stores average
    // hours. Reporting hours as nights would be a different measurement
    // wearing the board's label.
    out.add((label: 'Sleep', value: '${_trim(hours)} hours average'));
  }

  final stress = scale('stress_level');
  if (stress != null) out.add((label: 'Stress', value: '$stress of 5'));

  final mood = scale('mood');
  if (mood != null) out.add((label: 'Mood', value: '$mood of 5'));

  return out;
}

/// What the client wrote, or null when they wrote nothing.
String? checkinNote(WeeklyCheckin c) {
  final v = c.responses
      .where((r) => r.questionId == 'notes')
      .map((r) => r.answer)
      .firstOrNull;
  final s = v is String ? v.trim() : null;
  return (s == null || s.isEmpty) ? null : s;
}

/// `Sent Sunday 31 August`, or null before it was sent.
String? checkinSentLine(WeeklyCheckin c) {
  final at = c.submittedAt;
  if (at == null) return null;
  final l = at.toLocal();
  return 'Sent ${_weekdays[l.weekday - 1]} ${l.day} ${_monthsLong[l.month - 1]}';
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

