# Phase 1 — P0 Security Audit & Remediation

**Environment:** QA (`eyqtldjqpgpljlqvpowh`) only. Production (`nxdbooufqzkpslkcogxc`) untouched — no
migration, query or probe was run against it, and no Phase 1 migration file contains its ref (guarded
by `SEC-027`).
**Date:** 2026-08-24
**Method:** every finding was reproduced live over the REST/RPC surface with the published anon key
and real Supabase JWTs, then re-run after remediation. The probes are permanent regression tests in
`supabase/tests/security/`.

---

## 1. Headline

| | Before | After |
|---|---|---|
| Tables with no RLS | 3 | **0** |
| Tables `anon` can read or write | 91 | **0** |
| Functions `anon` can execute | 98 / 100 | **0** |
| `SECURITY DEFINER` functions with a mutable `search_path` | 73 | **0** |
| Policies applying to `PUBLIC` (i.e. anon) | 14 | **0** |
| Blanket `USING (true)` / `WITH CHECK (true)` policies | 24 | 21 (all reviewed and accepted — §7) |
| Subject-scoped RPCs trusting a caller-supplied UUID | 11 | **0** |

**Every P0 identified in Phase 0 is FIXED AND VERIFIED.** Three further P1s were found during the
sweep and also fixed. Remaining findings are P2/P3 and listed in §9.

Live regression: **270/270 assertions across 6 suites.**
Repo suites: `flutter test` **558/558**, `flutter analyze` **0 errors/warnings**, API Jest **58/58 + 6/6 e2e**.

---

## 2. P0 findings — before

### D-01 [P0] `coach_client_relationships` had no RLS — the authorization root was world-writable

`public.coach_client_relationships` was created in `000_baseline_preexisting_tables.sql` and never
had `ENABLE ROW LEVEL SECURITY`. It is the table `is_active_coach_of()` reads, and migration 100
routes *every* coach-read policy through that function while migration 102 routes the whole
`user_profiles` PII row through it.

Reproduced live, in order:

```
1. attacker (unrelated client) reads victim health          -> 0 rows   (100/102 working)
2. POST /coach_client_relationships
     {coach_id: attacker, client_id: victim, status:'active'} -> 201 Created
3. rpc is_active_coach_of(victim) as attacker               -> false -> TRUE
4. attacker re-reads victim                                 -> weight_logs 1, body_measurements 1,
                                                               weekly_checkins 1, user_profiles 1
                                                               (email, phone, DOB, medical_conditions,
                                                                parq_answers, Stripe ids)
5. same INSERT unauthenticated with the published anon key  -> 201 Created
6. attacker PATCHes a real coach relationship to 'cancelled' -> 200, relationship severed
7. anon SELECT invite_token                                 -> 200, 3 rows
```

**Root cause:** the table is an *authorization source*, but was treated as ordinary data and skipped
when migration 100 audited existing policies — 100 looked at policies that existed, not at tables
that had none.

### D-02 [P0] Vertical privilege escalation through `user_profiles`

Two independent root causes, either sufficient alone.

1. `users can update own profile` (migration 015) is `USING/WITH CHECK (id = auth.uid())` with no
   column restriction. Reproduced: `PATCH user_profiles?id=eq.self {"role":"admin"}` → **204**, and
   the same for `coach`, `vendor`, `content_manager`, `membership_tier`,
   `marketplace_commission_rate`, the whole `stripe_*` Connect state and `is_demo`.
   `coaches can update client profiles` gave an active coach the same write over their *client's*
   `role`.
2. `handle_new_user()` (migration 044) copied `role` straight out of `raw_user_meta_data`, which is
   supplied by whoever calls `/auth/v1/signup`. Step 1 was never necessary — an attacker could
   simply register as an admin. Reproduced: a user created with `user_metadata.role = 'admin'`
   landed with `user_profiles.role = 'admin'`.

**Amplifier:** `is_admin()` (019) and the `role IN ('admin','content_manager')` gates in the
communication engine (096) and exercise moderation (050) all read that column.

### D-03 [P0] `weekly_checkins` had no RLS — anonymous CRUD on free-text health data

Reproduced: anon SELECT returned real check-ins; anon INSERT → 201; anon DELETE → 200. The table
carries weight, energy, stress, sleep, hunger, compliance %, free-text notes and coach feedback, and
it feeds compliance scoring, the coach at-risk roster and `ai_adjust_nutrition()`'s weight-trend
calculation — so forged rows steer a real nutrition prescription, not just a display.

### D-1D [P0] `SECURITY DEFINER` RPCs open to the internet and trusting caller-supplied UUIDs

Measured on QA: 100 functions in `public`, 86 `SECURITY DEFINER`, **73 with no pinned `search_path`**,
**98 executable by `anon`**. Postgres grants `EXECUTE` to `PUBLIC` on every new function and nothing
in migrations 001–112 took it back — one root cause, not 98 oversights.

