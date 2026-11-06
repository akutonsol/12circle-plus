-- Migration 193. The two assignment-time guards (189's clearance, 192's ownership)
-- no longer step aside for a caller they cannot vouch for: a third-party caller is
-- refused outright, with one generic message, in every execution context.
--
-- AUTHORED, NOT APPLIED. Not declared in supabase/expected_applied.json (a
-- protected edit the owner has not authorized). Depends on 189 and 192.
-- Independent of 191. Verified only on a local replay
-- (supabase/tests/local/assignment_caller_context_replay.sh).
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE DEFECT (confirmed on a local 000-192 replay, rolled back)
-- ═══════════════════════════════════════════════════════════════════════════
-- Both triggers "left to RLS" a caller who was neither the client nor their active
-- coach (189), or who named a different coach (192), so their errors could not be
-- used as an oracle. But RLS does not run for every writer:
--   * the service role bypasses RLS. 189 keyed the deferral on auth.uid(), so a
--     service-role write that CARRIED an unrelated user's claims was deferred and
--     then never checked: an engine-selected programme was assigned to an injured
--     client. (192 had the same flaw — finding O08 — and keyed on the session role
--     instead.)
--   * a SECURITY DEFINER function runs its statements as its owner, so RLS does not
--     apply — while auth.uid() is still the caller and current_setting('role') still
--     reads 'authenticated'. A definer function writing an assignment for an
--     unrelated caller bypassed BOTH guards: 189's clearance (engine programme ->
--     injured client) and 192's ownership (coach K + coach O's programme), even
--     after 192's role-based fix. No current definer function does this
--     (generate_client_plan writes the caller's own coach-less assignment), so the
--     hole was latent, not reachable from the app.
-- Inside a SECURITY DEFINER trigger nothing reliably says whether RLS will apply to
-- the statement, so "defer to RLS" cannot be made safe. Refusing can.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE FIX
-- ═══════════════════════════════════════════════════════════════════════════
--   * 189 (_engine_assignment_guard): when the row would make an engine_selected
--     programme active, a signed-in caller who is neither the client nor the
--     client's active coach is REFUSED with ASSIGNMENT_NOT_AUTHORIZED (42501),
--     before and regardless of clearance — so the message is identical for a
--     cleared and an uncleared client and reveals nothing about either.
--   * 192 (_assignment_program_ownership): a signed-in caller naming a coach other
--     than themselves is REFUSED with the same ASSIGNMENT_NOT_AUTHORIZED, before
--     and regardless of ownership — so it reveals nothing about who owns what.
--   * Who counts as "signed in" is decided by _api_caller(): the request claims of
--     an API session (login role cannot bypass RLS — PostgREST's authenticator,
--     whatever role it then SETs). A trusted owner session (login role is a
--     superuser or bypasses RLS: migrations, SQL-editor maintenance, fixtures) has
--     no caller, so stale claims there neither exempt nor refuse a write.
--   * A call with NO caller (service role without user claims, a trusted owner
--     session) is fully checked, as before: clearance and ownership apply.
--   * Everything else in both functions is restated unchanged: not retroactive,
--     replace/deactivate never blocked, self-plan assignments (coach-less) checked
--     against a coach-less programme.
-- CONSEQUENCE: tooling that writes assignments with the service key while
-- forwarding some OTHER user's claims is refused for engine programmes and for
-- coach-named rows; it must write without claims, or as the client / their active
-- coach. Signed-in clients and coaches see ASSIGNMENT_NOT_AUTHORIZED where they
-- previously saw RLS's "new row violates row-level security policy" — only for an
-- engine-selected programme (189) or a row naming another coach (192); other
-- refusals still come from RLS. The 189 refusal, raised only for engine-selected
-- programmes, still tells a third party that the programme id they supplied is
-- engine-selected — programme-level, not client-level, information.
--
-- Posture: both functions stay SECURITY DEFINER with search_path pinned and are
-- revoked from PUBLIC, anon and authenticated (restated).

BEGIN;

-- The signed-in caller as the API presents them, or NULL. A session whose LOGIN
-- role is a superuser or bypasses RLS (the database owner: migrations, SQL-editor
-- maintenance, seed and test fixtures) is trusted outright and has no "caller":
-- stale request.jwt.claims left in such a session must neither exempt a write from
-- the checks nor refuse it as a third party. API traffic logs in as a role that
-- cannot bypass RLS (PostgREST's `authenticator`) and then SETs ROLE — including to
-- service_role — so its claims are what identify the caller there. session_user is
-- unaffected by SECURITY DEFINER, so this holds inside definer functions too.
CREATE OR REPLACE FUNCTION public._api_caller()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
                            WHERE r.rolname = session_user AND (r.rolsuper OR r.rolbypassrls))
              THEN NULL
              ELSE auth.uid() END;
$$;

CREATE OR REPLACE FUNCTION public._engine_assignment_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_engine boolean;
BEGIN
  IF NEW.status IS DISTINCT FROM 'active' THEN
    RETURN NEW;
  END IF;
  -- Not retroactive: an assignment that stays active on the same programme and
  -- client (a current_week update, say) is not rechecked.
  IF TG_OP = 'UPDATE' AND OLD.status = 'active'
     AND NEW.program_id = OLD.program_id AND NEW.client_id = OLD.client_id THEN
    RETURN NEW;
  END IF;
  SELECT engine_selected INTO v_engine FROM public.workout_programs WHERE id = NEW.program_id;
  IF NOT coalesce(v_engine, false) THEN
    RETURN NEW;
  END IF;
  -- 193: a caller who is neither the client nor their active coach is refused, not
  -- deferred to RLS (which the service role and definer functions do not get).
  -- Raised before clearance is evaluated, so it says nothing about the client.
  -- Only an API session's claims identify a caller (_api_caller); a trusted owner
  -- session is checked fully below, as if no one were signed in.
  IF public._api_caller() IS NOT NULL AND public._api_caller() IS DISTINCT FROM NEW.client_id
     AND NOT public.is_active_coach_of(NEW.client_id) THEN
    RAISE EXCEPTION 'ASSIGNMENT_NOT_AUTHORIZED: you cannot assign a programme to this client. '
      'Nothing was assigned.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT (public._engine_client_clearance(NEW.client_id) ->> 'cleared')::boolean THEN
    RAISE EXCEPTION 'ENGINE_CLIENT_NOT_CLEARED: programme % holds engine-selected training and this '
      'client is not cleared for engine-generated training (completed intake, no reported injury, '
      'complete low-risk PAR-Q, no medical advice against exercise). Nothing was assigned.',
      NEW.program_id
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._assignment_program_ownership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid;
  v_found boolean;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.program_id IS NOT DISTINCT FROM OLD.program_id
     AND NEW.coach_id   IS NOT DISTINCT FROM OLD.coach_id
     AND NOT (NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active') THEN
    RETURN NEW;   -- replacing / deactivating / week updates are never blocked
  END IF;
  -- 193: a signed-in caller writing a row for ANOTHER coach is refused, not deferred
  -- to RLS (which the service role and definer functions do not get). Raised before
  -- ownership is evaluated, so it says nothing about who owns the programme.
  IF public._api_caller() IS NOT NULL AND NEW.coach_id IS NOT NULL
     AND NEW.coach_id IS DISTINCT FROM public._api_caller() THEN
    RAISE EXCEPTION 'ASSIGNMENT_NOT_AUTHORIZED: you cannot write an assignment for another coach. '
      'Nothing was assigned.'
      USING ERRCODE = '42501';
  END IF;
  SELECT coach_id, true INTO v_owner, v_found FROM public.workout_programs WHERE id = NEW.program_id;
  IF NOT coalesce(v_found, false) OR v_owner IS DISTINCT FROM NEW.coach_id THEN
    RAISE EXCEPTION 'ASSIGNMENT_PROGRAM_NOT_OWNED: an assignment must name a programme owned by its '
      'coach (or, for a self-plan assignment, a coach-less programme). Nothing was assigned.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._api_caller()                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._engine_assignment_guard()       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._assignment_program_ownership()  FROM PUBLIC, anon, authenticated;

COMMIT;
