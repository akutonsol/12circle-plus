-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 083 — Exercise Content Pipeline (editorial lifecycle)
--
-- Turns AI enrichment from "generate → live" into an editorial workflow:
--   draft → ai_generated → under_review → (needs_revision) → approved → published → archived
--
-- This `content_status` is a SEPARATE axis from the existing `status`
-- (app publish state, all 'published') and `submission_status` (coach-
-- contribution moderation). AI content lands as 'under_review' (or auto-
-- 'approved' at high confidence) and only a human editor publishes it.
-- Idempotent — safe to run more than once.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ── STAGE B.3 CORRECTION (B2-2): relation retargeted to custom_exercises ────
-- This file was written against `exercises`, but `exercises` is a VIEW over
-- custom_exercises (created by migration 058 line 23). You cannot ADD COLUMN,
-- ADD CONSTRAINT, CREATE INDEX or FOREIGN-KEY-reference a view, so every
-- statement below used to fail and this migration -- along with 084, 086, 087,
-- 090, 091, 097 and 099 -- has never applied in any environment. Confirmed
-- against the QA schema: `exercises` is a view there and every object these
-- migrations create is absent.
--
-- custom_exercises is the authoritative table (it is what the app writes, what
-- migrations 063-073 seed, and what 058 declares the view to alias), so the
-- relation names here are corrected to custom_exercises and the `exercises`
-- view is refreshed below so client reads still see the new columns.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Lifecycle columns on the global library ─────────────────────────────────
alter table custom_exercises add column if not exists content_status  text not null default 'draft';
alter table custom_exercises add column if not exists ai_confidence    int;      -- 0..100, last AI enrichment
alter table custom_exercises add column if not exists human_reviewed   boolean not null default false;
alter table custom_exercises add column if not exists content_version  int not null default 1;
alter table custom_exercises add column if not exists last_reviewed_at timestamptz;
alter table custom_exercises add column if not exists last_reviewed_by uuid references user_profiles(id);

-- Seed: rows that already have instructions are effectively published content;
-- everything else is an empty draft awaiting enrichment. (Type-agnostic guard so
-- it works whether `instructions` is text[] or jsonb.)
update custom_exercises set content_status = 'published'
  where content_status = 'draft'
    and coalesce(instructions::text, '') not in ('', '[]', '{}', 'null');

alter table custom_exercises drop constraint if exists exercises_content_status_chk;
alter table custom_exercises add constraint exercises_content_status_chk
  check (content_status in
    ('draft','ai_generated','under_review','needs_revision','approved','published','archived'));

create index if not exists idx_exercises_content_status on custom_exercises(content_status);

-- ── Refresh the client-facing compatibility view ────────────────────────────
-- `exercises` is re-created so the six lifecycle columns above are visible
-- through it. custom_exercise_service.reviewQueue() selects content_status,
-- ai_confidence and content_version from `exercises`, so without this the
-- editorial queue silently returns nothing.
--
-- Separately: migration 058 built the view with `select *`, which Postgres
-- expands to a fixed column list at creation time. Migration 060 then added
-- breathing, ai_exercise_tips and coaching_cues_by_level to custom_exercises
-- and the view never picked them up -- verified missing from the QA view today.
-- Re-expanding `select *` here recovers those three as well.
create or replace view public.exercises as select * from custom_exercises;

-- ── Version history (roll back any edit) ────────────────────────────────────
create table if not exists exercise_content_versions (
  id            uuid primary key default gen_random_uuid(),
  exercise_id   uuid not null references custom_exercises(id) on delete cascade,
  version       int  not null,
  content       jsonb not null,            -- snapshot of the content fields
  source        text not null,             -- 'ai_generated' | 'human_edit' | 'review_*' | 'import'
  ai_confidence int,
  created_by    uuid references user_profiles(id),
  created_at    timestamptz default now()
);
create index if not exists idx_ecv_exercise on exercise_content_versions(exercise_id, version desc);

alter table exercise_content_versions enable row level security;
drop policy if exists "content versions read" on exercise_content_versions;
create policy "content versions read" on exercise_content_versions
  for select to authenticated using (
    exists (select 1 from user_profiles
            where id = auth.uid() and role in ('admin','content_manager','coach')));

-- ── Helpers ─────────────────────────────────────────────────────────────────
create or replace function public.is_content_editor()
returns boolean language sql stable security definer as $$
  select exists (select 1 from user_profiles
                 where id = auth.uid() and role in ('admin','content_manager'));
$$;
grant execute on function public.is_content_editor() to authenticated;

-- Snapshot the current content of an exercise as the next version.
create or replace function public.snapshot_exercise_content(
  p_id uuid, p_source text, p_confidence int default null, p_actor uuid default null)
returns int language plpgsql security definer as $$
declare v_ex exercises%rowtype; v_next int;
begin
  select * into v_ex from custom_exercises where id = p_id;
  if not found then raise exception 'exercise % not found', p_id; end if;
  select coalesce(max(version), 0) + 1 into v_next
    from exercise_content_versions where exercise_id = p_id;
  insert into exercise_content_versions
    (exercise_id, version, content, source, ai_confidence, created_by)
  values (p_id, v_next,
    jsonb_build_object(
      'instructions', v_ex.instructions, 'coaching_cues', v_ex.coaching_cues,
      'common_mistakes', v_ex.common_mistakes, 'beginner_modification', v_ex.beginner_modification,
      'advanced_progression', v_ex.advanced_progression, 'alternatives', v_ex.alternatives),
    p_source, coalesce(p_confidence, v_ex.ai_confidence), coalesce(p_actor, auth.uid()));
  update custom_exercises set content_version = v_next where id = p_id;
  return v_next;
end;
$$;
grant execute on function public.snapshot_exercise_content(uuid, text, int, uuid) to authenticated;

-- Editor moves an exercise through the lifecycle (snapshots + updates status).
create or replace function public.review_exercise_content(p_id uuid, p_status text)
returns void language plpgsql security definer as $$
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  if p_status not in ('under_review','needs_revision','approved','published','archived') then
    raise exception 'invalid target status %', p_status;
  end if;
  perform public.snapshot_exercise_content(p_id, 'review_' || p_status, null, auth.uid());
  update custom_exercises set
    content_status   = p_status,
    human_reviewed   = case when p_status in ('approved','published','needs_revision')
                            then true else human_reviewed end,
    last_reviewed_at = now(),
    last_reviewed_by = auth.uid(),
    -- Publishing content also flips the app-visible publish state.
    status           = case when p_status = 'published' then 'published' else status end
  where id = p_id;
end;
$$;
grant execute on function public.review_exercise_content(uuid, text) to authenticated;

-- ── Content pipeline analytics (one row of counts) ──────────────────────────
create or replace function public.exercise_content_stats()
returns table(
  total bigint, draft bigint, ai_generated bigint, under_review bigint,
  needs_revision bigint, approved bigint, published bigint, archived bigint,
  human_reviewed bigint, ai_certified bigint)
language sql stable security definer as $$
  select
    count(*),
    count(*) filter (where content_status = 'draft'),
    count(*) filter (where content_status = 'ai_generated'),
    count(*) filter (where content_status = 'under_review'),
    count(*) filter (where content_status = 'needs_revision'),
    count(*) filter (where content_status = 'approved'),
    count(*) filter (where content_status = 'published'),
    count(*) filter (where content_status = 'archived'),
    count(*) filter (where human_reviewed),
    count(*) filter (where content_status in ('approved','published')
                       and human_reviewed and coalesce(ai_confidence,0) >= 90)
  from custom_exercises;
$$;
grant execute on function public.exercise_content_stats() to authenticated;
