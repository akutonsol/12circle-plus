-- 131_identity_constraints.sql
--
-- Wave 3A / task 3A-11.  CRC-06 — "an identity model that lives in
-- application convention (check-then-insert) instead of in a UNIQUE index."
--
-- Migration number assigned by docs/MASTER_REMEDIATION_WAVES.md section 0.2
-- (row 131).  Scope ruled by the owner 2026-09-09 (R-01/R-02), recorded in
-- docs/WAVE_3A_11_RULING_VALIDATION.md section 12: 3A-11 is the four identity
-- constraints PLUS the writer hardening the Workstream I fixes name, on the
-- basis of (a) the 3A-10 precedent for task-scoped cross-layer remediation and
-- (b) each Workstream I fix being a single fix in two parts.
--
-- ===========================================================================
-- THE FOUR FINDINGS
-- ===========================================================================
--
--   I-NUT-04  P1  client_nutrition_plans has no uniqueness on the active plan.
--                 Two active rows make every reader's .maybeSingle() return
--                 PostgREST 406, which every caller turns into "no plan" and
--                 silently reverts the client to hard-coded default macros.
--                 (QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md:337)
--
--   I-WMH-01  P2  cycle_logs has no uniqueness and no ordering constraint.
--                 A double tap inserts two periods for one day, and
--                 endCurrentPeriod() closes only the most recent open one, so
--                 a duplicate leaves an older period open forever and every
--                 cycle-length calculation runs over a corrupted series.
--                 (:422)
--
--   I-NOT-05  P2  conversations has no unique constraint on the participant
--                 pair, and two independent check-then-insert paths create it.
--                 Message history silently splits across two threads.  (:613)
--
--   I-PAY-01  P1  client_session_credits has no unique constraint on
--                 payment_id, and the Stripe webhook grants credits with a
--                 bare insert.  Stripe delivers at least once, so a redelivery
--                 grants the sessions again.  This is money.  (:448)
--                 ** CONSTRAINT HALF ONLY -- see the note at the end. **
--
-- ===========================================================================
-- DELIBERATELY NOT IN THIS MIGRATION
-- ===========================================================================
--
--   * The cycle_logs EXCLUSION constraint on overlapping [start_date,end_date]
--     ranges.  Workstream I conditions it on a dedupe pass, and "overlapping
--     periods" has no product definition.  DEFERRED by the 2026-09-09 ruling.
--   * I-NUT-03 (ai_adjust_nutrition overwriting a coach's prescription in
--     place).  Different defect, real product decision, not parallelizable.
--     DEFERRED.
--   * Any RLS policy change.  This migration adds no policy, revokes nothing
--     and grants nothing except EXECUTE on its two new functions.
--
-- ===========================================================================
-- DATA COMPATIBILITY -- checked against live QA before authoring
-- ===========================================================================
--
-- Read-only counts taken 2026-09-09 against QA eyqtldjqpgpljlqvpowh:
--
--   clients with more than one active nutrition plan ....... 0   (2 rows total)
--   duplicate (user_id, start_date) in cycle_logs .......... 0   (0 rows total)
--   cycle_logs rows with end_date < start_date ............. 0
--   duplicate conversation participant pairs .............. 0   (1 row total)
--   conversations rows with a NULL participant ............. 0
--   duplicate non-null payment_id in session credits ...... 0   (0 rows total)
--
-- Every constraint below therefore applies to QA with NO dedupe pass, which
-- is why the CHECK is added VALID rather than NOT VALID: I-MIG-02 already
-- records that both ALTER-added CHECKs in this tree are NOT VALID and were
-- never validated, and this file does not add a third.
--
-- PRODUCTION IS A DIFFERENT QUESTION AND IS NOT ADDRESSED HERE.  Production's
-- ledger has never been reconciled (REL-21, registry section 9 exposure 2), its
-- data is unreadable to this programme, and a production rollout must run its
-- own dedupe pass before this migration.  Out of scope.
--
-- IDEMPOTENT AND REPLAY-SAFE.  Every index is CREATE ... IF NOT EXISTS, the
-- CHECK is guarded on pg_constraint, and both functions are CREATE OR REPLACE.
--
-- NO ENVIRONMENT WAS CONTACTED IN AUTHORING THIS FILE beyond the read-only
-- counts above.  It has not been applied anywhere.  Application to QA is a
-- separately authorized step with its own pre-application state check.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. I-NUT-04 -- at most one active nutrition plan per client.
--
-- Partial, because the contract is "one ACTIVE plan", not "one plan": the
-- table keeps superseded rows as history.  is_active is a nullable boolean, so
-- `WHERE is_active` indexes only rows that are explicitly true -- which is
-- exactly the set every reader selects with .eq('is_active', true).
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS client_nutrition_plans_one_active_per_client
  ON public.client_nutrition_plans (client_id)
  WHERE is_active;

