-- Migration 198. Session credits are not writable by a coach, and a balance stays
-- in range. (K-25; Release Gate 4.8.)
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["198"]. Independent of 182-186 and 193-197.
--
-- THE DEFECT (K-25)
--   client_session_credits "coach updates client credits" is FOR UPDATE with
--   `coach_id = auth.uid()` as both USING and WITH CHECK. Every other column is
--   the coach's to rewrite: sessions_total (mint sessions), sessions_used (reset
--   a consumed block), client_id (move a paid block to a different client),
--   package_id, payment_id. Release Gate 4.8 requires the opposite: "a coach
--   cannot rewrite a credit balance or its owner". Nor is there any range check:
--   sessions_used could be negative or exceed sessions_total.
--
-- WHY THIS TAKES NOTHING THE PRODUCT USES
--   The app only READS credits (CoachRevenueService). The only writer is the
--   Stripe webhook's grant, which runs as service_role and is not subject to RLS.
--   No screen or function updates a credit row as a coach.
--
-- THE CHANGE
--   1. Drop the coach UPDATE policy. Clients and coaches keep their SELECT
--      policies; nobody but the server writes credits.
--   2. CHECK sessions_total >= 0 AND sessions_used BETWEEN 0 AND sessions_total.
--      Added NOT VALID: enforced on every new or changed row at once; existing
--      rows (QA has none) are validated separately so a bad historical row in an
--      environment this has not seen cannot block the apply.
--
-- NOT DECIDED HERE (owner decision 5, prepared in the ledger): which bookings
--   consume a credit. Consumption -- an atomic book-and-consume RPC under a row
--   lock, refused at zero -- is designed but not implemented, because it encodes
--   that policy. Until then nothing consumes credits (K-05 stays open).
--
-- Reversible: recreate the policy as in migration 028; DROP CONSTRAINT.

BEGIN;

DROP POLICY IF EXISTS "coach updates client credits" ON public.client_session_credits;

ALTER TABLE public.client_session_credits
  DROP CONSTRAINT IF EXISTS client_session_credits_balance_in_range;
ALTER TABLE public.client_session_credits
  ADD CONSTRAINT client_session_credits_balance_in_range
  CHECK (sessions_total >= 0 AND sessions_used >= 0 AND sessions_used <= sessions_total)
  NOT VALID;

COMMIT;
