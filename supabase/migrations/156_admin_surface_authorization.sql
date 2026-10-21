-- ═══════════════════════════════════════════════════════════════════════════
-- 156 · ADMIN-SURFACE AUTHORIZATION — the seven authorized areas + the curated
--        audit projection
--
-- Owner authorization 2026-10-05, on the 17-area reconciliation (V5 §127).
-- Implements ONLY the areas the reconciliation classified safe, plus the curated
-- Audit-logs view. Everything else stays parked (V5 §128).
--
-- ADDITIVE BY CONSTRUCTION. Every grant below is a NEW permissive policy. No
-- existing policy is edited, dropped or replaced, so nothing any existing policy
-- allows or denies changes: PostgreSQL ORs permissive policies, and a new one can
-- only widen, never narrow. The widening is exactly the owner-approved matrix.
--
-- WHAT IS DELIBERATELY ABSENT, and why:
--  · Training ROW-LEVEL reads — parked as a PHI disclosure boundary. Training gets
--    an AGGREGATE view only; no arm touches workout_logs/sessions rows.
--  · A direct arm on audit_events — it would restore what A13·1 deliberately
--    excludes. The curated view below carries the exclusion instead.
--  · Security's own projection — its content is a CATEGORY filter over
--    audit_events and no authority maps A2's 15 categories to the Security area.
--    Mapping them here would be inventing scope.
--  · Users, Organization, QA, Releases, platform_settings, Incidents evidence —
--    all parked per the authorization.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · Community ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "admin layer reads community posts" ON public.community_posts;
CREATE POLICY "admin layer reads community posts" ON public.community_posts
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));
DROP POLICY IF EXISTS "admin layer reads post comments" ON public.post_comments;
CREATE POLICY "admin layer reads post comments" ON public.post_comments
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));
DROP POLICY IF EXISTS "admin layer reads post reactions" ON public.post_reactions;
CREATE POLICY "admin layer reads post reactions" ON public.post_reactions
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));
DROP POLICY IF EXISTS "admin layer reads community groups" ON public.community_groups;
CREATE POLICY "admin layer reads community groups" ON public.community_groups
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));
DROP POLICY IF EXISTS "admin layer reads accountability pods" ON public.accountability_pods;
CREATE POLICY "admin layer reads accountability pods" ON public.accountability_pods
  FOR SELECT TO authenticated USING (public.admin_can('Community', 'view'));

-- ── 2 · Events ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "admin layer reads events" ON public.events;
CREATE POLICY "admin layer reads events" ON public.events
  FOR SELECT TO authenticated USING (public.admin_can('Events', 'view'));
DROP POLICY IF EXISTS "admin layer reads event registrations" ON public.event_registrations;
CREATE POLICY "admin layer reads event registrations" ON public.event_registrations
  FOR SELECT TO authenticated USING (public.admin_can('Events', 'view'));
DROP POLICY IF EXISTS "admin layer reads classes" ON public.classes;
CREATE POLICY "admin layer reads classes" ON public.classes
  FOR SELECT TO authenticated USING (public.admin_can('Events', 'view'));
DROP POLICY IF EXISTS "admin layer reads class bookings" ON public.class_bookings;
CREATE POLICY "admin layer reads class bookings" ON public.class_bookings
  FOR SELECT TO authenticated USING (public.admin_can('Events', 'view'));

-- ── 3 · Monetization (entities only) ────────────────────────────────────────
DROP POLICY IF EXISTS "admin layer reads subscriptions" ON public.subscriptions;
CREATE POLICY "admin layer reads subscriptions" ON public.subscriptions
  FOR SELECT TO authenticated USING (public.admin_can('Monetization', 'view'));
DROP POLICY IF EXISTS "admin layer reads payments" ON public.payments;
CREATE POLICY "admin layer reads payments" ON public.payments
  FOR SELECT TO authenticated USING (public.admin_can('Monetization', 'view'));
DROP POLICY IF EXISTS "admin layer reads coach packages" ON public.coach_packages;
CREATE POLICY "admin layer reads coach packages" ON public.coach_packages
  FOR SELECT TO authenticated USING (public.admin_can('Monetization', 'view'));

-- ── 4 · Wearable intelligence / Integrations — ONE table, TWO areas ─────────
-- user_integrations backs both areas (V5 §127.4). The owner directed "the stricter
-- applicable authorization", so the caller must hold the grant for BOTH areas, not
-- either. That is strictly narrower than either alone and stays correct if the two
-- areas ever diverge in a future matrix.
DROP POLICY IF EXISTS "admin layer reads user integrations" ON public.user_integrations;
CREATE POLICY "admin layer reads user integrations" ON public.user_integrations
  FOR SELECT TO authenticated
  USING (public.admin_can('Wearable intelligence', 'view') AND public.admin_can('Integrations', 'view'));

-- ── 5 · System ──────────────────────────────────────────────────────────────
-- observability_events carries NO subject identifier (D12·Q5), so this arm is
-- A12-safe by construction.
DROP POLICY IF EXISTS "admin layer reads observability events" ON public.observability_events;
CREATE POLICY "admin layer reads observability events" ON public.observability_events
  FOR SELECT TO authenticated USING (public.admin_can('System', 'view'));

