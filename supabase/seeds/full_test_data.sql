-- ============================================================
-- REL-36 · SEED TARGET GUARD — do not remove.
--
-- Second half of the guard in test_accounts.sql. That file refuses to run
-- against a database that already has users; by the time THIS file runs, that
-- one has just created some, so "auth.users is empty" is no longer the right
-- question. The right question is "are the only accounts here the ones the
-- fixture just made?".
--
-- This file writes marketplace coaches, community members and 30 days of
-- activity, and it inserts auth.users rows of its own. Run against a populated
-- database it would attach fabricated coaching relationships and social content
-- to real accounts.
--
-- Both pinned fixture ids must be present (proving test_accounts.sql ran in
-- this same reset, guard and all), and nothing else may be.
-- ============================================================
DO $seed_guard$
DECLARE
  fixture_client CONSTANT uuid := '5470a95f-bcae-4e01-b2be-7c16964fa432';
  fixture_coach  CONSTANT uuid := 'f626acd9-f76c-43ca-be4c-54d028ae09db';
  total_users    bigint;
  strangers      bigint;
BEGIN
  SELECT count(*) INTO total_users FROM auth.users;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = fixture_client)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = fixture_coach) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'raise_exception',
      MESSAGE = 'REFUSING TO SEED: the pinned test_accounts.sql fixtures are absent.',
      DETAIL  = 'full_test_data.sql builds on the client and coach that '
                'test_accounts.sql creates. Their absence means this is not a '
                'freshly seeded QA database.',
      HINT    = 'Run supabase/scripts/qa-db-reset.sh, which applies both seeds '
                'in order against a verified QA project.';
  END IF;

  SELECT count(*) INTO strangers
  FROM auth.users
  WHERE id NOT IN (fixture_client, fixture_coach);

  IF strangers > 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'raise_exception',
      MESSAGE = format(
        'REFUSING TO SEED: %s account(s) here were not created by this fixture.',
        strangers),
      DETAIL  = 'This seed fabricates coaching relationships, marketplace '
                'listings and community posts. Attaching them to real accounts '
                'is not something that can be undone by re-running a seed.',
      HINT    = 'Only ever seed a freshly reset QA database.';
  END IF;

  RAISE NOTICE 'REL-36 seed guard: % fixture account(s), no strangers, proceeding.',
    total_users;
END
$seed_guard$;

-- ============================================================
-- 12 Circle Fitness — Comprehensive Test Data Seed
-- Run in Supabase SQL Editor AFTER test_accounts.sql
--
-- Populates marketplace coaches, community members, and 30 days
-- of realistic activity data so the app feels fully live.
--
-- Test accounts (must exist before running this):
--   Coach:  coach@12circle.app / Coach1234!
--   Client: test@12circle.app  / Test1234!
-- ============================================================

DO $$
DECLARE
  -- ── Main test accounts (must already exist from test_accounts.sql) ──────────
  v_coach_id  uuid := 'f626acd9-f76c-43ca-be4c-54d028ae09db';
  v_client_id uuid := '5470a95f-bcae-4e01-b2be-7c16964fa432';

  -- ── Stable UUIDs for marketplace coaches ────────────────────────────────────
  v_coach_sarah   uuid := 'a1000000-0000-0000-0000-000000000001';
  v_coach_marcus  uuid := 'a2000000-0000-0000-0000-000000000002';
  v_coach_priya   uuid := 'a3000000-0000-0000-0000-000000000003';
  v_coach_derek   uuid := 'a4000000-0000-0000-0000-000000000004';
  v_coach_natasha uuid := 'a5000000-0000-0000-0000-000000000005';

  -- ── Stable UUIDs for community clients ──────────────────────────────────────
  v_client_maria  uuid := 'b1000000-0000-0000-0000-000000000001';
  v_client_james  uuid := 'b2000000-0000-0000-0000-000000000002';
  v_client_aisha  uuid := 'b3000000-0000-0000-0000-000000000003';

  -- Working vars
  v_conv_id    uuid;
  v_pod_id     uuid;

BEGIN

-- ═══════════════════════════════════════════════════════════════
-- SECTION 1: MARKETPLACE COACHES (auth + profiles)
-- ═══════════════════════════════════════════════════════════════

