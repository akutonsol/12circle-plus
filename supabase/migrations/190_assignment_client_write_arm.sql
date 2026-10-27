-- Migration 190. A client may READ their programme assignments; they may not
-- create, alter or delete assignment rows. Only an active coach writes them (and
-- the member self-plan functions, which are SECURITY DEFINER and unaffected).
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 185 (whose policy it
-- narrows). Verified only on a local replay
-- (supabase/tests/local/assignment_guard_replay.sh). A SECURITY DEFECT, kept
-- visible until this is applied and verified on the target database.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE DEFECT
-- ═══════════════════════════════════════════════════════════════════════════
-- "coaches manage assignments" (001, narrowed by 185) is FOR ALL with no WITH
-- CHECK, so its USING clause also governs INSERT and UPDATE:
--     client_id = auth.uid() OR (coach_id = auth.uid() AND is_active_coach_of(client_id))
-- The first arm lets a CLIENT insert, update or delete their own assignment rows
-- naming ANY coach and ANY programme id. Proven on the 000-188 replay (rolled
-- back): a client self-inserted an active assignment of another coach's programme.
-- Before 185 (QA today) the coach arm is weaker still: coach_id = auth.uid() alone.
--
-- Who writes assignment rows legitimately (traced):
--   * coaches — CoachProgramService.assignProgram (client detail sheet, Copilot);
--   * generate_client_plan / its predecessors (047/048/052/077/121) for a member's
--     self-generated plan — SECURITY DEFINER, so RLS does not apply to them;
--   * no app path writes an assignment as the client. The client READS its active
--     assignment (CoachProgramService.getMyAssignedProgram).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE FIX — narrow
-- ═══════════════════════════════════════════════════════════════════════════
--   * "coaches manage assignments": the client arm is removed and WITH CHECK is
--     stated explicitly (the same predicate), so a coach may write only rows that
--     name themselves and a client they are ACTIVE with.
--   * "clients read own program assignments": new, SELECT only.
--   * "authoring coach reads own program assignments" (185, SELECT): unchanged.
-- Not changed: which programme a coach may assign (program_id is not checked
-- against workout_programs.coach_id) — recorded as an open question, not fixed
-- here, because nothing traced shows whether shared/template programmes exist.
--
-- Rollback: ALTER POLICY back to 185's USING with no WITH CHECK and DROP the new
-- SELECT policy — which reopens the defect.

BEGIN;

ALTER POLICY "coaches manage assignments" ON public.workout_program_assignments
  USING      (coach_id = auth.uid() AND public.is_active_coach_of(client_id))
  WITH CHECK (coach_id = auth.uid() AND public.is_active_coach_of(client_id));

DROP POLICY IF EXISTS "clients read own program assignments" ON public.workout_program_assignments;
CREATE POLICY "clients read own program assignments"
  ON public.workout_program_assignments FOR SELECT TO authenticated
  USING (client_id = auth.uid());

COMMIT;
