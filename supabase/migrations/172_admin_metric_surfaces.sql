-- ═══════════════════════════════════════════════════════════════════════════
-- 172 · THE AUTHORIZED METRICS — owner decisions of 2026-10-07
--   METRIC-02 = Option 3  both Session and sign-in, shown separately
--   METRIC-03 = Option 1  calendar month
--   METRIC-13 = Option 1  a pod is an `accountability_pods` row
--   METRIC-14 = Option 2  attended ÷ registered
--   METRIC-17 = Option 2  the fourth bucket is `unknown`
-- Decided WITHOUT implementation, and so absent here by instruction, not omission:
--   METRIC-05 = 2 (total only — already served by admin_user_overview.vendors_total)
--   METRIC-16 = 2 · METRIC-18 producer = N · METRIC-19 = 3 (out of scope V1)
--
-- Pattern is 166's: security_invoker = off, authorization in the view's own WHERE,
-- write grants revoked. Every view is additive; nothing existing is narrowed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0 · a correction to 171, not a change of behaviour ─────────────────────
-- 171's comment claimed coaching kinds "carry payments.coach_id". Live QA refutes
-- it: the one paid `package` row has coach_id NULL. The SELECTOR was never coach_id
-- — it is the kind vocabulary at create-checkout:52 — so the figures stand, but the
-- stated justification was wrong and is withdrawn here rather than left on record.
COMMENT ON VIEW public.admin_revenue_overview IS
  'V5 §162 · METRIC-06a/06b. Gross · commission · net, per the owner''s calculation, '
  'in the SOURCE currency. Qualifying coaching payments are kind IN (coach, package) '
  '— the two kinds in the create-checkout:52 vocabulary by which a member pays a '
  'coach for coaching, as against coach_plan (a coach paying 12 Circle), '
  'self_guided/ai_guided (member plans) and event_ticket. The selector is the kind, '
  'NOT coach_id: that column is nullable and is in fact NULL on live paid rows. '
  'Commission uses the per-payment commission_rate (038:23) as it applied; payments '
  'missing it are counted in commission_rate_missing, never given a substituted '
  'rate. NO GBP figure is computed: fx_usd_gbp_rate/as_of/source carry the recorded '
  'rate and are NULL when none exists.';

-- ── 1 · METRIC-02 · activity, on two bases, separately gated ───────────────
-- The two bases do NOT share an authorization source, and the card must not become
-- a side channel into the audit population. The Session basis reads user activity
-- (Users·view). The sign-in basis reads audit_events category `authentication`,
-- which ruling B-1 placed in the SECURITY area — so it is gated Security·view and
-- returns NULL, not zero, to a role holding Users without Security.
--
-- Windows. "Calendar" is the owner's ruling for "this month" (METRIC-03), applied
-- here for consistency; the month-on-month delta the card shows is only coherent on
-- calendar months. `week` is date_trunc('week') for the same reason. The weekly
-- window itself was not separately ruled — recorded as an applied convention.
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
          AND occurred_at <  date_trunc('month', now())) END       AS signin_users_prev_month
  WHERE public.admin_can('Users', 'view') OR public.admin_can('Security', 'view');

COMMENT ON VIEW public.admin_activity_overview IS
  'V5 §162 · METRIC-02 = Option 3. The two bases are reported SEPARATELY and gated '
  'SEPARATELY: Session columns on Users·view, sign-in columns on Security·view '
  '(ruling B-1 places category `authentication` in Security). A role holding one and '
  'not the other sees NULL — not 0 — for the other basis, so the card cannot be used '
  'to read the audit population indirectly. No pseudonym is resolved and no actor is '
  'identified: only DISTINCT counts leave this view.';

REVOKE ALL ON public.admin_activity_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_activity_overview TO authenticated;

-- ── 2 · METRIC-03 + METRIC-17 · appended to the existing Users surface ─────
-- Same gate as 166's view, so these belong on it rather than in a new surface.
-- METRIC-03: a coach counts as active this CALENDAR month if they hold a currently
-- active relationship, or one cancelled within the month. `activated_at` is NOT the
-- window column: it is NULL on 117 of 118 live active rows, so a window computed on
-- it would be vacuous — exactly the defect QA_CLOSURE_STANDARD §5.2 warns of.
-- METRIC-17: the owner ruled the FOURTH BUCKET is `unknown`. Half-open intervals are
-- forced by the design's overlapping labels. `date_of_birth` is preferred where
-- present and `user_profiles.age` is the fallback — both columns exist, dob is
-- populated on 0 rows and age on 4, so using only dob would make the panel vacuous.
-- An age at or above 60 has NO ruled bucket; such rows are counted in
-- `age_out_of_range` so the four buckets plus that column reconcile to users_total.
-- That column is a RECONCILIATION figure, not a fifth card bucket.
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
    (SELECT count(*) FROM ages WHERE yrs IS NOT NULL AND (yrs < 18 OR yrs >= 60)) AS age_out_of_range
  WHERE public.admin_can('Users', 'view');

