-- ============================================================
-- REL-36 · SEED TARGET GUARD — do not remove.
--
-- This file creates auth.users rows with PUBLISHED passwords
-- (test@12circle.app / Test1234!, coach@12circle.app / Coach1234!, and the
-- bcrypt hashes below, which are in git history as of W1-T1). Anywhere it runs,
-- it creates known-credential accounts. It must therefore only ever run against
-- an empty QA database.
--
-- `supabase db reset` applies this file automatically via [db.seed] in
-- config.toml, against whatever project the CLI happens to be linked to. There
-- is no CLI-level confirmation of that target, so the refusal lives here, in
-- the one place every invocation path has to pass through -- including a
-- hand-run `psql -f`, which a wrapper script cannot intercept.
--
-- The test: a genuine `db reset` truncates everything before seeding, so
-- auth.users is empty. Any populated database -- production first among them --
-- aborts the whole seed before a single credential is written.
--
-- Companion control: supabase/scripts/qa-db-reset.sh verifies the LINKED PROJECT
-- REF before it will call `supabase db reset` at all. Two independent controls,
-- because one of them is a shell script that can simply be bypassed.
-- ============================================================
DO $seed_guard$
DECLARE
  existing_users bigint;
BEGIN
  SELECT count(*) INTO existing_users FROM auth.users;

  IF existing_users > 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'raise_exception',
      MESSAGE = format(
        'REFUSING TO SEED: auth.users already contains %s row(s).',
        existing_users),
      DETAIL  = 'This seed writes accounts with published passwords and is only '
                'valid against a freshly reset QA database. A database that '
                'already has users is not one -- it may be production.',
      HINT    = 'Reset first with supabase/scripts/qa-db-reset.sh, which '
                'verifies the linked project ref before doing anything.';
  END IF;

  RAISE NOTICE 'REL-36 seed guard: auth.users is empty, proceeding.';
END
$seed_guard$;

-- ============================================================
-- 12 Circle Fitness — Test Accounts Seed
-- Run in Supabase SQL Editor AFTER running 001_full_ecosystem.sql
--
-- TEST CLIENT:  test@12circle.app  / Test1234!
-- TEST COACH:   coach@12circle.app / Coach1234!
-- ============================================================

-- STAGE B.3: this script now creates its own auth.users rows.
--
-- The two UUIDs below are pinned, and public.user_profiles.id has a FOREIGN KEY
-- to auth.users(id) ON DELETE CASCADE (confirmed in the QA schema dump). Creating
-- the auth users by hand in the dashboard produces DIFFERENT uuids, so on a
-- rebuilt database the profile inserts below failed the FK and every fixture
-- keyed on these ids was orphaned. They are inserted here at their pinned ids
-- instead, exactly as full_test_data.sql already does for its own fixtures.
--
-- raw_user_meta_data carries first_name/last_name/role so the
-- on_auth_user_created trigger (migration 109 -> handle_new_user, 044) builds a
-- correct profile row immediately; the upserts below then fill in the detail.

DO $$
DECLARE
  v_coach_id  uuid := 'f626acd9-f76c-43ca-be4c-54d028ae09db';
  v_client_id uuid := '5470a95f-bcae-4e01-b2be-7c16964fa432';
  v_rel_id    uuid;
  v_program_id uuid;
BEGIN

