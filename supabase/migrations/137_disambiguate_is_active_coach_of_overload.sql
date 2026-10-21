-- 137_disambiguate_is_active_coach_of_overload.sql
--
-- V5 SECURITY FOUNDATION — P1. A DEFECT REPAIR, not new scope.
--
-- ===========================================================================
-- THE DEFECT — INTRODUCED BY MIGRATION 136, FOUND BY THE LIVE HARNESS
-- ===========================================================================
--
-- 136 added `is_active_coach_of(target_user text)` alongside the existing
-- `is_active_coach_of(target_user uuid)`. Both parameters are named
-- `target_user`, and PostgREST resolves an RPC overload BY PARAMETER NAME. A
-- call to `/rest/v1/rpc/is_active_coach_of` with `{"target_user": ...}` is
-- therefore ambiguous, and PostgREST refuses it:
--
--   PGRST203 — "Could not choose the best candidate function between:
--   public.is_active_coach_of(target_user => uuid),
--   public.is_active_coach_of(target_user => text)"
--
-- Observed live on QA by `d01-coach-client-relationships.mjs`, assertion
-- "is_active_coach_of(victim) stays false for the attacker" — status 300.
--
-- SCOPE OF THE BREAKAGE, stated accurately rather than minimised:
--
--   * The RLS POLICIES ARE UNAFFECTED. Inside SQL the argument type is known at
--     parse time -- `is_active_coach_of(user_id)` binds uuid, and
--     `is_active_coach_of((storage.foldername(name))[1])` binds text. No policy
--     was ever ambiguous, and the live catalog confirms both resolved.
--   * What broke is the POSTGREST RPC PATH ONLY. The function is
--     EXECUTE-granted to `authenticated` and reachable at `/rpc/`, so this is a
--     real regression in a reachable surface even though no application code
--     calls it -- verified: no `rpc('is_active_coach_of')` caller exists in
--     `apps/`. The security harness does call it, which is how it surfaced.
--
-- ===========================================================================
-- THE REPAIR
-- ===========================================================================
--
-- Rename the TEXT overload's parameter so PostgREST can disambiguate by name.
-- `target_path` is also the more honest name: that overload exists for storage
-- object paths (D3, migration 136), which is the only thing that calls it.
--
-- Postgres cannot rename an input parameter through CREATE OR REPLACE ("cannot
-- change name of input parameter"), so the function must be dropped and
-- recreated. The progress-photos policy depends on it, so the policy is dropped
-- and recreated around it IN THE SAME TRANSACTION -- the boundary is never
-- absent from a committed state.
--
-- OWNER DECISION D3 IS UNCHANGED. It ruled "YES, UNIFORMLY, via (b) the
-- is_active_coach_of(text) overload". This is still that overload, with the
-- same body, the same delegation and the same grants. Only the parameter NAME
-- changes, which is invisible to every positional caller.
--
-- ===========================================================================
-- EVIDENCE CEILING
-- ===========================================================================
--
-- FIXED IN CODE at authoring time. Live re-verification of the RPC path and of
-- the progress-photos boundary is required after application and is recorded
-- separately in docs/V5_PROGRAMME_DEFINITION.md. SEC-PHI-9 is NOT closed here
-- and the registry is not edited.

BEGIN;

-- The policy depends on the function; drop it first so the function can go.
DROP POLICY IF EXISTS "coach reads client progress photos" ON storage.objects;

DROP FUNCTION IF EXISTS public.is_active_coach_of(text);

-- Recreated verbatim except for the parameter name. Still delegates to the uuid
-- overload, so "active" keeps exactly one definition and cannot drift.
CREATE OR REPLACE FUNCTION public.is_active_coach_of(target_path text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN target_path IS NULL THEN false
           -- Fail closed on anything that is not a well-formed uuid rather than
           -- raising 22P02 from inside an RLS predicate.
           WHEN target_path !~*
             '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             THEN false
           ELSE public.is_active_coach_of(target_path::uuid)
         END;
$$;

REVOKE ALL ON FUNCTION public.is_active_coach_of(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_coach_of(text) TO authenticated;

COMMENT ON FUNCTION public.is_active_coach_of(text) IS
  'D3: the text-taking overload for predicates whose subject identifier is text '
  '(storage object paths). DELEGATES to is_active_coach_of(uuid) so the meaning '
  'of "active" has exactly one definition and cannot drift. Returns false -- '
  'never raises -- for NULL or non-uuid input. The parameter is named '
  '`target_path`, NOT `target_user`: PostgREST resolves RPC overloads by '
  'parameter name, and sharing the name with the uuid overload made every '
  '/rpc/is_active_coach_of call ambiguous (PGRST203). Migration 137.';

-- Recreated unchanged. The call is positional, so the parameter rename is
-- invisible here; this exists only because the function had to be dropped.
CREATE POLICY "coach reads client progress photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'progress-photos'
    AND public.is_active_coach_of((storage.foldername(name))[1])
  );

COMMIT;

-- ===========================================================================
-- WHAT THIS MIGRATION DOES NOT DO
-- ===========================================================================
--
--   * It does not change what "active" means, or the uuid overload, which is
--     untouched at 100:21-35.
--   * It does not change the progress-photos boundary -- the policy is
--     recreated with an identical predicate.
--   * It does not close SEC-PHI-9, SEC-PHI-10 or QAX-SEC-09.
--   * It does not revisit owner decision D3, which chose this overload.
