/// V5 §163 — models for the owner-approved Admin metric surfaces
/// (migrations 171–173).
///
/// THE ONE RULE THIS FILE EXISTS TO ENFORCE. Every numeric field is nullable, and
/// nothing in here ever writes `?? 0`. The SQL behind these views deliberately
/// distinguishes three states, and collapsing them in Dart would quietly undo a
/// security property and a governance rule:
///
///   * a **missing row** — the caller holds no capability for the area at all;
///   * a **null column** — the caller is not authorized for *that figure*, which is
///     how METRIC-02 keeps a `Users`-only role from reading the Security-owned
///     sign-in basis (ruling `B-1`);
///   * a **zero** — a real, measured zero.
///
/// `?? 0` turns "you may not see this" and "nothing was recorded" into "the answer
/// is none". For METRIC-02 that would be an indirect disclosure dressed as a
/// number; for METRIC-06 it would fabricate a monetary value the owner's
/// calculation forbids. So the UI asks `isAvailable` and renders the approved `A11`
/// empty state, rather than a confident zero.
library;

import 'dart:convert';

/// Why a figure has no value. The UI needs the distinction: one of these is an
/// authorization outcome and the other is an absence of data.
enum MetricAbsence {
  /// The caller lacks the capability that gates this particular figure.
  notAuthorized,

  /// The caller is authorized, but nothing has been recorded or measured.
  notRecorded,
}

/// METRIC-02 · activity on two bases, each gated independently.
class AdminActivityOverview {
  const AdminActivityOverview({
    required this.sessionUsersToday,
    required this.sessionUsersWeek,
    required this.sessionUsersMonth,
    required this.sessionUsersPrevMonth,
    required this.signInUsersToday,
    required this.signInUsersWeek,
    required this.signInUsersMonth,
    required this.signInUsersPrevMonth,
    required this.sessionsToday,
    required this.sessionsMonth,
    required this.dayStart,
    required this.weekStart,
    required this.monthStart,
    required this.windowTimezone,
    required this.sessionUsersTodayByRole,
    required this.sessionUsersWeekByRole,
    required this.sessionUsersMonthByRole,
    required this.signInUsersTodayByRole,
    required this.signInUsersWeekByRole,
    required this.signInUsersMonthByRole,
  });

  final int? sessionUsersToday;
  final int? sessionUsersWeek;
  final int? sessionUsersMonth;
  final int? sessionUsersPrevMonth;

  final int? signInUsersToday;
  final int? signInUsersWeek;
  final int? signInUsersMonth;
  final int? signInUsersPrevMonth;

  /// SESSION COUNTS, not user counts. A member who trains twice in a day is ONE active
  /// user and TWO Sessions, and the approved design shows both — "947 Daily sessions"
  /// beside the DAU figure, which the data contract (:97) calls distinct required
  /// measures. Rendering one as the other would misreport engagement in whichever
  /// direction the population happens to lean.
  final int? sessionsToday;
  final int? sessionsMonth;

  /// The boundaries the figures above were actually computed over, and the timezone
  /// they were computed in. These exist because the data contract (:98) names the
  /// timezone as a sub-question the owner's definition must settle, and it is not
  /// settled. An undisclosed window is an assumption the reader cannot check; a
  /// disclosed one is a fact they can.
  final DateTime? dayStart;
  final DateTime? weekStart;
  final DateTime? monthStart;
  final String? windowTimezone;

  /// Q2 / `METRIC-02` sub-answer (migration 181) — the active-user ROLE SPLIT,
  /// published beside each total.
  ///
  /// The owner ruled the population is ALL users *"with the role split PUBLISHED
  /// beside the total … so a reader can apply either definition."* These are
  /// role→count maps rather than named `clients` / `coaches` / `partners` fields
  /// for the reason the migration gives: collapsing the schema's seven roles into
  /// buckets would be a metric definition nobody issued, and it would foreclose
  /// exactly the choice the ruling says the reader must keep.
  ///
  /// The same three states as every other field here, and for the same reason: a
  /// **null map** is "not authorized for this basis" (Session on `Users·view`,
  /// sign-in on `Security·view` per `B-1`), while an **empty map** is a measured
  /// emptiness — nobody was active. Rendering the first as the second would tell a
  /// reader "no coaches were active" when the truth is that they may not know.
  final Map<String, int>? sessionUsersTodayByRole;
  final Map<String, int>? sessionUsersWeekByRole;
  final Map<String, int>? sessionUsersMonthByRole;
  final Map<String, int>? signInUsersTodayByRole;
  final Map<String, int>? signInUsersWeekByRole;
  final Map<String, int>? signInUsersMonthByRole;

