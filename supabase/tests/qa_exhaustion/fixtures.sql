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
