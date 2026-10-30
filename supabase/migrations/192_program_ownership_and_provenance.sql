-- Migration 192. A coach can attach, generate, replace or read only their OWN
-- programmes; and engine-generated training cannot be moved or copied out from
-- under the engine_selected mark that 189's assignment clearance depends on.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 189 (engine_selected,
-- _engine_client_clearance) and 190 (the assignment policy). Independent of 191.
-- Verified only on a local replay (supabase/tests/local/program_ownership_replay.sh).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IS WRONG (confirmed on the local 000-190 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
-- P0 · OWNERSHIP. Nothing checks that an assignment's programme belongs to the
--   coach who writes it (001/185/190 policies check only coach_id = auth.uid() and
--   an active relationship). Then can_act_on_program (116:109) and
--   can_read_program grant rights over a programme to the active coach of ANY
--   client assigned to it, and to the assigned client. So:
--     * coach K attached coach O's programme to K's client (insert, and re-pointing
--       an existing row by UPDATE);
--     * K then READ O's private days;
--     * K REGENERATED O's week with replace_existing — O's coach-edited day was
--       destroyed — and the assigned client could regenerate it too;
--     * O attached K's programme to O's uncleared client, after which K's own
--       generation was refused (a block, and a one-bit leak about O's client).
-- P1 · PROVENANCE. The "coaches manage program workouts" policy (001:354) is FOR
--   ALL with no WITH CHECK, so a coach could UPDATE a generated day's program_id
--   into an unmarked programme, or INSERT a verbatim copy of generated days into
--   one, and then assign that programme to an uncleared client: 189's guard never
--   sees engine_selected.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT CHANGES
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Assignment ownership (trigger, every writer). A row that is inserted, or
--    whose program_id / coach_id changes, or that BECOMES active, must name a
--    programme whose coach_id equals the row's coach_id — a coach's own programme
--    for a coach assignment, a coach-less self plan for a coach-less (member
--    self-plan) assignment. Otherwise ASSIGNMENT_PROGRAM_NOT_OWNED (42501), nothing
--    written. Deactivating or replacing any existing row (status away from active)
--    is never blocked, so assignProgram's "replace the current assignment" step
--    keeps working even over legacy rows. A client-role (`authenticated`) caller
--    who names a DIFFERENT coach is left to RLS (190 refuses them), so the trigger
--    is not an oracle of who owns which programme; the service role and the owner
--    bypass RLS and are therefore always checked, whatever claims they carry. Staff templates (coach_id NULL,
--    is_template true) cannot be attached by a coach — no app path does.
-- 2. Authoring rights (owner coach or admin). materialize_program_week,
--    regenerate_program and snapshot_program_version now require BOTH their
--    existing can_act_on_program check AND _program_author_or_admin (the
--    programme's own coach, or an admin; a call with no signed-in user — service
--    role / internal — stays allowed, as can_act_on_program already allows it).
--    An assigned client and the coach of an assigned client can no longer
--    generate, regenerate, replace or snapshot it. evaluate_week (read-only) is
--    unchanged.
-- 3. Read rights. can_read_program keeps: the owner, an admin, the assigned client,
--    and the active coach of a client assigned to a COACH-LESS (self-generated)
--    plan. It drops "authored an assignment of it" and "active coach of a client
--    assigned to it" for programmes owned by another coach. CONSEQUENCE: after a
--    client switches coach, the new coach no longer reads the previous coach's
--    programme content (190 already hid the previous coach's assignment rows).
-- 4. Day provenance (trigger on program_workouts, every writer):
--    * program_id is immutable — moving a day between programmes is refused
--      (PROGRAM_DAY_MOVE_REFUSED). No app path changes it; edits never send it.
--    * a day inserted or edited into an UNMARKED programme that carries any
--      UUID-shaped exercise_instance_id already present in a day of a DIFFERENT,
--      engine_selected programme marks the target engine_selected too. Only
--      UUID-shaped ids count: the engine (186/188) mints gen_random_uuid() ids and
--      Copilot now does too, while hand-built days carry 'ex-…' ids, so ordinary
--      editing never trips it.
-- 5. Marking a programme engine_selected (false -> true, by generation, by
--    propagation, or by any writer) is refused while it is ACTIVE for a client who
--    is not cleared (ENGINE_CLIENT_NOT_CLEARED), so marking cannot be used to slip
--    engine content under an existing uncleared assignment. (_engine_selected_sticky,
--    189, extended; the true -> false refusal is unchanged.)
--
-- RESIDUAL, stated plainly: a coach who RE-KEYS copied exercises (new ids) through
-- raw API calls produces content indistinguishable from hand-building; a Copilot-
-- shaped programme typed by hand is hand-built. Legacy cross-coach assignment rows
-- that already exist are not deleted or rewritten (a read-only audit of QA would
-- show whether any exist); they no longer grant read or authoring rights, but an
-- uncleared legacy row can still block marking of the programme it points at.
--
-- Posture: every function pins search_path; helpers and trigger functions are
-- revoked from PUBLIC, anon and authenticated; the three public RPCs keep EXECUTE
-- for authenticated only.

BEGIN;

-- ── helpers ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._program_author_or_admin(p_program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (SELECT auth.uid()) IS NULL
      OR public.is_admin()
      OR EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = p_program AND p.coach_id = (SELECT auth.uid()));
$$;

CREATE OR REPLACE FUNCTION public._is_uuid_text(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false);
$$;

-- ── 1. assignment ownership ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._assignment_program_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid;
  v_found boolean;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.program_id IS NOT DISTINCT FROM OLD.program_id
     AND NEW.coach_id   IS NOT DISTINCT FROM OLD.coach_id
     AND NOT (NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active') THEN
    RETURN NEW;   -- replacing / deactivating / week updates are never blocked
  END IF;
  -- A client-role caller naming another coach is refused by RLS; answering here
  -- would reveal who owns the programme. Keyed on the session ROLE, not on
  -- auth.uid(): RLS applies only to `authenticated`, so the service role and the
  -- owner (which bypass RLS) are always checked here, whatever claims they carry.
  IF current_setting('role', true) = 'authenticated'
     AND NEW.coach_id IS NOT NULL AND NEW.coach_id IS DISTINCT FROM auth.uid() THEN
    RETURN NEW;
  END IF;
  SELECT coach_id, true INTO v_owner, v_found FROM public.workout_programs WHERE id = NEW.program_id;
  IF NOT coalesce(v_found, false) OR v_owner IS DISTINCT FROM NEW.coach_id THEN
    RAISE EXCEPTION 'ASSIGNMENT_PROGRAM_NOT_OWNED: an assignment must name a programme owned by its '
      'coach (or, for a self-plan assignment, a coach-less programme). Nothing was assigned.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assignment_program_ownership ON public.workout_program_assignments;
CREATE TRIGGER assignment_program_ownership
  BEFORE INSERT OR UPDATE ON public.workout_program_assignments
  FOR EACH ROW EXECUTE FUNCTION public._assignment_program_ownership();

-- ── 2. authoring rights: owner coach or admin ──────────────────────────────
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

CREATE OR REPLACE FUNCTION public.regenerate_program(p_program_id uuid, p_week integer, p_approved boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.can_act_on_program(p_program_id)
     OR NOT public._program_author_or_admin(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  RETURN public.regenerate_program_engine(p_program_id, p_week, p_approved);
END;
$$;

CREATE OR REPLACE FUNCTION public.snapshot_program_version(p_program_id uuid, p_reason text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_next int; v_strat jsonb; v_plan jsonb;
BEGIN
  IF NOT public.can_act_on_program(p_program_id)
     OR NOT public._program_author_or_admin(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501';
  END IF;
  SELECT strategy, plan INTO v_strat, v_plan FROM workout_programs WHERE id = p_program_id;
  SELECT COALESCE(max(version), 0) + 1 INTO v_next FROM program_versions WHERE program_id = p_program_id;
  INSERT INTO program_versions(program_id, version, strategy, plan, reason, created_by)
  VALUES (p_program_id, v_next, v_strat, v_plan, p_reason, (SELECT auth.uid()));
  UPDATE workout_programs SET program_version = v_next WHERE id = p_program_id;
  RETURN v_next;
END;
$$;

-- ── 3. read rights ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_read_program(p_program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = p_program AND p.coach_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                  WHERE a.program_id = p_program AND a.client_id = (SELECT auth.uid()))
      -- a coach sees an active client's SELF-GENERATED plan, never another coach's programme
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                   JOIN public.workout_programs p ON p.id = a.program_id
                  WHERE a.program_id = p_program AND p.coach_id IS NULL
                    AND public.is_active_coach_of(a.client_id))
      OR public.is_admin();
$$;

-- ── 4. day provenance ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._program_workouts_provenance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids text[];
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.program_id IS DISTINCT FROM OLD.program_id THEN
    RAISE EXCEPTION 'PROGRAM_DAY_MOVE_REFUSED: a training day cannot be moved to another programme; '
      'add it to that programme instead. Nothing was changed.'
      USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.workout_programs WHERE id = NEW.program_id AND engine_selected) THEN
    RETURN NEW;
  END IF;
  IF jsonb_typeof(NEW.exercises) IS DISTINCT FROM 'array' THEN
    RETURN NEW;
  END IF;
  SELECT array_agg(i) INTO v_ids
    FROM (SELECT coalesce(e->>'exercise_instance_id', e->>'id') AS i
            FROM jsonb_array_elements(NEW.exercises) e) s
   WHERE public._is_uuid_text(i);
  IF v_ids IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1
               FROM public.program_workouts pw
               JOIN public.workout_programs p ON p.id = pw.program_id AND p.engine_selected
               CROSS JOIN LATERAL jsonb_array_elements(
                 CASE WHEN jsonb_typeof(pw.exercises) = 'array' THEN pw.exercises ELSE '[]'::jsonb END) e
              WHERE pw.program_id <> NEW.program_id
                AND coalesce(e->>'exercise_instance_id', e->>'id') = ANY (v_ids)) THEN
    -- Carry the mark with the copied training (refused by _engine_selected_sticky
    -- if the programme is already active for an uncleared client).
    UPDATE public.workout_programs SET engine_selected = true WHERE id = NEW.program_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS program_workouts_provenance ON public.program_workouts;
CREATE TRIGGER program_workouts_provenance
  BEFORE INSERT OR UPDATE ON public.program_workouts
  FOR EACH ROW EXECUTE FUNCTION public._program_workouts_provenance();

-- ── 5. marking under an uncleared assignment is refused ────────────────────
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
  IF NOT OLD.engine_selected AND NEW.engine_selected
     AND EXISTS (SELECT 1 FROM public.workout_program_assignments a
                  WHERE a.program_id = NEW.id AND a.status = 'active'
                    AND NOT (public._engine_client_clearance(a.client_id) ->> 'cleared')::boolean) THEN
    RAISE EXCEPTION 'ENGINE_CLIENT_NOT_CLEARED: programme % is assigned to a client who is not cleared '
      'for engine-generated training, so it cannot take engine-selected training. Nothing was changed.', NEW.id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

-- ── privileges ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._program_author_or_admin(uuid)      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._is_uuid_text(text)                 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._assignment_program_ownership()     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._program_workouts_provenance()      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_selected_sticky()           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.regenerate_program(uuid, integer, boolean)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.snapshot_program_version(uuid, text)           FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.materialize_program_week(uuid, integer, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.regenerate_program(uuid, integer, boolean)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.snapshot_program_version(uuid, text)           TO authenticated;

COMMIT;
