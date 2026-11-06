-- Migration 194. Two information leaks found by the final read-only audit of
-- 187–193 are closed: a coach can no longer infer a FORMER client's current
-- clearance from whether their own programme may be marked or generated, and an
-- unauthorized API write can no longer tell a coach-owned programme id from a
-- coach-less one (staff template or member self plan).
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 189, 192 and 193.
-- Independent of 191. Verified only on a local replay
-- (supabase/tests/local/assignment_visibility_replay.sh).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- A · FORMER-CLIENT CLEARANCE (confirmed on the 000-193 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
-- Ending coaching (CoachRelationshipService.cancelCoach -> status 'cancelled')
-- touches no assignment, and no trigger or function does: the client keeps their
-- active programme. That is the existing lifecycle, so this migration does NOT
-- deactivate anything. But two checks consulted the clearance of EVERY active
-- assignment of a programme on the caller's behalf:
--   * materialize_program_week (192) refused generation if any active assignee
--     was uncleared;
--   * _engine_selected_sticky (192) refused marking a programme (by generation, by
--     copy propagation, or by a direct update) under the same condition.
-- So a coach who pasted generated days into a programme still active for a FORMER
-- client was refused if that person had since become uncleared and allowed if
-- not — their current clearance, to someone who no longer coaches them. Legacy
-- cross-coach assignment rows (written before 192) leaked the same way about a
-- stranger.
--
-- FIX: _engine_marking_block(programme) decides, for both paths:
--   1. an API caller (193's _api_caller) with ANY active assignment of the
--      programme whose client is neither the caller nor a client the caller
--      ACTIVELY coaches -> 'UNVERIFIABLE', raised as ENGINE_ASSIGNMENT_UNVERIFIABLE
--      BEFORE any clearance is evaluated, so the outcome is the same whether that
--      person is cleared or not;
--   2. otherwise, any uncleared active assignee -> ENGINE_CLIENT_NOT_CLEARED, as
--      before (the caller actively coaches every assignee, so they are entitled to
--      it — engine_client_clearance already tells them);
--   3. a call with no API caller (service role without user claims, a trusted owner
--      session) is checked fully, as before.
-- Admins are NOT treated as entitled: the owner-approved admin capability matrix
-- (docs/design/admin-dashboard/ADMIN-CAPABILITY-MATRIX.json) grants no
-- assessment, PAR-Q, injury or medical capability. An admin acting through the
-- API therefore gets the same refusal; administrative maintenance through a
-- trusted owner session is checked fully and unaffected.
-- CONSEQUENCE: a programme still active for someone the coach no longer coaches
-- cannot take engine-selected training (generation, a pasted copy, or a direct
-- mark) through the API. Hand-built editing of it is unchanged, as is assignment
-- replacement for current clients. The former coach cannot retire that row (190's
-- policy needs an active relationship); whether former coaches should be able to
-- is a product decision, not taken here.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- B · COACH-LESS PROGRAMME ORACLE (confirmed on the 000-193 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
-- An API write naming no coach reached 192/193's ownership check, which answered
-- ASSIGNMENT_PROGRAM_NOT_OWNED for a coach-owned programme id but let a coach-less
-- one through to RLS ("new row violates row-level security policy") — revealing
-- which kind of programme a known id is. Every coach-less assignment written
-- directly by an RLS-bound role is unauthorized anyway (190: only an active coach
-- writes, naming themselves); the legitimate coach-less writers are SECURITY
-- DEFINER functions (generate_client_plan and its predecessors), whose statements
-- run as their owner.
--
-- FIX: _assignment_api_write_scope, a SECURITY INVOKER trigger that fires FIRST
-- (by name) on workout_program_assignments. Because it runs as the role that
-- executes the statement, it can tell a direct API write (authenticated / anon —
-- roles that neither own the table nor bypass RLS) from a definer function's write
-- (the function owner) and from trusted writers (service role, owner session).
-- A coach-less row written directly by an RLS-bound role is refused with
-- ASSIGNMENT_NOT_AUTHORIZED before any programme is looked at. It reads no table
-- but the catalog, so it needs no privilege its callers lack.
--   Unchanged: member self plans (definer), service-role and owner maintenance of
--   coach-less rows (fully checked by 192/193: the programme must be coach-less),
--   staff templates (created by admin_create_program_template, a definer; no app
--   path assigns them, and a coach never can — 192).
--
-- Posture: every function pins search_path; helpers and trigger functions are
-- revoked from PUBLIC, anon and authenticated; materialize_program_week keeps
-- EXECUTE for authenticated only. Authorization of the wrapper is unchanged
-- (can_act_on_program AND _program_author_or_admin, 192).

BEGIN;

-- ── A · the one decision for marking and generation ────────────────────────
CREATE OR REPLACE FUNCTION public._engine_marking_block(p_program uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := public._api_caller();
BEGIN
  -- Decided BEFORE any clearance is read: the answer must not depend on it.
  IF v_caller IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.workout_program_assignments a
        WHERE a.program_id = p_program AND a.status = 'active'
          AND a.client_id IS DISTINCT FROM v_caller
          AND NOT public.is_active_coach_of(a.client_id)) THEN
    RETURN 'UNVERIFIABLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.workout_program_assignments a
              WHERE a.program_id = p_program AND a.status = 'active'
                AND NOT (public._engine_client_clearance(a.client_id) ->> 'cleared')::boolean) THEN
    RETURN 'NOT_CLEARED';
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._engine_marking_raise(p_program uuid, p_block text, p_action text)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_block = 'UNVERIFIABLE' THEN
    RAISE EXCEPTION 'ENGINE_ASSIGNMENT_UNVERIFIABLE: programme % is still active for someone you do not '
      'currently coach, so it cannot take engine-selected training. Nothing was %.', p_program, p_action
      USING ERRCODE = '42501';
  ELSIF p_block = 'NOT_CLEARED' THEN
    RAISE EXCEPTION 'ENGINE_CLIENT_NOT_CLEARED: programme % is assigned to a client who is not cleared '
      'for engine-generated training. Nothing was %.', p_program, p_action
      USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._engine_selected_sticky()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.engine_selected AND NOT NEW.engine_selected THEN
    RAISE EXCEPTION 'ENGINE_SELECTED_IS_PERMANENT: programme % holds engine-selected training; '
      'the mark cannot be removed', OLD.id
      USING ERRCODE = '42501';
  END IF;
  IF NOT OLD.engine_selected AND NEW.engine_selected THEN
    PERFORM public._engine_marking_raise(NEW.id, public._engine_marking_block(NEW.id), 'changed');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.materialize_program_week(
  p_program_id uuid,
  p_week integer,
  p_context jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.can_act_on_program(p_program_id)
     OR NOT public._program_author_or_admin(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program'
      USING ERRCODE = '42501';
  END IF;

  v_result := public.materialize_program_week_engine(p_program_id, p_week, p_context);

  -- 194: routing engine output to the programme's active assignees is refused if
  -- any of them is not the caller's current client (without consulting their
  -- clearance), or if any is uncleared; the whole call (days included) rolls back.
  PERFORM public._engine_marking_raise(p_program_id, public._engine_marking_block(p_program_id), 'generated');

  UPDATE public.workout_programs SET engine_selected = true
   WHERE id = p_program_id AND NOT engine_selected;
  RETURN v_result;
END;
$$;

-- ── B · coach-less rows written directly through the API ───────────────────
CREATE OR REPLACE FUNCTION public._assignment_api_write_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- current_user here is the role executing the statement (this function is NOT
  -- a definer): authenticated/anon for a direct API write, the owner inside a
  -- SECURITY DEFINER function, service_role or the owner for trusted writers.
  IF NEW.coach_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
                      WHERE r.rolname = current_user AND (r.rolsuper OR r.rolbypassrls))
     AND current_user IS DISTINCT FROM (SELECT pg_catalog.pg_get_userbyid(c.relowner)
                                          FROM pg_catalog.pg_class c WHERE c.oid = TG_RELID) THEN
    RAISE EXCEPTION 'ASSIGNMENT_NOT_AUTHORIZED: you cannot write this assignment. Nothing was assigned.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assignment_api_write_scope ON public.workout_program_assignments;
CREATE TRIGGER assignment_api_write_scope
  BEFORE INSERT OR UPDATE ON public.workout_program_assignments
  FOR EACH ROW EXECUTE FUNCTION public._assignment_api_write_scope();

-- ── privileges ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._engine_marking_block(uuid)            FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_marking_raise(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_selected_sticky()               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._assignment_api_write_scope()           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) TO authenticated;

COMMIT;
