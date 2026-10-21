-- =============================================================================
-- SEC-PHI-9 — a coach keeps access to a client's PROGRESS PHOTOGRAPHS after the
--              coaching relationship ends.
--
-- STATUS: **PROPOSAL. AUTHORED, UNNUMBERED, NOT APPLIED.**
--
-- docs/MASTER_REMEDIATION_WAVES.md reserves migration numbers **132+**,
-- "assigned at wave entry, never before". This file carries no number and must
-- not be applied as-is.
--
-- Authored by the security/QA workstream (AG-01). Requires AG-02 review.
-- =============================================================================
--
-- SEVERITY: HIGH. Progress photographs are body images. Access survives
-- termination indefinitely, and the relationship row is never deleted — it is
-- set to `cancelled` — so nothing ever revokes it.
--
-- LIVE EVIDENCE (QA `eyqtldjqpgpljlqvpowh`, 2026-09-24)
-- -----------------------------------------------------
-- A throwaway object was uploaded by the owner, probed, and removed. Net state
-- change: none.
--
--   owner    signs the object  -> 200  SIGNED
--   attacker signs the object  -> 400  not_found      (denied)
--   COACH    signs the object  -> 200  SIGNED         <-- the finding
--   admin    signs the object  -> 400  not_found      (denied)
--   anon     public route      -> 400  Bucket not found  (bucket IS private)
--   attacker DELETE            -> 400  Unauthorized
--   owner    DELETE            -> 200  deleted; object verified gone
--
-- **The coach fixture's relationship with that client has status
-- `cancelled`** — confirmed by reading `coach_client_relationships` as both
-- parties. The same identity is correctly DENIED that client's profile,
-- PAR-Q, weekly check-ins, weight logs, body measurements, AI memories and AI
-- profile. Revocation works everywhere except this bucket.
--
-- ROOT CAUSE
-- ----------
-- `029_progress_photos_storage_rls.sql:36`:
--
--     CREATE POLICY "coach reads client progress photos"
--       ON storage.objects FOR SELECT TO authenticated
--       USING (
--         bucket_id = 'progress-photos'
--         AND EXISTS (
--           SELECT 1 FROM coach_client_relationships r
--           WHERE r.coach_id = auth.uid()
--             AND r.client_id::text = (storage.foldername(name))[1]
--         )
--       );
--
-- It tests only that a relationship ROW EXISTS. There is no status predicate,
-- so `pending`, `declined`, `cancelled` and any future status all satisfy it.
--
-- Migration 029 predates the 100-series hardening. `public.is_active_coach_of`
-- (migration 100) exists precisely to express this check once, and requires
-- `r.status = 'active'`. It is referenced **30 times** across table policies.
-- This is the **only** storage policy that joins `coach_client_relationships`,
-- and the only one that does not check status — a single isolated omission,
-- not a pattern.
--
-- =============================================================================
-- ADDENDUM 2026-09-27 — THE EXPOSURE NEEDS NO PRIOR RELATIONSHIP AT ALL
-- =============================================================================
--
-- This file originally recorded two exposures: a FORMER coach (demonstrated
-- live) and a PENDING coach (inferred). Reconciling against the Cloud
-- workstream's QAX-SEC-02 ("self-made or former coach") and then tracing the
-- write path gives a sharper and worse statement, with the mechanism named:
--
--   1. `role = 'coach'` is SELF-SELECTABLE AT SIGNUP. Migration 115's
--      `enforce_profile_privilege` blocks role CHANGES — verified live, a
--      client's own PATCH of `role` returns 42501 — but its INSERT branch
--      explicitly permits it: "Self-service coach / vendor registration
--      survives". So anyone may register AS a coach.
--
--   2. A self-made coach may create a relationship to ANY client.
--      `113:271 "relationship parties create"` permits
--      `coach_id = auth.uid() AND initiated_by = 'coach' AND status = 'pending'`.
--      It checks `is_coach_profile(coach_id)`, which (1) satisfies.
--
--   3. Escalating that row to 'active' IS blocked — 113's UPDATE WITH CHECK
--      plus `trg_relationship_integrity`. So `is_active_coach_of()` stays
--      false and every policy that uses it holds. **That part of the design
--      works.**
--
--   4. But THIS policy, and `score_events` (035:183), check only that a
--      relationship ROW EXISTS. `status = 'pending'` satisfies them.
--
-- Composed: **a stranger can sign up as a coach, request any client, and read
-- that client's progress photographs before the client has accepted, declined,
-- or been notified.** No prior relationship, no acceptance, no active status.
--
-- That is materially worse than the "former coach" case demonstrated live, and
-- it is confined to exactly the two policies this file corrects — because they
-- are the only two that omit the status predicate. The `is_active_coach_of`
-- population is unaffected, which is why adding the predicate here is the
-- whole fix for this arm rather than a partial mitigation.
--
-- Evidence class: the live former-coach denial/permission was reproduced
-- against QA. Steps 1–4 above are read from the migrations; the composed
-- self-made path was NOT executed here (it would require creating a coach
-- identity and a relationship row in a shared QA database). Cloud reports it
-- reproduced on a local migration replay (QAX-SEC-02, LR+MUT); note their
-- harness header states it "is NOT evidence about QA".
--
-- =============================================================================

