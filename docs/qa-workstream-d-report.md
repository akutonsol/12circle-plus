# 12 Circle Fitness — AI QA Workstream D
## Coach · Community · Marketplace — Security & Authorization Discovery

**Environment:** QA (`eyqtldjqpgpljlqvpowh`) only. Production (`nxdbooufqzkpslkcogxc`) untouched.
**Date:** 2026-08-24
**Method:** Live REST/RPC probing against QA with real seeded accounts (client `test@12circle.app`,
coach `coach@12circle.app`, unrelated users `maria@/james@/aisha@community.test`, `sarah@marketplace.test`),
cross-referenced with the migration source. Read-only wherever possible; every write probe used a
`QA-D` marker and was reverted. Final state verified clean (see §Cleanup).

**Headline:** The user_profiles / coach-read RLS hardening (migrations 100–102) **is applied and
working** — but it is fully defeated by three base tables that never had RLS enabled, most critically
`coach_client_relationships`. Any anonymous internet caller (the anon key is published in this repo)
can forge coach↔client relationships and read every user's private health data, and any client can
escalate their own role to `admin`.

---

## RESULT SUMMARY

| Area | Result |
|---|---|
| A. Coach authorization | **FAIL** — forged-relationship escalation (D-01), self role-escalation (D-02) |
| B. Coach dashboard | PARTIAL — data scoping correct *when relationship table is trusted*; defeated by D-01 |
| C. Coach notes | **PASS** — client cannot read notes; only authoring coach reads/writes |
| D. Program management | PARTIAL — coach program protected from client edits; **client can rewrite own completed sessions & jump program week** (D-06) |
| E. Compliance | PASS (scoping) — stats view/health scoped to owner+active coach; inherits D-01 exposure |
| F. Coach communication | **PASS** — message read/insert scoped to conversation participants; injection blocked |
| G. Marketplace | PARTIAL — no email/billing leak in directory; **demo coaches not filtered** (D-04) |
| H. Community | PARTIAL — cross-user post edit/delete blocked; posts world-readable to authenticated (by design) |
| I. Coach media | **PASS** — coach_exercise_media / coaching_packs / video_responses all RLS-enforced |
| J. Role-based navigation | Not app-runnable in this harness (see §Blocked) |

---

## SECURITY FINDINGS

### D-01 — [P0] Anyone (incl. anonymous) can forge coach↔client relationships and read all health data
- **Feature:** Coach authorization (A) / whole data model
- **Severity:** P0 — Critical
- **Expected:** `coach_client_relationships` is the authorization root (`is_active_coach_of()` in
  migration 100 trusts it). It must be RLS-protected so only the coach/client parties can create or
  see a relationship.
- **Actual:** The table has **no `ENABLE ROW LEVEL SECURITY`** in any migration (created in
  `000_baseline_preexisting_tables.sql`, never hardened). Anon and any authenticated user can
  SELECT / INSERT / UPDATE / DELETE arbitrary rows.
- **Reproduction (verified live, reverted):**
  1. As unrelated user `maria`, baseline read of victim `test@`'s `body_measurements` / `weight_logs`
     / `nutrition_logs` = **0 rows** (correctly blocked by migration 100).
  2. `POST /rest/v1/coach_client_relationships {coach_id: maria, client_id: victim, status:'active'}` → **201 Created**.
  3. Re-read victim health as maria → **7 body_measurements, 30 weight_logs, 21 nutrition_logs**,
     e.g. `{"weight_kg":82.7,"note":"Monday weigh-in"}`.
  4. Same works unauthenticated with the published anon key.
- **Evidence:** live 201 on the forge insert; row counts jump 0→7/30/21 immediately after.
- **Root cause:** RLS never enabled on `coach_client_relationships`; migration 100's
  `is_active_coach_of()` is `SECURITY DEFINER` and trusts the table's contents unconditionally.
- **Authorization impact:** Total. Every coach-scoped read policy (nutrition, weight, measurements,
  photos, habits, daily_scores, workout_sessions/set_logs, feedback, **and** the whole
  `user_profiles` PII row via migration 102) becomes readable for any target user on demand.
- **Data impact:** Full read of all users' private health, body, training and profile data
  (email, phone, DOB, medical_conditions, parq_answers, injury_description, Stripe IDs). Also
  write/delete of relationships (sever real coaching, plant fake ones).
- **Recommended fix (do not apply — discovery only):** `ALTER TABLE coach_client_relationships
  ENABLE ROW LEVEL SECURITY;` + policies: SELECT/ALL restricted to `coach_id = auth.uid() OR
  client_id = auth.uid()`, with INSERT `WITH CHECK` forbidding a caller from naming themselves the
  counterparty of an unconsented party (invite/accept flow). Revoke anon entirely.

### D-02 — [P0] Any client can self-escalate role to `admin` (and set membership_tier/Stripe fields)
- **Feature:** Role boundaries / privilege (A)
- **Severity:** P0 — Critical
- **Expected:** `user_profiles.role` is a privilege boundary; a user must not be able to change their
  own role or entitlement columns.
