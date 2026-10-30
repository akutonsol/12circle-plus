-- Migration 188. The coaching engine selects only exercises that are BOTH certified
-- for the calling module AND carry human-approved intelligence; the module is
-- explicit and an unknown one is refused; a Push / Pull / Legs session draws only
-- from its own movement patterns.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 182 (the scoped
-- certification view), 186 (the engine body it extends) and 187 (what 'approved'
-- means). Verified only on a local replay (supabase/tests/local/engine_gate_replay.sh).
--
-- Owner direction 2026-10-25, as an IMPLEMENTATION TARGET — PD-A02 is NOT recorded
-- as decided, and the D-1 wording conflict (MASTER_PRODUCT_DECISIONS §0.2 "already
-- answered" vs MASTER_REMEDIATION_WAVES 5.2/5.7 "Blocked on D-1") is NOT resolved
-- by this file:
--   A    option (c): module-specific certification AND approved intelligence.
--   A.1  Program Builder -> program_generator; Copilot -> workout_builder; the
--        module is passed explicitly; unknown values fail closed.
--   D    distinct session focus is a product acceptance requirement when
--        Push/Pull/Legs is advertised.
--   A.2  ai-generate-workout is OUT of this milestone (it does not call this engine
--        and stays an open compliance item).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT IS WRONG TODAY (127's build_workout, 186's engine)
-- ═══════════════════════════════════════════════════════════════════════════
--   * build_workout ranks `exercises e JOIN exercise_intelligence ei` (127:101):
--     any profile in any status — derived heuristics, AI drafts — is eligible,
--     and certification is never read (ENG-07).
--   * it reads `exercises` (owner rights, every row), so a coach's request can
--     select — and record in the decision trace — another coach's private
--     exercise once that exercise has a profile.
--   * the engine passes each session only `size` and `recovery` (186:182), so
--     every session of a week asks the same question: on the 000-186 replay all
--     three Push/Pull/Legs days came out identical.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT CHANGES
-- ═══════════════════════════════════════════════════════════════════════════
-- build_workout(p_context) — same signature, STABLE, SECURITY DEFINER, pinned:
--   * p_context.module MUST be the JSON string "workout_builder" or
--     "program_generator". Missing, null, non-string or anything else raises
--     ENGINE_UNKNOWN_MODULE (22023) before anything is read.
--   * the candidate universe is the exercises the CALLER may read
--     (exercise_readable(id) OR is_content_editor() — 182's predicate).
--   * eligible = certified for the module in exercise_certifications (182's
--     column of that name) AND exercise_intelligence.status = 'approved'
--     (187's contract) AND, when a focus is given, a movement pattern in it.
--     Only eligible exercises are scored; the existing rules (equipment, injury
--     score, systemic-fatigue cap, one per pattern) then run unchanged.
--   * the result adds `module`, `focus`, `allowed_patterns`, `selection_status`
--     ('ok' | 'NO_ELIGIBLE_EXERCISES' | 'ALL_CANDIDATES_REJECTED' |
--     'INSUFFICIENT_ELIGIBLE_EXERCISES') and `eligibility` {considered, eligible,
--     eligible_compound, rejected:{NOT_CERTIFIED_FOR_MODULE,
--     INTELLIGENCE_MISSING, INTELLIGENCE_NOT_APPROVED, OUTSIDE_SESSION_FOCUS},
--     ineligible_sample (<= 25, closest-to-eligible first)}. An exercise can carry
--     several reasons. rules_triggered is unchanged in meaning, so analytics over
--     decision_traces do not fill with eligibility noise.
--   * p_context.focus (optional) restricts main slots via _engine_in_focus
--     (pattern + category, below) and requires a compound lift; an unknown focus
--     raises ENGINE_UNKNOWN_FOCUS. Copilot sends no focus and is unrestricted.
--
-- materialize_program_week_engine — 186's body, with three changes only:
--   * each session's context is p_context || {size, recovery,
--     module: "program_generator", focus: <the split label>}. The engine SETS
--     both keys, so a caller cannot widen the gate by passing its own.
--   * ENGINE_NO_SELECTION now says why: selection_status and the rejection counts.
--   * a session with no eligible compound lift raises ENGINE_INSUFFICIENT_ELIGIBLE.
--   All-or-nothing, ENGINE_WEEK_EXISTS, ENGINE_BAD_PRESCRIPTION, the FOR UPDATE
--   lock, the canonical prescription and the 124 wrapper are unchanged. An
--   unknown split label raises ENGINE_UNKNOWN_FOCUS before anything is written.
--
-- SESSION FOCUS — owner direction 2026-10-25 (implementation target; not a
-- recorded governance decision). An exercise fills a main slot of a focused
-- session only if its movement_pattern AND its library category match. Both are
-- display labels ("Horizontal Push", "Upper Body", sometimes "upper_body"), so
-- both are normalized to snake_case first.
--   Push   pattern horizontal_push, vertical_push, elbow_extension,
--          shoulder_flexion, shoulder_abduction          AND category upper_body
--   Pull   pattern horizontal_pull, vertical_pull, elbow_flexion, rear_delt,
--          shrug (NOT `pull`: that label holds cleans and snatches)
--                                                       AND category upper_body
--   Legs / Lower   pattern squat, hinge, hip_extension, unilateral, knee_flexion,
--          knee_extension, hip_abduction, hip_adduction, ankle_extension,
--          ankle_flexion                                AND category lower_body,
--          PLUS the deadlift family: pattern hinge AND category full_body
--          (Deadlift, Sumo, Trap Bar, Deficit, Snatch-Grip, Axle, Rack Pull on the
--          000-188 replay) — deadlifts go on Legs, never Pull
--   Upper  Push + Pull rules       Full Body  no restriction
-- These are every label plan_program (093) can emit. So Olympic lifts, sled and
-- strongman work, kettlebell front squats (category Functional, until their role
-- is confirmed), thrusters, warm-ups, corrective, mobility, conditioning and core
-- exercises fill no main slot of a focused session. Core MAY be an extra in a
-- later change; nothing here adds extras.
-- COMPOUND REQUIREMENT: a focused session (every Program Builder session) must
-- contain at least one exercise whose exercise_type is Compound. When one is
-- eligible it is placed first; when none is, build_workout returns
-- selection_status INSUFFICIENT_ELIGIBLE_EXERCISES with nothing selected and the
-- engine raises ENGINE_INSUFFICIENT_ELIGIBLE, writing nothing.
--
-- CONSEQUENCE, stated plainly: with no exercise both certified and carrying
-- human-approved intelligence, BOTH engine entry points select nothing — Copilot
-- returns selection_status NO_ELIGIBLE_EXERCISES, Program Builder raises
-- ENGINE_NO_SELECTION and writes nothing. On QA today (0 intelligence rows,
-- 2026-10-25) that is the state until the content work (EB-4) is done through
-- 187's review pipeline.
--
-- NOT CHANGED, deliberately: score_exercise and its injury logic (decision C: the
-- first walkthrough uses a client with no injuries; this file does not make
-- injury handling safe); rank_exercises (uncalled by the app, ungated — kept
-- visible, not fixed here); ai-generate-workout (A.2); generate_workout and the
-- 124 wrapper (authorization unchanged).
--
-- Authorization and posture: build_workout stays allowlisted to authenticated
-- (116 class B, pure helper, no writes); the engine stays revoked from PUBLIC,
-- anon and authenticated and reachable only through materialize_program_week
-- (can_act_on_program, 124); _engine_focus_patterns and _engine_pattern_key are
-- revoked from all client roles. Every function pins search_path.

BEGIN;

CREATE OR REPLACE FUNCTION public._engine_pattern_key(p_pattern text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT nullif(lower(regexp_replace(btrim(coalesce(p_pattern, '')), '[[:space:]-]+', '_', 'g')), '');
$$;

-- NULL = no restriction (Full Body). Unknown labels raise.
CREATE OR REPLACE FUNCTION public._engine_focus_patterns(p_focus text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  k    text := public._engine_pattern_key(p_focus);
  push text[] := ARRAY['horizontal_push', 'vertical_push', 'elbow_extension',
                       'shoulder_flexion', 'shoulder_abduction'];
  pull text[] := ARRAY['horizontal_pull', 'vertical_pull', 'elbow_flexion', 'rear_delt', 'shrug'];
  legs text[] := ARRAY['squat', 'hinge', 'hip_extension', 'unilateral', 'knee_flexion',
                       'knee_extension', 'hip_abduction', 'hip_adduction',
                       'ankle_extension', 'ankle_flexion'];
BEGIN
  IF k = 'push' THEN RETURN push;
  ELSIF k = 'pull' THEN RETURN pull;
  ELSIF k IN ('legs', 'lower') THEN RETURN legs;
  ELSIF k = 'upper' THEN RETURN push || pull;
  ELSIF k = 'full_body' THEN RETURN NULL;
  END IF;
  RAISE EXCEPTION 'ENGINE_UNKNOWN_FOCUS: the engine has no movement-pattern mapping for session "%" '
    '(known: Push, Pull, Legs, Upper, Lower, Full Body). Nothing was selected.', p_focus
    USING ERRCODE = '22023';
END;
$$;

-- Does an exercise belong in a session's main slots? Owner direction 2026-10-25:
-- pattern AND normalized library category. Push / Pull / Upper take Upper Body;
-- Legs / Lower take Lower Body, plus the deadlift family (Hinge, category Full
-- Body). Every other category — Olympic, Functional (sled, strongman, kettlebell
-- front squat), Warmups, Corrective Exercise, Mobility, Conditioning, Core, and
-- Full Body outside the hinge — is out of the main slots. Full Body sessions are
-- unrestricted. An unknown focus raises (via _engine_focus_patterns).
CREATE OR REPLACE FUNCTION public._engine_in_focus(p_focus text, p_pattern text, p_category text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  pats text[] := public._engine_focus_patterns(p_focus);
  f    text   := public._engine_pattern_key(p_focus);
  k    text   := public._engine_pattern_key(p_pattern);
  c    text   := public._engine_pattern_key(p_category);
BEGIN
  IF pats IS NULL THEN RETURN true; END IF;
  IF k IS NULL OR NOT (k = ANY (pats)) THEN RETURN false; END IF;
  IF f IN ('push', 'pull', 'upper') THEN RETURN c = 'upper_body'; END IF;
  RETURN c = 'lower_body' OR (k = 'hinge' AND c = 'full_body');
END;
$$;

create or replace function public.build_workout(p_context jsonb)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_module   text;
  v_focus    text := nullif(btrim(coalesce(p_context->>'focus', '')), '');
  v_allowed  text[];
  v_size     int := coalesce((p_context->>'size')::int, 5);
  v_recovery int := coalesce((p_context->>'recovery')::int, 100);
  v_vol      numeric := case when v_recovery < 60 then 0.8 else 1.0 end;
  v_target   int := greatest(1, round(v_size * v_vol));
  v_systemic int := 0;
  v_patterns text[] := '{}';
  v_ids      uuid[] := '{}';
  v_count    int := 0;
  v_traced   int := 0;
  sel        jsonb := '[]'::jsonb;
  trace      jsonb := '[]'::jsonb;
  rules      text[] := '{}';
  rec        record;
  decision text; reason text; rule text; em int; ic int;
  v_elig     jsonb;
  v_status   text;
begin
  -- A.1: the module is explicit. Anything but these two strings is refused.
  if jsonb_typeof(p_context->'module') is distinct from 'string'
     or (p_context->>'module') not in ('workout_builder', 'program_generator') then
    raise exception 'ENGINE_UNKNOWN_MODULE: build_workout needs "module" = "workout_builder" (Copilot) '
      'or "program_generator" (Program Builder); got %. Nothing was selected.',
      coalesce(p_context->'module', 'null'::jsonb)
      using errcode = '22023';
  end if;
  v_module := p_context->>'module';
  if v_focus is not null then
    v_allowed := public._engine_focus_patterns(v_focus);
  end if;

  -- Why each readable exercise is, or is not, a candidate.
  with cand as (
    select e.id, e.name, e.movement_pattern, e.category, e.exercise_type,
           ei.exercise_id is not null as has_profile, ei.status as intel_status,
           case v_module when 'workout_builder'   then c.workout_builder
                         when 'program_generator' then c.program_generator end as certified
      from exercises e
      left join exercise_intelligence ei on ei.exercise_id = e.id
      left join exercise_certifications c on c.id = e.id
     where public.exercise_readable(e.id) or public.is_content_editor()
  ), judged as (
    select id, name, movement_pattern, exercise_type, array_remove(array[
        case when not coalesce(certified, false) then 'NOT_CERTIFIED_FOR_MODULE' end,
        case when not has_profile then 'INTELLIGENCE_MISSING'
             when intel_status is distinct from 'approved' then 'INTELLIGENCE_NOT_APPROVED' end,
        case when v_focus is not null
              and not public._engine_in_focus(v_focus, movement_pattern, category)
             then 'OUTSIDE_SESSION_FOCUS' end], null) as reasons
      from cand
  )
  select jsonb_build_object(
      'considered', count(*),
      'eligible',   count(*) filter (where cardinality(reasons) = 0),
      'eligible_compound', count(*) filter (where cardinality(reasons) = 0
                                              and public._engine_pattern_key(exercise_type) = 'compound'),
      'rejected', jsonb_build_object(
        'NOT_CERTIFIED_FOR_MODULE',  count(*) filter (where 'NOT_CERTIFIED_FOR_MODULE'  = any (reasons)),
        'INTELLIGENCE_MISSING',      count(*) filter (where 'INTELLIGENCE_MISSING'      = any (reasons)),
        'INTELLIGENCE_NOT_APPROVED', count(*) filter (where 'INTELLIGENCE_NOT_APPROVED' = any (reasons)),
        'OUTSIDE_SESSION_FOCUS',     count(*) filter (where 'OUTSIDE_SESSION_FOCUS'     = any (reasons))),
      'ineligible_sample', coalesce((
        select jsonb_agg(s.x) from (
          select jsonb_build_object('name', j.name, 'pattern', j.movement_pattern,
                                    'reasons', to_jsonb(j.reasons)) as x
            from judged j where cardinality(j.reasons) > 0
           order by cardinality(j.reasons), j.name limit 25) s), '[]'::jsonb))
    into v_elig
    from judged;

  if v_recovery < 60 then rules := rules || 'RECOVERY_REDUCTION'::text; end if;
  for rec in
    with scored as (
      select e.id, e.name, e.movement_pattern,
             public._engine_pattern_key(e.exercise_type) = 'compound' as is_compound,
             coalesce(ei.systemic_fatigue, 0) as sysfat,
             public.score_exercise(e.id, p_context) as bd
        from exercises e
        join exercise_intelligence ei on ei.exercise_id = e.id and ei.status = 'approved'
        join exercise_certifications c on c.id = e.id
       where (case v_module when 'workout_builder'   then c.workout_builder
                            when 'program_generator' then c.program_generator end)
         and (public.exercise_readable(e.id) or public.is_content_editor())
         and (v_focus is null or public._engine_in_focus(v_focus, e.movement_pattern, e.category))
    ), ranked as (
      -- A focused session must contain a compound lift. The best compound that
      -- passes the equipment and injury rules goes FIRST; with nothing selected
      -- yet the fatigue cap and variety rule cannot reject it, so it is accepted
      -- whenever one is eligible. Everything else keeps 127's score order.
      select s.*, (s.bd->>'final_score')::int as fs,
             row_number() over (
               partition by (s.is_compound and (s.bd->>'equipment_match')::int <> 0
                             and (s.bd->>'injury_compatibility')::int >= 40)
               order by (s.bd->>'final_score')::int desc nulls last, s.name) as crank,
             (s.is_compound and (s.bd->>'equipment_match')::int <> 0
                and (s.bd->>'injury_compatibility')::int >= 40) as compound_ok
        from scored s)
    select id, name, movement_pattern, is_compound, sysfat, bd, fs
    from ranked
    order by (v_focus is not null and compound_ok and crank = 1) desc, fs desc nulls last
  loop
    exit when v_count >= v_target;
    em := (rec.bd->>'equipment_match')::int;
    ic := (rec.bd->>'injury_compatibility')::int;
    rule := null; reason := null; decision := 'accepted';
    if em = 0 then
      decision := 'rejected'; rule := 'EQUIPMENT_CONSTRAINT'; reason := 'required equipment unavailable';
    elsif ic < 40 then
      decision := 'rejected'; rule := 'INJURY_PREVENTION'; reason := 'injury incompatibility (score ' || ic || ')';
    elsif rec.sysfat >= 7 and v_systemic >= 2 then
      decision := 'rejected'; rule := 'MAX_SYSTEMIC_FATIGUE'; reason := 'systemic-fatigue cap (2) reached';
    elsif rec.movement_pattern is not null and rec.movement_pattern = any(v_patterns) then
      decision := 'rejected'; rule := 'MOVEMENT_VARIETY'; reason := rec.movement_pattern || ' already selected';
    else
      reason := 'top-ranked available candidate';
    end if;

    if v_traced < 25 then
      trace := trace || jsonb_build_object(
        'name', rec.name, 'score', rec.fs, 'pattern', rec.movement_pattern,
        'systemic_fatigue', rec.sysfat, 'decision', decision, 'reason', reason,
        'rule', rule, 'breakdown', rec.bd);
      v_traced := v_traced + 1;
    end if;

    if decision = 'accepted' then
      sel := sel || jsonb_build_object('id', rec.id, 'name', rec.name,
               'pattern', rec.movement_pattern, 'score', rec.fs, 'systemic_fatigue', rec.sysfat);
      if rec.sysfat >= 7 then v_systemic := v_systemic + 1; end if;
      if rec.movement_pattern is not null then v_patterns := v_patterns || rec.movement_pattern; end if;
      v_ids := v_ids || rec.id;
      v_count := v_count + 1;
    elsif rule is not null and not (rule = any(rules)) then
      rules := rules || rule;
    end if;
  end loop;

  v_status := case when v_count > 0 then 'ok'
                   when (v_elig->>'eligible')::int = 0 then 'NO_ELIGIBLE_EXERCISES'
                   else 'ALL_CANDIDATES_REJECTED' end;

  -- A focused session without a compound lift is refused, not shipped: the
  -- selection is withdrawn and the status says why.
  if v_focus is not null and v_count > 0
     and not exists (select 1 from jsonb_array_elements(sel) x
                       join exercises e on e.id = (x->>'id')::uuid
                      where public._engine_pattern_key(e.exercise_type) = 'compound') then
    sel := '[]'::jsonb; v_ids := '{}'; v_count := 0;
    v_status := 'INSUFFICIENT_ELIGIBLE_EXERCISES';
  end if;

  return jsonb_build_object(
    'volume_factor', v_vol, 'target_size', v_target, 'selected', sel,
    'systemic_fatigue_count', v_systemic, 'warmup', public.generate_warmup(v_ids),
    'trace', trace, 'rules_triggered', to_jsonb(rules),
    'module', v_module, 'focus', v_focus, 'allowed_patterns', to_jsonb(v_allowed),
    'selection_status', v_status, 'eligibility', v_elig,
    'rules_applied', jsonb_build_array(
      'certified for ' || v_module || ' AND human-approved intelligence only',
      case when v_allowed is null then 'no session focus restriction'
           else 'session focus ' || v_focus || ' only (pattern and library category)' end,
      case when v_focus is null then 'no compound requirement'
           else 'at least one compound lift, else refused' end,
      case when v_recovery < 60 then 'recovery<60 → volume −20%' else 'full volume' end,
      '≤2 systemic-fatigue exercises', 'one exercise per movement pattern',
      'exclude unavailable-equipment / injury-incompatible'));
end;
$$;

CREATE OR REPLACE FUNCTION public.materialize_program_week_engine(
  p_program_id uuid, p_week integer, p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan     jsonb;
  v_week     jsonb;
  v_split    jsonb;
  v_vol      numeric;
  v_base     int;
  v_sets     int;
  v_reps     int;
  v_rest     int;
  v_replace  boolean;
  v_existing int;
  v_ctx      jsonb;
  v_result   jsonb;
  v_selected jsonb;
  v_built    jsonb := '[]'::jsonb;   -- [{label, trace_id, exercises}]
  v_sessions jsonb := '[]'::jsonb;
  v_s        jsonb;
  i          int;
BEGIN
  -- 3. Serialize concurrent materializations of the same programme.
  SELECT plan INTO v_plan FROM workout_programs WHERE id = p_program_id FOR UPDATE;
  IF v_plan IS NULL THEN
    RAISE EXCEPTION 'ENGINE_NO_PLAN: programme % has no plan to materialize', p_program_id;
  END IF;

  SELECT w INTO v_week FROM jsonb_array_elements(v_plan->'weeks') w
   WHERE (w->>'week')::int = p_week;
  IF v_week IS NULL THEN
    RAISE EXCEPTION 'ENGINE_NO_WEEK: week % is not in the plan of programme %', p_week, p_program_id;
  END IF;

  v_split   := coalesce(v_week->'split', '[]'::jsonb);
  v_vol     := coalesce((v_week->>'volume_multiplier')::numeric, 1.0);
  v_base    := coalesce((p_context->>'size')::int, 5);
  v_sets    := coalesce(public._wk_int(p_context->'sets'), 3);
  v_reps    := coalesce(public._wk_int(p_context->'reps'), 10);
  v_rest    := public._wk_int(p_context->'rest_seconds');
  -- Only a JSON `true` replaces anything. A string ("true", "yes") or a missing
  -- key is NOT consent to delete a week's days.
  v_replace := coalesce(p_context->'replace_existing' = 'true'::jsonb, false);

  -- A prescription value that is PRESENT but not a whole number ("8-12", "ten",
  -- 7.5) is refused, not replaced by the 3 x 10 default: silently substituting a
  -- number the caller did not give is inventing a prescription. Absent or null
  -- still means "use the default". Bounds mirror the canonical CHECK.
  IF (p_context ? 'sets' AND jsonb_typeof(p_context->'sets') <> 'null'
        AND (public._wk_int(p_context->'sets') IS NULL OR v_sets < 1))
  OR (p_context ? 'reps' AND jsonb_typeof(p_context->'reps') <> 'null'
        AND (public._wk_int(p_context->'reps') IS NULL OR v_reps < 0))
  OR (p_context ? 'rest_seconds' AND jsonb_typeof(p_context->'rest_seconds') <> 'null'
        AND (v_rest IS NULL OR v_rest < 0)) THEN
    RAISE EXCEPTION 'ENGINE_BAD_PRESCRIPTION: sets, reps and rest_seconds must be whole '
      'numbers (sets >= 1, reps >= 0, rest_seconds >= 0); got sets=%, reps=%, rest_seconds=%. '
      'Nothing was changed.',
      p_context->'sets', p_context->'reps', p_context->'rest_seconds';
  END IF;

  IF jsonb_array_length(v_split) = 0 THEN
    RAISE EXCEPTION 'ENGINE_NO_WEEK: week % of programme % has no sessions in its split', p_week, p_program_id;
  END IF;

  -- 2. Never overwrite a week silently.
  SELECT count(*) INTO v_existing FROM program_workouts
   WHERE program_id = p_program_id AND week_number = p_week;
  IF v_existing > 0 AND NOT v_replace THEN
    RAISE EXCEPTION 'ENGINE_WEEK_EXISTS: week % of programme % already has % training day(s). '
      'Nothing was changed. Pass "replace_existing": true to regenerate it.',
      p_week, p_program_id, v_existing;
  END IF;

  -- 1. Build and validate EVERY session before writing anything.
  FOR i IN 0 .. jsonb_array_length(v_split) - 1 LOOP
    -- 188: the engine, not the caller, sets the module and the session focus.
    v_ctx := p_context || jsonb_build_object(
      'size', greatest(2, round(v_base * v_vol)),
      'recovery', coalesce((p_context->>'recovery')::int, 75),
      'module', 'program_generator',
      'focus', v_split->>i);
    v_result   := public.generate_workout(v_ctx, (p_context->>'subject')::uuid);
    v_selected := coalesce(v_result->'selected', '[]'::jsonb);

    IF v_result->>'selection_status' = 'INSUFFICIENT_ELIGIBLE_EXERCISES' THEN
      RAISE EXCEPTION 'ENGINE_INSUFFICIENT_ELIGIBLE: week %, session "%" of programme % has no eligible '
        'compound lift, and a session needs one. Nothing was saved. Certify and review at least one '
        'compound exercise in this session''s movement patterns (eligible %, eligible compound %).',
        p_week, coalesce(v_split->>i, (i + 1)::text), p_program_id,
        coalesce(v_result->'eligibility'->>'eligible', '?'),
        coalesce(v_result->'eligibility'->>'eligible_compound', '?');
    END IF;
    IF jsonb_typeof(v_selected) <> 'array' OR jsonb_array_length(v_selected) = 0 THEN
      RAISE EXCEPTION 'ENGINE_NO_SELECTION: the coaching engine selected no exercises for '
        'week %, session "%" of programme %. Nothing was saved. Only exercises certified for '
        'Program Builder with human-approved intelligence in this session''s movement patterns '
        'can be selected (status %, rejected %).',
        p_week, coalesce(v_split->>i, (i + 1)::text), p_program_id,
        coalesce(v_result->>'selection_status', 'unknown'),
        coalesce(v_result->'eligibility'->'rejected', '{}'::jsonb);
    END IF;

    v_built := v_built || jsonb_build_object(
      'label', v_split->>i,
      'trace_id', v_result->'trace_id',
      'exercises', (
        SELECT jsonb_agg(jsonb_build_object(
                 'exercise_instance_id', gen_random_uuid()::text,
                 'exercise_id',          s.value->>'id',
                 'name',                 s.value->>'name',
                 'position',             (s.ordinality - 1)::int,
                 'sets',                 v_sets,
                 'reps',                 v_reps,
                 'weight_kg',            null,
                 'rest_seconds',         public._wk_jint(v_rest),
                 'rpe',                  null,
                 'tempo',                null,
                 'duration_seconds',     null,
                 'notes',                null,
                 'movement_pattern',     s.value->>'pattern')
               ORDER BY s.ordinality)
          FROM jsonb_array_elements(v_selected) WITH ORDINALITY s(value, ordinality)));
  END LOOP;

  -- Only now is anything changed.
  IF v_existing > 0 THEN
    DELETE FROM program_workouts WHERE program_id = p_program_id AND week_number = p_week;
  END IF;

  i := 0;
  FOR v_s IN SELECT value FROM jsonb_array_elements(v_built) LOOP
    INSERT INTO program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
    VALUES (p_program_id, p_week,
      (ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[least(i + 1, 7)],
      format('Week %s · %s', p_week, v_s->>'label'),
      v_s->'exercises', i);
    v_sessions := v_sessions || jsonb_build_object(
      'session',   v_s->>'label',
      'trace_id',  v_s->'trace_id',
      'exercises', jsonb_array_length(v_s->'exercises'));
    i := i + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'week', p_week,
    'sessions_created', i,
    'replaced_existing', v_existing > 0,
    'sessions', v_sessions);
END;
$$;

REVOKE ALL ON FUNCTION public._engine_pattern_key(text)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_focus_patterns(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_in_focus(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.materialize_program_week_engine(uuid, integer, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.build_workout(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.build_workout(jsonb) TO authenticated;

COMMENT ON FUNCTION public.build_workout(jsonb) IS
  'Deterministic session builder (188). Requires p_context.module = workout_builder | '
  'program_generator (ENGINE_UNKNOWN_MODULE otherwise). Selects only exercises the caller '
  'may read that are certified for that module AND have approved intelligence (187), '
  'optionally within a session focus (ENGINE_UNKNOWN_FOCUS for unknown labels). Reports '
  'selection_status and per-reason eligibility counts.';

COMMENT ON FUNCTION public.materialize_program_week_engine(uuid, integer, jsonb) IS
  'Coach programme engine (186, gated by 188): materializes one plan week into canonical '
  'training days — each session built with module program_generator and its split label as '
  'focus; sets/reps from context (default 3x10), weight_kg null, real day names — or raises '
  'ENGINE_NO_SELECTION / ENGINE_INSUFFICIENT_ELIGIBLE / ENGINE_UNKNOWN_FOCUS / ENGINE_WEEK_EXISTS / ENGINE_BAD_PRESCRIPTION / '
  'ENGINE_NO_PLAN / ENGINE_NO_WEEK and changes nothing. Existing days are replaced only with '
  '"replace_existing": true. Reached only through materialize_program_week (authorization wrapper, 124).';

COMMIT;
