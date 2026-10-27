-- Assignment visibility leaks (migration 194). LOCAL REPLAY ONLY — run by
-- assignment_visibility_replay.sh, which refuses any non-loopback target and any
-- QA/production credential.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against a replay WITH 194 (every check passes) and one WITHOUT it but with
-- 189–193 (the negative control: the checks listed in the runner must FAIL).
--
-- API calls are emulated as PostgREST makes them: the session logs in as
-- `authenticator`, the request claims are set, then ROLE is set to authenticated or
-- service_role. A "trusted owner session" is the postgres login itself.
--
-- Fixtures
--   coach K; coach O; admin AD; content editor ED
--   CA  K's ACTIVE client, cleared        CB  K's ACTIVE client, injured
--   F1  K's FORMER client (cancelled), injured since      F2  K's FORMER client, cleared
--   OI  O's ACTIVE client, injured (holder of a legacy cross-coach row)
--   M, N members with self-generated plans
--   K's programmes (each with a Push/Pull/Legs plan): PA->CA, PB->CB, PF1->F1,
--   PF2->F2, PL (legacy cross-coach row: coach O, client OI), PU unassigned, and SRC
--   (marked, one generated-looking day with a UUID instance id)
--   T   a staff template (coach_id NULL, is_template true)

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
begin execute stmt into r; return 'ok:' || left(coalesce(r, 'null'), 50);
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
create function pg_temp.approve(e uuid, a text) returns void language plpgsql as $$
begin
  execute 'select public.review_attribute($1, $2, ''approved'', null, null, $3)'
    using e, a, public.attribute_review_state(e)->a->>'fingerprint';
end $$;
create function pg_temp.code(r text) returns text language sql as
$$ select case when r like 'err:%' then split_part(split_part(r, ':', 3), ':', 1) else r end $$;
create function pg_temp.paste(p text) returns text language sql as $$
  select format('insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 2, ''Friday'', ''pasted'', %L::jsonb, 9)',
    p, '[{"exercise_instance_id":"0b6e2c55-7d1a-4f3e-9a2b-1c3d4e5f6a7b","name":"copied bench","sets":3,"reps":10}]') $$;
create function pg_temp.coachless(p text, c text) returns text language sql as
$$ select format('insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, null, ''active'', 1)', p, c) $$;
grant execute on function pg_temp.try(text), pg_temp.call(text), pg_temp.approve(uuid, text), pg_temp.code(text),
  pg_temp.paste(text), pg_temp.coachless(text, text) to authenticated, service_role;

-- ── users ──────────────────────────────────────────────────────────────────
insert into auth.users(id,email) values
 ('a4000000-0000-0000-0000-00000000000a','vis-k@local'), ('a4000000-0000-0000-0000-00000000000b','vis-o@local'),
 ('a4000000-0000-0000-0000-0000000000ad','vis-admin@local'), ('a4000000-0000-0000-0000-0000000000ed','vis-editor@local'),
 ('a4000000-0000-0000-0000-0000000000ca','vis-ca@local'), ('a4000000-0000-0000-0000-0000000000cb','vis-cb@local'),
 ('a4000000-0000-0000-0000-0000000000f1','vis-f1@local'), ('a4000000-0000-0000-0000-0000000000f2','vis-f2@local'),
 ('a4000000-0000-0000-0000-0000000000c3','vis-oi@local'),
 ('a4000000-0000-0000-0000-0000000000e1','vis-m@local'), ('a4000000-0000-0000-0000-0000000000e2','vis-n@local')
 on conflict do nothing;
update public.user_profiles set role='coach' where id in ('a4000000-0000-0000-0000-00000000000a','a4000000-0000-0000-0000-00000000000b');
update public.user_profiles set role='admin' where id='a4000000-0000-0000-0000-0000000000ad';
update public.user_profiles set role='content_manager' where id='a4000000-0000-0000-0000-0000000000ed';
update public.user_profiles set onboarding_complete=true, has_injuries=false, injury_locations='',
  parq_answers='{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}',
  fitness_goal='build_muscle', training_days_per_week=3
 where id in ('a4000000-0000-0000-0000-0000000000ca','a4000000-0000-0000-0000-0000000000f1','a4000000-0000-0000-0000-0000000000f2',
              'a4000000-0000-0000-0000-0000000000e1','a4000000-0000-0000-0000-0000000000e2');
