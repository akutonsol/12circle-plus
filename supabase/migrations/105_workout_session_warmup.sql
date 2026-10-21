-- Migration 105: the warm-up acknowledgement belongs to the session.
--
-- The Workout Zone prompted for a warm-up every time the screen mounted, so a
-- browser refresh (or leaving and returning) re-asked a client who had already
-- warmed up and started lifting. The acknowledgement was screen state, and
-- screen state does not survive a reload.
--
-- Recording it on the session makes it part of the thing being restored: once
-- acknowledged for an active session it stays acknowledged for that session,
-- and a genuinely new session asks again.
--
-- Nullable with no default: NULL means "not yet acknowledged", which is the
-- correct reading for every historical row.

ALTER TABLE public.workout_sessions
  ADD COLUMN IF NOT EXISTS warmup_acknowledged_at timestamptz;

COMMENT ON COLUMN public.workout_sessions.warmup_acknowledged_at IS
  'When the client confirmed they warmed up for this session. NULL = not yet '
  'acknowledged; set once and never cleared, so restoring an active session '
  'does not re-prompt.';
