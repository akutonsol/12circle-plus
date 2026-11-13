import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/home/domain/home_session_card.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/data/program_schedule.dart';
import 'package:circle_fitness/features/workout/domain/week_row.dart';

/// A finished training day is no longer offered as today's session.
///
/// The defect: `Workout.isCompleted` was never read from the database, so after
/// the client finished today's assigned workout, Home, Activity and the
/// Workouts tab kept offering it for the rest of the day. A day is now done
/// when the client has a `completed` session for it under this assignment.
///
/// Every fixture is persisted data — the assignment `getMyAssignedProgram()`
/// returns and the `workout_sessions` rows `getMyCompletedProgramSessions()`
/// reads — through the real decoder. None sets `isCompleted` by hand.

/// One training day as the Program Builder saves it.
Map<String, dynamic> _row(String id, int week, String day) => {
      'id': id,
      'program_id': 'prog-1',
      'title': 'W$week $day',
      'week_number': week,
      'day_of_week': day,
      'estimated_minutes': 40,
      'exercises': [
        {
          'exercise_instance_id': 'ex-$id-1',
          'name': 'Back Squat',
          'sets': 3,
          'reps': 8,
        },
      ],
    };

/// Assigned Wednesday 4 Nov 2026 at 14:00 UTC; week 1 runs 2-8 Nov.
Map<String, dynamic> _assignment({
  String? assignedAt = '2026-11-04T14:00:00.000000+00:00',
  String? coachId = 'coach-1',
}) =>
    {
      'id': 'asg-1',
      'program_id': 'prog-1',
      'client_id': 'client-1',
      'coach_id': coachId,
      'start_date': '2026-11-04',
      'current_week': 1,
      'status': 'active',
      'assigned_at': assignedAt,
      'workouts': [
        _row('w1-mon', 1, 'Monday'),
        _row('w1-wed', 1, 'Wednesday'),
        _row('w1-fri', 1, 'Friday'),
        _row('w2-wed', 2, 'Wednesday'),
      ],
    };

/// A `workout_sessions` row as `select('workout_id, status, completed_at')`
/// returns it.
Map<String, dynamic> _session(String workoutId,
        {String status = 'completed', String? completedAt}) =>
    {
      'workout_id': workoutId,
      'status': status,
      'completed_at': completedAt,
    };

/// Wednesday 4 Nov, 18:30 local — after today's session was finished.
final _wedEvening = DateTime(2026, 11, 4, 18, 30);

List<Workout> _decode(Map<String, dynamic> a, List<Map<String, dynamic>> s) =>
    assignedProgramToWorkouts(a, sessions: s);

Workout _day(List<Workout> w, String id) => w.firstWhere((x) => x.id == id);

String? _todayTitle(Map<String, dynamic> a, List<Map<String, dynamic>> s,
        DateTime now) =>
    homeSession(AsyncValue.data(_decode(a, s)), now: now).title;