COMMENT ON INDEX public.client_nutrition_plans_one_active_per_client IS
  'I-NUT-04: at most one active plan per client. Without it two active rows '
  'make every reader''s maybeSingle() return 406, which callers turn into '
  '"no plan" and silently substitute default macros.';

-- ---------------------------------------------------------------------------
-- 2. I-WMH-01 -- one period per start date, and a period cannot end before it
--    begins.
--
-- user_id and start_date are both NOT NULL, so a plain unique index needs no
-- partial predicate.  cycle_symptoms already carries UNIQUE (user_id, log_date)
-- and cycle_settings a PRIMARY KEY (user_id): two of the three tables in this
-- module were given an identity model and this one was not.
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS cycle_logs_one_period_per_start
  ON public.cycle_logs (user_id, start_date);

COMMENT ON INDEX public.cycle_logs_one_period_per_start IS
  'I-WMH-01: one period per start date. A double tap previously inserted two, '
  'and endCurrentPeriod() closes only the most recent open period, so the '
  'duplicate stayed open forever and corrupted every cycle-length figure.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.cycle_logs'::regclass
       AND conname  = 'cycle_logs_end_on_or_after_start'
  ) THEN
    ALTER TABLE public.cycle_logs
      ADD CONSTRAINT cycle_logs_end_on_or_after_start
      CHECK (end_date IS NULL OR end_date >= start_date);
  END IF;
END
$$;

COMMENT ON CONSTRAINT cycle_logs_end_on_or_after_start ON public.cycle_logs IS
  'I-WMH-01: a period cannot end before it starts. Added VALID -- QA carries '
  'zero violating rows. A production rollout must dedupe and repair first.';

-- ---------------------------------------------------------------------------
-- 3. I-NOT-05 -- one conversation per participant pair.
--
-- The pair is UNORDERED -- getOrCreateConversationWith() and
-- getOrCreateCoachClientConversation() each write whichever participant is the
-- caller into participant_1 -- which is why an index was never obvious.
-- least()/greatest() normalise the pair so (A,B) and (B,A) collide.
--
-- NULL semantics, stated because they are not obvious: least()/greatest()
-- IGNORE nulls, so a row with participant_2 NULL indexes as (p1, p1). QA holds
-- zero such rows. This follows Workstream I's recommended definition exactly
-- rather than adding a partial predicate the requirement does not ask for.
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS conversations_unique_participant_pair
  ON public.conversations (
    least(participant_1, participant_2),
    greatest(participant_1, participant_2)
  );

COMMENT ON INDEX public.conversations_unique_participant_pair IS
  'I-NOT-05: one conversation per unordered participant pair. Two '
  'check-then-insert paths could each create a thread for one pair, splitting '
  'message history in half with no error anywhere.';

