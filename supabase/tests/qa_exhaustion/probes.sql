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

-- ── QAX-SEC-06 certification extension (added 2026-10-19) ─────────────────────
-- QAX-SEC-06 above probes the `exercises` view. `exercise_certifications` is a
-- SECOND unpredicated definer view and it reads `custom_exercises` DIRECTLY
-- (086:33), not through `exercises` — so fixsim/QAX-SEC-06.sql cannot close it.
-- The same rows are also returned by the allowlisted SECURITY DEFINER RPC
-- `exercise_certification(p_id)` (084:76-79, no authorization check), which is
-- live in the app at custom_exercise_service.dart:366.

-- Path 1 — direct read: a non-owner must not see another coach's private draft.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'QAX-SEC-06.cert-view', count(*)=0,
  'non-owner sees other coach''s private draft via exercise_certifications: '||count(*)
  from public.exercise_certifications where id='99999999-0000-0000-0000-000000000009';
reset role; release savepoint p;

-- Path 2 — the definer RPC with an id belonging to another owner. `to_jsonb(c)`
-- over no rows yields NULL, so NULL is the secure outcome.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'QAX-SEC-06.cert-rpc',
  public.exercise_certification('99999999-0000-0000-0000-000000000009') is null,
  'exercise_certification(other owner''s private draft) returned: '
    ||coalesce(left((public.exercise_certification('99999999-0000-0000-0000-000000000009'))::text,60),'NULL');
reset role; release savepoint p;

-- Path 3 — certification_summary(). This probe tests migration 116's OWN stated
-- premise, not a preference: 116:463 allowlists it under "E: admin /
-- content-editor, each self-guarding". 086:100-122 carries no guard, so a
-- non-editor reaching it contradicts that classification. The aggregate exposes
-- counts only, never a row; whether library-wide totals should stay library-wide
-- is a product question (see POS-06C) and is NOT asserted here.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
do $$ declare t bigint; begin
  select total into t from public.certification_summary();
  execute 'reset role';
  insert into qax_out values ('QAX-SEC-06.cert-summary', false,
    '116 classes this self-guarding; a non-editor got total='||t);
exception when insufficient_privilege then
            insert into qax_out values ('QAX-SEC-06.cert-summary', true, 'non-editor denied (42501)');
          when others then
            insert into qax_out values ('QAX-SEC-06.cert-summary', true, 'non-editor refused: '||sqlstate);
end $$;
reset role; release savepoint p;

-- Path 4 — anon. GRANT-LEVEL evidence in the replay only: 084:72 and 086:92 both
-- granted anon, and 112:47 revoked it across every view. This asserts the revoke
-- is what the replay reproduces. It is NOT runtime evidence about QA, where the
-- standing anon check is supabase/tests/security/d06-sweep-posture.mjs:41-46.
savepoint p; select set_config('request.jwt.claims','{}',true);
do $$ declare n int; begin
  execute 'set local role anon';
  execute 'select count(*) from public.exercise_certifications' into n;
  execute 'reset role';
  insert into qax_out values ('QAX-SEC-06.cert-anon', n=0, 'anon read rows: '||n);
exception when insufficient_privilege then
            insert into qax_out values ('QAX-SEC-06.cert-anon', true, 'anon denied (42501)');
          when others then
            insert into qax_out values ('QAX-SEC-06.cert-anon', true, 'anon refused: '||sqlstate);
end $$;
reset role; release savepoint p;

