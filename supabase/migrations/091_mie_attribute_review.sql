-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 091 — MIE: Per-Attribute Review System
--
-- An editorial workflow for KNOWLEDGE. An AI-drafted intelligence profile is not
-- approve-or-reject as a whole — each attribute group (joint_stress, fatigue,
-- contraindications, rep_ranges, programming_goals, biomechanics, loading,
-- coaching) is reviewed independently. High-confidence attributes auto-pass;
-- reviewers only touch the low-confidence ones. A profile becomes 'approved'
-- only once every attribute is resolved.
--
-- Depends on 090 (attribute_confidence). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists intelligence_attribute_reviews (
  exercise_id    uuid not null references custom_exercises(id) on delete cascade,
  attribute      text not null,                 -- e.g. joint_stress | fatigue | coaching
  status         text not null,                 -- approved | rejected | needs_edit
  value_override jsonb,                          -- reviewer-corrected value (optional)
  note           text,
  reviewed_by    uuid references user_profiles(id),
  reviewed_at    timestamptz default now(),
  primary key (exercise_id, attribute)
);
alter table intelligence_attribute_reviews enable row level security;
drop policy if exists "attr review read" on intelligence_attribute_reviews;
create policy "attr review read" on intelligence_attribute_reviews for select to authenticated using (
  exists (select 1 from user_profiles where id = auth.uid() and role in ('admin','content_manager','coach')));

-- ── Review a single attribute ───────────────────────────────────────────────
create or replace function public.review_attribute(
  p_exercise_id uuid, p_attribute text, p_status text,
  p_value jsonb default null, p_note text default null)
returns void language plpgsql security definer as $$
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  if p_status not in ('approved','rejected','needs_edit') then
    raise exception 'invalid status %', p_status;
  end if;
  insert into intelligence_attribute_reviews(
    exercise_id, attribute, status, value_override, note, reviewed_by, reviewed_at)
  values (p_exercise_id, p_attribute, p_status, p_value, p_note, auth.uid(), now())
  on conflict (exercise_id, attribute) do update set
    status = excluded.status, value_override = excluded.value_override,
    note = excluded.note, reviewed_by = auth.uid(), reviewed_at = now();
end;
$$;
grant execute on function public.review_attribute(uuid, text, text, jsonb, text) to authenticated;

-- ── Merged per-attribute state (confidence + review) for the review UI ──────
-- review_status ∈ 'auto' (high-confidence, no review needed) | 'pending' |
--   'approved' | 'rejected' | 'needs_edit'
create or replace function public.attribute_review_state(p_exercise_id uuid, p_threshold int default 90)
returns jsonb language sql stable security definer as $$
  select coalesce(jsonb_object_agg(a.k, jsonb_build_object(
      'confidence', (a.v)::int,
      'review_status', coalesce(r.status,
          case when (a.v)::int >= p_threshold then 'auto' else 'pending' end),
      'note', r.note)), '{}'::jsonb)
  from exercise_intelligence ei
  cross join lateral jsonb_each_text(coalesce(ei.attribute_confidence, '{}'::jsonb)) as a(k, v)
  left join intelligence_attribute_reviews r
    on r.exercise_id = ei.exercise_id and r.attribute = a.k
  where ei.exercise_id = p_exercise_id;
$$;
grant execute on function public.attribute_review_state(uuid, int) to authenticated;

-- ── Finalize: derive the profile status from its attributes ─────────────────
-- rejected/needs_edit on any attribute → needs_revision; all resolved (high-
-- confidence OR approved) → approved; otherwise still under_review.
create or replace function public.finalize_intelligence(p_exercise_id uuid, p_threshold int default 90)
returns text language plpgsql security definer as $$
declare rec record; any_bad boolean := false; all_ok boolean := true; rvw text; v_status text;
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  for rec in
    select a.k as attr, (a.v)::int as conf
    from exercise_intelligence ei
    cross join lateral jsonb_each_text(coalesce(ei.attribute_confidence, '{}'::jsonb)) as a(k, v)
    where ei.exercise_id = p_exercise_id
  loop
    select status into rvw from intelligence_attribute_reviews
      where exercise_id = p_exercise_id and attribute = rec.attr;
    if rvw in ('rejected','needs_edit') then any_bad := true; end if;
    if not ((rec.conf >= p_threshold) or (rvw = 'approved')) then all_ok := false; end if;
  end loop;

  v_status := case when any_bad then 'needs_revision'
                   when all_ok then 'approved' else 'under_review' end;
  update exercise_intelligence set status = v_status,
    reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where exercise_id = p_exercise_id;
  return v_status;
end;
$$;
grant execute on function public.finalize_intelligence(uuid, int) to authenticated;

-- ── Review queue: profiles awaiting an editor, lowest confidence first ──────
create or replace function public.intelligence_review_queue(p_limit int default 50)
returns table(exercise_id uuid, name text, status text, confidence int, low_conf_count int)
language sql stable security definer as $$
  select ei.exercise_id, e.name, ei.status, ei.confidence,
    (select count(*)::int from jsonb_each_text(coalesce(ei.attribute_confidence, '{}'::jsonb)) a
       where (a.value)::int < 90)
  from exercise_intelligence ei
  join custom_exercises e on e.id = ei.exercise_id
  where ei.status in ('ai_generated','under_review')
  order by ei.confidence asc nulls first
  limit greatest(1, least(p_limit, 100));
$$;
grant execute on function public.intelligence_review_queue(int) to authenticated;
