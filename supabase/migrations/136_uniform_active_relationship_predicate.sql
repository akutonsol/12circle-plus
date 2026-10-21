-- 136_uniform_active_relationship_predicate.sql
--
-- V5 SECURITY FOUNDATION — P1 (FOUNDATION / SECURITY).
--
-- Migration number 136 assigned at phase entry per docs/MASTER_REMEDIATION_WAVES.md
-- section 0.2 ("132+ ... assigned at wave entry, never before").
--
-- Executes owner decision D3, recorded verbatim in docs/V5_PROGRAMME_DEFINITION.md
-- section 19.1:
--
--   "D3 — ANSWERED: YES, UNIFORMLY, via (b) the `is_active_coach_of(text)`
--    overload."
--
-- The recorded rationale: a non-uniform status predicate grants access on
-- INACTIVE relationships -- a standing privilege leak -- and a single helper is
-- one place to audit and cannot drift across policies, where inline predicates
-- demonstrably did.
--
-- ===========================================================================
-- THE POPULATION — "2 of 5", CONFIRMED BY ENUMERATION, NOT ASSUMED
-- ===========================================================================
--
-- Five migrations carry an INLINE relationship-consuming predicate. Three
-- already require `status = 'active'`; two do not:
--
--   005_custom_exercises.sql:66,136        status = 'active'    OK
--   026_coach_client_event_notifications:27 status = 'active'   OK
--   036_client_plan_and_coach_media.sql:12  status = 'active'   OK
--   029_progress_photos_storage_rls.sql:41  NO STATUS       <-- SEC-PHI-9
--   035_scoring_engine.sql:184              NO STATUS       <-- SEC-PHI-10
--
-- That is exactly the "2 of 5 policies omit it" recorded as D3's evidence.
-- Both target policies were checked for supersession: neither is redefined by
-- any later migration, so both are live as written.
--
-- 029's own comment reads "Coach: read an ACTIVE client's photos" while its
-- predicate enforces no such thing. A coach whose relationship is `pending`,
-- `ended` or any other status reads the client's progress and transformation
-- photographs. 035 is the same defect over `score_events`.
--
-- ===========================================================================
-- WHY A text OVERLOAD, AND WHY IT DELEGATES RATHER THAN DUPLICATES
-- ===========================================================================
--
-- 029's predicate compares against `(storage.foldername(name))[1]`, which is
-- TEXT extracted from a storage object path. The existing helper takes uuid.
-- D3 chose the overload rather than an inline predicate precisely so there is
-- one definition of "is an active coach of".
--
-- The overload therefore DELEGATES to the uuid implementation. It does not
-- restate the predicate. This is the property that makes drift impossible: if
-- the meaning of "active" ever changes, it changes in one place (100:21-35) and
-- both overloads follow. A copied predicate would not.
--
-- FAIL-CLOSED ON NON-UUID INPUT. `(storage.foldername(name))[1]` is
-- user-controlled text from an object path and is not guaranteed to be a uuid.
-- A bare `target_user::uuid` would raise 22P02 (`invalid input syntax for type
-- uuid`) from inside an RLS predicate -- which is a QUERY ERROR, not a denial.
-- The guard below returns false for anything that is not a well-formed uuid, so
-- a malformed path denies rather than errors. The previous inline predicate
-- compared `r.client_id::text = <text>`, which never raised; preserving
-- fail-closed behaviour is therefore a requirement of this change, not a
-- refinement.
--
-- ===========================================================================
-- A SECOND DEFECT THIS CLOSES INCIDENTALLY, RECORDED SO IT IS NOT MISSED
-- ===========================================================================
--
-- Both target policies read `coach_client_relationships` DIRECTLY from inside a
-- policy predicate. Migration 113 put RLS on that table. 100:18-19 records why
-- the helper is SECURITY DEFINER: "so the check can read
-- coach_client_relationships regardless of that table's own RLS (prevents
-- recursive policy evaluation)". Routing both policies through the helper
-- removes that recursion exposure as well.
--
-- ===========================================================================
-- EVIDENCE CEILING — STATED SO IT IS NOT OVERCLAIMED
-- ===========================================================================
--
-- docs/QA_CLOSURE_STANDARD.md section 5.2 requires VERIFIED LIVE for a security
-- finding. NO DATABASE WAS CONTACTED. This reaches FIXED IN CODE only.
-- SEC-PHI-9 AND SEC-PHI-10 ARE NOT CLOSED by this file and their registry
-- statuses are unchanged.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The text overload. Delegates; does not duplicate.
--
--    `SET search_path = public, pg_temp` is the canonical pinned form
--    established by migration 122 and asserted by the existing guards.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_active_coach_of(target_user text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN target_user IS NULL THEN false
           -- Fail closed on anything that is not a well-formed uuid rather than
           -- raising 22P02 from inside an RLS predicate.
           WHEN target_user !~*
             '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             THEN false
           ELSE public.is_active_coach_of(target_user::uuid)
         END;
$$;

-- Grant posture mirrors the uuid overload exactly (100:37-38).
REVOKE ALL ON FUNCTION public.is_active_coach_of(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_coach_of(text) TO authenticated;

COMMENT ON FUNCTION public.is_active_coach_of(text) IS
  'D3: the text-taking overload for predicates whose subject identifier is text '
  '(storage object paths). DELEGATES to is_active_coach_of(uuid) so the meaning '
  'of "active" has exactly one definition and cannot drift. Returns false -- '
  'never raises -- for NULL or non-uuid input, so a malformed storage path '
  'denies rather than erroring inside an RLS predicate.';

-- ---------------------------------------------------------------------------
-- 2. SEC-PHI-9 — progress photos. storage.objects.
--
--    Was: an inline EXISTS over coach_client_relationships with NO status
--    condition, despite the policy's own comment claiming "active".
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "coach reads client progress photos" ON storage.objects;
CREATE POLICY "coach reads client progress photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'progress-photos'
    AND public.is_active_coach_of((storage.foldername(name))[1])
  );

-- ---------------------------------------------------------------------------
-- 3. SEC-PHI-10 — score events.
--
--    Was: an inline EXISTS over coach_client_relationships with NO status
--    condition. The subject identifier is uuid here, so this uses the existing
--    typed overload directly.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "coach reads client events" ON score_events;
CREATE POLICY "coach reads client events"
  ON score_events FOR SELECT TO authenticated
  USING (public.is_active_coach_of(score_events.user_id));

COMMIT;

-- ===========================================================================
-- WHAT THIS MIGRATION DOES NOT DO
-- ===========================================================================
--
--   * It does not close SEC-PHI-9 or SEC-PHI-10. No database was contacted;
--     the evidence reaches FIXED IN CODE only and the registry is not edited.
--   * It does not alter is_active_coach_of(uuid). The typed implementation at
--     100:21-35 is untouched, and the overload delegates to it.
--   * It does not touch the three policies that already carry the status
--     condition (005, 026, 036). D3 is satisfied by making the population
--     uniform, not by rewriting predicates that were already correct.
--   * It does not change the `own score events` or `own progress photos`
--     self-access policies -- a member's access to their own rows is unaffected.
--   * It invents no lifecycle semantics. "Active" means exactly what
--     coach_client_relationships.status = 'active' already meant; this file
--     adds no new state, transition or expiry.