-- Auth user rows for marketplace coaches (no real login needed,
-- but required for the user_profiles FK to auth.users)
--
-- confirmation_token / recovery_token / email_change_token_new / email_change have
-- NO column default, so a direct INSERT leaves them NULL. GoTrue scans them into
-- non-nullable Go strings, and every LOGIN for such a user then fails with
--     500 {"error_code":"unexpected_failure","msg":"Database error querying schema"}
-- even with the right password. GoTrue's own signup path writes ''. Found in
-- Stage B.4 by attempting a real login against the rebuilt QA project.
INSERT INTO auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) VALUES
  ('00000000-0000-0000-0000-000000000000', v_coach_sarah,
   'authenticated', 'authenticated', 'sarah@marketplace.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"coach"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_coach_marcus,
   'authenticated', 'authenticated', 'marcus@marketplace.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"coach"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_coach_priya,
   'authenticated', 'authenticated', 'priya@marketplace.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"coach"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_coach_derek,
   'authenticated', 'authenticated', 'derek@marketplace.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"coach"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_coach_natasha,
   'authenticated', 'authenticated', 'natasha@marketplace.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"coach"}', NOW(), NOW(),
   '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Auth user rows for community clients (same NULL-token caveat as above)
INSERT INTO auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) VALUES
  ('00000000-0000-0000-0000-000000000000', v_client_maria,
   'authenticated', 'authenticated', 'maria@community.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"client"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_client_james,
   'authenticated', 'authenticated', 'james@community.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"client"}', NOW(), NOW(),
   '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', v_client_aisha,
   'authenticated', 'authenticated', 'aisha@community.test',
   crypt('Fake1234!', gen_salt('bf')), NOW(),
   '{"provider":"email","providers":["email"]}', '{"role":"client"}', NOW(), NOW(),
   '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- Marketplace coach profiles
INSERT INTO user_profiles (
  id, email, first_name, last_name, role,
  bio, tagline, specialties, certifications,
  pricing_monthly, years_experience, rating_avg, review_count,
  onboarding_complete
) VALUES
  (v_coach_sarah,
   'sarah@marketplace.test', 'Sarah', 'Johnson', 'coach',
   'Elite powerlifting coach and body recomposition specialist with a decade of experience. I help everyday athletes build real strength and confidence in the gym.',
   'Lift heavy. Live strong.',
   ARRAY['Powerlifting','Strength Training','Body Recomposition','Women''s Fitness'],
   ARRAY['NSCA-CSCS','IPF Certified Coach','Precision Nutrition Level 2'],
   150.00, 10, 4.9, 42, true),

  (v_coach_marcus,
   'marcus@marketplace.test', 'Marcus', 'Lee', 'coach',
   'Former collegiate runner turned endurance coach. I help clients go from the couch to their first 5K — and from 5K to their first marathon. Running changed my life, and I want it to change yours.',
   'Every step counts.',
   ARRAY['Running','Cardio','Endurance','Weight Loss'],
   ARRAY['RRCA Run Coach','ACSM Certified Personal Trainer'],
   120.00, 7, 4.7, 28, true),

  (v_coach_priya,
   'priya@marketplace.test', 'Priya', 'Sharma', 'coach',
   'Yoga instructor and holistic wellness coach. I blend mindfulness, mobility, and functional strength to help you feel as good as you look. Specialising in stress-related weight gain and burnout recovery.',
   'Mind and body in harmony.',
   ARRAY['Yoga','Mindfulness','Mobility','Stress Management','Strength'],
   ARRAY['RYT-500 Yoga Alliance','ACE Certified Health Coach','Level 1 Nutrition Coaching'],
   100.00, 5, 4.8, 19, true),

  (v_coach_derek,
   'derek@marketplace.test', 'Derek', 'Williams', 'coach',
   'Sports performance coach and former Division I athlete. I work with competitive athletes and weekend warriors who want to take their game to the next level through evidence-based programming.',
   'Train smarter. Perform better.',
   ARRAY['Sports Performance','Athletic Training','Speed & Agility','Strength & Conditioning'],
   ARRAY['NSCA-CSCS','USA Weightlifting Level 2','First Aid/CPR'],
   175.00, 12, 4.6, 35, true),

  (v_coach_natasha,
   'natasha@marketplace.test', 'Natasha', 'Brown', 'coach',
   'Weight loss and lifestyle transformation coach. I have helped over 200 women lose weight and keep it off without fad diets or punishing workouts. Sustainable habits are the only habit.',
   'Small steps. Big changes.',
   ARRAY['Weight Loss','Fat Loss','Habit Building','Nutrition Coaching','Women''s Health'],
   ARRAY['ACE-CPT','Lifestyle & Weight Management Coach','Intuitive Eating Counselor'],
   130.00, 8, 4.85, 51, true)
ON CONFLICT (id) DO UPDATE SET
  -- STAGE B.3 (B2-7): migration 109's on_auth_user_created trigger already
  -- created these rows from the auth.users inserts above, as role='client'
  -- first_name='User'. Any column omitted here keeps the trigger's value, which
  -- is how a rebuilt QA ended up with zero coaches in the marketplace.
  email             = EXCLUDED.email,
  first_name        = EXCLUDED.first_name,
  last_name         = EXCLUDED.last_name,
  role              = EXCLUDED.role,
  bio               = EXCLUDED.bio,
  tagline           = EXCLUDED.tagline,
  specialties       = EXCLUDED.specialties,
  certifications    = EXCLUDED.certifications,
  pricing_monthly   = EXCLUDED.pricing_monthly,
  years_experience  = EXCLUDED.years_experience,
  rating_avg        = EXCLUDED.rating_avg,
  review_count      = EXCLUDED.review_count,
  onboarding_complete = EXCLUDED.onboarding_complete;

-- These five are demo fixtures and must stay out of community member discovery.
-- Flagged explicitly (migration 110) instead of being inferred from the
-- @marketplace.test address at query time -- the app no longer reads email.
UPDATE user_profiles SET is_demo = true
 WHERE id IN (v_coach_sarah, v_coach_marcus, v_coach_priya, v_coach_derek, v_coach_natasha);

-- Community client profiles
INSERT INTO user_profiles (
  id, email, first_name, last_name, role,
  age, height_cm, current_weight_kg, goal_weight_kg,
  fitness_goal, fitness_level, activity_level,
  onboarding_complete
) VALUES
  (v_client_maria, 'maria@community.test', 'Maria', 'Chen', 'client',
   32, 163, 68.0, 62.0, 'fat_loss', 'beginner', 'lightly_active', true),
  (v_client_james, 'james@community.test', 'James', 'Wilson', 'client',
   26, 182, 88.0, 83.0, 'muscle_building', 'intermediate', 'very_active', true),
  (v_client_aisha, 'aisha@community.test', 'Aisha', 'Thompson', 'client',
   35, 168, 74.5, 70.0, 'general_fitness', 'intermediate', 'moderately_active', true)
ON CONFLICT (id) DO UPDATE SET
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
  onboarding_complete = EXCLUDED.onboarding_complete;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 2: COACH REVIEWS (for test coach and marketplace coaches)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO coach_reviews (coach_id, client_id, rating, review_text, created_at) VALUES
  -- Reviews for the main test coach (Alex)
  (v_coach_id, v_client_maria,  5, 'Alex completely transformed my approach to training. Down 8kg in 12 weeks and I actually enjoy going to the gym now. Highly recommend!', NOW() - INTERVAL '45 days'),
  (v_coach_id, v_client_james,  5, 'Best investment I''ve ever made. The personalised programs and weekly check-ins kept me accountable. Gained 4kg of muscle in 3 months.', NOW() - INTERVAL '30 days'),
  (v_coach_id, v_client_aisha,  4, 'Really knowledgeable and responsive. The nutrition plan was a game changer. Would give 5 stars but sometimes takes a day to reply.', NOW() - INTERVAL '15 days'),
  -- Reviews for marketplace coaches
  (v_coach_sarah, v_client_id,  5, 'Sarah is the real deal. My squat went from 60kg to 100kg in 6 months. Incredibly technical, always explains the why.', NOW() - INTERVAL '60 days'),
  (v_coach_marcus, v_client_id, 4, 'Marcus got me from zero running to completing a 10K. Great communicator, very encouraging. Programs are solid.', NOW() - INTERVAL '20 days')
ON CONFLICT (coach_id, client_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 3: 30 DAYS OF DAILY SCORES (test client)
-- ═══════════════════════════════════════════════════════════════
-- Already have days 0-6 from test_accounts.sql; add days 7-29

INSERT INTO daily_scores (
  user_id, score_date,
  workout_points, nutrition_points, habits_points, checkin_points, community_points, total_score
) VALUES
  (v_client_id, CURRENT_DATE - 29,  30, 28, 20, 0,  0,  78),
  (v_client_id, CURRENT_DATE - 28,   0, 22, 12, 0,  0,  34),
  (v_client_id, CURRENT_DATE - 27,  30, 30, 20, 0, 10,  90),
  (v_client_id, CURRENT_DATE - 26,  30, 25, 16, 10, 0,  81),
  (v_client_id, CURRENT_DATE - 25,  30, 28, 20, 0,  0,  78),
  (v_client_id, CURRENT_DATE - 24,   0, 18,  8, 0,  0,  26),
  (v_client_id, CURRENT_DATE - 23,  30, 30, 20, 0, 10,  90),
  (v_client_id, CURRENT_DATE - 22,  30, 27, 18, 0,  0,  75),
  (v_client_id, CURRENT_DATE - 21,  30, 25, 20, 10, 10, 95),
  (v_client_id, CURRENT_DATE - 20,   0, 20, 12, 0,  0,  32),
  (v_client_id, CURRENT_DATE - 19,  30, 30, 20, 0,  0,  80),
  (v_client_id, CURRENT_DATE - 18,  30, 28, 16, 0, 10,  84),
  (v_client_id, CURRENT_DATE - 17,  30, 30, 20, 0,  0,  80),
  (v_client_id, CURRENT_DATE - 16,   0, 15,  8, 0,  0,  23),
  (v_client_id, CURRENT_DATE - 15,  30, 30, 20, 10, 0,  90),
  (v_client_id, CURRENT_DATE - 14,  30, 25, 16, 0, 10,  81),
  (v_client_id, CURRENT_DATE - 13,  30, 28, 20, 0,  0,  78),
  (v_client_id, CURRENT_DATE - 12,  30, 30, 20, 0, 10,  90),
  (v_client_id, CURRENT_DATE - 11,  30, 22, 12, 0,  0,  64),
  (v_client_id, CURRENT_DATE - 10,  30, 30, 20, 0,  0,  80),
  (v_client_id, CURRENT_DATE -  9,   0, 20,  8, 10, 0,  38),
  (v_client_id, CURRENT_DATE -  8,  30, 30, 20, 0, 10,  90),
  (v_client_id, CURRENT_DATE -  7,  30, 28, 18, 0,  0,  76)
ON CONFLICT (user_id, score_date) DO NOTHING;

-- Daily scores for community clients (so leaderboard has more people)
INSERT INTO daily_scores (user_id, score_date, workout_points, nutrition_points, habits_points, checkin_points, community_points, total_score)
  SELECT v_client_maria, CURRENT_DATE - gs,
    CASE WHEN gs % 4 = 0 THEN 0 ELSE 30 END,
    18 + (gs % 12), 12 + (gs % 8), 0, 0,
    (CASE WHEN gs % 4 = 0 THEN 0 ELSE 30 END) + 18 + (gs % 12) + 12 + (gs % 8)
  FROM generate_series(0,14) gs
ON CONFLICT (user_id, score_date) DO NOTHING;

INSERT INTO daily_scores (user_id, score_date, workout_points, nutrition_points, habits_points, checkin_points, community_points, total_score)
  SELECT v_client_james, CURRENT_DATE - gs,
    30, 25 + (gs % 5), 16 + (gs % 4), 0, 10,
    30 + 25 + (gs % 5) + 16 + (gs % 4) + 10
  FROM generate_series(0,14) gs
ON CONFLICT (user_id, score_date) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 4: WEIGHT LOGS (30 days — gradual downward trend)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO weight_logs (user_id, weight_kg, note, logged_at)
  SELECT
    v_client_id,
    ROUND((82.5 - (gs * 0.05) + (random() * 0.4 - 0.2))::numeric, 1),
    CASE gs % 7
      WHEN 0 THEN 'Monday weigh-in'
      WHEN 1 THEN null
      WHEN 2 THEN null
      WHEN 3 THEN 'Mid-week check'
      ELSE null
    END,
    NOW() - (gs || ' days')::interval
  FROM generate_series(0, 29) gs
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 5: BODY MEASUREMENTS (monthly entries over 6 months)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO body_measurements (user_id, chest_cm, waist_cm, hips_cm, arms_cm, thighs_cm, logged_at)
VALUES
  (v_client_id, 97.5, 88.0, 102.0, 37.0, 58.0, NOW() - INTERVAL '180 days'),
  (v_client_id, 97.0, 86.5, 101.5, 37.2, 57.5, NOW() - INTERVAL '150 days'),
  (v_client_id, 96.5, 85.0, 101.0, 37.5, 57.0, NOW() - INTERVAL '120 days'),
  (v_client_id, 96.0, 84.0, 100.5, 37.8, 56.5, NOW() - INTERVAL '90 days'),
  (v_client_id, 95.5, 83.0, 100.0, 38.0, 56.0, NOW() - INTERVAL '60 days'),
  (v_client_id, 95.0, 82.0,  99.5, 38.2, 55.5, NOW() - INTERVAL '30 days'),
  (v_client_id, 94.5, 81.0,  99.0, 38.5, 55.0, NOW())
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 6: NUTRITION LOGS (last 7 days)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO nutrition_logs (user_id, meal_type, food_name, calories, protein, carbs, fat, logged_at)
VALUES
  -- Day 0 (today)
  (v_client_id, 'breakfast', 'Greek Yogurt + Berries',     320, 28.0, 35.0,  6.0, NOW() - INTERVAL '0 days 8 hours'),
  (v_client_id, 'lunch',     'Chicken Rice Bowl',           520, 45.0, 52.0,  8.0, NOW() - INTERVAL '0 days 4 hours'),
  (v_client_id, 'snack',     'Protein Shake',               210, 25.0, 12.0,  4.0, NOW() - INTERVAL '0 days 1 hour'),

  -- Day -1
  (v_client_id, 'breakfast', 'Oat Porridge + Banana',       380, 12.0, 68.0,  6.0, NOW() - INTERVAL '1 day 8 hours'),
  (v_client_id, 'lunch',     'Turkey Wrap',                 450, 38.0, 42.0,  9.0, NOW() - INTERVAL '1 day 4 hours'),
  (v_client_id, 'dinner',    'Salmon + Sweet Potato',       550, 42.0, 48.0, 14.0, NOW() - INTERVAL '1 day 0 hours'),

  -- Day -2
  (v_client_id, 'breakfast', 'Scrambled Eggs + Toast',     380, 26.0, 28.0, 14.0, NOW() - INTERVAL '2 days 8 hours'),
  (v_client_id, 'lunch',     'Tuna Salad',                  380, 40.0, 12.0, 16.0, NOW() - INTERVAL '2 days 4 hours'),
  (v_client_id, 'dinner',    'Chicken Stir-Fry + Rice',     620, 48.0, 58.0, 12.0, NOW() - INTERVAL '2 days 0 hours'),
  (v_client_id, 'snack',     'Almonds 30g',                 180,  6.0,  5.0, 16.0, NOW() - INTERVAL '2 days 2 hours'),

  -- Day -3
  (v_client_id, 'breakfast', 'Protein Shake + Banana',      310, 28.0, 38.0,  4.0, NOW() - INTERVAL '3 days 8 hours'),
  (v_client_id, 'lunch',     'Beef Mince + Veg',            480, 44.0, 18.0, 22.0, NOW() - INTERVAL '3 days 4 hours'),
  (v_client_id, 'dinner',    'Grilled Chicken + Salad',     420, 48.0, 12.0, 14.0, NOW() - INTERVAL '3 days 0 hours'),

  -- Day -4 (rest day, lower intake)
  (v_client_id, 'breakfast', 'Avocado Toast 2 slices',      380, 14.0, 38.0, 18.0, NOW() - INTERVAL '4 days 9 hours'),
  (v_client_id, 'lunch',     'Vegetable Soup + Bread',      280,  8.0, 42.0,  6.0, NOW() - INTERVAL '4 days 1 hour'),

  -- Day -5
  (v_client_id, 'breakfast', 'Overnight Oats',              420, 18.0, 62.0,  8.0, NOW() - INTERVAL '5 days 7 hours'),
  (v_client_id, 'lunch',     'Prawn Noodle Bowl',           520, 36.0, 58.0,  8.0, NOW() - INTERVAL '5 days 2 hours'),
  (v_client_id, 'dinner',    'Steak + Broccoli',            580, 52.0, 14.0, 24.0, NOW() - INTERVAL '5 days 0 hours'),

  -- Day -6
  (v_client_id, 'breakfast', 'Greek Yogurt + Granola',      350, 22.0, 40.0,  8.0, NOW() - INTERVAL '6 days 8 hours'),
  (v_client_id, 'lunch',     'Chicken Caesar Wrap',         480, 38.0, 38.0, 14.0, NOW() - INTERVAL '6 days 3 hours'),
  (v_client_id, 'dinner',    'Baked Salmon + Quinoa',       560, 44.0, 42.0, 16.0, NOW() - INTERVAL '6 days 0 hours')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 7: HABIT LOGS (last 14 days)
-- ═══════════════════════════════════════════════════════════════
-- Patch any missing columns that the migration skipped (pre-existing table)
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS logged_date date DEFAULT CURRENT_DATE;
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS value numeric DEFAULT 1;
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS completed bool DEFAULT true;
ALTER TABLE habit_logs ADD COLUMN IF NOT EXISTS logged_at timestamptz DEFAULT now();

-- Grab the first 5 habits for the test client and log them realistically

DO $inner$
DECLARE
  v_habit record;
  v_day   int;
BEGIN
  FOR v_habit IN
    SELECT id FROM client_habits
    WHERE client_id = '5470a95f-bcae-4e01-b2be-7c16964fa432'
    ORDER BY assigned_at LIMIT 5
  LOOP
    FOR v_day IN 0..13 LOOP
      -- Skip habit completion ~20% of the time (realistic compliance)
      IF (random() > 0.2) THEN
        INSERT INTO habit_logs (habit_id, user_id, logged_date, value, completed, logged_at)
        VALUES (
          v_habit.id,
          '5470a95f-bcae-4e01-b2be-7c16964fa432',
          CURRENT_DATE - v_day,
          1,
          true,
          NOW() - (v_day || ' days')::interval - INTERVAL '20 hours'
        ) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END LOOP;
END $inner$;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 8: WORKOUT SESSIONS (completed, last 14 days)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO workout_sessions (user_id, workout_title, started_at, completed_at, status, duration_seconds, calories_burned, progress_data)
VALUES
  (v_client_id, 'Monday — Upper Push',
   NOW() - INTERVAL '13 days', NOW() - INTERVAL '13 days' + INTERVAL '58 minutes', 'completed', 3480, 310,
   '{"exercisesCompleted":5,"totalSets":16}'),
  (v_client_id, 'Tuesday — Lower Pull',
   NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days' + INTERVAL '62 minutes', 'completed', 3720, 340,
   '{"exercisesCompleted":5,"totalSets":17}'),
  (v_client_id, 'Thursday — Upper Pull',
   NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '55 minutes', 'completed', 3300, 290,
   '{"exercisesCompleted":5,"totalSets":17}'),
  (v_client_id, 'Friday — Lower Quad',
   NOW() - INTERVAL '9 days',  NOW() - INTERVAL '9 days'  + INTERVAL '65 minutes', 'completed', 3900, 380,
   '{"exercisesCompleted":5,"totalSets":16}'),
  (v_client_id, 'Monday — Upper Push',
   NOW() - INTERVAL '6 days',  NOW() - INTERVAL '6 days'  + INTERVAL '60 minutes', 'completed', 3600, 325,
   '{"exercisesCompleted":5,"totalSets":16}'),
  (v_client_id, 'Tuesday — Lower Pull',
   NOW() - INTERVAL '5 days',  NOW() - INTERVAL '5 days'  + INTERVAL '63 minutes', 'completed', 3780, 350,
   '{"exercisesCompleted":5,"totalSets":17}'),
  (v_client_id, 'Thursday — Upper Pull',
   NOW() - INTERVAL '3 days',  NOW() - INTERVAL '3 days'  + INTERVAL '57 minutes', 'completed', 3420, 300,
   '{"exercisesCompleted":5,"totalSets":17}'),
  (v_client_id, 'Friday — Lower Quad',
   NOW() - INTERVAL '2 days',  NOW() - INTERVAL '2 days'  + INTERVAL '67 minutes', 'completed', 4020, 395,
   '{"exercisesCompleted":5,"totalSets":16}')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 9: MESSAGING (conversation + 25 messages)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO conversations (participant_1, participant_2, last_message, last_message_at)
VALUES (v_coach_id, v_client_id, 'Great work this week Jordan! Keep it up 💪', NOW() - INTERVAL '2 hours')
ON CONFLICT DO NOTHING
RETURNING id INTO v_conv_id;

-- If already exists, look it up
IF v_conv_id IS NULL THEN
  SELECT id INTO v_conv_id FROM conversations
  WHERE (participant_1 = v_coach_id AND participant_2 = v_client_id)
     OR (participant_1 = v_client_id AND participant_2 = v_coach_id)
  LIMIT 1;
END IF;

IF v_conv_id IS NOT NULL THEN
  INSERT INTO messages (conversation_id, sender_id, content, is_read, sent_at) VALUES
    (v_conv_id, v_coach_id,  'Hey Jordan! Welcome aboard. I''ve set up your first week of training. Check the Workout tab.', true,  NOW() - INTERVAL '14 days 10 hours'),
    (v_conv_id, v_client_id, 'Thanks Alex! Just had a look — looks intense but I''m ready!', true,  NOW() - INTERVAL '14 days 9 hours'),
    (v_conv_id, v_coach_id,  'Perfect attitude. Remember: form over weight every single time. Let me know how Monday''s session goes.', true, NOW() - INTERVAL '14 days 8 hours'),
    (v_conv_id, v_client_id, 'Just finished Monday''s Upper Push. Bench press felt heavy at 60kg but I got through all 4 sets!', true,  NOW() - INTERVAL '13 days 7 hours'),
    (v_conv_id, v_coach_id,  '60kg for 4x8 on your first session is great. How did your energy feel?', true, NOW() - INTERVAL '13 days 5 hours'),
    (v_conv_id, v_client_id, 'Energy was good. Felt strong the first 2 sets then a bit tired on the last. Is that normal?', true,  NOW() - INTERVAL '13 days 4 hours'),
    (v_conv_id, v_coach_id,  'Completely normal — that''s what progressive overload feels like. Trust the process. Make sure you nail the nutrition today.', true, NOW() - INTERVAL '13 days 3 hours'),
    (v_conv_id, v_client_id, 'Logged all my meals today. Hit 172g protein. Was aiming for 175g but close enough right?', true, NOW() - INTERVAL '12 days 8 hours'),
    (v_conv_id, v_coach_id,  'Yes 172 is fine! Consistency matters more than hitting the exact number daily. Great job.', true, NOW() - INTERVAL '12 days 7 hours'),
    (v_conv_id, v_client_id, 'Weighed in this morning: 81.9kg. Down from 82.5kg at the start!', true, NOW() - INTERVAL '11 days 7 hours'),
    (v_conv_id, v_coach_id,  'Amazing! 600g in the first week. That''s right on track. Let''s keep that momentum.', true, NOW() - INTERVAL '11 days 6 hours'),
    (v_conv_id, v_client_id, 'Struggled with Thursday''s session. Pull-ups killed me — only got 6 reps on sets 3 and 4.', true, NOW() - INTERVAL '10 days 6 hours'),
    (v_conv_id, v_coach_id,  'That''s completely fine. Pull-ups are one of the hardest movements. Drop to 5 reps if you need to and focus on full range of motion. Quality > quantity.', true, NOW() - INTERVAL '10 days 5 hours'),
    (v_conv_id, v_client_id, 'Makes sense. Also — the waist measurement you asked about: 86cm down from 88cm at the start!', true, NOW() - INTERVAL '9 days 9 hours'),
    (v_conv_id, v_coach_id,  '2cm off the waist in 2 weeks — that''s incredible Jordan! Your body is responding really well.', true, NOW() - INTERVAL '9 days 8 hours'),
    (v_conv_id, v_client_id, 'Skipped Saturday cardio — had a family event. Feel a bit guilty about it.', true, NOW() - INTERVAL '8 days 10 hours'),
    (v_conv_id, v_coach_id,  'Don''t stress about it. Life happens. One session doesn''t make or break your progress — it''s the 90% consistency over time that counts. Rest days can also be planned.', true, NOW() - INTERVAL '8 days 8 hours'),
    (v_conv_id, v_client_id, 'Starting week 2 strong! Hit a new PR on the squat — 85kg for 4x8!', true, NOW() - INTERVAL '7 days 8 hours'),
    (v_conv_id, v_coach_id,  'Let''s go!!! 85kg is a great milestone. Video next session so I can check your depth?', true, NOW() - INTERVAL '7 days 7 hours'),
    (v_conv_id, v_client_id, 'Will do. Also I noticed I''m sleeping better since starting this program. Is that a thing?', true, NOW() - INTERVAL '6 days 9 hours'),
    (v_conv_id, v_coach_id,  'Absolutely — resistance training significantly improves sleep quality. Plus the stress reduction from having a structured routine helps too. Keep it up.', true, NOW() - INTERVAL '6 days 8 hours'),
    (v_conv_id, v_client_id, 'Check-in done for this week. Lost another 600g! Total: 1.3kg in 2 weeks.', true, NOW() - INTERVAL '3 days 9 hours'),
    (v_conv_id, v_coach_id,  'Consistent, steady fat loss. Exactly what we want. How are energy levels this week?', true, NOW() - INTERVAL '3 days 8 hours'),
    (v_conv_id, v_client_id, 'Energy is honestly the best it''s been in years. I actually look forward to training now.', true, NOW() - INTERVAL '2 days 3 hours'),
    (v_conv_id, v_coach_id,  'Great work this week Jordan! Keep it up 💪', true,  NOW() - INTERVAL '2 hours')
  ON CONFLICT DO NOTHING;
END IF;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 10: COMMUNITY POSTS + REACTIONS + COMMENTS
-- ═══════════════════════════════════════════════════════════════

INSERT INTO community_posts (user_id, content, post_type, likes_count, comments_count, created_at) VALUES
  (v_client_id,    'Week 2 done and dusted! Lost 1.3kg, hit a new squat PR of 85kg, and honestly feel like a different person. This is the most consistent I''ve been in YEARS. 🏋️ #12CircleFitness', 'milestone',    8, 3, NOW() - INTERVAL '2 days'),
  (v_client_james, 'Just hit 100kg on bench for the first time ever. 6 months ago I couldn''t even press 60kg. Trust the process 🔥', 'milestone',    12, 5, NOW() - INTERVAL '3 days'),
  (v_client_maria, 'Rest days are hard mentally but I know my body needs it. Trying to remember that recovery IS the work. Anyone else struggle with taking days off?', 'general',    6, 4, NOW() - INTERVAL '4 days'),
  (v_client_aisha, 'Morning meditation + cold shower + protein shake. My non-negotiable morning routine. What''s everyone else''s?', 'general',    9, 6, NOW() - INTERVAL '5 days'),
  (v_client_id,    'Nutrition tip from my coach that changed everything: prep your food on Sunday night and decision fatigue disappears. No more ''what should I eat'' at 7pm 🥦', 'tip',          7, 2, NOW() - INTERVAL '6 days'),
  (v_client_james, 'Started tracking my macros and realised I was eating 60g less protein than I thought. No wonder the gains were stalling! Track everything, people.', 'tip',          10, 3, NOW() - INTERVAL '7 days'),
  (v_client_maria, 'Just did my first ever unassisted pull-up! 3 months ago I couldn''t do even one. Slow and steady wins the race! 💪', 'milestone',    15, 7, NOW() - INTERVAL '8 days'),
  (v_client_aisha, 'Honest post: missed 3 workouts this week. Work deadlines took over. Not beating myself up — just getting back on it tomorrow. Progress isn''t linear.', 'general',    11, 8, NOW() - INTERVAL '9 days'),
  (v_client_id,    'Dropped 2cm off my waist in 2 weeks. Body recomposition is real — scale barely moved but the measurements tell a different story 📏', 'progress',    5, 2, NOW() - INTERVAL '10 days'),
  (v_client_james, 'Anyone tried training fasted in the morning? Curious if it actually makes a difference for fat loss or if that''s just a myth.', 'question',    4, 5, NOW() - INTERVAL '11 days')
ON CONFLICT DO NOTHING;

-- Reactions (likes)
INSERT INTO post_reactions (post_id, user_id, reaction_type, created_at)
  SELECT p.id, r.uid, 'like', NOW() - (random() * 5 || ' days')::interval
  FROM community_posts p
  CROSS JOIN (VALUES (v_client_id), (v_client_james), (v_client_maria), (v_client_aisha)) AS r(uid)
  WHERE p.user_id != r.uid
ON CONFLICT (post_id, user_id) DO NOTHING;

-- Comments on posts
WITH posts AS (
  SELECT id, user_id FROM community_posts ORDER BY created_at DESC LIMIT 5
)
INSERT INTO post_comments (post_id, user_id, content, created_at)
  (SELECT p.id, v_client_james, 'Amazing progress! Keep it going! 🙌', NOW() - INTERVAL '1 day' FROM posts p WHERE p.user_id = v_client_id LIMIT 1)
UNION ALL
  (SELECT p.id, v_client_aisha, 'This is so inspiring. Down 1.3kg in 2 weeks is brilliant!', NOW() - INTERVAL '2 days' FROM posts p WHERE p.user_id = v_client_id LIMIT 1)
UNION ALL
  (SELECT p.id, v_client_id, 'YES! Take those rest days. Your muscles grow when you rest, not when you train.', NOW() - INTERVAL '3 days' FROM posts p WHERE p.user_id = v_client_maria LIMIT 1)
UNION ALL
  (SELECT p.id, v_client_james, 'Mine: 5min journalling + black coffee + 10min walk. Game changer.', NOW() - INTERVAL '4 days' FROM posts p WHERE p.user_id = v_client_aisha LIMIT 1)
UNION ALL
  (SELECT p.id, v_client_maria, 'First pull-up is always the hardest! It only gets better from here 🔥', NOW() - INTERVAL '7 days' FROM posts p WHERE p.user_id = v_client_maria LIMIT 1)
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 11: FOODS (barcode scanner test items)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO foods (barcode, name, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g)
VALUES
  ('5000112548167', 'Quaker Oats Original',             375, 11.0, 64.0, 7.5),
  ('5000159407236', 'Kellogg''s Special K Original',    375,  8.5, 78.0, 2.0),
  ('5000232554535', 'Weetabix Whole Wheat Biscuits',    362, 11.5, 71.0, 2.5),
  ('5010029031233', 'Alpro Oat Milk Original',           46,  1.0,  6.5, 1.5),
  ('5000159421225', 'Müller Corner Strawberry Yogurt',  106,  3.8, 16.5, 2.6),
  ('5010029030144', 'Activia Vanilla Greek Yogurt',      72,  5.5,  7.0, 2.0),
  ('5000112548280', 'McVitie''s Digestives Original',   481,  6.5, 63.0, 20.0),
  ('5000119014004', 'Walkers Ready Salted Crisps 25g',  524,  6.3, 53.0, 31.0),
  ('5000173109059', 'Tracker Chocolate Chip Bar',       461,  6.4, 59.0, 21.0),
  ('5000168009830', 'Myprotein Impact Whey Vanilla',    403, 82.0,  6.5, 4.5),
  ('5000168011963', 'Myprotein Impact Whey Chocolate',  397, 80.0,  8.0, 4.2),
  ('5060743710018', 'Huel Black Edition Vanilla',       400, 40.0, 26.0, 17.0),
  ('5060368612315', 'PHD Pharma Whey Protein Bar',      344, 32.0, 32.0, 9.0),
  ('5011269002387', 'Innocent Banana Berry Smoothie',    69,  0.8, 15.5, 0.5),
  ('4056489111375', 'Lidl Pistachio Nuts Roasted',      602, 21.0, 15.0, 51.0),
  ('5000159416094', 'Nakd Cocoa Orange Bar',            399,  8.5, 44.0, 19.5),
  ('5010029027335', 'Basmati Rice 250g',                357,  6.7, 81.0, 0.9),
  ('5051551002700', 'Warburtons Wholemeal Bread',       218,  9.0, 39.0, 2.5),
  ('5000168009977', 'Myprotein Peanut Butter Smooth',   616, 26.0, 13.0, 51.0),
  ('8720182865052', 'Optimum Nutrition Gold Standard Whey', 416, 76.0, 9.5, 8.5)
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 12: PROGRESS PHOTO LOGS (placeholder paths)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO progress_photo_logs (user_id, storage_path, side, logged_at)
VALUES
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-01/front.jpg', 'front',  NOW() - INTERVAL '90 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-01/side.jpg',  'side',   NOW() - INTERVAL '90 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-01/back.jpg',  'back',   NOW() - INTERVAL '90 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-04/front.jpg', 'front',  NOW() - INTERVAL '30 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-04/side.jpg',  'side',   NOW() - INTERVAL '30 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-04/back.jpg',  'back',   NOW() - INTERVAL '30 days'),
  (v_client_id, 'progress-photos/5470a95f-bcae-4e01-b2be-7c16964fa432/2026-06/front.jpg', 'gallery', NOW() - INTERVAL '7 days')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 13: COACH AVAILABILITY + COACHING CALLS
-- ═══════════════════════════════════════════════════════════════

INSERT INTO coach_availability (coach_id, slot_time, duration_minutes, type, is_booked)
VALUES
  (v_coach_id, NOW() + INTERVAL '1 day 10 hours',   30, 'check_in',          false),
  (v_coach_id, NOW() + INTERVAL '1 day 14 hours',   30, 'check_in',          false),
  (v_coach_id, NOW() + INTERVAL '2 days 10 hours',  60, 'consultation',      false),
  (v_coach_id, NOW() + INTERVAL '3 days 9 hours',   30, 'nutrition_review',  true),
  (v_coach_id, NOW() + INTERVAL '3 days 11 hours',  30, 'check_in',          false),
  (v_coach_id, NOW() + INTERVAL '5 days 10 hours',  30, 'check_in',          true),
  (v_coach_id, NOW() + INTERVAL '5 days 14 hours',  60, 'consultation',      false),
  (v_coach_id, NOW() + INTERVAL '7 days 10 hours',  30, 'check_in',          false),
  (v_coach_id, NOW() + INTERVAL '7 days 13 hours',  30, 'nutrition_review',  false),
  (v_coach_id, NOW() + INTERVAL '10 days 10 hours', 30, 'check_in',          false)
ON CONFLICT DO NOTHING;

-- Completed + upcoming coaching calls
INSERT INTO coaching_calls (
  coach_id, client_id, scheduled_at, duration_minutes,
  call_type, status, notes, meeting_link
)
VALUES
  (v_coach_id, v_client_id,
   NOW() - INTERVAL '7 days',
   30, 'check_in', 'completed',
   'Week 1 check-in. Client doing well. Discussed energy levels and sleep. Adjusted carbs around workouts. Very motivated.',
   'https://meet.google.com/abc-defg-hij'),
  (v_coach_id, v_client_id,
   NOW() + INTERVAL '3 days 9 hours',
   30, 'nutrition_review', 'scheduled',
   'Week 3 nutrition review — assess macro adherence and tweak if needed.',
   'https://meet.google.com/klm-nopq-rst'),
  (v_coach_id, v_client_id,
   NOW() + INTERVAL '10 days',
   60, 'consultation', 'scheduled',
   'Mid-program check. Review measurements, progress photos, and adjust program for weeks 5-8.',
   'https://meet.google.com/uvw-xyz1-234')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 14: CLASSES
-- ═══════════════════════════════════════════════════════════════

INSERT INTO classes (coach_id, title, description, type, is_online, meeting_link, scheduled_at, duration_minutes, max_capacity, current_enrolled, status)
VALUES
  (v_coach_id, 'Live Q&A: Nutrition for Fat Loss',
   'Ask me anything about your diet, macros, and how to sustain a caloric deficit without feeling miserable.',
   'q_and_a', true, 'https://meet.google.com/aaaa-bbbb-cccc',
   NOW() + INTERVAL '3 days 19 hours', 60, 20, 7, 'scheduled'),
  (v_coach_id, 'Group Check-In: Week 4 Review',
   'Group accountability call for all active clients in the 12-week program. Share wins, discuss challenges.',
   'group_checkin', true, 'https://meet.google.com/dddd-eeee-ffff',
   NOW() + INTERVAL '5 days 18 hours', 45, 15, 4, 'scheduled'),
  (v_coach_sarah, 'Powerlifting 101: Learning the Big 3',
   'Intro session covering squat, bench, and deadlift technique. Perfect for beginners wanting to start strength training.',
   'workshop', true, 'https://meet.google.com/gggg-hhhh-iiii',
   NOW() + INTERVAL '4 days 17 hours', 90, 12, 9, 'scheduled')
ON CONFLICT DO NOTHING;

-- Register test client for first class
INSERT INTO class_bookings (class_id, user_id, status)
  SELECT id, v_client_id, 'confirmed' FROM classes
  WHERE title = 'Live Q&A: Nutrition for Fat Loss' LIMIT 1
ON CONFLICT (class_id, user_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 15: EVENTS
-- ═══════════════════════════════════════════════════════════════

INSERT INTO events (title, description, location, event_date, end_date, host_name, max_capacity, current_registered, price, is_free, status)
VALUES
  ('12 Circle Fitness Summer Kickoff',
   'Join us for a full-day fitness festival with outdoor workouts, nutrition talks, a marketplace from our vendors, and prizes for the most improved members!',
   'Victoria Park, London E9 7BT',
   NOW() + INTERVAL '30 days',
   NOW() + INTERVAL '30 days' + INTERVAL '8 hours',
   'Alex Coach', 200, 78, 0, true, 'upcoming'),
  ('Strength & Conditioning Workshop',
   'A hands-on 3-hour workshop covering progressive overload, program design, and how to track progress. Suitable for intermediate lifters.',
   'Pure Gym Shoreditch, London EC2A 4BX',
   NOW() + INTERVAL '14 days',
   NOW() + INTERVAL '14 days' + INTERVAL '3 hours',
   'Sarah Johnson', 25, 18, 35, false, 'upcoming'),
  ('Free Community Yoga & Mindfulness Session',
   'Priya leads a free outdoor yoga session followed by a guided meditation. All levels welcome — just bring a mat!',
   'Regent''s Park, London NW1',
   NOW() + INTERVAL '7 days',
   NOW() + INTERVAL '7 days' + INTERVAL '2 hours',
   'Priya Sharma', 50, 31, 0, true, 'upcoming')
ON CONFLICT DO NOTHING;

-- Register test client for free events
INSERT INTO event_registrations (event_id, user_id, status)
  SELECT id, v_client_id, 'registered' FROM events
  WHERE title = '12 Circle Fitness Summer Kickoff' LIMIT 1
ON CONFLICT (event_id, user_id) DO NOTHING;

INSERT INTO event_registrations (event_id, user_id, status)
  SELECT id, v_client_id, 'registered' FROM events
  WHERE title = 'Free Community Yoga & Mindfulness Session' LIMIT 1
ON CONFLICT (event_id, user_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 16: ADDITIONAL CHALLENGES (beyond the one in test_accounts.sql)
-- ═══════════════════════════════════════════════════════════════

WITH ch2 AS (
  INSERT INTO challenges (
    coach_id, title, description, type, target_value, unit, status, start_date, end_date, emoji
  ) VALUES (
    v_coach_id,
    '10k Steps Daily — June',
    'Hit 10,000 steps every day this month. Log your steps in the Habits section each day to earn points.',
    'steps', 10000, 'steps', 'active',
    DATE_TRUNC('month', CURRENT_DATE),
    DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day',
    '👟'
  ) RETURNING id
)
INSERT INTO challenge_participants (challenge_id, user_id, current_progress)
  SELECT id, v_client_id,   12 FROM ch2
  UNION ALL
  SELECT id, v_client_james,  9 FROM ch2
  UNION ALL
  SELECT id, v_client_maria,  7 FROM ch2
  UNION ALL
  SELECT id, v_client_aisha, 11 FROM ch2
ON CONFLICT (challenge_id, user_id) DO NOTHING;

WITH ch3 AS (
  INSERT INTO challenges (
    coach_id, title, description, type, target_value, unit, status, start_date, end_date, emoji
  ) VALUES (
    v_coach_sarah,
    '100kg Deadlift in 90 Days',
    'A strength-focused challenge for anyone who wants to hit a 100kg deadlift within 90 days. Log your PBs in the Workout tracker.',
    'strength', 100, 'kg', 'active',
    CURRENT_DATE - 30,
    CURRENT_DATE + 60,
    '🏋️'
  ) RETURNING id
)
INSERT INTO challenge_participants (challenge_id, user_id, current_progress)
  SELECT id, v_client_id,   85  FROM ch3
  UNION ALL
  SELECT id, v_client_james, 95  FROM ch3
ON CONFLICT (challenge_id, user_id) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 17: ACCOUNTABILITY POD
-- ═══════════════════════════════════════════════════════════════

INSERT INTO accountability_pods (
  coach_id, name, description, max_members, member_count, status, meeting_frequency
) VALUES (
  v_coach_id,
  'Summer Shred Squad',
  'A small accountability group for clients on the Summer Shred 8-Week program. Daily check-ins, wins, and motivation.',
  8, 0, 'open', 'Daily check-ins'
) RETURNING id INTO v_pod_id;

IF v_pod_id IS NOT NULL THEN
  INSERT INTO accountability_pod_members (pod_id, user_id, joined_at)
  VALUES
    (v_pod_id, v_client_id,    NOW() - INTERVAL '10 days'),
    (v_pod_id, v_client_james, NOW() - INTERVAL '8 days'),
    (v_pod_id, v_client_maria, NOW() - INTERVAL '6 days')
  ON CONFLICT (pod_id, user_id) DO NOTHING;
END IF;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 18: NOTIFICATIONS (test client)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO notifications (recipient_id, type, title, body, read, created_at)
VALUES
  (v_client_id, 'message',     'New message from Alex',  'Great work this week Jordan! Keep it up 💪',                               false, NOW() - INTERVAL '2 hours'),
  (v_client_id, 'weekly_checkins', 'Weekly check-in due','It''s Sunday! Time to complete your weekly check-in with Alex.',           false, NOW() - INTERVAL '5 hours'),
  (v_client_id, 'today_score', 'New PB!',                'You hit a squat PR of 85kg. Incredible work! 🏋️',                         true,  NOW() - INTERVAL '7 days'),
  (v_client_id, 'challenges',  'Challenge update',       '10k Steps Challenge: you''re in 3rd place with 12 days logged!',           true,  NOW() - INTERVAL '1 day'),
  (v_client_id, 'messages',    'Class reminder',         'Your Q&A with Alex is in 1 hour. Join via the Classes tab.',               true,  NOW() - INTERVAL '3 days'),
  (v_client_id, 'message',     'New message from Alex',  'How did week 2 go? Let me know your weigh-in!',                            true,  NOW() - INTERVAL '3 days 4 hours'),
  (v_client_id, 'user',        'Event registered!',      'You''re registered for the Summer Kickoff. See you there! 🎉',             true,  NOW() - INTERVAL '5 days'),
  (v_client_id, 'nutrition_assigned', 'Log your meals',  'You haven''t logged lunch yet today. Stay on track with your 2000 cal target!', true, NOW() - INTERVAL '2 days 6 hours')
ON CONFLICT DO NOTHING;

-- Notifications for the test coach
INSERT INTO notifications (recipient_id, type, title, body, read, created_at)
VALUES
  (v_coach_id, 'weekly_checkins', 'Jordan completed Week 3 check-in', 'Jordan logged: weight 81.2kg, energy 4/5, compliance 92%. ✅', false, NOW() - INTERVAL '1 day'),
  (v_coach_id, 'coach_request',   'New review from Maria Chen',        'Maria left you a 5-star review! 🌟',                           false, NOW() - INTERVAL '45 days'),
  (v_coach_id, 'message',         'New message from Jordan',           'Weigh-in this morning: 81.9kg. Down from 82.5kg!',             true,  NOW() - INTERVAL '11 days')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- SECTION 19: COACH INVITES (test coach has sent a few)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO coach_invites (coach_id, invitee_email, status, created_at, expires_at)
VALUES
  (v_coach_id, 'sarah.prospect@gmail.com',  'pending',  NOW() - INTERVAL '2 days',  NOW() + INTERVAL '5 days'),
  (v_coach_id, 'mike.training@hotmail.com', 'pending',  NOW() - INTERVAL '5 days',  NOW() + INTERVAL '2 days'),
  (v_coach_id, 'lisa.fitness@outlook.com',  'accepted', NOW() - INTERVAL '20 days', NOW() - INTERVAL '13 days'),
  (v_coach_id, 'tom.gains@gmail.com',       'pending',  NOW() - INTERVAL '1 day',   NOW() + INTERVAL '6 days')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- DONE
-- ═══════════════════════════════════════════════════════════════

RAISE NOTICE '✅ Full test data seeded successfully!';
RAISE NOTICE '  Marketplace coaches : 5 (Sarah, Marcus, Priya, Derek, Natasha)';
RAISE NOTICE '  Community clients   : 3 (Maria, James, Aisha)';
RAISE NOTICE '  Daily scores        : 30 days for test client';
RAISE NOTICE '  Weight logs         : 30 entries (gradual downward trend)';
RAISE NOTICE '  Body measurements   : 7 entries over 6 months';
RAISE NOTICE '  Nutrition logs      : 21 meals across 7 days';
RAISE NOTICE '  Habit logs          : 14 days (auto-generated)';
RAISE NOTICE '  Workout sessions    : 8 completed sessions';
RAISE NOTICE '  Messages            : 25 (coach ↔ client conversation)';
RAISE NOTICE '  Community posts     : 10 with likes and comments';
RAISE NOTICE '  Foods (barcode)     : 20 items with barcodes';
RAISE NOTICE '  Progress photo logs : 7 entries';
RAISE NOTICE '  Coach availability  : 10 slots';
RAISE NOTICE '  Coaching calls      : 3 (1 completed, 2 upcoming)';
RAISE NOTICE '  Classes             : 3 (2 by Alex, 1 by Sarah)';
RAISE NOTICE '  Events              : 3';
RAISE NOTICE '  Challenges          : 2 additional (total 3)';
RAISE NOTICE '  Accountability pod  : 1 with 3 members';
RAISE NOTICE '  Notifications       : 8 client + 3 coach';
RAISE NOTICE '  Coach invites       : 4 (3 pending, 1 accepted)';
RAISE NOTICE '  Coach reviews       : 5';
RAISE NOTICE '';
RAISE NOTICE '  Test accounts still valid:';
RAISE NOTICE '    Coach:  coach@12circle.app / Coach1234!  (UUID: f626acd9-...)';
RAISE NOTICE '    Client: test@12circle.app  / Test1234!   (UUID: 5470a95f-...)';

END $$;
