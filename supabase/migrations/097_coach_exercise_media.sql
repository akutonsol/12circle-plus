-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 097 — Layered Exercise Media · Phase 1: Coach Overlay
--
-- Identity feature (deliberate pre-beta exception): the official library is never
-- the final experience — every coach can OVERLAY their own coaching on any
-- exercise. Not replace — override pieces (a focus, a note, their own video).
-- The resolver walks: client → coach → official. Voice is a first-class future
-- slot; text ("Coach Focus Today") is the highest-adoption path and ships now.
--
-- Depends on 025 (coach_client_relationships). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists coach_exercise_media (
  coach_id    uuid not null references user_profiles(id) on delete cascade,
  exercise_id uuid not null references custom_exercises(id) on delete cascade,
  note        text,                    -- free-form coaching note
  focus       text[] default '{}',     -- "Coach Focus Today" bullets
  video_ref   text,                    -- coach's own demo (YouTube id or url)
  voice_url   text,                    -- coach voice note (future: in-app recording)
  updated_at  timestamptz default now(),
  primary key (coach_id, exercise_id)
);
alter table coach_exercise_media enable row level security;

-- Coach manages their own overlays.
drop policy if exists "coach media own rw" on coach_exercise_media;
create policy "coach media own rw" on coach_exercise_media for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());

-- A client may read the overlay of a coach they're actively working with.
drop policy if exists "client reads coach overlay" on coach_exercise_media;
create policy "client reads coach overlay" on coach_exercise_media for select to authenticated
  using (exists (
    select 1 from coach_client_relationships r
    where r.coach_id = coach_exercise_media.coach_id
      and r.client_id = auth.uid() and r.status = 'active'));

-- ── Resolver: the highest-priority coaching overlay for a viewer ────────────
-- Phase 1 resolves the viewer's active coach's overlay (client → coach). Level 3
-- (client-specific) slots in above this later without changing callers.
create or replace function public.resolve_exercise_media(p_exercise_id uuid, p_viewer_id uuid)
returns jsonb language sql stable security definer as $$
  select coalesce((
    select jsonb_build_object(
      'has_coach_overlay', true,
      'coach_id', m.coach_id,
      'coach_name', up.first_name,
      'note', m.note,
      'focus', to_jsonb(coalesce(m.focus, '{}')),
      'video_ref', m.video_ref,
      'voice_url', m.voice_url,
      'updated_at', m.updated_at)
    from coach_client_relationships r
    join coach_exercise_media m on m.coach_id = r.coach_id and m.exercise_id = p_exercise_id
    join user_profiles up on up.id = m.coach_id
    where r.client_id = p_viewer_id and r.status = 'active'
    order by r.activated_at desc nulls last
    limit 1),
    jsonb_build_object('has_coach_overlay', false));
$$;
grant execute on function public.resolve_exercise_media(uuid, uuid) to authenticated;