  /// The Session basis is gated on `Users·view`.
  bool get hasSessionBasis => sessionUsersToday != null;

  /// The sign-in basis is gated on `Security·view`, because it reads
  /// `audit_events` category `authentication`. A role without it gets null here
  /// and MUST NOT be shown a zero.
  bool get hasSignInBasis => signInUsersToday != null;

  /// Month-on-month delta, or null when the basis is unavailable. Returns null
  /// rather than 0 when the previous month is unknown — an unknown delta and a
  /// flat month are different findings.
  int? get sessionMonthDelta =>
      (sessionUsersMonth == null || sessionUsersPrevMonth == null)
          ? null
          : sessionUsersMonth! - sessionUsersPrevMonth!;

  int? get signInMonthDelta =>
      (signInUsersMonth == null || signInUsersPrevMonth == null)
          ? null
          : signInUsersMonth! - signInUsersPrevMonth!;

  static AdminActivityOverview fromRow(Map<String, dynamic> r) =>
      AdminActivityOverview(
        sessionUsersToday: _int(r['session_users_today']),
        sessionUsersWeek: _int(r['session_users_week']),
        sessionUsersMonth: _int(r['session_users_month']),
        sessionUsersPrevMonth: _int(r['session_users_prev_month']),
        signInUsersToday: _int(r['signin_users_today']),
        signInUsersWeek: _int(r['signin_users_week']),
        signInUsersMonth: _int(r['signin_users_month']),
        signInUsersPrevMonth: _int(r['signin_users_prev_month']),
        sessionsToday: _int(r['sessions_today']),
        sessionsMonth: _int(r['sessions_month']),
        dayStart: _date(r['day_start']),
        weekStart: _date(r['week_start']),
        monthStart: _date(r['month_start']),
        windowTimezone: r['window_timezone'] as String?,
        sessionUsersTodayByRole: _roleMap(r['session_users_today_by_role']),
        sessionUsersWeekByRole: _roleMap(r['session_users_week_by_role']),
        sessionUsersMonthByRole: _roleMap(r['session_users_month_by_role']),
        signInUsersTodayByRole: _roleMap(r['signin_users_today_by_role']),
        signInUsersWeekByRole: _roleMap(r['signin_users_week_by_role']),
        signInUsersMonthByRole: _roleMap(r['signin_users_month_by_role']),
      );
}

/// METRIC-03 + METRIC-17, alongside the role counts from migration 166.
class AdminUserOverview {
  const AdminUserOverview({
    required this.usersTotal,
    required this.clientsTotal,
    required this.coachesTotal,
    required this.vendorsTotal,
    required this.coachesActiveThisMonth,
    required this.coachesNoClientThisMonth,
    required this.coachClientsServed,
    required this.coachClientsPerActiveCoach,
    required this.age18to30,
    required this.age30to45,
    required this.age45to60,
    required this.ageUnknown,
    required this.ageOutOfRange,
  });

  final int? usersTotal;
  final int? clientsTotal;
  final int? coachesTotal;

  /// METRIC-05 = Option 2: the total only. There is deliberately no
  /// "awaiting approval" sub-count — no approval state machine exists and none
  /// was invented.
  final int? vendorsTotal;

  final int? coachesActiveThisMonth;
  final int? coachesNoClientThisMonth;

  /// Active coach–client relationships. A REAL COUNT: 0 means no active relationship
  /// exists, which is a fact and renders as the design's zero wording.
  final int? coachClientsServed;

  /// The average per ACTIVE coach, and the denominator is not a choice: the approved card
  /// reads 2,210 · "avg 15.7 per coach" · Active "141 of 164", and 2210/141 = 15.7 where
  /// 2210/164 would print 13.5. Null when there is no active coach to divide by — "nobody
  /// to average over" is not an average of zero.
  final double? coachClientsPerActiveCoach;

  final int? age18to30;
  final int? age30to45;
  final int? age45to60;

  /// METRIC-17 = Option 2: the fourth bucket.
  final int? ageUnknown;

  /// NOT a fifth bucket, and must never be rendered as one. An age of 60 or above
  /// has no ruled bucket; this column carries those rows so the panel reconciles
  /// to [usersTotal] instead of silently dropping people.
  final int? ageOutOfRange;

  /// True when the four approved buckets plus the reconciliation column account
  /// for every user. A false here means the panel is lying about its own total.
  bool get bucketsReconcile {
    final parts = [age18to30, age30to45, age45to60, ageUnknown, ageOutOfRange];
    if (usersTotal == null || parts.any((p) => p == null)) return false;
    return parts.fold<int>(0, (a, p) => a + p!) == usersTotal;
  }

