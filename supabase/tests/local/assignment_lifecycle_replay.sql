-- Assignment lifecycle (migration 195). LOCAL REPLAY ONLY — run by
-- assignment_lifecycle_replay.sh, which refuses any non-loopback target and any
-- QA/production credential. Concurrency is exercised separately, with committed
-- data in a throw-away clone, by assignment_lifecycle_concurrency.sh.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against a replay WITH 195 (every check passes) and one WITHOUT it but with
-- 189–194 (the negative control: the checks listed in the runner must FAIL).
-- API calls are emulated as PostgREST makes them: log in as `authenticator`, set
-- the request claims, SET ROLE authenticated.
--
-- Fixtures
--   coaches K, K2, K3
--   X  K's client who CANCELS K and takes K2 (the coach switch)
--   Y  K's client who cancels K and has no other programme
--   Z  former client of BOTH K and K3 (legacy: two stale active rows, nothing valid)
--   M  a member with a self-generated plan (later coached by K2)
--   programmes KP, KP2 (K); K2P, K2Q (K2, K2P has a day); K3P (K3)

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated, service_role;
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.claims(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', case when u is null then '' else json_build_object('sub',u,'role','authenticated')::text end, true) $$;
create function pg_temp.try(stmt text) returns text language plpgsql as $$
declare n bigint;
begin execute 'with x as (' || stmt || ' returning 1) select count(*) from x' into n; return 'ok:' || n;
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
create function pg_temp.call(stmt text) returns text language plpgsql as $$
declare r text;
begin execute stmt into r; return 'ok:' || left(coalesce(r, 'null'), 60);
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
create function pg_temp.assign(p text, c text, coach text) returns text language sql as
$$ select format('insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, %L, ''active'', 1)', p, c, coach) $$;
create function pg_temp.active(c text) returns text language sql as
$$ select count(*)||':'||coalesce(string_agg(right(program_id::text, 2), ',' order by program_id), '')
     from public.workout_program_assignments where client_id = c::uuid and status = 'active' $$;
grant execute on function pg_temp.try(text), pg_temp.call(text), pg_temp.assign(text, text, text), pg_temp.active(text)
  to authenticated, service_role;

-- ── users, relationships, programmes ───────────────────────────────────────
insert into auth.users(id,email) values
 ('a3000000-0000-0000-0000-00000000000a','lc-k@local'), ('a3000000-0000-0000-0000-00000000000b','lc-k2@local'),
 ('a3000000-0000-0000-0000-00000000000c','lc-k3@local'),
 ('a3000000-0000-0000-0000-0000000000a1','lc-x@local'), ('a3000000-0000-0000-0000-0000000000a2','lc-y@local'),
 ('a3000000-0000-0000-0000-0000000000a3','lc-z@local'), ('a3000000-0000-0000-0000-0000000000a4','lc-m@local')
 on conflict do nothing;
update public.user_profiles set role='coach'
 where id in ('a3000000-0000-0000-0000-00000000000a','a3000000-0000-0000-0000-00000000000b','a3000000-0000-0000-0000-00000000000c');
update public.user_profiles set onboarding_complete=true, has_injuries=false, injury_locations='',
  parq_answers='{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}',
  fitness_goal='build_muscle', training_days_per_week=3
 where id in ('a3000000-0000-0000-0000-0000000000a1','a3000000-0000-0000-0000-0000000000a2',
              'a3000000-0000-0000-0000-0000000000a3','a3000000-0000-0000-0000-0000000000a4');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('a3000000-0000-0000-0000-00000000000a','a3000000-0000-0000-0000-0000000000a1','active','client'),
 ('a3000000-0000-0000-0000-00000000000a','a3000000-0000-0000-0000-0000000000a2','active','client'),
 ('a3000000-0000-0000-0000-00000000000a','a3000000-0000-0000-0000-0000000000a3','active','client'),
 ('a3000000-0000-0000-0000-00000000000c','a3000000-0000-0000-0000-0000000000a3','active','client');
insert into public.workout_programs(id, coach_id, name) values
 ('a3100000-0000-0000-0000-0000000000a1','a3000000-0000-0000-0000-00000000000a','lc KP'),
 ('a3100000-0000-0000-0000-0000000000a2','a3000000-0000-0000-0000-00000000000a','lc KP2'),
 ('a3100000-0000-0000-0000-0000000000b1','a3000000-0000-0000-0000-00000000000b','lc K2P'),
 ('a3100000-0000-0000-0000-0000000000b2','a3000000-0000-0000-0000-00000000000b','lc K2Q'),
 ('a3100000-0000-0000-0000-0000000000c1','a3000000-0000-0000-0000-00000000000c','lc K3P');
insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values
 ('a3100000-0000-0000-0000-0000000000b1', 1, 'Monday', 'K2 private day',
  '[{"exercise_instance_id":"ex-1-1","name":"k2 secret","sets":3,"reps":10}]', 0);
select set_config('lc.K','a3000000-0000-0000-0000-00000000000a',true), set_config('lc.K2','a3000000-0000-0000-0000-00000000000b',true),
       set_config('lc.K3','a3000000-0000-0000-0000-00000000000c',true),
       set_config('lc.X','a3000000-0000-0000-0000-0000000000a1',true), set_config('lc.Y','a3000000-0000-0000-0000-0000000000a2',true),
       set_config('lc.Z','a3000000-0000-0000-0000-0000000000a3',true), set_config('lc.M','a3000000-0000-0000-0000-0000000000a4',true),
       set_config('lc.KP','a3100000-0000-0000-0000-0000000000a1',true), set_config('lc.KP2','a3100000-0000-0000-0000-0000000000a2',true),
       set_config('lc.K2P','a3100000-0000-0000-0000-0000000000b1',true), set_config('lc.K2Q','a3100000-0000-0000-0000-0000000000b2',true),
       set_config('lc.K3P','a3100000-0000-0000-0000-0000000000c1',true);

-- K assigns while active (API): KP -> X, KP2 -> Y.
select pg_temp.claims(current_setting('lc.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select pg_temp.try(pg_temp.assign(current_setting('lc.KP'),  current_setting('lc.X'), current_setting('lc.K')));
select pg_temp.try(pg_temp.assign(current_setting('lc.KP2'), current_setting('lc.Y'), current_setting('lc.K')));
reset role; reset session authorization;
-- Z's legacy state (pre-fix): stale active rows from BOTH former coaches, written raw.
alter table public.workout_program_assignments disable trigger user;
insert into public.workout_program_assignments(id, program_id, client_id, coach_id, status, current_week) values
 ('a3200000-0000-0000-0000-0000000000a3', current_setting('lc.KP2')::uuid, current_setting('lc.Z')::uuid, current_setting('lc.K')::uuid,  'active', 1),
 ('a3200000-0000-0000-0000-0000000000c3', current_setting('lc.K3P')::uuid, current_setting('lc.Z')::uuid, current_setting('lc.K3')::uuid, 'active', 1);
alter table public.workout_program_assignments enable trigger user;
-- Every client ends coaching the way the app does (cancelCoach); X then takes K2.
select pg_temp.claims(null);
update public.coach_client_relationships set status='cancelled', cancelled_by='client', cancelled_at=now()
 where client_id in (current_setting('lc.X')::uuid, current_setting('lc.Y')::uuid, current_setting('lc.Z')::uuid);
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 (current_setting('lc.K2')::uuid, current_setting('lc.X')::uuid, 'active', 'client'),
 (current_setting('lc.K2')::uuid, current_setting('lc.M')::uuid, 'active', 'client');
select set_config('lc.KXrow', (select id::text from public.workout_program_assignments
  where coach_id = current_setting('lc.K')::uuid and client_id = current_setting('lc.X')::uuid), true);
select set_config('lc.KYrow', (select id::text from public.workout_program_assignments
  where coach_id = current_setting('lc.K')::uuid and client_id = current_setting('lc.Y')::uuid), true);
insert into res select 'F00 fixture: X, Y each hold one active assignment from K; Z holds two stale ones',
  pg_temp.active(current_setting('lc.X')) = '1:a1' and pg_temp.active(current_setting('lc.Y')) = '1:a2'
  and pg_temp.active(current_setting('lc.Z')) like '2:%',
  pg_temp.active(current_setting('lc.X'))||' / '||pg_temp.active(current_setting('lc.Y'))||' / '||pg_temp.active(current_setting('lc.Z'));

-- ═══ S · the coach switch ═════════════════════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('lc.K2')::uuid);
set local session authorization authenticator; set local role authenticated;
-- assignProgram's two writes
select set_config('lc.s1a', pg_temp.try(format('update public.workout_program_assignments set status = ''replaced'' where client_id = %L and status = ''active''', current_setting('lc.X'))), true);
select set_config('lc.s1b', pg_temp.try(pg_temp.assign(current_setting('lc.K2P'), current_setting('lc.X'), current_setting('lc.K2'))), true);
reset role; reset session authorization;
select set_config('lc.after1', pg_temp.active(current_setting('lc.X')), true);
-- the client's own read, as getMyAssignedProgram(...).maybeSingle() makes it
select pg_temp.claims(current_setting('lc.X')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.s2', (select count(*)||':'||coalesce(string_agg(right(program_id::text, 2), ','), '')
  from public.workout_program_assignments where client_id = current_setting('lc.X')::uuid and status = 'active'), true);
reset role; reset session authorization;
insert into res select 'S01 switching coaches leaves ONE active assignment — the new coach''s',
  current_setting('lc.s1b') = 'ok:1' and current_setting('lc.after1') = '1:b1', current_setting('lc.after1');
insert into res select 'S02 …and the former coach''s row is marked replaced (not deleted)',
  (select status from public.workout_program_assignments where id = current_setting('lc.KXrow')::uuid) = 'replaced', '';
insert into res select 'S03 the client''s own active read (the maybeSingle query) returns exactly one row',
  current_setting('lc.s2') = '1:b1', current_setting('lc.s2');
-- repeated assignments by the current coach
select pg_temp.claims(current_setting('lc.K2')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.s4a', pg_temp.try(pg_temp.assign(current_setting('lc.K2Q'), current_setting('lc.X'), current_setting('lc.K2'))), true);
select set_config('lc.s4b', pg_temp.try(pg_temp.assign(current_setting('lc.K2Q'), current_setting('lc.X'), current_setting('lc.K2'))), true);
select set_config('lc.s4c', pg_temp.try(pg_temp.assign(current_setting('lc.K2P'), current_setting('lc.X'), current_setting('lc.K2'))), true);
reset role; reset session authorization;
insert into res select 'S04 repeated assignments (including the same programme twice) always leave exactly one active',
  current_setting('lc.s4a') = 'ok:1' and current_setting('lc.s4b') = 'ok:1' and current_setting('lc.s4c') = 'ok:1'
  and pg_temp.active(current_setting('lc.X')) = '1:b1',
  pg_temp.active(current_setting('lc.X'));
-- weekly feedback attribution (175 counts the programme's active assignments the caller can see)
select pg_temp.claims(current_setting('lc.K2')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.w1', pg_temp.try(format('insert into public.weekly_feedback(program_id, week) values (%L, 1)', current_setting('lc.K2P'))), true);
reset role; reset session authorization;
select pg_temp.claims(current_setting('lc.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.w2', pg_temp.try(format('insert into public.weekly_feedback(program_id, week) values (%L, 1)', current_setting('lc.KP'))), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'S05 weekly feedback on the new coach''s programme is attributed to the client',
  current_setting('lc.w1') = 'ok:1'
  and (select subject_id from public.weekly_feedback where program_id = current_setting('lc.K2P')::uuid and week = 1) = current_setting('lc.X')::uuid,
  current_setting('lc.w1');
insert into res select 'S06 …while feedback on the FORMER coach''s programme is attributed to no one',
  current_setting('lc.w2') = 'ok:1'
  and (select subject_id from public.weekly_feedback where program_id = current_setting('lc.KP')::uuid and week = 1) is null,
  current_setting('lc.w2')||' subject='||coalesce((select subject_id::text from public.weekly_feedback
     where program_id = current_setting('lc.KP')::uuid and week = 1), 'null');
-- the former coach regains nothing
select pg_temp.claims(current_setting('lc.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.n1', (select count(*)::text from public.program_workouts where program_id = current_setting('lc.K2P')::uuid), true);
select set_config('lc.n2', pg_temp.call(format('select to_jsonb(a)::text from public.get_client_assessment(%L) a', current_setting('lc.X'))), true);
select set_config('lc.n3', pg_temp.call(format('select public.engine_client_clearance(%L)::text', current_setting('lc.X'))), true);
select set_config('lc.n4', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('lc.K2P'))), true);
select set_config('lc.n5', (select count(*)::text from public.user_profiles where id = current_setting('lc.X')::uuid), true);
select set_config('lc.n6', (select count(*)::text from public.workout_program_assignments where coach_id = current_setting('lc.K2')::uuid), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'S07 the former coach still reads none of the new programme, the profile, or the new assignment',
  current_setting('lc.n1') = '0' and current_setting('lc.n5') = '0' and current_setting('lc.n6') = '0',
  current_setting('lc.n1')||' day(s), '||current_setting('lc.n5')||' profile(s), '||current_setting('lc.n6')||' assignment(s)';
insert into res select 'S08 …and is refused the assessment, the clearance and generation (42501)',
  current_setting('lc.n2') like 'err:42501:%' and current_setting('lc.n3') like 'err:42501:%' and current_setting('lc.n4') like 'err:42501:%',
  current_setting('lc.n2')||' / '||current_setting('lc.n3')||' / '||current_setting('lc.n4');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ R · former-coach retirement ══════════════════════════════════════════
savepoint s;
-- X's LEGACY state (pre-fix): K2 already assigned while K's row stayed active.
alter table public.workout_program_assignments disable trigger user;
insert into public.workout_program_assignments(id, program_id, client_id, coach_id, status, current_week) values
 ('a3200000-0000-0000-0000-0000000000b1', current_setting('lc.K2P')::uuid, current_setting('lc.X')::uuid, current_setting('lc.K2')::uuid, 'active', 1);
alter table public.workout_program_assignments enable trigger user;
select pg_temp.claims(current_setting('lc.M')::uuid);
set local session authorization authenticator; set local role authenticated;
select public.generate_client_plan();
reset role; reset session authorization;
select set_config('lc.Mrow', (select id::text from public.workout_program_assignments
  where client_id = current_setting('lc.M')::uuid and coach_id is null and status = 'active'), true);
select set_config('lc.before', pg_temp.active(current_setting('lc.X')), true);
select pg_temp.claims(current_setting('lc.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.r1', pg_temp.call(format('select public.retire_my_assignment(%L)::text', current_setting('lc.KXrow'))), true);
select set_config('lc.r2', pg_temp.call(format('select public.retire_my_assignment(%L)::text', current_setting('lc.KYrow'))), true);
select set_config('lc.r3', pg_temp.call('select public.retire_my_assignment(''a3200000-0000-0000-0000-0000000000a3'')::text'), true);
select set_config('lc.r4', pg_temp.call('select public.retire_my_assignment(''a3200000-0000-0000-0000-0000000000b1'')::text'), true);
select set_config('lc.r5', pg_temp.call(format('select public.retire_my_assignment(%L)::text', current_setting('lc.Mrow'))), true);
select set_config('lc.r6', pg_temp.call('select public.retire_my_assignment(''a3200000-0000-0000-0000-00000000dead'')::text'), true);
select set_config('lc.r7', pg_temp.call(format('select public.retire_my_assignment(%L)::text', current_setting('lc.KXrow'))), true);
select set_config('lc.r8', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('lc.KP'))), true);
select set_config('lc.r9', pg_temp.try(format('update public.workout_program_assignments set status = ''active'' where id = %L', current_setting('lc.KXrow'))), true);
reset role; reset session authorization;
select pg_temp.claims(current_setting('lc.K2')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.r10', pg_temp.call('select public.retire_my_assignment(''a3200000-0000-0000-0000-0000000000b1'')::text'), true);
reset role; reset session authorization;
select pg_temp.claims(current_setting('lc.K3')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.r11', pg_temp.call('select public.retire_my_assignment(''a3200000-0000-0000-0000-0000000000c3'')::text'), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'R01 a former coach RETIRES their own stale row when the client has a current coach''s programme',
  current_setting('lc.before') like '2:%' and current_setting('lc.r1') like 'ok:%'
  and (select status from public.workout_program_assignments where id = current_setting('lc.KXrow')::uuid) = 'replaced'
  and pg_temp.active(current_setting('lc.X')) = '1:b1',
  current_setting('lc.before')||' -> '||pg_temp.active(current_setting('lc.X'))||' / '||current_setting('lc.r1');
insert into res select 'R02 …but NOT the client''s only active programme (Y)',
  current_setting('lc.r2') like 'err:42501:ASSIGNMENT_NOT_RETIRABLE%'
  and (select status from public.workout_program_assignments where id = current_setting('lc.KYrow')::uuid) = 'active',
  current_setting('lc.r2');
insert into res select 'R03 …nor when the other active row is ANOTHER former coach''s (not valid) — Z keeps both',
  current_setting('lc.r3') like 'err:42501:ASSIGNMENT_NOT_RETIRABLE%' and current_setting('lc.r11') like 'err:42501:ASSIGNMENT_NOT_RETIRABLE%'
  and pg_temp.active(current_setting('lc.Z')) like '2:%',
  current_setting('lc.r3')||' / '||current_setting('lc.r11');
insert into res select 'R04 …nor another coach''s assignment, a member''s self plan, an unknown id, or an already-retired row — one identical refusal',
  current_setting('lc.r2') like 'err:42501:ASSIGNMENT_NOT_RETIRABLE%'
  and current_setting('lc.r4') = current_setting('lc.r2') and current_setting('lc.r5') = current_setting('lc.r2')
  and current_setting('lc.r6') = current_setting('lc.r2') and current_setting('lc.r7') = current_setting('lc.r2')
  and (select status from public.workout_program_assignments where id = 'a3200000-0000-0000-0000-0000000000b1') = 'active'
  and (select status from public.workout_program_assignments where id = current_setting('lc.Mrow')::uuid) = 'active',
  current_setting('lc.r4')||' | '||current_setting('lc.r5')||' | '||current_setting('lc.r6')||' | '||current_setting('lc.r7');
insert into res select 'R05 a CURRENT coach cannot use it on their own active row (normal path only)',
  current_setting('lc.r10') like 'err:42501:ASSIGNMENT_NOT_RETIRABLE%' and current_setting('lc.r10') = current_setting('lc.r2'),
  current_setting('lc.r10');
insert into res select 'R06 the retired row cannot be reactivated by the former coach',
  current_setting('lc.r9') = 'ok:0'
  and (select status from public.workout_program_assignments where id = current_setting('lc.KXrow')::uuid) = 'replaced',
  current_setting('lc.r9');
insert into res select 'R07 with the stale row retired, the former coach''s programme can take engine training again (no clearance consulted)',
  current_setting('lc.r8') = 'ok:1', current_setting('lc.r8');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ M · member self plans ════════════════════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('lc.M')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.m1', pg_temp.call('select public.generate_client_plan()::text'), true);
reset role; reset session authorization;
select set_config('lc.m1n', pg_temp.active(current_setting('lc.M')), true);
select pg_temp.claims(current_setting('lc.M')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.m2', pg_temp.call('select public.generate_client_plan()::text'), true);
reset role; reset session authorization;
select set_config('lc.m2n', pg_temp.active(current_setting('lc.M')), true);
-- K2 (M's active coach) assigns over the active self plan
select pg_temp.claims(current_setting('lc.K2')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.m3', pg_temp.try(pg_temp.assign(current_setting('lc.K2Q'), current_setting('lc.M'), current_setting('lc.K2'))), true);
reset role; reset session authorization;
select set_config('lc.m3n', pg_temp.active(current_setting('lc.M')), true);
-- back to self-guided: regenerate, then turn it off
select pg_temp.claims(current_setting('lc.M')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.m4', pg_temp.call('select public.generate_client_plan()::text'), true);
reset role; reset session authorization;
select set_config('lc.m4n', (select count(*)||':'||count(*) filter (where coach_id is null)
  from public.workout_program_assignments where client_id = current_setting('lc.M')::uuid and status = 'active'), true);
select pg_temp.claims(current_setting('lc.M')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('lc.m5', pg_temp.call('select public.deactivate_self_generated_plan()::text'), true);
reset role; reset session authorization;
select set_config('lc.m5n', (select count(*)::text from public.workout_program_assignments
  where client_id = current_setting('lc.M')::uuid and coach_id is null), true);
select pg_temp.claims(null);
insert into res select 'M01 self-plan generation and REgeneration each leave one active (self) assignment',
  current_setting('lc.m1') like 'ok:%' and current_setting('lc.m2') like 'ok:%'
  and current_setting('lc.m1n') like '1:%' and current_setting('lc.m2n') like '1:%',
  current_setting('lc.m1n')||' / '||current_setting('lc.m2n');
insert into res select 'M02 a coach assigning over an active self plan leaves ONE active — the coach''s',
  current_setting('lc.m3') = 'ok:1' and current_setting('lc.m3n') = '1:b2', current_setting('lc.m3n');
insert into res select 'M03 regenerating a self plan afterwards leaves one active — the self plan',
  current_setting('lc.m4') like 'ok:%' and current_setting('lc.m4n') = '1:1', current_setting('lc.m4n');
insert into res select 'M04 deactivation (191) still removes the member''s self-plan assignments',
  current_setting('lc.m5') like 'ok:%' and current_setting('lc.m5n') = '0',
  current_setting('lc.m5')||' / remaining '||current_setting('lc.m5n');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ T · trusted maintenance also leaves one active ═══════════════════════
savepoint s;
select pg_temp.claims(null);
select set_config('lc.t1', pg_temp.try(pg_temp.assign(current_setting('lc.KP2'), current_setting('lc.Y'), current_setting('lc.K'))), true);
insert into res select 'T01 an owner-session activation also replaces the client''s other active assignment',
  current_setting('lc.t1') = 'ok:1' and pg_temp.active(current_setting('lc.Y')) = '1:a2'
  and (select count(*) from public.workout_program_assignments where client_id = current_setting('lc.Y')::uuid and status = 'replaced') = 1,
  pg_temp.active(current_setting('lc.Y'));
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 posture: retire fn DEFINER, pinned, authenticated-only; helpers closed; the single-active trigger fires last',
  coalesce((select prosecdef and coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'
                   and has_function_privilege('authenticated', oid, 'execute') and not has_function_privilege('anon', oid, 'execute')
              from pg_proc where oid = to_regprocedure('public.retire_my_assignment(uuid)')), false)
  and coalesce((select bool_and(not has_function_privilege('authenticated', oid, 'execute')) and count(*) = 2
              from pg_proc where oid in (to_regprocedure('public._assignment_client_lock(uuid)'),
                                         to_regprocedure('public._assignment_single_active()'))), false)
  and coalesce((select tgname from pg_trigger where tgrelid = 'public.workout_program_assignments'::regclass
                  and not tgisinternal order by tgname desc limit 1) = 'single_active_assignment', false),
  '';

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
