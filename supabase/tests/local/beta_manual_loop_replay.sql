-- Beta loop, MANUAL route, run on the LOCAL REPLAY only (loopback scratch DB).
--
-- The first-beta milestone is: a coach builds week 1, assigns it, and the
-- client uses it. The engine route ("Generate week 1") is held behind
-- ENGINE_WEEK_GENERATION until 182-186 are on QA and the substrate exists.
-- The engine's own fallback tells coaches "Build this week by hand in
-- Programs". This file proves that manual route works end to end on a given
-- schema, using the exact statement shapes the app sends:
--
--   coach   workout_programs insert         (CoachProgramService.createProgram,
--                                            _ProgramMetaSheet keys)
--           program_workouts insert         (addWorkoutToProgram; _WorkoutSheet
--                                            + _ExerciseDialog keys)
--           assignment replace + insert     (assignProgram)
--           notification insert             (assignProgram)
--   client  active assignment + programme   (getMyAssignedProgram)
--           program_workouts, ordered       (getProgramWorkouts)
--           session start, set log, finish  (SupabaseWorkoutSessionStore,
--                                            WorkoutService.saveSetLog)
--
-- Nothing in it reads the exercise library: the manual builder writes free-text
-- exercise names, so this route needs no certified content and no
-- exercise_intelligence rows.
--
-- Runs inside ONE transaction that is always ROLLED BACK. Never applied to QA or
-- production -- see beta_manual_loop_replay.sh, which refuses any non-loopback
-- target. A denial passes ONLY on SQLSTATE 42501, and every denial has a
-- positive control in the same shape.
--
-- Output: `PASS|id|detail` / `FAIL|id|detail` per assertion, and `OBS|id|detail`
-- for behaviour that is recorded, not judged (it differs by schema on purpose).

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
create temp table obs(id text, detail text);
grant all on res, obs to authenticated;

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;

create function pg_temp.attempt(stmt text) returns text language plpgsql as $$
begin execute stmt; return 'ok'; exception when others then return sqlstate; end $$;
grant execute on function pg_temp.attempt(text) to authenticated;