update public.user_profiles set onboarding_complete=true, has_injuries=true, injury_locations='Knee'
 where id in ('a4000000-0000-0000-0000-0000000000cb','a4000000-0000-0000-0000-0000000000c3');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('a4000000-0000-0000-0000-00000000000a','a4000000-0000-0000-0000-0000000000ca','active','client'),
 ('a4000000-0000-0000-0000-00000000000a','a4000000-0000-0000-0000-0000000000cb','active','client'),
 ('a4000000-0000-0000-0000-00000000000a','a4000000-0000-0000-0000-0000000000f1','active','client'),
 ('a4000000-0000-0000-0000-00000000000a','a4000000-0000-0000-0000-0000000000f2','active','client'),
 ('a4000000-0000-0000-0000-00000000000b','a4000000-0000-0000-0000-0000000000c3','active','client');

-- ── an eligible library, through the real review path ─────────────────────
update public.custom_exercises set content_status = 'approved',
  instructions = case when cardinality(instructions) = 0 then array['Move with control.'] else instructions end,
  alternatives = case when cardinality(alternatives) = 0 then array['(fixture alternative)'] else alternatives end;
insert into public.exercise_intelligence(exercise_id, attribute_confidence)
select id, '{"programming_goals":80,"fatigue":80,"joint_stress":80,"contraindications":80,"rep_ranges":80,"biomechanics":80,"loading":80,"coaching":80}'::jsonb
  from public.custom_exercises on conflict do nothing;
