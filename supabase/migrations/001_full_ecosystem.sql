-- ── STAGE B.4: search_path for pgcrypto ─────────────────────────────────────
-- This file declares column DEFAULTs of the form
--     encode(gen_random_bytes(16), 'hex')
-- with gen_random_bytes() UNQUALIFIED. On Supabase pgcrypto is installed in the
-- `extensions` schema, and the role `supabase db reset` logs in as has a
-- search_path that does not include it, so the function does not resolve and the
-- whole replay aborts here:
--     ERROR: function gen_random_bytes(integer) does not exist  (SQLSTATE 42883)
--
-- Setting it in 000 does not help -- the CLI gives each migration file its own
-- connection, so the setting has to be in the file that needs it. This is
-- session-scoped: it changes no database or role configuration. `public` stays
-- first, so unqualified CREATEs still land in public, and the DEFAULT is stored
-- bound to extensions.gen_random_bytes by OID -- byte-identical to the shape the
-- pre-rebuild QA database carried.
SET search_path = public, extensions;

-- ═══════════════════════════════════════════════════════════
-- 12 Circle Fitness — Full Coach-Client Ecosystem Schema
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ── Pre-existing table patches ──────────────────────────────
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS coach_id uuid REFERENCES user_profiles(id);
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'workout';
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS target_value numeric;
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS unit text;
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS start_date date;
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS end_date date;
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS emoji text DEFAULT '🏆';
ALTER TABLE challenges ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS coach_id uuid REFERENCES user_profiles(id);
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS weight_kg numeric;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS energy_level int;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS stress_level int;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS sleep_hours numeric;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS hunger_level int;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS compliance_percent int;
ALTER TABLE weekly_checkins ADD COLUMN IF NOT EXISTS notes text;

-- ── Coach Profile Enhancements ──────────────────────────────
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS specialties text[] DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS certifications text[] DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS pricing_monthly numeric;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS pricing_description text;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS years_experience int;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS transformation_photo_urls text[] DEFAULT '{}';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS rating_avg numeric DEFAULT 0;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS review_count int DEFAULT 0;

-- ── Coach-Client Relationship Enhancements ──────────────────
ALTER TABLE coach_client_relationships ADD COLUMN IF NOT EXISTS request_message text;
ALTER TABLE coach_client_relationships ADD COLUMN IF NOT EXISTS invite_id uuid;
ALTER TABLE coach_client_relationships ADD COLUMN IF NOT EXISTS pending_at timestamptz;

-- ── Coach Invites ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coach_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid REFERENCES user_profiles(id) ON DELETE CASCADE,
  invitee_email text NOT NULL,
  token text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '7 days'),
  accepted_at timestamptz
);

-- ── Workout Programs (coach creates templates) ───────────────
CREATE TABLE IF NOT EXISTS workout_programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid REFERENCES user_profiles(id),
  name text NOT NULL,
  description text,
  goal text,
  difficulty text DEFAULT 'intermediate',
  duration_weeks int DEFAULT 12,
  is_template bool DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS program_workouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id uuid REFERENCES workout_programs(id) ON DELETE CASCADE,
  week_number int NOT NULL,
  day_of_week text NOT NULL,
  title text NOT NULL,
  description text,
  estimated_minutes int DEFAULT 45,
  exercises jsonb DEFAULT '[]',
  sort_order int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS workout_program_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id uuid REFERENCES workout_programs(id),
  client_id uuid REFERENCES user_profiles(id),
  coach_id uuid REFERENCES user_profiles(id),
  start_date date DEFAULT CURRENT_DATE,
  current_week int DEFAULT 1,
  status text DEFAULT 'active',
  assigned_at timestamptz DEFAULT now()
);

-- ── Client Nutrition Plans ───────────────────────────────────
CREATE TABLE IF NOT EXISTS client_nutrition_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid REFERENCES user_profiles(id),
  coach_id uuid REFERENCES user_profiles(id),
  calories_target int,
  protein_g int,
  carbs_g int,
  fat_g int,
  notes text,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- ── Client Habits (coach-assigned) ──────────────────────────
