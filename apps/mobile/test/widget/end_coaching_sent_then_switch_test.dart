// P0-RM-1 (C15-63b-03) · Settings' "End & switch" and Intake's "end previous
// coach" when the coach being ended is PAID with two subscriptions and the
// account changes while the FIRST cancellation is in flight.
//
// The first IS cancelled (it answered ok), so something happened that nobody
// was shown: that is recorded once as `<flow> outcome not shown`, beside the
// service's record of the stop — and the second cancellation is never sent.
// When the switch comes before anything was sent (the subscriptions read in
// flight), the service's record stays the single one.
//
// Harnesses of meal_and_mode_sheets_keep_their_owner_test.dart (Settings) and
// intake_end_previous_coach_keeps_its_member_test.dart (Intake): the REAL
// screens and service, real auth transitions on one device, no AccountScope,
// the screen stays mounted across the switch.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/coach/data/coach_relationship_service.dart
// lib/features/settings/presentation/settings_screen.dart
// lib/features/onboarding/presentation/intake_flow_screen.dart`.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';
import '../support/pump_until.dart';

const _endsAt = '2027-03-03T12:00:00Z';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester t) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  /// A's (and B's) paid subscriptions with [coach]: two for A, one for B.
  void paidWith(String coach) {
    Map<String, Object?> sub(String id, String who) => {
          'id': id, 'user_id': who, 'coach_id': coach, 'kind': 'coach',
          'status': 'active', 'current_period_end': _endsAt,
        };
    server.rows['subscriptions'] = {
      memberA: [sub('sub-a-1', memberA), sub('sub-a-2', memberA)],
      memberB: [sub('sub-b-1', memberB)],
    };
    server.functions['cancel-subscription'] = {'ok': true, 'endsAt': _endsAt};
  }

  Iterable<SeenRequest> invokes() =>
      server.seen.where((r) => r.target == 'cancel-subscription');

  List<(String, String)> records() =>
      [for (final f in reported) (f.origin, '${f.error}')];

  const stop = ('CoachRelationshipService.cancelCoach',
      'Ending coaching: the signed-in account changed');

  final flows = <({
    String name,
    (String, String) outcome,
    Future<void> Function(WidgetTester) open,
    Future<void> Function(WidgetTester) start,
  })>[
    (
      name: 'Settings "End & switch"',
      outcome: ('CoachingModeSheet.apply.cancelCoach',
          'Bad state: end coaching outcome not shown: the signed-in account changed'),
      open: (t) async {
        Map<String, Object?> me(String id, String name) => {
              'id': id, 'role': 'client', 'first_name': name, 'last_name': 'Lee',
              'coaching_mode': 'coach_guided',
            };
        server.rows.addAll({
          'user_profiles': {
            memberA: [me(memberA, 'Ana')],
            memberB: [me(memberB, 'Ben')],
          },
          'coach_client_relationships': {
            for (final m in [memberA, memberB])
              m: [
                {'id': 'rel-coach-a', 'coach_id': 'coach-a', 'status': 'active'},
              ],
          },
          'public_profiles': {
            for (final m in [memberA, memberB])
              m: [{'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'}],
          },
        });
        paidWith('coach-a');
        await t.binding.setSurfaceSize(const Size(500, 3000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(ProviderScope(
          overrides: [
            clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
          ],
          child: MaterialApp(
            home: const SettingsScreen(),
            builder: (_, child) => Consumer(builder: (_, ref, __) {
              ref.watch(myCoachesProvider);
              return child!;
            }),
          ),
        ));
        await settle(t);
        await t.tap(find.text('Coach Guided'));
        await settle(t);
        await t.tap(find.text('Self Guided'));
        await settle(t);
        await t.tap(find.text('Apply'));
        await settle(t);
        expect(find.text('End coaching with Coach Avery Stone?'), findsOneWidget,
            reason: 'premise');
        server.seen.clear();
      },
      start: (t) async {
        await t.tap(find.text('End & switch'));
        await t.pump();
      },
    ),
    (
      name: 'Intake "end previous coach"',
      outcome: ('IntakeFlow.selectCoach.endPrevious',
          'Bad state: end previous coach outcome not shown: the signed-in account changed'),
      open: (t) async {
        Map<String, Object?> at(String first) =>
            {'onboarding_step': 23, 'first_name': first, 'last_name': 'Lee'};
        server.rows.addAll({
          'user_profiles': {
            memberA: [at('Alice')],
            memberB: [at('Bob')],
          },
          'coach_client_relationships': {
            memberA: [{'coach_id': 'coach-9'}],
            memberB: [{'coach_id': 'coach-7'}],
          },
        });
        paidWith('coach-9');
        await t.binding.setSurfaceSize(const Size(430, 1600));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(ProviderScope(
          overrides: [
            availableCoachesProvider.overrideWith((ref) async => [
                  {'id': 'coach-1', 'first_name': 'Cody', 'last_name': 'Ng'},
                ]),
          ],
          child: const MaterialApp(home: IntakeFlowScreen()),
        ));
        await settle(t);
        expect(find.text('Select Coach'), findsOneWidget, reason: 'premise');
        server.seen.clear();
        reported.clear();
      },
      start: (t) async {
        await t.tap(find.text('Select Coach'));
        await t.pump();
      },
    ),
  ];

  for (final flow in flows) {
    group(flow.name, () {
      void nothingSaid() {
        expect(find.byType(SnackBar), findsNothing);
        expect(find.textContaining('account changed'), findsNothing);
        expect(find.textContaining('Not done'), findsNothing);
        expect(find.textContaining('continues until'), findsNothing);
      }

      for (final (what, next) in [('B signs in', memberB), ('A signs out', null)]) {
        testWidgets("$what while A's FIRST cancellation is in flight: the "
            'second is never sent; the outcome recorded once', (t) async {
          await flow.open(t);
          final hold = server.holds['POST cancel-subscription:$memberA'] = Completer();
          await flow.start(t);
          await pumpUntil(t, () => invokes().isNotEmpty, what: 'A asked');
          await t.runAsync(() => next == null ? signOut() : signInAs(next));
          hold.complete();
          await settle(t, 12);
          expect(invokes().map((r) => (r.who, (r.body as Map)['subscriptionId'])),
              [(memberA, 'sub-a-1')]);
          expect(server.seen.where((r) => r.who == memberB && !r.isRead), isEmpty);
          expect(server.writes('notifications'), isEmpty);
          nothingSaid();
          expect(records(), [stop, flow.outcome],
              reason: "THE defect: A's first subscription WAS cancelled and "
                  'nothing recorded that its outcome was never shown');
          await close(t);
        });

        testWidgets('$what while the subscriptions read is in flight (nothing '
            'sent): the service\'s stop is the single record', (t) async {
          await flow.open(t);
          final hold = server.holds['GET subscriptions:$memberA'] = Completer();
          await flow.start(t);
          await pumpUntil(
              t, () => server.reads('subscriptions', memberA).isNotEmpty,
              what: 'the read');
          await t.runAsync(() => next == null ? signOut() : signInAs(next));
          hold.complete();
          await settle(t, 12);
          expect(invokes(), isEmpty);
          nothingSaid();
          expect(records(), [stop]);
          await close(t);
        });
      }

      testWidgets('control, the same account through a token refresh: both '
          'cancelled as A, nothing recorded', (t) async {
        await flow.open(t);
        final hold = server.holds['POST cancel-subscription:$memberA'] = Completer();
        await flow.start(t);
        await pumpUntil(t, () => invokes().isNotEmpty, what: 'A asked');
        await t.runAsync(refreshSession);
        hold.complete();
        await settle(t, 12);
        expect(invokes().map((r) => (r.who, (r.body as Map)['subscriptionId'])),
            [(memberA, 'sub-a-1'), (memberA, 'sub-a-2')]);
        expect(records(), isEmpty);
        await close(t);
      });
    });
  }
}
