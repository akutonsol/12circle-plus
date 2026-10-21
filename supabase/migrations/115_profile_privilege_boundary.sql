-- 115_profile_privilege_boundary.sql
--
-- PHASE 1C — closes D-02 (P0), vertical privilege escalation through
-- public.user_profiles, and the PAR-Q risk-authority hole behind Phase 0 Q-4.
--
-- ── THE HOLE (reproduced live on QA) ────────────────────────────────────────
-- TWO independent root causes, either one sufficient on its own:
--
--   1. `users can update own profile` (migration 015) is USING / WITH CHECK
--      (id = auth.uid()) with no column restriction, so the owner could write
--      ANY column on their row:
--          PATCH user_profiles?id=eq.self {"role":"admin"}        -> 204
--      is_admin() (019) and the role IN ('admin','content_manager') gates in the
--      communication engine (096) and exercise moderation (050) all read that
--      column, so the caller was instantly an admin -- admin_recent_users()
--      returned every user's name and email.
--      Verified live: role -> admin, coach, vendor and content_manager all
--      landed, as did membership_tier, marketplace_commission_rate, the whole
--      stripe_* Connect state and is_demo.
--
--   2. handle_new_user() (migration 044) took `role` straight from
--      new.raw_user_meta_data, which is supplied by whoever CALLS
--      /auth/v1/signup. Step 1 was never even necessary -- an attacker could
--      simply register as an admin.
--
--   Also verified: `coaches can update client profiles` (an UPDATE policy with
--   no column restriction) let an active coach set their CLIENT's role to admin.
--
-- ── PAR-Q RISK (Phase 0 Q-4) ────────────────────────────────────────────────
-- risk_score / risk_level / risk_flags were computed in Dart (intake_data.dart)
-- and written from the client. Q-4 makes high-risk PAR-Q status an ACTIVE
-- TRAINING CONSTRAINT rather than metadata -- but a constraint the constrained
-- party can overwrite is not a constraint. A member who answered "yes" to the
-- heart-condition question could submit risk_level = 'low' and go on to receive
-- an ordinary prescription.
--
-- The classification is a pure function of the answers, so it moves to the
-- server unchanged (same thresholds, same flag vocabulary as the Dart). The
-- member still owns the ANSWERS; the server owns the CLASSIFICATION. That is the
-- Q-3 rule -- THE ENGINE DECIDES -- and it is the minimum change that makes the
-- Q-4 constraint enforceable at all. What the product then DOES with a
-- high-risk member (clearance routing, prescription gating) is a clinical-policy
-- decision and is deliberately NOT invented here.
--
-- ── THE LEGITIMATE ROLE ARCHITECTURE (as discovered, preserved) ─────────────
--   * self-service signup offers client | coach | vendor (signup_screen.dart,
--     enum _Role) -- the product's open marketplace model, and it lives.
--   * admin and content_manager had NO in-app assignment path anywhere in the
--     codebase; they were set by hand. That becomes one explicit, authorized,
--     logged function (admin_set_user_role) instead of an unwritten rule.
--   * service_role keeps a direct write as the break-glass path.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   DROP TRIGGER IF EXISTS trg_profile_privilege ON public.user_profiles;
--   DROP TRIGGER IF EXISTS trg_profile_parq_risk ON public.user_profiles;
--   ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;

-- ---------------------------------------------------------------------------
-- The role vocabulary, written down for the first time. There was no CHECK
-- constraint on this column at all, which is why 'content_manager' -- and
-- anything else a caller cared to invent -- landed silently.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(DISTINCT role, ', ') INTO v_bad
    FROM public.user_profiles
   WHERE role IS NOT NULL
     AND role NOT IN ('client', 'coach', 'vendor', 'admin', 'content_manager');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '115: existing rows hold unknown roles (%) -- reconcile before adding the constraint', v_bad;
  END IF;
END $$;

ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;
ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_role_check
  CHECK (role IN ('client', 'coach', 'vendor', 'admin', 'content_manager'));

