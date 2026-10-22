-- Migration 184. assign_nutrition_plan requires an ACTIVE coach-client relationship.
--
-- QAX-SEC-01 (P0) · decision OD-QAX-2, Option A.
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["184"]; environments.qa.applied_through is "181".
--
-- THE DEFECT. Migration 131's assign_nutrition_plan is SECURITY DEFINER, so its
-- UPDATE and INSERT bypass the RLS the direct table path enforces. It authorized
-- nobody: any authenticated caller could supersede ANY client's active plan and
-- install their own. 131's comment records the choice -- "deliberately NOT
-- stricter than the policy it replaces" -- because 3A-11 was not authorized to
-- change who may write. That authorization has now been given (below).
--
-- THE DECISION. OD-QAX-2 is answered Option A, with the sub-questions Q-A1..Q-A5
-- answered in docs/V5_DELEGATED_DETERMINATIONS_2026-10-21.md section 4.1. The
-- determination was made by Claude under the product owner's written delegation
-- and AUTHORIZED FOR IMPLEMENTATION by the owner in chat on 2026-10-21; the
-- ledger is .skills-agent/decisions.json. In short:
--   Q-A1  caller is auth.uid(); must be the coach side of an ACTIVE relationship
--         naming p_client_id -- public.is_active_coach_of(p_client_id) (migration
--         100). coach_id is still taken from auth.uid(); it is not a parameter.
--   Q-A2  only 'active' authorizes. 'pending', 'cancelled', ended and no row do
--         not. (migration 113: never grant a write path that lets one party name
--         the other without consent.)
--   Q-A3  ONE refusal -- 42501 'not authorized' -- for every reason, so the
--         function is not an oracle for whether a relationship exists.
--   Q-A4  the direct table policy is handled by migration 185, not here.
--   Q-A5  see supabase/tests/local/od_qax2_od14_replay.sql.
--
-- PRODUCT CONSEQUENCE. A coach can no longer assign a plan to a client who has
-- been invited but has not accepted. The plan is assigned after acceptance.
--
-- FUNCTION REPLACEMENT RULE. CREATE OR REPLACE preserves ACL and owner but NOT
-- proconfig or body, so the search_path pin is restated in the definition and the
-- REVOKE / GRANT / COMMENT are restated below. Signature, RETURNS, LANGUAGE,
-- VOLATILE and SECURITY DEFINER are unchanged from 131.
--
-- ATOMIC WITH its manifest declaration in supabase/expected_applied.json: the
-- manifest guard fails a file without a declaration and a declaration without a
-- file. This migration changes no table, policy or role.

BEGIN;

CREATE OR REPLACE FUNCTION public.assign_nutrition_plan(
  p_client_id       uuid,
  p_calories_target integer,
  p_protein_g       integer,
  p_carbs_g         integer,
  p_fat_g           integer,
  p_water_target_oz integer DEFAULT NULL,
  p_notes           text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_coach uuid := (SELECT auth.uid());
  v_id    uuid;
BEGIN
  IF v_coach IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'p_client_id is required' USING ERRCODE = '22004';
  END IF;

  -- OD-QAX-2 Option A. Before the supersede UPDATE: a refused call must change
  -- nothing, and the victim's active plan must still be the active one.
  IF NOT public.is_active_coach_of(p_client_id) THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  -- Supersede, then insert. Both in one transaction, under the partial unique
  -- index added by migration 131.
  UPDATE public.client_nutrition_plans
     SET is_active = false
   WHERE client_id = p_client_id
     AND is_active;

  INSERT INTO public.client_nutrition_plans (
    client_id, coach_id, calories_target, protein_g, carbs_g, fat_g,
    water_target_oz, notes, is_active
  )
  VALUES (
    p_client_id, v_coach, p_calories_target, p_protein_g, p_carbs_g, p_fat_g,
    p_water_target_oz, p_notes, true
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) TO authenticated;

COMMENT ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) IS
  'I-NUT-04 writer half + QAX-SEC-01 (OD-QAX-2, Option A): supersede the '
  'client''s active nutrition plan and insert the new one in ONE transaction, '
  'only when the caller is the coach of an ACTIVE coach_client_relationships '
  'row for p_client_id (is_active_coach_of). coach_id is taken from auth.uid() '
  'and is not a parameter. Every refusal is 42501 ''not authorized''.';

COMMIT;
