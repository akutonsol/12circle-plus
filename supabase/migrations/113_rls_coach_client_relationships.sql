-- 113_rls_coach_client_relationships.sql
--
-- PHASE 1A — closes D-01 (P0). The relationship table is the AUTHORIZATION
-- ROOT of this product and it had no row level security at all.
--
-- ── THE HOLE (reproduced live on QA, see test/security/) ────────────────────
-- public.coach_client_relationships was created in 000_baseline_preexisting_tables
-- and never had `ENABLE ROW LEVEL SECURITY`. With the anon key that ships in the
-- client build, ANY caller -- including an unauthenticated one -- could:
--
--   POST /rest/v1/coach_client_relationships
--        {coach_id: <attacker>, client_id: <victim>, status: 'active'}   -> 201
--
-- and `public.is_active_coach_of(<victim>)` immediately flipped false -> true for
-- the attacker. Because migration 100 routes every coach-read policy through that
-- function, and migration 102 routes the whole user_profiles PII row through it,
-- one forged INSERT handed the attacker the victim's weight logs, body
-- measurements, nutrition logs, progress photos, habits, daily scores, workout
-- sessions, check-ins AND their email / phone / DOB / medical_conditions /
-- parq_answers / injury_description / Stripe identifiers.
--
-- The same hole allowed UPDATE and DELETE of other people's relationships:
-- severing a real coaching relationship, or repointing an attacker's own row at a
-- third-party client.
--
-- ── WHY BLOCKING SELECT IS NOT THE FIX ──────────────────────────────────────
-- This table is not merely sensitive data; it is an authorization source. Its
-- CONTENTS decide who may read whose health record. So the write path is the
-- security boundary -- SELECT scoping alone would leave the escalation intact.
--
-- ── THE MODEL ───────────────────────────────────────────────────────────────
-- Activating a relationship grants the COACH access to the CLIENT's data. The
-- client is the data subject, so authority is asymmetric:
--
--   * A client may create and activate their own relationship freely. They are
--     consenting to share their own record -- that is the marketplace/onboarding
--     flow and it harms nobody else.
--   * A coach may only ever create a 'pending' row, and may only activate a row
--     the CLIENT initiated. A coach can never unilaterally reach an unconsenting
--     client's data.
--   * Nobody who is not a party to the row can see it, change it, or delete it.
--   * DELETE is not granted to clients at all. Ending a relationship is
--     status = 'cancelled' (that is what every app call site already does);
--     hard deletion would destroy the audit trail and is service-role only.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────
--   ALTER TABLE public.coach_client_relationships DISABLE ROW LEVEL SECURITY;
-- (restores the pre-113 behaviour completely; policies are inert while disabled)

-- ---------------------------------------------------------------------------
-- Helper: is this user actually a coach?
--
-- SECURITY DEFINER because migration 102 restricts user_profiles to the owner
-- and their active coach -- evaluated as the caller this would return NULL for
-- every coach the client has not yet enrolled with, i.e. all of them.
-- Returns a boolean only; it never projects a profile row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_coach_profile(target_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles p
     WHERE p.id = target_user
       AND p.role = 'coach'
  );
$$;

REVOKE ALL ON FUNCTION public.is_coach_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_coach_profile(uuid) TO authenticated;

COMMENT ON FUNCTION public.is_coach_profile(uuid) IS
  'True when target_user holds role = coach. Membership predicate only. Used by '
  'the coach_client_relationships INSERT policy so a relationship cannot be '
  'opened against an arbitrary non-coach account.';

