-- Migration 189. A programme that contains engine-selected training is marked so,
-- permanently, and the DATABASE refuses to make it active for a client who is not
-- cleared for engine-generated training — on every assignment path.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 124 (the
-- materialize_program_week wrapper it restates), 140/141 (assessment_access_log),
-- 115/126 (risk_level derivation) and 188. Verified only on a local replay
-- (supabase/tests/local/assignment_guard_replay.sh, engine_gate_replay.sh).
--
-- Owner direction 2026-10-25 (implementation target, NOT a recorded governance
-- decision; NOT a clinical policy): the initial walkthrough is limited to a client
-- with completed intake, explicit no-injury status, low PAR-Q risk and no
-- conflicting medical advice; engine-selected programmes may be assigned only to
-- such a client; existing assignments are NOT retroactively rechecked; there is
-- NO admin override. This file does not make injury or clinical handling safe and
-- does not represent clinical sign-off — the project names no clinical owner
-- (MASTER_PRODUCT_DECISIONS §D).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IS WRONG TODAY (proven on the 000-188 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
--   * a coach's direct API insert of an engine-generated programme for an
--     injured active client is ALLOWED — nothing checks injury status;
--   * a coach can flip workout_programs.engine_generated to false, and Copilot's
--     programmes are never flagged — so an app-only check keyed on that flag is
--     bypassable three ways;
--   * a client can insert their own assignment naming any coach and programme
--     (fixed separately in 190).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT CHANGES
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. workout_programs.engine_selected boolean NOT NULL DEFAULT false — a NEW
--    column, not engine_generated (which means "planned in Program Builder" and
--    drives the continuous-coaching list). It is STICKY: true -> false is refused
--    for every writer (ENGINE_SELECTED_IS_PERMANENT), including the owner and the
--    service role — no override. Coach edits to the days do not clear it.
--    Set by: materialize_program_week (below) on every successful generation, and
--    by the app when Copilot saves a recommendation as a programme. Any writer may
--    set it true; that only makes the guard stricter.
-- 2. _engine_client_clearance(client) -> {cleared, reasons[]}, one rule:
--      INTAKE_INCOMPLETE   onboarding_complete is not true
--      INJURY_REPORTED     has_injuries is not false, or injury_locations is set
--      PARQ_INCOMPLETE     parq_answers lacks a boolean answer to any of Q1-Q8
--                          (an EMPTY PAR-Q derives risk_level 'low' — 126 — so
--                          "low" alone is not evidence)
--      PARQ_RISK_NOT_LOW   risk_level is not 'low' (null included)
--      MEDICAL_ADVICE      PAR-Q Q7 (doctor advised against exercise) or Q8 (other
--                          medical reason) answered yes, or either flag present
--      NO_PROFILE          no user_profiles row
--    medical_conditions free text is NOT interpreted beyond what 126 already
--    folds into risk_level (pregnancy, heart disease, high blood pressure).
-- 3. engine_client_clearance(p_client): the same verdict for the app (Copilot),
--    active coach only (is_active_coach_of — the get_client_assessment rule), and
--    LOGGED to assessment_access_log as 'assessment_view', because it reads
--    intake data. It returns reason codes, never the underlying answers.
-- 4. Trigger on workout_program_assignments (BEFORE INSERT OR UPDATE): a row that
--    BECOMES active for an engine_selected programme — an insert, a reactivation,
--    or a change of programme or client — requires a cleared client, else
--    ENGINE_CLIENT_NOT_CLEARED (42501) and nothing is written. An assignment that
--    was already active and keeps its programme and client is NOT rechecked.
--    The error names no reasons (the caller may not be entitled to them); a
--    caller who is neither the client nor the client's active coach is passed
--    through to RLS, so the trigger is not an oracle of a stranger's health status.
--    Applies to the service role too.
-- 5. materialize_program_week (124's wrapper) — authorization unchanged
--    (can_act_on_program first) — after a successful generation it refuses if the
--    programme is ACTIVELY assigned to any client who is not cleared (generating
--    onto an already-assigned programme is a new routing of engine output;
--    ENGINE_CLIENT_NOT_CLEARED, whole call rolled back), then sets engine_selected.
--
-- CONSEQUENCES: a programme that ever held engine-selected training can never be
-- made active for an uncleared client, even after the coach rewrites its days —
-- the coach builds a separate programme. A client whose status changes after
-- assignment is not re-checked. An app build that sets the flag needs this
-- migration applied; Copilot treats a missing clearance RPC as "not cleared".
--
-- KNOWN GAPS (not closed here): copying a flagged programme's days into a new
-- programme through raw API calls produces an unflagged programme (that is
-- hand-building by another name); a coach can create a Copilot-shaped programme
-- without the flag through raw API calls. Neither is an app path.
--
-- Posture: every function pins search_path; helpers and trigger functions are
-- revoked from PUBLIC, anon and authenticated; engine_client_clearance and the
-- wrapper are executable by authenticated only.

BEGIN;

ALTER TABLE public.workout_programs
  ADD COLUMN IF NOT EXISTS engine_selected boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.workout_programs.engine_selected IS
  'True once the programme holds engine-selected training (Program Builder generation '
  'or a saved Copilot recommendation). Permanent: it cannot be cleared (189). An '
  'engine_selected programme can be made active only for a cleared client.';

-- ── 1. sticky flag ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._engine_selected_sticky()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.engine_selected AND NOT NEW.engine_selected THEN
    RAISE EXCEPTION 'ENGINE_SELECTED_IS_PERMANENT: programme % holds engine-selected training; '
      'the mark cannot be removed', OLD.id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS engine_selected_sticky ON public.workout_programs;
CREATE TRIGGER engine_selected_sticky
  BEFORE UPDATE OF engine_selected ON public.workout_programs
  FOR EACH ROW EXECUTE FUNCTION public._engine_selected_sticky();

-- ── 2. the clearance rule ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._engine_client_clearance(p_client uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN p.id IS NULL
    THEN jsonb_build_object('cleared', false, 'reasons', jsonb_build_array('NO_PROFILE'))
    ELSE jsonb_build_object('cleared', cardinality(r.reasons) = 0, 'reasons', to_jsonb(r.reasons)) END
  FROM (SELECT p_client AS id) want
  LEFT JOIN public.user_profiles p ON p.id = want.id
  CROSS JOIN LATERAL (SELECT array_remove(ARRAY[
      CASE WHEN p.onboarding_complete IS NOT TRUE THEN 'INTAKE_INCOMPLETE' END,
      CASE WHEN p.has_injuries IS DISTINCT FROM false
             OR btrim(coalesce(p.injury_locations, '')) <> '' THEN 'INJURY_REPORTED' END,
      CASE WHEN jsonb_typeof(p.parq_answers) IS DISTINCT FROM 'object'
             OR EXISTS (SELECT 1 FROM unnest(ARRAY['1','2','3','4','5','6','7','8']) q
                         WHERE jsonb_typeof(p.parq_answers -> q) IS DISTINCT FROM 'boolean')
           THEN 'PARQ_INCOMPLETE' END,
      CASE WHEN p.risk_level IS DISTINCT FROM 'low' THEN 'PARQ_RISK_NOT_LOW' END,
      CASE WHEN p.parq_answers ->> '7' = 'true' OR p.parq_answers ->> '8' = 'true'
             OR coalesce(p.risk_flags, '') ~ '(doctor_advised_no_exercise|other_medical_reason)'
           THEN 'MEDICAL_ADVICE' END], NULL) AS reasons) r;
$$;

-- ── 3. the app's read of the verdict ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.engine_client_clearance(p_client uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_active_coach_of(p_client) THEN
    RAISE EXCEPTION 'not authorized to read this client''s clearance' USING ERRCODE = '42501';
  END IF;
  -- It reads intake data, so it is logged exactly like get_client_assessment.
  INSERT INTO public.assessment_access_log (coach_id, client_id, event)
  VALUES (auth.uid(), p_client, 'assessment_view');
  RETURN public._engine_client_clearance(p_client);
END;
$$;

-- ── 4. assignment-time guard ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._engine_assignment_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_engine boolean;
BEGIN
  IF NEW.status IS DISTINCT FROM 'active' THEN
    RETURN NEW;
  END IF;
  -- Not retroactive: an assignment that stays active on the same programme and
  -- client (a current_week update, say) is not rechecked.
  IF TG_OP = 'UPDATE' AND OLD.status = 'active'
     AND NEW.program_id = OLD.program_id AND NEW.client_id = OLD.client_id THEN
    RETURN NEW;
  END IF;
  SELECT engine_selected INTO v_engine FROM public.workout_programs WHERE id = NEW.program_id;
  IF NOT coalesce(v_engine, false) THEN
    RETURN NEW;
  END IF;
  -- A caller who is neither the client nor their active coach is left to RLS:
  -- answering them here would reveal whether a stranger is cleared.
  IF auth.uid() IS NOT NULL AND auth.uid() <> NEW.client_id
     AND NOT public.is_active_coach_of(NEW.client_id) THEN
    RETURN NEW;
  END IF;
  IF NOT (public._engine_client_clearance(NEW.client_id) ->> 'cleared')::boolean THEN
    RAISE EXCEPTION 'ENGINE_CLIENT_NOT_CLEARED: programme % holds engine-selected training and this '
      'client is not cleared for engine-generated training (completed intake, no reported injury, '
      'complete low-risk PAR-Q, no medical advice against exercise). Nothing was assigned.',
      NEW.program_id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS engine_assignment_guard ON public.workout_program_assignments;
CREATE TRIGGER engine_assignment_guard
  BEFORE INSERT OR UPDATE ON public.workout_program_assignments
  FOR EACH ROW EXECUTE FUNCTION public._engine_assignment_guard();

-- ── 5. the generation wrapper (124), authorization first and unchanged ─────
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
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program'
      USING ERRCODE = '42501';
  END IF;

  v_result := public.materialize_program_week_engine(p_program_id, p_week, p_context);

  -- Generating onto a programme already ACTIVE for an uncleared client would route
  -- engine output to that client; refuse, and the whole call (days included) rolls back.
  IF EXISTS (SELECT 1 FROM public.workout_program_assignments a
              WHERE a.program_id = p_program_id AND a.status = 'active'
                AND NOT (public._engine_client_clearance(a.client_id) ->> 'cleared')::boolean) THEN
    RAISE EXCEPTION 'ENGINE_CLIENT_NOT_CLEARED: programme % is assigned to a client who is not cleared '
      'for engine-generated training. Nothing was generated.', p_program_id
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.workout_programs SET engine_selected = true
   WHERE id = p_program_id AND NOT engine_selected;
  RETURN v_result;
END;
$$;

-- ── privileges ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._engine_selected_sticky()          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_client_clearance(uuid)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_assignment_guard()         FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.engine_client_clearance(uuid)      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.engine_client_clearance(uuid)   TO authenticated;
REVOKE ALL ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) TO authenticated;

COMMENT ON FUNCTION public.engine_client_clearance(uuid) IS
  'Whether a client is cleared for engine-generated training under the initial-walkthrough '
  'restriction (189): {cleared, reasons[]}. Active coach only; logged as assessment_view. '
  'Not a clinical assessment.';
COMMENT ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) IS
  'Authorization wrapper (124) over the programme engine. 189: refuses if the programme is '
  'actively assigned to an uncleared client, and marks it engine_selected on success.';

COMMIT;
