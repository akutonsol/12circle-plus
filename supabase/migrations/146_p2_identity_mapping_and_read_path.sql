-- Migration 146 — P2 · A12's EXTERNAL IDENTITY MAPPING, the erasure executor,
--                      and A13's audit read path.
--
-- This is the object A12's entire erasure model rests on. §8.20 states it plainly:
-- "A12's entire erasure model rests on this object. Ruling 1 is ANONYMISE-AND-
-- RETAIN; ruling 2 is 'NO exception -- use an external mapping. The frozen row is
-- never mutated.' ANONYMISING MEANS SEVERING THE MAPPING."
--
-- §8.20 recorded it as PREPARED, NOT ANSWERED. It is answered now, entirely by
-- later rulings, and nothing below is invented:
--
--   §8.20·Q1  where it lives      ANSWERED §19.3 — "A TABLE IN public, RLS ENABLED,
--                                 WITH NO POLICY GRANTING ANY CLIENT ROLE."
--   §8.20·Q2/Q3, §8.18·Q3         ANSWERED §19.3 as one — who may RESOLVE: NO
--                                 STANDING PARTY, "resolution occurs inside the
--                                 audit read path"; who may SEVER: the erasure
--                                 executor; the mapping authority is "a named,
--                                 separately-grantable capability vested in the
--                                 erasure executor -- NOT a third role."
--   §8.20·Q4  durability          ANSWERED §19.3 — DML-deep severance, and "the
--                                 programme must NOT describe anonymisation as
--                                 irreversible."
--   A12 ruling 6                  the executor is a NEW CONSTRAINED ROLE and
--                                 explicitly NOT service_role.
--   §8.18·Q2                      no single party holds both erasure authority and
--                                 read authority.
--
-- CLAIM LIMIT, required by 13 and by §8.20·Q4: severance binds every caller at the
-- DML layer and is NOT durable against a party holding DDL rights. Nothing here
-- may be described as irreversible anonymisation.

-- ── 1 · THE MAP ────────────────────────────────────────────────────────────
-- Deny-by-default. §8.20·Q1's rationale names the precedent it copies: "the
-- decision_traces shape -- a policy that grants reads and NO WRITE POLICY AT ALL
-- -- is genuinely applicable precedent." Here it is stricter still: NO POLICY AT
-- ALL, so RLS denies every client role outright and the only routes in are the
-- definer functions below.
CREATE TABLE IF NOT EXISTS public.audit_identity_map (
  pseudonym  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_identity_map_subject_key UNIQUE (subject_id)
);
ALTER TABLE public.audit_identity_map OWNER TO postgres;
ALTER TABLE public.audit_identity_map ENABLE ROW LEVEL SECURITY;

-- No FK to auth.users: the map must outlive the subject, which is the whole point
-- of ANONYMISE-AND-RETAIN, and a cascade would sever the mapping as a side effect
-- of account deletion rather than as a deliberate erasure act by the executor.
COMMENT ON TABLE public.audit_identity_map IS
  'A12 ruling 2''s external mapping — pseudonym → subject. ANONYMISING MEANS SEVERING THE '
  'MAPPING (§8.20); the frozen Event row is never mutated. §8.20·Q1: a table in public, RLS '
  'enabled, WITH NO POLICY GRANTING ANY CLIENT ROLE — reachable only by the erasure executor''s '
  'named grant and the SECURITY DEFINER audit read path. §8.20·Q4: severance is DML-DEEP ONLY '
  'and is NOT durable against a party holding DDL rights — anonymisation must never be described '
  'as irreversible.';

-- ── 2 · THE ERASURE EXECUTOR ───────────────────────────────────────────────
-- 142 added the role VALUE (§8.18·Q1 named two roles and A12 ruling 6 forbade
-- service_role). This is its predicate, mirroring is_admin()/is_trust_operator().
CREATE OR REPLACE FUNCTION public.is_erasure_executor() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE id = auth.uid() AND role = 'erasure_executor'
  );
$$;
ALTER FUNCTION public.is_erasure_executor() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_erasure_executor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_erasure_executor() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_erasure_executor() TO authenticated;

COMMENT ON FUNCTION public.is_erasure_executor() IS
  '§8.18·Q1 + A12 ruling 6 — the second of the two roles. Holds erasure authority and, per '
  '§8.18·Q2 and A13 sub-ruling 4, must NOT also hold read authority: it is deliberately absent '
  'from every audit read policy and from the read path below.';

-- ── 3 · MINTING (the write side) ───────────────────────────────────────────
-- Returns the subject's pseudonym, creating it on first use. Granted to
-- service_role ONLY -- the tier that writes audit rows. `authenticated` is NOT
-- granted: a client able to mint could map a chosen subject to its pseudonym,
-- which is a resolution in the reverse direction and exactly the "enumerate or
-- bulk-resolve" capability §19.3 refuses to give any standing party.
CREATE OR REPLACE FUNCTION public.audit_mint_pseudonym(p_subject uuid) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_pseudonym uuid;
BEGIN
  IF p_subject IS NULL THEN RETURN NULL; END IF;
  SELECT pseudonym INTO v_pseudonym FROM public.audit_identity_map WHERE subject_id = p_subject;
  IF v_pseudonym IS NULL THEN
    INSERT INTO public.audit_identity_map(subject_id) VALUES (p_subject)
      ON CONFLICT (subject_id) DO NOTHING;
    SELECT pseudonym INTO v_pseudonym FROM public.audit_identity_map WHERE subject_id = p_subject;
  END IF;
  RETURN v_pseudonym;
