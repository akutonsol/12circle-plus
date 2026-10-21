import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/plan_summary.dart';

/// FIT-014 hero card — the derivations behind it.
///
/// These assert the real functions the screen calls, not a copy of their logic
/// restated in this file. The rendering is verified on the emulator; the wiring
/// by A-G6.

Exercise _ex(String id) => Exercise(
      id: id, name: 'Movement $id', category: 'Strength', muscleGroup: 'Legs',
      equipment: 'Barbell', difficulty: 'Intermediate', description: '',
      instructions: const []);

WorkoutExercise _we(String id, {required int sets, double? kg}) => WorkoutExercise(
      exercise: _ex(id),
      sets: List.generate(
          sets, (i) => WorkoutSet(setNumber: i + 1, reps: 8, weightKg: kg)),
    );

Workout _w({
  String id = '1',
  String title = 'Session',
  DateTime? when,
  bool done = false,
  int minutes = 48,
  String? coach,
  List<WorkoutExercise>? exercises,
}) =>
    Workout(
      id: id, title: title, description: '', estimatedDuration: minutes,
      difficulty: 'Intermediate', category: 'Strength',
      coachName: coach, isCompleted: done, scheduledDate: when,
      exercises: exercises ?? [_we('a', sets: 4, kg: 60), _we('b', sets: 2, kg: 62.5)],
    );

void main() {
  final today = DateTime(2026, 9, 23, 9, 41);

  group('todaysSession — the hero may only claim what is true', () {
    test('returns the session scheduled for today', () {
      final w = _w(id: '1', when: today);
      expect(todaysSession([w], now: today)?.id, '1');
    });

    test('a session on another day is NOT promoted to today', () {
      final w = _w(id: '2', when: today.add(const Duration(days: 2)));
      expect(todaysSession([w], now: today), isNull,
          reason: "FIT-014's pill reads 'Today'. Rendering another day beneath "
              'it would state something untrue.');
    });

    test('a completed session today is not offered again', () {
      final w = _w(id: '3', when: today, done: true);
      expect(todaysSession([w], now: today), isNull);
    });

    test('an unscheduled session is never today', () {
      expect(todaysSession([_w(id: '4')], now: today), isNull);
    });

    test('picks the first matching session when several are scheduled today', () {
      final a = _w(id: 'a', when: today);
      final b = _w(id: 'b', when: today);
      expect(todaysSession([a, b], now: today)?.id, 'a');
    });

    test('an empty plan has no session today', () {
      expect(todaysSession(const [], now: today), isNull);
    });

    test('matches on the calendar day, not the clock', () {
      final lateSameDay = DateTime(2026, 9, 23, 23, 59);
      expect(todaysSession([_w(when: lateSameDay)], now: today), isNotNull);
      // ...and one minute later is a different day.
      final justAfterMidnight = DateTime(2026, 9, 24, 0, 1);
      expect(todaysSession([_w(when: justAfterMidnight)], now: today), isNull);
    });
  });

  group('workoutSummaryLine — a missing figure is omitted, never zeroed', () {
    test('full line', () {
      expect(workoutSummaryLine(_w()), '2 exercises · 48 min · heaviest set 62.5 kg');
    });

    test('a whole number of kg does not render a trailing .0', () {
      final w = _w(exercises: [_we('a', sets: 3, kg: 70)]);
      expect(workoutSummaryLine(w), contains('heaviest set 70 kg'));
      expect(workoutSummaryLine(w), isNot(contains('70.0')));
    });

    test('bodyweight work omits the load clause entirely', () {
      final w = _w(exercises: [_we('a', sets: 3)]);
      expect(workoutSummaryLine(w), isNot(contains('kg')),
          reason: '"heaviest set 0 kg" would be a fabricated measurement.');
      expect(workoutSummaryLine(w), '1 exercise · 48 min');
    });

    test('no estimate omits the duration clause', () {
      final w = _w(minutes: 0, exercises: [_we('a', sets: 3, kg: 40)]);
      expect(workoutSummaryLine(w), isNot(contains('min')));
      expect(workoutSummaryLine(w), '1 exercise · heaviest set 40 kg');
    });

    test('singular and plural are both correct', () {
      expect(workoutSummaryLine(_w(exercises: [_we('a', sets: 1, kg: 20)])),
          startsWith('1 exercise ·'));
      expect(workoutSummaryLine(_w()), startsWith('2 exercises ·'));
    });

    test('an empty workout produces an empty line rather than "0 exercises"', () {
      final w = _w(minutes: 0, exercises: const []);
      expect(workoutSummaryLine(w), '');
    });

    test('the heaviest load is the maximum across every set of every exercise', () {
      final w = _w(exercises: [
        _we('a', sets: 3, kg: 40),
        _we('b', sets: 3, kg: 95),
        _we('c', sets: 3, kg: 62.5),
      ]);
      expect(heaviestPrescribedLoad(w), 95);
      expect(workoutSummaryLine(w), contains('heaviest set 95 kg'));
    });

    test('a zero weight is treated as no weight, not as a load of zero', () {
      final w = _w(exercises: [_we('a', sets: 2, kg: 0)]);
      expect(heaviestPrescribedLoad(w), isNull);
    });
  });

  group('todayPillLabel', () {
    test('names the coach when the workout carries one', () {
      expect(todayPillLabel(_w(coach: 'Nadia')), 'Today · assigned by Nadia');
    });

    test('degrades to the bare day rather than inventing a coach', () {
      expect(todayPillLabel(_w()), 'Today');
      expect(todayPillLabel(_w(coach: '   ')), 'Today');
    });
  });
}
