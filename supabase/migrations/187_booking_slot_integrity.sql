-- Migration 187. A coach availability slot holds at most one live call, and the
-- database -- not the booking client -- keeps coach_availability.is_booked.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["187"]; environments.qa.applied_through is "181".
--
-- THE DEFECT (verified on QA's live catalog, 2026-11-14). The client books a slot
-- in two writes (booking_screen.dart `_book`):
--   1. INSERT coaching_calls (client_id = me, availability_slot_id = slot)
--   2. UPDATE coach_availability SET is_booked = true WHERE id = slot
-- coach_availability's only write policies are the coach's own
-- ("Coaches manage own availability", "coach_manage_availability": coach_id =
-- auth.uid()). Write 2 therefore matches ZERO rows for a client -- PostgREST
-- answers 204 and nothing is said -- so a booked slot is never marked booked,
-- stays in every client's list (`is_booked = false`), and the next client books
-- it again. Nothing in the schema stops two live calls on one slot: the only
-- index on coaching_calls is its primary key. Cancelling has the mirror defect:
-- the client's `is_booked = false` reopen also matches zero rows.
--
-- THE FIX. Decision-free: the product already intends one booking per slot (the
-- screen hides booked slots, and both cancel paths "reopen" the slot).
--   * BEFORE INSERT / UPDATE trigger on coaching_calls: a call that takes a slot
--     must name the slot's own coach, takes the slot's own time, and is refused
--     with 23505 when the slot is already flagged booked or already holds a live
--     call. The slot row is locked FOR UPDATE first, so two concurrent bookings
--     of one slot serialize and the second sees the first.
--   * A partial UNIQUE index -- one non-cancelled call per slot -- is the
--     backstop that holds even for a path that bypasses the trigger.
--   * AFTER trigger: is_booked follows the calls. A claim sets it; a release
--     (cancel, repoint, delete) clears it only when no other live call remains.
--   * Both trigger functions are SECURITY DEFINER because the CLIENT's own write
--     must be able to update the coach's slot row, which RLS forbids it to do
--     directly. Each touches only the slot named by the call row the caller was
--     already allowed to write.
--
-- "LIVE" means any status other than 'cancelled' (no CHECK constraint names the
-- statuses; the app writes 'scheduled', 'completed', 'cancelled'). A completed
-- call keeps its slot -- it was used.
--
-- NO BACKFILL OF is_booked. On QA two slots are flagged booked with no live call
-- behind them (origin not established). Rewriting existing flags from the calls
-- table would reopen them, which is not this migration's call to make; existing
-- flags are left exactly as they are and are RESPECTED (a flagged slot refuses a
-- booking). Pre-flight on QA, 2026-11-14: 0 slots with two non-cancelled calls,
-- so the unique index builds.
--
-- COMPATIBILITY. The app's existing writes keep working unchanged: its INSERT
-- passes the checks (same coach, same time), and its no-op is_booked UPDATEs
-- stay no-ops. A double booking now fails with 23505 instead of succeeding.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS coaching_calls_one_live_call_per_slot
  ON public.coaching_calls (availability_slot_id)
  WHERE availability_slot_id IS NOT NULL AND status <> 'cancelled';

CREATE OR REPLACE FUNCTION public.coaching_calls_claim_slot()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_slot  public.coach_availability%ROWTYPE;
  v_holds boolean;
BEGIN
  IF NEW.availability_slot_id IS NULL OR NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;
  -- Does this call already hold the slot? (An UPDATE that keeps a live call on
  -- its slot: a completed call keeps the slot it already holds.)
  v_holds := TG_OP = 'UPDATE'
             AND NEW.availability_slot_id IS NOT DISTINCT FROM OLD.availability_slot_id
             AND OLD.status <> 'cancelled';
  IF v_holds AND NEW.coach_id IS NOT DISTINCT FROM OLD.coach_id THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_slot
    FROM public.coach_availability
   WHERE id = NEW.availability_slot_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;                          -- the foreign key reports it
  END IF;

  IF v_slot.coach_id IS DISTINCT FROM NEW.coach_id THEN
    RAISE EXCEPTION 'this slot belongs to another coach'
      USING ERRCODE = '23514';
  END IF;

  IF v_holds THEN
    RETURN NEW;                          -- already its slot; only the coach was re-checked
  END IF;

  IF v_slot.is_booked
     OR EXISTS (SELECT 1 FROM public.coaching_calls c
                 WHERE c.availability_slot_id = NEW.availability_slot_id
                   AND c.status <> 'cancelled'
                   AND c.id <> NEW.id) THEN
    RAISE EXCEPTION 'that time has already been booked'
      USING ERRCODE = '23505';
  END IF;

  -- The slot is the source of truth for when the call is.
  NEW.scheduled_at := v_slot.slot_time;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.coaching_calls_sync_slot()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_released uuid;
BEGIN
  -- Claim.
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND NEW.availability_slot_id IS NOT NULL
     AND NEW.status <> 'cancelled' THEN
    UPDATE public.coach_availability
       SET is_booked = true
     WHERE id = NEW.availability_slot_id
       AND is_booked IS DISTINCT FROM true;
  END IF;

  -- Release: the slot this call held before, if it no longer holds it.
  IF TG_OP = 'DELETE' THEN
    v_released := CASE WHEN OLD.status <> 'cancelled' THEN OLD.availability_slot_id END;
  ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'cancelled'
        AND (NEW.status = 'cancelled'
             OR NEW.availability_slot_id IS DISTINCT FROM OLD.availability_slot_id) THEN
    v_released := OLD.availability_slot_id;
  END IF;

  IF v_released IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.coaching_calls c
                      WHERE c.availability_slot_id = v_released
                        AND c.status <> 'cancelled') THEN
    UPDATE public.coach_availability
       SET is_booked = false
     WHERE id = v_released;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.coaching_calls_claim_slot() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.coaching_calls_sync_slot()  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_coaching_calls_claim_slot ON public.coaching_calls;
CREATE TRIGGER trg_coaching_calls_claim_slot
  BEFORE INSERT OR UPDATE OF status, availability_slot_id, coach_id
  ON public.coaching_calls
  FOR EACH ROW EXECUTE FUNCTION public.coaching_calls_claim_slot();

DROP TRIGGER IF EXISTS trg_coaching_calls_sync_slot ON public.coaching_calls;
CREATE TRIGGER trg_coaching_calls_sync_slot
  AFTER INSERT OR UPDATE OF status, availability_slot_id OR DELETE
  ON public.coaching_calls
  FOR EACH ROW EXECUTE FUNCTION public.coaching_calls_sync_slot();

COMMENT ON FUNCTION public.coaching_calls_claim_slot() IS
  'Migration 187: a call that takes an availability slot must name the slot''s '
  'coach, takes the slot''s time, and is refused 23505 when the slot is flagged '
  'booked or already holds a non-cancelled call. Locks the slot row first.';
COMMENT ON FUNCTION public.coaching_calls_sync_slot() IS
  'Migration 187: coach_availability.is_booked follows coaching_calls -- set on '
  'claim, cleared on release only when no other non-cancelled call holds the slot.';

COMMIT;
