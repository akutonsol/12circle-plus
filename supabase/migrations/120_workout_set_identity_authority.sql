-- Migration 120: `set_id` becomes the ONLY identity of a logged set.
--
-- Two identity keys were live at once and they disagreed:
--
--   uq_workout_set_logs_set          (session_id, exercise_name, set_number)  -- 051
--   uq_workout_set_logs_set_identity (session_id, set_id)                     -- 106
--
-- Migration 106's own comment declares `set_id` "authoritative for resume", but
-- the writer (`WorkoutService.saveSetLog`) still keyed its update on the 051
-- ordinal and carried `set_id` as a mere payload column. That is the root of
-- three reported defects at once:
--
--   * DUPLICATE EXERCISE NAMES. A workout may legitimately prescribe the same
--     movement twice. Both instances write set_number 1 under the same
--     exercise_name, so the 051 index makes them the SAME ROW — one block's
--     set 1 silently overwrites the other's.
--
--   * EXERCISE SWAP → 23505. Swapping a movement changes `exercise_name` while
--     the set ids stay. The UPDATE then matches nothing, falls through to the
--     INSERT, and the INSERT violates uq_workout_set_logs_set_identity. A hard
--     error on the next set logged after any swap.
--
--   * RESUME SEATING. An ordinal is only meaningful while an exercise's sets
--     are exactly 1..N in arrival order; `set_id` is meaningful always.
--
-- Retiring 051 is not a loosening. `(session_id, set_id)` is strictly stronger:
-- it is unique per *set*, where the ordinal was unique per (name, number) — a
-- pair that two different sets can legitimately share.
--
-- Nothing is deleted. Historical rows with a NULL `set_id` keep resuming by
-- their stored set number, exactly as migration 106 intended.

-- ── 1. The exercise instance a set belonged to ──────────────────────────────
--
-- `exercise_id` referenced the LIBRARY exercise, which cannot distinguish two
-- instances of the same movement in one workout. The instance is the identity;
-- the library id and the name stay as recorded attributes (history, PRs).
ALTER TABLE public.workout_set_logs
  ADD COLUMN IF NOT EXISTS exercise_instance_id text;

COMMENT ON COLUMN public.workout_set_logs.exercise_instance_id IS
  'Identity of the exercise instance this set belonged to, matching '
  'exercises[].exercise_instance_id in the session workout snapshot. NULL for '
  'rows written before migration 120.';

COMMENT ON COLUMN public.workout_set_logs.exercise_name IS
  'The movement performed, as a RECORDED ATTRIBUTE. Never an identity: a '
  'workout may prescribe the same name twice, and a mid-session swap changes '
  'it. Kept unchanged for history and PR lookups.';

COMMENT ON COLUMN public.workout_set_logs.set_number IS
  'Display ordinal of the set within its exercise. Never an identity — see '
  'set_id.';

-- Backfill from the row's own evidence: a set id minted as `<instance>:s<n>`
-- carries its instance in front of the separator. Rows whose set_id has another
-- shape, or none, are left NULL rather than guessed at.
UPDATE public.workout_set_logs
   SET exercise_instance_id = split_part(set_id, ':s', 1)
 WHERE exercise_instance_id IS NULL
   AND set_id IS NOT NULL
   AND set_id LIKE '%:s%';

-- ── 2. Retire the ordinal identity ──────────────────────────────────────────
--
-- Dropped only now that the writer no longer depends on it. Leaving both is
-- what made "two authoritative keys" a property of the database.
DROP INDEX IF EXISTS public.uq_workout_set_logs_set;

-- The columns stay indexed for the reads that still use them (history by
-- exercise, progression charts) — non-unique, because they are attributes.
CREATE INDEX IF NOT EXISTS workout_set_logs_session_exercise_idx
  ON public.workout_set_logs (session_id, exercise_name, set_number);

CREATE INDEX IF NOT EXISTS workout_set_logs_instance_idx
  ON public.workout_set_logs (session_id, exercise_instance_id);

-- ── 3. Identity is required from here on ────────────────────────────────────
--
-- A row with no set_id cannot be read back onto the set it recorded. Historical
-- NULLs are kept (their identity is genuinely unrecoverable and inventing one
-- would assert something the data does not support), but nothing new may be
-- written without one.
CREATE OR REPLACE FUNCTION public.workout_set_logs_require_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.set_id IS NULL OR btrim(NEW.set_id) = '' THEN
    RAISE EXCEPTION
      'workout_set_logs.set_id is required: a logged set must carry the '
      'identity of the set it records (session %, exercise %, set %)',
      NEW.session_id, NEW.exercise_name, NEW.set_number
      USING HINT = 'See docs/WORKOUT_DOMAIN_CONTRACT.md §4.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workout_set_logs_require_identity ON public.workout_set_logs;
