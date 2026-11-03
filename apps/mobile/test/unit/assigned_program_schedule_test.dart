import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/home/domain/home_session_card.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/program_schedule.dart';

/// A hand-built week 1 reaches the client's Today card.
///
/// The defect: `program_workouts` rows were decoded with no date, and Home only
/// offers a workout whose `scheduledDate` is today — so a coach could build and
/// assign a session for today and the client's Home still said "No session
/// assigned for today". The date now comes from the assignment's `start_date`:
/// week 1 is the Monday-to-Sunday week containing it.
///
/// Every fixture below is persisted data — the map `getMyAssignedProgram()`
/// returns — and goes through the real decoder. None sets a date by hand.

/// One training day exactly as the Program Builder saves it
/// (`_WorkoutEditorSheet` + `_ExerciseDialog`), read back with `select()`.
Map<String, dynamic> _row(String id, int week, String day,
        {String? title, int minutes = 40}) =>
    {
      'id': id,
      'program_id': 'prog-1',
      'title': title ?? 'W$week $day',
      'week_number': week,
      'day_of_week': day,
      'estimated_minutes': minutes,
      'sort_order': const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
        'Sunday',
      ].indexOf(day),
      'exercises': [
        {
          'exercise_instance_id': 'ex-$id-1',
          'name': 'Back Squat',
          'sets': 3,
          'reps': 8,
          'weight_kg': 60,
          'rest_seconds': 90,
        },
        {
          // Load and rest left blank in the dialog.
          'exercise_instance_id': 'ex-$id-2',
          'name': 'Plank',
          'sets': 3,
          'reps': 1,
          'weight_kg': null,
          'rest_seconds': null,
        },
      ],
      'created_at': '2026-11-01T18:20:00.000000+00:00',
    };

/// The assignment row (`select('*, workout_programs(*)')`) plus `workouts`.
Map<String, dynamic> _assignment(String? startDate,
        List<Map<String, dynamic>> workouts, {String? coachId = 'coach-1'}) =>
    {
      'id': 'asg-1',
      'program_id': 'prog-1',
      'client_id': 'client-1',
      'coach_id': coachId,
      'start_date': startDate,
      'current_week': 1,
      'status': 'active',
      'workout_programs': {'id': 'prog-1', 'name': 'Beta week 1', 'duration_weeks': 4},
      'workouts': workouts,
    };

DateTime? _dateOf(List<Workout> w, String id) =>
    w.firstWhere((x) => x.id == id).scheduledDate;

String? _todayTitle(Map<String, dynamic> assignment, DateTime now) =>
    homeSession(AsyncValue.data(assignedProgramToWorkouts(assignment)), now: now)
        .title;

