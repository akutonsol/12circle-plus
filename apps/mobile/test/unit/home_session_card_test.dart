import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/home/domain/home_session_card.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';

/// FIT-001 · the Today card on `/home`.
///
/// The defect worth stating first: the card fell back to the **sample
/// library** when nothing was assigned, and captioned it *"Assigned by your
/// coach"*. A client with no plan was shown a demo workout as their own — F-20
/// on the app's front door.
///
/// The rest are of a piece with it. `45 min`, `550 kcal` and `2.0K steps` were
/// hardcoded literals, and a failed assignment read became an empty list and
/// then, through the same fallback, somebody else's workout.

Workout _w({
  String title = 'Lower body — strength',
  String? coach = 'Nadia',
  DateTime? on,
  int minutes = 48,
  bool completed = false,
  int exercises = 6,
  double? kg = 62.5,
}) =>
    Workout(
      id: title,
      title: title,
      description: '',
      estimatedDuration: minutes,
      difficulty: 'Intermediate',
      category: 'Strength',
      coachName: coach,
      isCompleted: completed,
      scheduledDate: on,
      exercises: [
        for (var i = 0; i < exercises; i++)
          WorkoutExercise(
            exercise: Exercise(
              id: 'e$i',
              name: 'Movement $i',
              category: 'Strength',
              muscleGroup: 'Legs',
              equipment: 'Barbell',
              difficulty: 'Intermediate',
              description: '',
              instructions: const [],
            ),
            sets: [WorkoutSet(setNumber: 1, reps: 6, weightKg: kg)],
          ),
      ],
    );

final _today = DateTime(2026, 9, 23);

AsyncValue<List<Workout>> _data(List<Workout> w) => AsyncValue.data(w);

void main() {
  group('a real assigned session', () {
    test('reads exactly as the board draws it', () {
      final s = homeSession(_data([_w(on: _today)]), now: _today);
      expect(s.context, 'Today · assigned by Nadia');
      expect(s.title, 'Lower body — strength');
      expect(s.summary, '6 exercises · 48 min · heaviest set 62.5 kg');
      expect(s.canBegin, isTrue);
      expect(HomeSession.beginLabel, 'Begin session');
    });

    test('a workout with no coach still names the day', () {
      final s = homeSession(_data([_w(on: _today, coach: null)]), now: _today);
      expect(s.context, 'Today');
      expect(s.canBegin, isTrue);
    });
  });

  // THE defect. A sample workout is not this client's session, whatever the
  // card would look like with one in it.
  group('nothing assigned', () {
    test('offers nothing rather than a workout from the library', () {
      final s = homeSession(_data(const []), now: _today);
      expect(s.canBegin, isFalse);
      expect(s.title, isNull);
      expect(s.workout, isNull);
      expect(s.emptyLine, 'No session assigned for today');
    });

    test('a plan with nothing scheduled for TODAY is also nothing', () {
      final s = homeSession(
          _data([_w(on: DateTime(2026, 9, 25))]), now: _today);
      expect(s.canBegin, isFalse);
      expect(s.title, isNull);
    });

    test('a session already completed today is not offered again', () {
      final s =
          homeSession(_data([_w(on: _today, completed: true)]), now: _today);
      expect(s.canBegin, isFalse);
    });

    test('an undated workout is not treated as today\'s', () {
      final s = homeSession(_data([_w(on: null)]), now: _today);
      expect(s.canBegin, isFalse);
    });
  });

  // Three different facts, and a client can act on only one of them.
  group('the three states stay apart', () {
    test('a FAILED read is not an empty plan', () {
      final s = homeSession(
          AsyncValue<List<Workout>>.error(Exception('net'), StackTrace.empty),
          now: _today);
      expect(s.failed, isTrue);
      expect(s.canBegin, isFalse);
      expect(s.emptyLine, "Couldn't load your plan");
      expect(s.emptyLine, isNot('No session assigned for today'));
    });

    test('LOADING is neither', () {
      final s = homeSession(const AsyncValue<List<Workout>>.loading(),
          now: _today);
      expect(s.failed, isFalse);
      expect(s.canBegin, isFalse);
      // Nothing is asserted about the plan while it is still being read.
      expect(s.title, isNull);
    });

    test('an empty plan is not a failure', () {
      expect(homeSession(_data(const []), now: _today).failed, isFalse);
    });
  });

  group('the badges', () {
    // `45 min`, `550 kcal` and `2.0K steps` were literals on a card that
    // presented them as this session's stats.
    test('carry only what the workout states', () {
      final b = homeSessionBadges(_w(on: _today));
      expect(b, ['48 min', '6 exercises']);
      for (final invented in const ['550 kcal', '2.0K steps', '45 min']) {
        expect(b, isNot(contains(invented)));
      }
    });

    test('an unknown duration is omitted, not rendered as 0 min', () {
      expect(homeSessionBadges(_w(minutes: 0)), ['6 exercises']);
    });

    test('one exercise is not "1 exercises"', () {
      expect(homeSessionBadges(_w(minutes: 0, exercises: 1)), ['1 exercise']);
    });

    test('no workout, no badges', () {
      expect(homeSessionBadges(null), isEmpty);
    });
  });

  test('the summary drops a clause the data cannot support', () {
    // `plan_summary` already guarantees this; asserted here because the home
    // card is the surface where a fabricated figure was actually shipping.
    final s = homeSession(
        _data([_w(on: _today, kg: null, minutes: 0)]), now: _today);
    expect(s.summary, '6 exercises');
    expect(s.summary, isNot(contains('0 min')));
    expect(s.summary, isNot(contains('0 kg')));
  });
}