CREATE TRIGGER trg_workout_set_logs_require_identity
  BEFORE INSERT ON public.workout_set_logs
  FOR EACH ROW EXECUTE FUNCTION public.workout_set_logs_require_identity();

-- ── 4. Completed history is immutable ───────────────────────────────────────
--
-- The client already enforces this (ActiveWorkoutNotifier's completed-set gate
-- and the explicit correction flow), but the client is not a boundary: the same
-- table is reachable over PostgREST with the user's own JWT. These are the
-- rules the contract states, made properties of the data:
--
--   * a confirmed set is never un-confirmed;
--   * a confirmed set's identity never moves to a different set or session;
--   * a set log is never re-attributed to a different exercise instance.
--
-- Values (reps/weight/rpe/notes) stay updatable, because the product HAS an
-- explicit correction flow and a correction is a legitimate edit of a recorded
-- result — it is a different thing from a set silently changing underneath it.
CREATE OR REPLACE FUNCTION public.workout_set_logs_protect_history()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.completed AND NOT coalesce(NEW.completed, false) THEN
    RAISE EXCEPTION 'a completed set cannot be un-completed (set_id %)', OLD.set_id
      USING HINT = 'Completed history is immutable. See '
                   'docs/WORKOUT_DOMAIN_CONTRACT.md §4.';
  END IF;
  IF NEW.session_id IS DISTINCT FROM OLD.session_id THEN
    RAISE EXCEPTION 'a set log cannot move between sessions (set_id %)', OLD.set_id;
  END IF;
  IF OLD.set_id IS NOT NULL AND NEW.set_id IS DISTINCT FROM OLD.set_id THEN
    RAISE EXCEPTION 'a set log cannot change the set it records (was %)', OLD.set_id;
  END IF;
  IF OLD.exercise_instance_id IS NOT NULL
     AND NEW.exercise_instance_id IS DISTINCT FROM OLD.exercise_instance_id THEN
    RAISE EXCEPTION
      'a set log cannot be re-attributed to another exercise instance (was %)',
      OLD.exercise_instance_id
      USING HINT = 'A swapped-in exercise gets new set identities; the replaced '
                   'exercise keeps its own logs.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workout_set_logs_protect_history ON public.workout_set_logs;
CREATE TRIGGER trg_workout_set_logs_protect_history
  BEFORE UPDATE ON public.workout_set_logs
  FOR EACH ROW EXECUTE FUNCTION public.workout_set_logs_protect_history();

-- ── 5. A finished session is finished ───────────────────────────────────────
--
-- `completed` and `abandoned` are terminal (docs/WORKOUT_DOMAIN_CONTRACT.md §7).
-- Re-opening one would resurrect a session into the single active-session slot
-- and, for a completed one, re-open history for editing.
ALTER TABLE public.workout_sessions
  DROP CONSTRAINT IF EXISTS workout_sessions_status_known;
ALTER TABLE public.workout_sessions
  ADD CONSTRAINT workout_sessions_status_known
  CHECK (status IN ('in_progress', 'completed', 'abandoned')) NOT VALID;

CREATE OR REPLACE FUNCTION public.workout_sessions_terminal_status()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('completed', 'abandoned')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'session % is % and cannot be re-opened', OLD.id, OLD.status
      USING HINT = 'completed and abandoned are terminal states. See '
                   'docs/WORKOUT_DOMAIN_CONTRACT.md §7.';
  END IF;
  -- A session that is no longer in progress has a frozen prescription: the
  -- snapshot is what the client actually performed against.
  IF OLD.status <> 'in_progress'
     AND NEW.workout_snapshot IS DISTINCT FROM OLD.workout_snapshot THEN
    RAISE EXCEPTION 'the workout snapshot of a % session is immutable (session %)',
      OLD.status, OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workout_sessions_terminal_status ON public.workout_sessions;
CREATE TRIGGER trg_workout_sessions_terminal_status
  BEFORE UPDATE ON public.workout_sessions
  FOR EACH ROW EXECUTE FUNCTION public.workout_sessions_terminal_status();

COMMENT ON COLUMN public.workout_sessions.status IS
  'in_progress | completed | abandoned. in_progress is the one live session per '
  'user (workout_sessions_one_active_per_user); the other two are terminal. '
  'There is no separate paused state — pausing is in_progress plus the stored '
  'cursor (migrations 105/107). Abandoning NEVER deletes set logs.';
