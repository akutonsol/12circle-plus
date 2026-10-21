// WKT-110 — completed sets are historical records.
//
// QA found that a set which is already confirmed still exposed editable
// Weight/Reps/RPE fields, so resuming a partially completed workout let the
// client silently rewrite results that had already been logged. These tests
// drive the production rules in `ActiveWorkoutNotifier` — the state boundary
// every UI path and every database write goes through — so a completed set is
// immutable no matter which path reaches it.
//
// Resume is deliberately exercised alongside: locking completed sets must not
// cost the ability to open a 10/15 workout and carry on from set 11.
import 'package:flutter_test/flutter_test.dart';
import 'package:circle_fitness/features/workout/data/models/exercise_model.dart';
import 'package:circle_fitness/features/workout/data/models/workout_model.dart';
import 'package:circle_fitness/features/workout/domain/workout_provider.dart';

/// Two exercises of fifteen sets each. Every set carries the id the app builds
/// it with, and the notifier is addressed through those sets rather than
/// through list positions — which is the point: nothing below names a set by
/// where it sits.
final _workout = Workout(
  id: 'w-1',
  title: 'Lower Body',
  description: '',
  estimatedDuration: 45,
  difficulty: 'Intermediate',
  category: 'Strength',
  exercises: [
    for (final id in ['ex-1', 'ex-2'])
      WorkoutExercise(
        exercise: Exercise(
          id: id,
          name: 'Exercise $id',
          category: 'Strength',
          muscleGroup: 'Legs',
          equipment: 'Barbell',
          difficulty: 'Intermediate',
          description: '',
          instructions: const [],
        ),
        sets: [
          for (var n = 1; n <= 15; n++)
            WorkoutSet(setNumber: n, reps: 10, weightKg: 60, restSeconds: 90),
        ],
      ),
  ],
);

/// Set number [n] of [exerciseId] — the set itself, not an index into anything.
WorkoutSet _set(String exerciseId, int n) => _workout.exercises
    .firstWhere((e) => e.exercise.id == exerciseId)
    .sets
    .firstWhere((s) => s.setNumber == n);

/// Mirrors `WorkoutService.getSessionCompletedSets`: each persisted set log
/// carries the identity of the set it recorded, its set number, and its
/// recorded completion state. A log exists for any set the client edited, so
/// `completed` defaults to true here only because these fixtures describe
/// confirmed sets.
Map<String, List<Map<String, dynamic>>> _logs(
  String exerciseId,
  List<Map<String, dynamic>> sets,
) =>
    {
      exerciseId: [
        for (final s in sets)
          {
            'completed': true,
            'set_id': _set(exerciseId, s['set_number'] as int).id,
            ...s,
          },
      ],
    };

