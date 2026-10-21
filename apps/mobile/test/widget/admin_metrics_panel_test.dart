import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/domain/admin_trust.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/presentation/admin_metric_tile.dart';
import 'package:circle_fitness/features/admin/presentation/admin_metrics_panel.dart';

/// V5 §166 — the panel's job is to render the right `A11` state, and the states it
/// must never confuse are: not authorized · not recorded · loading · error · a real
/// zero. Each of those is a different statement to an operator, and four of the five
/// are indistinguishable once something writes `?? 0`.
Future<void> _pump(WidgetTester t, List<Override> overrides) async {
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    // The panel is a Column and does NOT own scrolling — a panel composed into a
    // page should not, or two of them on one page fight for it. So the harness
    // supplies the scroll view, exactly as the hosting screen must. The first draft
    // put the panel in a fixed-height SizedBox and overflowed by 330px, which is a
    // defect in the harness rather than in the widget.
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: Size(420, 900)),
        child: SizedBox(
          width: 420,
          height: 900,
          child: SingleChildScrollView(child: AdminMetricsPanel()),
        ),
      ),
    ),
  ));
  await t.pump();
}

String _allText(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' | ');

void main() {
  // Every provider resolved to null = "no capability for this area".
  final allDenied = [
    adminActivityOverviewProvider.overrideWith((_) async => null),
    adminUserOverviewProvider.overrideWith((_) async => null),
    adminEventsOverviewProvider.overrideWith((_) async => null),
    adminCommunityOverviewProvider.overrideWith((_) async => null),
    adminRevenueOverviewProvider.overrideWith((_) async => null),
    adminReleaseStatusProvider.overrideWith((_) async => null),
  // Overridden EXPLICITLY, not left to chance. Without it the attention queue
  // reaches for an uninitialised Supabase client and lands in the error state,
  // so these tests would pass for an accidental reason rather than a stated one.
    adminIncidentsProvider.overrideWith((_) async => null),
    // §197 · Q12's audit tail. Same reason as the line above: unoverridden it reaches an
    // uninitialised Supabase client and the card lands in its error state, so a test would
    // pass for an accidental reason.
    adminAuditEventsProvider.overrideWith((_) async => null),
  ];

  /// A revenue row built from a MAP, so the test drives the same `fromRow` parser the
  /// service uses rather than a hand-built object the parser never sees.
  List<Override> revenue(Map<String, Object?> r) => [
        adminRevenueOverviewProvider
            .overrideWith((_) async => AdminRevenueOverview.fromRow(r)),
      ];

  testWidgets('an unauthorized operator sees WHY each area is empty, and no figure '
      'anywhere — the card does not vanish and does not show zeros', (t) async {
    await _pump(t, allDenied);
    expect(find.text('Not available to your role'), findsWidgets);

    // A FIGURE IS A TILE VALUE, NOT ANY DIGIT ON THE PAGE — and this assertion had to be
    // re-shaped to say so. It banned `\d` anywhere, and §193's "Not shown here" card broke
    // it by citing the rulings BY NAME: PD-A24, PD-G01, WI-13, P7. Those are the reasons an
    // absence is an absence; a sweep that forbids them forbids explaining the gap. Fifth
    // instance of the same shape in this run, and the rule is unchanged: assert that no
    // MEASUREMENT renders, not that no digit appears.
    //
    // A metric value is rendered by AdminMetricTile, so the check reads the tiles rather
    // than the page: every one must be in an absent state, which is strictly stronger than
    // the digit sweep — it would catch a tile rendering "0" OR one rendering "none".
    final tiles = t.widgetList<AdminMetricTile>(find.byType(AdminMetricTile)).toList();
    expect(tiles, isNotEmpty,
        reason: 'no tiles found at all, so this assertion would prove nothing');
    final shown = tiles.where((x) => !x.isAbsent).toList();
    expect(shown, isEmpty,
        reason: 'these tiles rendered a value to an unauthorized operator: '
            '${shown.map((x) => x.label).join(', ')}');
  });

  testWidgets('LOADING is its own state — a card mid-flight must not read as a '
      'platform with no activity', (t) async {
    // A provider that never completes stays in the loading state. A Completer is
    // used rather than Future.delayed, which leaves a pending Timer and makes the
    // test fail on teardown for a reason unrelated to what it asserts.
    final never = Completer<AdminActivityOverview?>();
    addTearDown(() => never.complete(null));
    await _pump(t, [
      ...allDenied,
      adminActivityOverviewProvider.overrideWith((_) => never.future),
    ]);
    expect(find.text('Loading…'), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('ERROR is its own state, and is NOT reported as a permission boundary '
      '— a dropped connection is not an authorization outcome', (t) async {
    await _pump(t, [
      ...allDenied,
      adminEventsOverviewProvider
          .overrideWith((_) async => throw Exception('network')),
    ]);
    expect(find.text('Unavailable'), findsWidgets);
  });

  group('METRIC-02 · the authorization split reaches the screen', () {
    testWidgets('a Users-only operator sees Session figures and is told the sign-in '
        'basis is not theirs — not that it is zero', (t) async {
      await _pump(t, [
        ...allDenied,
        adminActivityOverviewProvider.overrideWith((_) async =>
            AdminActivityOverview.fromRow(const {
              'session_users_today': 4,
              'session_users_week': 11,
              'session_users_month': 26,
              'session_users_prev_month': 19,
              'signin_users_today': null,
              'signin_users_week': null,
              'signin_users_month': null,
              'signin_users_prev_month': null,
              'sessions_today': 9,
              'sessions_month': 140,
              'day_start': '2026-10-07T00:00:00Z',
              'week_start': '2026-10-05T00:00:00Z',
              'month_start': '2026-10-01T00:00:00Z',
              'window_timezone': 'UTC',
            })),
      ]);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
      expect(find.text('+7'), findsOneWidget); // 26 - 19
      // SESSIONS ARE NOT USERS. 4 members were active today and they recorded 9
      // Sessions between them; the design shows both and the card must not conflate
      // them. If the panel rendered one for the other, "9" would be absent.
      expect(find.text('Daily sessions'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      // The window is DISCLOSED, because the data contract leaves the timezone
      // unsettled and an invisible window is an assumption the reader cannot check.
      expect(find.textContaining('Day begins 2026-10-07'), findsOneWidget);
      expect(find.textContaining('UTC'), findsOneWidget);
      // The three sign-in rows must each say so.
      expect(find.text('Active today · Sign-ins'), findsOneWidget);
      expect(find.text('Not available to your role'), findsWidgets);
    });
  });

  group('METRIC-17 · the reconciliation row is not a fifth bucket', () {
    AdminUserOverview users({required int outOfRange}) =>
        AdminUserOverview.fromRow({
          'users_total': 100,
          'coaches_total': 10,
          'vendors_total': 0,
          'coaches_active_this_month': 3,
          'coaches_no_client_this_month': 7,
          'age_18_30': 40,
          'age_30_45': 25,
          'age_45_60': 10,
          'age_unknown': 25 - outOfRange,
          'age_out_of_range': outOfRange,
        });

    testWidgets('with nobody outside the approved buckets, no extra row appears',
        (t) async {
      await _pump(t, [
        ...allDenied,
        adminUserOverviewProvider.overrideWith((_) async => users(outOfRange: 0)),
      ]);
      expect(find.text('Outside the approved buckets'), findsNothing);
      expect(find.text('Age unknown'), findsOneWidget);
    });

    testWidgets('with genuine 60+ records the row DOES appear, labelled as what it '
        'is — hiding it would make the panel misstate its own total, and inventing '
        'a 60+ bucket is forbidden', (t) async {
      await _pump(t, [
        ...allDenied,
        adminUserOverviewProvider.overrideWith((_) async => users(outOfRange: 5)),
      ]);
      expect(find.text('Outside the approved buckets'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining('60+'), findsNothing);
    });

    testWidgets('METRIC-05 shows a total only — there is no approval sub-count',
        (t) async {
      await _pump(t, [
        ...allDenied,
        adminUserOverviewProvider.overrideWith((_) async => users(outOfRange: 0)),
      ]);
      expect(find.text('Wellness partners'), findsOneWidget);
      expect(find.textContaining('awaiting'), findsNothing);
      expect(find.textContaining('approval'), findsNothing);
    });
  });

  group('METRIC-14 · a missing rate is not 0%', () {
    testWidgets('no registrations yields the not-recorded state, never "0.0%"',
        (t) async {
      await _pump(t, [
        ...allDenied,
        adminEventsOverviewProvider.overrideWith((_) async =>
            AdminEventsOverview.fromRow(const {
              'events_total': 3,
              'event_registrations_total': 0,
              'event_registrations_attended': 0,
              'event_attendance_rate_pct': null,
              'event_registrations_30d': 0,
            })),
      ]);
      expect(find.text('Attendance rate'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.text('0.0%'), findsNothing);
    });

    testWidgets('a measured rate renders, and a measured zero count uses the '
        'design\'s wording', (t) async {
      await _pump(t, [
        ...allDenied,
        adminEventsOverviewProvider.overrideWith((_) async =>
            AdminEventsOverview.fromRow(const {
              'events_total': 3,
              'event_registrations_total': 4,
              'event_registrations_attended': 0,
              'event_attendance_rate_pct': 0,
              'event_registrations_30d': 2,
            })),
      ]);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('None'), findsWidgets); // attended = 0
    });
  });

  group('METRIC-06 · incompleteness is disclosed, FX is never approximated', () {
    AdminRevenueOverview rev({
      int missing = 0,
      bool fx = false,
      int other = 0,
      int payoutMissing = 0,
    }) =>
        AdminRevenueOverview.fromRow({
          'gross_coaching_cents': 13000,
          'platform_commission_cents': 500,
          'net_platform_cents': 12500,
          'source_currency': 'usd',
          'commission_rate_missing': missing,
          'amount_missing': 0,
          'excluded_non_coaching': 2,
          'stream_coach_cents': 12000,
          'stream_coach_plan_cents': 4900,
          'stream_self_guided_cents': 0,
          'stream_ai_guided_cents': 0,
          'stream_event_ticket_cents': 9900,
          'stream_package_cents': 1000,
          'stream_other_cents': other,
          'stream_other_count': other > 0 ? 1 : 0,
          'paid_total_cents': 27800 + other,
          'coach_payout_cents': 0,
          'platform_fee_cents': 0,
          'payout_missing': payoutMissing,
          if (fx) 'fx_usd_gbp_rate': 0.79,
          if (fx) 'fx_as_of': '2026-10-07',
          if (fx) 'fx_source': 'owner-recorded',
        });

    testWidgets('the three figures are shown with their source currency', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev())]);
      expect(find.text('USD 130.00'), findsOneWidget);
      expect(find.text('USD 5.00'), findsOneWidget);
      expect(find.text('USD 125.00'), findsOneWidget);
    });

    testWidgets('with no recorded FX the row says so — no pounds figure is '
        'approximated', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev())]);
      expect(find.text('FX USD→GBP'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.textContaining('GBP 1'), findsNothing);
    });

    testWidgets('a recorded rate is shown WITH its date, so the figure is datable',
        (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev(fx: true))]);
      expect(find.text('FX USD→GBP · 2026-10-07'), findsOneWidget);
      expect(find.text('0.7900'), findsOneWidget);
    });

    testWidgets('an incomplete commission figure DISCLOSES how many payments it '
        'could not account for', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev(missing: 3))]);
      expect(find.text('Payments with no recorded rate'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('each stream is labelled in the design\'s words and shown separately, '
        'because the Dashboard requires "revenue by stream"', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev())]);
      expect(find.text('Stream · coaching'), findsOneWidget);
      expect(find.text('Stream · event tickets'), findsOneWidget);
      expect(find.text('Stream · session packages'), findsOneWidget);
      expect(find.text('USD 120.00'), findsOneWidget);  // coaching
      expect(find.text('USD 99.00'), findsOneWidget);   // event tickets
    });

    testWidgets('an UNRECOGNISED stream is shown, not hidden — understating revenue is '
        'the one direction a money figure must not be wrong by accident', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev(other: 2500))]);
      expect(find.text('Stream · unrecognised'), findsOneWidget);
      expect(find.text('USD 25.00'), findsOneWidget);
      expect(rev(other: 2500).streamsReconcile, isTrue);
    });

    testWidgets('with every stream recognised, no unrecognised row appears', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev())]);
      expect(find.text('Stream · unrecognised'), findsNothing);
    });

    testWidgets('the recorded split is shown, and an incomplete one is disclosed',
        (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith(
            (_) async => rev(payoutMissing: 3))]);
      expect(find.text('Paid to coaches'), findsOneWidget);
      expect(find.text('Platform fee'), findsOneWidget);
      expect(find.text('Payments with no recorded split'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a complete commission figure does not nag', (t) async {
      await _pump(t, [...allDenied,
        adminRevenueOverviewProvider.overrideWith((_) async => rev())]);
      expect(find.text('Payments with no recorded rate'), findsNothing);
    });
  });

  group('METRIC-11 · two verdicts, never one', () {
    testWidgets('the all-NULL row migration 174 returns means NOT RECORDED for both '
        'halves — the operator is authorized and there is simply nothing yet',
        (t) async {
      await _pump(t, [
        ...allDenied,
        adminReleaseStatusProvider.overrideWith(
            (_) async => AdminReleaseStatus.fromRow(const {})),
      ]);
      expect(find.text('CI status'), findsOneWidget);
      expect(find.text('V5 release gate'), findsOneWidget);
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.text('Not available to your role'), findsWidgets); // other areas
    });

    testWidgets('a recorded disagreement is rendered as a disagreement — CI Passing '
        'beside gate FAIL, separately labelled, with no third combined verdict',
        (t) async {
      await _pump(t, [
        ...allDenied,
        adminReleaseStatusProvider.overrideWith((_) async =>
            AdminReleaseStatus.fromRow(const {
              'release_version': '4.2.0',
              'environment': 'staging',
              'ci_status': 'Passing',
              'ci_checks_passed': 6,
              'ci_checks_total': 6,
              'ci_source': 'run 1',
              'ci_recorded_at': '2026-10-07T00:00:00Z',
              'gate_verdict': 'FAIL',
              'gates_pass': 5,
              'gates_partial': 2,
              'gates_fail': 8,
              'gates_total': 15,
              'gate_source': 'RELEASE_GATES.md',
              'gate_recorded_at': '2026-10-07T00:00:00Z',
            })),
      ]);
      expect(find.text('4.2.0 · staging'), findsOneWidget);
      expect(find.text('Passing'), findsOneWidget);
      expect(find.text('FAIL'), findsOneWidget);
      expect(find.text('6 / 6'), findsOneWidget);
      expect(find.text('5 pass · 2 partial · 8 fail of 15'), findsOneWidget);
      // No synthesised overall verdict anywhere.
      final text = _allText(t);
      for (final forbidden in ['BLOCKED', 'Releasable', 'Not releasable', 'Overall']) {
        expect(text.contains(forbidden), isFalse,
            reason: 'the panel must not synthesise "$forbidden" from two '
                'authorities that disagree: $text');
      }
    });
  });

  // ── §193 · the page that most needed its absences stated had none ─────────
  group('Control Center · requirements NOT shown, each stated', () {
    test('every published requirement with no surface has its OWN reason — a shared '
        'placeholder would masquerade as seven findings', () {
      final reasons = AdminMetricsPanelAbsences.all.values.toList();
      // SIX, DOWN FROM SEVEN — and the count fell because an absence became a BUILD, not
      // because the guard was relaxed. Owner decision Q12 authorized the audit tail, so
      // "Audit-log tail" left this map and became `_RecentAdminActivity`. The substance of
      // this guard is unchanged: distinct reasons, each naming a ruling or a missing
      // producer, none reading as a measured zero.
      expect(reasons.length, 6);
      expect(AdminMetricsPanelAbsences.all.containsKey('Audit-log tail'), isFalse,
          reason: 'Q12 built the tail, so it is no longer an absence to state');
      expect(reasons.toSet().length, reasons.length,
          reason: 'two absences share a reason, so one of them is not really explained');
      for (final r in reasons) {
        // A reason that does not say anything is a blank with extra steps.
        expect(r.length, greaterThan(40), reason: 'too thin to be a reason: $r');
      }
    });

    test('each reason names the RULING or the missing producer, not just the absence', () {
      final m = AdminMetricsPanelAbsences.all;
      expect(m['Installs'], contains('PD-A24'));
      expect(m['Wearable sync status'], contains('PD-G01'));
      expect(m['AI Guardian findings'], contains('P7'));
      expect(m['Impressions'], contains('no producer'));
      expect(m['Churn'], contains('never put as a metric decision'));
    });

    test('an absence is never described as a zero', () {
      for (final r in AdminMetricsPanelAbsences.all.values) {
        expect(RegExp(r'\b(0|zero|none)\b', caseSensitive: false).hasMatch(r), isFalse,
            reason: 'reads as a measured zero rather than an absence: $r');
      }
    });
  });

  // ── §197 · OWNER DECISION Q11 · monthly subscription churn ────────────────
  group('Q11 · churn renders insufficient history, never a misleading 0%', () {
    testWidgets('THE DECISIVE PAIR · 0 cancellations with no recorded history shows the '
        'A11 state and NOT "0.0%"', (t) async {
      await _pump(t, [
        ...allDenied,
        ...revenue(const {
          'churn_cancellations_month': 0,
          'churn_active_at_month_start': 420,
          'churn_rate_pct': null,
          'churn_first_cancellation_at': null,
          'churn_denominator_basis': 'existed before the month began and not yet canceled',
        }),
      ]);
      // The rate is absent, not zero.
      expect(find.text('0.0%'), findsNothing,
          reason: 'a null churn rate must not render as a measured zero');
      final rate = t
          .widgetList<AdminMetricTile>(find.byType(AdminMetricTile))
          .firstWhere((x) => x.label == 'Monthly churn');
      expect(rate.isAbsent, isTrue, reason: 'the rate tile must be in an absent state');
      // And the components still show, because they ARE recorded counts.
      expect(find.text('420'), findsOneWidget);
      expect(find.text('None'), findsWidgets,
          reason: '0 cancellations is a measured zero and uses the design zero wording');
    });

    testWidgets('…and it says WHY there is no rate, so the absence is not unexplained',
        (t) async {
      await _pump(t, [
        ...allDenied,
        ...revenue(const {
          'churn_rate_pct': null,
          'churn_first_cancellation_at': null,
          'churn_active_at_month_start': 10,
          'churn_cancellations_month': 0,
        }),
      ]);
      final text = _allText(t);
      expect(text.contains('no cancellation has been recorded'), isTrue, reason: text);
      expect(text.contains('not backfilled'), isTrue, reason: text);
    });

    testWidgets('once history EXISTS, a month with no cancellations renders a REAL 0.0% — '
        'the measured zero the null state was protecting', (t) async {
      await _pump(t, [
        ...allDenied,
        ...revenue({
          'churn_cancellations_month': 0,
          'churn_active_at_month_start': 200,
          'churn_rate_pct': 0,
          'churn_first_cancellation_at': '2026-09-01T00:00:00Z',
          'churn_denominator_basis': 'existed before the month began and not yet canceled',
        }),
      ]);
      expect(find.text('0.0%'), findsOneWidget,
          reason: 'with capture proven, a zero month is a real zero');
      expect(_allText(t).contains('no cancellation has been recorded'), isFalse,
          reason: 'the insufficient-history sentence must not appear once history exists');
    });

    testWidgets('a real rate renders, and the denominator basis is read FROM THE VIEW so '
        'the surface cannot drift from the definition it reports', (t) async {
      await _pump(t, [
        ...allDenied,
        ...revenue({
          'churn_cancellations_month': 4,
          'churn_active_at_month_start': 200,
          'churn_rate_pct': 2.0,
          'churn_first_cancellation_at': '2026-09-01T00:00:00Z',
          'churn_denominator_basis': 'existed before the month began and not yet canceled',
        }),
      ]);
      expect(find.text('2.0%'), findsOneWidget);
      final text = _allText(t);
      expect(text.contains('existed before the month began and not yet canceled'), isTrue,
          reason: text);
      // Q13 is unresolved, and the card says so rather than offering a split.
      expect(text.contains('No plan-level split'), isTrue, reason: text);
    });
  });

  // ── §197 · OWNER DECISION Q12 · the actor-anonymous audit tail ────────────
  group('Q12 · the audit tail shows what the ruling permits and nothing else', () {
    List<Override> audit(List<Map<String, Object?>> rows) => [
          adminAuditEventsProvider.overrideWith(
              (_) async => [for (final r in rows) AdminAuditEvent.fromRow(r)]),
        ];

    const row = {
      'id': 'a1',
      'actor_id': '00000000-0000-4000-8000-0000000000aa',
      'subject_pseudonym': '11111111-1111-4111-8111-1111111111bb',
      'action': 'user_profiles.name.set',
      'occurred_at': '2026-10-07T10:41:00Z',
      'outcome': 'success',
      'category': 'admin_action',
    };

    testWidgets('no capability is a different state from an empty ledger', (t) async {
      await _pump(t, allDenied);
      expect(find.text('RECENT ADMIN ACTIVITY'), findsOneWidget);
      expect(find.text('Not available to your role'), findsWidgets);
      expect(find.text('No admin activity recorded'), findsNothing);
    });

    testWidgets('an authorized but EMPTY ledger says so, and still discloses A13·1',
        (t) async {
      await _pump(t, [...allDenied, ...audit(const [])]);
      expect(find.text('No admin activity recorded'), findsOneWidget);
      expect(_allText(t).contains('excluded from this log'), isTrue);
    });

    testWidgets('a row shows action · category · outcome · time, and NOTHING that names '
        'the actor — the ruling forbids resolving actor IDs into user names', (t) async {
      await _pump(t, [...allDenied, ...audit(const [row])]);
      final text = _allText(t);
      expect(text.contains('user_profiles.name.set'), isTrue, reason: text);
      expect(text.contains('admin_action'), isTrue, reason: text);
      expect(text.contains('success'), isTrue, reason: text);
      expect(text.contains('10:41'), isTrue, reason: text);
      // Neither the raw actor id nor the pseudonym may reach the screen.
      expect(text.contains('00000000-0000-4000-8000-0000000000aa'), isFalse,
          reason: 'the actor id reached the tail: $text');
      expect(text.contains('11111111-1111-4111-8111-1111111111bb'), isFalse,
          reason: 'the subject pseudonym reached the tail: $text');
    });

    testWidgets('A13·1 is DISCLOSED, because a ledger that looks complete while excluding '
        'its own reader is worse than one that says so', (t) async {
      await _pump(t, [...allDenied, ...audit(const [row])]);
      expect(_allText(t).contains('Your own admin actions are excluded'), isTrue);
      expect(_allText(t).contains('is not named here'), isTrue);
    });

    testWidgets('the four design sample rows are NOT fabricated — no Guardian finding, no '
        'release-as-audit-event, no MFA claim, no person named', (t) async {
      await _pump(t, [...allDenied, ...audit(const [row])]);
      final text = _allText(t);
      for (final invented in ['J. Park', 'D. Mac', 'MFA', 'Release 4.2.0',
                              'Senior coach', 'Guardian flagged']) {
        expect(text.contains(invented), isFalse,
            reason: 'fabricated the mock-up row "$invented": $text');
      }
    });

    testWidgets('an unrecorded field is NAMED, and a missing timestamp does not default '
        'to now', (t) async {
      await _pump(t, [
        ...allDenied,
        ...audit(const [{'id': 'a2', 'action': null, 'category': null,
                         'outcome': null, 'occurred_at': null}]),
      ]);
      final text = _allText(t);
      for (final phrase in ['Action not recorded', 'No category recorded',
                            'No outcome recorded', 'No time recorded']) {
        expect(text.contains(phrase), isTrue, reason: 'missing "$phrase" in: $text');
      }
    });
  });
}
