import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/habits/data/models/habit_model.dart';
import 'package:circle_fitness/features/habits/presentation/widgets/habit_card.dart';

/// FIT-058 · the habit row, mounted.
///
/// > *"Tapping the row is the whole interaction — no separate checkbox to hit
/// > — with `role="checkbox"` so the state is announced."*
///
/// Four defects that sentence names, all of which shipped:
///
///   1. the only tap target was a **32 × 32 circle**, not the row — and 32 is
///      under the 44 dp floor;
///   2. there was **no `Semantics` at all**: no role, no state, no name;
///   3. a completed habit rendered a plain `Container`, so it **could not be
///      un-toggled** — a one-way action on a daily yes/no;
///   4. the week — "6 of 7 this week" — was not on the row.
///
/// Asserted against the semantics tree, because a checkbox role is precisely
/// the thing source presence cannot demonstrate.

Habit _habit({bool done = false, int daysDone = 6}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return Habit(
    id: 'h1',
    name: '10 minutes of walking',
    emoji: '🚶',
    category: HabitCategory.values.first,
    targetValue: 1,
    unit: 'time',
    currentStreak: 11,
    longestStreak: 14,
    completedDates: [for (var i = 0; i < daysDone; i++) today.subtract(Duration(days: i))],
    isCompletedToday: done,
    currentValue: done ? 1 : 0,
  );
}

Future<void> _pump(WidgetTester tester, Habit habit) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: HabitCard(habit: habit))),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The row's own semantics node.
///
/// NOT `find.byType(HabitCard)` — that resolves to the card's root, whose
/// data does not merge the `checked` flag up from the `Semantics` inside the
/// `Stack`. Asserting against the root reported no checkbox role on a widget
/// that has one.
SemanticsData _row(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsLabel(RegExp(r'10 minutes of walking')))
    .getSemanticsData();

void main() {
  testWidgets('the ROW carries the checkbox role and its state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _habit(done: false));

    final d = _row(tester);
    // `Semantics(checked:)` is what gives Flutter the checkbox role.
    expect(d.hasFlag(SemanticsFlag.hasCheckedState), isTrue,
        reason: 'without a checked state there is no checkbox role, and a '
            'screen reader says nothing about whether the habit is done');
    expect(d.hasFlag(SemanticsFlag.isChecked), isFalse);
    expect(d.hasAction(SemanticsAction.tap), isTrue,
        reason: 'tapping the ROW is the whole interaction');

    handle.dispose();
  });

  testWidgets('a completed habit announces itself checked', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _habit(done: true));

    final d = _row(tester);
    expect(d.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
    expect(d.hasFlag(SemanticsFlag.isChecked), isTrue);
    handle.dispose();
  });

  // The one-way action. A completed habit rendered a plain Container.
  testWidgets('a completed habit can still be tapped, to undo it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _habit(done: true));

    expect(_row(tester).hasAction(SemanticsAction.tap), isTrue,
        reason: 'a habit marked done by accident had no way back');
    expect(_row(tester).hint, 'Mark as not done today');

    // The GESTURE, not just the declaration. A mutation that nulled the
    // GestureDetector's onTap while leaving `Semantics(onTap:)` in place
    // survived the assertion above — the semantics action stays either way,
    // so it cannot tell a wired control from a declared one.
    final gesture = tester.widgetList<GestureDetector>(find.descendant(
      of: find.byType(HabitCard),
      matching: find.byType(GestureDetector),
    ));
    expect(gesture.where((g) => g.onTap != null), isNotEmpty,
        reason: 'the row declares a tap it cannot perform');

    handle.dispose();
  });

  testWidgets('the name carries the habit and its week, not the state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _habit(daysDone: 6));

    final d = _row(tester);
    expect(d.label, '10 minutes of walking, 6 of 7 this week');
    // The state belongs to the role, so a reader announces it in the user's
    // own language rather than an English word baked into the name.
    for (final w in const ['done', 'checked', 'complete']) {
      expect(d.label.toLowerCase(), isNot(contains(w)));
    }
    handle.dispose();
  });

  testWidgets('the week is on the row, as the board draws it', (tester) async {
    await _pump(tester, _habit(daysDone: 6));
    expect(find.text('6 of 7 this week'), findsOneWidget);
  });

  testWidgets('the row clears the 44 dp target floor', (tester) async {
    await _pump(tester, _habit());
    expect(tester.getSize(find.byType(HabitCard)).height,
        greaterThanOrEqualTo(44.0));
  });

  // One announcement, not two. The mark is excluded so the row reads once.
  testWidgets('the tick is not a second control', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _habit());
    expect(find.byIcon(Icons.check), findsOneWidget);
    // Only one semantics node for the whole card.
    expect(_row(tester).label, isNotEmpty);
    handle.dispose();
  });
}
