-- 127_typed_rule_accumulator_appends.sql
--
-- Closes F-J-07 (registry SEC-R3, P0) and the two further instances of the same
-- defect class that F-J-07's own remediation note required to be swept for.
--
-- ── ROOT CAUSE (identical to F-J-17 / migration 126) ────────────────────────
--   v text[] := '{}';
--   v := v || 'LABEL';        -- unknown-typed literal
--
-- `text[] || unknown` is ambiguous. PostgreSQL resolves it to
-- anyarray || anyarray, then tries to read 'LABEL' AS AN ARRAY LITERAL and
-- raises 22P02 malformed array literal: "LABEL". An append of a DECLARED text
-- value (`rules := rules || rule`) or of an explicit array constructor
-- (`rules := rules || array['A','B']`) is unambiguous and works — which is why
-- the fault hides: in every function below the working shape sits beside the
-- broken one.
--
-- ── THE ELEVEN SITES, ALL ON DECISION PATHS ─────────────────────────────────
--   build_workout          089:55  RECOVERY_REDUCTION                        (1)
--   evaluate_week          094:52  INJURY_ADAPTATION                         (4)
--                          094:55  FATIGUE_DELOAD
--                          094:60  ADHERENCE_SUPPORT
--                          094:65  PROGRESSIVE_OVERLOAD
--   predict_client         095:125 plateau_approaching                       (6)
--                          095:127 recovery_declining
--                          095:128 high_injury_probability
--                          095:129 coach_followup_recommended
--                          095:130 ahead_of_schedule
--                          095:131 goal_achieved_early
--
-- Each throws the moment its branch is taken. In build_workout that is
-- recovery < 60 — the one rule that protects an under-recovered member is the
-- only rule in the function that cannot run. In evaluate_week the low-recovery
-- branch survives only because it appends an array CONSTRUCTOR; the injury,
-- deload, adherence and overload branches all throw. In predict_client every
-- deterministic alert throws, including high_injury_probability.
--
-- ── WHY THIS FILE REDECLARES *_engine, NOT THE PUBLIC NAMES ─────────────────
-- Migration 116 renamed predict_client(uuid,uuid) -> predict_client_engine and
-- evaluate_week(uuid,integer) -> evaluate_week_engine, and published NEW public
-- functions of those names as authorization wrappers (can_act_for /
-- can_act_on_program). The defective bodies therefore live in the *_engine
-- functions today. Redeclaring the PUBLIC names with these bodies would delete
-- 116's authorization wrappers — precisely the F-J-01 / SEC-R1 regression that
-- migration 119 caused and migration 124 had to repair. The wrappers are NOT
-- touched here. build_workout was not renamed by 116 (it is in 116's
-- "pure/deterministic helpers with no subject" class) and is replaced directly.
--
-- ── WHAT IS PRESERVED, EXACTLY ──────────────────────────────────────────────
-- Each body below is byte-identical to its 089 / 094 / 095 original except for
-- the ::text casts, the two *_engine names, and the restated search_path pin.
--   * signatures, argument defaults, return types      unchanged
--   * STABLE volatility                                restated verbatim
--   * SECURITY DEFINER                                 restated verbatim
--   * SET search_path = public, pg_temp                RESTATED ON PURPOSE.
--     118 (F-08) pinned every function in public and 122 re-pinned what Phase 2
--     dropped, both via ALTER FUNCTION so no body was touched. CREATE OR REPLACE
--     does NOT preserve proconfig (I-MIG-03 / CRC-07), so omitting it here would
--     silently unpin all three functions.
--   * EXECUTE privileges                               preserved by CREATE OR
--     REPLACE (same oid); 116's REVOKEs on the engines still stand. No GRANT or
--     REVOKE is issued by this migration.
--
-- No table, column, policy, trigger, grant or row is touched. No behaviour
-- changes other than the branches that previously threw now completing.
--
-- Out of scope, deliberately: F-J-09 (null-permissive gates), F-J-23, F-J-05,
-- F-J-06 and every P1 finding.
--
-- Forward-only. Idempotent: CREATE OR REPLACE.

BEGIN;

-- ── 1/3 · build_workout (089) — F-J-07 / SEC-R3 ─────────────────────────────
create or replace function public.build_workout(p_context jsonb)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
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
begin
  if v_recovery < 60 then rules := rules || 'RECOVERY_REDUCTION'::text; end if;
  for rec in
    with scored as (
      select e.id, e.name, e.movement_pattern,
             coalesce(ei.systemic_fatigue, 0) as sysfat,
             public.score_exercise(e.id, p_context) as bd
      from exercises e join exercise_intelligence ei on ei.exercise_id = e.id)
    select id, name, movement_pattern, sysfat, bd, (bd->>'final_score')::int as fs
    from scored order by (bd->>'final_score')::int desc nulls last
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

  return jsonb_build_object(
    'volume_factor', v_vol, 'target_size', v_target, 'selected', sel,
    'systemic_fatigue_count', v_systemic, 'warmup', public.generate_warmup(v_ids),
    'trace', trace, 'rules_triggered', to_jsonb(rules),
    'rules_applied', jsonb_build_array(
      case when v_recovery < 60 then 'recovery<60 → volume −20%' else 'full volume' end,
      '≤2 systemic-fatigue exercises', 'one exercise per movement pattern',
      'exclude unavailable-equipment / injury-incompatible'));
