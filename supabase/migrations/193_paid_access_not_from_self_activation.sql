-- Migration 193. A coaching relationship the client activated by themselves,
-- unpaid, shares data with the coach but does not unlock Coach-Guided.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["193"].
--
-- OWNER DECISION (2026-11-15, Julia, in session; recorded in docs/decision-log.md):
-- "an unpaid, client-activated relationship grants data sharing only -- the
-- coach can see the client's data, but Coach-Guided features need a paid coach
-- subscription or a coach-approved or coach-invited relationship."
--
-- THE DEFECT (S1, live definitions read from QA). client_plan() -- what the
-- paywall asks -- returned 'coach_guided' for ANY active coach_client_relationships
-- row. Migration 113 lets a client INSERT its own row as 'active' and set its own
-- row back to 'active', and the intake flow does exactly that when a client picks
-- a coach. The top tier was free to anyone.
--
-- THE FIX.
--   * activated_by -- who moved the row INTO 'active': 'client', 'coach',
--     'invite' (accept_coach_invite, migration 194) or 'system' (no signed-in
--     caller: the Stripe webhook, service role, migrations). Set by trigger on
--     every transition into 'active'; on any other write it keeps its value, so
--     no caller can choose it. It is server-owned: not granted to authenticated.
--   * client_plan(): the relationship branch counts only a row NOT activated by
--     the client. A paid coach subscription still grants coach_guided through the
--     subscription branch, unchanged.
--
-- EXISTING ROWS (implementation choice, flagged for the owner): rows activated
-- before this migration have activated_by NULL -- who activated them cannot be
-- recovered (the status audit records before/after, not the actor) -- and keep
-- their access (NULL is not 'client'). Only activations from now on are judged.
--
-- FUNCTION REPLACEMENT RULE. client_plan keeps signature, STABLE, SECURITY
-- DEFINER; search_path pin and grants restated.

BEGIN;

ALTER TABLE public.coach_client_relationships
  ADD COLUMN IF NOT EXISTS activated_by text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'coach_client_relationships_activated_by_check') THEN
    ALTER TABLE public.coach_client_relationships
      ADD CONSTRAINT coach_client_relationships_activated_by_check
      CHECK (activated_by IS NULL OR activated_by IN ('client', 'coach', 'invite', 'system'));
  END IF;
END $$;

COMMENT ON COLUMN public.coach_client_relationships.activated_by IS
  'Migration 193: who moved this row into active -- client | coach | invite | system '
  '(NULL = activated before 193). Set by trg_relationship_activated_by; not client-writable. '
  'client_plan() grants coach_guided from a relationship only when this is not ''client''.';

CREATE OR REPLACE FUNCTION public.set_relationship_activated_by()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_src text := nullif(current_setting('app.relationship_activation', true), '');
BEGIN
  IF NEW.status = 'active' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'active') THEN
    NEW.activated_by := CASE
      WHEN v_src = 'invite'          THEN 'invite'
      WHEN v_uid IS NULL             THEN 'system'
      WHEN v_uid = NEW.coach_id      THEN 'coach'
      WHEN v_uid = NEW.client_id     THEN 'client'
      ELSE 'system'
    END;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.activated_by := OLD.activated_by;   -- nobody chooses it
  ELSE
    NEW.activated_by := NULL;               -- inserted as pending / anything not active
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_relationship_activated_by() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_relationship_activated_by ON public.coach_client_relationships;
CREATE TRIGGER trg_relationship_activated_by
  BEFORE INSERT OR UPDATE ON public.coach_client_relationships
  FOR EACH ROW EXECUTE FUNCTION public.set_relationship_activated_by();

CREATE OR REPLACE FUNCTION public.client_plan()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    -- Top tier: an active coaching relationship the CLIENT did not activate by
    -- themselves (coach-approved, coach-invited, paid via the webhook, or from
    -- before migration 193).
    (SELECT 'coach_guided' FROM coach_client_relationships
      WHERE client_id = auth.uid() AND status = 'active'
        AND activated_by IS DISTINCT FROM 'client'
      LIMIT 1),
    -- An explicit coach or monthly-package subscription.
    (SELECT 'coach_guided' FROM subscriptions
      WHERE user_id = auth.uid() AND kind IN ('coach', 'package_monthly')
        AND status IN ('active', 'trialing')
        AND (current_period_end IS NULL OR current_period_end > now())
      LIMIT 1),
    -- Else the highest active platform membership (ai outranks self).
    (SELECT kind FROM subscriptions
      WHERE user_id = auth.uid() AND kind IN ('self_guided', 'ai_guided')
        AND status IN ('active', 'trialing')
        AND (current_period_end IS NULL OR current_period_end > now())
      ORDER BY CASE kind WHEN 'ai_guided' THEN 0 ELSE 1 END
      LIMIT 1),
    'free'
  );
$$;

REVOKE ALL ON FUNCTION public.client_plan() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_plan() TO authenticated;

COMMIT;
