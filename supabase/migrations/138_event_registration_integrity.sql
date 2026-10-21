-- 138_event_registration_integrity.sql
--
-- BIL-3 / K-04 -- P0, pulled forward into P1 by OWNER DECISION A (§25.4).
--
-- ===========================================================================
-- WHAT THIS CLOSES
-- ===========================================================================
--
-- The registry records K-04 as a BILLING defect: "event_registrations' policy
-- has no WITH CHECK, so a member sets paid/payment_id themselves."
--
-- §25 established that the SAME missing WITH CHECK is also an AUTHORIZATION
-- defect with a PII impact the registry does not record, because the surface it
-- feeds did not exist when K-04 was written. The chain, each link verified
-- against the live QA catalog:
--
--   1. `event_attendee_profiles` (migration 135) runs security_invoker = off
--      and is owned by postgres, so it bypasses user_profiles RLS by
--      construction. `hosts_event_for()` is the ENTIRE authorization.
--   2. `hosts_event_for()` trusts `event_registrations.user_id`.
--   3. That column is attacker-writable: "vendors check in own event
--      registrations" is FOR UPDATE with NO WITH CHECK, so Postgres reuses
--      USING -- which constrains event_id -> vendor_id only, never user_id.
--   4. `handle_new_user()` takes the role from signup metadata and admits
--      'vendor', so the attacker self-assigns the role.
--   5. `public_profiles` has no WHERE clause, so victim uuids are enumerable.
--
-- Result, before this migration: a self-registered vendor rewrites a
-- registration's user_id to any victim and reads that victim's first_name,
-- last_name, email and avatar_url through the view -- repeatable across the
-- entire user base.
--
-- ===========================================================================
-- WHY A TRIGGER AND NOT ONLY A `WITH CHECK`
-- ===========================================================================
--
-- A WITH CHECK clause only sees the NEW row. It cannot express "this column did
-- not change", so it cannot stop a vendor who legitimately holds UPDATE on a
-- registration from rewriting whose registration it is -- the result still
-- satisfies any predicate about the vendor's own event. Column immutability
-- needs a BEFORE trigger.
--
-- This is not a new pattern. Migration 113 solved the identical problem on
-- coach_client_relationships (113:118-176) and its header states the reasoning
-- verbatim. 138 follows that trigger shape deliberately, including the
-- auth.uid() IS NULL passthrough for internal callers, which bypass RLS anyway.
--
-- ===========================================================================
-- WHAT THE LEGITIMATE WRITERS ACTUALLY SEND -- read, not assumed
-- ===========================================================================
--
--   * Member registration, `event_ticket_screen.dart:62-67`, INSERT:
--       { event_id, user_id, qr_code, status }   -- never paid, never payment_id
--   * Vendor check-in, `vendor_service.dart:90-93`, UPDATE:
--       { checked_in_at, status }                -- nothing else
--
-- So freezing user_id / event_id / qr_code / paid / payment_id on UPDATE, and
-- forcing paid/payment_id to their unpaid values on a client INSERT, leaves
-- both real call sites working unchanged. qr_code stays client-writable on
-- INSERT because that screen generates it.
--
-- ===========================================================================
-- SCOPE -- what this migration deliberately does NOT do
-- ===========================================================================
--
--   * It does NOT touch DAT-4 / I-COM-01. The registry says K-04 and DAT-4
--     should be fixed "in one change -- same table", but DAT-4 is a Wave 3
--     APPLICATION-layer defect (the write named a nonexistent `ticket_code`
--     column) and Decision A pulled forward BIL-3/K-04 only. Absorbing another
--     wave's finding would be the scope expansion §25.4 warned against.
--     `event_ticket_screen.dart:62-67` already writes `qr_code`, so nothing
--     here depends on DAT-4's state either way.
--   * It does NOT touch F-21 / OD-14. §25.4 asserted this fix "touches the
--     F-21/OD-14 policy-shape population". That assertion is WRONG and is
--     corrected in the programme document: F-21's population is 4 tables in its
--     §2a and 11 in its §2b, and `event_registrations` is in neither. OD-14 is
--     a decision about the PROGRAMME-ASSIGNMENT model and does not gate this.
--   * It does NOT revisit migration 135, which is not edited (§8:219).
--   * It does NOT close SEC-PHI-9, SEC-PHI-10 or QAX-SEC-09, and it allocates
--     no finding ID.
--   * It does NOT make `paid` writable by anyone. Granting a paid ticket is a
--     server concern; service_role and the internal path are unaffected.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1 · Column integrity.
--
-- Internal callers (service_role, migrations, the SQL editor, the deterministic
-- engine) run with auth.uid() IS NULL and pass straight through. They bypass
-- RLS regardless, so gating them here would add no protection and would break
-- legitimate server-side ticket issuance.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_registration_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN NEW;                      -- internal / service-role path
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- A client may register. A client may not decide that the registration is
    -- paid for. This is K-04's originally recorded impact.
    NEW.paid       := false;
    NEW.payment_id := NULL;
    RETURN NEW;
  END IF;

  -- UPDATE. The vendor's legitimate operation is check-in: status and
  -- checked_in_at. Everything that decides WHOSE registration this is, WHICH
  -- event it belongs to, or WHETHER IT WAS PAID FOR is frozen.

  -- user_id is the whole of hosts_event_for()'s trust, and therefore the whole
  -- of event_attendee_profiles' authorization. This single check is what closes
  -- the §25 PII-harvesting path.
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION
      'event_registrations: user_id is immutable -- a registration cannot be reassigned to another user'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.event_id IS DISTINCT FROM OLD.event_id THEN
    RAISE EXCEPTION
      'event_registrations: event_id is immutable -- a registration cannot be moved between events'
      USING ERRCODE = '42501';
  END IF;

  -- qr_code is a bearer credential (DEFAULT encode(gen_random_bytes(16))).
  -- Same class as coach_client_relationships.invite_token in migration 113.
  IF NEW.qr_code IS DISTINCT FROM OLD.qr_code THEN
    RAISE EXCEPTION
      'event_registrations: qr_code is a bearer credential and is not client-rewritable'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.paid IS DISTINCT FROM OLD.paid
  OR NEW.payment_id IS DISTINCT FROM OLD.payment_id THEN
    RAISE EXCEPTION
      'event_registrations: paid/payment_id are set by the server, not by a client'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'event_registrations: id is immutable'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.registered_at IS DISTINCT FROM OLD.registered_at THEN
    NEW.registered_at := OLD.registered_at;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_registration_integrity() IS
  'BIL-3/K-04 (migration 138). Freezes the columns that decide WHOSE '
  'registration a row is (user_id, event_id), whether it was PAID for '
  '(paid, payment_id), and its bearer credential (qr_code). A WITH CHECK '
  'cannot express immutability because it sees only the NEW row, which is why '
  'this is a trigger -- the same reasoning and shape as migration 113 on '
  'coach_client_relationships. user_id immutability is what closes the '
  'event_attendee_profiles PII path recorded in V5 section 25.';

