-- OD-QAX-2 / OD-14 regression, run on the LOCAL REPLAY only (loopback scratch DB).
--
--   Q-A5 (docs/V5_DELEGATED_DETERMINATIONS_2026-10-21.md section 4.1) and the
--   per-table criteria of section 4.2. Migrations 184 and 185.
--
-- Runs inside ONE transaction that is always ROLLED BACK. Never applied to QA or
-- production -- see od_qax2_od14_replay.sh, which refuses any non-loopback target.
--
-- WHAT MAKES THIS DIFFERENT FROM THE QA-EXHAUSTION PROBES. Those probes count ANY
-- exception as "refused", so a malformed INSERT passes as a denial. Here a denial
-- passes ONLY on SQLSTATE 42501, and every denied statement has a POSITIVE
-- CONTROL: the identical statement shape succeeds for an ACTIVE coach. A test
-- that cannot tell "forbidden" from "broken" proves nothing.
--
-- Output: one `PASS|id|detail` or `FAIL|id|detail` line per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;

-- Run a statement; report the SQLSTATE, or 'ok'. Any statement that fails for a
-- reason OTHER than 42501 is reported as that reason, so it cannot masquerade as a denial.
create function pg_temp.attempt(stmt text) returns text language plpgsql as $$
begin execute stmt; return 'ok'; exception when others then return sqlstate; end $$;
grant execute on function pg_temp.attempt(text) to authenticated;

-- Fixtures ------------------------------------------------------------------
-- C client (victim) · A ACTIVE coach · P PENDING coach · X CANCELLED coach
-- S ordinary user with no relationship · T a coach PROFILE with no relationship
insert into auth.users(id,email) values
  ('c0000000-0000-0000-0000-00000000000c','odq-client@local'),
  ('a0000000-0000-0000-0000-00000000000a','odq-active@local'),
  ('b0000000-0000-0000-0000-00000000000b','odq-pending@local'),
  ('d0000000-0000-0000-0000-00000000000d','odq-cancelled@local'),
  ('e0000000-0000-0000-0000-00000000000e','odq-stranger@local'),
  ('f0000000-0000-0000-0000-00000000000f','odq-coachprofile@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in
  ('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b',
   'd0000000-0000-0000-0000-00000000000d','f0000000-0000-0000-0000-00000000000f');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('a0000000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-00000000000c','active','client'),
  ('b0000000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-00000000000c','pending','coach'),
  ('d0000000-0000-0000-0000-00000000000d','c0000000-0000-0000-0000-00000000000c','cancelled','client');
-- The victim's real active plan, authored by the ACTIVE coach.
insert into public.client_nutrition_plans(client_id,coach_id,calories_target,protein_g,carbs_g,fat_g,is_active,notes)
  values ('c0000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-00000000000a',2200,150,220,70,true,'odq real plan');
-- A programme the active coach owns, for the assignment-table statement.
insert into public.workout_programs(id,coach_id,name)
  values ('10000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','odq program');
-- Pre-existing rows authored by the CANCELLED coach, for the "preserved, not mutated" criterion.
insert into public.client_habits(client_id,coach_id,name)
  values ('c0000000-0000-0000-0000-00000000000c','d0000000-0000-0000-0000-00000000000d','odq legacy habit');

-- ===========================================================================
-- Q-A5 · assign_nutrition_plan
-- ===========================================================================
create function pg_temp.plan_call() returns text language sql as $$
  select pg_temp.attempt($q$select public.assign_nutrition_plan('c0000000-0000-0000-0000-00000000000c'::uuid,800,10,10,10,null,'odq attempt')$q$) $$;
grant execute on function pg_temp.plan_call() to authenticated;

-- Capture the exact message of each refusal so we can assert there is ONE.
create temp table refusal(who text, state text, msg text);
grant all on refusal to authenticated;
create function pg_temp.plan_refusal(who text) returns void language plpgsql as $$
begin
  perform public.assign_nutrition_plan('c0000000-0000-0000-0000-00000000000c'::uuid,800,10,10,10,null,'odq attempt');
  insert into refusal values (who,'ok','');
exception when others then insert into refusal values (who, sqlstate, sqlerrm); end $$;
grant execute on function pg_temp.plan_refusal(text) to authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    ('stranger',        'e0000000-0000-0000-0000-00000000000e'),
    ('coach-profile',   'f0000000-0000-0000-0000-00000000000f'),
    ('pending',         'b0000000-0000-0000-0000-00000000000b'),
    ('cancelled',       'd0000000-0000-0000-0000-00000000000d'),
    ('client-self',     'c0000000-0000-0000-0000-00000000000c')
  ) v(who,uid) loop
    perform pg_temp.as_user(r.uid::uuid);
    set local role authenticated;
    perform pg_temp.plan_refusal(r.who);
    reset role;
  end loop;