-- ---------------------------------------------------------------------------
-- 4. I-PAY-01 (constraint half) -- one credit grant per payment.
--
-- Stripe retries every non-2xx, so this index is the arbiter the handler never
-- had: every other write in that handler already has a conflict target and
-- only the credit grant was a bare insert.
--
-- DELIBERATE DEVIATION FROM THE SOURCE CARD, stated because it is a departure.
-- QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md:448 recommends "a partial unique
-- index WHERE payment_id IS NOT NULL" in the same sentence as "change the
-- insert to upsert ... onConflict: 'payment_id'".  Those two halves are in
-- tension: PostgREST's on_conflict takes column names only and cannot carry an
-- index predicate, so Postgres cannot INFER a PARTIAL index from
-- `ON CONFLICT (payment_id)` and the recommended upsert would fail with
-- "there is no unique or exclusion constraint matching the ON CONFLICT
-- specification".
--
-- A PLAIN unique index gives identical semantics and is inferrable.  Postgres
-- treats NULLs as DISTINCT in a unique index by default, so a nullable column
-- already admits unlimited NULL rows -- a manually granted block that carries
-- no payment stays insertable, exactly as the partial predicate intended.
-- The card's stated CONTRACT ("one checkout.session.completed grants one
-- credit block") is preserved in full; only the mechanism differs, and it
-- differs so that the card's own recommended upsert can work.
-- ---------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS client_session_credits_unique_payment
  ON public.client_session_credits (payment_id);

COMMENT ON INDEX public.client_session_credits_unique_payment IS
  'I-PAY-01: one session-credit grant per payment. Stripe delivers webhooks '
  'at least once; every other write in the handler was already idempotent and '
  'only the credit grant was a bare insert.';

