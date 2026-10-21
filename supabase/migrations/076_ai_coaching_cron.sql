-- Migration 076: overnight AI coaching generation (pg_cron, active users only)
--
-- Generates daily briefs each morning and weekly reviews on Mondays for users
-- who were ACTIVE in the last 14 days (a workout session or a daily score), so
-- briefs are ready instantly when they open the app — without billing Claude for
-- inactive users.
--
-- ── ENVIRONMENT SAFETY ──────────────────────────────────────────────────────
-- This migration previously hardcoded the PRODUCTION project URL
-- (https://<prod-ref>.supabase.co/...). Replaying it into any non-production
-- project — QA, a branch, a local stack — silently created cron jobs that POST
-- to PRODUCTION edge functions with a service_role bearer token. Both the URL
-- and the key are now read from Vault at call time, so each project targets
-- ITSELF and nothing else.
--
-- Vault is used (not platform_settings) because platform_settings is readable by
-- every authenticated user, and because the service_role key must never be
-- ── STAGE B.3 CORRECTION (B2-6): created_at -> started_at ───────────────────
-- ai_cron_generate() selected `workout_sessions.created_at`. That column does
-- not exist and never has: 001 gives workout_sessions `started_at`, and the
-- workout work in 103-108 did not add a created_at. Every scheduled run raised
--     ERROR: column "created_at" does not exist
-- but only once Vault was configured -- with an empty Vault the function returns
-- at the secret check before it ever reaches the query, which is why it survived
-- review. Corrected in place below; the fail-closed contract is unchanged.
--
-- reachable from Flutter/client code. vault.decrypted_secrets is server-side
-- only; these functions are the sole readers.
--
-- ⚠️ ONE-TIME SETUP, PER PROJECT (run once in each of prod / QA, with that
--    project's OWN values — never paste production values into QA):
--      select vault.create_secret('https://<this-project-ref>.supabase.co', 'project_url');
--      select vault.create_secret('<THIS PROJECT SERVICE_ROLE_KEY>', 'service_role_key');
--
-- FAIL-CLOSED: if either secret is missing the functions log a notice and
-- return without making any HTTP call. There is deliberately NO default URL —
-- a freshly rebuilt project is inert until someone sets its own values, so a
-- forgotten setup step can never resolve to production.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Resolves THIS project's own Supabase base URL from Vault. Returns NULL when
-- unset so every caller can fail closed. Shared by 076 and 080.
create or replace function public.project_base_url()
returns text language plpgsql stable security definer
set search_path = public, extensions, vault as $$
declare
  v_url text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url';
  if v_url is null or btrim(v_url) = '' then
    return null;
  end if;
  return rtrim(btrim(v_url), '/');
end;
$$;

-- Infrastructure config: server-side callers only, never the client roles.
revoke all on function public.project_base_url() from public, anon, authenticated;

create or replace function public.ai_cron_generate(p_type text)
returns void language plpgsql security definer
set search_path = public, extensions, vault as $$
declare
  v_key  text;
  v_base text;
  v_url  text;
  u record;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if v_key is null then
    raise notice 'ai_cron_generate: vault secret "service_role_key" not set — skipping';
    return;
  end if;

  v_base := public.project_base_url();
  if v_base is null then
    raise notice 'ai_cron_generate: vault secret "project_url" not set — skipping';
    return;
  end if;
  v_url := v_base || '/functions/v1/ai-coaching-engine';

  for u in
    select id from (
      -- started_at, not created_at: workout_sessions has no created_at column in
      -- any migration (see the note at the top of this file).
      select distinct user_id as id from workout_sessions where started_at > now() - interval '14 days'
      union
      select distinct user_id from daily_scores where score_date > current_date - 14
    ) active where id is not null
  loop
    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      body    := jsonb_build_object('type', p_type, 'user_id', u.id));
  end loop;
end;
$$;

-- Daily briefs at 06:00 UTC; weekly reviews Monday 07:00 UTC. Reschedule-safe.
select cron.unschedule('ai-daily-briefs')   where exists (select 1 from cron.job where jobname = 'ai-daily-briefs');
select cron.unschedule('ai-weekly-reviews') where exists (select 1 from cron.job where jobname = 'ai-weekly-reviews');

select cron.schedule('ai-daily-briefs',   '0 6 * * *', $$ select public.ai_cron_generate('daily_insight'); $$);
select cron.schedule('ai-weekly-reviews', '0 7 * * 1', $$ select public.ai_cron_generate('weekly_review'); $$);
