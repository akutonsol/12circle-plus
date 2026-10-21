-- Wave 2A — security regressions carried forward after 116.
--
-- Scope:
--   1. Restore the authorization boundary accidentally removed from
--      materialize_program_week().
--   2. Guard ai_adjust_nutrition() against arbitrary subject mutation.
--
-- Deliberately out of scope:
--   * build_workout() — deterministic helper, no subject parameter.
--   * derive_parq_risk() — already correctly pinned.
--   * messages UPDATE policy — requires a separate contract decision.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Restore the authorized materialize_program_week wrapper.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.materialize_program_week(
  p_program_id uuid,
  p_week integer,
  p_context jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.can_act_on_program(p_program_id) THEN
    RAISE EXCEPTION 'not authorized for this program'
      USING ERRCODE = '42501';
  END IF;

  RETURN public.materialize_program_week_engine(
    p_program_id,
    p_week,
    p_context
  );
END;
$$;

REVOKE ALL ON FUNCTION public.materialize_program_week(uuid, integer, jsonb)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.materialize_program_week(uuid, integer, jsonb)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Guard ai_adjust_nutrition() against arbitrary subject mutation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ai_adjust_nutrition(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  p        user_profiles%rowtype;
  v_plan   client_nutrition_plans%rowtype;
  v_first  numeric; v_last numeric; v_weeks numeric; v_rate numeric;
  v_goal   text; v_delta int := 0; v_new int; v_protein int; v_fat int; v_carbs int; v_n int;
BEGIN
  IF NOT public.can_act_for(p_uid) THEN
    RAISE EXCEPTION 'not authorized for this subject'
      USING ERRCODE = '42501';
  END IF;

  select * into p from user_profiles where id = p_uid;
  if not found then return; end if;

  select * into v_plan from client_nutrition_plans
    where client_id = p_uid and is_active order by created_at desc limit 1;
  if not found then return; end if;

  select count(*) into v_n from weekly_checkins
    where user_id = p_uid and weight_kg is not null and created_at > now() - interval '35 days';
  if v_n < 2 then return; end if;

  select weight_kg into v_first from weekly_checkins
    where user_id = p_uid and weight_kg is not null and created_at > now() - interval '35 days'
    order by created_at asc limit 1;

  select weight_kg into v_last from weekly_checkins
    where user_id = p_uid and weight_kg is not null order by created_at desc limit 1;

  select greatest(extract(epoch from (max(created_at) - min(created_at))) / 604800.0, 1)
    into v_weeks from weekly_checkins
    where user_id = p_uid and weight_kg is not null and created_at > now() - interval '35 days';

  v_rate := (v_last - v_first) / v_weeks;

  v_goal := coalesce(p.fitness_goal, p.goal, 'general');

  if v_goal = 'lose_fat' then
    if v_rate > -0.2 then v_delta := -150; elsif v_rate < -1.0 then v_delta := 150; end if;
  elsif v_goal = 'build_muscle' then
    if v_rate < 0.1 then v_delta := 150; elsif v_rate > 0.5 then v_delta := -150; end if;
  elsif v_goal = 'body_recomp' then
    if v_rate > 0.3 then v_delta := -120; elsif v_rate < -0.5 then v_delta := 120; end if;
  end if;

  if v_delta = 0 then return; end if;

  v_new := greatest(1200, v_plan.calories_target + v_delta);
  if v_new = v_plan.calories_target then return; end if;

  v_protein := round(coalesce(p.weight_kg, 70) * 2.0);
  v_fat     := round(v_new * 0.25 / 9.0);
  v_carbs   := greatest(0, round((v_new - v_protein * 4 - v_fat * 9) / 4.0));

  update client_nutrition_plans
    set calories_target = v_new,
        protein_g = v_protein,
        carbs_g = v_carbs,
        fat_g = v_fat,
        notes = 'Auto-adjusted from your weight trend (' ||
          to_char(v_rate, 'FM990.0') || ' kg/wk).'
    where id = v_plan.id;

  insert into ai_insights (user_id, type, title, body, data)
  values (
    p_uid,
    'nutrition_adjustment',
    case when v_delta < 0 then 'Calories reduced' else 'Calories increased' end,
    'Your ' || to_char(v_rate, 'FM990.0') ||
      ' kg/week trend moved your target to ' || v_new ||
      ' kcal to keep you on pace for your goal.',
    jsonb_build_object(
      'delta_cal', v_delta,
      'new_calories', v_new,
      'rate_kg_wk', round(v_rate::numeric, 2)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ai_adjust_nutrition(uuid)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.ai_adjust_nutrition(uuid)
  TO service_role;

COMMIT;
