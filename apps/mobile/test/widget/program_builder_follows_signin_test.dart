import 'dart:async';

import 'package:circle_fitness/core/observability/app_failure.dart';
import 'package:circle_fitness/features/auth/domain/auth_provider.dart';
import 'package:circle_fitness/features/coach/domain/coach_ecosystem_provider.dart';
import 'package:circle_fitness/features/coach/presentation/program_builder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_until.dart';
import '../support/two_coach_postgrest.dart';

// P0-FL-59f round 5 (S3) · the program library and the builder stay mounted
// across a real coach A -> coach B switch. A's programs and workouts were drawn
// for B while A's refresh was in flight at the switch (or the list was
// invalidated before it was flushed), and every button, sheet and dialog A had
// built did its write as whoever was signed in when it was tapped.
//
// The real service over a fake PostgREST; no app-root account scope.
//
// HOW TO SEE IT FAIL: `git checkout b00e5c4 -- lib/features/coach`.

const _lists = 'GET workout_programs';
const _days = 'GET program_workouts';

void main() {
  late TwoCoachPostgrest server;
  late ProviderContainer c;
  final reported = <AppFailure>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    server = TwoCoachPostgrest();
    await initTwoMemberSupabase(server);
  });

  setUp(() async {
    server.reset();
    reported.clear();
    setFailureSink(reported.add);
    // Both coaches may read the same program id: RLS answers each with its own.
    for (final (who, name) in [(memberA, 'A'), (memberB, 'B')]) {
      server
        ..seed('workout_programs', who, [
          {
            'id': 'prog-1',
            'name': 'Plan of $name',
            'duration_weeks': 8,
            'program_workouts': [
              {'count': 1}
            ],
          }
        ])
        ..seed('program_workouts', who, [
          {
            'id': 'w-1',
            'title': 'Session of $name',
            'week_number': 1,
            'day_of_week': 'Monday',
            'exercises': const <Map<String, Object?>>[],
          }
        ]);
    }
    await signInAs(memberA);
  });
  tearDown(resetFailureSink);

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool seen(Finder f) => f.evaluate().isNotEmpty;

  Future<void> library(WidgetTester tester, {String? what = 'Plan of A'}) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.reset);
    c = ProviderContainer();
    c.listen(currentUserProvider, (_, __) {});
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: ProgramLibraryScreen())));
    if (what != null) {
      await pumpUntil(tester, () => seen(find.text(what)), what: what);
    }
    await frames(tester);
  }

  /// A's builder, opened from the library as a coach opens it.
  Future<void> builder(WidgetTester tester) async {
    await library(tester);
    await tester.tap(find.text('Plan of A'));
    await pumpUntil(tester, () => seen(find.text('Session of A')), what: 'day');
    await frames(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> switchTo(WidgetTester tester, String? uid) =>
      tester.runAsync(() => uid == null ? signOut() : signInAs(uid));

  Future<void> become(WidgetTester tester, String? uid) async {
    await switchTo(tester, uid);
    await pumpUntil(tester, () => c.read(currentUserProvider)?.id == uid,
        what: 'signed in: $uid');
    await frames(tester, 2);
  }

  /// The same coach, as a new [User]: the event is asserted, not assumed.
  Future<void> tokenRefreshed(WidgetTester tester) async {
    final before = c.read(currentUserProvider);
    await tester.runAsync(refreshSession);
    await pumpUntil(tester, () => c.read(currentUserProvider) != before,
        what: 'the same coach as a new User');
    expect(c.read(currentUserProvider)?.id, memberA);
    await frames(tester, 2);
  }

  void nothingOfA(String when) {
    expect(find.textContaining('Plan of A'), findsNothing,
        reason: "THE defect: A's program was shown ($when)");
    expect(find.textContaining('Session of A'), findsNothing,
        reason: "THE defect: A's workout was shown ($when)");
  }

  Finder field(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint);

  VoidCallback press(WidgetTester tester, String label) => tester
      .widget<ButtonStyleButton>(find
          .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
          .last)
      .onPressed!;

  VoidCallback fab(WidgetTester tester, String label) => tester
      .widget<FloatingActionButton>(find.ancestor(
          of: find.text(label), matching: find.byType(FloatingActionButton)))
      .onPressed!;

  void pick(WidgetTester tester, IconData icon, String value) => tester
      .widget<PopupMenuButton<String>>(find.byWidgetPredicate((w) =>
          w is PopupMenuButton<String> && (w.icon as Icon?)?.icon == icon))
      .onSelected!(value);

  // ── the lists ─────────────────────────────────────────────────────────────

  group('the library', () {
    testWidgets("A's refresh in flight as B signs in, drawn: A's are not B's "
        "while B's read is out; then B's own", (tester) async {
      await library(tester);
      final holdA = server.holds['$_lists:$memberA'] = Completer<void>();
      c.invalidate(myProgramsProvider);
      await pumpUntil(tester, () => server.count('$_lists:$memberA') == 2,
          what: "A's refresh");
      final holdB = server.holds['$_lists:$memberB'] = Completer<void>();
      await become(tester, memberB);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        nothingOfA('frame $i');
      }
      holdA.complete();
      await frames(tester, 10);
      nothingOfA("A's answer, late");
      expect(find.textContaining('No programs yet'), findsNothing);
      holdB.complete();
      await pumpUntil(tester, () => seen(find.text('Plan of B')), what: 'B');
      nothingOfA("B's own");
      await unmount(tester);
    });

    for (final next in [memberB, null]) {
      final who = next == null ? 'A signs out' : 'B signs in';
      testWidgets("A's refresh in flight as $who, and the first frame after",
          (tester) async {
        await library(tester);
        server.holds['$_lists:$memberA'] = Completer<void>();
        c.invalidate(myProgramsProvider);
        await pumpUntil(tester, () => server.count('$_lists:$memberA') == 2,
            what: "A's refresh");
        server.holds['$_lists:$memberB'] = Completer<void>();
        await switchTo(tester, next);
        for (var i = 0; i < 8; i++) {
          await tester.pump();
          nothingOfA('frame $i');
        }
        for (final h in server.holds.values) {
          h.complete();
        }
        await frames(tester);
        await unmount(tester);
      });
    }

    for (final when in ['before', 'after']) {
      testWidgets('invalidated $when the switch, before it is flushed',
          (tester) async {
        await library(tester);
        final holdB = server.holds['$_lists:$memberB'] = Completer<void>();
        if (when == 'before') c.invalidate(myProgramsProvider);
        await switchTo(tester, memberB);
        if (when == 'after') c.invalidate(myProgramsProvider);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          nothingOfA('frame $i');
        }
        holdB.complete();
        await pumpUntil(tester, () => seen(find.text('Plan of B')), what: 'B');
        await unmount(tester);
      });
    }

    testWidgets("B's read pending, then failed: B's failure, with a retry",
        (tester) async {
      await library(tester);
      final hold = server.holds['$_lists:$memberB'] = Completer<void>();
      await become(tester, memberB);
      nothingOfA('pending');
      server.fails.add('$_lists:$memberB');
      hold.complete();
      await pumpUntil(tester,
          () => seen(find.text("Couldn't load your programs")), what: 'failed');
      nothingOfA('failed');
      expect(find.textContaining('SECRET_TABLE'), findsNothing);
      expect(find.textContaining('No programs yet'), findsNothing);
      server.fails.clear();
      press(tester, 'Try again')();
      await pumpUntil(tester, () => seen(find.text('Plan of B')), what: 'B');
      expect(find.text("Couldn't load your programs"), findsNothing);
      await unmount(tester);
    });

    testWidgets("A's failure, its Try again tapped after B signed in and before "
        "any frame, is not B's", (tester) async {
      server.fails.add('$_lists:$memberA');
      await library(tester, what: "Couldn't load your programs");
      final retry = press(tester, 'Try again');
      final hold = server.holds['$_lists:$memberB'] = Completer<void>();
      await switchTo(tester, memberB);
      retry();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text("Couldn't load your programs"), findsNothing,
            reason: "A's failure was said to B (frame $i)");
      }
      hold.complete();
      await pumpUntil(tester, () => seen(find.text('Plan of B')), what: 'B');
      await unmount(tester);
    });

    testWidgets('control: a refreshed token re-reads nothing; a refresh of '
        'theirs flickers nothing; a failed one keeps the list and says so, '
        'busy while it is tried again', (tester) async {
      await library(tester);
      await tokenRefreshed(tester);
      expect(server.count('$_lists:$memberA'), 1);
      var hold = server.holds['$_lists:$memberA'] = Completer<void>();
      c.invalidate(myProgramsProvider);
      await frames(tester);
      expect(find.text('Plan of A'), findsOneWidget);
      server.fails.add('$_lists:$memberA');
      hold.complete();
      await pumpUntil(tester,
          () => seen(find.text("Couldn't load your programs")), what: 'said');
      expect(find.text('Plan of A'), findsOneWidget, reason: 'kept');
      expect(find.textContaining('may be out of date'), findsOneWidget);
      server.fails.clear();
      hold = server.holds['$_lists:$memberA'] = Completer<void>();
      press(tester, 'Try again')();
      await frames(tester, 3);
      expect(find.text("Couldn't load your programs"), findsOneWidget);
      expect(find.text('Try again'), findsNothing, reason: 'busy');
      expect(find.text('Plan of A'), findsOneWidget);
      hold.complete();
      await pumpUntil(tester,
          () => !seen(find.text("Couldn't load your programs")), what: 'read');
      expect(find.text('Plan of A'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('control: pull to refresh reads again and shows what is new',
        (tester) async {
      server.seed('workout_programs', memberA, [
        for (var i = 1; i <= 40; i++) // long enough to scroll
          {'id': 'p-$i', 'name': 'Plan $i', 'duration_weeks': 8}
      ]);
      await library(tester, what: 'Plan 1');
      server.seed('workout_programs', memberA, [
        {'id': 'prog-2', 'name': 'Plan two', 'duration_weeks': 8}
      ]);
      await tester.fling(find.byType(ListView), const Offset(0, 1500), 3000);
      await pumpUntil(tester, () => seen(find.text('Plan two')),
          what: 'refreshed', step: const Duration(milliseconds: 50));
      await frames(tester);
      await unmount(tester);
    });

    testWidgets('control: a coach with no programs is told so, not failed',
        (tester) async {
      server.seed('workout_programs', memberA, []);
      await library(tester, what: null);
      await pumpUntil(tester,
          () => seen(find.textContaining('No programs yet')), what: 'none');
      expect(find.textContaining("Couldn't load"), findsNothing);
      await unmount(tester);
    });

    testWidgets('the failed-refresh notice does not overflow at 2x on a small '
        'phone', (tester) async {
      await library(tester);
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      server.fails.add('$_lists:$memberA');
      c.invalidate(myProgramsProvider);
      await pumpUntil(tester,
          () => seen(find.text("Couldn't load your programs")), what: 'said');
      await frames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Plan of A'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('the builder', () {
    for (final next in [memberB, null]) {
      final who = next == null ? 'A signs out' : 'B signs in';
      for (final (state, drawn) in [
        ('settled', true),
        ('settled', false),
        ('being refreshed', true),
        ('being refreshed', false),
        ('invalidated before the flush', false),
        ('failed', true),
      ]) {
        testWidgets("A's, $state, as $who"
            "${drawn ? '' : ', and the first frame after'}: none of it",
            (tester) async {
          await builder(tester);
          if (state == 'being refreshed' || state == 'failed') {
            final hold = server.holds['$_days:$memberA'] = Completer<void>();
            if (state == 'failed') {
              server.fails.add('$_days:$memberA');
              hold.complete();
            }
            c.invalidate(programWorkoutsProvider('prog-1'));
            await pumpUntil(tester, () => server.count('$_days:$memberA') == 2,
                what: "A's refresh");
            await frames(tester, 2);
          }
          server.holds['$_days:$memberB'] = Completer<void>();
          await switchTo(tester, next);
          if (state.startsWith('invalidated')) {
            c.invalidate(programWorkoutsProvider('prog-1'));
          }
          if (drawn) {
            await pumpUntil(tester,
                () => c.read(currentUserProvider)?.id == next, what: who);
          }
          for (var i = 0; i < 8; i++) {
            await tester.pump(drawn ? const Duration(milliseconds: 100) : null);
            nothingOfA('frame $i');
            expect(find.textContaining("Couldn't load"), findsNothing);
            expect(find.text('Add Workout'), findsNothing,
                reason: "A's actions");
            expect(find.byType(BackButton), findsOneWidget,
                reason: 'a way back');
          }
          for (final h in server.holds.values) {
            if (!h.isCompleted) h.complete();
          }
          await frames(tester, 10);
          nothingOfA('answered');
          await unmount(tester);
        });
      }
    }

    testWidgets('A back in: the page is theirs again', (tester) async {
      await builder(tester);
      await become(tester, memberB);
      nothingOfA('B');
      await become(tester, memberA);
      await pumpUntil(tester, () => seen(find.text('Session of A')), what: 'A');
      expect(find.text('Plan of A'), findsOneWidget);
      await unmount(tester);
    });

    // The family outlives the page: B opens the same program.
    for (final fate in ['invalidated before the flush', 'pending', 'failed']) {
      testWidgets("B opens a program A had open, B's workouts read $fate: none "
          "of A's", (tester) async {
        await builder(tester);
        await tester.tap(find.byType(BackButton));
        await frames(tester);
        final hold = server.holds['$_days:$memberB'] = Completer<void>();
        if (fate == 'failed') server.fails.add('$_days:$memberB');
        await switchTo(tester, memberB);
        if (fate.startsWith('invalidated')) {
          c.invalidate(programWorkoutsProvider('prog-1'));
        }
        await pumpUntil(tester, () => seen(find.text('Plan of B')), what: 'B');
        await tester.tap(find.text('Plan of B'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          nothingOfA('frame $i');
        }
        hold.complete();
        if (fate == 'failed') {
          await pumpUntil(
              tester,
              () => seen(find.text("Couldn't load this program's workouts")),
              what: 'said');
          nothingOfA('failed');
          expect(find.textContaining('No workouts yet'), findsNothing);
        } else {
          await pumpUntil(tester, () => seen(find.text('Session of B')),
              what: "B's own");
        }
        await unmount(tester);
      });
    }

    testWidgets('control: a refreshed token re-reads nothing; a failed refresh '
        'keeps the workouts and says so; its retry reads them', (tester) async {
      await builder(tester);
      await tokenRefreshed(tester);
      expect(server.count('$_days:$memberA'), 1);
      expect(find.text('Session of A'), findsOneWidget);
      server.fails.add('$_days:$memberA');
      c.invalidate(programWorkoutsProvider('prog-1'));
      await pumpUntil(
          tester,
          () => seen(find.text("Couldn't load this program's workouts")),
          what: 'said');
      expect(find.text('Session of A'), findsOneWidget, reason: 'kept');
      server.fails.clear();
      press(tester, 'Try again')();
      await pumpUntil(
          tester,
          () => !seen(find.text("Couldn't load this program's workouts")),
          what: 'read');
      expect(find.text('Session of A'), findsOneWidget);
      await unmount(tester);
    });
  });

  // ── what opens something ──────────────────────────────────────────────────

  Future<void> addSheet(WidgetTester tester) async {
    await builder(tester);
    await tester.tap(find.text('Add Workout'));
    await frames(tester);
    await tester.enterText(field('e.g. Upper Body Push'), 'TYPED BY A');
    await frames(tester, 1);
  }

  Future<void> exerciseDialog(WidgetTester tester) async {
    await addSheet(tester);
    await tester.tap(find.text('Add').last);
    await frames(tester);
    await tester.enterText(field('e.g. Bench Press'), 'MOVE OF A');
    await frames(tester, 1);
  }

  // name → (opened on, the tap, what it would draw, what is recorded)
  final openers = <String,
      (
        Future<void> Function(WidgetTester),
        VoidCallback Function(WidgetTester),
        String,
        String
      )>{
    'New Program': (
      (t) => library(t),
      (t) => fab(t, 'New Program'),
      'Create & build',
      'ProgramLibrary._createProgram'
    ),
    'a program card': (
      (t) => library(t),
      (t) => t
          .widget<InkWell>(find
              .ancestor(
                  of: find.text('Plan of A'), matching: find.byType(InkWell))
              .first)
          .onTap!,
      'Add Workout',
      'ProgramLibrary.openProgram'
    ),
    'Add Workout': (
      builder,
      (t) => fab(t, 'Add Workout'),
      'Save workout',
      'ProgramBuilder._addWorkout'
    ),
    'a workout\'s Edit': (
      builder,
      (t) => () => pick(t, Icons.more_horiz, 'edit'),
      'Save workout',
      'ProgramBuilder._editWorkout'
    ),
    'Delete program': (
      builder,
      (t) => () => pick(t, Icons.more_vert, 'delete'),
      'Delete program?',
      'ProgramBuilder._deleteProgram'
    ),
    "the sheet's Add exercise": (
      addSheet,
      (t) => press(t, 'Add'),
      'Exercise name',
      'WorkoutEditorSheet._addExercise'
    ),
  };

  for (final e in openers.entries) {
    final (ready, tapOf, drawn, origin) = e.value;
    for (final next in [memberB, null]) {
      final who = next == null ? 'A signed out' : 'B signed in';
      testWidgets('${e.key}, tapped after $who and before any frame: opens '
          'nothing, and it is recorded', (tester) async {
        await ready(tester);
        final tap = tapOf(tester);
        await switchTo(tester, next);
        tap();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text(drawn), findsNothing,
              reason: "THE defect: A's ${e.key} opened for them (frame $i)");
          nothingOfA('frame $i');
        }
        expect(reported.map((f) => f.origin), contains(origin));
        expect(server.writes, isEmpty);
        await unmount(tester);
      });

      testWidgets('${e.key}, tapped by A, and $who before its first frame: it '
          'is never drawn', (tester) async {
        await ready(tester);
        tapOf(tester)();
        await switchTo(tester, next);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text(drawn), findsNothing, reason: 'frame $i');
          nothingOfA('frame $i');
        }
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('control: ${e.key} opens for A, whose token was refreshed',
        (tester) async {
      await ready(tester);
      await tokenRefreshed(tester);
      tapOf(tester)();
      await pumpUntil(tester, () => seen(find.text(drawn)), what: drawn);
      await unmount(tester);
    });
  }

  testWidgets('New Program, built and tapped with nobody signed in: opens '
      'nothing, and it is recorded', (tester) async {
    await library(tester);
    await become(tester, null);
    final tap = fab(tester, 'New Program');
    reported.clear();
    tap();
    await frames(tester);
    expect(find.text('Create & build'), findsNothing);
    expect(reported.map((f) => f.origin),
        contains('ProgramLibrary._createProgram'));
    await unmount(tester);
  });

  // ── what is open ──────────────────────────────────────────────────────────

  Future<void> metaSheet(WidgetTester tester) async {
    await library(tester);
    await tester.tap(find.text('New Program'));
    await frames(tester);
    await tester.enterText(field('e.g. 12-Week Hypertrophy'), 'TYPED BY A');
    await frames(tester, 1);
  }

  Future<void> editSheet(WidgetTester tester) async {
    await builder(tester);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await frames(tester);
    await tester.tap(find.text('Edit'));
    await frames(tester);
  }

  Future<void> workoutMenu(WidgetTester tester) async {
    await builder(tester);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await frames(tester);
  }

  Future<void> programMenu(WidgetTester tester) async {
    await builder(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await frames(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    await programMenu(tester);
    await tester.tap(find.text('Delete program'));
    await frames(tester);
  }

  final open = <String, (Future<void> Function(WidgetTester), List<String>)>{
    'the New Program sheet': (metaSheet, ['Create & build', 'TYPED BY A']),
    'the Add Workout sheet': (addSheet, ['Save workout', 'TYPED BY A']),
    'the Edit Workout sheet': (editSheet, ['Save workout', 'Session of A']),
    'the exercise dialog, over its sheet': (
      exerciseDialog,
      ['Exercise name', 'MOVE OF A', 'Save workout']
    ),
    "a workout's menu": (workoutMenu, ['Edit', 'Delete']),
    "the program's menu": (programMenu, ['Delete program']),
    'the delete dialog': (confirm, ['Delete program?', 'Delete']),
  };
  for (final e in open.entries) {
    final (ready, texts) = e.value;
    for (final next in [memberB, null]) {
      testWidgets(
          '${e.key} is not drawn once ${next == null ? 'A signed out' : 'B signed in'}, and it closes',
          (tester) async {
        await ready(tester);
        for (final t in texts) {
          expect(find.text(t), findsWidgets, reason: 'premise');
        }
        await switchTo(tester, next);
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          for (final t in texts) {
            expect(find.text(t), findsNothing,
                reason: "THE defect: A's was drawn for them: $t (frame $i)");
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing,
            reason: 'the route closed');
        expect(tester.takeException(), isNull);
        expect(server.writes, isEmpty);
        await unmount(tester);
      });
    }

    testWidgets('control: ${e.key} stays through a refreshed token',
        (tester) async {
      await ready(tester);
      await tokenRefreshed(tester);
      for (final t in texts) {
        expect(find.text(t), findsWidgets);
      }
      await unmount(tester);
    });
  }

  testWidgets("the exercise dialog's Add, tapped after B signed in and before "
      "any frame: added to nothing, and it is recorded", (tester) async {
    await exerciseDialog(tester);
    final add = press(tester, 'Add');
    await switchTo(tester, memberB);
    add();
    await tester.pump();
    expect(find.textContaining('MOVE OF A'), findsNothing);
    expect(reported.map((f) => f.origin),
        contains('WorkoutEditorSheet._addExercise'));
    await frames(tester, 8);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('control: swiping the sheet away writes nothing and says nothing',
      (tester) async {
    await addSheet(tester);
    await tester.tapAt(const Offset(5, 5));
    await frames(tester);
    expect(find.text('Save workout'), findsNothing);
    expect(server.writes, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Session of A'), findsOneWidget);
    await unmount(tester);
  });

  // ── the writes ────────────────────────────────────────────────────────────

  // name → (ready, the tap, METHOD table, origin, what a failure says)
  final writes = <String,
      (
        Future<void> Function(WidgetTester),
        VoidCallback Function(WidgetTester),
        String,
        String,
        String
      )>{
    'create a program': (
      metaSheet,
      (t) => press(t, 'Create & build'),
      'POST workout_programs',
      'ProgramLibrary._createProgram',
      "Couldn't create the program"
    ),
    'add a workout': (
      addSheet,
      (t) => press(t, 'Save workout'),
      'POST program_workouts',
      'ProgramBuilder._addWorkout',
      "Couldn't save the workout"
    ),
    'edit a workout': (
      editSheet,
      (t) => press(t, 'Save workout'),
      'PATCH program_workouts',
      'ProgramBuilder._editWorkout',
      "Couldn't save the workout"
    ),
    'delete a workout': (
      builder,
      (t) => () => pick(t, Icons.more_horiz, 'delete'),
      'DELETE program_workouts',
      'ProgramBuilder._deleteWorkout',
      "Couldn't delete the workout"
    ),
    'delete the program': (
      confirm,
      (t) => press(t, 'Delete'),
      'DELETE workout_programs',
      'ProgramBuilder._deleteProgram',
      "Couldn't delete the program"
    ),
  };

  for (final e in writes.entries) {
    final (ready, tapOf, request, origin, failure) = e.value;
    List<CoachWrite> sent() => server.writes;

    for (final next in [memberB, null]) {
      final who = next == null ? 'A signed out' : 'B signed in';
      testWidgets('${e.key}, tapped after $who and before any frame: nothing is '
          'sent, and it is recorded', (tester) async {
        await ready(tester);
        final tap = tapOf(tester);
        await switchTo(tester, next);
        tap();
        await frames(tester, 10);
        expect(sent(), isEmpty, reason: "THE defect: A's write went as $next");
        expect(reported.map((f) => f.origin), contains(origin));
        expect(find.byType(SnackBar), findsNothing);
        nothingOfA('after');
        await unmount(tester);
      });
    }

    for (final (fate, drawn) in [
      ('done', true),
      ('done', false),
      ('refused', true),
      ('refused', false),
    ]) {
      testWidgets("${e.key}, in flight as B signs in, then $fate"
          "${drawn ? '' : ' before any frame'}: A's one write, nothing said to "
          'B, nothing opened, closed or re-read for it', (tester) async {
        await ready(tester);
        final hold = server.holds['$request:$memberA'] = Completer<void>();
        tapOf(tester)();
        await pumpUntil(tester, () => sent().isNotEmpty, what: 'sent');
        if (fate == 'refused') server.fails.add('$request:$memberA');
        if (drawn) {
          await become(tester, memberB);
          await pumpUntil(tester, () => !c.read(myProgramsProvider).isLoading,
              what: "B's list");
        } else {
          await switchTo(tester, memberB);
        }
        final pages = find.byType(BackButton).evaluate().length;
        hold.complete();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await frames(tester, 10);
        expect(sent().map((w) => w.who), [memberA]);
        expect(find.byType(SnackBar), findsNothing,
            reason: "THE defect: A's write was reported to B");
        expect(find.textContaining(failure), findsNothing);
        expect(reported.map((f) => f.origin), contains(origin));
        expect(find.byType(BackButton).evaluate().length, pages,
            reason: 'a page was pushed or popped under B');
        expect(server.count('$_lists:$memberB'), 1,
            reason: "B's list is read for B, once");
        nothingOfA('after');
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets("control: ${e.key}, A's token refreshed while it is in flight: "
        'sent once as A, and acted on', (tester) async {
      await ready(tester);
      final hold = server.holds['$request:$memberA'] = Completer<void>();
      tapOf(tester)();
      await pumpUntil(tester, () => sent().isNotEmpty, what: 'sent');
      await tokenRefreshed(tester);
      final lists = server.count('$_lists:$memberA');
      hold.complete();
      await pumpUntil(tester, () => server.count('$_lists:$memberA') > lists,
          what: 'the list is read again');
      await frames(tester);
      expect(sent().single.who, memberA);
      expect('${sent().single.method} ${sent().single.path.split('/').last}',
          request);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BackButton),
          e.key == 'delete the program' ? findsNothing : findsOneWidget,
          reason: 'create opens the builder; delete leaves it');
      await unmount(tester);
    });

    for (final next in [memberB, null]) {
      testWidgets('${e.key} refused: A is told; once '
          '${next == null ? 'A signed out' : 'B signed in'} it is not in the '
          'next frame', (tester) async {
        await ready(tester);
        server.fails.add('$request:$memberA');
        tapOf(tester)();
        await pumpUntil(tester, () => seen(find.textContaining(failure)),
            what: 'A is told');
        expect(find.textContaining('SECRET_TABLE'), findsNothing);
        await switchTo(tester, next);
        await tester.pump();
        expect(find.textContaining(failure), findsNothing,
            reason: "what A was told was left up");
        await unmount(tester);
      });
    }
  }
}
