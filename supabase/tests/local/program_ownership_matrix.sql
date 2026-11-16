-- Program ownership matrix: who can assign, and who can then READ, a program.
-- LOCAL REPLAY only (loopback scratch DB). One transaction, always ROLLED BACK.
-- Writes are issued as `authenticated` with JWT claims, so RLS applies as on the
-- platform. This is an EVIDENCE MAP, not a pass/fail gate: each row prints what
-- the database ALLOWS today, so a finding is a row whose answer is "yes" where
-- disclosure was not intended. Output: `ROW|id|description|result`.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, what text, result text);
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

-- Coaches A, B, Z (Z unrelated to everyone); clients C (A's client), D (B's client).
insert into auth.users(id,email) values
  ('a7000000-0000-0000-0000-0000000000a1','own-coach-a@local'),
  ('b7000000-0000-0000-0000-0000000000b1','own-coach-b@local'),
  ('f7000000-0000-0000-0000-0000000000f1','own-coach-z@local'),
  ('c7000000-0000-0000-0000-0000000000c1','own-client-c@local'),
  ('d7000000-0000-0000-0000-0000000000d1','own-client-d@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in
  ('a7000000-0000-0000-0000-0000000000a1','b7000000-0000-0000-0000-0000000000b1','f7000000-0000-0000-0000-0000000000f1');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('a7000000-0000-0000-0000-0000000000a1','c7000000-0000-0000-0000-0000000000c1','active','coach'),
  ('b7000000-0000-0000-0000-0000000000b1','d7000000-0000-0000-0000-0000000000d1','active','coach');
insert into public.workout_programs(id,coach_id,name) values
  ('a7000000-0000-0000-0000-00000000aaaa','a7000000-0000-0000-0000-0000000000a1','PA private'),
  ('b7000000-0000-0000-0000-00000000bbbb','b7000000-0000-0000-0000-0000000000b1','PB private');
insert into public.program_workouts(program_id,week_number,day_of_week,title) values
  ('a7000000-0000-0000-0000-00000000aaaa',1,'Monday','PA w1'),
  ('b7000000-0000-0000-0000-00000000bbbb',1,'Monday','PB w1');

do $$
declare r text; n int;
  A constant uuid := 'a7000000-0000-0000-0000-0000000000a1';
  B constant uuid := 'b7000000-0000-0000-0000-0000000000b1';
  Z constant uuid := 'f7000000-0000-0000-0000-0000000000f1';
  C constant uuid := 'c7000000-0000-0000-0000-0000000000c1';
  D constant uuid := 'd7000000-0000-0000-0000-0000000000d1';
  PA constant text := 'a7000000-0000-0000-0000-00000000aaaa';
  PB constant text := 'b7000000-0000-0000-0000-00000000bbbb';
  ins constant text := 'insert into public.workout_program_assignments(program_id,client_id,coach_id,status) values (%L,%L,%L,''active'')';
  pw  constant text := 'public.program_workouts where program_id=%L';
begin
  -- O1 own program -> own client (intended).
  r := pg_temp.run_as(A, format(ins, PA, C, A));
  n := pg_temp.sees(C, format(pw, PA));
  insert into res values ('O1','coach A assigns OWN program to OWN client; client reads it', 'assign='||r||' client_sees='||n);

  -- O2 another coach's private program -> own client (coach B's PB to A's client C).
  n := pg_temp.sees(A, format(pw, PB));
  r := pg_temp.run_as(A, format(ins, PB, C, A));
  insert into res values ('O2','coach A assigns coach B''s PRIVATE program to A''s client; can A then read it?',
    'before='||n||' assign='||r||' A_sees_after='||pg_temp.sees(A, format(pw, PB)));

  -- O3 explicitly shared: no sharing mechanism exists (no policy reads is_template or any share flag).
  insert into res values ('O3','assign an explicitly SHARED program','not representable: no sharing mechanism exists');

  -- O4 client assigns a coach's private program to itself (196's case).
  r := pg_temp.run_as(D, format(ins, PA, D, D));
  insert into res values ('O4','client D assigns itself coach A''s private program; can D read it?',
    'assign='||r||' D_sees='||pg_temp.sees(D, format(pw, PA)));

  -- O5 a client reads another client's assigned program.
  insert into res values ('O5','client D reads client C''s assigned program PA',
    'D_sees='||pg_temp.sees(D, format(pw, PA))||' D_sees_C_assignments='||
    pg_temp.sees(D, format('public.workout_program_assignments where client_id=%L', C)));

  -- O6 an UNRELATED coach assigns a program to someone else's client.
  r := pg_temp.run_as(Z, format(ins, PB, C, Z));
  insert into res values ('O6','unrelated coach Z assigns B''s program to A''s client C (no relationship); can Z read PB?',
    'assign='||r||' Z_sees_PB='||pg_temp.sees(Z, format(pw, PB)));

  -- O7 the relationship ends and the client moves to coach B.
  update public.coach_client_relationships set status='cancelled' where coach_id=A and client_id=C;
  insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (B,C,'active','coach');
  insert into res values ('O7','after C leaves A for B: can NEW coach B read A''s program PA (assigned to C earlier)?',
    'B_sees_PA='||pg_temp.sees(B, format(pw, PA)));
  insert into res values ('O8','…and does client C still read PA after leaving A?',
    'C_sees_PA='||pg_temp.sees(C, format(pw, PA)));
  insert into res values ('O9','…and does former coach A still read its own PA? (owner)',
    'A_sees_PA='||pg_temp.sees(A, format(pw, PA)));
  insert into res values ('O10','an unrelated coach Z reads PA',
    'Z_sees_PA='||pg_temp.sees(Z, format(pw, PA)));
end $$;

select 'ROW|'||id||'|'||what||'|'||result from res order by length(id), id;
rollback;
