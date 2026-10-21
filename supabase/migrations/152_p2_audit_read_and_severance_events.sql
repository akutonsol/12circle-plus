-- Migration 152 — the two owner decisions that closed the last V5 gaps.
--
--   DECISION 1 (R-1) · A13·5 — audit-read activity is recorded as a NEW dedicated
--   A2 category `audit_read`, promoted under A2's own provision that a later
--   requirement may "explicitly promote a specific event into audit scope".
--   Emitted from the existing `audit_read_events()` path, which §19.3 already
--   makes the sanctioned resolution point. The recursion boundary stays the
--   audit-read operation itself.
--
--   DECISION 2 (S-2) · the severance act emits an `export_deletion` Event carrying
--   the SEVERED, NON-RESOLVING pseudonym — never the pre-severance identifiable
--   subject. A12's anonymise-and-retain model is unchanged and the frozen rows are
--   untouched.
--
-- Both are additive. No completed P2 object is altered except the two functions
-- these decisions are about, and neither B1–B4 nor D12·Q5 is reopened.

-- ── 1 · THE FIFTEENTH CATEGORY (owner decision R-1) ────────────────────────
-- A2 §8.3 ruled fourteen categories IN and one OUT, and supplied the mechanism
-- used here: "treat routine session lifecycle and ordinary operational telemetry
-- as outside the core audit ledger UNLESS A LATER REQUIREMENT EXPLICITLY PROMOTES
-- A SPECIFIC EVENT INTO AUDIT SCOPE." This is that explicit promotion. It is an
-- owner decision, not an inference, and it is the only route by which the
-- vocabulary may grow.
ALTER TABLE public.audit_events DROP CONSTRAINT IF EXISTS audit_events_category_check;
ALTER TABLE public.audit_events ADD CONSTRAINT audit_events_category_check
  CHECK (category = ANY (ARRAY[
    'phi_read'::text, 'phi_correction'::text, 'financial'::text,          -- A2 tier 1
    'incident'::text, 'agent_action'::text, 'control_evidence'::text,
    'admin_action'::text, 'observability_audit'::text,                    -- A2 tier 2
    'authentication'::text, 'authorization_denial'::text,
    'billing_entitlement'::text, 'relationship_change'::text,
    'storage_media_access'::text, 'export_deletion'::text,                -- A2 tier 3
    'audit_read'::text                                                    -- owner decision R-1
  ]));

-- A6 §8.9 sorted A2's fourteen into nine delta-bearing and five occurrences with
-- no delta, and its five are PHI reads, authorization denials, authentication,
-- observability audit events and control evidence. An audit read is an occurrence
-- of the same shape as a PHI read -- there is no before and after to a read -- so
-- it joins the no-delta set. R-1 is consistent: the Event "may identify the actor
-- and the pseudonymous subject" and "MUST NOT contain PHI values"; it names no
-- delta. Enforced rather than left to callers.
ALTER TABLE public.audit_events DROP CONSTRAINT IF EXISTS audit_events_delta_category_check;
ALTER TABLE public.audit_events ADD CONSTRAINT audit_events_delta_category_check
  CHECK (
    delta IS NULL
    OR category NOT IN ('phi_read', 'authorization_denial', 'authentication',
                        'observability_audit', 'control_evidence', 'phi_correction',
                        'audit_read')
  );

COMMENT ON CONSTRAINT audit_events_category_check ON public.audit_events IS
  'A2 §8.3''s fourteen IN categories, plus `audit_read` promoted by owner decision R-1 under A2''s '
  'own "unless a later requirement explicitly promotes a specific event into audit scope" clause. '
  'Session lifecycle remains OUT.';

-- ── 2 · AUDIT READS ARE RECORDED (owner decision R-1) ──────────────────────
-- VOLATILE, not STABLE. The previous definition was STABLE, which PostgreSQL
-- forbids from writing, so the emission R-1 requires was impossible without this
-- change. Nothing else about the function's contract moves: same signature, same
-- return type, same reader rules, same single permitted resolution point.
--
-- THE RECURSION BOUNDARY, which R-1 keeps as §8.8 sub-ruling 5 set it --
-- "the recursion boundary is the audit-read operation itself" and "an audit_read
-- Event MUST NOT generate another audit_read Event":
--
--   Structurally it cannot. The emission is an INSERT through
--   audit_record_event(); it is not a read through this path, and no trigger on
--   audit_events emits anything. One call therefore produces exactly one Event,
--   however many rows it returns -- including rows that are themselves audit_read
--   Events, because returning a row is not recording a read of it.
--
--   The transaction-local guard below makes that a rule rather than a
--   coincidence, using migration 115's proven set_config(..., is_local := true)
--   pattern. If this path is ever re-entered inside one transaction, the inner
--   call reads and returns normally and records nothing.
CREATE OR REPLACE FUNCTION public.audit_read_events(
  p_subject uuid DEFAULT NULL,
  p_limit   int  DEFAULT 100
) RETURNS TABLE (
  id uuid, actor_id uuid, subject_id uuid, action text, occurred_at timestamptz,
  outcome text, category text, actor_provenance text, correlation_id uuid
)
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid     uuid    := auth.uid();
  v_admin   boolean := public.is_admin();
  v_trust   boolean := public.is_trust_operator();
  v_inside  boolean := COALESCE(current_setting('circle12.in_audit_read', true), 'off') = 'on';
  v_ps      uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'audit reads require an authenticated caller' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.actor_id, m.subject_id, e.action, e.occurred_at,
         e.outcome, e.category, e.actor_provenance, e.correlation_id
    FROM public.audit_events e
    LEFT JOIN public.audit_identity_map m ON m.pseudonym = e.subject_pseudonym
   WHERE (
           (v_admin AND NOT (e.category = 'admin_action' AND e.actor_id = v_uid))
           OR v_trust
           OR (m.subject_id IS NOT NULL AND public.is_active_coach_of(m.subject_id))
         )
     AND (p_subject IS NULL OR m.subject_id = p_subject)
   ORDER BY e.occurred_at DESC
   LIMIT GREATEST(1, LEAST(coalesce(p_limit, 100), 1000));

  -- The recursion boundary. Recording happens once, at the outermost read.
  IF v_inside THEN
    RETURN;
  END IF;
  PERFORM set_config('circle12.in_audit_read', 'on', true);

  -- "may identify the actor performing the audit read and the pseudonymous
  -- subject being read" (R-1). A subject-scoped read names that subject's
  -- pseudonym; an unscoped read has no single subject and names none. The actor
  -- is derived by audit_record_event() from auth.uid(), so it is `grounded`.
  -- The table reference MUST be aliased and qualified. This function's RETURNS
  -- TABLE declares an OUT parameter named `subject_id`, so an unqualified
  -- `WHERE subject_id = p_subject` is ambiguous between that parameter and the
  -- column -- and plpgsql raises rather than guessing. An earlier revision of
  -- this migration did exactly that, and the error propagated out of the READ
  -- PATH: the emission did not merely fail to record, it broke the read. Caught
  -- locally; it would have taken the audit read path down on QA.
  IF p_subject IS NOT NULL THEN
    SELECT m.pseudonym INTO v_ps
      FROM public.audit_identity_map m
     WHERE m.subject_id = p_subject;
  END IF;

  PERFORM public.audit_record_event(
    p_action            => 'audit_events.read',
    p_category          => 'audit_read',
    p_outcome           => 'success',
    p_subject_pseudonym => v_ps);

  PERFORM set_config('circle12.in_audit_read', 'off', true);
  RETURN;
