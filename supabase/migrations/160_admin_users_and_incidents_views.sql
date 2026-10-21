-- ═══════════════════════════════════════════════════════════════════════════
-- 160 · THE USERS AND INCIDENTS PROJECTIONS — owner decisions B-2 and B-4,
--        2026-10-05
--
-- Both are the curated-view architecture the owner authorized for Audit logs and
-- which 156/159 proved. Both revoke their write grants IN THIS MIGRATION, naming
-- all three roles per the 118 pattern — the V5 §129.2 lesson at source.
--
-- TWO BOUNDARIES CLOSED IN THE SAME ROUND WITH NO CODE, recorded here so a reader
-- does not look for the migration that implements them:
--   · B-3 Training row-level — owner decided AGGREGATE ONLY. The existing
--     admin_training_overview is the whole answer; row-level training stays denied,
--     now as a CONFIRMED privacy boundary rather than a parked gap.
--   · B-8 platform_settings — owner decided CONFIRM BY DESIGN. It holds one row,
--     marketplace_commission_rate, and 039's own comment states why it must be
--     readable: "checkout/coach need the rate". My flagging of it is withdrawn.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1 · Users — owner decision B-2: IDENTITY AND ACCOUNT STATE ONLY ─────────
-- `user_profiles` is the most PHI-dense table in the schema. It carries
-- medical_conditions, parq_answers, has_injuries, injury_locations,
-- injury_description, date_of_birth, height_cm, weight_kg, sleep_hours,
-- stress_level, dietary_restrictions, food_allergies, the derived risk_score /
-- risk_level / risk_flags, and the financial identifiers stripe_customer_id and
-- stripe_account_id. The approved matrix grants `Users` View to ALL FIVE roles.
--
-- The owner chose the narrowest option offered: identity and account state. Every
-- other column is ABSENT BY CONSTRUCTION, not merely unselected by the UI.
--
-- `phone` is NOT here. It was excluded from the chosen option and is contact PII.
-- The risk_* fields are NOT here: they were offered as a third option and declined,
-- because a risk_level discloses something about a member's health even when the
-- fields it derives from stay hidden. Do not add either without a new decision.
--
-- This changes nothing about user_profiles' own RLS, which still governs every
-- direct read. D7's five column-limited views are unaffected.
CREATE OR REPLACE VIEW public.admin_user_directory
WITH (security_invoker = off) AS
  SELECT u.id, u.first_name, u.last_name, u.email, u.avatar_url, u.role,
         u.membership_tier, u.onboarding_complete, u.created_at
    FROM public.user_profiles u
   WHERE public.admin_can('Users', 'view');

COMMENT ON VIEW public.admin_user_directory IS
  'V5 §134 · the Users area projection. Owner decision B-2: identity and account '
  'state ONLY. user_profiles PHI (medical_conditions, parq_answers, injury_*, '
  'date_of_birth, height_cm, weight_kg, sleep_hours, stress_level, dietary_*, '
  'food_allergies), the derived risk_score/risk_level/risk_flags, the Stripe '
  'identifiers and `phone` are ABSENT BY CONSTRUCTION. risk_* and phone were '
  'offered and declined — do not add either without a new owner decision. The '
  'Support Update write path remains PARKED (B-2 second half).';

REVOKE ALL ON public.admin_user_directory FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_user_directory TO authenticated;

-- ── 2 · Incidents — owner decision B-4: NO evidence, NO actor_identity ──────
-- §127 named the unbounded `evidence` jsonb as the reason a curated view was
-- required. Inspecting the live population corrected that: `evidence` is EMPTY in
-- every row, while `actor_identity` holds a REAL uuid — a direct identity, not a
-- pseudonym, which resolves to a person WITHOUT passing through the audit identity
-- map that §19.3 governs. The risk §127 did not name was the larger one, and the
-- matrix grants `Incidents` View to `viewer` as well as the two leads.
--
-- The owner withheld BOTH. An Admin sees what happened and how it was handled.
--   · `evidence` is unbounded free-form and cannot be shown safe in advance;
--   · `actor_identity` is a direct identity and is therefore an A12 surface.
--
-- `actor_provenance`, `created_at` and `updated_at` are also absent: they were not
-- in the chosen column set, and this view is built to the decision rather than to
-- what seemed harmless to add.
CREATE OR REPLACE VIEW public.admin_incidents
WITH (security_invoker = off) AS
  SELECT i.id, i.summary, i.occurred_at, i.scope, i.severity,
         i.suspected_cause, i.recommended_action, i.action_taken,
         i.approval_status, i.resolution
    FROM public.audit_incidents i
   WHERE public.admin_can('Incidents', 'view');

COMMENT ON VIEW public.admin_incidents IS
  'V5 §134 · the Incidents area projection. Owner decision B-4: withhold BOTH '
  '`evidence` (unbounded free-form, cannot be shown safe in advance) and '
  '`actor_identity` (a DIRECT identity, not a pseudonym, so an A12 surface — the '
  'risk §127 did not name). audit_incidents own policy is untouched. Severity is '
  'not Risk: Critical/High/Warning/Informational is the incident severity scale.';

REVOKE ALL ON public.admin_incidents FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.admin_incidents TO authenticated;
