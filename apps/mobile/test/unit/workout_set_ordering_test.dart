// WKT-111 — persisted set order is authoritative.
//
// QA found that a workout saved as
//     set 1 → 200 lb × 13 @ 8, set 2 → 150 lb × 13 @ 6, set 3 → 100 lb × 10 @ 7
// came back after navigating away as
//     set 1 → 100 lb × 10 @ 7, set 2 → 150 lb × 13 @ 6, set 3 → 200 lb × 13 @ 8
// with each set's notes travelling along with its numbers — the signature of a
// reversed *reconstruction*, not a mis-numbered list.
//
// Root cause: postgrest-dart's `order()` defaults to `ascending: false` (the
// opposite of the JS client), so `.order('set_number')` in
// `WorkoutService.getSessionCompletedSets` returned set 3, 2, 1 — and the
// restore path then seated those rows by list position, putting set 3's values
// on set 1. Three independent defences are pinned below: the query now states
// its direction, every row carries the id of the set it recorded, and the
// restore path attaches a row to that set — so a row arriving out of order
// still lands on the set it belongs to.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';

// ── The QA scenario, as three uniquely identifiable sets ─────────────────────

const _exerciseId = 'ex-bench';

/// The workout definition the sets belong to. Each set has an id of its own,
/// which is what the logs are attached back to.
final _workout = Workout(
  id: 'w-bench',
  title: 'Bench Day',
  description: '',
  estimatedDuration: 40,
  difficulty: 'Intermediate',
  category: 'Strength',
  exercises: [
    WorkoutExercise(
      exercise: Exercise(
        id: _exerciseId,
        name: 'Bench Press',
        category: 'Strength',
        muscleGroup: 'Chest',
        equipment: 'Barbell',
        difficulty: 'Intermediate',
        description: '',
        instructions: const [],
      ),
      sets: [
        for (var n = 1; n <= 3; n++)
          WorkoutSet(setNumber: n, reps: 10, weightKg: 60, restSeconds: 90),
      ],
    ),
  ],
);

/// Set number [n] of the bench press — the set itself, not a list index.
WorkoutSet _set(int n) =>
    _workout.exercises.first.sets.firstWhere((s) => s.setNumber == n);

/// The workout exactly as QA entered it, in the order the workout defines.
const _entered = <Map<String, dynamic>>[
  {'set_number': 1, 'weight': 200.0, 'reps': 13, 'rpe': 8.0, 'notes': 'top set'},
  {'set_number': 2, 'weight': 150.0, 'reps': 13, 'rpe': 6.0, 'notes': 'backoff'},
  {'set_number': 3, 'weight': 100.0, 'reps': 10, 'rpe': 7.0, 'notes': 'burnout'},
];

/// One `workout_set_logs` row, shaped as `WorkoutService.saveSetLog` writes it.
/// Weight is stored in the `weight_kg` column; completion is a stored column
/// since migration 104.
Map<String, dynamic> _row(Map<String, dynamic> set) => {
      'session_id': 'session-1',
      'exercise_id': _exerciseId,
      'exercise_name': 'Bench Press',
      'set_id': _set(set['set_number'] as int).id,
      'set_number': set['set_number'],
      'reps': set['reps'],
      'weight_kg': set['weight'],
      'rpe': set['rpe'],
      'notes': set['notes'],
      'completed': true,
    };

/// Mirrors the read mapping in `WorkoutService.getSessionCompletedSets`:
/// database rows in whatever order the query returned them, grouped per
/// exercise. Nothing here re-sorts — reconstruction must not depend on it.
Map<String, List<Map<String, dynamic>>> _readBack(List<Map<String, dynamic>> rows) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final exId = row['exercise_id'] as String? ?? row['exercise_name'] as String? ?? '';
    result.putIfAbsent(exId, () => []).add({
      'completed': row['completed'] != false,
      'reps': row['reps'],
      'weight': row['weight_kg'],
      'rpe': row['rpe'],
      'notes': row['notes'],
      'set_id': row['set_id'],
      'set_number': row['set_number'],
    });
  }
  return result;
}

/// Asserts the reloaded workout is the workout QA entered: set N holds set N's
/// weight, reps, RPE *and* note — the last of these is what proves the values
/// were not merely renumbered.
void _expectOriginalOrder(ActiveWorkoutNotifier notifier) {
  for (final expected in _entered) {
    final set = _set(expected['set_number'] as int);
    final actual = notifier.setData(set.id);
    final label = 'set ${expected['set_number']}';
    expect(actual['weight'], expected['weight'], reason: '$label weight');
    expect(actual['reps'], expected['reps'], reason: '$label reps');
    expect(actual['rpe'], expected['rpe'], reason: '$label RPE');
    expect(actual['notes'], expected['notes'], reason: '$label notes');
  }
}

File _serviceSource() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('could not locate the Flutter package root');
    }
    dir = parent;
  }
  return File('${dir.path}/lib/features/workout/data/workout_service.dart');
}

