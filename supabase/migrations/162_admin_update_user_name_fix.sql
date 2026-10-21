-- ═══════════════════════════════════════════════════════════════════════════
-- 162 · FIXES A DEFECT IN 161 — the function could never succeed
--
-- 161 built its changed-columns array with
--
--     v_changed := v_changed || 'first_name';
--
-- PostgreSQL resolves `||` here through `anyarray || anyarray`, so it tries to cast
-- the untyped literal 'first_name' to text[] and raises
--
--     22P02  malformed array literal: "first_name"
--
-- EVERY call failed with 400 -- including the authorized `support` path, which is
-- the only caller the owner's decision creates. The authorization half was correct
-- from the first run (unassigned, viewer and trust_lead were all refused 403); the
-- function simply could not complete its audit emission, and because the emission
-- happens AFTER the UPDATE, the whole statement rolled back and no name was ever
-- written. Nothing was half-applied.
--
-- `array_append` is unambiguous: its signature is (anycompatiblearray, anycompatible),
-- so the literal resolves to text rather than text[].
--
-- Forward-only, like 157 and 158. 161 is already applied to QA, so editing it would
-- leave QA holding the broken function while a replay from empty produced the fixed
-- one -- exactly the divergence check-migration-hygiene.sh exists to prevent.
--
-- The function is otherwise IDENTICAL to 161's, including the owner's decision that
-- only first_name and last_name are writable and the A12 reasoning for emitting
-- changed_columns with no delta.
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
    v_changed := array_append(v_changed, 'first_name');
  END IF;
  IF p_last_name IS NOT NULL AND p_last_name IS DISTINCT FROM v_old_last THEN
    v_changed := array_append(v_changed, 'last_name');
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