end $$;

insert into res select 'QA-1 refused with 42501 for every non-active caller',
  bool_and(state='42501'), string_agg(who||'='||state, ', ') from refusal;
insert into res select 'QA-2 ONE refusal message for every reason (no oracle)',
  count(distinct msg)=1, 'distinct messages: '||count(distinct msg)||' ('||min(msg)||')' from refusal;
insert into res select 'QA-3 refused calls changed nothing: the victim''s real plan is still the one active plan',
  count(*)=1 and bool_and(notes='odq real plan'), 'active plans: '||count(*)
  from public.client_nutrition_plans where client_id='c0000000-0000-0000-0000-00000000000c' and is_active;

-- Unauthenticated: no claims at all.
select set_config('request.jwt.claims','',true);
set local role authenticated;
insert into res select 'QA-4 unauthenticated caller refused 42501', pg_temp.plan_call()='42501', pg_temp.plan_call();
reset role;

-- POSITIVE CONTROL: the ACTIVE coach still assigns.
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a');
set local role authenticated;
insert into res select 'QA-5 POSITIVE CONTROL: an active coach still assigns', pg_temp.plan_call()='ok', pg_temp.plan_call();
reset role;
insert into res select 'QA-6 ...and the new plan superseded the old: exactly one active, and it is the new one',
  count(*)=1 and bool_and(notes='odq attempt'), 'active plans: '||count(*)||' notes='||coalesce(min(notes),'-')
  from public.client_nutrition_plans where client_id='c0000000-0000-0000-0000-00000000000c' and is_active;

-- Function posture preserved (the Function Replacement Rule).
insert into res select 'QA-7 search_path pin preserved',
  coalesce(array_to_string(p.proconfig,',') ilike '%search_path=public%','f') , coalesce(array_to_string(p.proconfig,','),'NO proconfig')
  from pg_proc p where p.oid='public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)'::regprocedure;
insert into res select 'QA-8 grants preserved: authenticated yes, anon no, PUBLIC no',
  has_function_privilege('authenticated','public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)','execute')
  and not has_function_privilege('anon','public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)','execute'),
  'authenticated='||has_function_privilege('authenticated','public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)','execute')
  ||' anon='||has_function_privilege('anon','public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)','execute');
insert into res select 'QA-9 COMMENT preserved and names the decision',
  obj_description('public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)'::regprocedure,'pg_proc') like '%OD-QAX-2%',
  left(obj_description('public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)'::regprocedure,'pg_proc'),60);

-- ===========================================================================
-- OD-14 · the six tables. Same statement shape for every actor, so a denial is
-- distinguishable from a broken statement: the active coach must succeed.
-- ===========================================================================
create temp table stmts(tbl text, tmpl text);
-- :coach is substituted per actor; the client is always the victim.
insert into stmts values
 ('client_habits',  $q$insert into public.client_habits(client_id,coach_id,name) values ('c0000000-0000-0000-0000-00000000000c',':coach','odq')$q$),
 ('action_items',   $q$insert into public.action_items(client_id,coach_id,title) values ('c0000000-0000-0000-0000-00000000000c',':coach','odq')$q$),
 ('coaching_calls', $q$insert into public.coaching_calls(coach_id,client_id,scheduled_at) values (':coach','c0000000-0000-0000-0000-00000000000c',now())$q$),
 ('coach_video_responses', $q$insert into public.coach_video_responses(coach_id,client_id) values (':coach','c0000000-0000-0000-0000-00000000000c')$q$),
 ('client_nutrition_plans', $q$insert into public.client_nutrition_plans(client_id,coach_id,calories_target,is_active) values ('c0000000-0000-0000-0000-00000000000c',':coach',600,false)$q$),
 ('workout_program_assignments', $q$insert into public.workout_program_assignments(program_id,client_id,coach_id) values ('10000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-00000000000c',':coach')$q$);
grant all on stmts to authenticated;

