import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';

/// V5 §163 — the Dart half of the metric contract.
///
/// These views deliberately distinguish "you may not see this" (null) from "the
/// measured answer is none" (zero). SQL enforces it; this file exists because a
/// single `?? 0` anywhere in the Dart layer would silently undo it, and nothing
/// in the live QA suite can see Dart code.
///
/// The sharpest assertion in this file is that a REAL ZERO IS NOT ABSENCE. An
/// `isAvailable` helper written as `value != null && value != 0`, or a model that
/// defaults nulls to zero, passes every naive test and fails this one.
void main() {
  mainRoleSplit();
  group('METRIC-02 · the two bases are independently available', () {
    // A `support` admin: holds Users/view, does NOT hold Security/view. This is
    // the row the live suite proves PostgREST actually returns for that role.
    final supportRow = <String, dynamic>{
      'session_users_today': 4,
      'session_users_week': 11,
      'session_users_month': 26,
      'session_users_prev_month': 19,
      'signin_users_today': null,
      'signin_users_week': null,
      'signin_users_month': null,
      'signin_users_prev_month': null,
    };

    test('a Users-only role gets the Session basis and NOT the sign-in basis', () {
      final m = AdminActivityOverview.fromRow(supportRow);
      expect(m.hasSessionBasis, isTrue);
      expect(m.hasSignInBasis, isFalse);
    });

    test('the unavailable basis stays NULL and is never coerced to zero — a zero '
        'would read as "nobody signed in", which is a false statement about a '
        'population this role may not query', () {
      final m = AdminActivityOverview.fromRow(supportRow);
      expect(m.signInUsersToday, isNull);
      expect(m.signInUsersMonth, isNull);
      expect(m.signInUsersToday, isNot(0));
    });

    test('A REAL ZERO IS NOT ABSENCE: an authorized role measuring zero sign-ins '
        'still HAS the basis', () {
      final m = AdminActivityOverview.fromRow({
        ...supportRow,
        'signin_users_today': 0,
        'signin_users_month': 0,
        'signin_users_prev_month': 0,
      });
      expect(m.hasSignInBasis, isTrue,
          reason: 'measuring zero is an answer; being unauthorized is not');
      expect(m.signInUsersToday, 0);
      expect(m.signInMonthDelta, 0);
    });

    test('a SESSION COUNT is not a user count, and an absent one stays null rather '
        'than borrowing the user figure', () {
      final m = AdminActivityOverview.fromRow({
        ...supportRow,
        'sessions_today': 9,
        'window_timezone': 'UTC',
        'day_start': '2026-10-07T00:00:00Z',
      });
      expect(m.sessionUsersToday, 4);
      expect(m.sessionsToday, 9);
      expect(m.sessionsMonth, isNull);
      expect(m.windowTimezone, 'UTC');
      expect(m.dayStart, DateTime.parse('2026-10-07T00:00:00Z'));
    });

    test('an undisclosed window stays null, so the UI omits the footnote rather than '
        'inventing a timezone', () {
      final m = AdminActivityOverview.fromRow(supportRow);
      expect(m.dayStart, isNull);
      expect(m.windowTimezone, isNull);
    });

    test('a delta is null when either month is unavailable — an unknown delta and '
        'a flat month are different findings', () {
      final m = AdminActivityOverview.fromRow(supportRow);
      expect(m.sessionMonthDelta, 7); // 26 - 19
      expect(m.signInMonthDelta, isNull);
    });
  });

  group('METRIC-17 · buckets, and the row that must not become a fifth bucket', () {
    test('the four approved buckets plus the reconciliation column account for '
        'every user', () {
      final m = AdminUserOverview.fromRow({
        'users_total': 100,
        'age_18_30': 40,
        'age_30_45': 25,
        'age_45_60': 10,
        'age_unknown': 20,
        'age_out_of_range': 5,
      });
      expect(m.bucketsReconcile, isTrue);
      expect(m.ageOutOfRange, 5);
    });

    test('reconciliation FAILS loudly when the buckets do not add up, rather than '
        'rendering a panel that misstates its own total', () {
      final m = AdminUserOverview.fromRow({
        'users_total': 100,
        'age_18_30': 40,
        'age_30_45': 25,
        'age_45_60': 10,
        'age_unknown': 20,
        'age_out_of_range': 0, // the 5 genuine 60+ records dropped
      });
      expect(m.bucketsReconcile, isFalse);
    });

    test('an unauthorized read does not reconcile, because it has no figures to '
        'reconcile — not because they are zero', () {
      final m = AdminUserOverview.fromRow(const {});
      expect(m.usersTotal, isNull);
      expect(m.bucketsReconcile, isFalse);
    });
  });

  group('METRIC-14 · attendance', () {
    test('no registrations yields a NULL rate, not 0% — "nobody registered" and '
        '"nobody turned up" are different statements', () {
      final m = AdminEventsOverview.fromRow({
        'events_total': 3,
        'event_registrations_total': 0,
        'event_registrations_attended': 0,
        'event_attendance_rate_pct': null,
        'event_registrations_30d': 0,
      });
      expect(m.attendanceRatePct, isNull);
      expect(m.registrationsTotal, 0);
    });

    test('a measured rate is carried through, including a genuine 0%', () {
      final m = AdminEventsOverview.fromRow({
        'event_registrations_total': 4,
        'event_registrations_attended': 0,
        'event_attendance_rate_pct': 0,
      });
      expect(m.attendanceRatePct, 0.0);
      expect(m.attendanceRatePct, isNotNull);
    });
  });

  group('METRIC-06 · revenue refuses to invent a monetary value', () {
    final noFx = <String, dynamic>{
      'gross_coaching_cents': 13000,
      'platform_commission_cents': 500,
      'net_platform_cents': 12500,
      'source_currency': 'usd',
      'commission_rate_missing': 1,
      'amount_missing': 0,
      'excluded_non_coaching': 2,
      'fx_usd_gbp_rate': null,
      'fx_as_of': null,
      'fx_source': null,
    };

    test('with no recorded FX rate there is NO GBP figure — null, never an '
        'approximation', () {
      final m = AdminRevenueOverview.fromRow(noFx);
      expect(m.hasRecordedFx, isFalse);
      expect(m.gbpFrom(m.grossCoachingCents), isNull);
      expect(m.sourceCurrency, 'usd');
    });

    test('a recorded rate converts, and the rate, date and source all travel with '
        'the figure', () {
      final m = AdminRevenueOverview.fromRow({
        ...noFx,
        'fx_usd_gbp_rate': 0.79,
        'fx_as_of': '2026-10-07',
        'fx_source': 'owner-recorded',
      });
      expect(m.hasRecordedFx, isTrue);
      expect(m.gbpFrom(13000), 10270); // 13000 * 0.79
      expect(m.fxAsOf, DateTime.parse('2026-10-07'));
      expect(m.fxSource, 'owner-recorded');
    });

    test('an unavailable source amount converts to null, never to zero', () {
      final m = AdminRevenueOverview.fromRow({
        ...noFx,
        'fx_usd_gbp_rate': 0.79,
        'fx_as_of': '2026-10-07',
        'fx_source': 'owner-recorded',
      });
      expect(m.gbpFrom(null), isNull);
    });

    test('a payment with no recorded commission_rate makes the commission figure '
        'INCOMPLETE, so the card cannot present it as a total', () {
      expect(AdminRevenueOverview.fromRow(noFx).commissionIsComplete, isFalse);
      expect(
          AdminRevenueOverview.fromRow(
                  {...noFx, 'commission_rate_missing': 0})
              .commissionIsComplete,
          isTrue);
    });

    test('net is the recorded net and is not recomputed in Dart — two authorities '
        'for one figure is how they drift apart', () {
      final m = AdminRevenueOverview.fromRow(noFx);
      expect(m.netPlatformCents, 12500);
      expect(m.grossCoachingCents! - m.platformCommissionCents!, 12500);
    });
  });

  group('METRIC-11 · CI and the gate ledger stay separate', () {
    test('both verdicts are carried, and a disagreement survives intact — CI '
        'passing while the gate ledger says FAIL is the real current state', () {
      final m = AdminReleaseStatus.fromRow({
        'release_version': '4.2.0',
        'environment': 'staging',
        'ci_status': 'Passing',
        'ci_checks_passed': 6,
        'ci_checks_total': 6,
        'ci_source': 'workflow run 1',
        'ci_recorded_at': '2026-10-07T00:00:00Z',
        'gate_verdict': 'FAIL',
        'gates_pass': 5,
        'gates_partial': 2,
        'gates_fail': 8,
        'gates_total': 15,
        'gate_source': 'RELEASE_GATES.md',
        'gate_recorded_at': '2026-10-07T00:00:00Z',
      });
      expect(m.hasCiVerdict, isTrue);
      expect(m.hasGateVerdict, isTrue);
      expect(m.ciStatus, 'Passing');
      expect(m.gateVerdict, 'FAIL');
      expect(m.gatesPass! + m.gatesPartial! + m.gatesFail!, m.gatesTotal);
    });

    test('one half recorded and the other not leaves the second half ABSENT, not '
        'passing and not failing', () {
      final m = AdminReleaseStatus.fromRow({
        'release_version': '4.2.0',
        'environment': 'staging',
        'ci_status': 'Passing',
        'ci_source': 'workflow run 1',
        'ci_recorded_at': '2026-10-07T00:00:00Z',
        'gate_verdict': null,
        'gate_source': null,
        'gate_recorded_at': null,
      });
      expect(m.hasCiVerdict, isTrue);
      expect(m.hasGateVerdict, isFalse);
      expect(m.gateVerdict, isNull);
    });

    test('a verdict without its provenance is NOT shown — the same rule the table '
        'enforces as a CHECK constraint', () {
      final m = AdminReleaseStatus.fromRow({
        'ci_status': 'Passing',
        'ci_source': null,
        'ci_recorded_at': null,
      });
      expect(m.hasCiVerdict, isFalse,
          reason: 'an unsourced verdict is an assertion nobody made');
    });
  });

  group('parsing never defaults to zero', () {
    test('PostgREST may return a bigint as a string; it parses, and garbage '
        'becomes null rather than 0', () {
      final m = AdminRevenueOverview.fromRow({
        'gross_coaching_cents': '13000',
        'platform_commission_cents': 'not a number',
      });
      expect(m.grossCoachingCents, 13000);
      expect(m.platformCommissionCents, isNull);
      expect(m.platformCommissionCents, isNot(0));
    });
  });
}

