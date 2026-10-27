-- Assignment safety (migration 189) and the client write arm (migration 190).
-- LOCAL REPLAY ONLY — run by assignment_guard_replay.sh, which refuses any
-- non-loopback target and any QA/production credential.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against BOTH a replay WITH 189 + 190 (every check passes) and one WITHOUT
-- them (the negative control: the checks listed in the runner must FAIL).
--
-- Fixtures. Coach K is ACTIVE with every client; coach O is PENDING with CL.
--   CL cleared — completed intake, no injury, eight PAR-Q "no" answers (risk low)
--   IN injured (Knee)          UN intake never completed
--   HR PAR-Q Q2 yes (high)     MA PAR-Q Q8 yes, "other medical reason" (moderate)
--   PQ intake complete, no injury, but NO PAR-Q answers — parq_answers is NOT
--      NULL, so "none" is '{}', which 126 derives as risk 'low'
-- Programmes (K): E and E2 engine_selected; H hand-built.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated, service_role;
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
-- Run a statement; 'ok:<rows>' (row count from RETURNING) or 'err:<sqlstate>:<message>'.
create function pg_temp.try(stmt text) returns text language plpgsql as $$
declare n bigint;
begin
  execute 'with x as (' || stmt || ' returning 1) select count(*) from x' into n;
  return 'ok:' || n;
exception when others then
  return 'err:' || sqlstate || ':' || left(sqlerrm, 120);
end $$;
create function pg_temp.call(stmt text) returns text language plpgsql as $$
declare r jsonb;
begin
  execute stmt into r;
  return coalesce(r::text, 'null');
exception when others then
  return 'err:' || sqlstate || ':' || left(sqlerrm, 120);
end $$;
grant execute on function pg_temp.try(text), pg_temp.call(text) to authenticated, service_role;
create function pg_temp.assign(p text, c text, coach text, st text default 'active') returns text language sql as
$$ select format('insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, %L, %L, 1)', p, c, coach, st) $$;
grant execute on function pg_temp.assign(text, text, text, text) to authenticated, service_role;

-- ── users ──────────────────────────────────────────────────────────────────
insert into auth.users(id,email) values
 ('a9000000-0000-0000-0000-000000000001','asg-coach-k@local'),
 ('a9000000-0000-0000-0000-000000000002','asg-coach-o@local'),
 ('a9000000-0000-0000-0000-000000000011','asg-cleared@local'),
 ('a9000000-0000-0000-0000-000000000012','asg-injured@local'),
 ('a9000000-0000-0000-0000-000000000013','asg-nointake@local'),
 ('a9000000-0000-0000-0000-000000000014','asg-highrisk@local'),
 ('a9000000-0000-0000-0000-000000000015','asg-medadvice@local'),
 ('a9000000-0000-0000-0000-000000000016','asg-noparq@local') on conflict do nothing;
update public.user_profiles set role = 'coach'
 where id in ('a9000000-0000-0000-0000-000000000001','a9000000-0000-0000-0000-000000000002');
select set_config('asg.no8', '{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}', true);
update public.user_profiles p set onboarding_complete = v.done, has_injuries = v.inj,
       injury_locations = v.loc, parq_answers = v.parq::jsonb,
       fitness_goal = 'build_muscle', training_days_per_week = 3
from (values
  ('a9000000-0000-0000-0000-000000000011', true,  false, '',     current_setting('asg.no8')),
  ('a9000000-0000-0000-0000-000000000012', true,  true,  'Knee', current_setting('asg.no8')),
  ('a9000000-0000-0000-0000-000000000013', false, false, '',     '{}'),
  ('a9000000-0000-0000-0000-000000000014', true,  false, '',     replace(current_setting('asg.no8'), '"2":false', '"2":true')),
  ('a9000000-0000-0000-0000-000000000015', true,  false, '',     replace(current_setting('asg.no8'), '"8":false', '"8":true')),
  ('a9000000-0000-0000-0000-000000000016', true,  false, '',     '{}')
) v(id, done, inj, loc, parq) where p.id = v.id::uuid;
insert into public.coach_client_relationships(coach_id, client_id, status, initiated_by)
select 'a9000000-0000-0000-0000-000000000001', ('a9000000-0000-0000-0000-0000000000'||n)::uuid, 'active', 'client'
  from unnest(array['11','12','13','14','15','16']) n;
