-- 112_view_grants_read_only.sql
--
-- Closes a privilege-escalation hole found during the Stage B.4 post-rebuild
-- verification.
--
-- ── THE HOLE ────────────────────────────────────────────────────────────────
-- Supabase carries `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON
-- TABLES TO anon, authenticated, service_role`. That default fires when a VIEW
-- is created too, so every view in this schema was handed INSERT/UPDATE/DELETE
-- to `authenticated`. The REVOKE lines in migrations 101, 102 and 110 removed
-- PUBLIC and anon but never authenticated, so the write grant survived.
--
-- Three of the five public views are simple enough to be AUTO-UPDATABLE, and all
-- of them run with security_invoker = off -- so a write through the view executes
-- as the view OWNER (postgres) and is not filtered by the base table's RLS.
--
-- Verified against a byte-identical local replica of the rebuilt schema: an
-- authenticated user who could read ZERO rows of another user's user_profiles
-- was still able to run
--     UPDATE public.public_profiles SET first_name = 'PWNED' WHERE id = <victim>
-- and have it land on the base table. public_profiles projects `role`, so the
-- same path allowed self-promotion to role = 'coach'. `exercises` gave the same
-- write-through to custom_exercises (that one predates this work -- migration 058).
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
-- Every view in this schema is a read projection; no application code writes
-- through any of them (verified across apps/ -- all call sites are .select()).
-- So: revoke everything from anon and authenticated on every public view, then
-- grant back SELECT only. Applied by name so the intent is auditable, and
-- idempotent.
--
-- service_role keeps its grants: it is the trusted server-side identity and is
-- never exposed to a client.

DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('v', 'm')          -- views and materialized views
     ORDER BY c.relname
  LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', v.relname);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', v.relname);
    RAISE NOTICE '112: public.% is now SELECT-only for authenticated (anon: no access)', v.relname;
  END LOOP;
END $$;

-- NOT done here: narrowing ALTER DEFAULT PRIVILEGES. Postgres has no
-- view-only default-privilege class -- `ON TABLES` covers tables and views
-- alike -- so revoking write there would also strip INSERT/UPDATE/DELETE from
-- every future TABLE, which the app genuinely needs (table access is governed
-- by RLS, not by withholding the grant). Any NEW view therefore has to revoke
-- its own write grants the way 101/102/110 should have; the standing guard for
-- that is the view-grant test in the Flutter suite.

COMMENT ON SCHEMA public IS
  'Application schema. Views here are read projections: authenticated holds '
  'SELECT only (migration 112). A view that runs security_invoker = off writes '
  'as its owner and bypasses base-table RLS, so never grant a view write access.';
