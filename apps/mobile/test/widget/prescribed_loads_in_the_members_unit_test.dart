import 'dart:io';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/exercise_brief.dart';
import 'package:circle_fitness/features/workout/domain/load_format.dart';
import 'package:circle_fitness/features/workout/domain/plan_summary.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A coach's prescribed load is stored in kg. The workout screen shows it to the
// member in their own unit (lb unless they chose metric) and takes their entry
// in that unit. The two lines that describe the same prescription before the
// session starts did not:
//   * the workout detail rows (and their brief sheet and accessible name):
//     "4 × 6 · 65 kg · rest 120 s";
//   * the Train hub's Today card: "heaviest set 65 kg".
// So an imperial member was told 65 and then shown 143.3 at the bar.

WorkoutExercise _we({double? kg = 65}) => WorkoutExercise(
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
      sets: List.generate(
          4, (i) => WorkoutSet(setNumber: i + 1, reps: 6, weightKg: kg, restSeconds: 120)),
    );

Workout _workout() => Workout(
      id: 'w1',
      title: 'Lower body — strength',
      description: '',
      estimatedDuration: 48,
      difficulty: 'Intermediate',
      category: 'Strength',
      exercises: [_we()],
    );

void main() {
  group('the lines, in lb', () {
    test('the prescription', () {
      expect(prescriptionLine(_we(), metric: false), '4 × 6 · 143.3 lb · rest 120 s');
      expect(rowLabel(1, _we(), metric: false), '1 Back squat 4 × 6 · 143.3 lb · rest 120 s');
      expect(exerciseBrief(_we(), metric: false).prescription, '4 × 6 · 143.3 lb · rest 120 s');
    });
    test('the summary', () {
      expect(workoutSummaryLine(_workout(), metric: false),
          '1 exercise · 48 min · heaviest set 143.3 lb');
    });
    test('no load is still no load, in either unit', () {
      expect(prescriptionLine(_we(kg: null), metric: false), '4 × 6 · rest 120 s');
      expect(prescriptionLine(_we(kg: 0), metric: false), '4 × 6 · rest 120 s');
    });
    test('metric is unchanged, rounded to 0.1', () {
      expect(prescriptionLine(_we(), metric: true), '4 × 6 · 65 kg · rest 120 s');
      expect(prescriptionLine(_we(kg: 61.23496995), metric: true), '4 × 6 · 61.2 kg · rest 120 s');
    });
  });

  group('the workout detail screen', () {
    Future<void> pump(WidgetTester tester, {required bool metric}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          selectedWorkoutProvider.overrideWith((ref) => _workout()),
          memberPrefersMetricProvider.overrideWithValue(metric),
        ],
        child: const MaterialApp(home: WorkoutDetailScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an imperial member reads the load they will lift', (tester) async {
      await pump(tester, metric: false);
      expect(find.textContaining('65 kg'), findsNothing, reason: 'THE defect');
      expect(find.text('4 × 6 · 143.3 lb · rest 120 s'), findsOneWidget);
    });

    testWidgets('a metric member reads kg (control)', (tester) async {
      await pump(tester, metric: true);
      expect(find.text('4 × 6 · 65 kg · rest 120 s'), findsOneWidget);
    });
  });

  test("the unit follows the member's profile, lb by default", () {
    // The provider every load display reads.
    expect(prefersMetric(null), isFalse);
    expect(prefersMetric('imperial'), isFalse);
    expect(prefersMetric('metric'), isTrue);
  });

  test("the Train hub's Today card states the load in the member's unit", () {
    // The hero card is private to a screen with a dozen providers behind it;
    // this pins its summary to the member's unit.
    final src = File('lib/features/workout/presentation/train_hub_screen.dart').readAsStringSync();
    expect(src, contains('workoutSummaryLine(workout, metric: metric)'));
    expect(src, isNot(contains('workoutSummaryLine(workout);')));
  });
}
