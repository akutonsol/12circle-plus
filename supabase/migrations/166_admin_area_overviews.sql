-- ═══════════════════════════════════════════════════════════════════════════
-- 166 · USERS AND EVENTS AGGREGATE SURFACES — the same inert pattern as 163
--
-- THE GAP. `admin_platform_stats()` (019) computes thirteen platform counts and is
-- gated on `is_admin()` ALONE. Measured live: an Admin-layer `viewer`, `trust_lead`
-- and `operations_lead` all receive `42501 not authorized`, so the Admin layer can
-- see no aggregate at all — exactly the shape V5 §135 found on the AI Guardian
-- registry, where an owner-approved grant did nothing because the backend keyed on
-- a role the Admin layer deliberately does not hold (`CONF-D7`).
--
-- 019 IS NOT TOUCHED. Widening its gate would hand one caller a CROSS-AREA
-- aggregate, and the approved matrix grants View per AREA. These are two
-- self-gating views instead, each answering only for its own area.
--
-- THE PATTERN IS NOT NEW, which is why this needs no new authorization: it is
-- exactly `admin_training_overview`, authorized in 156 and shipped — counts only,
-- `security_invoker = off`, authorization in the view's own WHERE, write grants
-- revoked in the same migration.
--
-- NO MAPPING IS INVENTED. Each count sits in the area §127 already placed its table
-- in, and the owner accepted that classification:
--   · `user_profiles`  -> Users   (§127 §4.2, and 160's admin_user_directory reads it)
--   · `events`, `event_registrations`, `classes`, `class_bookings` -> Events (§127 §1.2, and 156's arms)
--
-- DELIBERATELY ABSENT, because no accepted mapping places them:
--   `coach_client_relationships` · `weekly_checkins` · `challenges`. 019 counts all
--   three; §127 maps none of them to an Admin area. Guessing one would be inventing
--   the authorization boundary, which is the thing this programme refuses to do.
--
-- AND NO OPEN METRIC IS COMPUTED HERE. The Dashboard's DAU, revenue, health, and
-- the rest each carry at least one open business definition
-- (V5_ADMIN_DASHBOARD_DATA_CONTRACT §10: "Every one of the fourteen has at least one
-- open business definition"). Nothing below defines "active", a currency, a window
-- or a threshold. These are raw counts of rows that already exist.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · Users ──────────────────────────────────────────────────────────────
-- ALL SEVEN ROLES ARE REPRESENTED. The data contract's row 1 names the gap in
-- `admin_platform_stats()` as "3 of 7 roles unrepresented" — it counts client,
-- coach, vendor and admin, and omits content_manager, trust_operator and
-- erasure_executor. Enumerating the roles the schema's own CHECK already fixes is
-- mechanical, not a product decision, and it closes the stated gap.
--
-- Counts only: no identity, no PHI, no contact detail. 160's admin_user_directory
-- remains the row-level surface and keeps its nine-column contract.
CREATE OR REPLACE VIEW public.admin_user_overview
WITH (security_invoker = off) AS
  SELECT
    (SELECT count(*) FROM public.user_profiles)                                           AS users_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'client')                     AS clients_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'coach')                      AS coaches_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'vendor')                     AS vendors_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'admin')                      AS admins_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'content_manager')            AS content_managers_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'trust_operator')             AS trust_operators_total,
    (SELECT count(*) FROM public.user_profiles WHERE role = 'erasure_executor')           AS erasure_executors_total
  WHERE public.admin_can('Users', 'view');

COMMENT ON VIEW public.admin_user_overview IS
  'V5 §145 · Users aggregate surface. Counts only — no identity, no PHI, no contact '
  'detail. All SEVEN schema roles are represented, closing the data contract row 1 '
  'gap ("3 of 7 roles unrepresented" in admin_platform_stats). Self-gating on '
  'admin_can(''Users'',''view''). Defines no open metric: these are raw row counts.';

REVOKE ALL ON public.admin_user_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_user_overview TO authenticated;

-- ── 2 · Events ─────────────────────────────────────────────────────────────
-- The four tables 156 gave the Events area, counted. "Attendance" is NOT computed:
-- the data contract's row 14 records it as undefined, and `events.current_registered`
-- is a denormalised counter with no trigger maintaining it (V5 §142), so counting
-- registrations and reading that column could legitimately disagree. This counts
-- the registration ROWS, which is a fact, and leaves "attendance" to its decision.
CREATE OR REPLACE VIEW public.admin_events_overview
WITH (security_invoker = off) AS
  SELECT
    (SELECT count(*) FROM public.events)              AS events_total,
    (SELECT count(*) FROM public.event_registrations) AS event_registrations_total,
    (SELECT count(*) FROM public.classes)             AS classes_total,
    (SELECT count(*) FROM public.class_bookings)      AS class_bookings_total
  WHERE public.admin_can('Events', 'view');

COMMENT ON VIEW public.admin_events_overview IS
  'V5 §145 · Events aggregate surface, counting the four tables 156 placed in the '
  'Events area. Does NOT compute "attendance": the data contract records it as '
  'undefined, and events.current_registered is an unmaintained counter that can '
  'legitimately disagree with the registration rows. Self-gating on '
  'admin_can(''Events'',''view'').';

REVOKE ALL ON public.admin_events_overview FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_events_overview TO authenticated;
