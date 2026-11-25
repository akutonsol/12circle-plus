import 'dart:async';
import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
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
    show initTwoMemberSupabase, memberA, memberB, signInAs, signOut;
import '../support/workout_members_server.dart';

// P0-FL-59b round 3 · a swap is stored as it is shown.
//
// A swap whose save failed was undone on screen only. The session's stored
// workout could still hold it — a later swap's save had carried it, or the
// write had landed and only its answer was lost — so the next reload brought
// the undone movement back, and the sets logged on the one on screen, whose ids
// that workout does not have, were dropped from it. Saves now run one at a
// time, in order, and an undo is saved too; "Couldn't swap" is said only once
// that save has landed.
//
// The real screen over the real auth client and services; only the network is
// faked. HOW TO SEE IT FAIL: `git checkout db390ea -- ` active_workout_screen.dart.

final _aWorkout = WorkoutService().getSampleWorkouts().first;
final _bWorkout = WorkoutService().getSampleWorkouts()[1];
Map<String, Object?> _snap(Workout w) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(workoutToSnapshot(w))) as Map);

bool _isSnapshot(Asked a) =>
    a.method == 'PATCH' && a.table == 'workout_sessions' && a.body.contains('workout_snapshot');

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

  Future<String> aTrains(WidgetTester t) async {
    c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
    await mount(t);
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
    final mine = server.sessions.where((r) => r['user_id'] == memberA);
    expect(mine, hasLength(1), reason: "premise: A's session is open");
    return mine.single['id'] as String;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  }

  /// Restores from the server: out and back in.
  Future<void> restore(WidgetTester t) async {
    await t.runAsync(signOut);
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == null, what: 'the sign-out');
    await settle(t);
    await t.runAsync(() => signInAs(memberA));
    await pumpUntil(t, () => c.read(restoringUserIdProvider) == memberA, what: 'the sign-in');
    await settle(t, 30);
  }

  Finder logSet() => find.bySemanticsLabel('Log set');

  /// Swaps exercise [at] for the substitute on offer, and answers its name.
  Future<String> swap(WidgetTester t, [int at = 0]) async {
    server.rows['custom_exercises:$memberA'] = [
      {'name': 'Goblet Squat', 'muscle_group': 'Legs', 'equipment': 'Dumbbell', 'difficulty': 'x'}
    ];
    await t.tap(find.byIcon(Icons.swap_horizontal_circle_rounded).at(at));
    await settle(t, 10);
    final name = (t.widget<ListTile>(find.byType(ListTile).first).title! as Text).data!;
    await t.tap(find.byType(ListTile).first);
    await t.pump();
    return name;
  }

  Workout shown() => c.read(selectedWorkoutProvider)!;
  String nameAt(int i) => shown().exercises[i].exercise.name;
  Object? stored() => server.sessions.single['workout_snapshot'];
  int snapshotWrites() => server.asked.where(_isSnapshot).length;

  void scripted(Outcome outcome, [Completer<void>? until]) =>
      server.script.add((where: _isSnapshot, outcome: outcome, until: until));

  void expectStoredAsShown() =>
      expect(stored(), _snap(shown()), reason: 'THE defect: a reload brings back what is not shown');

  void expectNothingSaid() {
    expect(find.byType(SnackBar), findsNothing, reason: "A's swap said to B");
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.textContaining('Swapped'), findsNothing);
  }

  final x = _aWorkout.exercises.first.exercise.name;

  group('a swap that failed is stored as it is shown (B1)', () {
    testWidgets('(a) swap 1 failing after swap 2 saved: X in slot 1, and swap 2', (t) async {
      await aTrains(t);
      final hold = Completer<void>();
      scripted(Outcome.refused, hold);
      final y1 = await swap(t, 0);
      await settle(t, 3);
      final y2 = await swap(t, 1);
      await settle(t, 5);
      hold.complete();
      await settle(t, 10);
      expect(nameAt(0), x);
      expect(nameAt(1), y2);
      expectStoredAsShown();
      expect(jsonEncode(stored()), isNot(contains(y1)));
      expect(find.text('Swapped to $y2'), findsOneWidget);
      await settle(t, 50);
      expect(find.textContaining("Couldn't swap to $y1 — try again in a moment"), findsOneWidget);
      await close(t);
    });

    testWidgets('(b) the save landed but its answer was lost: X is stored', (t) async {
      await aTrains(t);
      scripted(Outcome.lost);
      final y = await swap(t);
      await settle(t, 10);
      expect(nameAt(0), x);
      expectStoredAsShown();
      expect(find.textContaining("Couldn't swap to $y — check your connection"), findsOneWidget);
      expect(failures.map((f) => f.origin), contains('ActiveWorkoutScreen.saveSnapshot'));
      await close(t);
    });

    testWidgets('(c) a set logged on X after that survives a restore', (t) async {
      final sid = await aTrains(t);
      scripted(Outcome.lost);
      await swap(t);
      await settle(t, 10);
      await t.tap(logSet().first);
      await settle(t);
      expect(server.setLogs.where((r) => r['completed'] == true), hasLength(1));
      await restore(t);
      expect(c.read(activeWorkoutProvider.notifier).sessionId, sid);
      expect(nameAt(0), x);
      expect(c.read(activeWorkoutProvider.notifier).completedSetCount, 1,
          reason: 'THE defect: the logged set was dropped from the restored workout');
      await close(t);
    });

    testWidgets('(d) the undo does not save either: nothing promised', (t) async {
      await aTrains(t);
      scripted(Outcome.refused);
      scripted(Outcome.refused);
      final y = await swap(t);
      await settle(t, 10);
      expect(nameAt(0), x);
      expect(find.text('$x is back — but the change could not be saved.'), findsOneWidget);
      expect(find.textContaining("Couldn't swap"), findsNothing,
          reason: 'THE defect: said not swapped, when what is stored is not known');
      expect(find.textContaining('Swapped to $y'), findsNothing);
      expect(find.textContaining('Reloading'), findsNothing);
      await close(t);
    });

    testWidgets('a 0-row save whose undo lands: "Couldn\'t swap", and X stored', (t) async {
      await aTrains(t);
      scripted(Outcome.matchesNothing);
      final y = await swap(t);
      await settle(t, 10);
      expect(nameAt(0), x);
      expectStoredAsShown();
      expect(find.textContaining("Couldn't swap to $y — try again in a moment"), findsOneWidget);
      await close(t);
    });

    testWidgets('a set logged on the new movement keeps it, and stores it', (t) async {
      await aTrains(t);
      final hold = Completer<void>();
      scripted(Outcome.refused, hold);
      final y = await swap(t);
      await settle(t, 5);
      await t.tap(logSet().first);
      await settle(t, 3);
      hold.complete();
      await settle(t, 10);
      expect(nameAt(0), y, reason: 'a logged set must not lose its row');
      expectStoredAsShown();
      expect(find.text('Swapped to $y'), findsOneWidget);
      await close(t);
    });
  });

  group('an account change between the failure and the undo\'s save', () {
    Future<Completer<void>> twoSwapsFirstFailing(WidgetTester t) async {
      await aTrains(t);
      final first = Completer<void>();
      final second = Completer<void>();
      scripted(Outcome.refused, first);
      scripted(Outcome.ok, second);
      await swap(t, 0);
      await settle(t, 3);
      await swap(t, 1);
      await settle(t, 3);
      first.complete();
      await t.pump();
      await t.pump();
      // The undo's save waits behind the second swap's, still held.
      return second;
    }

    for (final (what, change) in [
      ('B signs in', () => signInAs(memberB)),
      ('A signs out', signOut),
    ]) {
      testWidgets('$what (no frame): nothing sent, nothing said', (t) async {
        final second = await twoSwapsFirstFailing(t);
        final before = snapshotWrites();
        await t.runAsync(() async {
          await change();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
        expect(Supabase.instance.client.auth.currentUser?.id,
            what == 'B signs in' ? memberB : isNull);
        second.complete();
        await t.pump();
        expectNothingSaid();
        await settle(t);
        expectNothingSaid();
        expect(snapshotWrites(), before, reason: 'the undo was saved for the next account');
        expect(server.writes(by: memberB), isEmpty);
        expect(failures.map((f) => f.error.toString()),
            contains(contains('the signed-in account changed')));
        await close(t);
      });
    }
  });

  group('controls: the same member', () {
    testWidgets('one swap that saves: stays, stored, said', (t) async {
      await aTrains(t);
      final y = await swap(t);
      await settle(t, 6);
      expect(nameAt(0), y);
      expectStoredAsShown();
      expect(find.text('Swapped to $y'), findsOneWidget);
      expect(snapshotWrites(), 1);
      expect(failures, isEmpty);
      await close(t);
    });

    testWidgets('two swaps in a row: both stay and are stored, in order', (t) async {
      await aTrains(t);
      final y1 = await swap(t, 0);
      final y2 = await swap(t, 1);
      await settle(t, 10);
      expect(nameAt(0), y1);
      expect(nameAt(1), y2);
      expectStoredAsShown();
      expect(snapshotWrites(), 2);
      expect(failures, isEmpty);
      await close(t);
    });
  });

  group('a swap made while the session is still opening (UX 1)', () {
    testWidgets('is stored once the session opens: a reload shows it', (t) async {
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      final y = await swap(t);
      await settle(t, 5);
      hold.complete();
      await settle(t);
      await t.tap(find.textContaining('Warmed Up'));
      await settle(t);
      expect(nameAt(0), y);
      expect(jsonEncode(stored()), contains(y),
          reason: 'THE defect: the session kept the workout from before the swap');
      expectStoredAsShown();
      expect(find.text('Swapped to $y'), findsOneWidget);
      await restore(t);
      expect(nameAt(0), y, reason: 'the reload brought back the replaced exercise');
      await close(t);
    });

    testWidgets('B signs in before it opens (no frame): nothing stored, nothing said', (t) async {
      final hold = server.holds['POST workout_sessions:$memberA'] = Completer<void>();
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      await swap(t);
      await settle(t, 5);
      await t.runAsync(() async {
        await signInAs(memberB);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      hold.complete();
      await t.pump();
      expectNothingSaid();
      await settle(t);
      expect(snapshotWrites(), 0);
      expect(server.writes(by: memberB), isEmpty);
      await close(t);
    });
  });

  group('End during a rest, another workout opened before it answers', () {
    Future<(Completer<void>, Object?)> endDuringRest(WidgetTester t) async {
      await aTrains(t);
      await t.tap(logSet().first);
      await settle(t, 5);
      final rest = c.read(restTimerProvider);
      expect(rest, isNotNull, reason: 'premise: resting');
      final hold = server.holds['PATCH workout_sessions:$memberA'] = Completer<void>();
      await t.tap(find.bySemanticsLabel('End session'));
      await settle(t, 5);
      await t.tap(find.text('End Workout'));
      await settle(t, 3);
      router.go('/home');
      await settle(t);
      final w2 = Workout(
          id: 'w2', title: 'Second of A', description: '', estimatedDuration: 20,
          difficulty: 'x', category: 'Strength', exercises: _bWorkout.exercises);
      c.read(selectedWorkoutProvider.notifier).state = w2;
      c.read(activeWorkoutProvider.notifier).beginSession('s2');
      return (hold, rest);
    }

    testWidgets("the ended workout's rest stops", (t) async {
      final (hold, rest) = await endDuringRest(t);
      expect(c.read(restTimerProvider), same(rest), reason: 'premise: still running');
      hold.complete();
      await settle(t);
      expect(c.read(restTimerProvider), isNull,
          reason: "THE defect: W1's rest kept running, and charging, over W2");
      expect(c.read(selectedWorkoutProvider)?.id, 'w2');
      await close(t);
    });

    testWidgets("control: the new workout's own rest is kept", (t) async {
      final (hold, _) = await endDuringRest(t);
      final own = RestTimerState(DateTime.now().add(const Duration(minutes: 1)), 60);
      c.read(restTimerProvider.notifier).state = own;
      hold.complete();
      await settle(t);
      expect(c.read(restTimerProvider), same(own));
      await close(t);
    });
  });

  group('said in the house voice (UX 3)', () {
    testWidgets('a workout that did not start', (t) async {
      server.fails.add('POST workout_sessions:$memberA');
      c.read(selectedWorkoutProvider.notifier).state = _aWorkout;
      await mount(t);
      expect(find.textContaining("Couldn't start this workout — try again in a moment"),
          findsOneWidget);
      expect(find.textContaining('Could not start'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      await close(t);
    });
  });
}
