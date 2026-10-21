import '../data/models/workout_model.dart';

/// FIT-016 · what the session row's info control opens.
///
/// ── WHERE THE BEHAVIOUR COMES FROM ─────────────────────────────────────────
/// The board's own annotation on the Workout detail frame:
///
///   *"Prescription reads as one line per exercise — sets, reps, load, rest —
///   because that is what a lifter checks. No thumbnails, no cards. **The info
///   icon opens form and instructions.**"*
///
/// and `manifest.json → FIT-016` lists `ph-info` among the frame's icons and
/// declares each session row as `el: "button"`. So the affordance and what it
/// does are both **design decisions already made** — they are not invented
/// here. What the package does NOT contain is a drawn frame for the surface it
/// opens: there is no exercise-detail screen in the 110.
///
/// That gap is bridged without inventing product behaviour, by composing only
/// from things the package does specify:
///
///   * the design system's sheet surface (`#121215`, "Cards, sheets, rows")
///     and its 240 ms sheet present/dismiss motion;
///   * the package's own dismissal word, `Done` — used in five other frames;
///   * **no invented section headings.** `Form` and `Instructions` appear
///     nowhere in the package, so nothing is labelled with them. The prose
///     reads as prose and the steps read as numbered steps, which is what they
///     are.
///
/// ── AND WHERE IT STOPS ─────────────────────────────────────────────────────
/// Every field below already exists on `Exercise`, `WorkoutExercise` and
/// `WorkoutSet`. Nothing is derived, inferred or filled in. When a movement
/// carries none of them, [hasBrief] is false and the caller must not draw the
/// control at all — an info icon that opens an empty sheet is a worse lie than
/// no info icon, and a row that announces `button: true` with nothing behind it
/// is the same defect one layer down.
class ExerciseBrief {
  /// The library movement's name, as prescribed.
  final String name;

  /// The row's own line — `4 × 6 · 65 kg · rest 120 s`.
  final String prescription;

  /// What the coach wrote about **this slot**, if anything.
  ///
  /// `WorkoutExercise.notes` is per-instance prescription commentary. The board
  /// does not draw it on the row, and it is the most specific form guidance
  /// that exists for this movement in this session, so it leads here. Hiding a
  /// coach's note behind no surface at all was the alternative.
  final String? coachNote;

  /// The library entry's prose — `Exercise.description`.
  final String? form;

  /// The library entry's ordered steps — `Exercise.instructions`.
  final List<String> steps;

  /// Equipment and target musculature, each only when the library says.
  final String? equipment;
  final String? muscleGroup;

  const ExerciseBrief({
    required this.name,
    required this.prescription,
    this.coachNote,
    this.form,
    this.steps = const [],
    this.equipment,
    this.muscleGroup,
  });

  /// True when there is something to show. Drives whether the control exists.
  ///
  /// Equipment and muscle group alone do **not** qualify: the control promises
  /// form and instructions, and two metadata chips are not that.
  bool get hasContent =>
      (coachNote != null) || (form != null) || steps.isNotEmpty;
}

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// `4 × 6 · 65 kg · rest 120 s` — assembled only from fields that are set.
///
/// A missing weight or rest is omitted rather than rendered as `0`; null and
/// zero are different answers on `WorkoutSet.weightKg` and the model says so.
///
/// The design also shows `3 × 10 each` for a unilateral movement. No
/// unilateral/per-side field exists on `Exercise` or `WorkoutSet`, so `each` is
/// NOT emitted: inventing it would assert something about the prescription that
/// the data does not say. Recorded rather than guessed.
String prescriptionLine(WorkoutExercise exercise) {
  final sets = exercise.sets;
  if (sets.isEmpty) return 'No sets prescribed';
  final first = sets.first;
  final parts = <String>['${sets.length} × ${first.reps}'];
  final kg = first.weightKg;
  if (kg != null && kg > 0) {
    final s = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();
    parts.add('$s kg');
  }
  final rest = first.restSeconds;
  if (rest != null && rest > 0) parts.add('rest $rest s');
  return parts.join(' · ');
}

ExerciseBrief exerciseBrief(WorkoutExercise exercise) {
  final e = exercise.exercise;
  return ExerciseBrief(
    name: e.name,
    prescription: prescriptionLine(exercise),
    coachNote: _clean(exercise.notes),
    form: _clean(e.description),
    steps: e.instructions
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false),
    equipment: _clean(e.equipment),
    muscleGroup: _clean(e.muscleGroup),
  );
}

/// The row's accessible name — the board's own label shape, verbatim:
/// `1 Back squat 4 × 6 · 65 kg · rest 120 s`.
String rowLabel(int index, WorkoutExercise exercise) =>
    '$index ${exercise.exercise.name} ${prescriptionLine(exercise)}';

/// What the row's action does, for assistive technology.
///
/// WCAG 2.5.3: the accessible name must contain the visible label, so the
/// action cannot be written into the name — it goes in the hint. Null when
/// there is nothing behind the control, because then there is no control.
String? rowHint(WorkoutExercise exercise) =>
    exerciseBrief(exercise).hasContent ? 'Shows form and instructions' : null;
