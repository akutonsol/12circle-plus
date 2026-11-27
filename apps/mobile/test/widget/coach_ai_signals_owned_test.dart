// P0-FL-62c · the coach dashboard's AI COACH SIGNALS card belongs to its coach.
//
// The card names a coach's flagged clients with their drop-off and injury
// risk. It was drawn with `maybeWhen(data: …, orElse: shrink)`: while the
// read is refreshed Riverpod keeps the previous value and `maybeWhen` draws
// it, so coach A's flagged clients stayed up for coach B until B's answer
// landed — and a failed read was drawn as the card's absence, which is what
// "nobody is flagged" looks like.
//
// The screen is mounted WITHOUT the app-root account scope and kept mounted
// across a real A -> B switch (the real auth client; the fake server answers
// each coach with what the RPC returns for `auth.uid()`).
//
// HOW TO SEE IT FAIL:
//   git checkout a446926 -- lib/features/dashboard/presentation/coach_dashboard_screen.dart
// "A's refresh, then B" draws A's client for B; "B's read failed" finds no
// failure said; "B's own failure is retried" likewise. The controls pass on
// both.
import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/checkins/domain/checkin_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/dashboard/domain/coach_triage_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/coach_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

const _rpc = 'POST rpc/coach_client_ai_signals';
const _failed = "Couldn't load your AI coach signals";

/// A live change to a table: the reads that watch it run again.
final _tick = StateProvider<int>((ref) => 0);

