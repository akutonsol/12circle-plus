-- Migration 151 — P2 · the four owner-approved emitters, B1–B4.
--
-- Each is implemented against the REAL mutation path traced in the repository,
-- and each reuses the sanctioned A3 mechanism (audit_record_event) rather than
-- creating a second audit channel.
--
-- ── A COLUMN B4 REQUIRES, AND WHY IT IS NOT `delta` ────────────────────────
-- A6 §8.9 excludes PHI-correction DELTAS by name, and migration 150 enforces that
-- as a CHECK. The owner's B4 decision requires the CHANGED-COLUMN NAME SET be
-- recorded. Those are different objects: A6 excludes before/after VALUES; a name
-- set is metadata. §8.9 recorded the name-set question as "NOT DECIDED" and B4
-- decides it, so the names get their own column and `delta` stays NULL for
-- phi_correction exactly as 150 requires. No PHI value can reach the ledger by
-- this route, because only `array_agg(key)` is ever written.
ALTER TABLE public.audit_events ADD COLUMN IF NOT EXISTS changed_columns text[];

COMMENT ON COLUMN public.audit_events.changed_columns IS
  'Owner decision B4 — the changed-column NAME SET, metadata only, never values. §8.9 recorded '
  'this question as "NOT DECIDED"; B4 decides it. Distinct from `delta`, which A6 excludes for '
  'phi_correction and which migration 150 constrains accordingly.';

CREATE OR REPLACE FUNCTION public.audit_record_event(
  p_action            text,
  p_category          text,
  p_outcome           text,
  p_subject_pseudonym uuid   DEFAULT NULL,
  p_actor_id          uuid   DEFAULT NULL,
  p_actor_provenance  text   DEFAULT NULL,
  p_correlation_id    uuid   DEFAULT NULL,
  p_delta             jsonb  DEFAULT NULL,
  p_changed_columns   text[] DEFAULT NULL
) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_uid uuid := auth.uid(); v_actor uuid; v_provenance text;
BEGIN
  IF v_uid IS NOT NULL THEN v_actor := v_uid; v_provenance := 'grounded';
  ELSIF p_actor_id IS NOT NULL THEN v_actor := p_actor_id; v_provenance := 'asserted';
  ELSE v_actor := NULL; v_provenance := 'system'; END IF;
  IF p_actor_provenance = 'asserted' AND v_provenance = 'grounded' THEN v_provenance := 'asserted'; END IF;

  INSERT INTO public.audit_events
    (actor_id, subject_pseudonym, action, outcome, actor_provenance, category,
     correlation_id, delta, changed_columns)
  VALUES
    (v_actor, p_subject_pseudonym, p_action, p_outcome, v_provenance, p_category,
     p_correlation_id, p_delta, p_changed_columns);
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_record_event failed (action=%, category=%): % [%]',
    p_action, p_category, SQLERRM, SQLSTATE;
  RETURN false;
