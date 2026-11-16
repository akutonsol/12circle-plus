-- Migrations 196-197 regression: a client cannot assign itself someone else's
-- program, and a coach cannot assign another coach's program (either way, the
-- assignment row was the key to reading it). LOCAL REPLAY only (loopback scratch DB). One transaction,
-- always ROLLED BACK. Client writes are issued as `authenticated` with the
-- caller's JWT claims, so RLS applies as on the platform. Every refusal has a
-- positive control. Output: one `PASS|id|detail` or `FAIL|id|detail` per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;

create function pg_temp.run_as(u uuid, stmt text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
  set local role authenticated;
  begin execute stmt; r := 'ok'; exception when others then r := sqlstate; end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;

-- How many rows of [tbl] matching [cond] the user can SEE.
create function pg_temp.sees(u uuid, q text) returns int language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
  set local role authenticated;
  execute 'select count(*) from ' || q into n;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return n;
end $$;

-- Fixtures: coaches A, B; client C (A's client); X (a client of nobody).
insert into auth.users(id,email) values
  ('a9600000-0000-0000-0000-0000000000a1','asg-coach-a@local'),
  ('b9600000-0000-0000-0000-0000000000b1','asg-coach-b@local'),
  ('c9600000-0000-0000-0000-0000000000c1','asg-client-c@local'),
  ('d9600000-0000-0000-0000-0000000000d1','asg-client-x@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach'
 where id in ('a9600000-0000-0000-0000-0000000000a1','b9600000-0000-0000-0000-0000000000b1');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by)
values ('a9600000-0000-0000-0000-0000000000a1','c9600000-0000-0000-0000-0000000000c1','active','coach');

-- A's paid program PA with one workout; B's program PB, assigned by B to X earlier.
insert into public.workout_programs(id,coach_id,name) values
  ('a9600000-0000-0000-0000-00000000aaaa','a9600000-0000-0000-0000-0000000000a1','PA'),
  ('b9600000-0000-0000-0000-00000000bbbb','b9600000-0000-0000-0000-0000000000b1','PB');
insert into public.program_workouts(program_id,week_number,day_of_week,title) values
  ('a9600000-0000-0000-0000-00000000aaaa',1,'Monday','PA week 1');
insert into public.workout_program_assignments(id,program_id,client_id,coach_id) values
  ('e9600000-0000-0000-0000-0000000000e1','b9600000-0000-0000-0000-00000000bbbb',
   'd9600000-0000-0000-0000-0000000000d1','b9600000-0000-0000-0000-0000000000b1');

do $$
declare r text; n int;
  pa constant text := 'a9600000-0000-0000-0000-00000000aaaa';
  x  constant uuid := 'd9600000-0000-0000-0000-0000000000d1';
begin
  -- The premise: X cannot see PA's workouts before doing anything.
  n := pg_temp.sees(x, format('public.program_workouts where program_id=%L', pa));
  insert into res values ('P0 premise: an unrelated client cannot read another coach''s program', n=0, 'sees='||n);

  -- S1 the defect: X assigns itself A's program, naming A as coach.
  r := pg_temp.run_as(x, format(
    'insert into public.workout_program_assignments(program_id,client_id,coach_id) values (%L,%L,%L)',
    pa, x, 'a9600000-0000-0000-0000-0000000000a1'));
  n := pg_temp.sees(x, format('public.program_workouts where program_id=%L', pa));
  insert into res values ('S1 a client cannot assign itself another coach''s program, and cannot read it',
    r<>'ok' and n=0, 'insert='||r||' sees='||n);

  -- S2 the same, naming ITSELF as coach.
  r := pg_temp.run_as(x, format(
    'insert into public.workout_program_assignments(program_id,client_id,coach_id) values (%L,%L,%L)', pa, x, x));
  n := pg_temp.sees(x, format('public.program_workouts where program_id=%L', pa));
  insert into res values ('S2 …nor by naming itself as the coach', r<>'ok' and n=0, 'insert='||r||' sees='||n);

  -- S3 repointing an assignment it already holds (B's, for PB) at A's program.
  r := pg_temp.run_as(x, format(
    'update public.workout_program_assignments set program_id=%L where id=%L', pa, 'e9600000-0000-0000-0000-0000000000e1'));
  n := pg_temp.sees(x, format('public.program_workouts where program_id=%L', pa));
  insert into res select 'S3 …nor by repointing an assignment it holds at that program',
    a.program_id='b9600000-0000-0000-0000-00000000bbbb' and n=0, 'update='||r||' program='||a.program_id||' sees='||n
    from public.workout_program_assignments a where a.id='e9600000-0000-0000-0000-0000000000e1';

  -- C1 positive control: coach A assigns PA to its client C, and C reads it.
  r := pg_temp.run_as('a9600000-0000-0000-0000-0000000000a1', format(
    'insert into public.workout_program_assignments(program_id,client_id,coach_id,status) values (%L,%L,%L,''active'')',
    pa, 'c9600000-0000-0000-0000-0000000000c1', 'a9600000-0000-0000-0000-0000000000a1'));
  n := pg_temp.sees('c9600000-0000-0000-0000-0000000000c1', format('public.program_workouts where program_id=%L', pa));
  insert into res values ('C1 the coach still assigns its program to its client, who reads it (positive control)',
    r='ok' and n=1, 'insert='||r||' sees='||n);

  -- C2 the coach's replace step (assignProgram's update) still lands.
  r := pg_temp.run_as('a9600000-0000-0000-0000-0000000000a1', format(
    'update public.workout_program_assignments set status=''replaced'' where client_id=%L and status=''active''',
    'c9600000-0000-0000-0000-0000000000c1'));
  insert into res select 'C2 the coach still replaces its client''s active assignment',
    r='ok' and a.status='replaced', 'update='||r||' status='||a.status
    from public.workout_program_assignments a where a.client_id='c9600000-0000-0000-0000-0000000000c1';

  -- C3 a client assigning ITS OWN program to itself is untouched.
  perform pg_temp.run_as(x, format(
    'insert into public.workout_programs(id,coach_id,name) values (%L,%L,''PX'')', 'd9600000-0000-0000-0000-0000000000ff', x));
  r := pg_temp.run_as(x, format(
    'insert into public.workout_program_assignments(program_id,client_id,coach_id) values (%L,%L,%L)',
    'd9600000-0000-0000-0000-0000000000ff', x, x));
  insert into res values ('C3 a client can still assign itself a program it owns', r='ok', 'insert='||r);

  -- C4 the client still reads its own assignments.
  n := pg_temp.sees(x, format('public.workout_program_assignments where client_id=%L', x));
  insert into res values ('C4 a client still reads its own assignments', n>=1, 'sees='||n);

  -- 197 · S4 coach A assigns coach B's PRIVATE program PB to A's own client C.
  n := pg_temp.sees('a9600000-0000-0000-0000-0000000000a1',
         format('public.program_workouts where program_id=%L', 'b9600000-0000-0000-0000-00000000bbbb'));
  r := pg_temp.run_as('a9600000-0000-0000-0000-0000000000a1', format(
    'insert into public.workout_program_assignments(program_id,client_id,coach_id,status) values (%L,%L,%L,''active'')',
    'b9600000-0000-0000-0000-00000000bbbb', 'c9600000-0000-0000-0000-0000000000c1', 'a9600000-0000-0000-0000-0000000000a1'));
  insert into res values ('S4 a coach cannot assign another coach''s program to its client, and cannot read it',
    r<>'ok' and pg_temp.sees('a9600000-0000-0000-0000-0000000000a1',
      format('public.program_workouts where program_id=%L', 'b9600000-0000-0000-0000-00000000bbbb'))=0,
    'before='||n||' insert='||r);

  -- 197 · S5 coach A repoints its own (replaced) assignment of PA at B's PB.
  r := pg_temp.run_as('a9600000-0000-0000-0000-0000000000a1', format(
    'update public.workout_program_assignments set program_id=%L where client_id=%L and coach_id=%L',
    'b9600000-0000-0000-0000-00000000bbbb', 'c9600000-0000-0000-0000-0000000000c1', 'a9600000-0000-0000-0000-0000000000a1'));
  insert into res select 'S5 …nor by repointing its own assignment at that program',
    bool_and(a.program_id='a9600000-0000-0000-0000-00000000aaaa'), 'update='||r||' programs='||string_agg(a.program_id::text, ',')
    from public.workout_program_assignments a
   where a.client_id='c9600000-0000-0000-0000-0000000000c1' and a.coach_id='a9600000-0000-0000-0000-0000000000a1';
end $$;

select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || detail from res order by id;
rollback;
