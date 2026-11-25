import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/coach_client_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/resume_workout_banner.dart';
import 'package:circle_fitness/features/workout/presentation/zone_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, refreshSession, signInAs, signOut;
import '../support/workout_members_server.dart';

// P0-FL-59b · the ways INTO a workout, and the coach's workout stats, across a
// real account change under a mounted screen: the Resume banner (A-09),
// `bindSessionToSelectedWorkout` / `selectWorkoutForZone` (A-16) and the
// client-workout screen (A-18 / E7).
//
// HOW TO SEE IT FAIL: `git checkout a82f993 --` the lib/features/workout files.

final Workout _w = WorkoutService().getSampleWorkouts().first;

void main() {
  late WorkoutMembersServer server;
  late ProviderContainer c;
  late GoRouter router;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = WorkoutMembersServer();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    setFailureSink((_) {});
    await signInAs(memberA);
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
    ]);
    c.listen(restoringUserIdProvider, (_, __) {});
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester t, Widget screen) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2000);
    addTearDown(t.view.reset);
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: screen)),
      GoRoute(path: '/active-workout', builder: (_, __) => const Text('the zone')),
    ]);
    addTearDown(router.dispose);
    // The auth event replayed to the subscription made in setUp lands first.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle(t);
  }

  Future<void> switchUnseen(WidgetTester t, String to) => t.runAsync(() async {
        await signInAs(to);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });

  Future<void> signOutSeen(WidgetTester t) async {
    await t.runAsync(signOut);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == null, what: 'the sign-out');
    await settle(t);
  }

  Future<void> switchTo(WidgetTester t, String to) async {
    await switchUnseen(t, to);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == to, what: 'the switch');
    await settle(t);
  }

  group('the Resume banner', () {
    const a = 'Leg Day of A', b = 'Push Day of B';
    Finder named(String title) => find.textContaining(title);

    setUp(() => server.seedSession(memberA, workoutId: _w.id, title: a));

    testWidgets("B's lookup pending: A's workout is not offered", (t) async {
      await mount(t, const ResumeWorkoutBanner());
      expect(named(a), findsOneWidget);
      server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      await switchTo(t, memberB);
      expect(named(a), findsNothing, reason: "THE defect: A's workout offered to B");
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets("B's lookup failed: A's workout is not offered", (t) async {
      await mount(t, const ResumeWorkoutBanner());
      server.fails.add('GET workout_sessions:$memberB');
      await switchTo(t, memberB);
      expect(named(a), findsNothing, reason: "THE defect: A's workout stayed after B's failed read");
    });

    testWidgets('signed out: nothing is offered', (t) async {
      await mount(t, const ResumeWorkoutBanner());
      await signOutSeen(t);
      expect(named(a), findsNothing);
    });

    testWidgets("B's own unfinished workout is offered", (t) async {
      server.seedSession(memberB, workoutId: _w.id, title: b);
      await mount(t, const ResumeWorkoutBanner());
      await switchTo(t, memberB);
      expect(named(b), findsOneWidget);
      expect(named(a), findsNothing);
    });

    testWidgets("A's discard does not hide B's unfinished workout", (t) async {
      server.seedSession(memberB, workoutId: _w.id, title: b);
      await mount(t, const ResumeWorkoutBanner());
      await t.tap(find.byIcon(Icons.close_rounded));
      await settle(t);
      expect(named(a), findsNothing);
      await switchTo(t, memberB);
      expect(named(b), findsOneWidget, reason: "THE defect: B's workout was hidden by A's discard");
    });

    testWidgets('Discard on A\'s banner after the switch sends nothing', (t) async {
      await mount(t, const ResumeWorkoutBanner());
      await switchUnseen(t, memberB);
      await t.tap(find.byIcon(Icons.close_rounded));
      await settle(t);
      expect(server.writes(), isEmpty, reason: "THE defect: A's session written as B");
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Resume on A\'s banner after the switch opens nothing', (t) async {
      await mount(t, const ResumeWorkoutBanner());
      await switchUnseen(t, memberB);
      await t.tap(find.text('Resume'));
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull, reason: "THE defect: A's workout bound for B");
      expect(find.text('the zone'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Resume in flight across the switch binds nothing', (t) async {
      final hold =
          server.holds['GET workout_program_assignments:$memberA'] = Completer<void>();
      // Home watches the program too, so its read is answered for B.
      await mount(t, Consumer(builder: (context, ref, _) {
        ref.watch(assignedWorkoutsProvider);
        return const ResumeWorkoutBanner();
      }));
      await t.tap(find.text('Resume'));
      await t.pump();
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull, reason: 'THE defect: bound after the switch');
      expect(find.text('the zone'), findsNothing);
    });

    testWidgets('a discard that matched no session keeps the banner and says so', (t) async {
      await mount(t, const ResumeWorkoutBanner());
      server.sessions.single['user_id'] = memberB; // RLS: no longer A's to update
      await t.tap(find.byIcon(Icons.close_rounded));
      await settle(t);
      expect(named(a), findsOneWidget, reason: 'THE defect: 0 rows hid the banner');
      expect(find.textContaining("Couldn't discard"), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('control: A resumes, also after a token refresh', (t) async {
      await mount(t, const ResumeWorkoutBanner());
      await t.runAsync(refreshSession);
      await settle(t);
      expect(named(a), findsOneWidget);
      // The session has no snapshot here: it is matched to the sample workout.
      await t.tap(find.text('Resume'));
      await settle(t);
      expect(find.text('the zone'), findsOneWidget);
      expect(c.read(selectedWorkoutProvider)?.id, _w.id);
    });

    testWidgets('negative control: no unfinished workout shows no banner', (t) async {
      server.sessions.clear();
      await mount(t, const ResumeWorkoutBanner());
      expect(find.text('Resume Workout?'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
    });
  });

  group('selectWorkoutForZone', () {
    Widget opener() => Consumer(builder: (context, ref, _) {
          ref.watch(activeSessionProvider); // as Home's banner does
          return TextButton(
              onPressed: () => selectWorkoutForZone(ref, _w), child: const Text('open'));
        });

    testWidgets('the lookup in flight across the switch selects nothing', (t) async {
      final hold = server.holds['GET workout_sessions:$memberA'] = Completer<void>();
      await mount(t, opener());
      await t.tap(find.text('open'));
      await t.pump();
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull,
          reason: "THE defect: A's tap selected A's workout for B");
    });

    testWidgets('the lookup failing after the switch selects nothing', (t) async {
      final hold = server.holds['GET workout_sessions:$memberA'] = Completer<void>();
      await mount(t, opener());
      server.fails.addAll(['GET workout_sessions:$memberA', 'GET workout_sessions:$memberB']);
      await t.tap(find.text('open'));
      await t.pump();
      await switchTo(t, memberB);
      hold.complete();
      await settle(t);
      expect(c.read(selectedWorkoutProvider), isNull);
    });

    testWidgets('control: A\'s own tap selects it, also when the lookup fails', (t) async {
      server.fails.add('GET workout_sessions:$memberA');
      await mount(t, opener());
      await t.tap(find.text('open'));
      await settle(t);
      expect(c.read(selectedWorkoutProvider), same(_w));
    });
  });

  group('the coach\'s client workouts', () {
    Map<String, Object?> client(String id, String name) => {
          'client_id': id,
          'client_name': name,
          'total_completed': 3,
          'total_in_progress': 0,
          'total_abandoned': 0,
          'completion_rate_pct': 90,
          'workouts_this_week': 1,
          'last_workout_at': null,
        };

    setUp(() {
      server.rows['coach_client_workout_stats:$memberA'] = [client('ca', 'Alma of A')];
      server.rows['coach_client_workout_stats:$memberB'] = [client('cb', 'Bruno of B')];
      server.rows['workout_set_logs:$memberA'] = const [];
    });

    testWidgets('coach A -> coach B: B\'s read pending, then B\'s own clients', (t) async {
      await mount(t, const CoachClientWorkoutScreen());
      expect(find.text('Alma of A'), findsOneWidget);
      final hold =
          server.holds['GET coach_client_workout_stats:$memberB'] = Completer<void>();
      await switchTo(t, memberB);
      expect(find.text('Alma of A'), findsNothing, reason: "THE defect: A's client for coach B");
      hold.complete();
      await settle(t);
      expect(find.text('Bruno of B'), findsOneWidget);
      final asked = server.asked.where((a) => a.table == 'coach_client_workout_stats');
      expect([for (final a in asked) (a.who, a.query.contains(a.who))],
          [(memberA, true), (memberB, true)]);
    });

    testWidgets('coach B\'s read failed: no client of A\'s', (t) async {
      await mount(t, const CoachClientWorkoutScreen());
      server.fails.add('GET coach_client_workout_stats:$memberB');
      await switchTo(t, memberB);
      expect(find.text('Alma of A'), findsNothing);
      expect(find.text('Error loading stats'), findsOneWidget);
    });

    testWidgets('A\'s late answer landing after B is not shown', (t) async {
      final hold =
          server.holds['GET coach_client_workout_stats:$memberA'] = Completer<void>();
      await mount(t, const CoachClientWorkoutScreen());
      await switchTo(t, memberB);
      expect(find.text('Bruno of B'), findsOneWidget);
      hold.complete();
      await settle(t);
      expect(find.text('Alma of A'), findsNothing);
      expect(find.text('Bruno of B'), findsOneWidget);
    });

    testWidgets('a client both coach: A\'s open card is closed for B', (t) async {
      server.rows['coach_client_workout_stats:$memberA'] = [client('shared', 'Shared')];
      server.rows['coach_client_workout_stats:$memberB'] = [client('shared', 'Shared')];
      await mount(t, const CoachClientWorkoutScreen());
      await t.tap(find.text('Shared'));
      await settle(t);
      expect(find.text('TOP PERSONAL RECORDS'), findsOneWidget);
      await switchTo(t, memberB);
      expect(find.text('Shared'), findsOneWidget);
      expect(find.text('TOP PERSONAL RECORDS'), findsNothing);
    });

    testWidgets('signed out: no clients', (t) async {
      await mount(t, const CoachClientWorkoutScreen());
      await signOutSeen(t);
      expect(find.text('Alma of A'), findsNothing);
    });

    testWidgets('control: a token refresh keeps the open card and re-reads nothing', (t) async {
      await mount(t, const CoachClientWorkoutScreen());
      await t.tap(find.text('Alma of A'));
      await settle(t);
      final before = server.asked.length;
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('TOP PERSONAL RECORDS'), findsOneWidget);
      expect(server.asked, hasLength(before));
    });

    testWidgets('negative control: a coach with no clients is told so', (t) async {
      server.rows.remove('coach_client_workout_stats:$memberA');
      await mount(t, const CoachClientWorkoutScreen());
      expect(find.text('No Active Clients'), findsOneWidget);
      expect(find.text('Error loading stats'), findsNothing);
    });
  });
}
