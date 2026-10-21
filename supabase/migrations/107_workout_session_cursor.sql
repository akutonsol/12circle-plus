-- Migration 107: the session records which set the client is on.
--
-- "Where am I in this workout" was screen state, so a browser refresh lost it
-- and the app had to guess the answer back by scanning for the first set with
-- no completion recorded. That guess is right in the common case and wrong in
-- the one that matters: a client who deliberately skipped ahead — starting the
-- last exercise first, or leaving a set open to come back to — was sent back to
-- the earliest unfinished set instead of the one they were actually on.
--
-- Storing the position makes it part of the session being restored, alongside
-- the workout snapshot, the logged sets and the warm-up acknowledgement.
-- Identity, not indices: the ids survive the workout being re-snapshotted after
-- a mid-session exercise swap, where a position would not.
--
-- The derived answer stays as the fallback, and remains authoritative when the
-- cursor has gone stale (the set was swapped out, or has since been completed),
-- so a resumed workout can never point at a set that is not there.
--
-- Nullable with no default: NULL means "the client has not moved within this
-- workout yet", which is the correct reading for every historical row.

ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS current_exercise_id text,
  ADD COLUMN IF NOT EXISTS current_set_id text;

COMMENT ON COLUMN public.workout_sessions.current_exercise_id IS
  'Identity of the exercise the client is currently on. NULL until they move '
  'within the workout.';

COMMENT ON COLUMN public.workout_sessions.current_set_id IS
  'Identity of the set the client is currently on, matching set_details[].id in '
  'workout_snapshot and workout_set_logs.set_id. Honoured on resume while it '
  'still names an outstanding set; otherwise the first outstanding set wins.';
