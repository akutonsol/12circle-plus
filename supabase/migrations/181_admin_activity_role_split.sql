-- ---------------------------------------------------------------------------
-- 181 · Q2 / METRIC-02 sub-answer — the active-user ROLE SPLIT, published.
--
-- OWNER DECISION, verbatim from V5_METRIC_DECISION_SHEET.md (METRIC-02):
--   "RESOLVED 2026-10-08 · the active-user population is ALL users, with the
--    role split PUBLISHED beside the total. Not clients-only and not an
--    unexplained aggregate: the split is to be shown, so a reader can apply
--    either definition. Not yet implemented -- authorized here, built later."
--
-- This is "built later". It closes the last of the three sub-questions the data
-- contract (:98) put to the owner -- "whether a coach or partner counts as an
-- 'active user' or only clients" -- the other two having been settled by
-- METRIC-02 = Option 3 (172) and the UTC/Monday ratification (176).
--
-- ── WHY A ROLE MAP AND NOT NAMED BUCKETS ───────────────────────────────────
-- The obvious shape would be columns like `active_clients` / `active_coaches` /
-- `active_partners`. That shape INVENTS. The schema's role vocabulary (142) is
--   client · coach · vendor · admin · content_manager · trust_operator ·
--   erasure_executor
-- and NULL is permitted. Deciding that `vendor` is what the contract's question
-- calls a "partner", or that the four staff roles collapse into one bucket, is
-- a metric definition the owner has not issued -- and the decision's own words
-- are that the reader must be able to "apply EITHER definition", which a
-- pre-collapsed bucket forecloses.
--
-- So the split is published as a role -> count map. It invents no grouping,
-- survives a future role being added to 142's CHECK without a migration here,
-- and lets the reader compute clients-only, clients+coaches, or any other
-- reading for themselves.
--
-- ── THE TWO NON-ROLES ARE DISTINGUISHED, NOT MERGED ────────────────────────
-- Three states, kept apart on purpose (the §19.4 discipline):
--   * a real role           -> that role's key
--   * `no_profile` -- the actor has NO `user_profiles` row at all. For the
--     sign-in basis this is a legitimate, documented case: 142:113-115 says the
--     ledger "must accept actors that were never users".
--   * `unrecorded` -- a profile exists and its `role` is NULL. 115 added the
--     role CHECK but did not make the column NOT NULL, so this is reachable.
-- Collapsing these two into one "unknown" would report a missing profile and an
-- unset column as the same finding. They are not the same finding.
--
-- ── THE INVARIANT THIS BUYS, AND WHY IT IS TESTABLE ────────────────────────
-- Every user_id / actor_id falls in EXACTLY ONE bucket (`user_profiles.id` is
-- the PK, so the LEFT JOIN cannot fan out). Therefore, for each window:
--     sum(values of the map) == the matching total column
-- That is an equality a live test can assert without knowing the population,
-- and it is what makes this a published split rather than a second, unrelated
-- count that happens to sit nearby. NULL identifiers are excluded explicitly so
-- the two sides agree exactly: `count(DISTINCT x)` already ignores NULL, so the
-- guard is what keeps the map from reporting a 0-valued bucket the total omits.
--
-- ── §19.3 IS NOT ENGAGED, AND THAT WAS CHECKED, NOT ASSUMED ────────────────
-- The sign-in basis joins `audit_events.actor_id` to `user_profiles`. That is
-- NOT pseudonym resolution. 142:113 states the actor identifiers "are therefore
-- stored raw"; the PSEUDONYM is the NEXT column, `subject_pseudonym`, and
-- §19.3's prohibition -- which 142:313-317 applies to the active-coach arm --
-- is about resolving THAT. `subject_pseudonym` is not read here. Only counts
-- leave this view, exactly as its existing comment already promises, and no
-- standing resolver is created.
--
-- ── GATING IS INHERITED, NOT RE-DERIVED ────────────────────────────────────
-- Each new column carries the SAME `admin_can` guard as the total it splits:
-- Session on `Users·view`, sign-in on `Security·view` per ruling B-1. A role
-- holding one and not the other sees NULL -- never `{}` -- for the other basis,
-- because an empty map is a measured emptiness and NULL is an absent
-- authorization. `prev_month` is deliberately NOT split: it exists to compute a
-- delta, it is not a total displayed beside a split, and splitting it would add
-- two columns no decision asks for.
--
-- 176's view body is reproduced VERBATIM below and the Q2 columns appended,
-- which is the pattern 179 and 180 established for extending these surfaces.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.admin_activity_overview
WITH (security_invoker = off) AS
  SELECT
    -- basis A · Session (product-bible §5: a Session is one day's workout)
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(DISTINCT user_id) FROM public.workout_sessions
        WHERE started_at >= date_trunc('day', now())) END          AS session_users_today,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(DISTINCT user_id) FROM public.workout_sessions
        WHERE started_at >= date_trunc('week', now())) END         AS session_users_week,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(DISTINCT user_id) FROM public.workout_sessions
        WHERE started_at >= date_trunc('month', now())) END        AS session_users_month,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(DISTINCT user_id) FROM public.workout_sessions
        WHERE started_at >= date_trunc('month', now()) - interval '1 month'
          AND started_at <  date_trunc('month', now())) END        AS session_users_prev_month,
    -- basis B · sign-in. Security area per B-1. NULL ≠ 0.
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT count(DISTINCT actor_id) FROM public.audit_events
        WHERE category = 'authentication'
          AND occurred_at >= date_trunc('day', now())) END         AS signin_users_today,
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT count(DISTINCT actor_id) FROM public.audit_events
        WHERE category = 'authentication'
          AND occurred_at >= date_trunc('week', now())) END        AS signin_users_week,
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT count(DISTINCT actor_id) FROM public.audit_events
        WHERE category = 'authentication'
          AND occurred_at >= date_trunc('month', now())) END       AS signin_users_month,
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT count(DISTINCT actor_id) FROM public.audit_events
        WHERE category = 'authentication'
          AND occurred_at >= date_trunc('month', now()) - interval '1 month'
          AND occurred_at <  date_trunc('month', now())) END       AS signin_users_prev_month,
    -- ── the session COUNT, which is not a user count (contract :97) ────────
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(*) FROM public.workout_sessions
        WHERE started_at >= date_trunc('day', now())) END          AS sessions_today,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(*) FROM public.workout_sessions
        WHERE started_at >= date_trunc('month', now())) END        AS sessions_month,
    -- ── the boundaries these figures were computed over ────────────────────
    date_trunc('day', now())                                       AS day_start,
    date_trunc('week', now())                                      AS week_start,
    date_trunc('month', now())                                     AS month_start,
    current_setting('TimeZone')                                     AS window_timezone,

    -- ── NEW · Q2 · the role split, published beside each total ─────────────
    -- Session basis · Users·view, matching session_users_{today,week,month}.
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT s.user_id)          AS n
          FROM public.workout_sessions s
          LEFT JOIN public.user_profiles p ON p.id = s.user_id
         WHERE s.started_at >= date_trunc('day', now())
           AND s.user_id IS NOT NULL
         GROUP BY 1) q) END                       AS session_users_today_by_role,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT s.user_id)          AS n
          FROM public.workout_sessions s
          LEFT JOIN public.user_profiles p ON p.id = s.user_id
         WHERE s.started_at >= date_trunc('week', now())
           AND s.user_id IS NOT NULL
         GROUP BY 1) q) END                       AS session_users_week_by_role,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT s.user_id)          AS n
          FROM public.workout_sessions s
          LEFT JOIN public.user_profiles p ON p.id = s.user_id
         WHERE s.started_at >= date_trunc('month', now())
           AND s.user_id IS NOT NULL
         GROUP BY 1) q) END                       AS session_users_month_by_role,
    -- sign-in basis · Security·view per B-1, matching signin_users_{...}.
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT e.actor_id)         AS n
          FROM public.audit_events e
          LEFT JOIN public.user_profiles p ON p.id = e.actor_id
         WHERE e.category = 'authentication'
           AND e.occurred_at >= date_trunc('day', now())
           AND e.actor_id IS NOT NULL
         GROUP BY 1) q) END                       AS signin_users_today_by_role,
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT e.actor_id)         AS n
          FROM public.audit_events e
          LEFT JOIN public.user_profiles p ON p.id = e.actor_id
         WHERE e.category = 'authentication'
           AND e.occurred_at >= date_trunc('week', now())
           AND e.actor_id IS NOT NULL
         GROUP BY 1) q) END                       AS signin_users_week_by_role,
    CASE WHEN public.admin_can('Security', 'view') THEN
      (SELECT coalesce(jsonb_object_agg(bucket, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN p.id   IS NULL THEN 'no_profile'
                    WHEN p.role IS NULL THEN 'unrecorded'
                    ELSE p.role END               AS bucket,
               count(DISTINCT e.actor_id)         AS n
          FROM public.audit_events e
          LEFT JOIN public.user_profiles p ON p.id = e.actor_id
         WHERE e.category = 'authentication'
           AND e.occurred_at >= date_trunc('month', now())
           AND e.actor_id IS NOT NULL
         GROUP BY 1) q) END                       AS signin_users_month_by_role
  WHERE public.admin_can('Users', 'view') OR public.admin_can('Security', 'view');

COMMENT ON VIEW public.admin_activity_overview IS
  'V5 §173 · METRIC-02 = Option 3. The two bases are reported SEPARATELY and gated '
  'SEPARATELY: Session columns on Users·view, sign-in columns on Security·view '
  '(ruling B-1 places category `authentication` in Security). A role holding one and '
  'not the other sees NULL — not 0 — for the other basis. `sessions_today` / '
  '`sessions_month` are SESSION COUNTS, not user counts: the approved design shows '
  '"947 Daily sessions" beside the DAU figure and the data contract (:97) calls them '
  'distinct required measures. day_start/week_start/month_start/window_timezone '
  'publish the boundaries each figure was computed over — now an AUTHORIZATION '
  '(Q1: UTC, week starts Monday), not merely a disclosed assumption. '
  'V5 §205 · Q2 — the `*_by_role` columns publish the active-user ROLE SPLIT beside '
  'each total, per the owner ruling that the population is ALL users with the split '
  'shown so a reader can apply either definition. They are role→count MAPS rather '
  'than named buckets because collapsing 142''s seven roles into "partner"/"staff" '
  'would be a metric definition no decision issued. `no_profile` (no user_profiles '
  'row — legitimate for sign-ins per 142:113) and `unrecorded` (row exists, role '
  'NULL) are kept distinct. Each map sums EXACTLY to its total. No pseudonym is '
  'resolved: `actor_id` is stored raw (142:113) and `subject_pseudonym` is not read '
  'here, so §19.3 is not engaged. Only counts leave this view.';

REVOKE ALL ON public.admin_activity_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_activity_overview TO authenticated;