END;
$$;
ALTER FUNCTION public.audit_record_event(text,text,text,uuid,uuid,text,uuid,jsonb,text[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_record_event(text,text,text,uuid,uuid,text,uuid,jsonb,text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.audit_record_event(text,text,text,uuid,uuid,text,uuid,jsonb,text[]) TO authenticated, service_role;
-- PostgREST resolves overloads BY PARAMETER NAME (PGRST203); two live forms would
-- make every call ambiguous.
DROP FUNCTION IF EXISTS public.audit_record_event(text,text,text,uuid,uuid,text,uuid,jsonb);

-- ═══ B1 · INCIDENT CREATION AUTHORITY ══════════════════════════════════════
-- OWNER DECISION B1: "Incident creation is restricted to authenticated `admin`
-- and `trust_operator` actors through the sanctioned Incident RPC/application
-- path. Clients, ordinary coaches, service_role and erasure_executor are
-- excluded." §81.2 recorded that no ruling named a creator; B1 names one.
--
-- This is the RPC arm of A3's "RPC + application" write path for population 2.
-- The case semantics of 143 are untouched: the transition-history trigger still
-- fires on every later UPDATE, and the row is still undeletable.
CREATE OR REPLACE FUNCTION public.audit_open_incident(
  p_summary            text,
  p_occurred_at        timestamptz,
  p_severity           text,
  p_scope              text  DEFAULT NULL,
  p_evidence           jsonb DEFAULT '[]'::jsonb,
  p_suspected_cause    text  DEFAULT NULL,
  p_recommended_action text  DEFAULT NULL
) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_ps  uuid;
BEGIN
  -- "authenticated admin and trust_operator actors" — so an unauthenticated or
  -- internal caller is excluded too, which is why auth.uid() must be present.
  -- service_role reaches this with auth.uid() IS NULL and is refused, as B1 says.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'opening an incident requires an authenticated actor (owner decision B1)'
      USING ERRCODE = '42501';
  END IF;
  IF NOT (public.is_admin() OR public.is_trust_operator()) THEN
    RAISE EXCEPTION 'only admin or trust_operator may open an incident (owner decision B1)'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.audit_incidents
    (summary, occurred_at, severity, scope, evidence, suspected_cause,
     recommended_action, actor_identity, actor_provenance)
  VALUES
    (p_summary, p_occurred_at, p_severity, p_scope, p_evidence, p_suspected_cause,
     p_recommended_action, v_uid, 'grounded')   -- B1: "actor identity must be recorded"
  RETURNING id INTO v_id;

  -- A2 puts `incidents` IN. The opening is itself audit-worthy.
  v_ps := public.audit_mint_pseudonym(v_uid);
  PERFORM public.audit_record_event(
    p_action => 'audit_incidents.open', p_category => 'incident',
    p_outcome => 'success', p_subject_pseudonym => v_ps);

  RETURN v_id;
END;
$$;
ALTER FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) FROM PUBLIC, anon;
-- service_role is NOT granted: B1 excludes it, and a grant would let an internal
-- caller reach the function even though the auth.uid() gate would then refuse it.
GRANT EXECUTE ON FUNCTION public.audit_open_incident(text,timestamptz,text,text,jsonb,text,text) TO authenticated;

-- ═══ B2 · RELATIONSHIP_CHANGE — both tables, STATUS transitions only ═══════
-- OWNER DECISION B2: "applies to MATERIAL relationship-status transitions in BOTH
-- coach_client_relationships and coach_team_members. Audit the actual status
-- transition/delta. Do NOT audit every incidental metadata change."
--
-- So the guard is `status IS DISTINCT FROM status` and nothing else: an update
-- that touches notes, timestamps or any other column emits nothing.
-- A6 names this category's delta as `status`, and it is non-PHI, so the
-- before/after pair is permitted.
CREATE OR REPLACE FUNCTION public.audit_relationship_status_change() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_subject uuid; v_ps uuid;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;                      -- incidental metadata change: B2 excludes it
  END IF;

  -- The subject is the party whose relationship status moved.
  v_subject := CASE TG_TABLE_NAME
                 WHEN 'coach_client_relationships' THEN NEW.client_id
                 WHEN 'coach_team_members'         THEN NEW.coach_id
               END;
  v_ps := public.audit_mint_pseudonym(v_subject);

  PERFORM public.audit_record_event(
    p_action            => TG_TABLE_NAME || '.status',
    p_category          => 'relationship_change',
    p_outcome           => 'success',
    p_subject_pseudonym => v_ps,
    p_delta             => jsonb_build_object(
                             'before', jsonb_build_object('status', OLD.status),
                             'after',  jsonb_build_object('status', NEW.status)));
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_relationship_status_change() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_relationship_status_change() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_audit_ccr_status
  AFTER UPDATE ON public.coach_client_relationships
  FOR EACH ROW EXECUTE FUNCTION public.audit_relationship_status_change();

-- coach_team_members is covered because B2 says BOTH. It is currently INERT and
-- that is recorded rather than hidden: migration 132 states there are "zero
-- writers of coach_team_members in the app or edge functions" and that the
-- invited->active transition "IS the acceptance step, and no acceptance mechanism
-- exists anywhere in this system". The control is in place for Wave 2's governed
-- conversion; it fires the moment a writer appears.
CREATE OR REPLACE TRIGGER trg_audit_ctm_status
  AFTER UPDATE ON public.coach_team_members
  FOR EACH ROW EXECUTE FUNCTION public.audit_relationship_status_change();

-- ═══ B3 · BILLING_ENTITLEMENT — the authoritative subscription state ═══════
-- OWNER DECISION B3: "must use the authoritative billing/subscription state and
-- the actual mutation path that changes effective subscription/entitlement state.
-- Do NOT use legacy user_profiles.membership_tier as the authoritative source."
--
-- Traced from repository evidence: `public.subscriptions` carries `status` and
-- `plan_tier` and is written by the Stripe surface — stripe-webhook,
-- update-subscription and cancel-subscription. `user_profiles.membership_tier` is
-- written by NOTHING in the tree and migration 115 guards it as "set by billing,
-- not by the client". So subscriptions is the source of truth and membership_tier
-- is the legacy field B3 excludes.
--
-- A6 names this category's delta as `tier`; both the tier and the status are the
-- effective entitlement, so the pair is recorded. Neither is PHI.
CREATE OR REPLACE FUNCTION public.audit_entitlement_change() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_ps uuid;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.plan_tier IS NOT DISTINCT FROM OLD.plan_tier THEN
    RETURN NEW;                      -- period rollovers and metadata: not an entitlement change
  END IF;

  v_ps := public.audit_mint_pseudonym(NEW.user_id);
  PERFORM public.audit_record_event(
    p_action            => 'subscriptions.entitlement',
    p_category          => 'billing_entitlement',
    p_outcome           => 'success',
    p_subject_pseudonym => v_ps,
    p_delta             => jsonb_build_object(
                             'before', jsonb_build_object('status', OLD.status, 'plan_tier', OLD.plan_tier),
                             'after',  jsonb_build_object('status', NEW.status, 'plan_tier', NEW.plan_tier)));
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_entitlement_change() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_entitlement_change() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_audit_subscription_entitlement
  AFTER UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.audit_entitlement_change();

-- ═══ B4 · PHI_CORRECTION — names only, never values ════════════════════════
-- OWNER DECISION B4: "Emit a phi_correction Event for an authorized mutation
-- whose purpose is correcting existing PHI. Record the changed-column-name set
-- only. NEVER place PHI before/after values into the audit Event."
--
-- The real path, traced rather than chosen: migration 114 governs
-- `weekly_checkins` -- free-text health data -- and its trigger already splits the
-- two writers. `v_coach_cols` (feedback_message, feedback_recommendations,
-- coach_name, reviewed_at, coach_id, status) are the COACH'S REVIEW fields;
-- everything else on the row is the client's own submitted health answers. So a
-- client updating an existing row in any column OUTSIDE that set is, by 114's own
-- construction, correcting their previously-submitted PHI. That is the authorized
-- correction mutation, and no new PHI classification is invented to find it.
--
-- A coach writing only review fields is NOT a PHI correction and emits nothing.
--
-- `delta` is left NULL: A6 excludes PHI-correction deltas and migration 150's
-- CHECK enforces it. Only `array_agg(key)` is ever computed, so no value can leak.
CREATE OR REPLACE FUNCTION public.audit_phi_correction() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_changed text[];
  v_phi     text[];
  v_ps      uuid;
  v_coach_cols constant text[] := ARRAY[
    'feedback_message', 'feedback_recommendations', 'coach_name',
    'reviewed_at', 'coach_id', 'status'
  ];
BEGIN
  IF v_uid IS NULL OR v_uid IS DISTINCT FROM OLD.user_id THEN
    RETURN NEW;             -- not the subject correcting their own record
  END IF;

  -- 114's own computation, reused rather than reinvented.
  SELECT array_agg(k) INTO v_changed
    FROM jsonb_each(to_jsonb(NEW)) AS e(k, v)
   WHERE e.v IS DISTINCT FROM (to_jsonb(OLD) -> e.k);
  IF v_changed IS NULL THEN RETURN NEW; END IF;

  -- NAMES ONLY, and only the health-answer columns.
  SELECT array_agg(c) INTO v_phi
    FROM unnest(v_changed) AS c
   WHERE c <> ALL (v_coach_cols) AND c <> 'updated_at';
  IF v_phi IS NULL THEN RETURN NEW; END IF;

  v_ps := public.audit_mint_pseudonym(OLD.user_id);
  PERFORM public.audit_record_event(
    p_action          => 'weekly_checkins.correction',
    p_category        => 'phi_correction',
    p_outcome         => 'success',
    p_subject_pseudonym => v_ps,
    p_delta           => NULL,        -- A6 excludes PHI deltas; 150 enforces it
    p_changed_columns => v_phi);      -- B4: the name set, metadata only
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.audit_phi_correction() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_phi_correction() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_audit_phi_correction
  AFTER UPDATE ON public.weekly_checkins
  FOR EACH ROW EXECUTE FUNCTION public.audit_phi_correction();
