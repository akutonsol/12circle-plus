// P0-FL-62c (round 3) · the coach dashboard's NEEDS YOU TODAY card belongs to
// its coach.
//
// The card names a coach's clients and why each needs them today (a check-in
// note, a silence, a block ending, an unanswered message). It was drawn with
// `ref.watch(coachTriageSignalsProvider).when(...)` and no owner check: Riverpod
// keeps the previous value while the next read is out, so coach A's clients and
// reasons could be up for coach B. And the read is EIGHT requests long: one that
// straddled a switch went on asking, under coach B's token, about coach A's
// clients.
//
// The screen is mounted WITHOUT the app-root account scope and kept mounted
// across a real A -> B switch (the real auth client; the fake server answers
// each coach with what RLS shows the coach the bearer token names).
//
// HOW TO SEE IT FAIL:
//   git checkout 0a723c3 -- lib/features/dashboard/domain/coach_triage_provider.dart \
//       lib/features/dashboard/presentation/coach_dashboard_screen.dart
// Fail there: "A's read straddles the switch" (3 `workout_sessions` as B for
// 2 reads of B's: A's read went on under B's token), "the auth client already
// names coach B" (A's row drawn on the rebuild), and — for the error contract,
// not the owner — "B's read failed" and "the same coach's own refresh fails"
// (the failure was never recorded). The rest are coverage: on 0a723c3 a change
// of dependency makes the read a RELOAD, which `.when` draws as loading, so A's
// rows were not drawn on the frames these tests can reach. "A's read
// straddles the switch at its LAST step" fails there on the record only.
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
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, User;

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

/// Requests only the triage read makes on this screen (the other readers of
/// these tables are replaced below).
const _checkins = 'GET weekly_checkins';
const _sessions = 'GET workout_sessions';
const _convos = 'GET conversations';
const _failed = "Couldn't load what needs you today";
const _origin = 'coachTriageSignalsProvider';

/// The account the app's providers have heard of, held apart from the auth
/// client: the window in which the auth client already names the next coach
/// and no rebuild of [currentUserProvider] has been flushed yet.
final _heard = StateProvider<User?>(
    (ref) => Supabase.instance.client.auth.currentUser);

