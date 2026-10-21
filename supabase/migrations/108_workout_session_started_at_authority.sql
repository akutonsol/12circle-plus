-- Migration 108: make session recency trustworthy, and reconcile the rows the
-- untrustworthy version produced.
--
-- `workout_sessions.started_at` is the key every "which session is active"
-- decision sorts on — the app's `inProgressSessions` ordering, and migration
-- 103's own duplicate reconciliation. It was being written by the client as
-- `DateTime.now().toIso8601String()`, which in Dart renders a *local* time with
-- no zone marker (`2026-08-23T19:11:26.689532`). Postgres reads a naive literal
-- into `timestamptz` as UTC, so a client at UTC-5 stored every session five
-- hours in the past, and a client at UTC+2 two hours in the future.
--
-- The consequence is the reported defect. Rows stamped by the database default
-- (`now()`, true UTC) and rows stamped by a skewed client are ordered against
-- each other, so a session started *later* can sort *earlier* than the one it
-- superseded. "Newest in-progress session" then resolves to the older workout —
-- a Full Body Strength session outranking the Lower Body session that replaced
-- it — and, because the app closes everything it does not pick, the genuinely
-- current session is the one marked abandoned.
--
-- The app side of this is fixed by not sending `started_at` at all: the column
-- already defaults to `now()`, so the database stamps it, which is UTC,
-- consistent between sessions and immune to the device's clock and timezone.
--
-- This migration repairs the rows already written and hardens the invariant.

-- ── 1. The database is the authority on when a session started ───────────────

-- The default already existed; restated so the column cannot be left to a
-- client that omits it under a different default.
ALTER TABLE public.workout_sessions
  ALTER COLUMN started_at SET DEFAULT now();

-- Any row that predates the default (or was inserted with an explicit NULL)
-- would block SET NOT NULL. Backfill from the session's own evidence before
-- asserting it: the first set logged against it, else its completion time.
UPDATE public.workout_sessions s
   SET started_at = COALESCE(
         (SELECT min(l.logged_at)
            FROM public.workout_set_logs l
           WHERE l.session_id = s.id),
         s.completed_at,
         now())
 WHERE s.started_at IS NULL;

ALTER TABLE public.workout_sessions
  ALTER COLUMN started_at SET NOT NULL;

COMMENT ON COLUMN public.workout_sessions.started_at IS
  'Server-stamped session start (UTC). Written by the column default, never by '
  'the client: a client-rendered local timestamp is zone-ambiguous and made '
  'newer sessions sort older than the ones they superseded. Ordering key for '
  'resume selection.';

-- ── 2. Reconcile duplicate active sessions, by trustworthy recency ───────────
--
-- Migration 103 did this too, but ranked on `started_at` alone — the very value
-- the skew corrupted, so it could keep the older session and abandon the newer.
-- Rank instead on the most recent thing we can actually trust about a session:
-- the latest server-stamped `logged_at` of a set recorded against it, falling
-- back to `started_at` when nothing was logged. `workout_set_logs.logged_at`
-- defaults to `now()` and has always been server-stamped, so it is unaffected.
--
-- `id DESC` is the final tiebreak so the result is total and deterministic
-- rather than dependent on physical row order.
WITH activity AS (
  SELECT s.id,
         s.user_id,
         GREATEST(
           s.started_at,
           COALESCE(
             (SELECT max(l.logged_at)
                FROM public.workout_set_logs l
               WHERE l.session_id = s.id),
             s.started_at)
         ) AS last_active_at
    FROM public.workout_sessions s
   WHERE s.status = 'in_progress'
), ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id
           ORDER BY last_active_at DESC, id DESC
         ) AS rn
    FROM activity
)
UPDATE public.workout_sessions s
   SET status = 'abandoned'
  FROM ranked r
 WHERE s.id = r.id
   AND r.rn > 1;

-- ── 3. One active session per user, restated ─────────────────────────────────
--
-- Already created by migration 103; restated so a database that skipped or
-- failed that step still ends up with the invariant. This is the constraint
-- that makes "exactly one authoritative active session" a property of the
-- data rather than a convention the client is trusted to keep.
CREATE UNIQUE INDEX IF NOT EXISTS workout_sessions_one_active_per_user
  ON public.workout_sessions (user_id)
  WHERE status = 'in_progress';

COMMENT ON INDEX public.workout_sessions_one_active_per_user IS
  'At most one in_progress session per user. Starting a workout must abandon '
  'the previous session before inserting, so the resume candidate is never '
  'ambiguous.';