  static AdminUserOverview fromRow(Map<String, dynamic> r) => AdminUserOverview(
        usersTotal: _int(r['users_total']),
        clientsTotal: _int(r['clients_total']),
        coachesTotal: _int(r['coaches_total']),
        vendorsTotal: _int(r['vendors_total']),
        coachesActiveThisMonth: _int(r['coaches_active_this_month']),
        coachesNoClientThisMonth: _int(r['coaches_no_client_this_month']),
        coachClientsServed: _int(r['coach_clients_served']),
        coachClientsPerActiveCoach:
            (r['coach_clients_per_active_coach'] as num?)?.toDouble(),
        age18to30: _int(r['age_18_30']),
        age30to45: _int(r['age_30_45']),
        age45to60: _int(r['age_45_60']),
        ageUnknown: _int(r['age_unknown']),
        ageOutOfRange: _int(r['age_out_of_range']),
      );
}

/// METRIC-14 · attendance, over the pre-existing `checked_in_at`.
class AdminEventsOverview {
  const AdminEventsOverview({
    required this.eventsTotal,
    required this.registrationsTotal,
    required this.registrationsAttended,
    required this.attendanceRatePct,
    required this.registrations30d,
  });

  final int? eventsTotal;
  final int? registrationsTotal;
  final int? registrationsAttended;

  /// Null when there is nothing to divide. The card renders `A11`, never `0%` —
  /// "no registrations" and "nobody turned up" are different statements.
  final double? attendanceRatePct;

  final int? registrations30d;

  static AdminEventsOverview fromRow(Map<String, dynamic> r) =>
      AdminEventsOverview(
        eventsTotal: _int(r['events_total']),
        registrationsTotal: _int(r['event_registrations_total']),
        registrationsAttended: _int(r['event_registrations_attended']),
        attendanceRatePct: _double(r['event_attendance_rate_pct']),
        registrations30d: _int(r['event_registrations_30d']),
      );
}

/// METRIC-13 · "pods" means `accountability_pods`.
class AdminCommunityOverview {
  const AdminCommunityOverview({
    required this.podsTotal,
    required this.podsActive,
    required this.communityGroupsTotal,
    required this.postsTotal,
    required this.postsVisible,
    required this.reportsOpen,
  });

  final int? podsTotal;
  final int? podsActive;

  /// Reported beside the pod count and never merged into it — they are different
  /// units and the design names them separately.
  final int? communityGroupsTotal;

  final int? postsTotal;
  final int? postsVisible;
  final int? reportsOpen;

  static AdminCommunityOverview fromRow(Map<String, dynamic> r) =>
      AdminCommunityOverview(
        podsTotal: _int(r['pods_total']),
        podsActive: _int(r['pods_active']),
        communityGroupsTotal: _int(r['community_groups_total']),
        postsTotal: _int(r['posts_total']),
        postsVisible: _int(r['posts_visible']),
        reportsOpen: _int(r['reports_open']),
      );
}

/// METRIC-06a + METRIC-06b · revenue, in the SOURCE currency.
class AdminRevenueOverview {
  const AdminRevenueOverview({
    required this.grossCoachingCents,
    required this.platformCommissionCents,
    required this.netPlatformCents,
    required this.sourceCurrency,
    required this.commissionRateMissing,
    required this.amountMissing,
    required this.excludedNonCoaching,
    required this.fxUsdGbpRate,
    required this.fxAsOf,
    required this.fxSource,
    required this.streams,
    required this.streamOtherCents,
    required this.streamOtherCount,
    required this.paidTotalCents,
    required this.coachPayoutCents,
    required this.platformFeeCents,
    required this.payoutMissing,
    required this.churnCancellationsMonth,
    required this.churnActiveAtMonthStart,
    required this.churnRatePct,
    required this.churnFirstCancellationAt,
    required this.churnDenominatorBasis,
  });

  final int? grossCoachingCents;
  final int? platformCommissionCents;
  final int? netPlatformCents;

  /// The currency the three figures above are actually denominated in.
  final String? sourceCurrency;

  /// Qualifying coaching payments whose `commission_rate` was never recorded.
  /// They ARE in gross and are NOT in commission, because no rate was
  /// substituted onto them. A non-zero value here means the commission figure is
  /// a floor, not a total — the UI must say so rather than imply precision.
  final int? commissionRateMissing;

  final int? amountMissing;
  final int? excludedNonCoaching;

  final double? fxUsdGbpRate;
  final DateTime? fxAsOf;
  final String? fxSource;

