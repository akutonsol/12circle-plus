-- 118_security_sweep.sql
--
-- PHASE 1F — the sweep past the known P0s. Every baseline table, every policy,
-- every view. Findings and their status are written up in
-- docs/PHASE_1_SECURITY_AUDIT.md; this file is the remediation.
--
-- ── WHAT THE SWEEP FOUND (beyond D-01 / D-02 / D-03) ────────────────────────
--
--  F-01 [P1] public.coach_client_workout_stats is a SECURITY DEFINER view with
--            NO caller scoping. It groups by coach_id but returns every coach's
--            whole roster: client name, avatar, completion rate, last workout.
--            Verified live -- an unrelated account read another coach's client
--            "Jordan Test" at 100% completion. The app already filters
--            .eq('coach_id', coachId) client-side, which is presentation, not
--            authorization.
--
--  F-02 [P1] public.workouts still had no RLS (the third table in the Workstream
--            D list). Anon CRUD on a legacy content catalog. See Q-2 below.
--
--  F-03 [P1] notifications' INSERT policy is WITH CHECK (true): any signed-in
--            account could push an arbitrary title and body into any user's feed.
--            A phishing surface, and the table-layer twin of the
--            insert_notification() hole migration 116 closed at the RPC layer.
--
--  F-04 [P2] coach_availability carried TWO duplicate SELECT policies, both
--            USING (true) with no TO clause -- i.e. PUBLIC. Anon could read every
--            coach's slot times and booked/free status. (Workstream D's D-05.)
--
--  F-05 [P2] class_bookings' "coaches read bookings" is USING (true): every
--            signed-in account could see who booked which class.
--
--  F-06 [P2] Ten more policies carry no TO clause, so they apply to PUBLIC.
--            Their predicates are all auth.uid()-based, so anon matches nothing
--            today -- but this is precisely the class that produced F-04, and one
--            careless predicate away from mattering.
--
--  F-07 [P2] anon holds SELECT/INSERT/UPDATE/DELETE table grants across the
--            whole schema. RLS is currently the only thing between the published
--            anon key and every table; a table shipped with RLS off (which has
--            now happened three times) is immediately world-writable.
--
--  F-08 [P3] Nine SECURITY INVOKER functions still have a mutable search_path.
--            Lower risk than the definer case migration 116 fixed, but free.
--
-- ── WHAT WAS DELIBERATELY LEFT ALONE ────────────────────────────────────────
-- Roughly twenty USING (true) SELECT policies cover the social surface --
-- challenges, classes, community groups/posts/comments/reactions, events,
-- badges, foods, coach packages, coach reviews, accountability pods. Those are
-- shared content in a social fitness product and every feed depends on them.
-- They are catalogued in the audit doc as accepted, not as unfound.
--
-- ── Q-2: public.workouts ────────────────────────────────────────────────────
-- Dependency analysis, as instructed, before any retirement proposal:
--   rows on QA           0
--   readers/writers      none anywhere in apps/, supabase/functions/ or the API
--   referenced by        workout_logs.workout_id (FK)
--   shape                a static catalog: title, category, difficulty,
--                        coach_name, image_url, is_featured
-- It reads as a pre-programming-engine workout library, superseded by
-- program_workouts and workout_sessions.workout_snapshot. NOT deleted here.
-- It is made a read-only catalog so the anon-CRUD surface closes without
-- prejudging retirement, which stays a later-phase decision.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   ALTER TABLE public.workouts DISABLE ROW LEVEL SECURITY;
--   GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
--   -- plus re-create the pre-118 policies quoted inline below.

