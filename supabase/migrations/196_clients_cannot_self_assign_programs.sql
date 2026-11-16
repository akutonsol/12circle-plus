-- Migration 196. A client cannot assign itself someone else's program -- the
-- assignment row was the key to reading that program's content.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["196"]. Independent of 182-186 and of 193-195.
--
-- THE DEFECT
--   workout_program_assignments "coaches manage assignments" (001) is FOR ALL with
--   `coach_id = auth.uid() OR client_id = auth.uid()`. On the client arm a client
--   can INSERT (or UPDATE into) a row naming itself as client and ANY program_id.
--   public.can_read_program() then answers true for that program, because a row
--   with `client_id = auth.uid()` exists for it -- so the client reads the program
--   and every program_workouts row of it (both SELECT policies call
--   can_read_program). Any coach's program, paid or not, by one INSERT.
--   Migration 185 (pending, gated) keeps this arm and records only that it lets a
--   client "attribute content to a coach"; the read it unlocks was not noted.
--
-- WHY THE FIX TAKES NOTHING THE PRODUCT USES
--   Every assignment the product creates is written by the coach
--   (CoachProgramService.assignProgram) or by a SECURITY DEFINER function
--   (generate_client_plan -- owned by postgres, so RLS does not apply). The app
--   never inserts or updates an assignment as the client. A client keeps reading
--   its own assignments.
--
-- THE RULE (RESTRICTIVE, so it composes with whichever permissive arm is live --
-- 001's today, 185's if that is applied later, in either order):
--   a row that names the CALLER as client may be written only for a program the
--   caller owns (workout_programs.coach_id = auth.uid()). A coach assigning to a
--   client is untouched by this policy; the permissive arm still governs it.
--
-- NOT CHANGED, STATED SO IT IS NOT ASSUMED:
--   * A coach can still assign a program owned by ANOTHER coach to their own
--     client and so read it. Whether coaches may share programs (a coaching team)
--     is a product question; this does not decide it.
--   * DELETE by the client is not restricted (it reads nothing new).
--
-- Reversible: DROP POLICY on the two names below.

BEGIN;

DROP POLICY IF EXISTS "client writes assignments only for own programs (insert)"
  ON public.workout_program_assignments;
CREATE POLICY "client writes assignments only for own programs (insert)"
  ON public.workout_program_assignments
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK (
    client_id IS DISTINCT FROM (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = program_id AND p.coach_id = (SELECT auth.uid()))
  );

DROP POLICY IF EXISTS "client writes assignments only for own programs (update)"
  ON public.workout_program_assignments;
CREATE POLICY "client writes assignments only for own programs (update)"
  ON public.workout_program_assignments
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (
    client_id IS DISTINCT FROM (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.workout_programs p
                WHERE p.id = program_id AND p.coach_id = (SELECT auth.uid()))
  );

COMMIT;
