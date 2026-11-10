-- Engine gate, approval contract and session focus (migrations 187 + 188).
-- LOCAL REPLAY ONLY — run by engine_gate_replay.sh, which refuses any non-loopback
-- target and any QA/production credential.
--
-- One transaction, always ROLLED BACK. Every check prints PASS|id|detail or
-- FAIL|id|detail. Scenarios that change state run inside savepoints; results are
-- stashed across each rollback (same trick as engine_materialize_replay.sql).
--
-- Run it against BOTH:
--   * a replay WITH 187 + 188  — expected: every check PASSES;
--   * a replay WITHOUT them    — the NEGATIVE CONTROL: the checks listed in
--     engine_gate_replay.sh (NEGATIVE_EXPECTED) must FAIL, proving each one can
--     detect the old behaviour rather than passing vacuously.
--
-- Fixture library (all global + submission-approved, so a coach may read them,
-- except X25). Eligible = certified for both modules + intelligence approved by a
-- content editor reviewing all eight attribute groups; goal_hypertrophy 6.
--   01 Horizontal Push  02 Vertical Push  03 Elbow Extension      (Push)
--   04 Horizontal Pull  05 Vertical Pull  06 Elbow Flexion        (Pull)
--   07 Squat            08 Hinge          09 Unilateral           (Legs)
--   10 Rotation (eligible, in no focused session)
-- Ineligible decoys score HIGHER (goal_hypertrophy 10), so an ungated engine picks
-- them first:
--   20 content draft (NOT certified), intelligence approved
--   21 certified for workout_builder ONLY (no alternatives), intelligence approved
--   22 certified, intelligence draft / derived      23 certified, ai_generated
--   24 certified, under_review                      25 ANOTHER coach's PRIVATE
--      exercise, certified content, intelligence approved
-- Approval-contract fixtures (content draft, so they never matter to the gate):
--   30 ai_generated, every attribute confidence 99, no reviews
--   31 attribute map EMPTY

