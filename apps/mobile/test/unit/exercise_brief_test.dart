import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/exercise_brief.dart';

/// FIT-016 · the rules behind the session row's info control.
///
/// The defect these pin: the row announced `button: true` to assistive
/// technology and drew an info icon, with **no action wired to either**. The
/// board declares the rows as buttons and its annotation says the icon "opens
/// form and instructions", so the affordance was right and the wiring was
/// missing — and a control that exists for the eye and for the screen reader
/// and responds to neither is exactly the false-affordance class.
///
/// The second half of the fix is the harder half: the control must NOT exist
/// when the data behind it is empty. `hasContent` is what decides that, so it
/// is tested against every shape of emptiness, including the one that looks
/// like content and is not.

Exercise _ex({
  String name = 'Back squat',
  String description = '',
  List<String> instructions = const [],
  String equipment = '',
  String muscleGroup = '',
}) =>
    Exercise(
      id: 'e1',
      name: name,
      category: 'Strength',
      muscleGroup: muscleGroup,
      equipment: equipment,
      difficulty: 'Intermediate',
      description: description,
      instructions: instructions,
    );

WorkoutExercise _we({
  Exercise? exercise,
  String? notes,
  int sets = 4,
  int reps = 6,
  double? kg = 65,
  int? rest = 120,
}) =>
    WorkoutExercise(
      exercise: exercise ?? _ex(),
      notes: notes,
      sets: List.generate(
        sets,
        (i) => WorkoutSet(
            setNumber: i + 1, reps: reps, weightKg: kg, restSeconds: rest),
      ),
    );

void main() {
  group('prescriptionLine — the board\'s own line shape', () {
    test('full prescription reads exactly as FIT-016 draws it', () {
      expect(prescriptionLine(_we()), '4 × 6 · 65 kg · rest 120 s');
      expect(
        prescriptionLine(_we(
            exercise: _ex(name: 'Romanian deadlift'),
            sets: 4,
            reps: 8,
            kg: 62.5,
            rest: 90)),
        '4 × 8 · 62.5 kg · rest 90 s',
      );
    });

    test('an absent load or rest is omitted, never rendered as 0', () {
      expect(prescriptionLine(_we(kg: null)), '4 × 6 · rest 120 s');
      expect(prescriptionLine(_we(rest: null)), '4 × 6 · 65 kg');
      expect(prescriptionLine(_we(kg: null, rest: null)), '4 × 6');
    });

    // `WorkoutSet` documents null and zero as DIFFERENT answers — null is "no
    // load prescribed", zero is a prescribed zero (bodyweight). On screen they
    // render the same, because the design package contains no word for
    // bodyweight anywhere and writing `0 kg` would be worse than silence.
    // Pinned so the collapse is a recorded decision, not an accident.
    test('a prescribed zero renders as silence, like an absent load', () {
      expect(prescriptionLine(_we(kg: 0)), '4 × 6 · rest 120 s');
    });

    test('no sets at all says so rather than rendering an empty line', () {
      expect(prescriptionLine(_we(sets: 0)), 'No sets prescribed');
    });
  });

  group('hasContent — whether the control may exist at all', () {
    test('nothing behind the movement means no control', () {
      expect(exerciseBrief(_we()).hasContent, isFalse);
      expect(rowHint(_we()), isNull);
    });

    test('a coach note alone is enough', () {
      expect(exerciseBrief(_we(notes: 'Keep the depth.')).hasContent, isTrue);
    });

    test('library prose alone is enough', () {
      expect(
          exerciseBrief(_we(exercise: _ex(description: 'Brace, then descend.')))
              .hasContent,
          isTrue);
    });

    test('instructions alone are enough', () {
      expect(
          exerciseBrief(_we(exercise: _ex(instructions: ['Set the bar.'])))
              .hasContent,
          isTrue);
    });

    // The sharp one. Equipment and muscle group are populated on almost every
    // library row, so treating them as content would have made `hasContent`
    // true nearly always — restoring the inert-control defect while looking
    // like it was fixed. The control promises form and instructions; two
    // metadata chips are not that.
    test('equipment and muscle group alone are NOT content', () {
      final brief = exerciseBrief(
          _we(exercise: _ex(equipment: 'Barbell', muscleGroup: 'Legs')));
      expect(brief.equipment, 'Barbell');
      expect(brief.muscleGroup, 'Legs');
      expect(brief.hasContent, isFalse,
          reason: 'metadata must not conjure a control that shows no form');
      expect(rowHint(_we(exercise: _ex(equipment: 'Barbell'))), isNull);
    });

    test('whitespace is emptiness, not content', () {
      expect(
          exerciseBrief(_we(notes: '   ', exercise: _ex(description: '\n')))
              .hasContent,
          isFalse);
    });

    test('blank steps are dropped rather than rendered as empty rows', () {
      final brief = exerciseBrief(
          _we(exercise: _ex(instructions: ['Set the bar.', '  ', 'Descend.'])));
      expect(brief.steps, ['Set the bar.', 'Descend.']);
    });
  });

  group('rowLabel / rowHint — WCAG 2.5.3', () {
    test('the accessible name is the board\'s label, verbatim', () {
      expect(rowLabel(1, _we()), '1 Back squat 4 × 6 · 65 kg · rest 120 s');
    });

    // The visible label is the movement and its prescription. The action is
    // not part of that name, so it cannot be appended to it — it belongs in
    // the hint, or the name stops matching what is on screen.
    test('the action is in the hint, and never in the name', () {
      final we = _we(notes: 'Keep the depth.');
      expect(rowHint(we), 'Shows form and instructions');
      expect(rowLabel(1, we), isNot(contains('form and instructions')));
    });
  });

  test('the brief carries the coach note first-class, not folded into prose',
      () {
    final brief = exerciseBrief(_we(
      notes: 'Keep last week\'s loads.',
      exercise: _ex(description: 'A hinge pattern.', instructions: ['Brace.']),
    ));
    expect(brief.coachNote, 'Keep last week\'s loads.');
    expect(brief.form, 'A hinge pattern.');
    expect(brief.steps, ['Brace.']);
  });
}
