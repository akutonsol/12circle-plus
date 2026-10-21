import 'package:flutter_test/flutter_test.dart';

import 'package:circle_fitness/features/workout/domain/workout_save.dart';

// EC-05 / N-07 · "Workout completion swallows persistence and celebrates
// anyway" — docs/MASTER_REMEDIATION_REGISTRY.md:53, status CONFIRMED.
//
// `_completeWorkout` ran four network writes. One was swallowed and three were
// unguarded:
//
//     await _workoutService.logWorkout(log);            // UNGUARDED
//     if (_sessionId != null) {
//       try { await _sessions.completeSession(…); }
//       catch (_) {}                                    // SWALLOWED
//     }
//     await ScoreService().addWorkoutPoints();          // UNGUARDED
//     await ScoreEngine().workoutCompleted(workout.id); // UNGUARDED
//     ref.read(activeWorkoutProvider.notifier).reset();
//     … showDialog(WorkoutCompleteDialog(…))
//
// A throw from an unguarded call propagated out, so the trailing
// `setState(() => _saving = false)` never ran; `_saving` stayed true and the
// button — `onPressed: _saving ? null : _completeWorkout` — was permanently
// dead, with no dialog and no message.
//
// A throw from completeSession was discarded, so the sets were reset and the
// celebration went up over a row the server still had as `in_progress`. That
// one crosses a boundary: `workout_sessions` is the table a coach can read
// (migration 100) and the coach surfaces filter on status = 'completed', so a
// swallowed failure hid a finished session from the coach while telling the
// client it had worked.

void main() {
  group('what counts as filed', () {
    test('the log failing is a failure, whatever else happened', () {
      expect(
        workoutSaveOutcome(
            logWritten: false, sessionCompleted: true, scored: true),
        WorkoutSave.failed,
      );
    });

    test('the session failing is a failure — it was swallowed', () {
      expect(
        workoutSaveOutcome(
            logWritten: true, sessionCompleted: false, scored: true),
        WorkoutSave.failed,
        reason: 'this is the case that reset the sets and celebrated over an '
            'in_progress row, and hid the session from the coach',
      );
    });

    test('no session to complete is not a failure', () {
      // `completeSession` only ran when `_sessionId != null`. Nothing to do is
      // not the same as something that did not work.
      expect(
        workoutSaveOutcome(
            logWritten: true, sessionCompleted: null, scored: true),
        WorkoutSave.scored,
      );
      expect(
        workoutSaveOutcome(
            logWritten: true, sessionCompleted: null, scored: false),
        WorkoutSave.saved,
      );
    });

    test('score failing alone does NOT lose the workout', () {
      // Points and the engine are derived and recomputable. Making someone
      // retry a finished workout for them would be the opposite mistake.
      expect(
        workoutSaveOutcome(
            logWritten: true, sessionCompleted: true, scored: false),
        WorkoutSave.saved,
      );
    });

    test('everything landing is scored', () {
      expect(
        workoutSaveOutcome(
            logWritten: true, sessionCompleted: true, scored: true),
        WorkoutSave.scored,
      );
    });
  });

  group('what the screen may do next', () {
    test('a failure may NOT reset, invalidate or celebrate', () {
      expect(mayFinishWorkout(WorkoutSave.failed), isFalse,
          reason: 'the local sets are the only remaining copy of what the user '
              'did; resetting them to show a celebration destroys it');
    });

    test('saved and scored both finish', () {
      expect(mayFinishWorkout(WorkoutSave.saved), isTrue);
      expect(mayFinishWorkout(WorkoutSave.scored), isTrue);
    });

    test('every outcome is decided — none falls through', () {
      for (final s in WorkoutSave.values) {
        expect(() => mayFinishWorkout(s), returnsNormally);
      }
      expect(WorkoutSave.values, hasLength(3));
    });
  });

  group('the failure copy is this screen\'s own', () {
    test('it reuses the language already in the file', () {
      // `_RestoreFailedView` and the feedback sheet's `_saveFailed` row say
      // the same thing the same way.
      expect(workoutSaveFailedMessage,
          'Could not save your workout. Check your connection and try again.');
      expect(workoutSaveRetryLabel, 'Try Again');
    });

    test('the exception is not interpolated into it', () {
      // F-2 and F-16 were raised about exactly that.
      expect(workoutSaveFailedMessage, isNot(contains('\$')));
      expect(workoutSaveFailedMessage.toLowerCase(),
          isNot(contains('exception')));
    });
  });
}
