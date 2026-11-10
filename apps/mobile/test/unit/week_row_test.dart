import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/week_row.dart';

/// FIT-014 · the "This week" rows, against the board's own markup.
///
/// Four defects are pinned here. Three were fidelity — an abbreviated day next
/// to a chip saying the same word, an uppercased `NOW` where the board's
/// `.pill` carries no `text-transform`, and no marker at all on an upcoming
/// session where the board draws a ring. The fourth is in the widget: the rows
/// were `Semantics(button: true)` with no action.

Workout _w({
  String title = 'Upper body — push',
  bool completed = false,
  DateTime? on,
  int minutes = 44,
}) =>
    Workout(
      id: title,
      title: title,
      description: '',
      estimatedDuration: minutes,
      difficulty: 'Intermediate',
      category: 'Strength',
      isCompleted: completed,
      scheduledDate: on,
      exercises: [
        WorkoutExercise(
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
          sets: const [WorkoutSet(setNumber: 1, reps: 6)],
        ),
      ],
    );

// A fixed Wednesday, so "today" never drifts with the wall clock.
final _now = DateTime(2026, 9, 23); // a Wednesday
final _monday = DateTime(2026, 9, 21);
final _thursday = DateTime(2026, 9, 24);
final _saturday = DateTime(2026, 9, 26);

