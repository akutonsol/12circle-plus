import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/payments/presentation/manage_subscription_screen.dart';
import 'package:circle_fitness/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_change_server.dart';
import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart';

// P0-RM-1 (C15-63b-03, C14-62b-04) · "Stop coach" (Manage Subscription) and
// "Cancel Coach" (Profile) when A pays for TWO coaching subscriptions and the
// account changes part-way.
//
// The REAL screens and service run against a fake server that answers by
// bearer token; nothing mounts an account scope and each screen STAYS mounted
// across the switch. Profile draws the REAL assignedCoachProvider.
//
//  * B signs in (or A signs out) while A's FIRST cancellation is in flight:
//    the second is never sent; A's first subscription IS cancelled, so the
//    outcome nobody saw is recorded once (`<flow> outcome not shown`), beside
//    the service's own record of the stop — exactly two records;
//  * the same while A's subscriptions read is in flight: nothing was sent, the
//    service's stop is the single record;
//  * controls: same account (and a token refresh mid-flow): both cancelled,
//    told once, nothing recorded.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --` the RM-1 lib files (see the
// RM-1 report): the "first cancellation" cases find no outcome record.

const _a = memberA;
const _b = memberB;
const _endsSaid = 'Your coaching continues until Mar 3, the end of the period '
    'you have paid for, then ends. Your coach has been notified.';

void main() {
  final server = CoachChangeServer();
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  setUp(() {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    for (final who in [_a, _b]) {
      server.coachOf[who] = CoachChangeServer.coach;
    }
    server.paid[_a] = ['sub-a-1', 'sub-a-2'];
    server.paid[_b] = ['sub-b-1'];
    server.profiles[CoachChangeServer.coach] = {
      'id': CoachChangeServer.coach,
      'first_name': 'Anna',
      'last_name': 'Coach',
    };
  });
  tearDown(resetFailureSink);

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester t) async {
    for (final g in server.gates.values) {
      if (!g.isCompleted) g.complete();
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    await t.runAsync(signOut);
  }

  List<(String, Object?)> invoked() => [
        for (final r in server.invokes)
          (r.who, (jsonDecode(r.body) as Map)['subscriptionId'])
      ];

  List<(String, String)> records() =>
      [for (final f in reported) (f.origin, '${f.error}')];

  final flows = <({
    String name,
    String origin,
    String flow,
    Future<void> Function(WidgetTester) open,
    Future<void> Function(WidgetTester) toConfirm,
    Finder confirm,
  })>[
    (
      name: 'Manage Subscription "Stop"',
      origin: 'ManageSubscriptionScreen.stopCoach',
      flow: 'stop coaching',
      open: (t) async {
        await t.binding.setSurfaceSize(const Size(700, 3200));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.runAsync(() => signInAs(_a));
        await t.pumpWidget(const ProviderScope(
            child: MaterialApp(home: ManageSubscriptionScreen())));
        await pumpUntil(t, () => seen(find.text('Stop')), what: "A's coach");
        await settle(t);
      },
      toConfirm: (t) async {
        await t.tap(find.text('Stop'));
        await pumpUntil(t, () => seen(find.text('Stop working with Anna Coach?')),
            what: 'the dialog');
        await settle(t);
      },
      confirm: find.text('Yes, stop'),
    ),
    (
      name: 'Profile "Cancel Coach"',
      origin: 'MyCoachSection.cancelCoach',
      flow: 'end coaching',
      open: (t) async {
        t.view.physicalSize = const Size(900, 2000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.runAsync(() => signInAs(_a));
        await t.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: MyCoachSection(onCoachCancelled: () {}))),
          ),
        ));
        await pumpUntil(t, () => seen(find.text('Cancel Coach')), what: "A's coach");
        await settle(t);
      },
      toConfirm: (t) async {
        await t.tap(find.text('Cancel Coach'));
        await pumpUntil(t, () => seen(find.text('Cancel Your Coach')),
            what: 'the sheet');
        await settle(t);
        await t.tap(find.text('Not a good fit'));
        await t.pump();
      },
      confirm: find.text('Cancel Coach').last,
    ),
  ];

  for (final flow in flows) {
    group(flow.name, () {
      void nothingSaid() {
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(_endsSaid), findsNothing);
        expect(find.textContaining('account changed'), findsNothing);
        expect(find.textContaining('Not done'), findsNothing);
      }

      for (final (what, next) in [('B signs in', _b), ('A signs out', null)]) {
        testWidgets('$what while A\'s FIRST cancellation is in flight (a step '
            'already SENT): second never sent, outcome recorded once as not '
            'shown', (t) async {
          await flow.open(t);
          await flow.toConfirm(t);
          server.log.clear();
          final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
          await t.tap(flow.confirm);
          await t.pump();
          await pumpUntil(t, () => server.invokes.isNotEmpty, what: 'A asked');
          await t.runAsync(() => next == null ? signOut() : signInAs(next));
          await t.pump();
          gate.complete();
          await settle(t);
          expect(invoked(), [(_a, 'sub-a-1')],
              reason: 'the second went out, or as someone else');
          expect(server.restWrites, isEmpty);
          expect(server.log.where((r) => r.body.contains('sub-b')), isEmpty);
          nothingSaid();
          expect(records(), [
            ('CoachRelationshipService.cancelCoach',
                'Ending coaching: the signed-in account changed'),
            (flow.origin,
                'Bad state: ${flow.flow} outcome not shown: the signed-in account changed'),
          ], reason: "THE defect: A's first subscription WAS cancelled and "
              'nothing recorded that its outcome was never shown');
          await unmount(t);
        });

        testWidgets('$what while A\'s subscriptions read is in flight (NOTHING '
            'sent yet): the service\'s stop is the single record', (t) async {
          await flow.open(t);
          await flow.toConfirm(t);
          server.log.clear();
          final gate = server.gates['GET subscriptions/coach:$_a'] = Completer();
          await t.tap(flow.confirm);
          await t.pump();
          await pumpUntil(t, () => server.named('subscriptions').isNotEmpty,
              what: 'the read');
          await t.runAsync(() => next == null ? signOut() : signInAs(next));
          await t.pump();
          gate.complete();
          await settle(t);
          expect(server.invokes, isEmpty);
          expect(server.restWrites, isEmpty);
          nothingSaid();
          expect(records(), [
            ('CoachRelationshipService.cancelCoach',
                'Ending coaching: the signed-in account changed'),
          ]);
          await unmount(t);
        });
      }

      for (final refresh in [false, true]) {
        testWidgets('control, the same account${refresh ? ' (token refresh '
            'mid-flow)' : ''}: both cancelled as A, told once, nothing '
            'recorded', (t) async {
          await flow.open(t);
          await flow.toConfirm(t);
          server.log.clear();
          final gate = server.gates['POST cancel-subscription:$_a'] = Completer();
          await t.tap(flow.confirm);
          await t.pump();
          await pumpUntil(t, () => server.invokes.isNotEmpty, what: 'A asked');
          if (refresh) await t.runAsync(refreshSession);
          gate.complete();
          await pumpUntil(t, () => seen(find.text(_endsSaid)), what: 'the outcome');
          await settle(t);
          expect(invoked(), [(_a, 'sub-a-1'), (_a, 'sub-a-2')]);
          expect(find.text(_endsSaid), findsOneWidget);
          expect(records(), isEmpty);
          await unmount(t);
        });
      }
    });
  }
}
