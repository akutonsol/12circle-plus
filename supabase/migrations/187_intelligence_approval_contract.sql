-- Migration 187. Exercise intelligence is 'approved' only through human review of
-- every attribute group — never on model self-confidence, never on an empty
-- attribute map, never by a direct status write — and an edit to a reviewed
-- attribute withdraws the approval.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Verified only on a local replay
-- (supabase/tests/local/engine_gate_replay.sh); not on QA, not in production.
--
-- Owner direction 2026-10-25 (decision B, as an implementation target — NOT a
-- recorded governance decision): "Model self-confidence alone must never approve
-- intelligence; empty attribute maps must fail; approval must require the
-- required human attribute reviews; edits to reviewed attributes must invalidate
-- approval." product-bible.md:33: AI-drafted intelligence flows "through a human
-- review pipeline (per-attribute) before the engine consumes them".
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IS WRONG TODAY (read from the 000-186 replay catalog)
-- ═══════════════════════════════════════════════════════════════════════════
--   * review_intelligence(id, 'approved') (090) sets status = 'approved' in one
--     call with no precondition.
--   * finalize_intelligence (091) approves every attribute whose MODEL-reported
--     confidence is >= p_threshold (default 90) with no human review at all —
--     enrich-exercise-intelligence writes that confidence from the model's own
--     JSON — and approves outright when attribute_confidence is EMPTY, because
--     its loop never runs and all_ok stays true.
--   * Nothing ties a review to the value reviewed: an attribute rewritten after
--     its approval keeps that approval, and an 'approved' profile stays approved.
--   * Nothing stops a writer that bypasses the functions (service role, SQL)
--     from storing status = 'approved'.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE CONTRACT
-- ═══════════════════════════════════════════════════════════════════════════
-- REQUIRED ATTRIBUTES are the eight groups the enrichment prompt and 090's
-- attribute_confidence document. EVERY one needs a human approval — the set is
-- fixed here, not read from attribute_confidence, so a profile cannot shrink its
-- own review burden. Each scoring column belongs to exactly one group:
--   programming_goals  goal_strength/hypertrophy/power/endurance/fat_loss,
--                      beginner/intermediate/advanced, min_experience,
--                      energy_systems, profile.goals, profile.programming
--   fatigue            local_fatigue, systemic_fatigue, recovery_cost,
--                      profile.fatigue, profile.fatigue_extra
--   joint_stress       joint_stress
--   contraindications  contraindications
--   rep_ranges         rep_ranges, frequency_per_week
--   biomechanics       technical_complexity, coordination, balance,
--                      mobility_requirement, profile.skill, profile.biomechanics
--   loading            profile.loading
--   coaching           profile.coaching
-- A review records a FINGERPRINT (md5 of the group's value) taken by the database
-- at the moment of review. It counts only while the value still matches.
--
-- A profile is approvable only when ALL hold:
--   1. attribute_confidence is a non-empty object (an unenriched profile has no
--      attribute map and fails — the owner's "empty attribute maps must fail");
--   2. every required attribute has a review with status 'approved', recorded
--      by a signed-in content editor (reviewed_by = auth.uid(), is_content_editor());
--   3. every such review's fingerprint equals the attribute's current value.
-- Model confidence plays NO part. p_threshold is still accepted by
-- finalize_intelligence and attribute_review_state so existing callers keep
-- working; it is ignored.
--
-- ENFORCEMENT is in triggers, so it holds for every writer, not only for the
-- functions:
--   * exercise_intelligence BEFORE INSERT/UPDATE: a row may BECOME 'approved'
--     only if the contract holds (else INTEL_APPROVAL_REFUSED, nothing written);
--     an 'approved' row whose contract stops holding on update (a reviewed
--     attribute edited, the map emptied) is written as 'under_review' instead.
--   * intelligence_attribute_reviews BEFORE INSERT/UPDATE: an 'approved' review
--     must be recorded by a signed-in content editor in their own name
--     (INTEL_REVIEW_NOT_HUMAN otherwise) and must carry the fingerprint of the
--     value the reviewer was SHOWN (INTEL_REVIEW_FINGERPRINT_REQUIRED), which must
--     still be the attribute's current value (INTEL_REVIEW_VALUE_CHANGED, 55000) —
--     so the value approved is the value reviewed. A rejection / edit request is
--     stamped with the current fingerprint by the database. The attribute must be
--     a required one.
--   * intelligence_attribute_reviews AFTER INSERT/UPDATE/DELETE: an 'approved'
--     profile whose contract no longer holds is moved to 'needs_revision' (a
--     rejection) or 'under_review'.
-- Functions:
--   * review_intelligence refuses 'approved' (INTEL_APPROVAL_REQUIRES_REVIEW);
--     draft / under_review / needs_revision are unchanged.
--   * review_attribute gains a trailing p_reviewed_fingerprint (default null), so
--     the 091 function is dropped and recreated with its grant restated. It
--     refuses an unknown attribute, an unknown exercise, and an 'approved' review
--     that carries a value_override: nothing applies overrides to the profile, so
--     approving one would approve a value the profile does not hold.
--   * finalize_intelligence raises INTEL_EMPTY_ATTRIBUTES for an empty map;
--     otherwise any rejected / needs_edit -> 'needs_revision', any missing or
--     stale review -> 'under_review', else 'approved'.
--   * attribute_review_state_engine reports all eight groups, each with its
--     current `value` and `fingerprint` — before 187 the review screen never
--     showed the reviewer the value at all; 'auto' is gone (it
--     told reviewers a model-confident attribute needed no review). New value
--     'stale' = approved, but the value changed since. confidence stays an int
--     (0 when the model gave none) because the review screen sorts on it.
--   * intelligence_review_queue_engine's low_conf_count now counts the required
--     attributes still lacking a current human approval (column name kept).
--
-- EXISTING DATA: any row 'approved' today that does not meet the contract is set
-- to 'under_review' at the end of this migration (count raised as a NOTICE). QA
-- had 0 exercise_intelligence rows on 2026-10-25 (read-only count, runbook §3);
-- production is unverifiable (REL-21). Existing review rows have no fingerprint,
-- so every one of them must be re-recorded before it counts.
--
-- NOT IN SCOPE, deliberately: clinical sign-off. Every attribute — joint_stress
-- and contraindications included — is approvable by a content editor (admin /
-- content_manager), which is all the existing role model supports. The project
-- names no clinical owner (MASTER_PRODUCT_DECISIONS §D) and migration 142 records
-- that no further role may be created (§19.3), so a clinical reviewer cannot be
-- represented without an owner decision. An approval here is a CONTENT review,
-- not a clinical one;
-- injury handling (decision C restricts the first walkthrough to a client with no
-- injuries — this migration does not make injury data safe); the engine gate
-- that consumes 'approved' (migration 188); rank_exercises.
--
-- Authorization and posture: every redefined function keeps its signature (except
-- review_attribute, above) and its is_content_editor() / require_content_editor() guard; every function below
-- pins search_path; helpers, trigger functions and *_engine functions are revoked
-- from PUBLIC, anon and authenticated; the three public RPCs keep EXECUTE for
-- authenticated only (restated, as 184 does).

BEGIN;

ALTER TABLE public.intelligence_attribute_reviews
  ADD COLUMN IF NOT EXISTS reviewed_fingerprint text;

COMMENT ON COLUMN public.intelligence_attribute_reviews.reviewed_fingerprint IS
  'md5 of the attribute group''s value when this review was recorded, stamped by '
  'the database (migration 187). A review counts only while it matches.';

-- ── helpers ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._intel_required_attributes()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT ARRAY['programming_goals', 'fatigue', 'joint_stress', 'contraindications',
               'rep_ranges', 'biomechanics', 'loading', 'coaching']::text[];
$$;

CREATE OR REPLACE FUNCTION public._intel_attribute_value(ei public.exercise_intelligence, p_attribute text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE p_attribute
    WHEN 'programming_goals' THEN jsonb_build_object(
      'goal_strength', ei.goal_strength, 'goal_hypertrophy', ei.goal_hypertrophy,
      'goal_power', ei.goal_power, 'goal_endurance', ei.goal_endurance,
      'goal_fat_loss', ei.goal_fat_loss, 'beginner', ei.beginner,
      'intermediate', ei.intermediate, 'advanced', ei.advanced,
      'min_experience', ei.min_experience, 'energy_systems', to_jsonb(ei.energy_systems),
      'profile_goals', ei.profile->'goals', 'profile_programming', ei.profile->'programming')
    WHEN 'fatigue' THEN jsonb_build_object(
      'local_fatigue', ei.local_fatigue, 'systemic_fatigue', ei.systemic_fatigue,
      'recovery_cost', ei.recovery_cost, 'profile_fatigue', ei.profile->'fatigue',
      'profile_fatigue_extra', ei.profile->'fatigue_extra')
    WHEN 'joint_stress' THEN jsonb_build_object('joint_stress', ei.joint_stress)
    WHEN 'contraindications' THEN jsonb_build_object('contraindications', to_jsonb(ei.contraindications))
    WHEN 'rep_ranges' THEN jsonb_build_object(
      'rep_ranges', ei.rep_ranges, 'frequency_per_week', ei.frequency_per_week)
    WHEN 'biomechanics' THEN jsonb_build_object(
      'technical_complexity', ei.technical_complexity, 'coordination', ei.coordination,
      'balance', ei.balance, 'mobility_requirement', ei.mobility_requirement,
      'profile_skill', ei.profile->'skill', 'profile_biomechanics', ei.profile->'biomechanics')
    WHEN 'loading' THEN jsonb_build_object('profile_loading', ei.profile->'loading')
    WHEN 'coaching' THEN jsonb_build_object('profile_coaching', ei.profile->'coaching')
  END;
$$;

CREATE OR REPLACE FUNCTION public._intel_attribute_fingerprint(ei public.exercise_intelligence, p_attribute text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT md5(public._intel_attribute_value(ei, p_attribute)::text);
$$;

-- {empty_attribute_map, missing[], rejected[], stale[]} for one profile row.
CREATE OR REPLACE FUNCTION public._intel_approval_gaps(ei public.exercise_intelligence)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'empty_attribute_map',
      coalesce(jsonb_typeof(ei.attribute_confidence), 'null') <> 'object'
      OR ei.attribute_confidence = '{}'::jsonb,
    'missing',  coalesce(jsonb_agg(a ORDER BY a) FILTER (
                  WHERE r.exercise_id IS NULL OR r.status NOT IN ('approved', 'rejected', 'needs_edit')), '[]'::jsonb),
    'rejected', coalesce(jsonb_agg(a ORDER BY a) FILTER (
                  WHERE r.status IN ('rejected', 'needs_edit')), '[]'::jsonb),
    'stale',    coalesce(jsonb_agg(a ORDER BY a) FILTER (
                  WHERE r.status = 'approved'
                    AND (r.reviewed_by IS NULL
                         OR r.reviewed_fingerprint IS DISTINCT FROM public._intel_attribute_fingerprint(ei, a))), '[]'::jsonb))
  FROM unnest(public._intel_required_attributes()) AS a
  LEFT JOIN public.intelligence_attribute_reviews r
    ON r.exercise_id = ei.exercise_id AND r.attribute = a;
$$;

CREATE OR REPLACE FUNCTION public._intel_approval_holds(p_gaps jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT NOT coalesce((p_gaps->>'empty_attribute_map')::boolean, true)
     AND jsonb_array_length(coalesce(p_gaps->'missing', '[]'::jsonb)) = 0
     AND jsonb_array_length(coalesce(p_gaps->'rejected', '[]'::jsonb)) = 0
     AND jsonb_array_length(coalesce(p_gaps->'stale', '[]'::jsonb)) = 0;
$$;

-- ── trigger: exercise_intelligence ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._intel_enforce_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  g jsonb;
BEGIN
  IF NEW.status IS DISTINCT FROM 'approved' THEN
    RETURN NEW;
  END IF;
  g := public._intel_approval_gaps(NEW);
  IF public._intel_approval_holds(g) THEN
    RETURN NEW;
  END IF;
  -- Already approved and an update broke the contract: withdraw, do not refuse
  -- the edit itself.
  IF TG_OP = 'UPDATE' AND OLD.status = 'approved' THEN
    NEW.status := 'under_review';
    RAISE NOTICE 'INTEL_APPROVAL_WITHDRAWN: exercise % moved to under_review — %', NEW.exercise_id, g;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'INTEL_APPROVAL_REFUSED: exercise % cannot become approved without a current human '
    'approval of every required attribute and a non-empty attribute map. Gaps: %. Nothing was written.',
    NEW.exercise_id, g
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS intel_enforce_approval ON public.exercise_intelligence;
CREATE TRIGGER intel_enforce_approval
  BEFORE INSERT OR UPDATE ON public.exercise_intelligence
  FOR EACH ROW EXECUTE FUNCTION public._intel_enforce_approval();

-- ── triggers: intelligence_attribute_reviews ───────────────────────────────
CREATE OR REPLACE FUNCTION public._intel_review_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ei public.exercise_intelligence;
BEGIN
  IF NOT (NEW.attribute = ANY (public._intel_required_attributes())) THEN
    RAISE EXCEPTION 'INTEL_UNKNOWN_ATTRIBUTE: "%" is not a reviewable attribute (expected one of %)',
      NEW.attribute, public._intel_required_attributes()
      USING ERRCODE = '22023';
  END IF;
  SELECT * INTO ei FROM public.exercise_intelligence WHERE exercise_id = NEW.exercise_id;
  IF NEW.status = 'approved' THEN
    IF ei.exercise_id IS NULL THEN
      RAISE EXCEPTION 'INTEL_NOT_FOUND: exercise % has no intelligence profile to approve', NEW.exercise_id
        USING ERRCODE = '22023';
    END IF;
    IF auth.uid() IS NULL OR NOT public.is_content_editor() THEN
      RAISE EXCEPTION 'INTEL_REVIEW_NOT_HUMAN: an attribute approval must be recorded by a signed-in '
        'content editor in their own name'
        USING ERRCODE = '42501';
    END IF;
    NEW.reviewed_by := auth.uid();
    -- The approval must name the value the reviewer was SHOWN (the fingerprint
    -- attribute_review_state returned), and that value must still be current.
    -- Otherwise an edit landing between "reviewer opens it" and "reviewer approves"
    -- would be approved unseen.
    IF NEW.reviewed_fingerprint IS NULL THEN
      RAISE EXCEPTION 'INTEL_REVIEW_FINGERPRINT_REQUIRED: an approval of "%" must carry the fingerprint '
        'of the value reviewed (attribute_review_state returns it)', NEW.attribute
        USING ERRCODE = '22023';
    END IF;
    IF NEW.reviewed_fingerprint IS DISTINCT FROM public._intel_attribute_fingerprint(ei, NEW.attribute) THEN
      RAISE EXCEPTION 'INTEL_REVIEW_VALUE_CHANGED: "%" of exercise % changed after it was shown for review. '
        'Nothing was approved; reload it and review the current value.', NEW.attribute, NEW.exercise_id
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;
  -- Rejections and edit requests record the value they were made against.
  NEW.reviewed_fingerprint := CASE WHEN ei.exercise_id IS NULL THEN NULL
                                   ELSE public._intel_attribute_fingerprint(ei, NEW.attribute) END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS intel_review_stamp ON public.intelligence_attribute_reviews;
CREATE TRIGGER intel_review_stamp
  BEFORE INSERT OR UPDATE ON public.intelligence_attribute_reviews
  FOR EACH ROW EXECUTE FUNCTION public._intel_review_stamp();

CREATE OR REPLACE FUNCTION public._intel_review_invalidate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.exercise_id ELSE NEW.exercise_id END;
  ei   public.exercise_intelligence;
  g    jsonb;
BEGIN
  SELECT * INTO ei FROM public.exercise_intelligence WHERE exercise_id = v_id;
  IF ei.status = 'approved' THEN
    g := public._intel_approval_gaps(ei);
    IF NOT public._intel_approval_holds(g) THEN
      UPDATE public.exercise_intelligence
         SET status = CASE WHEN jsonb_array_length(g->'rejected') > 0 THEN 'needs_revision'
                           ELSE 'under_review' END,
             updated_at = now()
       WHERE exercise_id = v_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS intel_review_invalidate ON public.intelligence_attribute_reviews;
CREATE TRIGGER intel_review_invalidate
  AFTER INSERT OR UPDATE OR DELETE ON public.intelligence_attribute_reviews
  FOR EACH ROW EXECUTE FUNCTION public._intel_review_invalidate();

-- ── public review functions (signatures unchanged) ─────────────────────────
CREATE OR REPLACE FUNCTION public.review_intelligence(p_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  if p_status = 'approved' then
    raise exception 'INTEL_APPROVAL_REQUIRES_REVIEW: a profile is approved only by finalize_intelligence, '
      'after every required attribute has a current human approval'
      using errcode = '42501';
  end if;
  if p_status not in ('under_review','needs_revision','draft') then
    raise exception 'invalid status %', p_status;
  end if;
  update exercise_intelligence set
    status = p_status,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    updated_at = now()
  where exercise_id = p_id;
end;
$$;

-- A new trailing parameter changes the signature, so the 091 function is dropped
-- and recreated (its grant is restated below). Existing callers that pass named
-- p_exercise_id / p_attribute / p_status / p_note still resolve; an APPROVAL
-- without p_reviewed_fingerprint is now refused.
DROP FUNCTION IF EXISTS public.review_attribute(uuid, text, text, jsonb, text);
CREATE FUNCTION public.review_attribute(
  p_exercise_id uuid, p_attribute text, p_status text,
  p_value jsonb default null, p_note text default null,
  p_reviewed_fingerprint text default null)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  if p_status not in ('approved','rejected','needs_edit') then
    raise exception 'invalid status %', p_status;
  end if;
  if not (p_attribute = any (public._intel_required_attributes())) then
    raise exception 'INTEL_UNKNOWN_ATTRIBUTE: "%" is not a reviewable attribute (expected one of %)',
      p_attribute, public._intel_required_attributes()
      using errcode = '22023';
  end if;
  if not exists (select 1 from exercise_intelligence where exercise_id = p_exercise_id) then
    raise exception 'INTEL_NOT_FOUND: exercise % has no intelligence profile', p_exercise_id
      using errcode = '22023';
  end if;
  if p_status = 'approved' and p_value is not null then
    raise exception 'INTEL_OVERRIDE_NOT_APPLIED: an approval cannot carry a corrected value — nothing '
      'applies overrides to the profile. Correct the profile, then approve what it holds.'
      using errcode = '22023';
  end if;
  -- intel_review_stamp sets reviewed_by, and for an approval checks that
  -- p_reviewed_fingerprint is the attribute's CURRENT fingerprint.
  insert into intelligence_attribute_reviews(
    exercise_id, attribute, status, value_override, note, reviewed_by, reviewed_at, reviewed_fingerprint)
  values (p_exercise_id, p_attribute, p_status, p_value, p_note, auth.uid(), now(), p_reviewed_fingerprint)
  on conflict (exercise_id, attribute) do update set
    status = excluded.status, value_override = excluded.value_override,
    note = excluded.note, reviewed_by = auth.uid(), reviewed_at = now(),
    reviewed_fingerprint = excluded.reviewed_fingerprint;
end;
$$;

CREATE OR REPLACE FUNCTION public.finalize_intelligence(p_exercise_id uuid, p_threshold int default 90)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
declare
  ei public.exercise_intelligence;
  g jsonb;
  v_status text;
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  -- p_threshold is accepted for compatibility and ignored: model confidence never approves.
  select * into ei from exercise_intelligence where exercise_id = p_exercise_id for update;
  if not found then
    raise exception 'INTEL_NOT_FOUND: exercise % has no intelligence profile', p_exercise_id
      using errcode = '22023';
  end if;
  g := public._intel_approval_gaps(ei);
  if (g->>'empty_attribute_map')::boolean then
    raise exception 'INTEL_EMPTY_ATTRIBUTES: exercise % has no attribute map, so there is nothing a '
      'reviewer has certified. It was not approved.', p_exercise_id
      using errcode = '22023';
  end if;
  v_status := case when jsonb_array_length(g->'rejected') > 0 then 'needs_revision'
                   when public._intel_approval_holds(g) then 'approved'
                   else 'under_review' end;
  update exercise_intelligence set status = v_status,
    reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where exercise_id = p_exercise_id;
  return v_status;
end;
$$;

-- ── read-side engines behind 117's require_content_editor() wrappers ───────
CREATE OR REPLACE FUNCTION public.attribute_review_state_engine(p_exercise_id uuid, p_threshold integer DEFAULT 90)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  select coalesce(jsonb_object_agg(a, jsonb_build_object(
      -- What the reviewer is approving, and the token an approval must send back.
      'value', public._intel_attribute_value(ei, a),
      'fingerprint', public._intel_attribute_fingerprint(ei, a),
      'confidence', case when (ei.attribute_confidence->>a) ~ '^-?[0-9]+(\.[0-9]+)?$'
                         then round((ei.attribute_confidence->>a)::numeric)::int else 0 end,
      'review_status', case
          when r.exercise_id is null then 'pending'
          when r.status = 'approved'
               and (r.reviewed_by is null
                    or r.reviewed_fingerprint is distinct from public._intel_attribute_fingerprint(ei, a))
            then 'stale'
          else r.status end,
      'note', r.note)), '{}'::jsonb)
  from exercise_intelligence ei
  cross join unnest(public._intel_required_attributes()) as a
  left join intelligence_attribute_reviews r
    on r.exercise_id = ei.exercise_id and r.attribute = a
  where ei.exercise_id = p_exercise_id;
$$;

CREATE OR REPLACE FUNCTION public.intelligence_review_queue_engine(p_limit integer DEFAULT 50)
RETURNS TABLE(exercise_id uuid, name text, status text, confidence integer, low_conf_count integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  -- low_conf_count (name kept for callers) = required attributes still lacking a
  -- current human approval.
  select ei.exercise_id, e.name, ei.status, ei.confidence,
    (select count(*)::int from unnest(public._intel_required_attributes()) a
      where not exists (
        select 1 from intelligence_attribute_reviews r
         where r.exercise_id = ei.exercise_id and r.attribute = a and r.status = 'approved'
           and r.reviewed_by is not null
           and r.reviewed_fingerprint = public._intel_attribute_fingerprint(ei, a)))
  from exercise_intelligence ei
  join custom_exercises e on e.id = ei.exercise_id
  where ei.status in ('ai_generated','under_review')
  order by ei.confidence asc nulls first
  limit greatest(1, least(p_limit, 100));
$$;

-- ── privileges ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._intel_required_attributes()                                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_attribute_value(public.exercise_intelligence, text)       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_attribute_fingerprint(public.exercise_intelligence, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_approval_gaps(public.exercise_intelligence)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_approval_holds(jsonb)                                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_enforce_approval()                                       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_review_stamp()                                           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._intel_review_invalidate()                                      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.attribute_review_state_engine(uuid, integer)                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.intelligence_review_queue_engine(integer)                       FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.review_intelligence(uuid, text)                     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_attribute(uuid, text, text, jsonb, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_intelligence(uuid, integer)                FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_intelligence(uuid, text)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_attribute(uuid, text, text, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_intelligence(uuid, integer)             TO authenticated;

COMMENT ON FUNCTION public.finalize_intelligence(uuid, integer) IS
  'Derives an intelligence profile''s status from its attribute reviews (187): '
  'approved only when every required attribute has a current human approval and '
  'the attribute map is non-empty. Model confidence never approves; p_threshold is ignored.';
COMMENT ON FUNCTION public.review_intelligence(uuid, text) IS
  'Moves a profile to draft / under_review / needs_revision. Refuses approved (187): '
  'approval comes only from finalize_intelligence.';

-- ── existing approvals that do not meet the contract ───────────────────────
DO $$
DECLARE n int;
BEGIN
  UPDATE public.exercise_intelligence ei
     SET status = 'under_review', updated_at = now()
   WHERE ei.status = 'approved'
     AND NOT public._intel_approval_holds(public._intel_approval_gaps(ei));
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '187: % approved intelligence profile(s) did not meet the human-review contract and are now under_review', n;
END $$;

COMMIT;