void main() {
  group('a persisted hand-built program decodes to dated workouts', () {
    // Assigned on Wednesday 4 Nov 2026: week 1 is Mon 2 – Sun 8 Nov.
    final assignment = _assignment('2026-11-04', [
      _row('w1-mon', 1, 'Monday'),
      _row('w1-wed', 1, 'Wednesday', title: 'Upper Body Push'),
      _row('w1-sun', 1, 'Sunday'),
      _row('w2-mon', 2, 'Monday'),
      _row('w2-wed', 2, 'Wednesday'),
    ]);
    final workouts = assignedProgramToWorkouts(assignment);

    test('each day lands in the Monday-anchored week of the start date', () {
      expect(_dateOf(workouts, 'w1-mon'), DateTime(2026, 11, 2));
      expect(_dateOf(workouts, 'w1-wed'), DateTime(2026, 11, 4));
      expect(_dateOf(workouts, 'w1-sun'), DateTime(2026, 11, 8));
      expect(_dateOf(workouts, 'w2-mon'), DateTime(2026, 11, 9));
      expect(_dateOf(workouts, 'w2-wed'), DateTime(2026, 11, 11));
    });

    test('the rest of the row decodes as before (blank load stays blank)', () {
      final w = workouts.firstWhere((x) => x.id == 'w1-wed');
      expect(w.title, 'Upper Body Push');
      expect(w.estimatedDuration, 40);
      expect(w.exercises, hasLength(2));
      expect(w.exercises[1].sets.first.weightKg, isNull);
      expect(w.exercises[1].sets.first.restSeconds, isNull);
    });

    test('Home selects the workout on its own day', () {
      expect(_todayTitle(assignment, DateTime(2026, 11, 4, 7, 30)),
          'Upper Body Push');
      expect(_todayTitle(assignment, DateTime(2026, 11, 11, 18)), 'W2 Wednesday');
    });

    test('Home does not select a workout on any other day', () {
      // Thursday of week 1, and the Tuesday of week 2: nothing scheduled.
      expect(_todayTitle(assignment, DateTime(2026, 11, 5)), isNull);
      expect(_todayTitle(assignment, DateTime(2026, 11, 10)), isNull);
      // Same weekday a week after the program's last row: nothing.
      expect(_todayTitle(assignment, DateTime(2026, 11, 18)), isNull);
      // Tuesday of week 1, the day before the start date: nothing scheduled.
      expect(_todayTitle(assignment, DateTime(2026, 11, 3)), isNull);
    });

    test('a week-1 day is not offered again on the same weekday of week 2', () {
      final onlyWeek1 = _assignment('2026-11-04', [_row('w1-wed', 1, 'Wednesday')]);
      expect(_todayTitle(onlyWeek1, DateTime(2026, 11, 4)), 'W1 Wednesday');
      expect(_todayTitle(onlyWeek1, DateTime(2026, 11, 11)), isNull);
    });
  });

  group('week boundaries', () {
    test('assigned on a Sunday: week 1 is the week that ends that day', () {
      final a = _assignment('2026-11-08', [
        _row('w1-sun', 1, 'Sunday'),
        _row('w1-mon', 1, 'Monday'),
        _row('w2-mon', 2, 'Monday'),
      ]);
      final w = assignedProgramToWorkouts(a);
      expect(_dateOf(w, 'w1-mon'), DateTime(2026, 11, 2));
      expect(_dateOf(w, 'w1-sun'), DateTime(2026, 11, 8));
      expect(_dateOf(w, 'w2-mon'), DateTime(2026, 11, 9));
      // Sunday night, then the first minute of Monday.
      expect(_todayTitle(a, DateTime(2026, 11, 8, 23, 59)), 'W1 Sunday');
      expect(_todayTitle(a, DateTime(2026, 11, 9, 0, 0)), 'W2 Monday');
    });

    test('assigned on a Monday: week 1 starts that day', () {
      final a = _assignment('2026-11-02', [
        _row('w1-mon', 1, 'Monday'),
        _row('w1-sun', 1, 'Sunday'),
      ]);
      final w = assignedProgramToWorkouts(a);
      expect(_dateOf(w, 'w1-mon'), DateTime(2026, 11, 2));
      expect(_dateOf(w, 'w1-sun'), DateTime(2026, 11, 8));
      expect(_todayTitle(a, DateTime(2026, 11, 2, 6)), 'W1 Monday');
    });

    test('across a month and a year end', () {
      // Wednesday 30 Dec 2026: week 1 is Mon 28 Dec – Sun 3 Jan.
      final a = _assignment('2026-12-30', [
        _row('w1-sun', 1, 'Sunday'),
        _row('w2-mon', 2, 'Monday'),
      ]);
      final w = assignedProgramToWorkouts(a);
      expect(_dateOf(w, 'w1-sun'), DateTime(2027, 1, 3));
      expect(_dateOf(w, 'w2-mon'), DateTime(2027, 1, 4));
      expect(_todayTitle(a, DateTime(2027, 1, 3, 12)), 'W1 Sunday');
      expect(_todayTitle(a, DateTime(2027, 1, 4, 12)), 'W2 Monday');
    });

    test('across a daylight-saving change the day does not drift', () {
      // US DST starts Sun 8 Mar 2026, EU Sun 29 Mar; both weeks are crossed.
      final a = _assignment('2026-03-04', [
        _row('w2-mon', 2, 'Monday'),
        _row('w4-mon', 4, 'Monday'),
      ]);
      final w = assignedProgramToWorkouts(a);
      expect(_dateOf(w, 'w2-mon'), DateTime(2026, 3, 9));
      expect(_dateOf(w, 'w4-mon'), DateTime(2026, 3, 23));
    });

    test('a DST change that skips midnight still gives the right day', () {
      // Chile skips 00:00 on Sun 6 Sep 2026, so that "midnight" is 01:00 in
      // America/Santiago. Home compares calendar days, not instants.
      final d = programDayDate(DateTime(2026, 9, 2), 1, 'Sunday')!;
      expect([d.year, d.month, d.day], [2026, 9, 6]);
      final a = _assignment('2026-09-02', [_row('w1-sun', 1, 'Sunday')]);
      expect(_todayTitle(a, DateTime(2026, 9, 6, 9)), 'W1 Sunday');
    });
  });

  group('re-assignment', () {
    test('the replacement program is dated from its own start date', () {
      // First program assigned Wed 4 Nov; replaced on Tue 17 Nov (week 3 of the
      // old one). `getMyAssignedProgram()` returns only the active row, so the
      // new program's week 1 is the week of 17 Nov, not of 4 Nov.
      final replacement = _assignment('2026-11-17', [
        _row('new-w1-tue', 1, 'Tuesday', title: 'New program day 1'),
        _row('new-w1-wed', 1, 'Wednesday'),
      ])..['id'] = 'asg-2';
      final w = assignedProgramToWorkouts(replacement);
      expect(_dateOf(w, 'new-w1-tue'), DateTime(2026, 11, 17));
      expect(_dateOf(w, 'new-w1-wed'), DateTime(2026, 11, 18));
      expect(_todayTitle(replacement, DateTime(2026, 11, 17)), 'New program day 1');
      // Its week 1 Tuesday is not placed in the old program's week 1.
      expect(_todayTitle(replacement, DateTime(2026, 11, 3)), isNull);
    });
  });

  group('self-generated plans are unchanged', () {
    test('no coach on the assignment: undated, and Home offers nothing', () {
      // `generate_client_plan` writes coach_id null and start_date by default.
      final selfGuided =
          _assignment('2026-11-04', [_row('w1-wed', 1, 'Wednesday')], coachId: null);
      expect(_dateOf(assignedProgramToWorkouts(selfGuided), 'w1-wed'), isNull);
      expect(_todayTitle(selfGuided, DateTime(2026, 11, 4)), isNull);
    });
  });

  group('nothing is guessed', () {
    test('no start date: undated, and Home offers nothing', () {
      final a = _assignment(null, [_row('w1-wed', 1, 'Wednesday')]);
      expect(_dateOf(assignedProgramToWorkouts(a), 'w1-wed'), isNull);
      expect(_todayTitle(a, DateTime(2026, 11, 4)), isNull);
    });

    test('a day label or week outside the contract: undated', () {
      final a = _assignment('2026-11-04', [
        _row('bad-day', 1, 'Wednesday')..['day_of_week'] = 'Day 3',
        _row('bad-week', 1, 'Wednesday')..['week_number'] = 0,
        _row('no-week', 1, 'Wednesday')..['week_number'] = null,
      ]);
      final w = assignedProgramToWorkouts(a);
      for (final id in ['bad-day', 'bad-week', 'no-week']) {
        expect(_dateOf(w, id), isNull, reason: id);
      }
      expect(_todayTitle(a, DateTime(2026, 11, 4)), isNull);
    });
  });

  test('the client\'s provider decodes through this rule', () {
    // The tests above exercise `assignedProgramToWorkouts`; this pins that the
    // real assignment read uses it rather than the undated per-row decode.
    final src = File('lib/features/workout/domain/workout_provider.dart')
        .readAsStringSync();
    final body = src.substring(src.indexOf('final assignedWorkoutsProvider'));
    final provider = body.substring(0, body.indexOf('});'));
    expect(provider, contains('getMyAssignedProgram()'));
    expect(provider, contains('assignedProgramToWorkouts(program,'));
    expect(provider, isNot(contains('map(programWorkoutToWorkout)')));
  });
}
