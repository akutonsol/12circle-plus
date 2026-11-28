import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, refreshSession, signInAs;
import '../support/workout_members_server.dart';

// RM-3 · workout data integrity (blocker register C14-62d-02, C14-62d-03).
//
// C14-62d-02. A set confirmed while the session was still being opened (a
// slow or failed start) was saved to the server once, but
// `ActiveWorkoutNotifier.beginSession` then cleared every set held in memory
// as the late session bound: the Zone showed the confirmed set as outstanding
// again (FL-62d only patched the Finish count). The held sets now survive the
// bind and belong to the session that bound, saved once.
//
// C14-62d-03 (integrity half). Android back dismisses the "workout complete"
// dialog without running its Done/Skip, so the Zone stays on the filed
// workout. A SECOND Finish there sent `daily_scores` and `award_points` again
// (the server's dedup key and the daily upsert happened to absorb them — the
// client must not rely on that); leaving and coming back opened a NEW session
// for the filed workout and filed a SECOND `workout_logs` row. A filed workout
// is now filed and awarded once. What back itself should do (block, or leave
// the Zone) is the owner's decision and is not changed here.
//
// The real screen, the real auth client and the real services; only the
// network is faked (WorkoutMembersServer: RLS by the bearer, 204 to a write
// that asks for no rows, 23505 on a second set log for one set). No
// AccountScope: the Zone stays mounted across a switch.
//
// HOW TO SEE IT FAIL: `git checkout 6d1611d --
// lib/features/workout/domain/workout_provider.dart
// lib/features/workout/presentation/active_workout_screen.dart`.

final _workout = WorkoutService().getSampleWorkouts().first; // Full Body Strength
final _set1 = _workout.exercises.first.sets.first;
final _totalSets = _workout.exercises.fold<int>(0, (n, e) => n + e.sets.length);

