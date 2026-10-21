-- 133_team_membership_consent_origination.sql
--
-- V5 SECURITY FOUNDATION — WAVE 1, fidelity remediation.
--
-- Migration number 133 assigned at wave entry per docs/MASTER_REMEDIATION_WAVES.md
-- section 0.2.  Authorized by the owner decision D1(i) already recorded verbatim
-- in docs/adr/ADR-W1-001-team-membership-lifecycle.md; the reconciliation showing
-- that D1(i) already requires this enforcement is Addendum A of that ADR.  No new
-- owner decision was taken.
--
-- ===========================================================================
-- WHY
-- ===========================================================================
--
-- Migration 132 correctly denied UNILATERAL creation by a team lead, which is the
-- first clause of D1(i).  It then admitted a member-originated INSERT at
-- status = 'invited', reasoning that such a row is inert because both
-- authorization helpers require status = 'active'.
--
-- Agent 3's independent verification accepted that the row is inert and rejected
-- the reasoning as sufficient.  D1(i)'s second clause is not scoped to leads:
--
--     "Membership must originate through the invite/consent flow and only become
--      an active membership after the required acceptance/consent step."
--
-- That constrains origination as such.  The invite/consent flow does not exist
-- anywhere in this system -- no trigger on either team table, no function reading
-- coach_team_invites, no writer of coach_team_members outside a SELECT at
-- coach_business_screen.dart.  So no origination currently satisfies the clause,
-- and the faithful enforcement is to admit none until Wave 2 supplies the link.
--
-- Two defects Agent 3 recorded follow from the 132 policy and are addressed or
-- neutralised here:
--
--   NEW-W1-01  Any authenticated caller could insert an 'invited' row naming an
--              ARBITRARY user as coach_id, which then appeared in that unwilling
--              lead's roster.  It granted no authorization -- is_team_lead_of and
--              may_notify both returned false -- but the row itself was
--              unauthorized state.  ELIMINATED by this migration.
--
--   NEW-W1-02  A member cannot delete their own membership row; there is no
--              member-side DELETE policy.  This becomes UNREACHABLE here, because
--              no membership can be created at all.  It is NOT fixed: whether a
--              member has a right to leave a team is a semantic question no owner
--              decision addresses, so answering it would be deciding for the
--              owner.  Carried to Wave 2.
--
-- ===========================================================================
-- WHAT THIS MIGRATION DOES NOT DO
-- ===========================================================================
--
-- Nothing else changes.  The lifecycle column and its CHECK, the SELECT policy,
-- the DELETE policy, is_team_lead_of(), may_notify(), the team_member_profiles
-- view, its grants and the user_profiles SELECT policy are all left exactly as
-- migration 132 left them.
--
-- Still open and NOT touched here: may_notify()'s coach_client_relationships arm
-- at any status (F-03b's second half), hosts_event_for() (QAX-SEC-09),
-- SEC-PHI-9/10, SEC-AI-1, and coach_team_invites' own missing WITH CHECK (Wave 2).

BEGIN;

-- ---------------------------------------------------------------------------
-- An explicit deny, rather than simply dropping the policy.
--
-- Dropping it would also deny INSERT, because RLS defaults to deny when no
-- policy admits a command.  A named policy is used instead so the closure is
-- visible in the catalog: a future reader sees a deliberate, dated decision
-- rather than an absence they might "helpfully" fill in.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "member originates own membership" ON public.coach_team_members;

CREATE POLICY "membership originates only through the consent flow"
  ON public.coach_team_members
  FOR INSERT TO authenticated
  WITH CHECK (false);

COMMENT ON TABLE public.coach_team_members IS
  'Team membership. Owner decision D1(i) 2026-09-27: membership must originate '
  'through the invite/consent flow. That flow does not exist yet, so INSERT is '
  'denied to every caller until Wave 2 links an accepted coach_team_invites row '
  'to a membership. D1(ii): only status = ''active'' satisfies team-lead '
  'authorization; row existence alone is not authorization.';

COMMIT;
