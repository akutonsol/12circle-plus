-- 140_assessment_access.sql — N-07 Coach Client Assessment
--
-- LANDED 2026-09-29 under OWNER DECISION OD-56 = A. Authored as
-- docs/proposed/N07_assessment_access.sql and held unnumbered because
-- `docs/MASTER_REMEDIATION_WAVES.md` §0.2 assigns numbers "at wave entry, never
-- before". 140 was verified free before the move: authored migrations topped out
-- at 139, the QA ledger read 139, and the declared frontier was 139 — the number
-- was checked, not assumed.
--
-- ONE CHANGE was made to the proposed text when it landed, and nothing else:
-- `SET search_path` was widened from `public` to `public, pg_temp`. V5 §30.2
-- recorded that exactly four functions carry the weaker `public`-only pin and
-- that they are the whole authorization surface; Postgres searches the temp
-- schema FIRST for relation names when `pg_temp` is not listed. This body does
-- schema-qualify every reference, so the weaker pin was not exploitable — but
-- 136/137 and 128 of the schema's 133 functions use the stronger form, and
-- landing a fifth weakly-pinned definer function onto the PHI surface would have
-- been a step backwards. Nothing else in the file was altered.
--
-- ===========================================================================
-- WHY
-- ===========================================================================
--
-- N-07 requires: "A coach may only access assessment/intake data belonging to
-- their assigned clients. Do not expose assessment data for unassigned
-- clients", with the privacy copy "Only you and Amara can see this. Opening it
-- is logged."
--
-- Two facts make that impossible on the existing path:
--
--  1. Intake writes 32 columns onto `user_profiles`, including `parq_answers`,
--     `risk_level`, `risk_score`, `medical_conditions`, `has_injuries`,
--     `injury_locations`, `injury_description` and `food_allergies`.
--
--  2. Migration 102's SELECT policy grants the WHOLE ROW to
--        id = auth.uid()
--        OR public.is_active_coach_of(id)
--        OR public.is_team_lead_of(id)      -- head coach, coach_team_members
--        OR public.hosts_event_for(id)      -- ANY event vendor the client
--                                           -- registered with
--     102's own header shows the last two were added for a team ROSTER and an
--     attendee LIST -- i.e. for names. They nonetheless carry the medical
--     columns with them.
--
-- So today an event vendor can read the PAR-Q answers and injury history of
-- anyone who registered for their event, and the N-07 copy would be false.
--
-- ===========================================================================
-- APPROACH — additive, not a policy rewrite
-- ===========================================================================
--
-- This does NOT alter migration 102's policy. Narrowing that policy would
-- break coach_business_screen (team roster) and vendor_portal_screen
-- (attendee list), both of which legitimately need names.
--
-- Instead it adds a dedicated, narrow read path for assessment data which
-- admits ONLY the active assigned coach -- not team leads, not event hosts --
-- and which records every access. The residual exposure on the base table is
-- recorded separately as a security finding (see docs section at the bottom).
--
-- This mirrors the pattern 102 itself established for messaging: a narrow
-- authorization predicate plus a projection, rather than a row grant.

-- ---------------------------------------------------------------------------
-- 1. The audit log. Append-only.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.assessment_access_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event       text NOT NULL DEFAULT 'assessment_view',
  accessed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT assessment_access_log_event_chk
    CHECK (event IN ('assessment_view'))
);

CREATE INDEX IF NOT EXISTS assessment_access_log_client_idx
  ON public.assessment_access_log (client_id, accessed_at DESC);
CREATE INDEX IF NOT EXISTS assessment_access_log_coach_idx
  ON public.assessment_access_log (coach_id, accessed_at DESC);

ALTER TABLE public.assessment_access_log ENABLE ROW LEVEL SECURITY;

-- The subject can see who opened their assessment. This is what makes the
-- privacy claim inspectable rather than merely asserted.
DROP POLICY IF EXISTS "client reads own assessment access log"
  ON public.assessment_access_log;
CREATE POLICY "client reads own assessment access log"
  ON public.assessment_access_log FOR SELECT TO authenticated
  USING (client_id = auth.uid());

-- A coach can see their own access history (their own actions only).
DROP POLICY IF EXISTS "coach reads own assessment access log"
  ON public.assessment_access_log;
CREATE POLICY "coach reads own assessment access log"
  ON public.assessment_access_log FOR SELECT TO authenticated
  USING (coach_id = auth.uid());

-- Deliberately NO insert/update/delete policy for `authenticated`. Rows are
-- written only by the SECURITY DEFINER function below, and nothing may edit or
-- erase an audit row -- an audit log a caller can rewrite is not an audit log.
REVOKE INSERT, UPDATE, DELETE ON public.assessment_access_log FROM authenticated;
REVOKE ALL ON public.assessment_access_log FROM anon;

