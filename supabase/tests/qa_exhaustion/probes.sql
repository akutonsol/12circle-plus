-- QA-EXHAUSTION probes. Each asserts the SECURE outcome and prints PASS|ID|detail or
-- FAIL|ID|detail. A FAIL is a reproduced defect. Every probe runs inside a savepoint
-- so one error cannot mask another. Requires fixtures.sql in the same transaction.
\set ON_ERROR_STOP off
create temp table qax_out(id text, ok boolean, detail text) on commit drop;
grant all on qax_out to authenticated;

-- Results must survive "rollback to savepoint": stash them client-side (psql \gset), roll
-- back, then restore. Without this a rolled-back probe prints nothing at all.
\set KEEP 'select coalesce(string_agg(id||chr(31)||ok||chr(31)||detail, chr(30)),'''') as qax_keep from qax_out \\gset'
\set RESTORE 'delete from qax_out; insert into qax_out select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''qax_keep'',chr(30))) r where r <> '''';'
create or replace function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;

-- CTRL-1: an unrelated user must NOT write another user's cycle log (proves the harness sees denials).
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
do $$ begin
  insert into public.cycle_logs(user_id,start_date) values ('22222222-2222-2222-2222-222222222222','2026-01-01');
  insert into qax_out values ('CTRL-1',false,'cross-user cycle_logs insert was ALLOWED');
exception when insufficient_privilege then insert into qax_out values ('CTRL-1',true,'denied (42501)'); end $$;
reset role; release savepoint p;

-- QAX-SEC-01: a non-coach must not supersede another coach's active nutrition plan via the RPC.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
do $$ begin
  perform public.assign_nutrition_plan('22222222-2222-2222-2222-222222222222'::uuid,800,10,10,10,null,'qax attacker');
  insert into qax_out values ('QAX-SEC-01',false,'stranger replaced the victim''s active plan');
exception when others then insert into qax_out values ('QAX-SEC-01',true,'refused: '||sqlstate); end $$;
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-02a: a cancelled coach must not read the former client's progress photos.
savepoint p; select pg_temp.as_user('33333333-3333-3333-3333-333333333333'); set local role authenticated;
insert into qax_out select 'QAX-SEC-02a', count(*)=0, 'cancelled coach sees '||count(*)||' photo object(s)'
  from storage.objects where bucket_id='progress-photos';
reset role; release savepoint p;

-- QAX-SEC-02b: a self-registered coach who self-creates a PENDING relationship must not read photos.
savepoint p; select set_config('request.jwt.claims','{}',true);
-- 'coach' is self-selectable at signup (migration 115 handle_new_user); set it as signup would.
update public.user_profiles set role='coach' where id='11111111-1111-1111-1111-111111111111';
select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by)
  values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','pending','coach');
insert into qax_out select 'QAX-SEC-02b', count(*)=0, 'stranger coach with self-made pending row sees '||count(*)||' photo object(s)'
  from storage.objects where bucket_id='progress-photos';
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-03: an unrelated user must not create coaching records aimed at another user.
create or replace function pg_temp.try_write(pid text, stmt text) returns void language plpgsql as $$
begin
  execute stmt;
  insert into qax_out values (pid,false,'ALLOWED: '||left(stmt,70));
exception when insufficient_privilege then insert into qax_out values (pid,true,'denied');
          when others then insert into qax_out values (pid,true,'refused: '||sqlstate);
