// Coach programme engine — the app's side of `materialize_program_week`.
//
// The database function is the only generator (this file adds none). What lives
// here is everything the coach-facing "Generate week 1" step needs that can be
// built and tested WITHOUT the database fix: the integration flag, the context
// the engine is called with, the reading of its result, and the mapping of its
// errors to sentences a coach can act on.
//
// ── THE INTEGRATION DEPENDENCY ─────────────────────────────────────────────
// Until migration 186 is applied to the database the app points at, the engine
// behind `materialize_program_week` is 093's body: with no intelligence data it
// writes EMPTY training days and reports success, and with data it fails 23514
// (reproduced on a 000-181 local replay, 2026-10-25). Calling it from a screen
// before then would hand coaches empty days. So the step is behind a build-time
// flag that is OFF by default and must only be turned on for a build whose
// database has 186:
//
//   flutter run --dart-define=ENGINE_WEEK_GENERATION=true
//
// `summarizeMaterialization` is a second line of defence: 186 reports an
// exercise count per session and 093 does not, so a result without counts is
// treated as "the engine on this database is out of date", never as success.

/// Build-time switch for the coach "Generate week 1" step. OFF unless the
/// target database has migration 186.
const bool kEngineWeekGeneration =
    bool.fromEnvironment('ENGINE_WEEK_GENERATION', defaultValue: false);

/// Why a generation attempt did not produce a week.
enum EngineFailure {
  /// The engine selected no exercises. Since 188 that means no exercise is both
  /// certified for Program Builder and expert-reviewed (or none fits the
  /// session's focus). Nothing saved.
  noSelection,

  /// The plan has a session type the engine has no movement-pattern mapping for
  /// (ENGINE_UNKNOWN_FOCUS, 188). Nothing saved.
  unsupportedSplit,

  /// A session has no eligible compound lift, and each needs one
  /// (ENGINE_INSUFFICIENT_ELIGIBLE, 188). Nothing saved.
  insufficientEligible,

  /// The programme is already assigned to a client who is not cleared for
  /// generated training (ENGINE_CLIENT_NOT_CLEARED, 189). Nothing saved.
  clientNotCleared,

  /// The week already has training days; nothing changed. Replacing is explicit.
  weekExists,

  /// sets/reps/rest in the request were not whole numbers in range.
  badPrescription,

  /// The programme has no plan, or the week is not in it.
  noPlan,

  /// The caller may not act on this programme (SQLSTATE 42501).
  notAuthorized,

  /// The call "succeeded" but the result has no per-session exercise counts —
  /// the database still runs the pre-186 engine.
  outdatedEngine,

  /// Anything else (network, server error).
  unknown,
}

/// Classifies an error thrown by `materialize_program_week`. Matches on the
/// stable `ENGINE_*` prefixes migration 186 raises, never on free prose.
EngineFailure classifyEngineError(Object error, {String? sqlState}) {
  final code = sqlState ?? _codeOf(error);
  final text = _messageOf(error);
  // Raised with 42501 too, so it must be told apart BEFORE the generic refusal.
  if (text.contains('ENGINE_CLIENT_NOT_CLEARED')) return EngineFailure.clientNotCleared;
  if (code == '42501') return EngineFailure.notAuthorized;
  if (text.contains('ENGINE_NO_SELECTION')) return EngineFailure.noSelection;
  if (text.contains('ENGINE_UNKNOWN_FOCUS')) return EngineFailure.unsupportedSplit;
  if (text.contains('ENGINE_INSUFFICIENT_ELIGIBLE')) return EngineFailure.insufficientEligible;
  if (text.contains('ENGINE_WEEK_EXISTS')) return EngineFailure.weekExists;
  if (text.contains('ENGINE_BAD_PRESCRIPTION')) return EngineFailure.badPrescription;
  if (text.contains('ENGINE_NO_PLAN') || text.contains('ENGINE_NO_WEEK')) {
    return EngineFailure.noPlan;
  }
  return EngineFailure.unknown;
}

String? _codeOf(Object e) {
  try {
    final code = (e as dynamic).code;
    return code is String ? code : null;
  } catch (_) {
    return null;
  }
}

String _messageOf(Object e) {
  try {
    final m = (e as dynamic).message;
    if (m is String) return m;
  } catch (_) {}
  return e.toString();
}

/// What a coach is told for each failure. Every sentence says what happened to
/// their data and what to do next.
String coachMessageFor(EngineFailure f) => switch (f) {
      EngineFailure.noSelection =>
        "Couldn't pick exercises yet — none have been cleared for Program Builder "
            '(certified and expert-reviewed). Nothing was saved. Build this week by hand in Programs for now.',
      EngineFailure.insufficientEligible =>
        "Each training day needs at least one main compound lift, and none is cleared for "
            'Program Builder yet. Nothing was saved. Build this week by hand in Programs.',
      EngineFailure.clientNotCleared =>
        "This programme is assigned to a client who isn't cleared for generated training, so "
            'nothing was generated. Build their week by hand in Programs.',
      EngineFailure.unsupportedSplit =>
        "This programme has a session type that can't be generated yet. Nothing was saved. "
            'Build this week by hand in Programs.',
      EngineFailure.weekExists =>
        'Week 1 already has training days, so nothing was changed.',
      EngineFailure.badPrescription =>
        "Sets and reps must be whole numbers. Nothing was saved.",
      EngineFailure.noPlan =>
        "This programme has no plan for that week. Re-create it from Program Builder.",
      EngineFailure.notAuthorized =>
        "You can't generate workouts for this programme.",
      EngineFailure.outdatedEngine =>
        "Workout generation isn't available on this server yet. Build the week by hand in Programs.",
      EngineFailure.unknown =>
        "Couldn't generate the week — check your connection and try again.",
    };

/// The request context for a programme built in Program Builder. The goal
/// vocabulary is Copilot's (`coach_copilot_screen.dart`), so both screens ask the
/// engine the same question. No equipment filter: a programme is not yet any one
/// client's, and a filter the substrate cannot satisfy empties every session.
Map<String, dynamic> engineContextFor({
  required String programType,
  bool replaceExisting = false,
}) {
  final t = programType.toLowerCase();
  final goal = t.contains('fat') ? 'fat_loss'
      : t.contains('strength') || t.contains('athletic') ? 'strength'
      : 'hypertrophy';
  return {
    'goal': goal,
    'experience': 'intermediate',
    'size': 5,
    // Only a JSON `true` is consent to replace (186). Never sent by default.
    if (replaceExisting) 'replace_existing': true,
  };
}

/// Reads a successful `materialize_program_week` result.
///
/// Returns the day and exercise totals, or `null` when the result cannot be
/// trusted: no sessions, a session without an exercise count (the pre-186
/// engine), or a session with zero exercises. A `null` is shown as
/// [EngineFailure.outdatedEngine], never as success.
({int days, int exercises})? summarizeMaterialization(Object? result) {
  if (result is! Map) return null;
  final sessions = result['sessions'];
  if (sessions is! List || sessions.isEmpty) return null;
  var exercises = 0;
  for (final s in sessions) {
    if (s is! Map) return null;
    final n = s['exercises'];
    if (n is! num || n <= 0) return null;
    exercises += n.toInt();
  }
  return (days: sessions.length, exercises: exercises);
}