-- ---------------------------------------------------------------------------
-- 2. The narrow read path.
-- ---------------------------------------------------------------------------
--
-- VOLATILE (the default for plpgsql) because it writes the audit row; a STABLE
-- function could not. SECURITY DEFINER so the authorization check and the log
-- write are not themselves filtered by RLS. search_path pinned, per the
-- standing requirement recorded in the security workstream.

CREATE OR REPLACE FUNCTION public.get_client_assessment(p_client uuid)
RETURNS TABLE (
  client_id                uuid,
  has_assessment           boolean,
  onboarding_complete      boolean,
  -- identity / basics
  first_name               text,
  last_name                text,
  date_of_birth            date,
  gender                   text,
  height_cm                numeric,
  weight_kg                numeric,
  weight_goal_kg           numeric,
  -- safety-critical
  parq_answers             jsonb,
  risk_level               text,
  risk_score               integer,
  risk_flags               text,
  medical_conditions       text,
  has_injuries             boolean,
  injury_locations         text,
  injury_description       text,
  food_allergies           text,
  dietary_restrictions     text,
  -- training context
  experience_level         text,
  worked_with_coach_before boolean,
  activity_level           text,
  training_days_per_week   integer,
  training_location        text,
  -- lifestyle
  sleep_hours              numeric,
  stress_level             integer,
  occupation               text,
  -- goals
  fitness_goal             text,
  target_timeline          text,
  nutrition_goal           text,
  protein_confidence       text,
  biggest_challenges       text,
  activities               text[],
  -- consent
  consent_agreed           boolean,
  consent_date             timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- ONLY the active assigned coach. Deliberately NOT is_team_lead_of() and
  -- NOT hosts_event_for(): a roster or an attendee list is not a clinical
  -- relationship. Deliberately not self-access either -- a client reads their
  -- own intake through the existing own-profile policy, which needs no audit
  -- row and no definer escalation.
  IF NOT public.is_active_coach_of(p_client) THEN
    RAISE EXCEPTION 'not authorized to read this assessment'
      USING ERRCODE = '42501';
  END IF;

  -- Log BEFORE returning. If the insert fails the read does not happen; an
  -- unlogged access would falsify the privacy copy shown on the screen.
  INSERT INTO public.assessment_access_log (coach_id, client_id, event)
  VALUES (auth.uid(), p_client, 'assessment_view');

  RETURN QUERY
  SELECT
    p.id,
    (p.parq_answers IS NOT NULL OR p.onboarding_complete IS TRUE),
    p.onboarding_complete,
    p.first_name, p.last_name, p.date_of_birth, p.gender,
    p.height_cm, p.weight_kg, p.weight_goal_kg,
    p.parq_answers, p.risk_level, p.risk_score, p.risk_flags,
    p.medical_conditions, p.has_injuries, p.injury_locations,
    p.injury_description, p.food_allergies, p.dietary_restrictions,
    p.experience_level, p.worked_with_coach_before, p.activity_level,
    p.training_days_per_week, p.training_location,
    p.sleep_hours, p.stress_level, p.occupation,
    p.fitness_goal, p.target_timeline, p.nutrition_goal,
    p.protein_confidence, p.biggest_challenges, p.activities,
    p.consent_agreed, p.consent_date
  FROM public.user_profiles p
  WHERE p.id = p_client;
  -- No row => the client has no profile. The caller must render that as
  -- "no assessment on file", NOT as an empty assessment. `has_assessment`
  -- distinguishes "profile exists, intake never completed" from both.
END;
$$;

REVOKE ALL ON FUNCTION public.get_client_assessment(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_client_assessment(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_client_assessment(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- NOTE — a schema/code type mismatch found while writing this
-- ---------------------------------------------------------------------------
-- `intake_data.dart` models medical_conditions, injury_locations and
-- dietary_restrictions as List<String>, but all three columns are TEXT (not
-- text[]). risk_flags is likewise TEXT while the Dart side treats it as a list.
-- The return types above follow the DATABASE, which is authoritative. Whatever
-- delimiter the writer uses is a display concern for the caller, and is worth a
-- separate look -- a list flattened into TEXT round-trips badly.
--
-- ---------------------------------------------------------------------------
-- Rollback
-- ---------------------------------------------------------------------------
--   DROP FUNCTION IF EXISTS public.get_client_assessment(uuid);
--   DROP TABLE IF EXISTS public.assessment_access_log;
-- Dropping the log destroys audit history; export before rolling back.
