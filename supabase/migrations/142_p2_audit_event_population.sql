-- Migration 142 — P2 · the AUDIT EVENT population, and the two roles it reads through.
--
-- P2's entry conditions are satisfied: §5.2 gates P2 on D4 + D12; D4 completed at
-- V5 §19.2, D12's content at §74, and SQ-10 -- the added entry condition (§8.10) --
-- was answered by §19.3's Q1. The schema below is the one D4 already decided. Nothing
-- here is a new audit design; every object cites the ruling that produced it, and
-- V5 §75 carries the full specification this implements.
--
-- SCOPE. This migration builds ONE of D4's four populations -- the Event population
-- (A1 §8.4, population 1). Incident, Control evidence and the D12 observability
-- population are separate objects with separate rulings and are NOT built here.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- CLAIM LIMITS. These are RULINGS, not commentary. Each forbids a claim this
-- schema would otherwise imply, and each is carried into the object comments so
-- it survives away from this file (V5 §75.4):
--
--   1. NO TAMPER-RESISTANCE CLAIM. A11 sub-ruling 2 requires an out-of-database
--      trust anchor before any meaningful append-only claim. §8.19 DECLINED the
--      anchor, so the binding below is DML-DEEP ONLY. It binds every caller
--      including service_role; it binds nobody at the DDL layer.
--   2. NO UNIVERSAL ACCESS-LOGGING CLAIM. A3 sub-ruling 1 / A11 sub-ruling 4:
--      PHI-read audit observes only RPC-routed reads -- 8.7% of the client's
--      data-access calls. No document may describe PHI-read auditing as complete.
--   3. THREE ACCEPTED BLIND SPOTS (A3 sub-ruling 2): RLS authorization denials,
--      managed authentication events, storage/media reads. They are IN under A2
--      and unemittable by any path. They must not be represented as audited.
--   4. ANONYMISATION IS NOT IRREVERSIBLE. §8.20·Q4 -- severance binds at the DML
--      layer and is not durable against a party holding DDL rights.
--   5. THE CORRELATION IDENTIFIER IS NOT TRUSTWORTHY AGAINST THE FUNCTION TIER.
--      V5 §71.1, normative. §68 demonstrated a compromised Edge Function obtains
--      valid signatures on demand, defeating all five signer designs. Signing is
--      DETECTION, never prevention, against that adversary.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1 · THE TWO ROLES (§8.18·Q1 — TWO ROLES) ────────────────────────────────
-- "The Trust operator reads and reviews; a separate new constrained role executes
-- erasure. The Trust operator is therefore NOT the role A12 ruling 6 mandated --
-- that remains a distinct second role."
--
-- A12 ruling 6 asked whether the erasure executor may be service_role: NO.
-- Both values are added in ONE constraint change rather than two, but only
-- trust_operator is USED here -- the erasure flow is a later migration.
-- §19.3 forbids a THIRD role; these are the two, and no more are created.
ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_role_check
  CHECK (role = ANY (ARRAY[
    'client'::text, 'coach'::text, 'vendor'::text, 'admin'::text,
    'content_manager'::text,
    'trust_operator'::text,      -- §8.18·Q1 — reads and reviews
    'erasure_executor'::text     -- §8.18·Q1 + A12 ruling 6 — NOT service_role
  ]));

-- Mirrors is_admin() exactly: SQL / STABLE / SECURITY DEFINER / pinned search_path.
-- Hierarchy 5 -- the precedent is genuinely applicable, this is the same shape of
-- predicate evaluated by the same kind of policy.
CREATE OR REPLACE FUNCTION public.is_trust_operator() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE id = auth.uid() AND role = 'trust_operator'
  );
$$;
ALTER FUNCTION public.is_trust_operator() OWNER TO postgres;

-- Migration 116 posture. 116 set ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE FROM
-- PUBLIC and anon, so a new function inherits no PUBLIC execute -- but the REVOKE
-- is restated explicitly rather than relied upon, because migration 138 regressed
-- exactly this class and only CI caught it (V5 §39, repaired by 139).
-- EXECUTE to authenticated is REQUIRED: this predicate is evaluated by an RLS
-- policy as the caller, and 116's allowlist exists for precisely that reason.
REVOKE ALL ON FUNCTION public.is_trust_operator() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_trust_operator() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_trust_operator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_trust_operator() TO service_role;

COMMENT ON FUNCTION public.is_trust_operator() IS
  '§8.18·Q1 TWO ROLES — the Trust operator READS AND REVIEWS and holds no erasure '
  'authority (A13 sub-ruling 4 / §8.18·Q2: no single party may hold both). '
  'Mirrors is_admin(). Not a third role — §19.3 forbids one.';

