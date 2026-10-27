-- Programme ownership, authoring rights and day provenance (migration 192).
-- LOCAL REPLAY ONLY — run by program_ownership_replay.sh, which refuses any
-- non-loopback target and any QA/production credential.
--
-- One transaction, always ROLLED BACK. Prints PASS|id|detail or FAIL|id|detail.
-- Run against a replay WITH 192 (every check passes) and one WITHOUT it (the
-- negative control: the checks listed in the runner — every bypass the audit
-- confirmed — must FAIL). Needs 187–190 (engine gate, engine_selected, clearance).
--
-- Fixtures
--   coaches K and O; admin A; content editor E
--   KC  K's ACTIVE client, cleared (complete intake, no injury, low-risk PAR-Q)
--   KI  K's ACTIVE client, injured
--   OI  O's ACTIVE client, injured
--   M   member with a self-generated plan; K is M's ACTIVE coach
--   KP  K's programme (PPL plan), assigned to KC — K generates it
--   KH  K's hand-built programme (no plan)   KH2 K's second hand-built programme
--   OP  O's private programme with a coach-edited week 1 day
--   T   a staff template (coach_id NULL, is_template true)

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated, service_role;
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.try(stmt text) returns text language plpgsql as $$
declare n bigint;
begin execute 'with x as (' || stmt || ' returning 1) select count(*) from x' into n; return 'ok:' || n;
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
create function pg_temp.call(stmt text) returns text language plpgsql as $$
declare r text;
begin execute stmt into r; return 'ok:' || left(coalesce(r, 'null'), 60);
exception when others then return 'err:' || sqlstate || ':' || left(sqlerrm, 110); end $$;
create function pg_temp.approve(e uuid, a text) returns void language plpgsql as $$
begin
  execute 'select public.review_attribute($1, $2, ''approved'', null, null, $3)'
    using e, a, public.attribute_review_state(e)->a->>'fingerprint';
end $$;
grant execute on function pg_temp.try(text), pg_temp.call(text), pg_temp.approve(uuid, text) to authenticated, service_role;
create function pg_temp.assign(p text, c text, coach text, st text default 'active') returns text language sql as
$$ select format('insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values (%L, %L, %L, %L, 1)', p, c, coach, st) $$;
grant execute on function pg_temp.assign(text, text, text, text) to authenticated, service_role;

-- ── users ──────────────────────────────────────────────────────────────────
insert into auth.users(id,email) values
 ('a6000000-0000-0000-0000-00000000000a','own-k@local'), ('a6000000-0000-0000-0000-00000000000b','own-o@local'),
 ('a6000000-0000-0000-0000-0000000000ad','own-admin@local'), ('a6000000-0000-0000-0000-0000000000ed','own-editor@local'),
 ('a6000000-0000-0000-0000-0000000000c1','own-kc@local'), ('a6000000-0000-0000-0000-0000000000c2','own-ki@local'),
 ('a6000000-0000-0000-0000-0000000000c3','own-oi@local'), ('a6000000-0000-0000-0000-0000000000c4','own-m@local')
 on conflict do nothing;
update public.user_profiles set role='coach' where id in ('a6000000-0000-0000-0000-00000000000a','a6000000-0000-0000-0000-00000000000b');
update public.user_profiles set role='admin' where id='a6000000-0000-0000-0000-0000000000ad';
update public.user_profiles set role='content_manager' where id='a6000000-0000-0000-0000-0000000000ed';
update public.user_profiles set onboarding_complete=true, has_injuries=false, injury_locations='',
  parq_answers='{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}',
  fitness_goal='build_muscle', training_days_per_week=3
 where id in ('a6000000-0000-0000-0000-0000000000c1','a6000000-0000-0000-0000-0000000000c4');
update public.user_profiles set onboarding_complete=true, has_injuries=true, injury_locations='Knee'
 where id in ('a6000000-0000-0000-0000-0000000000c2','a6000000-0000-0000-0000-0000000000c3');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('a6000000-0000-0000-0000-00000000000a','a6000000-0000-0000-0000-0000000000c1','active','client'),
 ('a6000000-0000-0000-0000-00000000000a','a6000000-0000-0000-0000-0000000000c2','active','client'),
 ('a6000000-0000-0000-0000-00000000000a','a6000000-0000-0000-0000-0000000000c4','active','client'),
 ('a6000000-0000-0000-0000-00000000000b','a6000000-0000-0000-0000-0000000000c3','active','client');

