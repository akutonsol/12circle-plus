-- QA-EXHAUSTION local-replay fixtures. Loopback scratch DB only; runs inside the
-- caller's transaction, which is always rolled back. Never applied anywhere.
-- A = ordinary client (attacker) · B = victim client · C = B's coach (later cancelled
-- in P2) · D = B's active coach. User ids are fixed so output is diffable.
insert into auth.users(id,email) values
  ('11111111-1111-1111-1111-111111111111','qax-a@local'),
  ('22222222-2222-2222-2222-222222222222','qax-b@local'),
  ('33333333-3333-3333-3333-333333333333','qax-c@local'),
  ('44444444-0000-0000-0000-000000000004','qax-d@local')
on conflict (id) do nothing;
update public.user_profiles set role='coach'
 where id in ('33333333-3333-3333-3333-333333333333','44444444-0000-0000-0000-000000000004');
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values
  ('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222','cancelled','client'),
  ('44444444-0000-0000-0000-000000000004','22222222-2222-2222-2222-222222222222','active','client');
insert into public.client_nutrition_plans(client_id,coach_id,calories_target,protein_g,carbs_g,fat_g,is_active,notes)
  values ('22222222-2222-2222-2222-222222222222','44444444-0000-0000-0000-000000000004',2200,150,220,70,true,'qax real plan');
insert into public.conversations(id,participant_1,participant_2) values
  ('55555555-5555-5555-5555-000000000001','22222222-2222-2222-2222-222222222222','44444444-0000-0000-0000-000000000004');
insert into storage.objects(bucket_id,name,owner) values
  ('progress-photos','22222222-2222-2222-2222-222222222222/front.jpg','22222222-2222-2222-2222-222222222222'),
  ('exercise-media','library/qax-squat.mp4','44444444-0000-0000-0000-000000000004');
insert into public.custom_exercises(name,coach_id,visibility,submission_status)
  values ('qax private draft','44444444-0000-0000-0000-000000000004','private','draft');

-- QAX-SEC-08/09 (added 2026-09-25, run 2): PHI on the victim profile, a vendor event B registered for.
update public.user_profiles set medical_conditions='qax-condition', parq_answers='{"0":true}'::jsonb
 where id='22222222-2222-2222-2222-222222222222';
insert into auth.users(id,email) values ('77777777-0000-0000-0000-000000000007','qax-vendor@local') on conflict (id) do nothing;
update public.user_profiles set role='vendor' where id='77777777-0000-0000-0000-000000000007';
insert into public.events(id,vendor_id,title,event_date)
  values ('66666666-6666-6666-6666-000000000001','77777777-0000-0000-0000-000000000007','qax event',current_date+7);
insert into public.event_registrations(event_id,user_id)
  values ('66666666-6666-6666-6666-000000000001','22222222-2222-2222-2222-222222222222');

-- QAX-SEC-06 certification extension (added 2026-10-19). An ADMIN (E), a second
-- private draft owned by D with a FIXED id so the RPC probe can name it, and an
-- approved-global row so the legitimate path has a positive control.
-- Deliberately NOT reusing the name 'qax private draft': QAX-SEC-06 and POS-06
-- count by that name, and a second row would flip POS-06's expected 1.
insert into auth.users(id,email) values ('88888888-0000-0000-0000-000000000008','qax-admin@local')
  on conflict (id) do nothing;
update public.user_profiles set role='admin' where id='88888888-0000-0000-0000-000000000008';
insert into public.custom_exercises(id,name,coach_id,visibility,submission_status,content_status)
  values ('99999999-0000-0000-0000-000000000009','qax cert private draft',
          '44444444-0000-0000-0000-000000000004','private','draft','draft');
insert into public.custom_exercises(id,name,coach_id,visibility,submission_status,content_status)
  values ('99999999-0000-0000-0000-00000000000a','qax cert global approved',
          '44444444-0000-0000-0000-000000000004','global','approved','published');

-- Gap-closure fixtures (added 2026-10-19).
-- (A) A CONTENT_MANAGER (F) — distinct from the admin (E) and the ordinary
--     client (A). Option A's predicate admits `is_content_editor()`, which is
--     admin OR content_manager (083:88-89), so the non-admin editor arm needs its
--     own subject. The role is set by direct UPDATE: auth.uid() is NULL here, so
--     115's enforce_profile_privilege takes its internal early return.
insert into auth.users(id,email) values ('8888888c-0000-0000-0000-00000000000c','qax-cm@local')
  on conflict (id) do nothing;
update public.user_profiles set role='content_manager' where id='8888888c-0000-0000-0000-00000000000c';

-- (B) A NON-EMPTY intelligence substrate. EB-4 records the real substrate as
--     0 profiles / 621 exercises, and `build_workout` (127:27) sources candidates
--     from `exercises e join exercise_intelligence ei` with no WHERE — an INNER
--     join, so with 0 profiles the pool is 0 regardless of any view predicate.
--     Two rows: one GLOBAL+APPROVED, one another coach's PRIVATE DRAFT. Every
--     column but the key defaults (087:13-14), so the key is all a fixture needs.
insert into public.exercise_intelligence(exercise_id)
  values ('99999999-0000-0000-0000-00000000000a'),   -- global + approved
         ('99999999-0000-0000-0000-000000000009')    -- another coach's private draft
  on conflict (exercise_id) do nothing;
