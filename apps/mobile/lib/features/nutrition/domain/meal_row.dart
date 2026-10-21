/// FIT-003 · "Nutrition — now a primary destination".
///
/// ── THE BOARD'S ROWS ───────────────────────────────────────────────────────
///
///   Greek yoghurt, berries, seeds   Breakfast · 07:20        380
///   Chicken, rice, greens           Lunch · 12:45            640
///   Protein shake, banana           After training · 18:10   620
///
/// and its annotation:
///
/// > *"Today, what you ate, what's left, coach guidance — in that order. Macros
/// > read as three figures against their targets on one rule, not three
/// > progress cards. Logging is two taps from anywhere."*
///
/// ── WHAT SHIPPED INSTEAD ───────────────────────────────────────────────────
/// A card per meal: a 52 dp tinted icon, the name, `380 kcal`, three macro
/// **progress bars**, and an inert `more_horiz`. The meal's **type and time —
/// `Breakfast · 07:20` — were not rendered at all**, though `nutrition_logs`
/// has carried `meal_type` and `logged_at` since migration 012. The board's
/// middle line was simply missing.
///
/// ── THE ONE PLACE THE BOARD CANNOT BE FOLLOWED ─────────────────────────────
/// Its third row reads **`After training`**. `nutrition_logs.meal_type` is a
/// CHECK constraint over exactly five values —
/// `breakfast | lunch | dinner | snack | protein_shake` — and *"after
/// training"* is not one of them. It is a statement about **when the meal was
/// taken relative to a session**, which this product does not record: nothing
/// links a nutrition log to a workout.
///
/// Rendering `After training` for `protein_shake` would assert a training
/// session that may not have happened. So `protein_shake` reads as
/// **`Protein shake`** and the divergence is recorded as **OD-22**, the same
/// treatment OD-16 got for `Energy · Steady`. A test below asserts the board's
/// phrase is NOT produced, so this cannot be resolved silently.
library;

/// The five values `nutrition_logs.meal_type` permits, in the order a day runs.
const mealTypeOrder = <String>[
  'breakfast',
  'lunch',
  'dinner',
  'snack',
  'protein_shake',
];

const _mealTypeWords = <String, String>{
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'snack': 'Snack',
  // NOT "After training" — see OD-22 above.
  'protein_shake': 'Protein shake',
};

/// `Breakfast`, or null for a value the schema does not define.
///
/// An unrecognised type is not passed through and not title-cased into
/// something plausible: a word invented from a database value is still an
/// invented word.
String? mealTypeLabel(String? raw) =>
    _mealTypeWords[raw?.trim().toLowerCase() ?? ''];

/// `07:20` — 24-hour, as the board writes every time in this package.
String? mealTime(DateTime? at) {
  if (at == null) return null;
  final l = at.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// The board's middle line — `Breakfast · 07:20`.
///
/// Each half is omitted when it is unknown rather than filled in, so a log
/// with no type still shows its time and a log with neither shows nothing at
/// all instead of a bare separator.
String mealRowDetail({String? mealType, DateTime? loggedAt}) => [
      if (mealTypeLabel(mealType) != null) mealTypeLabel(mealType)!,
      if (mealTime(loggedAt) != null) mealTime(loggedAt)!,
    ].join(' · ');

/// `380` — the board shows the number alone in the row, with `kcal` carried
/// once by the header. Rounded, never `380.0`.
String mealCalories(num? calories) => (calories ?? 0).round().toString();

/// `Greek yoghurt, berries, seeds Breakfast · 07:20 380` — the shape the
/// manifest declares for these rows.
///
/// `kcal` IS spoken, because a bare `380` at the end of a sentence tells a
/// screen-reader user nothing. The board can rely on the header for that; a
/// spoken label cannot.
String mealRowLabel({
  required String name,
  String? mealType,
  DateTime? loggedAt,
  num? calories,
}) {
  final detail = mealRowDetail(mealType: mealType, loggedAt: loggedAt);
  return [
    name,
    if (detail.isNotEmpty) detail,
    '${mealCalories(calories)} kcal',
  ].join(' ');
}

/// One macro against its target — `118 g Protein · 140`.
///
/// The annotation is explicit that these are *"three figures against their
/// targets on one rule, not three progress cards"*, so this returns the
/// figures and says nothing about how they are drawn.
class MacroFigure {
  final String name;
  final int value;

  /// The target, or null when none is set. A macro with no target reads as a
  /// figure alone rather than against a zero it was never measured against.
  final int? target;

  const MacroFigure({required this.name, required this.value, this.target});

  /// `118 g` — the value and its unit.
  String get reading => '$value g';

  /// `Protein · 140`, or just `Protein` when nothing is targeted.
  String get against => target == null ? name : '$name · $target';

  /// What a screen reader says: `Protein 118 of 140 grams`.
  ///
  /// The visible form is two fragments on either side of a number, which
  /// announces as a fragment. This is the sentence.
  String get spoken => target == null
      ? '$name $value grams'
      : '$name $value of $target grams';
}

/// `1,640` — thousands separated, as the board writes it.
String kcalReading(num? value) {
  final n = (value ?? 0).round();
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// `of 2,050 kcal`, or `kcal` alone when no target is set.
///
/// A zero target is not a target. `/meals-dashboard` shipped `?? 0.0` on this
/// read — the tenth F-15 case — so "no goal set" rendered as a goal of zero
/// and every day read as over budget.
String kcalTargetLine(num? target) =>
    (target == null || target <= 0) ? 'kcal' : 'of ${kcalReading(target)} kcal';