-- ── an eligible library, through the real review path ─────────────────────
update public.custom_exercises set content_status = 'approved',
  instructions = case when cardinality(instructions) = 0 then array['Move with control.'] else instructions end,
  alternatives = case when cardinality(alternatives) = 0 then array['(fixture alternative)'] else alternatives end;
insert into public.exercise_intelligence(exercise_id, attribute_confidence)
select id, '{"programming_goals":80,"fatigue":80,"joint_stress":80,"contraindications":80,"rep_ranges":80,"biomechanics":80,"loading":80,"coaching":80}'::jsonb
  from public.custom_exercises on conflict do nothing;
select pg_temp.as_user('a6000000-0000-0000-0000-0000000000ed'); set local role authenticated;
select count(x::text) from (select pg_temp.approve(e.id, a) as x from public.custom_exercises e,
  unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading','coaching']) a) s;
select count(public.finalize_intelligence(id)) from public.custom_exercises;
reset role;
select set_config('request.jwt.claims', '', true);

-- ── programmes ─────────────────────────────────────────────────────────────
insert into public.workout_programs(id, coach_id, name, plan, is_template) values
 ('a6100000-0000-0000-0000-0000000000a1','a6000000-0000-0000-0000-00000000000a','own KP',
    public.plan_program('{"frequency":3,"duration_weeks":4}'), false),
 ('a6100000-0000-0000-0000-0000000000a2','a6000000-0000-0000-0000-00000000000a','own KH', null, false),
 ('a6100000-0000-0000-0000-0000000000a3','a6000000-0000-0000-0000-00000000000a','own KH2', null, false),
 ('a6100000-0000-0000-0000-0000000000b1','a6000000-0000-0000-0000-00000000000b','own OP',
    public.plan_program('{"frequency":3,"duration_weeks":4}'), false),
 ('a6100000-0000-0000-0000-0000000000f1', null, 'own staff template', null, true);
insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values
 ('a6100000-0000-0000-0000-0000000000b1', 1, 'Monday', 'O COACH-EDITED DAY',
  '[{"exercise_instance_id":"ex-1-1","name":"o secret press","sets":5,"reps":5,"weight_kg":100}]', 0),
 ('a6100000-0000-0000-0000-0000000000a2', 1, 'Monday', 'KH hand-built day',
  '[{"exercise_instance_id":"ex-1730000000-1","name":"goblet squat","sets":3,"reps":10,"weight_kg":null}]', 0);
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values
 ('a6100000-0000-0000-0000-0000000000a1','a6000000-0000-0000-0000-0000000000c1','a6000000-0000-0000-0000-00000000000a','active',1);
-- A LEGACY cross-coach row, as could exist from before this migration: K's
-- assignment of O's programme to K's client. Written as the owner, bypassing RLS
-- and — on a 192 replay — the ownership trigger, so the read/authoring checks can
-- be tested against it.
alter table public.workout_program_assignments disable trigger user;
insert into public.workout_program_assignments(id, program_id, client_id, coach_id, status, current_week) values
 ('a6200000-0000-0000-0000-0000000000e1','a6100000-0000-0000-0000-0000000000b1','a6000000-0000-0000-0000-0000000000c1',
  'a6000000-0000-0000-0000-00000000000a','replaced',1);
alter table public.workout_program_assignments enable trigger user;
-- M's self-generated plan.
select pg_temp.as_user('a6000000-0000-0000-0000-0000000000c4'); set local role authenticated;
select public.generate_client_plan();
reset role;
select set_config('own.mplan', coalesce((select program_id::text from public.workout_program_assignments
  where client_id='a6000000-0000-0000-0000-0000000000c4' and coach_id is null and status='active' limit 1), ''), true);
select set_config('request.jwt.claims', '', true);

select set_config('own.K',  'a6000000-0000-0000-0000-00000000000a', true);
select set_config('own.O',  'a6000000-0000-0000-0000-00000000000b', true);
select set_config('own.KC', 'a6000000-0000-0000-0000-0000000000c1', true);
select set_config('own.KI', 'a6000000-0000-0000-0000-0000000000c2', true);
select set_config('own.OI', 'a6000000-0000-0000-0000-0000000000c3', true);
select set_config('own.KP', 'a6100000-0000-0000-0000-0000000000a1', true);
select set_config('own.KH', 'a6100000-0000-0000-0000-0000000000a2', true);
select set_config('own.KH2','a6100000-0000-0000-0000-0000000000a3', true);
select set_config('own.OP', 'a6100000-0000-0000-0000-0000000000b1', true);
select set_config('own.T',  'a6100000-0000-0000-0000-0000000000f1', true);
insert into res select 'F00 fixture: library eligible, self plan generated, legacy cross-coach row present',
  current_setting('own.mplan') <> ''
  and exists (select 1 from public.workout_program_assignments where id='a6200000-0000-0000-0000-0000000000e1'),
  'self plan '||current_setting('own.mplan');

-- ═══ O · assignment ownership ═════════════════════════════════════════════
savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.o1', pg_temp.try(pg_temp.assign(current_setting('own.OP'), current_setting('own.KC'), current_setting('own.K'))), true);
select set_config('own.o2a', pg_temp.try(pg_temp.assign(current_setting('own.KH'), current_setting('own.KC'), current_setting('own.K'), 'replaced')), true);
select set_config('own.o2', pg_temp.try(format('update public.workout_program_assignments set program_id = %L where program_id = %L and client_id = %L and coach_id = %L',
  current_setting('own.OP'), current_setting('own.KH'), current_setting('own.KC'), current_setting('own.K'))), true);
select set_config('own.o3', pg_temp.try('update public.workout_program_assignments set status = ''active'' where id = ''a6200000-0000-0000-0000-0000000000e1'''), true);
select set_config('own.o4', pg_temp.try(pg_temp.assign(current_setting('own.T'), current_setting('own.KC'), current_setting('own.K'))), true);
reset role;
insert into res select 'O01 a coach cannot ATTACH another coach''s programme to their client (insert)',
  current_setting('own.o1') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('own.o1');
insert into res select 'O02 …nor RE-POINT an existing assignment at it (update)',
  current_setting('own.o2a') = 'ok:1' and current_setting('own.o2') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%',
  current_setting('own.o2a')||' / '||current_setting('own.o2');
insert into res select 'O03 …nor REACTIVATE a legacy cross-coach row',
  current_setting('own.o3') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('own.o3');
insert into res select 'O04 …nor attach a staff template (coach-less, is_template)',
  current_setting('own.o4') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('own.o4');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.o5a', pg_temp.try(format('update public.workout_program_assignments set status = ''replaced'' where client_id = %L and status = ''active''', current_setting('own.KC'))), true);
select set_config('own.o5b', pg_temp.try(pg_temp.assign(current_setting('own.KH'), current_setting('own.KC'), current_setting('own.K'))), true);
select set_config('own.o5c', pg_temp.try('update public.workout_program_assignments set status = ''cancelled'' where id = ''a6200000-0000-0000-0000-0000000000e1'''), true);
reset role;
select pg_temp.as_user(current_setting('own.O')::uuid); set local role authenticated;
select set_config('own.o6', pg_temp.try(pg_temp.assign(current_setting('own.KP'), current_setting('own.KC'), current_setting('own.K'))), true);
select set_config('own.o7', pg_temp.try(pg_temp.assign(current_setting('own.KH'), current_setting('own.OI'), current_setting('own.O'))), true);
reset role;
set local role service_role;
select set_config('own.o8', pg_temp.try(pg_temp.assign(current_setting('own.OP'), current_setting('own.KC'), current_setting('own.K'))), true);
reset role;
insert into res select 'O05 the owner''s replace-then-assign flow works, and a legacy row can still be retired',
  current_setting('own.o5a') = 'ok:1' and current_setting('own.o5b') = 'ok:1' and current_setting('own.o5c') = 'ok:1',
  current_setting('own.o5a')||' / '||current_setting('own.o5b')||' / '||current_setting('own.o5c');
