-- 000_baseline_preexisting_tables.sql
--
-- The tables that PREDATE the tracked migration sequence.
--
-- ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
-- Migrations 001-110 were written against a database that already existed. They
-- patch these tables (ALTER TABLE ... ADD COLUMN IF NOT EXISTS) and reference
-- them in foreign keys, but NOTHING in the sequence ever creates them. The very
-- first executable statement of 001 is
--
--     ALTER TABLE challenges ADD COLUMN IF NOT EXISTS coach_id uuid
--       REFERENCES user_profiles(id);
--
-- so a replay against an empty database dies on line 7 of 001. No prefix of
-- 001-110 can build this schema from nothing. That is the root cause of the
-- Stage A finding that QA "does not correspond to a coherent migration prefix".
--
-- ── PROVENANCE ──────────────────────────────────────────────────────────────
-- Every column, type, default, nullability and constraint below was extracted
-- from a READ-ONLY `supabase db dump --linked --schema public` of the QA project
-- (12Circle QA, eyqtldjqpgpljlqvpowh). Nothing here is invented.
--
-- The column list is the dump's column list MINUS every column that some
-- migration in 001-110 adds, so this file states only what genuinely predates
-- the sequence and leaves the rest to the migrations that own them. Replaying
-- 001-110 on top of this reconstructs the full tables.
--
-- Deliberately NOT included, because migrations already own them:
--   * RLS enablement and policies      (003, 015, 100, 102, ...)
--   * indexes                           (various)
--   * triggers and functions            (004, 044, 109, ...)
--   * every column any migration adds
--
-- ── pgcrypto ────────────────────────────────────────────────────────────────
-- `coach_invites`, `event_registrations` and `coach_team_invites` use
-- encode(gen_random_bytes(16),'hex') as a column DEFAULT. gen_random_bytes()
-- comes from pgcrypto, which no migration ever enables -- the sequence silently
-- relies on Supabase having it on by default. Declared here so the dependency
-- is explicit and a replay does not depend on project defaults.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Migrations 001 and 002 call gen_random_bytes() UNQUALIFIED in column DEFAULTs.
-- pgcrypto lives in the `extensions` schema and the migration role's search_path
-- does not include it, so each of those files sets its own search_path. See the
-- note at the top of 001. Nothing is set here: the CLI applies every migration
-- over its own connection, so a SET or an ALTER DATABASE here would not reach
-- them (both were tried against QA and 001 still failed).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- user_profiles: 28 pre-existing columns (+48 added by migrations 001-110)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    "id" "uuid" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "avatar_url" "text",
    "role" "text" DEFAULT 'client'::"text",
    "fitness_goal" "text",
    "height_cm" numeric,
    "weight_kg" numeric,
    "date_of_birth" "date",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "activity_level" "text",
    "training_days_per_week" integer,
    "training_location" "text",
    "nutrition_goal" "text",
    "protein_confidence" "text",
    "biggest_challenges" "text",
    "weight_goal_kg" numeric DEFAULT 0,
    "assigned_coach_id" "uuid",
    "bio" "text",
    "age" integer,
    "current_weight_kg" numeric,
    "goal_weight_kg" numeric,
    "fitness_level" "text",
    "gender" "text",
    "ai_client_summary" "text" DEFAULT ''::"text"
);

-- workouts: 10 pre-existing columns
CREATE TABLE IF NOT EXISTS public.workouts (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "category" "text",
    "difficulty" "text",
    "estimated_duration" integer,
    "coach_name" "text",
    "image_url" "text",
    "is_featured" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);

-- workout_logs: 9 pre-existing columns
CREATE TABLE IF NOT EXISTS public.workout_logs (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "workout_id" "uuid",
    "workout_title" "text",
    "duration_minutes" integer,
    "calories_burned" integer,
    "category" "text",
    "completed_at" timestamp with time zone DEFAULT "now"(),
    "notes" "text"
);

-- coach_client_relationships: 9 pre-existing columns (+10 added by migrations 001-110)
CREATE TABLE IF NOT EXISTS public.coach_client_relationships (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "coach_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "initiated_by" "text" DEFAULT 'client'::"text" NOT NULL,
    "invite_email" "text",
    "invite_token" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "activated_at" timestamp with time zone
);

