import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_failure.dart';
import '../data/models/workout_model.dart';
import '../data/workout_session_store.dart';
import '../domain/workout_provider.dart';

/// Points the Workout Zone at [workout] — or, when a session is already open
/// for it, at that session's own workout.
///
/// The Workouts list's RESUME, the Directory's day card and Home's hero set the
/// PROGRAM's workout and went to the Zone. The Zone resumed the open session
/// with it and seated the logged sets against it, so sets on an exercise the
/// client had swapped (new `swap-…` ids, kept in the session's snapshot) had
/// nowhere to go: they vanished from the screen and from the finish totals.
/// The Train hub and the resume banner already bind the session's workout
/// (`bindSessionToSelectedWorkout`); every entry point now does.
///
/// Selects nothing when the account changed while the session was looked up:
/// the tapped workout was the previous member's.
Future<void> selectWorkoutForZone(WidgetRef ref, Workout workout) async {
  final uid = ref.read(restoringUserIdProvider);
  bool sameMember() {
    if (!ref.context.mounted) return false;
    if (ref.read(restoringUserIdProvider) == uid) return true;
    reportError('selectWorkoutForZone',
        StateError('opening a workout: the signed-in account changed'));
    return false;
  }

  WorkoutSessionRecord? session;
  try {
    session = await ref.read(activeSessionProvider.future);
  } catch (_) {
    // The lookup failed: select the tapped workout, as before. The Zone looks
    // the session up again on entry and states its own failure there. This is
    // an entry point, not a provider — workout_provider.dart holds no catch
    // (EC-G1), and the read it guards still propagates to every screen.
    session = null;
  }
  if (!sameMember()) return;
  if (session != null && session.workoutId == workout.id) {
    final bound = await bindSessionToSelectedWorkout(ref, session);
    if (bound != null || !sameMember()) return;
  }
  ref.read(selectedWorkoutProvider.notifier).state = workout;
}