insert into res select 'O06 a coach naming ANOTHER coach is refused by RLS, and the error says nothing about ownership',
  current_setting('own.o6') like 'err:42501:%' and position('OWNED' in current_setting('own.o6')) = 0, current_setting('own.o6');
insert into res select 'O07 the griefing path is closed: O cannot attach K''s programme to O''s injured client',
  current_setting('own.o7') like 'err:42501:ASSIGNMENT_PROGRAM_NOT_OWNED%', current_setting('own.o7');
-- 192 refuses this as ASSIGNMENT_PROGRAM_NOT_OWNED; 193 refuses it earlier as
-- ASSIGNMENT_NOT_AUTHORIZED (the caller's claims name another coach). Either way
-- it must be refused and nothing written.
insert into res select 'O08 the service role cannot write a cross-coach assignment either',
  current_setting('own.o8') like 'err:42501:ASSIGNMENT_%'
  and not exists (select 1 from public.workout_program_assignments
                   where program_id = current_setting('own.OP')::uuid and client_id = current_setting('own.KC')::uuid
                     and status = 'active'),
  current_setting('own.o8');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ R · read rights ══════════════════════════════════════════════════════
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.r1', (select count(*)::text from public.program_workouts where program_id = current_setting('own.OP')::uuid), true);
select set_config('own.r1b', (select count(*)::text from public.workout_programs where id = current_setting('own.OP')::uuid), true);
select set_config('own.r2', (select count(*)::text from public.workout_programs where id = current_setting('own.KP')::uuid), true);
select set_config('own.r3', (select count(*)::text from public.program_workouts where program_id::text = current_setting('own.mplan')), true);
reset role;
select pg_temp.as_user(current_setting('own.KC')::uuid); set local role authenticated;
select set_config('own.r4', (select count(*)::text from public.workout_programs where id = current_setting('own.KP')::uuid), true);
reset role;
insert into res select 'R01 a legacy cross-coach row no longer lets K read O''s programme or its days',
  current_setting('own.r1') = '0' and current_setting('own.r1b') = '0',
  current_setting('own.r1')||' day(s), '||current_setting('own.r1b')||' programme row(s)';
insert into res select 'R02 the owner reads their own programme', current_setting('own.r2') = '1', current_setting('own.r2');
insert into res select 'R03 a coach still reads an active client''s SELF-GENERATED plan',
  current_setting('own.r3')::int > 0, current_setting('own.r3')||' day(s)';
insert into res select 'R04 an assigned client still reads the programme assigned to them', current_setting('own.r4') = '1', current_setting('own.r4');

-- ═══ A · authoring rights ═════════════════════════════════════════════════
savepoint s;
-- Make the legacy row ACTIVE (as the owner, triggers off) so K holds every
-- assignment-based right the old helpers granted.
alter table public.workout_program_assignments disable trigger user;
update public.workout_program_assignments set status = 'active' where id = 'a6200000-0000-0000-0000-0000000000e1';
alter table public.workout_program_assignments enable trigger user;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.a1', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{"replace_existing": true}'')::text', current_setting('own.OP'))), true);
select set_config('own.a3', pg_temp.call(format('select public.regenerate_program(%L, 1, true)::text', current_setting('own.OP'))), true);
select set_config('own.a4', pg_temp.call(format('select public.snapshot_program_version(%L, ''k'')::text', current_setting('own.OP'))), true);
reset role;
select pg_temp.as_user(current_setting('own.KC')::uuid); set local role authenticated;
select set_config('own.a2', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('own.KP'))), true);
select set_config('own.a2b', pg_temp.call(format('select public.materialize_program_week(%L, 2, ''{"replace_existing": true}'')::text', current_setting('own.OP'))), true);
reset role;
insert into res select 'A01 a coach cannot GENERATE/REPLACE another coach''s week through an assignment (42501)',
  current_setting('own.a1') like 'err:42501:%', current_setting('own.a1');
