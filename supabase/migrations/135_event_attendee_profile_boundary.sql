-- 135_event_attendee_profile_boundary.sql
--
-- V5 SECURITY FOUNDATION — P1 (FOUNDATION / SECURITY).
--
-- Migration number 135 assigned at phase entry per docs/MASTER_REMEDIATION_WAVES.md
-- section 0.2 ("132+ ... assigned at wave entry, never before").  P1's entry
-- conditions are satisfied as recorded in docs/V5_PROGRAMME_DEFINITION.md section
-- 20.2: D1(i)-(iv), D3 and D17 are all answered.  This migration executes the
-- second half of P1's "corrected SEC_PHI_1" content under owner decision D17
-- (section 19.1: FIX BEFORE APPLYING).
--
-- ===========================================================================
-- THE FINDING THIS ADDRESSES
-- ===========================================================================
--
-- QAX-SEC-09, recorded OPEN in section 9:
--
--   "hosts_event_for() still grants an event host the WHOLE user_profiles row.
--    Profile PHI remains exposed through this path.  Closing QAX-SEC-08 would
--    not change it."
--
-- Migration 102 replaced two blanket `USING (true)` policies on user_profiles
-- with a four-arm policy.  Migration 132 removed the `is_team_lead_of(id)` arm
-- and served the roster from a column-limited view instead.  132:228-230 states
-- explicitly why it stopped there:
--
--   "`hosts_event_for(id)` ALSO remains: it is a separate profile path
--    (QAX-SEC-09) and removing it here would be scope expansion and would break
--    the event-vendor flow."
--
-- This migration completes that path.  `user_profiles` carries `parq_answers`
-- (the PAR-Q medical questionnaire), `weight_kg`, `goal_weight_kg`,
-- `transformation_photo_urls`, `membership_tier` and `stripe_details_submitted`.
-- A vendor gains none of them after this change.
--
-- ===========================================================================
-- WHY `security_invoker = off` — AND WHY THE PROPOSAL AS WRITTEN WOULD FAIL
-- ===========================================================================
--
-- docs/proposed/SEC_PHI_1_roster_attendee_views.sql defines the equivalent view
-- with `security_invoker = on`.  Under owner decision D17 that proposal is fixed
-- BEFORE it is applied, not applied and then fixed.  The defect is structural:
-- with `security_invoker = on` the caller's own RLS on user_profiles still
-- applies, and this migration removes the very arm that would have let it pass —
-- so the view would return `200 []` to exactly the users it exists to serve.
-- Migration 132 recorded the same defect as finding NEW-5 and resolved it the
-- same way (132:246-251).  This file follows that precedent exactly.
--
-- `security_barrier = true` keeps the optimizer from leaking rows through the
-- predicate, matching `conversation_participant_profiles` (102) and
-- `team_member_profiles` (132).
--
-- ===========================================================================
-- TWO OWNER BOUNDARIES THIS MIGRATION PRESERVES AND DOES NOT DECIDE
-- ===========================================================================
--
-- (1) `hosts_event_for()` HAS NO LIFECYCLE BOUND.  Its definition (102:65-79) is
--     EXISTS(event_registrations JOIN events WHERE events.vendor_id = auth.uid()
--     AND registrations.user_id = target) — with no status, date or expiry
--     condition.  A vendor therefore retains access indefinitely from a single
--     registration, including after the event has passed.
--
--     Migration 132 bounded the team counterpart with `status = 'active'`, but
--     only because owner decision D1 created that column.  THERE IS NO
--     EQUIVALENT OWNER DECISION FOR EVENTS.  Bounding this one would be
--     inventing product policy about what event-host access means — the same
--     class of question the record carries as OD-QAX-9 ("what a team means").
--
--     This migration therefore NARROWS THE COLUMNS AND LEAVES THE LIFETIME
--     UNCHANGED.  That is a strict reduction, not a broadening.  The lifetime
--     question is preserved as an owner decision and is NOT resolved here.
--
-- (2) `email` IS PII AND IS PRESERVED, NOT DECIDED.  The proposal records an
--     explicit "OPEN QUESTION FOR THE OWNER (do not resolve in this file)":
--     whether an event vendor should receive an attendee's email address.  132
--     preserved `email` for the roster under ADR-3 on the same reasoning.  This
--     file preserves current behaviour for the same reason — changing it would
--     be a product decision, and preserving it broadens nothing.
--
-- ===========================================================================
-- EVIDENCE CEILING — STATED SO IT IS NOT OVERCLAIMED
-- ===========================================================================
--
-- docs/QA_CLOSURE_STANDARD.md section 5.2 requires VERIFIED LIVE for a security
-- finding: "a real request against QA reproduces the secure/correct behaviour,
-- and the same probe demonstrably failed before the fix", and a closure that
-- redefines a database object "must prove it preserved every property".
--
-- NO DATABASE WAS CONTACTED IN PRODUCING THIS MIGRATION.  It therefore reaches
-- FIXED IN CODE only.  QAX-SEC-09 IS NOT CLOSED BY THIS FILE and its registry
-- status is unchanged.  Live verification against QA remains outstanding.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The column-limited attendee view.
--
--    Five columns, mirroring `team_member_profiles` (132:259-268) exactly.  No
--    health, body-composition, intake or billing column appears.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.event_attendee_profiles
WITH (security_invoker = off, security_barrier = true) AS
  SELECT p.id,
         p.first_name,
         p.last_name,
         p.email,
         p.avatar_url
    FROM public.user_profiles p
   WHERE p.id = auth.uid()
      OR public.hosts_event_for(p.id);

