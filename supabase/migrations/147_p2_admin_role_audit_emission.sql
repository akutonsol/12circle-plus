-- Migration 147 — P2 · `admin_set_user_role()` becomes assignable and AUDITED.
--
-- Two defects, one authorized closure. Both are determined by existing rulings;
-- neither is a new decision.
--
-- ── 1 · AN INTEGRATION DEFECT MIGRATION 142 INTRODUCED ──────────────────────
-- 142 added `trust_operator` and `erasure_executor` to `user_profiles_role_check`
-- (§8.18·Q1 TWO ROLES; A12 ruling 6 forbids service_role as the executor). It did
-- NOT extend `admin_set_user_role()`, whose own vocabulary list is
-- ('client','coach','vendor','admin','content_manager'). That function is, in its
-- own words, "the only client-reachable path that changes user_profiles.role", so
-- the two roles the programme just created were UNASSIGNABLE by any sanctioned
-- route -- the table would accept them and the only door refused them (22023).
-- Caught by reading 115 against 142 rather than by a test, and recorded in V5 §79.
--
-- ── 2 · A2's NAMED, UNCLOSED AUDIT GAP ──────────────────────────────────────
-- §8.3's consequences name this function specifically:
--   "admin_set_user_role() is unaudited. Admin actions are IN, and the server-log
--    ruling is NO. The repository's single sanctioned privilege-escalation
--    primitive (115:363) writes NO AUDIT ROW; its only record is one RAISE LOG at
--    :392 -- the only RAISE LOG in the entire migration tree. UNDER A2 THAT IS NOT
--    AN AUDIT RECORD."
-- A2 puts `admin_action` IN; A3 §8.5 gives the Event population the write path
-- "trigger + RPC + application", and this is the application arm calling the RPC.
--
-- PRESERVED DELIBERATELY, because I-MIG-03 watches for exactly this: SECURITY
-- DEFINER, `SET search_path = public, pg_temp`, the `is_admin()` authorization
-- wrapper, the `circle12.privileged_role_write` set_config envelope, and the
-- REVOKE/GRANT posture are all carried through unchanged. Nothing is stripped.
CREATE OR REPLACE FUNCTION public.admin_set_user_role(target_user uuid, new_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_role   text;
  v_pseudonym  uuid;
BEGIN
  -- auth.uid() IS NULL is the service_role / internal path, which is already
  -- trusted; every client-reachable call must prove admin.  (115, unchanged.)
  IF (SELECT auth.uid()) IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  -- The vocabulary now matches `user_profiles_role_check` as 142 left it. The two
  -- additions are not new roles invented here -- they are §8.18·Q1's two, which
  -- had no assignment path until now.
  IF new_role NOT IN ('client', 'coach', 'vendor', 'admin', 'content_manager',
                      'trust_operator', 'erasure_executor') THEN
    RAISE EXCEPTION 'unknown role: %', new_role USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_old_role FROM public.user_profiles WHERE id = target_user;
  IF v_old_role IS NULL THEN
    RAISE EXCEPTION 'no such user' USING ERRCODE = '22023';
  END IF;

  -- Definer rights do NOT clear auth.uid(), so enforce_profile_privilege would
  -- reject this write like any other. Announce the sanctioned exception for the
  -- duration of this transaction only (set_config is_local = true); the
  -- authorization decision was made above.  (115, unchanged.)
  PERFORM set_config('circle12.privileged_role_write', 'on', true);
  UPDATE public.user_profiles SET role = new_role, updated_at = now()
   WHERE id = target_user;
  PERFORM set_config('circle12.privileged_role_write', 'off', true);

  -- ── THE AUDIT ROW A2 REQUIRES ────────────────────────────────────────────
  -- Subject is a PSEUDONYM, not the target's real id: A12 ruling 2's external
  -- mapping is what makes severance anonymise the frozen Event row (V5 §78.2).
  -- Minting is a definer call and runs as this function's owner.
  v_pseudonym := public.audit_mint_pseudonym(target_user);

  -- BEST-EFFORT, and the ordering proves it: the role change is already
  -- committed above. A3 sub-ruling 4 -- "an audit-write failure MUST NOT
  -- automatically abort the audited business action". audit_record_event()
  -- swallows its own failures and returns false, so this cannot raise.
  PERFORM public.audit_record_event(
    p_action            => 'user_profiles.role.set',
    p_category          => 'admin_action',
    p_outcome           => 'success',
    p_subject_pseudonym => v_pseudonym,
    p_correlation_id    => NULL
  );

  -- The RAISE LOG is KEPT, and is not the audit record. A2 ruled a server-log
  -- line does not satisfy an audit obligation; it remains as operational
  -- breadcrumb only, alongside the row above rather than instead of it.
  RAISE LOG 'admin_set_user_role: % set % to % (was %)',
    auth.uid(), target_user, new_role, v_old_role;
END;
$$;

COMMENT ON FUNCTION public.admin_set_user_role(uuid, text) IS
  'The only client-reachable path that changes user_profiles.role. Admin-only, and since '
  'migration 147 it EMITS AN AUDIT EVENT (category admin_action) as A2 requires — §8.3 named '
  'this function as the unclosed gap: "its only record is one RAISE LOG ... under A2 that is '
  'not an audit record." The log line is kept as an operational breadcrumb, not as the audit '
  'record. The audit write is BEST-EFFORT per A3 sub-ruling 4 and is sequenced after the role '
  'change so it cannot abort it. The audited subject is recorded as a PSEUDONYM so A12 ruling '
  '2''s severance actually anonymises the frozen row. Vocabulary matches '
  'user_profiles_role_check, including §8.18·Q1''s trust_operator and erasure_executor, which '
  'had no assignment path before this migration.';