-- ── 2 · THE EVENT POPULATION (A1 §8.4 population 1) ─────────────────────────
-- A1's shape, verbatim: "append-only occurrence record — actor · subject · action
-- · time · outcome". Every column below is either one of those five or carries its
-- own citation.
CREATE TABLE IF NOT EXISTS public.audit_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- A1's five.
  --
  -- DELIBERATELY NO FOREIGN KEY, and the omission is a ruling, not an oversight.
  -- An earlier revision of this migration declared both columns
  -- `REFERENCES auth.users(id) ON DELETE SET NULL`. Local validation refuted it on
  -- two independent counts, both of which would have been defects on QA:
  --
  --   1. It makes A3 sub-ruling 3 UNIMPLEMENTABLE. That ruling PERMITS an
  --      application-asserted actor, and §8.5's own consequence names the case:
  --      `stripe-webhook` has no JWT at all and its actor is
  --      `session.metadata.user_id`, "supplied by a third party's payload". An FK
  --      rejects any asserted actor that is not already an auth.users row --
  --      exactly the case the ruling contemplates. Verified: the asserted-actor
  --      probe failed 23503 against the FK.
  --   2. `ON DELETE SET NULL` MUTATES A FROZEN ROW. A11 freezes the Event row and
  --      A12 ruling 2 takes NO exception -- "the frozen row is never mutated";
  --      erasure goes through the external mapping instead. A1 sub-ruling 2 already
  --      forbids the sibling form: audit records "must not be ON DELETE CASCADE'd
  --      merely because the audited subject is deleted." SET NULL is the same
  --      class. It would also have DEADLOCKED against policy: the freeze trigger
  --      below refuses the SET NULL, so deleting a user would fail outright.
  --
  -- The identifiers are therefore stored raw. Referential integrity to auth.users
  -- is not asserted, because the audit ledger must outlive the subject (A12 ruling
  -- 1, ANONYMISE-AND-RETAIN) and must accept actors that were never users.
  actor_id      uuid,

  -- A PSEUDONYM, NOT THE SUBJECT'S REAL IDENTIFIER, and the distinction is
  -- load-bearing rather than stylistic. A12 ruling 1 is ANONYMISE-AND-RETAIN and
  -- ruling 2 answers whether the A11 Event freeze gets an exception for erasure:
  -- "NO exception -- USE AN EXTERNAL MAPPING. The frozen row is never mutated."
  -- §8.7 glosses it: "an external PSEUDONYMOUS mapping -- severed to anonymise,
  -- leaving the frozen Event row untouched."
  --
  -- An earlier revision of this migration stored the real auth.users id here.
  -- That makes A12's erasure model INOPERABLE: severing a mapping anonymises
  -- nothing if the row already carries the identifier the mapping was meant to
  -- resolve, and the only remaining way to erase would be to mutate the frozen
  -- row, which ruling 2 forbids in the same sentence. Corrected; V5 §78.
  --
  -- SCOPE. Ruling 2 is titled "A11 EVENT FREEZE" and this is the only population
  -- that needs it: Incident is mutable by A1 sub-ruling 1 and can be anonymised
  -- in place, Control evidence carries no subject by A1, and the observability
  -- population carries none by D12·Q5.
  --
  -- The resolving map, who may sever it and who may resolve through it are
  -- migration 146 (§8.20·Q1, §19.3). Until it exists a pseudonym resolves to
  -- nothing, which is the safe direction to be incomplete in.
  subject_pseudonym uuid,
  action        text NOT NULL,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  outcome       text NOT NULL,

  -- A3 sub-ruling 3. "Asserted / application-provided identity and
  -- cryptographically grounded auth.uid() attribution MUST REMAIN DISTINGUISHABLE
  -- in the design and MUST NOT BE EQUATED." The tag vocabulary is §19.3's D12·Q2
  -- ruling: server-minted are tagged by origin, client-asserted are tagged
  -- `asserted`. A3's consequence note is why this cannot be omitted: auth.uid() is
  -- NULL on every internal path, current_user cannot distinguish an Edge Function
  -- from pg_cron from a migration, and stripe-webhook's actor arrives inside a
  -- third party's payload.
  actor_provenance text NOT NULL,

  -- A2 §8.3. Required, not decorative: A12 ruling 3 makes retention precedence
  -- PER-CATEGORY, and ruling 4 gives financial/tax a DIFFERENT window (7 years)
  -- from every other category (6). Without the category the retention rule is
  -- unevaluable.
  category      text NOT NULL,

  -- D12·Q3, ANSWERED §19.3: "a correlation identifier column on the audit Event
  -- row", classified under A11's freeze as an IDENTITY/OCCURRENCE column and
  -- therefore immutable. §19.3's D12·Q5 requires it be "a random opaque value with
  -- no derivation from subject identity".
  correlation_id uuid,

  -- V5 §71 (D12·Q5 = Option A). The signature and key id the external signer
  -- issues. NULLABLE BY NECESSITY: the signer is project B, which is NOT
  -- PROVISIONED, so no value is obtainable today. A row with a NULL signature is
  -- NOT correlatable by Trust -- see the comment on correlation_signature.
  correlation_signature text,
  correlation_key_id    text,

  recorded_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT audit_events_outcome_check
    CHECK (outcome = ANY (ARRAY['success'::text, 'failure'::text, 'denied'::text])),

  -- A3 sub-ruling 3's distinction, made structural rather than conventional.
  CONSTRAINT audit_events_actor_provenance_check
    CHECK (actor_provenance = ANY (ARRAY[
      'grounded'::text,   -- from auth.uid(); cryptographically grounded
      'asserted'::text,   -- application- or client-supplied; NOT grounded
      'system'::text      -- internal path with no actor at all (auth.uid() IS NULL)
    ])),

  -- A2 §8.3's fourteen IN categories, verbatim. Session lifecycle is OUT and is
  -- deliberately absent -- A2: "subject to the promotion clause", so adding it
  -- later is a ruling, not an oversight.
  CONSTRAINT audit_events_category_check
    CHECK (category = ANY (ARRAY[
      'phi_read'::text, 'phi_correction'::text, 'financial'::text,          -- tier 1
      'incident'::text, 'agent_action'::text, 'control_evidence'::text,
      'admin_action'::text, 'observability_audit'::text,                    -- tier 2
      'authentication'::text, 'authorization_denial'::text,
      'billing_entitlement'::text, 'relationship_change'::text,
      'storage_media_access'::text, 'export_deletion'::text                 -- tier 3
    ]))
);
ALTER TABLE public.audit_events OWNER TO postgres;

