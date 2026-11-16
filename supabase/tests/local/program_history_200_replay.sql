-- Migration 200 regression: program history after a client changes coach.
-- LOCAL REPLAY only (loopback scratch DB). One transaction, always ROLLED BACK.
-- Reads issued as `authenticated` with JWT claims. Every refusal has a positive
-- control. Output: `PASS|id|detail` or `FAIL|id|detail` per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;

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

-- Coaches A (former), B (new), Z (unrelated); client C; client D (B's other client).
insert into auth.users(id,email) values
  ('a2000000-0000-0000-0000-0000000020a1','h2-coach-a@local'),
  ('b2000000-0000-0000-0000-0000000020b1','h2-coach-b@local'),
  ('f2000000-0000-0000-0000-0000000020f1','h2-coach-z@local'),
  ('c2000000-0000-0000-0000-0000000020c1','h2-client-c@local'),
  ('d2000000-0000-0000-0000-0000000020d1','h2-client-d@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in
  ('a2000000-0000-0000-0000-0000000020a1','b2000000-0000-0000-0000-0000000020b1','f2000000-0000-0000-0000-0000000020f1');
-- PA: A's private program, assigned by A to C. PG: an unowned generated plan for C.
-- PC: a program C owns (self-built). PB: B's own program assigned by B to C now.
insert into public.workout_programs(id,coach_id,name) values
  ('a2000000-0000-0000-0000-00000020aaaa','a2000000-0000-0000-0000-0000000020a1','PA'),
  ('f2000000-0000-0000-0000-00000020ffff',null,'PG'),
  ('c2000000-0000-0000-0000-00000020cccc','c2000000-0000-0000-0000-0000000020c1','PC'),
  ('b2000000-0000-0000-0000-00000020bbbb','b2000000-0000-0000-0000-0000000020b1','PB');
insert into public.program_workouts(program_id,week_number,day_of_week,title) values
  ('a2000000-0000-0000-0000-00000020aaaa',1,'Monday','PA w1'),
  ('f2000000-0000-0000-0000-00000020ffff',1,'Monday','PG w1'),
  ('c2000000-0000-0000-0000-00000020cccc',1,'Monday','PC w1'),
  ('b2000000-0000-0000-0000-00000020bbbb',1,'Monday','PB w1');
insert into public.workout_program_assignments(program_id,client_id,coach_id,status) values
  ('a2000000-0000-0000-0000-00000020aaaa','c2000000-0000-0000-0000-0000000020c1','a2000000-0000-0000-0000-0000000020a1','replaced'),
  ('f2000000-0000-0000-0000-00000020ffff','c2000000-0000-0000-0000-0000000020c1',null,'replaced'),
  ('c2000000-0000-0000-0000-00000020cccc','c2000000-0000-0000-0000-0000000020c1','c2000000-0000-0000-0000-0000000020c1','replaced'),
  ('b2000000-0000-0000-0000-00000020bbbb','c2000000-0000-0000-0000-0000000020c1','b2000000-0000-0000-0000-0000000020b1','active');
-- C left A for B.
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('a2000000-0000-0000-0000-0000000020a1','c2000000-0000-0000-0000-0000000020c1','cancelled','coach'),
  ('b2000000-0000-0000-0000-0000000020b1','c2000000-0000-0000-0000-0000000020c1','active','coach'),
  ('b2000000-0000-0000-0000-0000000020b1','d2000000-0000-0000-0000-0000000020d1','active','coach');
-- C's workout history: a session done under A's program.
insert into public.workout_sessions(user_id,workout_title,status,started_at,completed_at)
values ('c2000000-0000-0000-0000-0000000020c1','PA w1','completed',now()-interval '30 days',now()-interval '30 days');

do $$
declare
  A constant uuid := 'a2000000-0000-0000-0000-0000000020a1';
  B constant uuid := 'b2000000-0000-0000-0000-0000000020b1';
  Z constant uuid := 'f2000000-0000-0000-0000-0000000020f1';
  C constant uuid := 'c2000000-0000-0000-0000-0000000020c1';
  D constant uuid := 'd2000000-0000-0000-0000-0000000020d1';
  pw constant text := 'public.program_workouts where program_id=%L';
  n int;
begin
  n := pg_temp.sees(B, format(pw, 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('H1 a new coach cannot read the previous coach''s private program (O7)', n=0, 'B_sees_PA='||n);
  n := pg_temp.sees(B, format('public.workout_programs where id=%L', 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('H2 …nor its program row', n=0, 'B_sees_PA_row='||n);
  n := pg_temp.sees(Z, format(pw, 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('H3 an unrelated coach cannot read it', n=0, 'Z_sees_PA='||n);
  n := pg_temp.sees(D, format(pw, 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('H4 another client cannot read it', n=0, 'D_sees_PA='||n);
  -- positive controls
  n := pg_temp.sees(C, format(pw, 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('K1 the client keeps its history: it still reads PA (O8)', n=1, 'C_sees_PA='||n);
  n := pg_temp.sees(A, format(pw, 'a2000000-0000-0000-0000-00000020aaaa'));
  insert into res values ('K2 the author keeps its program (O12)', n=1, 'A_sees_PA='||n);
  n := pg_temp.sees(B, format(pw, 'f2000000-0000-0000-0000-00000020ffff'));
  insert into res values ('K3 the active coach reads the client''s generated plan (O11)', n=1, 'B_sees_PG='||n);
  n := pg_temp.sees(B, format(pw, 'c2000000-0000-0000-0000-00000020cccc'));
  insert into res values ('K4 the active coach reads a program the client owns', n=1, 'B_sees_PC='||n);
  n := pg_temp.sees(B, format(pw, 'b2000000-0000-0000-0000-00000020bbbb'));
  insert into res values ('K5 the new coach reads its own assigned program', n=1, 'B_sees_PB='||n);
  n := pg_temp.sees(C, format('public.workout_sessions where user_id=%L', C));
  insert into res values ('K6 the client''s workout history is intact', n=1, 'C_sessions='||n);
  n := pg_temp.sees(A, format(pw, 'f2000000-0000-0000-0000-00000020ffff'));
  insert into res values ('K7 the former coach no longer reads the client''s generated plan (not its client)', n=0, 'A_sees_PG='||n);
end $$;

select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || detail from res order by id;
rollback;
