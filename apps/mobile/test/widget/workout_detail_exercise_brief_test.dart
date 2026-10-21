import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_detail_screen.dart';

/// FIT-016 · the session row's control, on screen.
///
/// `test/unit/exercise_brief_test.dart` pins the rules. This pins that the
/// widget obeys them — specifically the two claims the rules cannot make on
/// their own:
///
///   1. a row with content exposes a real `tap` ACTION, not just `button:
///      true`. `excludeSemantics: true` drops the child's actions along with
///      its labels, which is how F-20 shipped a back button reading
///      `44x44 tap=false label="Back"`. The assertion below reads
///      `SemanticsAction.tap` out of the tree, so removing `onTap:` from the
///      `Semantics` kills it;
///   2. a row with nothing behind it exposes NO button and draws NO info icon.
///
/// Both are asserted against the semantics tree rather than against rendered
/// text, because text presence would pass whether or not anything is wired.

Exercise _ex(String id, String name,
        {String description = '', List<String> instructions = const []}) =>
    Exercise(
      id: id,
      name: name,
      category: 'Strength',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      difficulty: 'Intermediate',
      description: description,
      instructions: instructions,
    );

WorkoutExercise _we(Exercise e, {String? notes}) => WorkoutExercise(
      exercise: e,
      notes: notes,
      sets: List.generate(
        4,
        (i) => WorkoutSet(
            setNumber: i + 1, reps: 6, weightKg: 65, restSeconds: 120),
      ),
    );

Workout _workout(List<WorkoutExercise> exercises) => Workout(
      id: 'w1',
      title: 'Lower body — strength',
      description: '',
      estimatedDuration: 48,
      difficulty: 'Intermediate',
      category: 'Strength',
      coachName: 'Nadia',
      exercises: exercises,
    );

Future<void> _pump(WidgetTester tester, Workout w) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [selectedWorkoutProvider.overrideWith((ref) => w)],
    child: const MaterialApp(home: WorkoutDetailScreen()),
  ));
  await tester.pumpAndSettle();
}

SemanticsData _dataFor(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  return node.getSemanticsData();
}

void main() {
  testWidgets('a row with instructions is a button AND carries a tap action',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
        tester,
        _workout([
          _we(_ex('e1', 'Back squat',
              instructions: ['Set the bar on your back.', 'Descend.'])),
        ]));

    final data = _dataFor(tester, '1 Back squat 4 × 6 · 65 kg · rest 120 s');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: 'a row that announces itself a button must respond to one');
    expect(data.hint, 'Shows form and instructions');

    handle.dispose();
  });

  testWidgets('tapping the row opens the brief, with the steps in it',
      (tester) async {
    await _pump(
        tester,
        _workout([
          _we(
            _ex('e1', 'Back squat',
                description: 'A knee-dominant pattern.',
                instructions: ['Set the bar on your back.', 'Descend.']),
            notes: "Keep last week's loads.",
          ),
        ]));

    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('Back squat'));
    await tester.pumpAndSettle();

    // The coach's note, the library prose and the ordered steps — all of it,
    // and the package's own dismissal word.
    expect(find.text("Keep last week's loads."), findsOneWidget);
    expect(find.text('A knee-dominant pattern.'), findsOneWidget);
    expect(find.text('Set the bar on your back.'), findsOneWidget);
    expect(find.text('Descend.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Done dismisses it', (tester) async {
    await _pump(
        tester,
        _workout([
          _we(_ex('e1', 'Back squat', instructions: ['Descend.'])),
        ]));

    await tester.tap(find.text('Back squat'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
  });

  testWidgets(
      'a movement with no form and no instructions offers no control at all',
      (tester) async {
    final handle = tester.ensureSemantics();
    // Equipment and muscle group ARE set — the case that would silently
    // restore the inert control if `hasContent` counted metadata.
    await _pump(tester, _workout([_we(_ex('e1', 'Back squat'))]));

    final data = _dataFor(tester, '1 Back squat 4 × 6 · 65 kg · rest 120 s');
    expect(data.hasFlag(SemanticsFlag.isButton), isFalse,
        reason: 'nothing to open, so nothing may claim to be a button');
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    expect(data.hint, isEmpty);

    // …and the icon that promises it is not drawn either.
    expect(find.byIcon(Icons.info_outline), findsNothing);

    handle.dispose();
  });

  testWidgets('rows are independent — one row\'s emptiness is not the other\'s',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
        tester,
        _workout([
          _we(_ex('e1', 'Back squat')),
          _we(_ex('e2', 'Romanian deadlift', instructions: ['Hinge.'])),
        ]));

    expect(
        _dataFor(tester, '1 Back squat 4 × 6 · 65 kg · rest 120 s')
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(
        _dataFor(tester, '2 Romanian deadlift 4 × 6 · 65 kg · rest 120 s')
            .hasAction(SemanticsAction.tap),
        isTrue);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    handle.dispose();
  });
}
