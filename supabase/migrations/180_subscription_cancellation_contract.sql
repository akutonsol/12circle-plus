-- ═══════════════════════════════════════════════════════════════════════════
-- V5 §197 · OWNER DECISION Q11 — monthly subscription churn, event-based
--
-- THE RULING, VERBATIM: *"Option B — Subscription churn, event-based. Define monthly
-- subscription churn as: subscriptions canceled during the month ÷ active subscriptions at
-- the beginning of the month."* With: do not manufacture historical churn; do not infer
-- cancellation dates from unrelated fields; implement the minimum authoritative data
-- contract to record FUTURE cancellation events, including an appropriate cancellation
-- timestamp and authorized writer path; preserve existing data and do not backfill; render
-- the A11 insufficient-history state rather than a misleading 0%; no plan-level churn until
-- Q13; and Q1/Q2 ambiguity must not alter this subscription-based definition.
--
-- ── 1 · THE COLUMN, AND WHY NOTHING IS BACKFILLED ──────────────────────────
--
-- Before this migration the schema carried NO subscription end-date at all: 022's table has
-- `status`, `current_period_end` and `cancel_at_period_end`, and the only cancellation
-- timestamp anywhere in 180 migrations was `coach_client_relationships.cancelled_at`
-- (025:19). So a cancellation could be observed as a STATE and never as an EVENT.
--
-- `canceled_at` is added NULLABLE with no DEFAULT and no UPDATE statement. Every one of the
-- 173 existing QA subscriptions keeps a null, and that null is the truthful answer: those
-- rows are all `status = 'active'`, so none of them has a cancellation date to record, and
-- for any that later did there is no authoritative source for WHEN. Deriving one from
-- `updated_at` or `current_period_end` is exactly the inference the ruling forbids —
-- `updated_at` moves on any write and a period end is a billing boundary, not a departure.
--
-- SPELLING: `canceled_at`, one L, matching Stripe's own field and this table's existing
-- `status = 'canceled'` value written by the webhook. `coach_client_relationships` uses
-- `cancelled_at` with two. The inconsistency is pre-existing and is NOT renamed here: a
-- rename is a contract change to a column 172 and 179 already read.
--
-- ── 2 · THE AUTHORIZED WRITER IS THE ONE THAT ALREADY EXISTS ───────────────
--
-- No trigger, and no new RPC. `stripe-webhook` already handles
-- `customer.subscription.deleted` and already writes `status = 'canceled'` on that event —
-- it IS the system-of-record path, and Stripe's own `canceled_at` is the authoritative
-- moment. A trigger inferring `now()` from a status transition would record when WE noticed
-- rather than when the cancellation happened, and would fire for backfills and repairs too.
-- The webhook sets the column in the same update that sets the status; see
-- `supabase/functions/stripe-webhook/index.ts`.
--
-- ── 3 · THE DENOMINATOR, AND THE ONE IMPRECISION IT CANNOT AVOID ───────────
--
-- "Active at the beginning of the month" is computed from the two AUTHORITATIVE timestamps
-- only: a subscription counts when it was `created_at` before the month began and was not
-- yet canceled then (`canceled_at IS NULL OR canceled_at >= month_start`).
--
-- IT DOES NOT CONSULT `status`, and that is deliberate rather than careless. `status` is a
-- CURRENT value with no history, so applying it to a past instant would assert that a row
-- which is `past_due` today was `past_due` a month ago. A subscription that never activated
-- is therefore counted in the denominator; the alternative is to infer a historical state
-- from a present field, which is the same class of error the ruling forbids for dates.
-- `churn_denominator_basis` names the basis on the surface so no reader has to guess.
--
-- ── 4 · INSUFFICIENT HISTORY IS NOT 0% ─────────────────────────────────────
--
-- `churn_rate_pct` is NULL until at least one cancellation has EVER been recorded. Before
-- that the measure cannot distinguish "nobody left" from "we were not recording
-- departures", and 0% would assert the first while the second is true. After the first
-- recorded cancellation the mechanism is proven live, and a month with no cancellations is
-- a REAL zero. `churn_first_cancellation_at` publishes how much history exists — the
-- earliest recorded cancellation, which is a fact and not an estimate.
--
-- Q1/Q2 DO NOT REACH THIS. The month boundary is `date_trunc('month', now())` in the
-- database's timezone, the same basis 172/176/179 already use, and the population is
-- SUBSCRIPTIONS — so neither the "today" timezone question (Q1) nor the active-user
-- definition (Q2) can alter it. Migration 176's published window columns remain the
-- disclosure for the activity figures, which is a different card.
--
-- NO PLAN-LEVEL BREAKDOWN. Q13 is unresolved: `subscriptions.kind` carries `'app'` on all
-- 173 QA rows while 022:17-19 documents `'coach' | 'self_guided' | 'ai_guided'`, and there
-- is no CHECK. A per-plan churn split would have to pick which of those is authoritative,
-- which is the owner's. No `kind` appears below.
--
-- Additive: one nullable column, and columns appended to an existing gated view. No grant,
-- policy, CHECK, NOT NULL, trigger or backfill.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS canceled_at timestamptz;

