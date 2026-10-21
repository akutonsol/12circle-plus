-- ═══════════════════════════════════════════════════════════════════════════
-- 164 · THE INCIDENTS WRITE PATH — owner decisions B-21a and B-21b, 2026-10-06
--
-- The approved matrix grants Incidents Create/Update/Manage/Approve to trust_lead.
-- V5 §129.4's B-21 parked all four. The evidence separated them into four
-- different problems, and only two are built here.
--
--  · Update  -> B-21a · RESPONSE FIELDS ONLY (this migration)
--  · Create  -> B-21b · amend owner decision B1, additively (this migration)
--  · Approve -> BLOCKED on an undefined vocabulary. 143's own column comment:
--               "the approval-status values are not enumerated in any tracked
--               source. Left unconstrained rather than invented; see V5 §77.3."
--               Setting a value would invent what §77.3 declined to invent.
--  · Manage  -> no stated meaning anywhere, the same condition as B-23's sixteen.
--
-- Approve and Manage are registered NON-OPERATIONAL alongside B-20's four, with
-- the same three-leg proof. They are not built and nothing is owed on them.
--
-- WHY NO audit_record_event() CALL IN THE UPDATE PATH. Every other admin writer in
-- this repository emits one. This one deliberately does not, because migration 143
-- already ruled the mechanism: audit_incident_transitions IS "the RETENTION
-- MECHANISM A11 mandates for population 2", and 143 records emitting transitions
-- into the Event population as an "ALTERNATIVE CONSIDERED AND NOT TAKEN", on the
-- ground that an Event row "cannot express 'approval_status moved from pending to
-- approved' without stuffing the field, the old value and the new value into free
-- text, which loses exactly the fidelity A11 is asking to be retained." The
-- trigger journals every field change with actor and provenance automatically.
-- Emitting as well would create the duplicate record 143 rejected.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · B-21b · audit_open_incident gains the Admin-layer arm ──────────────
-- ADDITIVE AMENDMENT TO OWNER DECISION B1. B1 ruled "only admin or trust_operator
-- may open an incident". The matrix grants Incidents/Create to trust_lead, who is
-- NEITHER -- CONF-D7 forbids mapping Trust lead to the trust_operator role and 153
-- keeps is_admin() false for every Admin-layer principal. The owner amended B1 to
-- include the Admin layer. B1's existing holders lose nothing.
--
-- RESTATED IN FULL, NOT PATCHED. CREATE OR REPLACE drops proconfig unless the SET
-- is restated (I-MIG-03 / CRC-07), and 118/122 pinned search_path on every
-- function in public. The body below is 151's, unchanged except the authorization
-- line and this comment.
CREATE OR REPLACE FUNCTION public.audit_open_incident(
  p_summary            text,
  p_occurred_at        timestamptz,
  p_severity           text,
  p_scope              text  DEFAULT NULL,
  p_evidence           jsonb DEFAULT '[]'::jsonb,
  p_suspected_cause    text  DEFAULT NULL,
  p_recommended_action text  DEFAULT NULL
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_ps  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'opening an incident requires an authenticated actor (owner decision B1)'
      USING ERRCODE = '42501';
  END IF;
  -- B1 as amended by owner decision B-21b: the Admin layer joins the two database
  -- roles B1 named. service_role still cannot reach it -- auth.uid() is NULL there.
  IF NOT (public.is_admin()
          OR public.is_trust_operator()
          OR public.admin_can('Incidents', 'create')) THEN
    RAISE EXCEPTION 'only admin, trust_operator or an Admin-layer holder of Incidents/create may open an incident (owner decisions B1, B-21b)'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.audit_incidents
    (summary, occurred_at, severity, scope, evidence, suspected_cause,
     recommended_action, actor_identity, actor_provenance)
  VALUES
    (p_summary, p_occurred_at, p_severity, p_scope, p_evidence, p_suspected_cause,
     p_recommended_action, v_uid, 'grounded')   -- B1: "actor identity must be recorded"
  RETURNING id INTO v_id;

  v_ps := public.audit_mint_pseudonym(v_uid);
  PERFORM public.audit_record_event(
    p_action => 'audit_incidents.open', p_category => 'incident',
    p_outcome => 'success', p_subject_pseudonym => v_ps);

  RETURN v_id;
END;
$$;
ALTER FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) TO authenticated;

