-- Migration 191. Turning off a member's self-generated plan works again.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Verified only on a local replay
-- (supabase/tests/local/self_plan_deactivate_replay.sh). Functionally independent
-- of 187–190; numbered after them only because they precede it in this tree.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE DEFECT (pre-existing; reproduced on local replays of 000-186, 000-188, 000-190)
-- ═══════════════════════════════════════════════════════════════════════════
-- deactivate_self_generated_plan() (047:55, pinned by 116/118/122; called by the app
-- at coaching_mode_provider.dart:92 when a member leaves self-guided mode) deletes
-- the member's workout_programs BEFORE the workout_program_assignments rows that
-- reference them. workout_program_assignments.program_id (001:95) has NO delete
-- action, so the first DELETE raises 23503 and the whole call rolls back: the
-- member's self plan, its assignment, its nutrition plan and its habits all stay
-- active. Every call fails once a self plan exists.
--
-- generate_client_plan (121:166-172) already does the same cleanup in the right
-- order — capture the programme ids, delete the assignments, then the programmes.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE FIX — same behaviour, right order, two guards
-- ═══════════════════════════════════════════════════════════════════════════
--   1. Unchanged: no signed-in user -> return; deactivate the member's coach-less
--      nutrition plans and habits.
--   2. Capture the programme ids of the member's coach-less assignments, delete those
--      assignments, THEN delete the programmes — as 121 does.
--   3. A programme is deleted only if it is a member self plan — coach_id IS NULL
--      AND is_template IS FALSE (121:228 writes false; staff templates, 165:191,
--      write true; the column DEFAULTS to true, so an unset row is never deleted) —
--      and no remaining assignment of ANY client still references it. Before 190 a
--      client could attach an arbitrary programme to themselves, so a member's
--      coach-less assignment is not proof that its programme is theirs alone.
-- Behaviour kept from 047: the member's self-plan programmes ARE deleted, with
-- their days, versions, weekly feedback and predictions (all ON DELETE CASCADE);
-- communications keep their row with program_id set null. Coach-authored
-- assignments and programmes are never touched.
--
-- KNOWN RESIDUAL (not changed): workout_sessions.program_workout_id (001:149) has no
-- delete action. Nothing writes it today (no app or SQL path sets it), so it cannot
-- block this; if PD-B21 / I-WRK-03 starts populating it, deleting a self plan with
-- logged sessions would fail again — and generate_client_plan's regeneration with
-- it. Whether history should be kept or cleared is a data-retention decision.
--
-- Posture restated: SECURITY DEFINER, search_path pinned, EXECUTE for authenticated
-- only (116's allowlist class B: self-scoped member function).

BEGIN;

CREATE OR REPLACE FUNCTION public.deactivate_self_generated_plan()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
declare
  v_uid   uuid := auth.uid();
  v_progs uuid[];
begin
  if v_uid is null then return; end if;
  update client_nutrition_plans set is_active=false
    where client_id=v_uid and coach_id is null and is_active;
  update client_habits set is_active=false
    where client_id=v_uid and coach_id is null and is_active;

  -- Assignments first: they reference the programmes (no ON DELETE action).
  select array_agg(program_id) into v_progs
    from workout_program_assignments
   where client_id=v_uid and coach_id is null and program_id is not null;
  delete from workout_program_assignments
    where client_id=v_uid and coach_id is null;

  if v_progs is not null then
    delete from workout_programs wp
     where wp.id = any(v_progs)
       and wp.coach_id is null
       and wp.is_template is false
       and not exists (select 1 from workout_program_assignments a where a.program_id = wp.id);
  end if;
end;
$$;

REVOKE ALL ON FUNCTION public.deactivate_self_generated_plan() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deactivate_self_generated_plan() TO authenticated;

COMMENT ON FUNCTION public.deactivate_self_generated_plan() IS
  'Turns off the calling member''s self-generated plan (191): deactivates coach-less '
  'nutrition plans and habits, deletes coach-less assignments, then deletes their '
  'self-plan programmes (coach_id NULL, is_template false) that nothing else references.';

COMMIT;
