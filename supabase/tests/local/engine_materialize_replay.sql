-- Coach programme engine regression (migration 186), LOCAL REPLAY ONLY.
--
-- One transaction, always ROLLED BACK. Every check prints PASS|id|detail or
-- FAIL|id|detail. Run by engine_materialize_replay.sh, which refuses any
-- non-loopback target. Designed to be run against BOTH:
--   * a replay WITHOUT 186 (expected: the defect reproduces — many FAILs), and
--   * a replay WITH 186     (expected: all PASS).
--
-- Each scenario runs inside a savepoint so one failure cannot mask another, and
-- results are stashed client-side across the rollback-to-savepoint (same trick
-- as qa_exhaustion/probes.sql).

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;
-- NULL-safe: id||ok||detail is NULL when detail (or ok) is NULL, and string_agg
-- silently skips NULLs — a FAIL row would vanish from the stash. Found that way.
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;

-- Run the public wrapper as the current role; return the result or the error.
create function pg_temp.mat(p uuid, w int, ctx jsonb) returns jsonb language plpgsql as $$
begin
  return jsonb_build_object('ok', public.materialize_program_week(p, w, ctx));
exception when others then
  return jsonb_build_object('err', sqlerrm, 'state', sqlstate);
end $$;
grant execute on function pg_temp.mat(uuid,int,jsonb) to authenticated;

-- Fixtures ----------------------------------------------------------------
insert into auth.users(id,email) values
 ('e1000000-0000-0000-0000-000000000001','eng-coach@local'),
 ('e2000000-0000-0000-0000-000000000002','eng-client@local'),
 ('e3000000-0000-0000-0000-000000000003','eng-other-coach@local') on conflict do nothing;
update public.user_profiles set role='coach' where id in
 ('e1000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003');
update public.user_profiles set fitness_goal='build_muscle', training_days_per_week=4
 where id='e2000000-0000-0000-0000-000000000002';

select set_config('eng.plan', public.plan_program(
  '{"program_type":"hypertrophy","duration_weeks":4,"frequency":3,"primary_focus":"Full Body","progression_model":"linear","deload_strategy":"every_4th"}'::jsonb)::text, true);
insert into public.workout_programs(id, coach_id, name, plan, strategy, engine_generated) values
 ('f1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','eng A',
  current_setting('eng.plan')::jsonb, '{}'::jsonb, true),
 ('f2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','eng B (has a coach-edited week 1)',
  current_setting('eng.plan')::jsonb, '{}'::jsonb, true);
-- Programme B: a valid, coach-authored week 1 that must never be silently destroyed.
insert into public.program_workouts(program_id, week_number, day_of_week, title, exercises, sort_order)
values ('f2000000-0000-0000-0000-000000000002', 1, 'Monday', 'Coach day',
  '[{"exercise_instance_id":"coach-1","name":"Bench Press","sets":4,"reps":6,"weight_kg":80,"rest_seconds":120}]'::jsonb, 0);

-- The context the coach Copilot builds (no equipment filter), sets/reps unspecified.
select set_config('eng.ctx', '{"goal":"hypertrophy","experience":"intermediate","size":5}', true);

-- ═══ S1 · EMPTY substrate: explicit failure, nothing written ════════════════
savepoint s; select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 1, current_setting('eng.ctx')::jsonb)::text, true);
reset role;
insert into res select 'S1 empty substrate: the call FAILS (no false success)',
  (current_setting('eng.r')::jsonb ? 'err'), left(current_setting('eng.r'), 160);
insert into res select 'S1 …with an actionable ENGINE_NO_SELECTION message',
  coalesce(current_setting('eng.r')::jsonb->>'err','') like 'ENGINE_NO_SELECTION:%library is not populated%',
  left(coalesce(current_setting('eng.r')::jsonb->>'err','(no error)'), 120);
insert into res select 'S1 …and NO training day was written',
  count(*) = 0, count(*)||' day(s)' from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- Populate the substrate the way EB-4 would (one default profile per exercise).
insert into public.exercise_intelligence(exercise_id) select id from public.custom_exercises on conflict do nothing;

-- ═══ S2 · POPULATED substrate: complete, canonical days ════════════════════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 1, current_setting('eng.ctx')::jsonb)::text, true);
reset role;
insert into res select 'S2 populated substrate: the call SUCCEEDS',
  (current_setting('eng.r')::jsonb ? 'ok'), left(current_setting('eng.r'), 160);
