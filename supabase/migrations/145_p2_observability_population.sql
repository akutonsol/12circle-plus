-- Migration 145 — P2 · the D12 OBSERVABILITY population.
--
-- The fourth population, and NOT one of A1's three. §8.14 (D12·Q4) ruled that the
-- observability-audit category is audit-worthy under A2 AND resident in a
-- "separate D12/observability population — not in any of A1's three audit
-- populations". A1 sub-ruling 3 says the same from the other side: audit and
-- observability audit events "are TWO DISTINCT populations. Their schemas and
-- semantics must not be merged."
--
-- D12·Q7 (V5 §74.2) ruled the store IN-DATABASE: PD-A24 = C is "vendor-free by
-- construction" and introduces no third-party vendor, and §19.3's four DML-layer
-- rulings for this population could not bind an external store.
CREATE TABLE IF NOT EXISTS public.observability_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- §19.3's D12·Q1 ruled SQ-10's component list: "structured logs · metrics ·
  -- traces · health endpoints · alerting · the correlation identifier". The
  -- correlation identifier is a column below, not a component row, so the five
  -- emitting components are the vocabulary here. The column is REQUIRED because
  -- §8.16·Q2 sets retention PER COMPONENT.
  component      text NOT NULL,

  -- §19.3's D12·Q5, and it is a prohibition as much as a definition: "the
  -- observability population carries NO SUBJECT IDENTIFIER — only the correlation
  -- identifier", which "must be a random opaque value with no derivation from
  -- subject identity". THERE IS DELIBERATELY NO subject_id COLUMN. Adding one
  -- would reverse the ruling that makes severance anonymise the operation across
  -- both populations.
  correlation_id uuid,

  -- V5 §71 (D12·Q5 = Option A). NULL until project B is provisioned.
  correlation_signature text,
  correlation_key_id    text,

  occurred_at    timestamptz NOT NULL DEFAULT now(),
  recorded_at    timestamptz NOT NULL DEFAULT now(),

  -- §8.16·Q1: "identity and occurrence facts of an observability record are
  -- immutable at the DML layer; PAYLOAD FIELDS ARE WRITE-ONCE."
  payload        jsonb,

  -- §8.16·Q2 / D12·Q6, ANSWERED AS ONE: "Observability audit events retain A12's
  -- 6-year Event window. All other observability components — logs, metrics,
  -- traces, health — take a 90-day operational window." Stored rather than
  -- derived so a retention sweep reads one column and cannot disagree with the
  -- component vocabulary.
  retention_class text NOT NULL,

  CONSTRAINT observability_events_component_check
    CHECK (component = ANY (ARRAY['structured_log'::text, 'metric'::text, 'trace'::text,
                                  'health'::text, 'alerting'::text,
                                  'observability_audit'::text])),
  CONSTRAINT observability_events_retention_class_check
    CHECK (retention_class = ANY (ARRAY['audit_6y'::text, 'operational_90d'::text])),
  -- The two vocabularies are bound to each other, so a 90-day class can never be
  -- attached to an audit-worthy record (§8.16·Q2, and 11 — never silently narrow
  -- an already-ruled retention).
  CONSTRAINT observability_events_retention_matches_component
    CHECK ((component = 'observability_audit' AND retention_class = 'audit_6y')
        OR (component <> 'observability_audit' AND retention_class = 'operational_90d'))
);
ALTER TABLE public.observability_events OWNER TO postgres;

COMMENT ON TABLE public.observability_events IS
  'The D12 observability population — SEPARATE from A1''s three audit populations (§8.14, A1 '
  'sub-ruling 3: "their schemas and semantics must not be merged"). In-database per D12·Q7 '
  '(V5 §74.2) because PD-A24 = C is vendor-free by construction. Carries NO subject identifier '
  'by ruling (D12·Q5) — only the correlation identifier, which must be random and opaque. '
  'Retention is per component (§8.16·Q2): observability audit events 6 years, everything else '
  '90 days. NOT tamper-resistant: §8.19 declined the anchor and §19.3 states it outright.';

