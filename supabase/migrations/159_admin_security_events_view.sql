-- ═══════════════════════════════════════════════════════════════════════════
-- 159 · THE SECURITY AREA PROJECTION — owner decision B-1, 2026-10-05
--
-- V5 §129.4's boundary B-1 asked which of `A2`'s fifteen audit categories
-- constitute the `Security` area. No document mapped them, so choosing would have
-- been inventing product scope. The owner decided: **access-control oversight** --
--
--     authentication · authorization_denial · admin_action · audit_read
--
-- Deliberately NOT in scope, each for a stated reason:
--   · `incident`                     -> the Incidents area owns it (B-4, parked)
--   · `phi_read`, `phi_correction`   -> Trust
--   · `financial`, `billing_entitlement` -> Monetization
--   · `agent_action`                 -> AI Guardian (B-17)
--   · `control_evidence`, `storage_media_access` -> offered and NOT taken. They
--     were the third option; the owner chose the narrower one. They are not
--     "missing" and must not be added without a new decision.
--   · `relationship_change`, `export_deletion`, `observability_audit` -> not
--     offered; outside access-control oversight.
--
-- This is the SAME curated-view architecture the owner authorized for Audit logs
-- and which 156 proved. Four properties are carried over deliberately:
--
--  1. A13·1 IS PRESERVED INSIDE THIS PROJECTION TOO. `admin_action` is in scope,
--     so the exclusion matters here exactly as it does for Audit logs: a reader
--     never sees their OWN admin_action rows. The clause is reproduced verbatim.
--     Without it, adding admin_action to a second surface would have quietly
--     restored what A13·1 removes from the first.
--  2. NO PSEUDONYM RESOLUTION. §19.3 rules that no standing party may resolve a
--     pseudonym and that resolution occurs inside the audit read path. A view is a
--     standing resolver by definition -- the argument 142 used for the coach arm --
--     so this view projects subject_pseudonym and joins no identity map. A12 holds
--     by construction.
--  3. `delta` AND `changed_columns` ARE WITHHELD. Owner decision B-19, same date:
--     withhold both. They exist (added by 150, A6 delta capture) and the
--     established 146/152 read paths omit them. Not an oversight -- a decision.
--  4. THE WRITE GRANTS ARE REVOKED IN THIS MIGRATION, not a later one. 156/157
--     revoked from PUBLIC and anon but not `authenticated`, and because Supabase
--     grants ALL on a new view by default, a View-only Viewer could DELETE through
--     one (V5 §129.2). SEC-018 caught it and 158 fixed it forward. The revoke
--     below is the established 118 pattern, in the same statement, naming all
--     three roles.
--
-- Gated on admin_can('Security','view'), which the approved matrix grants to
-- trust_lead, operations_lead and viewer, and DENIES to support and
-- content_editor. The matrix is unchanged by this migration.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.admin_security_events
WITH (security_invoker = off) AS
  SELECT e.id, e.actor_id, e.subject_pseudonym, e.action, e.occurred_at,
         e.outcome, e.category, e.actor_provenance, e.correlation_id
    FROM public.audit_events e
   WHERE public.admin_can('Security', 'view')
     AND e.category = ANY (ARRAY['authentication', 'authorization_denial',
                                 'admin_action', 'audit_read'])
     AND NOT (e.category = 'admin_action' AND e.actor_id = (SELECT auth.uid()));

COMMENT ON VIEW public.admin_security_events IS
  'V5 §132 · the Security area projection. Owner decision B-1: access-control '
  'oversight -- authentication, authorization_denial, admin_action, audit_read. '
  'control_evidence and storage_media_access were offered and NOT chosen; do not '
  'add them without a new decision. Carries A13.1 in its own predicate (a reader '
  'never sees their own admin_action rows), projects subject_pseudonym and never '
  'resolves it, and withholds delta/changed_columns per owner decision B-19. '
  'audit_events own policy is untouched.';

REVOKE ALL ON public.admin_security_events FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_security_events TO authenticated;
