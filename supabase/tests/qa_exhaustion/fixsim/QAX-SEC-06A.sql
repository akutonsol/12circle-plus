-- Simulated fix A — PER-OWNER visibility for the certification path.
-- Generated from the SAME operative SQL as the review draft
-- (scratchpad/V5_QAXSEC06_OPTION_A_DRAFT_182.sql) so the simulation and the
-- proposed migration cannot drift apart.
--
-- Single object, no `_unscoped` twin: the predicate lives in the view's base CTE,
-- so a 112-style sweep that re-grants SELECT cannot re-open the path
-- (QAX-SEC-06.cert-sweep probes exactly that). Companion QAX-SEC-06.sql fixes the
-- separate `exercises` view; neither fix substitutes for the other.
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
  -- ── THE AUTHORIZATION LINE. Removing it re-opens QAX-SEC-06 (certification half).
  --    Reuses public.exercise_readable (058:26) rather than restating its rule:
  --    global+approved, or own row, or is_admin(). `or is_content_editor()` keeps
  --    admin/content_manager library-wide, so 117 aggregation is unchanged.
  where public.exercise_readable(id) or public.is_content_editor()
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

-- Restate the posture 112 established, so a rebuild in migration order lands here.
revoke all on public.exercise_certifications from public, anon;
grant select on public.exercise_certifications to authenticated;

-- ── The second path: the definer RPC ────────────────────────────────────────
-- Redundant while the view carries the predicate, and deliberately kept: an
-- operator who later rewrites the view without the WHERE still cannot read a
-- stranger's row through this function.
create or replace function public.exercise_certification(p_id uuid)
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $$
  select to_jsonb(c) from public.exercise_certifications c
   where c.id = p_id
     and (public.exercise_readable(p_id) or public.is_content_editor());
$$;
revoke all on function public.exercise_certification(uuid) from public, anon;
grant execute on function public.exercise_certification(uuid) to authenticated;

comment on view public.exercise_certifications is
  'Certification projection over custom_exercises. Runs security_invoker = off '
  '(owner rights), so its ONLY boundary is the WHERE in its base CTE: '
  'exercise_readable(id) OR is_content_editor(). Do not remove it, and do not '
  'split this view over an unscoped twin -- migration 112 sweeps SELECT onto '
  'every view in public, which would re-open the read path. QAX-SEC-06.';

comment on function public.exercise_certification(uuid) is
  'Single-exercise certification object. SECURITY DEFINER, so it carries its own '
  'predicate as well as reading the scoped view. QAX-SEC-06.';
