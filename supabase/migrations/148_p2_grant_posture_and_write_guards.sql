-- Migration 148 — P2 · grant posture, and the two write guards the live rung exposed.
--
-- WHY THIS EXISTS. Migrations 142–147 were validated on a bare postgres:17 and
-- every assertion passed. The FIRST live run against QA failed one: service_role
-- INSERTed a control-evidence row (201) that A11's NO RUNTIME WRITE PATH forbids.
--
-- The cause is a platform difference a bare cluster cannot reproduce. Supabase
-- applies ALTER DEFAULT PRIVILEGES on `public` granting ALL to `authenticated`
-- and `service_role` on every newly created table. Verified on the live catalog:
--
--     GRANT ALL ON TABLE "public"."audit_events"             TO "authenticated";
--     GRANT ALL ON TABLE "public"."audit_events"             TO "service_role";
--     ... the same pair for all six P2 tables ...
--
-- So every `GRANT SELECT` in 142–146 was an additive no-op against a grant that
-- was already wider, and the narrow posture those migrations describe was never
-- the posture they produced. This is the SP-5 class again -- the one migration 138
-- introduced and 139 repaired (V5 §39) -- and it is the second time in this
-- programme that a grant regression was invisible until it ran somewhere real.
--
-- WHAT WAS ACTUALLY EXPOSED, stated plainly rather than minimised:
--   * `authenticated` held ALL on all six. RLS still gated it -- each table has a
--     SELECT policy and no write policy -- so no client write was reachable. The
--     grant was wrong; the outcome was defended.
--   * `service_role` held ALL and BYPASSES RLS, so for it the grant WAS the
--     control. Where a freeze trigger exists it was still bound (triggers bind
--     every caller -- the migration 120 precedent). Where none exists it was not:
--       - audit_control_evidence had no INSERT guard  -> the observed 201;
--       - audit_identity_map had NO TRIGGER AT ALL    -> service_role could
--         sever an identity directly, bypassing audit_sever_identity()'s
--         executor check and with it A12 ruling 6, which says in terms that the
--         erasure executor may NOT be service_role.
--
-- A3 sub-ruling 5 requires that service_role be CONSTRAINED from bypassing the
-- intended audit controls, and A11 sub-ruling 3's deferral is discharged (A12 is
-- decided). This migration does that at the only layer that binds it.
--
-- CLAIM LIMIT, unchanged: §8.19 declined the out-of-database anchor, so all of
-- this is DML-DEEP ONLY. A party holding DDL rights can drop these triggers, and
-- §68 showed the compromised function tier is undefended against by ruling.
-- Nothing here is a tamper-resistance claim.

-- ── 1 · THE GRANTS, MADE TO MATCH WHAT THE MIGRATIONS ALWAYS SAID ──────────
-- REVOKE first, then grant precisely. Writes reach these tables through
-- SECURITY DEFINER functions owned by the table owner, which need no role grant.
REVOKE ALL ON TABLE public.audit_events               FROM authenticated, service_role;
REVOKE ALL ON TABLE public.audit_incidents            FROM authenticated, service_role;
REVOKE ALL ON TABLE public.audit_incident_transitions FROM authenticated, service_role;
REVOKE ALL ON TABLE public.audit_control_evidence     FROM authenticated, service_role;
REVOKE ALL ON TABLE public.observability_events       FROM authenticated, service_role;
REVOKE ALL ON TABLE public.audit_identity_map         FROM authenticated, service_role;

-- Readers, per A13 §8.8 and §8.16·Q3. RLS narrows these further; the grant is the
-- outer bound, not the policy.
GRANT SELECT ON TABLE public.audit_events               TO authenticated, service_role;
GRANT SELECT ON TABLE public.audit_incidents            TO authenticated, service_role;
GRANT SELECT ON TABLE public.audit_incident_transitions TO authenticated, service_role;
GRANT SELECT ON TABLE public.audit_control_evidence     TO authenticated, service_role;
GRANT SELECT ON TABLE public.observability_events       TO authenticated, service_role;

-- §8.16·Q4: service_role is not the writer of record, but it IS the tier that
-- emits telemetry, and no definer RPC exists for the observability population
-- yet. INSERT only; the freeze trigger binds it exactly as it binds anyone.
GRANT INSERT ON TABLE public.observability_events TO service_role;

-- audit_identity_map: NOTHING to either role. §8.20·Q1 -- "reachable only by the
-- erasure executor's named grant and the SECURITY DEFINER audit read path."

-- ── 2 · CONTROL EVIDENCE — the missing INSERT guard (A11 NO RUNTIME WRITE PATH) ──
-- The existing freeze covers UPDATE and DELETE. A11 gives this population the
-- strictest reading of the three and INSERT was never guarded, so a runtime role
-- holding the grant could author evidence -- which is precisely what "authored/
-- produced evidence, NOT a runtime audit event" excludes.
--
-- The predicate is the connecting role. PostgREST performs SET ROLE to the JWT's
-- role, so a request arrives as anon/authenticated/service_role; an authored
-- migration runs as the table owner, and a SECURITY DEFINER function runs with
-- current_user = its owner. Refusing the three PostgREST roles therefore refuses
-- exactly the runtime write path and nothing else.
CREATE OR REPLACE FUNCTION public.audit_control_evidence_no_runtime_write() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated', 'service_role') THEN
    RAISE EXCEPTION
      'audit_control_evidence has NO RUNTIME WRITE PATH (A11 §8.6) — it is authored evidence, written by migration'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_control_evidence_no_runtime_write() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_control_evidence_no_runtime_write() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_audit_control_evidence_no_runtime_write
  BEFORE INSERT ON public.audit_control_evidence
  FOR EACH ROW EXECUTE FUNCTION public.audit_control_evidence_no_runtime_write();

-- ── 3 · THE IDENTITY MAP — severance only through the executor's path ──────
-- A12 ruling 6 asks whether the erasure executor may be service_role and answers
-- NO. Without this, service_role could DELETE a mapping row directly and perform
-- an erasure the ruling reserves to another party. Same predicate, same reason:
-- audit_sever_identity() and audit_mint_pseudonym() are definer functions owned by
-- the table owner, so they pass; a PostgREST request does not.
CREATE OR REPLACE FUNCTION public.audit_identity_map_definer_only() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated', 'service_role') THEN
    RAISE EXCEPTION
      'audit_identity_map is reachable only through the audit read path and audit_sever_identity() (§8.20·Q1; A12 ruling 6)'
      USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
ALTER FUNCTION public.audit_identity_map_definer_only() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_identity_map_definer_only() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_audit_identity_map_definer_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.audit_identity_map
  FOR EACH ROW EXECUTE FUNCTION public.audit_identity_map_definer_only();

COMMENT ON FUNCTION public.audit_identity_map_definer_only() IS
  'A3 sub-ruling 5 — constrains service_role from bypassing the intended audit controls, at the '
  'only layer that binds it. Without this, GRANT ALL + BYPASSRLS let service_role sever an '
  'identity directly and perform an erasure A12 ruling 6 reserves to the erasure executor. '
  'DML-DEEP ONLY (§8.19 declined the anchor): a party holding DDL rights can drop this trigger.';
