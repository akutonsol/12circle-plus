-- Migration 185. The coach write arms on six tables require an ACTIVE relationship.
--
-- QAX-SEC-03 (P1) and the policy half of F-21 · decision OD-14.
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["185"]; environments.qa.applied_through is "181".
--
-- THE DEFECT. Six tables carry a policy whose coach arm is `coach_id = auth.uid()`
-- and nothing more. coach_id is a column the CALLER writes, so any authenticated
-- user can satisfy it by naming themselves as coach and ANYONE as client. The
-- victim sees the row, gets the notification, and a plan or programme can be
-- hijacked or blanked. Reproduced on the local replay (bare run of
-- supabase/tests/qa_exhaustion/run.sh: six FAILs, one per table).
--
-- THE DECISION. OD-14 is answered in docs/V5_DELEGATED_DETERMINATIONS_2026-10-21.md
-- section 4.2. The determination was made by Claude under the product owner's
-- written delegation and AUTHORIZED FOR IMPLEMENTATION by the owner in chat on
-- 2026-10-21 (ledger: .skills-agent/decisions.json). In short:
--   * every client-naming WRITE on these tables requires an ACTIVE relationship
--     (public.is_active_coach_of(client_id), migration 100);
--   * a client keeps full access to rows that name them (client_id = auth.uid());
--   * coach_video_responses is in scope;
--   * QAX-SEC-03 is built to this stricter contract, so the registry-vs-ledger
--     dispute about its `Owner?` cell (B-04) need not be settled to proceed;
--   * EXISTING rows that would not be writable under the new policy are
--     PRESERVED, NOT MUTATED, and stay READABLE by the coach who authored them and
--     by the client they name -- they simply cannot be changed or re-created by a
--     coach without an active relationship. That is why each altered FOR ALL
--     policy is paired with a narrow SELECT policy for the authoring coach below:
--     tightening the FOR ALL policy alone would also have removed that read.
--
-- READ-ONLY AUDIT of rows that fail the new write test (run only in an
-- owner-approved QA window; the reviewer is the platform admin role). Nothing in
-- this migration runs it, deletes or rewrites any row:
--
--   SELECT 'client_habits' AS t, count(*) FROM public.client_habits h
--    WHERE h.coach_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM
--          public.coach_client_relationships r WHERE r.coach_id = h.coach_id
--          AND r.client_id = h.client_id AND r.status = 'active');
--   -- ...the same shape for action_items, coaching_calls, coach_video_responses,
--   -- client_nutrition_plans and workout_program_assignments.
--
-- NOT CHANGED, STATED SO IT IS NOT ASSUMED:
--   * public.workout_programs "coaches manage programs" (001) -- the policy F-21
--     was first proven on -- is NOT altered. Requiring is_coach_profile() there
--     could break self-guided users who create their own programmes with
--     coach_id = themselves, and that flow was not verified. F-21 therefore
--     stays OPEN.
--   * A client can still write a row naming an arbitrary coach_id on the
--     client_id = auth.uid() arm. That attributes content to a coach rather than
--     reaching a victim client; it is a different defect and is not addressed.
--   * SECURITY DEFINER functions that write these tables bypass RLS and are not
--     touched here.
--
-- ALTER POLICY, not DROP/CREATE: it changes the predicate in place, keeps the
-- policy's name, roles and command, and cannot leave a window with no policy. On
-- a FOR ALL policy, WITH CHECK defaults to USING, so USING alone is restated.

BEGIN;

-- 1. client_habits ----------------------------------------------------------
ALTER POLICY "coach client habits" ON public.client_habits
  USING (client_id = auth.uid()
         OR (coach_id = auth.uid() AND public.is_active_coach_of(client_id)));

CREATE POLICY "authoring coach reads own client habits"
  ON public.client_habits FOR SELECT TO authenticated
  USING (coach_id = auth.uid());

-- 2. action_items -----------------------------------------------------------
-- The existing SELECT policy "client reads own action items" already admits
-- coach_id = auth.uid() for reads, so no companion SELECT policy is needed.
ALTER POLICY "coach manages assigned action items" ON public.action_items
  USING (coach_id = auth.uid() AND public.is_active_coach_of(client_id));

-- 3. coaching_calls -- BOTH policies, which are equivalent FOR ALL policies ---
ALTER POLICY "Coach and client can see calls" ON public.coaching_calls
  USING (client_id = auth.uid()
         OR (coach_id = auth.uid() AND public.is_active_coach_of(client_id)));

ALTER POLICY "calls_participant_access" ON public.coaching_calls
  USING (client_id = auth.uid()
         OR (coach_id = auth.uid() AND public.is_active_coach_of(client_id)));

CREATE POLICY "authoring coach reads own coaching calls"
  ON public.coaching_calls FOR SELECT TO authenticated
  USING (coach_id = auth.uid());

-- 4. coach_video_responses (in scope per OD-14 / B-09) ------------------------
-- INSERT-only policy: restate WITH CHECK. The SELECT policy already admits the
-- authoring coach, so reads are unchanged.
ALTER POLICY "Coach can insert video responses" ON public.coach_video_responses
  WITH CHECK (coach_id = auth.uid() AND public.is_active_coach_of(client_id));

-- 5. client_nutrition_plans ---------------------------------------------------
ALTER POLICY "coach client nutrition" ON public.client_nutrition_plans
  USING (client_id = auth.uid()
         OR (coach_id = auth.uid() AND public.is_active_coach_of(client_id)));

CREATE POLICY "authoring coach reads own client nutrition plans"
  ON public.client_nutrition_plans FOR SELECT TO authenticated
  USING (coach_id = auth.uid());

-- 6. workout_program_assignments ----------------------------------------------
ALTER POLICY "coaches manage assignments" ON public.workout_program_assignments
  USING (client_id = auth.uid()
         OR (coach_id = auth.uid() AND public.is_active_coach_of(client_id)));

CREATE POLICY "authoring coach reads own program assignments"
  ON public.workout_program_assignments FOR SELECT TO authenticated
  USING (coach_id = auth.uid());

COMMIT;
