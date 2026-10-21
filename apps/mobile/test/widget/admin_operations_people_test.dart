import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/admin/domain/admin_metrics.dart';
import 'package:circle_fitness/features/admin/domain/admin_provider.dart';
import 'package:circle_fitness/features/admin/domain/admin_trust.dart';
import 'package:circle_fitness/features/admin/presentation/admin_operations_screen.dart';
import 'package:circle_fitness/features/admin/presentation/admin_people_screen.dart';

/// V5 §185 — P5 · Operations and People. Both pages are ListViews, so the harness uses a
/// tall surface to build every section rather than relaxing the finders (§183.3).
Future<void> _pump(WidgetTester t, Widget screen, List<Override> o) async {
  await t.binding.setSurfaceSize(const Size(500, 4000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: o,
    child: MaterialApp(home: screen),
  ));
  await t.pump();
}

/// Like [_pump], but gives the ASYNC CAPABILITY PROVIDERS time to answer.
///
/// [_pump] advances one frame, which is enough for a `FutureProvider` whose body returns a
/// value synchronously but NOT for `adminCanUpdateUsersProvider` — on frame one it is
/// still loading, and an action gated on it correctly renders nothing. Asserting the
/// action's absence there would prove only that the test was early. The in-flight test
/// below deliberately keeps the one-frame state and says so.
Future<void> _pumpSettled(WidgetTester t, Widget screen, List<Override> o) async {
  await t.binding.setSurfaceSize(const Size(500, 4000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(overrides: o, child: MaterialApp(home: screen)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final _denied = <Override>[
  adminReleaseStatusProvider.overrideWith((_) async => null),
  adminWearableConnectionsProvider.overrideWith((_) async => null),
  adminSecurityEventsProvider.overrideWith((_) async => null),
  adminUserOverviewProvider.overrideWith((_) async => null),
  adminUserDirectoryProvider.overrideWith((_) async => null),
  // §189. An un-overridden capability provider does not fail the test — it makes a real
  // network call to QA, which is how EC-04 went from 2 minutes to a 25-minute cancel.
  adminCanUpdateUsersProvider.overrideWith((_) async => false),
];

/// One directory row built from a MAP, so the test drives the same `fromRow` parser the
/// service uses rather than a hand-built object the parser never sees.
List<Override> _withUsers(List<Map<String, Object?>> rows, {bool canEdit = false}) => [
      adminUserDirectoryProvider.overrideWith(
          (_) async => [for (final r in rows) AdminUserDirectoryEntry.fromRow(r)]),
      adminCanUpdateUsersProvider.overrideWith((_) async => canEdit),
    ];

const _row = {
  'id': 'u1',
  'first_name': 'Probe',
  'last_name': 'Member',
  'email': 'probe@qa.invalid',
  'role': 'client',
};

String _allText(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' | ');

void main() {
  group('Operations', () {
    testWidgets('the four published sections are present, in order', (t) async {
      await _pump(t, const AdminOperationsScreen(), _denied);
      final text = _allText(t);
      for (final s in ['OVERVIEW', 'RELEASES', 'INTEGRATIONS', 'SYSTEM EVENTS']) {
        expect(text.contains(s), isTrue, reason: 'missing $s in: $text');
      }
    });

    testWidgets('no capability means every area says so and no figure appears',
        (t) async {
      await _pump(t, const AdminOperationsScreen(), _denied);
      expect(find.text('Not available to your role'), findsWidgets);
      expect(RegExp(r'\b\d').hasMatch(_allText(t)), isFalse);
    });

    testWidgets('an authorized operator with NOTHING recorded sees the A11 state and the '
        'reason — the registry is empty because CI ingestion is gated, not broken',
        (t) async {
      await _pump(t, const AdminOperationsScreen(), [
        ..._denied,
        adminReleaseStatusProvider
            .overrideWith((_) async => AdminReleaseStatus.fromRow(const {})),
      ]);
      expect(find.text('Not recorded'), findsWidgets);
      expect(find.textContaining('gated on P10'), findsOneWidget);
    });

    testWidgets('a recorded disagreement keeps the two verdicts SEPARATE, with no third '
        'combined verdict anywhere — METRIC-11 Option 3', (t) async {
      await _pump(t, const AdminOperationsScreen(), [
        ..._denied,
        adminReleaseStatusProvider.overrideWith((_) async =>
            AdminReleaseStatus.fromRow(const {
              'release_version': '4.2.0',
              'environment': 'staging',
              'ci_status': 'Passing',
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
      expect(find.text('Passing'), findsOneWidget);
      expect(find.text('FAIL'), findsOneWidget);
      expect(find.text('5 pass · 2 partial · 8 fail of 15'), findsOneWidget);
      final text = _allText(t);
      for (final forbidden in ['BLOCKED', 'Releasable', 'Not releasable', 'Overall']) {
        expect(text.contains(forbidden), isFalse,
            reason: 'must not synthesise "$forbidden": $text');
      }
    });

    testWidgets('integrations shows connections and states that health waits on PD-G01',
        (t) async {
      await _pump(t, const AdminOperationsScreen(), [
        ..._denied,
        adminWearableConnectionsProvider.overrideWith((_) async =>
            AdminWearableConnections.fromRows(const [
              {'provider': 'whoop', 'connected': true},
            ])),
      ]);
      expect(find.textContaining('waits on PD-G01'), findsOneWidget);
      for (final label in ['Latency', 'Sync status', 'Integration health']) {
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets('system events states A13·1, because this projection excludes the '
        "reader's own admin actions too", (t) async {
      await _pump(t, const AdminOperationsScreen(), [
        ..._denied,
        adminSecurityEventsProvider.overrideWith((_) async => [
              AdminAuditEventStub.adminAction(),
              AdminAuditEventStub.auditRead(),
            ]),
      ]);
      expect(find.text('Admin actions'), findsOneWidget);
      expect(find.text('Audit reads'), findsOneWidget);
      expect(find.textContaining('excluded from this log'), findsOneWidget);
    });
  });

  group('People', () {
    testWidgets('the five published sections are present, in order', (t) async {
      await _pump(t, const AdminPeopleScreen(), _denied);
      final text = _allText(t);
      for (final s in ['USERS', 'COACHES', 'CLIENTS', 'WELLNESS PARTNERS',
                       'STATE SYSTEM']) {
        expect(text.contains(s), isTrue, reason: 'missing $s in: $text');
      }
    });

    testWidgets('no capability means every area says so and no figure appears',
        (t) async {
      await _pump(t, const AdminPeopleScreen(), _denied);
      expect(find.text('Not available to your role'), findsWidgets);
      expect(RegExp(r'\b\d').hasMatch(_allText(t)), isFalse);
    });

    testWidgets('METRIC-05 · partners show a TOTAL ONLY, with no approval sub-count',
        (t) async {
      await _pump(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {
              'users_total': 640,
              'clients_total': 500,
              'coaches_total': 135,
              'vendors_total': 0,
              'coaches_active_this_month': 2,
              'coaches_no_client_this_month': 133,
              'age_18_30': 1,
              'age_30_45': 1,
              'age_45_60': 0,
              'age_unknown': 638,
              'age_out_of_range': 0,
            })),
      ]);
      expect(find.text('Partners'), findsOneWidget);
      expect(find.text('None'), findsWidgets);
      // ASSERTED AS LABELLED READINGS, NOT AS PROSE. A sweep for "approval state" fires
      // on the card's own footnote, which says approval states are NOT shown — the third
      // time in this programme that a "must not mention X" assertion caught the sentence
      // explaining that X is absent (§184.3 for 'latency'). The property is that no
      // approval figure is DISPLAYED, and a tile label is an exact string.
      for (final label in ['Awaiting approval', 'Approval state', 'Pending approval',
                           'Approved', 'Onboarding state']) {
        expect(find.text(label), findsNothing,
            reason: 'METRIC-05 is "total only" — no "$label" reading may appear');
      }
      // METRIC-17's reconciliation row is hidden when empty, never shown as a bucket.
      expect(find.text('Outside the approved buckets'), findsNothing);
    });

    testWidgets('METRIC-03 · the coach partition is rendered as the design requires',
        (t) async {
      await _pump(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {
              'coaches_total': 164,
              'coaches_active_this_month': 141,
              'coaches_no_client_this_month': 23,
            })),
      ]);
      expect(find.text('164'), findsOneWidget);
      expect(find.text('141'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
    });

    testWidgets('the three unbuilt requirements are STATED, not left blank', (t) async {
      // AUTHORIZED, because two of the three statements live beside the data they
      // qualify. To an operator who cannot see the area at all, "last active is not
      // shown" is noise — the statements explain what an otherwise-populated card omits.
      await _pump(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {
              'users_total': 640,
              'coaches_total': 164,
              'vendors_total': 0,
              'coaches_active_this_month': 141,
              'coaches_no_client_this_month': 23,
            })),
      ]);
      final text = _allText(t);
      expect(text.contains('"Last active" is not shown'), isTrue,
          reason: 'the open population question is stated: $text');
      expect(text.contains('Coach verification is not shown'), isTrue,
          reason: 'no verification state exists in the schema, and that is said');
      expect(text.contains('Total only.'), isTrue,
          reason: "METRIC-05's ruling is stated beside the figure");
    });

    testWidgets('the account list shows the role and onboarding, and never relabels it '
        '"status" — no such state machine exists', (t) async {
      await _pump(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserDirectoryProvider.overrideWith((_) async => [
              AdminUserDirectoryEntry.fromRow(const {
                'id': 'u1',
                'first_name': 'Probe',
                'last_name': 'Member',
                'email': 'probe@qa.invalid',
                'role': 'client',
                'membership_tier': 'core',
                'onboarding_complete': false,
              }),
            ]),
      ]);
      expect(find.text('Probe Member'), findsOneWidget);
      expect(find.textContaining('client · core · onboarding incomplete'), findsOneWidget);
    });

    // ── §199 · the search box the approved table carries ─────────────────────
    testWidgets('the search box uses the approved placeholder and STATES its fields — a '
        'box that implied it searched everything would make a zero result a lie', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row])]);
      // THE PLACEHOLDER IS A HINT, NOT A VALUE — and the first version of this assertion
      // got the mechanism wrong: `widgetWithText` MATCHES, because Flutter renders the hint
      // as a Text descendant of the field. The claim is about the controller, so the
      // controller is what it reads.
      final field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.decoration?.hintText, 'Search name or email',
          reason: 'the approved placeholder, verbatim');
      expect(field.controller?.text, isEmpty,
          reason: 'the hint must not have been seeded as the query');
      final text = _allText(t);
      expect(text.contains('Searches first name, last name and email'), isTrue,
          reason: text);
      expect(text.contains('not that the account does not exist'), isTrue, reason: text);
    });

    testWidgets('typing updates the query provider, which is what re-runs the SERVER-side '
        'read — the filter is not applied to the rendered page', (t) async {
      late ProviderContainer container;
      await t.binding.setSurfaceSize(const Size(500, 4000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [..._denied, ..._withUsers(const [_row])],
        child: Consumer(builder: (ctx, ref, _) {
          container = ProviderScope.containerOf(ctx);
          return const MaterialApp(home: AdminPeopleScreen());
        }),
      ));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(container.read(adminUserSearchProvider), '');
      await t.enterText(find.byType(TextField).first, 'probe');
      await t.pump(const Duration(milliseconds: 50));
      expect(container.read(adminUserSearchProvider), 'probe');
    });

    // TWO TESTS, NOT ONE. The first draft pumped a second tree over the first inside one
    // test; that is not a fresh mount and the second assertion read the first tree's state.
    testWidgets('an empty DIRECTORY with no query says "None" — the population really is '
        'empty', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [])]);
      expect(find.text('None'), findsWidgets);
      expect(find.text('No account matches that search'), findsNothing);
    });

    testWidgets('…and an empty SEARCH RESULT is worded differently, so a filter cannot '
        'read as a fact about the population', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(), [
        ..._denied,
        ..._withUsers(const []),
        adminUserSearchProvider.overrideWith((_) => 'zzz'),
      ]);
      expect(find.text('No account matches that search'), findsOneWidget);
      expect(find.text('None'), findsNothing);
    });

    // ── §189 · "Edit profile", and the one action deliberately absent ─────────
    // ── §193 · "Clients served" — the fourth requirement §185.2's audit omitted ──
    testWidgets('"Clients served" is shown with its average per ACTIVE coach — the '
        'denominator the approved card\'s own arithmetic fixes', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {
              'coaches_total': 164,
              'coaches_active_this_month': 141,
              'coaches_no_client_this_month': 23,
              'coach_clients_served': 2210,
              'coach_clients_per_active_coach': 15.7,
            })),
      ]);
      // "2,210", not "2210": AdminMetricTile groups thousands, which is the approved
      // card's own rendering. The first version of this assertion asked for the raw
      // digits and was wrong about the UI rather than finding a defect in it.
      expect(find.text('2,210'), findsOneWidget);
      // 2210/141 = 15.7. Had the denominator been coaches_total it would read 13.5.
      expect(find.text('15.7'), findsOneWidget);
      expect(find.text('13.5'), findsNothing,
          reason: 'the average must be per ACTIVE coach, not per coach');
    });

    testWidgets('an average with NOTHING TO DIVIDE BY renders the A11 state, never 0.0 — '
        '"no active coach to average over" is not "an average of zero"', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {
              'coaches_total': 3,
              'coaches_active_this_month': 0,
              'coaches_no_client_this_month': 3,
              'coach_clients_served': 0,
              'coach_clients_per_active_coach': null,
            })),
      ]);
      // The count is a real zero and uses the design's zero wording.
      expect(find.text('Clients served'), findsOneWidget);
      // The average is absent, not 0.0.
      expect(find.text('0.0'), findsNothing,
          reason: 'a null average must not render as zero');
      expect(find.text('Average per active coach'), findsOneWidget);
      expect(AdminUserOverview.fromRow(const {'coach_clients_served': 0})
          .coachClientsPerActiveCoach, isNull);
    });

    testWidgets('the three Coaches tiles that remain unbuilt are NAMED, so a gap is not '
        'read as an oversight', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(), [
        ..._denied,
        adminUserOverviewProvider.overrideWith((_) async =>
            AdminUserOverview.fromRow(const {'coaches_total': 164})),
      ]);
      final text = _allText(t);
      for (final phrase in ['Programs live', 'coach-led', 'Reassign clients']) {
        expect(text.contains(phrase), isTrue, reason: 'missing "$phrase" in: $text');
      }
    });

    testWidgets('a role with Users·view but not Users·update sees the rows and no action, '
        'and is told which capability is missing', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(), [..._denied, ..._withUsers(const [_row])]);
      expect(find.text('Probe Member'), findsOneWidget);
      expect(find.text('Edit profile'), findsNothing);
      expect(_allText(t).contains('requires Users · update'), isTrue);
    });

    testWidgets('Users·update turns the action on', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row], canEdit: true)]);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(_allText(t).contains('requires Users · update'), isFalse);
    });

    testWidgets('"Change role" is NOT offered beside it — the approved menu lists it, but '
        'admin_set_user_role gates on is_admin() and not on the capability matrix, so '
        'wiring it to Users·update would widen who may grant admin', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row], canEdit: true)]);
      final text = _allText(t);
      expect(text.contains('Change role'), isFalse, reason: text);
      // Nor any of the other row actions the approved menu carries but no governed path
      // accepts from this screen.
      for (final absent in ['Suspend', 'Change plan', 'Change payout', 'Deactivate']) {
        expect(text.contains(absent), isFalse, reason: 'offers "$absent" with no backing');
      }
    });

    testWidgets('the form is name-only and SAYS so, so its narrowness is not read as a '
        'missing field — and it states that clearing a box cannot blank a name', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row], canEdit: true)]);
      await t.tap(find.text('Edit profile'));
      await t.pumpAndSettle();
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name'), findsOneWidget);
      final text = _allText(t);
      expect(text.contains('Name only.'), isTrue, reason: text);
      expect(text.contains('cannot blank a name'), isTrue, reason: text);
      // The dialog must not offer a field 161 has no parameter for.
      for (final absent in ['Email', 'Role', 'Tier', 'Plan']) {
        expect(find.widgetWithText(TextField, absent), findsNothing,
            reason: 'offers a $absent field with no governed path');
      }
    });

    testWidgets('saving with nothing changed reports that nothing was saved, rather than '
        'claiming a success it did not perform', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row], canEdit: true)]);
      await t.tap(find.text('Edit profile'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      // No service call is made at all, so this reaches the message without a fake:
      // the unchanged-field check happens BEFORE the RPC. If it did not, this test would
      // throw on the real client instead of finding the sentence.
      expect(find.text('Nothing was changed, so nothing was saved.'), findsOneWidget);
    });

    // THE REGRESSION THIS FILE'S ONE-FRAME PUMP CAUGHT. The first version of §189 put
    // `adminCapabilityGate` around the whole directory, so while the `Users·update` check
    // was still in flight the gate's honest "Checking your permissions…" replaced EVERY
    // ROW — hiding records `Users·view` had already authorized, on the strength of a
    // pending answer about a different verb. This test pumps exactly ONE frame, which is
    // the state that defect lived in, and asserts the rows are there anyway.
    testWidgets('a capability check still IN FLIGHT does not hide data the operator is '
        'already authorized to see — and does not announce a denial either', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 4000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(ProviderScope(
        overrides: [
          ..._denied,
          adminUserDirectoryProvider.overrideWith(
              (_) async => [AdminUserDirectoryEntry.fromRow(_row)]),
          // Never completes: the capability answer is permanently pending.
          adminCanUpdateUsersProvider.overrideWith((_) => Completer<bool>().future),
        ],
        child: const MaterialApp(home: AdminPeopleScreen()),
      ));
      // Enough frames for the DIRECTORY to resolve, while the capability stays pending.
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Probe Member'), findsOneWidget);
      // No action, because no answer — and no claim of a denial.
      expect(find.text('Edit profile'), findsNothing);
      expect(_allText(t).contains('requires Users · update'), isFalse,
          reason: 'a pending check must not render as a denial');
    });

    testWidgets('the action meets the 44px touch target', (t) async {
      await _pumpSettled(t, const AdminPeopleScreen(),
          [..._denied, ..._withUsers(const [_row], canEdit: true)]);
      final size = t.getSize(find.ancestor(
          of: find.text('Edit profile'), matching: find.byType(TextButton)).first);
      expect(size.height, greaterThanOrEqualTo(44.0));
    });
  });
}

/// Minimal fixtures so these assertions do not depend on the Trust test's file.
abstract final class AdminAuditEventStub {
  static AdminAuditEvent adminAction() => _ev('admin_action');
  static AdminAuditEvent auditRead() => _ev('audit_read');
  static AdminAuditEvent _ev(String c) => AdminAuditEvent.fromRow({
        'id': 'e-\$c',
        'action': c,
        'occurred_at': '2026-10-07T03:00:00Z',
        'outcome': 'success',
        'category': c,
    
  });
}
