-- Migrations 187-192 regression, run on the LOCAL REPLAY only (loopback scratch DB).
--
-- Runs inside ONE transaction that is always ROLLED BACK. Never applied to QA or
-- production -- see integrity_187_192_replay.sh, which refuses any non-loopback
-- target and any credential.
--
-- Every client write below is the app's OWN write, issued as `authenticated` with
-- the caller's JWT claims, so RLS applies exactly as it does on the platform:
--   booking   booking_screen.dart _book / _cancelBooking
--   classes   live_class_service.dart bookClass / cancelBooking (incl. its
--             _syncEnrollment and _promoteFromWaitlist writes)
--   comms     CoachProgramService.sendCommunication / updateCommunication
--   rel       a client inserting / updating its own coach_client_relationships row
-- A denial passes only on the expected SQLSTATE, and each has a positive control.
--
-- Output: one `PASS|id|detail` or `FAIL|id|detail` line per assertion.

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);

-- Run `stmt` as `u` (role authenticated, RLS on). Returns 'ok' or the SQLSTATE.
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

-- Fixtures ------------------------------------------------------------------
-- A, B coaches · C1..C4 clients
insert into auth.users(id,email) values
  ('a1000000-0000-0000-0000-0000000000a1','int-coach-a@local'),
  ('b1000000-0000-0000-0000-0000000000b1','int-coach-b@local'),
  ('c1000000-0000-0000-0000-0000000000c1','int-client-1@local'),
  ('c2000000-0000-0000-0000-0000000000c2','int-client-2@local'),
  ('c3000000-0000-0000-0000-0000000000c3','int-client-3@local'),
  ('c4000000-0000-0000-0000-0000000000c4','int-client-4@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach' where id in
  ('a1000000-0000-0000-0000-0000000000a1','b1000000-0000-0000-0000-0000000000b1');

-- Slots: S1,S2 coach A · S3 coach B · S4 coach A, flagged booked with no call.
insert into public.coach_availability(id,coach_id,slot_time,is_booked) values
  ('51000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1', now()+interval '2 days', false),
  ('51000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-0000000000a1', now()+interval '3 days', false),
  ('51000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-0000000000b1', now()+interval '4 days', false),
  ('51000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-0000000000a1', now()+interval '5 days', true);

-- The app's booking: insert the call, then flag the slot (a no-op for a client).
create function pg_temp.book(u uuid, slot uuid, coach uuid, at timestamptz) returns text language plpgsql as $$
declare r text;
begin
  r := pg_temp.run_as(u, format(
    'insert into public.coaching_calls(client_id,coach_id,availability_slot_id,scheduled_at,duration_minutes,call_type,status) values (%L,%L,%L,%L,30,''check_in'',''scheduled'')',
    u, coach, slot, at));
  if r = 'ok' then
    perform pg_temp.run_as(u, format('update public.coach_availability set is_booked = true where id = %L', slot));
  end if;
  return r;
end $$;

-- ===========================================================================
-- 187 · booking slot integrity
-- ===========================================================================
do $$
declare r text; t timestamptz;
begin
  select slot_time into t from public.coach_availability where id='51000000-0000-0000-0000-000000000001';
  r := pg_temp.book('c1000000-0000-0000-0000-0000000000c1','51000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1',t);
  insert into res values ('B1 a client books a free slot (positive control)', r='ok', r);
  insert into res select 'B2 the booked slot is now flagged booked (it is hidden from other clients)',
    is_booked, 'is_booked='||is_booked from public.coach_availability where id='51000000-0000-0000-0000-000000000001';
  r := pg_temp.book('c2000000-0000-0000-0000-0000000000c2','51000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1',t);
  insert into res values ('B3 a second client booking the same slot is refused 23505', r='23505', r);
  insert into res select 'B4 the slot holds exactly one live call', count(*)=1, 'live calls='||count(*)
    from public.coaching_calls where availability_slot_id='51000000-0000-0000-0000-000000000001' and status<>'cancelled';

  select slot_time into t from public.coach_availability where id='51000000-0000-0000-0000-000000000003';
  r := pg_temp.book('c2000000-0000-0000-0000-0000000000c2','51000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-0000000000a1',t);
  insert into res values ('B5 a call naming coach A on coach B''s slot is refused 23514', r='23514', r);

  -- Cancel as the client, exactly as _cancelBooking does.
  r := pg_temp.run_as('c1000000-0000-0000-0000-0000000000c1',
    'update public.coaching_calls set status=''cancelled'' where client_id=''c1000000-0000-0000-0000-0000000000c1''');
  perform pg_temp.run_as('c1000000-0000-0000-0000-0000000000c1',
    'update public.coach_availability set is_booked=false where id=''51000000-0000-0000-0000-000000000001''');
  insert into res select 'B6 cancelling reopens the slot', r='ok' and not is_booked, 'cancel='||r||' is_booked='||is_booked
    from public.coach_availability where id='51000000-0000-0000-0000-000000000001';
  select slot_time into t from public.coach_availability where id='51000000-0000-0000-0000-000000000001';
  r := pg_temp.book('c2000000-0000-0000-0000-0000000000c2','51000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1',t);
  insert into res values ('B7 the reopened slot can be booked again', r='ok', r);

  r := pg_temp.book('c3000000-0000-0000-0000-0000000000c3','51000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-0000000000a1', now()+interval '9 days');
  insert into res select 'B8 a call takes its slot''s time, not a time the client supplies',
    r='ok' and c.scheduled_at = a.slot_time, r||' scheduled_at=slot_time:'||(c.scheduled_at = a.slot_time)
    from public.coaching_calls c join public.coach_availability a on a.id=c.availability_slot_id
   where c.availability_slot_id='51000000-0000-0000-0000-000000000002';

  select slot_time into t from public.coach_availability where id='51000000-0000-0000-0000-000000000004';
  r := pg_temp.book('c3000000-0000-0000-0000-0000000000c3','51000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-0000000000a1',t);
  insert into res values ('B9 a slot already flagged booked (no call behind it) is refused, its flag respected', r='23505', r);

  -- A completed call keeps its slot.
  update public.coaching_calls set status='completed' where availability_slot_id='51000000-0000-0000-0000-000000000002';
  insert into res select 'B10 a completed call keeps its slot booked', is_booked, 'is_booked='||is_booked
    from public.coach_availability where id='51000000-0000-0000-0000-000000000002';
end $$;
insert into res select 'B11 a partial unique index allows one non-cancelled call per slot',
  count(*)=1, coalesce(string_agg(indexname,','),'none') from pg_indexes
  where tablename='coaching_calls' and indexdef like '%UNIQUE%availability_slot_id%';

-- ===========================================================================
-- 188 · class seats (capacity 2)
-- ===========================================================================
insert into public.classes(id,coach_id,title,scheduled_at,max_capacity,current_enrolled)
  values ('c1a50000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1','int class', now()+interval '2 days', 2, 0);

-- The app's bookClass: count confirmed (RLS: own rows only), pick a status, upsert,
-- then _syncEnrollment. Returns the stored status.
create function pg_temp.book_class(u uuid) returns text language plpgsql as $$
declare st text := 'confirmed';
begin
  perform pg_temp.run_as(u, format(
    'insert into public.class_bookings(class_id,user_id,status) values (%L,%L,%L) on conflict (class_id,user_id) do update set status = excluded.status',
    'c1a50000-0000-0000-0000-000000000001', u, st));
  -- One transaction gives every booking the same now(); in production each booking
  -- is its own transaction. Give a freshly inserted booking its real moment.
  update public.class_bookings set booked_at = clock_timestamp()
   where class_id='c1a50000-0000-0000-0000-000000000001' and user_id=u and booked_at = now();
  perform pg_temp.run_as(u,
    'update public.classes set current_enrolled = 0 where id = ''c1a50000-0000-0000-0000-000000000001'' and false');
  return (select status from public.class_bookings where class_id='c1a50000-0000-0000-0000-000000000001' and user_id=u);
end $$;

do $$
declare s1 text; s2 text; s3 text; s4 text; n int;
begin
  s1 := pg_temp.book_class('c1000000-0000-0000-0000-0000000000c1');
  perform pg_sleep(0.01);
  s2 := pg_temp.book_class('c2000000-0000-0000-0000-0000000000c2');
  perform pg_sleep(0.01);
  s3 := pg_temp.book_class('c3000000-0000-0000-0000-0000000000c3');
  perform pg_sleep(0.01);
  s4 := pg_temp.book_class('c4000000-0000-0000-0000-0000000000c4');
  insert into res values ('K1 the first two bookings are confirmed (positive control)', s1='confirmed' and s2='confirmed', s1||','||s2);
  insert into res values ('K2 bookings past capacity are waitlisted, not confirmed', s3='waitlisted' and s4='waitlisted', s3||','||s4);
  insert into res select 'K3 current_enrolled counts the confirmed seats', current_enrolled=2, 'current_enrolled='||current_enrolled
    from public.classes where id='c1a50000-0000-0000-0000-000000000001';

  -- C1 cancels, as cancelBooking does (then the app's promotion attempt on C3's row).
  perform pg_temp.run_as('c1000000-0000-0000-0000-0000000000c1',
    'update public.class_bookings set status=''cancelled'' where class_id=''c1a50000-0000-0000-0000-000000000001'' and user_id=''c1000000-0000-0000-0000-0000000000c1''');
  insert into res select 'K4 a released seat goes to the EARLIEST waitlisted booking',
    max(status) filter (where user_id='c3000000-0000-0000-0000-0000000000c3')='confirmed'
    and max(status) filter (where user_id='c4000000-0000-0000-0000-0000000000c4')='waitlisted',
    string_agg(right(user_id::text,2)||'='||status, ',' order by user_id)
    from public.class_bookings where class_id='c1a50000-0000-0000-0000-000000000001';
  select count(*) into n from public.notifications
   where recipient_id='c3000000-0000-0000-0000-0000000000c3' and type='class' and title='You''re In!';
  insert into res values ('K5 the promoted client is told, once', n=1, 'notifications='||n);
  select count(*) into n from public.notifications
   where recipient_id='c4000000-0000-0000-0000-0000000000c4' and title='You''re In!';
  insert into res values ('K6 the still-waitlisted client is NOT told they are in', n=0, 'notifications='||n);
  insert into res select 'K7 current_enrolled is still the confirmed count after the hand-on', current_enrolled=2,
    'current_enrolled='||current_enrolled from public.classes where id='c1a50000-0000-0000-0000-000000000001';

  s1 := pg_temp.book_class('c1000000-0000-0000-0000-0000000000c1');
  insert into res values ('K8 re-booking into a full class waitlists (the conflict-update path)', s1='waitlisted', s1);
  s2 := pg_temp.book_class('c2000000-0000-0000-0000-0000000000c2');
  insert into res values ('K9 re-upserting a held confirmed seat keeps it', s2='confirmed', s2);
  select count(*) into n from public.class_bookings
   where class_id='c1a50000-0000-0000-0000-000000000001' and status='confirmed';
  insert into res values ('K10 confirmed bookings never exceed capacity', n<=2, 'confirmed='||n);
end $$;

-- ===========================================================================
-- 189 · communications report a write that changed nothing
-- ===========================================================================
insert into public.communications(id,coach_id,subject_id,type,brief,status)
  values ('c0330000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-0000000000a1',
          'c1000000-0000-0000-0000-0000000000c1','weekly_review','{}'::jsonb,'draft');
do $$
declare r1 text; r2 text; r3 text; r4 text; r5 text;
begin
  r1 := pg_temp.run_as('b1000000-0000-0000-0000-0000000000b1',
    'select public.send_communication(''c0330000-0000-0000-0000-000000000001'')');
  r2 := pg_temp.run_as('a1000000-0000-0000-0000-0000000000a1',
    'select public.send_communication(''c0330000-0000-0000-0000-0000000000ff'')');
  r3 := pg_temp.run_as('b1000000-0000-0000-0000-0000000000b1',
    'select public.update_communication(''c0330000-0000-0000-0000-000000000001'',''x'',''y'')');
  insert into res values ('M1 another coach sending is refused 42501', r1='42501', r1);
  insert into res values ('M2 sending an id that does not exist is refused 42501 (same refusal)', r2='42501', r2);
  insert into res values ('M3 another coach editing is refused 42501', r3='42501', r3);
  insert into res select 'M4 the refused calls changed nothing', status='draft' and client_text is null,
    'status='||status from public.communications where id='c0330000-0000-0000-0000-000000000001';
  r4 := pg_temp.run_as('a1000000-0000-0000-0000-0000000000a1',
    'select public.update_communication(''c0330000-0000-0000-0000-000000000001'',''hello'',''note'')');
  r5 := pg_temp.run_as('a1000000-0000-0000-0000-0000000000a1',
    'select public.send_communication(''c0330000-0000-0000-0000-000000000001'')');
  insert into res select 'M5 the owning coach edits and sends (positive control)',
    r4='ok' and r5='ok' and status='sent' and client_text='hello', r4||','||r5||' status='||status
    from public.communications where id='c0330000-0000-0000-0000-000000000001';
end $$;

-- ===========================================================================
-- 190 · PR detection counts confirmed sets only
-- ===========================================================================
insert into public.workout_sessions(id,user_id,workout_title,status)
  values ('5e550000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-0000000000c1','int session','in_progress');
create function pg_temp.set_log(n int, ex text, kg numeric, done boolean) returns void language sql as $$
  insert into public.workout_set_logs(session_id,user_id,set_id,exercise_instance_id,exercise_name,set_number,reps,weight_kg,completed)
  values ('5e550000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-0000000000c1',
          'int-set-'||ex||'-'||n,'int-inst-'||ex,ex,n,5,kg,done) $$;
do $$
declare n int;
begin
  perform pg_temp.set_log(1,'Bench',50,true);
  perform pg_temp.set_log(2,'Bench',80,false);         -- typed, never confirmed
  select count(*) into n from public.notifications
   where recipient_id='c1000000-0000-0000-0000-0000000000c1' and type='pr_achieved' and data->>'exercise'='Bench';
  insert into res values ('P1 an UNCONFIRMED heavier set announces no PR', n=0, 'pr notifications='||n);
  perform pg_temp.set_log(1,'Squat',50,true);
  perform pg_temp.set_log(2,'Squat',80,false);
  perform pg_temp.set_log(3,'Squat',60,true);          -- a real PR over the confirmed 50
  select count(*) into n from public.notifications
   where recipient_id='c1000000-0000-0000-0000-0000000000c1' and type='pr_achieved' and data->>'exercise'='Squat'
     and (data->>'weight_kg')::numeric = 60;
  insert into res values ('P2 a confirmed set is measured against confirmed sets only (60 beats the confirmed 50, and is the PR announced)', n=1, 'pr notifications at 60kg='||n);
end $$;

-- ===========================================================================
-- 191 · realtime publishes workout_set_logs
-- ===========================================================================
insert into res select 'R0 workout_set_logs is in supabase_realtime', count(*)=1, 'rows='||count(*)
  from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='workout_set_logs';

-- ===========================================================================
-- 192 · price and commission source are not client-writable
-- ===========================================================================
insert into public.coach_invites(coach_id,invitee_email)
  values ('b1000000-0000-0000-0000-0000000000b1','int-client-4@local');
do $$
declare r text;
begin
  r := pg_temp.run_as('c4000000-0000-0000-0000-0000000000c4',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by,client_source) values (''a1000000-0000-0000-0000-0000000000a1'',''c4000000-0000-0000-0000-0000000000c4'',''pending'',''client'',''coach_invited'')');
  insert into res select 'S1 a client cannot insert itself as coach_invited (0% commission) -- the source is derived',
    r='ok' and client_source='marketplace', r||' client_source='||coalesce(client_source,'null')
    from public.coach_client_relationships where coach_id='a1000000-0000-0000-0000-0000000000a1' and client_id='c4000000-0000-0000-0000-0000000000c4';
  r := pg_temp.run_as('c4000000-0000-0000-0000-0000000000c4',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values (''b1000000-0000-0000-0000-0000000000b1'',''c4000000-0000-0000-0000-0000000000c4'',''pending'',''client'')');
  insert into res select 'S2 a genuinely invited client is still derived coach_invited (positive control)',
    r='ok' and client_source='coach_invited', r||' client_source='||coalesce(client_source,'null')
    from public.coach_client_relationships where coach_id='b1000000-0000-0000-0000-0000000000b1' and client_id='c4000000-0000-0000-0000-0000000000c4';
  r := pg_temp.run_as('c3000000-0000-0000-0000-0000000000c3',
    'insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by,monthly_price) values (''a1000000-0000-0000-0000-0000000000a1'',''c3000000-0000-0000-0000-0000000000c3'',''pending'',''client'',1)');
  insert into res values ('S3 a client inserting its own row with a price is refused 42501', r='42501', r);
  r := pg_temp.run_as('c4000000-0000-0000-0000-0000000000c4',
    'update public.coach_client_relationships set monthly_price = 1 where client_id=''c4000000-0000-0000-0000-0000000000c4'' and coach_id=''a1000000-0000-0000-0000-0000000000a1''');
  insert into res values ('S4 a client changing its own price is refused 42501', r='42501', r);
  r := pg_temp.run_as('a1000000-0000-0000-0000-0000000000a1',
    'update public.coach_client_relationships set monthly_price = 99 where client_id=''c4000000-0000-0000-0000-0000000000c4'' and coach_id=''a1000000-0000-0000-0000-0000000000a1''');
  insert into res select 'S5 the coach sets the client''s price (positive control)', r='ok' and monthly_price=99,
    r||' monthly_price='||coalesce(monthly_price::text,'null')
    from public.coach_client_relationships where coach_id='a1000000-0000-0000-0000-0000000000a1' and client_id='c4000000-0000-0000-0000-0000000000c4';
end $$;

-- Report ------------------------------------------------------------------
select case when ok then 'PASS' else 'FAIL' end || '|' || id || '|' || coalesce(detail,'') from res order by id;
rollback;