  /// Revenue BY STREAM, which the approved design requires on the Dashboard, keyed by
  /// the `create-checkout:52` vocabulary. Kept as a map rather than six fields so the
  /// UI iterates the vocabulary instead of hard-coding it — a seventh stream would
  /// otherwise need a code change in two places to become visible.
  final Map<String, int?> streams;

  /// Revenue whose `kind` is outside that vocabulary. `payments.kind` carries no CHECK
  /// constraint, so this is reachable — and it exists so the named streams plus this
  /// reconcile to [paidTotalCents]. Understating revenue by silently dropping a stream
  /// is the one direction a money figure must never be wrong in by accident.
  final int? streamOtherCents;
  final int? streamOtherCount;
  final int? paidTotalCents;

  /// The money split AS RECORDED (`038:24-25` — "cents to the coach", "cents to
  /// 12 Circle"). Never derived from `amount x commission_rate`: that would invent a
  /// second authority for a figure Stripe already settled.
  final int? coachPayoutCents;
  final int? platformFeeCents;

  /// Coaching payments carrying no recorded split, so the totals above are a floor.
  final int? payoutMissing;

  // ── OWNER DECISION Q11 · monthly subscription churn, event-based ─────────
  /// Cancellations RECORDED within the current month. A real count: 0 means no cancellation
  /// was recorded this month, which is a fact — it is [churnRatePct] that distinguishes
  /// "none this month" from "we were not recording".
  final int? churnCancellationsMonth;

  /// Subscriptions that existed before the month began and were not yet canceled then.
  final int? churnActiveAtMonthStart;

  /// NULL until any cancellation has EVER been recorded. The ruling is explicit: *"until
  /// sufficient real cancellation history exists, the Dashboard must render the appropriate
  /// A11 empty/insufficient-history state rather than a misleading 0%."* 0% would assert
  /// that nobody left; null says we cannot yet tell.
  final double? churnRatePct;

  /// The earliest recorded cancellation — how much history exists, as a fact. Null means
  /// none has been recorded, which is the insufficient-history condition itself.
  final DateTime? churnFirstCancellationAt;

  /// The denominator's basis, published by the view so the surface discloses it rather than
  /// restating it from memory.
  final String? churnDenominatorBasis;

  /// True while no cancellation has ever been recorded — the A11 insufficient-history
  /// state, distinguished from a measured zero.
  bool get churnHistoryInsufficient => churnFirstCancellationAt == null;

  /// True when every named stream plus `other` accounts for the paid total.
  bool get streamsReconcile {
    if (paidTotalCents == null || streamOtherCents == null) return false;
    var sum = streamOtherCents!;
    for (final v in streams.values) {
      if (v == null) return false;
      sum += v;
    }
    return sum == paidTotalCents;
  }

  /// True when the commission figure accounts for every qualifying payment.
  bool get commissionIsComplete => commissionRateMissing == 0;

  /// An explicitly recorded conversion, or null. THERE IS NO FALLBACK RATE AND
  /// THERE MUST NEVER BE ONE: the owner's calculation says "never fabricate a
  /// monetary value where the underlying source amount is unavailable", and a
  /// hardcoded or remembered rate is exactly that fabrication. Null means the UI
  /// shows the USD source figure, or the `A11` state — not a guess in pounds.
  int? gbpFrom(int? sourceCents) {
    if (sourceCents == null || fxUsdGbpRate == null) return null;
    return (sourceCents * fxUsdGbpRate!).round();
  }

  bool get hasRecordedFx =>
      fxUsdGbpRate != null && fxAsOf != null && fxSource != null;

  static AdminRevenueOverview fromRow(Map<String, dynamic> r) =>
      AdminRevenueOverview(
        grossCoachingCents: _int(r['gross_coaching_cents']),
        platformCommissionCents: _int(r['platform_commission_cents']),
        netPlatformCents: _int(r['net_platform_cents']),
        sourceCurrency: r['source_currency'] as String?,
        commissionRateMissing: _int(r['commission_rate_missing']),
        amountMissing: _int(r['amount_missing']),
        excludedNonCoaching: _int(r['excluded_non_coaching']),
        fxUsdGbpRate: _double(r['fx_usd_gbp_rate']),
        fxAsOf: _date(r['fx_as_of']),
        fxSource: r['fx_source'] as String?,
        streams: {
          for (final k in const [
            'coach', 'coach_plan', 'self_guided', 'ai_guided', 'event_ticket', 'package',
          ])
            k: _int(r['stream_${k}_cents']),
        },
        streamOtherCents: _int(r['stream_other_cents']),
        streamOtherCount: _int(r['stream_other_count']),
        paidTotalCents: _int(r['paid_total_cents']),
        coachPayoutCents: _int(r['coach_payout_cents']),
        platformFeeCents: _int(r['platform_fee_cents']),
        payoutMissing: _int(r['payout_missing']),
        churnCancellationsMonth: _int(r['churn_cancellations_month']),
        churnActiveAtMonthStart: _int(r['churn_active_at_month_start']),
        churnRatePct: (r['churn_rate_pct'] as num?)?.toDouble(),
        churnFirstCancellationAt: _date(r['churn_first_cancellation_at']),
        churnDenominatorBasis: r['churn_denominator_basis'] as String?,
      );
}

