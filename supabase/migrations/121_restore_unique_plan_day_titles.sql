-- Migration 121: restore the unique day-title rule that migration 077 dropped.
--
-- ── What happened ───────────────────────────────────────────────────────────
--
-- Migration 052 ("give generated program days unique titles") added exactly one
-- behaviour to generate_client_plan(): when a training focus repeats inside a
-- split, the day titles are suffixed A/B/C, so a 3-day full-body split reads
-- "Full Body A / Full Body B / Full Body C" instead of "Full Body" three times.
-- Diffing the function bodies, 052 added four declarations (j, v_occ, v_total,
-- v_title) and one counting loop, and nothing else.
--
-- Migration 077 ("bias generate_client_plan() toward the AI coach's focus")
-- states in its own header that it "Reproduces 048 verbatim + the bias block".
-- It did — and 048 predates 052. So 077 silently reverted 052. Nothing in 077
-- depends on titles being ambiguous; the removal is collateral from branching
-- off the wrong base.
--
-- Observed live on QA before this migration — two self-generated programs, both
-- regressed:
--     211206c2…  3-day   "Full Body",  "Full Body",  "Full Body"
--     48099a62…  4-day   "Upper Body", "Lower Body", "Upper Body", "Lower Body"
-- The coach-authored seed program was unaffected (its titles are day-specific).
--
-- ── Why this is worth restoring ─────────────────────────────────────────────
--
-- 052's stated motivation was that session status was keyed by workout_title,
-- so starting one day marked all three in progress. **That defect is fixed
-- separately and better**: Phase 2 made programSessionStatusProvider key by
-- workout id, with the title only as a guarded pre-migration-103 fallback
-- (`sessionStatusFor`). This migration does NOT reintroduce title-based
-- identity and nothing here depends on titles being unique.
--
-- What remains is a legibility contract: a client looking at their week must be
-- able to tell Monday's session from Thursday's. Three cards all reading
-- "Full Body" is a data-generation defect in its own right, independent of how
-- status is keyed. That is what this restores.
--
-- ── One deliberate improvement over 052 ─────────────────────────────────────
--
-- 077's bias block rewrites the LAST day of the split
-- (`v_split[v_days] := v_focus_day`), which can manufacture duplicates 052
-- never saw — an upper/lower/upper/lower week biased toward "upper" becomes
-- upper/lower/upper/upper, i.e. "Upper Body" three times. The title rule is
-- therefore applied to the split AS FINALLY SET, after the bias. That is 052's
-- own rule applied to 077's own data; no new naming scheme is introduced.

-- ── 1. One authority for the rule ───────────────────────────────────────────
--
-- Extracted from 052's inline loop so the generator, the backfill below and the
-- regression suite all exercise the SAME implementation. A rule that lives in
-- three copies is a rule that drifts again.
CREATE OR REPLACE FUNCTION public.plan_day_titles(p_split text[])
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_out   text[] := '{}';
  v_days  int := coalesce(array_length(p_split, 1), 0);
  i       int;
  j       int;
  v_occ   int;
  v_total int;
  v_title text;
BEGIN
  FOR i IN 1 .. v_days LOOP
    -- How many days with this focus precede-or-are this one, and how many in
    -- total. A focus that appears once keeps its plain title.
    v_occ := 0;
    FOR j IN 1 .. i LOOP
      IF p_split[j] = p_split[i] THEN v_occ := v_occ + 1; END IF;
    END LOOP;
    v_total := 0;
    FOR j IN 1 .. v_days LOOP
      IF p_split[j] = p_split[i] THEN v_total := v_total + 1; END IF;
    END LOOP;
    v_title := public._plan_day_title(p_split[i]);
    IF v_total > 1 THEN
      v_title := v_title || ' ' || chr(64 + v_occ);
    END IF;
    v_out := v_out || v_title;
  END LOOP;
  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION public.plan_day_titles(text[]) IS
  'Day titles for a generated split, suffixed A/B/C where a focus repeats '
  '(migration 052''s rule, restored by 121). Titles are a LABEL, never an '
  'identity — sessions are keyed by workout id.';

