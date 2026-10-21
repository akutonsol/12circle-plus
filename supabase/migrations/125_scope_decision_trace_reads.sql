-- 125_scope_decision_trace_reads.sql
--
-- Closes F-J-12: the 089 decision_traces SELECT policy granted every
-- authenticated coach global access to every member's decision traces.
--
-- Decision traces are sensitive training-decision provenance. A coach may
-- read a trace only when:
--   1. they are the subject;
--   2. they created the trace;
--   3. they are an admin/content_manager; or
--   4. they are the subject's ACTIVE coach.
--
-- Do not use the broad "role = coach" arm from migration 089.

DROP POLICY IF EXISTS "dtrace read own/staff"
  ON public.decision_traces;

CREATE POLICY "dtrace read own/creator/scoped-staff"
  ON public.decision_traces
  FOR SELECT
  TO authenticated
  USING (
    subject_id = (SELECT auth.uid())
    OR created_by = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.user_profiles
      WHERE id = (SELECT auth.uid())
        AND role IN ('admin', 'content_manager')
    )
    OR public.is_active_coach_of(subject_id)
  );

COMMENT ON POLICY "dtrace read own/creator/scoped-staff"
  ON public.decision_traces IS
  'Decision traces are readable by the subject, creator, admin/content_manager, or the subject''s active coach; coach role alone is not sufficient.';