-- ── Auth users (must exist first: user_profiles.id -> auth.users.id) ──────────
-- Migration 109's trigger fires on each of these and creates the matching
-- public.user_profiles row.
-- The four *_token / email_change columns have NO column default. A row inserted
-- directly into auth.users therefore leaves them NULL, and GoTrue scans them into
-- non-nullable Go strings -- so every LOGIN for a seeded user fails with
--     500 {"error_code":"unexpected_failure","msg":"Database error querying schema"}
-- even though the password is correct. GoTrue's own signup path writes ''. Found
-- in Stage B.4 by attempting a real login against the rebuilt QA project.
INSERT INTO auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) VALUES
  ('00000000-0000-0000-0000-000000000000', v_coach_id,
   'authenticated', 'authenticated', 'coach@12circle.app',
   crypt('Coach1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}',
   '{"first_name":"Alex","last_name":"Coach","role":"coach"}',
   NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_client_id,
   'authenticated', 'authenticated', 'test@12circle.app',
   crypt('Test1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}',
   '{"first_name":"Jordan","last_name":"Test","role":"client"}',
   NOW(), NOW(),
   '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- ── Coach Profile ──────────────────────────────────────────────────────────────
INSERT INTO user_profiles (
  id, email, first_name, last_name, role,
  bio, specialties, certifications,
  pricing_monthly, years_experience, rating_avg, review_count,
  onboarding_complete
) VALUES (
  v_coach_id,
  'coach@12circle.app',
  'Alex', 'Coach',
  'coach',
  'NASM-certified trainer with 8 years helping clients build lean muscle and burn fat. Specializing in body recomposition and mindset coaching.',
  ARRAY['Fat Loss', 'Muscle Building', 'Strength Training', 'Nutrition Coaching'],
  ARRAY['NASM-CPT', 'Precision Nutrition Level 1', 'Functional Movement Screen'],
  149.00, 8, 4.9, 47,
  true
) ON CONFLICT (id) DO UPDATE SET
  -- STAGE B.3 (B2-7): every column in the INSERT list must be repeated here.
  -- Migration 109's trigger has already created this row as role='client' with
  -- first_name='User', so anything omitted below keeps the trigger's value --
  -- which previously left the platform with zero coaches.
  email             = EXCLUDED.email,
  first_name        = EXCLUDED.first_name,
  last_name         = EXCLUDED.last_name,
  role              = EXCLUDED.role,
  bio               = EXCLUDED.bio,
  specialties       = EXCLUDED.specialties,
  certifications    = EXCLUDED.certifications,
  pricing_monthly   = EXCLUDED.pricing_monthly,
  years_experience  = EXCLUDED.years_experience,
  rating_avg        = EXCLUDED.rating_avg,
  review_count      = EXCLUDED.review_count,
  onboarding_complete = EXCLUDED.onboarding_complete;

-- ── Client Profile ─────────────────────────────────────────────────────────────
INSERT INTO user_profiles (
  id, email, first_name, last_name, role,
  age, height_cm, current_weight_kg, goal_weight_kg,
  fitness_goal, fitness_level, activity_level,
  training_days_per_week, dietary_restrictions,
  onboarding_complete
) VALUES (
  v_client_id,
  'test@12circle.app',
  'Jordan', 'Test',
  'client',
  28, 175, 82.5, 75.0,
  'fat_loss', 'intermediate', 'moderately_active',
  4, ARRAY[]::text[],
  true
) ON CONFLICT (id) DO UPDATE SET
  -- STAGE B.3 (B2-7): full column list, same reason as the coach upsert above.
  email             = EXCLUDED.email,
  first_name        = EXCLUDED.first_name,
  last_name         = EXCLUDED.last_name,
  role              = EXCLUDED.role,
  age               = EXCLUDED.age,
  height_cm         = EXCLUDED.height_cm,
  current_weight_kg = EXCLUDED.current_weight_kg,
  goal_weight_kg    = EXCLUDED.goal_weight_kg,
  fitness_goal      = EXCLUDED.fitness_goal,
  fitness_level     = EXCLUDED.fitness_level,
  activity_level    = EXCLUDED.activity_level,
  training_days_per_week = EXCLUDED.training_days_per_week,
  dietary_restrictions   = EXCLUDED.dietary_restrictions,
  onboarding_complete    = EXCLUDED.onboarding_complete;

-- ── Active Coach-Client Relationship ──────────────────────────────────────────
INSERT INTO coach_client_relationships (
  coach_id, client_id, status, activated_at, request_message
) VALUES (
  v_coach_id, v_client_id, 'active', NOW(),
  'Test account — pre-approved relationship'
) ON CONFLICT (coach_id, client_id) DO UPDATE SET status = 'active'
RETURNING id INTO v_rel_id;

-- ── Workout Program ────────────────────────────────────────────────────────────
INSERT INTO workout_programs (id, coach_id, name, description, duration_weeks, difficulty)
VALUES (
  gen_random_uuid(), v_coach_id,
  'Summer Shred 8-Week', '4-day split focused on fat loss while preserving muscle', 8, 'intermediate'
) RETURNING id INTO v_program_id;

-- Week 1 workouts.
--
-- `day_of_week` is the full English day name, per the canonical contract
-- (docs/WORKOUT_DOMAIN_CONTRACT.md §3.4). This seed used to write '1'..'5';
-- the client matches today's NAME against the column, so the seeded coach
-- program could never be "today's workout" for anyone. Verified live on QA
-- before the fix: the stored values were "1","2","4","5".
--
-- Loads are under `weight_kg` — the canonical key. They used to be dropped on
-- the floor because the codec read `weight`, so a 60 kg bench press reached the
-- client as 0 kg.
INSERT INTO program_workouts (program_id, week_number, day_of_week, title, exercises) VALUES
  (v_program_id, 1, 'Monday', 'Monday — Upper Push', '[
    {"name":"Bench Press","sets":4,"reps":8,"weight_kg":60,"rest_seconds":90},
    {"name":"Overhead Press","sets":3,"reps":10,"weight_kg":40,"rest_seconds":75},
    {"name":"Incline Dumbbell Press","sets":3,"reps":12,"weight_kg":20,"rest_seconds":60},
    {"name":"Tricep Pushdown","sets":3,"reps":15,"weight_kg":25,"rest_seconds":45},
    {"name":"Lateral Raises","sets":3,"reps":15,"weight_kg":10,"rest_seconds":45}
  ]'::jsonb),
  (v_program_id, 1, 'Tuesday', 'Tuesday — Lower Pull', '[
    {"name":"Romanian Deadlift","sets":4,"reps":8,"weight_kg":80,"rest_seconds":120},
    {"name":"Leg Curl","sets":3,"reps":12,"weight_kg":40,"rest_seconds":60},
    {"name":"Walking Lunges","sets":3,"reps":20,"weight_kg":20,"rest_seconds":60},
    {"name":"Calf Raises","sets":4,"reps":20,"weight_kg":60,"rest_seconds":45},
    {"name":"Plank","sets":3,"reps":1,"weight_kg":0,"rest_seconds":60}
  ]'::jsonb),
  (v_program_id, 1, 'Thursday', 'Thursday — Upper Pull', '[
    {"name":"Pull-Ups","sets":4,"reps":8,"weight_kg":0,"rest_seconds":90},
    {"name":"Barbell Row","sets":4,"reps":8,"weight_kg":60,"rest_seconds":90},
    {"name":"Cable Row","sets":3,"reps":12,"weight_kg":50,"rest_seconds":60},
    {"name":"Face Pulls","sets":3,"reps":15,"weight_kg":20,"rest_seconds":45},
    {"name":"Dumbbell Curl","sets":3,"reps":12,"weight_kg":15,"rest_seconds":45}
  ]'::jsonb),
  (v_program_id, 1, 'Friday', 'Friday — Lower Quad', '[
    {"name":"Back Squat","sets":4,"reps":8,"weight_kg":80,"rest_seconds":120},
    {"name":"Leg Press","sets":3,"reps":12,"weight_kg":120,"rest_seconds":90},
    {"name":"Leg Extension","sets":3,"reps":15,"weight_kg":40,"rest_seconds":60},
    {"name":"Hip Thrust","sets":3,"reps":12,"weight_kg":80,"rest_seconds":75},
    {"name":"Ab Wheel","sets":3,"reps":12,"weight_kg":0,"rest_seconds":45}
  ]'::jsonb);

-- Assign program to client
INSERT INTO workout_program_assignments (
  program_id, client_id, coach_id, status, current_week, start_date
) VALUES (
  v_program_id, v_client_id, v_coach_id, 'active', 1, CURRENT_DATE
) ON CONFLICT DO NOTHING;

-- ── Nutrition Plan ─────────────────────────────────────────────────────────────
INSERT INTO client_nutrition_plans (
  client_id, coach_id, calories_target, protein_g, carbs_g, fat_g,
  notes, is_active
) VALUES (
  v_client_id, v_coach_id,
  2000, 175, 190, 67,
  'High protein to preserve muscle during cut. Carbs around workouts. Track everything.',
  true
) ON CONFLICT DO NOTHING;

-- ── Assigned Habits ────────────────────────────────────────────────────────────
INSERT INTO client_habits (client_id, coach_id, name, emoji, category, target_value, unit) VALUES
  (v_client_id, v_coach_id, '10k Steps', '👟', 'fitness', 10000, 'steps'),
  (v_client_id, v_coach_id, 'Drink 3L Water', '💧', 'health', 3, 'litres'),
  (v_client_id, v_coach_id, 'Sleep 8 Hours', '😴', 'sleep', 8, 'hours'),
  (v_client_id, v_coach_id, '10min Meditation', '🧘', 'mindfulness', 10, 'minutes'),
  (v_client_id, v_coach_id, 'Mobility Routine', '🤸', 'fitness', 1, 'session')
ON CONFLICT DO NOTHING;

-- ── Sample Check-Ins ───────────────────────────────────────────────────────────
INSERT INTO weekly_checkins (
  user_id, coach_id, week_number, week_start_date,
  weight_kg, energy_level, stress_level, sleep_hours,
  hunger_level, compliance_percent, notes, created_at
) VALUES
  (v_client_id, v_coach_id, 1, CURRENT_DATE - 14, 82.5, 4, 2, 7.5, 3, 90, 'Feeling great, energy is up. Workouts feel strong.', NOW() - INTERVAL '14 days'),
  (v_client_id, v_coach_id, 2, CURRENT_DATE - 7,  81.8, 3, 3, 7.0, 4, 85, 'Had a stressful week at work but stayed consistent.', NOW() - INTERVAL '7 days'),
  (v_client_id, v_coach_id, 3, CURRENT_DATE,      81.2, 4, 2, 8.0, 3, 92, 'Down 1.3kg this week! Sleep improved a lot.', NOW());

-- ── Sample Daily Scores ────────────────────────────────────────────────────────
INSERT INTO daily_scores (
  user_id, score_date, workout_points, nutrition_points, habits_points, checkin_points, community_points, total_score
) VALUES
  (v_client_id, CURRENT_DATE - 6, 30, 25, 16, 0, 0, 71),
  (v_client_id, CURRENT_DATE - 5, 30, 28, 20, 0, 10, 88),
  (v_client_id, CURRENT_DATE - 4, 0,  24, 12, 0, 0,  36),
  (v_client_id, CURRENT_DATE - 3, 30, 30, 20, 0, 0,  80),
  (v_client_id, CURRENT_DATE - 2, 30, 27, 18, 10, 0, 85),
  (v_client_id, CURRENT_DATE - 1, 30, 30, 20, 0, 10, 90),
  (v_client_id, CURRENT_DATE,     30, 25, 16, 0, 0,  71)
ON CONFLICT (user_id, score_date) DO NOTHING;

-- ── Active Challenge ───────────────────────────────────────────────────────────
WITH ch AS (
  INSERT INTO challenges (coach_id, title, description, type, target_value, unit, status, start_date, end_date, emoji)
  VALUES (v_coach_id, '30-Day Body Recomp', 'Track your daily compliance and build the streak', 'workout', 30, 'workouts', 'active', CURRENT_DATE, CURRENT_DATE + 30, '🔥')
  RETURNING id
)
INSERT INTO challenge_participants (challenge_id, user_id, current_progress)
SELECT id, v_client_id, 6 FROM ch;

RAISE NOTICE 'Test accounts seeded successfully!';
RAISE NOTICE 'Coach UUID: %', v_coach_id;
RAISE NOTICE 'Client UUID: %', v_client_id;
RAISE NOTICE '';
RAISE NOTICE 'Auth users were created by this script at the pinned UUIDs above.';

END $$;
