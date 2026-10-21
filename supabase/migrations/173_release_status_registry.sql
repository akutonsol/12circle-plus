-- ═══════════════════════════════════════════════════════════════════════════
-- 173 · QA & RELEASE — owner decision METRIC-11 = Option 3, 2026-10-07
--
--   "show both CI status and V5 release-gate status, clearly labelled.
--    For example:  CI Status: Passing  /  V5 Release Gate: Blocked
--    These are intentionally separate states and must not be collapsed."
--
-- WHAT THIS MIGRATION DOES AND DELIBERATELY DOES NOT DO.
-- The owner's ruling answers the NARROW question the data contract raised at
-- `V5_ADMIN_DASHBOARD_DATA_CONTRACT:219` — "whether the card reflects the V5 gate
-- ledger, CI status, or both". It is Option 3: both.
--
-- It does NOT release the ARCHITECTURE item recorded immediately below it at :220,
-- "ingesting CI results requires an egress or webhook path", which cites `P10`'s
-- unresolved "installation forbidden" constraint and is explicitly "not released
-- here". `CONF-D9` (ingest CI conclusions) is likewise unreleased. So this migration
-- builds the RECORDED SURFACE and NO INGESTION PRODUCER. No egress is introduced, no
-- webhook, no credential, no third party. Until a row is recorded the card renders
-- its approved `A11` empty state, which is the honest rendering of "not ingested".
--
-- It also supplies the artifact :221 records as missing — "there is no release/version
-- registry in the database" — WITHOUT deciding what sources the version string. The
-- column exists; whoever records a row supplies the value and must name its source.
--
-- WHY THE TWO HALVES CANNOT BE COLLAPSED HERE EVEN BY ACCIDENT. The owner's
-- requirement is structural, so it is enforced structurally: each half carries its own
-- status, its own counts, its own source and its own recorded_at. There is
-- deliberately NO `overall_status`, NO `is_blocked`, NO single badge column — a column
-- like that is exactly the collapse the ruling forbids, and it would also assert a
-- release verdict from two authorities that currently DISAGREE (CI green 6/6 while
-- §20.3 records 5 PASS · 2 PARTIAL · 8 FAIL of 15). The disagreement is the point.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.release_status (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  release_version    text NOT NULL,
  environment        text NOT NULL,
  is_current         boolean NOT NULL DEFAULT false,

  -- ── half A · CI. Its own provenance, independent of the gate half. ────────
  ci_status          text,
  ci_checks_passed   integer,
  ci_checks_total    integer,
  ci_source          text,
  ci_recorded_at     timestamptz,

  -- ── half B · the V5 release-gate ledger. Its own provenance. ─────────────
  gate_verdict       text,
  gates_pass         integer,
  gates_partial      integer,
  gates_fail         integer,
  gates_total        integer,
  gate_source        text,
  gate_recorded_at   timestamptz,

  recorded_at        timestamptz NOT NULL DEFAULT now(),

  -- ANTI-FABRICATION, and the most load-bearing constraint in this table. A status
  -- may not exist without the source that asserted it and the moment it was
  -- asserted. "Never fabricate a value where the underlying source is unavailable"
  -- is thereby a schema property rather than a convention someone has to remember.
  CONSTRAINT release_status_ci_provenance CHECK (
    (ci_status IS NULL AND ci_source IS NULL AND ci_recorded_at IS NULL)
    OR (ci_status IS NOT NULL AND ci_source IS NOT NULL AND ci_recorded_at IS NOT NULL)),
  CONSTRAINT release_status_gate_provenance CHECK (
    (gate_verdict IS NULL AND gate_source IS NULL AND gate_recorded_at IS NULL)
    OR (gate_verdict IS NOT NULL AND gate_source IS NOT NULL AND gate_recorded_at IS NOT NULL)),

  -- The gate verdict vocabulary IS ruled: §20.3 tracks the ledger as
  -- "5 PASS · 2 PARTIAL · 8 FAIL of 15". It is constrained to exactly those words.
  CONSTRAINT release_status_gate_vocabulary CHECK (
    gate_verdict IS NULL OR gate_verdict IN ('PASS', 'PARTIAL', 'FAIL')),

  -- `environment` and `ci_status` get NO vocabulary constraint, on purpose. The
  -- approved design evidences exactly one environment ("Release: 4.2.0 · staging")
  -- and exactly one build word ("Build: Passing"); their complements appear nowhere.
  -- Inventing 'production' or 'failing' to fill a CHECK would be inventing a state
  -- vocabulary, which §77.3 already refused to do for `approval_status` and
  -- `events.status`. A wrong CHECK is worse than an absent one.

  -- Counts must reconcile, the same discipline METRIC-17's buckets follow.
  CONSTRAINT release_status_gate_counts CHECK (
    (gates_pass IS NULL AND gates_partial IS NULL AND gates_fail IS NULL AND gates_total IS NULL)
    OR (COALESCE(gates_pass,0) + COALESCE(gates_partial,0) + COALESCE(gates_fail,0) = gates_total)),
  CONSTRAINT release_status_ci_counts CHECK (
    ci_checks_passed IS NULL OR ci_checks_total IS NULL OR ci_checks_passed <= ci_checks_total)
);

