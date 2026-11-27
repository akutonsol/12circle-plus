import 'dart:convert';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/core/realtime/realtime.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/workout_service.dart';
import 'package:circle_fitness/features/workout/data/workout_snapshot.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/set_tracker_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../support/two_member_postgrest.dart'
    show initTwoMemberSupabase, memberA, memberB, signInAs;
import '../support/workout_members_server.dart';

// P0-FL-62d round 2 · security N1: the Workout Zone's OWN owner check on a set
// row's flush (onChanged in active_workout_screen.dart), isolated.
//
// Two members on one coach program share workout ids and set ids. A has typed
// a weight into set 2 (its 600 ms save pending) when the account changes in a
// hidden tab — no frame follows, so A's Zone is still mounted — and B's own
// unfinished session of the SAME workout is restored into the app. Then A's
// debounce fires.
//
// Nothing below the view stops this one: the selection is B's workout with
// A's workout's id, so the view's "is my workout still selected" check passes,
// and the write never reaches the server (the save is refused further down by
// WorkoutService's bound owner) — but `_cacheSet` writes A's typed weight into
// the in-memory sets, which are B's by now, on the very set B is about to do.
//
// HOW TO SEE IT FAIL: in `_buildSetRows`' onChanged, drop `!_isOwner('saving a
// set') ||` (mutant onChanged_drops_owner_check / _r2).
//
// No AccountScope: the Zone stays mounted across the switch, as in a hidden
// web tab (see workout_zone_belongs_to_its_member_test.dart for the harness).

final _workout = WorkoutService().getSampleWorkouts().first;
Map<String, Object?> _snap(Workout w) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(workoutToSnapshot(w))) as Map);

void main() {
  late WorkoutMembersServer server;
  late ProviderContainer c;
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
    final router = GoRouter(initialLocation: '/active-workout', routes: [
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

  Finder weightOf(int i) => find
      .descendant(of: find.byType(SetTrackerRow).at(i), matching: find.byType(TextField))
      .first;

  final set2 = _workout.exercises.first.sets[1];

  /// A trains, set 2's weight typed and its save pending; then the account
  /// changes to B with no frame, and B's own session of the same workout is
  /// restored into the app (what B's Resume card does on B's first read).
  Future<void> bRestoresTheSameWorkoutUnderAsZone(WidgetTester t) async {
    server.seedSession(memberB,
        workoutId: _workout.id, title: _workout.title, snapshot: _snap(_workout));
    c.read(selectedWorkoutProvider.notifier).state = _workout;
    await mount(t);
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
    expect(server.sessions.where((s) => s['user_id'] == memberA), hasLength(1),
        reason: "premise: A's session is open");

    await t.enterText(weightOf(1), '77');
    await t.pump(const Duration(milliseconds: 100));

    await t.runAsync(() async {
      await signInAs(memberB);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final restored = await c.read(activeWorkoutRestorationProvider.future);
      expect(restored?.session.userId, memberB, reason: "premise: B's own session");
    });
    expect(Supabase.instance.client.auth.currentUser?.id, memberB);
    expect(c.read(selectedWorkoutProvider)?.id, _workout.id,
        reason: "premise: B's selection has A's workout's id");
    expect(c.read(activeWorkoutProvider)[set2.id], isNull,
        reason: 'premise: B has nothing on set 2');
  }

  /// Unmounted even when an expectation fails, so the next test starts clean.
  void zoneTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        try {
          await body(t);
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 5));
        }
      });

  zoneTest("A's pending set save fires after the switch: A's typed weight is not "
      "put into B's set of the same workout, and nothing is sent", (t) async {
    await bRestoresTheSameWorkoutUnderAsZone(t);
    final mark = server.asked.length;

    // A's 600 ms debounce fires; no frame has run since the switch.
    await t.pump(const Duration(milliseconds: 700));

    expect(c.read(activeWorkoutProvider)[set2.id]?['weight'], isNot(77),
        reason: "THE defect: A's typed weight was put into B's set 2");
    expect(c.read(activeWorkoutProvider)[set2.id], isNull);
    expect(
        [for (final a in server.asked.skip(mark)) if (a.method != 'GET') '${a.method} ${a.table}'],
        isEmpty);
    expect(server.setLogs, isEmpty);
    expect(failures.map((f) => '${f.error}'),
        contains(contains('the signed-in account changed')),
        reason: "A's refused save is recorded");

  });

  // Positive control: the same member, the same pending save, no switch.
  zoneTest('control: no switch, the debounce saves set 2 once, as A, into the '
      'in-memory sets and to the server', (t) async {
    c.read(selectedWorkoutProvider.notifier).state = _workout;
    await mount(t);
    await t.tap(find.textContaining('Warmed Up'));
    await settle(t);
    final sid = server.sessions.single['id'];
    await t.enterText(weightOf(1), '77');
    await t.pump(const Duration(milliseconds: 700));
    await settle(t, 5);
    expect(c.read(activeWorkoutProvider)[set2.id]?['weight'], 77);
    expect(
        [
          for (final r in server.setLogs)
            if (r['set_id'] == set2.id) (r['user_id'], r['session_id'], r['weight_kg'])
        ],
        [(memberA, sid, 77)]);
    expect(failures.where((f) => '${f.error}'.contains('account changed')), isEmpty);

  });
}