void main() {
  final server = TwoCoachPostgrest();
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initTwoMemberSupabase(server);
  });

  void coach(String who, String client, String note) {
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
      ..seed('weekly_checkins', who, [
        {
          'user_id': client,
          'week_number': 3,
          'notes': note,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_at': null,
        }
      ]);
  }

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    coach(memberA, 'alma', 'Alma triage note');
    coach(memberB, 'boris', 'Boris triage note');
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool seen(Finder f) => f.evaluate().isNotEmpty;
  // The row's reason, which only the triage card draws (the client's name is
  // on the roster too, which has its own owner check).
  Finder ofA() => find.text('Week 3 check-in · Alma triage note');
  Finder ofB() => find.text('Week 3 check-in · Boris triage note');
  String key(String what, String who) => '$what:$who';

  void nothingOfA(String when) {
    expect(ofA(), findsNothing,
        reason: "THE defect: A's client and reason were drawn for B ($when)");
    expect(find.bySemanticsLabel(RegExp('Alma triage note')), findsNothing,
        reason: "A's row's label ($when)");
  }

  Future<void> show(WidgetTester tester, {bool holdHeard = false}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      currentUserProfileProvider.overrideWith((ref) async => null),
      currentUserDisplayNameProvider.overrideWithValue('Coach'),
      coachNotificationsProvider.overrideWith((ref) => Stream.value(const [])),
      coachSubmittedCheckinsProvider.overrideWith((ref) async => const []),
      coachLeaderboardProvider.overrideWith((ref) async => const []),
      coachAiSignalsProvider.overrideWith((ref) async => const []),
      clientCheckinsProvider.overrideWith((ref) async => const []),
      clientWorkoutLogsProvider.overrideWith((ref) async => const []),
      if (holdHeard)
        currentUserProvider.overrideWith((ref) => ref.watch(_heard)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: CoachDashboardScreen())));
    await pumpUntil(tester, () => seen(ofA()), what: "A's triage row");
    await frames(tester);
    expect(find.text('Needs you today'), findsOneWidget, reason: 'premise');
    expect(server.count(key(_checkins, memberA)), 1,
        reason: 'premise: only the triage read asks for check-ins here');
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
      "coach A -> coach B in the same turn as A's refresh, B's read pending: "
      "nothing of A's on any frame; then B's own", (tester) async {
    // Coverage on 0a723c3 (the switch makes A's refresh a reload there).
    await show(tester);
    final holdB = server.holds[key(_checkins, memberB)] = Completer<void>();
    await tester.runAsync(() async {
      c.invalidate(coachTriageSignalsProvider);
      await signInAs(memberB);
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      nothingOfA('B pending, frame $i');
    }
    expect(find.text(_failed), findsNothing,
        reason: 'B has not failed: nothing to say yet');
    holdB.complete();
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    nothingOfA('B answered');
    expect(server.count(key(_checkins, memberB)), greaterThanOrEqualTo(1),
        reason: "B's check-ins are asked for as B");
    await unmount(tester);
  });

  testWidgets(
      "coach A -> coach B, B's read pending (A's rows settled): nothing of "
      "A's on any frame; B's own when it lands", (tester) async {
    // Coverage on 0a723c3: a change of dependency already hid the card there.
    await show(tester);
    final holdB = server.holds[key(_checkins, memberB)] = Completer<void>();
    await become(tester, memberB);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      nothingOfA('B pending, frame $i');
    }
    expect(find.text(_failed), findsNothing);
    holdB.complete();
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    nothingOfA('B answered');
    expect(server.count(key(_checkins, memberB)), greaterThanOrEqualTo(1));
    expect(server.count(key(_checkins, memberA)), 0,
        reason: 'nothing was asked as A after A left');
    await unmount(tester);
  });

  testWidgets(
      "coach A -> coach B, B's read failed: B's failure is said, never A's "
      'rows and never "Nothing needs you"', (tester) async {
    await show(tester);
    server.fails.add(key(_checkins, memberB));
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "B's failure said", timeout: const Duration(seconds: 10));
    nothingOfA('B failed');
    expect(ofB(), findsNothing);
    expect(find.text('Nothing needs you right now.'), findsNothing,
        reason: 'a failure is never drawn as "nothing needs you"');
    expect(find.textContaining('SECRET'), findsNothing,
        reason: 'never the raw exception text');
    // (The card is re-subscribed when the roster under it reloads for B, and
    // the auto-disposed read is asked again: each B read fails, each once.)
    final bReads = server.count(key(_checkins, memberB));
    expect(bReads, greaterThanOrEqualTo(1));
    expect(server.count(key(_checkins, memberA)), 0);
    expect(reported.where((f) => f.origin == _origin).length, bReads,
        reason: "each of B's failed reads is recorded once");
    await unmount(tester);
  });

  testWidgets(
      "coach A -> coach B with A's refresh held, B's read failed: nothing of "
      "A's, B's failure said; A's late answer changes nothing", (tester) async {
    await show(tester);
    final lateA = server.holds[key(_checkins, memberA)] = Completer<void>();
    server.fails.add(key(_checkins, memberB));
    c.invalidate(coachTriageSignalsProvider);
    await frames(tester, 2);
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "B's failure said", timeout: const Duration(seconds: 10));
    nothingOfA('B failed over A refresh');
    lateA.complete();
    await frames(tester);
    nothingOfA("after A's late answer");
    expect(find.text(_failed), findsOneWidget, reason: "B's failure stays said");
    await unmount(tester);
  });

  testWidgets(
      "A's read straddles the switch, A's late answer lands after B's: "
      "nothing more is asked under B's token about A's clients, nothing of "
      "A's drawn, the stop recorded once", (tester) async {
    // FAILS on 0a723c3: A's read goes on after its check-ins answer, under
    // B's token (a second `workout_sessions` and `conversations` as B — the
    // latter filtered on A's id).
    await show(tester);
    final lateA = server.holds[key(_checkins, memberA)] = Completer<void>();
    c.invalidate(coachTriageSignalsProvider);
    await frames(tester, 2);
    expect(server.count(key(_checkins, memberA)), 1, reason: "A's read is out");
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    // Each read of B's own asks for check-ins once, then sessions and
    // conversations once each. (The card can be re-subscribed as the roster
    // reloads for B, so B may read more than once.)
    final bReads = server.count(key(_checkins, memberB));
    expect(bReads, greaterThanOrEqualTo(1));
    expect(server.count(key(_sessions, memberB)), bReads, reason: 'premise');
    // Now A's late answer.
    lateA.complete();
    await frames(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await frames(tester);
    nothingOfA("after A's late answer");
    expect(ofB(), findsOneWidget);
    expect(server.count(key(_checkins, memberB)), bReads);
    expect(server.count(key(_sessions, memberB)), bReads,
        reason: "A's read asked nothing more once B was signed in");
    expect(server.count(key(_convos, memberB)), bReads,
        reason: "A's read asked nothing more once B was signed in");
    expect(server.count(key(_sessions, memberA)), 0);
    final stops = reported.where((f) =>
        f.origin == _origin &&
        '${f.error}'.contains('the signed-in account changed'));
    expect(stops.length, 1, reason: "A's stopped read is recorded once");
    await unmount(tester);
  });

  testWidgets(
      "A's read straddles the switch at its LAST step (the drop-off scores): "
      "its answer is no answer — the stop is recorded, nothing of A's drawn",
      (tester) async {
    // FAILS on 0a723c3 on the record only (no stop was recorded; the screen
    // was safe there, Riverpod drops a superseded future's value). Kills "the
    // last step's guard dropped", which hands back A's rows as if the read had
    // finished for A.
    const rpc = 'POST rpc/coach_client_ai_signals';
    await show(tester);
    final lateA = server.holds[key(rpc, memberA)] = Completer<void>();
    c.invalidate(coachTriageSignalsProvider);
    await pumpUntil(tester, () => server.count(key(rpc, memberA)) == 1,
        what: "A's read at its last step");
    await become(tester, memberB);
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    lateA.complete();
    await frames(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await frames(tester);
    nothingOfA("after A's late last answer");
    expect(ofB(), findsOneWidget);
    final stops = reported.where((f) =>
        f.origin == _origin &&
        '${f.error}'.contains('the signed-in account changed'));
    expect(stops.length, 1,
        reason: "A's read that finished after A left is a recorded stop");
    await unmount(tester);
  });

  testWidgets(
      'the auth client already names coach B and nothing has heard yet (no '
      "frame of currentUserProvider): a rebuild draws nothing of A's",
      (tester) async {
    // FAILS on 0a723c3: the rebuild draws A's row.
    await show(tester, holdHeard: true);
    final holdB = server.holds[key(_checkins, memberB)] = Completer<void>();
    await tester.runAsync(() => signInAs(memberB));
    expect(Supabase.instance.client.auth.currentUser?.id, memberB,
        reason: 'premise: the auth client names B');
    expect(c.read(currentUserProvider)?.id, memberA,
        reason: 'premise: nothing has heard of B yet');
    tester.element(find.byType(CoachDashboardScreen)).markNeedsBuild();
    await tester.pump();
    nothingOfA('the auth client is B, the screen still watches A');
    expect(find.text(_failed), findsNothing,
        reason: 'nothing failed: nothing to say');
    expect(server.count(key(_checkins, memberA)), 0,
        reason: 'nothing was asked as A');
    c.read(_heard.notifier).state = Supabase.instance.client.auth.currentUser;
    await frames(tester, 2);
    nothingOfA('B heard, B pending');
    holdB.complete();
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    nothingOfA('B answered');
    expect(server.count(key(_checkins, memberB)), greaterThanOrEqualTo(1));
    await unmount(tester);
  });

  testWidgets(
      "coach A -> sign-out -> coach B: nothing of A's while out, nothing while "
      "B's read is pending, then B's own; A's never asked again",
      (tester) async {
    await show(tester);
    await become(tester, null);
    await frames(tester);
    nothingOfA('signed out');
    expect(find.text(_failed), findsNothing,
        reason: 'signed out is not a failure to say');
    final holdB = server.holds[key(_checkins, memberB)] = Completer<void>();
    await become(tester, memberB);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      nothingOfA('B signed in, B pending, frame $i');
    }
    holdB.complete();
    await pumpUntil(tester, () => seen(ofB()), what: "B's own row");
    nothingOfA('B answered');
    expect(server.count(key(_checkins, memberB)), greaterThanOrEqualTo(1));
    expect(server.count(key(_checkins, memberA)), 0,
        reason: 'nothing was asked as A after A left');
    await unmount(tester);
  });

  testWidgets(
      "the same coach's own refresh fails: the failure is said (as before), "
      'recorded once', (tester) async {
    await show(tester);
    server.fails.add(key(_checkins, memberA));
    c.invalidate(coachTriageSignalsProvider);
    await pumpUntil(tester, () => seen(find.text(_failed)),
        what: "A's own failure said", timeout: const Duration(seconds: 10));
    expect(find.text('Nothing needs you right now.'), findsNothing);
    expect(reported.where((f) => f.origin == _origin).length, 1);
    expect(server.count(key(_checkins, memberA)), 1);
    expect(server.count(key(_checkins, memberB)), 0);
    await unmount(tester);
  });

  testWidgets(
      'CONTROL: a reload for the same coach keeps the row up throughout and '
      'reads once more, as A', (tester) async {
    await show(tester);
    final hold = server.holds[key(_checkins, memberA)] = Completer<void>();
    c.invalidate(coachTriageSignalsProvider);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(ofA(), findsOneWidget,
          reason: "A's own row stays while A's reload is in flight ($i)");
    }
    expect(server.count(key(_checkins, memberA)), 1, reason: 'one reload');
    hold.complete();
    await frames(tester);
    expect(ofA(), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    expect(server.count(key(_checkins, memberB)), 0);
    expect(reported.where((f) => f.origin == _origin), isEmpty,
        reason: 'the same coach is never "stopped"');
    await unmount(tester);
  });

  testWidgets('CONTROL: a refreshed token keeps the row and reads nothing again',
      (tester) async {
    await show(tester);
    final before = c.read(currentUserProvider);
    await tester.runAsync(refreshSession);
    await pumpUntil(tester, () => c.read(currentUserProvider) != before,
        what: 'the same coach as a new User');
    expect(c.read(currentUserProvider)?.id, memberA);
    await frames(tester);
    expect(ofA(), findsOneWidget);
    expect(server.count(key(_checkins, memberA)), 0);
    await unmount(tester);
  });

  testWidgets(
      "CONTROL: sign-out -> the same coach back in: nothing while out, then "
      "A's own row again", (tester) async {
    await show(tester);
    await become(tester, null);
    await frames(tester);
    expect(ofA(), findsNothing, reason: "nothing of A's while signed out");
    await become(tester, memberA);
    await pumpUntil(tester, () => seen(ofA()), what: "A's row again");
    expect(server.count(key(_checkins, memberA)), greaterThanOrEqualTo(1));
    expect(server.count(key(_checkins, memberB)), 0);
    await unmount(tester);
  });
}
