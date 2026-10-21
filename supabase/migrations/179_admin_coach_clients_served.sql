-- ═══════════════════════════════════════════════════════════════════════════
-- V5 §193 · "Clients served" — the fourth People requirement
--
-- WHY THIS EXISTS. §185.2 audited the published People page against its stated data
-- requirements and recorded *"three requirements are deliberately absent, and each is
-- stated"*: last active, coach verification, and partner approval states. The requirement
-- list has FOUR items — "account list with role, status, last active; coach verification;
-- CLIENT ASSIGNMENT; Wellness Partner onboarding and approval states" — so the audit was
-- one short, and the missing item was neither built nor explained. That is the worst of the
-- three possible states: a reader of §185.2 would conclude it was covered.
--
-- The approved Coaches module carries six overview tiles. Three are built
-- (Active N of M, Inactive "no client 30 d+", and the role totals); one is recorded as
-- unbuildable (Pending/verification — no verification state exists in the schema); and
-- "Clients served — 2,210 · avg 15.7 per coach" is this one.
--
-- WHY IT IS MECHANICAL AND NOT A DECISION. Two things are needed and the record already
-- fixes both:
--
--   1. THE PREDICATE. `coach_client_relationships.status = 'active'` is the same predicate
--      migration 172 already uses for METRIC-03's `active_coaches`. Nothing new is defined.
--
--   2. THE DENOMINATOR, which the DESIGN'S OWN ARITHMETIC settles rather than I do. The
--      card shows 2,210 clients served, "avg 15.7 per coach", and Active "141 of 164".
--      2210 / 141 = 15.67 → "15.7". 2210 / 164 = 13.47, which would have printed "13.5".
--      So the average is per ACTIVE coach, and that is read off the approved numbers, not
--      chosen. This is the same method §162 used to settle METRIC-06b.
--
-- THREE-STATE RULE, APPLIED TO THE AVERAGE. `NULLIF` on the denominator means a platform
-- with no active coaches reports the average as NULL, not 0. An average of zero clients
-- per coach is a measurement; "there are no coaches to average over" is not, and the two
-- must not render alike. The count itself is a real count and is 0 when it is 0.
--
-- WHAT IS STILL NOT BUILT, and stated so this is not read as closing the module:
--   · "Pending · awaiting review" — no verification state exists (§185.2, unchanged).
--   · "Programs live" — `workout_programs` (001:69) carries name, goal, difficulty,
--     duration_weeks and is_template, and NO lifecycle state. A program's "live" is
--     undefined in the schema; deriving it from assignment status would invent the
--     lifecycle the Ecosystem Programs table's Active/Archived column also lacks.
--   · "Sessions · 30 d — coach-led" — "coach-led" is not a column. It could mean a session
--     by a client with an active coach, or one against a coach-authored program; the two
--     differ and nothing rules between them.
--   · "Reassign clients" — a write with no governed path and no defined triage model.
--
-- Additive: two columns appended to an existing view. No table, no column, no grant and no
-- policy changes. The view keeps its `admin_can('Users','view')` gate, so the figures are
-- unreachable without the capability that already governs the rest of the card.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.admin_user_overview
WITH (security_invoker = off) AS
  WITH ages AS (
    SELECT COALESCE(date_part('year', age(date_of_birth))::int, age) AS yrs
      FROM public.user_profiles
  ),
  month AS (SELECT date_trunc('month', now()) AS s, date_trunc('month', now()) + interval '1 month' AS e),
  active_coaches AS (
    SELECT DISTINCT r.coach_id
      FROM public.coach_client_relationships r, month m
     WHERE r.status = 'active'
        OR (r.cancelled_at >= m.s AND r.cancelled_at < m.e)
  )
  SELECT
    (SELECT count(*) FROM public.user_profiles)                                 AS users_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'client')           AS clients_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'coach')            AS coaches_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'vendor')           AS vendors_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'admin')            AS admins_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'content_manager')  AS content_managers_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'trust_operator')   AS trust_operators_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'erasure_executor') AS erasure_executors_total,
    -- METRIC-03
    (SELECT count(*) FROM public.user_profiles p
      WHERE p.role = 'coach' AND p.id IN (SELECT coach_id FROM active_coaches))       AS coaches_active_this_month,
    (SELECT count(*) FROM public.user_profiles p
      WHERE p.role = 'coach' AND p.id NOT IN (SELECT coach_id FROM active_coaches
                                               WHERE coach_id IS NOT NULL))           AS coaches_no_client_this_month,
    -- METRIC-17 · half-open, fourth bucket = unknown
    (SELECT count(*) FROM ages WHERE yrs >= 18 AND yrs < 30)                     AS age_18_30,
    (SELECT count(*) FROM ages WHERE yrs >= 30 AND yrs < 45)                     AS age_30_45,
    (SELECT count(*) FROM ages WHERE yrs >= 45 AND yrs < 60)                     AS age_45_60,
    (SELECT count(*) FROM ages WHERE yrs IS NULL)                                AS age_unknown,
    (SELECT count(*) FROM ages WHERE yrs IS NOT NULL AND (yrs < 18 OR yrs >= 60)) AS age_out_of_range,
    -- ── §193 · "Clients served", and its average per ACTIVE coach ───────────
    -- A real count: 0 here means no active relationship exists, which is a fact.
    (SELECT count(*) FROM public.coach_client_relationships WHERE status = 'active')
                                                                                 AS coach_clients_served,
    -- NULL, not 0, when there is no active coach to divide by. See the header.
    (SELECT round(
       (SELECT count(*) FROM public.coach_client_relationships WHERE status = 'active')::numeric
         / NULLIF((SELECT count(*) FROM public.user_profiles p
                    WHERE p.role = 'coach'
                      AND p.id IN (SELECT coach_id FROM active_coaches)), 0), 1))
                                                                                 AS coach_clients_per_active_coach
  WHERE public.admin_can('Users', 'view');

COMMENT ON VIEW public.admin_user_overview IS
  'V5 §193 · role counts (166), METRIC-03 (active coaches, CALENDAR month), METRIC-17 '
  '(age buckets, half-open, fourth bucket = unknown) and "Clients served" with its '
  'average per ACTIVE coach. age_out_of_range exists so the buckets reconcile to '
  'users_total. The average denominator is the ACTIVE coach count because the approved '
  'card''s own arithmetic fixes it (2210/141 = 15.7, where 2210/164 would be 13.5), and '
  'it is NULL rather than 0 when there is no active coach to divide by. Gated '
  'admin_can(''Users'',''view''). No row identifies anyone.';

REVOKE ALL ON public.admin_user_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_user_overview TO authenticated;
