-- 132_team_membership_lifecycle.sql
--
-- V5 SECURITY FOUNDATION — WAVE 1.
--
-- Migration number 132 assigned at wave entry per docs/MASTER_REMEDIATION_WAVES.md
-- section 0.2 ("132+ ... assigned at wave entry, never before").  Scope and
-- semantics ruled by the owner 2026-09-27 (D1(i)/D1(ii)/D1(iii)), recorded
-- verbatim in docs/adr/ADR-W1-001-team-membership-lifecycle.md and authorized in
-- docs/V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md.
--
-- ===========================================================================
-- THE FINDINGS THIS CLOSES
-- ===========================================================================
--
--   QAX-SEC-08  P0  `coach_team_members` carried
--                   `FOR ALL USING (coach_id = auth.uid())` with NO `WITH CHECK`.
--                   Postgres reuses USING as the INSERT check, so ANY
--                   authenticated account could insert a row naming itself
--                   `coach_id` and any victim `member_id` -- with no role check of
--                   any kind (`has_role_check = false`).  `is_team_lead_of()` then
--                   treated that row as an authorization fact, and the
--                   `user_profiles` SELECT policy granted the team lead the
--                   ENTIRE profile row: `parq_answers` (PAR-Q medical history),
--                   `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`,
--                   `membership_tier`, Stripe flags.
--
--   F-03b       P1  `may_notify()` consumed the same forgeable row, so the
--                   `notifications` INSERT policy admitted attacker-controlled
--                   content into an arbitrary victim's feed.  **This migration
--                   closes only the team-membership arm.**  `may_notify()` also
--                   trusts `coach_client_relationships` at ANY status; that arm
--                   is a separate residual and is NOT addressed here.
--
-- Neither finding may be recorded closed on the strength of this file.  Closure
-- requires the live verification contract in the authorization document.
--
-- ===========================================================================
-- WHAT THE OWNER DECIDED (verbatim extracts)
-- ===========================================================================
--
--   D1(i)   NO.  "Membership must not be created unilaterally by a team lead.
--           Membership must originate through the invite/consent flow and only
--           become an active membership after the required acceptance/consent
--           step."
--
--   D1(ii)  YES.  States: invited | active | suspended | revoked.
--           "Only ACTIVE membership may satisfy team-lead authorization checks."
--           "The authorization helpers is_team_lead_of() and may_notify() must
--           evaluate the lifecycle state rather than merely the existence of a
--           row."
--
--   D1(iii) "minimum member information required for legitimate team-management
--           functions."  "PAR-Q, medical conditions, and other
--           health-sensitive/PHI information are NOT accessible through
--           team-lead membership authorization."  "Do not expose the full
--           user_profiles row to team leads."
--
-- ===========================================================================
-- WHY THERE IS NO UPDATE POLICY -- read before adding one
-- ===========================================================================
--
-- The `invited -> active` transition IS the acceptance step, and no acceptance
-- mechanism exists anywhere in this system: zero triggers on either team table,
-- zero functions referencing `coach_team_invites`, and zero writers of
-- `coach_team_members` in the app or edge functions (the only reference is a
-- SELECT at coach_business_screen.dart:66).  Granting an RLS UPDATE path now
-- would create an ungoverned activation route and defeat D1(i).  Removal stays
-- available to the lead through DELETE, which is the pre-existing capability.
-- Activation is Wave 2's governed conversion.
--
-- ===========================================================================
-- WHY A MEMBER-ORIGINATED INSERT IS PERMITTED, AND WHY IT IS INERT
-- ===========================================================================
--
-- D1(i) requires membership to ORIGINATE through invite/consent, so the INSERT
-- policy admits only `member_id = auth.uid()` at `status = 'invited'`.  Because
-- both helpers below now require `'active'`, such a row grants NOTHING to
-- anybody: it cannot satisfy `is_team_lead_of()` and it cannot satisfy
-- `may_notify()`.  That is what makes the lifecycle load-bearing rather than
-- decorative -- and it is what closes the REVERSE direction of F-03b, where a
-- member self-asserts onto a stranger's team to obtain a notify channel.

BEGIN;