create function pg_temp.write_as(actor_label text, uid text) returns void language plpgsql as $$
declare s record; st text;
begin
  for s in select * from stmts loop
    st := pg_temp.attempt(replace(s.tmpl, ':coach', uid));
    insert into res values (
      'OD14 '||actor_label||' -> '||s.tbl,
      case when actor_label = 'ACTIVE coach' then st = 'ok' else st = '42501' end,
      'sqlstate '||st);
  end loop;
end $$;
grant execute on function pg_temp.write_as(text,text) to authenticated;

select pg_temp.as_user('e0000000-0000-0000-0000-00000000000e'); set local role authenticated;
select pg_temp.write_as('stranger user',   'e0000000-0000-0000-0000-00000000000e'); reset role;
select pg_temp.as_user('f0000000-0000-0000-0000-00000000000f'); set local role authenticated;
select pg_temp.write_as('coach profile, no relationship', 'f0000000-0000-0000-0000-00000000000f'); reset role;
select pg_temp.as_user('b0000000-0000-0000-0000-00000000000b'); set local role authenticated;
select pg_temp.write_as('PENDING coach',   'b0000000-0000-0000-0000-00000000000b'); reset role;
select pg_temp.as_user('d0000000-0000-0000-0000-00000000000d'); set local role authenticated;
select pg_temp.write_as('CANCELLED coach', 'd0000000-0000-0000-0000-00000000000d'); reset role;
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a'); set local role authenticated;
select pg_temp.write_as('ACTIVE coach',    'a0000000-0000-0000-0000-00000000000a'); reset role;

-- The client keeps access to rows that name them.
select pg_temp.as_user('c0000000-0000-0000-0000-00000000000c'); set local role authenticated;
insert into res select 'OD14 client still sees the habit authored for them (including by a cancelled coach)',
  count(*)>=1, 'rows: '||count(*) from public.client_habits where client_id='c0000000-0000-0000-0000-00000000000c';
insert into res select 'OD14 client still writes their own habit',
  pg_temp.attempt($q$insert into public.client_habits(client_id,coach_id,name) values ('c0000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-00000000000a','odq self')$q$)='ok',
  'client-side arm intact';
reset role;

-- Existing rows are PRESERVED, NOT MUTATED, and stay READABLE by their authoring coach;
-- but that coach can no longer change or delete them.
select pg_temp.as_user('d0000000-0000-0000-0000-00000000000d'); set local role authenticated;
insert into res select 'OD14 cancelled coach can still READ the habit they authored (preserved, not hidden)',
  count(*)=1, 'rows: '||count(*) from public.client_habits where name='odq legacy habit';
with u as (update public.client_habits set name='odq tampered' where name='odq legacy habit' returning 1)
insert into res select 'OD14 cancelled coach cannot UPDATE it (0 rows)', count(*)=0, 'updated: '||count(*) from u;
with d as (delete from public.client_habits where name='odq legacy habit' returning 1)
insert into res select 'OD14 cancelled coach cannot DELETE it (0 rows)', count(*)=0, 'deleted: '||count(*) from d;
reset role;
insert into res select 'OD14 the legacy row is byte-for-byte untouched',
  count(*)=1, 'rows named "odq legacy habit": '||count(*) from public.client_habits where name='odq legacy habit';

-- A stranger reads none of it.
select pg_temp.as_user('e0000000-0000-0000-0000-00000000000e'); set local role authenticated;
insert into res select 'OD14 a stranger reads none of the victim''s rows',
  (select count(*) from public.client_habits where client_id='c0000000-0000-0000-0000-00000000000c')
  + (select count(*) from public.client_nutrition_plans where client_id='c0000000-0000-0000-0000-00000000000c') = 0,
  'visible to stranger';
reset role;

-- Policy shape: nothing on the six tables is left asserting only coach_id = auth.uid() on its write arm.
insert into res select 'OD14 no FOR ALL / INSERT policy on the six tables still lacks the active-relationship test',
  count(*)=0, coalesce(string_agg(tablename||'/'||policyname, ', '),'none')
  from pg_policies
  where schemaname='public'
    and tablename in ('client_habits','action_items','coaching_calls','coach_video_responses','client_nutrition_plans','workout_program_assignments')
    and cmd in ('ALL','INSERT','UPDATE','DELETE')
    and coalesce(qual,'')||coalesce(with_check,'') like '%coach_id = auth.uid()%'
    and coalesce(qual,'')||coalesce(with_check,'') not like '%is_active_coach_of%';

-- Report ------------------------------------------------------------------
select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || detail from res order by ok, id;
rollback;
