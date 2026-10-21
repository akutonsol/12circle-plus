-- ═══════════════════════════════════════════════════════════════════════════
-- 153 · GRADED ADMIN AUTHORIZATION — the Admin-layer principal dimension
--
-- Owner-approved direction A (V5 §113): an additive SQL/RLS predicate model
-- giving differentiated Admin authority to Operations lead, Support and Viewer
-- without granting them full `admin`.
--
-- CONF-D7 = Option 3 (V5 §107): the five Admin roles are a PRODUCT/ADMIN-FACING
-- LAYER ABOVE the four admin-class database roles. They are therefore NOT values
-- of `user_profiles.role`, and this migration adds none.
--
-- WHY THE LAYER IS KEYED SEPARATELY — the load-bearing decision.
-- `is_admin()` is binary (`role = 'admin'`) and `'admin'` appears in 14 inline
-- RLS clauses. Letting a Viewer in by giving them `role='admin'` would hand them
-- all fourteen. So Admin-layer membership lives in its own relation and
-- `is_admin()` is left to mean exactly what it has always meant.
--
-- PRIVILEGE-NEUTRAL ON APPLICATION. No capability row is seeded, so
-- `admin_can()` is false for every caller, every area, every verb at apply time.
-- The cell grants are DESIGN DATA this migration does not hold (V5 §10.2: the
-- matrix cells were not extractable from the approved pages) and inventing them
-- would be inventing authorization.
--
-- PRESERVED, UNTOUCHED: the seven role values; `is_admin()`;
-- `is_trust_operator()`; `is_erasure_executor()` and severance; all 202 existing
-- policies; A12's identity map (RLS, zero policies, definer path only).
-- A12 identity resolution remains TRUST-ONLY — nothing here confers it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── The Admin-layer population ──────────────────────────────────────────────
-- "People who can sign in to the admin" — the Settings > Administrators surface.
-- Disjoint by construction from `user_profiles.role`, which keeps describing the
-- member/admin-class population it always has.
CREATE TABLE IF NOT EXISTS public.admin_role_assignments (
  user_id     uuid PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  admin_role  text NOT NULL,
  granted_by  uuid REFERENCES public.user_profiles(id),
  granted_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_role_assignments_role_check
    CHECK (admin_role = ANY (ARRAY[
      'trust_lead'::text,       -- "Security, AI oversight and audit"
      'operations_lead'::text,  -- "QA, releases, integrations, system"
      'support'::text,          -- "Members and bookings, read-mostly"
      'content_editor'::text,   -- "Community and training content"
      'viewer'::text            -- "Read-only across the admin"
    ]))
);

COMMENT ON TABLE public.admin_role_assignments IS
  'V5 §113 · the Admin-layer principal. CONF-D7 Option 3: a layer ABOVE the four '
  'admin-class database roles, not a replacement for them. Keyed separately from '
  'user_profiles.role so that Admin-layer membership never satisfies is_admin() '
  'and therefore never inherits the 14 inline RLS clauses that name ''admin''.';

-- ── The capability grid ─────────────────────────────────────────────────────
-- area and verb are DATA, not enum types: the approved design's area list was not
-- fully extractable (V5 §10.1), and a type would bake an incomplete vocabulary
-- into DDL. Rows are correctable without a migration.
CREATE TABLE IF NOT EXISTS public.admin_role_capabilities (
  admin_role text NOT NULL,
  area       text NOT NULL,
  verb       text NOT NULL,
  PRIMARY KEY (admin_role, area, verb),
  CONSTRAINT admin_role_capabilities_role_check
    CHECK (admin_role = ANY (ARRAY[
      'trust_lead'::text, 'operations_lead'::text, 'support'::text,
      'content_editor'::text, 'viewer'::text
    ])),
  CONSTRAINT admin_role_capabilities_verb_check
    CHECK (verb = ANY (ARRAY[
      'view'::text, 'create'::text, 'update'::text, 'manage'::text, 'approve'::text
    ]))
);

