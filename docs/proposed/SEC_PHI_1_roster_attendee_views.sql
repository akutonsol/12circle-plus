-- =============================================================================
-- SEC-PHI-1 — narrow the team-lead and event-host arms of the user_profiles
--              SELECT policy to column-limited views.
--
-- STATUS: **PROPOSAL. AUTHORED, UNNUMBERED, NOT APPLIED.**
--
-- docs/MASTER_REMEDIATION_WAVES.md reserves migration numbers **132+**,
-- "assigned at wave entry, never before". This file therefore carries no
-- number and must not be applied as-is. It is evidence of an intended
-- remediation, not the remediation.
--
-- Authored by the security/QA workstream (AG-01 scope). Requires AG-02 review
-- per the registry's pairing matrix (RLS/grants: AG-01 primary, AG-02 review).
-- =============================================================================
--
-- THE FINDING
-- -----------
-- Migration 102 replaced two blanket `USING (true)` policies on
-- `public.user_profiles` with:
--
--     CREATE POLICY "own profile or active coach reads profile"
--       ON public.user_profiles FOR SELECT TO authenticated
--       USING ( id = auth.uid()
--            OR public.is_active_coach_of(id)
--            OR public.is_team_lead_of(id)
--            OR public.hosts_event_for(id) );
--
-- The last two arms each grant the **entire profile row**. That row contains
-- `parq_answers` (the PAR-Q medical questionnaire), `weight_kg`,
-- `goal_weight_kg`, `transformation_photo_urls`, `membership_tier` and
-- `stripe_details_submitted`.
--
--   * `is_team_lead_of` = EXISTS(coach_team_members WHERE coach_id = auth.uid()
--     AND member_id = target). It has **no status or active condition** — unlike
--     `is_active_coach_of`, which requires `status = 'active'`. There is no
--     revocation path: a row in `coach_team_members` grants access to a team
--     member's medical history indefinitely.
--
--   * `hosts_event_for` = EXISTS(event_registrations JOIN events
--     WHERE events.vendor_id = auth.uid() AND registrations.user_id = target).
--     **A vendor gains the full profile of anyone who registers for their
--     event, permanently, from a single registration** — including PAR-Q.
--
-- Migration 102 states the correct principle for the messaging case in its own
-- comments:
--
--     "The message list has to render the OTHER participant's name and avatar.
--      That is the whole requirement -- no contact, medical, intake or billing
--      column is involved -- so it is served by a narrow view rather than by a
--      row grant on user_profiles."
--
-- It then did not apply that principle to these two arms. This proposal does.
--
-- WHAT THE SURFACES ACTUALLY CONSUME (measured, not assumed)
-- ----------------------------------------------------------
--   Team roster    apps/mobile/lib/features/coach/presentation/
--                  coach_business_screen.dart:67
--                  -> user_profiles(first_name, last_name, email, avatar_url)
--
--   Attendee list  apps/mobile/lib/features/vendor/data/vendor_service.dart:41
--                  -> user_profiles(first_name, last_name, email, avatar_url)
--
-- Four columns each. Neither reads a medical, body-composition or billing
-- column. Dropping the two arms costs those surfaces nothing once the views
-- below exist.
--
-- =============================================================================
-- ⚠ CORRECTION 2026-09-27 — THIS PROPOSAL IS NECESSARY BUT NOT SUFFICIENT
-- =============================================================================
--
-- Written before the local↔cloud reconciliation. The Cloud workstream's
-- QAX-SEC-08 (P0, live-reproduced) supplies a root cause this file does not
-- address, and it changes what "fixed" means here.
--
-- THE MISSING LINK. `coach_team_members` carries, from 002:146:
--
--     CREATE POLICY "Head coach manages team"
--       ON coach_team_members FOR ALL USING (coach_id = auth.uid());
--
-- `FOR ALL` with a USING clause and **no WITH CHECK**. Postgres reuses USING as
-- the INSERT check, so ANY authenticated user may insert a row naming
-- themselves `coach_id` and ANY victim as `member_id` — becoming a "team lead"
-- of a stranger on demand. That satisfies `is_team_lead_of()`, which carries no
-- status condition, which satisfies the `102` arm this file drops.
--
-- This is not a new class. It is member 12 of the 15 policies already ratcheted
-- locally as **F-21 / OD-14** by `test/unit/rls_policy_shape_guard_test.dart`
-- (SEC-G1), whose header records the same shape proven exploitable on
-- `workout_programs` (F-21b: a client fixture created, self-assigned and
-- cross-assigned a programme, all 201). What was new in Run 2 is the
-- **composition**: that one member of that population chains into a full
-- `user_profiles` read, i.e. PAR-Q and medical history. Three separately
-- recorded facts that nobody had joined up.
--
-- WHAT THIS MEANS FOR THE VIEWS BELOW.
-- `team_member_profiles` is defined `... OR public.is_team_lead_of(p.id)`.
-- Applying this file alone therefore still lets a **self-made** team lead read
-- `first_name, last_name, email, avatar_url` for **any user in the system**.
-- That is a large reduction — PAR-Q, medical history, weight and billing stop
-- being reachable — but it is NOT closure: it leaves unauthenticated-style
-- enumeration of every member's name and **email address**, which is PII.
--
-- REQUIRED COMPANION CHANGE (same wave, not a follow-up):
-- constrain who may create a team membership. Cloud's simulated fix
-- (`supabase/tests/qa_exhaustion/fixsim/QAX-SEC-08.sql`) models consent —
-- the LEAD may not insert, the MEMBER may:
--
--     alter policy "Head coach manages team" on public.coach_team_members
--       using (coach_id = auth.uid()) with check (false);
--     create policy "member joins team" on public.coach_team_members
--       for insert to authenticated with check (member_id = auth.uid());
--
-- That is a model, not an approved policy: "what a team means" is **OD-QAX-9**
-- and the 15-policy population is **OD-14**. Both are owner decisions. Do not
-- apply either half of this without them.
--
-- =============================================================================