insert into res select 'S2 …one training day per session in the plan''s split',
  count(*) = jsonb_array_length((current_setting('eng.plan')::jsonb->'weeks'->0->'split'))
    and count(*) > 0,
  count(*)||' day(s) for split '||(current_setting('eng.plan')::jsonb->'weeks'->0->>'split')
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001' and week_number=1;
insert into res select 'S2 …every day has exercises',
  coalesce(bool_and(jsonb_array_length(exercises) > 0), false),
  string_agg(jsonb_array_length(exercises)::text, ',' order by sort_order)
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001';
insert into res select 'S2 …every day passes the canonical-prescription check',
  coalesce(bool_and(public.is_canonical_exercise_prescription(exercises)), false), count(*)||' day(s) checked'
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001';
insert into res select 'S2 …every exercise has sets>=1 and reps, and weight_kg present-but-null (no invented load)',
  coalesce(bool_and((e->>'sets')::int >= 1 and (e->>'reps') is not null and e ? 'weight_kg'
                    and jsonb_typeof(e->'weight_kg') = 'null'), false),
  count(*)||' exercise(s)'
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
  where pw.program_id='f1000000-0000-0000-0000-000000000001';
insert into res select 'S2 …default prescription is 119''s 3 x 10',
  coalesce(bool_and((e->>'sets')::int = 3 and (e->>'reps')::int = 10), false), ''
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
  where pw.program_id='f1000000-0000-0000-0000-000000000001';
insert into res select 'S2 …day_of_week is a full English day name',
  coalesce(bool_and(day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')), false),
  string_agg(day_of_week, ',' order by sort_order)
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001';

-- ═══ S3 · repeat on the same week: no duplicates, no silent overwrite ══════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r2', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 1, current_setting('eng.ctx')::jsonb)::text, true);
reset role;
insert into res select 'S3 a second call WITHOUT replace_existing is refused (ENGINE_WEEK_EXISTS)',
  coalesce(current_setting('eng.r2')::jsonb->>'err','') like 'ENGINE_WEEK_EXISTS:%',
  left(coalesce(current_setting('eng.r2')::jsonb->>'err','(no error: '||left(current_setting('eng.r2'),80)||')'), 120);
insert into res select 'S3 …and the week is unchanged (no duplicate days)',
  count(*) = jsonb_array_length((current_setting('eng.plan')::jsonb->'weeks'->0->'split')),
  count(*)||' day(s)'
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001' and week_number=1;
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r3', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 1,
  (current_setting('eng.ctx')::jsonb || '{"replace_existing": true, "sets": 4, "reps": 8, "rest_seconds": 90}'))::text, true);
reset role;
insert into res select 'S3 WITH replace_existing it regenerates — same number of days, not double',
  (current_setting('eng.r3')::jsonb ? 'ok') and count(*) = jsonb_array_length((current_setting('eng.plan')::jsonb->'weeks'->0->'split')),
  count(*)||' day(s); '||left(current_setting('eng.r3'),80)
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001' and week_number=1;
insert into res select 'S3 …and the caller''s sets/reps/rest are what is prescribed',
  coalesce(bool_and((e->>'sets')::int = 4 and (e->>'reps')::int = 8 and (e->>'rest_seconds')::int = 90), false), ''
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
  where pw.program_id='f1000000-0000-0000-0000-000000000001';

-- ═══ S4 · a coach-edited week is never silently destroyed ═════════════════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r4', pg_temp.mat('f2000000-0000-0000-0000-000000000002', 1, current_setting('eng.ctx')::jsonb)::text, true);
reset role;
insert into res select 'S4 materializing over a coach-edited week is refused',
  coalesce(current_setting('eng.r4')::jsonb->>'err','') like 'ENGINE_WEEK_EXISTS:%',
  left(coalesce(current_setting('eng.r4')::jsonb->>'err','(no error)'), 100);
insert into res select 'S4 …and the coach''s day is intact',
  count(*) = 1 and bool_and(title = 'Coach day' and (exercises->0->>'weight_kg')::numeric = 80), count(*)||' day(s)'
  from public.program_workouts where program_id='f2000000-0000-0000-0000-000000000002';

-- ═══ S7 · a FAILED replacement leaves the existing week exactly as it was ══
-- Programme A has a generated week 1 (S3). Remove the substrate inside a
-- savepoint, then ask for an explicit replacement: validation runs before the
-- DELETE, so the call must fail and every existing day must survive unchanged.
savepoint s;
select set_config('eng.before', coalesce((select jsonb_agg(exercises order by sort_order)::text
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001' and week_number=1), '[]'), true);
delete from public.exercise_intelligence;
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r7', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 1,
  (current_setting('eng.ctx')::jsonb || '{"replace_existing": true}'))::text, true);
reset role;
insert into res select 'S7 replace_existing with no usable data FAILS (ENGINE_NO_SELECTION)',
  coalesce(current_setting('eng.r7')::jsonb->>'err','') like 'ENGINE_NO_SELECTION:%',
  left(coalesce(current_setting('eng.r7')::jsonb->>'err','(no error)'), 100);
insert into res select 'S7 …and the existing week is byte-for-byte unchanged',
  (select jsonb_agg(exercises order by sort_order)::text from public.program_workouts
     where program_id='f1000000-0000-0000-0000-000000000001' and week_number=1) = current_setting('eng.before')
  and current_setting('eng.before') <> '[]',
  'compared the stored exercises of every day before and after';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ S8 · a malformed prescription is refused, not replaced by 3 x 10 ═════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r8', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 2,
  (current_setting('eng.ctx')::jsonb || '{"reps": "8-12"}'))::text, true);
