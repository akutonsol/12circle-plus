-- Assignment guards in every caller context (migration 193). LOCAL REPLAY ONLY —
-- run by assignment_caller_context_replay.sh, which refuses any non-loopback target
-- and any QA/production credential.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against a replay WITH 193 (every check passes) and one WITHOUT it but with
-- 189 + 192 (the negative control: the checks listed in the runner must FAIL).
--
-- Contexts exercised. API traffic is emulated faithfully: the session logs in as
-- `authenticator` (PostgREST's login role, which cannot bypass RLS) and then SETs
-- ROLE, exactly as PostgREST does.
--   * the service role WITH an unrelated user's claims, and WITHOUT any claims;
--   * the service role carrying the active coach's claims;
--   * a SECURITY DEFINER function (owner: postgres, so RLS never applies) called by
--     an unrelated signed-in user — the shape of any future definer write path;
--   * an ordinary signed-in caller (PostgREST: role authenticated, RLS applies);
--   * a TRUSTED owner session (login role postgres) carrying stale claims — it must
--     be checked fully, as if no one were signed in.
-- Fixtures: coach K (ACTIVE with I and C), coach O; I injured, C cleared, S an
-- unrelated member; KE = K's engine_selected programme, KH = K's hand-built
-- programme, OP = O's programme.

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
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 100); end $$;
create function pg_temp.assign(p text, c text, coach text) returns text language sql as
$$ select format('insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, %L, ''active'', 1)', p, c, coach) $$;
-- A SECURITY DEFINER writer owned by postgres: RLS never applies to its statements.
create function pg_temp.definer_assign(p text, c text, coach text) returns text
  language plpgsql security definer as $$ begin return pg_temp.try(pg_temp.assign(p, c, coach)); end $$;
grant execute on function pg_temp.try(text), pg_temp.assign(text, text, text), pg_temp.definer_assign(text, text, text)
  to authenticated, service_role;

insert into auth.users(id,email) values
 ('a5000000-0000-0000-0000-00000000000a','ctx-k@local'), ('a5000000-0000-0000-0000-00000000000b','ctx-o@local'),
 ('a5000000-0000-0000-0000-0000000000c1','ctx-injured@local'), ('a5000000-0000-0000-0000-0000000000c2','ctx-cleared@local'),
 ('a5000000-0000-0000-0000-0000000000d1','ctx-stranger@local'), ('a5000000-0000-0000-0000-0000000000d2','ctx-member@local')
 on conflict do nothing;
update public.user_profiles set role='coach' where id in ('a5000000-0000-0000-0000-00000000000a','a5000000-0000-0000-0000-00000000000b');
update public.user_profiles set onboarding_complete=true, has_injuries=true, injury_locations='Knee'
 where id='a5000000-0000-0000-0000-0000000000c1';
update public.user_profiles set onboarding_complete=true, has_injuries=false, injury_locations='',
  parq_answers='{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}',
  fitness_goal='build_muscle', training_days_per_week=3
 where id in ('a5000000-0000-0000-0000-0000000000c2','a5000000-0000-0000-0000-0000000000d2');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('a5000000-0000-0000-0000-00000000000a','a5000000-0000-0000-0000-0000000000c1','active','client'),
 ('a5000000-0000-0000-0000-00000000000a','a5000000-0000-0000-0000-0000000000c2','active','client');
insert into public.workout_programs(id, coach_id, name, is_template) values
 ('a5100000-0000-0000-0000-0000000000e1','a5000000-0000-0000-0000-00000000000a','ctx KE', false),
 ('a5100000-0000-0000-0000-0000000000a1','a5000000-0000-0000-0000-00000000000a','ctx KH', false),
 ('a5100000-0000-0000-0000-0000000000b1','a5000000-0000-0000-0000-00000000000b','ctx OP', false),
 ('a5100000-0000-0000-0000-0000000000e2','a5000000-0000-0000-0000-00000000000b','ctx OE', false);
update public.workout_programs set engine_selected = true
 where id in ('a5100000-0000-0000-0000-0000000000e1','a5100000-0000-0000-0000-0000000000e2');
select set_config('ctx.KE','a5100000-0000-0000-0000-0000000000e1',true), set_config('ctx.KH','a5100000-0000-0000-0000-0000000000a1',true),
       set_config('ctx.OP','a5100000-0000-0000-0000-0000000000b1',true), set_config('ctx.K','a5000000-0000-0000-0000-00000000000a',true),
       set_config('ctx.I','a5000000-0000-0000-0000-0000000000c1',true),  set_config('ctx.C','a5000000-0000-0000-0000-0000000000c2',true),
       set_config('ctx.S','a5000000-0000-0000-0000-0000000000d1',true),
       set_config('ctx.O','a5000000-0000-0000-0000-00000000000b',true),  set_config('ctx.OE','a5100000-0000-0000-0000-0000000000e2',true);

