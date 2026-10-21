-- ═══════════════════════════════════════════════════════════════════════════
-- 157 · REMEDIATES A DEFECT IN 156 — the Wearable / Integrations surface must
--        never carry OAuth bearer tokens
--
-- WHAT 156 GOT WRONG. It put a blanket SELECT arm on public.user_integrations:
--
--   CREATE POLICY "admin layer reads user integrations" ON public.user_integrations
--     FOR SELECT TO authenticated
--     USING (admin_can('Wearable intelligence','view') AND admin_can('Integrations','view'));
--
-- user_integrations carries access_token and refresh_token. The approved matrix
-- grants Wearable/Integrations View to ALL FIVE Admin roles, so that arm handed
-- every Viewer, Support agent and Content editor the live OAuth bearer tokens for
-- every user's wearable account — credentials that permit impersonating the user
-- against the upstream provider. It is a credential disclosure, not a reporting
-- surface, and it is the one table among the sixteen that 156 touched which
-- carries a secret at all (the other fifteen were audited: payments and
-- subscriptions hold Stripe IDENTIFIERS, which are references, not credentials).
--
-- COWORK_ENGINEERING_GOVERNANCE §9 is explicit that no remediation may weaken
-- authorization, and the standing constraint "do not grant broad admin access as
-- a shortcut" names this exact shape. Caught before any push, any CI run and any
-- UI consumer, but AFTER 156 was applied to QA — so it is remediated forward
-- rather than by editing an applied migration.
--
-- NO APPROVED CAPABILITY IS LOST (V5 §102). The Admin design shows integration
-- CONNECTION STATUS — which provider, connected or not, since when. Every one of
-- those fields is below. Nothing in the approved design displays a token, and a
-- token could not be rendered usefully if it did.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · withdraw the over-broad arm ─────────────────────────────────────────
-- Dropping a policy 156 added cannot narrow anything that predates 156: the
-- table's original "user_own_integrations" policy (011) is untouched, so a user's
-- own rows remain exactly as readable as they have always been.
DROP POLICY IF EXISTS "admin layer reads user integrations" ON public.user_integrations;

-- ── 2 · the column-limited replacement, D7 pattern ──────────────────────────
-- security_invoker = off follows 101/110, so the view reads across users; the
-- authorization lives in the WHERE, making the view self-gating. The "stricter
-- applicable authorization" the owner directed is the AND: the caller must hold
-- View on BOTH areas that share this table, which is narrower than either alone
-- and stays correct if the two areas ever diverge.
CREATE OR REPLACE VIEW public.admin_integration_connections
WITH (security_invoker = off) AS
  SELECT i.id, i.user_id, i.provider, i.connected, i.connected_at, i.disconnected_at
    FROM public.user_integrations i
   WHERE public.admin_can('Wearable intelligence', 'view')
     AND public.admin_can('Integrations', 'view');

COMMENT ON VIEW public.admin_integration_connections IS
  'V5 §128 · Admin-facing projection of user_integrations for the Wearable '
  'intelligence and Integrations areas. access_token and refresh_token are '
  'DELIBERATELY ABSENT — they are OAuth bearer credentials and no Admin surface '
  'displays them. Replaces the blanket RLS arm 156 added, which would have '
  'disclosed them to all five Admin roles. Gated on the View grant of BOTH areas.';

REVOKE ALL ON public.admin_integration_connections FROM PUBLIC;
REVOKE ALL ON public.admin_integration_connections FROM anon;
GRANT SELECT ON public.admin_integration_connections TO authenticated;
