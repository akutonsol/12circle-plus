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
/// Selects nothing — and answers false — when the workout is not the signed-in
/// member's: read for somebody else and still on a card ([Workout.readFor],
/// A-10), or tapped by a member who has gone while the session was looked up.
/// [builtFor] is the account the tapped card was built for, for a caller that
/// knows it; the workout's own owner is asked either way.
Future<bool> selectWorkoutForZone(WidgetRef ref, Workout workout,
    {String? builtFor}) async {
  const origin = 'selectWorkoutForZone';
  final owner = builtFor ?? workout.readFor ?? signedInNow(ref);
  bool sameMember() =>
      ref.context.mounted && _mayOpen(ref, workout, owner, origin);

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
  if (!sameMember()) return false;
  if (session != null && session.workoutId == workout.id) {
    final Workout? bound;
    try {
      bound = await bindSessionToSelectedWorkout(ref, session);
    } catch (_) {
      // The member's own program could not be read: the caller's, as before.
      // Another member's is nothing to anybody here.
      if (sameMember()) rethrow;
      return false;
    }
    if (bound != null) return true;
    if (!sameMember()) return false;
  }
  ref.read(selectedWorkoutProvider.notifier).state = workout;
  return true;
}

/// Selects [workout] (null clears the selection) for a card built for
/// [builtFor]. False, with nothing selected, when that is not who is signed in
/// or the workout was read for somebody else.
///
/// Every direct selection goes through here or [selectWorkoutForZone], so a
/// card that outlived its member opens nothing (A-10).
bool selectWorkout(WidgetRef ref, Workout? workout, {required String? builtFor}) {
  if (!_mayOpen(ref, workout, builtFor, 'selectWorkout')) return false;
  ref.read(selectedWorkoutProvider.notifier).state = workout;
  return true;
}

/// Whether the member signed in now is [owner], and may open [workout]. Recorded
/// when not.
bool _mayOpen(WidgetRef ref, Workout? workout, String? owner, String origin) {
  final now = signedInNow(ref);
  if (now == owner && (workout == null || workout.isFor(now))) return true;
  reportError(origin,
      StateError('opening a workout: the signed-in account changed'));
  return false;
}
