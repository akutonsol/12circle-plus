-- ═══════════════════════════════════════════════════════════════════════════
-- 163 · THE AI GUARDIAN GRANT WAS INERT — the registry never honoured it
--
-- The owner-approved matrix grants `AI Guardian · View` to trust_lead,
-- operations_lead and viewer. The registry 154 created reads under
--
--     USING (public.is_admin() OR public.is_trust_operator())
--
-- and an Admin-layer `trust_lead` is NEITHER. CONF-D7 ruled explicitly that Trust
-- lead must NOT be mapped to the `trust_operator` database role, and 153 built the
-- Admin layer so that is_admin() stays FALSE for every Admin-layer principal —
-- which is the property D13 exists to protect.
--
-- So the grant was real in the matrix and did nothing in the database. Measured
-- live before this migration: admin_can('AI Guardian','view') returned TRUE for an
-- assigned trust_lead while the registry returned no rows to them.
--
-- THE DESIGN→ARCHITECTURE UNION RULE APPLIES HERE EXACTLY. An approved capability
-- must not be dropped because the backend lacks support; the architecture is
-- extended instead. Nothing here is a new authorization decision — the matrix
-- already decided WHO may view AI Guardian, and this makes that decision effective.
--
-- WHAT THIS IS NOT:
--   · not a change to the matrix — no grant is added, removed or reinterpreted;
--   · not an enforcement point. 154's registry remains DOCUMENTATION ONLY, and
--     §13's deterministic authority is untouched: admin_can() and RLS still decide
--     everything. Reading a policy document does not make it one;
--   · not the AI Guardian RUNTIME. The Dashboard card's autonomy level, "awaiting
--     human review" and "recommendations · 24h" come from a telemetry surface that
--     does not exist. That stays V5 §129.4 B-17;
--   · not write access. Writes remain is_admin() only, exactly as 154 built them,
--     so the Admin layer can read the governance record and cannot author it.
--
-- Additive: five NEW permissive SELECT policies. No existing policy is edited, so
-- is_admin() and is_trust_operator() keep every read they already had.
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "admin layer reads governance policy" ON public.governance_policy;
CREATE POLICY "admin layer reads governance policy" ON public.governance_policy
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));

DROP POLICY IF EXISTS "admin layer reads governance policy version" ON public.governance_policy_version;
CREATE POLICY "admin layer reads governance policy version" ON public.governance_policy_version
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));

DROP POLICY IF EXISTS "admin layer reads governance policy rule" ON public.governance_policy_rule;
CREATE POLICY "admin layer reads governance policy rule" ON public.governance_policy_rule
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));

DROP POLICY IF EXISTS "admin layer reads governance policy set" ON public.governance_policy_set;
CREATE POLICY "admin layer reads governance policy set" ON public.governance_policy_set
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));

DROP POLICY IF EXISTS "admin layer reads governance policy set member" ON public.governance_policy_set_member;
CREATE POLICY "admin layer reads governance policy set member" ON public.governance_policy_set_member
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));
