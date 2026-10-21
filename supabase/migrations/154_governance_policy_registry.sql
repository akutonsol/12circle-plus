-- ═══════════════════════════════════════════════════════════════════════════
-- 154 · GOVERNANCE POLICY REGISTRY — the documentation / auditability layer
--
-- Owner-approved direction (V5 §105, §114.2): implement the registry ONLY as a
-- documentation and auditability layer. IT MUST NOT BECOME AN ENFORCEMENT POINT.
--
-- WHY IT CANNOT ENFORCE, stated here so no later change forgets it:
-- COWORK_ENGINEERING_GOVERNANCE §13 — "the deterministic system remains
-- authoritative for enforceable contracts, including authorization" — and §9 —
-- "no remediation may weaken Row Level Security; authorization; ... SECURITY
-- DEFINER boundaries". Authorization is enforced by RLS and the SQL predicates
-- (is_admin, is_trust_operator, is_erasure_executor, and 153's admin_can).
-- THIS REGISTRY DESCRIBES THOSE PREDICATES. It is read BY people, never BY a
-- policy. No RLS policy anywhere may call into these tables to decide access.
--
-- NAMING — V5 §114.2. `governance_*`, not `policy_*` and not `guardian_*`.
-- `policy_*` collides with PostgreSQL's own concept, of which this repository has
-- 405 CREATE/DROP POLICY statements; `guardian_*` would couple security to the AI
-- Guardian in the schema itself, which A10 forbids ("security controls remain
-- independent of the AI Guardian") — and this registry carries RB-nn
-- AUTHORIZATION policies, not only AI ones.
--
-- SCOPE: the four policy entities only. `principal` and `resource` are not policy
-- entities and are deferred; `policy_evaluation` goes to observability_events
-- under direction B and is deferred with the D12 component vocabulary it needs.
--
-- Purely additive. No existing table, function, policy or grant is touched.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.governance_policy (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,      -- the design's coded form: RB-01, DA-07
  name        text NOT NULL,             -- "Export scope limits"
  category    text NOT NULL,
  scope       text,                      -- applicability: "All agents", a role, …
  owner_id    uuid REFERENCES public.user_profiles(id),
  status      text NOT NULL DEFAULT 'draft',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT governance_policy_status_check
    CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'retired'::text])),
  CONSTRAINT governance_policy_category_check
    CHECK (category = ANY (ARRAY[
      'data_access'::text,     -- DA- · "Export scope limits"
      'human_approval'::text,  -- "Bulk messaging approval"
      'privacy'::text,         -- "Health data minimisation"
      'model_usage'::text,     -- "Model allow-list"
      'safety'::text,          -- "Moderation escalation"
      'role_based'::text       -- RB- · the authorization family
    ]))
);

COMMENT ON TABLE public.governance_policy IS
  'V5 §114.2 · DOCUMENTATION LAYER ONLY. Describes the deterministic authorization '
  'and governance rules enforced elsewhere (RLS, SQL predicates). No RLS policy may '
  'read this table to decide access — that would make the registry an enforcement '
  'point, which COWORK governance §13 forbids.';

-- A policy's versions. The design shows v1..v11, an effective-from with a TIME,
-- a change note in prose, and retirement by an individual OR a body
-- ("v6 retired after review — Security review board"), so retired_by is text and
-- not a user reference.
CREATE TABLE IF NOT EXISTS public.governance_policy_version (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id      uuid NOT NULL REFERENCES public.governance_policy(id) ON DELETE CASCADE,
  version        integer NOT NULL,
  effective_from timestamptz,
  change_note    text,                   -- "limit lowered from 200 to 50"
  authored_by    uuid REFERENCES public.user_profiles(id),
  retired_at     timestamptz,
  retired_by     text,                   -- an individual OR a body
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (policy_id, version),
  CONSTRAINT governance_policy_version_positive CHECK (version > 0)
);