insert into public.coach_client_relationships(coach_id, client_id, status, initiated_by) values
 ('a9000000-0000-0000-0000-000000000002','a9000000-0000-0000-0000-000000000011','pending','coach');
insert into res select 'F00 fixture: derived PAR-Q risk is low / low / high / moderate / low(empty)',
  string_agg(right(id::text, 2)||'='||coalesce(risk_level,'null'), ',' order by id)
    = '11=low,12=low,14=high,15=moderate,16=low', string_agg(right(id::text, 2)||'='||coalesce(risk_level,'null'), ',' order by id)
  from public.user_profiles where id::text in ('a9000000-0000-0000-0000-000000000011','a9000000-0000-0000-0000-000000000012',
   'a9000000-0000-0000-0000-000000000014','a9000000-0000-0000-0000-000000000015','a9000000-0000-0000-0000-000000000016');

-- ── programmes ─────────────────────────────────────────────────────────────
insert into public.workout_programs(id, coach_id, name) values
 ('a9100000-0000-0000-0000-00000000000e','a9000000-0000-0000-0000-000000000001','asg engine E'),
 ('a9100000-0000-0000-0000-0000000000e2','a9000000-0000-0000-0000-000000000001','asg engine E2'),
 ('a9100000-0000-0000-0000-00000000000f','a9000000-0000-0000-0000-000000000001','asg hand-built H');
-- Mark E and E2 the way generation does (only where the column exists: on the
-- negative-control replay it does not, and they stay ordinary programmes).
do $$ begin
  if exists (select 1 from information_schema.columns
              where table_name = 'workout_programs' and column_name = 'engine_selected') then
    execute 'update public.workout_programs set engine_selected = true where id in
      (''a9100000-0000-0000-0000-00000000000e'', ''a9100000-0000-0000-0000-0000000000e2'')';
  end if;
end $$;
select set_config('asg.E',  'a9100000-0000-0000-0000-00000000000e', true);
select set_config('asg.E2', 'a9100000-0000-0000-0000-0000000000e2', true);
select set_config('asg.H',  'a9100000-0000-0000-0000-00000000000f', true);
select set_config('asg.K',  'a9000000-0000-0000-0000-000000000001', true);
select set_config('asg.O',  'a9000000-0000-0000-0000-000000000002', true);

-- ═══ G · the sticky mark ══════════════════════════════════════════════════
savepoint s;
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.g1', pg_temp.try(format('update public.workout_programs set engine_selected = false where id = %L', current_setting('asg.E'))), true);
reset role;
set local role service_role;
select set_config('asg.g2', pg_temp.try(format('update public.workout_programs set engine_selected = false where id = %L', current_setting('asg.E'))), true);
reset role;
insert into res select 'G01 the owning coach cannot clear engine_selected (ENGINE_SELECTED_IS_PERMANENT)',
  current_setting('asg.g1') like 'err:42501:ENGINE_SELECTED_IS_PERMANENT%', current_setting('asg.g1');