-- ═══ S · the service role ═════════════════════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('ctx.S')::uuid); set local session authorization authenticator; set local role service_role;
select set_config('ctx.s1', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.s2', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
select set_config('ctx.s3', pg_temp.try(pg_temp.assign(current_setting('ctx.OP'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
reset role; reset session authorization;
insert into res select 'S01 service role + an UNRELATED user''s claims: engine programme -> injured client is refused',
  current_setting('ctx.s1') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%', current_setting('ctx.s1');
insert into res select 'S02 …and -> a cleared client too, with the IDENTICAL message (no clearance oracle)',
  current_setting('ctx.s2') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%'
  and split_part(current_setting('ctx.s1'), ':', 3) = split_part(current_setting('ctx.s2'), ':', 3),
  current_setting('ctx.s2');
insert into res select 'S03 service role + unrelated claims: a row naming a coach and ANOTHER coach''s programme is refused',
  current_setting('ctx.s3') like 'err:42501:ASSIGNMENT_%', current_setting('ctx.s3');
insert into res select 'S04 …and none of those rows exists',
  count(*) = 0, count(*)||' row(s)' from public.workout_program_assignments where coach_id = current_setting('ctx.K')::uuid;
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(null); set local session authorization authenticator; set local role service_role;
select set_config('ctx.s5', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.s6', pg_temp.try(pg_temp.assign(current_setting('ctx.OP'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
select set_config('ctx.s7', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
reset role; reset session authorization;
insert into res select 'S05 service role WITHOUT claims: engine programme -> injured client is refused (clearance)',
  current_setting('ctx.s5') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('ctx.s5');
insert into res select 'S06 service role WITHOUT claims: a coach + another coach''s programme is refused (ownership)',
  current_setting('ctx.s6') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('ctx.s6');
insert into res select 'S07 service role WITHOUT claims: a coach''s own engine programme -> a cleared client is allowed',
  current_setting('ctx.s7') = 'ok:1', current_setting('ctx.s7');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(current_setting('ctx.K')::uuid); set local session authorization authenticator; set local role service_role;
select set_config('ctx.s8', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.s9', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
reset role; reset session authorization;
insert into res select 'S08 service role with the ACTIVE coach''s claims: injured client still refused by clearance',
  current_setting('ctx.s8') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('ctx.s8');
insert into res select 'S09 …and the cleared client is allowed', current_setting('ctx.s9') = 'ok:1', current_setting('ctx.s9');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- 189's own branch in isolation: the caller OWNS the engine programme and names
-- themselves as coach (so 192's ownership check passes), but has no relationship
-- with the client.
savepoint s;
select pg_temp.claims(current_setting('ctx.O')::uuid); set local session authorization authenticator; set local role service_role;
select set_config('ctx.s10', pg_temp.try(pg_temp.assign(current_setting('ctx.OE'), current_setting('ctx.I'), current_setting('ctx.O'))), true);
select set_config('ctx.s11', pg_temp.try(pg_temp.assign(current_setting('ctx.OE'), current_setting('ctx.C'), current_setting('ctx.O'))), true);
reset role; reset session authorization;
select pg_temp.claims(current_setting('ctx.O')::uuid); set local session authorization authenticator; set local role authenticated;
select set_config('ctx.d5', pg_temp.definer_assign(current_setting('ctx.OE'), current_setting('ctx.I'), current_setting('ctx.O')), true);
reset role; reset session authorization;
insert into res select 'S10 service role + the claims of a coach with NO relationship: their own engine programme -> injured client is refused',
  current_setting('ctx.s10') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED: you cannot assign a programme to this client%', current_setting('ctx.s10');
insert into res select 'S11 …and -> a cleared client, with the IDENTICAL message',
  current_setting('ctx.s11') like 'err:42501:%' and current_setting('ctx.s11') = current_setting('ctx.s10'),
  current_setting('ctx.s11');
insert into res select 'D05 definer context, a coach with NO relationship: their own engine programme -> injured client is refused',
  current_setting('ctx.d5') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED: you cannot assign a programme to this client%', current_setting('ctx.d5');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ D · a SECURITY DEFINER writer called by an unrelated user ════════════
savepoint s;
select pg_temp.claims(current_setting('ctx.S')::uuid); set local session authorization authenticator; set local role authenticated;
select set_config('ctx.d1', pg_temp.definer_assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K')), true);
select set_config('ctx.d2', pg_temp.definer_assign(current_setting('ctx.OP'), current_setting('ctx.C'), current_setting('ctx.K')), true);
select set_config('ctx.d3', pg_temp.definer_assign(current_setting('ctx.KH'), current_setting('ctx.I'), current_setting('ctx.K')), true);
reset role; reset session authorization;
insert into res select 'D01 definer context, unrelated caller: engine programme -> injured client is refused',
  current_setting('ctx.d1') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%', current_setting('ctx.d1');
insert into res select 'D02 definer context, unrelated caller: coach K + coach O''s programme is refused',
  current_setting('ctx.d2') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%', current_setting('ctx.d2');
insert into res select 'D03 definer context, unrelated caller: a row naming coach K at all is refused',
  current_setting('ctx.d3') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%', current_setting('ctx.d3');
insert into res select 'D04 …and none of those rows exists',
  count(*) = 0, count(*)||' row(s)' from public.workout_program_assignments where coach_id = current_setting('ctx.K')::uuid;
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ R · an ordinary signed-in caller (RLS applies) ═══════════════════════
savepoint s;
select pg_temp.claims(current_setting('ctx.S')::uuid); set local session authorization authenticator; set local role authenticated;
select set_config('ctx.r1', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.r2', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
reset role; reset session authorization;
insert into res select 'R01 an unrelated signed-in user is refused for an injured and a cleared client with the SAME error',
  current_setting('ctx.r1') like 'err:42501:%' and current_setting('ctx.r1') = current_setting('ctx.r2')
  and position('CLEARED' in current_setting('ctx.r1')) = 0,
  current_setting('ctx.r1');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ T · a trusted owner session with stale claims ════════════════════════
savepoint s;
select pg_temp.claims(current_setting('ctx.S')::uuid);   -- stale claims, still the postgres login
select set_config('ctx.t1', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.t2', pg_temp.try(pg_temp.assign(current_setting('ctx.OP'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
select set_config('ctx.t3', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
select pg_temp.claims(null);
insert into res select 'T01 owner session + stale claims: the injured client is still refused by clearance (claims do not exempt)',
  current_setting('ctx.t1') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('ctx.t1');
insert into res select 'T02 owner session + stale claims: another coach''s programme is still refused by ownership',
  current_setting('ctx.t2') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('ctx.t2');
insert into res select 'T03 owner session + stale claims: a legitimate row is written (claims do not refuse maintenance)',
  current_setting('ctx.t3') = 'ok:1', current_setting('ctx.t3');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ W · legitimate workflows ═════════════════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('ctx.K')::uuid); set local session authorization authenticator; set local role authenticated;
select set_config('ctx.w1', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.C'), current_setting('ctx.K'))), true);
select set_config('ctx.w2', pg_temp.try(pg_temp.assign(current_setting('ctx.KH'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.w3', pg_temp.try(pg_temp.assign(current_setting('ctx.KE'), current_setting('ctx.I'), current_setting('ctx.K'))), true);
select set_config('ctx.w4', pg_temp.try(format(
  'update public.workout_program_assignments set status = ''replaced'' where client_id = %L and status = ''active''', current_setting('ctx.C'))), true);
reset role; reset session authorization;
select pg_temp.claims('a5000000-0000-0000-0000-0000000000d2'); set local session authorization authenticator; set local role authenticated;
select public.generate_client_plan();
reset role; reset session authorization;
insert into res select 'W01 the active coach assigns their engine programme to a cleared client',
  current_setting('ctx.w1') = 'ok:1', current_setting('ctx.w1');
insert into res select 'W02 the active coach assigns a hand-built programme to an injured client',
  current_setting('ctx.w2') = 'ok:1', current_setting('ctx.w2');
insert into res select 'W03 the active coach is still told plainly that an injured client is not cleared',
  current_setting('ctx.w3') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('ctx.w3');
insert into res select 'W04 the active coach can replace an assignment', current_setting('ctx.w4') = 'ok:1', current_setting('ctx.w4');
insert into res select 'W05 a member''s self-plan (generate_client_plan, definer, coach-less) still assigns',
  exists (select 1 from public.workout_program_assignments
           where client_id = 'a5000000-0000-0000-0000-0000000000d2' and coach_id is null and status = 'active'), '';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 both guard functions are SECURITY DEFINER, pinned, and closed to authenticated and anon',
  count(*) = 2 and bool_and(prosecdef and coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'
                            and not has_function_privilege('authenticated', oid, 'execute')
                            and not has_function_privilege('anon', oid, 'execute')), string_agg(proname, ',')
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('_engine_assignment_guard', '_assignment_program_ownership');

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