-- ---------------------------------------------------------------------------
-- M1.  The lifecycle column.
--
--      DEFAULT 'invited' is not a style choice.  D1(ii) says "Do not treat the
--      existence of a coach_team_members row alone as proof of active
--      authorization", so any pre-existing row must NOT become 'active'.
--      QA holds 0 rows (verified).  Production state is unknown and was never
--      contacted; if production holds memberships they become 'invited' here,
--      which is the security-correct outcome under D1(ii).  See ADR-1.
--
--      `role` is deliberately NOT constrained.  The owner answered D1(i), (ii)
--      and (iii); the permitted `role` value set was NOT answered, so
--      constraining it would decide an open question.  Deferred -- see ADR-2.
-- ---------------------------------------------------------------------------

ALTER TABLE public.coach_team_members
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'invited';

ALTER TABLE public.coach_team_members
  DROP CONSTRAINT IF EXISTS coach_team_members_status_check;

ALTER TABLE public.coach_team_members
  ADD CONSTRAINT coach_team_members_status_check
  CHECK (status IN ('invited', 'active', 'suspended', 'revoked'));

COMMENT ON COLUMN public.coach_team_members.status IS
  'Membership lifecycle (owner decision D1(ii) 2026-09-27): invited | active | '
  'suspended | revoked.  ONLY ''active'' satisfies team-lead authorization. '
  'Row existence alone is not authorization.';

-- ---------------------------------------------------------------------------
-- M2.  Replace the single FOR ALL policy with explicit per-command policies --
--      the hardened idiom already used by `coach_client_relationships`.
--
--      The old policy MUST be dropped rather than supplemented: multiple
--      permissive policies are OR-ed together, so leaving it in place would
--      preserve the defect entirely.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Head coach manages team" ON public.coach_team_members;

-- SELECT: the lead sees their own roster; the member sees their own membership.
-- Preserves the roster read at coach_business_screen.dart:66.
CREATE POLICY "team membership readable by parties"
  ON public.coach_team_members
  FOR SELECT TO authenticated
  USING (coach_id = auth.uid() OR member_id = auth.uid());

-- INSERT: member-originated only, never self-activating.  A lead cannot create
-- a membership at all (D1(i) = NO).
CREATE POLICY "member originates own membership"
  ON public.coach_team_members
  FOR INSERT TO authenticated
  WITH CHECK (
    member_id = auth.uid()
    AND coach_id <> member_id
    AND status = 'invited'
  );

-- DELETE: the lead may remove a member from their own team.  Pre-existing
-- capability, preserved deliberately so revocation-by-removal still works.
CREATE POLICY "lead removes own team member"
  ON public.coach_team_members
  FOR DELETE TO authenticated
  USING (coach_id = auth.uid());

-- No UPDATE policy.  See the header.

-- ---------------------------------------------------------------------------
-- M3.  `is_team_lead_of()` evaluates the lifecycle (D1(ii)).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.coach_team_members t
    WHERE t.coach_id  = auth.uid()
      AND t.member_id = target_user
      -- D1(ii): only ACTIVE membership satisfies team-lead authorization.
      AND t.status    = 'active'
  );
$function$;

-- ---------------------------------------------------------------------------
-- M4.  `may_notify()` evaluates the lifecycle on its team arm (D1(ii)).
--
--      Body reproduced verbatim from the pre-change definition with exactly one
--      change: `AND t.status = 'active'` on the coach_team_members arm.
--
--      NOT CHANGED, and therefore NOT CLOSED: the coach_client_relationships
--      arm still matches at ANY status.  That is F-03b's second half and is
--      outside this wave (owner decision D3).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT (SELECT auth.uid()) IS NULL
      OR recipient = (SELECT auth.uid())
      OR EXISTS (SELECT 1 FROM public.coach_client_relationships r
                  WHERE (r.coach_id  = (SELECT auth.uid()) AND r.client_id = recipient)
                     OR (r.client_id = (SELECT auth.uid()) AND r.coach_id  = recipient))
      OR public.shares_conversation_with(recipient)
      OR EXISTS (SELECT 1 FROM public.coaching_calls c
                  WHERE (c.coach_id  = (SELECT auth.uid()) AND c.client_id = recipient)
                     OR (c.client_id = (SELECT auth.uid()) AND c.coach_id  = recipient))
      -- WAVE 1 (D1(ii)): only an ACTIVE membership creates a notify channel.
      OR EXISTS (SELECT 1 FROM public.coach_team_members t
                  WHERE t.status = 'active'
                    AND ((t.coach_id  = (SELECT auth.uid()) AND t.member_id = recipient)
                      OR (t.member_id = (SELECT auth.uid()) AND t.coach_id  = recipient)))
      -- I-NOT-02 arm 1: the recipient authored a post the caller has commented
      -- on. Both sides are required -- authorship alone does not qualify, and
      -- neither does commenting on somebody else's post.
      OR EXISTS (SELECT 1 FROM public.community_posts p
                   JOIN public.post_comments pc ON pc.post_id = p.id
                  WHERE p.user_id  = recipient
                    AND pc.user_id = (SELECT auth.uid()))
      -- I-NOT-02 arm 2: the recipient and the caller are both booked into the
      -- same class. Status is deliberately not filtered: the writer this arm
      -- exists for is _promoteFromWaitlist, reached from cancelBooking, where
      -- the caller's own booking has just been set to 'cancelled'.
      OR EXISTS (SELECT 1 FROM public.class_bookings cb_self
                   JOIN public.class_bookings cb_other
                     ON cb_other.class_id = cb_self.class_id
                  WHERE cb_self.user_id  = (SELECT auth.uid())
                    AND cb_other.user_id = recipient);