insert into res select 'G02 …nor can the service role — there is no override',
  current_setting('asg.g2') like 'err:42501:ENGINE_SELECTED_IS_PERMANENT%', current_setting('asg.g2');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ G · assignment-time guard, coach direct API path ═════════════════════
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.g3', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.K'))), true);
select set_config('asg.g4', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000013', current_setting('asg.K'))), true);
select set_config('asg.g5', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000014', current_setting('asg.K'))), true);
select set_config('asg.g6', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000015', current_setting('asg.K'))), true);
select set_config('asg.g7', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000016', current_setting('asg.K'))), true);
reset role;
insert into res select 'G03 coach API: engine programme -> INJURED client is refused (ENGINE_CLIENT_NOT_CLEARED)',
  current_setting('asg.g3') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g3');
insert into res select 'G04 …-> client whose intake is INCOMPLETE is refused',
  current_setting('asg.g4') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g4');
insert into res select 'G05 …-> client with HIGH PAR-Q risk is refused',
  current_setting('asg.g5') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g5');
insert into res select 'G06 …-> client with PAR-Q medical advice (Q8) is refused',
  current_setting('asg.g6') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g6');
insert into res select 'G07 …-> client with NO PAR-Q answers (derived "low") is refused',
  current_setting('asg.g7') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g7');
insert into res select 'G08 …and none of those assignments exists',
  count(*) = 0, count(*)||' row(s)' from public.workout_program_assignments where program_id = current_setting('asg.E')::uuid;

savepoint s;
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.g9', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.K'))), true);
select set_config('asg.g10', pg_temp.try(pg_temp.assign(current_setting('asg.H'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.K'))), true);
reset role;
insert into res select 'G09 engine programme -> the CLEARED client (complete intake, no injury, low PAR-Q) is allowed',
  current_setting('asg.g9') = 'ok:1', current_setting('asg.g9');
insert into res select 'G10 a HAND-BUILT programme -> the injured client is still allowed',
  current_setting('asg.g10') = 'ok:1', current_setting('asg.g10');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- service role and client paths
savepoint s;
set local role service_role;
select set_config('asg.g11', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.K'))), true);
reset role;
select pg_temp.as_user('a9000000-0000-0000-0000-000000000012'); set local role authenticated;
select set_config('asg.g12', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.K'))), true);
reset role;
insert into res select 'G11 the service role cannot assign an engine programme to the injured client either',
  current_setting('asg.g11') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('asg.g11');
insert into res select 'G12 the injured client cannot self-assign the engine programme',
  current_setting('asg.g12') like 'err:42501:%', current_setting('asg.g12');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- reactivation, and no retroactive recheck
savepoint s;
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.g13a', pg_temp.try(pg_temp.assign(current_setting('asg.E2'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.K'), 'replaced')), true);
select set_config('asg.g13', pg_temp.try(format(
  'update public.workout_program_assignments set status = ''active'' where program_id = %L and client_id = %L',
  current_setting('asg.E2'), 'a9000000-0000-0000-0000-000000000012')), true);
select set_config('asg.g14a', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.K'))), true);
reset role;
-- The CLEARED client reports an injury AFTER the engine programme was assigned.
-- (Marking a programme already active for an uncleared client is refused by 192,
-- so a change in the client's status is the way an existing assignment goes stale.)
update public.user_profiles set has_injuries = true, injury_locations = 'Knee'
 where id = 'a9000000-0000-0000-0000-000000000011';
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.g14', pg_temp.try(format(
  'update public.workout_program_assignments set current_week = 2 where program_id = %L and client_id = %L',
  current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000011')), true);
reset role;
insert into res select 'G13 REACTIVATING an inactive assignment of an engine programme for the injured client is refused',
  current_setting('asg.g13a') = 'ok:1' and current_setting('asg.g13') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%',
  current_setting('asg.g13a')||' / '||current_setting('asg.g13');
insert into res select 'G14 an assignment already active is NOT retroactively rechecked when the client''s status changes (current_week update allowed)',
  current_setting('asg.g14a') = 'ok:1' and current_setting('asg.g14') = 'ok:1',
  current_setting('asg.g14a')||' / '||current_setting('asg.g14');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- an unrelated caller learns nothing about a stranger's clearance
savepoint s;
select pg_temp.as_user(current_setting('asg.O')::uuid); set local role authenticated;
select set_config('asg.g15', pg_temp.try(pg_temp.assign(current_setting('asg.E'), 'a9000000-0000-0000-0000-000000000012', current_setting('asg.O'))), true);
reset role;
insert into res select 'G15 a coach with no relationship is refused by RLS, and the error says nothing about clearance',
  current_setting('asg.g15') like 'err:42501:%' and position('CLEARED' in current_setting('asg.g15')) = 0,
  current_setting('asg.g15');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ K · the clearance verdict the app reads ══════════════════════════════
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.k' || n, pg_temp.call(format('select public.engine_client_clearance(%L)', 'a9000000-0000-0000-0000-0000000000' || n)), true)
  from unnest(array['11','12','13','14','15','16']) n;
reset role;
select pg_temp.as_user(current_setting('asg.O')::uuid); set local role authenticated;
select set_config('asg.kO', pg_temp.call(format('select public.engine_client_clearance(%L)', 'a9000000-0000-0000-0000-000000000011')), true);
reset role;
insert into res select 'K01 the cleared client reads cleared, with no reasons',
  current_setting('asg.k11') = '{"cleared": true, "reasons": []}', current_setting('asg.k11');
insert into res select 'K02 injured -> INJURY_REPORTED',
  current_setting('asg.k12') like '{"cleared": false%' and current_setting('asg.k12') like '%INJURY_REPORTED%', current_setting('asg.k12');
insert into res select 'K03 intake incomplete -> INTAKE_INCOMPLETE and PARQ_INCOMPLETE',
  current_setting('asg.k13') like '%INTAKE_INCOMPLETE%' and current_setting('asg.k13') like '%PARQ_INCOMPLETE%', current_setting('asg.k13');
insert into res select 'K04 high PAR-Q risk -> PARQ_RISK_NOT_LOW',
  current_setting('asg.k14') like '%PARQ_RISK_NOT_LOW%', current_setting('asg.k14');
insert into res select 'K05 PAR-Q Q8 -> MEDICAL_ADVICE',
  current_setting('asg.k15') like '%MEDICAL_ADVICE%', current_setting('asg.k15');
insert into res select 'K06 empty PAR-Q -> PARQ_INCOMPLETE even though risk_level reads low',
  current_setting('asg.k16') = '{"cleared": false, "reasons": ["PARQ_INCOMPLETE"]}', current_setting('asg.k16');
insert into res select 'K07 a PENDING coach cannot read a clearance (42501)',
  current_setting('asg.kO') like 'err:42501:%', current_setting('asg.kO');
insert into res select 'K08 every clearance read is logged as an assessment view',
  count(*) = 6, count(*)||' log row(s)'
  from public.assessment_access_log where coach_id = current_setting('asg.K')::uuid;

-- ═══ H · the client write arm (190) ═══════════════════════════════════════
-- CL holds a legitimate active assignment of the hand-built programme.
insert into public.workout_program_assignments(id, program_id, client_id, coach_id, status, current_week) values
 ('a9200000-0000-0000-0000-000000000001', current_setting('asg.H')::uuid,
  'a9000000-0000-0000-0000-000000000011', current_setting('asg.K')::uuid, 'active', 1);
savepoint s;
select pg_temp.as_user('a9000000-0000-0000-0000-000000000011'); set local role authenticated;
select set_config('asg.h1', (select count(*)::text from public.workout_program_assignments
                              where client_id = 'a9000000-0000-0000-0000-000000000011'), true);
select set_config('asg.h2', pg_temp.try(pg_temp.assign(current_setting('asg.H'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.O'))), true);
select set_config('asg.h3', pg_temp.try(
  'update public.workout_program_assignments set status = ''active'', current_week = 9, coach_id = ''a9000000-0000-0000-0000-000000000002'' where id = ''a9200000-0000-0000-0000-000000000001'''), true);
select set_config('asg.h4', pg_temp.try(
  'delete from public.workout_program_assignments where id = ''a9200000-0000-0000-0000-000000000001'''), true);
reset role;
insert into res select 'H01 a client still READS their own assignment',
  current_setting('asg.h1') = '1', current_setting('asg.h1')||' row(s)';
insert into res select 'H02 a client cannot CREATE an assignment naming another coach and a programme',
  current_setting('asg.h2') like 'err:42501:%', current_setting('asg.h2');
insert into res select 'H03 a client cannot ALTER their assignment (coach, week, status)',
  current_setting('asg.h3') = 'ok:0'
  and (select coach_id = current_setting('asg.K')::uuid and current_week = 1
         from public.workout_program_assignments where id = 'a9200000-0000-0000-0000-000000000001'),
  current_setting('asg.h3');
insert into res select 'H04 a client cannot DELETE their assignment',
  current_setting('asg.h4') = 'ok:0'
  and exists (select 1 from public.workout_program_assignments where id = 'a9200000-0000-0000-0000-000000000001'),
  current_setting('asg.h4');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user(current_setting('asg.K')::uuid); set local role authenticated;
select set_config('asg.h5', pg_temp.try(
  'update public.workout_program_assignments set status = ''replaced'' where id = ''a9200000-0000-0000-0000-000000000001'''), true);
select set_config('asg.h5b', pg_temp.try(pg_temp.assign(current_setting('asg.H'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.K'))), true);
select set_config('asg.h7', pg_temp.try(pg_temp.assign(current_setting('asg.H'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.O'))), true);
reset role;
select pg_temp.as_user(current_setting('asg.O')::uuid); set local role authenticated;
select set_config('asg.h6', pg_temp.try(pg_temp.assign(current_setting('asg.H'), 'a9000000-0000-0000-0000-000000000011', current_setting('asg.O'))), true);
reset role;
insert into res select 'H05 the ACTIVE coach can still replace and insert assignments (assignProgram''s two writes)',
  current_setting('asg.h5') = 'ok:1' and current_setting('asg.h5b') = 'ok:1',
  current_setting('asg.h5')||' / '||current_setting('asg.h5b');
insert into res select 'H06 a PENDING coach cannot assign',
  current_setting('asg.h6') like 'err:42501:%', current_setting('asg.h6');
insert into res select 'H07 a coach cannot write a row naming a DIFFERENT coach',
  current_setting('asg.h7') like 'err:42501:%', current_setting('asg.h7');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user('a9000000-0000-0000-0000-000000000011'); set local role authenticated;
select set_config('asg.h8', pg_temp.call('select to_jsonb(public.generate_client_plan())'), true);
reset role;
insert into res select 'H08 the member self-plan (generate_client_plan, SECURITY DEFINER) still assigns the client''s own plan',
  current_setting('asg.h8') not like 'err:%'
  and exists (select 1 from public.workout_program_assignments
               where client_id = 'a9000000-0000-0000-0000-000000000011' and coach_id is null and status = 'active'),
  left(current_setting('asg.h8'), 100);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 helpers and triggers are closed to authenticated and anon; the clearance RPC is not open to anon',
  coalesce(bool_and(f is not null and not has_function_privilege('authenticated', f, 'execute')
                    and not has_function_privilege('anon', f, 'execute')), false)
  and coalesce(has_function_privilege('authenticated', to_regprocedure('public.engine_client_clearance(uuid)'), 'execute'), false)
  and not coalesce(has_function_privilege('anon', to_regprocedure('public.engine_client_clearance(uuid)'), 'execute'), true),
  coalesce(string_agg(n, ',') filter (where f is null), '')
  from (select n, to_regprocedure(n) f from unnest(array[
    'public._engine_selected_sticky()', 'public._engine_client_clearance(uuid)',
    'public._engine_assignment_guard()']) n) s;
insert into res select 'P02 the materialize wrapper keeps its authorization check and a pinned search_path',
  prosrc like '%can_act_on_program(p_program_id)%' and coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%', ''
  from pg_proc where oid = 'public.materialize_program_week(uuid,integer,jsonb)'::regprocedure;

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
