-- Migration 080: accountability timing
--
-- Learns each user's usual workout HOUR (UTC) and fires a contextual
-- accountability nudge ~1 hour before it, only for active users who haven't
-- trained yet today. Reproduces ai_detect_patterns (078) + the modal hour.
--
-- ENVIRONMENT SAFETY: the edge-function URL is resolved per project from the
-- Vault secret 'project_url' (see migration 076 for the one-time, per-project
-- setup). It is never hardcoded. The service_role key likewise stays in Vault
-- and is never exposed to Flutter/client code.

create or replace function public.ai_detect_patterns(p_uid uuid)
returns void language plpgsql security definer as $$
declare
  v_best int; v_worst int; v_best_day text; v_missed_day text;
  v_avg_min int; v_bf int; v_din int; v_hour int;
  dow text[] := array['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
begin
  with d as (
    select extract(dow from started_at)::int as dw, count(*) c
    from workout_sessions
    where user_id = p_uid and status = 'completed' and started_at > now() - interval '70 days'
    group by 1
  )
  select (select dw from d order by c desc, dw limit 1),
         (select dw from d order by c asc,  dw limit 1)
  into v_best, v_worst;

  select round(avg(duration_seconds) / 60.0)::int into v_avg_min
    from workout_sessions
    where user_id = p_uid and status = 'completed' and duration_seconds > 0
      and started_at > now() - interval '70 days';

  -- Modal workout hour (UTC).
  select h from (
    select extract(hour from started_at)::int h, count(*) c
    from workout_sessions
    where user_id = p_uid and status = 'completed' and started_at > now() - interval '70 days'
    group by 1 order by c desc, h limit 1
  ) m into v_hour;

  select count(*) filter (where meal_type = 'breakfast'),
         count(*) filter (where meal_type = 'dinner')
    into v_bf, v_din
    from nutrition_logs where user_id = p_uid and logged_at > now() - interval '30 days';

  v_best_day   := case when v_best  is not null then dow[v_best + 1] end;
  v_missed_day := case when v_worst is not null and v_worst <> coalesce(v_best, -1) then dow[v_worst + 1] end;

  insert into ai_profiles (user_id, behavioral_patterns)
  values (p_uid, jsonb_strip_nulls(jsonb_build_object(
    'best_adherence_day', v_best_day, 'missed_workout_day', v_missed_day,
    'average_workout_time', v_avg_min, 'usual_workout_hour', v_hour)))
  on conflict (user_id) do update
    set behavioral_patterns = jsonb_strip_nulls(jsonb_build_object(
          'best_adherence_day', v_best_day, 'missed_workout_day', v_missed_day,
          'average_workout_time', v_avg_min, 'usual_workout_hour', v_hour)),
        updated_at = now();

  delete from ai_memories where user_id = p_uid and kind = 'pattern';
  if v_best_day is not null and v_avg_min is not null then
    insert into ai_memories (user_id, kind, content, source) values
      (p_uid, 'pattern', 'Trains most consistently on ' || v_best_day || ' (~' || v_avg_min || ' min sessions)', 'inferred')
      on conflict (user_id, kind, content) do nothing;
  end if;
  if v_missed_day is not null then
    insert into ai_memories (user_id, kind, content, source) values
      (p_uid, 'pattern', 'Tends to miss ' || v_missed_day || ' workouts', 'inferred')
      on conflict (user_id, kind, content) do nothing;
  end if;
  if v_bf >= 5 and v_din <= greatest(1, v_bf / 3) then
    insert into ai_memories (user_id, kind, content, source) values
      (p_uid, 'pattern', 'Logs breakfast consistently but rarely logs dinner', 'inferred')
      on conflict (user_id, kind, content) do nothing;
  end if;
end;
$$;

-- Hourly: nudge active users ~1h before their usual workout hour, if untrained today.
create or replace function public.ai_cron_accountability()
returns void language plpgsql security definer
set search_path = public, extensions, vault as $$
declare
  v_key  text;
  v_base text;
  v_url  text;
  v_hr   int := extract(hour from now())::int;
  u record;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if v_key is null then
    raise notice 'ai_cron_accountability: vault secret "service_role_key" not set — skipping';
    return;
  end if;

  -- Environment safety: resolve THIS project's base URL from Vault (helper is
  -- defined in 076). Fails closed -- there is deliberately no hardcoded
  -- fallback, because the previous literal pointed at PRODUCTION and made any
  -- replayed QA/branch project POST to prod with a service_role token.
  v_base := public.project_base_url();
  if v_base is null then
    raise notice 'ai_cron_accountability: vault secret "project_url" not set — skipping';
    return;
  end if;
  v_url := v_base || '/functions/v1/ai-coaching-engine';

  for u in
    select p.user_id from ai_profiles p
    where (p.behavioral_patterns->>'usual_workout_hour')::int = v_hr + 1
      and exists (select 1 from workout_sessions ws
        where ws.user_id = p.user_id and ws.started_at > now() - interval '14 days')
      and not exists (select 1 from workout_sessions w2
        where w2.user_id = p.user_id and w2.status = 'completed' and w2.started_at::date = current_date)
  loop
    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      body    := jsonb_build_object('type', 'accountability', 'user_id', u.user_id));
  end loop;
end;
$$;

select cron.unschedule('ai-accountability') where exists (select 1 from cron.job where jobname = 'ai-accountability');
select cron.schedule('ai-accountability', '0 * * * *', $$ select public.ai_cron_accountability(); $$);
