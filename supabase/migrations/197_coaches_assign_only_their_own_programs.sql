-- Migration 197. A coach assigns only a program the coach owns -- assigning
-- another coach's private program was a way to read it.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["197"]. Companion of 196 (the client side); applies
-- after it. Independent of 182-186 and 193-195.
--
-- THE DEFECT (supabase/tests/local/program_ownership_matrix.sql, row O2)
--   A row in workout_program_assignments naming the caller as coach may carry ANY
--   program_id: 001's arm checks only `coach_id = auth.uid()`, and 185 (pending)
--   adds an active relationship with the client but not ownership of the program.
--   can_read_program() then opens that program to the caller, because an
--   assignment with `coach_id = auth.uid()` exists for it. So a coach could read
--   any other coach's private program by assigning it to one of their own clients
--   -- on QA today, and still with 185 + 196 applied (matrix: O2 = leaks on all
--   three shapes). On QA today an UNRELATED coach can do the same to anyone's
--   client (O6); 185 closes that part.
--
-- WHY THIS TAKES NOTHING THE PRODUCT USES
--   The coach's assign sheet lists only the coach's own programs
--   (CoachProgramService.getMyPrograms: coach_id = auth.uid()); Coach Copilot
--   creates its own program and assigns that. No program-sharing mechanism
--   exists -- no policy reads is_template or any share flag -- so every program
--   is private to its owner today. If coaches are later allowed to share
--   programs (a coaching team: an open product decision), the sharing feature
--   adds its own path; this does not decide it.
--
-- THE RULE (RESTRICTIVE, so it composes with 001's arm, 185 and 196 in any order):
--   a row that names the CALLER as coach may be written only for a program the
--   caller owns (workout_programs.coach_id = auth.uid()).
--   Self-guided rows (caller is coach AND client of their own program) pass.
--   SECURITY DEFINER writers (generate_client_plan, owned by postgres) are not
--   subject to RLS and are unaffected.
--
-- NOT CHANGED, STATED SO IT IS NOT ASSUMED (decisions, recorded in the ledger):
--   * A client's NEW coach can read programs a previous coach assigned to that
--     client (can_read_program's is_active_coach_of arm; matrix O7). Continuity
--     of history vs the previous coach's ownership is a product question.
--   * A client keeps reading a former coach's program after leaving (O8).
--   * Existing rows are not touched; a coach's earlier assignment of a program
--     they do not own keeps its read access until removed.
--
-- Reversible: DROP POLICY on the two names below.

BEGIN;

DROP POLICY IF EXISTS "coach writes assignments only for own programs (insert)"
  ON public.workout_program_assignments;
CREATE POLICY "coach writes assignments only for own programs (insert)"
  ON public.workout_program_assignments
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (
    coach_id IS DISTINCT FROM (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = program_id AND p.coach_id = (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "coach writes assignments only for own programs (update)"
  ON public.workout_program_assignments;
CREATE POLICY "coach writes assignments only for own programs (update)"
  ON public.workout_program_assignments
  AS RESTRICTIVE FOR UPDATE TO authenticated
  -- The row as it is and as it becomes: a coach cannot repoint an assignment at
  -- a program it does not own. Replacing (status-only updates of the coach's own
  -- rows) keeps passing because the row's program is the coach's own.
  USING (
    coach_id IS DISTINCT FROM (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = program_id AND p.coach_id = (SELECT auth.uid()))
  )
  WITH CHECK (
    coach_id IS DISTINCT FROM (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = program_id AND p.coach_id = (SELECT auth.uid()))
  );

COMMIT;
