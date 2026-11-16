import 'package:circle_fitness/features/exercise_database/data/exercise_database_service.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/exercise_brief.dart';
import 'package:circle_fitness/features/workout/domain/library_match.dart';
import 'package:flutter_test/flutter_test.dart';

// A program row names its movements in free text and carries no description,
// instructions or library id (QA: program_workouts.exercises keys are name,
// sets, reps, weight_kg, rest_seconds, rpe, tempo, notes, position,
// duration_seconds, exercise_instance_id). So the workout's "form and
// instructions" brief was empty for every assigned movement -- including ones
// the app's own library covers and shows clients on the Exercise Library
// screen. The brief now falls back to the library entry with the SAME name
// (case, spaces and punctuation aside) for what the prescription lacks.

WorkoutExercise _we(String name, {String description = '', List<String> instructions = const [], String? notes}) =>
    WorkoutExercise(
      exercise: Exercise(
        id: 'x',
        name: name,
        category: 'Strength',
        muscleGroup: '',
        equipment: '',
        difficulty: 'Intermediate',
        description: description,
        instructions: instructions,
      ),
      notes: notes,
      sets: const [WorkoutSet(setNumber: 1, reps: 10)],
    );

void main() {
  final pushUp = ExerciseDatabaseService().getAllExercises().firstWhere((e) => e.name == 'Push-Up');

  test('premise: the library covers Push-Up with form and steps', () {
    expect(pushUp.description, isNotEmpty);
    expect(pushUp.instructions, isNotEmpty);
  });

  test('"Push Up" from a program row shows the library\'s Push-Up form and steps', () {
    final b = exerciseBrief(_we('Push Up'));
    expect(b.hasContent, isTrue, reason: 'THE defect: the brief was empty for a movement the library covers');
    expect(b.form, pushUp.description);
    expect(b.steps, pushUp.instructions);
  });

  test('the match is exact after normalising, never a near match', () {
    expect(normalizeExerciseName('Push-Up'), normalizeExerciseName('push up'));
    expect(bundledLibraryEntry('Bench Press'), isNull,
        reason: '"Bench Press" must not borrow "Barbell Bench Press" form');
    expect(exerciseBrief(_we('Bench Press')).hasContent, isFalse);
    expect(bundledLibraryEntry(''), isNull);
  });

  test("the prescription's own description and steps always win", () {
    final b = exerciseBrief(_we('Push Up', description: 'Coach form.', instructions: const ['Coach step.']));
    expect(b.form, 'Coach form.');
    expect(b.steps, ['Coach step.']);
  });

  test('only the missing part is filled', () {
    final b = exerciseBrief(_we('Push Up', description: 'Coach form.'));
    expect(b.form, 'Coach form.');
    expect(b.steps, pushUp.instructions);
  });

  test('a movement the library does not cover keeps an empty brief', () {
    expect(exerciseBrief(_we('Zercher Carry Complex')).hasContent, isFalse);
  });

  test('the lookup is injectable (no library: unchanged behaviour)', () {
    expect(exerciseBrief(_we('Push Up'), library: (_) => null).hasContent, isFalse);
  });
}
