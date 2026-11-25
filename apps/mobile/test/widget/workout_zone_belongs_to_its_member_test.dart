import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_save.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/rest_timer_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, refreshSession, signInAs, signOut;
import '../support/workout_members_server.dart';

// P0-FL-59b · the live workout belongs to the member who started it.
//
// The Workout Zone kept a member's workout, sets, rest and clock in app-wide
// state and stamped each write with whoever was signed in when it was SENT. On
// a real account change under a mounted Zone (a web tab another tab signs into;
// a screen left by navigation), B's taps and A's own debounces and timers filed
// A's workout as B's: set logs, workout_logs, points and −5 penalties — and a
// completion that matched no row counted as done.
//
// The real screen over the real auth client and the real services; only the
// network is faked, with the live policies' acceptance (an insert is checked on
// `user_id` alone). No AccountScope: the Zone stays mounted across the switch.
// `switchUnseen` is a switch no frame follows — a hidden tab.
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` the lib/features/workout files.

final _aWorkout = WorkoutService().getSampleWorkouts().first; // 'Full Body Strength'
final _bWorkout = WorkoutService().getSampleWorkouts()[1]; // 'Glute and Hamstring Focus'
Map<String, Object?> _snap(Workout w) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(workoutToSnapshot(w))) as Map);

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

  Future<void> mount(WidgetTester t, {String at = '/active-workout'}) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2600);
    addTearDown(t.view.reset);
    router = GoRouter(initialLocation: at, routes: [
      ShellRoute(builder: (_, __, child) => Scaffold(body: child), routes: [
        GoRoute(path: '/home', builder: (_, __) => const Text('home screen')),
        GoRoute(path: '/train', builder: (_, __) => const Text('train screen')),
        GoRoute(path: '/active-workout', builder: (_, __) => const ActiveWorkoutScreen()),
      ]),
    ]);
    addTearDown(router.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle(t);
  }

  /// A is in the Zone, warmed up, with a session open.
  Future<String> aTrains(WidgetTester t, {bool sessionOpens = true}) async {
    c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
    await mount(t);
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
    expect(find.text(_aWorkout.title), findsOneWidget);
    if (!sessionOpens) return '';
    final mine = server.sessions.where((r) => r['user_id'] == memberA);
    expect(mine, hasLength(1), reason: "premise: A's session is open");
    return mine.single['id'] as String;
  }

  Finder logSet() => find.bySemanticsLabel('Log set');

  /// The account changes and NO frame follows.
  Future<void> switchUnseen(WidgetTester t, [String to = memberB]) async {
    await t.runAsync(() async {
      await signInAs(to);
      // Let the event reach Riverpod (its subscription is outside the test's
      // fake clock), as it always does before a real frame.
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    expect(Supabase.instance.client.auth.currentUser?.id, to);
  }

  Future<void> switchTo(WidgetTester t, String to) async {
    await switchUnseen(t, to);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == to, what: 'the switch');
    await settle(t);
  }

  Future<void> signOutSeen(WidgetTester t) async {
    await t.runAsync(signOut);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == null, what: 'the sign-out');
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  void expectNoWritesByB() => expect(
      [for (final w in server.writes(by: memberB)) '${w.method} ${w.table} ${w.query} ${w.body}'],
      isEmpty,
      reason: "THE defect: A's workout was written as B's");

  void expectRecorded() => expect(
      failures.map((f) => f.error.toString()),
      contains(contains('the signed-in account changed')));

  group('the Zone does not show A\'s workout to B', () {
    testWidgets('A -> B: B has no workout, A\'s sets and rest are gone', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      expect(c.read(activeWorkoutProvider), isNotEmpty);
      expect(c.read(restTimerProvider), isNotNull);
      final before = server.asked.length;

      await switchTo(t, memberB);

      expect(find.text(_aWorkout.title), findsNothing,
          reason: "THE defect: A's workout on B's screen");
      expect(find.text('No workout selected'), findsOneWidget);
      expect(c.read(selectedWorkoutProvider), isNull);
      expect(c.read(activeWorkoutProvider), isEmpty);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull);
      expect(c.read(restTimerProvider), isNull);
      expect(server.asked.skip(before).where((a) => a.method != 'GET'), isEmpty);
      expect(server.sessions.single['status'], 'in_progress', reason: 'A can resume $sid');
      await close(t);
    });

    testWidgets('A -> B: B\'s own unfinished workout is the one restored', (t) async {
      server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout));
      await aTrains(t);
      await switchTo(t, memberB);
      expect(find.text(_bWorkout.title), findsOneWidget);
      expect(find.text(_aWorkout.title), findsNothing);
      expect(c.read(selectedWorkoutProvider)?.title, _bWorkout.title);
      expect([for (final s in server.sessions) if (s['user_id'] == memberB) s['status']],
          ['in_progress'],
          reason: "THE defect: A's workout abandoned B's own open session");
      expect(server.writes(by: memberB, to: 'workout_sessions'), isEmpty);
      await close(t);
    });

    testWidgets('B\'s restore pending shows no A; failed shows recovery, no A', (t) async {
      await aTrains(t);
      final hold = server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      server.fails.add('GET workout_sessions:$memberB');
      await switchTo(t, memberB);
      expect(find.text('Restoring your workout…'), findsOneWidget);
      expect(find.text(_aWorkout.title), findsNothing);
      hold.complete();
      await settle(t);
      expect(find.text("We couldn't restore your workout."), findsOneWidget);
      expect(find.text(_aWorkout.title), findsNothing);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('sign-out -> sign-in: A left the Zone by nav; B opens it clean', (t) async {
      await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      router.go('/home');
      await settle(t);
      await signOutSeen(t);
      await switchTo(t, memberB);
      router.go('/active-workout');
      await settle(t);
      expect(find.text(_aWorkout.title), findsNothing);
      expect(find.byType(RestTimerWidget), findsNothing,
          reason: "THE defect: A's rest counting down for B");
      expect(find.text('No workout selected'), findsOneWidget);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('signed out: the Zone holds nothing of A', (t) async {
      await aTrains(t);
      await signOutSeen(t);
      expect(find.text(_aWorkout.title), findsNothing);
      expect(c.read(selectedWorkoutProvider), isNull);
      await close(t);
    });

    testWidgets('the open dialogs go with A: the set correction', (t) async {
      await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      await t.tap(find.text('Adjust weight or reps').first);
      await settle(t, 5);
      expect(find.text('Save Correction'), findsOneWidget);
      await switchTo(t, memberB);
      expect(find.text('Save Correction'), findsNothing,
          reason: "THE defect: A's recorded set in a dialog over B's screen");
      await close(t);
    });

    testWidgets('the open sheets go with A: the exercise swap', (t) async {
      await aTrains(t);
      await t.tap(find.byIcon(Icons.swap_horizontal_circle_rounded).first);
      await settle(t, 10);
      expect(find.textContaining('keeps your sets'), findsOneWidget);
      await switchTo(t, memberB);
      expect(find.textContaining('keeps your sets'), findsNothing);
      await close(t);
    });
  });

  group('sets', () {
    testWidgets('B taps a set on A\'s Zone: nothing is sent', (t) async {
      await aTrains(t);
      await switchUnseen(t);
      await t.tap(logSet().first);
      await settle(t);
      expectNoWritesByB();
      expect(server.setLogs, isEmpty);
      expectRecorded();
      await close(t);
    });

    testWidgets('a pending debounce fires after the switch: nothing is sent', (t) async {
      await aTrains(t);
      await t.enterText(find.byType(TextField).first, '77');
      await switchUnseen(t);
      await t.pump(const Duration(milliseconds: 700));
      await settle(t);
      expectNoWritesByB();
      expect(server.setLogs, isEmpty);
      expect(c.read(activeWorkoutProvider), isEmpty,
          reason: "A's typed set was seated in B's workout");
      await close(t);
    });

    testWidgets('a save in flight: the next step is not taken as B', (t) async {
      await aTrains(t);
      final hold = server.holds['PATCH workout_set_logs:$memberA'] = Completer<void>();
      await t.tap(logSet().first);
      await settle(t, 5);
      expect(server.writes(to: 'workout_set_logs'), hasLength(1), reason: 'premise: in flight');
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expectNoWritesByB();
      expect(server.setLogs, isEmpty);
      await close(t);
    });

    testWidgets('no session yet: B\'s tap opens none, and abandons none of B\'s', (t) async {
      server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout));
      server.fails.add('POST workout_sessions:$memberA');
      await aTrains(t, sessionOpens: false);
      expect(server.sessions, hasLength(1), reason: 'premise: A has no session');
      await switchUnseen(t);
      await t.tap(logSet().first);
      await settle(t);
      expect(server.sessions, hasLength(1),
          reason: "THE defect: a session of B's was created from A's workout");
      expect(server.sessions.single['status'], 'in_progress',
          reason: "THE defect: B's own workout was abandoned");
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('starting held until after the switch: no session, no points for B', (t) async {
      final hold = server.holds['GET workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expect(server.sessions, isEmpty);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('a session created just before the switch: no points, no set state for B',
        (t) async {
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(server.sessions, hasLength(1), reason: 'premise: created, not yet answered');
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull,
          reason: "B's sets were bound to A's session");
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('A\'s set, its slot taken by another row, is not called saved', (t) async {
      final sid = await aTrains(t);
      // The row a switched account used to leave behind.
      server.setLogs.add({
        'id': 'stray', 'session_id': sid, 'user_id': memberB,
        'set_id': _aWorkout.exercises.first.sets.first.id,
      });
      await t.tap(logSet().first);
      await settle(t, 5);
      expect(find.textContaining("Couldn't save that set"), findsOneWidget,
          reason: "THE defect: A's set was lost silently");
      await close(t);
    });

    testWidgets('control: a set A logs is saved once, as A\'s', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      expect(server.setLogs, hasLength(1));
      expect(server.setLogs.single['user_id'], memberA);
      expect(server.setLogs.single['session_id'], sid);
      expect(find.textContaining("Couldn't save that set"), findsNothing);
      await close(t);
    });
  });

  group('the clock, the rest and the other controls', () {
    testWidgets('the 30 s checkpoint after the switch sends nothing', (t) async {
      await aTrains(t);
      final elapsed = server.writes(to: 'workout_sessions').length;
      await switchUnseen(t);
      await t.pump(const Duration(seconds: 31));
      await settle(t);
      expectNoWritesByB();
      expect(server.writes(to: 'workout_sessions'), hasLength(elapsed));
      await close(t);
    });

    testWidgets('going to the background after the switch sends nothing', (t) async {
      await aTrains(t);
      await switchUnseen(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump(const Duration(seconds: 1));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // supabase_flutter's own observer starts its token timer on resume.
      Supabase.instance.client.auth.stopAutoRefresh();
      await settle(t);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('A\'s rest runs over after the switch: B is not charged', (t) async {
      await aTrains(t);
      c.read(restTimerProvider.notifier).state =
          RestTimerState(DateTime.now().add(const Duration(milliseconds: 400)), 90);
      await t.pump();
      expect(find.byType(RestTimerWidget), findsOneWidget);
      await switchUnseen(t);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 300)); // the rest's own timer, then a frame
      await settle(t);
      expect(server.writes(to: 'penalize_points'), isEmpty,
          reason: "THE defect: −5 from B for A's rest");
      expect(find.textContaining('−5 points'), findsNothing);
      expect(find.byType(RestTimerWidget), findsNothing);
      await close(t);
    });

    testWidgets('control: A\'s own rest running over still costs A', (t) async {
      await aTrains(t);
      c.read(restTimerProvider.notifier).state =
          RestTimerState(DateTime.now().add(const Duration(milliseconds: 400)), 90);
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 300));
      await settle(t, 3);
      expect(server.writes(to: 'penalize_points').map((w) => w.who), [memberA]);
      await close(t);
    });

    testWidgets('End Workout pressed after the switch ends nothing', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await switchUnseen(t);
      await t.tap(find.text('End Workout'));
      await settle(t);
      expectNoWritesByB();
      expect(server.sessions.single['status'], 'in_progress');
      await close(t);
    });

    testWidgets('A\'s workout ended while switching: B\'s selection is kept', (t) async {
      await aTrains(t);
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 3);
      await switchTo(t, memberB);
      router.go('/home');
      await settle(t);
      c.read(selectedWorkoutProvider.notifier).state = _bWorkout;
      hold.complete();
      await settle(t);
      expect(c.read(selectedWorkoutProvider)?.title, _bWorkout.title,
          reason: "THE defect: A's End cleared B's workout");
      await close(t);
    });

    testWidgets('control: End Workout ends A\'s own session', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t);
      expect(server.sessions.single['status'], 'abandoned');
      expect(find.text('home screen'), findsOneWidget);
      await close(t);
    });

    testWidgets('an End that matched no session is not called ended', (t) async {
      await aTrains(t);
      server.sessions.single['user_id'] = memberB; // RLS: no longer A's to update
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 5);
      expect(find.textContaining("Couldn't end the workout"), findsOneWidget);
      expect(find.text('home screen'), findsNothing);
      await close(t);
    });
  });

  group('finishing', () {
    Finder finish() => find.textContaining('Finish Early');

    testWidgets('B presses Finish on A\'s Zone: nothing is filed or awarded', (t) async {
      await aTrains(t);
      await switchUnseen(t);
      await t.tap(finish());
      await settle(t);
      expectNoWritesByB();
      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(server.sessions.single['status'], 'in_progress');
      await close(t);
    });

    testWidgets('switch while the log is saving: no completion, no points as B', (t) async {
      await aTrains(t);
      final hold = server.holds['POST workout_logs:$memberA'] = Completer<void>();
      await t.tap(finish());
      await settle(t, 3);
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expectNoWritesByB();
      expect(find.byType(WorkoutCompleteDialog), findsNothing,
          reason: "THE defect: A's workout celebrated on B's screen");
      await close(t);
    });

    testWidgets('switch while completing: no points for B, B\'s workout untouched', (t) async {
      await aTrains(t);
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(finish());
      await settle(t, 3);
      await switchTo(t, memberB);
      router.go('/home');
      await settle(t);
      c.read(selectedWorkoutProvider.notifier).state = _bWorkout;
      c.read(activeWorkoutProvider.notifier)
        ..beginSession('b-session')
        ..completeSet(_bWorkout.exercises.first.sets.first, {'reps': 8});
      hold.complete();
      await settle(t);
      expect(server.writes(by: memberB), isEmpty, reason: 'THE defect: points to B');
      expect(server.sessions.single['status'], 'completed', reason: "A's finish had landed");
      expect(c.read(selectedWorkoutProvider)?.title, _bWorkout.title,
          reason: "THE defect: A's finish cleared B's selection");
      expect(c.read(activeWorkoutProvider), isNotEmpty,
          reason: "THE defect: A's finish reset B's sets");
      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      await close(t);
    });

    testWidgets('switch between the two awards: the second is not B\'s', (t) async {
      await aTrains(t);
      final hold = server.holds['POST daily_scores:$memberA'] = Completer<void>();
      await t.tap(finish());
      await settle(t, 5);
      expect(server.writes(to: 'daily_scores'), hasLength(1), reason: 'premise: first award in flight');
      final awards = server.writes(to: 'award_points').length;
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expect(server.writes(to: 'award_points'), hasLength(awards),
          reason: 'THE defect: +25 to B');
      await close(t);
    });

    testWidgets('a completion that matched no session keeps the workout', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      server.sessions.single['user_id'] = memberB;
      final awards = server.writes(to: 'award_points').length;
      await t.tap(finish());
      await settle(t);
      expect(find.text(workoutSaveFailedMessage), findsOneWidget,
          reason: 'THE defect: 0 rows counted as completed');
      expect(find.byType(WorkoutCompleteDialog), findsNothing);
      expect(c.read(activeWorkoutProvider), isNotEmpty, reason: 'the sets are kept');
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(c.read(selectedWorkoutProvider), isNotNull);
      expect(server.writes(to: 'award_points'), hasLength(awards));

      // The retry files the completion, and the log only once.
      server.sessions.single['user_id'] = memberA;
      await t.tap(find.text(workoutSaveRetryLabel));
      await settle(t);
      expect(server.writes(to: 'workout_logs'), hasLength(1));
      expect(server.sessions.single['status'], 'completed');
      await close(t);
    });

    testWidgets('control: A finishes: filed once, as A, with the points', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      await t.tap(finish());
      await settle(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      final logs = server.writes(to: 'workout_logs');
      expect(logs.map((w) => w.who), [memberA]);
      expect(jsonDecode(logs.single.body)['user_id'], memberA);
      expect(server.sessions.single['id'], sid);
      expect(server.sessions.single['status'], 'completed');
      expect(server.writes(to: 'daily_scores').map((w) => w.who), [memberA]);
      expect(server.writes(to: 'award_points').map((w) => jsonDecode(w.body)['p_action']),
          ['workout_start', 'workout_complete']);
      expect(failures, isEmpty);
      await close(t);
    });

    Future<void> rate(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.star_border_rounded).at(3));
      await t.enterText(
          find.descendant(of: find.byType(WorkoutCompleteDialog), matching: find.byType(TextField)),
          'knee felt off');
      await t.pump();
    }

    testWidgets('feedback pressed after the switch is not sent, and goes away', (t) async {
      server.rows['coach_client_relationships:$memberB'] = [{'coach_id': 'coach-of-b'}];
      await aTrains(t);
      await t.tap(finish());
      await settle(t);
      await rate(t);
      await switchUnseen(t);
      await t.tap(find.text('Done'));
      await settle(t);
      expect(server.writes(to: 'workout_feedback'), isEmpty,
          reason: "THE defect: A's feedback filed as B's, for B's coach");
      expect(server.writes(to: 'notifications'), isEmpty);
      expect(find.byType(WorkoutCompleteDialog), findsNothing,
          reason: "A's workout and notes over B's screen");
      expect(find.text('knee felt off'), findsNothing);
      await close(t);
    });

    testWidgets('feedback: switch while the coach is looked up sends nothing', (t) async {
      await aTrains(t);
      await t.tap(finish());
      await settle(t);
      await rate(t);
      final hold = server.holds['GET coach_client_relationships:$memberA'] = Completer<void>();
      await t.tap(find.text('Done'));
      await settle(t, 3);
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expect(server.writes(to: 'workout_feedback'), isEmpty);
      expect(server.writes(to: 'notifications'), isEmpty);
      await close(t);
    });

    testWidgets('feedback: switch while it saves does not notify as B', (t) async {
      server.rows['coach_client_relationships:$memberA'] = [{'coach_id': 'coach-of-a'}];
      await aTrains(t);
      await t.tap(finish());
      await settle(t);
      await rate(t);
      final hold = server.holds['POST workout_feedback:$memberA'] = Completer<void>();
      await t.tap(find.text('Done'));
      await settle(t, 3);
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expect(server.writes(to: 'workout_feedback').map((w) => w.who), [memberA]);
      expect(server.writes(to: 'notifications'), isEmpty);
      await close(t);
    });

    testWidgets('control: A\'s feedback is A\'s, and reaches A\'s coach', (t) async {
      server.rows['coach_client_relationships:$memberA'] = [{'coach_id': 'coach-of-a'}];
      final sid = await aTrains(t);
      await t.tap(finish());
      await settle(t);
      await rate(t);
      await t.tap(find.text('Done'));
      await settle(t);
      expect(find.text('Feedback sent to your coach!'), findsOneWidget);
      final body = jsonDecode(server.writes(to: 'workout_feedback').single.body) as Map;
      expect([body['user_id'], body['session_id'], body['coach_id']],
          [memberA, sid, 'coach-of-a']);
      expect(server.writes(to: 'notifications'), hasLength(1));
      await close(t);
    });

    testWidgets('A\'s finished dialog closed by A\'s Skip: the selection is dropped', (t) async {
      await aTrains(t);
      await t.tap(finish());
      await settle(t);
      await t.tap(find.text('Skip'));
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull);
      expect(find.text('home screen'), findsOneWidget);
      await close(t);
    });
  });

  group('controls: the same member', () {
    testWidgets('a token refresh mid-workout keeps the sets, rest, clock and session', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      // An RPE (focusing weight or reps would dismiss the rest), not yet saved.
      await t.enterText(find.byType(TextField).at(2), '42');
      final rest = c.read(restTimerProvider);
      final sets = c.read(activeWorkoutProvider);
      final view = t.state(find.byType(RestTimerWidget));
      expect(rest, isNotNull);

      await t.runAsync(refreshSession);
      await settle(t, 5);

      expect(c.read(selectedWorkoutProvider)?.title, _aWorkout.title);
      expect(c.read(restTimerProvider), same(rest));
      expect(c.read(activeWorkoutProvider).keys, containsAll(sets.keys));
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(t.state(find.byType(RestTimerWidget)), same(view), reason: 'the view was rebuilt');
      expect(find.text('42'), findsOneWidget, reason: 'the draft was wiped');
      expect(server.sessions, hasLength(1));
      await t.tap(logSet().at(1));
      await settle(t);
      expect(server.setLogs.where((r) => r['completed'] == true), hasLength(2));
      await close(t);
    });

    testWidgets('leaving by nav and returning: same session, rest still counting', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      final rest = c.read(restTimerProvider);
      router.go('/home');
      await settle(t);
      router.go('/active-workout');
      await settle(t);
      expect(c.read(restTimerProvider), same(rest));
      expect(find.byType(RestTimerWidget), findsOneWidget);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1);
      expect(server.sessions, hasLength(1));
      await close(t);
    });

    testWidgets('A signs out and back in: the workout resumes from the server', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      await signOutSeen(t);
      await switchTo(t, memberA);
      await settle(t);
      expect(find.text(_aWorkout.title), findsOneWidget);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1);
      expect(server.sessions, hasLength(1));
      await close(t);
    });
  });

  // ── Round 2 (independent review of 3f17006) ───────────────────────────────

  void expectNothingSaid() {
    expect(find.byType(SnackBar), findsNothing, reason: "A's failure said to B");
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.textContaining('Could not'), findsNothing);
  }

  /// [_aWorkout] again, as a second workout of A's.
  Workout another(String id) => Workout(
      id: id, title: 'Second of A', description: '', estimatedDuration: 20,
      difficulty: 'x', category: 'Strength', exercises: _bWorkout.exercises);

  /// Opens the swap sheet of exercise [at] and answers the substitute on offer.
  Future<String> openSwap(WidgetTester t, [int at = 0]) async {
    server.rows['custom_exercises:$memberA'] = [
      {'name': 'Goblet Squat', 'muscle_group': 'Legs', 'equipment': 'Dumbbell', 'difficulty': 'x'}
    ];
    await t.tap(find.byIcon(Icons.swap_horizontal_circle_rounded).at(at));
    await settle(t, 10);
    return (t.widget<ListTile>(find.byType(ListTile).first).title! as Text).data!;
  }

  group('a rest that keeps running over', () {
    Future<void> overrun(WidgetTester t) async {
      c.read(restTimerProvider.notifier).state =
          RestTimerState(DateTime.now().add(const Duration(milliseconds: 400)), 90);
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump(const Duration(milliseconds: 300));
      await settle(t, 3);
      expect(server.writes(to: 'penalize_points').map((w) => w.who), [memberA],
          reason: 'premise: A is in overtime');
    }

    void tick(WidgetTester t) =>
        t.widget<RestTimerWidget>(find.byType(RestTimerWidget)).onOvertimePenaltyTick!();

    testWidgets('its repeating charge is not B\'s', (t) async {
      await aTrains(t);
      await overrun(t);
      await switchUnseen(t);
      for (var i = 0; i < 8; i++) {
        tick(t);
      }
      await settle(t);
      expect(server.writes(to: 'penalize_points').map((w) => w.who), [memberA],
          reason: "THE defect: A's overtime drained B's points");
      expect(server.writes(by: memberB), isEmpty);
      await close(t);
    });

    testWidgets('control: it keeps costing A, up to the cap', (t) async {
      await aTrains(t);
      await overrun(t);
      for (var i = 0; i < 12; i++) {
        tick(t);
      }
      await settle(t, 3);
      final charged = server.writes(to: 'penalize_points');
      expect(charged.map((w) => w.who).toSet(), {memberA});
      expect(charged, hasLength(8));
      await close(t);
    });
  });

  group('restoring into the Zone', () {
    Map<String, Object?> seedA() {
      final row = server.seedSession(memberA, workoutId: _aWorkout.id, title: _aWorkout.title,
          snapshot: _snap(_aWorkout));
      server.setLogs.add({
        'id': 'log-a', 'session_id': row['id'], 'user_id': memberA,
        'exercise_instance_id': _aWorkout.exercises.first.instanceId,
        'set_id': _aWorkout.exercises.first.sets.first.id,
        'set_number': 1, 'reps': 8, 'weight_kg': 60, 'completed': true,
      });
      return row;
    }

    testWidgets('A\'s logged sets landing after an unseen switch are not seated', (t) async {
      seedA();
      final hold = server.holds['GET workout_set_logs:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(server.asked.map((a) => '${a.table}:${a.who}'), contains('workout_set_logs:$memberA'),
          reason: "premise: A's sets are being read");
      await switchUnseen(t);
      hold.complete();
      await settle(t);
      expect(c.read(activeWorkoutProvider), isEmpty,
          reason: "THE defect: A's sets seated in B's workout");
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('A\'s logged sets failing to load after the switch: nothing is said to B',
        (t) async {
      seedA();
      server.fails.add('GET workout_set_logs:$memberA');
      final hold = server.holds['GET workout_set_logs:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      await switchUnseen(t);
      hold.complete();
      await t.pump(); // the answer, then the first frame since the switch
      expectNothingSaid();
      await settle(t);
      expectNothingSaid();
      await close(t);
    });

    testWidgets('control: A\'s own are seated; and a failure is said to A, honestly', (t) async {
      seedA();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1);
      router.go('/home');
      await settle(t);
      server.fails.add('GET workout_set_logs:$memberA');
      router.go('/active-workout');
      await settle(t, 5);
      expect(find.textContaining("Couldn't restore your logged sets — try again in a moment"),
          findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      await close(t);
    });

    testWidgets('a session created just before an unseen switch is not bound to B\'s sets',
        (t) async {
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(server.sessions, hasLength(1), reason: 'premise: created, not yet answered');
      await switchUnseen(t);
      // Nothing has drawn: the Zone, and its `ref`, are still A's.
      hold.complete();
      await t.pump();
      expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull,
          reason: "THE defect: B's sets were bound to A's session");
      await settle(t);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('re-read before the switch is seen: A\'s answer is not B\'s', (t) async {
      // A provider that watches `currentUserProvider.select` and is invalidated
      // with the change unflushed is REFRESHED by riverpod, keeping A's value.
      // This one reads the uid through a provider of its own and is reloaded;
      // pinned here.
      seedA();
      server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout))['elapsed_seconds'] = 600;
      await mount(t); // a cold start: the restore provider seats A's workout
      expect(find.text(_aWorkout.title), findsOneWidget);
      final hold = server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      await switchUnseen(t);
      c.invalidate(activeWorkoutRestorationProvider);
      await settle(t);
      expect(find.text('Restoring your workout…'), findsOneWidget);
      expect(find.text(_aWorkout.title), findsNothing);
      hold.complete();
      await settle(t);
      expect(find.text(_bWorkout.title), findsOneWidget);
      expect(find.textContaining('10:0'), findsOneWidget,
          reason: "THE defect: B's session was not resumed — its clock restarted at 0");
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('the coach brief, re-read before the switch is seen, is not shown to B',
        (t) async {
      server.rows['ai_insights:$memberA'] = [
        {'title': 'Easy day, A', 'body': 'x', 'data': {'intensity_delta': -20}}
      ];
      server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout));
      await aTrains(t);
      expect(find.textContaining('20%'), findsWidgets, reason: 'premise: shown to A');
      server.holds['GET ai_insights:$memberB'] = Completer<void>();
      await switchUnseen(t);
      c.read(selectedWorkoutProvider.notifier).state = _bWorkout; // the very next frame is B's Zone
      c.invalidate(coachAdjustmentProvider);
      await settle(t);
      expect(find.text(_bWorkout.title), findsOneWidget);
      expect(find.textContaining('20%'), findsNothing,
          reason: "THE defect: A's load guidance applied to B's workout");
      await close(t);
    });

    testWidgets('control: a same-member re-read mid-workout keeps the Zone', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      c.invalidate(activeWorkoutRestorationProvider);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text(_aWorkout.title), findsOneWidget);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1);
      await close(t);
    });
  });

  group('B\'s own workout, on the same mounted Zone', () {
    Future<void> bTrainsAndFinishes(WidgetTester t, String sidB) async {
      expect(find.text(_bWorkout.title), findsOneWidget);
      await t.tap(logSet().first);
      await settle(t, 3);
      expect(c.read(restTimerProvider), isNotNull, reason: "B's rest starts");
      await settle(t);
      await t.tap(find.textContaining('Finish Early'));
      await settle(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      Map sent(String table, [bool Function(Map)? where]) => [
            for (final w in server.writes(by: memberB, to: table))
              if (w.body.isNotEmpty) jsonDecode(w.body) as Map
          ].firstWhere(where ?? (_) => true);
      final set = server.setLogs.singleWhere((r) => r['user_id'] == memberB);
      expect([set['session_id'], set['set_id'], set['completed']],
          [sidB, _bWorkout.exercises.first.sets.first.id, true]);
      final done = sent('workout_sessions', (m) => m['status'] == 'completed');
      expect(done['idle_seconds'], 0, reason: "A's rest overrun booked as B's");
      expect(server.writes(by: memberB, to: 'workout_sessions').last.query, contains(sidB));
      expect(sent('workout_logs')['user_id'], memberB);
      expect(server.writes(to: 'daily_scores').map((w) => w.who), [memberB]);
      expect([
        for (final w in server.writes(by: memberB, to: 'award_points'))
          (jsonDecode(w.body) as Map)['p_action']
      ], contains('workout_complete'));
      expect(server.writes(to: 'penalize_points').where((w) => w.who == memberB), isEmpty);
    }

    testWidgets('A -> B: B logs, rests and finishes, as B and only B', (t) async {
      final sidB = server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout))['id'] as String;
      final sidA = await aTrains(t);
      // A's rest ran over, for a long time.
      c.read(restTimerProvider.notifier).state =
          RestTimerState(DateTime.now().subtract(const Duration(seconds: 500)), 90);
      await t.pump();
      await switchTo(t, memberB);
      await bTrainsAndFinishes(t, sidB);
      expect(server.sessions.singleWhere((s) => s['id'] == sidA)['status'], 'in_progress');
      expect(server.setLogs.where((r) => r['user_id'] == memberA), isEmpty);
      await close(t);
    });

    testWidgets('the next frame already holds B\'s workout: the view is B\'s, not A\'s', (t) async {
      final sidB = server.seedSession(memberB, workoutId: _bWorkout.id, title: _bWorkout.title,
          snapshot: _snap(_bWorkout))['id'] as String;
      await aTrains(t);
      await switchUnseen(t);
      c.read(selectedWorkoutProvider.notifier).state = _bWorkout;
      await settle(t);
      await bTrainsAndFinishes(t, sidB);
      await close(t);
    });
  });

  group('pressed or answered after a switch no frame followed', () {
    testWidgets('Save Correction', (t) async {
      await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      await t.tap(find.text('Adjust weight or reps').first);
      await settle(t, 5);
      expect(find.text('Save Correction'), findsOneWidget, reason: 'premise');
      final sent = server.writes(to: 'workout_set_logs').length;
      await switchUnseen(t);
      await t.tap(find.text('Save Correction'));
      await settle(t);
      expect(server.writes(to: 'workout_set_logs'), hasLength(sent));
      expectNoWritesByB();
      expect(find.textContaining('corrected'), findsNothing);
      expect(c.read(activeWorkoutProvider), isEmpty);
      expectRecorded();
      await close(t);
    });

    testWidgets('a substitute exercise', (t) async {
      await aTrains(t);
      await openSwap(t);
      await switchUnseen(t);
      await t.tap(find.byType(ListTile).first);
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull,
          reason: "THE defect: A's workout, swapped, selected for B");
      expectNoWritesByB();
      expect(find.textContaining('Swapped'), findsNothing);
      expectRecorded();
      await close(t);
    });

    testWidgets('Leave For Now', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await switchUnseen(t);
      c.read(selectedWorkoutProvider.notifier).state = _bWorkout;
      c.read(activeWorkoutProvider.notifier)
        ..beginSession('b-session')
        ..completeSet(_bWorkout.exercises.first.sets.first, {'reps': 8});
      await t.tap(find.text('Leave For Now'));
      expect(c.read(activeWorkoutProvider), isNotEmpty,
          reason: "THE defect: A's leaving reset B's sets");
      expect(c.read(activeWorkoutProvider.notifier).sessionId, 'b-session');
      expectNoWritesByB();
      expectRecorded();
      await close(t);
    });

    testWidgets('the warm-up', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(find.textContaining('Warmed Up'), findsOneWidget);
      await switchUnseen(t);
      await t.tap(find.textContaining('Warmed Up'));
      await settle(t);
      expectNoWritesByB();
      expect(server.sessions.single['warmup_acknowledged_at'], isNull);
      expectRecorded();
      await close(t);
    });

    testWidgets('a warm-up answer in flight: nothing is re-read for A, or of A', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.textContaining('Warmed Up'));
      await settle(t, 3);
      await switchUnseen(t);
      failures.clear();
      hold.complete();
      for (var i = 0; i < 20; i++) {
        await t.idle(); // the answer is acted on; nothing is drawn
      }
      expectRecorded();
      await settle(t);
      expect(find.text('No workout selected'), findsOneWidget);
      expectNoWritesByB();
      await close(t);
    });

    testWidgets('control: A\'s correction, swap and Leave For Now', (t) async {
      final sid = await aTrains(t);
      await t.tap(logSet().first);
      await settle(t);
      await t.tap(find.text('Adjust weight or reps').first);
      await settle(t, 5);
      await t.tap(find.text('Save Correction'));
      await settle(t, 5);
      expect(find.textContaining('corrected'), findsOneWidget);
      await settle(t, 50);
      await openSwap(t, 1);
      await t.tap(find.byType(ListTile).first);
      await settle(t, 5);
      expect(find.textContaining('Swapped to'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('Leave For Now'));
      await settle(t);
      expect(find.text('home screen'), findsOneWidget);
      expect(server.sessions.single['id'], sid);
      expect(server.sessions.single['status'], 'in_progress');
      expect(server.writes().map((w) => w.who).toSet(), {memberA});
      await close(t);
    });
  });

  group('the dialogs go with A', () {
    testWidgets('End', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      expect(find.text('Leave this workout?'), findsOneWidget);
      await switchTo(t, memberB);
      expect(find.text('Leave this workout?'), findsNothing,
          reason: "THE defect: A's dialog over B's screen");
      await close(t);
    });

    testWidgets('the warm-up, which nothing else can dismiss', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(find.textContaining('Warmed Up'), findsOneWidget);
      await switchTo(t, memberB);
      expect(find.textContaining('Warmed Up'), findsNothing);
      await t.tap(find.text('Browse Workouts')); // B can use the screen
      await settle(t);
      expect(find.text('train screen'), findsOneWidget);
      await close(t);
    });

    testWidgets('pushed, and the switch before its first frame: never drawn', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session')); // pushed; no frame yet
      await switchUnseen(t);
      await t.pump();
      expect(find.text('Leave this workout?'), findsNothing);
      expect(find.text('End Workout'), findsNothing);
      await settle(t);
      expect(find.text('No workout selected'), findsOneWidget);
      await close(t);
    });

    testWidgets('control: A\'s own stay up through a token refresh', (t) async {
      await aTrains(t);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('Leave this workout?'), findsOneWidget);
      await close(t);
    });
  });

  group('A\'s failure after the switch is not said to B', () {
    testWidgets('a set that did not save', (t) async {
      await aTrains(t);
      server.fails.add('PATCH workout_set_logs:$memberA');
      final hold = server.holds['PATCH workout_set_logs:$memberA'] = Completer<void>();
      await t.tap(logSet().first);
      await settle(t, 3);
      await switchUnseen(t);
      hold.complete();
      await t.pump();
      expectNothingSaid();
      await settle(t);
      expectNothingSaid();
      await close(t);
    });

    testWidgets('a workout that did not start', (t) async {
      server.fails.add('POST workout_sessions:$memberA');
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      await switchUnseen(t);
      hold.complete();
      await t.pump();
      expectNothingSaid();
      await settle(t);
      expectNothingSaid();
      expect(find.textContaining('Warmed Up'), findsNothing);
      await close(t);
    });

    testWidgets('a workout that did not end', (t) async {
      await aTrains(t);
      server.fails.add('PATCH workout_sessions:$memberA');
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 3);
      await switchUnseen(t);
      hold.complete();
      await t.pump();
      expectNothingSaid();
      await settle(t);
      expectNothingSaid();
      await close(t);
    });

    testWidgets('a swap that did not save', (t) async {
      await aTrains(t);
      server.fails.add('PATCH workout_sessions:$memberA');
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await openSwap(t);
      await t.tap(find.byType(ListTile).first);
      await settle(t, 5);
      await switchUnseen(t);
      hold.complete();
      await t.pump();
      expectNothingSaid();
      expect(find.textContaining('Swapped'), findsNothing);
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull);
      await close(t);
    });

    testWidgets('control: each is said to A, with the next step and no backend text', (t) async {
      await aTrains(t);
      server.fails.addAll(['PATCH workout_set_logs:$memberA', 'PATCH workout_sessions:$memberA']);
      await t.tap(logSet().first);
      await settle(t, 5);
      expect(find.textContaining("Couldn't save that set — try again in a moment"), findsOneWidget);
      await settle(t, 50);
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 5);
      expect(find.textContaining("Couldn't end the workout — try again in a moment"), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      await close(t);
    });
  });

  group('what is recorded', () {
    testWidgets('a hidden tab\'s clock records the change once, not every tick', (t) async {
      await aTrains(t);
      await switchUnseen(t);
      failures.clear();
      for (var i = 0; i < 4; i++) {
        // A checkpoint, with the tab hidden: no frame.
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      Supabase.instance.client.auth.stopAutoRefresh();
      expect(failures.where((f) => f.origin == 'ActiveWorkoutScreen'), hasLength(1));
      expectNoWritesByB();
      await settle(t);
      await close(t);
    });

    testWidgets('best-effort saves that fail are recorded, and not shown', (t) async {
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      server.fails.add('PATCH workout_sessions:$memberA');
      await t.tap(find.textContaining('Warmed Up'));
      await settle(t);
      await t.tap(logSet().first); // moves the cursor
      await settle(t, 3);
      await t.tap(find.bySemanticsLabel('Pause session')); // saves the clock
      await settle(t, 3);
      expect(failures.map((f) => f.origin), containsAll([
        'ActiveWorkoutScreen.acknowledgeWarmup',
        'ActiveWorkoutScreen.saveCursor',
        'ActiveWorkoutScreen.saveElapsed',
      ]));
      expectNothingSaid();
      await close(t);
    });

    testWidgets('leaving for now with a clock that does not save still leaves', (t) async {
      await aTrains(t);
      server.fails.add('PATCH workout_sessions:$memberA');
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      failures.clear();
      await t.tap(find.text('Leave For Now'));
      await settle(t);
      expect(find.text('home screen'), findsOneWidget);
      expect(failures.map((f) => f.origin), contains('ActiveWorkoutScreen.saveElapsed'));
      await close(t);
    });
  });

  group('a swap', () {
    final before = _aWorkout.exercises.first.exercise.name;
    Future<String> swapFirst(WidgetTester t) async {
      final name = await openSwap(t);
      await t.tap(find.byType(ListTile).first);
      await t.pump();
      return name;
    }

    String first() => c.read(selectedWorkoutProvider)!.exercises.first.exercise.name;

    testWidgets('that matched no session is said, and reverted', (t) async {
      final sid = await aTrains(t);
      server.locked.add(sid);
      final to = await swapFirst(t);
      await settle(t, 6);
      expect(find.textContaining("Couldn't swap to $to — try again in a moment"), findsOneWidget,
          reason: 'THE defect: 0 rows counted as swapped');
      expect(find.text('Swapped to $to'), findsNothing);
      expect(first(), before, reason: 'it would be back on the next reload anyway');
      expect(c.read(selectedWorkoutProvider)!.exercises.first.instanceId,
          _aWorkout.exercises.first.instanceId,
          reason: 'the same slot, so its logged sets are still its own');
      expect(failures.map((f) => f.origin), contains('ActiveWorkoutScreen.saveSnapshot'));
      await close(t);
    });

    testWidgets('that failed puts the cursor back too', (t) async {
      await aTrains(t);
      final ex = _aWorkout.exercises.first;
      // The cursor is on the swapped exercise's second set.
      await t.enterText(find.byType(TextField).first, '70');
      await t.pump(const Duration(seconds: 1));
      await settle(t, 3);
      server.fails.add('PATCH workout_sessions:$memberA');
      await swapFirst(t);
      await settle(t, 6);
      expect(first(), before);
      final cursors = [
        for (final w in server.writes(by: memberA, to: 'workout_sessions'))
          if (w.body.contains('current_set_id')) (jsonDecode(w.body) as Map)['current_set_id']
      ];
      expect(cursors.last, ex.sets.first.id);
      expect(cursors.length, greaterThan(2), reason: 'premise: it had been re-pointed');
      await close(t);
    });

    testWidgets('that failed, with a set logged on the new movement meanwhile, keeps it',
        (t) async {
      await aTrains(t);
      server.fails.add('PATCH workout_sessions:$memberA');
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      final to = await swapFirst(t);
      await settle(t, 5);
      await t.tap(logSet().first);
      await settle(t, 3);
      hold.complete();
      await settle(t, 6);
      expect(first(), to, reason: 'a logged set must not lose its row');
      expect(find.textContaining('the change could not be saved'), findsOneWidget);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1);
      await close(t);
    });

    testWidgets('with no session yet is kept: the session opens with it', (t) async {
      server.fails.add('POST workout_sessions:$memberA');
      await aTrains(t, sessionOpens: false);
      await settle(t, 50);
      final to = await swapFirst(t);
      await settle(t, 6);
      expect(first(), to);
      server.fails.clear();
      await t.tap(logSet().first);
      await settle(t);
      expect(jsonEncode(server.sessions.single['workout_snapshot']), contains(to));
      await close(t);
    });

    testWidgets('control: one that saved stays, and says so', (t) async {
      final sid = await aTrains(t);
      final to = await swapFirst(t);
      await settle(t, 6);
      expect(find.text('Swapped to $to'), findsOneWidget);
      expect(first(), to);
      expect(server.sessions.single['id'], sid);
      expect(jsonEncode(server.sessions.single['workout_snapshot']), contains(to));
      expect(failures, isEmpty);
      await close(t);
    });
  });

  group('A -> B -> A while a finish or an End is in flight (N4)', () {
    Future<Completer<void>> finishHeld(WidgetTester t) async {
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.textContaining('Finish Early'));
      await settle(t, 3);
      return hold;
    }

    Future<Completer<void>> endHeld(WidgetTester t) async {
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 3);
      return hold;
    }

    for (final (what, start) in [('finish', finishHeld), ('End', endHeld)]) {
      testWidgets('$what: the workout A has opened since keeps its sets', (t) async {
        await aTrains(t);
        final hold = await start(t);
        await switchTo(t, memberB);
        await switchTo(t, memberA);
        router.go('/home');
        await settle(t);
        final w2 = another('w2');
        c.read(selectedWorkoutProvider.notifier).state = w2;
        c.read(activeWorkoutProvider.notifier)
          ..beginSession('s2')
          ..setSetData(w2.exercises.first.sets.first, {'reps': 7});
        final rest = RestTimerState(DateTime.now().add(const Duration(minutes: 1)), 60);
        c.read(restTimerProvider.notifier).state = rest;
        hold.complete();
        await settle(t);
        expect(t.takeException(), isNull);
        expect(c.read(selectedWorkoutProvider), same(w2), reason: 'THE defect: W2 cleared');
        expect(c.read(activeWorkoutProvider), isNotEmpty, reason: "THE defect: W2's entries lost");
        expect(c.read(activeWorkoutProvider.notifier).sessionId, 's2');
        expect(c.read(restTimerProvider), same(rest));
        expect(find.byType(WorkoutCompleteDialog), findsNothing);
        await close(t);
      });

      testWidgets('$what: the same workout begun again keeps its sets', (t) async {
        await aTrains(t);
        final hold = await start(t);
        await switchTo(t, memberB);
        await switchTo(t, memberA);
        router.go('/home');
        await settle(t);
        c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
        c.read(activeWorkoutProvider.notifier)
          ..beginSession('s2')
          ..setSetData(_aWorkout.exercises.first.sets.first, {'reps': 7});
        hold.complete();
        await settle(t);
        expect(c.read(selectedWorkoutProvider), same(_aWorkout));
        expect(c.read(activeWorkoutProvider), isNotEmpty);
        await close(t);
      });

      // No switch at all: A leaves by a tab while it saves, and begins another.
      testWidgets('$what: another workout picked meanwhile, not yet open, is kept', (t) async {
        await aTrains(t);
        final hold = await start(t);
        router.go('/home');
        await settle(t);
        final w2 = another('w2');
        c.read(selectedWorkoutProvider.notifier).state = w2; // its session is not bound yet
        hold.complete();
        await settle(t);
        expect(c.read(selectedWorkoutProvider), same(w2), reason: 'THE defect: W2 cleared');
        await close(t);
      });

      testWidgets('$what: the same workout begun again by the same member is kept', (t) async {
        await aTrains(t);
        final hold = await start(t);
        router.go('/home');
        await settle(t);
        c.read(activeWorkoutProvider.notifier)
          ..beginSession('s2')
          ..setSetData(_aWorkout.exercises.first.sets.first, {'reps': 7});
        hold.complete();
        await settle(t);
        expect(c.read(activeWorkoutProvider), isNotEmpty, reason: 'THE defect: its sets lost');
        expect(c.read(selectedWorkoutProvider), same(_aWorkout));
        await close(t);
      });

      testWidgets('$what: the app\'s state thrown away meanwhile is not touched', (t) async {
        await aTrains(t);
        final hold = await start(t);
        await switchTo(t, memberB);
        await t.pumpWidget(const SizedBox());
        c.dispose(); // what an account scope does
        await t.runAsync(() => signInAs(memberA));
        hold.complete();
        await t.pump(const Duration(seconds: 5));
        expect(t.takeException(), isNull, reason: 'THE defect: a disposed container was read');
      });

      testWidgets('$what: an unseen round trip is the same workout, and clears it', (t) async {
        await aTrains(t);
        final hold = await start(t);
        await switchUnseen(t);
        await switchUnseen(t, memberA);
        hold.complete();
        await settle(t);
        if (what == 'finish') {
          expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
          await t.tap(find.text('Skip'));
          await settle(t);
        }
        expect(c.read(selectedWorkoutProvider), isNull);
        expect(c.read(activeWorkoutProvider), isEmpty);
        expect(find.text('home screen'), findsOneWidget);
        await close(t);
      });
    }

    testWidgets('control: finishing before the session opened still ends in the dialog', (t) async {
      server.fails.add('POST workout_sessions:$memberA');
      await aTrains(t, sessionOpens: false);
      await settle(t, 50);
      await t.tap(find.textContaining('Finish Early'));
      await settle(t);
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      await t.tap(find.text('Skip'));
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull);
      await close(t);
    });

    testWidgets('control: a session that opens while finishing is not left in the way', (t) async {
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      final log = server.holds['POST workout_logs:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      await t.tap(find.textContaining('Finish Early'));
      await settle(t, 3);
      hold.complete();
      await settle(t, 3);
      log.complete();
      await settle(t);
      expect(server.sessions.single['status'], 'completed');
      expect(find.byType(WorkoutCompleteDialog), findsOneWidget);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, isNull);
      await close(t);
    });
  });
}
