-- ═══════════════════════════════════════════════════════════════════════════
-- 161 · SUPPORT'S USERS-UPDATE WRITE PATH — owner decision B-2 (second half),
--        2026-10-05
--
-- The approved matrix grants `Users · Update` to `support` ALONE -- the only
-- non-View grant outside Trust and Operations. V5 §129.4's B-2 parked it because
-- which columns Support may write is a security decision, and `user_profiles`
-- carries medical_conditions, parq_answers, injury_*, date_of_birth, weight_kg and
-- the rest. enforce_profile_privilege() (115) already blocks nine columns, but
-- EVERYTHING ELSE was technically writable, PHI included.
--
-- Owner decision: NAME CORRECTIONS ONLY -- first_name, last_name.
--
-- WHY AN RPC AND NOT A COLUMN-LIMITED UPDATE POLICY. A policy constrains WHICH ROWS
-- a caller may update, not WHICH COLUMNS. PostgreSQL has column-level privileges,
-- but they are granted per role, and `authenticated` is one role shared by every
-- member -- so a column grant cannot express "support may write these two columns".
-- A SECURITY DEFINER function CAN: the writable set is the function body, enforced
-- server-side, and the UI cannot widen it. No UI-only authorization.
--
-- WHY THE AUDIT DELTA CARRIES NO VALUES, DIVERGING FROM admin_set_user_role().
-- That function records before/after `role` in the delta, which is correct: a role
-- is not identifying. A NAME IS. The audit population pseudonymises its subject
-- precisely so an audit record does not identify the person it concerns, and
-- writing "before: Jane Smith, after: Jane Jones" into that population would hand
-- back the identity the pseudonym removes -- defeating A12 through the audit trail
-- rather than through a read path. So this emits `changed_columns` (151's
-- signature) and NO delta: the record proves WHAT was changed and by whom, without
-- re-identifying WHO it was changed for.
--
-- Authorization is admin_can('Users','update') ONLY. It deliberately does not fall
-- back to is_admin(): this function is new, so gating it narrowly takes nothing
-- away from anyone, and widening it would grant a capability the matrix assigns to
-- `support` alone.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_update_user_name(
  p_user_id    uuid,
  p_first_name text,
  p_last_name  text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_old_first text;
  v_old_last  text;
  v_changed   text[] := ARRAY[]::text[];
  v_pseudonym uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('Users', 'update') THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  -- Trim first, so '   ' cannot pass as a name.
  p_first_name := nullif(btrim(coalesce(p_first_name, '')), '');
  p_last_name  := nullif(btrim(coalesce(p_last_name,  '')), '');
  IF p_first_name IS NULL AND p_last_name IS NULL THEN
    RAISE EXCEPTION 'nothing to update: supply a first or last name' USING ERRCODE = '22023';
  END IF;
  IF length(p_first_name) > 100 OR length(p_last_name) > 100 THEN
    RAISE EXCEPTION 'name exceeds 100 characters' USING ERRCODE = '22023';
  END IF;

  SELECT first_name, last_name INTO v_old_first, v_old_last
    FROM public.user_profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such user' USING ERRCODE = '22023';
  END IF;

  -- COALESCE means a NULL argument leaves that column alone, so this function can
  -- never blank a name it was not asked to change.
  UPDATE public.user_profiles
     SET first_name = coalesce(p_first_name, first_name),
         last_name  = coalesce(p_last_name,  last_name),
         updated_at = now()
   WHERE id = p_user_id;

  IF p_first_name IS NOT NULL AND p_first_name IS DISTINCT FROM v_old_first THEN
    v_changed := v_changed || 'first_name';
  END IF;
  IF p_last_name IS NOT NULL AND p_last_name IS DISTINCT FROM v_old_last THEN
    v_changed := v_changed || 'last_name';
  END IF;

  -- A no-op write is not an admin action worth recording; recording it would pad
  -- the Security card's "permission changes" count with events that changed nothing.
  IF array_length(v_changed, 1) IS NULL THEN
    RETURN;
  END IF;

  v_pseudonym := public.audit_mint_pseudonym(p_user_id);

  PERFORM public.audit_record_event(
    p_action            => 'user_profiles.name.set',
    p_category          => 'admin_action',
    p_outcome           => 'success',
    p_subject_pseudonym => v_pseudonym,
    p_delta             => NULL,          -- values are identifying; see the header
    p_changed_columns   => v_changed
  );

  RAISE LOG 'admin_update_user_name: % updated % (%)',
    auth.uid(), p_user_id, array_to_string(v_changed, ',');
END;
$$;

ALTER FUNCTION public.admin_update_user_name(uuid, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_update_user_name(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_name(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_update_user_name(uuid, text, text) IS
  'V5 §134 · Support''s Users-Update write path. Owner decision B-2: NAME '
  'CORRECTIONS ONLY. Gated on admin_can(''Users'',''update''), which the approved '
  'matrix grants to `support` alone. Writes first_name and last_name and nothing '
  'else -- the writable set is this function body, not a UI convention. Emits an '
  'admin_action audit event carrying changed_columns and NO delta, because names '
  'are identifying and a pseudonymised audit population must not carry them.';