select pg_temp.claims('a4000000-0000-0000-0000-0000000000ed'); set local role authenticated;
select count(x::text) from (select pg_temp.approve(e.id, a) as x from public.custom_exercises e,
  unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading','coaching']) a) s;
select count(public.finalize_intelligence(id)) from public.custom_exercises;
reset role;
select pg_temp.claims(null);

-- ── programmes and assignments (written while every relationship is ACTIVE) ─
insert into public.workout_programs(id, coach_id, name, plan, is_template)
select ('a4100000-0000-0000-0000-0000000000'||n)::uuid, 'a4000000-0000-0000-0000-00000000000a', 'vis '||n,
       public.plan_program('{"frequency":3,"duration_weeks":4}'), false
  from unnest(array['a1','b1','f1','f2','11','e0','5c']) n;
insert into public.workout_programs(id, coach_id, name, is_template) values
 ('a4100000-0000-0000-0000-0000000000ff', null, 'vis staff template', true);
update public.workout_programs set engine_selected = true where id = 'a4100000-0000-0000-0000-00000000005c';
insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values
 ('a4100000-0000-0000-0000-00000000005c', 1, 'Monday', 'generated',
  '[{"exercise_instance_id":"0b6e2c55-7d1a-4f3e-9a2b-1c3d4e5f6a7b","name":"copied bench","sets":3,"reps":10}]', 0);
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values
 ('a4100000-0000-0000-0000-0000000000a1','a4000000-0000-0000-0000-0000000000ca','a4000000-0000-0000-0000-00000000000a','active',1),
 ('a4100000-0000-0000-0000-0000000000b1','a4000000-0000-0000-0000-0000000000cb','a4000000-0000-0000-0000-00000000000a','active',1),
 ('a4100000-0000-0000-0000-0000000000f1','a4000000-0000-0000-0000-0000000000f1','a4000000-0000-0000-0000-00000000000a','active',1),
 ('a4100000-0000-0000-0000-0000000000f2','a4000000-0000-0000-0000-0000000000f2','a4000000-0000-0000-0000-00000000000a','active',1);
-- A LEGACY cross-coach row (pre-192): coach O's assignment of K's programme PL.
alter table public.workout_program_assignments disable trigger user;
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values
 ('a4100000-0000-0000-0000-000000000011','a4000000-0000-0000-0000-0000000000c3','a4000000-0000-0000-0000-00000000000b','active',1);
alter table public.workout_program_assignments enable trigger user;
-- F1 and F2 END coaching the way the app does (cancelCoach); F1 reports an injury afterwards.
update public.coach_client_relationships set status = 'cancelled', cancelled_by = 'client', cancelled_at = now()
 where coach_id = 'a4000000-0000-0000-0000-00000000000a'
   and client_id in ('a4000000-0000-0000-0000-0000000000f1','a4000000-0000-0000-0000-0000000000f2');
update public.user_profiles set has_injuries = true, injury_locations = 'Back' where id = 'a4000000-0000-0000-0000-0000000000f1';
-- Members' self plans, generated through the API (definer path).
select pg_temp.claims('a4000000-0000-0000-0000-0000000000e2');
set local session authorization authenticator; set local role authenticated;
select public.generate_client_plan();
reset role; reset session authorization;
select set_config('vis.nplan', coalesce((select program_id::text from public.workout_program_assignments
  where client_id = 'a4000000-0000-0000-0000-0000000000e2' and coach_id is null and status = 'active' limit 1), ''), true);
select pg_temp.claims(null);
insert into res select 'F00 fixture: assignments written, F1/F2 cancelled with assignments still active, N has a self plan',
  (select count(*) from public.workout_program_assignments where coach_id = 'a4000000-0000-0000-0000-00000000000a' and status = 'active') = 4
  and current_setting('vis.nplan') <> '', 'self plan '||current_setting('vis.nplan');

select set_config('vis.K','a4000000-0000-0000-0000-00000000000a',true), set_config('vis.T','a4100000-0000-0000-0000-0000000000ff',true),
       set_config('vis.PA','a4100000-0000-0000-0000-0000000000a1',true), set_config('vis.PB','a4100000-0000-0000-0000-0000000000b1',true),
       set_config('vis.PF1','a4100000-0000-0000-0000-0000000000f1',true), set_config('vis.PF2','a4100000-0000-0000-0000-0000000000f2',true),
       set_config('vis.PL','a4100000-0000-0000-0000-000000000011',true), set_config('vis.PU','a4100000-0000-0000-0000-0000000000e0',true),
       set_config('vis.CA','a4000000-0000-0000-0000-0000000000ca',true);

-- ═══ A · former-client clearance ══════════════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('vis.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('vis.a1', pg_temp.try(pg_temp.paste(current_setting('vis.PF1'))), true);
select set_config('vis.a2', pg_temp.try(pg_temp.paste(current_setting('vis.PF2'))), true);
select set_config('vis.a3a', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF1'))), true);
select set_config('vis.a3b', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF2'))), true);
select set_config('vis.a4a', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PF1'))), true);
select set_config('vis.a4b', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PF2'))), true);
select set_config('vis.a5a', pg_temp.try(pg_temp.paste(current_setting('vis.PL'))), true);
select set_config('vis.a5b', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PL'))), true);
select set_config('vis.a12', pg_temp.try(format(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 3, ''Monday'', ''hand'', %L::jsonb, 0)',
  current_setting('vis.PF1'), '[{"exercise_instance_id":"ex-1730000000-9","name":"lunge","sets":3,"reps":10}]')), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'A01 pasting generated days into a programme of a FORMER client (now injured) is refused without consulting clearance',
  pg_temp.code(current_setting('vis.a1')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE', current_setting('vis.a1');
insert into res select 'A02 …and for a FORMER client who is still cleared, the outcome is IDENTICAL (no oracle)',
  pg_temp.code(current_setting('vis.a2')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE', current_setting('vis.a2');
insert into res select 'A03 marking either programme directly is refused the same way',
  pg_temp.code(current_setting('vis.a3a')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE'
  and pg_temp.code(current_setting('vis.a3b')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE',
  current_setting('vis.a3a')||' / '||current_setting('vis.a3b');
insert into res select 'A04 GENERATING onto either programme is refused the same way, and no day is written',
  pg_temp.code(current_setting('vis.a4a')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE'
  and pg_temp.code(current_setting('vis.a4b')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE'
  and not exists (select 1 from public.program_workouts where week_number = 1
                   and program_id in (current_setting('vis.PF1')::uuid, current_setting('vis.PF2')::uuid)),
  current_setting('vis.a4a')||' / '||current_setting('vis.a4b');
insert into res select 'A05 a LEGACY cross-coach row (another coach''s injured client) is refused the same way, paste and generate',
  pg_temp.code(current_setting('vis.a5a')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE'
  and pg_temp.code(current_setting('vis.a5b')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE',
  current_setting('vis.a5a')||' / '||current_setting('vis.a5b');
insert into res select 'A06 hand-built editing of a former client''s programme is unchanged',
  current_setting('vis.a12') = 'ok:1', current_setting('vis.a12');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(current_setting('vis.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('vis.a7', pg_temp.try(pg_temp.paste(current_setting('vis.PB'))), true);
select set_config('vis.a8', pg_temp.try(pg_temp.paste(current_setting('vis.PA'))), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'A07 a CURRENT injured client: the coach is still told plainly (ENGINE_CLIENT_NOT_CLEARED)',
  pg_temp.code(current_setting('vis.a7')) = 'ENGINE_CLIENT_NOT_CLEARED', current_setting('vis.a7');
insert into res select 'A08 a CURRENT cleared client: pasting is allowed and the programme is marked',
  current_setting('vis.a8') = 'ok:1' and (select engine_selected from public.workout_programs where id = current_setting('vis.PA')::uuid),
  current_setting('vis.a8');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(current_setting('vis.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('vis.a9', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PA'))), true);
select set_config('vis.a10a', pg_temp.try(format(
  'update public.workout_program_assignments set status = ''replaced'' where client_id = %L and status = ''active''', current_setting('vis.CA'))), true);
select set_config('vis.a10b', pg_temp.try(format(
  'insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, %L, ''active'', 1)',
  current_setting('vis.PU'), current_setting('vis.CA'), current_setting('vis.K'))), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'A09 the owner generates onto a programme assigned to a CURRENT cleared client',
  current_setting('vis.a9') like 'ok:%', current_setting('vis.a9');
insert into res select 'A10 assignment replacement for a current client still works',
  current_setting('vis.a10a') = 'ok:1' and current_setting('vis.a10b') = 'ok:1',
  current_setting('vis.a10a')||' / '||current_setting('vis.a10b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- trusted contexts: checked fully (and entitled to the verdict)
savepoint s;
select pg_temp.claims(current_setting('vis.K')::uuid);    -- stale claims in an owner session
select set_config('vis.a11a', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF1'))), true);
select set_config('vis.a11b', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF2'))), true);
select pg_temp.claims(null);
insert into res select 'A11 owner maintenance (stale claims): full clearance check — injured refused, cleared allowed',
  pg_temp.code(current_setting('vis.a11a')) = 'ENGINE_CLIENT_NOT_CLEARED' and current_setting('vis.a11b') = 'ok:1',
  current_setting('vis.a11a')||' / '||current_setting('vis.a11b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(null);
set local session authorization authenticator; set local role service_role;
select set_config('vis.a12a', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF1'))), true);
select set_config('vis.a12b', pg_temp.try(format('update public.workout_programs set engine_selected = true where id = %L', current_setting('vis.PF2'))), true);
reset role; reset session authorization;
insert into res select 'A12 service role without claims: full clearance check — injured refused, cleared allowed',
  pg_temp.code(current_setting('vis.a12a')) = 'ENGINE_CLIENT_NOT_CLEARED' and current_setting('vis.a12b') = 'ok:1',
  current_setting('vis.a12a')||' / '||current_setting('vis.a12b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims('a4000000-0000-0000-0000-0000000000ad');
set local session authorization authenticator; set local role authenticated;
select set_config('vis.a13a', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PF2'))), true);
select set_config('vis.a13b', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('vis.PU'))), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'A13 an admin through the API is not entitled to the verdict: generation onto an assigned programme is refused',
  pg_temp.code(current_setting('vis.a13a')) = 'ENGINE_ASSIGNMENT_UNVERIFIABLE', current_setting('vis.a13a');
insert into res select 'A14 …while an admin can still generate onto an unassigned programme',
  current_setting('vis.a13b') like 'ok:%', current_setting('vis.a13b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ B · coach-less rows through the API ══════════════════════════════════
savepoint s;
select pg_temp.claims(current_setting('vis.CA')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('vis.b1', pg_temp.try(pg_temp.coachless(current_setting('vis.PA'), current_setting('vis.CA'))), true);
select set_config('vis.b2', pg_temp.try(pg_temp.coachless(current_setting('vis.T'), current_setting('vis.CA'))), true);
select set_config('vis.b3', pg_temp.try(pg_temp.coachless(current_setting('vis.nplan'), current_setting('vis.CA'))), true);
reset role; reset session authorization;
select pg_temp.claims(current_setting('vis.K')::uuid);
set local session authorization authenticator; set local role authenticated;
select set_config('vis.b4', pg_temp.try(pg_temp.coachless(current_setting('vis.T'), current_setting('vis.CA'))), true);
select set_config('vis.b4b', pg_temp.try(pg_temp.coachless(current_setting('vis.PA'), current_setting('vis.CA'))), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'B01 a client''s coach-less API write naming a COACH-OWNED programme is refused (ASSIGNMENT_NOT_AUTHORIZED)',
  current_setting('vis.b1') like 'err:42501:ASSIGNMENT_NOT_AUTHORIZED%', current_setting('vis.b1');
insert into res select 'B02 …naming a STAFF TEMPLATE gives the IDENTICAL error',
  current_setting('vis.b2') = current_setting('vis.b1'), current_setting('vis.b2');
insert into res select 'B03 …naming another member''s SELF PLAN gives the IDENTICAL error',
  current_setting('vis.b3') = current_setting('vis.b1'), current_setting('vis.b3');
insert into res select 'B04 a coach''s coach-less API write gets the IDENTICAL error for a template and an owned programme',
  current_setting('vis.b4') = current_setting('vis.b1') and current_setting('vis.b4b') = current_setting('vis.b1'),
  current_setting('vis.b4')||' / '||current_setting('vis.b4b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims('a4000000-0000-0000-0000-0000000000e1');
set local session authorization authenticator; set local role authenticated;
select set_config('vis.b5a', pg_temp.call('select public.generate_client_plan()::text'), true);
select set_config('vis.b5b', pg_temp.call('select public.generate_client_plan()::text'), true);
select set_config('vis.b5c', pg_temp.call('select public.deactivate_self_generated_plan()::text'), true);
reset role; reset session authorization;
select pg_temp.claims(null);
insert into res select 'B05 a member''s self plan (definer) is generated, REgenerated and turned off through the API',
  current_setting('vis.b5a') like 'ok:%' and current_setting('vis.b5b') like 'ok:%' and current_setting('vis.b5c') like 'ok:%'
  and not exists (select 1 from public.workout_program_assignments
                   where client_id = 'a4000000-0000-0000-0000-0000000000e1' and coach_id is null and status = 'active'),
  current_setting('vis.b5a')||' / '||current_setting('vis.b5b')||' / '||current_setting('vis.b5c');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.claims(current_setting('vis.CA')::uuid);    -- stale claims in an owner session
select set_config('vis.b6a', pg_temp.try(pg_temp.coachless(current_setting('vis.T'), current_setting('vis.CA'))), true);
select set_config('vis.b6b', pg_temp.try(pg_temp.coachless(current_setting('vis.PA'), current_setting('vis.CA'))), true);
select pg_temp.claims(null);
set local session authorization authenticator; set local role service_role;
select set_config('vis.b7a', pg_temp.try(pg_temp.coachless(current_setting('vis.nplan'), 'a4000000-0000-0000-0000-0000000000e2')), true);
select set_config('vis.b7b', pg_temp.try(pg_temp.coachless(current_setting('vis.PA'), 'a4000000-0000-0000-0000-0000000000e2')), true);
reset role; reset session authorization;
insert into res select 'B06 owner maintenance: a staff template can be attached coach-less; a coach-owned programme cannot (ownership)',
  current_setting('vis.b6a') = 'ok:1' and current_setting('vis.b6b') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%',
  current_setting('vis.b6a')||' / '||current_setting('vis.b6b');
insert into res select 'B07 service role (no claims): a self plan can be written coach-less; a coach-owned programme cannot',
  current_setting('vis.b7a') = 'ok:1' and current_setting('vis.b7b') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%',
  current_setting('vis.b7a')||' / '||current_setting('vis.b7b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 posture: the API-scope trigger is INVOKER and fires first; the decision helpers are DEFINER; all pinned and closed',
  coalesce((select not prosecdef from pg_proc where oid = to_regprocedure('public._assignment_api_write_scope()')), false)
  and coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public._engine_marking_block(uuid)')), false)
  and coalesce((select tgname from pg_trigger where tgrelid = 'public.workout_program_assignments'::regclass
                  and not tgisinternal order by tgname limit 1) = 'assignment_api_write_scope', false)
  and coalesce((select count(*) = 3 and bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'
                       and not has_function_privilege('authenticated', oid, 'execute')
                       and not has_function_privilege('anon', oid, 'execute'))
         from pg_proc where oid in (to_regprocedure('public._assignment_api_write_scope()'),
           to_regprocedure('public._engine_marking_block(uuid)'), to_regprocedure('public._engine_marking_raise(uuid,text,text)'))), false),
  '';

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