CREATE TABLE IF NOT EXISTS client_habits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid REFERENCES user_profiles(id),
  coach_id uuid REFERENCES user_profiles(id),
  name text NOT NULL,
  emoji text DEFAULT '⭐',
  category text DEFAULT 'health',
  target_value numeric DEFAULT 1,
  unit text DEFAULT 'times',
  is_active bool DEFAULT true,
  reminder_time text,
  assigned_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS habit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  habit_id uuid REFERENCES client_habits(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  logged_date date DEFAULT CURRENT_DATE,
  value numeric DEFAULT 1,
  completed bool DEFAULT true,
  logged_at timestamptz DEFAULT now(),
  UNIQUE(habit_id, logged_date)
);

-- ── Workout Sessions (for tracking + resume) ─────────────────
CREATE TABLE IF NOT EXISTS workout_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES user_profiles(id),
  workout_title text NOT NULL,
  program_workout_id uuid REFERENCES program_workouts(id),
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  status text DEFAULT 'in_progress',
  progress_data jsonb DEFAULT '{}',
  duration_seconds int DEFAULT 0,
  calories_burned int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS workout_set_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES workout_sessions(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  exercise_name text NOT NULL,
  set_number int NOT NULL,
  reps int,
  weight_kg numeric,
  rpe numeric,
  notes text,
  logged_at timestamptz DEFAULT now()
);

-- ── Post-Workout Feedback ────────────────────────────────────
CREATE TABLE IF NOT EXISTS workout_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES workout_sessions(id),
  user_id uuid REFERENCES user_profiles(id),
  coach_id uuid REFERENCES user_profiles(id),
  rating int CHECK (rating BETWEEN 1 AND 5),
  energy_level int CHECK (energy_level BETWEEN 1 AND 5),
  difficulty int CHECK (difficulty BETWEEN 1 AND 5),
  notes text,
  created_at timestamptz DEFAULT now()
);

-- ── 12 Circle Score ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES user_profiles(id),
  score_date date DEFAULT CURRENT_DATE,
  workout_points int DEFAULT 0,
  nutrition_points int DEFAULT 0,
  habits_points int DEFAULT 0,
  checkin_points int DEFAULT 0,
  community_points int DEFAULT 0,
  total_score int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, score_date)
);

-- ── Coach Reviews ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coach_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid REFERENCES user_profiles(id),
  client_id uuid REFERENCES user_profiles(id),
  rating int CHECK (rating BETWEEN 1 AND 5),
  review_text text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(coach_id, client_id)
);

-- ── Live Challenges ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid REFERENCES user_profiles(id),
  title text NOT NULL,
  description text,
  type text NOT NULL,
  emoji text DEFAULT '🏆',
  target_value numeric,
  unit text,
  start_date date,
  end_date date,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS challenge_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id uuid REFERENCES challenges(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  current_progress numeric DEFAULT 0,
  joined_at timestamptz DEFAULT now(),
  UNIQUE(challenge_id, user_id)
);

-- ── Live Classes ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id uuid REFERENCES user_profiles(id),
  title text NOT NULL,
  description text,
  type text,
  location text,
  is_online bool DEFAULT false,
  meeting_link text,
  scheduled_at timestamptz NOT NULL,
  duration_minutes int DEFAULT 60,
  max_capacity int DEFAULT 20,
  current_enrolled int DEFAULT 0,
  status text DEFAULT 'scheduled',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS class_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES classes(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  status text DEFAULT 'confirmed',
  booked_at timestamptz DEFAULT now(),
  UNIQUE(class_id, user_id)
);

-- ── Events ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  location text,
  event_date timestamptz NOT NULL,
  end_date timestamptz,
  cover_image_url text,
  host_name text,
  max_capacity int,
  current_registered int DEFAULT 0,
  price numeric DEFAULT 0,
  is_free bool DEFAULT true,
  status text DEFAULT 'upcoming',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid REFERENCES events(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  qr_code text DEFAULT encode(gen_random_bytes(16), 'hex'),
  status text DEFAULT 'registered',
  registered_at timestamptz DEFAULT now(),
  UNIQUE(event_id, user_id)
);

-- ── Community ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES user_profiles(id),
  content text NOT NULL,
  image_urls text[] DEFAULT '{}',
  post_type text DEFAULT 'general',
  likes_count int DEFAULT 0,
  comments_count int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS post_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  reaction_type text DEFAULT 'like',
  created_at timestamptz DEFAULT now(),
  UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS post_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id uuid REFERENCES user_profiles(id),
  content text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════