void main() {
  final server = TwoCoachPostgrest();
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  void coach(String who, String client, String signal) {
    server
      ..seed('coach_client_relationships', who, [
        {'client_id': client, 'status': 'active'}
      ])
      ..seed('user_profiles', who, [
        {
          'id': client,
          'first_name': client,
          'last_name': 'Client',
          'email': '$client@client.example',
          'role': 'client',
          'risk_level': 'low',
        }
      ])
      ..seed('rpc/coach_client_ai_signals', who, [
        {
          'client_id': client,
          'client_name': signal,
          'churn_risk': 80,
          'injury_risk': 60,
          'workouts_7d': 1,
          'risk_summary': 'Summary of $signal',
        }
      ]);
  }

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    coach(memberA, 'alma', 'Alma Signal');
    coach(memberB, 'boris', 'Boris Signal');
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool seen(Finder f) => f.evaluate().isNotEmpty;
  Finder ofA() => find.text('Alma Signal');
  Finder ofB() => find.text('Boris Signal');

  void nothingOfA(String when) {
    expect(ofA(), findsNothing,
        reason: "THE defect: A's flagged client was drawn for B ($when)");
    expect(find.textContaining('Summary of Alma'), findsNothing,
        reason: "A's client's risk summary ($when)");
  }

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider
          .overrideWith((ref, t) => Stream.value(ref.watch(_tick))),
      currentUserProfileProvider.overrideWith((ref) async => null),
      currentUserDisplayNameProvider.overrideWithValue('Coach'),
      coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
      coachLeaderboardProvider.overrideWith((ref) async => const []),
      coachTriageSignalsProvider.overrideWith((ref) async => const []),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: CoachDashboardScreen())));
    await pumpUntil(tester, () => seen(ofA()), what: "A's signals");
    await frames(tester);
    expect(find.text('AI COACH SIGNALS'), findsOneWidget, reason: 'premise');
    expect(find.text('Drop-off 80%'), findsOneWidget, reason: 'premise');
    server.calls.clear();
  }

  Future<void> unmount(WidgetTester tester) async {
    for (final h in server.holds.values) {
      if (!h.isCompleted) h.complete();
    }
    await frames(tester);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> become(WidgetTester tester, String? uid) async {
    await tester.runAsync(() => uid == null ? signOut() : signInAs(uid));
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
  }

  testWidgets(
      "coach A -> coach B with A's refresh in flight and B's read pending: "
      "nothing of A's; B's own when it lands; A's late answer lands on nobody",
      (tester) async {
    await show(tester);
    final lateA = server.holds['$_rpc:$memberA'] = Completer<void>();
    final holdB = server.holds['$_rpc:$memberB'] = Completer<void>();
    // A's own refresh (a retry, a pull): A's rows stay up meanwhile.
    c.invalidate(coachAiSignalsProvider);
    await frames(tester, 2);
    expect(ofA(), findsOneWidget, reason: "A's refresh keeps A's card for A");
    await become(tester, memberB);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      nothingOfA('B pending, frame $i');
    }
    expect(find.text(_failed), findsNothing,
        reason: 'B has not failed: nothing to say yet');
    // B's answer first, then A's late one.
    holdB.complete();
    await pumpUntil(tester, () => seen(ofB()), what: "B's own signals");
    lateA.complete();
    await frames(tester);
    nothingOfA("after A's late answer");
    expect(ofB(), findsOneWidget);
    // The request log: A's refresh asked as A, once; B's read as B, once.
    expect(server.count('$_rpc:$memberA'), 1);
    expect(server.count('$_rpc:$memberB'), 1);
    await unmount(tester);
  });

  for (final (cause, nudge) in [
    ('an invalidate (Try again)', (ProviderContainer c) => c.invalidate(coachAiSignalsProvider)),
    ('a live tick', (ProviderContainer c) => c.read(_tick.notifier).state++),
  ]) {
    testWidgets(
        "coach A -> coach B in the same turn as $cause, B's read pending: "
        "nothing of A's on any frame; then B's own", (tester) async {
      await show(tester);
      final holdB = server.holds['$_rpc:$memberB'] = Completer<void>();
      await tester.runAsync(() async {
        nudge(c);
        await signInAs(memberB);
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        nothingOfA('B pending after $cause, frame $i');
      }
      expect(server.count('$_rpc:$memberB'), greaterThanOrEqualTo(1),
          reason: "B's signals are asked for as B");
      holdB.complete();
      await pumpUntil(tester, () => seen(ofB()), what: "B's own signals");
      nothingOfA('B answered');
      await unmount(tester);
    });
  }

  testWidgets(
      "coach A -> coach B, B's read failed: B's failure is said, never A's "
      "rows and never 'nobody flagged'", (tester) async {
    await show(tester);
    server.fails.add('$_rpc:$memberB');
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "B's failure said",
        timeout: const Duration(seconds: 10));
    nothingOfA('B failed');
    expect(ofB(), findsNothing);
    expect(find.textContaining('SECRET'), findsNothing,
        reason: 'never the raw exception text');
    expect(find.bySemanticsLabel('Try again: load your AI coach signals'),
        findsOneWidget);
    expect(server.count('$_rpc:$memberB'), 1);
    expect(server.count('$_rpc:$memberA'), 0,
        reason: 'nothing was asked as A after A left');
    expect(
        reported.where((f) => f.origin == 'coachAiSignalsProvider').length, 1,
        reason: "B's failure is recorded once");
    await unmount(tester);
  });

  testWidgets(
      "coach A -> coach B with A's refresh held, B's read failed: nothing of "
      "A's, B's failure said", (tester) async {
    await show(tester);
    server.holds['$_rpc:$memberA'] = Completer<void>();
    server.fails.add('$_rpc:$memberB');
    c.invalidate(coachAiSignalsProvider);
    await frames(tester, 2);
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "B's failure said",
        timeout: const Duration(seconds: 10));
    nothingOfA('B failed over A refresh');
    server.holds['$_rpc:$memberA']!.complete();
    await frames(tester);
    nothingOfA("after A's late answer");
    await unmount(tester);
  });

  testWidgets("B's own failure is retried: busy, then B's own rows",
      (tester) async {
    await show(tester);
    server.fails.add('$_rpc:$memberB');
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "B's failure said",
        timeout: const Duration(seconds: 10));
    server.fails.clear();
    await tester.tap(find.text('Try again'));
    await pumpUntil(tester, () => seen(ofB()), what: "B's rows after retry");
    expect(find.text(_failed), findsNothing);
    nothingOfA('after retry');
    expect(server.count('$_rpc:$memberB'), 2);
    await unmount(tester);
  });

  testWidgets(
      'CONTROL: a live reload (tableTicker) for the same coach keeps the card '
      'up throughout and reads once more, as A', (tester) async {
    await show(tester);
    final hold = server.holds['$_rpc:$memberA'] = Completer<void>();
    c.read(_tick.notifier).state++;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(ofA(), findsOneWidget,
          reason: "A's own card stays while A's reload is in flight ($i)");
    }
    // (The test's ticker is rebuilt as a new stream, whose loading and data
    // each re-read; the real ticker is one stream. Asked as A, whatever.)
    expect(server.count('$_rpc:$memberA'), greaterThanOrEqualTo(1),
        reason: 'the reload went out');
    hold.complete();
    await frames(tester);
    expect(ofA(), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    expect(server.count('$_rpc:$memberB'), 0);
    await unmount(tester);
  });

  testWidgets(
      'CONTROL: a refreshed token keeps the card and reads nothing again',
      (tester) async {
    await show(tester);
    final before = c.read(currentUserProvider);
    await tester.runAsync(refreshSession);
    await pumpUntil(tester, () => c.read(currentUserProvider) != before,
        what: 'the same coach as a new User');
    expect(c.read(currentUserProvider)?.id, memberA);
    await frames(tester);
    expect(ofA(), findsOneWidget);
    expect(server.count('$_rpc:$memberA'), 0);
    await unmount(tester);
  });

  testWidgets(
      'CONTROL: sign-out -> the same coach back in: nothing while out, then '
      "A's own card again", (tester) async {
    await show(tester);
    await become(tester, null);
    await frames(tester);
    expect(ofA(), findsNothing, reason: "nothing of A's while signed out");
    await become(tester, memberA);
    await pumpUntil(tester, () => seen(ofA()), what: "A's card again");
    expect(server.count('$_rpc:$memberA'), greaterThanOrEqualTo(1));
    expect(server.count('$_rpc:$memberB'), 0);
    await unmount(tester);
  });
}
