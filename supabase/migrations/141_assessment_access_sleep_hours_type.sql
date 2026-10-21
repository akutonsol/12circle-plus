-- 141_assessment_access_sleep_hours_type.sql
--
-- A DEFECT REPAIR for migration 140. Not new scope.
--
-- ===========================================================================
-- THE DEFECT
-- ===========================================================================
--
-- 140 declared `get_client_assessment()`'s 26th output column as
-- `sleep_hours numeric`. `user_profiles.sleep_hours` is **text**. PostgreSQL
-- validates a RETURNS TABLE signature against the query at EXECUTION time, so
-- 140 applied cleanly and the function was created -- and then failed on every
-- single call:
--
--   42804 — "structure of query does not match function result type:
--            Returned type text does not match expected type numeric in column 26."
--
-- Observed against QA as the assigned coach, whose authorization was fine:
-- `is_active_coach_of(victim)` returned true in the same session. The function
-- was unusable by anyone, so d09's audit-log assertions failed downstream too --
-- no read happened, so nothing was logged.
--
-- `N07_IMPLEMENTATION_STATUS.md` §6 says all 36 column types "were verified
-- against the migrations before writing; five type errors were caught and
-- corrected". This was the sixth, and it survived because the suite had never
-- been executed -- exactly the gap §42 recorded when it declined to register
-- d09 on the strength of it being "authored".
--
-- ===========================================================================
-- THE REPAIR
-- ===========================================================================
--
-- A function's return type cannot be changed by CREATE OR REPLACE, so the
-- function is dropped and recreated. 140 is NOT rewritten in place -- it is
-- applied on QA and its ledger row stands (QA_CLOSURE_STANDARD §8:219). This is
-- the same shape as 137 repairing 136.
--
-- ONLY the one type changes. The authorization gate, the audit INSERT, the
-- ordering (log before return), the search_path pin and the grants are carried
-- over verbatim, and the grants are re-issued because DROP discards them.

BEGIN;

DROP FUNCTION IF EXISTS public.get_client_assessment(uuid);

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
  sleep_hours              text,
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

COMMENT ON FUNCTION public.get_client_assessment(uuid) IS
  'N-07 (migration 140, return type repaired by 141). The narrow assessment read '
  'path: admits is_active_coach_of ALONE -- not team leads, not event hosts -- and '
  'writes assessment_access_log BEFORE returning, so an unlogged access cannot '
  'happen. sleep_hours is text because user_profiles.sleep_hours is text; 140 '
  'declared it numeric and the function raised 42804 on every call.';

COMMIT;