-- ---------------------------------------------------------------------------
-- 5. I-NUT-04, writer half -- assign a nutrition plan atomically.
--
-- The client previously ran two independent statements (deactivate, then
-- insert) with no transaction between them, so a failure between them left the
-- client with NO active plan and silently on default macros.  One function
-- body is one transaction, which is the whole point.
--
-- AUTHORIZATION, and the reasoning is deliberate: this reproduces the EXISTING
-- policy exactly and does not tighten it.  "coach client nutrition" on
-- client_nutrition_plans is `FOR ALL USING (coach_id = auth.uid() OR
-- client_id = auth.uid())`.  The write arm a coach uses is `coach_id =
-- auth.uid()`, and this function satisfies it by CONSTRUCTION: coach_id is
-- taken from auth.uid() and is not a parameter, so no caller can attribute a
-- plan to another coach.
--
-- It deliberately does NOT require is_active_coach_of(p_client_id).  That
-- would be STRICTER than the policy it replaces and would break a coach
-- assigning a plan before the relationship row reaches 'active'.  3A-11 is an
-- identity/atomicity task and is not authorized to change who may write.
-- The looseness of the underlying policy is recorded as an observation in
-- docs/WAVE_3A_11_EXECUTION_EVIDENCE.md, not fixed here.
--
-- SECURITY DEFINER because it must write both statements as one unit under a
-- pinned search_path; STABLE is wrong (it writes), so VOLATILE.
-- Gate 0.14 / migration 122: pinned search_path, revoked from PUBLIC and anon,
-- granted only to authenticated.  No dynamic SQL anywhere.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.assign_nutrition_plan(
  p_client_id       uuid,
  p_calories_target integer,
  p_protein_g       integer,
  p_carbs_g         integer,
  p_fat_g           integer,
  p_water_target_oz integer DEFAULT NULL,
  p_notes           text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_coach uuid := (SELECT auth.uid());
  v_id    uuid;
BEGIN
  IF v_coach IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'p_client_id is required' USING ERRCODE = '22004';
  END IF;

  -- Supersede, then insert. Both in one transaction: the partial unique index
  -- added above makes any interleaving impossible rather than merely unlikely.
  UPDATE public.client_nutrition_plans
     SET is_active = false
   WHERE client_id = p_client_id
     AND is_active;

  INSERT INTO public.client_nutrition_plans (
    client_id, coach_id, calories_target, protein_g, carbs_g, fat_g,
    water_target_oz, notes, is_active
  )
  VALUES (
    p_client_id, v_coach, p_calories_target, p_protein_g, p_carbs_g, p_fat_g,
    p_water_target_oz, p_notes, true
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) TO authenticated;

COMMENT ON FUNCTION public.assign_nutrition_plan(
  uuid, integer, integer, integer, integer, integer, text) IS
  'I-NUT-04 writer half: supersede the client''s active nutrition plan and '
  'insert the new one in ONE transaction. coach_id is taken from auth.uid() '
  'and is not a parameter, which reproduces the "coach client nutrition" '
  'policy''s coach_id = auth.uid() arm by construction. Deliberately not '
  'stricter than that policy -- 3A-11 does not change who may write.';

-- ---------------------------------------------------------------------------
-- 6. I-NOT-05, writer half -- get or create a conversation atomically.
--
-- Replaces two independent check-then-insert paths.  The INSERT ... ON
-- CONFLICT DO NOTHING against the pair index is the arbiter: under a race the
-- loser inserts nothing and reads the winner's row, so both callers get the
-- same conversation id and history cannot split.
--
-- AUTHORIZATION: participant_1 is auth.uid() and is not a parameter, so a
-- caller can only ever create a conversation they are in -- exactly what
-- "participants can insert conversations" (WITH CHECK participant_1 =
-- auth.uid() OR participant_2 = auth.uid()) permits.  The lookup is scoped to
-- the caller's own pair, so this function cannot read a conversation the
-- caller is not part of, matching "participants can read conversations".
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_or_create_conversation(other_user uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_me uuid := (SELECT auth.uid());
  v_id uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;
  IF other_user IS NULL THEN
    RAISE EXCEPTION 'other_user is required' USING ERRCODE = '22004';
  END IF;
  IF other_user = v_me THEN
    RAISE EXCEPTION 'cannot open a conversation with yourself'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.conversations (participant_1, participant_2, last_message_at)
  VALUES (v_me, other_user, now())
  ON CONFLICT (
    least(participant_1, participant_2),
    greatest(participant_1, participant_2)
  ) DO NOTHING
  RETURNING id INTO v_id;

  -- DO NOTHING returns no row when the pair already exists (or when a
  -- concurrent caller won the race). Read the existing row by the same
  -- normalised pair the index uses.
  IF v_id IS NULL THEN
    SELECT c.id INTO v_id
      FROM public.conversations c
     WHERE least(c.participant_1, c.participant_2)    = least(v_me, other_user)
       AND greatest(c.participant_1, c.participant_2) = greatest(v_me, other_user);
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_or_create_conversation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_conversation(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_or_create_conversation(uuid) IS
  'I-NOT-05 writer half: race-free get-or-create for the caller''s '
  'conversation with other_user. participant_1 is auth.uid() and is not a '
  'parameter, so a caller can only create a conversation they are in. '
  'Replaces two independent check-then-insert paths in messaging_service.dart.';

COMMIT;

-- ---------------------------------------------------------------------------
-- I-PAY-01: THE CONSTRAINT HALF ONLY.
--
-- The webhook's insert -> upsert change ships with this task in
-- supabase/functions/stripe-webhook/index.ts, and the two MUST land together:
-- the index without the upsert would make a Stripe redelivery raise 23505,
-- which the handler returns as HTTP 500, which Stripe retries -- turning a
-- silent duplicate grant into a permanently failing webhook endpoint.
--
-- I-PAY-01 nevertheless reaches REMEDIATED and NOT VERIFIED_CLOSED in this
-- task.  Its closure class is Billing / entitlement, whose ladder requires
-- VERIFIED LIVE against Stripe TEST MODE and VERIFIED END-TO-END for anything
-- that moves money.  P-8 records that no QA Stripe test-mode credentials,
-- runbook or price ids exist.  Terminal closure travels to Wave 6 with K-01.
-- ---------------------------------------------------------------------------
