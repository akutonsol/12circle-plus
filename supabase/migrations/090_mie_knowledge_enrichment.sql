-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 090 — MIE Phase 2b: Knowledge Enrichment Pipeline
--
-- AI drafts the FULL intelligence profile; humans certify; the engine consumes
-- certified knowledge. Same philosophy as content/edges. The deterministic
-- scoring engine is UNCHANGED — this only improves the quality of its inputs.
--
-- Scoring-critical fields stay typed (score_exercise reads them). The richer
-- profile (biomechanics, loading, coaching metadata, extended goals) + PER-
-- ATTRIBUTE confidence live in jsonb, so reviewers can review only the low-
-- confidence attributes.
--
-- Depends on 087. Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

alter table exercise_intelligence add column if not exists profile              jsonb default '{}';
alter table exercise_intelligence add column if not exists attribute_confidence jsonb default '{}';
alter table exercise_intelligence add column if not exists evidence_source      text;
alter table exercise_intelligence add column if not exists ai_version           text;
alter table exercise_intelligence add column if not exists reviewed_by          uuid references user_profiles(id);
alter table exercise_intelligence add column if not exists reviewed_at          timestamptz;

-- profile jsonb shape (documented, not enforced):
--   programming: {athletic,functional,rehab,general_health,senior,postpartum,youth} 0..10
--   biomechanics: {plane_of_motion, unilateral bool, closed_chain bool, force_vector,
--                  stability_requirement 0..10}
--   loading: {spinal,shoulder,hip,knee,grip,core,cardio} 0..10
--   fatigue_extra: {neurological_demand, technical_fatigue} 0..10
--   coaching: {top_cue, common_errors[], regression_priority, progression_priority,
--              teaching_complexity 0..10, safety_notes, spotter_required bool, common_compensations[]}
-- attribute_confidence jsonb: {joint_stress, fatigue, contraindications, rep_ranges,
--   programming_goals, biomechanics, loading, coaching} → 0..100

-- ── Reviewer moves an intelligence profile through the lifecycle ─────────────
create or replace function public.review_intelligence(p_id uuid, p_status text)
returns void language plpgsql security definer as $$
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  if p_status not in ('under_review','needs_revision','approved','draft') then
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
grant execute on function public.review_intelligence(uuid, text) to authenticated;

-- Attributes still needing human review = those below a confidence threshold.
create or replace function public.intelligence_low_confidence(p_id uuid, p_threshold int default 90)
returns jsonb language sql stable security definer as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from exercise_intelligence ei,
       lateral jsonb_each_text(coalesce(ei.attribute_confidence, '{}'::jsonb)) as a(k, v)
  where ei.exercise_id = p_id and (v)::int < p_threshold;
$$;
grant execute on function public.intelligence_low_confidence(uuid, int) to authenticated;

-- ── Coverage + review-pipeline stats (extends 087) ──────────────────────────
create or replace function public.intelligence_stats()
returns jsonb language sql stable security definer as $$
  select jsonb_build_object(
    'total_exercises', (select count(*) from custom_exercises),
    'profiled',     (select count(*) from exercise_intelligence),
    'ai_generated', (select count(*) from exercise_intelligence where status = 'ai_generated'),
    'under_review', (select count(*) from exercise_intelligence where status = 'under_review'),
    'approved',     (select count(*) from exercise_intelligence where status = 'approved'),
    'draft',        (select count(*) from exercise_intelligence where status = 'draft'),
    'avg_confidence', (select round(avg(confidence),1) from exercise_intelligence),
    -- how many approved profiles the scoring engine can fully trust
    'engine_ready', (select count(*) from exercise_intelligence where status = 'approved'));
$$;
grant execute on function public.intelligence_stats() to authenticated;