COMMENT ON TABLE public.audit_events IS
  'D4·A1 §8.4 population 1 — the append-only Event ledger. '
  'CLAIM LIMITS (V5 §75.4, each a ruling): (1) NOT tamper-resistant — A11 sub-ruling 2 '
  'requires an out-of-database anchor and §8.19 DECLINED it, so the freeze below is '
  'DML-DEEP ONLY and binds nobody holding DDL rights. (2) PHI-read coverage is PARTIAL '
  '— A3 sub-ruling 1, RPC-routed reads only, 8.7% of client data-access calls; this must '
  'never be described as complete. (3) RLS denials, managed authentication events and '
  'storage/media reads are ACCEPTED BLIND SPOTS (A3 sub-ruling 2) — they are audit-worthy '
  'under A2 and unemittable by any path, and must not be represented as audited.';

COMMENT ON COLUMN public.audit_events.actor_provenance IS
  'A3 sub-ruling 3 — asserted and grounded attribution must remain distinguishable and '
  'must NOT be equated. `grounded` = auth.uid(); `asserted` = application/client-supplied; '
  '`system` = internal path with no actor. §19.3 D12·Q2: no identifier is treated as '
  'trustworthy merely because it is present.';

COMMENT ON COLUMN public.audit_events.correlation_signature IS
  'V5 §71.1 NORMATIVE — the signature PREVENTS correlation forgery only by an adversary '
  'holding database write access WITHOUT the signer''s invoke credential (a leaked '
  'service_role used directly against PostgREST or the pooler). It provides NO PREVENTION '
  'against a compromised Edge Function / service_role trust root, which holds that '
  'credential by construction and obtains valid signatures on demand (§68, C-1..C-6, '
  'defeating all five signer designs). Against that adversary the only control is '
  'DETECTION via the signer''s issuance log (§71.3 DET-1..DET-4), whose measured limit is '
  'that a patient adversary spending one issuance per fabrication is NOT DETECTED. '
  'NEVER describe this column as preventing correlation forgery. '
  'NULL until project B is provisioned; a NULL signature is NOT correlatable.';