end;
$$;

-- ── 2/3 · evaluate_week_engine (094 body, renamed by 116) ──────────────────
create or replace function public.evaluate_week_engine(p_program_id uuid, p_week int)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  fb weekly_feedback%rowtype; v_mode text; v_dur int; v_focus_injury boolean;
  action text := 'CONTINUE'; vol_delta numeric := 0; rules text[] := '{}';
  escalate boolean := false; needs_approval boolean := false; reason text := 'on track';
begin
  select * into fb from weekly_feedback where program_id = p_program_id and week = p_week;
  if not found then return jsonb_build_object('action', 'NO_FEEDBACK'); end if;
  select (plan->>'duration_weeks')::int into v_dur from workout_programs where id = p_program_id;
  select coaching_mode into v_mode from user_profiles where id = fb.subject_id;
  v_focus_injury := coalesce(jsonb_array_length(fb.pain), 0) > 0;

  -- Priority order: injury → fatigue deload → recovery → adherence → overload.
  if v_focus_injury then
    action := 'REPLACE_EXERCISES'; rules := rules || 'INJURY_ADAPTATION'::text;
    reason := 'pain reported — substitute via movement graph';
  elsif fb.recovery is not null and fb.recovery < 55 and coalesce(fb.energy, 100) < 50 then
    action := 'INSERT_DELOAD'; rules := rules || 'FATIGUE_DELOAD'::text; reason := 'accumulated fatigue';
  elsif fb.recovery is not null and fb.recovery < 60 then
    action := 'REDUCE_VOLUME'; vol_delta := -0.10;
    rules := rules || array['RECOVERY_PROTECTION', 'REPLACE_HIGH_FATIGUE']; reason := 'low recovery';
  elsif fb.completion_pct is not null and fb.completion_pct < 60 then
    action := 'REDUCE_COMPLEXITY'; rules := rules || 'ADHERENCE_SUPPORT'::text;
    escalate := true; reason := 'low adherence';
  elsif fb.recovery is not null and fb.recovery > 85
        and fb.completion_pct is not null and fb.completion_pct > 90 then
    action := 'INCREASE_VOLUME'; vol_delta := 0.05;
    rules := rules || 'PROGRESSIVE_OVERLOAD'::text; reason := 'recovered + high completion';
  end if;

  -- Coach approval matrix: coach-guided approves any change; injury needs
  -- approval in every mode; otherwise minor changes are automatic.
  needs_approval := (v_mode = 'coach_guided' and action <> 'CONTINUE')
                    or (rules && array['INJURY_ADAPTATION']);

  return jsonb_build_object(
    'week', p_week, 'action', action, 'volume_delta', vol_delta,
    'rules_triggered', to_jsonb(rules), 'escalate', escalate,
    'needs_approval', needs_approval, 'coaching_mode', coalesce(v_mode, 'unknown'),
    'affected_weeks', case when p_week < v_dur
        then jsonb_build_array(p_week + 1, v_dur) else jsonb_build_array() end,
    'reason', reason);
end;
$$;

-- ── 3/3 · predict_client_engine (095 body, renamed by 116) ─────────────────
create or replace function public.predict_client_engine(p_subject uuid, p_program uuid default null)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_prog uuid := p_program;
  v_dur int; v_done int; v_maxwk int;
  v_avg_comp numeric; v_avg_rec numeric; v_rec_first numeric; v_rec_last numeric;
  v_prs_recent int; v_pain_recent boolean; v_pain jsonb;
  v_start numeric; v_goal numeric; v_cur numeric; v_fitgoal text;
  need numeric; done numeric; progress numeric; pace_need numeric; pace_act numeric;
  remaining numeric; weeks_left numeric; finish date; confidence int;
  plateau text; injury_general text; adherence_churn text; rec_forecast numeric;
  alerts text[] := '{}';