-- ── 6 · Settings › Roles — READ ONLY ────────────────────────────────────────
-- The approved matrix gives every role View and nothing else here. WRITES REMAIN
-- ON legacy is_admin(), exactly as 153 built them: the capability matrix does not
-- authorize self-grant or self-promotion, and nothing below creates that authority.
DROP POLICY IF EXISTS "admin layer reads role assignments" ON public.admin_role_assignments;
CREATE POLICY "admin layer reads role assignments" ON public.admin_role_assignments
  FOR SELECT TO authenticated USING (public.admin_can('Roles', 'view'));
DROP POLICY IF EXISTS "admin layer reads role capabilities" ON public.admin_role_capabilities;
CREATE POLICY "admin layer reads role capabilities" ON public.admin_role_capabilities
  FOR SELECT TO authenticated USING (public.admin_can('Roles', 'view'));

-- ── 7 · Training — AGGREGATE ONLY ───────────────────────────────────────────
-- Row-level training data is a parked PHI disclosure boundary. This view exposes
-- COUNTS and no member row, no user_id and no free text, so it cannot disclose an
-- individual's training history. security_invoker = off follows the D7 pattern
-- (101, 110); authorization lives in the WHERE, so the view is self-gating.
CREATE OR REPLACE VIEW public.admin_training_overview
WITH (security_invoker = off) AS
  SELECT
    (SELECT count(*) FROM public.workout_programs)  AS programs_total,
    (SELECT count(*) FROM public.workouts)          AS workouts_total,
    (SELECT count(*) FROM public.workout_sessions)  AS sessions_total,
    (SELECT count(*) FROM public.workout_logs)      AS logs_total
  WHERE public.admin_can('Training', 'view');

COMMENT ON VIEW public.admin_training_overview IS
  'V5 §128 · Training AGGREGATE surface. Counts only — no member row, no user_id. '
  'Row-level training reads remain a parked PHI disclosure boundary. Self-gating: '
  'returns no row unless admin_can(''Training'',''view'').';

REVOKE ALL ON public.admin_training_overview FROM PUBLIC;
REVOKE ALL ON public.admin_training_overview FROM anon;
GRANT SELECT ON public.admin_training_overview TO authenticated;

-- ── 8 · Audit logs — THE CURATED PROJECTION ────────────────────────────────
-- A13·1 excludes an admin's OWN admin_action rows from their view. A direct
-- `OR admin_can(...)` arm on audit_events would RESTORE exactly that. This view
-- carries the exclusion in its own predicate instead, so the control survives.
--
-- Properties, each deliberate:
--  · the A13·1 exclusion is reproduced verbatim in the WHERE;
--  · authorization is admin_can('Audit logs','view') — the view is self-gating;
--  · audit_events' own policy is NOT touched, so direct reads of the base table
--    remain exactly as restricted as before;
--  · A12 is preserved BY CONSTRUCTION — the view projects subject_pseudonym and
--    NEVER resolves it. §19.3 rules that NO STANDING PARTY may resolve a pseudonym
--    and that resolution "occurs INSIDE THE AUDIT READ PATH". A view is a standing
--    resolver by definition — precisely the argument 142 used to keep the coach arm
--    out of a table policy — so this view must not join audit_identity_map, and does
--    not. Callers needing subject_id keep using the 146/152 SECURITY DEFINER path;
--  · the column set is the ESTABLISHED projection of those read paths (146, 152),
--    with subject_pseudonym standing where they return the resolved subject_id. It
--    was conformed to them rather than invented;
--  · correlation_signature and correlation_key_id are DELIBERATELY ABSENT. They are
--    write-once correlation-integrity material, exposed to no reader anywhere in the
--    repository, and an Admin screen has no use for them.
CREATE OR REPLACE VIEW public.admin_audit_events
WITH (security_invoker = off) AS
  SELECT e.id, e.actor_id, e.subject_pseudonym, e.action, e.occurred_at,
         e.outcome, e.category, e.actor_provenance, e.correlation_id
    FROM public.audit_events e
   WHERE public.admin_can('Audit logs', 'view')
     AND NOT (e.category = 'admin_action' AND e.actor_id = (SELECT auth.uid()));

COMMENT ON VIEW public.admin_audit_events IS
  'V5 §128 · curated Admin projection of audit_events. Carries A13·1''s exclusion '
  '(an admin may not read their own admin_action rows) in its own predicate, so the '
  'control is preserved rather than bypassed. Gated on admin_can(''Audit logs'',''view''). '
  'audit_events'' own policy is unchanged. A12 holds by construction: the population '
  'carries subject_pseudonym, never a subject identifier.';

REVOKE ALL ON public.admin_audit_events FROM PUBLIC;
REVOKE ALL ON public.admin_audit_events FROM anon;
GRANT SELECT ON public.admin_audit_events TO authenticated;
