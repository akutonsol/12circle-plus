// P0-FL-62b · Settings' switch to Self-Guided ends a PAID coach for the member
// whose sheet it is, at every step (cancelCoach is given that member), and a
// stop for a changed account is said to nobody and recorded once.
//
// The real SettingsScreen, row, sheet and CoachRelationshipService; real auth
// transitions; no AccountScope; the screen stays mounted across the switch.
// A and B each pay coach Avery (one active coaching subscription each).
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';

// Midday UTC: the same calendar day wherever the test runs (it is shown local).
const _endsAt = '2027-03-03T12:00:00Z';
const _endsSaid = 'Your coaching continues until Mar 3, the end of the period '
    'you have paid for, then ends. Your coach has been notified.';

void main() {
  final server = MemberSwitchServer();
  final reported = <AppFailure>[];
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
    watchAuthChanges();
  });

  setUp(() async {
    server.reset();
    await signInAs(memberA);
    reported.clear();
    setFailureSink(reported.add);
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
          m: [{'id': 'rel-$m', 'coach_id': 'coach-a', 'status': 'active'}],
      },
      'public_profiles': {
        for (final m in [memberA, memberB])
          m: [{'id': 'coach-a', 'first_name': 'Avery', 'last_name': 'Stone'}],
      },
      'subscriptions': {
        for (final m in [memberA, memberB])
          m: [{'id': 'sub-$m', 'current_period_end': _endsAt}],
      },
    });
    server.functions['cancel-subscription'] = {'ok': true, 'endsAt': _endsAt};
  });
  tearDown(resetFailureSink);

  Future<void> settle(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(500, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await settle(t);
    expect(find.text('Coach Guided'), findsOneWidget, reason: 'premise');
    // Ask to switch to Self-Guided, up to "End & switch".
    await t.tap(find.text('Coach Guided'));
    await settle(t);
    await t.tap(find.text('Self Guided'));
    await settle(t);
    await t.tap(find.text('Apply'));
    await settle(t);
    expect(find.text('End & switch'), findsOneWidget, reason: 'premise');
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 12));
  }

  Iterable<AppFailure> accountChanges() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'));

  Iterable<SeenRequest> invokes() => server.writes('cancel-subscription');

  void nothingSaidToB() {
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('continues until'), findsNothing);
    expect(find.textContaining('Could not save'), findsNothing);
    expect(find.textContaining('account changed'), findsNothing);
  }

  testWidgets('control, the same member: one cancel-subscription for their '
      'row, they are told when it ends, and their mode is saved', (t) async {
    await open(t);
    await t.tap(find.text('End & switch'));
    await settle(t, 12);
    final read = server.reads('subscriptions').single;
    expect((read.who, read.query['user_id'], read.query['coach_id']),
        (memberA, 'eq.$memberA', 'eq.coach-a'));
    expect(invokes().map((r) => (r.who, r.row['subscriptionId'])),
        [(memberA, 'sub-$memberA')]);
    expect(server.writes('coach_client_relationships'), isEmpty,
        reason: 'a paid coach is ended by the subscription (decision 2)');
    expect(find.text(_endsSaid), findsOneWidget);
    final mode = server
        .writes('user_profiles')
        .where((w) => '${w.body}'.contains('coaching_mode'))
        .single;
    expect((mode.who, mode.query['id']), (memberA, 'eq.$memberA'));
    expect(accountChanges(), isEmpty);
    await close(t);
  });

  for (final (what, next) in [('B signs in', memberB), ('A signs out', null)]) {
    testWidgets("$what while A's subscriptions read is in flight: no "
        'cancel-subscription, nothing said, recorded once', (t) async {
      await open(t);
      final hold = server.holds['GET subscriptions:$memberA'] = Completer();
      await t.tap(find.text('End & switch'));
      await settle(t, 3);
      expect(server.reads('subscriptions', memberA), hasLength(1),
          reason: 'premise');
      await t.runAsync(() => next == null ? signOut() : signInAs(next));
      hold.complete();
      await settle(t, 12);
      expect(invokes(), isEmpty);
      expect(server.writes(), isEmpty,
          reason: 'no relationship, notification or mode was written');
      nothingSaidToB();
      expect(accountChanges(), hasLength(1),
          reason: 'THE defect: the one stop was recorded '
              '${accountChanges().length} times');
      await close(t);
    });
  }

  testWidgets("B signs in while A's cancel-subscription is in flight: only A's "
      'row, once; nothing else is written, nothing said to B', (t) async {
    await open(t);
    final hold = server.holds['POST cancel-subscription:$memberA'] = Completer();
    await t.tap(find.text('End & switch'));
    await settle(t, 3);
    expect(invokes(), hasLength(1), reason: 'premise');
    await t.runAsync(() => signInAs(memberB));
    hold.complete();
    await settle(t, 12);
    expect(invokes().map((r) => (r.who, r.row['subscriptionId'])),
        [(memberA, 'sub-$memberA')]);
    expect(server.writes().where((w) => w.target != 'cancel-subscription'),
        isEmpty, reason: 'no relationship, notification or mode was written');
    nothingSaidToB();
    await close(t);
  });
}