/// METRIC-11 · the CI verdict and the V5 gate verdict, as two states.
///
/// There is deliberately no combined getter. The owner ruled these "must not be
/// collapsed", and they currently disagree — CI green while the gate ledger
/// records failures. A convenience `bool get isReleasable` would assert a verdict
/// neither authority gave, so none exists.
class AdminReleaseStatus {
  const AdminReleaseStatus({
    required this.releaseVersion,
    required this.environment,
    required this.ciStatus,
    required this.ciChecksPassed,
    required this.ciChecksTotal,
    required this.ciSource,
    required this.ciRecordedAt,
    required this.gateVerdict,
    required this.gatesPass,
    required this.gatesPartial,
    required this.gatesFail,
    required this.gatesTotal,
    required this.gateSource,
    required this.gateRecordedAt,
  });

  final String? releaseVersion;
  final String? environment;

  final String? ciStatus;
  final int? ciChecksPassed;
  final int? ciChecksTotal;
  final String? ciSource;
  final DateTime? ciRecordedAt;

  final String? gateVerdict;
  final int? gatesPass;
  final int? gatesPartial;
  final int? gatesFail;
  final int? gatesTotal;
  final String? gateSource;
  final DateTime? gateRecordedAt;

  /// A verdict is only shown when its source and timestamp came with it — the
  /// same provenance rule the table enforces as a CHECK constraint.
  bool get hasCiVerdict =>
      ciStatus != null && ciSource != null && ciRecordedAt != null;

  bool get hasGateVerdict =>
      gateVerdict != null && gateSource != null && gateRecordedAt != null;

  /// True for the all-NULL row migration 174 returns to an AUTHORIZED caller when
  /// no release has been recorded. It is how a client tells "nothing is recorded"
  /// from "you may not see this" — the latter is no row at all, i.e. a null model.
  /// Without the distinction the card must either claim a permission failure that
  /// did not happen, or report an absence of data to someone who simply lacks the
  /// capability. Both are confident falsehoods.
  bool get isUnrecorded => releaseVersion == null && environment == null;

  static AdminReleaseStatus fromRow(Map<String, dynamic> r) =>
      AdminReleaseStatus(
        releaseVersion: r['release_version'] as String?,
        environment: r['environment'] as String?,
        ciStatus: r['ci_status'] as String?,
        ciChecksPassed: _int(r['ci_checks_passed']),
        ciChecksTotal: _int(r['ci_checks_total']),
        ciSource: r['ci_source'] as String?,
        ciRecordedAt: _date(r['ci_recorded_at']),
        gateVerdict: r['gate_verdict'] as String?,
        gatesPass: _int(r['gates_pass']),
        gatesPartial: _int(r['gates_partial']),
        gatesFail: _int(r['gates_fail']),
        gatesTotal: _int(r['gates_total']),
        gateSource: r['gate_source'] as String?,
        gateRecordedAt: _date(r['gate_recorded_at']),
      );
}

/// `DESIGN-01` §1 — an incident as the Admin layer may see it, from
/// `admin_incidents` (migration 160).
///
/// WHAT THIS MODEL CANNOT CARRY, BY DESIGN. Owner decision `B-4` withholds `evidence`
/// (unbounded free-form, which cannot be shown safe in advance) and `actor_identity`
/// (a DIRECT identity rather than a pseudonym, so an `A12` surface). The view does not
/// project them and this model has no field for them, so no UI can accidentally
/// request one.
class AdminIncident {
  const AdminIncident({
    required this.id,
    required this.summary,
    required this.occurredAt,
    required this.scope,
    required this.severity,
    required this.suspectedCause,
    required this.recommendedAction,
    required this.actionTaken,
    required this.resolution,
  });

  final String? id;
  final String? summary;
  final DateTime? occurredAt;
  final String? scope;

