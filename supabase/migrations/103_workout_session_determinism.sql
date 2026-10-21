-- Migration 103: make the active workout session deterministic.
--
-- Before this migration a session could only be mapped back to a workout by its
-- title, and nothing ever closed an in-progress session. Starting a second
-- workout inserted another 'in_progress' row, so "the active session" resolved
-- to whichever row happened to sort first — a different workout than the one
-- the user selected. Rows accumulated indefinitely (sessions "started" months
-- ago still surfaced as resumable).
--
-- This migration:
--   1. records the exact workout a session belongs to (id + a snapshot), so a
--      session can be restored without string-matching on the title;
--   2. closes the historical duplicates, keeping the most recent per user;
--   3. enforces at most one in-progress session per user from here on.
--
-- Nothing is deleted. Superseded sessions become 'abandoned' (the status the
-- app already uses when a user dismisses a resume prompt); their set logs and
-- all 'completed' history are untouched.

-- ── 1. Workout identity on the session ───────────────────────────────────────

-- Plain text, not a program_workouts FK: a session can also reference a sample
-- workout ('1', '2', '3') or a one-off AI-generated workout, neither of which
-- has a program_workouts row.
ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS workout_id text;

-- Full workout definition as selected, so resuming after an app restart
-- rebuilds the exact workout — including a workout that no longer appears in
-- any list (AI-generated, or since edited by a coach).
ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS workout_snapshot jsonb;

-- Referenced by the resume flow to restore the running clock. Previously
-- written by the app but never added by a numbered migration, so the write
-- failed silently on any database built from migrations alone.
ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS elapsed_seconds int DEFAULT 0;

-- ── 2. Close historical duplicates ───────────────────────────────────────────

WITH ranked AS (
  SELECT id,
         row_number() OVER (PARTITION BY user_id ORDER BY started_at DESC, id DESC) AS rn
  FROM public.workout_sessions
  WHERE status = 'in_progress'
)
UPDATE public.workout_sessions s
   SET status = 'abandoned'
  FROM ranked r
 WHERE s.id = r.id
   AND r.rn > 1;

-- ── 3. One active session per user, enforced ─────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_one_active_per_user
  ON public.workout_sessions (user_id)
  WHERE status = 'in_progress';

-- Resume and the Train screen both filter on (user_id, status).
CREATE INDEX IF NOT EXISTS workout_sessions_user_status_started_idx
  ON public.workout_sessions (user_id, status, started_at DESC);