DROP TRIGGER IF EXISTS trg_registration_integrity ON public.event_registrations;
CREATE TRIGGER trg_registration_integrity
  BEFORE INSERT OR UPDATE ON public.event_registrations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_registration_integrity();

-- ---------------------------------------------------------------------------
-- 2 · The missing WITH CHECK -- the remediation the registry actually names.
--
-- Defence in depth rather than the primary control: the trigger above already
-- freezes event_id, so the post-image cannot leave the vendor's event. This
-- makes the intent explicit at the policy layer and removes the "no WITH CHECK,
-- so USING is silently reused" shape that K-04 is recorded against.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "vendors check in own event registrations" ON public.event_registrations;
CREATE POLICY "vendors check in own event registrations"
  ON public.event_registrations FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.events e
             WHERE e.id = event_registrations.event_id
               AND e.vendor_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.events e
             WHERE e.id = event_registrations.event_id
               AND e.vendor_id = auth.uid())
  );

COMMENT ON POLICY "vendors check in own event registrations" ON public.event_registrations IS
  'K-04 (migration 138): the WITH CHECK was absent, so Postgres reused USING -- '
  'which constrains event_id -> vendor_id and never user_id. Column immutability '
  'is enforced by trg_registration_integrity; this clause states the row-level '
  'intent explicitly so the defective shape cannot be reintroduced by reading '
  'the policy alone.';

COMMIT;

-- ===========================================================================
-- EVIDENCE CEILING
-- ===========================================================================
--
-- FIXED IN CODE at authoring time. Unlike QAX-SEC-09, the pre-fix half of
-- QA_CLOSURE_STANDARD §5.2 IS obtainable for this finding WITHOUT any rollback,
-- because the defect is live on QA right now and has never been remediated
-- there. The adversarial probe is therefore run against QA BEFORE this
-- migration is applied and again after. That evidence is recorded in
-- docs/V5_PROGRAMME_DEFINITION.md, not here, and the registry is updated only
-- through the established workflow.
