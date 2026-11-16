-- Migration 200. A client's new coach does not read the previous coach's private
-- programs; the client keeps its history. (Ownership matrix O7/O8; owner
-- decision 14, direction 2026-11-16.)
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["200"]. Applies after 196-197 (it assumes their
-- assignment rules) -- independent of 182-186, 193-195, 198, 199.
--
-- THE DEFECT (supabase/tests/local/program_history_200_replay.sql)
--   can_read_program() (117) grants a coach every program assigned to a client
--   they ACTIVELY coach -- `is_active_coach_of(a.client_id)` -- whoever authored
--   it. When a client leaves coach A for coach B, B silently reads A's private
--   programs: the program_workouts of each, through both SELECT policies that
--   call this function. A's authored work goes to a competitor with the client.
--
-- THE RULE
--   * the program's author reads it (unchanged);
--   * the client reads every program assigned to it -- its history stays its own
--     (unchanged; O8);
--   * the coach who made the assignment reads it (unchanged);
--   * the client's ACTIVE coach reads a program assigned to that client only when
--     it is not another coach's authored work: the client owns it, or it has no
--     owner (the self-guided generator writes coach_id null) -- so a coach keeps
--     seeing the client's own and generated plans (O11), but not a previous
--     coach's (O7);
--   * admins unchanged.
--   Workout history is untouched: it reads workout_sessions / workout_set_logs,
--   the client's own rows, never the program tables.
--
-- Same signature, SECURITY DEFINER, search_path pin and grants as 117 (CREATE OR
-- REPLACE keeps the ACL; the REVOKE/GRANT are restated so the posture is visible
-- at the point of definition).
--
-- Reversible: restore 117's body.

BEGIN;

CREATE OR REPLACE FUNCTION public.can_read_program(p_program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = p_program AND p.coach_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                   JOIN public.workout_programs p ON p.id = a.program_id
                  WHERE a.program_id = p_program
                    AND (a.client_id = (SELECT auth.uid())
                         OR a.coach_id = (SELECT auth.uid())
                         OR (public.is_active_coach_of(a.client_id)
                             AND (p.coach_id IS NULL OR p.coach_id = a.client_id))))
      OR public.is_admin();
$function$;

REVOKE ALL ON FUNCTION public.can_read_program(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_program(uuid) TO authenticated;

COMMIT;
