# 12 Circle Fitness — Master QA Reconciliation

**Phase 0 deliverable. No code changed.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` (read-only probes only, this run) · Production `nxdbooufqzkpslkcogxc` **not contacted**.

---

## 0. Evidence base — what actually exists

The prompt cites six completed QA workstreams. **Only one of them exists in the repository.**

| Workstream | Artifact in repo | Status |
|---|---|---|
| D — Coach/community/marketplace authorization | `docs/qa-workstream-d-report.md` | **Present**, detailed, live-verified |
| A — Workout/session integrity | none | **ABSENT as a document** |
| B — Intelligence + AI | none | **ABSENT** |
| C — Core product / nutrition / onboarding / women's health | none | **ABSENT** |
| E — Security / RLS | none | **ABSENT** |
| Final integrated 101-item discovery | none | **ABSENT** |

There is also **no feature blueprint / updated requirements document** in the repository. `docs/product-bible.md` and `docs/movement-intelligence-engine.md` are the only authoritative product/architecture documents, and both predate this QA cycle (July 2026). **Reporting this explicitly as instructed: no updated feature blueprint exists. No product requirement in this document is invented; every requirement cited traces to the product bible, the MIE document, migration comments, or existing tests.**

Workstreams A/B/C/E left **indirect but strong** evidence in the working tree instead of reports: migrations 103–112, the untracked `workout_restoration.dart` and nine untracked test files, and in-place migration comments tagged `STAGE A.6`, `STAGE B.2`, `B2-3`…`B2-6`, `STAGE B.3`, `STAGE B.4`. That work is **partial remediation already applied**, not discovery.

**Consequence for this reconciliation:** every finding below was **independently re-derived from source and, where safe, re-confirmed live against QA.** Nothing is carried on the authority of a summary. Findings I could not reproduce are marked as such rather than asserted.

### Verification legend

| Mark | Meaning |
|---|---|
| **LIVE** | Reproduced against QA this session with a read-only probe |
| **SRC** | Proven from migration/application source; not yet probed live |
| **RPT** | From the workstream D report's own live reproduction (write probes, reverted) |
| **OPEN** | Suspected; needs a probe or a decision before it can be classified |

### Baseline measured this session

| Suite | Result |
|---|---|
| Flutter (`apps/mobile`) | **514 passed, 0 failed** |
| API unit (`apps/api`) | **58 passed, 0 failed** |

The "514 baseline vs. working-tree count" discrepancy in the final discovery report **resolves to a non-issue**: 514 is exactly the working-tree count *including* the nine untracked test files. Committing them makes the number reproducible. See HYG-01.

---

## 1. Root-cause map

Fifty-plus reported symptoms collapse into **eight** root causes. This is the reason the work is sequenced as architecture, not as tickets.

| Root cause | ID | Symptoms it explains |
|---|---|---|
| Tables created outside the hardening migrations never had RLS enabled | **RC-1** | SEC-01, SEC-03, SEC-06, SEC-07, SEC-08 |
| Privilege columns share a row with user-editable profile columns | **RC-2** | SEC-02 |
| Postgres/Supabase default privileges grant execute + write to `anon`/`authenticated`; migrations revoke `PUBLIC` only | **RC-3** | SEC-05, SEC-10, (and the already-fixed 112 view hole) |
| Intelligence RPCs take a subject id as a parameter and never reconcile it with `auth.uid()` | **RC-4** | SEC-04, INT-01, INT-02 |
| `program_workouts.exercises` is untyped jsonb with **three** writers and **one** reader, none agreeing | **RC-5** | WRK-03, WRK-04, WRK-05, WRK-06, INT-03 |
| Two competing set-identity keys coexist (051 ordinal vs. 106 `set_id`) | **RC-6** | WRK-01, WRK-02 |
| Errors are caught and returned as a valid empty value | **RC-7** | WRK-07, CON-01, CON-02, CON-05 |
| `DateTime.now().toIso8601String()` writes a **naive local** time into `timestamptz` | **RC-8** | CON-06, CON-07, and ~60 call sites repo-wide |

RC-8 is already named and fixed for exactly one column by **migration 108**. The same defect is unfixed everywhere else. RC-3 is already named and fixed for **views** by **migration 112**; the same defect is unfixed for **functions**.

---

## 2. Findings

### 2.1 P0 — Security blockers

---

#### SEC-01 · `coach_client_relationships` has no RLS — the authorization root is forgeable
**Corroborates:** D-01 · **Root cause:** RC-1 · **Layer:** database · **Verified:** **LIVE** + RPT

Created in `000_baseline_preexisting_tables.sql`; no migration ever runs `ENABLE ROW LEVEL SECURITY`. Live probe this session: anonymous `GET /rest/v1/coach_client_relationships` → **HTTP 200 with real rows**.

**Downstream symptoms.** `is_active_coach_of()` (migration 100) is `SECURITY DEFINER` and trusts this table unconditionally. Every coach-scoped read policy written in 100, 102 and 111 — nutrition, weight, measurements, photos, habits, daily scores, workout sessions, set logs, feedback, and the full `user_profiles` PII row — is defeated by inserting one forged row. D's report reproduced the full chain live: victim health reads went 0 → 7/30/21 rows immediately after the forge.

**Dependencies.** Blocks nothing; **everything else in Phase 1 is worthless until this closes**, because a forged relationship re-opens each policy individually.

**Minimum correct fix.** Enable RLS. `SELECT`/`UPDATE`/`DELETE` restricted to `coach_id = auth.uid() OR client_id = auth.uid()`. `INSERT WITH CHECK` must not let a caller name an unconsenting counterparty — the relationship is created by the invite/accept flow, so the inserting party may only create a row in which they are a participant *and* the row starts in a non-active state, with activation by the other party. Revoke `anon` outright. The authorization root belongs in the database, never in Dart.

**Regression test.** A DB-level security test asserting: anon read = 0 rows / 401; unrelated authenticated user cannot insert a row naming a victim; a client cannot self-activate a relationship; a genuine coach↔client pair still reads and writes normally.

---

#### SEC-02 · Any client can self-escalate `user_profiles.role` to `admin`
**Corroborates:** D-02 · **Root cause:** RC-2 · **Layer:** database · **Verified:** RPT (live-reproduced by workstream D, reverted)

The self-update policy on `user_profiles` permits writing **any** column. D verified `PATCH {role:'admin'}` → 200, then called `admin_recent_users` and received **every user's name and email**, and `admin_platform_stats` for platform metrics. `membership_tier`, and by inspection `marketplace_commission_rate`, `stripe_*`, `is_demo` and `risk_*`, are on the same writable row.

**Amplifiers.** `is_admin()` (019), the `role in ('admin','content_manager')` gates in the communication engine (096) and exercise moderation (050) all read this column.

**Minimum correct fix.** Privilege columns must not be client-writable. A `WITH CHECK` pinning each privilege column to its OLD value, or a `BEFORE UPDATE` trigger that rejects a change to any privilege column unless the session is `service_role`. Trigger is preferred: it survives a future policy edit and covers every write path including RPCs. Role changes get a service-role/admin-only path.

**Regression test.** Client attempts to set `role`, `membership_tier`, `is_demo`, `marketplace_commission_rate`, `stripe_customer_id`, `risk_score` → each rejected, row unchanged; ordinary profile edits (name, phone, goal) still succeed.

---

#### SEC-03 · `weekly_checkins` has no RLS — anonymous CRUD on health check-in data
**Corroborates:** D-03 (rated P1 there; **raised to P0** here) · **Root cause:** RC-1 · **Layer:** database · **Verified:** **LIVE** + RPT

Live probe this session: anonymous read → **HTTP 200 with real rows**. D additionally verified anon INSERT → 201 and anon DELETE → 200.

**Raised to P0 because:** it is unauthenticated read *and write* of identified health data (weight, energy, stress, sleep, compliance, coach feedback), it is not gated behind SEC-01, and D observed pre-existing `QA-PROBE-ANON` rows — evidence the hole had already been exercised by another actor. Severity is not reduced by sharing a fix shape with SEC-01.

**Downstream.** `ai_adjust_nutrition()` reads `weekly_checkins` to move a user's calorie target (see SEC-04) — forged check-ins therefore drive real nutrition prescriptions. Compliance and at-risk scoring consume the same rows.

**Minimum correct fix.** Enable RLS; `SELECT` = owner OR `is_active_coach_of(user_id)`; writes owner-only; coach feedback columns writable only by the active coach. Revoke `anon`.

**Regression test.** Anon read/insert/delete all rejected; unrelated authenticated user reads 0 rows; owner and active coach behave correctly; a client cannot write `feedback_message`.

---

#### SEC-04 · Intelligence RPCs accept an arbitrary subject id and never check `auth.uid()`  ⟵ **NOT in any prior report**
**Root cause:** RC-4 · **Layer:** RPC · **Verified:** **LIVE** (execution) + **SRC** (missing check)

Seven `SECURITY DEFINER` functions take a subject/user uuid as a **parameter**, are granted to `authenticated`, and contain **no `auth.uid()` reconciliation and no `is_active_coach_of()` check**:

| Function | Migration | Effect on an arbitrary subject |
|---|---|---|
| `ai_adjust_nutrition(p_uid)` | 079 | **WRITES** — rewrites that user's active nutrition plan calories/macros; inserts an `ai_insights` row |
| `ai_detect_patterns(p_uid)` | 078/080 | **WRITES** — rewrites that user's `ai_profiles` behavioural model |
| `generate_workout(p_context, p_subject)` | 089 | **WRITES** — inserts a `decision_traces` row attributed to that subject |
| `create_weekly_review(p_subject, …)` | 096 | **WRITES** — inserts a `communications` row for that subject |
| `record_prediction(p_subject, …)` | 095 | **WRITES** — records a prediction against that subject |
| `predict_client(p_subject, …)` | 095 | **READS** — full predictive profile: recovery trend, adherence, PRs, pain flags, goal weight |
| `assemble_weekly_review(p_subject, …)` | 096 | **READS** — grounded brief incl. first name and weekly metrics |

Live this session: `POST /rest/v1/rpc/predict_client {"p_subject": …}` executed **as anonymous** and returned `{"status":"no_data"}` — it ran to completion; the uuid used simply has no feedback rows. Against a real subject it returns that subject's profile.

**Why this is architecturally serious, not just a leak.** The write-capable half lets any caller inject rows into the **deterministic engine's own record** — decision traces, AI profiles, predictions, communications. The product bible's second principle is "every recommendation is explainable… from a recorded decision trace." A forgeable trace store means the explainability guarantee is unenforceable. This is a *provenance integrity* failure as much as an authorization one.

**Minimum correct fix.** Each function must derive or verify its subject: default `p_subject := auth.uid()`, and permit a different subject **only** when `is_active_coach_of(p_subject)` (or the caller is `service_role`) — otherwise raise. `is_active_coach_of()` is only trustworthy once SEC-01 lands, so **SEC-01 is a hard prerequisite.** Keep the service-role/engine path working: the cron functions in 076/080 call these as `service_role` and must continue to.

**Regression test.** For each function: authenticated user A targeting user B → rejected; A targeting self → succeeds; A's active coach targeting A → succeeds; `service_role` → succeeds; anon → rejected.

---

#### SEC-05 · `anon` can execute SECURITY DEFINER functions; `REVOKE … FROM PUBLIC` does not close it  ⟵ **NOT in any prior report**
**Root cause:** RC-3 · **Layer:** database · **Verified:** **LIVE**

Of ~100 `SECURITY DEFINER` functions across the migrations, **five** carry a `REVOKE … FROM PUBLIC`. The rest rely on `GRANT EXECUTE … TO authenticated`, which does not remove the default.

The decisive live result: **`is_active_coach_of()` — which migration 100 *explicitly* `REVOKE ALL … FROM PUBLIC` — is still executable by anon (HTTP 200).** So is `marketplace_coaches()` (200, 6 rows) and `predict_client()` (200).

**Mechanism.** Supabase ships `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role`. That is a **direct grant to the `anon` role**, not a grant to `PUBLIC`. Revoking `PUBLIC` leaves the direct anon grant untouched. **This is the identical defect migration 112 documented and fixed for views** — the same default-privilege mechanism, applied to functions, never fixed.

**Minimum correct fix.** For every function in `public`: `REVOKE ALL … FROM PUBLIC, anon` then grant `EXECUTE` back to precisely the roles that need it (`authenticated`, and `service_role` where the engine/cron calls it). Apply by enumeration in a `DO` block so it is auditable and idempotent, mirroring 112's shape. A small allowlist of genuinely anonymous-safe functions (if any survives review) must be stated explicitly, not left implicit.

**Regression test.** A test that enumerates every `public` routine and asserts `has_function_privilege('anon', oid, 'EXECUTE')` is false except for a named allowlist — a standing guard, so a new migration cannot silently re-open it. This is the function-side twin of the existing view-grant test.

---

### 2.2 P1 — Release blockers

---

#### SEC-06 · Per-user AI/coaching tables have no RLS
**Root cause:** RC-1 · **Layer:** database · **Verified:** **SRC**; LIVE shows anon `SELECT` reaching the tables (200) but they are currently empty in QA, so no read exposure is demonstrated *today*

`ai_profiles`, `ai_memories`, `ai_insights`, `ai_reviews`, `ai_goal_predictions` — all carry a `user_id` FK to `user_profiles`, all created in 074, **none** ever get `ENABLE ROW LEVEL SECURITY`.

**Two distinct impacts.** (a) Confidentiality: `ai_memories` and `ai_insights` hold narrative coaching content derived from a user's health data. (b) **Integrity: these are engine *inputs*.** `ai_profiles` is what `ai_detect_patterns` writes and the accountability cron reads. Anonymous write access means the deterministic layer's substrate is attacker-controlled.

Empty-today is not a mitigation — Phase 4 populates them.

**Minimum correct fix.** Enable RLS; owner-only read/write; coach read via `is_active_coach_of(user_id)` where the product already exposes it (`coach_client_ai_signals` in 079 exists for exactly this and should remain the coach path); engine writes via `service_role`.

**Regression test.** Anon and unrelated-user read/write rejected for all five; `coach_client_ai_signals()` still returns a coach's own clients.

---

#### SEC-07 · Movement-intelligence substrate tables have no RLS — engine inputs are anon-writable
**Root cause:** RC-1 · **Layer:** database · **Verified:** **SRC** (+ LIVE: anon `SELECT` returns 200, tables empty in QA)

`exercise_substitutions`, `exercise_progressions`, `exercise_modifications`, `exercise_muscles`, `exercise_equipment`, `exercise_tags`, `exercise_media`, `exercise_analytics`, `exercise_reviews` — created in 058 and related, none RLS-enabled.

**Why this is a P1 and not a content nit.** Per `movement-intelligence-engine.md`, L1/L2 content and knowledge are exactly what L3 `score_exercise` / `build_workout` consume, and the certification view gates modules on them. An anonymous `INSERT` into `exercise_substitutions` or `exercise_progressions` is a **direct write into the deterministic coaching engine's decision inputs** — it changes what the engine recommends to real clients, while every recommendation still carries a valid decision trace. That defeats principle 4 of the product bible ("knowledge is reviewed before it becomes production truth").

**Minimum correct fix.** Enable RLS. Read: `authenticated` (library content is not secret). Write: `service_role` and the admin/content-manager role only — which is the pipeline the MIE document already specifies (AI drafts → `review_attribute()` → `finalize_intelligence()`). Note the role check depends on SEC-02 being closed first, or a self-escalated client becomes a content manager.

**Regression test.** Anon and ordinary authenticated insert/update/delete rejected on each table; read still works; the enrichment/review functions still write as `service_role`.

---

#### WRK-01 · `saveSetLog` upserts on the pre-106 ordinal key, not `set_id`
**Corroborates:** stated workout finding 1 · **Root cause:** RC-6 · **Layer:** service · **Verified:** **SRC**

[`workout_service.dart:98-114`](../apps/mobile/lib/features/workout/data/workout_service.dart#L98-L114): the `UPDATE` matches `session_id + exercise_name + set_number` and only *writes* `set_id` as a payload column. Migration 106 made `(session_id, set_id)` a unique index and its own comment declares `set_id` "authoritative for resume". Migration 051's `(session_id, exercise_name, set_number)` unique index still exists.

**Two live identity keys, disagreeing.** Concretely:
- A workout repeating an exercise (two "Bench Press" blocks) mints **colliding set ids** (see WRK-02) *and* collides on the 051 ordinal — one block's set 1 overwrites the other's.
- After an exercise swap, `exercise_name` changes but the set ids do not, so the `UPDATE` matches nothing, the `INSERT` fires, and it **violates `uq_workout_set_logs_set_identity` (23505)** — a hard error on the next set logged after any swap. This is the concrete interaction of WRK-01 and WRK-02.

**Minimum correct fix.** Make `set_id` the single persistence identity: upsert on `(session_id, set_id)`; keep `exercise_name`/`set_number` as recorded attributes. Migration 051's ordinal unique index must be **retired** in a forward migration once the writer no longer depends on it — leaving both indexes is what makes the two keys "both authoritative". `set_id` should become `NOT NULL` for rows written after the change (historical NULLs stay, per 106's stated intent).

**Regression test.** A workout containing the same exercise twice: logging set 1 of each produces two distinct rows with the right values. A swap followed by logging a set succeeds and does not collide. Resume reads each row back onto the set that recorded it.

---

#### WRK-02 · Exercise swap inherits the replaced exercise's set identities
**Corroborates:** stated workout finding 2 · **Root cause:** RC-6 · **Layer:** provider/state · **Verified:** **SRC**

[`active_workout_screen.dart:1177-1181`](../apps/mobile/lib/features/workout/presentation/active_workout_screen.dart#L1177-L1181) constructs the replacement with `sets: we.sets` — the old `WorkoutSet` objects, which already carry ids. `WorkoutExercise._identify` keeps any non-empty id (correctly — restored snapshots must survive the round trip), so the new exercise inherits the old exercise's identities verbatim.

**Symptoms.** Sets logged against the replaced exercise resume as already-completed *on the new exercise*; the immutability rule then locks values the client never entered for that movement. Plus the 23505 collision in WRK-01.

**Separately:** `WorkoutSet.mintId(exerciseId, setNumber)` is uniquified only **within one `WorkoutExercise`**. Two `WorkoutExercise` entries sharing an `exercise.id` mint identical ids. Uniqueness must be enforced at **workout** scope.

**Minimum correct fix.** A swap produces sets with fresh identities carrying the prescription (reps/weight/rest/tempo) but not the id, completion, or logged values. Move id uniquification to workout scope. Decide and record the treatment of logs already written against the replaced exercise — they are completed history and per product bible §2.6 must not be deleted; they should remain attached to the exercise that was actually performed.

**Regression test.** Swap after logging set 1: the new exercise's sets are all incomplete and carry new ids; the old exercise's log row is unchanged and still attributed to the old exercise name; logging a set on the new exercise succeeds.

---

#### WRK-03 · `program_workouts.exercises` has no schema — three writers, one reader, none agreeing
**Corroborates:** stated workout finding 3 · **Root cause:** RC-5 · **Layer:** database contract + service · **Verified:** **SRC**

`program_workouts.exercises` is `jsonb DEFAULT '[]'` (001). Three writers:

| Writer | Shape emitted |
|---|---|
| `_plan_day_exercises()` (047/077) — self-guided generator | `{name, sets:int, reps:int, rest_seconds:int}` — no weight, no id |
| [`program_builder_screen.dart:701-706`](../apps/mobile/lib/features/coach/presentation/program_builder_screen.dart#L701-L706) — coach UI | `{name, sets:int, reps:` **String** `, rest:int}` — wrong key for rest, no weight, no id |
| `materialize_program_week()` (093) — Program Intelligence Engine | `{id, name, pattern, score, systemic_fatigue}` — **no prescription at all** |

One reader — `programWorkoutToWorkout()` in [`workout_snapshot.dart:23-100`](../apps/mobile/lib/features/workout/data/workout_snapshot.dart#L23-L100) — expects `{exercise_id|id, name, sets:int, reps:int, weight:num, rest_seconds:int, set_details[]}`.

**This single untyped column is the root of WRK-03 through WRK-06 and INT-03.** Fixing them individually with casts would leave the contract undefined and the next writer would break it again.

**Minimum correct fix.** Define **one** canonical exercise-prescription shape and enforce it at the boundary. Concretely: a documented JSON contract, a Postgres `CHECK` or validation function on `program_workouts.exercises`, all three writers emitting it, and the codec reading it without defensive casts. Where a writer genuinely lacks a value (the engine does not currently prescribe load), that is a **product gap to be filled deliberately** (see Q-3), not a default to be silently invented.

**Regression test.** A codec round-trip test per writer shape; a contract test asserting each writer's output validates; a test that an out-of-contract row is rejected at write time rather than mis-read at read time.

---

#### WRK-04 · Coach-authored `reps` arrives as `String` and crashes the codec
**Corroborates:** stated workout finding 3 · **Root cause:** RC-5 · **Layer:** UI writer + codec · **Verified:** **SRC**

`program_builder_screen` writes `'reps': _reps.text.trim()`. The codec does `e['reps'] as int?`, which in Dart **throws** on a `String` — it does not yield null. The throw propagates to `assignedWorkoutsProvider`, whose `catch (_) { return []; }` converts it to *no program* (WRK-07). **A coach authoring a program makes the client's program disappear, silently.**

Note the sibling fields in the same dialog *are* parsed (`int.tryParse` for sets and rest); only `reps` is not. That is a plain omission, but the correct repair is at the contract (WRK-03), not a local `tryParse`.

**Regression test.** Codec test with `reps` as `'10'`, `10`, `'8-12'`, `''`, and null; a widget/service test that the builder cannot persist an out-of-contract row.

---

#### WRK-05 · Prescribed weight is always 0 kg; rest is always the 90 s default
**Corroborates:** stated workout findings 3 & 4 · **Root cause:** RC-5 · **Layer:** contract · **Verified:** **SRC**

- **Weight:** no writer emits a `weight` key. The codec's `((e['weight'] as num?) ?? 0).toDouble()` therefore yields **0.0 for every exercise of every program**, from every source.
- **Rest:** the coach UI writes `rest`; the codec reads `rest_seconds`. The value is discarded and 90 s substituted. The self-guided generator writes `rest_seconds` correctly, so the defect is coach-authored programs only.

**Minimum correct fix.** Part of WRK-03. Whether the engine should prescribe absolute load, a %1RM, or an RPE target is a **product decision** — see **Q-3**. Until it is answered, the honest client behaviour is to show *no* prescribed weight rather than `0 kg`, which currently reads as a real instruction to lift nothing.

**Regression test.** Coach sets rest 60 s → the client's session shows 60 s. A program with no prescribed load renders as "—", never "0 kg".

---

#### WRK-06 · The Program Intelligence Engine materializes workouts with no prescription
**Root cause:** RC-5 · **Layer:** deterministic engine · **Verified:** **SRC**

`materialize_program_week()` (093:160) inserts `coalesce(v_result->'selected','[]')` straight into `program_workouts.exercises`. `build_workout()` (088:110) emits selected elements of `{id, name, pattern, score, systemic_fatigue}`. The engine therefore chooses *which movements*, but records **no sets, reps, load or rest** — so every engine-materialized session reaches the client as the codec's defaults: 3 × 10 @ 0 kg, 90 s.

This is not a bug in the codec. It is a **genuine gap in the deterministic layer**: `build_workout` implements selection and volume-factor rules but no prescription assignment. Per the MIE document the engine is the "source of truth for every workout recommendation… and progression"; a set/rep/load prescription is a recommendation.

**Escalated as Q-3.** I will not invent a prescription model. Options and a recommendation are in §5.

---

#### WRK-07 · Workout errors are returned as empty state
**Corroborates:** stated workout finding 5 · **Root cause:** RC-7 · **Layer:** provider · **Verified:** **SRC**

[`workout_provider.dart:113-121`](../apps/mobile/lib/features/workout/domain/workout_provider.dart#L113-L121) — `assignedWorkoutsProvider` returns `[]` on any throw. `generateAiWorkout` returns `null` on any failure. `programSessionStatusProvider` returns `{}`. `activeSessionProvider` returns `null` on throw — meaning **a failed lookup is indistinguishable from "no session to resume"**, which is precisely the state the restoration work was built to eliminate.

The correct pattern already exists in this codebase and is worth preserving: `activeWorkoutRestorationProvider` deliberately distinguishes loading / null / **error**, and `WorkoutService.getSessionCompletedSets` documents why it lets read errors propagate. That pattern should be the rule, not the exception.

**Minimum correct fix.** Let these providers propagate; render an error state with a retry (product bible §4: "error (name the failure, offer the retry)"). Keep swallowing only where an empty result is genuinely equivalent to the error — nowhere in this set.

**Regression test.** With the program query failing, the surface shows an error + retry, never "no workout". With the session query failing, no Resume affordance is *hidden* — the failure is stated.

---

#### CON-01 · The Check-In feature targets a table that does not exist
**Corroborates:** "Check-In route points at non-existent/incorrect table contract" · **Root cause:** RC-7 (masking) · **Layer:** service/database · **Verified:** **LIVE**

`checkin_service.dart` reads and writes `checkins` at six call sites; `coach_dashboard_screen.dart:108` reads it too. Live probe: `GET /rest/v1/checkins` → **HTTP 404, `PGRST205` (table not found)**. No migration creates it. Every call throws and is swallowed into `false` / `[]` / `0`, so the feature **reports success-shaped failure**: the client sees "not checked in yet" forever and the coach dashboard shows zero check-ins.

`coach_tips` (`coach_provider.dart:64`) is the same defect — 404, swallowed.

A real, populated `weekly_checkins` table exists (the one with no RLS, SEC-03) and a separate `weekly_checkin_service.dart` uses it correctly.

**Escalated as Q-1:** whether the product intends a *daily* check-in distinct from the weekly one determines whether the fix is "create the table" or "retire the duplicate service and migrate callers to `weekly_checkins`". The product bible does not settle it. See §5.

**Regression test.** Once resolved: a check-in save that cannot reach its table surfaces an error; a successful save is readable back; the coach dashboard count matches.

---

#### CON-02 · Onboarding marks itself complete after the save fails
**Corroborates:** "onboarding can fail open" · **Root cause:** RC-7 · **Layer:** UI/service · **Verified:** **SRC** (explicit in code)

[`intake_flow_screen.dart:216-227`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L216-L227): if the full profile upsert throws, the handler explicitly writes `{'onboarding_complete': true, 'onboarding_step': 0}` and routes to `/home`. The comment states the intent — avoid looping the user — but the effect is that PAR-Q answers, medical conditions, injuries, allergies, dietary restrictions, goal, experience and **consent** are discarded while the user is recorded as fully onboarded and unable to return to the flow.

`_saveProgress()` Phase 2 has the same shape (`catch (_) {}`), so per-step intake data is also silently dropped.

**This is the parent of three other findings.** With the profile empty: PAR-Q risk data never exists (CON-04), allergies/restrictions never exist (CON-08), and `generate_client_plan()` builds a plan from nulls.

**Minimum correct fix.** Completion is a fact about the data, not about the navigation. Never set `onboarding_complete` on a failed save: surface the failure, keep the answers in memory, offer retry. Preserve the good half of the current design — the Phase-1 step/flag write that keeps resume working — and make the *data* write's failure visible instead of silent.

**Regression test.** With the profile write failing: `onboarding_complete` stays false, an error is shown, the answers survive, retry succeeds. With it succeeding: every intake field is present in the row before the flag flips.

---

#### CON-03 · `dietary_restrictions` has two conflicting serializers and the code's premise about the column is wrong
**Corroborates:** "dietary restriction serialization has conflicting contracts" · **Root cause:** RC-5 (contract) · **Layer:** service · **Verified:** **LIVE** (column type)

Two writers, one column:
- [`intake_data.dart:211-213`](../apps/mobile/lib/features/onboarding/domain/intake_data.dart#L211-L213) (`toSupabasePartial`, the per-step save) sends a **List**, with the comment *"Live column is text[] — send a real array, not a comma-joined string."*
- [`intake_data.dart:252`](../apps/mobile/lib/features/onboarding/domain/intake_data.dart#L252) (`toSupabase`, the final save) sends `dietaryRestrictions.join(',')` — a **String**.

**The comment is wrong for QA.** Live type probe (array-overlap operator): `dietary_restrictions` → `operator does not exist: text && unknown` — it is **`text`**, matching migration 013 (`TEXT NOT NULL DEFAULT ''`). The control column `activities` accepted the array operator, confirming the probe distinguishes the two.

**Therefore on QA the failing path is the per-step save**, not the final one: `toSupabasePartial` sends an array into a `text` column, the write fails, and `catch (_) {}` in `_saveProgress` discards **the entire step's intake data** — every field in that update, not just this one. That is why intake data goes missing during the flow.

**Production is a different and unverified case.** The "live column is text[]" comment suggests production may have been altered out-of-band — the same class of source/schema divergence migration 109 documented for the `auth.users` trigger. **Production was not inspected and must not be.** If prod is `text[]`, the *final* save is the failing path there and CON-02's fail-open fires on every onboarding. This must be confirmed before any production rollout — flagged in §6.

**Minimum correct fix.** One serializer, one type. Recommend migrating the column to `text[]` in a forward migration (it is a list by nature, and the reader already prefers a List) and deleting the string path — but the choice interacts with prod's actual type, so the migration must be written to converge either starting state.

**Regression test.** A serializer test asserting both paths emit the identical type; a round-trip test through the real column type; a test that a rejected data write does not silently drop the step.

---

#### CON-04 · High-risk PAR-Q answers are not enforced as a training constraint
**Corroborates:** "PAR-Q information is not consistently enforced" · **Layer:** deterministic engine · **Verified:** **SRC**

`intake_data.dart` computes `riskScore`, `riskLevel` (`high` when any of Q1,2,3,4,7 is yes) and `riskFlags`, and persists them to `user_profiles.risk_*` (013). `client_detail_screen` displays them to the coach. **Nothing consumes them as a constraint.** `build_workout()`'s context is `{goal, equipment, recovery, experience, injuries, recent_patterns}` — no risk term; `score_exercise`'s injury factor keys off `injuries[]`/`contraindications`, not PAR-Q. `generate_client_plan()` does not read `risk_level`.

Product bible §3: *"A great coach protects the client. Injury signals and low recovery override progression. Safety beats overload."* A high-risk PAR-Q is the strongest safety signal the product collects and the engine cannot see it.

**Dependency:** worthless until CON-02/CON-03 are fixed, because the data is not reliably persisted today.

**Escalated in part as Q-4:** the *mechanism* is clear (a deterministic constraint in `build_workout`/`generate_client_plan`, per the MIE extension points); the *policy* — whether high risk gates training entirely, caps intensity, or requires coach sign-off — is a product decision with clinical weight. See §5.

---

#### CON-05 · Nutrition auto-adjustment: no authorization, and it reads a table anyone can forge
**Corroborates:** "nutrition auto-adjustment references incorrect schema" + "requires authorization hardening before fixing its schema reference" · **Layer:** RPC · **Verified:** **SRC**

`ai_adjust_nutrition(p_uid)` (079) — covered as a member of SEC-04 for the authorization half. Two further specifics:

1. **It reads `weekly_checkins`** (`weight_kg`, `created_at`) — the table with no RLS (SEC-03). Anyone can insert fake check-ins and steer a real user's calorie target.
2. **Schema reference:** it reads `weekly_checkins.weight_kg` and `created_at`, both of which **do exist** (`weight_kg` added by 001:33; `created_at` in the 000 baseline), and `user_profiles.fitness_goal`/`goal`. I could **not reproduce a broken schema reference here.** The confirmed schema defect of this shape in the reported set is `ai_cron_generate()`'s `workout_sessions.created_at`, which **has already been corrected in place** in the working tree's migration 076 (tagged `B2-6`). Marking the "incorrect schema" half of this finding **NOT REPRODUCED / likely already resolved**, pending the absent workstream report.

**Order is fixed by the prompt and is correct:** authorization (SEC-04) and the input table (SEC-03) before any behavioural change.

---

#### CON-08 · AI nutrition plans can violate allergies and restrictions
**Corroborates:** "AI nutrition plans can violate allergies/restrictions" · **Layer:** API + data · **Verified:** **SRC**

`ai_nutrition_service.dart:116-124` passes restrictions into the prompt as free text (`Dietary restrictions: …`). There is no post-generation validation, and the API (`apps/api/src/ai/`) does not constrain or check the response. So the guarantee rests entirely on model compliance — and, upstream, on data that CON-02/CON-03 mean is frequently absent.

Product bible §6 lists AI's permitted acts; generating a *plan* the user then eats is the closest thing in the product to AI making a decision, and it currently has no deterministic guard.

**Minimum correct fix, two parts.** (a) Guarantee the inputs exist (CON-02, CON-03). (b) Add a deterministic post-check: allergens and restrictions are a finite, checkable set; a generated plan containing a prohibited item is rejected/regenerated rather than shown. That keeps the architecture honest — the engine (a deterministic rule) decides admissibility; AI writes the text.

**Regression test.** A plan request with a stated allergen: the returned plan contains none of it, or the call fails loudly. An injected model response containing the allergen is rejected by the guard.

---

### 2.3 P2 — Important defects

---

#### CON-06 · Naive local timestamps written into `timestamptz` (~60 call sites)
**Corroborates:** "historical-date nutrition writes can land on the wrong date" · **Root cause:** RC-8 · **Layer:** service · **Verified:** **SRC**; mechanism proven by migration 108

`DateTime.now().toIso8601String()` in Dart renders local time with **no zone marker** (`2026-08-24T21:30:00.000`). Postgres reads a naive literal into `timestamptz` as UTC. A client at UTC−5 stores every timestamp five hours early.

Migration 108 diagnosed this precisely for `workout_sessions.started_at` and fixed that one column. **The identical pattern is unfixed at ~60 call sites**, including: `nutrition_logs.logged_at`, `checkins.checked_in_at`, `messages.sent_at`, `conversations.last_message_at`, `weekly_checkins.submitted_at`/`reviewed_at`, `coach_client_relationships.pending_at`/`activated_at`, `goals.completed_at`, `weight_logs.logged_at`, `user_integrations.connected_at`. Reads use the same naive bounds, so day-window queries (today's meals, this week's workouts, streaks, compliance) are skewed by the offset in both directions.

`WorkoutService.logWorkout` uses `.toUtc()` correctly — so the codebase already disagrees with itself.

**Minimum correct fix.** One rule: every timestamp crossing the wire is UTC (`.toUtc().toIso8601String()`), and every day-boundary is computed explicitly in the user's local zone then converted. A shared helper plus a lint-style test is the durable form; scattered `.toUtc()` edits are not.

**Regression test.** A guard test asserting no `toIso8601String()` reaches a Supabase write without `.toUtc()`; a day-boundary test at a non-UTC offset showing an evening entry lands on the correct local day.

---

#### CON-07 · Nutrition cannot log to a past date, and has no edit/delete path
**Corroborates:** "historical-date nutrition writes can land on the wrong date" + "nutrition lacks appropriate edit/delete correction paths" · **Root cause:** RC-8 + gap · **Layer:** service · **Verified:** **SRC**

`nutrition_service.dart:63` hardcodes `'logged_at': DateTime.now()`. A date selected in the UI is **not carried into the write at all** — a historical entry lands on today, then CON-06 skews it further. No update or delete method exists on the service, so a mis-logged meal cannot be corrected.

Note this must be reconciled with product bible §2.6 ("completed history is immutable"): nutrition logs are *user-entered records*, not engine decisions, so a correction path is appropriate — but it should be an explicit, audited correction, mirroring the pattern already built for completed sets (`applyCorrection` + migration 111's replay corrections).

---

#### CON-09 · Barcode lookups can present per-100 g values as one serving
**Corroborates:** "barcode nutrition can misrepresent per-100g values as one serving" · **Layer:** service · **Verified:** **SRC**

`nutrition_service.dart:215-253` stores and returns `calories_per_100g`/`protein_per_100g`/… but the returned map keys are the unqualified `{calories, protein, carbs, fat}`. Any consumer treating that as a serving records ~100 g of food as one portion. The unit is dropped at the boundary between the lookup and the log.

**Minimum correct fix.** Keep the unit in the type: return per-100 g explicitly and require a quantity to produce a logged entry. This is a contract fix, not a UI fix.

---

#### SEC-11 · Completed sessions and program progression are client-writable
**Corroborates:** D-06 · **Layer:** database · **Verified:** RPT

A client `PATCH` of their own `status:'completed'` `workout_sessions` row → 200; `workout_program_assignments.current_week → 99` → 200.

Directly contradicts product bible §2.6 and the immutability work already done in the client (`ActiveWorkoutNotifier._editableWhenCompleted`, `applyCorrection`, migration 111). **That immutability is currently enforced only in Dart** — a UX safeguard, not a boundary. Per the prompt's security rule, it belongs in the database.

**Minimum correct fix.** A `BEFORE UPDATE` trigger or restrictive policy: once `completed_at` is set, ordinary client updates to a session are rejected; corrections go through the explicit authorized path (111's shape). `current_week` and assignment `status` become coach/service-writable only.

**Regression test.** Client cannot flip a completed session's status or rewrite its values; client cannot advance `current_week`; the sanctioned correction path still works; the coach can still advance the assignment.

---

#### SEC-09 · `SECURITY DEFINER` without `SET search_path`
**Root cause:** RC-3-adjacent · **Layer:** database · **Verified:** **SRC**

~45 migration files define `SECURITY DEFINER` functions with no `SET search_path`. Exploitability depends on whether a caller can create objects in a schema on the resolved path (Supabase revokes `CREATE ON SCHEMA public` from `authenticated` by default, which is the mitigating factor) — so this is hardening, not a demonstrated hole. It is cheap to fix in bulk and it is a standard audit finding; the newer files (076, 100, 102) already do it correctly.

---

### 2.4 P3

- **SEC-10** — `coach_availability` policy `USING (TRUE)` with no `TO` clause applies to `PUBLIC`; anon reads all slots. [D-05] · **SRC/RPT** · Fix: `TO authenticated`.
- **SEC-12** — `marketplace_coaches()` (046:67) filters only `p.role='coach'`; no `is_demo` filter and `is_demo` is not projected, so the client cannot filter either. [D-04] · **LIVE**: anon call returned **6 coaches**, including the five demo fixtures. Migration 110 states demo accounts are "excluded from discovery"; the RPC does not honour it. Fix: `AND p.is_demo = false`, and project the column.
- **SEC-08** — `workouts` table has no RLS, 0 rows, no reader in the app. A latent anon-write surface. Fix or drop — see **Q-2**.
- **CON-10** — Women's-health cycle computation (`cycle_phase.dart:36-80`): `daysSince % cl` extrapolates cycles indefinitely from a single logged period, so a *predicted* phase is presented as the current one with no staleness bound; a future-dated `lastPeriodStart` silently becomes cycle day 1. The fertile-window arithmetic (`ovulation−3 … ovulation+1`) is narrower than the conventional 6-day window. The first two are unambiguous data-integrity defects; **the clinical window is a product decision — see Q-5.** Compounded by SEC-06's sibling: `cycle_logs`/`cycle_settings`/`cycle_symptoms` **do** have RLS (verified — they are not in the gap list).

---

### 2.5 Environment / bootstrap

- **ENV-01** — QA Edge Functions are not deployed/configured for this cycle; `qa.json` has empty `STRIPE_PK` and `API_BASE_URL`. Blocks Phase 4 AI testing. Not a defect.
- **ENV-02** — The per-project Vault secrets (`project_url`, `service_role_key`) that migrations 076/080 now require are a **one-time manual step per project** and are presumably unset in QA, so the coaching crons are inert. Correct fail-closed behaviour; must be set before Phase 4, and **must never be set to production values in QA**.
- **ENV-03** — The intelligence substrate (`exercise_intelligence`, `movement_nodes`/`edges`, certifications) is unpopulated in QA. Per the prompt: an empty substrate is **not** evidence the engine is broken, and fixtures must be legitimate product data.

### 2.6 Repository hygiene

- **HYG-01** — All nine untracked test files are **legitimate** and are exactly what produces the 514-test baseline. `apps/mobile/lib/features/workout/domain/workout_restoration.dart` is **legitimate production source** — it is imported by `workout_provider.dart:8` and the app does not compile without it. **Nothing here should be deleted.** They are untracked only because the prior session did not commit. Recommendation: commit them as their own change so the baseline is reproducible. *Per instruction, I have committed nothing.*
- **HYG-02** — Historical migrations 001, 002, 003, 009, 076, 080, 083, 084, 086, 087, 090, 091, 096, 097, 102 are **modified in the working tree**. Reviewed: these are the documented `STAGE B.3/B.4` replay corrections, each carrying an in-file rationale and a pointer to forward migration 111. The stated justification — QA is being rebuilt from empty, so a defect that *aborts the replay* must be neutralised where it occurs — is sound and matches the prompt's migration rules. **One exception to flag:** 076's `B2-6` fix is applied **in place only**, and its own comment notes that any environment which already applied the old 076 will not pick it up by replaying. That is correct for a rebuilt QA and is a **known production-rollout gap**, recorded in §6.
- **HYG-03** — `supabase/.temp/*` (project-ref, pooler-url, versions) are modified and now point at QA. These are CLI scratch files; they should be `.gitignore`d rather than tracked, to prevent an accidental prod/QA flip landing in a commit.

---

## 3. Duplicate & corroboration map

| Canonical | Prior IDs / prompt items | Note |
|---|---|---|
| SEC-01 | D-01; prompt P0 #2 | Same finding |
| SEC-02 | D-02; prompt P0 #3 | Same finding |
| SEC-03 | D-03; prompt P0 #1 | **Re-rated P1 → P0** |
| SEC-04 | — | New; anticipated by the prompt's "critical AI security" section |
| SEC-05 | — | New; same mechanism as migration 112's view finding |
| SEC-06/07 | D report's "audit all" table list | Promoted from a to-verify list to classified findings |
| SEC-11 | D-06 | Same |
| SEC-12 | D-04 | Same; re-confirmed live |
| SEC-10 | D-05 | Same |
| WRK-01 | workout finding 1 | Same |
| WRK-02 | workout finding 2 | Same; **found to interact with WRK-01 producing a hard 23505** |
| WRK-03/04/05 | workout findings 3 & 4 | Merged into one contract root cause |
| WRK-06 | — | New; the engine-side half of the same contract |
| WRK-07 | workout finding 5 | Same |
| CON-01 | "Check-In route points at non-existent table" | Same; confirmed live |
| CON-02 | "onboarding can fail open" | Same |
| CON-03 | "dietary restriction serialization" | Same; **premise in code found to be wrong for QA** |
| CON-05 | "nutrition auto-adjustment" (2 items) | Authorization half → SEC-04; schema half **not reproduced** |
| CON-06/07 | "historical-date nutrition writes" | Merged into RC-8 |
| CON-09 | "barcode per-100g" | Same |
| CON-10 | "women's-health calculations" | Same; partly a product decision |
| — | workout findings 6 & 7 (lifecycle, history immutability) | **Largely already remediated** — see §4 |

---

## 4. Already resolved / false positive

| Item | Status |
|---|---|
| Workout finding 6 — finish/cancel/resume lifecycle semantics | **RESOLVED** by migrations 103, 105, 107, 108 + `workout_restoration.dart`, with tests. Re-verify in Phase 2; do not re-fix. |
| Workout finding 7 — completed history immutability | **PARTIALLY RESOLVED.** Client-side is done and tested (`_editableWhenCompleted`, `applyCorrection`, set_tracker widget tests). **Database side is open — SEC-11.** |
| "Nutrition auto-adjust references incorrect schema" | **NOT REPRODUCED.** The real instance of this defect shape (`workout_sessions.created_at` in 076) is already fixed in-tree. |
| Memory note "RLS coach policies unfixed — any authenticated user can read all health data" | **OUTDATED.** Migrations 100/102 are applied and working; exposure is now via SEC-01/SEC-02. |
| "514 baseline vs. working-tree test count" discrepancy | **NOT A DEFECT.** 514 measured this session; the delta was untracked test files. |
| Community/messaging display-name reads | **RESOLVED** in the working tree (`public_profiles`, `conversation_participant_profiles`). |
| Cross-project cron URLs (prod URL hardcoded in 076/080) | **RESOLVED** in the working tree — Vault-resolved, fail-closed. Notable: this was a QA-writes-to-production hazard. |

---

## 5. Architectural decisions required — I am stopping on these

Per the prompt's stop conditions, these cannot be settled from repository evidence. I will implement everything else and leave these open.

**Q-1 · Is there a daily check-in distinct from the weekly check-in?** (blocks CON-01)
`weekly_checkins` is real, populated and has a working service. `checkins` is referenced by a second service and the coach dashboard but has never existed. Either (a) daily check-ins are a real requirement → create the table with RLS from the start, or (b) they are a duplicate legacy path → retire `checkin_service.dart`, migrate the coach dashboard to `weekly_checkins`. The product bible does not mention a daily check-in. **My recommendation: (b)** — one authoritative implementation per feature, per the prompt — but this changes user-visible behaviour, so I want the call.

**Q-2 · Should the `workouts` table exist?** (blocks SEC-08) Zero rows, no reader, no RLS. Drop, or protect and populate. **Recommendation: drop** in a forward migration; nothing reads it.

**Q-3 · Does the deterministic engine prescribe load and volume?** (blocks WRK-05, WRK-06)
`build_workout` selects movements but emits no sets/reps/load/rest. The MIE document says the engine is the source of truth for "every workout recommendation, substitution, progression"; a prescription is a recommendation, so architecturally it belongs in L3 — but the scoring/rules layer has no prescription model today and inventing one is a product design act, not a repair. Options: (a) engine prescribes sets/reps and an intensity target (%1RM or RPE) as a new deterministic rule set; (b) engine prescribes structure only, load comes from the client's logged history (a progression rule); (c) coach-authored programs carry load, engine-generated ones show none. **Recommendation: (b)** — it is deterministic, explainable, needs no new clinical model, and matches "progression" as an existing engine responsibility. **Not proceeding without confirmation.**

**Q-4 · What does a high-risk PAR-Q result actually do?** (blocks CON-04)
The mechanism is clear; the policy is not, and it carries clinical weight. Options: gate training pending coach/medical sign-off; cap intensity and exclude contraindicated patterns; advisory flag to the coach only (status quo). **Recommendation: a deterministic constraint in `build_workout` that excludes contraindicated patterns and caps intensity, plus coach sign-off for coach-guided clients** — consistent with product bible §3 and §6. **Not proceeding without confirmation.**

**Q-5 · Women's-health clinical parameters.** (blocks part of CON-10) The mechanical defects I will fix regardless. The fertile-window definition and whether a predicted phase may be displayed as current are clinical/product calls.

**Q-6 · Production's `dietary_restrictions` column type.** (affects CON-03 rollout) QA is `text`. The code comment asserts the live column is `text[]`, which suggests prod diverges — the same out-of-band-change class as migration 109's trigger. **Production was not inspected and will not be without explicit authorization.** The forward migration must be written to converge from either starting type; confirming prod's actual type is a prerequisite to a production rollout, not to QA work.

---

## 6. Production impact — recorded, not acted on

Production was **not contacted** during this phase and must not be during implementation.

1. **SEC-01, SEC-02, SEC-03, SEC-04, SEC-05 are live in production too** — they are properties of the migration source, not of QA. This is the reason the security phase is first and the reason a production rollout plan will be needed once QA verification passes. That rollout is a separate, explicitly authorized activity.
2. **Migration 076's `B2-6` in-place fix does not self-apply** to any environment that already ran the old 076. Production needs the corrected function body applied explicitly.
3. **Migration 109 (`auth.users` trigger)** is deliberately not auto-applied; it is written name-agnostic and idempotent so it is safe there, but applying it is a separate decision.
4. **Migration 102's warning still stands**: it must not reach production until every beta build reads display names from `public_profiles` / `conversation_participant_profiles`.
5. **Q-6** — prod's `dietary_restrictions` type is unknown and unverified.

---

## 7. Blocked

| Item | Blocker |
|---|---|
| Workstream A/B/C/E finding-by-finding reconciliation | Reports absent. Findings re-derived from source instead; a *later* re-test cannot be a true BEFORE/AFTER for items I never saw stated. |
| Feature-blueprint conformance | No blueprint exists. |
| UI/navigation verification (D's item J) | Requires building and running the Flutter client. |
| Anon **write** confirmation on SEC-06/SEC-07 tables | Requires a write probe to QA. Deliberately not performed in Phase 0 (read-only); will be done under the authorized QA workflow in Phase 1, with cleanup. |
| Phase 4 AI testing | ENV-01/02/03. |