/// Q2 / `METRIC-02` sub-answer — the active-user ROLE SPLIT (migration 181).
///
/// The live suite (D22) proves the SQL: that each map sums exactly to its total and
/// that an unauthorized basis yields NULL rather than `{}`. It cannot see Dart, so
/// these are the assertions that keep the Dart half from undoing either property —
/// the same division of labour as the rest of this file.
void mainRoleSplit() {
  group('Q2 · the role split keeps null and empty apart', () {
    test('an unauthorized basis parses to NULL, not to an empty map', () {
      final m = AdminActivityOverview.fromRow(const {
        'session_users_today': 4,
        'session_users_today_by_role': {'client': 3, 'coach': 1},
        'signin_users_today': null,
        'signin_users_today_by_role': null,
      });
      expect(m.sessionUsersTodayByRole, isNotNull);
      expect(m.signInUsersTodayByRole, isNull,
          reason: 'a null jsonb must stay null: it means "not authorized for this '
              'basis", and an empty map would say "nobody signed in"');
    });

    test('an authorized-but-empty window parses to an EMPTY MAP, not to null', () {
      final m = AdminActivityOverview.fromRow(const {
        'session_users_today': 0,
        'session_users_today_by_role': <String, dynamic>{},
      });
      expect(m.sessionUsersTodayByRole, isNotNull,
          reason: 'a measured zero is not an absent authorization');
      expect(m.sessionUsersTodayByRole, isEmpty);
    });

    test('a row that omits the columns entirely yields null, not a crash', () {
      final m = AdminActivityOverview.fromRow(const {'session_users_today': 1});
      expect(m.sessionUsersTodayByRole, isNull);
      expect(m.signInUsersMonthByRole, isNull);
    });

    test('jsonb handed back as an encoded string is still decoded', () {
      final m = AdminActivityOverview.fromRow(const {
        'session_users_today_by_role': '{"client":2,"coach":1}',
      });
      expect(m.sessionUsersTodayByRole, {'client': 2, 'coach': 1});
    });

    test('the parsed split sums to the total it was published beside', () {
      final m = AdminActivityOverview.fromRow(const {
        'session_users_month': 26,
        'session_users_month_by_role': {'client': 20, 'coach': 5, 'vendor': 1},
      });
      final sum = m.sessionUsersMonthByRole!.values.reduce((a, b) => a + b);
      expect(sum, m.sessionUsersMonth,
          reason: 'the parts must account for the whole, or the split is the '
              '"unexplained aggregate" the ruling forbids');
    });
  });

  group('Q2 · the split is labelled without being regrouped', () {
    test('nothing is rendered for an unauthorized basis or a measured zero', () {
      expect(formatAdminRoleSplit(null), isNull);
      expect(formatAdminRoleSplit(const {}), isNull);
    });

    test('roles are labelled and ordered deterministically', () {
      expect(formatAdminRoleSplit(const {'coach': 1, 'client': 2}),
          'Clients 2 · Coaches 1');
    });

    test('a role the label table does not know renders RAW rather than vanishing', () {
      // If 142's CHECK gains a role before this table does, the count must still
      // appear — otherwise a total would stop matching its own breakdown.
      final out = formatAdminRoleSplit(const {'client': 2, 'future_role': 3});
      expect(out, contains('future_role 3'));
      expect(out, contains('Clients 2'));
    });

    test('no_profile and unrecorded are labelled DIFFERENTLY, never merged', () {
      final a = adminRoleSplitLabels['no_profile'];
      final b = adminRoleSplitLabels['unrecorded'];
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(equals(b)),
          reason: 'a missing profile and an unset role column are different '
              'findings; migration 181 keeps them apart and so must the UI');
    });

    test('every role in the schema CHECK has a label', () {
      for (final role in const [
        'client', 'coach', 'vendor', 'admin', 'content_manager',
        'trust_operator', 'erasure_executor',
      ]) {
        expect(adminRoleSplitLabels[role], isNotNull,
            reason: '$role is in migration 142\'s CHECK and must be labelled');
      }
    });
  });
}