void main() {
  late ActiveWorkoutNotifier notifier;

  setUp(() {
    notifier = ActiveWorkoutNotifier()..beginSession('session-1');
  });

  // ── TEST 1 — an incomplete set is fully editable ─────────────────────────
  group('WKT-110 an incomplete set is editable', () {
    test('weight, reps and RPE all take new values', () {
      expect(
        notifier.setSetData(_set('ex-1', 1), {'reps': 8, 'weight': 60.0, 'rpe': 7.0}, exerciseInstanceId: 'ex-1'),
        isTrue,
      );
      expect(
        notifier.setSetData(_set('ex-1', 1), {'reps': 10, 'weight': 65.0, 'rpe': 8.5}, exerciseInstanceId: 'ex-1'),
        isTrue,
        reason: 'an incomplete set can be revised as often as the client likes',
      );

      final set = notifier.setData(_set('ex-1', 1).id);
      expect(set['reps'], 10);
      expect(set['weight'], 65.0);
      expect(set['rpe'], 8.5);
      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isFalse);
    });

    test('notes are editable and an unchanged re-emit is not a write', () {
      notifier.setSetData(_set('ex-1', 1), {'notes': 'felt light'}, exerciseInstanceId: 'ex-1');
      expect(notifier.setData(_set('ex-1', 1).id)['notes'], 'felt light');

      expect(
        notifier.setSetData(_set('ex-1', 1), {'notes': 'felt light'}, exerciseInstanceId: 'ex-1'),
        isFalse,
        reason: 'a blur repeating what is already stored must not re-persist',
      );
    });

    test('a value edit can never smuggle in completion', () {
      notifier.setSetData(_set('ex-1', 1), {'reps': 8, 'completed': true}, exerciseInstanceId: 'ex-1');
      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isFalse);
      expect(notifier.setData(_set('ex-1', 1).id)['reps'], 8);
    });
  });

  // ── TEST 2 — completing records the final values ─────────────────────────
  group('WKT-110 completing a set records what was entered', () {
    test('the values in the fields become the recorded result', () {
      notifier.setSetData(_set('ex-1', 1), {'reps': 8, 'weight': 60.0}, exerciseInstanceId: 'ex-1');

      expect(
        notifier.completeSet(_set('ex-1', 1),
            {'reps': 10, 'weight': 90.0, 'rpe': 5.0, 'notes': 'PR'}, 'ex-1'),
        isTrue,
      );

      final set = notifier.setData(_set('ex-1', 1).id);
      expect(set['completed'], isTrue);
      expect(set['reps'], 10);
      expect(set['weight'], 90.0);
      expect(set['rpe'], 5.0);
      expect(set['notes'], 'PR');
    });

    test('completing one set leaves its neighbours alone', () {
      notifier.completeSet(_set('ex-1', 1), {'reps': 10, 'weight': 90.0}, 'ex-1');
      notifier.setSetData(_set('ex-1', 2), {'reps': 9, 'weight': 90.0}, exerciseInstanceId: 'ex-1');

      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isTrue);
      expect(notifier.isSetCompleted(_set('ex-1', 2).id), isFalse);
      expect(notifier.setData(_set('ex-1', 2).id)['reps'], 9,
          reason: 'the next set stays editable while an earlier one is locked');
    });
  });

  // ── TEST 3 — a completed set is immutable ────────────────────────────────
  group('WKT-110 a completed set is immutable', () {
    setUp(() {
      notifier.completeSet(_set('ex-1', 1),
          {'reps': 10, 'weight': 90.0, 'rpe': 5.0, 'notes': 'solid'}, 'ex-1');
    });

    test('weight, reps and RPE reject an ordinary edit', () {
      expect(
        notifier.setSetData(_set('ex-1', 1), {'reps': 1, 'weight': 5.0, 'rpe': 10.0}, exerciseInstanceId: 'ex-1'),
        isFalse,
        reason: 'the ordinary edit path must refuse a recorded result',
      );

      final set = notifier.setData(_set('ex-1', 1).id);
      expect(set['reps'], 10);
      expect(set['weight'], 90.0);
      expect(set['rpe'], 5.0);
    });

    test('the single-field edit path is refused too', () {
      notifier.updateSet(_set('ex-1', 1), 'weight', 5.0, exerciseInstanceId: 'ex-1');
      expect(notifier.setData(_set('ex-1', 1).id)['weight'], 90.0);
    });

    test('an edit mixing a note with new numbers keeps only the note', () {
      expect(
        notifier.setSetData(_set('ex-1', 1), {'reps': 1, 'weight': 5.0, 'notes': 'tweak'}, exerciseInstanceId: 'ex-1'),
        isTrue,
      );

      final set = notifier.setData(_set('ex-1', 1).id);
      expect(set['notes'], 'tweak', reason: 'notes stay editable when completed');
      expect(set['reps'], 10);
      expect(set['weight'], 90.0);
    });

    test('completion cannot be toggled off', () {
      expect(notifier.completeSet(_set('ex-1', 1), const {}, 'ex-1'), isFalse);
      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isTrue);

      // Nor through a value edit claiming completion is false.
      notifier.setSetData(_set('ex-1', 1), {'completed': false}, exerciseInstanceId: 'ex-1');
      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isTrue);
    });

    test('re-tapping complete does not rewrite the recorded values', () {
      expect(
        notifier.completeSet(_set('ex-1', 1), {'reps': 1, 'weight': 5.0}, 'ex-1'),
        isFalse,
      );
      expect(notifier.setData(_set('ex-1', 1).id)['reps'], 10);
      expect(notifier.setData(_set('ex-1', 1).id)['weight'], 90.0);
    });
  });

  // ── TEST 4 — completed values survive a reload ───────────────────────────
  group('WKT-110 completed values persist across a reload', () {
    test('restored logs come back completed, with their recorded values', () {
      notifier.completeSet(_set('ex-1', 1), {'reps': 10, 'weight': 90.0, 'rpe': 5.0}, 'ex-1');

      // Leaving and reopening the workout: state is rebuilt from set logs.
      final reopened = ActiveWorkoutNotifier()..beginSession('session-1');
      reopened.restoreFromLogs(_workout, _logs('ex-1', [
        {'set_number': 1, 'reps': 10, 'weight': 90.0, 'rpe': 5.0},
      ]));

      final set = reopened.setData(_set('ex-1', 1).id);
      expect(set['completed'], isTrue);
      expect(set['reps'], 10);
      expect(set['weight'], 90.0);
      expect(set['rpe'], 5.0);
    });

    test('a restored set is locked exactly like one completed in-session', () {
      notifier.restoreFromLogs(_workout, _logs('ex-1', [
        {'set_number': 1, 'reps': 10, 'weight': 90.0},
      ]));

      expect(notifier.setSetData(_set('ex-1', 1), {'weight': 5.0}, exerciseInstanceId: 'ex-1'), isFalse);
      expect(notifier.setData(_set('ex-1', 1).id)['weight'], 90.0);
      expect(notifier.completeSet(_set('ex-1', 1), const {}, 'ex-1'), isFalse);
    });

    test('a log restores onto the set it belongs to, not the next free slot', () {
      notifier.restoreFromLogs(_workout, _logs('ex-1', [
        {'set_number': 3, 'reps': 6, 'weight': 100.0},
      ]));

      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isFalse,
          reason: 'set 1 was never logged, so it must not appear locked');
      expect(notifier.isSetCompleted(_set('ex-1', 3).id), isTrue);
      expect(notifier.setData(_set('ex-1', 3).id)['reps'], 6);
    });
  });

  // ── TEST 5 — resume still works ──────────────────────────────────────────
  group('WKT-110 resuming a partially completed workout', () {
    test('10 of 15 sets completed resumes editable at set 11', () {
      notifier.restoreFromLogs(_workout, _logs('ex-1', [
        for (var i = 1; i <= 10; i++)
          {'set_number': i, 'reps': 10, 'weight': 60.0 + i},
      ]));

      // The first ten stay completed and locked…
      for (var i = 0; i < 10; i++) {
        expect(notifier.isSetCompleted(_set('ex-1', i + 1).id), isTrue);
        expect(notifier.setSetData(_set('ex-1', i + 1), {'weight': 1.0}, exerciseInstanceId: 'ex-1'), isFalse);
        expect(notifier.setData(_set('ex-1', i + 1).id)['weight'], 61.0 + i);
      }

      // …and the client carries on from set 11.
      expect(notifier.isSetCompleted(_set('ex-1', 11).id), isFalse);
      expect(notifier.setSetData(_set('ex-1', 11), {'reps': 8, 'weight': 75.0}, exerciseInstanceId: 'ex-1'), isTrue);
      expect(notifier.completeSet(_set('ex-1', 11), {'reps': 8, 'weight': 75.0}, 'ex-1'), isTrue);

      final completed = notifier.completedSetCount;
      expect(completed, 11, reason: 'progress counts every completed set once');
    });

    test('a set that was typed into but never confirmed resumes editable', () {
      // Set 1 was confirmed; set 2 only had values typed into it, which the
      // app persists too. Only the confirmed one comes back locked.
      notifier.restoreFromLogs(_workout, {
        'ex-1': [
          {'completed': true, 'set_number': 1, 'reps': 10, 'weight': 60.0},
          {'completed': false, 'set_number': 2, 'reps': 10, 'weight': 62.5},
        ],
      });

      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isTrue);
      expect(notifier.isSetCompleted(_set('ex-1', 2).id), isFalse);

      // …and it is still fully editable, then completable.
      expect(notifier.setSetData(_set('ex-1', 2), {'weight': 65.0}, exerciseInstanceId: 'ex-1'), isTrue);
      expect(notifier.setData(_set('ex-1', 2).id)['weight'], 65.0);
      expect(notifier.completeSet(_set('ex-1', 2), {'reps': 9, 'weight': 65.0}, 'ex-1'), isTrue);

      final completed = notifier.completedSetCount;
      expect(completed, 2,
          reason: 'progress counts confirmed sets, not merely edited ones');
    });

    test('the completed count is unaffected by refused edits', () {
      notifier.restoreFromLogs(_workout, _logs('ex-1', [
        {'set_number': 1, 'reps': 10, 'weight': 60.0},
        {'set_number': 2, 'reps': 10, 'weight': 62.5},
      ]));

      notifier.setSetData(_set('ex-1', 1), {'weight': 5.0}, exerciseInstanceId: 'ex-1');
      notifier.completeSet(_set('ex-1', 2), const {}, 'ex-1');

      final completed = notifier.completedSetCount;
      expect(completed, 2);
    });
  });

  // ── TEST 6 — the deliberate correction workflow ──────────────────────────
  group('WKT-110 Edit Completed Set', () {
    setUp(() {
      notifier.completeSet(_set('ex-1', 1),
          {'reps': 10, 'weight': 90.0, 'rpe': 5.0, 'notes': 'solid'}, 'ex-1');
    });

    test('corrects weight, reps and RPE while the set stays completed', () {
      expect(
        notifier.applyCorrection(_set('ex-1', 1), reps: 8, weight: 92.5, rpe: 8.0),
        isTrue,
      );

      final set = notifier.setData(_set('ex-1', 1).id);
      expect(set['reps'], 8);
      expect(set['weight'], 92.5);
      expect(set['rpe'], 8.0);
      expect(set['completed'], isTrue,
          reason: 'a correction fixes the record, it does not reopen the set');
      expect(set['notes'], 'solid',
          reason: 'fields the correction left alone keep their recorded value');
    });

    test('a corrected set is locked again immediately', () {
      notifier.applyCorrection(_set('ex-1', 1), weight: 92.5);

      expect(notifier.setSetData(_set('ex-1', 1), {'weight': 5.0}, exerciseInstanceId: 'ex-1'), isFalse);
      expect(notifier.setData(_set('ex-1', 1).id)['weight'], 92.5);
    });

    test('a correction can clear an RPE that should not have been logged', () {
      notifier.applyCorrection(_set('ex-1', 1), clearRpe: true);

      expect(notifier.setData(_set('ex-1', 1).id)['rpe'], isNull);
      expect(notifier.isSetCompleted(_set('ex-1', 1).id), isTrue);
    });

    test('the corrected value is what a reload restores', () {
      notifier.applyCorrection(_set('ex-1', 1), reps: 8, weight: 92.5);
      final corrected = notifier.setData(_set('ex-1', 1).id);

      // What the client persisted is what the set logs return on resume.
      final reopened = ActiveWorkoutNotifier()..beginSession('session-1');
      reopened.restoreFromLogs(_workout, _logs('ex-1', [
        {
          'set_number': 1,
          'reps': corrected['reps'],
          'weight': corrected['weight'],
        },
      ]));

      expect(reopened.setData(_set('ex-1', 1).id)['reps'], 8);
      expect(reopened.setData(_set('ex-1', 1).id)['weight'], 92.5);
      expect(reopened.isSetCompleted(_set('ex-1', 1).id), isTrue);
    });

    test('it refuses a set that was never completed', () {
      notifier.setSetData(_set('ex-2', 1), {'reps': 8, 'weight': 60.0}, exerciseInstanceId: 'ex-2');

      expect(
        notifier.applyCorrection(_set('ex-2', 1), reps: 12),
        isFalse,
        reason: 'an incomplete set is edited normally, not corrected',
      );
      expect(notifier.setData(_set('ex-2', 1).id)['reps'], 8);
      expect(notifier.isSetCompleted(_set('ex-2', 1).id), isFalse,
          reason: 'a correction must never complete a set as a side effect',
      );
    });
  });
}
