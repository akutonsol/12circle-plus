-- Migration 144 — P2 · the CONTROL EVIDENCE population (A1 §8.4 population 3).
--
-- Third of D4's four populations. A1's shape is unusual and its exclusions are
-- part of the ruling, not an omission: "versioned matrix row keyed to a
-- requirement (SA-03) — NO ACTOR, NO SUBJECT, NO OCCURRENCE TIME." Those three
-- columns are therefore absent BY RULING, and adding them later would be a change
-- to A1, not a refinement of this table.
--
-- The seven fields are quoted, not inferred. V5_IMPACT_ANALYSIS_2026-09-27.md:191
-- (SA-03): "Control evidence: requirement, implementation location, test evidence,
-- result, date/version, exception, owner. A generic statement that a control
-- 'passes' is insufficient."
CREATE TABLE IF NOT EXISTS public.audit_control_evidence (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  requirement             text NOT NULL,   -- 1 · requirement (the key)
  implementation_location text NOT NULL,   -- 2 · implementation location
  test_evidence           text NOT NULL,   -- 3 · test evidence
  result                  text NOT NULL,   -- 4 · result
  date_version            text NOT NULL,   -- 5 · date/version  ("versioned")
  exception               text,            -- 6 · exception
  owner                   text NOT NULL,   -- 7 · owner

  recorded_at             timestamptz NOT NULL DEFAULT now(),

  -- "versioned matrix row keyed to a requirement" — the key is (requirement,
  -- date_version), so a requirement accumulates versions rather than being
  -- overwritten. That is what makes the row VERSIONED rather than current-state.
  CONSTRAINT audit_control_evidence_version_key UNIQUE (requirement, date_version)
);
ALTER TABLE public.audit_control_evidence OWNER TO postgres;

COMMENT ON TABLE public.audit_control_evidence IS
  'D4·A1 §8.4 population 3 — versioned control-evidence matrix rows keyed to a requirement '
  '(SA-03). A1 excludes actor, subject and occurrence time BY RULING; their absence is the '
  'ruling, not an omission. A11 §8.6: NO RUNTIME WRITE PATH — "authored/produced evidence, not '
  'a runtime audit event". Retention 6 years (A12 ruling 4). Readers: admin · Trust operator '
  '(A13 §8.8). SA-03 also governs content: "a generic statement that a control passes is '
  'insufficient" — result must carry the evidence, not an assertion.';

-- ── IMMUTABILITY — A11 §8.6: NO RUNTIME WRITE PATH ─────────────────────────
-- A11 gives this population the strictest of the three readings. A row is
-- authored; it is never edited and never deleted. A correction is a NEW VERSION
-- (a new date_version for the same requirement), which is what "versioned" means
-- and why the unique key is the pair.
CREATE OR REPLACE FUNCTION public.audit_control_evidence_freeze() RETURNS trigger
  LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'audit_control_evidence is authored evidence: a row cannot be edited — record a new date_version instead (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;
  RAISE EXCEPTION 'audit_control_evidence is retained: a row cannot be deleted (id %)', OLD.id
    USING ERRCODE = '42501';
END;
$$;
ALTER FUNCTION public.audit_control_evidence_freeze() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_control_evidence_freeze() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_control_evidence_freeze() FROM anon;

CREATE OR REPLACE TRIGGER trg_audit_control_evidence_freeze
  BEFORE UPDATE OR DELETE ON public.audit_control_evidence
  FOR EACH ROW EXECUTE FUNCTION public.audit_control_evidence_freeze();

-- ── READERS (A13 §8.8 — Control evidence: admin · Trust operator) ──────────
ALTER TABLE public.audit_control_evidence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "control evidence read: admin, trust operator"
  ON public.audit_control_evidence FOR SELECT TO authenticated
  USING (public.is_admin() OR public.is_trust_operator());

-- A NOTED TENSION, taken narrowly rather than guessed.
--   A3 §8.5 gives this population the write path "AUTHORED MIGRATION + application".
--   A11 §8.6 gives it "NO RUNTIME WRITE PATH".
-- Read together, the authored-migration arm is unambiguous and the "application"
-- arm is not: a runtime application write is exactly what A11 excludes. The
-- narrow reading is taken under hierarchy 1 and 11 — writes come from authored
-- migrations, executed as the table's owner, and NO runtime role is granted
-- INSERT, not even service_role. Broadening this to admit an application writer
-- is an ADDITIVE ruling and must be taken as one; see V5 §77.3.
REVOKE ALL ON TABLE public.audit_control_evidence FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_control_evidence FROM anon;
GRANT SELECT ON TABLE public.audit_control_evidence TO authenticated;
GRANT SELECT ON TABLE public.audit_control_evidence TO service_role;
