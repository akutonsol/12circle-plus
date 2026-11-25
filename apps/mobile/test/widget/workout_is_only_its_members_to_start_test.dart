import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/coach/domain/coach_provider.dart';
import 'package:circle_fitness/features/dashboard/presentation/directory_screen.dart';
import 'package:circle_fitness/features/home/domain/home_session_card.dart';
import 'package:circle_fitness/features/notifications/domain/notification_provider.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_session_store.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_session_manager.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/train_hub_screen.dart';
import 'package:circle_fitness/features/workout/presentation/workout_detail_screen.dart';
import 'package:circle_fitness/features/workout/presentation/workout_list_screen.dart';
import 'package:circle_fitness/features/workout/presentation/zone_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_until.dart';
import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, refreshSession, signInAs;
import '../support/workout_members_server.dart';

// P0-FL-59b · A-10: a workout read for A and still on a card is not B's to
// start.
//
// The cards that list a program hold the previous member's list while the next
// one's is being read, after it failed, and for as long as no frame runs.
// `selectWorkoutForZone` asked who was signed in when the card was TAPPED — B,
// before and after — so it selected A's workout, and the Zone, opened by B,
// abandoned B's own open session, opened one from A's workout and awarded +5.
// Every other guard saw B doing it.
//
// Each tap is followed all the way: the real card, the real Zone, the real
// services; only the network is faked. `switchUnseen` is a switch no frame
// follows.
//
// HOW TO SEE IT FAIL: `git checkout 3f17006 --` the lib/features/workout files.

const _a = 'Leg Day of A', _b = 'Push Day of B';
const _days = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