void main() {
  late WorkoutMembersServer server;
  late ProviderContainer c;
  late GoRouter router;
  late List<AppFailure> failures;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = WorkoutMembersServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    failures = [];
    setFailureSink(failures.add);
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      memberPrefersMetricProvider.overrideWithValue(true),
    ]);
    c.listen(restoringUserIdProvider, (_, __) {});
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> settle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester t) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2600);
    addTearDown(t.view.reset);
    router = GoRouter(initialLocation: '/active-workout', routes: [
      ShellRoute(builder: (_, __, child) => Scaffold(body: child), routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('home screen')),
        GoRoute(path: '/active-workout', builder: (_, __) => const ActiveWorkoutScreen()),
      ]),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  /// Set-log INSERTs (a save is an update first, then an insert when the
  /// update matched no row), and any refused as a duplicate (23505).
  List<Asked> setLogInserts() =>
      [for (final w in server.writes(to: 'workout_set_logs')) if (w.method == 'POST') w];

  Finder logSet() => find.bySemanticsLabel('Log set');
  Finder finish() => find.textContaining('Finish Early');

  List<Map<String, Object?>> logsOf(String setId) =>
      [for (final r in server.setLogs) if (r['set_id'] == setId) r];

  /// A opens the Zone with the session insert HELD: the start is slow.
  Future<Completer<void>> aOpensWithStartHeld(WidgetTester t) async {
    final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
    c.read(selectedWorkoutProvider.notifier).state = _workout;
    await mount(t);
    expect(find.text(_workout.title), findsOneWidget, reason: 'premise: the Zone is open');
    expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull,
        reason: 'premise: no session is bound yet');
    return hold;
  }

  /// A confirms set 1 while the session is still opening.
  Future<void> aConfirmsSet1(WidgetTester t) async {
    await t.tap(logSet().first);
    await settle(t, 3);
    expect(c.read(activeWorkoutProvider)[_set1.id]?['completed'], true,
        reason: 'premise: set 1 is confirmed in memory');
    expect(server.setLogs, isEmpty, reason: 'premise: its save waits on the session');
  }

  Future<void> warmUp(WidgetTester t) async {
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
  }

  group('C14-62d-02 · sets confirmed before the session binds', () {
    testWidgets('survive the late bind, and are saved once to the bound session', (t) async {
      final hold = await aOpensWithStartHeld(t);
      await aConfirmsSet1(t);

      hold.complete();
      await settle(t);

      final sid = server.sessions.single['id'];
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(c.read(activeWorkoutProvider)[_set1.id]?['completed'], true,
          reason: 'THE defect: binding the late session cleared the confirmed set');
      expect(find.textContaining('Finish Early (1/$_totalSets sets)'), findsOneWidget,
          reason: 'THE defect: the Zone showed the confirmed set as outstanding');
      expect(logsOf(_set1.id).map((r) => (r['session_id'], r['user_id'], r['completed'])),
          [(sid, memberA, true)],
          reason: 'one row, for the bound session, as A');
      expect(setLogInserts(), hasLength(1),
          reason: 'saved exactly once (no duplicate, no 23505)');

      // And it is what Finish counts and files.
      await warmUp(t);
      await t.tap(finish());
      await settle(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      expect(t.widget<WorkoutCompleteDialog>(find.byType(WorkoutCompleteDialog)).setsLogged, 1);
      expect(server.writes(to: 'workout_logs'), hasLength(1));
      expect(setLogInserts(), hasLength(1));
      expect(failures, isEmpty);
      await close(t);
    });

    testWidgets('control: token refresh while the start is held keeps the set', (t) async {
      final hold = await aOpensWithStartHeld(t);
      await aConfirmsSet1(t);
      await t.runAsync(refreshSession);
      await settle(t, 3);
      expect(Supabase.instance.client.auth.currentUser?.id, memberA);

      hold.complete();
      await settle(t);
      expect(c.read(activeWorkoutProvider)[_set1.id]?['completed'], true,
          reason: 'a same-member token refresh must not wipe the held set');
      expect(logsOf(_set1.id), hasLength(1));
      expect(failures, isEmpty);
      await close(t);
    });

    testWidgets('A -> B while the start is held: nothing of A\'s reaches B', (t) async {
      // An owner-rule control (passes on the base too): the bind checks the
      // owner, so adopting held sets never carries them to another member.
      final hold = await aOpensWithStartHeld(t);
      await aConfirmsSet1(t);
      await t.runAsync(() async {
        await signInAs(memberB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await pumpUntil(t, () => c.read(restoringUserIdProvider) == memberB, what: 'the switch');
      hold.complete();
      await settle(t);
      expect(server.writes(by: memberB), isEmpty);
      expect(server.setLogs, isEmpty, reason: "A's set is not filed once A has left");
      expect(c.read(activeWorkoutProvider), isEmpty, reason: "B holds none of A's sets");
      expect(find.text(_workout.title), findsNothing);
      expect(failures.map((f) => f.error.toString()),
          contains(contains('the signed-in account changed')));
      await close(t);
    });

    testWidgets('control: a session opened on time binds empty and saves each set once',
        (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _workout;
      await mount(t);
      await warmUp(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      expect(c.read(activeWorkoutProvider)[_set1.id]?['completed'], true);
      expect(logsOf(_set1.id), hasLength(1));
      await close(t);
    });
  });

  group('C14-62d-03 · a filed workout is filed and awarded once', () {
    /// A trains, logs set 1, presses Finish, then dismisses the complete dialog
    /// with the system back button — not Done, not Skip.
    Future<void> aFinishesThenPressesBack(WidgetTester t) async {
      c.read(selectedWorkoutProvider.notifier).state = _workout;
      await mount(t);
      await warmUp(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      await t.tap(finish());
      await settle(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget, reason: 'premise: filed');
      expect(server.writes(to: 'workout_logs'), hasLength(1));
      expect(server.writes(to: 'daily_scores'), hasLength(1));
      expect(
          server.writes(to: 'award_points').where((w) => w.body.contains('workout_complete')),
          hasLength(1));

      await t.binding.handlePopRoute(); // Android back
      await settle(t);
      // The OBSERVATION recorded for the owner (C14-62d-03): back dismisses the
      // dialog and the Zone stays on the filed workout. Not changed here.
      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(find.text(_workout.title), findsOneWidget);
      expect(c.read(selectedWorkoutProvider)?.id, _workout.id);
    }

    void expectFiledOnce() {
      expect(server.writes(to: 'workout_logs'), hasLength(1),
          reason: 'THE defect: the filed workout was filed again');
      expect(server.writes(to: 'daily_scores'), hasLength(1),
          reason: 'THE defect: the workout points were sent again');
      expect(
          server.writes(to: 'award_points').where((w) => w.body.contains('workout_complete')),
          hasLength(1),
          reason: 'THE defect: +25 for the workout was asked for again');
      expect(server.sessions, hasLength(1),
          reason: 'THE defect: a new session was opened for the filed workout');
      expect(server.sessions.single['status'], 'completed');
      expect(server.writes(to: 'workout_sessions').where((w) => w.body.contains('"completed"')),
          hasLength(1));
    }

    testWidgets('a second Finish after back files and awards nothing', (t) async {
      await aFinishesThenPressesBack(t);
      final before = server.asked.length;
      await t.tap(finish());
      await settle(t);
      expectFiledOnce();
      expect(server.asked.skip(before).where((a) => a.method != 'GET'), isEmpty,
          reason: 'THE defect: a second Finish sent writes');
      expect(find.byType(WorkoutCompleteDialog), findsNothing,
          reason: 'THE defect: the workout was celebrated a second time');
      await close(t);
    });

    testWidgets('leaving after back and returning does not start or file it again', (t) async {
      await aFinishesThenPressesBack(t);
      router.go('/home');
      await settle(t);
      router.go('/active-workout');
      await settle(t);
      expect(find.textContaining('Warmed Up'), findsNothing,
          reason: 'THE defect: the filed workout was started again');
      await t.tap(finish());
      await settle(t);
      expectFiledOnce();
      expect(
          server.writes(to: 'award_points').where((w) => w.body.contains('workout_start')),
          hasLength(1),
          reason: 'THE defect: +5 start for the filed workout, again');
      await close(t);
    });

    testWidgets('control: Finish then Skip files once, awards once, and clears', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _workout;
      await mount(t);
      await warmUp(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      await t.tap(finish());
      await settle(t);
      await t.tap(find.text('Skip'));
      await settle(t);
      expectFiledOnce();
      expect(jsonDecode(server.writes(to: 'workout_logs').single.body)['user_id'], memberA);
      expect(c.read(selectedWorkoutProvider), isNull);
      expect(find.text('home screen'), findsOneWidget);

      // Coming back to the Zone: nothing is resumed or started.
      router.go('/active-workout');
      await settle(t);
      expect(find.text('No workout selected'), findsOneWidget);
      expect(server.sessions, hasLength(1));
      await close(t);
    });

    testWidgets('control: the same workout picked again after Skip starts afresh', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _workout;
      await mount(t);
      await warmUp(t);
      await t.tap(finish());
      await settle(t);
      await t.tap(find.text('Skip'));
      await settle(t);

      // The same Workout instance (sample workouts are one cached list).
      c.read(selectedWorkoutProvider.notifier).state = _workout;
      router.go('/active-workout');
      await settle(t);
      expect(server.sessions, hasLength(2), reason: 'a new workout gets its own session');
      await warmUp(t);
      await t.tap(finish());
      await settle(t);
      expect(server.writes(to: 'workout_logs'), hasLength(2),
          reason: 'a second, separately started workout is filed');
      await close(t);
    });

    testWidgets('control: token refresh after filing changes nothing', (t) async {
      await aFinishesThenPressesBack(t);
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(finish());
      await settle(t);
      expectFiledOnce();
      expect(find.text(_workout.title), findsOneWidget);
      await close(t);
    });

    testWidgets('A -> B after back: B\'s Finish on the stale Zone sends nothing', (t) async {
      await aFinishesThenPressesBack(t);
      await t.runAsync(() async {
        await signInAs(memberB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await pumpUntil(t, () => c.read(restoringUserIdProvider) == memberB, what: 'the switch');
      await settle(t);
      expect(find.text(_workout.title), findsNothing);
      expect(server.writes(by: memberB), isEmpty);
      expectFiledOnce();
      await close(t);
    });
  });
}