  /// The shipped `A2` scale — `Critical` · `High` · `Warning` · `Informational`,
  /// title case (`143:70`). METRIC-12 confirmed by evidence that an uppercase
  /// `CRITICAL` appears nowhere, so nothing here upper-cases it.
  final String? severity;

  final String? suspectedCause;
  final String? recommendedAction;
  final String? actionTaken;
  final String? resolution;

  bool get isCritical => severity == 'Critical';

  /// True when the item has something to show on open. `DESIGN-01` specifies a single
  /// primary action per item that OPENS it and changes nothing.
  bool get hasDetail =>
      (suspectedCause ?? recommendedAction ?? actionTaken ?? resolution) != null;

  static AdminIncident fromRow(Map<String, dynamic> r) => AdminIncident(
        id: r['id'] as String?,
        summary: r['summary'] as String?,
        occurredAt: _date(r['occurred_at']),
        scope: r['scope'] as String?,
        severity: r['severity'] as String?,
        suspectedCause: r['suspected_cause'] as String?,
        recommendedAction: r['recommended_action'] as String?,
        actionTaken: r['action_taken'] as String?,
        resolution: r['resolution'] as String?,
      );
}

/// `admin_training_overview` (migration 156) — raw counts, no derived rate.
class AdminTrainingOverview {
  const AdminTrainingOverview({
    required this.programsTotal,
    required this.workoutsTotal,
    required this.sessionsTotal,
    required this.logsTotal,
  });

  final int? programsTotal;
  final int? workoutsTotal;
  final int? sessionsTotal;
  final int? logsTotal;

  static AdminTrainingOverview fromRow(Map<String, dynamic> r) =>
      AdminTrainingOverview(
        programsTotal: _int(r['programs_total']),
        workoutsTotal: _int(r['workouts_total']),
        sessionsTotal: _int(r['sessions_total']),
        logsTotal: _int(r['logs_total']),
      );
}

/// Wearable CONNECTION counts, from `admin_integration_connections` (157).
///
/// THE CONNECTION HALF ONLY, AND THAT IS A RULING NOT A SHORTCUT. The data contract
/// splits this tile: *"its connection half is buildable now from `user_integrations`; its
/// ingestion-health half depends on `WI-13` and waits for `PD-G01`"*. So there is no
/// latency, no sync status and no error count here — `PD-G01` is `APPROVED — FUTURE BUILD ·
/// implementation NOT AUTHORIZED`, and inventing a health figure would cross it.
///
/// NO IDENTIFIER REACHES THE CLIENT. The view projects `user_id`, which an Admin holding
/// `Wearable intelligence·view` is authorized to read — but this page needs counts, so the
/// service selects `provider, connected` ONLY and the identifier never leaves the
/// database. Minimum necessary, rather than "authorized therefore fetched".
/// NOT a row-parsed model, and that is why its fields are non-nullable. It is COMPUTED
/// from rows the client already holds, so "unavailable" is expressed by the whole model
/// being null — a count derived from a list in hand cannot itself be unknown. Every model
/// that parses a surface row keeps `int?`, because there null means "you may not see this"
/// or "nothing was recorded"; see [AdminActivityOverview].
class AdminWearableConnections {
  const AdminWearableConnections({required this.byProvider, required this.connectedTotal});

  /// provider → number of CONNECTED rows. A provider the vocabulary does not know is
  /// still counted: `user_integrations.provider` is `TEXT NOT NULL` with no CHECK
  /// (`011:32`), so an unexpected value is reachable and dropping it would understate
  /// connections.
  final Map<String, int> byProvider;
  final int connectedTotal;

  static AdminWearableConnections fromRows(List<Map<String, dynamic>> rows) {
    final by = <String, int>{};
    var total = 0;
    for (final r in rows) {
      if (r['connected'] != true) continue;
      final p = (r['provider'] as String?) ?? 'unrecognised';
      // `update(..., ifAbsent:)` rather than `(by[p] ?? 0) + 1`: a map accumulator is
      // not a metric coercion, but writing it with `?? 0` puts the shape SEC-G4 hunts
      // into a file whose whole point is that the shape is absent.
      by.update(p, (v) => v + 1, ifAbsent: () => 1);
      total++;
    }
    return AdminWearableConnections(byProvider: by, connectedTotal: total);
  }
}

