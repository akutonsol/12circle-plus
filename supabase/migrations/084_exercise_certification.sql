-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 084 — Exercise Certification Matrix
--
-- The single source of truth for "can module X safely use this exercise?".
-- Instead of every system re-checking individual fields (has instructions? has
-- a video? reviewed?), each exercise exposes a computed certification — derived
-- from content completeness, media, AI confidence, human review, and publish
-- state. Workout Builder / AI Coach / Program Generator / Marketplace / Self- &
-- Coach-Guided all query this view instead of guessing.
--
-- Depends on 083 (content_status, ai_confidence, human_reviewed). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace view public.exercise_certifications as
with base as (
  select
    id, name, content_status,
    coalesce(ai_confidence, 0)     as ai_confidence,
    coalesce(human_reviewed, false) as human_reviewed,
    (content_status in ('approved', 'published')) as approved,
    -- Type-agnostic "field is populated" checks (arrays or jsonb or text).
    (coalesce(instructions::text, '')          not in ('', '[]', '{}', 'null')) as has_instructions,
    (coalesce(coaching_cues::text, '')         not in ('', '[]', '{}', 'null')) as has_cues,
    (coalesce(common_mistakes::text, '')       not in ('', '[]', '{}', 'null')) as has_mistakes,
    (coalesce(alternatives::text, '')          not in ('', '[]', '{}', 'null')) as has_alts,
    (coalesce(beginner_modification, '') <> '')  as has_beginner,
    (coalesce(advanced_progression, '') <> '')   as has_advanced,
    (coalesce(image_url, '') <> '')              as has_image,
    (coalesce(video_variants::text, '') not in ('', '[]', '{}', 'null')
       or coalesce(video_assets::text, '') not in ('', '[]', '{}', 'null')) as has_video,
    (coalesce(muscle_group, '') <> '')           as has_muscle,
    (coalesce(equipment, '') <> ''
       or coalesce(equipment_required::text, '') not in ('', '[]', '{}', 'null')) as has_equipment
  from custom_exercises
),
certs as (
  select *,
    (content_status = 'published')                                              as exercise_library,
    (approved and has_instructions and has_muscle and has_equipment)            as workout_builder,
    (approved and has_instructions and has_muscle and has_equipment and has_alts) as program_generator,
    (approved and has_instructions and has_cues and (has_video or has_image))   as self_guided,
    (approved and has_instructions)                                             as coach_guided,
    (approved and has_instructions and has_cues and has_mistakes and has_alts
       and has_muscle and has_equipment and (human_reviewed or ai_confidence >= 90)) as ai_coach,
    (approved and has_instructions and has_image)                              as marketplace,
    (approved and has_instructions and has_cues and has_mistakes and has_image
       and has_video and human_reviewed)                                        as premium_content,
    false as voice_coaching,   -- voice scripts not modeled yet
    false as wearables         -- metric integration not modeled yet
  from base
)
select
  id, name, content_status, ai_confidence, human_reviewed,
  exercise_library, workout_builder, program_generator, self_guided, coach_guided,
  ai_coach, marketplace, premium_content, voice_coaching, wearables,
  has_instructions, has_cues, has_mistakes, has_alts, has_beginner, has_advanced,
  has_image, has_video, has_muscle, has_equipment,
  -- Weighted overall (0..100). Voice/wearables carry low weight so a fully
  -- content-complete exercise still scores ~90 before those modules exist.
    (case when exercise_library  then 10 else 0 end)
  + (case when workout_builder   then 15 else 0 end)
  + (case when program_generator then 12 else 0 end)
  + (case when self_guided       then 12 else 0 end)
  + (case when coach_guided      then 10 else 0 end)
  + (case when ai_coach          then 15 else 0 end)
  + (case when marketplace       then  8 else 0 end)
  + (case when premium_content   then  8 else 0 end)
  + (case when voice_coaching    then  5 else 0 end)
  + (case when wearables         then  5 else 0 end) as overall_pct
from certs;

grant select on public.exercise_certifications to authenticated, anon;

-- Single-exercise certification object — the API a module calls to ask
-- "can I use this exercise?" e.g. select (exercise_certification(id))->>'ai_coach'.
create or replace function public.exercise_certification(p_id uuid)
returns jsonb language sql stable security definer as $$
  select to_jsonb(c) from public.exercise_certifications c where c.id = p_id;
$$;
grant execute on function public.exercise_certification(uuid) to authenticated;

-- Library-wide certification counts (how many exercises each module can use).
create or replace function public.certification_summary()
returns table(
  total bigint, exercise_library bigint, workout_builder bigint,
  program_generator bigint, self_guided bigint, coach_guided bigint,
  ai_coach bigint, marketplace bigint, premium_content bigint,
  voice_coaching bigint, wearables bigint, avg_overall numeric)
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
    round(avg(overall_pct), 1)
  from public.exercise_certifications;
$$;
grant execute on function public.certification_summary() to authenticated;