insert into res select 'A02 …and O''s coach-edited day is intact',
  exists (select 1 from public.program_workouts where program_id = current_setting('own.OP')::uuid and title = 'O COACH-EDITED DAY'), '';
insert into res select 'A03 a coach cannot REGENERATE another coach''s plan (42501)',
  current_setting('own.a3') like 'err:42501:%', current_setting('own.a3');
insert into res select 'A04 a coach cannot SNAPSHOT another coach''s programme (42501), version unchanged',
  current_setting('own.a4') like 'err:42501:%'
  and (select coalesce(program_version, 1) from public.workout_programs where id = current_setting('own.OP')::uuid) = 1,
  current_setting('own.a4');
insert into res select 'A05 an assigned CLIENT cannot generate or replace their coach''s programme (42501)',
  current_setting('own.a2') like 'err:42501:%' and current_setting('own.a2b') like 'err:42501:%',
  current_setting('own.a2')||' / '||current_setting('own.a2b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.a6', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('own.KP'))), true);
select set_config('own.a7', pg_temp.call(format('select public.snapshot_program_version(%L, ''owner'')::text', current_setting('own.KP'))), true);
select set_config('own.a8', pg_temp.call(format('select public.regenerate_program(%L, 1, false)::text', current_setting('own.KP'))), true);
reset role;
select pg_temp.as_user('a6000000-0000-0000-0000-0000000000ad'); set local role authenticated;
select set_config('own.a9', pg_temp.call(format('select public.snapshot_program_version(%L, ''admin'')::text', current_setting('own.OP'))), true);
reset role;
insert into res select 'A06 the OWNER generates their programme (assigned to a cleared client) and it is marked',
  current_setting('own.a6') like 'ok:%'
  and (select engine_selected from public.workout_programs where id = current_setting('own.KP')::uuid),
  current_setting('own.a6');
