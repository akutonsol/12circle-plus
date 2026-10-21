/// FIT-001 · the Today card on the app's front door.
///
/// ── WHAT THE BOARD DRAWS ───────────────────────────────────────────────────
///
///   Today
///   Assigned by Nadia
///   Lower body — strength
///   6 exercises · 48 min · heaviest set 62.5 kg
///   [ Begin session ]
///
/// Every line of that is already computed by `workout/domain/plan_summary.dart`
/// for FIT-014's hero card — `todaysSession`, `todayPillLabel`,
/// `workoutSummaryLine`. The same session should not be described two
/// different ways on two screens, so this reuses them rather than restating
/// them.
///
/// ── FOUR DEFECTS THIS REPLACES ─────────────────────────────────────────────
/// **1. A sample workout shown as the client's own.** The card read
/// `assigned.isNotEmpty ? assigned : sample`, then defaulted the title to
/// `'Full Body Strength'`. A coach-guided client with nothing assigned was
/// shown a workout from the demo library, captioned *"Assigned by your
/// coach"*. That is F-20 — a workout the user did not choose, presented as
/// theirs — on `/home`.
///
/// **2. Three hardcoded numbers presented as this session's stats.**
/// `'45 min'`, `'550 kcal'` and `'2.0K steps'` were literals. The workout
/// carries `estimatedDuration`; the other two are recorded nowhere, and a
/// front-door card is the last place to invent them.
///
/// **3. `Start` where the board says `Begin session`.** FIT-001 and FIT-014
/// both label it `Begin session`, and the shipped card had three different
/// words depending on coaching mode.
///
/// **4. A failed read rendered as "no plan".** `assignedWorkoutsProvider` was
/// read with `.valueOrNull`, so a failure became an empty list and then fell
/// through to the sample library — the error was not merely swallowed, it was
/// replaced with somebody else's workout.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/data/models/workout_model.dart';
import '../../workout/domain/plan_summary.dart';


/// What the Today card shows, once the rules have been applied.
class HomeSession {
  /// `Assigned by Nadia`, or `Today` — `todayPillLabel`'s output.
  final String? context;

  /// The workout's own title. Null when there is nothing to show.
  final String? title;

  /// `6 exercises · 48 min · heaviest set 62.5 kg`.
  final String? summary;

  /// The workout to start. Null when the card is not offering one.
  final Workout? workout;

  /// True when the assignment read failed — distinct from having no plan.
  final bool failed;

  const HomeSession({
    this.context,
    this.title,
    this.summary,
    this.workout,
    this.failed = false,
  });

  /// Whether a session can actually be started from here.
  bool get canBegin => workout != null;

  /// The board's word, on both FIT-001 and FIT-014.
  ///
  /// The shipped card said `Start`, `AI Train` or `Start Circle` depending on
  /// coaching mode. The action is the same in all three, and so is the label
  /// the package gives it.
  static const beginLabel = 'Begin session';

  /// What the card says when there is nothing to begin.
  ///
  /// Three different answers, because they are three different facts and a
  /// client can act on only one of them.
  String get emptyLine => failed
      ? "Couldn't load your plan"
      : 'No session assigned for today';
}

/// The Today card's content, from the assignment read and the coaching mode.
///
/// `assigned` is passed as an `AsyncValue` rather than a list precisely so the
/// failure can be told apart from the absence — the distinction the previous
/// implementation lost twice over.
HomeSession homeSession(
  AsyncValue<List<Workout>> assigned, {
  DateTime? now,
}) {
  if (assigned is AsyncError) return const HomeSession(failed: true);

  final list = assigned.valueOrNull;
  // Still loading: not an empty plan, and not a failure either.
  if (list == null) return const HomeSession();

  final today = todaysSession(list, now: now);
  // Nothing scheduled for today. The library is NOT consulted — a sample
  // workout is not this client's session, whatever the card would look like
  // with one in it.
  if (today == null) return const HomeSession();

  return HomeSession(
    context: todayPillLabel(today),
    title: today.title,
    summary: workoutSummaryLine(today),
    workout: today,
  );
}

/// The badge row's contents — only what the workout actually states.
///
/// The card drew `45 min`, `550 kcal` and `2.0K steps` as literals. Duration
/// is a real field; energy expenditure and step count are recorded nowhere on
/// a `Workout`, so they are not produced. A badge that is always right about
/// one thing beats three that are confidently wrong.
List<String> homeSessionBadges(Workout? w) {
  if (w == null) return const [];
  return [
    if (w.estimatedDuration > 0) '${w.estimatedDuration} min',
    if (w.exercises.isNotEmpty)
      '${w.exercises.length} exercise${w.exercises.length == 1 ? '' : 's'}',
  ];
}