COMMENT ON COLUMN public.subscriptions.canceled_at IS
  'V5 §197 · owner decision Q11. The moment a subscription was canceled, as reported by '
  'Stripe''s own canceled_at on customer.subscription.deleted. NULL means no cancellation '
  'is recorded for this row — never that one did not happen before this column existed. '
  'Deliberately NOT backfilled: no authoritative historical source exists, and deriving a '
  'date from updated_at or current_period_end is the inference the ruling forbids.';

-- ── the Dashboard figure, on the existing Monetization-gated surface ───────
--
-- 178's view body is reproduced EXACTLY and the Q11 columns appended. CREATE OR REPLACE
-- VIEW can only add columns at the end, so the preceding 23 must be byte-identical or the
-- replace fails -- and D15 pins the full set, which is what caught 179's drift.
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
      AND (coach_payout IS NULL OR platform_fee IS NULL))                      AS payout_missing,

  -- ══ OWNER DECISION Q11 · monthly subscription churn, event-based ═════════
  -- Numerator: cancellations RECORDED within the current month. A row whose
  -- canceled_at is null contributes nothing — it is not assumed to be a departure.
  (SELECT count(*) FROM public.subscriptions s
    WHERE s.canceled_at >= date_trunc('month', now())
      AND s.canceled_at <  date_trunc('month', now()) + interval '1 month')     AS churn_cancellations_month,
  -- Denominator: existed before the month began and was not yet canceled then.
  -- Computed from the two AUTHORITATIVE timestamps only; see the header on why
  -- `status` is deliberately not consulted for a past instant.
  (SELECT count(*) FROM public.subscriptions s
    WHERE s.created_at < date_trunc('month', now())
      AND (s.canceled_at IS NULL
           OR s.canceled_at >= date_trunc('month', now())))                     AS churn_active_at_month_start,
  -- NULL until any cancellation has EVER been recorded: before that, 0% would assert
  -- "nobody left" when the truth is "departures were not being recorded".
  (CASE
     WHEN (SELECT count(*) FROM public.subscriptions WHERE canceled_at IS NOT NULL) = 0
       THEN NULL
     ELSE round(
       (SELECT count(*) FROM public.subscriptions s
         WHERE s.canceled_at >= date_trunc('month', now())
           AND s.canceled_at <  date_trunc('month', now()) + interval '1 month')::numeric
       / NULLIF((SELECT count(*) FROM public.subscriptions s
                  WHERE s.created_at < date_trunc('month', now())
                    AND (s.canceled_at IS NULL
                         OR s.canceled_at >= date_trunc('month', now()))), 0) * 100, 1)
   END)                                                                         AS churn_rate_pct,
  -- How much history exists, as a recorded fact rather than an estimate.
  (SELECT min(canceled_at) FROM public.subscriptions
    WHERE canceled_at IS NOT NULL)                                             AS churn_first_cancellation_at,
  -- Discloses the denominator's basis where it is READ, not only where it is written.
  'existed before the month began and not yet canceled'::text                  AS churn_denominator_basis

 WHERE public.admin_can('Monetization', 'view');

COMMENT ON VIEW public.admin_revenue_overview IS
  'V5 §197 · 178''s recorded revenue decomposition plus owner decision Q11 — monthly '
  'subscription churn, event-based: cancellations RECORDED within the month over '
  'subscriptions that existed before it began and were not yet canceled. The rate is NULL '
  'until any cancellation has ever been recorded, because 0%% would otherwise assert that '
  'nobody left when the truth is that departures were not being recorded. '
  'churn_denominator_basis discloses that the denominator does not consult `status`, which '
  'has no history. No plan-level split: Q13 is unresolved. '
  'Gated admin_can(''Monetization'',''view'').';

REVOKE ALL ON public.admin_revenue_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_revenue_overview TO authenticated;