COMMENT ON COLUMN public.observability_events.correlation_signature IS
  'V5 §71.1 NORMATIVE — prevention only against an adversary WITHOUT the signer''s invoke '
  'credential. NO prevention against a compromised Edge Function / service_role trust root '
  '(§68). Detection only, via the issuance log (§71.3 DET-1..DET-4). NULL until project B is '
  'provisioned; a NULL signature is NOT correlatable.';

CREATE INDEX IF NOT EXISTS observability_events_correlation_idx
  ON public.observability_events (correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS observability_events_component_occurred_idx
  ON public.observability_events (component, occurred_at DESC);

-- ── IMMUTABILITY — §8.16·Q1 FREEZE-IDENTITY-COLUMNS, payload WRITE-ONCE ────
CREATE OR REPLACE FUNCTION public.observability_events_freeze() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'observability_events is retained: a record cannot be deleted (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  -- Identity and occurrence facts: immutable.
  IF NEW.id             IS DISTINCT FROM OLD.id
  OR NEW.component      IS DISTINCT FROM OLD.component
  OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
  OR NEW.occurred_at    IS DISTINCT FROM OLD.occurred_at
  OR NEW.recorded_at    IS DISTINCT FROM OLD.recorded_at
  OR NEW.retention_class IS DISTINCT FROM OLD.retention_class THEN
    RAISE EXCEPTION 'observability_events identity and occurrence facts are immutable (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  -- Payload: WRITE-ONCE. It may be filled once; it may never be rewritten.
  IF OLD.payload IS NOT NULL AND NEW.payload IS DISTINCT FROM OLD.payload THEN
    RAISE EXCEPTION 'observability_events.payload is write-once (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  -- The signature is part of the correlation claim, not payload, and is written
  -- once with it. Same rule.
  IF OLD.correlation_signature IS NOT NULL
     AND NEW.correlation_signature IS DISTINCT FROM OLD.correlation_signature THEN
    RAISE EXCEPTION 'observability_events.correlation_signature is write-once (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.observability_events_freeze() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.observability_events_freeze() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.observability_events_freeze() FROM anon;

CREATE OR REPLACE TRIGGER trg_observability_events_freeze
  BEFORE UPDATE OR DELETE ON public.observability_events
  FOR EACH ROW EXECUTE FUNCTION public.observability_events_freeze();

-- ── READERS — §8.16·Q3 / D12·Q12: admin + Trust operator, ROLE-CLASS ONLY ──
-- "Observability records carry no subject relationship to anchor on, so no
-- relationship-based reader applies." That is why there is no is_active_coach_of
-- arm here and there is one on the Event population: the ruling turns on the
-- absence of a subject, which D12·Q5 guarantees.
ALTER TABLE public.observability_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "observability read: admin, trust operator — role class only"
  ON public.observability_events FOR SELECT TO authenticated
  USING (public.is_admin() OR public.is_trust_operator());

REVOKE ALL ON TABLE public.observability_events FROM PUBLIC;
REVOKE ALL ON TABLE public.observability_events FROM anon;
GRANT SELECT ON TABLE public.observability_events TO authenticated;
-- §8.16·Q4, ANSWERED: "the deferral is discharged for the observability population
-- ON THE SAME TERMS AS THE AUDIT POPULATIONS — service_role is NOT the writer of
-- record." service_role may INSERT (it is the tier that emits telemetry) but the
-- freeze above binds it exactly as it binds every other caller, so it cannot
-- rewrite what it wrote. That is the whole of what "not the writer of record"
-- can mean at the DML layer, and §8.19 declined the anchor that would make it
-- mean more (limit required by 13).
GRANT SELECT, INSERT ON TABLE public.observability_events TO service_role;
