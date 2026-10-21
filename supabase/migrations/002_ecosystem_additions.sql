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

-- ============================================================
-- Migration 002: Additional ecosystem tables
-- Run in Supabase SQL Editor after 001_full_ecosystem.sql
-- ============================================================

-- ── AI Conversations log ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_conversations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  mode          text NOT NULL DEFAULT 'general',
  user_message  text NOT NULL,
  ai_response   text NOT NULL,
  created_at    timestamptz DEFAULT now()
);
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own AI conversations"
  ON ai_conversations FOR ALL USING (user_id = auth.uid());

-- ── Coach Availability Slots ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coach_availability (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id        uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  slot_time       timestamptz NOT NULL,
  duration_minutes int NOT NULL DEFAULT 30,
  type            text NOT NULL DEFAULT 'check_in', -- check_in | consultation | nutrition_review
  is_booked       boolean DEFAULT false,
  created_at      timestamptz DEFAULT now()
);
ALTER TABLE coach_availability ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Coaches manage own availability"
  ON coach_availability FOR ALL USING (coach_id = auth.uid());
CREATE POLICY "Clients can read availability"
  ON coach_availability FOR SELECT USING (true);

-- ── Coaching Calls (bookings) ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coaching_calls (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id             uuid NOT NULL REFERENCES user_profiles(id),
  client_id            uuid NOT NULL REFERENCES user_profiles(id),
  availability_slot_id uuid REFERENCES coach_availability(id),
  scheduled_at         timestamptz NOT NULL,
  duration_minutes     int NOT NULL DEFAULT 30,
  call_type            text NOT NULL DEFAULT 'check_in',
  status               text NOT NULL DEFAULT 'scheduled', -- scheduled | completed | cancelled | no_show
  notes                text,
  meeting_link         text,
  created_at           timestamptz DEFAULT now()
);
ALTER TABLE coaching_calls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Coach and client can see calls"
  ON coaching_calls FOR ALL
  USING (coach_id = auth.uid() OR client_id = auth.uid());

-- ── Coach Video Responses ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coach_video_responses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id    uuid NOT NULL REFERENCES user_profiles(id),
  client_id   uuid NOT NULL REFERENCES user_profiles(id),
  checkin_id  uuid REFERENCES weekly_checkins(id),
  video_url   text,
  notes       text,
  viewed_at   timestamptz,
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE coach_video_responses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Coach can insert video responses"
  ON coach_video_responses FOR INSERT WITH CHECK (coach_id = auth.uid());
CREATE POLICY "Coach and client can see video responses"
  ON coach_video_responses FOR SELECT
  USING (coach_id = auth.uid() OR client_id = auth.uid());

-- ── Accountability Pods ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS accountability_pods (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id          uuid REFERENCES user_profiles(id),
  name              text NOT NULL,
  description       text,
  max_members       int NOT NULL DEFAULT 8,
  member_count      int NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'open', -- open | full | closed
  meeting_frequency text DEFAULT 'Daily check-ins',
  created_at        timestamptz DEFAULT now()
);
ALTER TABLE accountability_pods ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read pods"
  ON accountability_pods FOR SELECT USING (true);
CREATE POLICY "Coaches manage pods"
  ON accountability_pods FOR ALL USING (coach_id = auth.uid());

CREATE TABLE IF NOT EXISTS accountability_pod_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pod_id     uuid NOT NULL REFERENCES accountability_pods(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  joined_at  timestamptz DEFAULT now(),
  UNIQUE (pod_id, user_id)
);
ALTER TABLE accountability_pod_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Members can see pod membership"
  ON accountability_pod_members FOR SELECT USING (true);
CREATE POLICY "Users can join pods"
  ON accountability_pod_members FOR INSERT WITH CHECK (user_id = auth.uid());

-- Update member_count trigger for pods
CREATE OR REPLACE FUNCTION update_pod_member_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE accountability_pods SET member_count = member_count + 1 WHERE id = NEW.pod_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE accountability_pods SET member_count = GREATEST(0, member_count - 1) WHERE id = OLD.pod_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
DROP TRIGGER IF EXISTS trg_pod_member_count ON accountability_pod_members;
CREATE TRIGGER trg_pod_member_count
  AFTER INSERT OR DELETE ON accountability_pod_members
  FOR EACH ROW EXECUTE FUNCTION update_pod_member_count();

-- ── Coach Team Members (UC36) ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coach_team_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id   uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  member_id  uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role       text NOT NULL DEFAULT 'assistant_coach',
  added_at   timestamptz DEFAULT now(),
  UNIQUE (coach_id, member_id)
);
ALTER TABLE coach_team_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Head coach manages team"
  ON coach_team_members FOR ALL USING (coach_id = auth.uid());

CREATE TABLE IF NOT EXISTS coach_team_invites (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id   uuid NOT NULL REFERENCES user_profiles(id),
  email      text NOT NULL,
  role       text NOT NULL DEFAULT 'assistant_coach',
  token      text DEFAULT encode(gen_random_bytes(16), 'hex'),
  accepted   boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE coach_team_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Coach manages own invites"
  ON coach_team_invites FOR ALL USING (coach_id = auth.uid());

-- ── User profile additions ────────────────────────────────────────────────────
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS tagline text;

-- ── Enable Realtime on new tables ────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE ai_conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE coaching_calls;
ALTER PUBLICATION supabase_realtime ADD TABLE accountability_pod_members;
