-- ═══════════════════════════════════════════════════════════════════════════
-- 169 · GUARDIAN STATE AND EMERGENCY DISABLEMENT — owner decision B-17 option 1
--
-- B-17 asked what produces Guardian runtime telemetry. The approved answer is the
-- SMALLEST increment: the state store and the emergency-disablement control, and
-- NOT the action queue or an evaluation producer, which stay P7-gated.
--
-- THE VOCABULARY IS NOT INVENTED. `A5` and Build Spec §5 fix it exactly:
--   "Persistent Guardian state: Active / Monitoring / Degraded / Disabled."
-- Those four strings are the CHECK below, spelled as the specification spells them.
-- This is the opposite of `approval_status` (§141) and `events.status` (§142),
-- where no tracked source enumerated the values and nothing was built.
--
-- WHY `A10` MAKES THIS A PRODUCT REQUIREMENT RATHER THAN A GUARDIAN FEATURE:
-- "Guardian must not hold admin authority; emergency disablement is a product
-- requirement." The control exists so a human can stop the Guardian. It therefore
-- belongs to the Admin layer and is gated by the approved matrix —
-- admin_can('AI Guardian','manage'), which the matrix grants to trust_lead alone.
-- THE GUARDIAN ITSELF CANNOT REACH IT: the RPC requires auth.uid() and an Admin
-- role assignment, and no agent holds either.
--
-- THE TABLE STARTS EMPTY, DELIBERATELY. Seeding 'Active' would assert that a
-- Guardian is running when no runtime exists — a claim this system cannot make.
-- "No state has ever been set" is the truth today, and the read surface returns
-- zero rows, which is an A11 state the approved design already defines. The first
-- write is the first time a human sets it.
--
-- SINGLETON BY CONSTRUCTION: `id boolean PRIMARY KEY CHECK (id)` admits exactly
-- one row, so there can never be two Guardian states to disagree about.
--
-- WHAT THIS IS NOT:
--   · not the action queue — "Actions awaiting human approval" needs an action
--     shape nothing defines; AI Guardian/Approve stays registered non-operational;
--   · not policy_evaluation — its home is ruled (observability_events) and no
--     producer exists; unchanged here;
--   · not a Guardian-written surface — only the Admin layer writes, and only
--     through the RPC;
--   · not a security control. "Security controls remain independent of the AI
--     Guardian" (Build Spec §12), and nothing here touches the Security area.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.guardian_state (
  id            boolean PRIMARY KEY DEFAULT true CHECK (id),
  state         text NOT NULL,
  reason        text,
  set_by        uuid REFERENCES public.user_profiles(id),
  set_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT guardian_state_state_check
    CHECK (state = ANY (ARRAY['Active'::text, 'Monitoring'::text,
                              'Degraded'::text, 'Disabled'::text]))
);

COMMENT ON TABLE public.guardian_state IS
  'V5 §150 · the Guardian state A5 and Build Spec §5 specify — Active / Monitoring '
  '/ Degraded / Disabled. Singleton: id is a boolean primary key CHECKed true, so '
  'exactly one row can exist. Starts EMPTY because seeding a state would assert a '
  'Guardian runtime that does not exist; zero rows is the A11 state. Written only '
  'through admin_set_guardian_state(), never by an agent.';

ALTER TABLE public.guardian_state ENABLE ROW LEVEL SECURITY;

-- Read follows the area's View grant, as 163 did for the registry.
DROP POLICY IF EXISTS "admin layer reads guardian state" ON public.guardian_state;
CREATE POLICY "admin layer reads guardian state" ON public.guardian_state
  FOR SELECT TO authenticated USING (public.admin_can('AI Guardian', 'view'));

-- NO write policy. The only writer is the SECURITY DEFINER RPC below, so the
-- authorization and the audit cannot be bypassed by writing the table directly.
REVOKE ALL ON TABLE public.guardian_state FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON TABLE public.guardian_state TO authenticated;

-- ── the control ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_guardian_state(
  p_state  text,
  p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_old text;
  v_ps  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.admin_can('AI Guardian', 'manage') THEN
    RAISE EXCEPTION 'not authorized: AI Guardian/manage is required' USING ERRCODE = '42501';
  END IF;
  IF p_state IS NULL OR p_state NOT IN ('Active', 'Monitoring', 'Degraded', 'Disabled') THEN
    RAISE EXCEPTION 'unknown Guardian state: % (A5 fixes Active/Monitoring/Degraded/Disabled)', p_state
      USING ERRCODE = '22023';
  END IF;
  p_reason := nullif(btrim(coalesce(p_reason, '')), '');
  -- Disabling the Guardian is the one transition a reader will always want
  -- explained, so it is the one that requires a reason.
  IF p_state = 'Disabled' AND p_reason IS NULL THEN
    RAISE EXCEPTION 'disabling the Guardian requires a reason' USING ERRCODE = '22023';
  END IF;

  SELECT state INTO v_old FROM public.guardian_state WHERE id;

  INSERT INTO public.guardian_state (id, state, reason, set_by, set_at)
  VALUES (true, p_state, p_reason, v_uid, now())
  ON CONFLICT (id) DO UPDATE
    SET state = EXCLUDED.state, reason = EXCLUDED.reason,
        set_by = EXCLUDED.set_by, set_at = EXCLUDED.set_at;

  IF v_old IS NOT DISTINCT FROM p_state THEN
    RETURN;                              -- no transition; nothing to audit
  END IF;

  -- A6: admin actions are delta-bearing, and a Guardian state is NOT personal
  -- data, so the before/after pair is recorded in full — the same reasoning
  -- admin_set_user_role applies to `role`, and the opposite of the name writer in
  -- §141, where the values would have re-identified a pseudonymous subject.
  v_ps := public.audit_mint_pseudonym(v_uid);
  PERFORM public.audit_record_event(
    p_action            => 'guardian_state.set',
    p_category          => 'admin_action',
    p_outcome           => 'success',
    p_subject_pseudonym => v_ps,
    p_delta             => jsonb_build_object(
                             'before', jsonb_build_object('state', v_old),
                             'after',  jsonb_build_object('state', p_state)),
    p_changed_columns   => ARRAY['state']);

  RAISE LOG 'admin_set_guardian_state: % set Guardian % -> %', v_uid, coalesce(v_old, '(unset)'), p_state;
END;
$$;

ALTER FUNCTION public.admin_set_guardian_state(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.admin_set_guardian_state(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_guardian_state(text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_set_guardian_state(text, text) IS
  'V5 §150 · the emergency Guardian disablement control A10 names as a product '
  'requirement. Gated on admin_can(''AI Guardian'',''manage''), which the approved '
  'matrix grants to trust_lead alone. Requires auth.uid(), so no agent can reach '
  'it. Disabling requires a reason. Records the transition as an admin_action with '
  'a full before/after delta — a Guardian state is not personal data.';
