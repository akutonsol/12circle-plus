import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/presentation/workout_detail_screen.dart';

/// F-20 · FIT-016 must show the workout that was selected — and only that one.
///
/// The defect these tests pin was concrete, not theoretical. `/workout-detail`
/// took no route parameter and `WorkoutDetailScreen` accepted no identity; it
/// rendered one hardcoded workout with a fixed hero image. It was reached as the
/// failure branch of a title-string match in `workout_list_screen.dart`, and the
/// browse list's `'Glute & Hamstring\nFocus'` can never equal the domain's
/// `'Glute and Hamstring Focus'` — so that card always landed here and showed a
/// workout the user had not chosen.

Exercise _ex(String id, String name) => Exercise(
      id: id,
      name: name,
      category: 'Strength',
      muscleGroup: 'Legs',
      equipment: 'Barbell',
      difficulty: 'Intermediate',
      description: '',
      instructions: const [],
    );

WorkoutExercise _we(String id, String name, {required int sets, required int reps, double? kg, int? rest}) =>
    WorkoutExercise(
      exercise: _ex(id, name),
      sets: List.generate(
        sets,
        (i) => WorkoutSet(setNumber: i + 1, reps: reps, weightKg: kg, restSeconds: rest),
      ),
    );

final _workoutA = Workout(
  id: '1',
  title: 'Lower body — strength',
  description: "Keep last week's loads.",
  estimatedDuration: 48,
  difficulty: 'Intermediate',
  category: 'Strength',
  coachName: 'Nadia',
  exercises: [
    _we('e1', 'Back squat', sets: 4, reps: 6, kg: 65, rest: 120),
    _we('e2', 'Romanian deadlift', sets: 4, reps: 8, kg: 62.5, rest: 90),
  ],
);

final _workoutB = Workout(
  id: '2',
  title: 'Upper body — push',
  description: 'Controlled tempo throughout.',
  estimatedDuration: 35,
  difficulty: 'Advanced',
  category: 'Strength',
  coachName: 'Marcus',
  exercises: [
    _we('e3', 'Bench press', sets: 5, reps: 5, kg: 80, rest: 150),
  ],
);

Widget _host(Workout? selected) => ProviderScope(
      overrides: [
        selectedWorkoutProvider.overrideWith((ref) => selected),
      ],
      child: const MaterialApp(home: WorkoutDetailScreen()),
    );

/// The screen is a ListView, so anything below the fold of the default 800x600
/// test surface is never built. That matters for more than the positive
/// assertions: an `expect(..., findsNothing)` for the CTA would pass trivially
/// because the CTA was simply off-screen, not because it was absent. Laying the
/// whole column out makes both directions mean something.
Future<void> _tall(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

void main() {
  group('F-20 the detail screen shows the SELECTED workout', () {
    testWidgets('workout A renders A — its title, metrics and exercises', (t) async {
      await t.pumpWidget(_host(_workoutA));
      await t.pump();

      expect(find.text('Lower body — strength'), findsOneWidget);
      expect(find.text("Keep last week's loads."), findsOneWidget);
      expect(find.text('Back squat'), findsOneWidget);
      expect(find.text('Romanian deadlift'), findsOneWidget);

      // Metric strip is computed from the workout, not hardcoded:
      // 2 exercises, 48 min, 8 sets (4 + 4).
      expect(find.text('2'), findsWidgets);
      expect(find.text('8'), findsWidgets);
      // Prescription assembled from real set fields.
      expect(find.text('4 × 6 · 65 kg · rest 120 s'), findsOneWidget);
    });

    testWidgets('workout B renders B, and none of A leaks into it', (t) async {
      await t.pumpWidget(_host(_workoutB));
      await t.pump();

      expect(find.text('Upper body — push'), findsOneWidget);
      expect(find.text('Bench press'), findsOneWidget);
      expect(find.text('5 × 5 · 80 kg · rest 150 s'), findsOneWidget);

      // The crux: A's content must be absent.
      expect(find.text('Lower body — strength'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
      expect(find.text('Romanian deadlift'), findsNothing);
      expect(find.text("Keep last week's loads."), findsNothing);
    });

    testWidgets('switching A -> B replaces the content entirely', (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedWorkoutProvider.notifier).state = _workoutA;

      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WorkoutDetailScreen()),
      ));
      await t.pump();
      expect(find.text('Back squat'), findsOneWidget);

      container.read(selectedWorkoutProvider.notifier).state = _workoutB;
      await t.pump();

      expect(find.text('Bench press'), findsOneWidget);
      expect(find.text('Back squat'), findsNothing,
          reason: 'A stale exercise from the previous workout is exactly the '
              'defect F-20 records.');
    });

    testWidgets('no selection shows a distinct state, never invented content', (t) async {
      await _tall(t);
      await t.pumpWidget(_host(null));
      await t.pump();

      expect(find.text('No workout selected'), findsOneWidget);
      // There must be no session to begin, and no fabricated exercise.
      expect(find.text('Begin session'), findsNothing);
      expect(find.text('Back squat'), findsNothing);
      expect(find.text('Bench press'), findsNothing);
    });

    testWidgets('a workout with no exercises does not offer a session to begin', (t) async {
      final empty = Workout(
        id: '9', title: 'Empty plan', description: '',
        estimatedDuration: 0, difficulty: 'Beginner', category: 'Strength',
        exercises: const [],
      );
      await _tall(t);
      await t.pumpWidget(_host(empty));
      await t.pump();

      expect(find.text('Empty plan'), findsOneWidget);
      expect(find.text('This workout has no exercises yet.'), findsOneWidget);
      expect(find.text('Begin session'), findsNothing,
          reason: 'An empty workout must not look like a session that is ready.');
    });
  });

  group('F-20 accessibility of the rebuilt screen', () {
    testWidgets('the back control and each exercise row carry names', (t) async {
      // Acquired BEFORE the first build: semantics are only compiled while a
      // handle is held, so asking for it afterwards finds an empty tree.
      final handle = t.ensureSemantics();
      await _tall(t);
      await t.pumpWidget(_host(_workoutA));
      await t.pump();

      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.bySemanticsLabel('Begin session'), findsOneWidget);
      // Row label carries position, movement and prescription together.
      expect(find.bySemanticsLabel('1 Back squat 4 × 6 · 65 kg · rest 120 s'),
          findsOneWidget);
      handle.dispose();
    });
  });
}