-- Rules are first-class: the design displays a COUNT ("Rules 2 — record count
-- <= 50 · roster match"), which an opaque blob could not produce.
CREATE TABLE IF NOT EXISTS public.governance_policy_rule (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.governance_policy_version(id) ON DELETE CASCADE,
  ordinal    integer NOT NULL,
  expression text NOT NULL,              -- "record count <= 50"
  UNIQUE (version_id, ordinal)
);

-- A policy SET is versioned independently of its policies: the design shows
-- "policy set v3.14 · 28 active policies" alongside per-policy v7/v3/v5/v11.
CREATE TABLE IF NOT EXISTS public.governance_policy_set (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_version          text NOT NULL UNIQUE,   -- "v3.14"
  last_full_evaluation timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.governance_policy_set_member (
  set_id     uuid NOT NULL REFERENCES public.governance_policy_set(id) ON DELETE CASCADE,
  version_id uuid NOT NULL REFERENCES public.governance_policy_version(id) ON DELETE CASCADE,
  PRIMARY KEY (set_id, version_id)
);

COMMENT ON TABLE public.governance_policy_set IS
  'V5 §105.1 · a policy set carries its OWN version, independent of its member '
  'policy versions — the approved design shows both, so one cannot be derived '
  'from the other.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Read: Trust and full admin. Trust lead's database counterpart is
-- trust_operator (V5 §107.2), and under direction C the Guardian policy surfaces
-- live in Trust. Write: full is_admin() only — authoring governance policy is a
-- high-impact administrative act, and 153's graded layer deliberately confers
-- nothing here until the design's capability cells exist.
-- A12: no table below carries a subject identifier, so no re-identification path
-- is created.
ALTER TABLE public.governance_policy            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_policy_version    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_policy_rule       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_policy_set        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_policy_set_member ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "governance policy read" ON public.governance_policy;
CREATE POLICY "governance policy read" ON public.governance_policy
  FOR SELECT TO authenticated USING (public.is_admin() OR public.is_trust_operator());
DROP POLICY IF EXISTS "governance policy write" ON public.governance_policy;
CREATE POLICY "governance policy write" ON public.governance_policy
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "governance policy version read" ON public.governance_policy_version;
CREATE POLICY "governance policy version read" ON public.governance_policy_version
  FOR SELECT TO authenticated USING (public.is_admin() OR public.is_trust_operator());
DROP POLICY IF EXISTS "governance policy version write" ON public.governance_policy_version;
CREATE POLICY "governance policy version write" ON public.governance_policy_version
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "governance policy rule read" ON public.governance_policy_rule;
CREATE POLICY "governance policy rule read" ON public.governance_policy_rule
  FOR SELECT TO authenticated USING (public.is_admin() OR public.is_trust_operator());
DROP POLICY IF EXISTS "governance policy rule write" ON public.governance_policy_rule;
CREATE POLICY "governance policy rule write" ON public.governance_policy_rule
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "governance policy set read" ON public.governance_policy_set;
CREATE POLICY "governance policy set read" ON public.governance_policy_set
  FOR SELECT TO authenticated USING (public.is_admin() OR public.is_trust_operator());
DROP POLICY IF EXISTS "governance policy set write" ON public.governance_policy_set;
CREATE POLICY "governance policy set write" ON public.governance_policy_set
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "governance policy set member read" ON public.governance_policy_set_member;
CREATE POLICY "governance policy set member read" ON public.governance_policy_set_member
  FOR SELECT TO authenticated USING (public.is_admin() OR public.is_trust_operator());
DROP POLICY IF EXISTS "governance policy set member write" ON public.governance_policy_set_member;
CREATE POLICY "governance policy set member write" ON public.governance_policy_set_member
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

REVOKE ALL ON TABLE public.governance_policy            FROM anon;
REVOKE ALL ON TABLE public.governance_policy_version    FROM anon;
REVOKE ALL ON TABLE public.governance_policy_rule       FROM anon;
REVOKE ALL ON TABLE public.governance_policy_set        FROM anon;
REVOKE ALL ON TABLE public.governance_policy_set_member FROM anon;

-- No policy rows are seeded. The RB-nn and DA-nn policies the approved design
-- displays are design data; inventing their text would be inventing governance.
