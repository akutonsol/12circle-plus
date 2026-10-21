-- ═══════════════════════════════════════════════════════════════════════════
-- 178 · P5 · "revenue by stream" and the money split — both named by the approved
--       design, both mechanically determined, neither invented.
--
-- WHY THIS IS AUTHORIZED WORK AND NOT A NEW PRODUCT DECISION.
-- The published design's own requirements list (SCREEN-INVENTORY.md, "Data each page
-- needs", at commit 931218b) states them outright:
--
--   * Dashboard  — "revenue by stream"
--   * Ecosystem  — "monetisation (plans, payouts, commission)"
--
-- 171 shipped the METRIC-06 decomposition the owner ruled — gross / commission / net
-- for COACHING — and nothing else. The two requirements above need no new definition:
--
--   * the STREAM vocabulary is already established: `create-checkout/index.ts:52`
--     declares `'coach' | 'coach_plan' | 'self_guided' | 'ai_guided' | 'event_ticket'
--     | 'package'`. Summing by it is a GROUP BY, not a business rule.
--   * the PAYOUT columns are defined in their own DDL comments (`038:24-25`):
--     `coach_payout int -- cents to the coach`, `platform_fee int -- cents to 12 Circle`.
--
-- So no vocabulary is invented and no rate is derived. What the owner ruled about
-- coaching revenue is untouched; these are additional columns beside it.
--
-- AN UNKNOWN STREAM IS COUNTED, NOT DROPPED. `payments.kind` carries NO CHECK
-- constraint — established at V5 §162 — so a value outside that vocabulary is possible.
-- `stream_other_cents` and `stream_other_count` exist so the six named streams plus
-- "other" reconcile to the paid total, exactly as METRIC-17's `age_out_of_range` keeps
-- its buckets honest. A silently dropped stream would understate revenue, which is the
-- one direction a revenue figure must never be wrong in by accident.
--
-- THE SPLIT IS REPORTED, NOT RECOMPUTED. `coach_payout` and `platform_fee` are read as
-- recorded; they are NOT derived from `amount_cents * commission_rate`. Deriving them
-- would invent a second authority for a figure Stripe already settled, and
-- `payout_missing` discloses how many paid coaching payments carry neither — the same
-- no-fabrication discipline as `commission_rate_missing`.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.admin_revenue_overview
WITH (security_invoker = off) AS
WITH coaching AS (
  SELECT p.amount_cents, p.commission_rate, p.currency
    FROM public.payments p
   WHERE p.kind IN ('coach', 'package')      -- create-checkout:52; the two coaching kinds
     AND p.status = 'paid'
     AND p.amount_cents IS NOT NULL          -- "do not fabricate where unavailable"
),
paid AS (
  SELECT p.kind, p.amount_cents, p.coach_payout, p.platform_fee
    FROM public.payments p
   WHERE p.status = 'paid'
),
KNOWN AS (SELECT ARRAY['coach','coach_plan','self_guided','ai_guided','event_ticket','package'] AS k)
SELECT
  -- ── METRIC-06a / 06b, exactly as 171 and 172 established ────────────────
  COALESCE((SELECT sum(amount_cents) FROM coaching), 0)                      AS gross_coaching_cents,
  COALESCE((SELECT sum(amount_cents * commission_rate)
              FROM coaching WHERE commission_rate IS NOT NULL), 0)::bigint   AS platform_commission_cents,
  COALESCE((SELECT sum(amount_cents) FROM coaching), 0)
    - COALESCE((SELECT sum(amount_cents * commission_rate)
                  FROM coaching WHERE commission_rate IS NOT NULL), 0)::bigint
                                                                             AS net_platform_cents,
  'usd'::text                                                                AS source_currency,
  (SELECT count(*) FROM coaching WHERE commission_rate IS NULL)              AS commission_rate_missing,
  (SELECT count(*) FROM public.payments
    WHERE kind IN ('coach','package') AND status = 'paid'
      AND amount_cents IS NULL)                                              AS amount_missing,
  (SELECT count(*) FROM public.payments
    WHERE kind NOT IN ('coach','package') AND status = 'paid')               AS excluded_non_coaching,
  (SELECT rate   FROM public.fx_rates
    WHERE base = 'usd' AND quote = 'gbp' ORDER BY as_of DESC LIMIT 1)        AS fx_usd_gbp_rate,
  (SELECT as_of  FROM public.fx_rates
    WHERE base = 'usd' AND quote = 'gbp' ORDER BY as_of DESC LIMIT 1)        AS fx_as_of,
  (SELECT source FROM public.fx_rates
    WHERE base = 'usd' AND quote = 'gbp' ORDER BY as_of DESC LIMIT 1)        AS fx_source,

  -- ── NEW · revenue BY STREAM (approved design: Dashboard) ────────────────
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'coach'), 0)        AS stream_coach_cents,
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'coach_plan'), 0)   AS stream_coach_plan_cents,
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'self_guided'), 0)  AS stream_self_guided_cents,
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'ai_guided'), 0)    AS stream_ai_guided_cents,
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'event_ticket'), 0) AS stream_event_ticket_cents,
  COALESCE((SELECT sum(amount_cents) FROM paid WHERE kind = 'package'), 0)      AS stream_package_cents,
  -- the reconciliation column: `kind` has no CHECK, so an unknown stream is possible
  COALESCE((SELECT sum(amount_cents) FROM paid, KNOWN
             WHERE kind IS NULL OR NOT (kind = ANY(KNOWN.k))), 0)              AS stream_other_cents,
  (SELECT count(*) FROM paid, KNOWN
    WHERE kind IS NULL OR NOT (kind = ANY(KNOWN.k)))                           AS stream_other_count,
  COALESCE((SELECT sum(amount_cents) FROM paid), 0)                            AS paid_total_cents,

  -- ── NEW · the money split as RECORDED (approved design: Ecosystem) ──────
  COALESCE((SELECT sum(coach_payout) FROM paid), 0)                            AS coach_payout_cents,
  COALESCE((SELECT sum(platform_fee) FROM paid), 0)                            AS platform_fee_cents,
  (SELECT count(*) FROM public.payments
    WHERE status = 'paid' AND kind IN ('coach','package')
      AND (coach_payout IS NULL OR platform_fee IS NULL))                      AS payout_missing
 WHERE public.admin_can('Monetization', 'view');

COMMENT ON VIEW public.admin_revenue_overview IS
  'V5 §181 · METRIC-06a/06b plus the approved design''s "revenue by stream" (Dashboard) '
  'and "payouts, commission" (Ecosystem). Qualifying coaching payments are '
  'kind IN (coach, package) — the two kinds in the create-checkout:52 vocabulary by '
  'which a member pays a coach. The STREAM columns sum that same established '
  'vocabulary, and stream_other_cents/count exist because payments.kind has NO CHECK '
  'constraint: an unrecognised stream is counted, never dropped, so the six named '
  'streams plus other reconcile to paid_total_cents. coach_payout_cents and '
  'platform_fee_cents are read AS RECORDED (038:24-25) and never derived from '
  'amount_cents * commission_rate — that would invent a second authority for a figure '
  'Stripe settled. payout_missing discloses the gap, as commission_rate_missing does.';

REVOKE ALL ON public.admin_revenue_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_revenue_overview TO authenticated;
