/// FIT-032 · "Coach dashboard — triage, not a wall".
///
/// ── THE PRODUCT DECISION, IN THE BOARD'S OWN WORDS ─────────────────────────
/// *"A coach with 24 clients does not need 24 rows on open — they need the six
/// that need something, each with the action named. 'Needs you today' is
/// triage; the roster is one tap away. Coach nav is unchanged."*
///
/// Four rows are drawn, each a client, a reason, and an action word:
///
///   Amara Osei    Week 14 check-in · travel next week   Review
///   Tomas Vidal   No sessions logged in 9 days          At risk
///   Priya Raman   Block ends Sunday · needs next        Assign
///   Lena Fischer  Asked about the split squat           Reply
///
/// …then `and two more`, against a `6 Need you` stat. So the list is **capped
/// at four with the remainder counted**, not scrolled.
///
/// ── WHAT THESE RULES MAY READ, AND WHY IT IS NOT EVERYTHING ────────────────
/// Every signal below is derived from a source a coach is **authorized** to
/// read. That is not a formality — see `SEC-G3`
/// (`test/unit/declared_denied_read_guard_test.dart`) and QA_EVIDENCE §3ah:
///
///   * `weekly_checkins` — `114_rls_weekly_checkins.sql`, owner **or**
///     `is_active_coach_of`;
///   * `workout_sessions` — `100_rls_harden_client_data.sql`, owner **or**
///     `is_active_coach_of`, FOR SELECT;
///   * `messages` / `conversations` — participant-scoped, and the coach is a
///     participant of their own thread.
///
/// **`workout_logs` is deliberately not a source.** It carries one policy,
/// `USING (user_id = auth.uid())`, and no coach clause exists in any of the
/// 131 migrations. An RLS-filtered SELECT is not an error — PostgREST answers
/// `200` with `[]` — so an `At risk` row built on it would fire for **every
/// client, always**, telling a coach everyone had stopped training when the
/// truth is the coach cannot see. `workout_sessions` answers the same question
/// and a coach is permitted to ask it.
///
/// ── AND WHAT IS NOT DECIDED HERE ───────────────────────────────────────────
/// The board shows *values* — "9 days", "Sunday" — not *thresholds*. How long
/// a silence must last before a coach is told a client is at risk, and how far
/// ahead a block's end should surface, are product judgements about what a
/// coach is being told, and this file does not make them. Both are **required
/// parameters with no default**, so no caller can adopt a number by accident,
/// and the values chosen are recorded as **OD-21**.
///
/// The one threshold that *is* fixed is the one already shipped:
/// `coach_dashboard_screen.dart:565` treats `churn_risk >= 50` as drop-off
/// risk today. Reusing it is not a new decision.
library;

enum TriageKind { review, atRisk, assign, reply }

/// The board's word for each row's action.
///
/// `At risk` is a state, not an imperative, and the board writes it that way.
/// It is not "improved" into "Check in" here: the package chose the word.
const _actions = {
  TriageKind.review: 'Review',
  TriageKind.atRisk: 'At risk',
  TriageKind.assign: 'Assign',
  TriageKind.reply: 'Reply',
};

/// The order the board lists them in.
///
/// It is the board's order and nothing more. No priority between a silent
/// client and an unanswered question is stated anywhere in the package, and
/// inventing one would be asserting a coaching judgement the design did not
/// make. Recorded rather than derived.
const _boardOrder = [
  TriageKind.review,
  TriageKind.atRisk,
  TriageKind.assign,
  TriageKind.reply,
];

/// One client, one reason, one action.
class TriageItem {
  final String clientId;

  /// The client's name as it will be read aloud. Never a placeholder: a client
  /// whose name cannot be resolved does not get a row, because "Client" needs
  /// you today is not triage.
  final String clientName;

  /// The board's middle line — `Week 14 check-in · travel next week`.
  final String detail;

  final TriageKind kind;

  const TriageItem({
    required this.clientId,
    required this.clientName,
    required this.detail,
    required this.kind,
  });

  String get action => _actions[kind]!;

  /// `Amara Osei Week 14 check-in · travel next week Review` — the shape the
  /// manifest declares for these rows.
  String get label => '$clientName $detail $action';
}

/// A client's state, assembled from the authorized sources by the caller.
///
/// Every field is nullable because every one of them can legitimately be
/// unknown, and "unknown" must never be rendered as a number. A null
/// `daysSinceLastSession` means *no completed session is on record* — which is
/// not the same as a long silence and does not produce an `At risk` row on its
/// own, because a client who has just started has no sessions either.
class ClientSignals {
  final String clientId;
  final String? clientName;

  /// The most recent submitted weekly check-in awaiting a coach reply, if any.
  final int? unrepliedCheckinWeek;

  /// What the client wrote on it, already trimmed to an excerpt by the caller.
  final String? unrepliedCheckinNote;

  /// Whole days since the last **completed** `workout_sessions` row.
  final int? daysSinceLastSession;

  /// `churn_risk` from `coach_client_ai_signals()`, 0–100.
  final int? churnRisk;