void main() {
  group('weekRowKind', () {
    test('completed wins over any date', () {
      expect(weekRowKind(_w(completed: true, on: _now), now: _now),
          WeekRowKind.done);
      expect(weekRowKind(_w(completed: true, on: _monday), now: _now),
          WeekRowKind.done);
    });

    test('today, another day, and no day at all are three different rows', () {
      expect(weekRowKind(_w(on: _now), now: _now), WeekRowKind.today);
      expect(weekRowKind(_w(on: _thursday), now: _now), WeekRowKind.scheduled);
      expect(weekRowKind(_w(), now: _now), WeekRowKind.undated);
    });

    test('same day of a different month is not today', () {
      expect(
          weekRowKind(_w(on: DateTime(2026, 8, 23)), now: _now),
          WeekRowKind.scheduled);
    });
  });

  group('weekRowDetail — the board writes the day in full', () {
    // The defect: the rows abbreviated it, so `Thu · 30 min` sat beside a
    // `THU` chip. The board reads `Thursday · 30 min` beside `Thu`.
    test('a scheduled day is spelled out', () {
      expect(weekRowDetail(_w(on: _monday, minutes: 44), now: _now),
          'Monday · 44 min');
      expect(
          weekRowDetail(_w(on: _thursday, minutes: 30), now: _now),
          'Thursday · 30 min');
      expect(weekRowDetail(_w(on: _saturday, minutes: 44), now: _now),
          'Saturday · 44 min');
    });

    test('today is "Today", not Wednesday', () {
      expect(weekRowDetail(_w(on: _now, minutes: 48), now: _now),
          'Today · 48 min');
    });

    // The board's first row is `Monday · 44 min` with a `Done` chip — a
    // finished session keeps the day it happened on.
    test('a completed session keeps its own day', () {
      expect(
          weekRowDetail(_w(completed: true, on: _monday, minutes: 44),
              now: _now),
          'Monday · 44 min');
    });

    test('an unknown duration is omitted, not rendered as 0 min', () {
      expect(weekRowDetail(_w(on: _monday, minutes: 0), now: _now), 'Monday');
      expect(weekRowDetail(_w(minutes: 0), now: _now), '');
      expect(weekRowDetail(_w(minutes: 30), now: _now), '30 min');
    });
  });

  group('weekRowChip — and which of them the stylesheet uppercases', () {
    test('the four chips the board draws', () {
      expect(weekRowChip(_w(completed: true, on: _monday), now: _now), 'Done');
      expect(weekRowChip(_w(on: _now), now: _now), 'Now');
      expect(weekRowChip(_w(on: _thursday), now: _now), 'Thu');
      expect(weekRowChip(_w(on: _saturday), now: _now), 'Sat');
    });

    test('an undated row has no chip rather than an empty one', () {
      expect(weekRowChip(_w(), now: _now), isNull);
    });

    // `.mic { text-transform: uppercase }`; `.pill` has none. So `Done`,
    // `Thu` and `Sat` render uppercased and `Now` does not — the shipped rows
    // uppercased all four.
    test('only the pill escapes the uppercase', () {
      expect(weekRowChipIsUppercase(_w(on: _now), now: _now), isFalse,
          reason: '.pill carries no text-transform — the chip reads "Now"');
      expect(
          weekRowChipIsUppercase(_w(completed: true, on: _monday), now: _now),
          isTrue);
      expect(weekRowChipIsUppercase(_w(on: _thursday), now: _now), isTrue);
    });
  });

  group('weekRowLabel', () {
    test('is the shape the manifest declares', () {
      expect(
          weekRowLabel(
              _w(title: 'Upper body — push', completed: true, on: _monday),
              now: _now),
          'Upper body — push Monday · 44 min Done');
      expect(
          weekRowLabel(
              _w(title: 'Lower body — strength', on: _now, minutes: 48),
              now: _now),
          'Lower body — strength Today · 48 min Now');
      expect(
          weekRowLabel(
              _w(title: 'Conditioning', on: _thursday, minutes: 30),
              now: _now),
          'Conditioning Thursday · 30 min Thu');
    });

    // A screen reader announcing `DONE` would spell it. The chip is named as
    // it is read, not as the stylesheet draws it.
    test('the name uses the spoken chip, never the uppercased one', () {
      final label =
          weekRowLabel(_w(completed: true, on: _monday), now: _now);
      expect(label, endsWith('Done'));
      expect(label, isNot(contains('DONE')));
    });

    test('an undated row names only what it has', () {
      expect(weekRowLabel(_w(title: 'Conditioning', minutes: 30), now: _now),
          'Conditioning 30 min');
    });
  });

  // R1 (owner, 2026-11-09): only the current week's sessions, and "No sessions
  // this week" when there are none. The list was the whole program: every
  // week's sessions, under a heading that says THIS WEEK.
  group('R1 only this week', () {
    final lastSunday = DateTime(2026, 9, 20);
    final sunday = DateTime(2026, 9, 27);
    final nextMonday = DateTime(2026, 9, 28);

    List<String> titles(List<Workout> ws) => [for (final w in ws) w.title];

    test('sessions from other weeks are left out', () {
      final week = thisWeeksSessions([
        _w(title: 'last week', on: lastSunday, completed: true),
        _w(title: 'mon', on: _monday, completed: true),
        _w(title: 'thu', on: _thursday),
        _w(title: 'sun', on: sunday),
        _w(title: 'next week', on: nextMonday),
      ], now: _now);

      expect(titles(week), ['mon', 'thu', 'sun']);
    });

    test('a session with a time of day still belongs to its day', () {
      final week = thisWeeksSessions([
        _w(title: 'sun evening', on: DateTime(2026, 9, 27, 21, 30)),
        _w(title: 'next mon early', on: DateTime(2026, 9, 28, 0, 30)),
      ], now: DateTime(2026, 9, 27, 23));

      expect(titles(week), ['sun evening']);
    });

    test('undated workouts stay listed as they were', () {
      final week = thisWeeksSessions([
        _w(title: 'self-guided A'),
        _w(title: 'next week', on: nextMonday),
        _w(title: 'self-guided B'),
      ], now: _now);

      expect(titles(week), ['self-guided A', 'self-guided B']);
    });

    test('a program with nothing this week gives an empty week', () {
      expect(thisWeeksSessions([_w(on: nextMonday)], now: _now), isEmpty);
    });

    // The hub cannot be driven in a widget test (plan_summary.dart says why),
    // so its wiring is held by its source.
    test('[SOURCE] THIS WEEK lists this week, and says when there is nothing', () {
      final src = File('lib/features/workout/presentation/train_hub_screen.dart')
          .readAsStringSync();
      final start = src.indexOf('class _ThisWeek ');
      expect(start, greaterThan(0), reason: '_ThisWeek has gone');
      final next = src.indexOf('\nclass ', start + 1);
      final body = src.substring(start, next < 0 ? src.length : next);

      expect(body, contains('thisWeeksSessions(workouts)'),
          reason: 'THIS WEEK is listing the whole program again');
      expect(body, isNot(contains('workouts.map(')));
      expect(body, contains("'No sessions this week'"));
    });
  });
}
