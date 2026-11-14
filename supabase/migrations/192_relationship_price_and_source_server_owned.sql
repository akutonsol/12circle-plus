-- Migration 192. A client cannot set the price it is charged or the commission
-- source that decides the platform's cut. Both become server/coach-owned on
-- coach_client_relationships, on INSERT as well as UPDATE.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["192"]; environments.qa.applied_through is "181".
--
-- THE DEFECTS (migration 113's grants and triggers, unchanged since; live trigger
-- list read from QA, 2026-11-14). Migration 113 grants authenticated INSERT and
-- UPDATE on every column except invite_token / invite_id, and its policies let a
-- client insert and update its OWN row. Two columns on that row are money:
--   * monthly_price -- the coach's per-client price. create-checkout charges it
--     for a `coach` checkout (rel.monthly_price ?? coach.pricing_monthly). The
--     only writer in the app is the COACH (CoachRelationshipService.setClientPrice,
--     `.eq('coach_id', me)`), but nothing stops the client PATCHing its own row's
--     price -- enforce_relationship_integrity (113) guards the parties,
--     initiated_by, client_source and invite_token, and not this.
--   * client_source -- 'coach_invited' means a 0% platform commission
--     (create-checkout). 113's comment says it "is set by the server" and its
--     UPDATE guard enforces that, but the BEFORE INSERT trigger
--     set_relationship_client_source (040 / 113) only derives the value when the
--     inserted one is NULL or 'marketplace'. A client that INSERTs its own row
--     with client_source = 'coach_invited' keeps it, and pays no commission.
--
-- THE FIX. Decision-free -- both rules are already stated (the price is the
-- coach's; the source "is set by the server") and only the missing half is added:
--   * set_relationship_client_source: for a signed-in caller the supplied value is
--     IGNORED and the source is always derived (coach invite for this client's
--     email -> 'coach_invited', else 'marketplace'). The internal path
--     (auth.uid() IS NULL: service_role, migrations) keeps 113's behaviour, so the
--     webhook's own writes are unaffected.
--   * A client inserting its own row with a monthly_price is refused (42501); a
--     coach-initiated row may carry the coach's price.
--   * enforce_relationship_integrity: monthly_price may be changed only by the
--     row's coach (42501 otherwise). Same convention as 113's other refusals.
--
-- NOT HERE, deliberately: user_profiles.max_clients (coach-writable) is open
-- product decision PD-C02 ("hard block or soft signal?"), and whether a
-- client-activated relationship should grant paid access is a separate owner
-- decision. Neither is decided by this migration.
--
-- FUNCTION REPLACEMENT RULE. CREATE OR REPLACE keeps ACL and owner but not
-- proconfig, so search_path is restated; both stay trigger-only (EXECUTE revoked
-- from PUBLIC, as migration 139 left them). Security mode unchanged: the insert
-- trigger is DEFINER (it must read coach_invites), the integrity trigger INVOKER.

BEGIN;

CREATE OR REPLACE FUNCTION public.set_relationship_client_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NOT NULL THEN
    -- Migration 192: a signed-in caller never chooses its own commission source,
    -- and a client never names its own price.
    IF NEW.client_id = v_uid AND NEW.monthly_price IS NOT NULL THEN
      RAISE EXCEPTION 'coach_client_relationships: monthly_price is set by the coach'
        USING ERRCODE = '42501';
    END IF;
    NEW.client_source := NULL;
  END IF;

  IF NEW.client_source IS NULL OR NEW.client_source = 'marketplace' THEN
    IF EXISTS (
      SELECT 1
        FROM coach_invites i
        JOIN user_profiles p ON p.id = NEW.client_id
       WHERE i.coach_id = NEW.coach_id
         AND lower(i.invitee_email) = lower(p.email)
    ) THEN
      NEW.client_source := 'coach_invited';
    ELSE
      NEW.client_source := COALESCE(NEW.client_source, 'marketplace');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_relationship_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN NEW;                      -- internal / service-role path
  END IF;

  IF NEW.id           IS DISTINCT FROM OLD.id
  OR NEW.coach_id     IS DISTINCT FROM OLD.coach_id
  OR NEW.client_id    IS DISTINCT FROM OLD.client_id THEN
    RAISE EXCEPTION 'coach_client_relationships: the parties of a relationship are immutable'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.initiated_by IS DISTINCT FROM OLD.initiated_by THEN
    RAISE EXCEPTION 'coach_client_relationships: initiated_by is immutable (it decides who may activate)'
      USING ERRCODE = '42501';
  END IF;

  -- client_source drives the marketplace commission rate (migration 040) and
  -- invite_token is a bearer credential. Neither is client-writable.
  IF NEW.client_source IS DISTINCT FROM OLD.client_source THEN
    RAISE EXCEPTION 'coach_client_relationships: client_source is set by the server'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.invite_token IS DISTINCT FROM OLD.invite_token THEN
    RAISE EXCEPTION 'coach_client_relationships: invite_token is not client-writable'
      USING ERRCODE = '42501';
  END IF;

  -- Migration 192: the price is the coach's to set.
  IF NEW.monthly_price IS DISTINCT FROM OLD.monthly_price
     AND (SELECT auth.uid()) IS DISTINCT FROM OLD.coach_id THEN
    RAISE EXCEPTION 'coach_client_relationships: monthly_price is set by the coach'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    NEW.created_at := OLD.created_at;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_relationship_client_source() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_relationship_integrity()  FROM PUBLIC, anon, authenticated;

COMMIT;