-- conversations: 6 pre-existing columns
CREATE TABLE IF NOT EXISTS public.conversations (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "participant_1" "uuid",
    "participant_2" "uuid",
    "last_message" "text",
    "last_message_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);

-- messages: 6 pre-existing columns
CREATE TABLE IF NOT EXISTS public.messages (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid",
    "sender_id" "uuid",
    "content" "text" NOT NULL,
    "is_read" boolean DEFAULT false,
    "sent_at" timestamp with time zone DEFAULT "now"()
);

-- weekly_checkins: 15 pre-existing columns (+8 added by migrations 001-110)
CREATE TABLE IF NOT EXISTS public.weekly_checkins (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "week_number" integer NOT NULL,
    "week_start_date" "date" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "mood" integer,
    "energy" integer,
    "sleep_hours_avg" numeric,
    "overall_score" numeric,
    "submitted_at" timestamp with time zone,
    "feedback_message" "text",
    "feedback_recommendations" "text"[],
    "reviewed_at" timestamp with time zone,
    "coach_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

-- weight_logs: 5 pre-existing columns
CREATE TABLE IF NOT EXISTS public.weight_logs (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "weight_kg" numeric(5,2) NOT NULL,
    "logged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "note" "text"
);

-- body_measurements: 9 pre-existing columns
CREATE TABLE IF NOT EXISTS public.body_measurements (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "logged_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "chest_cm" numeric(5,1),
    "waist_cm" numeric(5,1),
    "hips_cm" numeric(5,1),
    "arms_cm" numeric(5,1),
    "thighs_cm" numeric(5,1),
    "note" "text"
);

-- progress_photo_logs: 6 pre-existing columns (+3 added by migrations 001-110)
CREATE TABLE IF NOT EXISTS public.progress_photo_logs (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "front_path" "text",
    "side_path" "text",
    "back_path" "text",
    "note" "text"
);

-- challenges: 8 pre-existing columns (+8 added by migrations 001-110)
CREATE TABLE IF NOT EXISTS public.challenges (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "challenge_type" "text",
    "target_unit" "text",
    "reward_points" integer DEFAULT 0,
    "image_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);

-- ---------------------------------------------------------------------------
-- Primary keys, unique constraints and foreign keys, verbatim from the QA dump.
--
-- Note user_profiles_id_fkey: user_profiles.id REFERENCES auth.users(id) ON
-- DELETE CASCADE. A profile cannot exist without its auth user -- which is why
-- the seed files must create auth.users rows at their pinned UUIDs.
--
-- challenges_coach_id_fkey and weekly_checkins_coach_id_fkey are deliberately
-- NOT here: both name a coach_id column that migration 001 adds, and 001 adds it
-- with its own inline REFERENCES clause. Declaring them here would fail on a
-- column that does not exist yet.
-- ---------------------------------------------------------------------------

ALTER TABLE ONLY public.body_measurements ADD CONSTRAINT "body_measurements_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.challenges ADD CONSTRAINT "challenges_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.coach_client_relationships ADD CONSTRAINT "coach_client_relationships_coach_id_client_id_key" UNIQUE ("coach_id", "client_id");
ALTER TABLE ONLY public.coach_client_relationships ADD CONSTRAINT "coach_client_relationships_invite_token_key" UNIQUE ("invite_token");
ALTER TABLE ONLY public.coach_client_relationships ADD CONSTRAINT "coach_client_relationships_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.conversations ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.messages ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.progress_photo_logs ADD CONSTRAINT "progress_photo_logs_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.user_profiles ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.weekly_checkins ADD CONSTRAINT "weekly_checkins_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.weekly_checkins ADD CONSTRAINT "weekly_checkins_user_week_unique" UNIQUE ("user_id", "week_start_date");
ALTER TABLE ONLY public.weight_logs ADD CONSTRAINT "weight_logs_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.workout_logs ADD CONSTRAINT "workout_logs_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.workouts ADD CONSTRAINT "workouts_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY public.body_measurements ADD CONSTRAINT "body_measurements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.coach_client_relationships ADD CONSTRAINT "coach_client_relationships_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.coach_client_relationships ADD CONSTRAINT "coach_client_relationships_coach_id_fkey" FOREIGN KEY ("coach_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.conversations ADD CONSTRAINT "conversations_participant_1_fkey" FOREIGN KEY ("participant_1") REFERENCES "auth"."users"("id");
ALTER TABLE ONLY public.conversations ADD CONSTRAINT "conversations_participant_2_fkey" FOREIGN KEY ("participant_2") REFERENCES "auth"."users"("id");
ALTER TABLE ONLY public.messages ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.messages ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id");
ALTER TABLE ONLY public.progress_photo_logs ADD CONSTRAINT "progress_photo_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.user_profiles ADD CONSTRAINT "user_profiles_assigned_coach_id_fkey" FOREIGN KEY ("assigned_coach_id") REFERENCES "auth"."users"("id");
ALTER TABLE ONLY public.user_profiles ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.weekly_checkins ADD CONSTRAINT "weekly_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.weight_logs ADD CONSTRAINT "weight_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.workout_logs ADD CONSTRAINT "workout_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY public.workout_logs ADD CONSTRAINT "workout_logs_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("id");