/// One row of `admin_user_directory` (migration 160) — exactly nine columns, and the
/// Users area's authorized projection.
///
/// IT CARRIES NAME AND EMAIL, BY DESIGN AND BY GRANT. 160 projects precisely nine columns
/// for the Users area, and the approved People page asks for *"account list with role,
/// status, last active"*. So this is not an over-read — but it is PII, and a surface
/// showing it should show only what that surface needs.
///
/// THERE IS NO `lastActive`. The design asks for it; which signal counts as "active" is
/// the open population question (data contract `:98`), and METRIC-02's ruling settled
/// which events count for a COUNT, not what makes one person active. Inventing a per-user
/// recency from `workout_sessions` would answer a question nobody asked.
class AdminUserDirectoryEntry {
  const AdminUserDirectoryEntry({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.membershipTier,
    required this.onboardingComplete,
    required this.createdAt,
  });

  final String? id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? role;
  final String? membershipTier;

  /// The nearest thing the schema has to the design's "status" — and it is named as what
  /// it is rather than relabelled "status", which would imply a state machine that does
  /// not exist (§77.3).
  final bool? onboardingComplete;
  final DateTime? createdAt;

  String get displayName {
    final parts = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? (email ?? 'unknown') : parts.join(' ');
  }

  static AdminUserDirectoryEntry fromRow(Map<String, dynamic> r) =>
      AdminUserDirectoryEntry(
        id: r['id'] as String?,
        firstName: r['first_name'] as String?,
        lastName: r['last_name'] as String?,
        email: r['email'] as String?,
        role: r['role'] as String?,
        membershipTier: r['membership_tier'] as String?,
        onboardingComplete: r['onboarding_complete'] as bool?,
        createdAt: _date(r['created_at']),
      );
}

/// The approved authorization matrix as the Admin layer may read it
/// (`admin_role_capabilities`, gated `Roles·view` by 156).
///
/// This is the `CONF-D7` artifact — migration 155 records *"Owner (Julia) approved the
/// complete 85-cell / 425-grant authorization policy"* — so the Settings `#roles` section
/// renders the governing policy itself rather than a description of it.
class AdminRoleCapability {
  const AdminRoleCapability({
    required this.adminRole,
    required this.area,
    required this.verb,
  });

  final String? adminRole;
  final String? area;
  final String? verb;

  static AdminRoleCapability fromRow(Map<String, dynamic> r) => AdminRoleCapability(
        adminRole: r['admin_role'] as String?,
        area: r['area'] as String?,
        verb: r['verb'] as String?,
      );
}

/// One `platform_settings` key. A generic key/value store, so the model carries the key
/// and the value AS TEXT and interprets neither — a settings page that parsed values
/// would be asserting a schema the table does not have.
class AdminPlatformSetting {
  const AdminPlatformSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String? key;
  final String? value;
  final DateTime? updatedAt;

  static AdminPlatformSetting fromRow(Map<String, dynamic> r) => AdminPlatformSetting(
        key: r['key'] as String?,
        value: r['value'] as String?,
        updatedAt: _date(r['updated_at']),
      );
}

/// One open report from the moderation queue (`content_reports`, migration 170).
///
/// THE REPORTER IS NOT CARRIED. `content_reports.reporter_id` exists and the Admin read
/// policy would return it, but a moderator does not need to know WHO reported a post in
/// order to judge the post — and a queue that names reporters is a queue that discourages
/// reporting. The service selects the columns below and leaves `reporter_id` in the
/// database. Minimum necessary, as with `avatar_url` on the People page.
///
/// THE REASON IS FREE TEXT AND STAYS THAT WAY. 170's own column comment is explicit —
/// *"FREE TEXT; a reason-code list is owner vocabulary"* — which is `CAP-1-REASON`,
/// deferred. So this carries whatever the reporter wrote and offers no enum.
class AdminContentReport {
  const AdminContentReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
  });

  final String? id;

  /// `post` or `comment` (170's CHECK).
  final String? targetType;
  final String? targetId;
  final String? reason;
  final DateTime? createdAt;

  static AdminContentReport fromRow(Map<String, dynamic> r) => AdminContentReport(
        id: r['id'] as String?,
        targetType: r['target_type'] as String?,
        targetId: r['target_id'] as String?,
        reason: r['reason'] as String?,
        createdAt: _date(r['created_at']),
      );
}

// ── parsing ────────────────────────────────────────────────────────────────
// PostgREST returns bigint and numeric as JSON numbers or strings depending on
// magnitude and type. Each of these returns null for a null or unparseable
// input; none of them defaults to zero.
/// Q2 · the role split's presentation vocabulary.
///
/// Labels only — this map never merges two role keys into one bucket, because that
/// would be the grouping migration 181 deliberately refuses to invent. A key that is
/// NOT listed here falls through to its raw value rather than being dropped, so a role
/// added to the schema's CHECK later still renders instead of silently vanishing from
/// a total's own breakdown.
const Map<String, String> adminRoleSplitLabels = {
  'client': 'Clients',
  'coach': 'Coaches',
  'vendor': 'Vendors',
  'admin': 'Admins',
  'content_manager': 'Content managers',
  'trust_operator': 'Trust operators',
  'erasure_executor': 'Erasure executors',
  // The two non-roles 181 keeps distinct. A missing profile and an unset column are
  // different findings and are labelled differently.
  'no_profile': 'No profile',
  'unrecorded': 'Role unrecorded',
};

