// P0-FL-62b · Intake's "Choose Coach" step ends the member's PREVIOUS coach
// (`cancelCoach(..., 'switched_during_intake', expectedUid: owner)`) for the
// member who chose, at every step. When the service refuses because the
// signed-in account changed (it has recorded that once), the step stops
// there: nothing more is sent — no other coach ended, no notification — and
// nothing is said to whoever is signed in now.
//
// The real IntakeFlowScreen on its Choose Coach page (the harness of
// intake_coach_pick_truth_test.dart: `onboarding_step` 23 opens it), the real
// CoachRelationshipService, real auth transitions on one device; no
// AccountScope, and the screen stays mounted across the switch. The request
// log says whose token asked for which row.
//
// A has one previous, UNPAID coach (coach-9): ending it is a relationship
// update, then a "coaching ended" notice to that coach.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/onboarding/presentation/intake_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/member_switch_server.dart';
import '../support/pump_until.dart';

const _coachPage = 23;

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
    Map<String, Object?> at(String first) => {
          'onboarding_step': _coachPage,
          'first_name': first,
          'last_name': 'Lee',
        };
    server.rows.addAll({
      'user_profiles': {
        memberA: [at('Alice')],
        memberB: [at('Bob')],
      },
      // The "other active coaches" read: A had coach-9; B has coach-7.
      'coach_client_relationships': {
        memberA: [
          {'coach_id': 'coach-9'}
        ],
        memberB: [
          {'coach_id': 'coach-7'}
        ],
      },
      // Neither previous coach is paid: ending one is a relationship update.
      'subscriptions': {memberA: [], memberB: []},
    });
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
    expect(find.text('Select Coach'), findsOneWidget,
        reason: 'premise: the flow opened on Choose Coach');
    server.seen.clear();
    reported.clear();
  }

  Future<void> close(WidgetTester t) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  Iterable<AppFailure> accountChanges() => reported
      .where((f) => '${f.error}'.contains('the signed-in account changed'));

  /// The end of A's previous coach is under way: cancelCoach's own
  /// subscriptions read (it filters by coach) has been asked, as A.
  Iterable<SeenRequest> endReads() => server
      .reads('subscriptions')
      .where((r) => r.query.containsKey('coach_id'));

  /// A ending of a coaching: the relationship update.
  Iterable<SeenRequest> ends() => server
      .writes('coach_client_relationships')
      .where((w) => w.method == 'PATCH');

  void nothingSaid() {
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining("You're set with"), findsNothing);
    expect(find.textContaining("couldn't be ended"), findsNothing);
    expect(find.textContaining("Couldn't select"), findsNothing);
    expect(find.textContaining('account changed'), findsNothing);
  }

  for (final (what, next) in [('B signs in', memberB), ('A signs out', null)]) {
    testWidgets("$what while A's previous coach is being ended: nothing more "
        'is sent, nothing said, recorded once', (t) async {
      await open(t);
      final hold = server.holds['GET subscriptions:$memberA'] = Completer();
      await t.tap(find.text('Select Coach'));
      await pumpUntil(t, () => endReads().isNotEmpty, what: "A's end started");
      final read = endReads().single;
      expect((read.who, read.query['user_id'], read.query['coach_id']),
          (memberA, 'eq.$memberA', 'eq.coach-9'),
          reason: "premise: ending A's previous coach, as A");
      await t.runAsync(() => next == null ? signOut() : signInAs(next));
      hold.complete();
      await settle(t, 12);
      // Only A's link went out (before the switch); nothing after it.
      expect(server.writes().map((w) => (w.who, w.method, w.target)),
          [(memberA, 'POST', 'coach_client_relationships')]);
      expect(ends(), isEmpty, reason: 'a coaching was ended after the switch');
      expect(server.writes('notifications'), isEmpty,
          reason: 'a coach was told something after the switch');
      expect(endReads().where((r) => r.who != memberA), isEmpty,
          reason: "B's previous coach was looked up");
      nothingSaid();
      expect(find.textContaining('Meet Coach'), findsNothing);
      expect(accountChanges(), hasLength(1),
          reason: 'THE defect: the one stop was recorded '
              '${accountChanges().length} times '
              '(${reported.map((f) => f.origin).toList()})');
      await close(t);
    });
  }

  for (final (what, before, during)
      in <(String, Future<void> Function(WidgetTester)?, bool)>[
    ('as opened', null, false),
    ('through a token refresh while the end is under way', null, true),
    ('after A signed out and back in', (t) async {
      await t.runAsync(signOut);
      await settle(t);
      await t.runAsync(() => signInAs(memberA));
      await settle(t, 12);
      await pumpUntil(t, () => find.text('Select Coach').evaluate().isNotEmpty,
          what: 'Choose Coach again');
      server.seen.clear();
      reported.clear();
    }, false),
  ]) {
    testWidgets('POSITIVE CONTROL, the same member ($what): the previous coach '
        'is ended for A, both coaches are told, by A', (t) async {
      await open(t);
      if (before != null) await before(t);
      final hold = during
          ? server.holds['GET subscriptions:$memberA'] = Completer<void>()
          : null;
      await t.tap(find.text('Select Coach'));
      if (hold != null) {
        await pumpUntil(t, () => endReads().isNotEmpty, what: "A's end started");
        await t.runAsync(refreshSession);
        hold.complete();
      }
      await settle(t, 12);
      await pumpUntil(t, () => find.text('Meet Coach Cody Ng').evaluate().isNotEmpty,
          what: 'the new coach');
      final link = server.writes('coach_client_relationships')
          .singleWhere((w) => w.method == 'POST');
      expect((link.who, link.row['client_id'], link.row['coach_id']),
          (memberA, memberA, 'coach-1'));
      final end = ends().single;
      expect(
          (end.who, end.query['client_id'], end.query['coach_id'],
              end.query['status'], end.row['cancel_reason']),
          (memberA, 'eq.$memberA', 'eq.coach-9', 'eq.active',
              'switched_during_intake'));
      expect(end.query['select'], 'id', reason: 'a 0-row end must be seen');
      final told = server.writes('notifications')
          .map((w) => (w.who, w.row['recipient_id'], w.row['type']))
          .toList();
      expect(told, [
        (memberA, 'coach-9', 'coaching_ended'),
        (memberA, 'coach-1', 'new_client'),
      ]);
      expect(server.seen.where((r) => r.who == memberB), isEmpty);
      expect(find.textContaining("couldn't be ended"), findsNothing);
      expect(accountChanges(), isEmpty);
      await close(t);
    });
  }
}
