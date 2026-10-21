/// EC-05 / N-07 · "Workout completion swallows persistence and celebrates
/// anyway" — `docs/MASTER_REMEDIATION_REGISTRY.md:53`, status **CONFIRMED**.
///
/// ── WHAT `_completeWorkout` DID ────────────────────────────────────────────
/// ```dart
/// await _workoutService.logWorkout(log);            // UNGUARDED
///
/// if (_sessionId != null) {
///   try {
///     await _sessions.completeSession(…);
///   } catch (_) {}                                  // SWALLOWED
/// }
///
/// await ScoreService().addWorkoutPoints();          // UNGUARDED
/// await ScoreEngine().workoutCompleted(workout.id); // UNGUARDED
///
/// ref.read(activeWorkoutProvider.notifier).reset(); // state wiped
/// … showDialog(WorkoutCompleteDialog(…))            // celebration
/// ```
///
/// Two different failures, both bad, in opposite directions.
///
/// **A throw from `logWorkout` or either score call** propagates out of
/// `_completeWorkout`, so the trailing `setState(() => _saving = false)` never
/// runs. `_saving` stays `true`, and the Complete button is bound to
/// `onPressed: _saving ? null : _completeWorkout` — so it is **permanently
/// dead**. No dialog, no message, and no second attempt: the user is left on
/// the workout screen with a disabled button and a finished workout they
/// cannot file.
///
/// **A throw from `completeSession` is caught and discarded.** Execution
/// continues: the local state is reset, the session providers are invalidated,
/// and the celebration dialog is shown with the full stats — while the row is
/// still `in_progress` on the server. The client is told it worked.
///
/// That second one crosses a boundary. `workout_sessions` is the table a coach
/// can read (migration 100), and the coach surfaces filter on
/// `status = 'completed'` — so a swallowed failure means **the coach never
/// sees a session the client actually finished**, and the client has no way to
/// know.
///
/// ── THE RULE ───────────────────────────────────────────────────────────────
/// Modelled on `FeedbackDelivery`, which this file's own screen already uses:
/// *"the notes are safe and the screen must not claim a delivery."* The same
/// idea, one level up — do not claim a workout is filed until it is.
library;

enum WorkoutSave {
  /// An essential write did not land. The workout is **not** recorded.
  ///
  /// The local sets must NOT be reset and the celebration must NOT show:
  /// resetting would destroy the only remaining copy of what the user did.
  failed,

  /// The workout is recorded — the log and, where there was a session, its
  /// completion. Something derived did not land (points, engine), which is
  /// recomputable and is not worth making the user retry a finished workout
  /// for.
  saved,

  /// Everything landed.
  scored,
}

/// Which writes are essential is the whole decision, so it lives here.
///
/// [sessionCompleted] is `null` when there was no session to complete — that
/// is not a failure, it is nothing to do.
WorkoutSave workoutSaveOutcome({
  required bool logWritten,
  required bool? sessionCompleted,
  required bool scored,
}) {
  if (!logWritten) return WorkoutSave.failed;
  if (sessionCompleted == false) return WorkoutSave.failed;
  return scored ? WorkoutSave.scored : WorkoutSave.saved;
}

/// Whether the finished-workout flow may proceed: reset the sets, invalidate
/// the session providers, and celebrate.
///
/// Only when the workout is actually filed. This is the single guard the old
/// code was missing — it ran all four unconditionally.
bool mayFinishWorkout(WorkoutSave s) => s != WorkoutSave.failed;

/// The screen's existing failure language, reused rather than reinvented.
///
/// Voice and recovery match `_RestoreFailedView` and the feedback sheet's
/// `_saveFailed` row in the same file. **The exception is deliberately not
/// interpolated** — F-2 and F-16 were raised about exactly that.
const workoutSaveFailedMessage =
    'Could not save your workout. Check your connection and try again.';

/// The same word the feedback sheet uses for the same recovery.
const workoutSaveRetryLabel = 'Try Again';