$function$;

-- ---------------------------------------------------------------------------
-- M5.  Remove PHI from the team-lead authorization path (D1(iii)).
--
--      The `is_team_lead_of(id)` arm granted the WHOLE user_profiles row.  It is
--      dropped.  `id = auth.uid()` and `is_active_coach_of(id)` remain -- an
--      active coach legitimately needs the PAR-Q, which is the clinical point of
--      the intake.  `hosts_event_for(id)` ALSO remains: it is a separate profile
--      path (QAX-SEC-09) and removing it here would be scope expansion and would
--      break the event-vendor flow.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "own profile or active coach reads profile" ON public.user_profiles;

CREATE POLICY "own profile or active coach reads profile"
  ON public.user_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR public.is_active_coach_of(id)
    OR public.hosts_event_for(id)
  );

-- The column-limited replacement for the roster.
--
-- `security_invoker = off` is REQUIRED, not incidental: the view must serve rows
-- the caller's own RLS on user_profiles now denies.  The proposal in
-- docs/proposed/SEC_PHI_1_roster_attendee_views.sql used `security_invoker = on`
-- and would have returned `200 []` to exactly the users it existed to serve
-- (finding NEW-5).  `security_barrier = true` keeps the optimizer from leaking
-- rows through the predicate, matching `conversation_participant_profiles`.
--
-- The row gate is `is_team_lead_of()`, which now requires status = 'active', so
-- only an ACTIVE team lead sees these four columns.  No health, body-composition
-- or billing column appears -- PHI exclusion under D1(iii) is absolute.
-- `email` is included per ADR-3 to preserve the existing roster display; it is
-- PII rather than PHI and remains a flagged product question.

CREATE OR REPLACE VIEW public.team_member_profiles
WITH (security_invoker = off, security_barrier = true) AS
  SELECT p.id,
         p.first_name,
         p.last_name,
         p.email,
         p.avatar_url
    FROM public.user_profiles p
   WHERE p.id = auth.uid()
      OR public.is_team_lead_of(p.id);

-- GRANT HARDENING -- do not simplify these two lines.
--
-- Supabase carries `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON
-- TABLES TO anon, authenticated, service_role`, and that default fires when a
-- VIEW is created.  Migration 112_view_grants_read_only.sql exists precisely
-- because migrations 101/102/110 revoked PUBLIC and anon but never
-- `authenticated`, leaving every view in this schema INSERT/UPDATE/DELETE-able.
-- This view is a simple projection over one table and is therefore
-- AUTO-UPDATABLE, and it runs `security_invoker = off` -- so a write through it
-- would execute as the owner (postgres, BYPASSRLS) and land on user_profiles
-- unfiltered by RLS.  112 demonstrated exactly that against public_profiles
-- (`UPDATE ... SET first_name = 'PWNED'`).
--
-- So: revoke from anon AND authenticated, then grant back SELECT only.
-- service_role keeps its grants -- it is the trusted server-side identity.
REVOKE ALL ON public.team_member_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.team_member_profiles TO authenticated;

COMMENT ON VIEW public.team_member_profiles IS
  'Minimum-necessary team roster projection (owner decision D1(iii) 2026-09-27). '
  'Gated by is_team_lead_of(), which requires status = ''active''. '
  'NEVER add a medical, health, body-composition, intake or billing column to '
  'this view -- D1(iii) excludes PHI from team-lead authorization absolutely.';

COMMIT;
