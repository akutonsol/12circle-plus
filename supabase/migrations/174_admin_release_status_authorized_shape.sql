-- ═══════════════════════════════════════════════════════════════════════════
-- 174 · METRIC-11 · let the client tell "not authorized" from "not recorded"
--
-- THE DEFECT, found while wiring the UI and not by a test.
-- 173's `admin_release_status` returns NO ROW in two completely different cases:
--   (a) the caller lacks `System·view` — an AUTHORIZATION outcome;
--   (b) the caller is authorized but no release has been recorded — an absence of
--       DATA, which is the current and expected state, since the CI ingestion path
--       is gated on P10/CONF-D9 and is not built.
-- A client cannot distinguish them, so it must either mislabel an unauthorized
-- viewer's card as "Not recorded" or tell an authorized operator they lack a
-- permission they hold. Both are false statements rendered confidently.
--
-- Every other metric surface already draws this distinction the right way round, and
-- 172's METRIC-02 is the precedent: NO ROW means "no capability for this area", and a
-- NULL COLUMN means "authorized, but this figure is not available to you". This
-- migration brings METRIC-11 into line with that contract:
--
--   * not authorized  -> no row            (unchanged)
--   * authorized, nothing recorded -> ONE row whose every column is NULL
--   * authorized, recorded         -> one row per current release
--
-- The LEFT JOIN against a one-row anchor is what produces the all-NULL row. It
-- cannot leak anything: the WHERE still gates on admin_can, and a NULL column
-- carries no information beyond "there is nothing here".
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.admin_release_status
WITH (security_invoker = off) AS
  SELECT
    r.release_version,
    r.environment,
    -- half A · CI
    r.ci_status,
    r.ci_checks_passed,
    r.ci_checks_total,
    r.ci_source,
    r.ci_recorded_at,
    -- half B · the V5 gate ledger, still never merged with half A
    r.gate_verdict,
    r.gates_pass,
    r.gates_partial,
    r.gates_fail,
    r.gates_total,
    r.gate_source,
    r.gate_recorded_at,
    r.recorded_at
  FROM (SELECT 1) AS anchor
  LEFT JOIN public.release_status r ON r.is_current
 WHERE public.admin_can('System', 'view');

COMMENT ON VIEW public.admin_release_status IS
  'V5 §166 · METRIC-11. The current release per environment, carrying the CI verdict '
  'and the V5 gate verdict as separately labelled, separately sourced states. No '
  'column combines them. Gated admin_can(''System'',''view''). THE ROW SHAPE IS PART '
  'OF THE CONTRACT: no row = no System capability; ONE all-NULL row = authorized but '
  'nothing recorded, which is the expected state while CI ingestion remains gated on '
  'P10/CONF-D9; one row per current release otherwise. This is the same distinction '
  '172 draws for METRIC-02, so a client never has to guess which case it is in.';

REVOKE ALL ON public.admin_release_status FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_release_status TO authenticated;