-- ── 2 · B-21a · the response-field writer, and nothing wider ───────────────
-- The FIRST writer audit_incidents has ever had: there is no UPDATE policy and 148
-- grants the table SELECT only, so until now not even is_admin() could change an
-- incident. That is why this is a function and not a policy -- a policy constrains
-- WHICH ROWS may be updated, never WHICH COLUMNS, and `authenticated` is one role
-- shared by every member, so a column grant cannot express the contract either.
--
-- THE CONTRACT, owner decision B-21a: action_taken, recommended_action, resolution.
-- What the team DID about the incident -- the fields that genuinely accrue after it
-- is opened. The ACCOUNT of what happened (summary, severity, scope,
-- suspected_cause, occurred_at) is deliberately NOT writable, so an incident's
-- description cannot be rewritten after the fact.
--
-- TWO COLUMNS ARE EXCLUDED FOR SECURITY, not merely by preference:
--   · evidence        -- withheld from the Admin projection by owner decision B-4
--                        (unbounded free-form; cannot be shown safe in advance).
--                        A writer that cannot be read back is a blind write.
--   · actor_identity  -- PRIVILEGE-BEARING. 143's read policy is
--                        "actor_identity = auth.uid() OR is_active_coach_of(actor_identity)",
--                        so writing it CHANGES WHO CAN SEE THE INCIDENT. It is an
--                        authorization column wearing a data column's clothes.
CREATE OR REPLACE FUNCTION public.admin_update_incident_response(
  p_incident_id        uuid,
  p_action_taken       text DEFAULT NULL,
  p_recommended_action text DEFAULT NULL,
  p_resolution         text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_exists boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Incidents', 'update') THEN
    RAISE EXCEPTION 'not authorized: Incidents/update is required' USING ERRCODE = '42501';
  END IF;

  p_action_taken       := nullif(btrim(coalesce(p_action_taken, '')), '');
  p_recommended_action := nullif(btrim(coalesce(p_recommended_action, '')), '');
  p_resolution         := nullif(btrim(coalesce(p_resolution, '')), '');
  IF p_action_taken IS NULL AND p_recommended_action IS NULL AND p_resolution IS NULL THEN
    RAISE EXCEPTION 'nothing to update: supply at least one response field' USING ERRCODE = '22023';
  END IF;

  SELECT true INTO v_exists FROM public.audit_incidents WHERE id = p_incident_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such incident' USING ERRCODE = '22023';
  END IF;

  -- COALESCE: a NULL argument leaves that column alone, so this can never blank a
  -- field it was not asked to change. The transitions trigger journals whichever
  -- of the three actually moves, with the caller's uid and provenance.
  UPDATE public.audit_incidents
     SET action_taken       = coalesce(p_action_taken,       action_taken),
         recommended_action = coalesce(p_recommended_action, recommended_action),
         resolution         = coalesce(p_resolution,         resolution)
   WHERE id = p_incident_id;

  RAISE LOG 'admin_update_incident_response: % updated incident %', auth.uid(), p_incident_id;
END;
$$;

ALTER FUNCTION public.admin_update_incident_response(uuid, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_update_incident_response(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_incident_response(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_update_incident_response(uuid, text, text, text) IS
  'V5 §141 · the Incidents write path. Owner decision B-21a: RESPONSE FIELDS ONLY '
  '-- action_taken, recommended_action, resolution. The account of what happened is '
  'not writable. evidence is excluded by B-4; actor_identity is excluded because it '
  'is privilege-bearing (143''s read policy keys on it), so writing it would change '
  'who can see the incident. Gated on admin_can(''Incidents'',''update''). Changes '
  'are journalled by trg_audit_incidents_transitions, which 143 ruled is the '
  'retention mechanism for this population -- no Event is emitted, because 143 '
  'considered and rejected that duplicate.';
