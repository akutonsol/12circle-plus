-- Migration 106: give every logged set the identity of the set it recorded.
--
-- A `workout_set_logs` row could only say which set it belonged to by
-- (session, exercise name, set number). That is an ordinal, not an identity:
-- it is only meaningful while the exercise's sets are exactly 1..N and the
-- client reads them back in that order. When the rows came back in a different
-- order — or a set had been added, removed or renumbered — the app had no way
-- to tell which set a row was for, and resuming re-seated one set's weight,
-- reps, RPE and notes onto another.
--
-- `set_id` is the id the workout definition gives the set (carried in
-- `workout_sessions.workout_snapshot` under `set_details[].id`). Resuming
-- attaches a row to a set by this id, so the set a client filled in before
-- leaving is the same logical set when they come back, regardless of ordering.
--
-- Nullable with no backfill: the identity of a historical row is genuinely
-- unknown, and inventing one would assert something the data does not support.
-- Rows without it keep resuming by their stored set number, exactly as before.

ALTER TABLE public.workout_set_logs
  ADD COLUMN IF NOT EXISTS set_id text;

COMMENT ON COLUMN public.workout_set_logs.set_id IS
  'Identity of the workout set this row records, matching set_details[].id in '
  'the session workout snapshot. Authoritative for resume; set_number is the '
  'display ordinal and the pre-106 fallback. NULL for rows written before 106.';

-- Two rows in one session must never claim the same set. The existing
-- (session_id, exercise_name, set_number) unique index from migration 051 is
-- kept as-is; this adds the same guarantee in identity terms, and is partial so
-- the historical NULL rows are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS uq_workout_set_logs_set_identity
  ON public.workout_set_logs (session_id, set_id)
  WHERE set_id IS NOT NULL;
