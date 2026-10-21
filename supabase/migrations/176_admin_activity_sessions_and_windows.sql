-- ═══════════════════════════════════════════════════════════════════════════
-- 176 · METRIC-02 · the SESSION COUNT the approved design requires, and the
--       window boundaries the figures are actually computed over.
--
-- TWO THINGS 172 GOT INCOMPLETE, FOUND BY RE-READING THE DATA CONTRACT RATHER THAN
-- MY OWN NOTES.
--
-- 1 · `daily_sessions` IS A REQUIRED MEASURE AND WAS MISSING.
-- `V5_ADMIN_DASHBOARD_DATA_CONTRACT:97` is explicit: the Ecosystem activity card
-- "adds *947 Daily sessions*, so **DAU and sessions are distinct required measures**",
-- and :101 fixes the contract shape as
-- `{ dau, wau, mau, mom_change_pct, daily_sessions }`.
-- 172 built DISTINCT-USER counts on both bases and no session count at all. A member
-- who trains twice in a day is one active user and two Sessions, so the two figures
-- are not interchangeable and the design shows both. Added here as `sessions_today`
-- and `sessions_month` — `count(*)`, not `count(DISTINCT user_id)`.
--
-- 2 · THE WINDOW BOUNDARIES WERE AN INVISIBLE ASSUMPTION.
-- `date_trunc('day', now())` is evaluated in the DATABASE's timezone, which is UTC.
-- The same data contract at :98 names the timezone as one of the sub-questions the
-- owner's definition "must settle", and the METRIC-02 ruling (Option 3 — both bases,
-- shown separately) answered WHICH EVENTS COUNT and nothing about the timezone.
--
-- This migration does NOT choose a timezone. It EXPOSES the boundaries each figure was
-- computed over, so a reader can tell what "today" meant and the assumption stops being
-- invisible. That is the same discipline as METRIC-06a's recorded FX rate and
-- METRIC-11's per-verdict provenance: where the answer is not ours to give, publish
-- what was actually used.
--
-- STILL NOT ANSWERED, AND NOT GUESSED: the contract's third sub-question — whether a
-- coach or partner counts as an "active user" or only clients. These counts are over
-- every user who has a Session, with no role filter, which is what 172 shipped. A role
-- filter would be a business definition, so it is recorded for the owner rather than
-- invented. The population is at least DISCLOSED by `*_all_roles` being the plain
-- reading of the column names, and the owner pack carries the question.
-- ═══════════════════════════════════════════════════════════════════════════

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
    -- ── NEW · the session COUNT, which is not a user count (contract :97) ──
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(*) FROM public.workout_sessions
        WHERE started_at >= date_trunc('day', now())) END          AS sessions_today,
    CASE WHEN public.admin_can('Users', 'view') THEN
      (SELECT count(*) FROM public.workout_sessions
        WHERE started_at >= date_trunc('month', now())) END        AS sessions_month,
    -- ── NEW · the boundaries these figures were computed over ──────────────
    -- Not decoration. Without them "today" is an assumption the reader cannot see,
    -- and the governing contract names the timezone as an open sub-question.
    date_trunc('day', now())                                       AS day_start,
    date_trunc('week', now())                                      AS week_start,
    date_trunc('month', now())                                     AS month_start,
    current_setting('TimeZone')                                     AS window_timezone
  WHERE public.admin_can('Users', 'view') OR public.admin_can('Security', 'view');

COMMENT ON VIEW public.admin_activity_overview IS
  'V5 §173 · METRIC-02 = Option 3. The two bases are reported SEPARATELY and gated '
  'SEPARATELY: Session columns on Users·view, sign-in columns on Security·view '
  '(ruling B-1 places category `authentication` in Security). A role holding one and '
  'not the other sees NULL — not 0 — for the other basis. `sessions_today` / '
  '`sessions_month` are SESSION COUNTS, not user counts: the approved design shows '
  '"947 Daily sessions" beside the DAU figure and the data contract (:97) calls them '
  'distinct required measures. day_start/week_start/month_start/window_timezone '
  'publish the boundaries each figure was computed over, because the contract (:98) '
  'names the timezone as an unsettled sub-question and an invisible assumption is '
  'worse than a disclosed one. No pseudonym is resolved; only counts leave this view.';

REVOKE ALL ON public.admin_activity_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_activity_overview TO authenticated;