-- ---------------------------------------------------------------------------
-- PAR-Q risk classification -- server authority.
--
-- A faithful port of IntakeData.riskScore / riskLevel / riskFlags. Keep the two
-- in step: the Dart still computes the same values for immediate UI feedback,
-- but THIS is the copy that gets stored and that any downstream training
-- constraint must read.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.derive_parq_risk(
  p_parq                jsonb,
  p_medical_conditions  text,
  p_has_injuries        boolean,
  p_injury_locations    text
)
RETURNS TABLE (risk_score integer, risk_level text, risk_flags text)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_parq  jsonb := COALESCE(p_parq, '{}'::jsonb);
  v_med   text  := COALESCE(p_medical_conditions, '');
  v_score int;
  v_level text;
  v_flags text[] := '{}';
  -- PAR-Q question number -> flag label, in question order.
  v_labels constant text[] := ARRAY[
    'heart_condition',            -- 1
    'chest_pain_exercise',        -- 2
    'chest_pain_rest',            -- 3
    'fainting_dizziness',         -- 4
    'orthopedic_condition',       -- 5
    'bp_heart_medication',        -- 6
    'doctor_advised_no_exercise', -- 7
    'other_medical_reason'        -- 8
  ];
  i int;
BEGIN
  SELECT count(*) INTO v_score
    FROM jsonb_each(v_parq) AS e(k, v)
   WHERE e.v = 'true'::jsonb;

  -- Q1 heart condition, Q2 chest pain on exertion, Q3 chest pain at rest,
  -- Q4 fainting / dizziness, Q7 doctor advised against unsupervised exercise.
  IF (SELECT bool_or(v_parq ->> q = 'true')
        FROM unnest(ARRAY['1', '2', '3', '4', '7']) AS q) THEN
    v_level := 'high';
  ELSIF v_score > 0
     OR v_med LIKE '%Pregnancy%'
     OR v_med LIKE '%Heart Disease%'
     OR v_med LIKE '%High Blood Pressure%' THEN
    v_level := 'moderate';
  ELSE
    v_level := 'low';
  END IF;

  FOR i IN 1 .. array_length(v_labels, 1) LOOP
    IF v_parq ->> i::text = 'true' THEN
      v_flags := v_flags || v_labels[i];
    END IF;
  END LOOP;
  IF v_med LIKE '%Pregnancy%'  THEN v_flags := v_flags || 'pregnancy';  END IF;
  IF v_med LIKE '%Postpartum%' THEN v_flags := v_flags || 'postpartum'; END IF;
  IF COALESCE(p_has_injuries, false) AND COALESCE(p_injury_locations, '') <> '' THEN
    v_flags := v_flags || 'active_injuries';
  END IF;

  RETURN QUERY SELECT v_score, v_level, array_to_string(v_flags, ',');
END;
$$;

COMMENT ON FUNCTION public.derive_parq_risk(jsonb, text, boolean, text) IS
  'Authoritative PAR-Q risk classification (Phase 0 Q-4). Pure function of the '
  'member''s answers. The member owns the answers; the server owns the '
  'classification -- a safety constraint the constrained party can overwrite is '
  'not a constraint. Mirrors IntakeData.riskLevel in intake_data.dart.';

CREATE OR REPLACE FUNCTION public.apply_parq_risk()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  d record;
BEGIN
  SELECT * INTO d FROM public.derive_parq_risk(
    NEW.parq_answers, NEW.medical_conditions, NEW.has_injuries, NEW.injury_locations);
  NEW.risk_score := d.risk_score;
  NEW.risk_level := d.risk_level;
  NEW.risk_flags := d.risk_flags;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- The privilege boundary.
