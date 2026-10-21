-- Migration 150 — P2 · `A6`'s before/after delta, and the admin_action delta 147 could not record.
--
-- A6 §8.9 is ANSWERED — "NON-PHI DELTAS ONLY. Before/after values are captured for
-- delta-bearing categories that carry no PHI. PHI-CORRECTION DELTAS ARE EXCLUDED."
-- The Event population had nowhere to put one, so the ruling was unimplementable
-- and migration 147's admin_action Event recorded no delta at all.
--
-- A6 also enumerates exactly which categories this reaches. Quoted, not summarised:
--
--   "Of A2's 14 IN categories, NINE CARRY A DELTA: PHI corrections · admin actions
--    · billing/entitlement changes · financial/charge trail · relationship changes
--    · incidents · agent actions (writing ones only) · export/deletion events ·
--    storage/media (the revocation/replacement arm). FIVE ARE OCCURRENCES WITH NO
--    DELTA: PHI reads · authorization denials · authentication · observability
--    audit events · control evidence. Under this ruling, PHI CORRECTIONS ARE THE
--    EXCLUDED CASE; the others carry role, tier, commission, payout, status or
--    Stripe-identifier values — NOT PHI."
--
-- Both halves are enforced below as constraints rather than left to callers: the
-- five occurrence categories may carry no delta, and phi_correction may carry none
-- either, because A6 excludes it by name.
--
-- WHAT A6 DELIBERATELY DOES NOT SETTLE, and is therefore NOT implemented here:
--   "Whether a PHI-correction record still carries the CHANGED-COLUMN NAME SET
--    (metadata, not values) is NOT DECIDED — 'changed-column names only' was a
--    separate option and was not the one chosen."
-- So a phi_correction Event carries no delta and no name set. If the owner later
-- adopts the name-set option, the CHECK below is what must be amended, and A6's
-- own warning applies: "if A6 is ever widened to PHI deltas, the conflict
-- [A11 freeze vs A12 anonymisation] returns unchanged."

ALTER TABLE public.audit_events ADD COLUMN IF NOT EXISTS delta jsonb;

COMMENT ON COLUMN public.audit_events.delta IS
  'A6 §8.9 — before/after capture, NON-PHI ONLY. Shape {"before":…,"after":…}, the pair '
  '094_continuous_coaching_engine.sql:125-127 already uses. Permitted only for the nine '
  'delta-bearing categories A6 enumerates, and NEVER for phi_correction, which A6 excludes by '
  'name. Frozen with the rest of the row: it is an occurrence fact, not an annotation, so A11''s '
  '"any future writable annotation field must be explicitly classified" does not apply to it.';

-- A6's five occurrence categories carry no delta, and phi_correction is the
-- excluded sixth. Enforced, so a caller cannot put PHI in the ledger by
-- mislabelling a record.
ALTER TABLE public.audit_events ADD CONSTRAINT audit_events_delta_category_check
  CHECK (
    delta IS NULL
    OR category NOT IN ('phi_read', 'authorization_denial', 'authentication',
                        'observability_audit', 'control_evidence', 'phi_correction')
  );

-- ── the write path learns to carry it ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_record_event(
  p_action            text,
  p_category          text,
  p_outcome           text,
  p_subject_pseudonym uuid  DEFAULT NULL,
  p_actor_id          uuid  DEFAULT NULL,
  p_actor_provenance  text  DEFAULT NULL,
  p_correlation_id    uuid  DEFAULT NULL,
  p_delta             jsonb DEFAULT NULL
) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid;
  v_provenance text;
BEGIN
  IF v_uid IS NOT NULL THEN
    v_actor := v_uid; v_provenance := 'grounded';
  ELSIF p_actor_id IS NOT NULL THEN
    v_actor := p_actor_id; v_provenance := 'asserted';
  ELSE
    v_actor := NULL; v_provenance := 'system';
  END IF;
  IF p_actor_provenance = 'asserted' AND v_provenance = 'grounded' THEN
    v_provenance := 'asserted';
  END IF;

  INSERT INTO public.audit_events
    (actor_id, subject_pseudonym, action, outcome, actor_provenance, category, correlation_id, delta)
  VALUES
    (v_actor, p_subject_pseudonym, p_action, p_outcome, v_provenance, p_category, p_correlation_id, p_delta);

  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_record_event failed (action=%, category=%): % [%]',
    p_action, p_category, SQLERRM, SQLSTATE;
  RETURN false;
END;
$$;
ALTER FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid, jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid, jsonb) TO authenticated, service_role;

-- The 7-argument form is dropped: PostgREST resolves overloads BY PARAMETER NAME
-- (PGRST203), so leaving both would make every call ambiguous.
DROP FUNCTION IF EXISTS public.audit_record_event(text, text, text, uuid, uuid, text, uuid);

-- ── 147's emission gains the delta A6 says it carries ─────────────────────
-- A6 lists "admin actions" among the nine, and names the value they carry: "role".
-- 147 already had the old value in hand and discarded it, because there was no
-- column. Everything else about this function is carried through unchanged --
-- SECURITY DEFINER, the pinned search_path, the is_admin() wrapper, the
-- privileged_role_write envelope and the vocabulary.
CREATE OR REPLACE FUNCTION public.admin_set_user_role(target_user uuid, new_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_role  text;
  v_pseudonym uuid;
BEGIN
  IF (SELECT auth.uid()) IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;
  IF new_role NOT IN ('client', 'coach', 'vendor', 'admin', 'content_manager',
                      'trust_operator', 'erasure_executor') THEN
    RAISE EXCEPTION 'unknown role: %', new_role USING ERRCODE = '22023';
  END IF;
  SELECT role INTO v_old_role FROM public.user_profiles WHERE id = target_user;
  IF v_old_role IS NULL THEN
    RAISE EXCEPTION 'no such user' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('circle12.privileged_role_write', 'on', true);
  UPDATE public.user_profiles SET role = new_role, updated_at = now()
   WHERE id = target_user;
  PERFORM set_config('circle12.privileged_role_write', 'off', true);

  v_pseudonym := public.audit_mint_pseudonym(target_user);

  PERFORM public.audit_record_event(
    p_action            => 'user_profiles.role.set',
    p_category          => 'admin_action',
    p_outcome           => 'success',
    p_subject_pseudonym => v_pseudonym,
    -- A6: admin actions are delta-bearing and the value is `role`. Non-PHI, so
    -- the before/after pair is permitted and required.
    p_delta             => jsonb_build_object('before', jsonb_build_object('role', v_old_role),
                                              'after',  jsonb_build_object('role', new_role))
  );

  RAISE LOG 'admin_set_user_role: % set % to % (was %)',
    auth.uid(), target_user, new_role, v_old_role;
END;
$$;
