-- ═══════════════════════════════════════════════════════════════════════════
-- 158 · REMEDIATES A WRITE-ESCALATION DEFECT IN 156/157 — the three Admin views
--        were left holding Supabase's default write grants
--
-- WHAT WENT WRONG. 156 and 157 created three views and revoked privileges like
-- this:
--
--     REVOKE ALL ON public.<view> FROM PUBLIC;
--     REVOKE ALL ON public.<view> FROM anon;
--     GRANT SELECT ON public.<view> TO authenticated;
--
-- `authenticated` IS MISSING FROM THE REVOKE. Supabase ships
-- `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO authenticated`, so every
-- new view is born with INSERT, UPDATE and DELETE granted to authenticated, and a
-- later GRANT SELECT does not take those away. The established pattern in this
-- repository is one statement and names all three roles (118:106, 118:119):
--
--     REVOKE ALL ON public.<view> FROM PUBLIC, anon, authenticated;
--
-- WHY IT MATTERS, AND IT IS NOT THEORETICAL. All three views are
-- `security_invoker = off`, and admin_audit_events and
-- admin_integration_connections each select from exactly one table with no
-- aggregate, which makes them AUTO-UPDATABLE. A write through an auto-updatable
-- view runs as the VIEW'S OWNER, so base-table RLS does not constrain it. The
-- view's own WHERE still scopes which rows a write can reach -- which is why an
-- unassigned caller could touch nothing -- but a caller who HOLDS the area's View
-- grant sees rows through the view and could therefore write them.
--
-- PROVEN ON QA BEFORE THIS FIX (V5 §129.2): a user holding only the Admin-layer
-- `viewer` role -- which the approved matrix gives View and explicitly NOT Update,
-- Manage or Approve -- issued a DELETE through admin_integration_connections and
-- REMOVED ANOTHER USER'S integration row. Base RLS on user_integrations
-- ("user_own_integrations", auth.uid() = user_id) did not apply, because the write
-- executed as the view owner. That is a destructive privilege escalation and a
-- direct violation of the matrix this layer exists to enforce.
--
-- audit immutability was NOT breached: trg_audit_events_freeze (142:273) raises on
-- UPDATE and DELETE regardless of privilege, and triggers fire for the table owner
-- too. Defence in depth held where it existed. It did not exist on
-- user_integrations, which is where the escalation landed.
--
-- HOW IT WAS CAUGHT. Not by me -- by SEC-018, the standing guard in
-- apps/mobile/test/unit/profile_access_boundary_test.dart: "any view created after
-- 112 revokes its own write grants". It failed in CI on 9681ff6 (1703 passed, 1
-- failed) and names the exact mechanism in its own reason string: "Supabase
-- default privileges will have granted ALL". The guard was written for precisely
-- this mistake and it did its job.
--
-- Forward-only, like 157: 156/157 are already applied to QA.
-- ═══════════════════════════════════════════════════════════════════════════

REVOKE ALL ON public.admin_audit_events            FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_audit_events            TO authenticated;

REVOKE ALL ON public.admin_training_overview       FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_training_overview       TO authenticated;

REVOKE ALL ON public.admin_integration_connections FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_integration_connections TO authenticated;