-- OPEN QUESTION FOR THE OWNER (do not resolve in this file)
-- ---------------------------------------------------------
-- Both rosters currently render `email`. That is PII, and whether an event
-- vendor should receive an attendee's email address is a product/legal
-- decision, not a QA one. The views below **preserve current behaviour** by
-- including it. If the owner rules otherwise, drop `email` from
-- `event_attendee_profiles` and adjust `vendor_service.getRegistrations`.
--
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The two column-limited views, mirroring 102's
--    `conversation_participant_profiles`.
--
--    `security_invoker = on` so the view does NOT bypass RLS: the caller's own
--    permissions still apply to the underlying rows, and the view's job is to
--    limit COLUMNS, not to grant rows. The row predicate is carried in the
--    view's WHERE clause and re-uses the existing helper functions so there is
--    exactly one definition of "is a team lead of" in the schema.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.team_member_profiles
WITH (security_invoker = on) AS
  SELECT p.id, p.first_name, p.last_name, p.email, p.avatar_url
    FROM public.user_profiles p
   WHERE p.id = auth.uid()
      OR public.is_team_lead_of(p.id);

CREATE OR REPLACE VIEW public.event_attendee_profiles
WITH (security_invoker = on) AS
  SELECT p.id, p.first_name, p.last_name, p.email, p.avatar_url
    FROM public.user_profiles p
   WHERE p.id = auth.uid()
      OR public.hosts_event_for(p.id);

REVOKE ALL ON public.team_member_profiles   FROM PUBLIC, anon;
REVOKE ALL ON public.event_attendee_profiles FROM PUBLIC, anon;
GRANT SELECT ON public.team_member_profiles   TO authenticated;
GRANT SELECT ON public.event_attendee_profiles TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. Drop the two wide arms from the base-table policy.
--
--    `id = auth.uid()` and `is_active_coach_of(id)` REMAIN. An active coach
--    legitimately needs the PAR-Q — that is the clinical point of the intake —
--    and `is_active_coach_of` already requires `status = 'active'`, which the
--    live probe confirmed denies a coach whose relationship is `cancelled`.
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "own profile or active coach reads profile"
  ON public.user_profiles;

CREATE POLICY "own profile or active coach reads profile"
  ON public.user_profiles FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR public.is_active_coach_of(id)
  );

COMMIT;

-- =============================================================================
-- REQUIRED APPLICATION CHANGE — MUST LAND IN THE SAME WAVE
-- =============================================================================
--
-- Applying this file ALONE breaks two screens. Both currently reach
-- `user_profiles` through a PostgREST embedded resource, which resolves
-- against the base table and will start returning nothing:
--
--   coach_business_screen.dart:67
--     .select('*, user_profiles!coach_team_members_member_id_fkey(
--                 first_name, last_name, email, avatar_url)')
--     -> must embed/join `team_member_profiles` instead
--
--   vendor_service.dart:41
--     .select('..., user_profiles(first_name, last_name, email, avatar_url)')
--     -> must embed/join `event_attendee_profiles` instead
--
-- An embedded resource needs a foreign-key relationship for PostgREST to
-- traverse it. A view has none, so these two call sites will most likely need
-- to become explicit two-step reads (ids, then a filtered select on the view)
-- rather than a single embedded select. **That is a real integration cost and
-- must be prototyped before this migration is scheduled**, not discovered
-- during it. This is the SEC-VOICE-2 lesson: the one-line schema change was
-- safe, and the resolver on the other side of it was not.
--
-- =============================================================================
-- VERIFICATION TO RUN AFTER APPLYING (not yet possible — see below)
-- =============================================================================
--
-- The QA environment currently has **no rows** in `coach_team_members` or
-- `event_registrations`, so neither the present defect nor this fix can be
-- demonstrated live. Both arms returned `false` for every fixture identity in
-- the live probe, which is absence of data, not absence of exposure.
--
-- Provisioning those fixtures requires `QA_SERVICE`, which is not present in
-- any environment file. Until it is, the following stays UNVERIFIABLE:
--
--   1. team lead   -> member's `parq_answers`      expect: 0 rows
--   2. event host  -> attendee's `parq_answers`    expect: 0 rows
--   3. team lead   -> `team_member_profiles`       expect: the 4 columns
--   4. event host  -> `event_attendee_profiles`    expect: the 4 columns
--   5. active coach-> client's `parq_answers`      expect: STILL PERMITTED
--   6. former coach-> client's `parq_answers`      expect: 0 rows (regression)
--
-- Step 5 is the one that matters most: this change must not break the coach's
-- clinical access. Step 6 is already VERIFIED live today and must stay so.
-- =============================================================================
