-- ═══════════════════════════════════════════════════════════════════════════
-- 175 · ENG-02 · write `weekly_feedback.subject_id`, and close the latent write
--       path that writing it would otherwise OPEN.
--
-- THE FINDING. ENG-02 records that `subject_id` is never written, which silently
-- disables four systems: `predict_client` always returns `no_data`;
-- `assemble_weekly_review` always returns `no_feedback`; `evaluate_week` reads
-- `coaching_mode` through `fb.subject_id` → NULL → `needs_approval` NEVER FIRES for
-- coach-guided clients, disabling the approval matrix; and `regenerate_program`
-- stamps `decision_traces.subject_id` NULL, so a subject can never read the trace of
-- their own program change.
--
-- WHY THE OBVIOUS FIX WOULD HAVE OPENED A HOLE, AND THIS IS THE POINT OF 175.
-- Migration 117 split 094's `FOR ALL` policy because it let a subject DELETE their own
-- feedback. It removed DELETE. It LEFT the subject arm on UPDATE:
--
--     weekly fb update · USING/WITH CHECK (subject_id = auth.uid() OR <the coach>)
--
-- That arm is DEAD CODE TODAY, precisely because `subject_id` is always NULL — no
-- subject can ever match it. Writing `subject_id` WAKES IT, and the row contains
-- `coach_note`: the coach's written assessment of that person. So the naive ENG-02 fix
-- would hand every client row-level UPDATE over their own coach's notes. 117 could not
-- have caught this; the arm was unreachable when it was written.
--
-- So the freeze lands in the SAME migration as the derivation. The pattern is 138's
-- `enforce_registration_integrity`: SECURITY INVOKER, a service-role passthrough, and
-- frozen columns restored from OLD rather than rejected with an error.
--
-- WHAT THIS MIGRATION REFUSES TO DECIDE.
-- `workout_programs` has NO subject column — only `coach_id` — so the subject can only
-- come from `workout_program_assignments`. A program may carry SEVERAL active
-- assignments, while `weekly_feedback` is `unique (program_id, week)`: one row per
-- program-week, for what could be many clients. Which subject owns that row is a
-- MODELLING QUESTION the governing artifacts do not answer, and it is not answered
-- here. The derivation fires ONLY when there is EXACTLY ONE active assignment, and
-- leaves `subject_id` NULL otherwise — the same discipline as METRIC-06b's missing
-- commission rates: decline to guess, and leave the gap visible. Live QA currently has
-- 1 active assignment across 1 program, so the ambiguous case is real but unpopulated.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_weekly_feedback_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n       integer;
  v_subject uuid;
  v_is_coach boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN NEW;                      -- internal / service-role path, as 138:101
  END IF;

  v_is_coach := EXISTS (
    SELECT 1 FROM public.workout_programs p
     WHERE p.id = NEW.program_id AND p.coach_id = (SELECT auth.uid()));

  IF TG_OP = 'UPDATE' THEN
    -- Identity is frozen for everyone. Which program and which week a feedback row
    -- describes is not an editable field, and `unique (program_id, week)` is the only
    -- thing tying the row to its subject.
    NEW.program_id := OLD.program_id;
    NEW.week       := OLD.week;

    -- A subject may not reassign the row to someone else. Once derived, it stands;
    -- while still NULL, the derivation below may fill it.
    IF OLD.subject_id IS NOT NULL THEN
      NEW.subject_id := OLD.subject_id;
    END IF;

    -- THE FREEZE THIS MIGRATION EXISTS FOR. `coach_note` is the coach's written
    -- assessment of this person. A subject may edit their OWN note and nothing else.
    IF NOT v_is_coach THEN
      NEW.coach_note := OLD.coach_note;
    END IF;
  END IF;

  -- Derive the subject, and only when it is unambiguous.
  IF NEW.subject_id IS NULL THEN
    -- array_agg, not min(): PostgreSQL has NO min/max aggregate for uuid, and the
    -- first draft of this migration failed to apply on exactly that
    -- (`function min(uuid) does not exist`, SQLSTATE 42883). The subscript is only
    -- ever read when the count is 1, so it is the single assignment or nothing.
    SELECT count(*), (array_agg(a.client_id))[1]
      INTO v_n, v_subject
      FROM public.workout_program_assignments a
     WHERE a.program_id = NEW.program_id
       AND a.status = 'active';
    IF v_n = 1 THEN
      NEW.subject_id := v_subject;
    END IF;
    -- v_n = 0 or v_n > 1: left NULL on purpose. See the header. A guessed subject
    -- would decide, silently, whose body a coaching decision was made about.
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_weekly_feedback_integrity() IS
  'V5 §171 · ENG-02. Derives weekly_feedback.subject_id from the single active '
  'workout_program_assignments row, and refuses to derive it when a program has zero '
  'or several active assignments. Also freezes program_id, week, an already-derived '
  'subject_id, and — for any caller who is not the program''s coach — coach_note. '
  'That last freeze is not incidental: 117 left a subject UPDATE arm that was dead '
  'only because subject_id was never written, so deriving it without this freeze '
  'would give every client UPDATE over their own coach''s notes.';

REVOKE ALL ON FUNCTION public.enforce_weekly_feedback_integrity() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_weekly_feedback_integrity ON public.weekly_feedback;
CREATE TRIGGER trg_weekly_feedback_integrity
  BEFORE INSERT OR UPDATE ON public.weekly_feedback
  FOR EACH ROW EXECUTE FUNCTION public.enforce_weekly_feedback_integrity();

-- ── backfill, restricted to the unambiguous case ───────────────────────────
-- Idempotent and re-runnable. It cannot pick a subject for an ambiguous program, for
-- the same reason the trigger cannot.
UPDATE public.weekly_feedback f
   SET subject_id = a.client_id
  FROM (
    SELECT program_id, (array_agg(client_id))[1] AS client_id
      FROM public.workout_program_assignments
     WHERE status = 'active'
     GROUP BY program_id
    HAVING count(*) = 1
  ) a
 WHERE f.program_id = a.program_id
   AND f.subject_id IS NULL;
