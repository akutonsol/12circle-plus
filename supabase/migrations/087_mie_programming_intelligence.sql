-- ═══════════════════════════════════════════════════════════════════════════
-- Migration 087 — MIE Phase 2: Programming Intelligence Layer
--
-- Turns the graph into a DECISION ENGINE. The graph answers "what is related?";
-- this answers "which option is best right now, and why?" — DETERMINISTICALLY.
-- No LLM decisions: score_exercise() computes a suitability score from structured
-- metadata + a request context. A future LLM only *explains* the ranking.
--
-- Depends on 085 (MIE). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Exercise Intelligence Profile (1:1 with exercises, reviewable) ──────────
create table if not exists exercise_intelligence (
  exercise_id          uuid primary key references custom_exercises(id) on delete cascade,
  -- difficulty applicability
  beginner             boolean default false,
  intermediate         boolean default true,
  advanced             boolean default true,
  -- goal fit (0..10)
  goal_strength        int default 0,
  goal_hypertrophy     int default 0,
  goal_power           int default 0,
  goal_endurance       int default 0,
  goal_fat_loss        int default 0,
  -- fatigue / recovery (0..10)
  local_fatigue        int default 0,
  systemic_fatigue     int default 0,
  recovery_cost        int default 0,
  -- skill (0..10)
  technical_complexity int default 0,
  coordination         int default 0,
  balance              int default 0,
  mobility_requirement int default 0,
  -- joint stress 0..10 {knee,hip,lower_back,shoulder,elbow,wrist}
  joint_stress         jsonb default '{}',
  energy_systems       text[] default '{}',        -- atp_pc | lactic | aerobic
  rep_ranges           jsonb default '{}',         -- {strength,hypertrophy,endurance}
  frequency_per_week   int,
  min_experience       text default 'beginner',    -- beginner | intermediate | advanced
  contraindications    text[] default '{}',
  -- provenance (same reviewable lifecycle as content/edges)
  source               text default 'derived',     -- derived | ai_generated | human
  status               text default 'draft',       -- draft | ai_generated | under_review | approved
  confidence           int,
  updated_at           timestamptz default now()
);
alter table exercise_intelligence enable row level security;
drop policy if exists "intel read" on exercise_intelligence;
create policy "intel read" on exercise_intelligence for select to authenticated using (true);

-- ── Bootstrap partial profiles from existing structured columns ─────────────
-- goal_tags → goal fit; exercise_type (compound/isolation) → fatigue/skill.
-- Heuristic starter only: source='derived', low confidence, status='draft'.
create or replace function public.rebuild_exercise_intelligence()
returns jsonb language plpgsql security definer as $$
declare r record; v_count int := 0; gt jsonb; compound boolean;
begin
  if not public.is_content_editor() then raise exception 'forbidden'; end if;
  for r in select id, goal_tags, exercise_type from custom_exercises loop
    gt := to_jsonb(coalesce(r.goal_tags, array[]::text[]));
    compound := (coalesce(r.exercise_type,'') ilike '%compound%');
    insert into exercise_intelligence as ei (
      exercise_id, goal_strength, goal_hypertrophy, goal_power, goal_endurance, goal_fat_loss,
      local_fatigue, systemic_fatigue, recovery_cost, technical_complexity,
      source, status, confidence, updated_at)
    values (
      r.id,
      case when gt ? 'strength' then 8 else 3 end,
      case when gt ? 'muscle_gain' or gt ? 'hypertrophy' then 8 else 4 end,
      case when gt ? 'power' then 8 else 2 end,
      case when gt ? 'endurance' then 8 else 2 end,
      case when gt ? 'fat_loss' or gt ? 'conditioning' then 7 else 4 end,
      case when compound then 7 else 5 end,
      case when compound then 7 else 3 end,
      case when compound then 6 else 3 end,
      case when compound then 6 else 3 end,
      'derived', 'draft', 40, now())
    on conflict (exercise_id) do update set
      goal_strength = excluded.goal_strength, goal_hypertrophy = excluded.goal_hypertrophy,
      goal_power = excluded.goal_power, goal_endurance = excluded.goal_endurance,
      goal_fat_loss = excluded.goal_fat_loss, systemic_fatigue = excluded.systemic_fatigue,
      local_fatigue = excluded.local_fatigue, recovery_cost = excluded.recovery_cost,
      updated_at = now()
    where ei.status = 'draft';  -- never overwrite reviewed/human profiles
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('profiles', v_count);
end;
$$;
grant execute on function public.rebuild_exercise_intelligence() to authenticated;

-- ── THE SCORING ENGINE — deterministic suitability (0..100) ─────────────────
-- context keys: goal(text), equipment(jsonb array), recovery(int 0..100),
--   experience(text), injuries(jsonb array), recent_patterns(jsonb array).
create or replace function public.score_exercise(p_exercise_id uuid, p_context jsonb)
returns jsonb language plpgsql stable security definer as $$
declare
  ei exercise_intelligence%rowtype;
  ex record;
  v_goal text := lower(coalesce(p_context->>'goal',''));
  v_recovery int := coalesce((p_context->>'recovery')::int, 100);
  v_exp text := lower(coalesce(p_context->>'experience','advanced'));
  goal_match int := 0; equip_match int := 100; recovery_match int := 100;
  exp_match int := 100; injury_compat int := 100; balance int := 100;
  exp_rank int; min_rank int; inj text; area text; stress int; penalty int := 0;
  final numeric;
