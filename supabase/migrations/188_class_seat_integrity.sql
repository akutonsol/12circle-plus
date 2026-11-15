-- Migration 188. Class seats are allocated, counted and handed on by the
-- database, where every booking is visible -- not by the booking client, which
-- under RLS can see only its own.
--
-- AUTHORED, NOT APPLIED. Declared in supabase/expected_applied.json under
-- environments.qa.pending["188"]; environments.qa.applied_through is "181".
--
-- THE DEFECTS (verified on QA's live catalog, 2026-11-14). live_class_service.dart
-- implements Module 13 -- "full -> waitlisted; a cancellation hands the seat to
-- the earliest waitlisted booking" -- entirely in the client, and RLS defeats
-- every step of it:
--   1. CAPACITY IS NEVER ENFORCED. bookClass counts confirmed bookings with
--      `select ... from class_bookings where class_id = X and status = 'confirmed'`.
--      class_bookings' SELECT policy shows a client ONLY ITS OWN rows, so the
--      count is 0 (or 1), never >= max_capacity: every booking is confirmed and a
--      class overbooks without limit.
--   2. current_enrolled IS NEVER MAINTAINED. _syncEnrollment UPDATEs classes, whose
--      only write policy is the coach's ("coaches manage classes"). Zero rows, no
--      error. On QA 3 classes already disagree with their bookings, and the cards
--      ("N spots left", "Full") read that column.
--   3. NOBODY IS EVER PROMOTED FROM THE WAITLIST. _promoteFromWaitlist looks for the
--      earliest waitlisted booking -- which a client cannot see (own rows only), so
--      after a client cancels it finds none and the freed seat is never handed on.
--      For a caller who CAN read the waitlist (the class's coach, an admin) it is a
--      false success: its UPDATE of another user's booking is blocked by "users
--      manage own bookings" (zero rows, no error) and it then notifies that user
--      "You're In! ... your class booking is now confirmed" while the booking is
--      still waitlisted.
--
-- THE FIX. Decision-free: the rules are the ones the app already states (the
-- capacity default of 20 included -- `max_capacity ?? 20` in the client). Only
-- WHERE they run changes.
--   * BEFORE INSERT / UPDATE OF status on class_bookings: a booking that asks for a
--     seat (confirmed or waitlisted, and did not already hold a confirmed seat)
--     gets 'confirmed' when a seat is free and 'waitlisted' when the class is
--     full -- counted over ALL bookings, under a FOR UPDATE lock on the class row
--     so concurrent bookings cannot both take the last seat. A booking that
--     already holds a confirmed seat keeps it.
--   * AFTER INSERT / UPDATE / DELETE: when a confirmed seat is released, the
--     earliest waitlisted booking(s) are promoted while seats are free, each with
--     the same notification the app sent -- now true -- and current_enrolled is
--     recomputed from the confirmed bookings.
--   * A one-time recompute of current_enrolled for every class (a derived
--     counter; no booking row is changed). Pre-flight on QA, 2026-11-14: 0 classes
--     over capacity, so no booking needs to move.
--
-- SECURITY DEFINER because the seat count must see every booking and the
-- promotion must write another user's booking and the coach's class row, which
-- RLS forbids the caller. Each function touches only the class named by the
-- booking row the caller was already allowed to write.
--
-- COMPATIBILITY. The app's existing calls keep working: its upsert now receives
-- the server's decision (confirmed or waitlisted) instead of its own guess, and
-- its now-redundant client-side promotion / counter writes stay zero-row no-ops.

BEGIN;

CREATE OR REPLACE FUNCTION public.class_bookings_assign_seat()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_capacity  integer;
  v_confirmed integer;
BEGIN
  IF NEW.status IS NULL OR NEW.status NOT IN ('confirmed', 'waitlisted') THEN
    RETURN NEW;                          -- cancelling, or a status this does not own
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'confirmed' AND NEW.class_id = OLD.class_id THEN
    NEW.status := 'confirmed';           -- a held seat is kept, never demoted
    RETURN NEW;
  END IF;

  SELECT coalesce(max_capacity, 20) INTO v_capacity
    FROM public.classes
   WHERE id = NEW.class_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;                          -- the foreign key reports it
  END IF;

  SELECT count(*) INTO v_confirmed
    FROM public.class_bookings
   WHERE class_id = NEW.class_id
     AND status = 'confirmed'
     AND id <> NEW.id;

  NEW.status := CASE WHEN v_confirmed < v_capacity THEN 'confirmed' ELSE 'waitlisted' END;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.class_bookings_sync_class()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_class    uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.class_id ELSE NEW.class_id END;
  v_released boolean := false;
  v_capacity integer;
  v_next     record;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_released := OLD.status = 'confirmed';
  ELSIF TG_OP = 'UPDATE' THEN
    v_released := OLD.status = 'confirmed'
                  AND (NEW.status IS DISTINCT FROM 'confirmed' OR NEW.class_id <> OLD.class_id);
  END IF;

  SELECT coalesce(max_capacity, 20) INTO v_capacity
    FROM public.classes WHERE id = v_class FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;                         -- class deleted (cascade)
  END IF;

  IF v_released THEN
    -- Hand the seat on, earliest first, while seats are free. Each promotion runs
    -- class_bookings_assign_seat, which re-counts and confirms.
    LOOP
      EXIT WHEN (SELECT count(*) FROM public.class_bookings
                  WHERE class_id = v_class AND status = 'confirmed') >= v_capacity;
      SELECT id, user_id INTO v_next
        FROM public.class_bookings
       WHERE class_id = v_class AND status = 'waitlisted'
       ORDER BY booked_at NULLS LAST, id
       LIMIT 1;
      EXIT WHEN NOT FOUND;
      UPDATE public.class_bookings SET status = 'confirmed' WHERE id = v_next.id;
      INSERT INTO public.notifications (recipient_id, type, title, body, read)
      VALUES (v_next.user_id, 'class', 'You''re In!',
              'A spot opened up — your class booking is now confirmed.', false);
    END LOOP;
  END IF;

  UPDATE public.classes c
     SET current_enrolled = (SELECT count(*) FROM public.class_bookings b
                              WHERE b.class_id = c.id AND b.status = 'confirmed')
   WHERE c.id = v_class;

  -- A booking moved between classes also changes the class it left.
  IF TG_OP = 'UPDATE' AND NEW.class_id IS DISTINCT FROM OLD.class_id THEN
    UPDATE public.classes c
       SET current_enrolled = (SELECT count(*) FROM public.class_bookings b
                                WHERE b.class_id = c.id AND b.status = 'confirmed')
     WHERE c.id = OLD.class_id;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.class_bookings_assign_seat() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.class_bookings_sync_class()  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_class_bookings_assign_seat ON public.class_bookings;
CREATE TRIGGER trg_class_bookings_assign_seat
  BEFORE INSERT OR UPDATE OF status, class_id ON public.class_bookings
  FOR EACH ROW EXECUTE FUNCTION public.class_bookings_assign_seat();

DROP TRIGGER IF EXISTS trg_class_bookings_sync_class ON public.class_bookings;
CREATE TRIGGER trg_class_bookings_sync_class
  AFTER INSERT OR UPDATE OF status, class_id OR DELETE ON public.class_bookings
  FOR EACH ROW EXECUTE FUNCTION public.class_bookings_sync_class();

-- current_enrolled is derived; bring every class into line once.
UPDATE public.classes c
   SET current_enrolled = (SELECT count(*) FROM public.class_bookings b
                            WHERE b.class_id = c.id AND b.status = 'confirmed')
 WHERE coalesce(c.current_enrolled, -1) <> (SELECT count(*) FROM public.class_bookings b
                                            WHERE b.class_id = c.id AND b.status = 'confirmed');

COMMENT ON FUNCTION public.class_bookings_assign_seat() IS
  'Migration 188: a booking that asks for a seat is confirmed while the class has '
  'one (coalesce(max_capacity, 20)) and waitlisted when full, counted over every '
  'booking under a lock on the class row. A held confirmed seat is never demoted.';
COMMENT ON FUNCTION public.class_bookings_sync_class() IS
  'Migration 188: on a released confirmed seat, promote the earliest waitlisted '
  'bookings while seats are free (and notify them); recompute current_enrolled.';

COMMIT;
