-- Migrations 193-194 regression (owner decisions 1 and 4, 2026-11-15), run on the
-- LOCAL REPLAY only (loopback scratch DB). One transaction, always ROLLED BACK.
-- Client writes are issued as `authenticated` with the caller's JWT claims, so RLS
-- and the triggers apply as on the platform. Each denial has a positive control.
-- Output: one `PASS|id|detail` or `FAIL|id|detail` line per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);

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

create function pg_temp.plan_of(u uuid) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true);
  set local role authenticated;
  select public.client_plan() into r;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;

-- Fixtures: coaches A, B; clients C1..C6.
insert into auth.users(id,email) values
  ('a2000000-0000-0000-0000-0000000000a2','pol-coach-a@local'),
  ('b2000000-0000-0000-0000-0000000000b2','pol-coach-b@local'),
  ('c2100000-0000-0000-0000-0000000000c1','pol-client-1@local'),
  ('c2200000-0000-0000-0000-0000000000c2','pol-client-2@local'),
  ('c2300000-0000-0000-0000-0000000000c3','pol-client-3@local'),
  ('c2400000-0000-0000-0000-0000000000c4','pol-client-4@local'),
  ('c2500000-0000-0000-0000-0000000000c5','pol-client-5@local'),
  ('c2600000-0000-0000-0000-0000000000c6','pol-client-6@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach'
 where id in ('a2000000-0000-0000-0000-0000000000a2','b2000000-0000-0000-0000-0000000000b2');

-- ===========================================================================
-- 193 · decision 1: an unpaid client-activated relationship is data sharing only
-- ===========================================================================
do $$
declare r text; p text;
begin
  -- C1 inserts its own relationship straight to active (the intake path).
  r := pg_temp.run_as('c2100000-0000-0000-0000-0000000000c1',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (''a2000000-0000-0000-0000-0000000000a2'',''c2100000-0000-0000-0000-0000000000c1'',''active'',''client'')');
  p := pg_temp.plan_of('c2100000-0000-0000-0000-0000000000c1');
  insert into res values ('D1 a client that activates its own relationship gets data sharing, not Coach-Guided',
    r='ok' and p='free', 'insert='||r||' plan='||p);
  insert into res select 'D2 …and the row says who activated it', (to_jsonb(x)->>'activated_by')='client', 'activated_by='||coalesce(to_jsonb(x)->>'activated_by','null')
    from public.coach_client_relationships x where client_id='c2100000-0000-0000-0000-0000000000c1';

  -- C1 cannot rewrite the provenance.
  r := pg_temp.run_as('c2100000-0000-0000-0000-0000000000c1',
    'update public.coach_client_relationships set activated_by=''coach'' where client_id=''c2100000-0000-0000-0000-0000000000c1''');
  insert into res select 'D3 a client cannot choose activated_by', (to_jsonb(x)->>'activated_by')='client',
    'update='||r||' activated_by='||coalesce(to_jsonb(x)->>'activated_by','null')
    from public.coach_client_relationships x where client_id='c2100000-0000-0000-0000-0000000000c1';

  -- C2 requests (pending); coach A approves -> Coach-Guided.
  perform pg_temp.run_as('c2200000-0000-0000-0000-0000000000c2',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (''a2000000-0000-0000-0000-0000000000a2'',''c2200000-0000-0000-0000-0000000000c2'',''pending'',''client'')');
  r := pg_temp.run_as('a2000000-0000-0000-0000-0000000000a2',
    'update public.coach_client_relationships set status=''active'' where client_id=''c2200000-0000-0000-0000-0000000000c2'' and status=''pending''');
  p := pg_temp.plan_of('c2200000-0000-0000-0000-0000000000c2');
  insert into res values ('D4 a coach-approved relationship is Coach-Guided (positive control)',
    r='ok' and p='coach_guided', 'approve='||r||' plan='||p);

  -- C3 requests, then activates it itself -> data sharing only.
  perform pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (''a2000000-0000-0000-0000-0000000000a2'',''c2300000-0000-0000-0000-0000000000c3'',''pending'',''client'')');
  r := pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3',
    'update public.coach_client_relationships set status=''active'' where client_id=''c2300000-0000-0000-0000-0000000000c3''');
  p := pg_temp.plan_of('c2300000-0000-0000-0000-0000000000c3');
  insert into res values ('D5 a client that self-approves its own pending request gets data sharing only',
    r='ok' and p='free', 'activate='||r||' plan='||p);

  -- A paid coach subscription still grants Coach-Guided, whoever activated.
  insert into public.subscriptions(user_id,kind,coach_id,stripe_subscription_id,status,current_period_end)
    values ('c2100000-0000-0000-0000-0000000000c1','package_monthly','a2000000-0000-0000-0000-0000000000a2',
            'sub_pol_test_1','active', now()+interval '20 days');
  p := pg_temp.plan_of('c2100000-0000-0000-0000-0000000000c1');
  insert into res values ('D6 a paid coach subscription grants Coach-Guided (positive control)', p='coach_guided', 'plan='||p);

  -- The webhook / service role (no signed-in caller) activating -> 'system' -> Coach-Guided.
  insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by)
    values ('b2000000-0000-0000-0000-0000000000b2','c2400000-0000-0000-0000-0000000000c4','active','client');
  p := pg_temp.plan_of('c2400000-0000-0000-0000-0000000000c4');
  insert into res select 'D7 a server-side activation (webhook/service role) is Coach-Guided',
    (to_jsonb(x)->>'activated_by')='system' and p='coach_guided', 'activated_by='||coalesce(to_jsonb(x)->>'activated_by','null')||' plan='||p
    from public.coach_client_relationships x where client_id='c2400000-0000-0000-0000-0000000000c4';

  -- A row activated before 193 (activated_by NULL) keeps its access.
  insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by)
    values ('b2000000-0000-0000-0000-0000000000b2','c2500000-0000-0000-0000-0000000000c5','pending','client');
  alter table public.coach_client_relationships disable trigger user;
  begin
    execute 'update public.coach_client_relationships set status=''active'', activated_by=null where client_id=''c2500000-0000-0000-0000-0000000000c5''';
  exception when undefined_column then
    update public.coach_client_relationships set status='active' where client_id='c2500000-0000-0000-0000-0000000000c5';
  end;
  alter table public.coach_client_relationships enable trigger user;
  p := pg_temp.plan_of('c2500000-0000-0000-0000-0000000000c5');
  insert into res values ('D8 a relationship activated before 193 (no provenance) keeps its access', p='coach_guided', 'plan='||p);
