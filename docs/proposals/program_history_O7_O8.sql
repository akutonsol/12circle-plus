-- PROPOSAL (not a migration; nothing applies it). Program history after a client
-- changes coach -- ownership matrix rows O7 and O8. Owner decision 14.
--
-- Run on a LOOPBACK replay built through 199 (any shape):
--   psql -h 127.0.0.1 -p 55433 -U postgres -X -tA -f docs/proposals/program_history_O7_O8.sql <db>
-- One transaction, always ROLLED BACK. It measures the current answer, applies the
-- proposed can_read_program() inside the transaction, and measures again.
--
-- TODAY: can_read_program() (117) grants a coach any program assigned to a client
-- they ACTIVELY coach -- `is_active_coach_of(a.client_id)` -- whoever wrote it. So a
-- client's NEW coach silently reads the PREVIOUS coach's private program (O7).
--
-- PROPOSAL: the active-coach arm covers only programs that are not another coach's
-- authored work -- programs the client owns, or ones with no owner (the self-guided
-- generator writes coach_id null). The assigning coach keeps its own arm, the client
-- keeps reading everything assigned to them (O8: history stays theirs), admins
-- unchanged. Workout history is untouched either way: it reads workout_sessions,
-- the client's own rows, not the program tables.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, what text, result text);
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

insert into auth.users(id,email) values
  ('a8000000-0000-0000-0000-0000000000a1','hist-coach-a@local'),
  ('b8000000-0000-0000-0000-0000000000b1','hist-coach-b@local'),
  ('c8000000-0000-0000-0000-0000000000c1','hist-client-c@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in ('a8000000-0000-0000-0000-0000000000a1','b8000000-0000-0000-0000-0000000000b1');
-- C was A's client; A assigned its private program PA; the generator gave C an
-- unowned plan PG; C then left A for B.
insert into public.workout_programs(id,coach_id,name) values
  ('a8000000-0000-0000-0000-00000000aaaa','a8000000-0000-0000-0000-0000000000a1','PA (A''s private)'),
  ('f8000000-0000-0000-0000-00000000ffff',null,'PG (generated, unowned)');
insert into public.program_workouts(program_id,week_number,day_of_week,title) values
  ('a8000000-0000-0000-0000-00000000aaaa',1,'Monday','PA w1'),
  ('f8000000-0000-0000-0000-00000000ffff',1,'Monday','PG w1');
insert into public.workout_program_assignments(program_id,client_id,coach_id,status) values
  ('a8000000-0000-0000-0000-00000000aaaa','c8000000-0000-0000-0000-0000000000c1','a8000000-0000-0000-0000-0000000000a1','replaced'),
  ('f8000000-0000-0000-0000-00000000ffff','c8000000-0000-0000-0000-0000000000c1',null,'active');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('a8000000-0000-0000-0000-0000000000a1','c8000000-0000-0000-0000-0000000000c1','cancelled','coach'),
  ('b8000000-0000-0000-0000-0000000000b1','c8000000-0000-0000-0000-0000000000c1','active','coach');
insert into public.workout_sessions(user_id,workout_title,status,started_at,completed_at)
values ('c8000000-0000-0000-0000-0000000000c1','PA w1','completed',now()-interval '30 days',now()-interval '30 days');

create function pg_temp.measure(ph text) returns void language plpgsql as $$
begin
  insert into res values
   ('O7','new coach B reads former coach A''s private program', ph||': '||pg_temp.sees('b8000000-0000-0000-0000-0000000000b1','public.program_workouts where program_id=''a8000000-0000-0000-0000-00000000aaaa''')),
   ('O8','client C still reads PA (its history)', ph||': '||pg_temp.sees('c8000000-0000-0000-0000-0000000000c1','public.program_workouts where program_id=''a8000000-0000-0000-0000-00000000aaaa''')),
   ('O11','active coach B reads C''s generated (unowned) plan', ph||': '||pg_temp.sees('b8000000-0000-0000-0000-0000000000b1','public.program_workouts where program_id=''f8000000-0000-0000-0000-00000000ffff''')),
   ('O12','former coach A reads its own PA (author)', ph||': '||pg_temp.sees('a8000000-0000-0000-0000-0000000000a1','public.program_workouts where program_id=''a8000000-0000-0000-0000-00000000aaaa''')),
   ('H1','client C''s workout history (own sessions) is intact', ph||': '||pg_temp.sees('c8000000-0000-0000-0000-0000000000c1','public.workout_sessions where user_id=''c8000000-0000-0000-0000-0000000000c1'''));
end $$;

select pg_temp.measure('today');

-- ── the proposed definition ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_read_program(p_program uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.workout_programs p
                  WHERE p.id = p_program AND p.coach_id = (SELECT auth.uid()))
      OR EXISTS (SELECT 1 FROM public.workout_program_assignments a
                   JOIN public.workout_programs p ON p.id = a.program_id
                  WHERE a.program_id = p_program
                    AND (a.client_id = (SELECT auth.uid())
                         OR a.coach_id = (SELECT auth.uid())
                         OR (public.is_active_coach_of(a.client_id)
                             AND (p.coach_id IS NULL OR p.coach_id = a.client_id))))
      OR public.is_admin();
$function$;

select pg_temp.measure('proposed');

select id||'|'||what||'|'||string_agg(result, '  →  ' order by result like 'proposed%') from res group by id, what order by id;
rollback;