  /// Days until the assigned programme's last day, negative once past.
  final int? daysUntilBlockEnds;

  /// The weekday that block ends on — `Sunday` — when it is known.
  final String? blockEndsOn;

  /// True when a later assignment already exists, so nothing is needed.
  final bool hasNextBlock;

  /// The client's most recent unanswered message, already excerpted.
  final String? unansweredMessage;

  const ClientSignals({
    required this.clientId,
    this.clientName,
    this.unrepliedCheckinWeek,
    this.unrepliedCheckinNote,
    this.daysSinceLastSession,
    this.churnRisk,
    this.daysUntilBlockEnds,
    this.blockEndsOn,
    this.hasNextBlock = false,
    this.unansweredMessage,
  });
}

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// The board's shipped drop-off threshold — `coach_dashboard_screen.dart:565`.
const churnRiskThreshold = 50;

/// Every reason this client needs the coach today, in the board's order.
///
/// A client can need more than one thing. The board draws one row per client
/// per reason (four rows, four clients), and says nothing about a client with
/// two — so both are produced and the caller decides, rather than a silent
/// de-duplication rule being invented here.
List<TriageItem> triageFor(
  ClientSignals c, {
  required int inactivityDays,
  required int blockEndHorizonDays,
}) {
  final name = _clean(c.clientName);
  // No name, no row. A triage list is a list of people.
  if (name == null) return const [];

  final out = <TriageItem>[];

  TriageItem item(TriageKind kind, String detail) => TriageItem(
        clientId: c.clientId,
        clientName: name,
        detail: detail,
        kind: kind,
      );

  // ── Review ───────────────────────────────────────────────────────────────
  final week = c.unrepliedCheckinWeek;
  if (week != null) {
    final note = _clean(c.unrepliedCheckinNote);
    out.add(item(
      TriageKind.review,
      note == null ? 'Week $week check-in' : 'Week $week check-in · $note',
    ));
  }

  // ── At risk ──────────────────────────────────────────────────────────────
  // Two independent triggers, both grounded: the shipped churn threshold, and
  // a silence the caller has defined. A client with no sessions AT ALL is not
  // silent — they have not started — so `null` triggers neither.
  final days = c.daysSinceLastSession;
  final churn = c.churnRisk;
  final silent = days != null && days >= inactivityDays;
  final risky = churn != null && churn >= churnRiskThreshold;
  if (silent || risky) {
    out.add(item(
      TriageKind.atRisk,
      // The board states the fact it knows. When the only trigger is the risk
      // score, the day count is not asserted — there may not be one.
      days == null
          ? 'Flagged at risk of dropping off'
          : 'No sessions logged in $days days',
    ));
  }

  // ── Assign ───────────────────────────────────────────────────────────────
  final until = c.daysUntilBlockEnds;
  if (!c.hasNextBlock && until != null && until <= blockEndHorizonDays) {
    final on = _clean(c.blockEndsOn);
    out.add(item(
      TriageKind.assign,
      on == null ? 'Block ended · needs next' : 'Block ends $on · needs next',
    ));
  }

  // ── Reply ────────────────────────────────────────────────────────────────
  final asked = _clean(c.unansweredMessage);
  if (asked != null) out.add(item(TriageKind.reply, asked));

  out.sort((a, b) =>
      _boardOrder.indexOf(a.kind).compareTo(_boardOrder.indexOf(b.kind)));
  return out;
}

/// The whole list, in the board's order, across every client.
List<TriageItem> needsYouToday(
  Iterable<ClientSignals> clients, {
  required int inactivityDays,
  required int blockEndHorizonDays,
}) {
  final out = <TriageItem>[];
  for (final c in clients) {
    out.addAll(triageFor(c,
        inactivityDays: inactivityDays,
        blockEndHorizonDays: blockEndHorizonDays));
  }
  out.sort((a, b) =>
      _boardOrder.indexOf(a.kind).compareTo(_boardOrder.indexOf(b.kind)));
  return out;
}

/// The board draws four and counts the rest.
const triageVisibleCap = 4;

List<TriageItem> visibleTriage(List<TriageItem> all) =>
    all.length <= triageVisibleCap ? all : all.take(triageVisibleCap).toList();

/// `and two more`, or nothing when everything is on screen.
///
/// Spelled out to ten, because the board writes `and two more` and not
/// `and 2 more`. Beyond that a numeral reads better than `and seventeen more`.
String? triageOverflowLine(List<TriageItem> all) {
  final hidden = all.length - triageVisibleCap;
  if (hidden <= 0) return null;
  const words = [
    '', 'one', 'two', 'three', 'four', 'five',
    'six', 'seven', 'eight', 'nine', 'ten',
  ];
  final n = hidden <= 10 ? words[hidden] : '$hidden';
  return 'and $n more';
}

/// The `All 24 clients` control, with the real roster size.
///
/// Singular when there is one. A coach with no clients is not offered a roster
/// of nobody — the caller gets `null` and draws nothing.
String? allClientsLabel(int count) {
  if (count <= 0) return null;
  return count == 1 ? 'All 1 client' : 'All $count clients';
}
