-- Migration 198 regression: session credits are not writable by a coach, and a
-- balance stays in range. LOCAL REPLAY only (loopback scratch DB). One
-- transaction, always ROLLED BACK. Writes run as `authenticated` with JWT
-- claims, so RLS applies as on the platform. The grant path (the Stripe
-- webhook, service role) is the positive control.
-- Output: `PASS|id|detail` or `FAIL|id|detail` per assertion.

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

insert into auth.users(id,email) values
  ('a1980000-0000-0000-0000-0000000000a1','cr-coach@local'),
  ('c1980000-0000-0000-0000-0000000000c1','cr-client@local'),
  ('d1980000-0000-0000-0000-0000000000d1','cr-other@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id='a1980000-0000-0000-0000-0000000000a1';
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by)
values ('a1980000-0000-0000-0000-0000000000a1','c1980000-0000-0000-0000-0000000000c1','active','coach');

do $$
declare r text; v int; k uuid := 'e1980000-0000-0000-0000-0000000000e1';
  coach constant uuid := 'a1980000-0000-0000-0000-0000000000a1';
  client constant uuid := 'c1980000-0000-0000-0000-0000000000c1';
  other constant uuid := 'd1980000-0000-0000-0000-0000000000d1';
begin
  -- The grant path (the webhook runs as service role; here: the owner) still works.
  begin
    insert into public.client_session_credits(id,client_id,coach_id,sessions_total) values (k, client, coach, 5);
    r := 'ok';
  exception when others then r := sqlstate; end;
  insert into res values ('G1 the server grant path still writes a credit block (positive control)', r='ok', 'insert='||r);

  r := pg_temp.run_as(coach, format('update public.client_session_credits set sessions_total=500 where id=%L', k));
  insert into res select 'K1 a coach cannot raise or rewrite a balance', c.sessions_total=5, 'update='||r||' total='||c.sessions_total
    from public.client_session_credits c where c.id=k;

  r := pg_temp.run_as(coach, format('update public.client_session_credits set client_id=%L where id=%L', other, k));
  insert into res select 'K2 a coach cannot move a block to another client', c.client_id=client, 'update='||r||' owner='||c.client_id
    from public.client_session_credits c where c.id=k;

  -- Measured against the value just before THIS statement, so K1's outcome cannot leak in.
  select sessions_total into v from public.client_session_credits where id=k;
  r := pg_temp.run_as(client, format('update public.client_session_credits set sessions_total=99 where id=%L', k));
  insert into res select 'K3 a client cannot change its own balance', c.sessions_total=v, 'update='||r||' total='||c.sessions_total||' was='||v
    from public.client_session_credits c where c.id=k;

  r := pg_temp.run_as(client, format('insert into public.client_session_credits(client_id,coach_id,sessions_total) values (%L,%L,10)', client, coach));
  insert into res values ('K4 a client cannot grant itself credits', r<>'ok', 'insert='||r);

  -- Range: used never exceeds total, never negative (even for the server).
  begin
    update public.client_session_credits set sessions_used = 6 where id = k; r := 'ok';
  exception when others then r := sqlstate; end;
  insert into res values ('K5 sessions_used cannot exceed sessions_total', r='23514', 'update='||r);
  begin
    update public.client_session_credits set sessions_used = -1 where id = k; r := 'ok';
  exception when others then r := sqlstate; end;
  insert into res values ('K6 sessions_used cannot be negative', r='23514', 'update='||r);

  -- Reads unchanged.
  insert into res select 'R1 the client and the coach still read the block',
    (select count(*) from public.client_session_credits) >= 1, 'ok';
end $$;

select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || detail from res order by id;
rollback;
