import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/identity/account_scope.dart';
import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/router/app_router.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/payments/domain/entitlements.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/resume_workout_banner.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/rest_timer_widget.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/set_tracker_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/account_app.dart';
import '../support/workout_members_server.dart';

// P0-FL-62d · an account switch while a workout is OPEN.
//
// FL-59a's AccountScope throws away the provider container and the router
// when the account that owned them leaves; FL-59b made the live workout, its
// sets, rest, session store and finish carry their member. Each was proven
// alone. Nothing proved the two together: AccountScope tearing a container
// down UNDER an open Workout Zone, with a set's save debounce pending, a rest
// counting down, a session row open and the Zone on the real router.
//
// The REAL app root (CircleFitnessRoot: AccountScope, the real routerProvider,
// the real shell, the real ActiveWorkoutScreen), the real auth client switching
// accounts, and a fake backend that records every request: auth and
// `user_profiles` as AccountServer answers them (FL-59a's harness), every other
// REST table as WorkoutMembersServer does (FL-59b's harness — RLS by the
// bearer's uid, an insert checked on `user_id` alone, 204 to a write that asks
// for no rows).
//
// HOW TO SEE IT FAIL: `git checkout a446926 --
// lib/features/workout/presentation/active_workout_screen.dart`. Two defects:
//  * a set row flushes its pending save from its own dispose; when the owner
//    check passed (End Workout inside the debounce; A -> B -> A, torn down
//    while A is current again) the flush read `ref` on the deactivated Zone
//    and threw mid-teardown ("Looking up a deactivated widget's ancestor");
//  * an edit arriving after Finish/End (the focused field's blur when the
//    finish dialog takes focus, a row's flush) opened a NEW in-progress
//    session for the finished workout and wrote the set into it.
// The A -> B and sign-out tests pass on a446926 (FL-59b already holds there);
// each names, above it, the hand-applied mutation it fails under.

final _workout = WorkoutService().getSampleWorkouts().first;

class _Backend extends http.BaseClient {
  final account = AccountServer();
  final workout = WorkoutMembersServer();

  /// Every request, in order, as `(who, method, name, query, body)`.
  final sent = <Sent>[];

  void reset() {
    account.reset();
    workout.reset();
    sent.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent.add(Sent(AccountServer.who(request), request.method, request.url,
        request is http.Request ? request.body : ''));
    final rest = request.url.path.startsWith('/rest/v1/');
    final name = request.url.path.split('/').last;
    return rest && name != 'user_profiles'
        ? workout.send(request)
        : account.send(request);
  }

  /// Writes (not GET, not auth) from index [from] on.
  List<Sent> writesSince(int from, {String? by}) => [
        for (final s in sent.skip(from))
          if (s.method != 'GET' &&
              !s.url.path.startsWith('/auth/') &&
              (by == null || s.who == by))
            s
      ];
}

const _workoutTables = {
  'workout_sessions',
  'workout_set_logs',
  'workout_logs',
  'penalize_points',
  'award_points',
  'daily_scores',
  'workout_feedback',
};

