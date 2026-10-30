-- deactivate_self_generated_plan regression (migration 191). LOCAL REPLAY ONLY —
-- run by self_plan_deactivate_replay.sh, which refuses any non-loopback target and
-- any QA/production credential.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against a replay WITH 191 (every check passes) and one WITHOUT it (the
-- negative control: the checks listed in the runner must FAIL — the 23503 defect).
--
-- Fixtures: member M (self plan), member N, coach C (ACTIVE with M) with a
-- coach-authored programme assigned to M, and a staff template T (coach_id NULL,
-- is_template true).

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.call(stmt text) returns text language plpgsql as $$
begin execute stmt; return 'ok';
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
grant execute on function pg_temp.call(text) to authenticated;

insert into auth.users(id,email) values
 ('a7000000-0000-0000-0000-00000000000a','dsp-member@local'),
 ('a7000000-0000-0000-0000-00000000000b','dsp-other-member@local'),
 ('a7000000-0000-0000-0000-00000000000c','dsp-coach@local') on conflict do nothing;
update public.user_profiles set role='coach' where id='a7000000-0000-0000-0000-00000000000c';
update public.user_profiles set fitness_goal='build_muscle', training_days_per_week=3, onboarding_complete=true
 where id in ('a7000000-0000-0000-0000-00000000000a','a7000000-0000-0000-0000-00000000000b');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('a7000000-0000-0000-0000-00000000000c','a7000000-0000-0000-0000-00000000000a','active','client');
insert into public.workout_programs(id, coach_id, name, is_template) values
 ('a7100000-0000-0000-0000-0000000000c1','a7000000-0000-0000-0000-00000000000c','dsp coach programme', false),
 ('a7100000-0000-0000-0000-0000000000f1', null, 'dsp staff template', true);

-- M generates a self plan (the real member path).
select pg_temp.as_user('a7000000-0000-0000-0000-00000000000a'); set local role authenticated;
select set_config('dsp.gen', pg_temp.call('select public.generate_client_plan()'), true);
reset role;
select set_config('dsp.prog', coalesce((select program_id::text from public.workout_program_assignments
  where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and status='active' limit 1), ''), true);
insert into res select 'F00 fixture: the member''s self plan exists (assignment, programme with days, nutrition, habits)',
  current_setting('dsp.gen') = 'ok' and current_setting('dsp.prog') <> ''
  and exists (select 1 from public.program_workouts where program_id::text = current_setting('dsp.prog'))
  and exists (select 1 from public.client_nutrition_plans where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and is_active)
  and exists (select 1 from public.client_habits where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and is_active),
  current_setting('dsp.gen')||' prog='||current_setting('dsp.prog');
-- The coach's own assignment of their programme to M (a coach-guided plan alongside).
insert into public.workout_program_assignments(id, program_id, client_id, coach_id, status, current_week) values
 ('a7200000-0000-0000-0000-0000000000c1','a7100000-0000-0000-0000-0000000000c1','a7000000-0000-0000-0000-00000000000a',
  'a7000000-0000-0000-0000-00000000000c','replaced',1);

-- ═══ D · the member turns off their self plan ═════════════════════════════
savepoint s;
select pg_temp.as_user('a7000000-0000-0000-0000-00000000000a'); set local role authenticated;
select set_config('dsp.d', pg_temp.call('select public.deactivate_self_generated_plan()'), true);
reset role;
insert into res select 'D01 deactivate_self_generated_plan succeeds (was 23503)',
  current_setting('dsp.d') = 'ok', current_setting('dsp.d');
insert into res select 'D02 …the member''s self-plan assignment is gone',
  not exists (select 1 from public.workout_program_assignments
               where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null), '';
insert into res select 'D03 …and the self-plan programme and its days are deleted',
  not exists (select 1 from public.workout_programs where id::text = current_setting('dsp.prog'))
  and not exists (select 1 from public.program_workouts where program_id::text = current_setting('dsp.prog')),
  current_setting('dsp.prog');
insert into res select 'D04 …and the member''s self nutrition plan and habits are inactive',
  not exists (select 1 from public.client_nutrition_plans where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and is_active)
  and not exists (select 1 from public.client_habits where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and is_active), '';
insert into res select 'D05 the coach''s assignment and programme are untouched',
  exists (select 1 from public.workout_program_assignments where id='a7200000-0000-0000-0000-0000000000c1' and status='replaced')
  and exists (select 1 from public.workout_programs where id='a7100000-0000-0000-0000-0000000000c1'), '';
select pg_temp.as_user('a7000000-0000-0000-0000-00000000000a'); set local role authenticated;
select set_config('dsp.d2', pg_temp.call('select public.deactivate_self_generated_plan()'), true);
select set_config('dsp.regen', pg_temp.call('select public.generate_client_plan()'), true);
reset role;
insert into res select 'D06 calling it again with nothing to deactivate is a no-op, and a new self plan can then be generated',
  current_setting('dsp.d2') = 'ok' and current_setting('dsp.regen') = 'ok'
  and exists (select 1 from public.workout_program_assignments
               where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and status='active'),
  current_setting('dsp.d2')||' / '||current_setting('dsp.regen');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ G · guards: never a staff template, never a programme someone else holds ═
savepoint s;
-- M also holds a coach-less assignment of the staff TEMPLATE, and member N holds an
-- assignment of M's self-plan programme (both reachable before 190's client arm fix).
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values
 ('a7100000-0000-0000-0000-0000000000f1','a7000000-0000-0000-0000-00000000000a', null, 'replaced', 1),
 (current_setting('dsp.prog')::uuid,     'a7000000-0000-0000-0000-00000000000b', null, 'active', 1);
select pg_temp.as_user('a7000000-0000-0000-0000-00000000000a'); set local role authenticated;
select set_config('dsp.g', pg_temp.call('select public.deactivate_self_generated_plan()'), true);
reset role;
insert into res select 'G01 with a template and a shared programme in play, deactivation still succeeds',
  current_setting('dsp.g') = 'ok', current_setting('dsp.g');
insert into res select 'G02 …the staff template is NOT deleted (coach_id NULL but is_template true)',
  exists (select 1 from public.workout_programs where id='a7100000-0000-0000-0000-0000000000f1'), '';
insert into res select 'G03 …a self-plan programme another member still holds is NOT deleted, nor their assignment',
  exists (select 1 from public.workout_programs where id::text = current_setting('dsp.prog'))
  and exists (select 1 from public.workout_program_assignments
               where client_id='a7000000-0000-0000-0000-00000000000b' and program_id::text = current_setting('dsp.prog')),
  '';
insert into res select 'G04 …while the member''s own coach-less assignments are all removed',
  not exists (select 1 from public.workout_program_assignments
               where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null), '';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ N · no signed-in user changes nothing ═════════════════════════════════
savepoint s;
select set_config('request.jwt.claims', '', true);
select set_config('dsp.n', pg_temp.call('select public.deactivate_self_generated_plan()'), true);
insert into res select 'N01 with no signed-in user it returns and changes nothing',
  current_setting('dsp.n') = 'ok'
  and exists (select 1 from public.workout_program_assignments
               where client_id='a7000000-0000-0000-0000-00000000000a' and coach_id is null and status='active'),
  current_setting('dsp.n');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 posture: SECURITY DEFINER, search_path pinned, authenticated may execute, anon may not',
  prosecdef and coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'
  and has_function_privilege('authenticated', oid, 'execute') and not has_function_privilege('anon', oid, 'execute'), ''
  from pg_proc where oid = 'public.deactivate_self_generated_plan()'::regprocedure;

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