CREATE INDEX IF NOT EXISTS audit_events_subject_occurred_idx
  ON public.audit_events (subject_pseudonym, occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_events_correlation_idx
  ON public.audit_events (correlation_id) WHERE correlation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS audit_events_category_occurred_idx
  ON public.audit_events (category, occurred_at DESC);

-- ── 3 · IMMUTABILITY (A11 §8.6 — Event = FREEZE-IDENTITY-COLUMNS) ───────────
-- A11 Event: "identity and occurrence facts are immutable. Any future writable
-- annotation field MUST BE EXPLICITLY CLASSIFIED and must not alter the occurrence
-- record." This table defines NO annotation field, so every column is an identity
-- or occurrence fact and the whole row is frozen. Adding a writable annotation
-- later requires the explicit classification A11 demands.
--
-- MECHANISM, and why this one. A3 sub-ruling 5 requires that service_role be
-- CONSTRAINED from bypassing audit controls; A11 sub-ruling 3 deferred that binding
-- until A12's erasure mechanism was decided, and A12 IS NOW DECIDED, so the deferral
-- is discharged. §8.5's own consequence names the only verified mechanism: "a BEFORE
-- UPDATE/DELETE trigger that RAISEs (120_workout_set_identity_authority.sql
-- precedent)" is the only thing that binds EVERY caller including owner and
-- service_role. Grants and policies bind nothing here -- a compromised Edge Function
-- holds service_role, which bypasses RLS entirely.
CREATE OR REPLACE FUNCTION public.audit_events_freeze() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'audit_events is append-only: an occurrence record cannot be modified (id %)', OLD.id
      USING ERRCODE = '42501';
  END IF;
  -- DELETE is refused too. A12 ruling 1 is ANONYMISE-AND-RETAIN and ruling 2 takes
  -- NO exception to the Event freeze -- "the frozen row is never mutated", erasure
  -- goes through the external mapping instead. Retention purge at the A12 ruling 4
  -- windows is a SEPARATE authorized path that does not exist yet; when it is built
  -- it must be built as a ruling, not by leaving DELETE open here.
  RAISE EXCEPTION 'audit_events is append-only: an occurrence record cannot be deleted (id %)', OLD.id
    USING ERRCODE = '42501';
END;
$$;
ALTER FUNCTION public.audit_events_freeze() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.audit_events_freeze() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_events_freeze() FROM anon;

CREATE OR REPLACE TRIGGER trg_audit_events_freeze
  BEFORE UPDATE OR DELETE ON public.audit_events
  FOR EACH ROW EXECUTE FUNCTION public.audit_events_freeze();

COMMENT ON FUNCTION public.audit_events_freeze() IS
  'A11 §8.6 Event = FREEZE-IDENTITY-COLUMNS, enforced by the only mechanism verified to '
  'bind every caller INCLUDING service_role (§8.5, migration 120 precedent) — discharging '
  'A3 sub-ruling 5 now that A11 sub-ruling 3''s deferral condition (A12) is decided. '
  'DML-DEEP ONLY: §8.19 declined the out-of-database anchor A11 sub-ruling 2 requires, so '
  'this is NOT a tamper-resistance claim and binds nobody holding DDL rights.';

-- ── 4 · READERS (A13 §8.8 — Event: active coach · admin · Trust operator) ───
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

-- A13's enumeration is implemented EXACTLY as written. Note what it does not
-- contain: the SUBJECT is not an Event reader -- A13 lists the subject/actor only
-- for the Incident population. A13 sub-ruling 1 ("may the audited party read its
-- own audit? NOT FOR ADMIN ACTIONS") is therefore satisfied a fortiori here, and
-- the narrower reading is taken deliberately under hierarchy 1 (least privilege)
-- and 11 (never silently broaden). If the owner intended subject self-read for
-- non-admin categories, that is an ADDITIVE ruling, not a defect in this policy.
-- A13 SUB-RULING 1 IS ENFORCED HERE, and an earlier revision of this policy did
-- not enforce it. "May the audited party read its own audit? NOT FOR ADMIN
-- ACTIONS." §8.8's own consequence names the mechanism that was missing:
-- "excluding an admin from their own admin-action records means a predicate
-- distinguishing ACTOR-IDENTITY from READER-IDENTITY within one population. No
-- policy in the repository does this." This one does.
--
-- The exclusion is narrow and deliberate: it removes ONLY the reader's own
-- admin_action rows from the admin arm. The Trust operator arm is untouched, so
-- those rows remain readable by Trust -- which is the point of sub-ruling 1.
-- Self-audit is not oversight; oversight is someone else reading it.
CREATE POLICY "audit events read: active coach, admin, trust operator"
  ON public.audit_events FOR SELECT TO authenticated
  USING (
    (public.is_admin()
      AND NOT (category = 'admin_action' AND actor_id = (SELECT auth.uid())))
    OR public.is_trust_operator()
  );

-- WHY THE ACTIVE-COACH ARM IS NOT HERE. A13 §8.8 names three Event readers --
-- active coach, admin, Trust operator -- and the first cannot be expressed as a
-- table policy once the subject is a pseudonym: deciding `is_active_coach_of`
-- requires RESOLVING the pseudonym, and §19.3 rules that "NO STANDING PARTY" may
-- do that and that "resolution occurs INSIDE THE AUDIT READ PATH, gated by A13's
-- per-population reader rules". A policy is a standing resolver by definition.
-- The coach reader is therefore served by the SECURITY DEFINER read path in
-- migration 146, not removed. A13's list is honoured across the two objects;
-- this table alone implements the two ROLE-CLASS arms, which need no resolution.

-- NO INSERT, UPDATE or DELETE policy exists, and none may be added. RLS denies
-- what it does not permit, so `authenticated` cannot write this table by any path;
-- writes go through audit_record_event() below (A3: trigger + RPC + application).
-- The decision_traces shape §8.20·Q1 cites as genuinely applicable precedent is
-- exactly this: a read policy and no write policy at all.

REVOKE ALL ON TABLE public.audit_events FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_events FROM anon;
GRANT SELECT ON TABLE public.audit_events TO authenticated;
GRANT SELECT, INSERT ON TABLE public.audit_events TO service_role;

-- ── 5 · THE WRITE PATH (A3 §8.5 — Event: trigger + RPC + application) ───────
-- A3 sub-ruling 4: "An audit-write failure MUST NOT automatically abort the audited
-- business action", and reliable failure visibility is recorded there as "an
-- unresolved implementation concern CARRIED TO THE DOWNSTREAM DESIGN". This is that
-- downstream design, and it resolves it as far as the constraint allows:
--
--   * the write is wrapped so no audit failure propagates to the caller;
--   * the function returns BOOLEAN so the caller can observe the failure;
--   * a failure raises a WARNING carrying the SQLSTATE.
--
-- THE LIMIT, STATED: A2 ruled that a server-log line does NOT satisfy an audit
-- obligation. The warning below is therefore NOT an audit record and is not offered
-- as one -- it is an operational failure signal. A durable failure record would
-- itself be a write that can fail, which is the regress A3 sub-ruling 4 declined to
-- resolve. Nothing here claims reliable failure visibility.
CREATE OR REPLACE FUNCTION public.audit_record_event(
  p_action           text,
  p_category         text,
  p_outcome          text,
  p_subject_pseudonym uuid  DEFAULT NULL,
  p_actor_id         uuid   DEFAULT NULL,
  p_actor_provenance text   DEFAULT NULL,
  p_correlation_id   uuid   DEFAULT NULL
) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_actor      uuid;
  v_provenance text;
BEGIN
  -- A3 sub-ruling 3. Provenance is DERIVED, never taken on trust: a caller may
  -- assert an actor, but it may not assert that the actor is grounded. Only
  -- auth.uid() produces `grounded`.
  IF v_uid IS NOT NULL THEN
    v_actor := v_uid;
    v_provenance := 'grounded';
  ELSIF p_actor_id IS NOT NULL THEN
    v_actor := p_actor_id;
    v_provenance := 'asserted';
  ELSE
    v_actor := NULL;
    v_provenance := 'system';
  END IF;

  -- An explicitly asserted actor never upgrades to grounded, but a caller MAY
  -- declare its own record asserted when it knows the actor did not come from a
  -- verified session. Downgrade is permitted; upgrade is not.
  IF p_actor_provenance = 'asserted' AND v_provenance = 'grounded' THEN
    v_provenance := 'asserted';
  END IF;

  INSERT INTO public.audit_events
    (actor_id, subject_pseudonym, action, outcome, actor_provenance, category, correlation_id)
  VALUES
    (v_actor, p_subject_pseudonym, p_action, p_outcome, v_provenance, p_category, p_correlation_id);

  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_record_event failed (action=%, category=%): % [%]',
    p_action, p_category, SQLERRM, SQLSTATE;
  RETURN false;
END;
$$;
ALTER FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) TO service_role;

COMMENT ON FUNCTION public.audit_record_event(text, text, text, uuid, uuid, text, uuid) IS
  'A3 §8.5 Event write path (RPC arm). BEST-EFFORT per A3 sub-ruling 4 — an audit-write '
  'failure never aborts the audited business action; the boolean return and a WARNING are '
  'the failure signal. A2 ruled a server-log line does NOT satisfy an audit obligation, so '
  'that warning is NOT an audit record and reliable failure visibility remains the '
  'unresolved concern A3 sub-ruling 4 recorded. Provenance is DERIVED (A3 sub-ruling 3): '
  'only auth.uid() yields `grounded`; a caller may downgrade to `asserted` but never upgrade.';