END;
$$;
ALTER FUNCTION public.audit_mint_pseudonym(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_mint_pseudonym(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_mint_pseudonym(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.audit_mint_pseudonym(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.audit_mint_pseudonym(uuid) TO service_role;

-- ── 4 · SEVERANCE — the erasure act ────────────────────────────────────────
-- A12 ruling 1: ANONYMISE-AND-RETAIN. The audit rows stay exactly as written; the
-- mapping row is removed, so the pseudonym on them resolves to nothing from that
-- moment on. The frozen row is never touched, which is ruling 2 in one sentence.
CREATE OR REPLACE FUNCTION public.audit_sever_identity(p_subject uuid) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_removed int;
BEGIN
  IF NOT public.is_erasure_executor() THEN
    RAISE EXCEPTION 'severance is reserved to the erasure executor (A12 ruling 6; §8.18·Q1)'
      USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.audit_identity_map WHERE subject_id = p_subject;
  GET DIAGNOSTICS v_removed = ROW_COUNT;
  RETURN v_removed > 0;
END;
$$;
ALTER FUNCTION public.audit_sever_identity(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_sever_identity(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_sever_identity(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.audit_sever_identity(uuid) TO authenticated;

COMMENT ON FUNCTION public.audit_sever_identity(uuid) IS
  'A12 ruling 1 ANONYMISE-AND-RETAIN, performed as ruling 2 requires: the mapping row is removed '
  'and the frozen Event rows are NOT mutated. Reserved to the erasure executor (§19.3: "who may '
  'SEVER — the erasure executor role"). §8.20·Q4: DML-deep only, NOT durable against DDL rights. '
  'This is NOT irreversible anonymisation and must not be described as such. '
  'NOTE (A2/A12): export and deletion events are audit-worthy, so the act of severing is itself '
  'auditable and would produce a NEW Event naming the subject — the recursion §8.7 recorded as '
  'unresolved ("the A2 recursion is unresolved by A12") and §8.8 confirms sub-ruling 5 does NOT '
  'resolve. No severance audit row is emitted here; see V5 §78.3.';

-- ── 5 · A13's AUDIT READ PATH — where resolution is permitted to happen ────
-- §19.3: "NO STANDING PARTY" may resolve identity; "resolution occurs INSIDE THE
-- AUDIT READ PATH, gated by A13's per-population reader rules", and "no party may
-- enumerate or bulk-resolve the mapping."
--
-- This function is that path, and it is why the active-coach arm is absent from
-- audit_events' table policy: deciding is_active_coach_of on a pseudonymous
-- subject REQUIRES a resolution, and a policy that resolves is a standing
-- resolver. Here the resolution happens per row, for one caller, gated first.
--
-- A13's three Event readers are all served:
--   admin          — everything EXCEPT their own admin_action rows (sub-ruling 1)
--   Trust operator — everything
--   active coach   — only rows whose resolved subject they actively coach
-- The erasure executor is deliberately NOT a reader (§8.18·Q2, A13 sub-ruling 4).
CREATE OR REPLACE FUNCTION public.audit_read_events(
  p_subject uuid DEFAULT NULL,
  p_limit   int  DEFAULT 100
) RETURNS TABLE (
  id uuid, actor_id uuid, subject_id uuid, action text, occurred_at timestamptz,
  outcome text, category text, actor_provenance text, correlation_id uuid
)
  LANGUAGE plpgsql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_admin boolean := public.is_admin();
  v_trust boolean := public.is_trust_operator();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'audit reads require an authenticated caller' USING ERRCODE = '42501';
  END IF;

  -- A subject filter is resolved ONCE, for this caller, and only if they are
  -- entitled to it. There is no path here that returns the map itself.
  RETURN QUERY
  SELECT e.id, e.actor_id, m.subject_id, e.action, e.occurred_at,
         e.outcome, e.category, e.actor_provenance, e.correlation_id
    FROM public.audit_events e
    LEFT JOIN public.audit_identity_map m ON m.pseudonym = e.subject_pseudonym
   WHERE (
           -- A13 sub-ruling 1: an admin never reads their OWN admin actions.
           (v_admin AND NOT (e.category = 'admin_action' AND e.actor_id = v_uid))
           OR v_trust
           -- the coach arm, resolvable only here
           OR (m.subject_id IS NOT NULL AND public.is_active_coach_of(m.subject_id))
         )
     AND (p_subject IS NULL OR m.subject_id = p_subject)
   ORDER BY e.occurred_at DESC
   LIMIT GREATEST(1, LEAST(coalesce(p_limit, 100), 1000));
END;
$$;
ALTER FUNCTION public.audit_read_events(uuid, int) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_read_events(uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_read_events(uuid, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.audit_read_events(uuid, int) TO authenticated;

COMMENT ON FUNCTION public.audit_read_events(uuid, int) IS
  'A13 §8.8 Event read path. The ONLY place §19.3 permits pseudonym resolution ("no standing '
  'party ... resolution occurs inside the audit read path"), which is why the active-coach arm '
  'lives here and not in audit_events'' table policy. Serves A13''s three readers; sub-ruling 1 '
  'excludes an admin from their own admin_action rows; the erasure executor is deliberately not '
  'a reader (§8.18·Q2). '
  'A13 SUB-RULING 5 IS NOT IMPLEMENTED HERE AND IS NOT CLAIMED TO BE: audit reads are '
  'audit-worthy and are to be recorded "at the application/access layer", with the audit-read '
  'operation as the recursion boundary — but A2''s fourteen categories contain no slot for an '
  'audit-read record, and no ruling places the recording in the database rather than the access '
  'layer. Recorded as a gap in V5 §78.3 rather than guessed at.';
