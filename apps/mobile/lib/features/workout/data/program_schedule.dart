import 'models/workout_model.dart';
import 'workout_snapshot.dart';

/// Which calendar day a program's training day falls on.
///
/// A `program_workouts` row says only "week 2, Monday"; the assignment says
/// when the program started (`workout_program_assignments.start_date`). The
/// rule joining them:
///
///   **Week 1 runs Monday to Sunday — the week containing the assignment's
///   start date.** Week N is the N-th such week after it.
///
/// So a program assigned on a Wednesday has its week-1 Monday and Tuesday in
/// the past, and its week-1 Wednesday is today.
///
/// `start_date` is the only date source. `current_week` is written as 1 at
/// assignment and never advanced, so it is not read here.
///
/// Nothing is guessed: a missing start date, a week below 1 or a day that is
/// not one of the seven canonical names (`program_workouts_canonicalize`, 119)
/// gives no date, and an undated workout is never "today's".
DateTime? programDayDate(DateTime start, Object? weekNumber, Object? dayOfWeek) {
  final week = weekNumber is int ? weekNumber : null;
  final day = dayOfWeek is String ? _days.indexOf(dayOfWeek) : -1;
  if (week == null || week < 1 || day < 0) return null;
  // Day arithmetic through the constructor, which normalises overflow and stays
  // on local midnight across a DST change; adding a Duration would not.
  final monday = start.day - (start.weekday - DateTime.monday);
  return DateTime(start.year, start.month, monday + (week - 1) * 7 + day);
}

/// The client's assigned program — the map `getMyAssignedProgram()` returns:
/// the assignment row plus its `workouts` — decoded into dated workouts.
///
/// Only a **coach's** assignment is dated. A self-generated plan
/// (`generate_client_plan`, `coach_id` null) stays undated, as it always was:
/// whether it belongs on the Today card is an open product question, and the
/// card would caption it "assigned by Your Coach" — untrue for a client with no
/// coach.
///
/// [sessions] are the client's `workout_sessions` rows for these training days.
/// A coach's training day is **done** once one of them is `completed` at or
/// after this assignment's `assigned_at`, on any day — see [_finishedDays].
///
/// Errors propagate exactly as [programWorkoutToWorkout]'s do.
List<Workout> assignedProgramToWorkouts(Map<String, dynamic> assignment,
    {List<Map<String, dynamic>> sessions = const []}) {
  final coached = assignment['coach_id'] != null;
  final start = coached ? _date(assignment['start_date']) : null;
  final done = coached ? _finishedDays(assignment, sessions) : const <String>{};
  final rows =
      List<Map<String, dynamic>>.from(assignment['workouts'] as List? ?? []);
  return [
    for (final w in rows)
      programWorkoutToWorkout(w,
          scheduledDate: start == null
              ? null
              : programDayDate(start, w['week_number'], w['day_of_week']),
          isCompleted: done.contains(w['id'])),
  ];
}

/// The `program_workouts` ids the client finished under this assignment.
///
/// A session names its training day by `workout_id`. Re-assigning a program
/// reuses those ids, so a session counts only if it was completed at or after
/// the assignment's `assigned_at` — an earlier assignment's finished days do
/// not carry over. Two instants are compared, so no time zone is involved.
///
/// `in_progress` and `abandoned` sessions are not finished. A missing
/// `assigned_at` or `completed_at` counts nothing: the day stays on offer
/// rather than being hidden on a guess.
Set<String> _finishedDays(
    Map<String, dynamic> assignment, List<Map<String, dynamic>> sessions) {
  final since = _instant(assignment['assigned_at']);
  if (since == null) return const {};
  return {
    for (final s in sessions)
      if (s['status'] == 'completed' && s['workout_id'] is String)
        if (_instant(s['completed_at']) case final at? when !at.isBefore(since))
          s['workout_id'] as String,
  };
}

DateTime? _instant(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `start_date` is a Postgres `date` and arrives as `2026-11-04`. Read as the
/// local calendar day it names, never shifted through UTC.
DateTime? _date(Object? v) {
  final d = v is String ? DateTime.tryParse(v) : null;
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

const _days = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
