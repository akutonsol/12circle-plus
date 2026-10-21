-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 086 — Certification: Current + Projected
--
-- Replaces the 084 view so each module certification splits into:
--   • current_*  — consumable NOW (passes the approved/published gate)
--   • projected_* — what it WOULD be certified for once approved (content is
--     ready; a human approval flips the gate + sets human_reviewed)
--
-- This powers the motivating review UX: "Current 0% → After approval 92% —
-- approving unlocks AI Coach, Self-Guided, Marketplace, Program Generator."
-- Depends on 084 (and 083). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace view public.exercise_certifications as
with base as (
  select
    id, name, content_status,
    coalesce(ai_confidence, 0)      as ai_confidence,
    coalesce(human_reviewed, false) as human_reviewed,
    (content_status in ('approved', 'published')) as approved,
    (coalesce(instructions::text, '')    not in ('', '[]', '{}', 'null')) as has_instructions,
    (coalesce(coaching_cues::text, '')   not in ('', '[]', '{}', 'null')) as has_cues,
    (coalesce(common_mistakes::text, '') not in ('', '[]', '{}', 'null')) as has_mistakes,
    (coalesce(alternatives::text, '')    not in ('', '[]', '{}', 'null')) as has_alts,
    (coalesce(beginner_modification, '') <> '') as has_beginner,
    (coalesce(advanced_progression, '') <> '')  as has_advanced,
    (coalesce(image_url, '') <> '')             as has_image,
    (coalesce(video_variants::text, '') not in ('', '[]', '{}', 'null')
       or coalesce(video_assets::text, '') not in ('', '[]', '{}', 'null')) as has_video,
    (coalesce(muscle_group, '') <> '')          as has_muscle,
    (coalesce(equipment, '') <> ''
       or coalesce(equipment_required::text, '') not in ('', '[]', '{}', 'null')) as has_equipment
  from custom_exercises
),
reqs as (
  select *,
    -- Content requirements per module (independent of the approval gate).
    true                                                              as r_library,
    (has_instructions and has_muscle and has_equipment)              as r_workout_builder,
    (has_instructions and has_muscle and has_equipment and has_alts) as r_program_generator,
    (has_instructions and has_cues and (has_video or has_image))     as r_self_guided,
    (has_instructions)                                               as r_coach_guided,
    (has_instructions and has_cues and has_mistakes and has_alts and has_muscle and has_equipment) as r_ai_content,
    (has_instructions and has_image)                                 as r_marketplace,
    (has_instructions and has_cues and has_mistakes and has_image and has_video) as r_premium_content
  from base
)
select
  id, name, content_status, ai_confidence, human_reviewed,
  -- ── CURRENT (consumable now) — keep 084 column names/order/types ──
  (content_status = 'published')                                     as exercise_library,
  (approved and r_workout_builder)                                   as workout_builder,
  (approved and r_program_generator)                                 as program_generator,
  (approved and r_self_guided)                                       as self_guided,
  (approved and r_coach_guided)                                      as coach_guided,
  (approved and r_ai_content and (human_reviewed or ai_confidence >= 90)) as ai_coach,
  (approved and r_marketplace)                                       as marketplace,
  (approved and r_premium_content and human_reviewed)               as premium_content,
  false as voice_coaching,
  false as wearables,
  has_instructions, has_cues, has_mistakes, has_alts, has_beginner, has_advanced,
  has_image, has_video, has_muscle, has_equipment,
    (case when content_status = 'published'                           then 10 else 0 end)
  + (case when approved and r_workout_builder                         then 15 else 0 end)
  + (case when approved and r_program_generator                       then 12 else 0 end)
  + (case when approved and r_self_guided                             then 12 else 0 end)
  + (case when approved and r_coach_guided                            then 10 else 0 end)
  + (case when approved and r_ai_content and (human_reviewed or ai_confidence >= 90) then 15 else 0 end)
  + (case when approved and r_marketplace                             then  8 else 0 end)
  + (case when approved and r_premium_content and human_reviewed      then  8 else 0 end) as overall_pct,
  -- ── PROJECTED (after approval: gate passes, human_reviewed becomes true) ──
  true                        as proj_exercise_library,
  r_workout_builder           as proj_workout_builder,
  r_program_generator         as proj_program_generator,
  r_self_guided               as proj_self_guided,
  r_coach_guided              as proj_coach_guided,
  r_ai_content                as proj_ai_coach,       -- reviewed assumed on approval
  r_marketplace               as proj_marketplace,
  r_premium_content           as proj_premium_content,-- reviewed assumed on approval
  false as proj_voice_coaching,
  false as proj_wearables,
    10
  + (case when r_workout_builder   then 15 else 0 end)
  + (case when r_program_generator then 12 else 0 end)
  + (case when r_self_guided       then 12 else 0 end)
  + (case when r_coach_guided      then 10 else 0 end)
  + (case when r_ai_content        then 15 else 0 end)
  + (case when r_marketplace       then  8 else 0 end)
  + (case when r_premium_content   then  8 else 0 end) as projected_pct
from reqs;

grant select on public.exercise_certifications to authenticated, anon;

-- Summary gains projected averages (current counts unchanged).
-- STAGE B.3 (B2-10): this supersedes migration 084's certification_summary()
-- by ADDING projected_pct to the returned table. CREATE OR REPLACE FUNCTION
-- cannot change a return type, so the old signature has to be dropped first.
-- This never surfaced before because 084 itself never applied (B2-2).
drop function if exists public.certification_summary();
create or replace function public.certification_summary()
returns table(
  total bigint, exercise_library bigint, workout_builder bigint,
  program_generator bigint, self_guided bigint, coach_guided bigint,
  ai_coach bigint, marketplace bigint, premium_content bigint,
  voice_coaching bigint, wearables bigint, avg_overall numeric, avg_projected numeric)
language sql stable security definer as $$
  select
    count(*),
    count(*) filter (where exercise_library),
    count(*) filter (where workout_builder),
    count(*) filter (where program_generator),
    count(*) filter (where self_guided),
    count(*) filter (where coach_guided),
    count(*) filter (where ai_coach),
    count(*) filter (where marketplace),
    count(*) filter (where premium_content),
    count(*) filter (where voice_coaching),
    count(*) filter (where wearables),
    round(avg(overall_pct), 1),
    round(avg(projected_pct), 1)
  from public.exercise_certifications;
$$;
grant execute on function public.certification_summary() to authenticated;