void main() {
  // ── TEST 1 — the round trip QA performed ──────────────────────────────────
  group('WKT-111 a persisted workout reloads in its original order', () {
    test('three sets survive save → navigate away → reload', () {
      // Enter and confirm the three sets, in order.
      final live = ActiveWorkoutNotifier()..beginSession('session-1');
      for (final entered in _entered) {
        live.completeSet(_set(entered['set_number'] as int), {
          'weight': entered['weight'],
          'reps': entered['reps'],
          'rpe': entered['rpe'],
          'notes': entered['notes'],
        }, _exerciseId);
      }
      _expectOriginalOrder(live);

      // Navigating away persists a row per set; returning rebuilds from them.
      final rows = _entered.map(_row).toList();
      final reopened = ActiveWorkoutNotifier()..beginSession('session-1');
      reopened.restoreFromLogs(_workout, _readBack(rows));

      _expectOriginalOrder(reopened);
    });

    test('set 1 stays set 1 even when the rows come back reversed', () {
      // The exact pre-fix condition: the query handed back set 3, 2, 1.
      final reversed = _entered.reversed.map(_row).toList();
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.restoreFromLogs(_workout, _readBack(reversed));

      _expectOriginalOrder(notifier);
      expect(notifier.setData(_set(1).id)['weight'], 200.0,
          reason: 'the heaviest set was entered first and must reload first');
      expect(notifier.setData(_set(3).id)['weight'], 100.0);
    });

    test('every row arrival order reconstructs the same workout', () {
      // Row order is a property of the query, not of the data. Whatever order
      // rows arrive in, reconstruction must be identical.
      final orders = <List<Map<String, dynamic>>>[
        [_entered[0], _entered[1], _entered[2]],
        [_entered[2], _entered[1], _entered[0]],
        [_entered[1], _entered[2], _entered[0]],
        [_entered[2], _entered[0], _entered[1]],
      ];
      for (final order in orders) {
        final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
        notifier.restoreFromLogs(_workout, _readBack(order.map(_row).toList()));
        _expectOriginalOrder(notifier);
      }
    });

    test('notes stay attached to their own set', () {
      // The tell QA reported: notes moved with the numbers. Pinned explicitly
      // so a future regression can't pass by renumbering the UI alone.
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.restoreFromLogs(_workout, _readBack(_entered.reversed.map(_row).toList()));

      expect(notifier.setData(_set(1).id)['notes'], 'top set');
      expect(notifier.setData(_set(2).id)['notes'], 'backoff');
      expect(notifier.setData(_set(3).id)['notes'], 'burnout');
    });
  });

  // ── TEST 2 — gaps and partial workouts ────────────────────────────────────
  group('WKT-111 ordering holds for a partially logged workout', () {
    test('a gap leaves the unlogged set empty rather than shifting the rest', () {
      // Only sets 1 and 3 were confirmed. Set 2 must stay open — not be filled
      // by set 3 sliding down into it.
      final rows = [_row(_entered[2]), _row(_entered[0])];
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.restoreFromLogs(_workout, _readBack(rows));

      expect(notifier.setData(_set(1).id)['weight'], 200.0);
      expect(notifier.isSetCompleted(_set(2).id), isFalse,
          reason: 'set 2 was never logged and must resume editable');
      expect(notifier.setData(_set(3).id)['weight'], 100.0);
      expect(notifier.setData(_set(3).id)['notes'], 'burnout');
    });

    test('a resumed set stays editable and lands on its own row', () {
      final notifier = ActiveWorkoutNotifier()..beginSession('session-1');
      notifier.restoreFromLogs(_workout, _readBack([_row(_entered[0])]));

      // Carrying on with set 2 must not disturb the reloaded set 1.
      expect(
        notifier.setSetData(_set(2), {'weight': 155.0, 'reps': 12},
            exerciseInstanceId: _exerciseId),
        isTrue,
      );
      expect(notifier.setData(_set(1).id)['weight'], 200.0);
      expect(notifier.setData(_set(2).id)['weight'], 155.0);
    });
  });

  // ── TEST 3 — the root cause, pinned at the query ──────────────────────────
  group('WKT-111 set-log queries state their sort direction', () {
    test('no ordered query relies on the postgrest-dart default', () {
      // postgrest-dart orders DESCENDING when `ascending` is omitted, which is
      // the opposite of the JS client and the reason this defect existed. A
      // bare `.order(...)` in this service is therefore always a bug — this
      // guard is what stops the fix being undone by a plausible-looking edit.
      final source = _serviceSource();
      expect(source.existsSync(), isTrue,
          reason: 'workout_service.dart should exist at ${source.path}');

      final offenders = <String>[];
      final lines = source.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (!line.contains('.order(')) continue;
        if (line.contains('ascending:')) continue;
        offenders.add('  line ${i + 1}: ${line.trim()}');
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these queries inherit postgrest-dart\'s DESCENDING default; '
            'state `ascending:` explicitly:\n${offenders.join('\n')}',
      );
    });

    test('session set logs are read in ascending set order', () {
      final source = _serviceSource().readAsStringSync();
      // The read path behind resume. Ascending order is the authoritative one:
      // set 1 first, as the workout defines it.
      expect(source, contains("order('set_number', ascending: true)"));
    });
  });
}