- **Actual:** `user_profiles` UPDATE policy lets the owner write **any** column. Verified:
  `PATCH user_profiles?id=eq.self {role:'admin'}` → 200; `{membership_tier:'elite'}` → 200.
- **Amplifier:** `is_admin()` (migration 019) and the `role in ('admin','content_manager')` gates in
  the communication engine (096) and exercise moderation (050) all read `user_profiles.role`. After
  self-escalation, the client called `admin_recent_users` → **returned every user's name + email**;
  `admin_platform_stats` → returned platform-wide metrics. Chain verified live and reverted.
- **Root cause:** No column-level restriction on the self-update policy; privilege columns share the
  same writable row as user-editable profile fields.
- **Authorization impact:** Full vertical escalation to admin/content-manager surface (admin
  dashboard, exercise moderation, communications approval/sending).
- **Data impact:** Mass PII (all emails) via `admin_recent_users`; platform stats; ability to send
  `communications` as any coach.
- **Recommended fix:** Split privilege columns (`role`, `membership_tier`, `marketplace_commission_rate`,
  `stripe_*`, `is_demo`, `risk_*`) out of the self-writable policy — enforce via a `WITH CHECK` that
  pins them to their OLD values, or move them behind a trigger / service-role-only path.

### D-03 — [P1] `weekly_checkins` has no RLS — anonymous full CRUD on health check-in data
- **Feature:** Compliance / check-ins (E, B)
- **Severity:** P1 (P0-adjacent; separate root cause from D-01)
- **Expected:** Weekly check-in rows (weight, energy, stress, sleep, compliance %, coach feedback)
  are private to owner + active coach.
- **Actual:** Table created in `000_baseline_preexisting_tables.sql`; RLS never enabled. Anon can
  read all rows, and INSERT/DELETE arbitrary rows. Verified: anon read returned real check-ins for
  the client; anon INSERT (`week_number:999, notes:'QA-D-DELETE-ME'`) → 201; anon DELETE of it → 200.
- **Note:** Rows tagged `QA-PROBE-ANON` were already present at the start of this run — evidence a
  prior/parallel anonymous actor already exercised this hole.
- **Root cause:** Missing `ENABLE ROW LEVEL SECURITY` + policies.
- **Data impact:** Read/forge/delete of any user's check-in history; corrupts compliance & at-risk
  calculations (E).
- **Recommended fix:** Enable RLS; owner + `is_active_coach_of(user_id)` for SELECT, owner-only writes.

### D-04 — [P3] Demo/fixture coaches are not filtered out of the marketplace directory
- **Feature:** Marketplace ranking/discovery (G)
- **Severity:** P3
- **Expected:** Migration 110 added `is_demo` specifically so seeded fixtures
  (`*@marketplace.test`, flagged `is_demo=true`) are "excluded from discovery."
- **Actual:** `marketplace_coaches()` (046) filters only `WHERE p.role='coach'` — no `is_demo`
  filter — and does **not** even project `is_demo`, so the client app cannot filter them either.
  Verified: RPC returns all 5 demo coaches (Sarah/Marcus/Priya/Derek/Natasha) alongside the real one.
  `public_profiles` projects `is_demo` (both true/false rows returned) so community discovery *can*
  filter app-side, but the marketplace RPC cannot.
- **Impact:** Fake fixture coaches appear as bookable coaches; ranking pollution. No data leak.
- **Recommended fix:** Add `AND p.is_demo = false` to `marketplace_coaches()` (and/or project it).

### D-05 — [P4] `coach_availability` readable by anonymous (`USING (TRUE)`, no `TO authenticated`)
- **Feature:** Booking (G)
- **Severity:** P4
- **Expected:** Migration 100 closed no-`TO` (public) policies; this one was missed.
- **Actual:** Policy `client_read_availability ON coach_availability FOR SELECT USING (TRUE)`
  (migration 011) has no role clause → applies to PUBLIC. Anon reads all coaches' slot times and
  `is_booked` status (10 rows). No PII, but an unintended anon-reachable surface.
- **Recommended fix:** `TO authenticated`.

### D-06 — [P3] Client can rewrite own *completed* workout history and jump program week
- **Feature:** Program management / completed-work protection (D)
- **Severity:** P3 (own data; integrity, not cross-user)
- **Expected:** Brief: "completed historical work cannot be silently rewritten."
- **Actual:** Client PATCH of a `status:'completed'` `workout_sessions` row → 200 (status flipped);
  client PATCH `workout_program_assignments.current_week → 99` → 200. Both reverted.
  (Positive: client editing the **coach-owned** `workout_programs` row was correctly blocked — rows=0.)
- **Impact:** A client can alter their own completed-training record and coaching progression state,
  undermining compliance/progress integrity.
- **Recommended fix:** Restrict UPDATE on completed sessions (immutability once `completed_at` set);
  make `current_week`/assignment status coach-writable only.