ALTER TABLE coach_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_program_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_nutrition_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_set_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;

-- Coach invites
CREATE POLICY "coaches manage invites" ON coach_invites FOR ALL TO authenticated USING (coach_id = auth.uid());
CREATE POLICY "invitees read own" ON coach_invites FOR SELECT TO authenticated USING (invitee_email = (SELECT email FROM user_profiles WHERE id = auth.uid()));

-- Programs (coaches write, everyone reads)
CREATE POLICY "coaches manage programs" ON workout_programs FOR ALL TO authenticated USING (coach_id = auth.uid());
CREATE POLICY "all read programs" ON workout_programs FOR SELECT TO authenticated USING (true);
CREATE POLICY "all read program workouts" ON program_workouts FOR SELECT TO authenticated USING (true);
CREATE POLICY "coaches manage program workouts" ON program_workouts FOR ALL TO authenticated USING (
  program_id IN (SELECT id FROM workout_programs WHERE coach_id = auth.uid())
);
CREATE POLICY "coaches manage assignments" ON workout_program_assignments FOR ALL TO authenticated USING (coach_id = auth.uid() OR client_id = auth.uid());

-- Nutrition + habits (coach assigns, client reads)
CREATE POLICY "coach client nutrition" ON client_nutrition_plans FOR ALL TO authenticated USING (coach_id = auth.uid() OR client_id = auth.uid());
CREATE POLICY "coach client habits" ON client_habits FOR ALL TO authenticated USING (coach_id = auth.uid() OR client_id = auth.uid());
CREATE POLICY "users manage own habit logs" ON habit_logs FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read client habit logs" ON habit_logs FOR SELECT TO authenticated USING (
  habit_id IN (SELECT id FROM client_habits WHERE coach_id = auth.uid())
);

-- Workout sessions
CREATE POLICY "users manage own sessions" ON workout_sessions FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read client sessions" ON workout_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own set logs" ON workout_set_logs FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read client set logs" ON workout_set_logs FOR SELECT TO authenticated USING (true);

-- Feedback
CREATE POLICY "users manage own feedback" ON workout_feedback FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read feedback" ON workout_feedback FOR SELECT TO authenticated USING (true);

-- Scores
CREATE POLICY "users manage own scores" ON daily_scores FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read client scores" ON daily_scores FOR SELECT TO authenticated USING (true);

-- Reviews
CREATE POLICY "all read reviews" ON coach_reviews FOR SELECT TO authenticated USING (true);
CREATE POLICY "clients manage own reviews" ON coach_reviews FOR ALL TO authenticated USING (client_id = auth.uid());

-- Challenges
CREATE POLICY "coaches manage challenges" ON challenges FOR ALL TO authenticated USING (coach_id = auth.uid());
CREATE POLICY "all read challenges" ON challenges FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own participation" ON challenge_participants FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "all read participants" ON challenge_participants FOR SELECT TO authenticated USING (true);

-- Classes
CREATE POLICY "coaches manage classes" ON classes FOR ALL TO authenticated USING (coach_id = auth.uid());
CREATE POLICY "all read classes" ON classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own bookings" ON class_bookings FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "coaches read bookings" ON class_bookings FOR SELECT TO authenticated USING (true);

-- Events
CREATE POLICY "all read events" ON events FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own registrations" ON event_registrations FOR ALL TO authenticated USING (user_id = auth.uid());

-- Community
CREATE POLICY "all read posts" ON community_posts FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own posts" ON community_posts FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "all read reactions" ON post_reactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own reactions" ON post_reactions FOR ALL TO authenticated USING (user_id = auth.uid());
CREATE POLICY "all read comments" ON post_comments FOR SELECT TO authenticated USING (true);
CREATE POLICY "users manage own comments" ON post_comments FOR ALL TO authenticated USING (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════
-- Realtime (safe re-run)
-- ═══════════════════════════════════════════════════════════
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE notifications; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE community_posts; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE post_reactions; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE post_comments; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE workout_sessions; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages; EXCEPTION WHEN others THEN NULL; END $$;