/// Formats a role split for display, or returns null when there is nothing to show.
///
/// Null for BOTH a null map and an empty one, but for different reasons: a null map is
/// an absent authorization and must render nothing at all, and an empty map is a
/// measured zero whose own total already says `0` — appending "by role:" with nothing
/// after it would read as a defect rather than as a fact.
String? formatAdminRoleSplit(Map<String, int>? m) {
  if (m == null || m.isEmpty) return null;
  final keys = m.keys.toList()..sort();
  return keys
      .map((k) => '${adminRoleSplitLabels[k] ?? k} ${m[k]}')
      .join(' · ');
}

/// jsonb → `Map<String, int>?`, preserving the null/empty distinction above.
Map<String, int>? _roleMap(Object? v) {
  if (v == null) return null;
  if (v is Map) {
    final out = <String, int>{};
    v.forEach((k, value) {
      final parsed = _int(value);
      if (parsed != null) out[k.toString()] = parsed;
    });
    return out;
  }
  if (v is String) {
    // Some client paths hand jsonb back as an encoded string rather than a Map.
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return _roleMap(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

int? _int(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString());
}

double? _double(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// One row of the approved Ecosystem screen's Events directory.
///
/// WHY THIS IS NOT A VIEW. The directory needs no new surface: migration 156:45 already
/// grants `FOR SELECT TO authenticated USING (admin_can('Events','view'))` on
/// `public.events`, so an Events·view holder reads every event — drafts and cancelled
/// included. A dedicated aggregate view would have been the wrong instrument anyway:
/// `admin_events_overview` answers "how many", and this answers "which one", which is
/// what an edit action needs.
///
/// TWO COLUMNS OF THE APPROVED TABLE HAVE NO BACKING, and both are named rather than
/// filled:
///   · "Type" (Workshop/Social/Class) — `public.events` has no type column at all
///     (001:264, and the only later addition is `vendor_id` at 020:8). There is no
///     [type] field here because there is nothing to read.
///   · "Status" — the column exists, but it defaults to `'upcoming'` and carries no
///     CHECK, so it does not hold the design's Scheduled/Full/Live/Draft/Cancelled
///     vocabulary. [status] is therefore whatever is RECORDED, surfaced verbatim.
///     Mapping it onto the five designed labels would be inventing a state machine.
///
/// PRICE AND REVENUE ARE NOT SELECTED. `price` and `is_free` exist on the table, and the
/// approved screen gates event revenue behind "Needs the Finance viewer role" — a
/// Monetization capability this read does not test. Selecting them under an Events·view
/// gate would route a monetary figure around its own gate, so the query names its columns
/// explicitly instead of `select()`.
class AdminEventRow {
  const AdminEventRow({
    required this.id,
    required this.title,
    required this.location,
    required this.eventDate,
    required this.endDate,
    required this.hostName,
    required this.maxCapacity,
    required this.currentRegistered,
    required this.status,
    required this.description,
  });

  final String? id;
  final String? title;
  final String? location;
  final DateTime? eventDate;
  final DateTime? endDate;
  final String? hostName;
  final int? maxCapacity;
  final int? currentRegistered;

  /// As recorded — see the class note. Never relabelled.
  final String? status;
  final String? description;

  /// Null when EITHER side is missing, which is the three-state rule applied to a
  /// derived figure: an event with no recorded capacity has no occupancy, and 0 % would
  /// be a measurement nobody took.
  double? get occupancy {
    final cap = maxCapacity;
    final reg = currentRegistered;
    if (cap == null || reg == null || cap <= 0) return null;
    return reg / cap;
  }

  static AdminEventRow fromRow(Map<String, dynamic> r) => AdminEventRow(
        id: r['id'] as String?,
        title: r['title'] as String?,
        location: r['location'] as String?,
        eventDate: _date(r['event_date']),
        endDate: _date(r['end_date']),
        hostName: r['host_name'] as String?,
        maxCapacity: (r['max_capacity'] as num?)?.toInt(),
        currentRegistered: (r['current_registered'] as num?)?.toInt(),
        status: r['status'] as String?,
        description: r['description'] as String?,
      );
}