\set ON_ERROR_STOP off
begin;
create temp table res(id text, ok boolean, detail text);
grant all on res to authenticated;
\set KEEP 'select coalesce(string_agg(id||chr(31)||coalesce(ok,false)||chr(31)||coalesce(detail,''''), chr(30)),'''') as keep from res \\gset'
\set RESTORE 'delete from res; insert into res select (string_to_array(r,chr(31)))[1], (string_to_array(r,chr(31)))[2]::boolean, (string_to_array(r,chr(31)))[3] from unnest(string_to_array(:''keep'',chr(30))) r where r <> '''';'

create function pg_temp.as_user(u uuid) returns void language sql as
$$ select set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
-- Run a statement that yields one jsonb value; return {ok: value} or {err, state}.
create function pg_temp.try(stmt text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute stmt into r;
  return jsonb_build_object('ok', coalesce(r, 'null'::jsonb));
exception when others then
  return jsonb_build_object('err', sqlerrm, 'state', sqlstate);
end $$;
grant execute on function pg_temp.try(text) to authenticated, service_role;
-- Approve one attribute the way the review screen does: send back the fingerprint
-- attribute_review_state showed (187). On a pre-187 replay there is no fingerprint
-- and 091's review_attribute is called as before.
create function pg_temp.approve(e uuid, a text) returns void language plpgsql as $$
begin
  if to_regprocedure('public._intel_required_attributes()') is null then
    perform public.review_attribute(e, a, 'approved');
  else
    execute 'select public.review_attribute($1, $2, ''approved'', null, null, $3)'
      using e, a, public.attribute_review_state(e)->a->>'fingerprint';
  end if;
end $$;
grant execute on function pg_temp.approve(uuid, text) to authenticated;
create function pg_temp.ids(sel jsonb) returns text language sql as
$$ select coalesce(string_agg(right(x->>'id', 2), ',' order by right(x->>'id', 2)), '')
     from jsonb_array_elements(coalesce(sel, '[]'::jsonb)) x $$;
create function pg_temp.key(p text) returns text language sql as
$$ select lower(regexp_replace(btrim(coalesce(p,'')), '[[:space:]-]+', '_', 'g')) $$;
create function pg_temp.st(e text) returns text language sql as
$$ select status from public.exercise_intelligence where exercise_id = ('ab000000-0000-0000-0000-0000000000'||e)::uuid $$;

-- ── users ──────────────────────────────────────────────────────────────────
insert into auth.users(id,email) values
 ('ad000000-0000-0000-0000-000000000001','gate-editor@local'),
 ('ad000000-0000-0000-0000-000000000002','gate-coach@local'),
 ('ad000000-0000-0000-0000-000000000003','gate-other-coach@local') on conflict do nothing;
update public.user_profiles set role='content_manager' where id='ad000000-0000-0000-0000-000000000001';
update public.user_profiles set role='coach' where id in
 ('ad000000-0000-0000-0000-000000000002','ad000000-0000-0000-0000-000000000003');

-- ── exercises ──────────────────────────────────────────────────────────────
insert into public.custom_exercises(id, name, movement_pattern, category, exercise_type, visibility,
  submission_status, content_status, coach_id, instructions, alternatives, muscle_group, equipment)
select ('ab000000-0000-0000-0000-0000000000'||n)::uuid, 'gate '||n||' '||label, pattern, cat, typ,
       case when n = '25' then 'private' else 'global' end, 'approved',
       case when n in ('20','30','31') then 'draft' else 'approved' end,
       case when n = '25' then 'ad000000-0000-0000-0000-000000000003'::uuid end,
       array['Move with control.'],
       case when n = '21' then '{}'::text[] else array['(fixture alternative)'] end,
       'Chest', 'Bodyweight'
from (values
  ('01','bench','Horizontal Push','Upper Body','Compound'), ('02','press','Vertical Push','Upper Body','Compound'),
  ('03','pushdown','Elbow Extension','Upper Body','Isolation'),
  ('04','row','Horizontal Pull','Upper Body','Compound'),   ('05','pulldown','Vertical Pull','Upper Body','Compound'),
  ('06','curl','Elbow Flexion','Upper Body','Isolation'),
  ('07','squat','Squat','Lower Body','Compound'),           ('08','rdl','Hinge','Lower Body','Compound'),
  ('09','lunge','Unilateral','Lower Body','Compound'),
  ('10','twist','Rotation','Core','Isolation'),
  ('20','UNCERTIFIED','Carry','Functional','Compound'),     ('21','WB-ONLY','Shoulder Abduction','Upper Body','Isolation'),
  ('22','DRAFT','Shrug','Upper Body','Isolation'),          ('23','AI-GENERATED','Hip Abduction','Lower Body','Isolation'),
  ('24','UNDER-REVIEW','Knee Flexion','Lower Body','Isolation'),
  ('25','OTHER-PRIVATE','Shoulder Flexion','Upper Body','Isolation'),
  ('30','B-highconf','Breathing','Recovery','Isolation'),  ('31','B-emptymap','Breathing','Recovery','Isolation')
  ) v(n, label, pattern, cat, typ);

-- ── intelligence ───────────────────────────────────────────────────────────
select set_config('gate.map', '{"programming_goals":95,"fatigue":95,"joint_stress":95,"contraindications":95,"rep_ranges":95,"biomechanics":95,"loading":95,"coaching":95}', true);
insert into public.exercise_intelligence(exercise_id, goal_hypertrophy, attribute_confidence, source, status)
select ('ab000000-0000-0000-0000-0000000000'||n)::uuid,
       case when n::int >= 20 then 10 else 6 end,
       case when n = '22' or n = '31' then '{}'::jsonb
            when n = '30' then replace(current_setting('gate.map'), '95', '99')::jsonb
            else current_setting('gate.map')::jsonb end,
       case when n = '22' then 'derived' else 'ai_generated' end,
       case when n = '22' then 'draft' when n = '24' then 'under_review' else 'ai_generated' end
from unnest(array['01','02','03','04','05','06','07','08','09','10','20','21','22','23','24','25','30','31']) n;

-- A content editor reviews every attribute of the eligible set and finalizes it.
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select pg_temp.approve(('ab000000-0000-0000-0000-0000000000'||n)::uuid, a) as x
  from unnest(array['01','02','03','04','05','06','07','08','09','10','20','21','25']) n,
       unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges',
                    'biomechanics','loading','coaching']) a) s;
select count(public.finalize_intelligence(('ab000000-0000-0000-0000-0000000000'||n)::uuid))
  from unnest(array['01','02','03','04','05','06','07','08','09','10','20','21','25']) n;
reset role;
insert into res select 'F00 fixture: the eligible set and decoys 20/21/25 are approved through review',
  count(*) = 13 and bool_and(status = 'approved'), string_agg(right(exercise_id::text,2)||'='||status, ',')
  from public.exercise_intelligence
 where exercise_id::text in (select 'ab000000-0000-0000-0000-0000000000'||n from
       unnest(array['01','02','03','04','05','06','07','08','09','10','20','21','25']) n);

-- Programmes (coach C): PPL, Full Body (2/wk), Upper/Lower (4/wk), and an unknown split.
insert into public.workout_programs(id, coach_id, name, plan, strategy, engine_generated)
select ('ae000000-0000-0000-0000-0000000000'||n)::uuid, 'ad000000-0000-0000-0000-000000000002', 'gate '||n,
       public.plan_program(jsonb_build_object('program_type','hypertrophy','duration_weeks',4,'frequency',f)), '{}'::jsonb, true
from (values ('01',3), ('02',2), ('03',4)) v(n, f);
insert into public.workout_programs(id, coach_id, name, plan, strategy, engine_generated) values
 ('ae000000-0000-0000-0000-000000000004', 'ad000000-0000-0000-0000-000000000002', 'gate unknown split',
  '{"weeks":[{"week":1,"split":["Arms"],"volume_multiplier":1.0}]}', '{}'::jsonb, true);

select set_config('gate.wb', '{"goal":"hypertrophy","experience":"intermediate","size":16,"module":"workout_builder"}', true);
select set_config('gate.pg', '{"goal":"hypertrophy","experience":"intermediate","size":16,"module":"program_generator"}', true);
select set_config('gate.eligible_wb', '01,02,03,04,05,06,07,08,09,10,21', true);
select set_config('gate.eligible_pg', '01,02,03,04,05,06,07,08,09,10', true);

-- ═══ A · the dual gate (as coach C) ════════════════════════════════════════
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.cw', pg_temp.try(format('select public.generate_workout(%L::jsonb)', current_setting('gate.wb')))::text, true);
select set_config('gate.cp', pg_temp.try(format('select public.build_workout(%L::jsonb)', current_setting('gate.pg')))::text, true);
reset role;
insert into res select 'A01 Copilot (workout_builder) selects exactly the certified + approved set',
  pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected') = current_setting('gate.eligible_wb'),
  'selected '||pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')||coalesce(' err '||(current_setting('gate.cw')::jsonb->>'err'),'');
insert into res select 'A02 an UNCERTIFIED exercise with approved intelligence is never selected',
  position('20' in pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')) = 0
  and current_setting('gate.cw')::jsonb ? 'ok', '';
insert into res select 'A03 a certified exercise with DRAFT / derived intelligence is never selected',
  position('22' in pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')) = 0
  and current_setting('gate.cw')::jsonb ? 'ok', '';
insert into res select 'A04 a certified exercise with AI-GENERATED intelligence is never selected',
  position('23' in pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')) = 0
  and current_setting('gate.cw')::jsonb ? 'ok', '';
insert into res select 'A05 a certified exercise UNDER REVIEW is never selected',
  position('24' in pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')) = 0
  and current_setting('gate.cw')::jsonb ? 'ok', '';
insert into res select 'A06 another coach''s PRIVATE exercise is never selected, nor named in the result',
  current_setting('gate.cw')::jsonb ? 'ok'
  and position('25' in pg_temp.ids(current_setting('gate.cw')::jsonb->'ok'->'selected')) = 0
  and position('OTHER-PRIVATE' in current_setting('gate.cw')) = 0, '';
insert into res select 'A07 program_generator excludes the workout_builder-only exercise (module-specific)',
  pg_temp.ids(current_setting('gate.cp')::jsonb->'ok'->'selected') = current_setting('gate.eligible_pg'),
  'selected '||pg_temp.ids(current_setting('gate.cp')::jsonb->'ok'->'selected')||coalesce(' err '||(current_setting('gate.cp')::jsonb->>'err'),'');
insert into res select 'A08 …and reports it as NOT_CERTIFIED_FOR_MODULE',
  exists (select 1 from jsonb_array_elements(current_setting('gate.cp')::jsonb->'ok'->'eligibility'->'ineligible_sample') x
           where x->>'name' like 'gate 21 %' and x->'reasons' = '["NOT_CERTIFIED_FOR_MODULE"]'), '';
insert into res select 'A09 rejection reasons are counted per reason',
  coalesce((current_setting('gate.cw')::jsonb->'ok'->'eligibility'->'rejected'->>'NOT_CERTIFIED_FOR_MODULE')::int, 0) >= 1
  and coalesce((current_setting('gate.cw')::jsonb->'ok'->'eligibility'->'rejected'->>'INTELLIGENCE_NOT_APPROVED')::int, 0) >= 3
  and coalesce((current_setting('gate.cw')::jsonb->'ok'->'eligibility'->'rejected'->>'INTELLIGENCE_MISSING')::int, 0) >= 1
  and (current_setting('gate.cw')::jsonb->'ok'->>'selection_status') = 'ok',
  coalesce(current_setting('gate.cw')::jsonb->'ok'->'eligibility'->>'rejected', '(no eligibility)');
insert into res select 'A10 …and each ineligible decoy carries its own reason',
  exists (select 1 from jsonb_array_elements(current_setting('gate.cw')::jsonb->'ok'->'eligibility'->'ineligible_sample') x
           where x->>'name' like 'gate 22 %' and x->'reasons' = '["INTELLIGENCE_NOT_APPROVED"]')
  and exists (select 1 from jsonb_array_elements(current_setting('gate.cw')::jsonb->'ok'->'eligibility'->'ineligible_sample') x
           where x->>'name' like 'gate 20 %' and x->'reasons' = '["NOT_CERTIFIED_FOR_MODULE"]'), '';

-- A11 · the module is explicit; anything else fails closed.
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.m1', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":5}'')')::text, true);
select set_config('gate.m2', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":5,"module":"marketplace"}'')')::text, true);
select set_config('gate.m3', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":5,"module":true}'')')::text, true);
select set_config('gate.m4', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":5,"module":"Program_Generator"}'')')::text, true);
select set_config('gate.m5', pg_temp.try('select public.generate_workout(''{"goal":"hypertrophy","size":5}'')')::text, true);
reset role;
insert into res select 'A11 a MISSING module is refused (ENGINE_UNKNOWN_MODULE, 22023)',
  current_setting('gate.m1')::jsonb->>'state' = '22023' and current_setting('gate.m1')::jsonb->>'err' like 'ENGINE_UNKNOWN_MODULE:%',
  left(current_setting('gate.m1'), 110);
insert into res select 'A12 an UNKNOWN module ("marketplace") is refused',
  current_setting('gate.m2')::jsonb->>'err' like 'ENGINE_UNKNOWN_MODULE:%', left(current_setting('gate.m2'), 110);
insert into res select 'A13 a NON-STRING module (true) is refused',
  current_setting('gate.m3')::jsonb->>'err' like 'ENGINE_UNKNOWN_MODULE:%', left(current_setting('gate.m3'), 110);
insert into res select 'A14 a mis-cased module ("Program_Generator") is refused, not normalised',
  current_setting('gate.m4')::jsonb->>'err' like 'ENGINE_UNKNOWN_MODULE:%', left(current_setting('gate.m4'), 110);
insert into res select 'A15 generate_workout without a module is refused too (no decision trace written)',
  current_setting('gate.m5')::jsonb->>'err' like 'ENGINE_UNKNOWN_MODULE:%', left(current_setting('gate.m5'), 110);

-- A16-A18 · explicit EMPTY selection: withdraw every approval, then ask again.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select public.review_intelligence(('ab000000-0000-0000-0000-0000000000'||n)::uuid, 'under_review') as x
  from unnest(array['01','02','03','04','05','06','07','08','09','10','20','21','25']) n) s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.e1', pg_temp.try(format('select public.generate_workout(%L::jsonb)', current_setting('gate.wb')))::text, true);
select set_config('gate.e2', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000001'', 1, ''{"goal":"hypertrophy","size":5}'')')::text, true);
reset role;
insert into res select 'A16 no eligible exercise: Copilot returns selection_status NO_ELIGIBLE_EXERCISES and nothing',
  current_setting('gate.e1')::jsonb->'ok'->>'selection_status' = 'NO_ELIGIBLE_EXERCISES'
  and jsonb_array_length(current_setting('gate.e1')::jsonb->'ok'->'selected') = 0,
  left(coalesce(current_setting('gate.e1')::jsonb->'ok'->>'selection_status', current_setting('gate.e1')), 100)
    ||' / selected '||pg_temp.ids(current_setting('gate.e1')::jsonb->'ok'->'selected');
insert into res select 'A17 …Program Builder refuses with ENGINE_NO_SELECTION naming NO_ELIGIBLE_EXERCISES',
  coalesce(current_setting('gate.e2')::jsonb->>'err','') like 'ENGINE_NO_SELECTION:%NO_ELIGIBLE_EXERCISES%',
  left(coalesce(current_setting('gate.e2')::jsonb->>'err', current_setting('gate.e2')), 160);
insert into res select 'A18 …and writes no training day',
  count(*) = 0, count(*)||' day(s)' from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000001';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- A19 · the caller cannot widen Program Builder's gate.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.w1', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000003'', 1, ''{"goal":"hypertrophy","size":8,"module":"workout_builder","focus":"Full Body"}'')')::text, true);
reset role;
insert into res select 'A19 materialize ignores a caller-supplied module: the workout_builder-only exercise never appears',
  current_setting('gate.w1')::jsonb ? 'ok'
  and not exists (select 1 from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
                   where pw.program_id='ae000000-0000-0000-0000-000000000003' and e->>'name' like 'gate 21 %'),
  left(current_setting('gate.w1'), 120);
insert into res select 'A20 …and each session''s decision trace records module program_generator and its own focus',
  count(*) = 4 and bool_and(context->>'module' = 'program_generator')
  and count(distinct context->>'focus') = 2,
  count(*)||' trace(s); focus '||coalesce(string_agg(distinct context->>'focus', ','), '-')
  from public.decision_traces
 where created_by = 'ad000000-0000-0000-0000-000000000002' and context ? 'focus';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ D · distinct session focus ═══════════════════════════════════════════
savepoint s;
-- Category fixtures (owner direction 2026-10-25), certified and approved, scored
-- HIGHER than the conventional set: a rule that ignored category would pick them.
insert into public.custom_exercises(id, name, movement_pattern, category, exercise_type, visibility,
  submission_status, content_status, instructions, alternatives, muscle_group, equipment)
select ('ab000000-0000-0000-0000-0000000000'||n)::uuid, 'gate '||n||' '||label, pattern, cat, typ,
       'global', 'approved', 'approved', array['Move with control.'], array['(fixture alternative)'],
       'Chest', 'Bodyweight'
from (values
  ('40','Push Jerk','Vertical Push','Olympic','Power'),
  ('41','Sled Push','Horizontal Push','Functional','Compound'),
  ('42','Banded Glute Bridge','Hip Extension','Warmups','Isolation'),
  ('43','Spanish Squat','Squat','Corrective Exercise','Isolation'),
  ('44','Jefferson Curl','Hinge','Mobility','Isolation'),
  ('45','Double Kettlebell Front Squat','Squat','Functional','Compound'),
  ('46','Deadlift','Hinge','Full Body','Compound'),
  ('47','Thruster','Squat','Full Body','Compound'),
  ('48','Plank','Anti Extension','Core','Isometric'),
  ('49','Face Pull','Rear Delt','upper_body','Isolation')) v(n, label, pattern, cat, typ);
insert into public.exercise_intelligence(exercise_id, goal_hypertrophy, attribute_confidence, source, status)
select ('ab000000-0000-0000-0000-0000000000'||n)::uuid, 10, current_setting('gate.map')::jsonb, 'ai_generated', 'ai_generated'
  from unnest(array['40','41','42','43','44','45','46','47','48','49']) n;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select pg_temp.approve(('ab000000-0000-0000-0000-0000000000'||n)::uuid, a) as x
  from unnest(array['40','41','42','43','44','45','46','47','48','49']) n,
       unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges',
                    'biomechanics','loading','coaching']) a) s;
select count(public.finalize_intelligence(('ab000000-0000-0000-0000-0000000000'||n)::uuid))
  from unnest(array['40','41','42','43','44','45','46','47','48','49']) n;
reset role;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.d1', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000001'', 1, ''{"goal":"hypertrophy","size":5}'')')::text, true);
reset role;
insert into res select 'D01 Push/Pull/Legs week: generation succeeds with three days',
  current_setting('gate.d1')::jsonb ? 'ok' and count(*) = 3,
  count(*)||' day(s): '||coalesce(string_agg(title, ' | ' order by sort_order), '')||coalesce(' err '||(current_setting('gate.d1')::jsonb->>'err'),'')
  from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000001' and week_number=1;
insert into res select 'D02 the Push day holds only push patterns',
  count(*) > 0 and bool_and(pg_temp.key(e->>'movement_pattern') = any (array['horizontal_push','vertical_push','elbow_extension','shoulder_flexion','shoulder_abduction'])),
  coalesce(string_agg(e->>'name', ', '), 'no exercises')
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.title like '%· Push';
insert into res select 'D03 the Pull day holds only pull patterns',
  count(*) > 0 and bool_and(pg_temp.key(e->>'movement_pattern') = any (array['horizontal_pull','vertical_pull','elbow_flexion','rear_delt','shrug'])),
  coalesce(string_agg(e->>'name', ', '), 'no exercises')
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.title like '%· Pull';
insert into res select 'D04 the Legs day holds only leg patterns',
  count(*) > 0 and bool_and(pg_temp.key(e->>'movement_pattern') = any (array['squat','hinge','hip_extension','unilateral','knee_flexion','knee_extension','hip_abduction','hip_adduction','ankle_extension','ankle_flexion'])),
  coalesce(string_agg(e->>'name', ', '), 'no exercises')
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.title like '%· Legs';
insert into res select 'D05 no exercise appears in two of the three sessions',
  count(*) > 0 and count(*) = count(distinct e->>'exercise_id'),
  count(*)||' slot(s), '||count(distinct e->>'exercise_id')||' distinct exercise(s)'
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.week_number=1;
insert into res select 'D06 the three days are pairwise different',
  count(distinct ex) = 3, count(distinct ex)||' distinct day(s) of '||count(*)
  from (select (select string_agg(e->>'exercise_id', ',' order by e->>'exercise_id') from jsonb_array_elements(exercises) e) ex
          from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000001' and week_number=1) d;
insert into res select 'D10 Olympic, sled, strongman, warm-up, corrective, mobility, thruster and core exercises fill no main slot',
  count(*) filter (where right(e->>'exercise_id', 2) in ('40','41','42','43','44','45','47','48')) = 0 and count(*) > 0,
  coalesce(string_agg(e->>'name', ', ') filter (where right(e->>'exercise_id', 2) in ('40','41','42','43','44','45','47','48')), 'none')
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.week_number=1;
insert into res select 'D11 the deadlift (Hinge, category Full Body) is on Legs and not on Pull',
  bool_or(pw.title like '%· Legs' and right(e->>'exercise_id', 2) = '46')
  and not coalesce(bool_or(pw.title like '%· Pull' and right(e->>'exercise_id', 2) = '46'), false),
  coalesce(string_agg(pw.title, ', ') filter (where right(e->>'exercise_id', 2) = '46'), 'deadlift not selected')
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.week_number=1;
insert into res select 'D12 a lower-case category label ("upper_body") is normalized: Face Pull is on Pull',
  coalesce(bool_or(pw.title like '%· Pull' and right(e->>'exercise_id', 2) = '49'), false), ''
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.week_number=1;
insert into res select 'D13 every focused day contains at least one compound lift',
  count(*) = 3 and bool_and(has_compound), string_agg(title||'='||has_compound, ', ')
  from (select pw.title, exists (select 1 from jsonb_array_elements(pw.exercises) e
                                   join public.custom_exercises x on x.id = (e->>'exercise_id')::uuid
                                  where lower(x.exercise_type) = 'compound') as has_compound
          from public.program_workouts pw
         where pw.program_id='ae000000-0000-0000-0000-000000000001' and pw.week_number=1) d;
insert into res select 'D14 a generated programme is marked engine_selected',
  (select to_jsonb(p)->>'engine_selected' from public.workout_programs p
    where p.id = 'ae000000-0000-0000-0000-000000000001') = 'true',
  coalesce((select to_jsonb(p)->>'engine_selected' from public.workout_programs p
    where p.id = 'ae000000-0000-0000-0000-000000000001'), '(no such column)');
-- One slot on a Pull day: the Face Pull (isolation) outscores both compounds.
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.d15', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":1,"module":"program_generator","focus":"Pull"}'')')::text, true);
reset role;
insert into res select 'D15 a higher-scoring isolation does not crowd out the compound: one slot holds a compound',
  current_setting('gate.d15')::jsonb->'ok'->>'selection_status' = 'ok'
  and right(current_setting('gate.d15')::jsonb->'ok'->'selected'->0->>'id', 2) in ('04','05'),
  coalesce(current_setting('gate.d15')::jsonb->'ok'->'selected'->0->>'name', left(current_setting('gate.d15'), 90));
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- D16/D17 · withdraw the Push compounds: the session must be refused, not shipped.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select public.review_intelligence(('ab000000-0000-0000-0000-0000000000'||n)::uuid, 'under_review') as x
  from unnest(array['01','02']) n) s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.d16', pg_temp.try('select public.build_workout(''{"goal":"hypertrophy","size":5,"module":"program_generator","focus":"Push"}'')')::text, true);
select set_config('gate.d17', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000001'', 1, ''{"goal":"hypertrophy","size":5}'')')::text, true);
reset role;
insert into res select 'D16 no eligible compound on a Push day: INSUFFICIENT_ELIGIBLE_EXERCISES, nothing selected',
  current_setting('gate.d16')::jsonb->'ok'->>'selection_status' = 'INSUFFICIENT_ELIGIBLE_EXERCISES'
  and jsonb_array_length(current_setting('gate.d16')::jsonb->'ok'->'selected') = 0,
  coalesce(current_setting('gate.d16')::jsonb->'ok'->>'selection_status', left(current_setting('gate.d16'), 90));
insert into res select 'D17 …Program Builder refuses with ENGINE_INSUFFICIENT_ELIGIBLE and writes no day',
  coalesce(current_setting('gate.d17')::jsonb->>'err','') like 'ENGINE_INSUFFICIENT_ELIGIBLE:%'
  and not exists (select 1 from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000001'),
  left(current_setting('gate.d17'), 120);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.d7', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000004'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
select set_config('gate.d8', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000002'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
select set_config('gate.d9', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000003'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
reset role;
insert into res select 'D07 an UNKNOWN session label ("Arms") is refused (ENGINE_UNKNOWN_FOCUS), nothing written',
  coalesce(current_setting('gate.d7')::jsonb->>'err','') like 'ENGINE_UNKNOWN_FOCUS:%'
  and not exists (select 1 from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000004'),
  left(current_setting('gate.d7'), 120);
insert into res select 'D08 Full Body sessions are unrestricted and generate',
  current_setting('gate.d8')::jsonb ? 'ok' and count(*) = 2 and bool_and(jsonb_array_length(exercises) > 0),
  count(*)||' day(s) '||left(current_setting('gate.d8'), 80)
  from public.program_workouts where program_id='ae000000-0000-0000-0000-000000000002';
insert into res select 'D09 Upper / Lower days hold only upper / lower patterns',
  current_setting('gate.d9')::jsonb ? 'ok' and count(*) > 0
  and bool_and(case when pw.title like '%· Upper'
        then pg_temp.key(e->>'movement_pattern') = any (array['horizontal_push','vertical_push','elbow_extension','shoulder_flexion','shoulder_abduction','horizontal_pull','vertical_pull','elbow_flexion','rear_delt','shrug'])
        else pg_temp.key(e->>'movement_pattern') = any (array['squat','hinge','hip_extension','unilateral','knee_flexion','knee_extension','hip_abduction','hip_adduction','ankle_extension','ankle_flexion']) end),
  count(*)||' slot(s) '||left(current_setting('gate.d9'), 60)
  from public.program_workouts pw, jsonb_array_elements(pw.exercises) e
 where pw.program_id='ae000000-0000-0000-0000-000000000003';
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ B · the approval contract ════════════════════════════════════════════
-- B01 · an EMPTY attribute map never approves, even with every review in place.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.b1r', pg_temp.try($q$select to_jsonb(count(x::text)) from (select pg_temp.approve('ab000000-0000-0000-0000-000000000031', a) x
  from unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading','coaching']) a) s$q$)::text, true);
select set_config('gate.b1', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000031''))')::text, true);
reset role;
insert into res select 'B01 an EMPTY attribute map fails (INTEL_EMPTY_ATTRIBUTES) and is not approved',
  coalesce(current_setting('gate.b1')::jsonb->>'err','') like 'INTEL_EMPTY_ATTRIBUTES:%' and pg_temp.st('31') <> 'approved',
  'finalize: '||left(current_setting('gate.b1'), 90)||' / status '||pg_temp.st('31');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- B02 · model self-confidence alone never approves.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.b2', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
reset role;
insert into res select 'B02 every attribute at model confidence 99, no human review: NOT approved',
  pg_temp.st('30') <> 'approved' and current_setting('gate.b2')::jsonb->>'ok' = 'under_review',
  'finalize: '||left(current_setting('gate.b2'), 80)||' / status '||pg_temp.st('30');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- B03 · review_intelligence cannot approve.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.b3', pg_temp.try('select to_jsonb(public.review_intelligence(''ab000000-0000-0000-0000-000000000030'', ''approved'')::text)')::text, true);
reset role;
insert into res select 'B03 review_intelligence(id, ''approved'') is refused and changes nothing',
  coalesce(current_setting('gate.b3')::jsonb->>'err','') like 'INTEL_APPROVAL_REQUIRES_REVIEW:%' and pg_temp.st('30') = 'ai_generated',
  left(current_setting('gate.b3'), 100)||' / status '||pg_temp.st('30');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- B04/B05 · a direct table write cannot approve (service role, and the owner).
savepoint s;
set local role service_role;
select set_config('gate.b4', pg_temp.try($q$with u as (update public.exercise_intelligence set status = 'approved'
  where exercise_id = 'ab000000-0000-0000-0000-000000000030' returning 1) select to_jsonb(count(*)) from u$q$)::text, true);
reset role;
select set_config('gate.b5', pg_temp.try($q$with u as (insert into public.exercise_intelligence(exercise_id, attribute_confidence, status)
  values ('ab000000-0000-0000-0000-000000000023', '{"coaching":99}', 'approved')
  on conflict (exercise_id) do update set status = 'approved', attribute_confidence = '{"coaching":99}' returning 1)
  select to_jsonb(count(*)) from u$q$)::text, true);
insert into res select 'B04 a direct UPDATE to ''approved'' (service role) is refused (INTEL_APPROVAL_REFUSED)',
  coalesce(current_setting('gate.b4')::jsonb->>'err','') like 'INTEL_APPROVAL_REFUSED:%' and pg_temp.st('30') = 'ai_generated',
  left(current_setting('gate.b4'), 100)||' / status '||pg_temp.st('30');
insert into res select 'B05 a direct upsert to ''approved'' with self-reported confidence (owner) is refused',
  coalesce(current_setting('gate.b5')::jsonb->>'err','') like 'INTEL_APPROVAL_REFUSED:%',
  left(current_setting('gate.b5'), 100);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- B06-B08 · reviews must be human, by a content editor, of a known attribute.
savepoint s;
set local role service_role;
select set_config('gate.b6', pg_temp.try($q$with u as (insert into public.intelligence_attribute_reviews(exercise_id, attribute, status, reviewed_by)
  values ('ab000000-0000-0000-0000-000000000030', 'coaching', 'approved', 'ad000000-0000-0000-0000-000000000001') returning 1)
  select to_jsonb(count(*)) from u$q$)::text, true);
reset role;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.b7', pg_temp.try('select to_jsonb(public.review_attribute(''ab000000-0000-0000-0000-000000000030'', ''coaching'', ''approved'')::text)')::text, true);
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.b8', pg_temp.try('select to_jsonb(public.review_attribute(''ab000000-0000-0000-0000-000000000030'', ''vibes'', ''approved'')::text)')::text, true);
select set_config('gate.b9', pg_temp.try('select to_jsonb(public.review_attribute(''ab000000-0000-0000-0000-000000000030'', ''joint_stress'', ''approved'', ''{"knee":1}'')::text)')::text, true);
reset role;
insert into res select 'B06 an approval written straight into the review table without a signed-in editor is refused',
  coalesce(current_setting('gate.b6')::jsonb->>'err','') like 'INTEL_REVIEW_NOT_HUMAN:%', left(current_setting('gate.b6'), 100);
insert into res select 'B07 a coach (not a content editor) cannot review an attribute',
  coalesce(current_setting('gate.b7')::jsonb->>'err','') like '%forbidden%', left(current_setting('gate.b7'), 100);
insert into res select 'B08 an unknown attribute ("vibes") cannot be reviewed',
  coalesce(current_setting('gate.b8')::jsonb->>'err','') like 'INTEL_UNKNOWN_ATTRIBUTE:%', left(current_setting('gate.b8'), 100);
insert into res select 'B09 an approval that carries an unapplied override is refused',
  coalesce(current_setting('gate.b9')::jsonb->>'err','') like 'INTEL_OVERRIDE_NOT_APPLIED:%', left(current_setting('gate.b9'), 100);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- B10-B16 · partial review, full review, then edits and rejections withdraw approval.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select pg_temp.approve('ab000000-0000-0000-0000-000000000030', a) x
  from unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading']) a) s;
select set_config('gate.b10', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
select set_config('gate.b11s', pg_temp.try('select public.attribute_review_state(''ab000000-0000-0000-0000-000000000030'')')::text, true);
select pg_temp.approve('ab000000-0000-0000-0000-000000000030', 'coaching');
select set_config('gate.b12', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
reset role;
insert into res select 'B10 seven of eight attributes reviewed: NOT approved (under_review)',
  current_setting('gate.b10')::jsonb->>'ok' = 'under_review', left(current_setting('gate.b10'), 80);
insert into res select 'B11 review state lists all eight groups, the unreviewed one pending, and never "auto"',
  (select count(*) from jsonb_object_keys(current_setting('gate.b11s')::jsonb->'ok')) = 8
  and current_setting('gate.b11s')::jsonb->'ok'->'coaching'->>'review_status' = 'pending'
  and position('"auto"' in current_setting('gate.b11s')) = 0,
  left(current_setting('gate.b11s'), 120);
insert into res select 'B12 all eight reviewed by a content editor: approved (positive control)',
  current_setting('gate.b12')::jsonb->>'ok' = 'approved' and pg_temp.st('30') = 'approved',
  left(current_setting('gate.b12'), 80)||' / status '||pg_temp.st('30');
-- an edit to a reviewed attribute (the enrichment function writes as service role)
set local role service_role;
update public.exercise_intelligence set joint_stress = '{"knee": 9}' where exercise_id = 'ab000000-0000-0000-0000-000000000030';
reset role;
insert into res select 'B13 editing a reviewed attribute withdraws the approval',
  pg_temp.st('30') = 'under_review', 'status '||pg_temp.st('30');
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.b14s', pg_temp.try('select public.attribute_review_state(''ab000000-0000-0000-0000-000000000030'')')::text, true);
select set_config('gate.b14', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
select pg_temp.approve('ab000000-0000-0000-0000-000000000030', 'joint_stress');
select set_config('gate.b15', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
select public.review_attribute('ab000000-0000-0000-0000-000000000030', 'coaching', 'rejected');
reset role;
insert into res select 'B14 …the edited attribute reads "stale" and re-finalizing does not re-approve it',
  current_setting('gate.b14s')::jsonb->'ok'->'joint_stress'->>'review_status' = 'stale'
  and current_setting('gate.b14')::jsonb->>'ok' = 'under_review',
  'joint_stress '||coalesce(current_setting('gate.b14s')::jsonb->'ok'->'joint_stress'->>'review_status','?')
    ||' / finalize '||left(current_setting('gate.b14'), 60);
insert into res select 'B15 …re-reviewing the edited attribute restores approval',
  current_setting('gate.b15')::jsonb->>'ok' = 'approved', left(current_setting('gate.b15'), 60);
insert into res select 'B16 a later rejection of a reviewed attribute withdraws approval (needs_revision)',
  pg_temp.st('30') = 'needs_revision', 'status '||pg_temp.st('30');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ R · the value approved is the value reviewed ═════════════════════════
-- R01 · an approval that does not say which value it saw is refused.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.r1', pg_temp.try('select to_jsonb(public.review_attribute(''ab000000-0000-0000-0000-000000000030'', ''joint_stress'', ''approved'')::text)')::text, true);
reset role;
insert into res select 'R01 an approval without the reviewed value''s fingerprint is refused, nothing recorded',
  coalesce(current_setting('gate.r1')::jsonb->>'err','') like 'INTEL_REVIEW_FINGERPRINT_REQUIRED:%'
  and not exists (select 1 from public.intelligence_attribute_reviews
                   where exercise_id = 'ab000000-0000-0000-0000-000000000030' and attribute = 'joint_stress'),
  left(current_setting('gate.r1'), 110);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- R02 · shown value V1, edited to V2 before the click: the approval of V1 is refused.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.r2shown', coalesce(public.attribute_review_state('ab000000-0000-0000-0000-000000000030')->'joint_stress'->>'fingerprint', ''), true);
reset role;
set local role service_role;
update public.exercise_intelligence set joint_stress = '{"knee": 8}' where exercise_id = 'ab000000-0000-0000-0000-000000000030';
reset role;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.r2', pg_temp.try(format(
  'select to_jsonb(public.review_attribute(%L, %L, %L, null, null, %L)::text)',
  'ab000000-0000-0000-0000-000000000030', 'joint_stress', 'approved', current_setting('gate.r2shown')))::text, true);
reset role;
insert into res select 'R02 the value changed between display and approval: refused (INTEL_REVIEW_VALUE_CHANGED), nothing approved',
  current_setting('gate.r2shown') <> ''
  and coalesce(current_setting('gate.r2')::jsonb->>'err','') like 'INTEL_REVIEW_VALUE_CHANGED:%'
  and not exists (select 1 from public.intelligence_attribute_reviews
                   where exercise_id = 'ab000000-0000-0000-0000-000000000030' and attribute = 'joint_stress'
                     and status = 'approved'),
  left(current_setting('gate.r2'), 110);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- R03 · every attribute approved, then one changes BEFORE finalization.
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select count(x::text) from (select pg_temp.approve('ab000000-0000-0000-0000-000000000030', a) x
  from unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading','coaching']) a) s;
reset role;
set local role service_role;
update public.exercise_intelligence set contraindications = array['recent knee surgery']
 where exercise_id = 'ab000000-0000-0000-0000-000000000030';
reset role;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000001'); set local role authenticated;
select set_config('gate.r3', pg_temp.try('select to_jsonb(public.finalize_intelligence(''ab000000-0000-0000-0000-000000000030''))')::text, true);
select set_config('gate.r3s', pg_temp.try('select public.attribute_review_state(''ab000000-0000-0000-0000-000000000030'')')::text, true);
reset role;
insert into res select 'R03 a value changed between review and finalization is NOT approved',
  current_setting('gate.r3')::jsonb->>'ok' = 'under_review' and pg_temp.st('30') <> 'approved',
  'finalize '||left(current_setting('gate.r3'), 60)||' / status '||pg_temp.st('30');
insert into res select 'R04 …and the changed attribute reads "stale" while the untouched ones stay approved',
  current_setting('gate.r3s')::jsonb->'ok'->'contraindications'->>'review_status' = 'stale'
  and current_setting('gate.r3s')::jsonb->'ok'->'joint_stress'->>'review_status' = 'approved',
  'contraindications '||coalesce(current_setting('gate.r3s')::jsonb->'ok'->'contraindications'->>'review_status','?');
insert into res select 'R05 the reviewer is shown the value itself, not only a confidence score',
  current_setting('gate.r3s')::jsonb->'ok'->'contraindications'->'value'
    = '{"contraindications": ["recent knee surgery"]}'::jsonb,
  coalesce(current_setting('gate.r3s')::jsonb->'ok'->'contraindications'->>'value', '(no value shown)');
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ C · the coach's injury read (Copilot, decision C) ════════════════════
-- Copilot reads injury status through get_client_assessment (140/141): the
-- logged, active-coach-only path. N = intake complete, no injuries;
-- I = intake complete, injured; U = intake never completed (has_injuries is NOT
-- NULL DEFAULT false, so it ALSO reads false — the trap the app must not fall
-- into); the pending coach P has no access.
select set_config('request.jwt.claims', '', true);   -- fixture writes as the owner, not as a signed-in user
insert into auth.users(id,email) values
 ('ad000000-0000-0000-0000-0000000000c1','gate-client-noinjury@local'),
 ('ad000000-0000-0000-0000-0000000000c2','gate-client-injured@local'),
 ('ad000000-0000-0000-0000-0000000000c3','gate-client-nointake@local'),
 ('ad000000-0000-0000-0000-0000000000c4','gate-pending-coach@local') on conflict do nothing;
update public.user_profiles set role='coach' where id='ad000000-0000-0000-0000-0000000000c4';
update public.user_profiles set onboarding_complete = true, has_injuries = false, injury_locations = ''
 where id='ad000000-0000-0000-0000-0000000000c1';
update public.user_profiles set onboarding_complete = true, has_injuries = true, injury_locations = 'Knee, Lower back'
 where id='ad000000-0000-0000-0000-0000000000c2';
update public.user_profiles set onboarding_complete = false where id='ad000000-0000-0000-0000-0000000000c3';
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
 ('ad000000-0000-0000-0000-000000000002','ad000000-0000-0000-0000-0000000000c1','active','client'),
 ('ad000000-0000-0000-0000-000000000002','ad000000-0000-0000-0000-0000000000c2','active','client'),
 ('ad000000-0000-0000-0000-000000000002','ad000000-0000-0000-0000-0000000000c3','active','client'),
 ('ad000000-0000-0000-0000-0000000000c4','ad000000-0000-0000-0000-0000000000c1','pending','coach');
create function pg_temp.assess(c uuid) returns text language sql as
$$ select pg_temp.try(format('select to_jsonb(a) from public.get_client_assessment(%L) a', c))::text $$;
grant execute on function pg_temp.assess(uuid) to authenticated;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.cN', pg_temp.assess('ad000000-0000-0000-0000-0000000000c1'), true);
select set_config('gate.cI', pg_temp.assess('ad000000-0000-0000-0000-0000000000c2'), true);
select set_config('gate.cU', pg_temp.assess('ad000000-0000-0000-0000-0000000000c3'), true);
reset role;
select pg_temp.as_user('ad000000-0000-0000-0000-0000000000c4'); set local role authenticated;
select set_config('gate.cP', pg_temp.assess('ad000000-0000-0000-0000-0000000000c1'), true);
select set_config('gate.cPdirect', (select count(*)::text from public.user_profiles
  where id = 'ad000000-0000-0000-0000-0000000000c1' and has_injuries is not null), true);
reset role;
insert into res select 'C01 an ACTIVE coach reads a no-injury client: intake complete, has_injuries false',
  (current_setting('gate.cN')::jsonb->'ok'->>'onboarding_complete')::boolean is true
  and (current_setting('gate.cN')::jsonb->'ok'->>'has_injuries')::boolean is false,
  left(current_setting('gate.cN'), 90);
insert into res select 'C02 …an injured client: has_injuries true with the TEXT location list',
  (current_setting('gate.cI')::jsonb->'ok'->>'has_injuries')::boolean is true
  and current_setting('gate.cI')::jsonb->'ok'->>'injury_locations' = 'Knee, Lower back',
  coalesce(current_setting('gate.cI')::jsonb->'ok'->>'injury_locations', left(current_setting('gate.cI'), 80));
insert into res select 'C03 …a client who never finished intake ALSO reads has_injuries false — only onboarding_complete tells them apart',
  (current_setting('gate.cU')::jsonb->'ok'->>'has_injuries')::boolean is false
  and (current_setting('gate.cU')::jsonb->'ok'->>'onboarding_complete')::boolean is false,
  left(current_setting('gate.cU'), 90);
insert into res select 'C04 a PENDING coach cannot read the assessment (42501)',
  current_setting('gate.cP')::jsonb->>'state' = '42501', left(current_setting('gate.cP'), 80);
insert into res select 'C05 …nor the injury column directly from user_profiles',
  current_setting('gate.cPdirect') = '0', current_setting('gate.cPdirect')||' row(s)';
insert into res select 'C06 every assessment read by the active coach is logged',
  count(*) = 3, count(*)||' log row(s)'
  from public.assessment_access_log where coach_id = 'ad000000-0000-0000-0000-000000000002';

-- ═══ E · generation onto an assigned programme (189) ══════════════════════
-- N (c1) becomes the cleared client: completed intake, no injury, a complete PAR-Q
-- of eight "no" answers (risk_level is derived low by 115/126's trigger).
select set_config('request.jwt.claims', '', true);
update public.user_profiles set parq_answers =
  '{"1":false,"2":false,"3":false,"4":false,"5":false,"6":false,"7":false,"8":false}'
 where id = 'ad000000-0000-0000-0000-0000000000c1';
insert into res select 'E00 fixture: the cleared client''s PAR-Q derives risk_level low',
  risk_level = 'low', coalesce(risk_level, 'null') from public.user_profiles where id = 'ad000000-0000-0000-0000-0000000000c1';
insert into public.workout_programs(id, coach_id, name, plan, strategy, engine_generated)
select ('ae000000-0000-0000-0000-0000000000'||n)::uuid, 'ad000000-0000-0000-0000-000000000002', 'gate assigned '||n,
       public.plan_program('{"program_type":"hypertrophy","duration_weeks":4,"frequency":3}'::jsonb), '{}'::jsonb, true
  from unnest(array['05','06']) n;
-- Both assignments are made BEFORE generation, so the programmes are not yet marked.
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week) values
 ('ae000000-0000-0000-0000-000000000005','ad000000-0000-0000-0000-0000000000c2','ad000000-0000-0000-0000-000000000002','active',1),
 ('ae000000-0000-0000-0000-000000000006','ad000000-0000-0000-0000-0000000000c1','ad000000-0000-0000-0000-000000000002','active',1);
savepoint s;
select pg_temp.as_user('ad000000-0000-0000-0000-000000000002'); set local role authenticated;
select set_config('gate.e1', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000005'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
select set_config('gate.e2', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000006'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
reset role;
insert into res select 'E01 generating onto a programme assigned to an INJURED client is refused, nothing written or marked',
  coalesce(current_setting('gate.e1')::jsonb->>'err','') like 'ENGINE_CLIENT_NOT_CLEARED:%'
  and not exists (select 1 from public.program_workouts where program_id = 'ae000000-0000-0000-0000-000000000005')
  and (select to_jsonb(p)->>'engine_selected' from public.workout_programs p where p.id = 'ae000000-0000-0000-0000-000000000005') = 'false',
  left(current_setting('gate.e1'), 110);
insert into res select 'E02 generating onto a programme assigned to a CLEARED client succeeds and marks it',
  current_setting('gate.e2')::jsonb ? 'ok'
  and (select count(*) from public.program_workouts where program_id = 'ae000000-0000-0000-0000-000000000006') = 3
  and (select to_jsonb(p)->>'engine_selected' from public.workout_programs p where p.id = 'ae000000-0000-0000-0000-000000000006') = 'true',
  left(current_setting('gate.e2'), 110);
:KEEP
rollback to savepoint s; release savepoint s; :RESTORE

-- ═══ P · authorization and posture ════════════════════════════════════════
select pg_temp.as_user('ad000000-0000-0000-0000-000000000003'); set local role authenticated;
select set_config('gate.p1', pg_temp.try('select public.materialize_program_week(''ae000000-0000-0000-0000-000000000001'', 1, ''{"goal":"hypertrophy"}'')')::text, true);
reset role;
insert into res select 'P01 another coach cannot materialize this programme (42501)',
  current_setting('gate.p1')::jsonb->>'state' = '42501', left(current_setting('gate.p1'), 90);
insert into res select 'P02 build_workout: authenticated may execute, anon may not, search_path pinned',
  has_function_privilege('authenticated', 'public.build_workout(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.build_workout(jsonb)', 'execute')
  and (select coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'
         from pg_proc where oid = 'public.build_workout(jsonb)'::regprocedure), '';
insert into res select 'P03 the engine and every new helper are closed to authenticated and anon',
  coalesce(bool_and(f is not null and not has_function_privilege('authenticated', f, 'execute')
                    and not has_function_privilege('anon', f, 'execute')), false),
  coalesce(string_agg(n, ',') filter (where f is null), '')
  from (select n, to_regprocedure(n) f from unnest(array[
    'public.materialize_program_week_engine(uuid,integer,jsonb)', 'public._engine_focus_patterns(text)',
    'public._engine_pattern_key(text)', 'public._intel_required_attributes()',
    'public._intel_attribute_fingerprint(public.exercise_intelligence,text)',
    'public._intel_approval_gaps(public.exercise_intelligence)', 'public._intel_approval_holds(jsonb)',
    'public._intel_enforce_approval()', 'public._intel_review_stamp()', 'public._intel_review_invalidate()',
    'public.attribute_review_state_engine(uuid,integer)', 'public.intelligence_review_queue_engine(integer)',
    'public._engine_in_focus(text,text,text)']) n) s;
insert into res select 'P04 review RPCs: authenticated may execute, anon may not, every one pinned',
  bool_and(has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
           and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'), string_agg(p.proname, ',')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('finalize_intelligence', 'review_attribute', 'review_intelligence');
insert into res select 'P05 every new or redefined SECURITY DEFINER function pins search_path',
  coalesce(bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=public%'), false),
  coalesce(string_agg(proname, ',') filter (where coalesce(array_to_string(proconfig, ','), '') not like '%search_path=public%'), '')
  from pg_proc where pronamespace = 'public'::regnamespace and prosecdef
   and proname in ('build_workout','materialize_program_week_engine','_intel_approval_gaps','_intel_enforce_approval',
                   '_intel_review_stamp','_intel_review_invalidate','attribute_review_state_engine',
                   'intelligence_review_queue_engine','finalize_intelligence','review_attribute','review_intelligence');

select case when coalesce(ok, false) then 'PASS' else 'FAIL' end||'|'||id||'|'||coalesce(detail,'') from res order by id;
rollback;