-- One current release per environment, enforced rather than trusted.
CREATE UNIQUE INDEX IF NOT EXISTS release_status_one_current_per_env
  ON public.release_status (environment) WHERE is_current;

COMMENT ON TABLE public.release_status IS
  'V5 §163 · METRIC-11 = Option 3. Carries the CI verdict and the V5 release-gate '
  'verdict as TWO INDEPENDENT recorded states, each with its own source and '
  'timestamp. There is deliberately no combined status column: the owner ruled these '
  '"must not be collapsed", and the two authorities currently disagree. Starts EMPTY '
  'and has NO ingestion producer — the egress/webhook path at data-contract :220 is '
  'gated on P10 and CONF-D9, neither of which is released. Until a row exists the card '
  'renders its approved A11 empty state.';

COMMENT ON COLUMN public.release_status.ci_source IS
  'Who asserted the CI verdict, e.g. a workflow run reference. Required whenever '
  'ci_status is present — see release_status_ci_provenance.';
COMMENT ON COLUMN public.release_status.gate_source IS
  'Who asserted the gate verdict, e.g. RELEASE_GATES.md at a commit. Required '
  'whenever gate_verdict is present — see release_status_gate_provenance.';

ALTER TABLE public.release_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin layer reads release status" ON public.release_status;
CREATE POLICY "admin layer reads release status" ON public.release_status
  FOR SELECT TO authenticated USING (public.admin_can('System', 'view'));

-- Read-only to every caller, the 158 posture. A release verdict the Admin layer
-- could write is a release verdict the Admin layer could invent.
REVOKE ALL ON TABLE public.release_status FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON TABLE public.release_status TO authenticated;

-- ── the Admin surface ──────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.admin_release_status
WITH (security_invoker = off) AS
  SELECT
    r.release_version,
    r.environment,
    -- half A, labelled as the owner requires
    r.ci_status,
    r.ci_checks_passed,
    r.ci_checks_total,
    r.ci_source,
    r.ci_recorded_at,
    -- half B, labelled separately and never merged with half A
    r.gate_verdict,
    r.gates_pass,
    r.gates_partial,
    r.gates_fail,
    r.gates_total,
    r.gate_source,
    r.gate_recorded_at,
    r.recorded_at
  FROM public.release_status r
 WHERE r.is_current
   AND public.admin_can('System', 'view');

COMMENT ON VIEW public.admin_release_status IS
  'V5 §163 · METRIC-11. The current release per environment, carrying the CI verdict '
  'and the V5 gate verdict as separately labelled, separately sourced states. No '
  'column combines them. Gated admin_can(''System'',''view''). Empty until a release '
  'is recorded, which is the truthful rendering of an unbuilt ingestion path.';

REVOKE ALL ON public.admin_release_status FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_release_status TO authenticated;