COMMENT ON TABLE public.admin_role_capabilities IS
  'V5 §113 · the design''s role x area x verb grid. DELIBERATELY EMPTY at '
  'application: admin_can() is deny-by-default, so this migration is '
  'privilege-neutral. The cell grants are design data (V5 §10.2 records the '
  'matrix cells as unextractable) and are not invented here. Access level '
  '(Full/Limited/Read-only) is COMPUTED from this grid, never stored — two '
  'sources of truth can silently disagree with enforcement.';

-- ── Predicates ──────────────────────────────────────────────────────────────
-- Posture matches is_admin()/is_trust_operator()/is_erasure_executor() exactly:
-- sql STABLE SECURITY DEFINER, search_path pinned, owned by postgres, EXECUTE
-- revoked from PUBLIC and anon, granted only to authenticated. No service_role
-- grant is needed and none is given.

-- Entry to the Admin surfaces. THIS IS NOT is_admin() AND MUST NEVER BE
-- SUBSTITUTED FOR IT: is_admin() means a full database admin; this means a person
-- who may open the Admin Control Center at some level.
CREATE OR REPLACE FUNCTION public.is_admin_member() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_role_assignments
    WHERE user_id = (SELECT auth.uid())
  );
$$;
ALTER FUNCTION public.is_admin_member() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_admin_member() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin_member() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin_member() TO authenticated;

COMMENT ON FUNCTION public.is_admin_member() IS
  'V5 §113 · Admin-layer membership. NOT is_admin(). Gates entry only; every '
  'differentiated authority goes through admin_can().';

-- The enforcement predicate. Deny by default.
CREATE OR REPLACE FUNCTION public.admin_can(p_area text, p_verb text) RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.admin_role_assignments a
      JOIN public.admin_role_capabilities c ON c.admin_role = a.admin_role
     WHERE a.user_id = (SELECT auth.uid())
       AND c.area    = p_area
       AND c.verb    = p_verb
  );
$$;
ALTER FUNCTION public.admin_can(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_can(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_can(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_can(text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_can(text, text) IS
  'V5 §113 · the Admin-layer enforcement predicate, deny-by-default. Confers NO '
  're-identification: A12 identity resolution remains Trust-only through '
  'trust_operator and audit_read_events(). Confers neither is_trust_operator() '
  'nor is_erasure_executor().';

-- ── RLS on the new tables ───────────────────────────────────────────────────
-- These tables are themselves Admin data. READ is gated on Admin-layer
-- membership; WRITE is gated on full is_admin(), so the layer cannot be used to
-- escalate itself. (PD-A19 — admin assignment governance — is open; until it is
-- answered the conservative gate stands.)
ALTER TABLE public.admin_role_assignments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_role_capabilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin role assignments read" ON public.admin_role_assignments;
CREATE POLICY "admin role assignments read"
  ON public.admin_role_assignments FOR SELECT TO authenticated
  USING (public.is_admin_member() OR public.is_admin());

DROP POLICY IF EXISTS "admin role assignments write is full admin" ON public.admin_role_assignments;
CREATE POLICY "admin role assignments write is full admin"
  ON public.admin_role_assignments FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "admin role capabilities read" ON public.admin_role_capabilities;
CREATE POLICY "admin role capabilities read"
  ON public.admin_role_capabilities FOR SELECT TO authenticated
  USING (public.is_admin_member() OR public.is_admin());

DROP POLICY IF EXISTS "admin role capabilities write is full admin" ON public.admin_role_capabilities;
CREATE POLICY "admin role capabilities write is full admin"
  ON public.admin_role_capabilities FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Grants: the 116 posture. anon gets nothing.
REVOKE ALL ON TABLE public.admin_role_assignments  FROM anon;
REVOKE ALL ON TABLE public.admin_role_capabilities FROM anon;

-- NO capability rows are seeded. admin_can() is false for everyone until the
-- approved design's matrix cells are supplied. That is what makes this migration
-- provably privilege-neutral.
