-- Migration 109: track the auth.users -> handle_new_user() trigger
--
-- ── WHY THIS MIGRATION EXISTS ───────────────────────────────────────────────
-- Migration 044 defines public.handle_new_user(), which inserts a
-- public.user_profiles row for every new auth.users row. But NOTHING in the
-- tracked migration sequence (001-108, or the APPLY_*.sql helper scripts) ever
-- created the TRIGGER that calls it. The trigger was created out-of-band in
-- production -- almost certainly by hand in the Supabase SQL editor / dashboard
-- -- so it exists only in that one database and in no source file.
--
-- The Stage A.6 QA integrity audit confirmed the consequence: QA has the
-- function but ZERO non-internal triggers on auth.users. Every QA signup would
-- create an auth.users row with no matching user_profiles row, which breaks
-- essentially the whole app (routing, onboarding, profile, coach linkage) --
-- and no amount of replaying 001-108 would ever fix it, because the object is
-- not in any migration.
--
-- This migration brings that object under source control so a rebuilt QA, a
-- preview branch, a local stack, and a production restore all converge on the
-- same wiring.
--
-- ── SAFE TO APPLY TO PRODUCTION (but not applied by this change) ────────────
-- Production already has an equivalent trigger. Re-running this there must not
-- create a SECOND one, because two triggers would each INSERT into
-- user_profiles and the duplicate would raise a PK violation, breaking signup.
-- Production's trigger name could not be verified (production was deliberately
-- not inspected during the QA remediation), so this migration does not assume
-- it. Instead it drops ANY trigger on auth.users that calls
-- public.handle_new_user(), whatever its name, and then creates the canonical
-- one. That makes it idempotent and name-agnostic in every environment.
--
-- Applying this file is a separate, explicit step. It is not executed here.

DO $$
DECLARE
  v_fn   oid;
  v_trig record;
BEGIN
  -- auth.users only exists on a real Supabase stack; no-op on a bare Postgres.
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE '109: auth.users not present -- skipping trigger creation';
    RETURN;
  END IF;

  -- The function comes from migration 044; refuse to guess if it is missing.
  SELECT p.oid INTO v_fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'handle_new_user'
     AND p.pronargs = 0;

  IF v_fn IS NULL THEN
    RAISE EXCEPTION '109: public.handle_new_user() not found -- apply migration 044 first';
  END IF;

  -- Drop every existing trigger on auth.users bound to that function,
  -- regardless of name, so we can never end up with two.
  FOR v_trig IN
    SELECT t.tgname
      FROM pg_trigger t
      JOIN pg_class c  ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'auth'
       AND c.relname = 'users'
       AND NOT t.tgisinternal
       AND t.tgfoid = v_fn
  LOOP
    EXECUTE format('DROP TRIGGER %I ON auth.users', v_trig.tgname);
    RAISE NOTICE '109: dropped pre-existing trigger % on auth.users', v_trig.tgname;
  END LOOP;

  EXECUTE $ddl$
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_user()
  $ddl$;

  RAISE NOTICE '109: created trigger on_auth_user_created on auth.users';
END
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Creates the public.user_profiles row for a new auth.users row. Wired up by '
  'the on_auth_user_created trigger in migration 109. Defined in migration 044.';