end $$;

-- ===========================================================================
-- 195 · decision 1 in the database: booking a coach's call needs Coach-Guided access
-- ===========================================================================
insert into public.coach_availability(id,coach_id,slot_time) values
  ('5b000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-0000000000a2', now()+interval '2 days'),
  ('5b000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-0000000000a2', now()+interval '3 days');
do $$
declare r text;
begin
  -- C3 self-activated its relationship with coach A (D5): data sharing only.
  r := pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3', format(
    'insert into public.coaching_calls(client_id,coach_id,availability_slot_id,scheduled_at,status) values (%L,%L,%L,now()+interval ''2 days'',''scheduled'')',
    'c2300000-0000-0000-0000-0000000000c3','a2000000-0000-0000-0000-0000000000a2','5b000000-0000-0000-0000-000000000001'));
  insert into res values ('B1 a self-activated (unpaid) client cannot book the coach through the API', r='42501', r);
  -- C2's relationship was approved by coach A (D4): Coach-Guided.
  r := pg_temp.run_as('c2200000-0000-0000-0000-0000000000c2', format(
    'insert into public.coaching_calls(client_id,coach_id,availability_slot_id,scheduled_at,status) values (%L,%L,%L,now()+interval ''3 days'',''scheduled'')',
    'c2200000-0000-0000-0000-0000000000c2','a2000000-0000-0000-0000-0000000000a2','5b000000-0000-0000-0000-000000000002'));
  insert into res values ('B2 a coach-approved client books (positive control)', r='ok', r);
  -- A client with NO relationship at all, booking any coach.
  r := pg_temp.run_as('c2500000-0000-0000-0000-0000000000c5', format(
    'insert into public.coaching_calls(client_id,coach_id,scheduled_at,status) values (%L,%L,now()+interval ''4 days'',''scheduled'')',
    'c2500000-0000-0000-0000-0000000000c5','a2000000-0000-0000-0000-0000000000a2'));
  insert into res values ('B3 a stranger cannot book a coach they have no access to', r='42501', r);
end $$;

