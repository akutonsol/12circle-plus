-- 114_rls_weekly_checkins.sql
--
-- PHASE 1B — closes D-03 (P0 on re-scoring). weekly_checkins carries free-text
-- health information and had no row level security at all.
--
-- ── THE HOLE (reproduced live on QA) ────────────────────────────────────────
-- Created in 000_baseline_preexisting_tables, never hardened. With the published
-- anon key, an unauthenticated caller could read every user's weight, energy,
-- stress, sleep, hunger, compliance percentage, free-text notes and their coach's
-- written feedback -- and INSERT, UPDATE or DELETE any of it. The Workstream D
-- run found rows tagged QA-PROBE-ANON already present at the start of the run,
-- i.e. a prior anonymous actor had already exercised this hole.
--
-- Corrupting these rows is not only a privacy breach: compliance %, the coach
-- at-risk roster (compliance_service) and ai_adjust_nutrition's weight-trend
-- calculation (migration 079) all read this table, so forged rows steer real
-- coaching and real nutrition prescriptions.
--
-- ── AUTHORITY (Phase 0, Q-1) ────────────────────────────────────────────────
-- Daily check-ins are the authoritative check-in source; weekly review behaviour
-- is to be DERIVED from daily data rather than kept as a competing source of
-- truth. That consolidation is deliberately NOT done here -- this migration only
-- makes the existing table safe. The dependency map is recorded in
-- docs/PHASE_1_SECURITY_AUDIT.md; retirement is a later phase.
--
-- ── THE MODEL ───────────────────────────────────────────────────────────────
-- Owner + their ACTIVE coach may read (the same shape migration 100 gave every
-- other health table). Writes are split by authorship, because one row is
-- co-authored:
--
--     the CLIENT owns   mood / energy / stress / sleep / weight / hunger /
--                       compliance / notes / status(pending,submitted)
--     the COACH  owns   feedback_message / feedback_recommendations /
--                       coach_name / reviewed_at / coach_id / status(reviewed)
--
-- A column GRANT is per-role, not per-relationship, so it cannot express that
-- split -- both parties arrive as `authenticated`. The trigger below does.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   ALTER TABLE public.weekly_checkins DISABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Authorship split.
--
-- Internal callers (service_role, the engine, migrations) run with
-- auth.uid() IS NULL and pass through; they bypass RLS anyway. The SECURITY
-- DEFINER functions that read this table -- ai_adjust_nutrition (079),
-- create_weekly_review / assemble_weekly_review (094), admin_platform_stats
-- (019) and trg_notify_coach_on_checkin (004) -- are unaffected: definer rights
-- mean RLS is evaluated as the owner, so they keep seeing every row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_checkin_authorship()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid     uuid := (SELECT auth.uid());
  v_changed text[];
  -- Columns only a coach may move.
  v_coach_cols constant text[] := ARRAY[
    'feedback_message', 'feedback_recommendations', 'coach_name',
    'reviewed_at', 'coach_id', 'status'
  ];
BEGIN
  IF v_uid IS NULL THEN
    RETURN NEW;                          -- internal / service-role path
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'weekly_checkins: id and user_id are immutable'
      USING ERRCODE = '42501';
  END IF;

  SELECT array_agg(k) INTO v_changed
    FROM jsonb_each(to_jsonb(NEW)) AS e(k, v)
   WHERE e.v IS DISTINCT FROM (to_jsonb(OLD) -> e.k);

  IF v_changed IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_uid = OLD.user_id THEN
    -- The client. May re-submit their own answers; may not author, forge or
    -- clear the coach's review.
    IF v_changed && (v_coach_cols[1:5]) THEN
      RAISE EXCEPTION 'weekly_checkins: coach review fields are not client-writable'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.status = 'reviewed' AND OLD.status IS DISTINCT FROM 'reviewed' THEN
      RAISE EXCEPTION 'weekly_checkins: a client cannot mark their own check-in reviewed'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    -- The coach (the UPDATE policy has already proved an active relationship).
    -- May write the review and nothing else -- the client's answers are their
    -- own record and stay as submitted.
    IF NOT (v_changed <@ v_coach_cols) THEN
      RAISE EXCEPTION 'weekly_checkins: a coach may only write the review fields (attempted: %)',
        array_to_string(ARRAY(SELECT unnest(v_changed) EXCEPT SELECT unnest(v_coach_cols)), ', ')
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_checkin_authorship ON public.weekly_checkins;
CREATE TRIGGER trg_checkin_authorship
  BEFORE UPDATE ON public.weekly_checkins
  FOR EACH ROW EXECUTE FUNCTION public.enforce_checkin_authorship();

-- ---------------------------------------------------------------------------
-- Privileges. anon loses the table outright; the anon key is public.
--
-- Table-level (not column-level) SELECT is intentional here: WeeklyCheckinService
-- reads with a bare .select(), i.e. select=*, and every column on this table is
-- legitimately visible to the two parties. There is no bearer credential to
-- withhold, unlike coach_client_relationships.invite_token.
--
-- No DELETE: nothing in the app deletes a check-in, and this is health-record
-- history. Erasure stays with service_role.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.weekly_checkins FROM PUBLIC, anon;
REVOKE ALL ON public.weekly_checkins FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON public.weekly_checkins TO authenticated;

-- ---------------------------------------------------------------------------
-- Row level security.
-- ---------------------------------------------------------------------------
ALTER TABLE public.weekly_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner or active coach reads checkin" ON public.weekly_checkins;
DROP POLICY IF EXISTS "owner creates own checkin"           ON public.weekly_checkins;
DROP POLICY IF EXISTS "owner or active coach updates checkin" ON public.weekly_checkins;

CREATE POLICY "owner or active coach reads checkin"
  ON public.weekly_checkins FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_active_coach_of(user_id)
  );

-- Only the subject creates their own check-in. A coach opening a row on a
-- client's behalf is not a flow this product has, and allowing it would let a
-- coach fabricate compliance history.
DROP POLICY IF EXISTS "owner creates own checkin" ON public.weekly_checkins;
CREATE POLICY "owner creates own checkin"
  ON public.weekly_checkins FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Both parties may update; trg_checkin_authorship decides which columns.
CREATE POLICY "owner or active coach updates checkin"
  ON public.weekly_checkins FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_active_coach_of(user_id)
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR public.is_active_coach_of(user_id)
  );

COMMENT ON TABLE public.weekly_checkins IS
  'Free-text health check-in. Owner + active coach only (migration 114). Feeds '
  'compliance scoring, the coach at-risk roster and ai_adjust_nutrition''s '
  'weight-trend calculation, so forged rows steer real prescriptions -- the '
  'write path matters as much as the read path. Per Phase 0 Q-1 this table is '
  'NOT the authoritative check-in source; weekly behaviour is to be derived from '
  'daily data in a later phase.';