select set_config('eng.r8b', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 2,
  (current_setting('eng.ctx')::jsonb || '{"sets": 0}'))::text, true);
reset role;
insert into res select 'S8 reps "8-12" is refused (ENGINE_BAD_PRESCRIPTION), not silently made 10',
  coalesce(current_setting('eng.r8')::jsonb->>'err','') like 'ENGINE_BAD_PRESCRIPTION:%',
  left(coalesce(current_setting('eng.r8')::jsonb->>'err','(no error)'), 100);
insert into res select 'S8 sets 0 is refused (ENGINE_BAD_PRESCRIPTION)',
  coalesce(current_setting('eng.r8b')::jsonb->>'err','') like 'ENGINE_BAD_PRESCRIPTION:%',
  left(coalesce(current_setting('eng.r8b')::jsonb->>'err','(no error)'), 100);
insert into res select 'S8 …and nothing was written for week 2',
  count(*) = 0, count(*)||' day(s)'
  from public.program_workouts where program_id='f1000000-0000-0000-0000-000000000001' and week_number=2;

-- ═══ S9 · only a JSON true is consent to replace ═══════════════════════════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('eng.r9', pg_temp.mat('f2000000-0000-0000-0000-000000000002', 1,
  (current_setting('eng.ctx')::jsonb || '{"replace_existing": "true"}'))::text, true);
reset role;
insert into res select 'S9 replace_existing as the STRING "true" does not replace',
  coalesce(current_setting('eng.r9')::jsonb->>'err','') like 'ENGINE_WEEK_EXISTS:%',
  left(coalesce(current_setting('eng.r9')::jsonb->>'err','(no error)'), 100);
insert into res select 'S9 …and the coach''s day is still intact',
  count(*) = 1 and bool_and(title = 'Coach day'), count(*)||' day(s)'
  from public.program_workouts where program_id='f2000000-0000-0000-0000-000000000002';

-- ═══ S5 · authorization is unchanged ══════════════════════════════════════
select pg_temp.as_user('e3000000-0000-0000-0000-000000000003'); set local role authenticated;
select set_config('eng.r5', pg_temp.mat('f1000000-0000-0000-0000-000000000001', 2, current_setting('eng.ctx')::jsonb)::text, true);
reset role;
insert into res select 'S5 another coach cannot materialize this programme (42501)',
  coalesce(current_setting('eng.r5')::jsonb->>'state','') = '42501', left(current_setting('eng.r5'), 100);
insert into res select 'S5 authenticated cannot call the engine directly',
  not has_function_privilege('authenticated','public.materialize_program_week_engine(uuid,integer,jsonb)','execute'), '';
insert into res select 'S5 engine keeps a pinned search_path',
  coalesce(array_to_string(proconfig,','),'') like '%search_path=public%', coalesce(array_to_string(proconfig,','),'none')
  from pg_proc where oid='public.materialize_program_week_engine(uuid,integer,jsonb)'::regprocedure;

-- ═══ S6 · the other generators are unchanged ══════════════════════════════
select pg_temp.as_user('e1000000-0000-0000-0000-000000000001'); set local role authenticated;
insert into res select 'S6 Copilot (generate_workout) returns exercises with a populated substrate',
  jsonb_array_length(public.generate_workout(current_setting('eng.ctx')::jsonb)->'selected') > 0, '';
reset role;
select pg_temp.as_user('e2000000-0000-0000-0000-000000000002'); set local role authenticated;
select public.generate_client_plan();
reset role;
insert into res select 'S6 member plan (generate_client_plan) still has exercises on every day',
  coalesce(bool_and(jsonb_array_length(pw.exercises) > 0), false),
  string_agg(jsonb_array_length(pw.exercises)::text, ',' order by pw.sort_order)
  from public.program_workouts pw join public.workout_program_assignments a on a.program_id = pw.program_id
 where a.client_id='e2000000-0000-0000-0000-000000000002' and a.status='active';

-- NULL-safe: an aggregate over zero rows yields a NULL detail, and NULL||text is
-- NULL — the whole line would vanish and a FAIL would go unreported. (Found
-- exactly that way: the pre-186 run printed 19 of 21 lines.) A NULL ok is a FAIL.
select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