REVOKE ALL ON FUNCTION public.plan_day_titles(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_day_titles(text[]) TO authenticated;

-- ── 2. The generator: 077's body, with 052's rule put back ──────────────────
--
-- Everything except the day-title loop is 077 verbatim: the same nutrition
-- maths, the same habit set, the same supersede-and-delete ordering from 048,
-- and the same focus-bias block. Only the titling changed.
CREATE OR REPLACE FUNCTION public.generate_client_plan()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
declare
  p           user_profiles%rowtype;
  v_uid       uuid := auth.uid();
  v_age       int;
  v_mult      numeric;
  v_bmr       numeric;
  v_cal       int;
  v_protein   int;
  v_fat       int;
  v_carbs     int;
  v_water     int;
  v_days      int;
  v_is_home   boolean;
  v_reps      int;
  v_rest      int;
  v_prog      uuid;
  v_old_progs uuid[];
  v_split     text[];
  v_daynames  text[];
  v_titles    text[];
  v_focus     text;
  v_focus_day text;
  i           int;
begin
  if v_uid is null then return; end if;
  select * into p from user_profiles where id = v_uid;
  if not found then return; end if;

  -- ── Nutrition targets (Mifflin–St Jeor → TDEE → goal adjustment) ──
  v_age := greatest(16, extract(year from age(coalesce(p.date_of_birth, date '1995-01-01')))::int);
  v_mult := case
    when p.activity_level ilike '%sedentary%' then 1.2
    when p.activity_level ilike '%light%'     then 1.375
    when p.activity_level ilike '%moder%'     then 1.55
    when p.activity_level ilike '%very%'      then 1.725
    when p.activity_level ilike '%active%'    then 1.6
    else 1.45 end;
  v_bmr := 10 * coalesce(p.weight_kg, 70) + 6.25 * coalesce(p.height_cm, 170)
           - 5 * v_age + case when p.gender ilike 'f%' then -161 else 5 end;
  v_cal := round(v_bmr * v_mult + case
      when p.fitness_goal = 'lose_fat'    then -500
      when p.fitness_goal = 'build_muscle' then 300
      when p.fitness_goal = 'body_recomp'  then -200
      else 0 end);
  v_cal     := greatest(v_cal, 1200);
  v_protein := round(coalesce(p.weight_kg, 70) * 2.0);
  v_fat     := round(v_cal * 0.25 / 9.0);
  v_carbs   := greatest(0, round((v_cal - v_protein * 4 - v_fat * 9) / 4.0));
  v_water   := round(coalesce(p.weight_kg, 70) * 2.20462 * 0.5);

  update client_nutrition_plans set is_active=false
    where client_id=v_uid and is_active;
  insert into client_nutrition_plans
    (client_id, coach_id, calories_target, protein_g, carbs_g, fat_g, water_target_oz, notes, is_active)
  values (v_uid, null, v_cal, v_protein, v_carbs, v_fat, v_water,
          'Auto-generated from your onboarding answers.', true);

  update client_habits set is_active=false
    where client_id=v_uid and is_active;
  insert into client_habits (client_id, coach_id, name, emoji, category, target_value, unit, is_active) values
    (v_uid, null, 'Drink Water',    '💧', 'health',      coalesce(v_water, 64), 'oz',    true),
    (v_uid, null, 'Hit Step Goal',  '🚶', 'fitness',     8000,                  'steps', true),
    (v_uid, null, 'Sleep 7+ Hours', '😴', 'recovery',    7,                     'hours', true),
    (v_uid, null, 'Log Your Meals', '🍽️', 'nutrition',   3,                     'meals', true),
    (v_uid, null, 'Daily Mobility', '🧘', 'mindfulness', 10,                    'min',   true);

  -- ── Workout program ──
  update workout_program_assignments set status='superseded'
    where client_id=v_uid and status='active' and coach_id is not null;
  select array_agg(program_id) into v_old_progs
    from workout_program_assignments where client_id=v_uid and coach_id is null;
  delete from workout_program_assignments where client_id=v_uid and coach_id is null;
  if v_old_progs is not null then
    delete from workout_programs where id = any(v_old_progs) and coach_id is null;
  end if;

  v_days    := least(greatest(coalesce(p.training_days_per_week, 3), 2), 6);
  v_is_home := coalesce(p.training_location, '') ilike '%home%';
  v_reps    := case when p.fitness_goal = 'build_muscle' then 10
                    when p.fitness_goal in ('lose_fat','body_recomp') then 13 else 12 end;
  v_rest    := case when p.fitness_goal = 'build_muscle' then 90
                    when p.fitness_goal in ('lose_fat','body_recomp') then 60 else 75 end;

  if v_days <= 3 then
    v_split := array['full_body','full_body','full_body'];
    v_daynames := array['Monday','Wednesday','Friday'];
  elsif v_days = 4 then
    v_split := array['upper','lower','upper','lower'];
    v_daynames := array['Monday','Tuesday','Thursday','Friday'];
  elsif v_days = 5 then
    v_split := array['push','pull','legs','upper','lower'];
    v_daynames := array['Monday','Tuesday','Wednesday','Thursday','Friday'];
  else
    v_split := array['push','pull','legs','push','pull','legs'];
    v_daynames := array['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
  end if;

  -- ── Bias the final day toward the AI coach's focus, if any (077) ──
  v_focus := null;
  if to_regclass('public.ai_profiles') is not null then
    select lower(coalesce(goals->>'secondary_goal','')) into v_focus from ai_profiles where user_id = v_uid;
  end if;
  if (v_focus is null or v_focus = '') and to_regclass('public.ai_insights') is not null then
    select lower(coalesce(data->>'focus','')) into v_focus
      from ai_insights where user_id = v_uid and type = 'daily_insight'
      order by for_date desc limit 1;
  end if;
  v_focus_day := case
    when v_focus ~ '(lower|glute|leg|quad|hamstring|calf)'                then 'lower'
    when v_focus ~ '(upper|chest|back|arm|shoulder|bicep|tricep)'         then 'upper'
    when v_focus ~ 'push'                                                 then 'push'
    when v_focus ~ 'pull'                                                 then 'pull'
    when v_focus ~ '(full|condition|athletic|fat)'                        then 'full_body'
    else null end;
  if v_focus_day is not null then
    v_split[v_days] := v_focus_day;
  end if;

  -- ── Day titles (052's rule), computed from the split AS FINALLY SET ──
  -- After the bias, so a duplicate the bias itself created is suffixed too.
  v_titles := public.plan_day_titles(v_split);

  insert into workout_programs (coach_id, name, description, goal, difficulty, duration_weeks, is_template)
  values (null,
    initcap(replace(coalesce(p.fitness_goal, 'general'), '_', ' ')) || ' Program',
    'Auto-generated ' || v_days || '-day program from your onboarding answers'
      || case when v_focus_day is not null then ', with a ' || v_focus_day || ' emphasis from your coach.' else '.' end,
    coalesce(p.fitness_goal, 'general'),
    coalesce(p.experience_level, 'intermediate'),
    12, false)
  returning id into v_prog;

  for i in 1 .. v_days loop
    insert into program_workouts
      (program_id, week_number, day_of_week, title, description, estimated_minutes, exercises, sort_order)
    values (v_prog, 1, v_daynames[i], v_titles[i],
      'Generated from your onboarding answers.', 45,
      public._plan_day_exercises(v_split[i], v_is_home, v_reps, v_rest), i);
  end loop;

  insert into workout_program_assignments (program_id, client_id, coach_id, current_week, status)
  values (v_prog, v_uid, null, 1, 'active');
end;
$$;

GRANT EXECUTE ON FUNCTION public.generate_client_plan() TO authenticated;

-- ── 3. Repair the programs 077 already generated ────────────────────────────
--
-- Scoped to SELF-GENERATED programs (coach_id IS NULL): a coach's titles are
-- theirs to choose and are never rewritten.
--
-- The generator groups by training focus; `_plan_day_title` maps each focus to a
-- distinct title, so grouping the stored rows by title within a program (ordered
-- by sort_order) reproduces exactly what the generator would have produced.
--
-- `workout_sessions.workout_title` is deliberately NOT rewritten. That column
-- records what the client actually trained and is history; renaming it would
-- edit the past. The consequence is narrow and acceptable: a pre-migration-103
-- session (no workout_id) that fell back to matching by title will no longer
-- match a renamed day. Sessions written since 103 carry the id and are keyed by
-- it, which is the identity path Phase 2 established.
WITH numbered AS (
  SELECT pw.id,
         pw.title,
         count(*)  OVER (PARTITION BY pw.program_id, pw.title) AS total,
         row_number() OVER (PARTITION BY pw.program_id, pw.title
                            ORDER BY pw.sort_order, pw.id)     AS occ
    FROM public.program_workouts pw
    JOIN public.workout_programs p ON p.id = pw.program_id
   WHERE p.coach_id IS NULL
)
UPDATE public.program_workouts pw
   SET title = n.title || ' ' || chr(64 + n.occ::int)
  FROM numbered n
 WHERE pw.id = n.id
   AND n.total > 1
   AND n.occ <= 26;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (
    SELECT pw.program_id
      FROM public.program_workouts pw
      JOIN public.workout_programs p ON p.id = pw.program_id
     WHERE p.coach_id IS NULL
     GROUP BY pw.program_id, pw.title
    HAVING count(*) > 1) d;
  IF n > 0 THEN
    RAISE WARNING 'migration 121: % self-generated program/title group(s) are '
      'still duplicated after the backfill (more than 26 repeats?).', n;
  END IF;
END;
$$;

COMMENT ON COLUMN public.program_workouts.title IS
  'Human-readable day label. NEVER an identity — a session names its workout by '
  'program_workouts.id (migration 103). Generated days are suffixed A/B/C where '
  'a focus repeats (migration 052, restored by 121) so a client can tell their '
  'training days apart.';