-- ===========================================================================
-- 194 · decision 4: invites can be accepted; source from the VERIFIED email
-- ===========================================================================
insert into public.coach_invites(id,coach_id,invitee_email,token,status,expires_at) values
  ('11100000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-0000000000b2','pol-client-6@local','tok-good','pending', now()+interval '3 days'),
  ('11100000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-0000000000b2','pol-client-6@local','tok-expired','pending', now()-interval '1 day'),
  ('11100000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-0000000000b2','someone-else@local','tok-other','pending', now()+interval '3 days'),
  ('11100000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-0000000000a2','victim-invitee@local','tok-steal','pending', now()+interval '3 days');

do $$
declare r text; p text;
begin
  r := pg_temp.run_as('c2600000-0000-0000-0000-0000000000c6', 'select public.accept_coach_invite(''tok-expired'')');
  insert into res values ('I1 an expired invite is refused 42501', r='42501', r);
  r := pg_temp.run_as('c2600000-0000-0000-0000-0000000000c6', 'select public.accept_coach_invite(''tok-other'')');
  insert into res values ('I2 an invite sent to another email is refused 42501', r='42501', r);
  r := pg_temp.run_as('c2600000-0000-0000-0000-0000000000c6', 'select public.accept_coach_invite(''no-such-token'')');
  insert into res values ('I3 an unknown token is refused 42501 (same refusal)', r='42501', r);
  insert into res select 'I4 the refused calls linked nothing', count(*)=0, 'relationships='||count(*)
    from public.coach_client_relationships where client_id='c2600000-0000-0000-0000-0000000000c6';

  r := pg_temp.run_as('c2600000-0000-0000-0000-0000000000c6', 'select public.accept_coach_invite(''tok-good'')');
  p := pg_temp.plan_of('c2600000-0000-0000-0000-0000000000c6');
  insert into res select 'I5 a valid invite links the client: active, coach-invited, activated by the invite',
    r='ok' and x.status='active' and x.client_source='coach_invited' and (to_jsonb(x)->>'activated_by')='invite' and p='coach_guided',
    r||' status='||x.status||' source='||coalesce(x.client_source,'null')||' by='||coalesce(to_jsonb(x)->>'activated_by','null')||' plan='||p
    from public.coach_client_relationships x where client_id='c2600000-0000-0000-0000-0000000000c6';
  insert into res select 'I6 the invite is consumed', status='accepted' and accepted_at is not null,
    'status='||status from public.coach_invites where id='11100000-0000-0000-0000-000000000001';
  insert into res select 'I6b both parties are told (client and coach, invite_accepted)',
    count(*) filter (where recipient_id='c2600000-0000-0000-0000-0000000000c6')=1
      and count(*) filter (where recipient_id='b2000000-0000-0000-0000-0000000000b2')=1,
    'client='||count(*) filter (where recipient_id='c2600000-0000-0000-0000-0000000000c6')
      ||' coach='||count(*) filter (where recipient_id='b2000000-0000-0000-0000-0000000000b2')
    from public.notifications where type='invite_accepted';
  r := pg_temp.run_as('c2600000-0000-0000-0000-0000000000c6', 'select public.accept_coach_invite(''tok-good'')');
  insert into res values ('I7 an invite is single use', r='42501', r);

  -- The 0%-commission exploit: rewrite the PROFILE email to an invited address.
  perform pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3',
    'update public.user_profiles set email=''victim-invitee@local'' where id=''c2300000-0000-0000-0000-0000000000c3''');
  delete from public.coach_client_relationships where client_id='c2300000-0000-0000-0000-0000000000c3';
  r := pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (''a2000000-0000-0000-0000-0000000000a2'',''c2300000-0000-0000-0000-0000000000c3'',''pending'',''client'')');
  insert into res select 'I8 a rewritten profile email does not buy 0% commission (verified email is used)',
    r='ok' and client_source='marketplace', r||' source='||coalesce(client_source,'null')
    from public.coach_client_relationships where client_id='c2300000-0000-0000-0000-0000000000c3';
  r := pg_temp.run_as('c2300000-0000-0000-0000-0000000000c3', 'select public.accept_coach_invite(''tok-steal'')');
  insert into res values ('I9 nor can it accept someone else''s invite', r='42501', r);
end $$;

select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || coalesce(detail,'') from res order by id;
rollback;
