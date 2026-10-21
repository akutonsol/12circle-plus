-- 111_replay_corrections.sql
--
-- Forward corrective migration for the Stage B.2 replay-audit findings.
--
-- The rule applied throughout: a defect that ABORTS the replay has to be
-- neutralised where it occurs (a later migration never runs if an earlier one
-- halts), but the CORRECT end state is asserted here, forward-only, so no
-- historical migration is silently rewritten. Each earlier file now carries a
-- comment pointing at this one.
--
--   B2-3  003 created RLS policies on nutrition_logs (created by 006) and
--         notifications (created by 004). Guarded in 003; re-asserted below.
--   B2-4  009 read user_profiles.is_accepting_clients (added by 010). Guarded in
--         009. It is a one-time repair of legacy 'pending' rows, so a freshly
--         built database has nothing to repair and nothing is needed here.
--   B2-5  096 indexed communications(created_at); the column is generated_at.
--         Inert in 096; the correct index is created below.
--   B2-6  NOT handled here. 076's ai_cron_generate() selected from
--         workout_sessions.created_at, which no migration ever creates. That is
--         corrected IN PLACE in 076 instead, so the function body has exactly one
--         definition in the tree. A byte-identical CREATE OR REPLACE here would be
--         a second copy of the same body to keep in sync -- the drift risk is worse
--         than the redundancy is worth.
--
--         Consequence to be aware of: an environment that already applied the OLD
--         076 does not pick the fix up by replaying, because 076 will not re-run
--         there. QA is being rebuilt from empty, so it gets the corrected body.
--         Any other environment needs the corrected function applied explicitly as
--         part of its own rollout -- see the Stage B.3 report.
--
-- Everything here is idempotent and safe to replay.

-- ---------------------------------------------------------------------------
-- B2-3 — the seven RLS policies migration 003 could not create.
--
-- Identical in effect to what 003 intended. Both tables now exist (004, 006).
-- Note these are the ORIGINAL 003 definitions, including the over-permissive
-- `USING (true)` coach-read policies -- migration 100 is what tightens those to
-- is_active_coach_of(), and it runs before this file, so re-creating the loose
-- version here would REOPEN the hole 100 closed. The coach-read policies are
-- therefore asserted in their post-100 form.
-- ---------------------------------------------------------------------------

ALTER TABLE public.nutrition_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own nutrition logs" ON public.nutrition_logs;
CREATE POLICY "users manage own nutrition logs"
  ON public.nutrition_logs FOR ALL TO authenticated
  USING (user_id = auth.uid());

-- post-100 form, NOT 003's USING (true)
DROP POLICY IF EXISTS "coaches read client nutrition logs" ON public.nutrition_logs;
CREATE POLICY "coaches read client nutrition logs"
  ON public.nutrition_logs FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_active_coach_of(user_id));

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "recipients read own notifications" ON public.notifications;
CREATE POLICY "recipients read own notifications"
  ON public.notifications FOR SELECT TO authenticated
  USING (recipient_id = auth.uid());

DROP POLICY IF EXISTS "system can insert notifications" ON public.notifications;
CREATE POLICY "system can insert notifications"
  ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "recipients update own notifications" ON public.notifications;
CREATE POLICY "recipients update own notifications"
  ON public.notifications FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid());

-- ---------------------------------------------------------------------------
-- B2-5 — the communications index, on the column that exists.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_comm_subject
  ON public.communications (subject_id, generated_at DESC);
