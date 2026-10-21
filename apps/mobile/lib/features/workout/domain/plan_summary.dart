import '../data/models/workout_model.dart';

/// Pure derivations behind FIT-014's hero card.
///
/// These live outside the widget so they can be tested as behaviour. Driving
/// `TrainHubScreen` in a widget test was attempted first and abandoned: the
/// shared `AppScaffold` reads `Supabase.instance`, so rendering the screen in a
/// test requires initialising Supabase. Stubbing that to reach two string
/// computations would have produced exactly the kind of test
/// `QA_CLOSURE_STANDARD` §4 warns about — one that passes whatever the app
/// does. The rendering itself is verified on the emulator instead, and the
/// wiring by the A-G6 source guard.

/// The session the hub presents as today's work, or null.
///
/// FIT-014's pill reads "Today · assigned by …", so only a session actually
/// scheduled for today may appear under it. A completed session is not offered
/// again. The package draws no "plan exists but nothing today" frame, so that
/// case has no hero — it is not invented here.
Workout? todaysSession(List<Workout> workouts, {DateTime? now}) {
  final today = now ?? DateTime.now();
  for (final w in workouts) {
    final d = w.scheduledDate;
    if (d == null || w.isCompleted) continue;
    if (d.year == today.year && d.month == today.month && d.day == today.day) {
      return w;
    }
  }
  return null;
}

/// "6 exercises · 48 min · heaviest set 62.5 kg".
///
/// Every clause is dropped when the data does not support it. A workout with no
/// prescribed load must not read "heaviest set 0 kg", and one with no estimate
/// must not read "0 min" — a fabricated figure is worse than a missing one.
String workoutSummaryLine(Workout w) {
  final parts = <String>[];

  final n = w.exercises.length;
  if (n > 0) parts.add('$n ${n == 1 ? 'exercise' : 'exercises'}');

  if (w.estimatedDuration > 0) parts.add('${w.estimatedDuration} min');

  final heaviest = heaviestPrescribedLoad(w);
  if (heaviest != null) {
    final v = heaviest == heaviest.roundToDouble()
        ? heaviest.toStringAsFixed(0)
        : heaviest.toString();
    parts.add('heaviest set $v kg');
  }

  return parts.join(' · ');
}

/// The largest weight prescribed anywhere in the workout, or null when it is
/// bodyweight throughout. Null and zero are different answers and are kept so.
double? heaviestPrescribedLoad(Workout w) {
  double? heaviest;
  for (final e in w.exercises) {
    for (final s in e.sets) {
      final kg = s.weightKg;
      if (kg != null && kg > 0 && (heaviest == null || kg > heaviest)) {
        heaviest = kg;
      }
    }
  }
  return heaviest;
}

/// "Today · assigned by Nadia", degrading to the bare day when the workout
/// carries no coach. The name comes from the Workout already in hand — no
/// extra provider read, which is what EC-G8 ratchets.
String todayPillLabel(Workout w) {
  final coach = w.coachName?.trim();
  return (coach != null && coach.isNotEmpty)
      ? 'Today · assigned by $coach'
      : 'Today';
}
