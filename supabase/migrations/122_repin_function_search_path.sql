-- Migration 122: restore the Phase 1 function posture that Phase 2 escaped.
--
-- ── What happened ───────────────────────────────────────────────────────────
--
-- Phase 1 pinned two properties on every function in `public`: a fixed
-- search_path, and no EXECUTE for PUBLIC or anon. Phase 2's migrations
-- (119, 120, 121) redefined ten functions and created five new ones, and each
-- new or replaced function escaped one or both. §1 and §2 below put each back,
-- by re-running Phase 1's own statements. Neither is a new rule.
--
-- ── §1. search_path — what happened ─────────────────────────────────────────
--
-- Phase 1 established the pin in two steps:
--   * 116 §1   — ALTER every SECURITY DEFINER function in `public` to
--                `SET search_path = public, pg_temp`.
--   * 118 F-08 — the same for the remaining SECURITY INVOKER functions.
-- After 118, EVERY function in `public` carried a pinned search_path. Both did
-- it with ALTER FUNCTION precisely so that no function body was touched.
--
-- `SET search_path` is part of a function's definition, not a grant. ACLs and
-- ownership survive CREATE OR REPLACE; proconfig does NOT. So every Phase 2
-- migration that redefined a function without repeating the clause silently
-- unpinned it. Live on QA before this migration — 15 functions, mapping 1:1 to
-- the three Phase 2 migrations, 2 of them SECURITY DEFINER:
--
--   119 → _plan_day_exercises, _wk_int, _wk_jint, _wk_jnum, _wk_num,
--         canonical_exercise_prescription, canonical_exercise_prescriptions,
--         is_canonical_exercise_prescription, program_workouts_canonicalize,
--         **materialize_program_week** (SECURITY DEFINER)
--   120 → workout_sessions_terminal_status, workout_set_logs_protect_history,
--         workout_set_logs_require_identity
--   121 → **generate_client_plan** (SECURITY DEFINER), plan_day_titles
--
-- A definer function without a pinned search_path resolves unqualified names
-- through the CALLER's search_path, so a caller who can create objects in a
-- schema earlier on that path can shadow a table or operator and have it run
-- with the definer's rights. That is the exact hole 116 was written to close,
-- and `generate_client_plan()` is client-callable (116's Class B allow-list).
--
-- ── Note on how this recurred ───────────────────────────────────────────────
--
-- This is the same failure mode as the OBS-4 defect it was found while fixing:
-- a CREATE OR REPLACE that reproduced a function from an older base and
-- silently dropped a property an intervening migration had added. 077 dropped
-- 052's day-title rule; 119/120/121 dropped 116/118's search_path pin. Both
-- were invisible in review because the replacement looked complete on its own.
-- The source-level guard for this one is SEC-028 in
-- `apps/mobile/test/unit/phase1_security_boundary_test.dart`.
--
-- ── §1. The fix ─────────────────────────────────────────────────────────────
--
-- 118's loop, re-run. Restoration, not a new policy: same predicate, same
-- setting, same ALTER FUNCTION mechanism, no function body touched, no grant
-- changed, no policy changed. Idempotent — a function that is already pinned is
-- not visited.

DO $$
DECLARE
  f record;
  n int := 0;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public'
       AND p.prokind = 'f'
       AND NOT EXISTS (
         SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', f.sig);
    n := n + 1;
  END LOOP;
  RAISE NOTICE '122: re-pinned search_path on % function(s)', n;
END $$;

-- Self-verifying: the migration asserts the posture it exists to restore rather
-- than trusting that the loop above covered everything.
DO $$
DECLARE
  v_left text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname) INTO v_left
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public'
     AND p.prokind = 'f'
     AND NOT EXISTS (
       SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%');
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'migration 122: function(s) still have a mutable '
      'search_path after the re-pin: %', v_left;
  END IF;
END $$;

-- ── §2. EXECUTE grants ──────────────────────────────────────────────────────
--
-- Migration 116 took EXECUTE back from PUBLIC and anon across the whole schema,
-- then re-granted an explicit allow-list to `authenticated`, and set ALTER
-- DEFAULT PRIVILEGES so future functions would inherit the closed posture.
--
-- Default privileges are recorded PER CREATING ROLE. The Phase 2 migrations
-- were applied through the CLI's own login role, not the role 116's
-- ALTER DEFAULT PRIVILEGES was recorded for, so the five functions they created
-- were born with Postgres's built-in default of EXECUTE TO PUBLIC. Live on QA
-- before this migration — four of them, all created by 119/120:
--
--   program_workouts_canonicalize()      workout_sessions_terminal_status()
--   workout_set_logs_protect_history()   workout_set_logs_require_identity()
--
-- All four are trigger functions and SECURITY INVOKER, so this was a posture
-- deviation rather than a live escalation: a trigger function cannot be called
-- directly, and EXECUTE on one is checked at CREATE TRIGGER, not when it fires.
-- The posture exists precisely so that nobody has to make that argument
-- function by function.
--
-- 116's statement, re-run. It targets PUBLIC and anon only — the `authenticated`
-- allow-list 116 granted is not touched, and neither is service_role or the
-- owner. Revoking does not disturb the existing triggers, which is what the
-- phase2-contract probe re-verifies.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

DO $$
DECLARE
  v_left text;
BEGIN
  SELECT string_agg(DISTINCT p.oid::regprocedure::text, ', ') INTO v_left
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace,
         aclexplode(p.proacl) a
   WHERE ns.nspname = 'public'
     AND (a.grantee = 0 OR a.grantee = 'anon'::regrole::oid)
     AND a.privilege_type = 'EXECUTE';
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'migration 122: function(s) still executable by PUBLIC or '
      'anon after the revoke: %', v_left;
  END IF;
END $$;

-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--
-- Both halves are restorations of Phase 1 statements, so there is no state to
-- roll back TO that is not itself the defect. To undo §1 on one function:
--   ALTER FUNCTION public.<name>(<args>) RESET search_path;
-- To undo §2:
--   GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO PUBLIC;
-- Neither should ever be run outside an incident; both re-open what 116 and 118
-- closed.
