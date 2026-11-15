-- Migration 195. A client books a coach's call only with Coach-Guided access to
-- that coach -- enforced in the database, not only by the app's paywall.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["195"]. Applies after 193 (it reads activated_by).
--
-- OWNER DECISION 1 (2026-11-15, Julia, "Data sharing only"): an unpaid,
-- client-activated relationship shares data but does not unlock Coach-Guided.
-- The app gates "Coach Bookings" on client_plan() = coach_guided (app_router:
-- PaywallGate required: ClientPlan.coachGuided), and 193 makes client_plan()
-- honour the decision. But coaching_calls' client write arm is only
-- `client_id = auth.uid()`: a client can INSERT a call with ANY coach through
-- the API, paid or not, related or not. Hiding the screen is not enforcement.
--
-- THE RULE (decision-free given decision 1 -- the same test client_plan() uses,
-- scoped to the coach being booked):
--   public.has_coach_guided_access(client, coach) is true when
--     * an ACTIVE relationship with that coach was NOT client-activated
--       (coach-approved, invite, system/webhook, or activated before 193), or
--     * a live coaching subscription (coach / package_monthly) with that coach
--       is active or trialing and not past its period end.
--   A call the CLIENT inserts must satisfy it (42501 otherwise). Calls the coach
--   or the server create are unaffected (their own policies govern them).

BEGIN;

CREATE OR REPLACE FUNCTION public.has_coach_guided_access(p_client uuid, p_coach uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
           SELECT 1 FROM coach_client_relationships
            WHERE client_id = p_client AND coach_id = p_coach
              AND status = 'active'
              AND activated_by IS DISTINCT FROM 'client')
      OR EXISTS (
           SELECT 1 FROM subscriptions
            WHERE user_id = p_client AND coach_id = p_coach
              AND kind IN ('coach', 'package_monthly')
              AND status IN ('active', 'trialing')
              AND (current_period_end IS NULL OR current_period_end > now()));
$$;

REVOKE ALL ON FUNCTION public.has_coach_guided_access(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.coaching_calls_client_needs_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NOT NULL
     AND (SELECT auth.uid()) = NEW.client_id
     AND (SELECT auth.uid()) IS DISTINCT FROM NEW.coach_id
     AND NOT public.has_coach_guided_access(NEW.client_id, NEW.coach_id) THEN
    RAISE EXCEPTION 'coach bookings need Coach-Guided access to this coach'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.coaching_calls_client_needs_access() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_coaching_calls_client_needs_access ON public.coaching_calls;
CREATE TRIGGER trg_coaching_calls_client_needs_access
  BEFORE INSERT ON public.coaching_calls
  FOR EACH ROW EXECUTE FUNCTION public.coaching_calls_client_needs_access();

COMMENT ON FUNCTION public.has_coach_guided_access(uuid, uuid) IS
  'Migration 195 (owner decision 1): the client has Coach-Guided access to this coach -- '
  'an active relationship not activated by the client, or a live paid coaching subscription with them.';

COMMIT;
