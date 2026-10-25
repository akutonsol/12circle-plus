/// Whether a program has any training days a client could actually do.
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
/// The coach Program Builder (`/program-designer`) saves an engine-generated
/// program with a 12-week PLAN but no `program_workouts` rows: the step that
/// would fill them, `materialize_program_week`, has no caller in the app, and on
/// a database without a populated intelligence substrate it writes days with no
/// exercises (or, once populated, fails the canonical-prescription check). Such
/// a program could still be picked in the Assign Program sheet and handed to a
/// client, who would then own a program with nothing in it.
///
/// `getMyPrograms()` already selects `program_workouts(count)`, which PostgREST
/// returns as `[{count: n}]`. This reads it.
///
/// Returns `null` when the count is absent or unreadable — "unknown" is not
/// "empty", so callers must not block on it.
int? programDayCount(Map<String, dynamic> program) {
  final embed = program['program_workouts'];
  if (embed is List && embed.isNotEmpty) {
    final first = embed.first;
    if (first is Map && first['count'] is num) return (first['count'] as num).toInt();
  }
  return null;
}

/// True only when the program is KNOWN to have no training days.
bool isKnownEmptyProgram(Map<String, dynamic> program) => programDayCount(program) == 0;