-- ---------------------------------------------------------------------------
-- F-01. Scope the coach stats view to its caller.
--
-- security_invoker stays off deliberately: the view reads workout_sessions and
-- user_profiles, both of which are RLS-protected, and as an invoker view it
-- would return nothing. Its safety is the WHERE clause, so the WHERE clause has
-- to carry the authorization -- which it now does.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.coach_client_workout_stats
WITH (security_invoker = off, security_barrier = true) AS
SELECT r.coach_id,
       r.client_id,
       (p.first_name || ' '::text) || p.last_name AS client_name,
       p.avatar_url,
       count(DISTINCT ws.id) FILTER (WHERE ws.status = 'completed')   AS total_completed,
       count(DISTINCT ws.id) FILTER (WHERE ws.status = 'in_progress') AS total_in_progress,
       count(DISTINCT ws.id) FILTER (WHERE ws.status = 'abandoned')   AS total_abandoned,
       round(100.0 * count(DISTINCT ws.id) FILTER (WHERE ws.status = 'completed')::numeric
             / NULLIF(count(DISTINCT ws.id), 0)::numeric, 1)          AS completion_rate_pct,
       max(ws.completed_at)                                           AS last_workout_at,
       count(DISTINCT ws.id) FILTER (
         WHERE ws.status = 'completed'
           AND ws.completed_at >= (now() - '7 days'::interval))       AS workouts_this_week
  FROM public.coach_client_relationships r
  JOIN public.user_profiles p ON p.id = r.client_id
  LEFT JOIN public.workout_sessions ws ON ws.user_id = r.client_id
 WHERE r.status = 'active'
   -- THE authorization line. Removing it re-opens F-01.
   AND (r.coach_id = (SELECT auth.uid())
        OR r.client_id = (SELECT auth.uid())
        OR public.is_admin())
 GROUP BY r.coach_id, r.client_id, p.first_name, p.last_name, p.avatar_url;

-- Supabase's ALTER DEFAULT PRIVILEGES grants ALL on a newly created view to
-- authenticated, and a writable security_invoker = off view is a straight RLS
-- bypass on its base tables (migration 112). Revoke from authenticated too, not
-- just anon, so this holds on a clean rebuild where the view is created fresh.
REVOKE ALL ON public.coach_client_workout_stats FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.coach_client_workout_stats TO authenticated;

COMMENT ON VIEW public.coach_client_workout_stats IS
  'Per-client training compliance for the CALLING coach. Runs security_invoker '
  '= off, so the WHERE clause is the only authorization there is -- never remove '
  'the auth.uid() predicate (migration 118, finding F-01).';

-- ---------------------------------------------------------------------------
-- F-02. public.workouts -- read-only catalog. See Q-2 above.
-- ---------------------------------------------------------------------------
ALTER TABLE public.workouts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.workouts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.workouts TO authenticated;

DROP POLICY IF EXISTS "read workout catalog" ON public.workouts;
CREATE POLICY "read workout catalog"
  ON public.workouts FOR SELECT TO authenticated
  USING (true);

COMMENT ON TABLE public.workouts IS
  'LEGACY workout catalog -- 0 rows, no reader or writer anywhere in the '
  'codebase, superseded by program_workouts and workout_sessions.'
  'workout_snapshot. Read-only to members and writable only by service_role '
  '(migration 118). Retirement is deferred: workout_logs still carries an FK to '
  'it, so dropping it is a data-model decision, not a security one.';

-- ---------------------------------------------------------------------------
-- F-03. notifications -- a notification must come from someone you know.
--
--   Prior: CREATE POLICY "system can insert notifications"
--            ON notifications FOR INSERT TO authenticated WITH CHECK (true);
--
-- The DB triggers (migration 004) route through insert_notification(), which is
-- SECURITY DEFINER and therefore unaffected. The client-side inserts that remain
-- -- coach request / approve / decline / cancel, program assigned, session
-- booked / cancelled, video response, workout complete -- are all between two
-- parties who already hold a relationship, a conversation or a booked call, and
-- the predicate below is drawn from exactly that set.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (SELECT auth.uid()) IS NULL
      OR recipient = (SELECT auth.uid())
      OR EXISTS (SELECT 1 FROM public.coach_client_relationships r
                  WHERE (r.coach_id  = (SELECT auth.uid()) AND r.client_id = recipient)
                     OR (r.client_id = (SELECT auth.uid()) AND r.coach_id  = recipient))
      OR public.shares_conversation_with(recipient)
      OR EXISTS (SELECT 1 FROM public.coaching_calls c
                  WHERE (c.coach_id  = (SELECT auth.uid()) AND c.client_id = recipient)
                     OR (c.client_id = (SELECT auth.uid()) AND c.coach_id  = recipient))
      OR EXISTS (SELECT 1 FROM public.coach_team_members t
                  WHERE (t.coach_id = (SELECT auth.uid()) AND t.member_id = recipient)
                     OR (t.member_id = (SELECT auth.uid()) AND t.coach_id = recipient));
$$;