-- ---------------------------------------------------------------------------
-- Marketplace capacity.
--
-- availableCoachesProvider (coach_provider.dart) used to read every coach's
-- relationship rows to compute "x / max_clients" and hide full coaches. Under
-- the new SELECT policy a client sees only their own rows, so that count would
-- silently collapse to zero and a full coach would render as available.
--
-- This is the MINIMUM supporting change the security fix requires: an aggregate
-- that returns a count and nothing else -- no client identity ever leaves it.
-- The number is already public in the marketplace UI by design.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.coach_active_client_counts(coach_ids uuid[])
RETURNS TABLE (coach_id uuid, active_clients integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.id AS coach_id,
         COALESCE(
           (SELECT COUNT(DISTINCT r.client_id)
              FROM public.coach_client_relationships r
             WHERE r.coach_id = c.id
               AND r.status = 'active'), 0)::int AS active_clients
    FROM unnest(coach_ids) AS c(id)
   WHERE public.is_coach_profile(c.id);
$$;

REVOKE ALL ON FUNCTION public.coach_active_client_counts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.coach_active_client_counts(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.coach_active_client_counts(uuid[]) IS
  'Active-client COUNT per coach for marketplace capacity. Aggregate only -- it '
  'must never be widened to project client_id or any relationship column.';

-- ---------------------------------------------------------------------------
-- Row integrity: the parts RLS cannot express.
--
-- A WITH CHECK clause only sees the NEW row, so it cannot stop a party from
-- rewriting the row's identity or its provenance. Without this trigger an
-- attacker could take a relationship they legitimately own as the CLIENT and
-- PATCH it into {coach_id: self, client_id: victim} -- the WITH CHECK would
-- still pass, because the result names them the coach. Likewise a coach could
-- flip initiated_by to 'client' and then self-approve their own invite.
--
-- Internal callers (service_role, the deterministic engine, migrations, the
-- SQL editor) run with auth.uid() IS NULL and pass straight through -- they
-- bypass RLS anyway, so gating them here would only break the backfills in
-- migrations 009 and 040 without adding any protection.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_relationship_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN NEW;                      -- internal / service-role path
  END IF;

  IF NEW.id           IS DISTINCT FROM OLD.id
  OR NEW.coach_id     IS DISTINCT FROM OLD.coach_id
  OR NEW.client_id    IS DISTINCT FROM OLD.client_id THEN
    RAISE EXCEPTION 'coach_client_relationships: the parties of a relationship are immutable'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.initiated_by IS DISTINCT FROM OLD.initiated_by THEN
    RAISE EXCEPTION 'coach_client_relationships: initiated_by is immutable (it decides who may activate)'
      USING ERRCODE = '42501';
  END IF;

  -- client_source drives the marketplace commission rate (migration 040) and
  -- invite_token is a bearer credential. Neither is client-writable.
  IF NEW.client_source IS DISTINCT FROM OLD.client_source THEN
    RAISE EXCEPTION 'coach_client_relationships: client_source is set by the server'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.invite_token IS DISTINCT FROM OLD.invite_token THEN
    RAISE EXCEPTION 'coach_client_relationships: invite_token is not client-writable'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    NEW.created_at := OLD.created_at;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_relationship_integrity ON public.coach_client_relationships;
CREATE TRIGGER trg_relationship_integrity
  BEFORE UPDATE ON public.coach_client_relationships
  FOR EACH ROW EXECUTE FUNCTION public.enforce_relationship_integrity();

-- Migration 040's BEFORE INSERT trigger reads coach_invites and user_profiles to
-- decide client_source. Both are RLS-protected, so as a SECURITY INVOKER function
-- it now sees nothing and silently tags every coach-invited client 'marketplace'
-- (a 0% commission becomes a charged one). Same body, definer rights, pinned
-- search_path -- it only ever assigns NEW.client_source.
CREATE OR REPLACE FUNCTION public.set_relationship_client_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.client_source IS NULL OR NEW.client_source = 'marketplace' THEN
    IF EXISTS (
      SELECT 1
        FROM coach_invites i
        JOIN user_profiles p ON p.id = NEW.client_id
       WHERE i.coach_id = NEW.coach_id
         AND lower(i.invitee_email) = lower(p.email)
    ) THEN
      NEW.client_source := 'coach_invited';
    ELSE
      NEW.client_source := COALESCE(NEW.client_source, 'marketplace');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Privileges.
--
-- anon loses the table outright. The anon key is compiled into the published
-- client build, so "anonymous" here means "the whole internet". RLS alone would
-- be enough, but a missing policy is a one-line mistake away and the grant is
-- not; both layers now have to fail before the table is reachable.
--
-- invite_token / invite_id are bearer credentials with no reader anywhere in the
-- codebase (verified across apps/ and packages/ -- the live invite flow uses
-- coach_invites.token). They are removed at the column-privilege layer so no
-- future policy can hand them out by accident. Every application read of this
-- table uses an explicit column list, so this breaks no call site.
-- ---------------------------------------------------------------------------
REVOKE ALL ON public.coach_client_relationships FROM PUBLIC, anon;
REVOKE ALL ON public.coach_client_relationships FROM authenticated;

-- NOTE the shape here. A column-level REVOKE does NOT cut back a table-level
-- GRANT -- Postgres treats the two as independent, and the table-level grant
-- wins. `GRANT SELECT ... ; REVOKE SELECT (invite_token) ...` therefore leaves
-- the token fully readable (observed live on QA before this was corrected).
-- The only way to withhold a column is to never grant it: enumerate the allowed
-- columns instead. Built from the live catalog so a column added later is
-- included automatically, while the deny-list stays explicit.
DO $$
DECLARE
  cols text;
BEGIN
  SELECT string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position)
    INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name   = 'coach_client_relationships'
     AND column_name NOT IN ('invite_token', 'invite_id');

  EXECUTE format('GRANT SELECT (%s) ON public.coach_client_relationships TO authenticated', cols);
  EXECUTE format('GRANT INSERT (%s) ON public.coach_client_relationships TO authenticated', cols);
  EXECUTE format('GRANT UPDATE (%s) ON public.coach_client_relationships TO authenticated', cols);
END $$;

-- ---------------------------------------------------------------------------
-- Row level security.
-- ---------------------------------------------------------------------------
ALTER TABLE public.coach_client_relationships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "relationship parties read"     ON public.coach_client_relationships;
DROP POLICY IF EXISTS "relationship parties create"   ON public.coach_client_relationships;
DROP POLICY IF EXISTS "relationship parties update"   ON public.coach_client_relationships;

-- SELECT — the two parties, nobody else. No anon clause: anon has no grant and
-- no policy, so it is denied twice over.
CREATE POLICY "relationship parties read"
  ON public.coach_client_relationships FOR SELECT TO authenticated
  USING (
    coach_id  = (SELECT auth.uid())
    OR client_id = (SELECT auth.uid())
  );

-- INSERT — a client enrolls themselves (pending or active: their own data,
-- their own consent), or a coach opens a PENDING invite that the client must
-- accept. initiated_by is pinned to whoever is actually inserting, because the
-- update policy below reads it to decide who may activate.
DROP POLICY IF EXISTS "relationship parties create" ON public.coach_client_relationships;
CREATE POLICY "relationship parties create"
  ON public.coach_client_relationships FOR INSERT TO authenticated
  WITH CHECK (
    coach_id <> client_id
    AND public.is_coach_profile(coach_id)
    AND (
      (   client_id    = (SELECT auth.uid())
      AND initiated_by = 'client'
      AND status IN ('pending', 'active'))
      OR
      (   coach_id     = (SELECT auth.uid())
      AND initiated_by = 'coach'
      AND status       = 'pending')
    )
  );

-- UPDATE — either party may amend their own row. The asymmetry is in the WITH
-- CHECK: a coach may leave a row in status 'active' only when the CLIENT asked
-- for the relationship. trg_relationship_integrity above stops the two ways
-- around that (repointing the row, or rewriting initiated_by).
DROP POLICY IF EXISTS "relationship parties update" ON public.coach_client_relationships;
CREATE POLICY "relationship parties update"
  ON public.coach_client_relationships FOR UPDATE TO authenticated
  USING (
    coach_id  = (SELECT auth.uid())
    OR client_id = (SELECT auth.uid())
  )
  WITH CHECK (
    client_id = (SELECT auth.uid())
    OR (
      coach_id = (SELECT auth.uid())
      AND (status <> 'active' OR initiated_by = 'client')
    )
  );

-- No DELETE policy and no DELETE grant: ending a relationship is
-- status = 'cancelled', which every call site already does. Hard deletion stays
-- with service_role.

COMMENT ON TABLE public.coach_client_relationships IS
  'AUTHORIZATION SOURCE. is_active_coach_of() -- and through it every coach-read '
  'policy on health, body, training and profile data -- trusts the contents of '
  'this table. Treat any change to its RLS as a change to the whole '
  'authorization model, and never grant a write path that lets one party name '
  'the other without consent (see migration 113).';