Reproduced as an *anonymous* caller:

| Function | What it allowed |
|---|---|
| `insert_notification(any_user, …)` | arbitrary title + body into anyone's notification feed (phishing) |
| `generate_workout(ctx, any_subject)` | write a `decision_traces` row attributed to a stranger — forged engine provenance |
| `create_weekly_review(any_subject, …)` | create a `communications` draft against a stranger |
| `record_prediction(any_subject, …)` | write a `predictions` row for them |
| `predict_client(any_subject, …)` | read a stranger's adherence, recovery, pain reports, goal trajectory |
| `assemble_weekly_review(any_subject, …)` | same, in full brief form |
| `resolve_exercise_media(ex, any_viewer)` | learn who somebody's coach is + that coach's private note, voice note and video for them |
| `ai_adjust_nutrition(any_user)` | rewrite a stranger's macro targets |
| `mie_upsert_node/edge`, `rebuild_*`, `seed_exercise` | rewrite the movement graph and certified exercise intelligence the engine plans from |

### Q-4 [P0-class] PAR-Q risk classification was written by the client

`risk_score` / `risk_level` / `risk_flags` were computed in Dart (`intake_data.dart`) and submitted
with the intake payload. Reproduced: a member who answered **yes** to the heart-condition question
submitted `risk_level: 'low'` and it was stored. Q-4 makes high-risk PAR-Q status an *active training
constraint* — a constraint the constrained party can overwrite is not a constraint.

---

## 3. P1 findings discovered by the Phase 1F sweep

| ID | Sev | Finding |
|---|---|---|
| **F-01** | P1 | `coach_client_workout_stats` is a `security_invoker = off` view with **no caller scoping**. It groups by `coach_id` but returns every coach's roster: client name, avatar, completion rate, last workout. Reproduced live — an unrelated account read another coach's client at 100% completion. The app's `.eq('coach_id', …)` is presentation, not authorization. |
| **F-02** | P1 | `public.workouts` — the third table with no RLS. Anon CRUD on a legacy catalog. |
| **F-03** | P1 | `notifications` INSERT policy was `WITH CHECK (true)`: any signed-in account could push an arbitrary title and body into any user's feed. The table-layer twin of the `insert_notification()` hole. |
| **F-04** | P2 | `coach_availability` carried **two duplicate** `USING (true)` SELECT policies, both with no `TO` clause → PUBLIC. Anon read every coach's slot times and booked status. (Phase 0's D-05.) |
| **F-05** | P2 | `class_bookings` `"coaches read bookings"` was `USING (true)` — every signed-in account saw who booked which class. |
| **F-06** | P2 | Ten further policies had no `TO` clause. Predicates were `auth.uid()`-based so anon matched nothing *today* — but this is exactly the class that produced F-04. |
| **F-07** | P2 | `anon` held SELECT/INSERT/UPDATE/DELETE grants across all 91 tables. RLS was the *only* barrier; a table shipped with RLS off (which happened three times) was immediately world-writable. |
| **F-08** | P3 | Nine `SECURITY INVOKER` functions still had a mutable `search_path`. |

---

## 4. Root causes

1. **A missing control fails open.** All three RLS holes are the same event: `CREATE TABLE` without
   `ENABLE ROW LEVEL SECURITY`, in a schema where `anon` held full table grants. Nothing reported it.
2. **Authorization data was treated as ordinary data.** `coach_client_relationships` decides who may
   read whose health record. Migration 100 hardened everything that *consumed* it and never hardened
   it.
3. **Postgres defaults are open, and were never taken back.** `EXECUTE` to `PUBLIC` on functions and
   Supabase's `GRANT ALL ON TABLES` default account for the 98-function and 91-table exposure
   between them.
4. **Privilege columns shared a row with user-editable ones.** One `UPDATE` policy covered a
   fitness goal and an admin bit.
5. **Caller-supplied identity was trusted.** `raw_user_meta_data.role` at signup, and a `p_subject`
   UUID on eleven intelligence RPCs.
6. **Safety-critical derivation ran on the client.** The PAR-Q classification was computed by the
   party it constrains.

---

## 5. Remediation

### Migrations added

| # | File | Closes |
|---|---|---|
| 113 | `113_rls_coach_client_relationships.sql` | D-01 |
| 114 | `114_rls_weekly_checkins.sql` | D-03 |
| 115 | `115_profile_privilege_boundary.sql` | D-02, Q-4 |
| 116 | `116_rpc_execution_security.sql` | Phase 1D |
| 117 | `117_rls_intelligence_substrate.sql` | Phase 1E |
| 118 | `118_security_sweep.sql` | Phase 1F, F-01…F-08 |