---

## PASS (verified good)

- **C. Coach notes** — `coach_notes` RLS `coach_id = auth.uid()` only. Client read of notes about
  self = 0 rows; unrelated user = 0 rows. Privacy holds. (Minor: a coach may author a note whose
  `client_id` is a non-client — cosmetic validation gap, not a leak.)
- **F. Messaging** — read scoped to conversation participants (unrelated maria = 0 rows on the
  client↔coach conversation); message-injection attempt by a non-participant (`sender_id=self`) →
  **403 42501** (live policy is stricter than the base migration 003 `WITH CHECK`). Good.
- **H. Community write-authz** — maria editing/deleting another user's `community_posts` row → 0 rows
  affected (RLS `user_id = auth.uid()`). Posts are readable by all authenticated users by design.
- **I. Coach media** — `coach_exercise_media`, `coach_coaching_packs`, `coach_video_responses` all
  reject unauthorized insert (42501) and expose 0 rows to unrelated users.
- **Marketplace field hygiene** — `marketplace_coaches()` and `public_profiles` expose no email /
  phone / medical / Stripe columns; `user_profiles` PII is correctly gated by migrations 101/102
  (unrelated user cannot read other coaches'/clients' full profiles) — *except via D-01/D-02*.
- **OpenAPI / service surface** — anon cannot read the PostgREST root schema (service_role only).

---

## FEATURE ↔ DOCUMENT MISMATCHES

1. `docs/qa-environments.md` / migration 100–102 present the RLS story as closed ("closes two RLS
   holes… any authenticated account could read every user's health data"). The holes are closed for
   the *policy* layer but re-opened by three tables with **no RLS at all**
   (`coach_client_relationships`, `weekly_checkins`, `workouts`) — the exact class the migrations set
   out to fix. Migration 100 only audited *existing* policies, not tables lacking RLS entirely.
2. Migration 110 states demo accounts are "excluded from discovery"; `marketplace_coaches()` does
   not honor `is_demo` (D-04).
3. Repo memory note "RLS coach policies unfixed — any authenticated user can read all health data"
   is now **partially outdated**: 100/102 are applied. The live exposure is via D-01/D-02, not the
   original `USING(true)` coach policies.

---

## PRODUCT DECISIONS (for the owner)

- Are `workouts` and (empty) tables intended to exist at all? `workouts` has no RLS and 0 rows — a
  latent anon-write surface; either populate+protect or drop.
- Should `program_workouts` (program exercise templates) be world-readable to any authenticated user?
  Currently yes (maria sees 4). Fine if programs are non-proprietary; revisit if coach IP matters.
- Marketplace demo strategy: filter demo coaches out, or keep as seeded "starter" content and label
  them.

---

## RECOMMENDED FIX ORDER

1. **D-01** — enable RLS + parties-only policies on `coach_client_relationships` (unlocks everything else).
2. **D-02** — remove privilege columns from the self-update path on `user_profiles`.
3. **D-03** — enable RLS on `weekly_checkins` (and audit every table for missing RLS — see list below).
4. **D-05** — scope `coach_availability` read to `authenticated`.
5. **D-06** — completed-session immutability + coach-only assignment control.
6. **D-04** — demo filter in `marketplace_coaches()`.

**Tables with no `ENABLE ROW LEVEL SECURITY` anywhere in migrations (audit all):**
`coach_client_relationships`, `weekly_checkins`, `workouts` (confirmed anon-CRUD reachable);
plus these are RLS-off in source but currently empty/benign or protected by grants —
verify each on the live DB: `ai_goal_predictions, ai_insights, ai_memories, ai_profiles, ai_reviews,
badges, cycle_logs, cycle_settings, cycle_symptoms, exercise_analytics, exercise_equipment,
exercise_media, exercise_modifications, exercise_muscles, exercise_progressions, exercise_reviews,
exercise_substitutions, exercise_tags, payments, user_badges, user_integrations, user_scores`.
(Several *are* protected another way, e.g. `user_integrations` gets RLS in migration 011; the point
is the source is inconsistent and each needs a live check.)

---

## BLOCKED

- **J. Role-based navigation** (Clients/Compliance/FAB/Programs/Check-ins tab rendering, coach↔client
  role transition in-app) and any UI-level verification require building/running the Flutter client,
  which this discovery harness cannot do. All backend data feeding those screens was tested via REST.

## Cleanup

Every write probe was reverted and verified: no `QA-D*` residue in `weekly_checkins`, `coach_notes`,
`messages`, `community_posts`, `workout_programs`; client `role=client`/`membership_tier=basic`
restored; program assignment `current_week=1`/`status=active` restored; completed session status
restored; forged relationship deleted. A pre-existing external `maria→client` relationship and
`maria.role=admin` (created by a parallel actor, not this workstream) were observed and later cleared
by that actor — noted as corroborating evidence, not introduced by this run.
