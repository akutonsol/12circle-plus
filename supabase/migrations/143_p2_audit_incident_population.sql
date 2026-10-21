-- Migration 143 — P2 · the AUDIT INCIDENT population (A1 §8.4 population 2).
--
-- Second of D4's four populations. 142 built the Event population; Control
-- evidence and the D12 observability population follow separately. Nothing here
-- is a new audit design: every object cites the ruling that produced it, and V5
-- §75 carries the specification.
--
-- WHY THIS POPULATION IS SHAPED DIFFERENTLY FROM THE EVENT POPULATION.
-- A1 sub-ruling 1 is explicit: migration 128's "no write policy exists on this
-- table and none may be added" governs "that provenance model only; it is NOT a
-- standing D4 rule", and the consequence it draws is that "the Incident
-- population MAY CARRY AN UPDATE PATH, which its mutable investigation state
-- requires." So unlike audit_events, the case record here is mutable by design.
--
-- A11 §8.6 then constrains HOW it may mutate: Incident = APPEND-STATE-TRANSITIONS
-- -- "the incident may evolve, but EACH STATE TRANSITION IS RETAINED AS AN
-- IMMUTABLE HISTORICAL EVENT." That requires somewhere for transitions to be
-- retained, so this migration creates one.
--
--   `audit_incident_transitions` IS NOT A FOURTH POPULATION. A1 enumerates three
--   audit populations and D12 adds a separate observability population; this table
--   is the RETENTION MECHANISM A11 mandates for population 2, and it lives and
--   dies with it. The standing instruction not to invent new populations is
--   honoured: no new population, no new reader class, no new retention rule.
--
--   ALTERNATIVE CONSIDERED AND NOT TAKEN: emitting each transition into the Event
--   population as category='incident' (A2 lists `incident` as an IN category).
--   Rejected because the Event row's shape -- actor · subject · action · time ·
--   outcome -- cannot express "approval_status moved from pending to approved"
--   without stuffing the field, the old value and the new value into free text,
--   which loses exactly the fidelity A11 is asking to be retained. Recorded so the
--   choice is reviewable rather than assumed.

-- ── 1 · THE CASE RECORD (A1 §8.4 population 2 — the 11 fields) ──────────────
-- The eleven fields are quoted, not inferred. V5_DECISION_RESOLUTION_2026-09-27.md:114
-- (V2 Admin Incident Model): "Each incident records what happened, when, scope,
-- evidence, severity, suspected cause, recommended action, action taken,
-- actor/agent identity, approval status, and resolution."
CREATE TABLE IF NOT EXISTS public.audit_incidents (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  summary            text NOT NULL,          --  1 · what happened
  occurred_at        timestamptz NOT NULL,   --  2 · when
  scope              text,                   --  3 · scope
  evidence           jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 4 · evidence
  severity           text NOT NULL,          --  5 · severity
  suspected_cause    text,                   --  6 · suspected cause
  recommended_action text,                   --  7 · recommended action
  action_taken       text,                   --  8 · action taken
  actor_identity     uuid,                   --  9 · actor/agent identity
  approval_status    text NOT NULL DEFAULT 'pending',  -- 10 · approval status
  resolution         text,                   -- 11 · resolution

  -- A3 sub-ruling 3 applies to this population exactly as it does to the Event
  -- population: asserted and grounded attribution "must remain distinguishable in
  -- the design and must not be equated". An incident's actor may be an agent, so
  -- the asserted case is the common one, not the exception.
  actor_provenance   text NOT NULL,

  -- NO FOREIGN KEY on actor_identity, for the reason migration 142 records at
  -- length: A12 ruling 2 forbids mutating a retained audit record, A1 sub-ruling 2
  -- forbids cascading a deletion into one, and A3 sub-ruling 3 permits actors that
  -- were never auth.users rows.

  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  -- The severity enum is SPECIFIED, not chosen: V5_DECISION_RESOLUTION:117 --
  -- "Severity enum also specified: Critical · High · Warning · Informational."
  CONSTRAINT audit_incidents_severity_check
    CHECK (severity = ANY (ARRAY['Critical'::text, 'High'::text,
                                 'Warning'::text, 'Informational'::text])),

  CONSTRAINT audit_incidents_actor_provenance_check
    CHECK (actor_provenance = ANY (ARRAY['grounded'::text, 'asserted'::text, 'system'::text]))
);
ALTER TABLE public.audit_incidents OWNER TO postgres;

COMMENT ON TABLE public.audit_incidents IS
  'D4·A1 §8.4 population 2 — the Incident case record. MUTABLE BY RULING: A1 sub-ruling 1 '
  'states the Incident population "may carry an UPDATE path, which its mutable investigation '
  'state requires", and that 128''s write-deny rule "is NOT a standing D4 rule". A11 §8.6 '
  'constrains the mutation: APPEND-STATE-TRANSITIONS — every transition is retained immutably '
  'in audit_incident_transitions. DELETE is refused: A1 sub-ruling 2, AUDIT OUTRANKS DELETION. '
  'Retention 6 years (A12 ruling 4). NOT tamper-resistant — §8.19 declined the out-of-database '
  'anchor A11 sub-ruling 2 requires, so this binds at the DML layer only.';