final _backend = _Backend();
final _realtime = FakeRealtime();
final _store = MemoryStore();
final _failures = <AppFailure>[];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // AccountServer's helper, over the combined backend.
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      httpClient: _backend,
      realtimeClientOptions: RealtimeClientOptions(transport: _realtime.connect),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _store,
        detectSessionInUri: false,
        autoRefreshToken: true,
      ),
      debug: false,
    );
    Supabase.instance.client.auth.stopAutoRefresh();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    passwordRecoveryNotifier.value = null;
    accountReadFailureNotifier.value = null;
    _backend.reset();
    _failures.clear();
    setFailureSink(_failures.add);
    addTearDown(resetFailureSink);
    _backend.account.rows['user_profiles:$acctA'] = [
      {'id': acctA, 'role': 'client', 'onboarding_complete': true, 'first_name': 'Alba'}
    ];
    _backend.account.rows['user_profiles:$acctB'] = [
      {'id': acctB, 'role': 'client', 'onboarding_complete': true, 'first_name': 'Bruno'}
    ];
  });

  ProviderContainer container(WidgetTester t) => appContainer(t);
  Future<void> settle(WidgetTester t, [int frames = 12]) => settleApp(t, frames);

  Future<void> mount(WidgetTester t) => mountApp(t, as: acctA, at: '/home', overrides: [
        clientPlanProvider.overrideWith((ref) async => ClientPlan.coachGuided),
        memberPrefersMetricProvider.overrideWithValue(true),
      ]);

  void appTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        try {
          await body(t);
          expect(t.takeException(), isNull,
              reason: 'nothing may throw while the Zone is torn down');
        } finally {
          await unmountApp(t, _backend.account);
        }
      });

  Finder logSet() => find.bySemanticsLabel('Log set');

  /// The weight field of the [i]th set row on screen.
  Finder weightOf(int i) => find
      .descendant(of: find.byType(SetTrackerRow).at(i), matching: find.byType(TextField))
      .first;

  final set2 = _workout.exercises.first.sets[1];

  /// A opens the Zone on the REAL router, warms up, logs set 1 (a session row is
  /// open, set 1 filed, the real rest starts), then types a weight into set 2 —
  /// its 600 ms save debounce pending — and a rest is due to run over in 400 ms
  /// of wall clock. Returns A's session id.
  Future<String> aMidWorkout(WidgetTester t) async {
    await mount(t);
    container(t).read(selectedWorkoutProvider.notifier).state = _workout;
    appRouter(t).go('/active-workout');
    await settle(t);
    expect(appPath(t), '/active-workout');
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
    expect(find.text(_workout.title), findsOneWidget, reason: 'premise: the Zone is open');
    final sessions = _backend.workout.sessions;
    expect(sessions.map((s) => s['user_id']), [acctA], reason: "premise: A's session is open");

    await t.tap(logSet().first);
    await settle(t, 4);
    expect(_backend.workout.setLogs.map((r) => (r['user_id'], r['completed'])),
        [(acctA, true)],
        reason: 'premise: set 1 filed as A');
    expect(container(t).read(restTimerProvider), isNotNull,
        reason: "premise: the real rest is running");
    expect(find.byType(RestTimerWidget), findsOneWidget);

    await t.enterText(weightOf(1), '77');
    await t.pump(const Duration(milliseconds: 100));
    // Focusing a weight dismisses the rest (the member is starting the next
    // set): run one that overruns in 400 ms of wall clock, as a member who sat
    // down again would have.
    container(t).read(restTimerProvider.notifier).state =
        RestTimerState(DateTime.now().add(const Duration(milliseconds: 400)), 90);
    await t.pump();
    expect(find.byType(RestTimerWidget), findsOneWidget);
    expect(_backend.workout.setLogs.where((r) => r['set_id'] == set2.id), isEmpty,
        reason: "premise: set 2's save is still pending");
    return sessions.single['id'] as String;
  }

  /// [change] happens, then 600 ms of wall clock pass with NO frame (A's rest
  /// runs over meanwhile), then the rest's own 250 ms tick and the frame that
  /// tears the generation down, and the next generation settles.
  Future<void> switchUnderTheZone(WidgetTester t, Future<void> Function() change) async {
    await t.runAsync(() async {
      await change();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pump(const Duration(milliseconds: 300));
    await settle(t, 20);
  }

  /// Nothing of A's workout reached the server once A had left, under anyone.
  void expectNothingSentAfter(int mark, String sid) {
    final after = _backend.writesSince(mark);
    expect(
        [for (final w in after) if (w.who != 'anon' && _workoutTables.contains(w.name)) '$w'],
        isEmpty,
        reason: "a workout write after A left: A's debounce, clock, rest or finish");
    expect([for (final w in after) if (w.body.contains(sid) || w.url.query.contains(sid)) '$w'],
        isEmpty,
        reason: "A's session id in a write after the switch");
    expect([for (final w in after) if (w.body.contains('77')) '$w'], isEmpty,
        reason: "A's typed set 2 was sent after the switch");
    expect(_backend.workout.setLogs.where((r) => r['set_id'] == set2.id), isEmpty,
        reason: "A's pending set 2 must be sent before the switch or not at all");
    expect(_backend.workout.setLogs.map((r) => r['user_id']), everyElement(acctA));
    expect(_backend.workout.sessions.map((r) => r['user_id']), everyElement(acctA),
        reason: "a session row was opened for B from A's workout");
    expect(_backend.workout.sessions.single['status'], 'in_progress',
        reason: 'A can still resume $sid');
    expect(_backend.workout.sessions.single['idle_seconds'], isNull,
        reason: "A's rest overrun was filed after A left");
    expect(_backend.writesSince(mark).where((w) => w.name == 'penalize_points'), isEmpty,
        reason: "−5 for A's rest, charged after A left");
  }

  /// B's app holds nothing of A's workout, on any screen B can reach.
  Future<void> expectBHasNothingOfA(WidgetTester t) async {
    expect(find.text(_workout.title, skipOffstage: false), findsNothing);
    expect(find.byType(ActiveWorkoutScreen, skipOffstage: false), findsNothing);
    expect(find.byType(RestTimerWidget, skipOffstage: false), findsNothing);
    expect(find.textContaining('−5 points', skipOffstage: false), findsNothing);
    expect(find.text('77', skipOffstage: false), findsNothing);
    final c = container(t);
    expect(c.read(currentUserProvider)?.id, acctB);
    expect(c.read(selectedWorkoutProvider), isNull);
    expect(c.read(activeWorkoutProvider), isEmpty);
    expect(c.read(restTimerProvider), isNull);
    // B's home: no Resume for A's session.
    expect(appPath(t), '/home');
    expect(find.byType(ResumeWorkoutBanner), findsOneWidget, reason: "premise: B's home");
    expect(find.text('Resume Workout?'), findsNothing,
        reason: "B's home offers A's unfinished workout");
    // B's Zone: nothing to resume.
    appRouter(t).go('/active-workout');
    await settle(t);
    expect(find.text('No workout selected'), findsOneWidget);
    expect(find.text(_workout.title), findsNothing);
    expect(find.text('Resume'), findsNothing);
  }

  void expectChangeRecorded() => expect(
      _failures.map((f) => '${f.error}'),
      contains(contains('the signed-in account changed')),
      reason: "A's refused save is recorded, not silent");

  // MUTATION: `return true;` at the top of _ActiveWorkoutViewState._isOwner
  // (active_workout_screen.dart) -> A's rest overrun charges B (penalize_points
  // by B) and the change is no longer recorded.
  // MUTATION: AccountScope._follow returns before setState -> the old Zone stays
  // mounted on the old router: A's workout title / path '/active-workout'.
  appTest('A -> B with a debounce pending and a rest running: nothing of A is '
      'sent, charged, shown or resumable for B', (t) async {
    final sid = await aMidWorkout(t);
    final old = container(t);
    final mark = _backend.sent.length;

    await switchUnderTheZone(t, () => signInAs(acctB));

    expect(container(t), isNot(same(old)), reason: 'premise: a new generation');
    expect(() => old.read(restTimerProvider), throwsStateError,
        reason: 'the old container is disposed');
    expectNothingSentAfter(mark, sid);
    expectChangeRecorded();
    await expectBHasNothingOfA(t);
    // And the rest's ticker is gone with its container: more time, no charge.
    await t.pump(const Duration(seconds: 30));
    await settle(t, 4);
    expectNothingSentAfter(mark, sid);
    expect(_backend.writesSince(mark, by: acctB).where((w) => _workoutTables.contains(w.name)),
        isEmpty);
  });

  // MUTATION: as above (`_isOwner` always true): A's rest, run over while
  // signed out, is charged to nobody but recorded nowhere; on B's sign-in
  // nothing changes — fails on the recorded change and on penalize_points.
  appTest('A -> signed out -> B: nothing of A is sent, shown or resumable',
      (t) async {
    final sid = await aMidWorkout(t);
    final mark = _backend.sent.length;

    await switchUnderTheZone(t, signOut);
    expect(appPath(t), '/login');
    expect(find.text(_workout.title, skipOffstage: false), findsNothing);
    expect(find.byType(RestTimerWidget, skipOffstage: false), findsNothing);
    final signedOutGen = container(t);

    await t.runAsync(() => signInAs(acctB));
    await settle(t, 20);
    expect(container(t), same(signedOutGen), reason: 'a sign-in, not a switch');
    expectNothingSentAfter(mark, sid);
    expectChangeRecorded();
    await expectBHasNothingOfA(t);
  });

  // MUTATION: `ref.watch(restoringUserIdProvider)` replaced by
  // `ref.watch(currentUserProvider)` in restTimerProvider / activeWorkoutProvider
  // (workout_provider.dart) -> the same-uid refresh drops the rest / the sets.
  appTest('control: a same-uid token refresh mid-workout keeps sets, rest and '
      'session; the finish files once, as A', (t) async {
    final sid = await aMidWorkout(t);
    final c = container(t);
    final rest = c.read(restTimerProvider);
    final sets = Map.of(c.read(activeWorkoutProvider));
    final restView = t.state(find.byType(RestTimerWidget));

    await t.runAsync(renewToken);
    await settle(t, 2);

    expect(container(t), same(c), reason: 'a token refresh never remounts');
    expect(c.read(restTimerProvider), same(rest));
    expect(c.read(activeWorkoutProvider).keys, containsAll(sets.keys));
    expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
    expect(t.state(find.byType(RestTimerWidget)), same(restView));
    expect(find.text('77'), findsOneWidget, reason: 'the typed set 2 survives');
    // A's debounce lands, as A, on A's session; A's own rest overrun costs A.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 700));
    await settle(t, 4);
    final s2 = _backend.workout.setLogs.where((r) => r['set_id'] == set2.id).toList();
    expect(s2.map((r) => (r['user_id'], r['session_id'], r['weight_kg'])),
        [(acctA, sid, 77)]);
    expect(_backend.workout.asked
            .where((a) => a.table == 'penalize_points')
            .map((a) => a.who),
        [acctA]);

    await t.tap(find.textContaining('Finish Early'));
    await settle(t);
    expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
    final logs = _backend.workout.writes(to: 'workout_logs');
    expect(logs.map((w) => w.who), [acctA]);
    expect(jsonDecode(logs.single.body)['user_id'], acctA);
    expect(_backend.workout.sessions.map((s) => (s['id'], s['status'])), [(sid, 'completed')]);
    expect(_backend.workout.writes(to: 'award_points').map((w) => (w.who, jsonDecode(w.body)['p_action'])),
        [(acctA, 'workout_start'), (acctA, 'workout_complete')]);
    expect(
        _failures.where((f) => '${f.error}'.contains('the signed-in account changed')),
        isEmpty);
  });

  appTest('control: A finishes with set 2 typed and in focus: filed once, and '
      'no new session is opened for the finished workout', (t) async {
    final sid = await aMidWorkout(t);
    await t.pump(const Duration(milliseconds: 700)); // set 2's debounce lands
    await settle(t, 4);
    expect(_backend.workout.setLogs.where((r) => r['set_id'] == set2.id), hasLength(1),
        reason: 'premise: set 2 saved as typed');
    final mark = _backend.sent.length;

    await t.tap(find.textContaining('Finish Early'));
    await settle(t);
    expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
    expect(_backend.workout.writes(to: 'workout_logs').map((w) => w.who), [acctA]);
    expect(_backend.workout.sessions.map((s) => (s['id'], s['status'])), [(sid, 'completed')],
        reason: 'THE defect: the finished workout was opened again as a new session');
    expect(
        _backend.writesSince(mark).where((w) => w.name == 'workout_set_logs').map((w) => '$w'),
        isEmpty,
        reason: "THE defect: set 2's blur re-saved it after the finish");
    await t.tap(find.text('Skip'));
    await settle(t);
    expect(appPath(t), '/home');
    expect(find.text('Resume Workout?'), findsNothing,
        reason: 'a finished workout offered for resume');
    expect(_backend.workout.sessions, hasLength(1));
  });

  appTest('control: A ends the workout with set 2 typed and pending: no new '
      'session is opened for the ended workout', (t) async {
    final sid = await aMidWorkout(t);
    await t.tap(find.bySemanticsLabel('End session'));
    await settle(t, 2);
    await t.tap(find.text('End Workout'));
    await settle(t, 20);
    expect(appPath(t), '/home');
    expect(_backend.workout.sessions.map((s) => (s['id'], s['status'])), [(sid, 'abandoned')],
        reason: 'THE defect: the ended workout was opened again as a new session');
    expect(_backend.workout.setLogs.map((r) => r['session_id']), everyElement(sid));
    expect(find.text('Resume Workout?'), findsNothing);
  });

  appTest('control: A leaves the Zone by the tab bar with set 2 pending: the '
      'typed set is saved once, as A, and nothing throws', (t) async {
    final sid = await aMidWorkout(t);
    final mark = _backend.sent.length;
    appRouter(t).go('/home');
    await settle(t, 20);
    expect(appPath(t), '/home');
    final s2 = _backend.workout.setLogs.where((r) => r['set_id'] == set2.id).toList();
    expect(s2.map((r) => (r['user_id'], r['session_id'], r['weight_kg'])), [(acctA, sid, 77)],
        reason: "the row's flush on leaving is the only save of set 2");
    expect(
        _backend.writesSince(mark)
            .where((w) => w.name == 'workout_set_logs' && w.method == 'PATCH'),
        hasLength(1));
    expect(_backend.workout.sessions.map((s) => (s['id'], s['status'])), [(sid, 'in_progress')]);
  });

  // MUTATION: AccountScope keys the generation by currentUser instead of the
  // event's uid (`_follow(auth.currentUser?.id)`): both events arrive when A
  // is current again, nothing remounts, and A's dead Zone stays — fails on the
  // generation number and on the Zone still being on screen.
  appTest('A -> B -> A during the debounce: a clean A generation, the dead '
      "one's state not resurrected, nothing written twice", (t) async {
    final sid = await aMidWorkout(t);
    final old = container(t);
    final mark = _backend.sent.length;
    final startsBefore = _backend.workout.writes(to: 'award_points').length;

    await switchUnderTheZone(t, () async {
      unawaited(signInAs(acctB));
      await signInAs(acctA);
    });

    final now = container(t);
    expect(now, isNot(same(old)));
    expect(now.read(accountGenerationProvider).number, 2);
    expect(now.read(currentUserProvider)?.id, acctA);
    expect(appPath(t), '/home');
    expect(find.text(_workout.title, skipOffstage: false), findsNothing,
        reason: "the dead generation's Zone");
    expect(now.read(restTimerProvider), isNull, reason: "the dead generation's rest");
    expect(now.read(activeWorkoutProvider), isEmpty);
    expect(_backend.writesSince(mark, by: acctB), isEmpty, reason: 'B wrote');

    // Whatever the dead Zone sent as A after the switch (its debounce flush and
    // clock, if A was current again when it was torn down) is A's own, on A's
    // session, and at most once per set.
    final after = _backend.writesSince(mark);
    for (final w in after.where((w) => _workoutTables.contains(w.name))) {
      expect(w.who, acctA, reason: '$w');
    }
    // One save is an update (by session and set) then, finding no row, an insert.
    final set2Saves = after
        .where((w) =>
            w.name == 'workout_set_logs' &&
            w.method == 'PATCH' &&
            w.url.query.contains(set2.id))
        .toList();
    expect(set2Saves.length, lessThanOrEqualTo(1), reason: '$set2Saves');
    expect(
        after.where((w) =>
            w.name == 'workout_set_logs' && w.method == 'POST' && w.body.contains(set2.id)),
        hasLength(lessThanOrEqualTo(1)));
    // A's own rest ran over (wall clock) while A was signed in again: the dead
    // generation may charge A for it once — never B, never twice, and the new
    // generation holds no rest to charge again.
    final charges = after.where((w) => w.name == 'penalize_points').toList();
    expect(charges.map((w) => w.who), everyElement(acctA));
    expect(charges.length, lessThanOrEqualTo(1));
    await t.pump(const Duration(seconds: 45));
    await settle(t, 4);
    expect(_backend.writesSince(mark).where((w) => w.name == 'penalize_points'),
        hasLength(charges.length),
        reason: "the dead generation's rest kept charging A");

    // The new generation of A resumes A's own session from the server: the
    // same row, no new session, nothing abandoned, no second start award.
    appRouter(t).go('/active-workout');
    await settle(t, 20);
    expect(find.text(_workout.title), findsOneWidget);
    expect(_backend.workout.sessions.map((s) => (s['id'], s['status'])),
        [(sid, 'in_progress')]);
    expect(now.read(activeWorkoutProvider.notifier).sessionId, sid);
    expect(now.read(activeWorkoutProvider.notifier).isSetCompleted(
            _workout.exercises.first.sets.first.id),
        isTrue,
        reason: "A's filed set 1, restored from the server");
    expect(_backend.workout.writes(to: 'award_points').length, startsBefore,
        reason: 'a resume is not a start');
    final rows = _backend.workout.setLogs;
    expect(rows.map((r) => '${r['session_id']}/${r['set_id']}').toSet().length,
        rows.length,
        reason: 'one row per set');
    expect(rows.map((r) => r['user_id']), everyElement(acctA));
  });
}
