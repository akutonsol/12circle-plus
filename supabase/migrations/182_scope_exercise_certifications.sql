-- ═══════════════════════════════════════════════════════════════════════════
-- DRAFT — NOT APPLIED, NOT IN supabase/migrations/. Review artifact only.
-- Proposed as migration 182. QAX-SEC-06, certification half. Option A.
--
-- WHAT IS WRONG TODAY (reproduced on LOCAL-REPLAY 000-131, PostgreSQL 18.6):
--   FAIL|QAX-SEC-06.cert-view|non-owner sees other coach's private draft
--        via exercise_certifications: 1
--   FAIL|QAX-SEC-06.cert-rpc |exercise_certification(other owner's private
--        draft) returned: {"id": "9999...", "name": "qax ...
--
-- `exercise_certifications` (086:14) declares no security_invoker, so it runs as
-- its OWNER and `custom_exercises` RLS (005:45-62, 050:10-17) does not apply.
-- It also reads `custom_exercises` DIRECTLY (086:33) -- NOT through the
-- `exercises` view -- so the existing QAX-SEC-06 fix for `exercises` cannot
-- close this, and this migration does not touch `exercises`.
--
-- WHY THE PREDICATE LIVES IN THE VIEW BODY, NOT IN A GRANT:
-- 112:35-51 sweeps EVERY view in public -- `REVOKE ALL ... FROM PUBLIC, anon,
-- authenticated` then `GRANT SELECT ... TO authenticated`. Any fix that depends
-- on withholding that grant is silently undone the next time such a sweep runs.
-- A predicate inside the body is unaffected by re-granting SELECT, so this is
-- sweep-resistant by construction. For the same reason it does NOT split the
-- view into a scoped wrapper over an `_unscoped` twin: a sweep would grant
-- SELECT on the twin and re-open the path under a second name.
--
-- WHY A VIEW-ONLY FIX IS NOT SUFFICIENT: `exercise_certification(p_id)`
-- (084:76-79) is SECURITY DEFINER, is allowlisted to `authenticated` by
-- 116:440-471, takes the id as a PARAMETER and self-authorizes nothing. It is
-- live in the app at custom_exercise_service.dart:366. Verified against the
-- replay catalog: 117 wrapped its siblings but left this one a bare definer
-- select. It is closed below, in the same change.
--
-- `certification_summary()` is deliberately NOT redefined. 117:328-337 already
-- guards it with require_content_editor() and delegates to
-- certification_summary_engine(), which reads this view. Because the predicate
-- admits is_content_editor(), an entitled caller still sees every row and the
-- library-wide total is unchanged (observed 624 = 624 under simulation).
-- Replacing that wrapper would REGRESS 117's guard.
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