--
-- Two classes of column, deliberately handled differently:
--
--   HARD   -- privilege and money. A write RAISES, so an escalation attempt is
--             loud and lands in the logs rather than passing silently.
--   PINNED -- server-derived display / state. A write is silently reverted to
--             the stored value, because live screens fire these writes today
--             (home_screen recomputes a coach's rating_avg after a review) and
--             turning them into a 403 would surface an exception in the UI for
--             a write that is already a no-op under the current policies.
--
-- One rule covers every authenticated caller, so it closes the owner path and
-- the `coaches can update client profiles` path together. Internal callers
-- (service_role, the Stripe webhook, the engine, migrations) run with
-- auth.uid() IS NULL and pass through -- they bypass RLS in any case.
--
-- admin_set_user_role() below is the single sanctioned exception; it announces
-- itself with a transaction-local GUC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_profile_privilege()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_privileged boolean :=
    COALESCE(current_setting('circle12.privileged_role_write', true), 'off') = 'on';
BEGIN
  IF v_uid IS NULL THEN
    RETURN NEW;                                   -- internal / service-role path
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- A profile a signed-in user creates for themselves starts unprivileged.
    -- Self-service coach / vendor registration survives; anything else is a
    -- client. In practice handle_new_user() has already made this row, so this
    -- is the belt to that braces.
    IF NEW.role IS NULL OR NEW.role NOT IN ('client', 'coach', 'vendor') THEN
      NEW.role := 'client';
    END IF;
    NEW.membership_tier             := 'basic';
    NEW.marketplace_commission_rate := 0.10;
    NEW.stripe_customer_id          := NULL;
    NEW.stripe_account_id           := NULL;
    NEW.stripe_charges_enabled      := false;
    NEW.stripe_payouts_enabled      := false;
    NEW.stripe_details_submitted    := false;
    NEW.is_demo                     := false;
    NEW.rating_avg                  := 0;
    NEW.review_count                := 0;
    NEW.ai_client_summary           := '';
    NEW.assigned_coach_id           := NULL;
    RETURN NEW;
  END IF;

  -- ── HARD: privilege and money ──────────────────────────────────────────
  IF NEW.role IS DISTINCT FROM OLD.role AND NOT v_privileged THEN
    RAISE EXCEPTION 'user_profiles.role is not self-assignable -- use admin_set_user_role()'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.membership_tier IS DISTINCT FROM OLD.membership_tier THEN
    RAISE EXCEPTION 'user_profiles.membership_tier is set by billing, not by the client'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.marketplace_commission_rate IS DISTINCT FROM OLD.marketplace_commission_rate THEN
    RAISE EXCEPTION 'user_profiles.marketplace_commission_rate is not client-writable'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.stripe_customer_id       IS DISTINCT FROM OLD.stripe_customer_id
  OR NEW.stripe_account_id        IS DISTINCT FROM OLD.stripe_account_id
  OR NEW.stripe_charges_enabled   IS DISTINCT FROM OLD.stripe_charges_enabled
  OR NEW.stripe_payouts_enabled   IS DISTINCT FROM OLD.stripe_payouts_enabled
  OR NEW.stripe_details_submitted IS DISTINCT FROM OLD.stripe_details_submitted THEN
    RAISE EXCEPTION 'user_profiles Stripe Connect state is written by the Stripe webhook only'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN
    RAISE EXCEPTION 'user_profiles.is_demo is a fixture flag, not client-writable'
      USING ERRCODE = '42501';
  END IF;

  -- ── PINNED: server-derived, silently held ──────────────────────────────
  NEW.id                := OLD.id;
  NEW.email             := OLD.email;
  NEW.created_at        := OLD.created_at;
  NEW.rating_avg        := OLD.rating_avg;
  NEW.review_count      := OLD.review_count;
  NEW.ai_client_summary := OLD.ai_client_summary;
  NEW.assigned_coach_id := OLD.assigned_coach_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profile_privilege ON public.user_profiles;
CREATE TRIGGER trg_profile_privilege
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_privilege();

-- risk_* is recomputed AFTER the privilege trigger, for every caller including
-- service_role: it is derived data, and no path has a legitimate reason to
-- store a classification that disagrees with the answers.
DROP TRIGGER IF EXISTS trg_profile_parq_risk ON public.user_profiles;
CREATE TRIGGER trg_profile_parq_risk
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.apply_parq_risk();

-- ---------------------------------------------------------------------------
-- Signup: clamp the caller-supplied role.
--
-- Same body as migration 044 apart from the clamp and the pinned search_path.
-- An unrecognised or privileged request degrades to 'client' rather than
-- failing the signup, so a stale or malformed client build cannot lock users
-- out of registration.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
declare
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_full   text  := coalesce(v_meta->>'full_name', v_meta->>'name', '');
  v_first  text;
  v_last   text;
  v_avatar text;
  v_role   text;
begin
  v_first := coalesce(
    v_meta->>'first_name',
    v_meta->>'given_name',
    nullif(split_part(v_full, ' ', 1), ''),
    'User'
  );
  v_last := coalesce(
    v_meta->>'last_name',
    v_meta->>'family_name',
    nullif(trim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), ''),
    ''
  );
  v_avatar := coalesce(v_meta->>'avatar_url', v_meta->>'picture');

  -- raw_user_meta_data is supplied by whoever called /auth/v1/signup. Only the
  -- three self-service roles may come from there; admin and content_manager are
  -- assigned by admin_set_user_role() or service_role, never by the registrant.
  v_role := coalesce(v_meta->>'role', 'client');
  if v_role not in ('client', 'coach', 'vendor') then
    raise log 'handle_new_user: ignoring requested role % for %', v_role, new.id;
    v_role := 'client';
  end if;

  insert into public.user_profiles (id, first_name, last_name, email, role, avatar_url)
  values (new.id, v_first, v_last, new.email, v_role, v_avatar);
  return new;