insert into res select 'A07 the owner can snapshot and regenerate their own programme',
  current_setting('own.a7') like 'ok:%' and current_setting('own.a8') like 'ok:%',
  current_setting('own.a7')||' / '||current_setting('own.a8');
insert into res select 'A08 an admin keeps authoring rights', current_setting('own.a9') like 'ok:%', current_setting('own.a9');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ V · day provenance ═══════════════════════════════════════════════════
-- K generates KP (marked), then tries to carry its days out from under the mark.
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.vgen', pg_temp.call(format('select public.materialize_program_week(%L, 1, ''{}'')::text', current_setting('own.KP'))), true);
reset role;
select set_config('own.vday', coalesce((select id::text from public.program_workouts
  where program_id = current_setting('own.KP')::uuid and week_number = 1 order by sort_order limit 1), ''), true);
select set_config('own.vex', coalesce((select exercises::text from public.program_workouts
  where id::text = current_setting('own.vday')), '[]'), true);
insert into res select 'V00 fixture: K''s generated programme is marked and its day carries UUID instance ids',
  current_setting('own.vgen') like 'ok:%'
  and (select engine_selected from public.workout_programs where id = current_setting('own.KP')::uuid)
  and coalesce(current_setting('own.vex')::jsonb->0->>'exercise_instance_id', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  current_setting('own.vgen');

savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.v1', pg_temp.try(format('update public.program_workouts set program_id = %L where id = %L',
  current_setting('own.KH'), current_setting('own.vday'))), true);
reset role;
insert into res select 'V01 MOVING a generated day into an unmarked programme is refused',
  current_setting('own.v1') like 'err:42501:PROGRAM_DAY_MOVE_REFUSED%'
  and exists (select 1 from public.program_workouts where id::text = current_setting('own.vday') and program_id = current_setting('own.KP')::uuid),
  current_setting('own.v1');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.v2', pg_temp.try(format(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 1, ''Tuesday'', ''copied'', %L::jsonb, 1)',
  current_setting('own.KH'), current_setting('own.vex'))), true);
select set_config('own.v3', pg_temp.try(pg_temp.assign(current_setting('own.KH'), current_setting('own.KI'), current_setting('own.K'))), true);
reset role;
insert into res select 'V02 a verbatim COPY of generated days marks the target programme engine_selected',
  current_setting('own.v2') = 'ok:1' and (select engine_selected from public.workout_programs where id = current_setting('own.KH')::uuid),
  current_setting('own.v2');
insert into res select 'V03 …so assigning the copy to an INJURED client is refused (ENGINE_CLIENT_NOT_CLEARED)',
  current_setting('own.v3') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%', current_setting('own.v3');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
-- KH is first assigned (unmarked, legitimately) to the injured client; then the copy is pasted in.
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.v4a', pg_temp.try(pg_temp.assign(current_setting('own.KH'), current_setting('own.KI'), current_setting('own.K'))), true);
select set_config('own.v4', pg_temp.try(format(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 1, ''Tuesday'', ''copied'', %L::jsonb, 1)',
  current_setting('own.KH'), current_setting('own.vex'))), true);
select set_config('own.v5', pg_temp.try(format(
  'update public.program_workouts set exercises = %L::jsonb where program_id = %L and title = ''KH hand-built day''',
  current_setting('own.vex'), current_setting('own.KH'))), true);
reset role;
insert into res select 'V04 pasting generated days into a programme ALREADY active for an injured client is refused',
  current_setting('own.v4a') = 'ok:1' and current_setting('own.v4') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%'
  and not (select engine_selected from public.workout_programs where id = current_setting('own.KH')::uuid),
  current_setting('own.v4a')||' / '||current_setting('own.v4');
