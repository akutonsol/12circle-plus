import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/domain/session_complete.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

/// FIT-018 · "Session complete", mounted.
///
/// `test/unit/session_complete_test.dart` pins the rules. This pins that the
/// four declared interactions — `Easy`, `Right`, `Hard`, `Done` — are on
/// screen, named, mutually exclusive and wired, which is the part the anchor
/// was carried as having for as long as the metric matched one-word labels as
/// substrings.

Future<FeedbackDelivery> _ok({
  required int rating,
  required int energy,
  required int difficulty,
  required String notes,
}) async =>
    FeedbackDelivery.saved;

Future<void> _pump(
  WidgetTester tester, {
  String title = 'Lower body — strength',
  int elapsedSeconds = 51 * 60,
  int setsLogged = 18,
  double volumeKg = 4200,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WorkoutCompleteDialog(
            title: title,
            duration: '51:00',
            calories: 400,
            elapsedSeconds: elapsedSeconds,
            setsLogged: setsLogged,
            volumeKg: volumeKg,
            onDone: () {},
            submit: _ok,
          ),
        ),
      ),
    ));

void main() {
  testWidgets('the title is the board\'s, and not celebratory', (tester) async {
    await _pump(tester);
    expect(find.text('Lower body, done.'), findsOneWidget);
    // "rewarding, not celebratory ... No confetti."
    expect(find.text('Workout Complete!'), findsNothing);
  });

  testWidgets('the three figures come from what was logged', (tester) async {
    await _pump(tester);
    for (final v in const ['51', '18', '4.2']) {
      expect(find.text(v), findsOneWidget);
    }
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Sets logged'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
  });

  testWidgets('a bodyweight session shows two figures, not a zero',
      (tester) async {
    await _pump(tester, volumeKg: 0);
    expect(find.text('Volume'), findsNothing);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('Sets logged'), findsOneWidget);
  });

  testWidgets('the effort question offers the board\'s three answers',
      (tester) async {
    await _pump(tester);
    expect(find.text(effortQuestion), findsOneWidget);
    for (final w in const ['Easy', 'Right', 'Hard']) {
      expect(find.text(w), findsOneWidget);
    }
    // The 1–5 row it replaces asked the same thing as a score.
    expect(find.text('Difficulty'), findsNothing);
  });

  testWidgets('the answers are named, exclusive and selectable',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    for (final e in SessionEffort.values) {
      final d = tester
          .getSemantics(find.bySemanticsLabel(e.label))
          .getSemanticsData();
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: e.label);
      expect(d.hasAction(SemanticsAction.tap), isTrue,
          reason: '${e.label} announces a button it cannot perform (F-20)');
      expect(d.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue,
          reason: 'one question, one answer');
      expect(d.hasFlag(SemanticsFlag.isSelected), isFalse,
          reason: 'nothing is chosen until the client chooses');
    }
    handle.dispose();
  });

  testWidgets('choosing one selects it and deselects the others',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    await tester.tap(find.text('Hard'));
    await tester.pumpAndSettle();

    bool selected(String label) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .getSemanticsData()
        .hasFlag(SemanticsFlag.isSelected);

    expect(selected('Hard'), isTrue);
    expect(selected('Easy'), isFalse);
    expect(selected('Right'), isFalse);

    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    expect(selected('Easy'), isTrue);
    expect(selected('Hard'), isFalse);

    handle.dispose();
  });

  // The board's primary action. `Done` measured PRESENT while the button said
  // `Submit`, because `sessionDoneLabel` is a const in the same resolved file
  // set — a false positive this programme introduced itself, caught by the
  // device test.
  testWidgets('the primary action is the board\'s word, on screen',
      (tester) async {
    await _pump(tester);
    expect(find.text(sessionDoneLabel), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('each answer clears the 44 dp target floor', (tester) async {
    await _pump(tester);
    for (final e in SessionEffort.values) {
      expect(tester.getSize(find.bySemanticsLabel(e.label)).height,
          greaterThanOrEqualTo(44.0),
          reason: e.label);
    }
  });
}