-- Fixtures ------------------------------------------------------------------
-- A coach · C client of A (ACTIVE) · Y another client of A (ACTIVE)
-- B a second coach, no relationship with C · Z a user with no coach at all
insert into auth.users(id,email) values
  ('a1000000-0000-0000-0000-00000000000a','beta-coach@local'),
  ('c1000000-0000-0000-0000-00000000000c','beta-client@local'),
  ('c2000000-0000-0000-0000-00000000000c','beta-client2@local'),
  ('b1000000-0000-0000-0000-00000000000b','beta-othercoach@local'),
  ('e1000000-0000-0000-0000-00000000000e','beta-nocoach@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in
  ('a1000000-0000-0000-0000-00000000000a','b1000000-0000-0000-0000-00000000000b');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('a1000000-0000-0000-0000-00000000000a','c1000000-0000-0000-0000-00000000000c','active','client'),
  ('a1000000-0000-0000-0000-00000000000a','c2000000-0000-0000-0000-00000000000c','active','client');

-- ===========================================================================
-- 1. The coach builds week 1 by hand
-- ===========================================================================
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
set local role authenticated;

insert into res select 'L-1 coach creates a programme (meta-sheet keys)',
  pg_temp.attempt($q$insert into public.workout_programs(id,coach_id,name,goal,description,difficulty,duration_weeks)
    values ('20000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-00000000000a',
            'Beta strength','Strength','Week 1 by hand','intermediate',4)$q$) = 'ok', null;

-- Two training days in the exact shape _WorkoutSheet / _ExerciseDialog pop:
-- a load and rest given on Monday; NO load and NO rest on Wednesday (the dialog
-- sends null for both when the fields are left blank).
insert into res select 'L-2 coach adds Monday with prescribed load and rest',
  pg_temp.attempt($q$insert into public.program_workouts(program_id,title,week_number,day_of_week,estimated_minutes,exercises,sort_order)
    values ('20000000-0000-0000-0000-000000000001','Lower A',1,'Monday',45,
      '[{"exercise_instance_id":"beta-ex-1","name":"Back Squat","sets":3,"reps":8,"weight_kg":60.0,"rest_seconds":120},
        {"exercise_instance_id":"beta-ex-2","name":"Romanian Deadlift","sets":3,"reps":10,"weight_kg":50.0,"rest_seconds":90}]'::jsonb,0)$q$) = 'ok', null;
insert into res select 'L-3 coach adds Wednesday with no load and no rest (nulls, not zeros)',
  pg_temp.attempt($q$insert into public.program_workouts(program_id,title,week_number,day_of_week,estimated_minutes,exercises,sort_order)
    values ('20000000-0000-0000-0000-000000000001','Upper A',1,'Wednesday',40,
      '[{"exercise_instance_id":"beta-ex-3","name":"Push-up","sets":3,"reps":12,"weight_kg":null,"rest_seconds":null}]'::jsonb,2)$q$) = 'ok', null;
-- Negative control: the prescription CHECK is live, so L-2/L-3 passing means the
-- shapes are canonical, not that nothing is checked.
insert into res select 'L-4 a range in reps ("8-12") is refused by the prescription CHECK (23514)',
  pg_temp.attempt($q$insert into public.program_workouts(program_id,title,week_number,day_of_week,exercises)
    values ('20000000-0000-0000-0000-000000000001','Bad',1,'Friday',
      '[{"exercise_instance_id":"beta-ex-x","name":"Lunge","sets":3,"reps":"8-12","weight_kg":null}]'::jsonb)$q$) = '23514',
  pg_temp.attempt($q$insert into public.program_workouts(program_id,title,week_number,day_of_week,exercises)
    values ('20000000-0000-0000-0000-000000000001','Bad',1,'Friday',
      '[{"exercise_instance_id":"beta-ex-x","name":"Lunge","sets":3,"reps":"8-12","weight_kg":null}]'::jsonb)$q$);
reset role;

insert into res select 'L-5 both days stored, canonical, in week 1, with full day names',
  count(*)=2 and bool_and(public.is_canonical_exercise_prescription(exercises))
    and bool_and(day_of_week in ('Monday','Wednesday')) and bool_and(week_number=1),
  'rows '||count(*)||' days '||string_agg(day_of_week,',' order by sort_order)
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001';
insert into res select 'L-6 a load left blank is stored as null, never invented as 0',
  (exercises->0->'weight_kg') = 'null'::jsonb, (exercises->0)::text
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001' and day_of_week='Wednesday';

-- ===========================================================================
-- 2. The coach assigns it (assignProgram, statement for statement)
-- ===========================================================================
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
set local role authenticated;
insert into res select 'L-7 coach replaces any active assignment (none yet: a no-op, not an error)',
  pg_temp.attempt($q$update public.workout_program_assignments set status='replaced'
    where client_id='c1000000-0000-0000-0000-00000000000c' and status='active'$q$) = 'ok', null;
insert into res select 'L-8 coach assigns the programme to an ACTIVE client',
  pg_temp.attempt($q$insert into public.workout_program_assignments(program_id,client_id,coach_id,start_date,current_week,status)
    values ('20000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-00000000000c',
            'a1000000-0000-0000-0000-00000000000a',current_date,1,'active')$q$) = 'ok', null;
insert into res select 'L-9 coach notifies the client (may_notify via the relationship)',
  pg_temp.attempt($q$insert into public.notifications(recipient_id,type,title,body,read)
    values ('c1000000-0000-0000-0000-00000000000c','program_assigned','New Workout Program','Check your training tab!',false)$q$) = 'ok', null;
reset role;

-- ===========================================================================
-- 3. The client sees it (getMyAssignedProgram / getProgramWorkouts / today)
-- ===========================================================================
select pg_temp.as_user('c1000000-0000-0000-0000-00000000000c');
set local role authenticated;
insert into res select 'L-10 client sees exactly one active assignment, week 1',
  count(*)=1 and bool_and(current_week=1), 'active '||count(*)
  from public.workout_program_assignments
  where client_id='c1000000-0000-0000-0000-00000000000c' and status='active';
-- The embed `workout_programs(*)` is an RLS-filtered read of the programme row.
insert into res select 'L-11 client can read the assigned programme row (the embed)',
  count(*)=1, 'rows '||count(*)
  from public.workout_program_assignments a join public.workout_programs p on p.id=a.program_id
  where a.client_id='c1000000-0000-0000-0000-00000000000c' and a.status='active';
insert into res select 'L-12 client reads both training days, ordered by week then sort_order',
  count(*)=2 and string_agg(day_of_week,',' order by week_number,sort_order)='Monday,Wednesday',
  coalesce(string_agg(day_of_week,',' order by week_number,sort_order),'none')
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001';
-- getTodaysWorkout matches week_number = current_week AND day_of_week = the
-- English weekday name. Every stored label must be one the client can match.
insert into res select 'L-13 every day label is a name getTodaysWorkout can match',
  bool_and(day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
  string_agg(distinct day_of_week,',')
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001';
insert into res select 'L-14 client received the assignment notification',
  count(*)=1, 'rows '||count(*)
  from public.notifications where recipient_id='c1000000-0000-0000-0000-00000000000c' and type='program_assigned';
with u as (update public.program_workouts set title='hijack'
   where program_id='20000000-0000-0000-0000-000000000001' returning 1)
insert into res select 'L-15 client cannot edit the coach''s training day (0 rows changed)',
  count(*)=0, 'rows changed '||count(*) from u;
reset role;

-- ===========================================================================
-- 4. The client does Monday (session store + set log + finish)
-- ===========================================================================
select pg_temp.as_user('c1000000-0000-0000-0000-00000000000c');
set local role authenticated;
insert into res select 'L-16 client starts a session for the Monday workout',
  pg_temp.attempt($q$insert into public.workout_sessions(id,user_id,workout_id,workout_title,workout_snapshot,status,elapsed_seconds)
    select '30000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-00000000000c', w.id::text, w.title,
           jsonb_build_object('id',w.id,'title',w.title,'exercises',w.exercises),'in_progress',0
    from public.program_workouts w
    where w.program_id='20000000-0000-0000-0000-000000000001' and w.day_of_week='Monday'$q$) = 'ok', null;
insert into res select 'L-17 client logs a set under its set identity',
  pg_temp.attempt($q$insert into public.workout_set_logs(exercise_name,exercise_instance_id,exercise_id,set_number,reps,weight_kg,rpe,notes,tempo,completed,session_id,user_id,set_id)
    values ('Back Squat','beta-ex-1',null,1,8,60,null,null,null,true,
            '30000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-00000000000c','beta-ex-1#1')$q$) = 'ok', null;
insert into res select 'L-18 client completes the session',
  pg_temp.attempt($q$update public.workout_sessions set status='completed', completed_at=now(),
    duration_seconds=2400, idle_seconds=0, calories_burned=300
    where id='30000000-0000-0000-0000-000000000001'$q$) = 'ok', null;
reset role;

select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
set local role authenticated;
insert into res select 'L-19 the coach sees the completed session and its set',
  (select count(*) from public.workout_sessions where id='30000000-0000-0000-0000-000000000001' and status='completed')=1
  and (select count(*) from public.workout_set_logs where session_id='30000000-0000-0000-0000-000000000001')=1,
  'sessions '||(select count(*) from public.workout_sessions where id='30000000-0000-0000-0000-000000000001')
  ||' sets '||(select count(*) from public.workout_set_logs where session_id='30000000-0000-0000-0000-000000000001');
reset role;

-- ===========================================================================
-- 5. Re-assigning replaces, it does not stack
-- ===========================================================================
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
set local role authenticated;
insert into public.workout_programs(id,coach_id,name) values
  ('20000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-00000000000a','Beta strength v2');
update public.workout_program_assignments set status='replaced'
  where client_id='c1000000-0000-0000-0000-00000000000c' and status='active';
insert into public.workout_program_assignments(program_id,client_id,coach_id,start_date,current_week,status)
  values ('20000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-00000000000c',
          'a1000000-0000-0000-0000-00000000000a',current_date,1,'active');
reset role;
insert into res select 'L-20 re-assigning leaves exactly one active assignment, the new one',
  count(*) filter (where status='active')=1
  and bool_or(status='active' and program_id='20000000-0000-0000-0000-000000000002')
  and count(*) filter (where status='replaced')=1,
  string_agg(status,',' order by assigned_at)
  from public.workout_program_assignments where client_id='c1000000-0000-0000-0000-00000000000c';

-- ===========================================================================
-- 6. Isolation
-- ===========================================================================
select pg_temp.as_user('c2000000-0000-0000-0000-00000000000c');
set local role authenticated;
insert into res select 'L-21 another client of the same coach cannot read C''s training days',
  count(*)=0, 'rows '||count(*)
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001';
reset role;
select pg_temp.as_user('b1000000-0000-0000-0000-00000000000b');
set local role authenticated;
insert into res select 'L-22 an unrelated coach cannot read C''s training days',
  count(*)=0, 'rows '||count(*)
  from public.program_workouts where program_id='20000000-0000-0000-0000-000000000001';
insert into res select 'L-23 an unrelated coach cannot read C''s sessions',
  count(*)=0, 'rows '||count(*)
  from public.workout_sessions where user_id='c1000000-0000-0000-0000-00000000000c';
reset role;

-- ===========================================================================
-- OBS · assigning to someone who is NOT this coach's client. Recorded, not
-- judged: 000-181 lets the assignment row through (QAX-SEC-03, closed by 185),
-- while may_notify refuses the notification -- so the app's assignProgram would
-- write the assignment and THEN throw. 185 refuses the assignment itself.
-- ===========================================================================
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
set local role authenticated;
insert into obs select 'O-1 coach assigns to a user with NO relationship: assignment',
  pg_temp.attempt($q$insert into public.workout_program_assignments(program_id,client_id,coach_id,current_week,status)
    values ('20000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-00000000000e',
            'a1000000-0000-0000-0000-00000000000a',1,'active')$q$);
insert into obs select 'O-2 coach assigns to a user with NO relationship: notification',
  pg_temp.attempt($q$insert into public.notifications(recipient_id,type,title,body,read)
    values ('e1000000-0000-0000-0000-00000000000e','program_assigned','x','x',false)$q$);
reset role;

select case when ok then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
select 'OBS|'||id||'|'||detail from obs order by id;
rollback;
