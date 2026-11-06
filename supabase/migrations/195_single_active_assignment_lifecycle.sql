-- Migration 195. A client has ONE active workout-programme assignment: when an
-- authorized writer makes a new one active, the client's other active assignments
-- become 'replaced' in the same statement; and a former coach can retire their own
-- stale assignment when the client already has another valid active programme.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 190 (assignment
-- policies), 193 (_api_caller) and 194. Independent of 191. Verified only on a
-- local replay (supabase/tests/local/assignment_lifecycle_replay.sh and
-- assignment_lifecycle_concurrency.sh).
--
-- Owner decisions 2026-10-26 (implementation target, not recorded governance):
-- enforce one active assignment per client during a legitimate assignment change;
-- mark prior active assignments 'replaced' atomically; let a former coach retire
-- only their own historical assignment, never the client's only active programme;
-- reuse the existing 'replaced' status; do not restore client-side writes;
-- preserve member self-plan generation, regeneration and deactivation.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE DEFECT (confirmed on the local 000-194 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
-- When a client switches coach, the new coach's assignProgram first marks the
-- client's active rows 'replaced' — but RLS shows that coach only their OWN rows
-- (001/185/190), so the former coach's row stays active; then it inserts a second
-- active row. Nothing can repair it through the API: the former coach's write arm
-- needs an active relationship (185/190), the client has no write arm (190), and
-- the new coach cannot see the row. The client's own reads —
-- CoachProgramService.getMyAssignedProgram and coach_ecosystem_provider —
-- select status = 'active' with .maybeSingle(), which errors on two rows.
-- (Pre-existing since 001; 185/190 removed the last API paths that could clean up.)
-- The same happens when a coach assigns over a member's active self plan, which no
-- coach can see.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- WHAT CHANGES
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. _assignment_single_active (BEFORE INSERT OR UPDATE, named to fire LAST, after
--    the scope, ownership and clearance triggers): when a row BECOMES active for a
--    client (insert, reactivation, or a change of client), it takes a per-client
--    transaction-scoped advisory lock and marks every OTHER active row of that
--    client 'replaced'. SECURITY DEFINER, so it reaches rows the writer cannot see
--    (another coach's, a self plan) — it returns nothing and reads nothing back.
--    If a later check (RLS WITH CHECK) refuses the row, the whole statement rolls
--    back, the replacement with it.
--    RECURSION: its own UPDATE makes rows non-active; every trigger on the table
--    (194 scope, 192/193 ownership, 189/193 clearance, this one) returns at once
--    for a row that is not becoming active.
--    RACE: two concurrent activations for one client serialize on the advisory
--    lock. Under READ COMMITTED (the PostgREST/Supabase default) each statement in
--    the trigger takes a fresh snapshot, so the second one, after waiting, sees the
--    first one's committed row and replaces it — one active row remains. Under
--    SERIALIZABLE, PostgreSQL's predicate locking aborts one of them instead. Under
--    REPEATABLE READ the second snapshot could not see the first row, so an
--    activation there is REFUSED (ASSIGNMENT_ISOLATION_UNSUPPORTED) — no current
--    path uses that level.
-- 2. retire_my_assignment(p_assignment_id): a former coach marks THEIR OWN active
--    assignment 'replaced' — only when they no longer actively coach that client,
--    and only when the client has ANOTHER VALID active assignment (a member self
--    plan, or one written by a coach the client is actively with). It changes one
--    column of one row, returns nothing, and serializes on the same lock. Every
--    refusal — no such row, not yours, not active, still your client, or the
--    client's only valid programme — is the same ASSIGNMENT_NOT_RETIRABLE.
--    It grants nothing else: no read of the client's programme, assessment,
--    clearance or profile, and no generation, regeneration or replacement right.
--
-- NOT A UNIQUE INDEX, on purpose: a partial unique index on (client_id) WHERE
-- status = 'active' cannot be created while legacy duplicate rows exist (they do
-- wherever a client has switched coach), and resolving them would mean choosing,
-- at apply time, which programme a client keeps — a data decision not taken here.
-- Legacy duplicates are resolved by the next activation for that client, or by
-- the former coach's retire_my_assignment. A read-only count before applying:
--   select client_id, count(*) from workout_program_assignments
--    where status = 'active' group by 1 having count(*) > 1;
--
-- RESIDUAL: a successful or refused retirement tells a former coach whether the
-- client currently has another valid programme (that they have a new coach or a
-- self plan) — inherent in the owner's rule; no health or clearance information.
--
-- Posture: every function pins search_path; the helper and trigger function are
-- revoked from PUBLIC, anon and authenticated; retire_my_assignment is executable
-- by authenticated only.

BEGIN;

-- One lock per client, held to the end of the transaction.
CREATE OR REPLACE FUNCTION public._assignment_client_lock(p_client uuid)
RETURNS void
LANGUAGE sql
VOLATILE
SET search_path = public, pg_temp
AS $$
  SELECT pg_catalog.pg_advisory_xact_lock(
           pg_catalog.hashtextextended('workout_program_assignments:active:' || p_client::text, 0));
$$;

CREATE OR REPLACE FUNCTION public._assignment_single_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM 'active' OR NEW.client_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- Already active for the same client: not an activation.
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND OLD.client_id IS NOT DISTINCT FROM NEW.client_id THEN
    RETURN NEW;
  END IF;
  IF current_setting('transaction_isolation') = 'repeatable read' THEN
    RAISE EXCEPTION 'ASSIGNMENT_ISOLATION_UNSUPPORTED: an assignment cannot be made active in a REPEATABLE '
      'READ transaction (use READ COMMITTED or SERIALIZABLE). Nothing was assigned.'
      USING ERRCODE = '0A000';
  END IF;
  PERFORM public._assignment_client_lock(NEW.client_id);
  -- A fresh snapshot (READ COMMITTED), taken after the lock: sees any activation
  -- that committed while this one waited.
  UPDATE public.workout_program_assignments
     SET status = 'replaced'
   WHERE client_id = NEW.client_id
     AND status = 'active'
     AND id IS DISTINCT FROM NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS single_active_assignment ON public.workout_program_assignments;
CREATE TRIGGER single_active_assignment
  BEFORE INSERT OR UPDATE ON public.workout_program_assignments
  FOR EACH ROW EXECUTE FUNCTION public._assignment_single_active();

CREATE OR REPLACE FUNCTION public.retire_my_assignment(p_assignment_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := public._api_caller();
  v_client uuid;
  v_done   boolean := false;
BEGIN
  IF v_caller IS NOT NULL THEN
    SELECT client_id INTO v_client
      FROM public.workout_program_assignments
     WHERE id = p_assignment_id AND coach_id = v_caller;
    IF v_client IS NOT NULL THEN
      PERFORM public._assignment_client_lock(v_client);
      UPDATE public.workout_program_assignments a
         SET status = 'replaced'
       WHERE a.id = p_assignment_id
         AND a.coach_id = v_caller
         AND a.status = 'active'
         -- a FORMER coach only: a current coach uses the normal assignment path
         AND NOT EXISTS (SELECT 1 FROM public.coach_client_relationships r
                          WHERE r.coach_id = v_caller AND r.client_id = a.client_id AND r.status = 'active')
         -- never the client's only valid programme
         AND EXISTS (SELECT 1 FROM public.workout_program_assignments b
                      WHERE b.client_id = a.client_id AND b.id <> a.id AND b.status = 'active'
                        AND (b.coach_id IS NULL
                             OR EXISTS (SELECT 1 FROM public.coach_client_relationships r
                                         WHERE r.coach_id = b.coach_id AND r.client_id = b.client_id
                                           AND r.status = 'active')));
      v_done := FOUND;
    END IF;
  END IF;
  IF NOT v_done THEN
    RAISE EXCEPTION 'ASSIGNMENT_NOT_RETIRABLE: this assignment cannot be retired. Nothing was changed.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public._assignment_client_lock(uuid)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._assignment_single_active()      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.retire_my_assignment(uuid)       FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retire_my_assignment(uuid)    TO authenticated;

COMMENT ON FUNCTION public.retire_my_assignment(uuid) IS
  'A former coach retires their own active assignment (status replaced) when the client '
  'already has another valid active programme (195). Grants no other access. Any refusal '
  'is ASSIGNMENT_NOT_RETIRABLE.';

COMMIT;