All six are **additive forward migrations**, idempotent (verified by replaying each twice against
QA), and each carries a purpose, a security rationale and an inline rollback. No historical
migration (000–112) was edited.

### The relationship model (113)

Activating a relationship grants the **coach** access to the **client's** record, so authority is
asymmetric:

* a **client** may create and activate their own relationship freely — they are consenting to share
  their own record, which is the marketplace/onboarding flow and harms nobody else;
* a **coach** may only ever create a `pending` row, and may only activate a row the *client*
  initiated;
* non-parties see nothing, change nothing, delete nothing;
* `DELETE` is not granted to clients at all — ending a relationship is `status = 'cancelled'`, which
  is what every call site already does.

Two things RLS cannot express are handled by `trg_relationship_integrity`, because `WITH CHECK` sees
only `NEW`: repointing your own row at a third party, and rewriting `initiated_by` to self-approve.

`invite_token` is withheld by **never granting the column**. A column-level `REVOKE` does not cut
back a table-level `GRANT` — Postgres treats them independently and the table grant wins. That was
observed live during this work and is now guarded by `SEC-020`.

### The check-in authorship split (114)

One row is co-authored: the client owns mood/energy/stress/sleep/weight/notes, the coach owns
`feedback_*`/`coach_name`/`reviewed_at`/`status='reviewed'`. A column grant is per-role, not
per-relationship — both parties arrive as `authenticated` — so `trg_checkin_authorship` carries the
split.

### The privilege boundary (115)

Two classes, deliberately different:

* **HARD** (`role`, `membership_tier`, `marketplace_commission_rate`, `stripe_*`, `is_demo`) — a
  write **raises**, so an escalation attempt is loud and lands in the logs.