end $$;
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
select pg_temp.try_write('QAX-SEC-03.client_habits',  $q$insert into public.client_habits(client_id,coach_id,name) values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','qax')$q$);
select pg_temp.try_write('QAX-SEC-03.action_items',   $q$insert into public.action_items(client_id,coach_id,title) values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','qax')$q$);
select pg_temp.try_write('QAX-SEC-03.coaching_calls', $q$insert into public.coaching_calls(coach_id,client_id,scheduled_at) values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222',now())$q$);
select pg_temp.try_write('QAX-SEC-03.coach_video_responses', $q$insert into public.coach_video_responses(coach_id,client_id) values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222')$q$);
select pg_temp.try_write('QAX-SEC-03.client_nutrition_plans', $q$insert into public.client_nutrition_plans(client_id,coach_id,calories_target,is_active) values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111',600,false)$q$);
select pg_temp.try_write('QAX-SEC-03.workout_program_assignments', $q$with pr as (insert into public.workout_programs(coach_id,name) values ('11111111-1111-1111-1111-111111111111','qax') returning id) insert into public.workout_program_assignments(program_id,client_id,coach_id) select id,'22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111' from pr$q$);
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-04: a non-participant must not post into someone else's conversation.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
select pg_temp.try_write('QAX-SEC-04', $q$insert into public.messages(conversation_id,sender_id,content) values ('55555555-5555-5555-5555-000000000001','11111111-1111-1111-1111-111111111111','qax injected')$q$);
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-05: a non-owner must not overwrite/delete global exercise media.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
with d as (delete from storage.objects where bucket_id='exercise-media' and name='library/qax-squat.mp4' returning 1)
insert into qax_out select 'QAX-SEC-05', count(*)=0, 'non-owner deleted '||count(*)||' exercise-media object(s)' from d;
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-06: another coach's private draft exercise must not be readable through the exercises view.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'QAX-SEC-06', count(*)=0, 'private draft visible via view: '||count(*) from public.exercises where name='qax private draft';
reset role; release savepoint p;

-- QAX-SEC-08: a self-registered coach must not gain PHI reads by adding someone to "their team".
savepoint p; select set_config('request.jwt.claims','{}',true);
update public.user_profiles set role='coach' where id='11111111-1111-1111-1111-111111111111';
select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
do $$ begin
  insert into public.coach_team_members(coach_id,member_id) values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
exception when others then null; end $$;
insert into qax_out select 'QAX-SEC-08', count(*)=0, 'self-made team lead reads '||count(*)||' PHI profile row(s) of the victim'
  from public.user_profiles where id='22222222-2222-2222-2222-222222222222' and medical_conditions is not null;
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-09: an event vendor must not read a registrant's medical / PAR-Q columns.
savepoint p; select pg_temp.as_user('77777777-0000-0000-0000-000000000007'); set local role authenticated;
insert into qax_out select 'QAX-SEC-09', count(*)=0, 'vendor reads registrant medical/PAR-Q: '||count(*)
  from public.user_profiles where id='22222222-2222-2222-2222-222222222222' and (medical_conditions is not null or parq_answers is not null);
insert into qax_out select 'POS-09', count(*)=1, 'vendor still sees the registration row: '||count(*)
  from public.event_registrations where event_id='66666666-6666-6666-6666-000000000001';
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- FIX-08 (post-fix contract, EXPECTED FAIL before the fix — today no consent path exists): a member who adds THEMSELVES to lead C's team (consent) — C may then read them.
savepoint p; select pg_temp.as_user('22222222-2222-2222-2222-222222222222'); set local role authenticated;
do $$ begin
  insert into public.coach_team_members(coach_id,member_id) values ('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222');
exception when others then null; end $$;
reset role; select pg_temp.as_user('33333333-3333-3333-3333-333333333333'); set local role authenticated;
-- C's coaching relationship is CANCELLED, so the team arm is the only path: not vacuous.
insert into qax_out select 'FIX-08', count(*)=1, 'consented team lead reads member: '||count(*)
  from public.user_profiles where id='22222222-2222-2222-2222-222222222222';
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- QAX-SEC-10: a non-owner must not upload into another coach's folder of the public coach-media bucket.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
select pg_temp.try_write('QAX-SEC-10', $q$insert into storage.objects(bucket_id,name,owner) values ('coach-media','44444444-0000-0000-0000-000000000004/qax-fake.mp4','11111111-1111-1111-1111-111111111111')$q$);
reset role; select pg_temp.as_user('44444444-0000-0000-0000-000000000004'); set local role authenticated;
select pg_temp.try_write('POS-10', $q$insert into storage.objects(bucket_id,name,owner) values ('coach-media','44444444-0000-0000-0000-000000000004/own.mp4','44444444-0000-0000-0000-000000000004')$q$);
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- POSITIVE CONTROLS: the legitimate path must keep working (before AND after any fix).
savepoint p; select pg_temp.as_user('44444444-0000-0000-0000-000000000004'); set local role authenticated;
do $$ begin
  perform public.assign_nutrition_plan('22222222-2222-2222-2222-222222222222'::uuid,2300,160,230,72,null,'qax active coach');
  insert into qax_out values ('POS-01',true,'active coach can assign');
exception when others then insert into qax_out values ('POS-01',false,'active coach refused: '||sqlstate); end $$;
insert into qax_out select 'POS-02', count(*)=1, 'active coach sees '||count(*)||' photo object(s)' from storage.objects where bucket_id='progress-photos';
select pg_temp.try_write('POS-03', $q$insert into public.client_habits(client_id,coach_id,name) values ('22222222-2222-2222-2222-222222222222','44444444-0000-0000-0000-000000000004','qax')$q$);
select pg_temp.try_write('POS-04', $q$insert into public.messages(conversation_id,sender_id,content) values ('55555555-5555-5555-5555-000000000001','44444444-0000-0000-0000-000000000004','qax legit')$q$);
insert into qax_out select 'POS-06', count(*)=1, 'owner sees own draft via view: '||count(*) from public.exercises where name='qax private draft';
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE
-- try_write marks ALLOWED as not-ok; for POS-03/04 ALLOWED is the correct outcome.
update qax_out set ok = not ok where id in ('POS-03','POS-04','POS-10');

select case when ok then 'PASS' else 'FAIL' end||'|'||id||'|'||detail from qax_out order by id;