void main() {
  late WorkoutMembersServer server;
  late ProviderContainer c;
  late GoRouter router;
  late List<AppFailure> failures;
  late Map<String, Object?> sessionOfB;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The hub's exercise pictures go through a disk cache: it never answers.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) => Completer<Object?>().future);
    server = WorkoutMembersServer();
    await initTwoMemberSupabase(server);
  });

  /// [uid] is assigned a program with one training day: today's.
  void assign(String uid, String title, {String? workoutId}) {
    final now = DateTime.now();
    server.rows['workout_program_assignments:$uid'] = [
      {
        'id': 'as-$uid', 'client_id': uid, 'coach_id': 'coach', 'program_id': 'p-$uid',
        'status': 'active', 'current_week': 1,
        'start_date': now.toIso8601String().substring(0, 10),
        'assigned_at': '2026-01-01T00:00:00Z',
      }
    ];
    server.rows['program_workouts:$uid'] = [
      {
        'id': workoutId ?? 'pw-$uid', 'program_id': 'p-$uid', 'title': title,
        'week_number': 1, 'day_of_week': _days[now.weekday - 1], 'sort_order': 0,
        'estimated_minutes': 45,
        'exercises': [
          {'instance_id': 'i1', 'name': 'Squat', 'sets': 2, 'reps': 5, 'rest_seconds': 60},
        ],
      }
    ];
  }

  setUp(() async {
    server.reset();
    failures = [];
    setFailureSink(failures.add);
    await signInAs(memberA);
    assign(memberA, _a);
    assign(memberB, _b);
    sessionOfB = server.seedSession(memberB, workoutId: 'own-of-b', title: 'Own of B');
    c = ProviderContainer(overrides: [
      tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
      memberPrefersMetricProvider.overrideWithValue(true),
      // The screens' own chrome.
      notificationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      assignedCoachProvider.overrideWith((ref) async => null),
    ]);
    c.listen(restoringUserIdProvider, (_, __) {});
  });

  tearDown(() {
    resetFailureSink();
    c.dispose();
  });

  Future<void> settle(WidgetTester t, [int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester t, Widget screen) async {
    t.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 7000);
    addTearDown(t.view.reset);
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(path: '/active-workout', builder: (_, __) => const ActiveWorkoutScreen()),
      GoRoute(path: '/workout-detail', builder: (_, __) => const WorkoutDetailScreen()),
      for (final p in ['/home', '/train', '/workouts'])
        GoRoute(path: p, builder: (_, __) => Text('at $p')),
    ]);
    addTearDown(router.dispose);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    await settle(t);
    t.takeException(); // the surrounding screens' own layout at this size
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  Future<void> switchUnseen(WidgetTester t, [String to = memberB]) => t.runAsync(() async {
        await signInAs(to);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });

  Future<void> switchSeen(WidgetTester t, [String to = memberB]) async {
    await switchUnseen(t, to);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == to, what: 'the switch');
    await settle(t);
  }

  List<Map<String, Object?>> sessionsOf(String uid) =>
      [for (final s in server.sessions) if (s['user_id'] == uid) s];

  /// B tapped A's card: nothing of it is selected, started, abandoned, awarded.
  void expectNothingStarted({bool recorded = true}) {
    expect([for (final w in server.writes(by: memberB)) '${w.method} ${w.table} ${w.body}'],
        isEmpty,
        reason: "THE defect: A's workout started as B");
    expect(sessionOfB['status'], 'in_progress', reason: "THE defect: B's own session abandoned");
    expect(sessionsOf(memberB), [sessionOfB]);
    expect(c.read(selectedWorkoutProvider)?.title, isNot(_a),
        reason: "THE defect: A's workout selected for B");
    expect(find.byType(SnackBar), findsNothing, reason: "nothing is said to B about A's tap");
    if (recorded) {
      expect(failures.map((f) => f.error.toString()),
          contains(contains('the signed-in account changed')));
    }
  }

  /// A tapped A's own card: A trains, in one session of A's.
  Future<void> expectATrains(WidgetTester t, {String title = _a}) async {
    await settle(t);
    expect(c.read(selectedWorkoutProvider)?.title, title);
    final open = sessionsOf(memberA).where((s) => s['status'] == 'in_progress');
    expect([for (final s in open) s['workout_title']], [title]);
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(failures.map((f) => f.error.toString()),
        isNot(contains(contains('the signed-in account changed'))));
  }

  /// Home's Today card: private to a screen that reaches `Supabase.instance`
  /// and a score of other reads, so its read and its tap, verbatim.
  Widget homeCard() => Consumer(builder: (context, ref, _) {
        final session = homeSession(ref.watch(assignedWorkoutsProvider));
        ref.watch(activeSessionProvider); // as Home's Resume banner does
        Future<void> onStart() async {
          final w = session.workout;
          if (w != null) {
            await selectWorkoutForZone(ref, w);
            if (!context.mounted) return;
            context.go('/active-workout');
            return;
          }
          context.go('/train');
        }

        return Column(children: [
          Text(session.title ?? session.emptyLine),
          TextButton(onPressed: onStart, child: const Text(HomeSession.beginLabel)),
        ]);
      });

  final beginSession = find.text('Begin session');

  group("Directory's Resume", () {
    final resume = find.text('Resume Workout');
    setUp(() => server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a));

    testWidgets('B, no frame since the switch: nothing is started', (t) async {
      await mount(t, const DirectoryScreen());
      expect(resume, findsOneWidget);
      await switchUnseen(t);
      await t.tap(resume);
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets("B's program being read, A's card still up: nothing is started", (t) async {
      server.holds['GET workout_program_assignments:$memberB'] = Completer<void>();
      server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      await mount(t, const DirectoryScreen());
      await switchSeen(t);
      expect(resume, findsOneWidget, reason: 'premise: the card still holds A\'s');
      await t.tap(resume);
      server.holds['GET workout_sessions:$memberB']!.complete();
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets("B's program read failed, A's card still up: nothing is started", (t) async {
      server.fails.add('GET workout_program_assignments:$memberB');
      server.fails.add('GET workout_sessions:$memberB');
      await mount(t, const DirectoryScreen());
      await switchSeen(t);
      expect(resume, findsOneWidget, reason: 'premise: the card still holds A\'s');
      server.fails.remove('GET workout_sessions:$memberB');
      await t.tap(resume);
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets("A's status is not B's: one coach program, shared workout ids", (t) async {
      assign(memberB, _b, workoutId: 'pw-$memberA');
      // The statuses' own read, not the one that says which days are done.
      server
        ..heldByWhere = Completer<void>()
        ..holdWhere = ((a) =>
            a.table == 'workout_sessions' && a.who == memberB && a.query.contains('in_progress'));
      await mount(t, const DirectoryScreen());
      await switchSeen(t);
      expect(find.text(_b), findsOneWidget, reason: "premise: B's own program");
      expect(resume, findsNothing, reason: "THE defect: A's progress on B's workout");
      await close(t);
    });

    testWidgets('control: A resumes, also after a token refresh', (t) async {
      await mount(t, const DirectoryScreen());
      await t.runAsync(refreshSession);
      await settle(t);
      await t.tap(resume);
      await expectATrains(t);
      expect(sessionsOf(memberA), hasLength(1), reason: 'the open session, not another');
      await close(t);
    });
  });

  group("Home's Today card", () {
    testWidgets('B, no frame since the switch: nothing is started', (t) async {
      await mount(t, homeCard());
      expect(find.text(_a), findsOneWidget);
      await switchUnseen(t);
      await t.tap(find.text(HomeSession.beginLabel));
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets("B's program being read, A's card still up: nothing is started", (t) async {
      server.holds['GET workout_program_assignments:$memberB'] = Completer<void>();
      await mount(t, homeCard());
      await switchSeen(t);
      expect(find.text(_a), findsOneWidget, reason: 'premise: the card still holds A\'s');
      await t.tap(find.text(HomeSession.beginLabel));
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets("B's card, tapped as A with no frame since: nothing is started", (t) async {
      await mount(t, homeCard());
      await switchSeen(t);
      await switchUnseen(t, memberA);
      await t.tap(find.text(HomeSession.beginLabel)); // B's card, tapped as A
      await settle(t);
      expect(server.writes(by: memberA), isEmpty, reason: "B's workout started as A");
      expect(c.read(selectedWorkoutProvider)?.title, isNot(_b));
      await close(t);
    });

    testWidgets('control: A begins; then B, with B\'s own card, begins B\'s', (t) async {
      server.sessions.clear();
      await mount(t, homeCard());
      await t.tap(find.text(HomeSession.beginLabel));
      await expectATrains(t);
      router.go('/');
      await switchSeen(t);
      expect(find.text(_b), findsOneWidget);
      await t.tap(find.text(HomeSession.beginLabel));
      await settle(t);
      expect([for (final s in sessionsOf(memberB)) s['workout_title']], [_b]);
      expect(sessionsOf(memberA).single['status'], 'in_progress');
      await close(t);
    });
  });

  group('the Train hub', () {
    testWidgets('Begin session, B, no frame since the switch: nothing is started', (t) async {
      await mount(t, const TrainHubScreen());
      expect(find.text(_a), findsWidgets);
      await switchUnseen(t);
      await t.tap(beginSession);
      await settle(t);
      expectNothingStarted();
      await close(t);
    });

    testWidgets('a week row, B, no frame since the switch: nothing is selected', (t) async {
      await mount(t, const TrainHubScreen());
      await switchUnseen(t);
      await t.tap(find.text(_a).last);
      await settle(t);
      expectNothingStarted();
      expect(find.byType(WorkoutDetailScreen), findsNothing);
      await close(t);
    });

    testWidgets('Resume, B, no frame since the switch: nothing is bound, or said', (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      await mount(t, const TrainHubScreen());
      await switchUnseen(t);
      await t.tap(find.text('RESUME WORKOUT'));
      await t.pump();
      await settle(t, 5);
      expectNothingStarted();
      await close(t);
    });

    testWidgets('Resume in flight across the switch: nothing is bound, or said', (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      final hold =
          server.holds['GET workout_program_assignments:$memberA'] = Completer<void>();
      await mount(t, const TrainHubScreen());
      await t.tap(find.text('RESUME WORKOUT'));
      await t.pump();
      await switchUnseen(t);
      hold.complete();
      await settle(t, 5);
      expectNothingStarted();
      await close(t);
    });

    testWidgets('re-read before the switch is seen: A\'s plan and session are not B\'s',
        (t) async {
      // A provider that watches `currentUserProvider.select` and is invalidated
      // while the change is unflushed is REFRESHED by riverpod (data, loading,
      // A's value). These read the uid through a provider of its own, or the
      // whole user, and are reloaded; pinned here. The cards do not lean on it:
      // see 'a value read for A'.
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      await mount(t, const TrainHubScreen());
      expect(find.text(_a), findsWidgets);
      server.holds['GET workout_program_assignments:$memberB'] = Completer<void>();
      server.holds['GET workout_sessions:$memberB'] = Completer<void>();
      await switchUnseen(t);
      c.invalidate(assignedWorkoutsProvider); // a notification
      c.invalidate(activeSessionProvider); // an answered warm-up, a discard
      await settle(t);
      expect(find.text(_a), findsNothing, reason: "THE defect: A's plan shown to B");
      expect(find.text('RESUME WORKOUT'), findsNothing, reason: "THE defect: A's session");
      expect(beginSession, findsNothing);
      server.holds['GET workout_program_assignments:$memberB']!.complete();
      server.holds['GET workout_sessions:$memberB']!.complete();
      await settle(t);
      expect(find.text(_b), findsWidgets);
      expect(find.text('Own of B'), findsOneWidget);
      await close(t);
    });

    testWidgets('control: a same-member refresh keeps the plan and the session up', (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      await mount(t, const TrainHubScreen());
      server.holds['GET workout_program_assignments:$memberA'] = Completer<void>();
      server.holds['GET workout_sessions:$memberA'] = Completer<void>();
      c.invalidate(assignedWorkoutsProvider);
      c.invalidate(activeSessionProvider);
      await settle(t);
      expect(beginSession, findsOneWidget);
      expect(find.text('RESUME WORKOUT'), findsOneWidget);
      await close(t);
    });

    testWidgets('control: Begin session starts A\'s', (t) async {
      await mount(t, const TrainHubScreen());
      await t.tap(beginSession);
      await expectATrains(t);
      await close(t);
    });

    testWidgets('control: a week row opens A\'s review, and A begins it there', (t) async {
      await mount(t, const TrainHubScreen());
      await t.tap(find.text(_a).last);
      await settle(t);
      expect(find.byType(WorkoutDetailScreen), findsOneWidget);
      await t.tap(beginSession);
      await expectATrains(t);
      await close(t);
    });

    testWidgets('control: Resume binds A\'s own session', (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      await mount(t, const TrainHubScreen());
      await t.tap(find.text('RESUME WORKOUT'));
      await expectATrains(t);
      expect(sessionsOf(memberA), hasLength(1));
      await close(t);
    });
  });

  group('the Workouts list', () {
    testWidgets('START, B, no frame since the switch: nothing is started', (t) async {
      await mount(t, const WorkoutListScreen());
      await switchUnseen(t);
      await t.tap(find.text('START'));
      await settle(t);
      expectNothingStarted();
      expect(find.byType(ActiveWorkoutScreen), findsNothing);
      await close(t);
    });

    testWidgets('re-read before the switch is seen: A\'s program is not B\'s', (t) async {
      await mount(t, const WorkoutListScreen());
      expect(find.text(_a), findsOneWidget);
      server.holds['GET workout_program_assignments:$memberB'] = Completer<void>();
      await switchUnseen(t);
      c.invalidate(assignedWorkoutsProvider);
      await settle(t);
      expect(find.text(_a), findsNothing, reason: "THE defect: A's program shown to B");
      expect(find.text('START'), findsNothing);
      await close(t);
    });

    testWidgets('the coach brief, re-read before the switch is seen, is not shown to B',
        (t) async {
      server.rows['ai_insights:$memberA'] = [
        {'title': 'Easy day, A', 'body': 'x', 'data': {'intensity_delta': -20}}
      ];
      await mount(t, const WorkoutListScreen());
      expect(find.textContaining('EASY DAY, A'), findsOneWidget);
      c.invalidate(coachAdjustmentProvider);
      await settle(t, 3);
      expect(find.textContaining('EASY DAY, A'), findsOneWidget, reason: 'control: A\'s refresh');
      server.holds['GET ai_insights:$memberB'] = Completer<void>();
      await switchUnseen(t);
      c.invalidate(coachAdjustmentProvider);
      await settle(t);
      expect(find.textContaining('EASY DAY, A'), findsNothing,
          reason: "THE defect: A's coach brief shown to B");
      await close(t);
    });

    testWidgets('a browse card A\'s list was built with opens nothing for B', (t) async {
      await mount(t, const WorkoutListScreen());
      await switchUnseen(t);
      await t.tap(find.textContaining('Full Body').last, warnIfMissed: false);
      await settle(t);
      expect(find.byType(WorkoutDetailScreen), findsNothing,
          reason: "THE defect: a tap on A's list opened for B");
      expect(c.read(selectedWorkoutProvider), isNull);
      expectNothingStarted();
      await close(t);
    });

    for (final seen in [true, false]) {
      testWidgets(
          "A's generated workout arriving after the switch "
          '(${seen ? 'seen' : 'no frame'}) is not started as B', (t) async {
        final hold = server.holds['POST ai-generate-workout:$memberA'] = Completer<void>();
        server.answers['ai-generate-workout:$memberA'] = {
          'workout': {'id': '', 'title': _a, 'exercises': []}
        };
        await mount(t, const WorkoutListScreen());
        await t.tap(find.text('Generate AI Workout'));
        await t.pump();
        await pumpUntil(t, () => server.writes(to: 'ai-generate-workout').isNotEmpty,
            what: 'the generator to be asked');
        seen ? await switchSeen(t) : await switchUnseen(t);
        hold.complete();
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
        expectNothingStarted(recorded: !seen);
        await close(t);
      });
    }

    testWidgets('control: START starts A\'s, also after a token refresh', (t) async {
      await mount(t, const WorkoutListScreen());
      await t.enterText(find.byType(TextField).first, 'full');
      await t.runAsync(refreshSession);
      await settle(t);
      expect(find.text('full'), findsOneWidget, reason: 'the view was rebuilt');
      await t.tap(find.text('START'));
      await expectATrains(t);
      await close(t);
    });

    testWidgets('control: a generated workout starts, for the member who asked', (t) async {
      server.answers['ai-generate-workout:$memberA'] = {
        'workout': {
          'id': 'gen', 'title': 'Generated',
          'exercises': [
            {'instance_id': 'g1', 'name': 'Squat', 'sets': 2, 'reps': 5},
          ],
        }
      };
      await mount(t, const WorkoutListScreen());
      await t.tap(find.text('Generate AI Workout'));
      await pumpUntil(t, () => sessionsOf(memberA).isNotEmpty,
          what: 'the generated workout to open', step: const Duration(milliseconds: 20));
      await expectATrains(t, title: 'Generated');
      await close(t);
    });

    testWidgets('control: a catalogue workout opens its review and begins', (t) async {
      await mount(t, const WorkoutListScreen());
      await t.tap(find.textContaining('Full Body').last, warnIfMissed: false);
      await settle(t);
      expect(find.byType(WorkoutDetailScreen), findsOneWidget);
      expect(c.read(selectedWorkoutProvider)?.id, '1');
      await t.tap(beginSession);
      await expectATrains(t, title: 'Full Body Strength');
      await close(t);
    });
  });

  group('a value read for A, handed to B\'s screen as data', () {
    // Whatever way a read comes to hold it. The value says whose it is; the
    // read's state (data, loading, error) does not.
    /// [c], rebuilt for B with [overrides].
    Future<void> asB(WidgetTester t, List<Override> Function() overrides) async {
      c.dispose();
      c = ProviderContainer(overrides: [
        tableTickerProvider.overrideWith((ref, t) => Stream.value(0)),
        memberPrefersMetricProvider.overrideWithValue(true),
        notificationsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        assignedCoachProvider.overrideWith((ref) async => null),
        ...overrides(),
      ]);
      c.listen(restoringUserIdProvider, (_, __) {});
    }

    Future<T> readAsA<T>(WidgetTester t, FutureProvider<T> p) async {
      late T value;
      await t.runAsync(() async {
        final own = ProviderContainer(overrides: [
          tableTickerProvider.overrideWith((ref, t) => const Stream.empty()),
        ]);
        own.listen<Object?>(p, (_, __) {});
        value = await own.read(p.future);
        own.dispose();
      });
      return value;
    }

    for (final (name, screen) in [
      ('the Train hub', () => const TrainHubScreen()),
      ('the Workouts list', () => const WorkoutListScreen()),
    ]) {
      testWidgets('$name does not list A\'s program', (t) async {
        final ofA = await readAsA(t, assignedWorkoutsProvider);
        expect(ofA.single.title, _a);
        await switchUnseen(t);
        await asB(t, () => [assignedWorkoutsProvider.overrideWith((ref) async => ofA)]);
        await mount(t, screen());
        expect(find.text(_a), findsNothing, reason: "THE defect: A's program shown to B");
        expect(find.text('START'), findsNothing);
        expect(beginSession, findsNothing);
        await close(t);
      });
    }

    testWidgets('the Train hub does not offer A\'s session', (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      final ofA = await readAsA(t, activeSessionProvider);
      expect(ofA?.workoutTitle, _a);
      await switchUnseen(t);
      await asB(t, () => [activeSessionProvider.overrideWith((ref) async => ofA)]);
      await mount(t, const TrainHubScreen());
      expect(find.text('RESUME WORKOUT'), findsNothing, reason: "THE defect: A's session");
      expect(find.text(_a), findsNothing);
      await close(t);
    });

    for (final (name, screen) in [
      ('the Workouts list', () => const WorkoutListScreen()),
      ('the Zone', () => const ActiveWorkoutScreen()),
    ]) {
      testWidgets('$name does not apply A\'s coach brief', (t) async {
        server.rows['ai_insights:$memberA'] = [
          {'title': 'Easy day, A', 'body': 'x', 'data': {'intensity_delta': -20}}
        ];
        late CoachAdjustment? ofA;
        await t.runAsync(() async {
          final own = ProviderContainer();
          own.listen<Object?>(coachAdjustmentProvider, (_, __) {});
          ofA = await own.read(coachAdjustmentProvider.future);
          own.dispose();
        });
        expect(ofA?.title, 'Easy day, A');
        await switchUnseen(t);
        await asB(t, () => [coachAdjustmentProvider.overrideWith((ref) async => ofA)]);
        c.read(selectedWorkoutProvider.notifier).state =
            WorkoutService().getSampleWorkouts().first;
        await mount(t, screen());
        expect(find.textContaining('EASY DAY, A'), findsNothing);
        expect(find.text('COACH ADJUSTMENT'), findsNothing);
        await close(t);
      });
    }

    testWidgets('the Zone does not open on A\'s restored workout; B\'s is then resumed',
        (t) async {
      server.seedSession(memberA, workoutId: 'pw-$memberA', title: _a);
      final ofA = await readAsA(t, activeWorkoutRestorationProvider);
      expect(ofA?.workout.title, _a);
      await switchUnseen(t);
      sessionOfB['elapsed_seconds'] = 600;
      var reads = 0;
      final hold = Completer<void>();
      await asB(t, () => [
            activeWorkoutRestorationProvider.overrideWith((ref) async {
              if (reads++ == 0) return ofA;
              await hold.future;
              final w = Workout(
                  id: 'own-of-b', title: 'Own of B', description: '', estimatedDuration: 1,
                  difficulty: 'x', category: 'y',
                  exercises: WorkoutService().getSampleWorkouts().first.exercises);
              ref.read(selectedWorkoutProvider.notifier).state = w;
              return null;
            }),
          ]);
      await mount(t, const ActiveWorkoutScreen());
      expect(find.text('Restoring your workout…'), findsOneWidget);
      c.invalidate(activeWorkoutRestorationProvider);
      await settle(t, 3);
      hold.complete();
      await settle(t);
      expect(find.text('Own of B'), findsOneWidget);
      expect(find.textContaining('10:0'), findsOneWidget,
          reason: "THE defect: B's view was opened on A's answer, and never resumed B's session");
      await close(t);
    });
  });

  group('the Zone, and the session rules', () {
    late Workout ofA;
    setUp(() async {
      c.listen(assignedWorkoutsProvider, (_, __) {});
      ofA = (await c.read(assignedWorkoutsProvider.future)).single;
    });

    test('startWorkout refuses a workout read for another member, and asks nothing', () async {
      await signInAs(memberB);
      final before = server.asked.length;
      await expectLater(
          WorkoutSessionManager(SupabaseWorkoutSessionStore())
              .startWorkout(userId: memberB, workout: ofA),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('the signed-in account changed'))));
      expect(server.asked, hasLength(before));
      expect(sessionOfB['status'], 'in_progress', reason: "B's own session was abandoned");
    });

    test('control: A starts it; a workout read for nobody starts for anybody', () async {
      final m = WorkoutSessionManager(SupabaseWorkoutSessionStore());
      await m.startWorkout(userId: memberA, workout: ofA);
      await m.startWorkout(userId: memberA, workout: WorkoutService().getSampleWorkouts().first);
      expect([for (final s in sessionsOf(memberA)) s['status']], ['abandoned', 'in_progress']);
    });

    test('the program read does not go on as the next member', () async {
      final hold = server.holds['GET program_workouts:$memberA'] = Completer<void>();
      c.invalidate(assignedWorkoutsProvider);
      unawaited(c.read(assignedWorkoutsProvider.future).then((_) {}, onError: (_) {}));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await signInAs(memberB);
      hold.complete();
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final asB = server.asked.where((a) => a.table == 'workout_sessions' && a.who == memberB);
      expect(asB.where((a) => Uri.decodeFull(a.query).contains('pw-$memberA')), isEmpty,
          reason: "A's program, its sessions asked for as B");
      expect((await c.read(assignedWorkoutsProvider.future)).map((w) => w.title), [_b]);
    });

    testWidgets('A\'s workout seated in B\'s selection is not opened by the Zone', (t) async {
      await switchUnseen(t);
      c.read(selectedWorkoutProvider.notifier).state = ofA;
      await mount(t, const ActiveWorkoutScreen());
      expect(find.text(_a), findsNothing);
      expect(server.writes(by: memberB), isEmpty);
      expect(sessionOfB['status'], 'in_progress', reason: "B's own session abandoned");
      await close(t);
    });
  });
}