end;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Creates the public.user_profiles row for a new auth.users row (trigger wired '
  'in migration 109). The requested role is clamped to the self-service set '
  'client|coach|vendor -- raw_user_meta_data is caller-controlled (migration 115).';

-- ---------------------------------------------------------------------------
-- The one legitimate privileged-assignment path.
--
-- is_admin() is re-declared here only to pin its search_path; a SECURITY DEFINER
-- function without one resolves unqualified names through the caller's
-- search_path, which is caller-controlled.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE id = auth.uid() AND role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_set_user_role(target_user uuid, new_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- auth.uid() IS NULL is the service_role / internal path, which is already
  -- trusted; every client-reachable call must prove admin.
  IF (SELECT auth.uid()) IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;
  IF new_role NOT IN ('client', 'coach', 'vendor', 'admin', 'content_manager') THEN
    RAISE EXCEPTION 'unknown role: %', new_role USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE id = target_user) THEN
    RAISE EXCEPTION 'no such user' USING ERRCODE = '22023';
  END IF;

  -- Definer rights do NOT clear auth.uid(), so enforce_profile_privilege would
  -- reject this write like any other. Announce the sanctioned exception for the
  -- duration of this transaction only (set_config is_local = true); the
  -- authorization decision was made above. The GUC prefix must be a valid
  -- identifier, so it cannot lead with a digit -- 'circle12', not '12circle'.
  PERFORM set_config('circle12.privileged_role_write', 'on', true);
  UPDATE public.user_profiles SET role = new_role, updated_at = now()
   WHERE id = target_user;
  PERFORM set_config('circle12.privileged_role_write', 'off', true);

  RAISE LOG 'admin_set_user_role: % set % to %', auth.uid(), target_user, new_role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.admin_set_user_role(uuid, text) IS
  'The only client-reachable path that changes user_profiles.role. Admin-only, '
  'validated against the role vocabulary, and logged. Added by migration 115 '
  'because admin / content_manager previously had no assignment path at all and '
  'were being set by hand.';

COMMENT ON TABLE public.user_profiles IS
  'PRIVILEGE BOUNDARY. role drives is_admin(), the communication-engine and '
  'exercise-moderation gates, and every role-based screen. role, '
  'membership_tier, marketplace_commission_rate, the stripe_* Connect state and '
  'is_demo are not client-writable (migration 115); risk_* is derived from '
  'parq_answers server-side (Phase 0 Q-4).';
