-- 123_forward_in_place_corrections.sql
--
-- W1-T2 · ENV-2 (LRE-04, P0) — the forward carry for the fifteen migrations
-- that were corrected IN PLACE after they had already been applied.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHY THIS FILE EXISTS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Fifteen historical migrations were edited in place rather than corrected by a
-- forward migration: 001 002 003 009 076 080 083 084 086 087 090 091 096 097
-- 102. An in-place edit fixes a from-empty replay and does NOTHING for an
-- environment that already ran the original, because that migration never runs
-- there again. The enumeration input for this file is `git show 99492df`, the
-- custody commit that isolated those fifteen diffs for exactly this purpose.
--
-- Most of the fifteen turn out to need nothing here, and saying so precisely is
-- half the point of this migration. The per-file disposition is §0 below.
--
-- IDEMPOTENT AND REPLAY-SAFE. Every statement is CREATE OR REPLACE or REVOKE;
-- running this file twice produces the same end state, and running it against a
-- database that already has the corrected definitions is a no-op in effect.
--
-- NO ENVIRONMENT WAS CONTACTED IN AUTHORING THIS FILE. It has not been applied
-- anywhere. QA application is a separately authorized step that follows W1-T3.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- §0. DISPOSITION OF ALL FIFTEEN — what is carried here, and what is not
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CARRIED BY THIS FILE
--
--   076, 080  B2-6 and the environment-safety rewrite. Migration 111 §B2-6
--             states the case verbatim: "NOT handled here ... an environment
--             that already applied the OLD 076 does not pick the fix up by
--             replaying ... Any other environment needs the corrected function
--             applied explicitly as part of its own rollout." This file is that
--             explicit application. Two distinct defects travel together in
--             these two functions and neither can be carried without the other:
--               * the hardcoded PRODUCTION project URL, which made any replayed
--                 QA/branch project POST to production Edge Functions with a
--                 service_role bearer (§1, §2, §3); and
--               * ai_cron_generate() selecting workout_sessions.created_at, a
--                 column no migration creates, which raises on every scheduled
--                 run once Vault is configured (§2).
--
-- ALREADY CARRIED FORWARD BY MIGRATION 111 — nothing to repeat here
--
--   003       B2-3. The nutrition_logs and notifications policies 003 could not
--             create are re-asserted by 111, in their post-100 (tightened) form.
--             Re-emitting them here would risk re-widening what 100 narrowed.
--   096       B2-5. The communications index on the column that actually exists
--             (generated_at, not created_at) is created by 111.
--
-- NOTHING TO CARRY — the edit changes no persistent state
--
--   001, 002  A leading `SET search_path = public, extensions` so that an
--             unqualified gen_random_bytes() resolves during replay. Session-
--             scoped by construction: it changes no database, role or object
--             configuration, and the stored column DEFAULT binds to
--             extensions.gen_random_bytes by OID either way.
--   009       A one-time repair of legacy 'pending' relationship rows, guarded
--             on a column migration 010 adds later. 111 §B2-4 records the same
--             conclusion: an environment that already ran it has the repair, a
--             freshly built one has nothing to repair.
--
-- DELIBERATELY NOT CARRIED — and these need an owner decision, not a migration
--
--   083, 084, 086, 087, 090, 091, 097
--             B2-2. These were written against `exercises`, which migration 058
--             made a VIEW over custom_exercises. A view cannot take ADD COLUMN,
--             ADD CONSTRAINT, CREATE INDEX or a FOREIGN KEY reference, so every
--             one of them aborted and, per their own headers and registry §9
--             exposure 2, NONE has ever applied in any environment. Their
--             in-place correction retargets the relation to custom_exercises.
--
--             Their delta is therefore not a small semantic difference — it is
--             seven whole migrations' worth of schema (the content pipeline,
--             the certification views, exercise_intelligence, the per-attribute
--             review tables, coach_exercise_media). Carrying that here is
--             refused for three specific reasons:
--
--               1. SECURITY. Those files define resolve_exercise_media,
--                  intelligence_stats, exercise_content_stats,
--                  intelligence_review_queue, attribute_review_state,
--                  intelligence_low_confidence and others that migrations 116
--                  and 117 have SINCE renamed to *_engine and placed behind
--                  can_act_for / require_content_editor wrappers. Re-emitting
--                  the 083/087/090/091/097 bodies here would strip those
--                  wrappers exactly as migration 119 stripped
--                  materialize_program_week's — a fresh instance of F-J-01, the
--                  open regression this programme is in Wave 2 to close. The
--                  I-MIG-03 durability guard flags precisely this, and it is
--                  fatal for an unrecorded strip.
--               2. STATE. Whether those objects exist differs per environment
--                  (QA was rebuilt from empty with the corrected files;
--                  production ran the originals and has none of them), and
--                  authoring a convergent forward migration for objects whose
--                  live shape cannot be inspected would be guesswork. No QA or
--                  production request is permitted in this task, correctly.
--               3. SCOPE. Registry §9 exposure 2 already records this as the
--                  largest single production/QA schema divergence and files it
--                  as an input to the rollout plan — explicitly "not
--                  authorization to act". It is a distinct, ownable task with
--                  its own review, not a rider on a custody delta.
--
--   102       Its in-place edit ADDED shares_conversation_with() and the
--             conversation_participant_profiles view. QA already has them (the
--             live Phase 1 suite reads that view successfully), and migration
--             102 must NOT reach production until every beta build reads
--             display names from public_profiles — its own header and registry
--             §9 exposure 5 both say so. Carrying it forward here would push a
--             deliberately withheld migration into the one environment that is
--             deliberately withholding it.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT THIS FILE IS NOT
-- ═══════════════════════════════════════════════════════════════════════════
--
-- It does NOT remediate F-J-01 / SEC-R1. materialize_program_week's stripped
-- can_act_on_program wrapper is Wave 2 task 2A's migration 124, and this file
-- must not pre-empt it: the numbering is assigned in MASTER_REMEDIATION_WAVES
-- §0.2 and 124 is the only migration authorized to touch that function.
--
-- It redefines three functions and grants nothing. CREATE OR REPLACE preserves
-- ACLs and ownership, so no function's EXECUTE posture is widened by this file.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ---------------------------------------------------------------------------
-- §1. project_base_url() — introduced by 076's in-place correction.
--
-- Resolves THIS project's own Supabase base URL from Vault, and returns NULL
-- when the secret is unset so every caller can fail closed. There is
-- deliberately no default: a forgotten setup step must never resolve to
-- production. Body transcribed from the corrected 076, not re-derived.
-- ---------------------------------------------------------------------------

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
-- This REVOKE is part of 076's in-place delta and is carried verbatim.
--
-- NOTE FOR REVIEW, not resolved here: migration 116's Class-B allowlist names
-- `project_base_url`, so on a from-empty replay 116 re-grants EXECUTE to
-- `authenticated` after 076 revoked it. The two migrations disagree. This file
-- carries 076's stated intent (the more restrictive of the two, and the one no
-- client path depends on — the only callers are the two SECURITY DEFINER cron
-- functions below). Whether 116's allowlist entry should be removed is a
-- separate decision and belongs to a separate migration.
revoke all on function public.project_base_url() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- §2. ai_cron_generate(text) — 076's in-place correction, both halves.
--
--   * the hardcoded production URL is gone; the target is resolved per project
--     from Vault and the function returns without an HTTP call when unset;
--   * workout_sessions.started_at replaces created_at, a column that exists in
--     no migration and raised on every scheduled run once Vault was configured.
--
-- Body transcribed from the corrected 076. SECURITY DEFINER and the pinned
-- search_path are reproduced exactly: CREATE OR REPLACE does not preserve
-- proconfig, so omitting the SET clause here would unpin the search_path — the
-- I-MIG-03 class defect.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- §3. ai_cron_accountability() — 080's in-place correction.
--
-- The same hardcoded production URL, in the second of the two cron functions.
-- Body transcribed from the corrected 080, SECURITY DEFINER and pinned
-- search_path reproduced exactly, for the same reason as §2.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- §4. Cron schedules are deliberately untouched.
--
-- 076 and 080 schedule ai-daily-briefs, ai-weekly-reviews and the
-- accountability job through pg_cron. Those jobs invoke these functions by
-- name, so replacing the bodies above is sufficient and re-scheduling would
-- change job identity for no gain. Verifying that a scheduled run targets the
-- QA host and not production is a live assertion against cron.job_run_details,
-- and it belongs to the wave that turns the crons on — MASTER_REMEDIATION_WAVES
-- calls it "the single most important production-safety check in the
-- programme" and places it at 5.9.
-- ---------------------------------------------------------------------------