-- Path 5 — RESISTANCE TO THE 112 GRANT SWEEP. 112:35-51 sweeps every view in
-- public: REVOKE ALL from PUBLIC/anon/authenticated, then GRANT SELECT to
-- authenticated. A fix that merely withholds that grant is undone the next time
-- such a sweep runs, so this probe re-grants SELECT exactly as 112 would and then
-- re-reads a stranger's private draft. Pre-fix it fails like cert-view; under a
-- body-predicate fix the re-grant is irrelevant and it passes. DDL, so the
-- result is stashed and the savepoint rolled back.
savepoint p; grant select on public.exercise_certifications to authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'QAX-SEC-06.cert-sweep', count(*)=0,
  'after a 112-style re-grant, non-owner sees other coach''s private draft: '||count(*)
  from public.exercise_certifications where id='99999999-0000-0000-0000-000000000009';
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- ── GAP A · the content_manager arm ──────────────────────────────────────────
-- POS-06C covers the ADMIN arm. Option A's predicate admits `is_content_editor()`
-- = admin OR content_manager (083:88-89), and the non-admin editor is the arm that
-- keeps certification_summary() library-wide. It was untested. Three-way
-- distinction: an ordinary caller is DENIED (QAX-SEC-06.cert-summary), the admin
-- passes (POS-06C), and the content_manager must pass with the SAME total.
-- The library count is stashed as postgres first: a content_manager is not an
-- admin, so custom_exercises RLS (005:49-62, 050:12) does not let them count it.
savepoint p;
drop table if exists pg_temp.qax_lib;
create temp table qax_lib as select count(*)::bigint as n from public.custom_exercises;
grant select on qax_lib to authenticated;
select pg_temp.as_user('8888888c-0000-0000-0000-00000000000c'); set local role authenticated;
do $$ declare t bigint; w bigint; begin
  select total into t from public.certification_summary();
  select n into w from qax_lib;
  execute 'reset role';
  insert into qax_out values ('POS-06E', t = w,
    'content_manager summary total='||t||' vs full library='||w);
exception when others then
  execute 'reset role';
  insert into qax_out values ('POS-06E', false, 'content_manager summary refused: '||sqlstate);
end $$;
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE

-- The deliberate CONSEQUENCE of that arm, made explicit and testable rather than
-- left implicit: under Option A a content_manager CAN read another coach's private
-- draft. That is the price of keeping 117's aggregation library-wide, and the owner
-- should see it asserted. Pre-fix this also passes (nothing is scoped yet), so it
-- is a POSITIVE control, not a defect probe.
savepoint p; select pg_temp.as_user('8888888c-0000-0000-0000-00000000000c'); set local role authenticated;
insert into qax_out select 'POS-06F', count(*)=1,
  'content_manager sees the cross-owner private draft (intended under Option A): '||count(*)
  from public.exercise_certifications where id='99999999-0000-0000-0000-000000000009';
reset role; release savepoint p;

