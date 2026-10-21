// WKT-112 (QA-CL-003 / QA-CL-004) — what the Workout Zone shows while it is
// still deciding whether there is an active workout.
//
// The reported defect had a mid-session client land on "No workout selected"
// after a refresh. That string is an answer, and the app was giving it before
// it had one. These pin the three outcomes apart: restoring, genuinely empty,
// and failed-but-recoverable.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';
import 'package:circle_fitness/features/workout/domain/workout_restoration.dart';
import 'package:circle_fitness/features/workout/presentation/active_workout_screen.dart';

/// The Workout Zone route with restoration stubbed to [restore].
///
/// Nothing else is overridden: `selectedWorkoutProvider` starts null, which is
/// exactly the state a browser refresh leaves behind.
Widget _zone(Future<RestoredWorkoutSession?> Function() restore) => ProviderScope(
      overrides: [
        activeWorkoutRestorationProvider.overrideWith((ref) => restore()),
      ],
      child: const MaterialApp(home: ActiveWorkoutScreen()),
    );

void main() {
  group('WKT-112 hydration states', () {
    testWidgets('while restoring it says so — never "No workout selected"',
        (tester) async {
      await tester.pumpWidget(_zone(() => Completer<RestoredWorkoutSession?>().future));
      await tester.pump();

      expect(find.text('Restoring your workout…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No workout selected'), findsNothing);
      expect(find.text('Browse Workouts'), findsNothing);
    });

    testWidgets('a settled "no session" shows the empty state', (tester) async {
      await tester.pumpWidget(_zone(() async => null));
      await tester.pumpAndSettle();

      expect(find.text('No workout selected'), findsOneWidget);
      expect(find.text('Browse Workouts'), findsOneWidget);
      expect(find.text('Restoring your workout…'), findsNothing);
    });

    testWidgets('a failed restore offers recovery, not an empty state',
        (tester) async {
      await tester.pumpWidget(_zone(
          () async => throw const WorkoutRestorationFailure('nope')));
      await tester.pumpAndSettle();

      expect(find.text('We couldn\'t restore your workout.'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('No workout selected'), findsNothing);
    });

    testWidgets('Try Again re-runs the restore', (tester) async {
      var attempt = 0;
      await tester.pumpWidget(_zone(() async {
        if (attempt++ == 0) throw const WorkoutRestorationFailure('transient');
        return null;
      }));
      await tester.pumpAndSettle();
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(attempt, 2, reason: 'the retry asks storage again');
      expect(find.text('We couldn\'t restore your workout.'), findsNothing);
      expect(find.text('No workout selected'), findsOneWidget);
    });
  });
}