-- TWO DISTINCT EXPOSURES CLOSED BY THE SAME PREDICATE
-- ---------------------------------------------------
--   1. FORMER coach  — `cancelled` — retains access. Demonstrated live.
--   2. PENDING coach — a coach the client has merely *requested*, who has not
--      accepted and may never accept, can read their progress photographs.
--      Not demonstrated (no pending fixture), but it follows from the same
--      missing predicate and is arguably the worse of the two.
--
-- =============================================================================

-- A SECOND POLICY WITH THE SAME ROOT CAUSE — SEC-PHI-10
-- -----------------------------------------------------
-- A sweep of every policy that joins `coach_client_relationships` WITHOUT the
-- helper found exactly five. Three check status; two do not:
--
--   * storage.objects  "coach reads client progress photos"   (029) — above
--   * score_events     "coach reads client events"            (035:183)
--
--       USING (EXISTS (SELECT 1 FROM coach_client_relationships r
--                      WHERE r.coach_id = auth.uid()
--                        AND r.client_id = score_events.user_id));
--
-- Same shape, same missing predicate, never narrowed by a later migration.
--
-- **Status difference in the evidence, which matters:** the progress-photo
-- exposure is VERIFIED live. `score_events` is **INCONCLUSIVE** — the QA
-- fixture client has 0 rows in `score_events`, `user_badges`, `daily_scores`
-- and `user_scores`, so a 0-row result there demonstrates nothing. The defect
-- is confirmed in source only. Do not record it as reproduced.

BEGIN;

DROP POLICY IF EXISTS "coach reads client progress photos" ON storage.objects;

CREATE POLICY "coach reads client progress photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'progress-photos'
    -- One definition of "is the active coach of", shared with the 30 table
    -- policies. Inlining the EXISTS again is what allowed the two to drift.
    AND public.is_active_coach_of( ((storage.foldername(name))[1])::uuid )
  );

-- SEC-PHI-10. No cast hazard here: `client_id` and `user_id` are both uuid, so
-- the helper can be called directly.
DROP POLICY IF EXISTS "coach reads client events" ON score_events;

CREATE POLICY "coach reads client events"
  ON score_events FOR SELECT TO authenticated
  USING (public.is_active_coach_of(score_events.user_id));

COMMIT;

-- =============================================================================
-- A CAST HAZARD THIS FILE DELIBERATELY INHERITS — READ BEFORE APPLYING
-- =============================================================================
--
-- `is_active_coach_of` takes a uuid, so the path segment must be cast. Migration
-- 130 documents exactly why that is dangerous, from a defect it had to fix:
--
--   "The cast RAISES rather than denies. A policy predicate that errors aborts
--    the statement instead of evaluating false, and USING is applied per
--    candidate row -- so a single object whose first segment is not a uuid
--    breaks every read of the bucket, for every user. Migration 029, the
--    progress-photos precedent, deliberately compares as text for exactly this
--    reason."
--
-- The existing policy compares `client_id::text` to the segment, casting the
-- COLUMN (always a uuid) rather than the PATH (attacker-influenced). The form
-- above reverses that and is therefore **unsafe as written** if any object in
-- `progress-photos` has a non-uuid first segment.
--
-- TWO SAFE ALTERNATIVES — the wave must choose one, with evidence:
--
--   (a) Keep the text comparison and add the status predicate only:
--
--         AND EXISTS (SELECT 1 FROM coach_client_relationships r
--                      WHERE r.coach_id = auth.uid()
--                        AND r.client_id::text = (storage.foldername(name))[1]
--                        AND r.status = 'active')
--
--       Minimal, provably non-raising, but re-inlines the predicate — the
--       duplication that caused this drift.
--
--   (b) Add a text-taking overload `is_active_coach_of(text)` that returns
--       false on a malformed segment instead of raising, and call that.
--       Keeps one definition AND cannot abort a read.
--
-- **Recommendation: (b).** (a) is the smaller diff; (b) removes the root cause.
-- Whichever is chosen, first confirm against live QA that every object in
-- `progress-photos` has a uuid first segment.
--
-- =============================================================================
-- VERIFICATION AFTER APPLYING (all four are testable today with the fixtures)
-- =============================================================================
--
--   1. FORMER coach signs a client's object        -> expect 400 not_found
--   2. owner signs their own object                -> expect 200   (regression)
--   3. attacker signs it                           -> expect 400 not_found
--   4. anon public route                           -> expect Bucket not found
--
-- Step 1 is the fix. Step 2 is what must NOT break. An ACTIVE coach reading a
-- client's photos cannot be verified until a QA fixture with status='active'
-- exists — that needs `QA_SERVICE`, which is absent. Until then, applying this
-- migration risks breaking the legitimate active-coach path with no way to
-- detect it. **Seed an active relationship before scheduling this.**
-- =============================================================================
