-- Migration 189. send_communication and update_communication refuse instead of
-- succeeding silently when they change nothing.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["189"]; environments.qa.applied_through is "181".
--
-- THE DEFECT (live definitions read from QA, 2026-11-14). Both functions are
-- `RETURNS void` and end in one UPDATE whose WHERE clause carries the whole
-- authorization (`coach_id = auth.uid()` or an admin / content_manager role) as
-- well as the id. When the id does not exist, or the caller is not allowed, the
-- UPDATE matches zero rows and the function returns normally. The coach's weekly
-- review screen therefore says "Sent to client ✓" for a message that was never
-- sent -- its own comment (weekly_review_screen.dart, sendReviewedCommunication)
-- records that "send_communication returns void and cannot report a row it did
-- not change; that needs the RPC to return a count".
--
-- THE FIX. Same signatures, same authorization, same writes. After the UPDATE,
-- zero rows changed raises 42501 'not found or not authorized' -- ONE refusal for
-- both reasons, so the functions do not become an oracle for which ids exist (the
-- convention migration 184 set). The app already maps any error from these RPCs
-- to "not sent" / "not saved" (CoachProgramService.sendCommunication /
-- updateCommunication return false on a throw), so no client change is needed.
--
-- FUNCTION REPLACEMENT RULE. CREATE OR REPLACE keeps ACL and owner but not
-- proconfig, so the search_path pin is restated, and the grants are restated below
-- exactly as they are live (authenticated may EXECUTE; PUBLIC and anon may not).

BEGIN;

CREATE OR REPLACE FUNCTION public.send_communication(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE communications
     SET status = 'sent', approved_by = auth.uid(), approved_at = now(), sent_at = now()
   WHERE id = p_id
     AND (coach_id = auth.uid()
          OR EXISTS (SELECT 1 FROM user_profiles
                      WHERE id = auth.uid() AND role IN ('admin', 'content_manager')));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'not found or not authorized' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_communication(p_id uuid, p_client_text text, p_coach_text text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE communications
     SET client_text = p_client_text, coach_text = p_coach_text
   WHERE id = p_id
     AND (coach_id = auth.uid()
          OR EXISTS (SELECT 1 FROM user_profiles
                      WHERE id = auth.uid() AND role IN ('admin', 'content_manager')));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'not found or not authorized' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.send_communication(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_communication(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.update_communication(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_communication(uuid, text, text) TO authenticated;

COMMIT;
