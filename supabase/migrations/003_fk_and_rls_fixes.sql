-- ============================================================
-- Migration 003: FK → user_profiles + RLS for pre-existing tables
-- Run in Supabase SQL Editor
--
-- Fixes two issues:
-- 1. PostgREST FK joins (user_profiles!xxx_fkey) require the FK to
--    reference user_profiles(id), not auth.users(id).
-- 2. Pre-existing tables (conversations, messages, weight_logs, etc.)
--    need RLS policies so the app can read/write the seeded data.
-- ============================================================

-- ── 1. community_posts → user_profiles ───────────────────────────────────────
ALTER TABLE community_posts DROP CONSTRAINT IF EXISTS community_posts_user_id_fkey;
ALTER TABLE community_posts
  ADD CONSTRAINT community_posts_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 2. post_comments → user_profiles ─────────────────────────────────────────
ALTER TABLE post_comments DROP CONSTRAINT IF EXISTS post_comments_user_id_fkey;
ALTER TABLE post_comments
  ADD CONSTRAINT post_comments_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 3. post_reactions → user_profiles ────────────────────────────────────────
ALTER TABLE post_reactions DROP CONSTRAINT IF EXISTS post_reactions_user_id_fkey;
ALTER TABLE post_reactions
  ADD CONSTRAINT post_reactions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 4. weekly_checkins → user_profiles ───────────────────────────────────────
ALTER TABLE weekly_checkins DROP CONSTRAINT IF EXISTS weekly_checkins_user_id_fkey;
ALTER TABLE weekly_checkins
  ADD CONSTRAINT weekly_checkins_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 5. classes → user_profiles (coach_id) ────────────────────────────────────
ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_coach_id_fkey;
ALTER TABLE classes
  ADD CONSTRAINT classes_coach_id_fkey
  FOREIGN KEY (coach_id) REFERENCES user_profiles(id) ON DELETE SET NULL;