void main() {
  group('a completed session finishes its training day', () {
    final done = [
      _session('w1-wed', completedAt: '2026-11-04T17:05:00.000000+00:00'),
    ];

    test('the day decodes as completed', () {
      expect(_day(_decode(_assignment(), done), 'w1-wed').isCompleted, isTrue);
    });

    test('Home no longer offers it for the rest of the day', () {
      expect(_todayTitle(_assignment(), done, _wedEvening), isNull);
      expect(
          homeSession(AsyncValue.data(_decode(_assignment(), done)),
                  now: _wedEvening)
              .canBegin,
          isFalse);
    });

    test('its This Week row reads Done', () {
      expect(weekRowKind(_day(_decode(_assignment(), done), 'w1-wed'),
              now: _wedEvening),
          WeekRowKind.done);
    });

    test('only that day: the rest of the week stays on offer', () {
      final w = _decode(_assignment(), done);
      for (final id in ['w1-mon', 'w1-fri', 'w2-wed']) {
        expect(_day(w, id).isCompleted, isFalse, reason: id);
      }
      // Next week's Wednesday is a different training day with its own id.
      expect(_todayTitle(_assignment(), done, DateTime(2026, 11, 11, 9)),
          'W2 Wednesday');
      expect(_todayTitle(_assignment(), done, DateTime(2026, 11, 6, 9)),
          'W1 Friday');
    });
  });

  group('an unfinished session hides nothing', () {
    test('no session yet: today is offered', () {
      expect(_todayTitle(_assignment(), const [], _wedEvening), 'W1 Wednesday');
    });

    test('in progress: still offered, so it can be resumed or finished', () {
      final s = [_session('w1-wed', status: 'in_progress')];
      expect(_day(_decode(_assignment(), s), 'w1-wed').isCompleted, isFalse);
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });

    test('abandoned: still offered', () {
      final s = [
        _session('w1-wed',
            status: 'abandoned', completedAt: '2026-11-04T17:05:00Z'),
      ];
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });

    test('completed with no completed_at: not counted', () {
      final s = [_session('w1-wed')];
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });

    test('a session of another workout does not finish today', () {
      final s = [
        _session('library-workout-7', completedAt: '2026-11-04T17:05:00Z'),
        _session('', completedAt: '2026-11-04T17:05:00Z'),
      ];
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });
  });

  group('re-assignment starts clean', () {
    test('a day finished under an earlier assignment is offered again', () {
      // The same program re-assigned at 14:00 reuses its program_workouts ids.
      // Wednesday's session was finished at 09:00, under the old assignment.
      final s = [_session('w1-wed', completedAt: '2026-11-04T09:00:00Z')];
      expect(_day(_decode(_assignment(), s), 'w1-wed').isCompleted, isFalse);
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });

    test('finished again under the new assignment: done', () {
      final s = [
        _session('w1-wed', completedAt: '2026-11-04T09:00:00Z'),
        _session('w1-wed', completedAt: '2026-11-04T16:00:00Z'),
      ];
      expect(_todayTitle(_assignment(), s, _wedEvening), isNull);
    });

    test('completed at the instant of assignment counts', () {
      final s = [_session('w1-wed', completedAt: '2026-11-04T14:00:00Z')];
      expect(_day(_decode(_assignment(), s), 'w1-wed').isCompleted, isTrue);
    });

    test('instants compare across offsets, not as wall-clock text', () {
      // 09:30-05:00 is 14:30 UTC: after the 14:00 UTC assignment.
      final s = [_session('w1-wed', completedAt: '2026-11-04T09:30:00-05:00')];
      expect(_day(_decode(_assignment(), s), 'w1-wed').isCompleted, isTrue);
    });
  });

  group('the day is done whenever it was finished', () {
    test('Monday made up on Wednesday marks Monday done, not Wednesday', () {
      final s = [_session('w1-mon', completedAt: '2026-11-04T15:00:00Z')];
      final w = _decode(_assignment(), s);
      expect(_day(w, 'w1-mon').isCompleted, isTrue);
      expect(_day(w, 'w1-wed').isCompleted, isFalse);
      expect(_todayTitle(_assignment(), s, _wedEvening), 'W1 Wednesday');
    });

    test('Friday finished early is not offered again on Friday', () {
      final s = [_session('w1-fri', completedAt: '2026-11-04T15:00:00Z')];
      expect(_todayTitle(_assignment(), s, DateTime(2026, 11, 6, 9)), isNull);
    });
  });

  group('nothing is hidden on a guess', () {
    test('no assigned_at: no day is marked done', () {
      final s = [_session('w1-wed', completedAt: '2026-11-04T17:05:00Z')];
      expect(_todayTitle(_assignment(assignedAt: null), s, _wedEvening),
          'W1 Wednesday');
    });

    test('a self-generated plan is unchanged: nothing marked done', () {
      final s = [_session('w1-wed', completedAt: '2026-11-04T17:05:00Z')];
      final w = _decode(_assignment(coachId: null), s);
      expect(w.every((x) => !x.isCompleted), isTrue);
    });
  });

  group('the app reads and refreshes through this rule', () {
    test('the provider passes the client\'s sessions to the decoder', () {
      final src = File('lib/features/workout/domain/workout_provider.dart')
          .readAsStringSync();
      final body = src.substring(src.indexOf('final assignedWorkoutsProvider'));
      final provider = body.substring(0, body.indexOf('});'));
      expect(provider, contains('getMyCompletedProgramSessions(program)'));
      expect(provider, contains('sessions:'));
    });

    test('the session read asks only for completed sessions of these days', () {
      final src = File('lib/features/coach/data/coach_program_service.dart')
          .readAsStringSync();
      final body = src.substring(src.indexOf('getMyCompletedProgramSessions('));
      final method = body.substring(0, body.indexOf('\n  }\n'));
      expect(method, contains(".from('workout_sessions')"));
      expect(method, contains(".eq('user_id', clientId)"));
      expect(method, contains(".eq('status', 'completed')"));
      expect(method, contains(".inFilter('workout_id', ids)"));
    });

    test('finishing a workout re-reads the assigned program', () {
      final src = File(
              'lib/features/workout/presentation/active_workout_screen.dart')
          .readAsStringSync();
      final body = src.substring(src.indexOf('Future<void> _completeWorkout()'));
      final method = body.substring(0, body.indexOf('\n  }\n'));
      // Through the app's container, not `ref`: the screen can be left while
      // the save is in flight, and `ref` then throws before reaching this
      // (workout_finish_after_leaving_test.dart).
      expect(method, contains('app.invalidate(assignedWorkoutsProvider)'));
    });
  });
}