begin
  select * into ei from exercise_intelligence where exercise_id = p_exercise_id;
  select equipment, movement_pattern, name into ex from custom_exercises where id = p_exercise_id;
  if not found then return jsonb_build_object('error','exercise not found'); end if;
  if ei.exercise_id is null then
    return jsonb_build_object('final_score', 0, 'no_profile', true, 'name', ex.name);
  end if;

  -- 1) Goal match (0..100) from the goal fit score (0..10).
  goal_match := 10 * case v_goal
    when 'strength' then ei.goal_strength when 'hypertrophy' then ei.goal_hypertrophy
    when 'power' then ei.goal_power when 'endurance' then ei.goal_endurance
    when 'fat_loss' then ei.goal_fat_loss
    else greatest(ei.goal_strength, ei.goal_hypertrophy, ei.goal_fat_loss) end;

  -- 2) Equipment match: available, or bodyweight/none needed.
  if p_context ? 'equipment' and jsonb_array_length(p_context->'equipment') > 0 then
    if coalesce(ex.equipment,'') in ('', 'bodyweight', 'none')
       or (p_context->'equipment') ? ex.equipment then equip_match := 100;
    else equip_match := 0; end if;
  end if;

  -- 3) Recovery match: penalize systemic fatigue beyond current recovery capacity.
  recovery_match := greatest(0, least(100, 100 - greatest(0, ei.systemic_fatigue * 10 - v_recovery)));

  -- 4) Experience match: exercise minimum must be ≤ athlete level.
  exp_rank := case v_exp when 'advanced' then 3 when 'intermediate' then 2 else 1 end;
  min_rank := case lower(coalesce(ei.min_experience,'beginner'))
                when 'advanced' then 3 when 'intermediate' then 2 else 1 end;
  exp_match := case when min_rank <= exp_rank then 100 else 40 end;

  -- 5) Injury compatibility: contraindications + high joint stress on injured areas.
  if p_context ? 'injuries' then
    for inj in select jsonb_array_elements_text(p_context->'injuries') loop
      area := lower(inj);
      if ei.contraindications is not null
         and exists (select 1 from unnest(ei.contraindications) c where lower(c) like '%'||area||'%')
      then penalty := penalty + 60; end if;
      stress := coalesce((ei.joint_stress->>area)::int, 0);
      if stress >= 6 then penalty := penalty + (stress - 5) * 10; end if;
    end loop;
  end if;
  injury_compat := greatest(0, 100 - penalty);

  -- 6) Movement balance: avoid repeating a pattern already used recently.
  if p_context ? 'recent_patterns' and coalesce(ex.movement_pattern,'') <> ''
     and (p_context->'recent_patterns') ? ex.movement_pattern then
    balance := 40;
  end if;

  -- Weighted final (weights match the product spec: 30/20/15/15/15/5).
  final := (goal_match*0.30 + equip_match*0.20 + recovery_match*0.15
            + exp_match*0.15 + injury_compat*0.15 + balance*0.05);

  return jsonb_build_object(
    'name', ex.name,
    'goal_match', goal_match, 'equipment_match', equip_match,
    'recovery_match', recovery_match, 'experience_match', exp_match,
    'injury_compatibility', injury_compat, 'movement_balance', balance,
    'final_score', round(final));
end;
$$;
grant execute on function public.score_exercise(uuid, jsonb) to authenticated;

-- Rank candidates (or the whole profiled library) by suitability, best first.
create or replace function public.rank_exercises(p_context jsonb, p_limit int default 10)
returns table(exercise_id uuid, name text, final_score int, breakdown jsonb)
language sql stable security definer as $$
  select e.id, e.name,
         (public.score_exercise(e.id, p_context)->>'final_score')::int as final_score,
         public.score_exercise(e.id, p_context) as breakdown
  from custom_exercises e
  join exercise_intelligence ei on ei.exercise_id = e.id
  order by (public.score_exercise(e.id, p_context)->>'final_score')::int desc nulls last
  limit greatest(1, least(p_limit, 50));
$$;
grant execute on function public.rank_exercises(jsonb, int) to authenticated;

-- Coverage / readiness of the intelligence layer.
create or replace function public.intelligence_stats()
returns jsonb language sql stable security definer as $$
  select jsonb_build_object(
    'total_exercises', (select count(*) from custom_exercises),
    'profiled', (select count(*) from exercise_intelligence),
    'approved', (select count(*) from exercise_intelligence where status = 'approved'),
    'draft', (select count(*) from exercise_intelligence where status = 'draft'),
    'avg_confidence', (select round(avg(confidence),1) from exercise_intelligence));
$$;
grant execute on function public.intelligence_stats() to authenticated;