COMMENT ON VIEW public.admin_user_overview IS
  'V5 §162 · role counts (166) plus METRIC-03 (active coaches, CALENDAR month) and '
  'METRIC-17 (age buckets, half-open, fourth bucket = unknown). age_out_of_range '
  'exists so the buckets reconcile to users_total: an age >= 60 has no ruled bucket '
  'and is NOT silently dropped. Age prefers date_of_birth and falls back to '
  'user_profiles.age. Gated admin_can(''Users'',''view''). No row identifies anyone.';

REVOKE ALL ON public.admin_user_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_user_overview TO authenticated;

-- ── 3 · METRIC-14 · attendance, appended to the Events surface ─────────────
-- The sheet recorded that "no attendance column exists" and that option 2 "requires
-- a new column and a capture mechanism". BOTH STATEMENTS WERE WRONG, and the error
-- was mine: it came from looking for a column named `attended`.
-- event_registrations.checked_in_at exists (migration 138) and IS written today, by
-- vendor_service.dart:90-93 on check-in. METRIC-14 therefore needs NO new column and
-- NO new capture mechanism. The rate is NULL, not 0%, when there is nothing to divide.
CREATE OR REPLACE VIEW public.admin_events_overview
WITH (security_invoker = off) AS
  SELECT
    (SELECT count(*) FROM public.events)              AS events_total,
    (SELECT count(*) FROM public.event_registrations) AS event_registrations_total,
    (SELECT count(*) FROM public.classes)             AS classes_total,
    (SELECT count(*) FROM public.class_bookings)      AS class_bookings_total,
    -- METRIC-14
    (SELECT count(*) FROM public.event_registrations
      WHERE checked_in_at IS NOT NULL)                AS event_registrations_attended,
    (SELECT round(
       count(*) FILTER (WHERE checked_in_at IS NOT NULL)::numeric
         / NULLIF(count(*), 0) * 100, 1)
       FROM public.event_registrations)               AS event_attendance_rate_pct,
    (SELECT count(*) FROM public.event_registrations
      WHERE registered_at >= now() - interval '30 days') AS event_registrations_30d
  WHERE public.admin_can('Events', 'view');

COMMENT ON VIEW public.admin_events_overview IS
  'V5 §162 · event counts (166) plus METRIC-14 = attended / registered, where '
  '"attended" is checked_in_at IS NOT NULL — a column that already exists (138) and '
  'is already written (vendor_service.dart:90-93), contrary to the decision sheet''s '
  'note. The rate is NULL with zero registrations, so the card renders an A11 empty '
  'state rather than a misleading 0%. The 30-day window is the approved design''s own '
  'label ("Registrations · 30 d"). Gated admin_can(''Events'',''view'').';

REVOKE ALL ON public.admin_events_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_events_overview TO authenticated;

-- ── 4 · METRIC-13 · a pod is an accountability_pods row ────────────────────
CREATE OR REPLACE VIEW public.admin_community_overview
WITH (security_invoker = off) AS
  SELECT
    (SELECT count(*) FROM public.accountability_pods)                  AS pods_total,
    (SELECT count(*) FROM public.accountability_pods
      WHERE status = 'active')                                         AS pods_active,
    (SELECT count(*) FROM public.community_groups)                     AS community_groups_total,
    (SELECT count(*) FROM public.community_posts)                      AS posts_total,
    (SELECT count(*) FROM public.community_posts
      WHERE moderation_state = 'visible')                              AS posts_visible,
    (SELECT count(*) FROM public.content_reports
      WHERE resolved_at IS NULL)                                       AS reports_open
  WHERE public.admin_can('Community', 'view');

COMMENT ON VIEW public.admin_community_overview IS
  'V5 §162 · METRIC-13 = Option 1: a "pod" is an accountability_pods row. '
  'community_groups is reported alongside it as a distinct figure, never merged into '
  'the pod count. Moderation counts come from 170. Gated '
  'admin_can(''Community'',''view'').';

REVOKE ALL ON public.admin_community_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_community_overview TO authenticated;