-- ── GAP B · build_workout's candidate pool — NOT CLOSED, and why ───────────
-- `build_workout` (127:27) sources candidates from
--   `from exercises e join exercise_intelligence ei on ei.exercise_id = e.id`
-- with no WHERE, so that join IS the candidate pool. It CANNOT be reproduced from
-- a caller's privilege level, and the first version of this probe was wrong to try:
--   * `build_workout` is SECURITY DEFINER (pg_proc.prosecdef = t), so it evaluates
--     that join with OWNER rights;
--   * `exercise_intelligence`'s only read policy is `intel read staff only ::
--     is_content_editor()`.
-- Measured inside the fixture transaction: as owner the substrate is 2 rows and
-- the join is 2; as an ordinary member both are 0. A caller-level count therefore
-- measures RLS, not the engine's pool, and reporting it as the pool would have been
-- a manufactured result.
--
-- What this probe asserts instead is the real invariant it CAN see, which is worth
-- guarding on its own: an ordinary member cannot read the intelligence substrate
-- directly. The definer-level pool needs one of two prerequisites that are outside
-- this task: a valid `build_workout(p_context)` payload (shape not established
-- here, and not invented), or a SECURITY DEFINER test wrapper -- a new database
-- object. Documented in the report rather than faked.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'ENG-SUBSTRATE-01', count(*) = 0,
  'ordinary member reads intelligence substrate directly (staff-only per 117): '||count(*)
  from public.exercise_intelligence;
reset role; release savepoint p;

-- ── ENG-POOL-01 · build_workout's candidate selection, measured properly ─────
-- An earlier attempt counted `exercises JOIN exercise_intelligence` AS THE CALLER
-- and got 0 — wrong, because build_workout is SECURITY DEFINER (prosecdef = t) and
-- `exercise_intelligence`'s only read policy is `intel read staff only ::
-- is_content_editor()`. A caller-level count measures RLS, not the engine's pool.
-- This probe calls the function itself, so the join is evaluated with the owner
-- rights the engine really uses.
--
-- The p_context payload is NOT invented. It is the one an existing test already
-- uses: supabase/tests/security/d04-rpc-execution.mjs:153 passes
-- `{ size: 4, focus: 'push' }` and asserts build_workout "still runs for a member".
-- (fj07-rule-accumulator-contract.sql:54 uses `{recovery, size}` for its own case.)
-- build_workout is declared STABLE and writes nothing, so a plain savepoint is
-- sufficient; `generate_workout` is the wrapper that records a trace.
--
-- THIS PROBE IS NOT ABOUT MIGRATION 182. It is evidence for the SEPARATE
-- `exercises`-view fix. The assertion is only that the pool is non-vacuous; the
-- count is reported in the detail so two runs can be compared without ever
-- coupling the two changes:
--     run.sh                      -> no predicate on `exercises`
--     run.sh --mutate QAX-SEC-06  -> the proposed `exercises` predicate
-- The fixture substrate is 2 intelligence rows: one global+approved, one another
-- coach's private draft.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
do $$ declare j jsonb; n int; begin
  j := public.build_workout(jsonb_build_object('size', 4, 'focus', 'push'));
  n := coalesce(jsonb_array_length(j->'selected'), 0);
  execute 'reset role';
  insert into qax_out values ('ENG-POOL-01', n > 0,
    'build_workout selected '||n||' candidate(s) for an ordinary member');
exception when others then
  execute 'reset role';
  insert into qax_out values ('ENG-POOL-01', false, 'build_workout raised '||sqlstate);
end $$;
reset role; release savepoint p;

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
insert into qax_out select 'POS-06A', count(*)=1, 'owner still sees own private draft via exercise_certifications: '||count(*)
  from public.exercise_certifications where id='99999999-0000-0000-0000-000000000009';
insert into qax_out select 'POS-06D', count(*)=1, 'owner''s own RPC call still returns a row: '||count(*)
  from (select 1 where public.exercise_certification('99999999-0000-0000-0000-000000000009') is not null) z;
reset role; :KEEP
rollback to savepoint p; release savepoint p; :RESTORE
-- POS-06B / POS-06C: the legitimate certification paths must survive any fix.
savepoint p; select pg_temp.as_user('11111111-1111-1111-1111-111111111111'); set local role authenticated;
insert into qax_out select 'POS-06B', count(*)=1, 'ordinary caller still sees the approved-global row: '||count(*)
  from public.exercise_certifications where id='99999999-0000-0000-0000-00000000000a';
reset role; release savepoint p;
-- POS-06C pins certification_summary()'s LIBRARY-WIDE semantics for an entitled
-- caller, so a fix that silently narrows them to the caller's own rows fails here
-- rather than passing quietly. Admin reads every custom_exercises row (050:12).
savepoint p; select pg_temp.as_user('88888888-0000-0000-0000-000000000008'); set local role authenticated;
do $$ declare t bigint; w bigint; begin
  select total into t from public.certification_summary();
  select count(*) into w from public.custom_exercises;
  execute 'reset role';
  insert into qax_out values ('POS-06C', t=w,
    'admin summary total='||t||' vs full library='||w);
exception when others then
  insert into qax_out values ('POS-06C', false, 'admin summary failed: '||sqlstate);
end $$;
reset role; release savepoint p;

-- try_write marks ALLOWED as not-ok; for POS-03/04 ALLOWED is the correct outcome.
update qax_out set ok = not ok where id in ('POS-03','POS-04','POS-10');

select case when ok then 'PASS' else 'FAIL' end||'|'||id||'|'||detail from qax_out order by id;
