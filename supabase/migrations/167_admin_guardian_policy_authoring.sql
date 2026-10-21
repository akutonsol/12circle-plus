-- ═══════════════════════════════════════════════════════════════════════════
-- 167 · GOVERNANCE-POLICY AUTHORING — owner decision B-23-AI-1, 2026-10-06
--
-- THE GAP. The approved matrix grants `AI Guardian · Create` and `· Update` to
-- trust_lead. 154 created the registry with writes gated on `is_admin()`, and 163
-- made only the READ effective — so both grants were inert. This is the one verb
-- pair among B-23's sixteen with an existing, mutable, correctly-scoped resource.
--
-- WHAT THIS IS NOT — and 154's own constraint is the reason it is safe:
--   · NOT an enforcement point. §13 keeps the deterministic layer authoritative.
--     `admin_can()` and RLS decide everything; a row here is a DOCUMENT. Authoring
--     one confers no authorization on anybody, which D15 asserts directly.
--   · NOT a delete path. The matrix has no Delete verb and none is added.
--   · NOT a widening of `is_admin()`. 154's write policy is untouched; these are
--     ADDITIVE arms, so the legacy admin keeps exactly what it had.
--   · NOT the Guardian runtime. State and the approval queue are B-17/P7 and are
--     registered non-operational pending their producer.
--
-- WHY POLICIES PLUS A TRIGGER, RATHER THAN AN RPC PER TABLE. The other admin
-- writers in this repository are RPCs because they needed a COLUMN contract — a
-- policy cannot express "these two columns only". Here the whole row is the
-- document, so the column-contract argument does not apply, and five RPCs would be
-- five places for the audit to drift. One shared trigger audits every write to
-- every registry table uniformly, which is 143's journalling pattern applied to a
-- different population.
--
-- The audit emits `changed_columns` and NO delta, consistent with every admin
-- writer since 161. A policy document's values are not personal data, so a delta
-- would be permissible here — it is omitted for uniformity, not necessity.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · the shared audit trigger ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_governance_write() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid     uuid := (SELECT auth.uid());
  v_ps      uuid;
  v_changed text[] := ARRAY[]::text[];
  v_col     text;
BEGIN
  -- Internal/service writes carry no auth.uid(); 154's own seeding path must not
  -- be forced to mint a pseudonym for a caller that does not exist.
  IF v_uid IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'UPDATE' THEN
    FOR v_col IN
      SELECT key FROM jsonb_each(to_jsonb(NEW))
      WHERE to_jsonb(NEW) -> key IS DISTINCT FROM to_jsonb(OLD) -> key
    LOOP
      v_changed := array_append(v_changed, v_col);
    END LOOP;
    IF array_length(v_changed, 1) IS NULL THEN
      RETURN NEW;                       -- nothing actually moved
    END IF;
  ELSE
    v_changed := array_append(v_changed, 'created');
  END IF;

  v_ps := public.audit_mint_pseudonym(v_uid);
  PERFORM public.audit_record_event(
    p_action          => TG_TABLE_NAME || '.' || lower(TG_OP),
    p_category        => 'admin_action',
    p_outcome         => 'success',
    p_subject_pseudonym => v_ps,
    p_delta           => NULL,
    p_changed_columns => v_changed);

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_governance_write() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_governance_write() FROM PUBLIC, anon;

-- ── 2 · additive write arms + the audit trigger, on all five tables ────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['governance_policy', 'governance_policy_version',
                           'governance_policy_rule', 'governance_policy_set',
                           'governance_policy_set_member'] LOOP
    -- Create. WITH CHECK only: an INSERT has no existing row to qualify.
    EXECUTE format($q$DROP POLICY IF EXISTS "admin layer authors %1$s" ON public.%1$I$q$, t);
    EXECUTE format($q$CREATE POLICY "admin layer authors %1$s" ON public.%1$I
                      FOR INSERT TO authenticated
                      WITH CHECK (public.admin_can('AI Guardian', 'create'))$q$, t);

    -- Update. Both USING and WITH CHECK, so the grant is required to reach the row
    -- AND to leave it in a state this caller may author.
    EXECUTE format($q$DROP POLICY IF EXISTS "admin layer revises %1$s" ON public.%1$I$q$, t);
    EXECUTE format($q$CREATE POLICY "admin layer revises %1$s" ON public.%1$I
                      FOR UPDATE TO authenticated
                      USING (public.admin_can('AI Guardian', 'update'))
                      WITH CHECK (public.admin_can('AI Guardian', 'update'))$q$, t);

    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_governance_write ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_audit_governance_write
                      AFTER INSERT OR UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.audit_governance_write()', t);
  END LOOP;
END $$;

-- ── 3 · the table grants the policies depend on ───────────────────────────
-- 154 granted SELECT only. A policy cannot permit what the table grant withholds.
-- DELETE is deliberately NOT granted: the matrix has no Delete verb for this area.
GRANT INSERT, UPDATE ON public.governance_policy            TO authenticated;
GRANT INSERT, UPDATE ON public.governance_policy_version    TO authenticated;
GRANT INSERT, UPDATE ON public.governance_policy_rule       TO authenticated;
GRANT INSERT, UPDATE ON public.governance_policy_set        TO authenticated;
GRANT INSERT, UPDATE ON public.governance_policy_set_member TO authenticated;

COMMENT ON FUNCTION public.audit_governance_write() IS
  'V5 §149 · audits every write to the 154 governance registry as an admin_action '
  'carrying changed_columns and no delta. Returns early when auth.uid() is NULL so '
  'internal/service seeding is not forced to mint a pseudonym for an absent caller.';