begin
  if v_prog is null then
    select id into v_prog from workout_programs
      where coach_id is not null and id in (select program_id from weekly_feedback where subject_id = p_subject)
      order by created_at desc limit 1;
    if v_prog is null then
      select program_id into v_prog from weekly_feedback where subject_id = p_subject
        order by created_at desc limit 1;
    end if;
  end if;

  select (plan->>'duration_weeks')::int into v_dur from workout_programs where id = v_prog;
  v_dur := coalesce(v_dur, 12);

  select count(*), avg(completion_pct), avg(recovery), max(week)
    into v_done, v_avg_comp, v_avg_rec, v_maxwk
    from weekly_feedback where program_id = v_prog and subject_id = p_subject;
  v_done := coalesce(v_done, 0);
  if v_done = 0 then
    return jsonb_build_object('status','no_data','program_id',v_prog);
  end if;

  select recovery into v_rec_first from weekly_feedback
    where program_id = v_prog and subject_id = p_subject order by week asc limit 1;
  select recovery into v_rec_last from weekly_feedback
    where program_id = v_prog and subject_id = p_subject order by week desc limit 1;
  select coalesce(sum(prs),0) into v_prs_recent from weekly_feedback
    where program_id = v_prog and subject_id = p_subject and week > v_maxwk - 3;
  select bool_or(coalesce(jsonb_array_length(pain),0) > 0), (array_agg(pain order by week desc))[1]
    into v_pain_recent, v_pain
    from weekly_feedback where program_id = v_prog and subject_id = p_subject and week > v_maxwk - 2;

  select weight_kg, weight_goal_kg, fitness_goal into v_start, v_goal, v_fitgoal
    from user_profiles where id = p_subject;
  select bodyweight into v_cur from weekly_feedback
    where program_id = v_prog and subject_id = p_subject and bodyweight is not null
    order by week desc limit 1;
  v_cur := coalesce(v_cur, v_start);

  -- ── Goal Progress Engine (weight-based goals) ──
  if v_start is not null and v_goal is not null and v_start <> v_goal then
    need := v_goal - v_start;                 -- gain:+  loss:-
    done := v_cur - v_start;
    progress := case when need = 0 then 100
                     when (need * done) <= 0 then 0   -- wrong direction / none
                     else least(abs(done) / abs(need) * 100, 100) end;
    pace_need := need / v_dur;
    pace_act  := done / greatest(v_done, 1);
    remaining := need - done;
    weeks_left := case when pace_act = 0 or (pace_act * need) <= 0 then null
                       else remaining / pace_act end;
    finish := case when weeks_left is null then null
                   else current_date + (ceil(weeks_left) * 7)::int end;
    confidence := greatest(0, least(100, round(
        0.40 * least(case when pace_need = 0 then 1 else abs(pace_act / pace_need) end, 1.2) / 1.2 * 100
      + 0.30 * coalesce(v_avg_comp, 0)
      + 0.30 * coalesce(v_avg_rec, 0))::numeric));
  else
    progress := coalesce(v_avg_comp, 0);       -- non-weight goal → use adherence as proxy
    confidence := round((0.5 * coalesce(v_avg_comp,0) + 0.5 * coalesce(v_avg_rec,0))::numeric);
    finish := null;
  end if;

  -- ── Plateau ──
  plateau := case
    when v_done >= 3 and v_prs_recent = 0 and coalesce(v_avg_comp,0) > 85 then 'high'
    when v_done >= 3 and v_prs_recent = 0 then 'medium'
    else 'low' end;

  -- ── Injury risk ──
  injury_general := case when v_pain_recent then 'high'
                         when coalesce(v_avg_rec, 100) < 60 then 'medium' else 'low' end;

  -- ── Adherence / churn ──
  adherence_churn := case when coalesce(v_avg_comp,100) < 60 then 'high'
                          when coalesce(v_avg_comp,100) < 80 then 'medium' else 'low' end;

  -- ── Recovery forecast (linear extrapolation of the trend) ──
  rec_forecast := greatest(0, least(100,
    coalesce(v_rec_last, v_avg_rec, 70)
    + coalesce(v_rec_last - v_rec_first, 0) / greatest(v_done - 1, 1)));

  -- ── Deterministic alerts ──
  if plateau = 'high' then alerts := alerts || 'plateau_approaching'::text; end if;
  if coalesce(v_rec_last,100) < coalesce(v_rec_first,0) and coalesce(v_avg_rec,100) < 65 then
    alerts := alerts || 'recovery_declining'::text; end if;
  if injury_general = 'high' then alerts := alerts || 'high_injury_probability'::text; end if;
  if adherence_churn = 'high' then alerts := alerts || 'coach_followup_recommended'::text; end if;
  if confidence >= 90 and progress >= 60 then alerts := alerts || 'ahead_of_schedule'::text; end if;
  if progress >= 100 then alerts := alerts || 'goal_achieved_early'::text; end if;

  return jsonb_build_object(
    'status', 'ok', 'program_id', v_prog, 'engine_version', '1.0.0',
    'weeks_completed', v_done, 'duration_weeks', v_dur,
    'goal', jsonb_build_object(
      'fitness_goal', v_fitgoal, 'start', v_start, 'current', v_cur, 'target', v_goal,
      'progress_pct', round(progress), 'predicted_finish', finish, 'confidence', confidence),
    'plateau_risk', plateau,
    'injury_risk', jsonb_build_object('general', injury_general, 'areas', coalesce(v_pain, '[]'::jsonb)),
    'adherence', jsonb_build_object('avg_completion', round(coalesce(v_avg_comp,0)),
      'churn_risk', adherence_churn),
    'recovery', jsonb_build_object('avg', round(coalesce(v_avg_rec,0)),
      'forecast_next', round(rec_forecast),
      'trend', case when coalesce(v_rec_last,0) > coalesce(v_rec_first,0) then 'improving'
                    when coalesce(v_rec_last,0) < coalesce(v_rec_first,0) then 'declining' else 'stable' end),
    'alerts', to_jsonb(alerts));
end;
$$;

COMMIT;
