-- 139_registration_trigger_grant_posture.sql
--
-- A DEFECT REPAIR for migration 138, found by the standing guard. Not new scope.
--
-- ===========================================================================
-- THE DEFECT — INTRODUCED BY 138, CAUGHT BY FG-1/SP-5 IN CI
-- ===========================================================================
--
-- 138 created `enforce_registration_integrity()` and issued NO grant statement
-- at all, so the function kept PostgreSQL's default EXECUTE-to-PUBLIC. Once
-- Supabase's default privileges added `authenticated` and `service_role`, the
-- function's `proacl` became non-NULL, which makes that PUBLIC grant explicit
-- and therefore visible to the posture assertion:
--
--   supabase/tests/security/function-search-path.sql, SP-5:
--     "EXECUTE grants to PUBLIC or anon" must be 0.
--
-- CI run 36596636664 (b700c30):  FAIL SP-5  EXECUTE grants to PUBLIC or anon: 1
-- CI run 36368081140 (16ba19f):  PASS SP-5  EXECUTE grants to PUBLIC or anon: 0
--
-- The ratchet was green before 138 and red after it. This is mine.
--
-- Migration 113 -- which 138 explicitly copied its trigger shape from -- does
-- carry the revoke that 138 omitted:
--
--   REVOKE ALL ON FUNCTION public.enforce_relationship_integrity() FROM PUBLIC;
--
-- 138 copied the trigger and the reasoning and missed the grant line.
--
-- ===========================================================================
-- SEVERITY, STATED HONESTLY RATHER THAN INFLATED
-- ===========================================================================
--
-- `enforce_registration_integrity()` RETURNS trigger. PostgreSQL refuses to
-- call a trigger function directly -- "trigger functions can only be called as
-- triggers" (0A000) -- so the PUBLIC grant confers no reachable capability, and
-- PostgREST does not expose trigger-returning functions as RPC. **There is no
-- known exploit path.** This is a POSTURE regression against a ratchet the
-- programme deliberately keeps at zero, not a live exposure.
--
-- It is repaired anyway, and not by weakening SP-5. The guard's own output says
-- it: "RESULT: FAIL -- reported as found. The assertion is not weakened to go
-- green."
--
-- ===========================================================================
-- SCOPE
-- ===========================================================================
--
--   * 138 is NOT rewritten in place -- QA_CLOSURE_STANDARD §8:219, "never
--     rewrite a migration in place unless the wave plan explicitly authorizes
--     it". 138 is applied on QA and its ledger row stands.
--   * `authenticated` and `service_role` are left exactly as they are. Revoking
--     them is unnecessary -- PostgreSQL does NOT check EXECUTE on a trigger
--     function when the trigger fires -- and touching them risks the check-in
--     path for no gain. Only the two grantees SP-5 actually counts are removed.
--   * This changes no policy, no trigger, no column and no behaviour. The K-04
--     boundary proven by d11 (9/9 on QA, and 9/9 in CI run 36596636664) is
--     untouched, and d11 must still pass after this.
--   * It closes no finding and allocates no ID.

BEGIN;

REVOKE ALL ON FUNCTION public.enforce_registration_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_registration_integrity() FROM anon;

COMMENT ON FUNCTION public.enforce_registration_integrity() IS
  'BIL-3/K-04 (migration 138). Freezes the columns that decide WHOSE '
  'registration a row is (user_id, event_id), whether it was PAID for '
  '(paid, payment_id), and its bearer credential (qr_code). A WITH CHECK '
  'cannot express immutability because it sees only the NEW row, which is why '
  'this is a trigger -- the same reasoning and shape as migration 113 on '
  'coach_client_relationships. user_id immutability is what closes the '
  'event_attendee_profiles PII path recorded in V5 section 25. '
  'EXECUTE is revoked from PUBLIC and anon by migration 139: 138 omitted the '
  'revoke that 113 carries, and FG-1/SP-5 caught it in CI.';

COMMIT;
