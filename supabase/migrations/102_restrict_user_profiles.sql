-- 102_restrict_user_profiles.sql
--
-- PHASE 3 of the user_profiles hardening. THIS IS THE MIGRATION THAT ACTUALLY
-- CLOSES THE HOLE -- and the one that can break things.
--
-- ############################################################################
-- ## DO NOT APPLY THIS UNTIL ALL THREE ARE TRUE:                            ##
-- ##   1. Migration 101 (public_profiles view) is applied,                  ##
-- ##   2. Migration 110 (is_demo flag + public_profiles refresh) is applied, ##
-- ##      AND                                                                ##
-- ##   3. Every beta tester is running an app build that reads display       ##
-- ##      names from public_profiles / conversation_participant_profiles     ##
-- ##      instead of user_profiles.                                          ##
-- ##                                                                         ##
-- ## Beta testers have the OLD binary installed on their phones. Applying    ##
-- ## this before they update breaks the community feed, class list, pods,    ##
-- ## coach reviews, check-ins and the message list for them IMMEDIATELY --    ##
-- ## server-side changes do not wait for an app update.                      ##
-- ############################################################################
--
-- After this runs, user_profiles rows are readable only by:
--   * the owner, and
--   * a coach with an ACTIVE coach_client_relationship to that user, and
--   * that user's team lead / event host (see the two functions below)
-- which matches how the sensitive columns are actually consumed: the owner via
-- personal_info_screen / intake, and the coach via client_detail_screen.
--
-- ── WHAT THIS MIGRATION DELIBERATELY DOES NOT DO ───────────────────────────
-- It does NOT widen the base-table policy for messaging or community. Both of
-- those screens need only a display name, and granting them a row on
-- user_profiles would hand them medical_conditions, parq_answers,
-- injury_description, date_of_birth, phone, email, risk_score and the Stripe
-- identifiers along with it. Instead each gets a narrow, column-limited path:
--
--   * messaging  -> public.conversation_participant_profiles (defined below):
--                   5 display columns, rows scoped to people the caller
--                   actually shares a conversation with.
--   * community  -> public.public_profiles (migration 101 / 110): display
--                   columns only, demo accounts filtered via is_demo rather
--                   than by reading email.
--
-- Two access paths read profile columns that are deliberately NOT in the
-- public_profiles view (email), so they cannot be served by the view and need
-- their own policies instead:
--   * a head coach viewing their own team roster (coach_business_screen)
--   * an event host viewing their attendee list (vendor_portal_screen)
-- Both are SECURITY DEFINER so the lookup is not itself filtered by RLS on the
-- table being consulted, which would otherwise return no rows.

CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.coach_team_members t
    WHERE t.coach_id = auth.uid()
      AND t.member_id = target_user
  );
$$;

CREATE OR REPLACE FUNCTION public.hosts_event_for(target_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.event_registrations r
    JOIN public.events e ON e.id = r.event_id
    WHERE e.vendor_id = auth.uid()
      AND r.user_id = target_user
  );
$$;

REVOKE ALL ON FUNCTION public.is_team_lead_of(uuid)  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hosts_event_for(uuid)  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_team_lead_of(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hosts_event_for(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Messaging: conversation-participant authorization path.
--
-- The message list has to render the OTHER participant's name and avatar. That
-- is the whole requirement -- no contact, medical, intake or billing column is
-- involved -- so it is served by a narrow view rather than by a row grant on
-- user_profiles.
--
-- shares_conversation_with() is SECURITY DEFINER because public.conversations
-- carries its own RLS ("participants can read conversations", migration 003).
-- Evaluated as the caller from inside a view over user_profiles it would either
-- recurse or return nothing; as definer it resolves the membership fact only,
-- and returns a boolean -- it never projects a conversation row.
--
-- It is symmetric and self-contained: true only when the caller and the target
-- occupy the two participant slots of the same conversation. For an anonymous
-- caller auth.uid() is NULL, every comparison is NULL, EXISTS is false.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.shares_conversation_with(target_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversations c
    WHERE (c.participant_1 = auth.uid() AND c.participant_2 = target_user)
       OR (c.participant_2 = auth.uid() AND c.participant_1 = target_user)
  );
$$;

REVOKE ALL ON FUNCTION public.shares_conversation_with(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shares_conversation_with(uuid) TO authenticated;

COMMENT ON FUNCTION public.shares_conversation_with(uuid) IS
  'True when the caller and target_user are the two participants of the same '
  'public.conversations row. Membership predicate only -- it exposes no '
  'conversation or message content.';

-- Display-only projection, row-scoped to actual conversation partners.
--
--   security_invoker = off  -> reads user_profiles as the view owner, so it is
--                              unaffected by the row restriction added below.
--                              Its safety is the five-column list plus the WHERE.
--   security_barrier = true -> stops a caller-supplied filter (e.g. a PostgREST
--                              `first_name=eq.X` predicate) from being evaluated
--                              ahead of the membership check and used as an
--                              oracle over profiles the caller cannot see.
CREATE OR REPLACE VIEW public.conversation_participant_profiles
WITH (security_invoker = off, security_barrier = true) AS
SELECT
    p.id,
    p.first_name,
    p.last_name,
    p.role,
    p.avatar_url
FROM public.user_profiles p
WHERE public.shares_conversation_with(p.id);

COMMENT ON VIEW public.conversation_participant_profiles IS
  'Display name / avatar / role for the people the caller shares a conversation '
  'with. Never add contact, medical, intake or billing columns to this view, and '
  'never drop the shares_conversation_with() predicate.';

-- Signed-in users only. Deliberately NOT granted to anon: the anon key is
-- published in this public repo.
REVOKE ALL ON public.conversation_participant_profiles FROM PUBLIC, anon;
GRANT SELECT ON public.conversation_participant_profiles TO authenticated;

-- Two overlapping blanket policies exist on the live database; both grant
-- `USING (true)` to every authenticated user. Names verified against the live
-- schema dump -- a typo here would silently no-op and leave the hole open.
DROP POLICY IF EXISTS "authenticated_read_profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "profiles are viewable by authenticated users" ON public.user_profiles;

CREATE POLICY "own profile or active coach reads profile"
  ON public.user_profiles FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR public.is_active_coach_of(id)
    OR public.is_team_lead_of(id)
    OR public.hosts_event_for(id)
  );

-- Rollback (paste into the SQL editor if the app misbehaves after applying):
--
--   DROP POLICY IF EXISTS "own profile or active coach reads profile" ON public.user_profiles;
--   CREATE POLICY "authenticated_read_profiles"
--     ON public.user_profiles FOR SELECT TO authenticated USING (true);