* **PINNED** (`rating_avg`, `review_count`, `email`, `created_at`, `ai_client_summary`,
  `assigned_coach_id`) — a write is silently reverted, because live screens fire these today
  (`home_screen` recomputes a coach's `rating_avg` after a review) and a 403 would surface an
  exception in the UI for a write that is already a no-op.

The legitimate role architecture, as discovered and preserved:

* self-service signup offers `client | coach | vendor` (`signup_screen.dart`, `enum _Role`) — the
  product's open marketplace model, and it lives;
* `admin` / `content_manager` had **no in-app assignment path anywhere in the codebase** and were
  being set by hand. That is now one explicit, admin-only, validated, logged function,
  `admin_set_user_role()`;
* `service_role` keeps a direct write as the break-glass path.

`role` also gained the `CHECK` constraint it never had — which is why an invented value like
`content_manager` used to land silently.

### PAR-Q risk (115, Q-4)

`derive_parq_risk()` is a faithful port of `IntakeData.riskScore/riskLevel/riskFlags` — same five
high-risk questions (1,2,3,4,7), same eleven flag labels, same three moderate-risk conditions. A
`BEFORE INSERT OR UPDATE` trigger recomputes `risk_*` for **every** caller including `service_role`.
The member owns the **answers**; the server owns the **classification**. `SEC-023` asserts the Dart
and the SQL agree, so they cannot drift.

What the product then *does* with a high-risk member — clearance routing, prescription gating — is
clinical policy and was deliberately **not invented**. See §10.

### RPC execution (116)

Not a blanket revoke. Every function was classified A–E:

| Class | Meaning | Count |
|---|---|---|
| A | public/internal helper — no client EXECUTE | 22 trigger fns + helpers |
| B | authenticated user fn — subject from `auth.uid()`, never a parameter | 21 |
| C | coach-authorized — proves subject / active coach / admin | 12 |
| D | service-role / engine only — no client EXECUTE | 16 |
| E | admin / content-editor — self-guarding | 20 |

`EXECUTE` was taken back from `PUBLIC` and `anon` schema-wide, `ALTER DEFAULT PRIVILEGES` was
narrowed so future functions inherit the closed posture, and an explicit allowlist grants
`authenticated` back. `service_role` and `postgres` were never revoked from — that is the engine's
execution path.

`can_act_for(subject)` and `can_act_on_program(program)` are the authorization predicates the
intelligence functions were missing. Both begin `auth.uid() IS NULL OR …`, so pg_cron, the edge
functions and the NestJS API (all `service_role`, no JWT subject) are unaffected by construction.

Five long engine functions were guarded **by delegation** (`predict_client` → `predict_client_engine`)
rather than by retyping several hundred lines of planning logic into a migration — transcription is
how bugs get into an engine. The `*_engine` originals have no client EXECUTE.

### Engine substrate (117)

`exercise_intelligence`, `movement_nodes` and `movement_edges` have **zero direct reads anywhere in
`apps/`** — the client reaches the graph through `movement_graph()`, which is `SECURITY DEFINER` and
unaffected. They are now content-editor only. `workout_programs` / `program_workouts` moved from
world-readable to owning coach + assigned client + that client's active coach. `weekly_feedback` is
engine *input*, so client `DELETE` is gone.

**Already correct, now pinned by tests:** `decision_traces`, `predictions`, `program_versions`,
`communications`, `intelligence_attribute_reviews` and `exercise_content_versions` each carry a
SELECT policy and **no write policy at all**. Under RLS "no policy" means deny, so a client already
could not rewrite a decision trace or a prediction. That is asserted now because one careless
`FOR ALL` policy would open all of it in a single line.

---

## 6. Tables audited

All 91 tables in `public`. RLS is on for every one; `anon` holds no privilege on any.

| # | Table | Class | RLS | Policies | Cmds | Blanket-true | anon | Rows |
|---|---|---|---|---|---|---|---|---|
| 1 | `accountability_pod_members` | social | on | 2 | INSERT/SELECT | 1 | no | 3 |
| 2 | `accountability_pods` | social | on | 2 | ALL/SELECT | 1 | no | 1 |
| 3 | `action_items` | app data | on | 4 | ALL/INSERT/SELECT/UPDATE | - | no | 0 |
| 4 | `ai_conversations` | engine/intelligence | on | 1 | ALL | - | no | 0 |
| 5 | `ai_goal_predictions` | engine/intelligence | on | 1 | ALL | - | no | 0 |
| 6 | `ai_insights` | engine/intelligence | on | 1 | ALL | - | no | 0 |
| 7 | `ai_memories` | engine/intelligence | on | 1 | ALL | - | no | 0 |
| 8 | `ai_profiles` | engine/intelligence | on | 1 | ALL | - | no | 1 |
| 9 | `ai_reviews` | engine/intelligence | on | 1 | ALL | - | no | 0 |
| 10 | `badges` | social | on | 1 | SELECT | 1 | no | 11 |
| 11 | `body_measurements` | health | on | 2 | ALL/SELECT | - | no | 8 |
| 12 | `challenge_participants` | social | on | 2 | ALL/SELECT | 1 | no | 7 |
| 13 | `challenges` | social | on | 2 | ALL/SELECT | 1 | no | 3 |
| 14 | `class_bookings` | social | on | 2 | ALL/SELECT | - | no | 1 |
| 15 | `classes` | social | on | 2 | ALL/SELECT | 1 | no | 3 |
| 16 | `client_habits` | health | on | 1 | ALL | - | no | 10 |
| 17 | `client_nutrition_plans` | health | on | 1 | ALL | - | no | 2 |
| 18 | `client_schedules` | app data | on | 2 | ALL/SELECT | - | no | 0 |
| 19 | `client_session_credits` | app data | on | 3 | SELECT/UPDATE | - | no | 0 |
| 20 | `coach_availability` | app data | on | 3 | ALL/SELECT | 1 | no | 10 |
| 21 | `coach_client_relationships` | authorization | on | 3 | INSERT/SELECT/UPDATE | - | no | 1 |
| 22 | `coach_coaching_packs` | app data | on | 1 | ALL | - | no | 0 |
| 23 | `coach_exercise_media` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 24 | `coach_invites` | app data | on | 2 | ALL/SELECT | - | no | 4 |
| 25 | `coach_notes` | app data | on | 1 | ALL | - | no | 0 |
| 26 | `coach_packages` | app data | on | 2 | ALL/SELECT | 1 | no | 1 |
| 27 | `coach_reviews` | app data | on | 2 | ALL/SELECT | 1 | no | 5 |
| 28 | `coach_team_invites` | authorization | on | 1 | ALL | - | no | 0 |
| 29 | `coach_team_members` | authorization | on | 1 | ALL | - | no | 0 |
| 30 | `coach_video_responses` | app data | on | 2 | INSERT/SELECT | - | no | 0 |
| 31 | `coaching_calls` | app data | on | 2 | ALL | - | no | 3 |
| 32 | `communications` | app data | on | 1 | SELECT | - | no | 0 |
| 33 | `community_group_members` | social | on | 2 | ALL/SELECT | 1 | no | 0 |
| 34 | `community_groups` | social | on | 1 | SELECT | 1 | no | 5 |
| 35 | `community_posts` | social | on | 2 | ALL/SELECT | 1 | no | 10 |
| 36 | `conversations` | app data | on | 3 | INSERT/SELECT/UPDATE | - | no | 1 |
| 37 | `custom_exercises` | catalog | on | 5 | ALL/SELECT/UPDATE | - | no | 621 |
| 38 | `cycle_logs` | health | on | 1 | ALL | - | no | 0 |
| 39 | `cycle_settings` | health | on | 1 | ALL | - | no | 0 |
| 40 | `cycle_symptoms` | health | on | 1 | ALL | - | no | 0 |
| 41 | `daily_scores` | health | on | 2 | ALL/SELECT | - | no | 60 |
| 42 | `decision_traces` | engine/intelligence | on | 1 | SELECT | - | no | 7 |
| 43 | `event_registrations` | social | on | 3 | ALL/SELECT/UPDATE | - | no | 2 |
| 44 | `event_sessions` | social | on | 2 | ALL/SELECT | 1 | no | 0 |
| 45 | `events` | social | on | 2 | ALL/SELECT | 1 | no | 3 |
| 46 | `exercise_analytics` | catalog | on | 2 | ALL/SELECT | - | no | 621 |
| 47 | `exercise_content_versions` | catalog | on | 1 | SELECT | - | no | 0 |
| 48 | `exercise_equipment` | catalog | on | 2 | ALL/SELECT | - | no | 476 |
| 49 | `exercise_intelligence` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 50 | `exercise_media` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 51 | `exercise_modifications` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 52 | `exercise_muscles` | catalog | on | 2 | ALL/SELECT | - | no | 1495 |
| 53 | `exercise_progressions` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 54 | `exercise_reviews` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 55 | `exercise_substitutions` | catalog | on | 2 | ALL/SELECT | - | no | 0 |
| 56 | `exercise_tags` | catalog | on | 2 | ALL/SELECT | - | no | 855 |
| 57 | `exercise_videos` | catalog | on | 1 | SELECT | 1 | no | 0 |
| 58 | `foods` | catalog | on | 2 | INSERT/SELECT | 2 | no | 21 |
| 59 | `goals` | app data | on | 3 | ALL/SELECT/UPDATE | - | no | 0 |
| 60 | `habit_logs` | health | on | 2 | ALL/SELECT | - | no | 61 |
| 61 | `intelligence_attribute_reviews` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 62 | `messages` | app data | on | 3 | INSERT/SELECT/UPDATE | - | no | 25 |
| 63 | `movement_edges` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 64 | `movement_nodes` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 65 | `notifications` | app data | on | 4 | DELETE/INSERT/SELECT/UPDATE | - | no | 48 |
| 66 | `nutrition_logs` | health | on | 3 | ALL/SELECT | - | no | 21 |
| 67 | `payments` | billing | on | 2 | SELECT | - | no | 0 |
| 68 | `platform_settings` | catalog | on | 2 | ALL/SELECT | 1 | no | 1 |
| 69 | `post_comments` | social | on | 2 | ALL/SELECT | 1 | no | 5 |
| 70 | `post_reactions` | social | on | 2 | ALL/SELECT | 1 | no | 30 |
| 71 | `predictions` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 72 | `program_versions` | engine/intelligence | on | 1 | SELECT | - | no | 0 |
| 73 | `program_workouts` | catalog | on | 2 | ALL/SELECT | - | no | 11 |
| 74 | `progress_photo_logs` | health | on | 2 | ALL/SELECT | - | no | 7 |
| 75 | `score_cycles` | app data | on | 1 | SELECT | - | no | 0 |
| 76 | `score_events` | social | on | 2 | SELECT | - | no | 0 |
| 77 | `subscriptions` | billing | on | 1 | SELECT | - | no | 0 |
| 78 | `user_badges` | social | on | 1 | SELECT | 1 | no | 0 |
| 79 | `user_integrations` | app data | on | 1 | ALL | - | no | 0 |
| 80 | `user_profiles` | authorization | on | 4 | INSERT/SELECT/UPDATE | - | no | 14 |
| 81 | `user_scores` | app data | on | 1 | SELECT | - | no | 0 |
| 82 | `weekly_checkins` | health | on | 3 | INSERT/SELECT/UPDATE | - | no | 4 |
| 83 | `weekly_feedback` | app data | on | 3 | INSERT/SELECT/UPDATE | - | no | 0 |
| 84 | `weight_logs` | health | on | 2 | ALL/SELECT | - | no | 31 |
| 85 | `workout_feedback` | app data | on | 2 | ALL/SELECT | - | no | 0 |
| 86 | `workout_logs` | app data | on | 1 | ALL | - | no | 0 |
| 87 | `workout_program_assignments` | app data | on | 1 | ALL | - | no | 2 |
| 88 | `workout_programs` | app data | on | 2 | ALL/SELECT | - | no | 3 |
| 89 | `workout_sessions` | app data | on | 2 | ALL/SELECT | - | no | 8 |
| 90 | `workout_set_logs` | app data | on | 2 | ALL/SELECT | - | no | 0 |
| 91 | `workouts` | catalog | on | 1 | SELECT | 1 | no | 0 |
---

## 7. Blanket `USING (true)` policies — reviewed and accepted

21 remain. Every one is a **SELECT** on shared content in a social fitness product, readable by
signed-in members only (`anon` has no grant on any of them):

`accountability_pods`, `accountability_pod_members`, `badges`, `user_badges`, `challenges`,
`challenge_participants`, `classes`, `coach_availability`, `coach_packages`, `coach_reviews`,
`community_groups`, `community_group_members`, `community_posts`, `post_comments`,
`post_reactions`, `events`, `event_sessions`, `exercise_videos`, `foods`, `platform_settings`
(single row: `marketplace_commission_rate = 0.10`), `workouts` (legacy catalog, 0 rows).

One is an INSERT: `foods` `WITH CHECK (true)` — a user-contributed food database. Accepted; the
spam/abuse exposure is noted as P3 in §9.

These are catalogued as **accepted**, not as unfound.

---

## 8. Views

| View | `security_invoker` | Scoping | Status |
|---|---|---|---|
| `public_profiles` | off | display columns only, `is_demo` filter | OK (101/110) |
| `conversation_participant_profiles` | off | 5 columns, `shares_conversation_with()` predicate | OK (102) |
| `exercises` | off | shared library | OK |
| `exercise_certifications` | off | shared library | OK |
| `coach_client_workout_stats` | off | **was unscoped — F-01** | FIXED (118) |

All five are SELECT-only for `authenticated` and unreadable by `anon` (migration 112, re-asserted).
The Supabase advisor still reports `security_definer_view` on all five — that is expected and
deliberate: each reads RLS-protected base tables and would return nothing as an invoker view, so its
safety is its column list and its `WHERE` clause. For `coach_client_workout_stats` the `WHERE` clause
is now the authorization, and migration 118 says so in a comment directly above the line.

---

## 9. Remaining findings

Nothing P0 remains. Nothing is blocked.

| ID | Sev | Finding | Why deferred |
|---|---|---|---|
| **R-01** | P2 | `award_points()` / `penalize_points()` take an arbitrary `p_points`. They are correctly scoped to `auth.uid()` (a member can only score *themselves*), but a member can award themselves any number — leaderboard integrity, not a data breach. | Fixing it means moving point values server-side, which is the Phase 2 scoring work. |
| **R-02** | P3 | D-06 from Phase 0: a client can UPDATE their own **completed** `workout_sessions` row and their own `workout_program_assignments.current_week`. Self-affecting record integrity. | Explicitly deferred — Phase 1 is P0 containment, and this touches the workout/session contract Phase 2 owns. |
| **R-03** | P3 | D-04 from Phase 0: `marketplace_coaches()` does not filter `is_demo`, so seeded fixture coaches appear bookable. | Product/discovery defect, no data exposure. Phase 2. |
| **R-04** | P3 | `foods` accepts `INSERT` from any member (`WITH CHECK (true)`). Shared food database by design; abuse surface is spam. | Needs a moderation decision, not a security one. |
| **R-05** | P3 | `coaches can update client profiles` still lets an active coach write a client's `first_name`, `medical_conditions`, `injury_description` etc. Privilege columns are now blocked (115), but the policy is broader than any screen needs. | Narrowing it needs the coach-edit surface enumerated; no escalation path remains. |
| **R-06** | P3 | Supabase Auth: **leaked-password protection is disabled** on QA. | Auth *configuration*, not SQL — changing project auth settings was outside the authorization for this phase. Recommended before beta. |
| **R-07** | P3 | `pg_net` is installed in `public`. | Advisory hygiene; moving it is a maintenance-window change. |
| **R-08** | P3 | The intake Dart still computes and submits `risk_*`. The server now overrides it silently, so it is dead weight rather than a hole. | Removing the client-side write is cosmetic; `SEC-023` keeps the two algorithms in step meanwhile. |

---

## 10. Unresolved architectural decisions

1. **Q-4 clinical policy.** The constraint is now enforceable — `risk_level` is server-authoritative
   and cannot be overwritten by the member. What the product *does* with `risk_level = 'high'` is
   not implemented and was not invented: does a high-risk member get no prescription, a restricted
   one, or one gated behind uploaded clearance? Who may clear them, and does clearance expire? This
   needs a clinical-policy owner before any gating is written.
2. **Q-1 weekly check-in retirement.** Dependency map below. Consolidation deferred as instructed.
3. **Q-2 `public.workouts` retirement.** Dependency analysis in §11. It is now inert and safe;
   dropping it is a data-model decision because `workout_logs` still carries an FK.
4. **Coach IP boundary.** `program_workouts` is now scoped to the program's parties. If coach
   programming is meant to be *shareable* (templates, marketplace programs), that needs an explicit
   sharing model rather than a widened policy.
5. **`admin` / `content_manager` assignment governance.** `admin_set_user_role()` now exists and is
   logged, but there is no admin UI for it and no second-person approval. Who may create the first
   admin on a fresh environment is still "whoever holds `service_role`".

---

## 11. Dependency maps (Q-1, Q-2)

### Q-1 — `weekly_checkins`

Not deleted, not rewritten. RLS applied. Consumers, for the later consolidation:

| Consumer | Direction | Note |
|---|---|---|
| `weekly_checkin_service.dart` | read + write | submit, list, current week; coach feedback |
| `coach_ecosystem_provider.dart` | read | client detail — last 4 check-ins |
| `compliance_service.dart` | read | coach at-risk roster |
| `insights_provider.dart` | read | latest energy/sleep/stress/weight |
| `notifications_screen.dart` | read | deep-link target |
| `supabase/functions/ai-coach` | read | last 4 check-ins as AI context |
| `supabase/functions/send-checkin-reminder` | read | reminder scheduling |
| `trg_notify_coach_on_checkin` (004) | trigger | AFTER INSERT → coach notification |
| `ai_adjust_nutrition()` (079) | read | **weight-trend → macro adjustment** |
| `assemble_weekly_review()` / `create_weekly_review()` (094) | read | weekly brief |
| `admin_platform_stats()` (019) | read | `checkins_week` metric |
| `weekly_checkins.checkin_id` FK from `002` | schema | referenced by an `002` table |
| realtime publication (037) | subscription | live updates |

The load-bearing one is `ai_adjust_nutrition()`: weekly weight is the *only* trend input to macro
adjustment today. Deriving weekly behaviour from daily check-ins means giving that function a daily
weight source first.

### Q-2 — `public.workouts`

| Fact | Value |
|---|---|
| Rows on QA | 0 |
| Readers / writers in `apps/`, `supabase/functions/`, the API | **none** |
| Referenced by | `workout_logs.workout_id` (FK) |
| Shape | static catalog: `title, description, category, difficulty, estimated_duration, coach_name, image_url, is_featured` |

Reads as a pre-programming-engine workout library, superseded by `program_workouts` and
`workout_sessions.workout_snapshot`. **Not deleted.** Made a read-only catalog so the anon-CRUD
surface closes without prejudging retirement.

---

## 12. Files changed

**Migrations added (6):** `113` … `118` (see §5).

**Application code (1 file):**

* `apps/mobile/lib/features/coach/domain/coach_provider.dart` — `availableCoachesProvider` no longer
  reads every coach's `coach_client_relationships` rows to compute capacity; it calls the new
  aggregate `coach_active_client_counts()` RPC. This is the **minimum supporting change** migration
  113 requires: under the parties-only SELECT policy the old cross-coach read would silently return
  zero for every coach, rendering a full coach as available.

**Tests added (8 files):**

* `supabase/tests/security/lib.mjs` — harness (auth, REST/RPC, `mutate`/`blocked`/`landed`, reporting)
* `supabase/tests/security/setup-identities.mjs` — four fixture identities + seed health data
* `supabase/tests/security/d01-coach-client-relationships.mjs` — 43 assertions
* `supabase/tests/security/d02-role-escalation.mjs` — 39
* `supabase/tests/security/d03-weekly-checkins.mjs` — 27
* `supabase/tests/security/d04-rpc-execution.mjs` — 54
* `supabase/tests/security/d05-intelligence-substrate.mjs` — 73
* `supabase/tests/security/d06-sweep-posture.mjs` — 34
* `supabase/tests/security/run.mjs`, `README.md`
* `apps/mobile/test/unit/phase1_security_boundary_test.dart` — 44 static guards (SEC-020 … SEC-027)

**Config:** `package.json` gains `test:security`; `.gitignore` gains the generated `ids.json`.

---

## 13. Functions and policies changed

**Functions created:** `is_coach_profile`, `coach_active_client_counts`,
`enforce_relationship_integrity`, `enforce_checkin_authorship`, `derive_parq_risk`,
`apply_parq_risk`, `enforce_profile_privilege`, `admin_set_user_role`, `can_act_for`,
`can_act_on_program`, `require_content_editor`, `can_read_program`, `may_notify`,
`resolve_exercise_media_for`.

**Functions hardened in place:** `handle_new_user` (role clamp), `is_admin` (search_path),
`set_relationship_client_source` (definer + search_path), `generate_workout`, `create_weekly_review`,
`record_prediction`, `snapshot_program_version`, `resolve_exercise_media` (authorization guards),
plus `search_path` pinned on **82** functions.

**Functions guarded by delegation:** `predict_client`, `assemble_weekly_review`, `evaluate_week`,
`materialize_program_week`, `regenerate_program`, `intelligence_review_queue`, `intelligence_stats`,
`intelligence_low_confidence`, `decision_analytics`, `movement_graph_stats`, `exercise_content_stats`,
`attribute_review_state`, `certification_summary` — each renamed to `*_engine`, client EXECUTE
revoked, public name kept as an authorized wrapper.

**Policies dropped:** `intel read`, `mie nodes read`, `mie edges read`, `read user_scores`,
`all read programs`, `all read program workouts`, `weekly fb rw`, `system can insert notifications`,
`client_read_availability`, `Clients can read availability`, `coaches read bookings`, plus the 10
remaining no-`TO` policies re-issued `TO authenticated`.

**Policies created:** 15 (relationship ×3, check-in ×3, substrate ×3, programming ×2,
weekly_feedback ×3, workouts ×1) plus the re-scoped set above.

---

## 14. Evidence

Every exploit was proven **before** and disproven **after**, on live QA, in the same script. The
suites assert the *secure* state, so they failed against the pre-remediation database and pass now:

| Finding | Evidence BEFORE | Evidence AFTER |
|---|---|---|
| D-01 `coach_client_relationships` | suite run against the live pre-113 database: **11/31**, the 20 failures being the whole exploit chain — anon SELECT/INSERT/UPDATE/DELETE all succeeded, the forged INSERT returned `201`, `is_active_coach_of(victim)` returned `true`, and the victim's `weight_logs`, `body_measurements`, `weekly_checkins` and PII profile all became readable | **43/43** |
| D-02 role escalation / PAR-Q | suite run against the live pre-115 database: **13/35** — `role` → `admin`/`coach`/`vendor`/`content_manager` each returned `204` with the role actually changed, as did `membership_tier`, `marketplace_commission_rate`, the `stripe_*` state and `is_demo`; an active coach promoted their own client to `admin`; a self-declared `risk_level: 'low'` was stored over a `yes` to the heart-condition question | **39/39** |
| D-03 `weekly_checkins` | **not** measured by re-opening the hole — doing so means disabling RLS and re-granting `anon` full CRUD on live health data, which is not a safe thing to do to a shared QA project even briefly. Evidence is (a) the live D-01 baseline captured before 114 was applied: `attacker reads 0 weekly_checkins — rows=1`, an unrelated authenticated account reading the victim's check-in, recorded twice in that run; (b) the catalog state at the start of Phase 1: `relrowsecurity = false`, 0 policies, `anon` holding SELECT/INSERT/UPDATE/DELETE; (c) Phase 0 Workstream D's live anon SELECT / `201` INSERT / `200` DELETE against this table, including pre-existing `QA-PROBE-ANON` rows from a prior anonymous actor | **27/27** |
| 1D RPC execution | catalog measurement, not a suite: **98 of 100** functions executable by `anon`, **73** `SECURITY DEFINER` functions with a mutable `search_path`, 11 subject-scoped functions trusting a caller UUID. Individual exploits (arbitrary-subject `generate_workout`, `predict_client`, `resolve_exercise_media`) are the assertions that now pass | **54/54**, `anon`-executable functions **0**, mutable `search_path` **0** |
| 1E intelligence substrate | catalog measurement: 4 blanket `USING (true)` SELECT policies over engine state, `ai_conversations` policy applying to `PUBLIC` | **73/73** |
| 1F sweep posture | catalog measurement: 3 tables with no RLS, 91 tables `anon`-reachable, 14 `PUBLIC` policies; plus F-01 reproduced live — an unrelated account read another coach's client name and completion rate through `coach_client_workout_stats` | **34/34**, and 0 / 0 / 0 |

Legitimate-flow verification is inside each suite, not a separate pass — e.g. §8 of D-01 walks the
whole coaching lifecycle (client requests → coach approves → coach reads health data → coach sets a
per-client price → client cancels → access revoked) and §5 of 1D proves `build_workout`,
`rank_exercises`, `generate_warmup`, `client_plan`, `marketplace_coaches` and the `service_role`
engine path all still execute.

---

## 15. Recommendation for Phase 2

1. **Apply 113–118 to production behind a client release.** Migration 113 changes what
   `coach_client_relationships` returns to a client, and 117 narrows `workout_programs` /
   `program_workouts`. The one client change (`coach_provider.dart`) must ship first, exactly the
   sequencing migration 102 called for. Everything else is server-side-safe.
2. **Wire `test:security` into CI** against a QA project. The static Dart guards run everywhere; the
   live suite is what proves composition.
3. **Take a Q-4 clinical-policy decision** before any prescription gating is written. The constraint
   is now enforceable and unenforced.
4. **Start Phase 2 on the `program_workouts` JSON contract and set identity**, as scheduled. Note
   that `program_workouts` is now parties-only — any Phase 2 read path must go through
   `can_read_program()` or a `SECURITY DEFINER` function, not a widened policy.
5. **Fold R-01 (arbitrary `p_points`) into the Phase 2 scoring work** rather than patching it alone.
6. **Enable leaked-password protection** (R-06) — a project setting, one toggle, no code.
