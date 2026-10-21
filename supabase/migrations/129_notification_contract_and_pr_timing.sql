-- 129_notification_contract_and_pr_timing.sql
--
-- Wave 3A task 3A-9. Migration number assigned 2026-08-31 by the amendment to
-- docs/MASTER_REMEDIATION_WAVES.md section 0.2, recorded in registry section
-- 7.22, after Wave 2 consumed 126/127/128. Nothing is renumbered.
--
-- Four findings, each an object the application already names or a trigger whose
-- timing or duplication contradicts the contract. Every statement is idempotent
-- and nothing outside these four corrections changes behaviour.
--
--   I-NOT-01  public.messages has no `metadata` column, but sendMessage() sets
--             row['metadata'] for a photo message, so the insert 400s, the
--             caller returns false and _sendPhoto never checks it -- the photo
--             is uploaded and the message is silently discarded.
--
--   I-NOT-02  may_notify() (118, finding F-03) allowlists the coach link, a
--             shared conversation, a booked coaching call and team membership.
--             Two community members share none of those, so the two writers
--             below are rejected and both swallow the failure:
--               live_community_service.dart:129  comment -> post author
--               live_class_service.dart:173      waitlist promotion -> member
--             This extends the allowlist with exactly those two relationships.
--             It stays an allowlist. It is NOT widened to true.
--
--   I-NOT-03  Two triggers fire on the same workout_sessions status -> completed
--             transition and both insert a COACH notification:
--               notify_on_workout_complete        (004, body redefined by 026)
--                 -> notifies the client AND the coach, type 'client_workout',
--                    through insert_notification()
--               trg_notify_coach_workout_complete (049)
--                 -> notifies the coach again, type 'workout_completed', by raw
--                    insert
--             The coach receives two notifications per completed workout. Per
--             QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md I-NOT-03 the authoritative
--             trigger to KEEP is notify_on_workout_complete, because it also
--             notifies the client and routes through insert_notification().
--             049's trigger is dropped. 049's FUNCTION is left in place: it is a
--             trigger function, so it is not directly callable, and removing it
--             is outside this finding.
--
--   I-WRK-02  trg_detect_pr fires AFTER INSERT only while the writer is
--             update-then-insert, so a PR recorded by an update is never seen.
--             Only the trigger TIMING changes. detect_pr_on_set_log()'s body is
--             migration 056's authoritative version (it honours
--             supports_pr_tracking) and is deliberately NOT redefined here.
--
-- NOT IN SCOPE, deliberately: `custom_exercises.approved_by` is NOT added. The
-- authoritative column is `last_reviewed_by` (083_exercise_content_pipeline.sql)
-- and I-COM-03(a) repoints the client write at it instead -- B3, registry 7.22.
-- I-COM-03 (b) and (c) remain Q-9-gated and Wave 7D.

BEGIN;

-- ---------------------------------------------------------------------------
-- I-NOT-01. The column the chat photo path already writes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS metadata jsonb;

COMMENT ON COLUMN public.messages.metadata IS
  'Structured payload for non-plain-text messages -- the chat photo path writes '
  '{"type":"image","url":...} here (messaging_service.dart sendMessage). Absent '
  'until migration 129; every image message before it was discarded by a 400 '
  'that the sender swallowed (I-NOT-01).';

-- ---------------------------------------------------------------------------
-- I-NOT-02. Extend the notification allowlist by exactly two relationships.
--
-- Migration 118's five arms are carried forward verbatim. Gate 0.14 requires a
-- redefinition to preserve the SECURITY DEFINER shape, the search_path pin and
-- the grant posture; all three are re-stated below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.may_notify(recipient uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT (SELECT auth.uid()) IS NULL
      OR recipient = (SELECT auth.uid())
      OR EXISTS (SELECT 1 FROM public.coach_client_relationships r
                  WHERE (r.coach_id  = (SELECT auth.uid()) AND r.client_id = recipient)
                     OR (r.client_id = (SELECT auth.uid()) AND r.coach_id  = recipient))
      OR public.shares_conversation_with(recipient)
      OR EXISTS (SELECT 1 FROM public.coaching_calls c
                  WHERE (c.coach_id  = (SELECT auth.uid()) AND c.client_id = recipient)
                     OR (c.client_id = (SELECT auth.uid()) AND c.coach_id  = recipient))
      OR EXISTS (SELECT 1 FROM public.coach_team_members t
                  WHERE (t.coach_id = (SELECT auth.uid()) AND t.member_id = recipient)
                     OR (t.member_id = (SELECT auth.uid()) AND t.coach_id = recipient))
      -- I-NOT-02 arm 1: the recipient authored a post the caller has commented
      -- on. Both sides are required -- authorship alone does not qualify, and
      -- neither does commenting on somebody else's post.
      OR EXISTS (SELECT 1 FROM public.community_posts p
                   JOIN public.post_comments pc ON pc.post_id = p.id
                  WHERE p.user_id  = recipient
                    AND pc.user_id = (SELECT auth.uid()))
      -- I-NOT-02 arm 2: the recipient and the caller are both booked into the
      -- same class. Status is deliberately not filtered: the writer this arm
      -- exists for is _promoteFromWaitlist, reached from cancelBooking, where
      -- the caller's own booking has just been set to 'cancelled'.
      OR EXISTS (SELECT 1 FROM public.class_bookings cb_self
                   JOIN public.class_bookings cb_other
                     ON cb_other.class_id = cb_self.class_id
                  WHERE cb_self.user_id  = (SELECT auth.uid())
                    AND cb_other.user_id = recipient);
$$;

REVOKE ALL ON FUNCTION public.may_notify(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.may_notify(uuid) TO authenticated;

COMMENT ON FUNCTION public.may_notify(uuid) IS
  'True when the caller has an existing relationship with the recipient -- coach '
  'link (any status), conversation, booked call, team membership, a post of the '
  'recipient''s that the caller has commented on, or a class both are booked '
  'into. Gates client-side notification inserts so the feed cannot be used to '
  'deliver arbitrary text to a stranger (migration 118, finding F-03; the last '
  'two arms added by migration 129, finding I-NOT-02). This is an allowlist: it '
  'must never be widened to true.';

-- ---------------------------------------------------------------------------
-- I-NOT-03. Drop the duplicate. notify_on_workout_complete (004/026) is the
-- authoritative trigger and is left exactly as it is.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_notify_coach_workout_complete ON public.workout_sessions;

-- ---------------------------------------------------------------------------
-- I-WRK-02. Timing only. The function body is 056's and is not touched.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_detect_pr ON public.workout_set_logs;
CREATE TRIGGER trg_detect_pr
  AFTER INSERT OR UPDATE ON public.workout_set_logs
  FOR EACH ROW EXECUTE FUNCTION public.detect_pr_on_set_log();

COMMIT;
