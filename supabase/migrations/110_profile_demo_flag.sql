-- 110_profile_demo_flag.sql
--
-- PHASE 4 of the user_profiles hardening -- the community half of what
-- migration 102 breaks.
--
-- ── THE PROBLEM ────────────────────────────────────────────────────────────
-- The Members tab (community_screen -> liveMembersProvider) listed everyone on
-- the platform by querying user_profiles directly, and hid the five seeded
-- marketplace coaches by matching on their address:
--
--     .from('user_profiles')
--     .select('id, first_name, last_name, role, avatar_url, created_at, email')
--     .not('email', 'like', '%@marketplace.test')
--
-- Migration 102 makes that query return the caller's own row and nothing else,
-- so member discovery goes empty. The obvious repair -- adding `email` to
-- public_profiles -- would publish every user's address to every signed-in
-- account, which is a worse hole than the one 102 closes. Whether an account is
-- a demo fixture is a property of the account; it is not a fact about its email
-- address, and it should not require reading one.
--
-- ── THE FIX ────────────────────────────────────────────────────────────────
-- An explicit, non-sensitive `is_demo` flag on user_profiles, projected through
-- public_profiles so the app can filter on it. No existing column carried this
-- meaning: `role` is client/coach/vendor/admin, `visibility` exists only on
-- custom_exercises, and nothing else in the schema distinguishes a fixture
-- account. This is the smallest addition that does.
--
-- The email pattern survives only as a ONE-TIME backfill here. New demo
-- fixtures are expected to set is_demo = true explicitly at seed time rather
-- than encode their status in an address.

-- ---------------------------------------------------------------------------
-- 1. The flag.
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.user_profiles.is_demo IS
  'Seeded demo / test fixture account. Excluded from community member '
  'discovery. Non-sensitive -- deliberately projected through public_profiles '
  'so the app can filter on it without reading email.';

-- user_profiles predates the tracked migrations, so created_at is expected to
-- exist already; this is a no-op there and keeps the file replayable against a
-- bare schema.
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- ---------------------------------------------------------------------------
-- 2. One-time backfill of the accounts the app used to hide by email pattern.
--    Matches the exact set the old `.not('email','like','%@marketplace.test')`
--    filter excluded -- sarah/marcus/priya/derek/natasha@marketplace.test from
--    supabase/seeds/full_test_data.sql -- so member discovery returns the same
--    people before and after. Idempotent; never clears a flag someone set.
-- ---------------------------------------------------------------------------
UPDATE public.user_profiles
   SET is_demo = true
 WHERE lower(email) LIKE '%@marketplace.test'
   AND is_demo IS DISTINCT FROM true;

-- Partial index: the flag is true for a handful of rows, and every query is
-- `is_demo = false`, so this stays small and is only consulted for the
-- anti-join side.
CREATE INDEX IF NOT EXISTS idx_user_profiles_is_demo
  ON public.user_profiles (is_demo) WHERE is_demo;

-- ---------------------------------------------------------------------------
-- 3. Re-declare public_profiles with the two columns member discovery needs.
--
--    created_at -> the list is ordered newest-first.
--    is_demo    -> the fixture filter, replacing the email match.
--
--    Both are appended AFTER the existing column list: CREATE OR REPLACE VIEW
--    may add trailing columns but may not reorder, rename or drop them.
--
--    Column list is otherwise byte-identical to migration 101. Still NO email,
--    phone, date_of_birth, medical_conditions, parq_answers,
--    injury_description, risk_score or Stripe identifier.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.public_profiles
WITH (security_invoker = off) AS
SELECT
    -- identity (used for display names / avatars anywhere a user is shown)
    id,
    first_name,
    last_name,
    avatar_url,
    role,
    -- public coach-marketplace fields (NULL for non-coaches)
    coach_title,
    coach_bio,
    bio,
    tagline,
    specialties,
    certifications,
    years_experience,
    pricing_monthly,
    pricing_description,
    rating_avg,
    review_count,
    transformation_photo_urls,
    is_accepting_clients,
    max_clients,
    -- appended by migration 110 (order matters -- see above)
    created_at,
    is_demo
FROM public.user_profiles;

COMMENT ON VIEW public.public_profiles IS
  'Non-sensitive projection of user_profiles for display names, community '
  'member discovery and the coach marketplace. Never add medical, contact, '
  'billing or intake columns to this view -- in particular, never add email.';

-- Grants survive CREATE OR REPLACE VIEW; re-issued so the file is safe to
-- replay on a database where the view was created some other way.
REVOKE ALL ON public.public_profiles FROM PUBLIC, anon;
GRANT SELECT ON public.public_profiles TO authenticated;
