import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/widgets/week_row_tile.dart';

/// FIT-014 · a "This week" row, on screen.
///
/// `test/unit/week_row_test.dart` pins what the row says. This pins what it
/// does — the part the rules cannot assert:
///
///   * the board draws every row as `<button class="tap row">`. They shipped
///     as `Semantics(button: true)` with no action wired, announcing an
///     affordance to a screen reader and to the eye and answering neither;
///   * tapping must select THAT workout and open `/workout-detail`. Selecting
///     the wrong one is F-20's defect, which is why the provider's value is
///     read back rather than only the route.
///
/// Asserted against the semantics tree and the router, never against text
/// presence — text would pass whether or not anything were wired.

/// A date N days from today, at midnight.
///
/// `WeekRowTile` reads the real clock — correctly, that is what production
/// does — so the fixtures have to be relative to it. They were fixed dates
/// (`DateTime(2026, 9, 24)`), which made this file **pass on a Wednesday and
/// fail on a Thursday**: the 24th stopped being "Thursday" and became "today",
/// so the chip read `Now` instead of `THU`.
///
/// A test whose result depends on the day it runs is not a test.
DateTime _daysFromToday(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: days));
}

/// The next occurrence of `weekday` that is NOT today, so a fixture meant to
/// read as a named day never collides with `Today`.
DateTime _otherWeekday(int weekday) {
  var d = _daysFromToday(1);
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

const _dayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

Workout _w({
  String title = 'Conditioning',
  bool completed = false,
  DateTime? on,
  int minutes = 30,
}) =>
    Workout(
      id: title,
      title: title,
      description: '',
      estimatedDuration: minutes,
      difficulty: 'Intermediate',
      category: 'Strength',
      isCompleted: completed,
      scheduledDate: on,
      exercises: [
        WorkoutExercise(
          exercise: Exercise(
            id: 'e1',
            name: 'Back squat',
            category: 'Strength',
            muscleGroup: 'Legs',
            equipment: 'Barbell',
            difficulty: 'Intermediate',
            description: '',
            instructions: const [],
          ),
          sets: const [WorkoutSet(setNumber: 1, reps: 6)],
        ),
      ],
    );

/// A router with a real destination, so "it navigated" is observable rather
/// than inferred from a callback.
Future<ProviderContainer> _pump(WidgetTester tester, List<Workout> rows) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/train',
    routes: [
      GoRoute(
        path: '/train',
        builder: (_, __) => Scaffold(
          body: ListView(
              children: [for (final w in rows) WeekRowTile(workout: w)]),
        ),
      ),
      GoRoute(
        path: '/workout-detail',
        builder: (_, __) => const Scaffold(body: Text('DETAIL')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a row is a button and carries a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, [_w(on: DateTime.now().add(const Duration(days: 1)))]);

    final data = tester
        .getSemantics(find.byType(WeekRowTile))
        .getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: 'the board draws a <button>; it must respond like one');
    expect(data.label, contains('Conditioning'));

    handle.dispose();
  });

  testWidgets('tapping opens /workout-detail with THAT workout selected',
      (tester) async {
    final a = _w(title: 'Conditioning', on: _daysFromToday(1));
    final b = _w(title: 'Upper body — pull', on: _daysFromToday(3));
    final container = await _pump(tester, [a, b]);

    expect(container.read(selectedWorkoutProvider), isNull);

    // The SECOND row — selecting the first would pass a test that only
    // checked "something was selected".
    await tester.tap(find.text('Upper body — pull'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL'), findsOneWidget);
    expect(container.read(selectedWorkoutProvider)?.title, 'Upper body — pull');
  });

  testWidgets('a completed row still opens for review', (tester) async {
    final done =
        _w(title: 'Upper body — push', completed: true, on: _daysFromToday(-2));
    final container = await _pump(tester, [done]);

    await tester.tap(find.text('Upper body — push'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL'), findsOneWidget);
    expect(container.read(selectedWorkoutProvider)?.title, 'Upper body — push');
  });

  testWidgets('today\'s chip is a pill reading "Now", not an uppercased mic',
      (tester) async {
    await _pump(tester, [_w(title: 'Lower body — strength', on: DateTime.now(), minutes: 48)]);

    // `.pill` carries no `text-transform`.
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('NOW'), findsNothing);
    // And the detail says "Today", not a weekday.
    expect(find.text('Today · 48 min'), findsOneWidget);
  });

  testWidgets('the other chips ARE uppercased, and the day is spelled out',
      (tester) async {
    // Derived from the fixtures rather than hardcoded. The previous version
    // asserted `THU` / `Thursday` against a fixed `DateTime(2026, 9, 24)` and
    // broke the day that date became today.
    final past = _daysFromToday(-2);
    final future = _otherWeekday(DateTime.thursday);

    await _pump(tester, [
      _w(title: 'Upper body — push', completed: true, on: past, minutes: 44),
      _w(title: 'Conditioning', on: future, minutes: 30),
    ]);

    expect(find.text('DONE'), findsOneWidget);
    expect(find.text(_dayAbbr[future.weekday - 1]), findsOneWidget);
    // The defect: an abbreviated day beside a chip saying the same word.
    expect(find.text('${_dayNames[past.weekday - 1]} · 44 min'),
        findsOneWidget);
    expect(find.text('${_dayNames[future.weekday - 1]} · 30 min'),
        findsOneWidget);
    expect(
        find.text(
            '${_dayAbbr[future.weekday - 1].substring(0, 1)}'
            '${_dayAbbr[future.weekday - 1].substring(1).toLowerCase()}'
            ' · 30 min'),
        findsNothing,
        reason: 'the detail must spell the day out, not abbreviate it');
  });

  // The board marks an upcoming session with a hollow ring
  // (`box-shadow: inset 0 0 0 1px var(--dim)`); the rows drew nothing at all,
  // so an upcoming session had no marker. Today's is a FILLED violet dot —
  // the two must not collapse into each other.
  BoxDecoration? _dot(WidgetTester tester, String title) {
    final containers = tester
        .widgetList<Container>(find.descendant(
          of: find.ancestor(
              of: find.text(title), matching: find.byType(WeekRowTile)),
          matching: find.byType(Container),
        ))
        .where((c) =>
            (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
    return containers.isEmpty
        ? null
        : containers.first.decoration as BoxDecoration;
  }

  testWidgets('an upcoming session draws a ring; today draws a fill',
      (tester) async {
    await _pump(tester, [
      _w(title: 'Conditioning', on: _daysFromToday(1)),
      _w(title: 'Lower body — strength', on: DateTime.now()),
    ]);

    final upcoming = _dot(tester, 'Conditioning');
    expect(upcoming, isNotNull, reason: 'an upcoming session must be marked');
    expect(upcoming!.border, isNotNull, reason: 'a ring, not a fill');
    expect(upcoming.color, isNull);

    final today = _dot(tester, 'Lower body — strength');
    expect(today, isNotNull);
    expect(today!.color, isNotNull, reason: 'a fill, not a ring');
    expect(today.border, isNull);
  });

  testWidgets('an undated row shows no chip and claims no day', (tester) async {
    await _pump(tester, [_w(title: 'Conditioning', minutes: 30)]);

    expect(find.text('30 min'), findsOneWidget);
    final data =
        tester.getSemantics(find.byType(WeekRowTile)).getSemanticsData();
    expect(data.label, 'Conditioning 30 min');
  });
}