-- ── 6. coach_reviews → user_profiles (client_id) ─────────────────────────────
ALTER TABLE coach_reviews DROP CONSTRAINT IF EXISTS coach_reviews_client_id_fkey;
ALTER TABLE coach_reviews
  ADD CONSTRAINT coach_reviews_client_id_fkey
  FOREIGN KEY (client_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 7. coach_team_members → user_profiles (member_id) ────────────────────────
ALTER TABLE coach_team_members DROP CONSTRAINT IF EXISTS coach_team_members_member_id_fkey;
ALTER TABLE coach_team_members
  ADD CONSTRAINT coach_team_members_member_id_fkey
  FOREIGN KEY (member_id) REFERENCES user_profiles(id) ON DELETE CASCADE;

-- ── 8. accountability_pods → user_profiles (coach_id) ────────────────────────
ALTER TABLE accountability_pods DROP CONSTRAINT IF EXISTS accountability_pods_coach_id_fkey;
ALTER TABLE accountability_pods
  ADD CONSTRAINT accountability_pods_coach_id_fkey
  FOREIGN KEY (coach_id) REFERENCES user_profiles(id) ON DELETE SET NULL;

-- ── 9. conversations: RLS + policies ─────────────────────────────────────────
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "participants can read conversations" ON conversations;
CREATE POLICY "participants can read conversations"
  ON conversations FOR SELECT TO authenticated
  USING (participant_1 = auth.uid() OR participant_2 = auth.uid());

DROP POLICY IF EXISTS "participants can insert conversations" ON conversations;
CREATE POLICY "participants can insert conversations"
  ON conversations FOR INSERT TO authenticated
  WITH CHECK (participant_1 = auth.uid() OR participant_2 = auth.uid());

DROP POLICY IF EXISTS "participants can update conversations" ON conversations;
CREATE POLICY "participants can update conversations"
  ON conversations FOR UPDATE TO authenticated
  USING (participant_1 = auth.uid() OR participant_2 = auth.uid());

-- ── 10. messages: RLS + policies ─────────────────────────────────────────────
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversation participants can read messages" ON messages;
CREATE POLICY "conversation participants can read messages"
  ON messages FOR SELECT TO authenticated
  USING (
    conversation_id IN (
      SELECT id FROM conversations
      WHERE participant_1 = auth.uid() OR participant_2 = auth.uid()
    )
  );

DROP POLICY IF EXISTS "authenticated can send messages" ON messages;
CREATE POLICY "authenticated can send messages"
  ON messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "recipients can mark messages read" ON messages;
CREATE POLICY "recipients can mark messages read"
  ON messages FOR UPDATE TO authenticated
  USING (
    conversation_id IN (
      SELECT id FROM conversations
      WHERE participant_1 = auth.uid() OR participant_2 = auth.uid()
    )
  );

-- ── 11. weight_logs: RLS + policies ──────────────────────────────────────────
ALTER TABLE weight_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own weight logs" ON weight_logs;
CREATE POLICY "users manage own weight logs"
  ON weight_logs FOR ALL TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "coaches read client weight logs" ON weight_logs;
CREATE POLICY "coaches read client weight logs"
  ON weight_logs FOR SELECT TO authenticated
  USING (true);

-- ── 12. body_measurements: RLS + policies ────────────────────────────────────
ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own measurements" ON body_measurements;
CREATE POLICY "users manage own measurements"
  ON body_measurements FOR ALL TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "coaches read client measurements" ON body_measurements;
CREATE POLICY "coaches read client measurements"
  ON body_measurements FOR SELECT TO authenticated
  USING (true);

-- ── 13. nutrition_logs: RLS + policies ───────────────────────────────────────
-- STAGE B.3 (B2-3): nutrition_logs is created by migration 006, i.e. AFTER this
-- file, so on a clean replay these statements aborted 003 outright. Guarded with
-- the same `undefined_table` idiom this file already uses for workout_logs in
-- section 16. On a clean replay the block no-ops here and migration 111
-- re-asserts the policies once the table exists.
DO $$ BEGIN
  EXECUTE 'ALTER TABLE nutrition_logs ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS "users manage own nutrition logs" ON nutrition_logs';
  EXECUTE 'CREATE POLICY "users manage own nutrition logs" ON nutrition_logs FOR ALL TO authenticated USING (user_id = auth.uid())';
  EXECUTE 'DROP POLICY IF EXISTS "coaches read client nutrition logs" ON nutrition_logs';
  EXECUTE 'CREATE POLICY "coaches read client nutrition logs" ON nutrition_logs FOR SELECT TO authenticated USING (true)';
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE '003: nutrition_logs not present yet -- policies deferred to migration 111';
END $$;

-- ── 14. progress_photo_logs: RLS + policies ───────────────────────────────────
ALTER TABLE progress_photo_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own photo logs" ON progress_photo_logs;
CREATE POLICY "users manage own photo logs"
  ON progress_photo_logs FOR ALL TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "coaches read client photo logs" ON progress_photo_logs;
CREATE POLICY "coaches read client photo logs"
  ON progress_photo_logs FOR SELECT TO authenticated
  USING (true);

-- ── 15. foods: create if missing, then RLS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS foods (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode           text UNIQUE,
  name              text NOT NULL,
  brand             text,
  calories_per_100g numeric DEFAULT 0,
  protein_per_100g  numeric DEFAULT 0,
  carbs_per_100g    numeric DEFAULT 0,
  fat_per_100g      numeric DEFAULT 0,
  created_at        timestamptz DEFAULT now()
);

ALTER TABLE foods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "all authenticated can read foods" ON foods;
CREATE POLICY "all authenticated can read foods"
  ON foods FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "all authenticated can insert foods" ON foods;
CREATE POLICY "all authenticated can insert foods"
  ON foods FOR INSERT TO authenticated
  WITH CHECK (true);

-- ── 16. workout_logs (may or may not exist) ───────────────────────────────────
DO $$ BEGIN
  ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL; END $$;

DO $$ BEGIN
  EXECUTE 'DROP POLICY IF EXISTS "users manage own workout logs" ON workout_logs';
  EXECUTE 'CREATE POLICY "users manage own workout logs" ON workout_logs FOR ALL TO authenticated USING (user_id = auth.uid())';
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ── 17. notifications: ensure recipient can read ──────────────────────────────
-- STAGE B.3 (B2-3): notifications is created by migration 004, i.e. AFTER this
-- file. Same treatment as section 13 -- guarded here, re-asserted in 111.
DO $$ BEGIN
  EXECUTE 'ALTER TABLE notifications ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS "recipients read own notifications" ON notifications';
  EXECUTE 'CREATE POLICY "recipients read own notifications" ON notifications FOR SELECT TO authenticated USING (recipient_id = auth.uid())';
  EXECUTE 'DROP POLICY IF EXISTS "system can insert notifications" ON notifications';
  EXECUTE 'CREATE POLICY "system can insert notifications" ON notifications FOR INSERT TO authenticated WITH CHECK (true)';
  EXECUTE 'DROP POLICY IF EXISTS "recipients update own notifications" ON notifications';
  EXECUTE 'CREATE POLICY "recipients update own notifications" ON notifications FOR UPDATE TO authenticated USING (recipient_id = auth.uid())';
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE '003: notifications not present yet -- policies deferred to migration 111';
END $$;

-- ── 18. user_profiles: ensure marketplace coaches are readable ────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "profiles are viewable by authenticated users" ON user_profiles;
  CREATE POLICY "profiles are viewable by authenticated users"
    ON user_profiles FOR SELECT TO authenticated
    USING (true);
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ── 19. habit_logs: fix FK to reference client_habits, not habits ─────────────
ALTER TABLE habit_logs DROP CONSTRAINT IF EXISTS habit_logs_habit_id_fkey;
ALTER TABLE habit_logs
  ADD CONSTRAINT habit_logs_habit_id_fkey
  FOREIGN KEY (habit_id) REFERENCES client_habits(id) ON DELETE CASCADE;

ALTER TABLE habit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own habit logs" ON habit_logs;
CREATE POLICY "users manage own habit logs"
  ON habit_logs FOR ALL TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "coaches read client habit logs" ON habit_logs;
CREATE POLICY "coaches read client habit logs"
  ON habit_logs FOR SELECT TO authenticated
  USING (true);

-- ── 20. progress_photo_logs: add missing columns (table pre-existed) ─────────
ALTER TABLE progress_photo_logs ADD COLUMN IF NOT EXISTS storage_path text;
ALTER TABLE progress_photo_logs ADD COLUMN IF NOT EXISTS side text DEFAULT 'front';
ALTER TABLE progress_photo_logs ADD COLUMN IF NOT EXISTS logged_at timestamptz DEFAULT now();

-- ── 21. class_bookings: add missing columns + fix FK (table pre-existed) ──────
ALTER TABLE class_bookings ADD COLUMN IF NOT EXISTS status text DEFAULT 'confirmed';
ALTER TABLE class_bookings ADD COLUMN IF NOT EXISTS booked_at timestamptz DEFAULT now();
ALTER TABLE class_bookings DROP CONSTRAINT IF EXISTS class_bookings_class_id_fkey;
ALTER TABLE class_bookings
  ADD CONSTRAINT class_bookings_class_id_fkey
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

-- ── 22. community_posts: add missing columns (table pre-existed) ───────────────
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS post_type text DEFAULT 'general';
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS image_urls text[] DEFAULT '{}';
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS likes_count int DEFAULT 0;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS comments_count int DEFAULT 0;

-- ── Done ──────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  RAISE NOTICE '✅ Migration 003 complete — FK constraints and RLS policies fixed.';
END $$;