COMMENT ON COLUMN public.audit_incidents.approval_status IS
  'Field 10 of the 11 (V5_DECISION_RESOLUTION:114). NO VOCABULARY IS RULED — unlike severity, '
  'which V5 specifies as Critical/High/Warning/Informational, the approval-status values are '
  'not enumerated in any tracked source. Left unconstrained rather than invented; see V5 §77.3.';

CREATE INDEX IF NOT EXISTS audit_incidents_severity_occurred_idx
  ON public.audit_incidents (severity, occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_incidents_actor_idx
  ON public.audit_incidents (actor_identity) WHERE actor_identity IS NOT NULL;

-- ── 2 · A11's REQUIRED RETENTION OF EACH TRANSITION ────────────────────────
-- "each state transition is retained as an immutable historical event" (A11 §8.6).
CREATE TABLE IF NOT EXISTS public.audit_incident_transitions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id   uuid NOT NULL,
  changed_field text NOT NULL,
  old_value     text,
  new_value     text,
  changed_by    uuid,
  changed_by_provenance text NOT NULL,
  changed_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT audit_incident_transitions_provenance_check
    CHECK (changed_by_provenance = ANY (ARRAY['grounded'::text, 'asserted'::text, 'system'::text]))
);
ALTER TABLE public.audit_incident_transitions OWNER TO postgres;

-- Deliberately no FK to audit_incidents: the transition history must outlive any
-- future disposition of the case record, and a cascade would mutate retained
-- audit state, which A1 sub-ruling 2 forbids in terms.
CREATE INDEX IF NOT EXISTS audit_incident_transitions_incident_idx
  ON public.audit_incident_transitions (incident_id, changed_at DESC);

COMMENT ON TABLE public.audit_incident_transitions IS
  'A11 §8.6 Incident = APPEND-STATE-TRANSITIONS — "each state transition is retained as an '
  'immutable historical event". NOT A FOURTH POPULATION: A1 enumerates three audit populations '
  'and D12 adds one observability population. This is the retention mechanism A11 mandates for '
  'population 2. Frozen by the same trigger shape as audit_events (migration 120 precedent, '
  'the only mechanism §8.5 names as binding every caller including service_role).';

-- ── 3 · IMMUTABILITY ───────────────────────────────────────────────────────
-- Transitions are frozen outright, exactly as audit_events is.
CREATE OR REPLACE FUNCTION public.audit_incident_transitions_freeze() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'audit_incident_transitions is append-only: a retained transition cannot be modified (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;
  RAISE EXCEPTION 'audit_incident_transitions is append-only: a retained transition cannot be deleted (id %)', OLD.id
    USING ERRCODE = '42501';
END;
$$;
ALTER FUNCTION public.audit_incident_transitions_freeze() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_incident_transitions_freeze() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_incident_transitions_freeze() FROM anon;

CREATE OR REPLACE TRIGGER trg_audit_incident_transitions_freeze
  BEFORE UPDATE OR DELETE ON public.audit_incident_transitions
  FOR EACH ROW EXECUTE FUNCTION public.audit_incident_transitions_freeze();

