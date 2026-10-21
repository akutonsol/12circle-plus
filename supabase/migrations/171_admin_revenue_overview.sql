-- ═══════════════════════════════════════════════════════════════════════════
-- 171 · REVENUE — owner decisions METRIC-06a and METRIC-06b, 2026-10-07
--
-- THE CALCULATION IS THE OWNER'S, QUOTED:
--   "Gross coaching revenue = sum of qualifying coaching payment amounts at the
--    source transaction amount.
--    Platform commission = gross coaching revenue × marketplace_commission_rate.
--    Net/platform revenue = gross coaching revenue − platform commission.
--    Admin display uses explicit FX from the USD source amount to GBP, with the FX
--    rate/source and date recorded. Do not fabricate a value where the underlying
--    payment amount is unavailable."
--
-- Direction `I` requires the decomposition and forbids fabrication; COWORK §8 bars
-- an agent inventing monetization policy. Every selector below is therefore cited.
--
-- WHAT "QUALIFYING COACHING PAYMENT" RESOLVES TO, and why it is not a guess.
-- create-checkout/index.ts:52 declares the payment vocabulary:
--     'coach' | 'coach_plan' | 'self_guided' | 'ai_guided' | 'event_ticket' | 'package'
-- Of these, money reaches a COACH for coaching in exactly two: `coach` (a coaching
-- subscription) and `package` (a session pack bought from a coach) — and both are
-- the kinds that carry `payments.coach_id` (028:6). The others are platform revenue
-- or tickets: `coach_plan` is a coach paying 12 Circle, `self_guided`/`ai_guided`
-- are member plans, `event_ticket` is an event. They are EXCLUDED and counted
-- separately below, so the exclusion is visible rather than silent.
--
-- WHICH RATE. 038:14 puts `marketplace_commission_rate` on user_profiles —
-- "Commission charged to a MARKETPLACE-acquired client's coaching payments (0–1)",
-- default 0.10 — and 038:23 records `payments.commission_rate` per transaction.
-- The per-payment column IS that rate as it applied at the time, so it is the one
-- used. Where it is NULL the payment is NOT given a substituted rate; it is counted
-- in `commission_rate_missing` so the figure stays auditable. Substituting the
-- coach's current rate onto an old payment would fabricate a value.
--
-- NO GBP FIGURE IS COMPUTED HERE. METRIC-06a is single-currency USD plus explicit
-- FX for display. The view reports the SOURCE amounts in their source currency and
-- the FX row that would convert them, with rate, source and date. If no FX row
-- exists the GBP columns are NULL — the display renders an A11 state rather than a
-- number nobody can stand behind.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · the FX record the owner's definition requires ──────────────────────
CREATE TABLE IF NOT EXISTS public.fx_rates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  base        text NOT NULL,
  quote       text NOT NULL,
  rate        numeric NOT NULL CHECK (rate > 0),
  as_of       date NOT NULL,
  source      text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fx_rates_pair_day UNIQUE (base, quote, as_of)
);

COMMENT ON TABLE public.fx_rates IS
  'V5 §162 · the explicit FX record owner decision METRIC-06a requires: "Admin '
  'display uses explicit FX from the USD source amount to GBP, with the FX '
  'rate/source and date recorded." Starts EMPTY and is never auto-populated — a '
  'rate nobody supplied is a fabricated value. No vendor feed is introduced.';

ALTER TABLE public.fx_rates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin layer reads fx rates" ON public.fx_rates;
CREATE POLICY "admin layer reads fx rates" ON public.fx_rates
  FOR SELECT TO authenticated USING (public.admin_can('Monetization', 'view'));

-- Read-only to every caller. Rates arrive by a deliberate act, not an app write.
REVOKE ALL ON TABLE public.fx_rates FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON TABLE public.fx_rates TO authenticated;

-- ── 2 · the revenue surface ────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.admin_revenue_overview
WITH (security_invoker = off) AS
WITH coaching AS (
  SELECT p.amount_cents, p.commission_rate, p.currency
    FROM public.payments p
   WHERE p.kind IN ('coach', 'package')      -- create-checkout:52; both carry coach_id
     AND p.status = 'paid'
     AND p.amount_cents IS NOT NULL          -- "do not fabricate where unavailable"
),
fx AS (
  SELECT rate, as_of, source
    FROM public.fx_rates
   WHERE base = 'usd' AND quote = 'gbp'
   ORDER BY as_of DESC
   LIMIT 1
)
SELECT
  -- source amounts, in the source currency
  COALESCE((SELECT sum(amount_cents) FROM coaching), 0)                      AS gross_coaching_cents,
  COALESCE((SELECT sum(amount_cents * commission_rate)
              FROM coaching WHERE commission_rate IS NOT NULL), 0)::bigint   AS platform_commission_cents,
  COALESCE((SELECT sum(amount_cents) FROM coaching), 0)
    - COALESCE((SELECT sum(amount_cents * commission_rate)
                  FROM coaching WHERE commission_rate IS NOT NULL), 0)::bigint
                                                                             AS net_platform_cents,
  'usd'::text                                                                AS source_currency,
  -- auditability: what the figure could NOT account for
  (SELECT count(*) FROM coaching WHERE commission_rate IS NULL)              AS commission_rate_missing,
  (SELECT count(*) FROM public.payments
    WHERE kind IN ('coach','package') AND status = 'paid'
      AND amount_cents IS NULL)                                              AS amount_missing,
  (SELECT count(*) FROM public.payments
    WHERE kind NOT IN ('coach','package') AND status = 'paid')               AS excluded_non_coaching,
  -- the FX the owner requires, recorded rather than assumed
  (SELECT rate   FROM fx)                                                    AS fx_usd_gbp_rate,
  (SELECT as_of  FROM fx)                                                    AS fx_as_of,
  (SELECT source FROM fx)                                                    AS fx_source
 WHERE public.admin_can('Monetization', 'view');

COMMENT ON VIEW public.admin_revenue_overview IS
  'V5 §162 · METRIC-06a/06b. Gross · commission · net, per the owner''s calculation, '
  'in the SOURCE currency. Qualifying coaching payments are kind IN (coach, package) '
  '— the two kinds that reach a coach (create-checkout:52, payments.coach_id 028:6); '
  'other kinds are excluded and COUNTED. Commission uses the per-payment '
  'commission_rate (038:23) as it applied; payments missing it are counted, never '
  'given a substituted rate. NO GBP figure is computed: fx_usd_gbp_rate/as_of/source '
  'carry the recorded rate, and are NULL when none exists.';

REVOKE ALL ON public.admin_revenue_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_revenue_overview TO authenticated;
