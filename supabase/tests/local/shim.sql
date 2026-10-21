-- ─────────────────────────────────────────────────────────────────────────────
-- CI-LOCAL SUPABASE PLATFORM SHIM — used ONLY by supabase/scripts/negative-control.sh.
--
-- A hosted Supabase project supplies a set of platform objects that the repo's
-- migrations reference but never create: the GoTrue `auth` schema, the storage
-- and vault schemas, the four PostgREST roles, pg_cron / pg_net, and the
-- `supabase_realtime` publication. A bare PostgreSQL cluster has none of them,
-- so a replay of 000-121 dies on the first reference.
--
-- This file creates exactly those objects and nothing else, so that the
-- committed migrations can be replayed UNMODIFIED. It is test scaffolding for an
-- ephemeral, runner-local database.
--
-- WHAT THIS FILE IS NOT:
--   * It is not a migration and is never applied to any environment.
--   * It does not describe QA or production. It is not evidence about either.
--   * It names no project, carries no credential and opens no network path.
--
-- Every object is created idempotently so the harness can rebuild repeatedly.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── PostgREST / GoTrue roles ────────────────────────────────────────────────
do $$ begin create role anon nologin noinherit;              exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin noinherit;     exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin noinherit bypassrls; exception when duplicate_object then null; end $$;
do $$ begin create role authenticator noinherit login;       exception when duplicate_object then null; end $$;
do $$ begin create role supabase_auth_admin noinherit;       exception when duplicate_object then null; end $$;
do $$ begin create role supabase_admin superuser;            exception when duplicate_object then null; end $$;
grant anon, authenticated, service_role to authenticator;

-- ── Platform schemas ────────────────────────────────────────────────────────
create schema if not exists auth authorization supabase_auth_admin;
create schema if not exists storage;
create schema if not exists extensions;
create schema if not exists vault;
create schema if not exists graphql_public;
create schema if not exists realtime;
create schema if not exists cron;
create schema if not exists net;
grant usage on schema auth, storage, extensions, vault to postgres, anon, authenticated, service_role;

create extension if not exists pgcrypto with schema public;
create extension if not exists "uuid-ossp" with schema public;

-- ── auth.users, in the GoTrue column shape the seeds insert into ────────────
create table if not exists auth.users (
  instance_id             uuid default '00000000-0000-0000-0000-000000000000',
  id                      uuid primary key default gen_random_uuid(),
  aud                     varchar(255) default 'authenticated',
  role                    varchar(255) default 'authenticated',
  email                   text unique,
  encrypted_password      text,
  email_confirmed_at      timestamptz,
  invited_at              timestamptz,
  confirmation_token      varchar(255) default '',
  confirmation_sent_at    timestamptz,
  recovery_token          varchar(255) default '',
  recovery_sent_at        timestamptz,
  email_change_token_new  varchar(255) default '',
  email_change            varchar(255) default '',
  email_change_sent_at    timestamptz,
  last_sign_in_at         timestamptz,
  raw_app_meta_data       jsonb default '{}'::jsonb,
  raw_user_meta_data      jsonb default '{}'::jsonb,
  is_super_admin          boolean,
  created_at              timestamptz default now(),
  updated_at              timestamptz default now(),
  phone                   text unique,
  phone_confirmed_at      timestamptz,
  confirmed_at            timestamptz,
  banned_until            timestamptz,
  deleted_at              timestamptz
);

-- ── The claim accessors every RLS policy in the tree depends on ─────────────
-- FIDELITY FIX. These three cast the GUC to jsonb BEFORE guarding it, so an
-- EMPTY-STRING `request.jwt.claims` raised `invalid input syntax for type json`
-- rather than returning NULL. `auth.jwt()` on the line below already guards
-- correctly -- nullif(...,'') OUTSIDE the cast -- and so does hosted Supabase,
-- whose auth.uid() is
--   coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
--            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
-- The empty string is reachable in ordinary use: a transaction-local set_config
-- reverts to '' rather than to unset, so any statement afterwards in the same
-- session hit the error. That made a correct migration look broken during the
-- P2 replay (V5 §77). The shim now matches both its own auth.jwt() and the
-- platform it stands in for. NO MIGRATION WAS CHANGED TO ACCOMMODATE THIS.
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub','')::uuid $$;
create or replace function auth.role() returns text language sql stable as
$$ select coalesce(nullif(nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'role',''),'anon') $$;
create or replace function auth.email() returns text language sql stable as
$$ select nullif(nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'email','') $$;
create or replace function auth.jwt() returns jsonb language sql stable as
$$ select coalesce(nullif(current_setting('request.jwt.claims', true),'')::jsonb,'{}'::jsonb) $$;

-- ── storage ─────────────────────────────────────────────────────────────────
create table if not exists storage.buckets (
  id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id), name text, owner uuid,
  metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[] language sql immutable as
$$ select string_to_array(name,'/') $$;

-- ── pg_cron surface. Migration 076 calls schedule/unschedule and reads cron.job. ──
create table if not exists cron.job (jobid bigserial primary key, schedule text, command text, jobname text);
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint
  language sql as $$ insert into cron.job(schedule,command,jobname) values (schedule,command,job_name) returning jobid $$;
create or replace function cron.schedule(schedule text, command text) returns bigint
  language sql as $$ insert into cron.job(schedule,command) values (schedule,command) returning jobid $$;
create or replace function cron.unschedule(job_name text) returns boolean
  language sql as $$ delete from cron.job where jobname = job_name returning true $$;

-- ── pg_net surface. No network is opened: http_post is inert by construction. ──
create or replace function net.http_post(url text, body jsonb default '{}'::jsonb,
  params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb,
  timeout_milliseconds int default 5000) returns bigint
  language sql as $$ select 1::bigint $$;

-- ── vault ───────────────────────────────────────────────────────────────────
create table if not exists vault.secrets (id uuid primary key default gen_random_uuid(),
  name text unique, secret text, created_at timestamptz default now());
create or replace view vault.decrypted_secrets as
  select id, name, secret as decrypted_secret, created_at from vault.secrets;

-- ── realtime publication and the migration ledger table ─────────────────────
do $$ begin create publication supabase_realtime; exception when duplicate_object then null; end $$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text primary key, name text, statements text[]);