END;
$$;
ALTER FUNCTION public.audit_read_events(uuid, int) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_read_events(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_read_events(uuid, int) TO authenticated;

COMMENT ON FUNCTION public.audit_read_events(uuid, int) IS
  'A13 §8.8 Event read path, and since owner decision R-1 the emission point for the `audit_read` '
  'category. The ONLY place §19.3 permits pseudonym resolution. A13 sub-ruling 1 still excludes an '
  'admin from their own admin_action rows. VOLATILE because a STABLE function cannot write, which '
  'is what made R-1 unimplementable before. The recursion boundary is the audit-read operation '
  'itself: one call emits exactly one Event, and a re-entrant call emits none. Retention (A12 '
  'ruling 4, 6 years) and the A13 reader policy apply to audit_read exactly as to every other '
  'category, because the row lives in audit_events.';

-- ── 3 · SEVERANCE EMITS export_deletion (owner decision S-2) ───────────────
-- A2 puts export/deletion events IN, and §8.7 recorded the consequence as an open
-- recursion: "the act of anonymising is itself auditable and produces a NEW Event
-- naming the subject." S-2 resolves it by naming the PSEUDONYM instead.
--
-- The ordering is the mechanism, and it is deliberate:
--   1. capture the pseudonym while the mapping still exists;
--   2. SEVER -- delete the mapping;
--   3. emit the Event carrying that pseudonym, which by then RESOLVES TO NOTHING.
-- So the retained ledger gains a record that an erasure occurred without gaining
-- any way to identify whom it concerned. "No identifiable subject value may be
-- reintroduced into the retained audit ledger by the severance Event."
--
-- NO DELTA. A6 counts export/deletion among its nine delta-bearing categories, so
-- one would be permitted -- but any before/after here would carry the identity
-- S-2 exists to keep out, and S-2 asks for none. Left NULL deliberately.
CREATE OR REPLACE FUNCTION public.audit_sever_identity(p_subject uuid) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_removed int;
  v_ps      uuid;
BEGIN
  IF NOT public.is_erasure_executor() THEN
    RAISE EXCEPTION 'severance is reserved to the erasure executor (A12 ruling 6; §8.18·Q1)'
      USING ERRCODE = '42501';
  END IF;

  -- 1 · capture, while it still resolves
  SELECT pseudonym INTO v_ps FROM public.audit_identity_map WHERE subject_id = p_subject;

  -- 2 · sever
  DELETE FROM public.audit_identity_map WHERE subject_id = p_subject;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  -- 3 · record, if there was anything to sever. The pseudonym is already
  --     non-resolving at this point, which is the whole of S-2.
  IF v_removed > 0 THEN
    PERFORM public.audit_record_event(
      p_action            => 'audit_identity_map.sever',
      p_category          => 'export_deletion',
      p_outcome           => 'success',
      p_subject_pseudonym => v_ps,
      p_delta             => NULL);
  END IF;

  RETURN v_removed > 0;
END;
$$;
ALTER FUNCTION public.audit_sever_identity(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_sever_identity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_sever_identity(uuid) TO authenticated;

COMMENT ON FUNCTION public.audit_sever_identity(uuid) IS
  'A12 ruling 1 ANONYMISE-AND-RETAIN, performed as ruling 2 requires: the mapping row is removed '
  'and the frozen Event rows are NOT mutated. Reserved to the erasure executor (§19.3). Since owner '
  'decision S-2 it emits an export_deletion Event carrying the SEVERED, NON-RESOLVING pseudonym -- '
  'never the pre-severance subject -- which closes the A2 recursion §8.7 and §8.8 both recorded as '
  'open. §8.20·Q4 still governs the limit: severance is DML-DEEP ONLY and is NOT durable against a '
  'party holding DDL rights, so this is not irreversible anonymisation and must not be described '
  'as such.';