-- GRANT HARDENING -- do not simplify these two lines.
--
-- Supabase carries `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON
-- TABLES TO anon, authenticated, service_role`, and that default fires when a
-- VIEW is created.  This view is a simple projection over one table and is
-- therefore AUTO-UPDATABLE, and it runs `security_invoker = off` -- so a write
-- through it would execute as the owner (postgres, BYPASSRLS) and land on
-- user_profiles unfiltered by RLS.  Migration 112 demonstrated exactly that
-- against public_profiles (`UPDATE ... SET first_name = 'PWNED'`).
--
-- So: revoke from anon AND authenticated, then grant back SELECT only.
-- service_role keeps its grants -- it is the trusted server-side identity.
REVOKE ALL ON public.event_attendee_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.event_attendee_profiles TO authenticated;

COMMENT ON VIEW public.event_attendee_profiles IS
  'QAX-SEC-09 / SEC-PHI-1: the minimum-necessary columns an event vendor needs '
  'to render an attendee list. Replaces the hosts_event_for() arm of the '
  'user_profiles SELECT policy, which granted the whole row including PAR-Q. '
  'security_invoker = off is REQUIRED: the view serves rows the caller''s own '
  'RLS on user_profiles now denies. The row gate carries NO lifecycle bound '
  'because none is owner-decided -- see migration header, boundary (1).';

-- ---------------------------------------------------------------------------
-- 2. Remove the event-host arm from the user_profiles SELECT policy.
--
--    The policy is recreated with the two arms that remain owner-sanctioned:
--    the subject's own row, and an ACTIVE coach of the subject.  132 removed
--    `is_team_lead_of`; this removes `hosts_event_for`.
--
--    `is_active_coach_of(id)` is unchanged and still carries `status = 'active'`
--    (134:67, 134:88).
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "own profile or active coach reads profile" ON public.user_profiles;

CREATE POLICY "own profile or active coach reads profile"
  ON public.user_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR public.is_active_coach_of(id)
  );

COMMENT ON POLICY "own profile or active coach reads profile" ON public.user_profiles IS
  'Wave 1 (132) removed the is_team_lead_of arm; P1 (135) removes the '
  'hosts_event_for arm. Both are now served by column-limited views that '
  'exclude PHI. Only the subject and an ACTIVE coach read the whole row.';

COMMIT;

-- ===========================================================================
-- WHAT THIS MIGRATION DOES NOT DO
-- ===========================================================================
--
--   * It does not close QAX-SEC-09.  No database was contacted; the evidence
--     reaches FIXED IN CODE only, and the registry is not edited.
--   * It does not bound the event-host access lifetime (boundary 1 above).
--   * It does not decide whether a vendor should receive attendee email
--     (boundary 2 above).
--   * It does not touch `is_team_lead_of`, `coach_team_members`, or anything
--     migrations 132/133/134 established.
--   * It does not alter `hosts_event_for()` itself -- the function is retained
--     and is now consumed by the view rather than by the policy.  116's
--     search_path pinning of that function is unaffected.
