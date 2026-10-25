import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/coach/domain/program_readiness.dart';

void main() {
  group('programDayCount / isKnownEmptyProgram', () {
    test('reads the PostgREST embedded count', () {
      expect(programDayCount({'program_workouts': [{'count': 4}]}), 4);
      expect(isKnownEmptyProgram({'program_workouts': [{'count': 4}]}), isFalse);
    });

    test('a program with zero training days is known-empty', () {
      expect(programDayCount({'program_workouts': [{'count': 0}]}), 0);
      expect(isKnownEmptyProgram({'program_workouts': [{'count': 0}]}), isTrue);
    });

    test('an absent or malformed count is UNKNOWN, never treated as empty', () {
      for (final p in <Map<String, dynamic>>[
        {},
        {'program_workouts': null},
        {'program_workouts': []},
        {'program_workouts': [{'count': 'x'}]},
        {'program_workouts': 'nope'},
      ]) {
        expect(programDayCount(p), isNull, reason: '$p');
        expect(isKnownEmptyProgram(p), isFalse, reason: '$p must not block assignment');
      }
    });
  });
}