REVOKE ALL ON FUNCTION public.may_notify(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.may_notify(uuid) TO authenticated;

COMMENT ON FUNCTION public.may_notify(uuid) IS
  'True when the caller has an existing relationship with the recipient -- coach '
  'link (any status), conversation, booked call, or team membership. Gates '
  'client-side notification inserts so the feed cannot be used to deliver '
  'arbitrary text to a stranger (migration 118, finding F-03).';

DROP POLICY IF EXISTS "system can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "notify a known counterparty" ON public.notifications;
CREATE POLICY "notify a known counterparty"
  ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (public.may_notify(recipient_id));

-- ---------------------------------------------------------------------------
-- F-04. coach_availability -- two duplicate PUBLIC USING(true) SELECT policies.
--
--   Prior: "client_read_availability"   FOR SELECT USING (true)   -- no TO
--          "Clients can read availability" FOR SELECT USING (true) -- no TO
--
-- Slot times stay visible to every signed-in member (that is the booking
-- screen), but not to the internet.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "client_read_availability"       ON public.coach_availability;
DROP POLICY IF EXISTS "Clients can read availability"  ON public.coach_availability;
DROP POLICY IF EXISTS "members read availability" ON public.coach_availability;
CREATE POLICY "members read availability"
  ON public.coach_availability FOR SELECT TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- F-05. class_bookings -- who booked what is not everyone's business.
--
--   Prior: "coaches read bookings" FOR SELECT TO authenticated USING (true)
--
-- Restored to what the name always claimed: the owner, and the coach running
-- the class.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "coaches read bookings" ON public.class_bookings;
CREATE POLICY "coaches read bookings"
  ON public.class_bookings FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (SELECT 1 FROM public.classes c
                WHERE c.id = class_bookings.class_id
                  AND c.coach_id = (SELECT auth.uid()))
    OR public.is_admin()
  );

-- ---------------------------------------------------------------------------
-- F-06. Re-issue every remaining no-TO policy as TO authenticated.
--
-- Same predicate, same name; only the role clause changes. Done by rewriting
-- each from the catalog so nothing is transcribed by hand and nothing is missed.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  p record;
  n int := 0;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname, cmd, qual, with_check, permissive
      FROM pg_policies
     WHERE schemaname = 'public'
       AND roles::text = '{public}'
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
    EXECUTE format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO authenticated %s %s',
      p.policyname, p.schemaname, p.tablename,
      CASE WHEN p.permissive = 'PERMISSIVE' THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
      p.cmd,
      CASE WHEN p.qual       IS NULL THEN '' ELSE 'USING (' || p.qual || ')' END,
      CASE WHEN p.with_check IS NULL THEN '' ELSE 'WITH CHECK (' || p.with_check || ')' END);
    n := n + 1;
    RAISE NOTICE '118: %.% policy "%" is now TO authenticated', p.schemaname, p.tablename, p.policyname;
  END LOOP;
  RAISE NOTICE '118: re-scoped % PUBLIC policies', n;
END $$;

-- ---------------------------------------------------------------------------
-- F-07. anon holds no table privilege anywhere.
--
-- The anon key ships inside the published client build, so "anon" is the open
-- internet. Nothing in this product is served to a signed-out caller through
-- PostgREST: registration and login go through /auth/v1, and every server-side
-- job authenticates as service_role. There is therefore no anon surface to
-- preserve.
--
-- This is defence in depth, not the primary control -- RLS is. It exists because
-- the primary control has now failed three times in the same way (a table
-- created without ENABLE ROW LEVEL SECURITY), and a missing GRANT fails closed
-- where a missing policy failed open.
-- ---------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

-- ---------------------------------------------------------------------------
-- F-08. Pin search_path on the remaining SECURITY INVOKER functions.
-- Migration 116 covered the definer set; this closes the rest.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  f record;
  n int := 0;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public'
       AND NOT EXISTS (
         SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', f.sig);
    n := n + 1;
  END LOOP;
  RAISE NOTICE '118: pinned search_path on % remaining functions', n;
END $$;

-- ---------------------------------------------------------------------------
-- Standing guard: no table in this schema may sit without RLS again.
--
-- Reports rather than blocks -- a migration that legitimately creates a staging
-- table should not be unable to run -- but it puts the fact in the migration
-- output, where the previous three misses would have been caught.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_open text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_open
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;
  IF v_open IS NULL THEN
    RAISE NOTICE '118: every table in schema public has RLS enabled';
  ELSE
    RAISE WARNING '118: tables WITHOUT row level security: %', v_open;
  END IF;
END $$;
