import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/dashboard/domain/session_as_log.dart';

/// The one piece of new logic in the `workout_logs` → `workout_sessions`
/// repoint: the two tables record duration in different units.
///
/// Everything else about that change is a query targeting a table a coach is
/// authorized to read, which `SEC-G3` asserts against the migrations rather
/// than against a mock.
void main() {
  group('minutesFromSeconds', () {
    test('whole minutes convert exactly', () {
      expect(minutesFromSeconds(0), 0);
      expect(minutesFromSeconds(60), 1);
      expect(minutesFromSeconds(2880), 48); // the board's 48 min session
    });

    test('part minutes round rather than truncate', () {
      // 89 s is closer to 1 minute than 2; 91 s is closer to 2.
      expect(minutesFromSeconds(89), 1);
      expect(minutesFromSeconds(91), 2);
      // A 29-second session rounds to 0, not to 1 — it did not last a minute.
      expect(minutesFromSeconds(29), 0);
      expect(minutesFromSeconds(31), 1);
    });

    test('absent, null and negative all read as zero', () {
      expect(minutesFromSeconds(null), 0);
      expect(minutesFromSeconds('not a number'), 0);
      expect(minutesFromSeconds(0), 0);

      // A LARGE negative, deliberately. `-10 / 60` rounds to 0 with or without
      // the `<= 0` guard, so a small one cannot tell the two apart — a
      // mutation dropping the guard survived on exactly that. `-90 / 60`
      // rounds to -2, and a workout of minus two minutes would reach the
      // coach's adherence count.
      expect(minutesFromSeconds(-90), 0);
      expect(minutesFromSeconds(-3600), 0);
    });

    test('a double is accepted — the column is numeric in places', () {
      expect(minutesFromSeconds(120.0), 2);
      expect(minutesFromSeconds(150.4), 3);
    });
  });

  group('sessionAsWorkoutLog', () {
    test('adds duration_minutes and keeps every other field', () {
      final row = {
        'user_id': 'u1',
        'workout_title': 'Lower body — strength',
        'completed_at': '2026-09-23T18:00:00Z',
        'duration_seconds': 2880,
      };
      final out = sessionAsWorkoutLog(row);

      expect(out['duration_minutes'], 48);
      expect(out['user_id'], 'u1');
      expect(out['workout_title'], 'Lower body — strength');
      expect(out['completed_at'], '2026-09-23T18:00:00Z');
      // The source field is not stripped — nothing depends on that, and
      // dropping it would make the row harder to trace back to its table.
      expect(out['duration_seconds'], 2880);
    });

    test('a row with no duration still translates', () {
      final out = sessionAsWorkoutLog({'user_id': 'u1'});
      expect(out['duration_minutes'], 0);
      expect(out['user_id'], 'u1');
    });

    test('the input is not mutated', () {
      final row = {'user_id': 'u1', 'duration_seconds': 60};
      sessionAsWorkoutLog(row);
      expect(row.containsKey('duration_minutes'), isFalse);
    });
  });
}