insert into res select 'V05 …and so is overwriting an existing day''s exercises with them (UPDATE)',
  current_setting('own.v5') like 'err:42501:ENGINE_CLIENT_NOT_CLEARED%'
  and exists (select 1 from public.program_workouts where program_id = current_setting('own.KH')::uuid
               and title = 'KH hand-built day' and exercises->0->>'name' = 'goblet squat'),
  current_setting('own.v5');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.v6a', pg_temp.try(format(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 1, ''Tuesday'', ''hand day'', %L::jsonb, 1)',
  current_setting('own.KH2'), '[{"exercise_instance_id":"ex-1730000000-7","name":"push-up","sets":3,"reps":12,"weight_kg":null}]')), true);
select set_config('own.v6b', pg_temp.try(format(
  'update public.program_workouts set title = ''edited'', exercises = exercises || %L::jsonb where id = %L',
  '[{"exercise_instance_id":"ex-1730000000-8","name":"plank","sets":3,"reps":30,"weight_kg":null}]', current_setting('own.vday'))), true);
select set_config('own.v6c', pg_temp.try(pg_temp.assign(current_setting('own.KH2'), current_setting('own.KI'), current_setting('own.K'))), true);
reset role;
insert into res select 'V06 hand-built editing stays unmarked and assignable to the injured client (positive control)',
  current_setting('own.v6a') = 'ok:1' and current_setting('own.v6c') = 'ok:1'
  and not (select engine_selected from public.workout_programs where id = current_setting('own.KH2')::uuid),
  current_setting('own.v6a')||' / '||current_setting('own.v6c');
insert into res select 'V07 the owner can still edit a day of the generated programme in place',
  current_setting('own.v6b') = 'ok:1', current_setting('own.v6b');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- V08 · a Copilot-saved programme (marked at creation, UUID instance ids as the
-- app now mints them): a verbatim copy of its day carries the mark too.
savepoint s;
select pg_temp.as_user(current_setting('own.K')::uuid); set local role authenticated;
select set_config('own.v8a', pg_temp.try(format(
  'insert into public.workout_programs(id, coach_id, name, engine_selected) values (''a6100000-0000-0000-0000-0000000000a4'', %L, ''Copilot session'', true)',
  current_setting('own.K'))), true);
select set_config('own.v8b', pg_temp.try(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (''a6100000-0000-0000-0000-0000000000a4'', 1, ''Monday'', ''Copilot Session'', ''[{"exercise_instance_id":"3f2c8a1e-5b7d-4c9a-8e6f-0a1b2c3d4e5f","name":"bench press","sets":3,"reps":10}]''::jsonb, 0)'), true);
select set_config('own.v8', pg_temp.try(format(
  'insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order) values (%L, 1, ''Monday'', ''copied copilot'', ''[{"exercise_instance_id":"3f2c8a1e-5b7d-4c9a-8e6f-0a1b2c3d4e5f","name":"bench press","sets":3,"reps":10}]''::jsonb, 0)',
  current_setting('own.KH2'))), true);
reset role;
insert into res select 'V08 a verbatim copy of a Copilot-saved day marks the target programme too',
  current_setting('own.v8a') = 'ok:1' and current_setting('own.v8b') = 'ok:1' and current_setting('own.v8') = 'ok:1'
  and (select engine_selected from public.workout_programs where id = current_setting('own.KH2')::uuid),
  current_setting('own.v8a')||' / '||current_setting('own.v8b')||' / '||current_setting('own.v8');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

insert into res select 'P01 posture: helpers and trigger functions closed to authenticated and anon; RPCs pinned',
  coalesce(bool_and(f is not null and not has_function_privilege('authenticated', f, 'execute')
                    and not has_function_privilege('anon', f, 'execute')), false)
  and (select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%')
         from pg_proc where oid in ('public.materialize_program_week(uuid,integer,jsonb)'::regprocedure,
           'public.regenerate_program(uuid,integer,boolean)'::regprocedure,
           'public.snapshot_program_version(uuid,text)'::regprocedure, 'public.can_read_program(uuid)'::regprocedure)),
  coalesce(string_agg(n, ',') filter (where f is null), '')
  from (select n, to_regprocedure(n) f from unnest(array[
    'public._program_author_or_admin(uuid)', 'public._is_uuid_text(text)',
    'public._assignment_program_ownership()', 'public._program_workouts_provenance()']) n) s;

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