-- The case record may be UPDATEd (A1 sub-ruling 1) but never DELETEd (A1
-- sub-ruling 2 — "audit records must not be ON DELETE CASCADE'd merely because
-- the audited subject is deleted"; A12 ruling 1 — ANONYMISE-AND-RETAIN), and
-- every UPDATE must leave its transitions behind (A11).
CREATE OR REPLACE FUNCTION public.audit_incidents_record_transitions() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_prov text := CASE WHEN auth.uid() IS NOT NULL THEN 'grounded' ELSE 'system' END;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'audit_incidents is retained: an incident record cannot be deleted (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  -- The identity of the case is not investigation state and does not evolve.
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'audit_incidents identity columns are immutable (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  -- A11: retain each transition. Only the mutable investigation fields are
  -- tracked; the eleven-field record is what A1 defines, and `updated_at` is
  -- bookkeeping rather than investigation state.
  IF NEW.summary            IS DISTINCT FROM OLD.summary            THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'summary',OLD.summary,NEW.summary,v_uid,v_prov); END IF;
  IF NEW.scope              IS DISTINCT FROM OLD.scope              THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'scope',OLD.scope,NEW.scope,v_uid,v_prov); END IF;
  IF NEW.severity           IS DISTINCT FROM OLD.severity           THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'severity',OLD.severity,NEW.severity,v_uid,v_prov); END IF;
  IF NEW.suspected_cause    IS DISTINCT FROM OLD.suspected_cause    THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'suspected_cause',OLD.suspected_cause,NEW.suspected_cause,v_uid,v_prov); END IF;
  IF NEW.recommended_action IS DISTINCT FROM OLD.recommended_action THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'recommended_action',OLD.recommended_action,NEW.recommended_action,v_uid,v_prov); END IF;
  IF NEW.action_taken       IS DISTINCT FROM OLD.action_taken       THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'action_taken',OLD.action_taken,NEW.action_taken,v_uid,v_prov); END IF;
  IF NEW.approval_status    IS DISTINCT FROM OLD.approval_status    THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'approval_status',OLD.approval_status,NEW.approval_status,v_uid,v_prov); END IF;
  IF NEW.resolution         IS DISTINCT FROM OLD.resolution         THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'resolution',OLD.resolution,NEW.resolution,v_uid,v_prov); END IF;
  IF NEW.evidence           IS DISTINCT FROM OLD.evidence           THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'evidence',OLD.evidence::text,NEW.evidence::text,v_uid,v_prov); END IF;

  -- OCCURRENCE FACTS -- "when" and "actor/agent identity", fields 2 and 9 of the
  -- eleven. An earlier revision tracked neither, which left them SILENTLY MUTABLE:
  -- changeable with no retained transition, which is the one combination A11
  -- forbids outright ("each state transition is retained"). Local validation
  -- caught it (V5 §77.2).
  --
  -- They are tracked rather than frozen, deliberately. A1 calls this population a
  -- "case record carrying MUTABLE INVESTIGATION STATE", and an investigation that
  -- corrects who acted or when is doing its job -- freezing them would forbid the
  -- correction, which no ruling asks for. Tracking them forbids the SILENT
  -- correction, which is what A11 actually requires. Narrower than freezing on one
  -- axis, stricter than the earlier revision on the axis that matters.
  IF NEW.occurred_at        IS DISTINCT FROM OLD.occurred_at        THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'occurred_at',OLD.occurred_at::text,NEW.occurred_at::text,v_uid,v_prov); END IF;
  IF NEW.actor_identity     IS DISTINCT FROM OLD.actor_identity     THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'actor_identity',OLD.actor_identity::text,NEW.actor_identity::text,v_uid,v_prov); END IF;
  IF NEW.actor_provenance   IS DISTINCT FROM OLD.actor_provenance   THEN INSERT INTO public.audit_incident_transitions(incident_id,changed_field,old_value,new_value,changed_by,changed_by_provenance) VALUES (OLD.id,'actor_provenance',OLD.actor_provenance,NEW.actor_provenance,v_uid,v_prov); END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_incidents_record_transitions() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_incidents_record_transitions() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_incidents_record_transitions() FROM anon;

CREATE OR REPLACE TRIGGER trg_audit_incidents_transitions
  BEFORE UPDATE OR DELETE ON public.audit_incidents
  FOR EACH ROW EXECUTE FUNCTION public.audit_incidents_record_transitions();

-- ── 4 · READERS (A13 §8.8 — Incident: actor · active coach · admin · Trust) ─
ALTER TABLE public.audit_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_incident_transitions ENABLE ROW LEVEL SECURITY;

-- A13's Incident row names FOUR readers, and unlike the Event row it DOES include
-- the actor. Implemented exactly as enumerated.
CREATE POLICY "audit incidents read: actor, active coach, admin, trust operator"
  ON public.audit_incidents FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR public.is_trust_operator()
    OR actor_identity = auth.uid()
    OR public.is_active_coach_of(actor_identity)
  );

-- The transitions carry the same readers as the case they belong to: they are the
-- same population (A11's retention mechanism), so a different reader set would be
-- a new reader class, which the standing instruction forbids.
CREATE POLICY "audit incident transitions read: follows the incident"
  ON public.audit_incident_transitions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.audit_incidents i
             WHERE i.id = incident_id
               AND (public.is_admin()
                    OR public.is_trust_operator()
                    OR i.actor_identity = auth.uid()
                    OR public.is_active_coach_of(i.actor_identity)))
  );

-- No INSERT/UPDATE/DELETE policy on either table. A3 §8.5 gives the Incident
-- population the write path "RPC + application", so writes arrive through a
-- definer RPC, never through a client policy.
REVOKE ALL ON TABLE public.audit_incidents FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_incidents FROM anon;
REVOKE ALL ON TABLE public.audit_incident_transitions FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_incident_transitions FROM anon;
GRANT SELECT ON TABLE public.audit_incidents TO authenticated;
GRANT SELECT ON TABLE public.audit_incident_transitions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.audit_incidents TO service_role;
GRANT SELECT, INSERT ON TABLE public.audit_incident_transitions TO service_role;
