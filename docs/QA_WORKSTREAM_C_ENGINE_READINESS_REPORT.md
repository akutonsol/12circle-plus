# 12 Circle Fitness — Workstream C · Engine Readiness Audit

**Deliverable type:** audit. **No code changed, no migration written, no behaviour altered.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` — anonymous, read-only HTTP probes only.
Production `nxdbooufqzkpslkcogxc` **not contacted**.

**Scope.** Determine exactly what the deterministic coaching intelligence system *is*
today across thirteen layers, trace one complete client journey end to end, and name
every break in that chain — separating code defects from missing QA data, missing
deployment, missing product decisions and missing implementation.

**Non-goals, per the brief and honoured throughout.** The engine is not redesigned. No
coaching rule is invented. The Q-A prescription **methodology** is not decided — §12
records exactly where that decision touches architecture. Nothing is asserted on the
authority of a summary; every claim below is traced to source, to a live probe, or to a
prior phase's recorded live verification, and is marked accordingly.

---

## 0. Evidence legend and what could not be verified

| Mark | Meaning |
|---|---|
| **LIVE-C** | Probed against QA **this session**, read-only, anonymous |
| **LIVE-P** | Live-verified by a **prior** phase and recorded in a repository document or migration header; not re-confirmed this session |
| **SRC** | Proven from migration / application source in this working tree |
| **OPEN** | Suspected; needs a probe or a decision before it can be classified |

### Verification limits of this run

1. **Authenticated QA probing was not available.** An authenticated session against QA
   could not be established in this session, so **row counts inside the intelligence
   substrate could not be re-measured**. Every statement about *population* is carried
   as **LIVE-P** from the prior phase (migration 119's header and
   `PHASE_2_WORKOUT_RECONCILIATION.md` §W3, both of which record the live result), never
   asserted as fresh fact.
2. **Vault secret state could not be read** — `vault.decrypted_secrets` is service-role
   only. ENV-02 remains **OPEN**, not confirmed.
3. Everything anonymous is now denied on QA (see §1.2), which is the correct posture and
   is itself the reason (1) and (2) are blocked. That is a good trade, not a regression.

### What *was* established live this session

| Probe | Result | Meaning |
|---|---|---|
| `POST /functions/v1/{19 functions}` | **all HTTP 404 `NOT_FOUND`** | **Zero Edge Functions are deployed to QA.** ENV-01 confirmed, not inferred. |
| `POST /rest/v1/rpc/{24 engine RPCs}` as anon | **all HTTP 401 `42501` permission denied** | Every engine RPC of migrations 085–099 **and 119** *exists* in QA — PostgREST resolved each from the schema cache and Postgres refused execution. The engine schema **is** deployed. Anon execution is fully revoked (SEC-05 / migration 116 closed). |
| `GET /rest/v1/{14 substrate tables}` as anon | **all HTTP 401 `42501`** | Anon table reach into the substrate is closed (migrations 117/118 live). |

> The RPC result is the single most useful thing this audit established. It separates
> "the engine isn't there" from "the engine is there and has nothing to work with."
> **The engine is there.**

---

## 1. Architecture map

### 1.1 The layer stack as built

```
                       ┌───────────────────────────────────────────────┐
  L5  EXPERIENCE       │ Flutter — coach & admin surfaces only          │
  (app)                │  Coach Copilot · Dynamic Program Builder ·     │
                       │  Continuous Coaching · Weekly Review ·         │
                       │  MIE Debugger · Content Center · Knowledge     │
                       │  Review · Observability                        │
                       │  ── client-facing engine surface: NONE ──      │◀── ENG-10
                       └───────────────────┬───────────────────────────┘
                                           │
  L4  COMMUNICATION    ┌───────────────────▼───────────────────────────┐
  (grounded LLM)       │ explain-decision · generate-communication      │
                       │ ai-generate-workout · ai-coaching-engine       │
                       │ ai-coach                                       │
                       │  ── deployed to QA: NONE (LIVE-C) ──           │◀── ENG-15
                       └───────────────────┬───────────────────────────┘
                                           │ reads only
  L3  DECISION         ┌───────────────────▼───────────────────────────┐
  (deterministic)      │ 087 score_exercise · rank_exercises            │
                       │ 088/089 build_workout · generate_warmup ·      │
                       │         validate_week                          │
                       │ 089 generate_workout → decision_traces         │
                       │ 093 plan_program · materialize_program_week    │
                       │ 094 evaluate_week · regenerate_program         │
                       │ 095 predict_client · record_prediction         │
                       │ 096 assemble_weekly_review · create_weekly_…   │
                       └───────────────────┬───────────────────────────┘
                                           │ consumes
  L2  KNOWLEDGE        ┌───────────────────▼───────────────────────────┐
                       │ 085 movement_nodes / movement_edges            │
                       │ 087/090 exercise_intelligence (+ profile,      │
                       │         attribute_confidence)                  │
                       │ 091 intelligence_attribute_reviews             │
                       │  ── populated in QA: NO (LIVE-P) ──            │◀── ENG-17
                       └───────────────────┬───────────────────────────┘
                                           │ derives from
  L1  CONTENT          ┌───────────────────▼───────────────────────────┐
                       │ custom_exercises (+ `exercises` view)          │
                       │ 083 content pipeline · 084/086 certification   │
                       │ 057–073 normalized child tables + seeds        │
                       └───────────────────────────────────────────────┘
```

### 1.2 Authorization posture around the engine (as verified live)

Phase 1 (migrations 113–118) is applied on QA and it is **good**. Anon reaches nothing.
`exercise_intelligence`, `movement_nodes` and `movement_edges` are content-editor-read
only; the client reaches the graph through `movement_graph()` / `rank_exercises()`, which
are `SECURITY DEFINER` and survive the change. `decision_traces`, `predictions`,
`program_versions`, `communications` and `intelligence_attribute_reviews` carry a SELECT
policy and **no write policy at all** — under RLS that is deny, so engine provenance is
not client-forgeable. Migration 116 wrapped the seven subject-taking intelligence RPCs in
authorization shims (`*_engine` inner functions revoked from every client role). SEC-04
and SEC-05 are genuinely closed.

**Two residual authorization defects inside the engine surface** are recorded as ENG-09
and ENG-22 in §5.

---

## 2. Layer-by-layer audit

Each layer reports: database objects · migrations · functions/RPCs · Edge Functions ·
Flutter callers · API callers · inputs · outputs · authorization · deterministic vs AI ·
populated in QA · executable in QA · tested · production-ready · blockers.

---

### Layer 1 — Movement Intelligence Engine (graph + intelligence substrate)

| Field | Finding |
|---|---|
| **DB objects** | `movement_nodes` (unique `(node_type, slug)`), `movement_edges` (unique `(from,to,relationship)`, carries `confidence`/`reason`/`source`/`status`), `exercise_intelligence` (1:1 with `custom_exercises`; typed scoring fields + `profile` jsonb + `attribute_confidence` jsonb) |
| **Migrations** | 085 (graph), 087 (intelligence + bootstrap), 090 (enrichment columns + review lifecycle) |
| **Functions/RPCs** | `slugify`, `mie_upsert_node`, `mie_upsert_edge`, `rebuild_movement_graph`, `movement_graph`, `movement_graph_stats`, `rebuild_exercise_intelligence`, `intelligence_stats`, `review_intelligence`, `intelligence_low_confidence` |
| **Edge Functions** | `enrich-exercise-intelligence` (AI drafts the full profile for human review) |
| **Flutter callers** | `CustomExerciseService.rebuildMovementGraph / movementGraph / movementGraphStats / rebuildExerciseIntelligence / intelligenceStats / enrichExerciseIntelligence` → **Exercise Content Center** (`/content-center`), **Exercise Detail** |
| **API callers** | none. The NestJS API (`apps/api`) touches **no** engine surface; its only AI route is `POST /ai/nutrition/message` |
| **Inputs** | `custom_exercises.movement_pattern / muscle_group / secondary_muscles / equipment / alternatives / goal_tags / exercise_type` |
| **Outputs** | graph nodes+edges; a per-exercise intelligence profile with provenance |
| **Authorization** | writes gated on `is_content_editor()` (`role ∈ admin, content_manager`); reads staff-only since 117; client reaches the graph only through `movement_graph()` |
| **Deterministic vs AI** | `rebuild_movement_graph` / `rebuild_exercise_intelligence` are **pure SQL, no AI**. `enrich-exercise-intelligence` is AI **drafting for human review** — it never writes an approved profile. Boundary is correct as designed. |
| **Populated in QA** | **NO** (LIVE-P — migration 119 header: *"QA's `exercise_intelligence` is unpopulated, so `selected` comes back `[]`"*; `PHASE_2_WORKOUT_RECONCILIATION.md` §W3 records the same live result) |
| **Executable in QA** | **YES** for the SQL bootstrap (all RPCs verified present, LIVE-C). **NO** for AI enrichment — `enrich-exercise-intelligence` returns 404 (LIVE-C) |
| **Tested** | **NO behavioural tests.** Authorization is covered by `supabase/tests/security/d05-intelligence-substrate.mjs` (live) and `apps/mobile/test/unit/phase1_security_boundary_test.dart` (static). Zero tests exercise graph derivation or profile derivation |
| **Production-ready** | **No** |
| **Blockers** | ENG-07 (no approval gate downstream), ENG-17 (unpopulated), ENG-18 (bootstrap ordering has no runbook check), ENG-26 (pattern vocabulary mismatch) |

---

### Layer 2 — Decision Intelligence (scoring, rules, assembly, warm-up)

| Field | Finding |
|---|---|
| **DB objects** | none of its own; reads `exercises` (view over `custom_exercises`) ⋈ `exercise_intelligence`, and the graph for warm-ups |
| **Migrations** | 087 (`score_exercise`, `rank_exercises`), 088 (`build_workout` v1, `generate_warmup`, `validate_week`, `seed_warmup_library`), 089 (`build_workout` v2 — trace-emitting) |
| **Functions/RPCs** | `score_exercise(uuid, jsonb)`, `rank_exercises(jsonb, int)`, `build_workout(jsonb)`, `generate_warmup(uuid[])`, `validate_week(jsonb)`, `seed_warmup_library()` |
| **Edge Functions** | none — this layer is entirely in Postgres, which is correct |
| **Flutter callers** | `generateWorkout` → **Coach Copilot**, **MIE Debugger**. `seedWarmupLibrary` → **Content Center**. **`buildWorkout`, `rankExercises` and `validateWeek` have NO UI caller** (ENG-11) |
| **Inputs** | context `{goal, equipment[], recovery 0–100, experience, injuries[], recent_patterns[], size}` |
| **Outputs** | `{volume_factor, target_size, selected[], systemic_fatigue_count, warmup[], trace[], rules_triggered[], rules_applied[]}` |
| **Authorization** | `EXECUTE` to `authenticated`; anon revoked (LIVE-C). `SECURITY DEFINER` + `STABLE` — reads substrate as owner |
| **Deterministic vs AI** | **Fully deterministic.** No LLM anywhere. Weights fixed at 30/20/15/15/15/5. Rules: `RECOVERY_REDUCTION` (<60 → ×0.8), `MAX_SYSTEMIC_FATIGUE` (≤2 at ≥7), `MOVEMENT_VARIETY` (one per pattern), `EQUIPMENT_CONSTRAINT`, `INJURY_PREVENTION` (<40) |
| **Populated in QA** | n/a — stateless. Its **inputs** are not (Layer 1) |
| **Executable in QA** | **YES** — all six RPCs verified present (LIVE-C). It executes and returns `selected: []` (LIVE-P) |
| **Tested** | **NO.** Zero tests for scoring weights, rule precedence, volume factor, or warm-up derivation |
| **Production-ready** | **No** |
| **Blockers** | ENG-07, ENG-11, ENG-17, ENG-19, ENG-24, ENG-25, and **G-1** (no prescription assignment — §12) |

**Scoring correctness note (SRC).** `score_exercise` returns `{final_score: 0,
no_profile: true}` for an exercise with no intelligence row, and `build_workout` **inner
joins** `exercise_intelligence`, so unprofiled exercises are excluded outright rather than
scored at zero. That is the right shape — an unknown movement is not a bad movement, it is
an unselectable one.

---

### Layer 3 — Explainability / decision traces

| Field | Finding |
|---|---|
| **DB objects** | `decision_traces` (`subject_id`, `created_by`, four version stamps, `context`, `result`, `trace`, `rules_triggered`, + 092's `explanation_client` / `explanation_coach` / `explained_at` / `explain_model`) |
| **Migrations** | 089 (table + `generate_workout` + `decision_analytics`), 092 (explanation cache columns) |
| **Functions/RPCs** | `generate_workout(jsonb, uuid)` — build **and persist**; `decision_analytics()`; 094's `regenerate_program` also writes a trace |
| **Edge Functions** | `explain-decision` (L4 — see Layer 13) |
| **Flutter callers** | `generateWorkout` → Coach Copilot, MIE Debugger. `decisionAnalytics` → `platformObservability()` → **Admin Observability** |
| **Inputs** | a build context + the resulting plan |
| **Outputs** | a complete, versioned, structured record of every accept/reject with rule and reason |
| **Authorization** | `generate_workout` subject-authorized by migration 116. **SELECT policy (089, unchanged by 117/118) grants read to any account with `role ∈ (admin, content_manager, coach)`** — see ENG-09 |
| **Deterministic vs AI** | trace is 100% deterministic structured data. This is the product's strongest architectural asset |
| **Populated in QA** | **OPEN** — could not count. Any trace written today would carry `selected: []` |
| **Executable in QA** | **YES** (LIVE-C) |
| **Tested** | **NO** |
| **Production-ready** | **Structurally yes; operationally no** |
| **Blockers** | ENG-09, ENG-10 (no client can ever see a trace), ENG-22 |

**This layer is the product's differentiator and it is the healthiest thing in the
system.** The trace contract in `movement-intelligence-engine.md` matches what 089
actually emits, the version stamps are real, and the write path is not client-forgeable.
Its problem is not integrity — it is that **nothing downstream of a coach ever reads it.**

---

### Layer 4 — Program Intelligence / Dynamic Program Builder

| Field | Finding |
|---|---|
| **DB objects** | `workout_programs.{strategy, plan, program_version, engine_generated}`, `program_versions`, `program_workouts` |
| **Migrations** | 093, plus 119 §7 (materialization rewritten to the canonical contract) |
| **Functions/RPCs** | `plan_program(jsonb)` (`IMMUTABLE`), `snapshot_program_version(uuid, text)`, `materialize_program_week(uuid, int, jsonb)` |
| **Flutter callers** | `planProgram`, `createEngineProgram` → **Dynamic Program Builder** (`/program-designer`). **`materializeWeek` has NO caller anywhere in `lib/`** — ENG-01 |
| **Inputs** | strategy `{program_type, duration_weeks, frequency, primary_focus, progression_model, deload_strategy}` |
| **Outputs** | mesocycles + per-week `{phase, is_deload, volume_multiplier, intensity, sessions, split, emphasis}`; on materialization, `program_workouts` rows in the canonical prescription contract |
| **Authorization** | `authenticated`; `materialize_program_week` subject/coach-authorized via 116's shim |
| **Deterministic vs AI** | fully deterministic |
| **Populated in QA** | **OPEN**. Two self-generated programs were observed live by the prior phase (migration 121 header) — those are `generate_client_plan` output, not Program Intelligence output |
| **Executable in QA** | **YES** for `plan_program` / `snapshot_program_version`. `materialize_program_week` executes but **raises** on an empty selection by design (119) |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | **ENG-01 (P0)**, ENG-06, ENG-08, G-1 |

---

### Layer 5 — Continuous Coaching Engine

| Field | Finding |
|---|---|
| **DB objects** | `weekly_feedback` (unique `(program_id, week)`) |
| **Migrations** | 094; RLS tightened by 117 §5 (no client DELETE — feedback is engine input) |
| **Functions/RPCs** | `evaluate_week(uuid, int)`, `regenerate_program(uuid, int, boolean)` |
| **Flutter callers** | `submitWeeklyFeedback`, `evaluateWeek`, `regenerateProgram` → **Continuous Coaching** (`/continuous-coaching`) |
| **Inputs** | `completion_pct`, `recovery`, `sleep`, `stress`, `energy`, `pain[]`, `bodyweight`, `prs`, notes |
| **Outputs** | `{action, volume_delta, rules_triggered, escalate, needs_approval, coaching_mode, affected_weeks, reason}`; on apply: a mutated plan, a `program_versions` snapshot, a `decision_traces` audit row, a diff |
| **Authorization** | `authenticated`; 116 shim; RLS is subject-or-owning-coach |
| **Deterministic vs AI** | fully deterministic; priority order injury → fatigue deload → recovery → adherence → overload |
| **Populated in QA** | **OPEN** |
| **Executable in QA** | **YES** (LIVE-C) |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | **ENG-02 (P0)**, ENG-13, ENG-14 |

**The immutability guarantee is real and correctly implemented (SRC).**
`regenerate_program` copies weeks `≤ p_week` verbatim and only mutates weeks after it.
Product bible §2.6 is honoured at the plan level.

**But the adaptation is thinner than its own vocabulary.** `evaluate_week` can return
`REPLACE_EXERCISES` (`INJURY_ADAPTATION` — *"substitute via movement graph"*) and
`REDUCE_COMPLEXITY`; `regenerate_program` implements **only** `volume_multiplier` and
`is_deload` changes. No exercise is ever substituted, no complexity is ever reduced, and
no week is ever re-materialized after a regeneration. The named actions are labels over an
unimplemented behaviour — ENG-13.

---

### Layer 6 — Predictive Intelligence

| Field | Finding |
|---|---|
| **DB objects** | `predictions` (SELECT-only policy; no client write path) |
| **Migrations** | 095 |
| **Functions/RPCs** | `predict_client(uuid, uuid)` (`STABLE`), `record_prediction(uuid, uuid)` |
| **Flutter callers** | `predictClient` → **Coach Copilot** outlook panel. `recordPrediction` → service method with **no UI caller** |
| **Inputs** | `weekly_feedback` rows for `(program_id, subject_id)`, `workout_programs.plan.duration_weeks`, `user_profiles.{weight_kg, weight_goal_kg, fitness_goal}` |
| **Outputs** | goal progress + predicted finish + confidence, plateau risk, injury risk, adherence/churn, recovery forecast, deterministic alerts |
| **Authorization** | 116 shim: self, active coach, or service_role |
| **Deterministic vs AI** | fully deterministic; "confidence" is data-depth arithmetic, never a coaching decision's confidence — consistent with the product bible's terminology table |
| **Populated in QA** | **OPEN** |
| **Executable in QA** | **YES** (LIVE-C) — but see below |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | **ENG-02 (P0)** — `predict_client` filters `weekly_feedback` on `subject_id = p_subject`, and the only writer never sets `subject_id`. It therefore returns `{"status":"no_data"}` **for every client, always**, regardless of how much feedback a coach entered. ENG-21 (unvalidated arithmetic) |

---

### Layer 7 — Coaching Communication Engine

| Field | Finding |
|---|---|
| **DB objects** | `communications` (`brief` jsonb = the deterministic grounding packet, `source_refs`, `client_text`, `coach_text`, `status: draft→approved→sent`) |
| **Migrations** | 096; 111 creates the index 096's own statement got wrong (`created_at` vs `generated_at`) |
| **Functions/RPCs** | `assemble_weekly_review(uuid, uuid, int)`, `create_weekly_review(...)`, `update_communication(...)`, `send_communication(uuid)` |
| **Edge Functions** | `generate-communication` |
| **Flutter callers** | all four → **Weekly Review** (`/weekly-review`) |
| **Inputs** | `weekly_feedback` (this week and previous), `predict_client` output, the latest regeneration `decision_traces` row, `user_profiles.first_name` |
| **Outputs** | a grounded brief; then coach-editable client/coach text; then a sent communication |
| **Authorization** | RLS: **client sees only `status = 'sent'`** — coach-in-control is enforced at the database, which is exactly right |
| **Deterministic vs AI** | brief is deterministic; the LLM phrases it only. Correct boundary |
| **Populated in QA** | **OPEN** |
| **Executable in QA** | brief assembly **YES**; AI drafting **NO** (`generate-communication` → 404, LIVE-C). The screen degrades honestly to "write it below" |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | **ENG-02** (`assemble_weekly_review` filters on `subject_id`, so it returns `no_feedback` forever), ENG-15 |

---

### Layer 8 — AI memory / autocapture

| Field | Finding |
|---|---|
| **DB objects** | `ai_profiles`, `ai_memories`, `ai_insights`, `ai_reviews`, `ai_goal_predictions`, `ai_conversations` |
| **Migrations** | 074 (tables), 075 (auto-capture triggers + one-time backfill), 076 (cron), 078 (`ai_detect_patterns`), 079 (`ai_adjust_nutrition`, `coach_client_ai_signals`), 080 (accountability timing, redefines `ai_detect_patterns` with modal hour) |
| **Functions/RPCs** | `capture_injury_memory()` / `capture_feedback_memory()` (triggers on `user_profiles`, `workout_feedback`), `ai_detect_patterns(uuid)`, `ai_adjust_nutrition(uuid)`, `coach_client_ai_signals()`, `ai_cron_generate(text)`, `project_base_url()` |
| **Edge Functions** | `ai-coaching-engine`, `ai-coach` |
| **Flutter callers** | `AiCoachService` → `ai-coach` (chat) and `ai-coaching-engine` (typed generation) |
| **Inputs** | profile injuries, workout feedback notes, session history, nutrition logs, weekly check-ins |
| **Outputs** | `ai_memories` rows, `ai_profiles.behavioral_patterns`, `ai_insights` |
| **Authorization** | 117 closed `ai_conversations`' PUBLIC policy; 116 subject-authorized `ai_detect_patterns` / `ai_adjust_nutrition` |
| **Deterministic vs AI** | **mixed, and this is the one place the boundary is genuinely blurred.** Trigger capture and pattern detection are deterministic SQL. But `ai-coaching-engine`'s *daily_insight* emits `focus` and `intensity_delta` from a **Claude call**, and `docs/ai_coaching_architecture.md` §8 documents that those feed `coachAdjustmentProvider` → the active-workout load cue and `generate_client_plan()`'s program structure. That is an LLM output influencing training — see §4 |
| **Populated in QA** | **OPEN**; the triggers are unconditional so any onboarding with injuries populates `ai_memories` |
| **Executable in QA** | SQL half **YES**. Edge-function half **NO** (404, LIVE-C). Cron half **inert** — fail-closed on unset Vault secrets (ENV-02, OPEN) |
| **Tested** | partial — `apps/mobile/test/unit/edge_function_logic_test.dart` covers extracted logic; nothing covers the capture triggers or `ai_detect_patterns` |
| **Production-ready** | **No** |
| **Blockers** | ENG-15, ENV-02, and the §4 boundary question |

---

### Layer 9 — Exercise content intelligence

| Field | Finding |
|---|---|
| **DB objects** | `custom_exercises` (+ `exercises` view), `exercise_content_versions`, and the normalized children `exercise_muscles / _equipment / _tags / _media / _substitutions / _progressions / _modifications / _analytics / _reviews` |
| **Migrations** | 055–073 (schema, normalization, seeds), 082 (videos), 083 (content pipeline + the `custom_exercises` retarget), 097–099 (coach media overlay, packs, voice) |
| **Functions/RPCs** | `seed_exercise(jsonb, uuid)`, `_sync_exercise_relations`, `is_content_editor()`, `snapshot_exercise_content`, `review_exercise_content`, `exercise_content_stats`, `resolve_exercise_media` |
| **Edge Functions** | `enrich-exercise`, `enrich-exercise-content`, `enrich-exercise-videos` |
| **Flutter callers** | Content Center, Content Review Queue, Exercise Database/Detail |
| **Populated in QA** | **library: partially.** Migrations 063–073 issue **22** `seed_exercise()` calls in total. That is the migration-borne library; anything beyond it is data QA carries independently and could not be counted this session |
| **Executable in QA** | SQL **YES**; AI enrichment **NO** (404, LIVE-C) |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | ENG-25 and ENG-26 — the seeded content vocabulary does not match what the decision layer queries it with |

**Migration 083's own header records the most consequential fact about this layer:**
083, 084, 086, 087, 090, 091, 097 and 099 were originally written against `exercises`,
which is a **view**, so *"every statement below used to fail and this migration … has
never applied in any environment."* They were retargeted to `custom_exercises` in the
working tree. This session's LIVE-C probe confirms the retargeted versions **are** now
present in QA — every function those migrations create resolved. That repair worked.

---

### Layer 10 — Certification / review pipeline

| Field | Finding |
|---|---|
| **DB objects** | view `exercise_certifications` (current + projected per module), `intelligence_attribute_reviews` |
| **Migrations** | 084 (matrix), 086 (current vs projected; drops and recreates `certification_summary` because the return type changed), 091 (per-attribute review) |
| **Functions/RPCs** | `exercise_certification(uuid)`, `certification_summary()`, `review_attribute(...)`, `attribute_review_state(...)`, `finalize_intelligence(...)`, `intelligence_review_queue(int)` |
| **Flutter callers** | Content Center (summary tiles), Exercise Detail (per-exercise), **Knowledge Review** (`/knowledge-review`) |
| **Inputs** | content completeness, media presence, `ai_confidence`, `human_reviewed`, `content_status`, `attribute_confidence` |
| **Outputs** | per-module booleans (`workout_builder`, `program_generator`, `self_guided`, `coach_guided`, `ai_coach`, `marketplace`, `premium_content`), `overall_pct`, `projected_pct` |
| **Authorization** | `grant select … to authenticated, anon` on the view (084/086) is now moot — anon is revoked at the role level (LIVE-C) — but the grant is still in the source and should be tightened for hygiene |
| **Deterministic vs AI** | fully deterministic |
| **Populated in QA** | derived; non-empty iff the library is |
| **Executable in QA** | **YES** (LIVE-C) |
| **Tested** | **NO** |
| **Production-ready** | **No** |
| **Blockers** | **ENG-07 — this layer is built, correct, and consumed by nobody.** |

> `movement-intelligence-engine.md` states: *"Every module should gate on this view, not on
> individual fields"* and *"New consumer — query `exercise_certifications` to gate usage."*
> A repository-wide search finds **no reference to `exercise_certifications` in any
> migration other than 084 and 086**, and none in `build_workout`, `rank_exercises`,
> `materialize_program_week` or `generate_client_plan`. Neither does any of them filter
> `exercise_intelligence.status = 'approved'`. **The entire human-review pipeline — the
> mechanism behind product bible principle 4 — has no effect on what the engine
> recommends.**

---

### Layer 11 — Engine → program → workout materialization

| Field | Finding |
|---|---|
| **DB objects** | `program_workouts.exercises` under the canonical contract; trigger `trg_program_workouts_canonicalize`; CHECK `program_workouts_exercises_canonical` (`NOT VALID`) |
| **Migrations** | 093 (original), **119** (contract + canonicalizing trigger + validation + generator rewrite + fail-loud materialization), 120 (set identity), 121 (day-title legibility) |
| **Functions/RPCs** | `canonical_exercise_prescription(s)`, `is_canonical_exercise_prescription`, `_wk_int` / `_wk_num` / `_wk_jint` / `_wk_jnum`, `materialize_program_week`, `_plan_day_exercises`, `generate_client_plan` |
| **Flutter callers** | `programWorkoutToWorkout` (codec) ← `assignedWorkoutsProvider`, `WorkoutSessionManager` |
| **Deterministic vs AI** | deterministic; `ai-generate-workout` normalizes model output into the same contract before returning |
| **Populated in QA** | **OPEN** |
| **Executable in QA** | **YES** — all 119 helpers verified present (LIVE-C) |
| **Tested** | **YES, and well** — `workout_domain_contract_test.dart`, `workout_set_identity_test.dart`, `workout_set_immutability_test.dart`, `workout_session_persistence_test.dart`, plus `supabase/tests/workout/phase2-contract.sql`. This is the **only** layer in this audit with real coverage |
| **Production-ready** | contract **yes**; the engine's use of it **no** |
| **Blockers** | ENG-01, ENG-06, and G-1 |

**Migration 119 is the strongest piece of engineering in this stack.** It makes the shape
a property of the database rather than of six writers' habits; it makes `weight_kg: null`
mean *"no prescribed load"* and never `0`; and it made `materialize_program_week` **raise**
rather than report `sessions_created: 4` for four empty days. It also refuses to invent —
`"8-12"` is rejected rather than resolved to one end. That posture is exactly right and
should be preserved.

---

### Layer 12 — Engine → client presentation

| Field | Finding |
|---|---|
| **Client surfaces reading `decision_traces`** | **none** |
| **Client surfaces reading `predictions`** | **none** |
| **Client surfaces reading `communications`** | **none** — despite the RLS policy existing precisely to let a client read `status = 'sent'` |
| **Client surfaces reading `weekly_feedback`** | **none** — the only writer is a *coach* screen |
| **What the client does see** | `assignedWorkoutsProvider` → `program_workouts` decoded through the canonical codec; `coachAdjustmentProvider` → the AI daily-insight banner |
| **Verified** | SRC — repository-wide grep for these tables returns only `coach_program_service.dart`, `custom_exercise_service.platformObservability()` and the admin Observability screen |
| **Production-ready** | **Not built** |

The engine's every human-visible output — the trace, the explanation, the prediction, the
weekly review — terminates at a coach or admin screen. Product bible §4 (*"Show the
grounding … the client should understand why today looks the way it does"*) has **no
implementation on the client side**. This is ENG-10, and it is missing implementation
(category E), not a defect.

---

### Layer 13 — AI → explanation layer

| Field | Finding |
|---|---|
| **Edge Functions** | `explain-decision` (trace → prose, audience `client`\|`coach`), `generate-communication` (brief → `{client_text, coach_text}`), `ai-generate-workout` (library-grounded session), `ai-coaching-engine`, `ai-coach` |
| **Deployed to QA** | **NO — all five return HTTP 404 (LIVE-C)** |
| **Grounding constraints** | `explain-decision`'s SYSTEM prompt is genuinely hard-constrained: *use ONLY the trace; never invent physiology; say plainly it wasn't recorded; never contradict the trace.* `buildContext()` flattens the trace into a fixed line-set, so the model literally cannot see anything else. `generate-communication` is the same shape over the brief. `ai-generate-workout` says *"Do NOT prescribe a load. Weight is the deterministic engine's decision, not yours"* and validates the model's output against the canonical contract, dropping out-of-contract exercises and failing loudly if none survive |
| **Caching** | explanations cached on the trace (`explanation_client` / `explanation_coach`), written with the service role |
| **Flutter callers** | `explainDecision` → MIE Debugger (`_audience` toggle) and Coach Copilot (`audience: 'coach'`); `generateCommunication` → Weekly Review |
| **Failure behaviour** | honest. `explainDecision` swallows to `null` and the UI renders *"Explanation unavailable — set ANTHROPIC_API_KEY + deploy explain-decision."* Weekly Review renders *"Brief assembled. Deploy generate-communication for AI drafting."* Product bible §4's "degrade gracefully" is met |
| **Tested** | **NO test asserts groundedness** — no test feeds a trace and checks the output introduces nothing new, and no test asserts an LLM response cannot alter a decision |
| **Production-ready** | **No** |
| **Blockers** | ENG-15 (not deployed), ENG-22 (cache-poisoning shape), and the absence of a standing grounding test — which is precisely the test `REMEDIATION_EXECUTION_PLAN.md` Phase 4 step 3 calls for |

---

## 3. Readiness matrix

Legend — **Built**: the code exists in this tree. **In QA**: schema/function present in the
QA database (LIVE-C where marked). **Runs**: would produce a correct non-empty result today.
**Reachable**: a human can trigger it from the app. **Tested**: has behavioural test coverage.
**Prod-ready**: could ship.

| # | Layer | Built | In QA | Runs | Reachable | Tested | Prod-ready | Top blocker |
|---|---|---|---|---|---|---|---|---|
| 1 | Movement Intelligence (graph) | ✅ | ✅ LIVE-C | ⚠️ empty | ✅ Content Center | ❌ | ❌ | ENG-17 |
| 1b | Exercise intelligence substrate | ✅ | ✅ LIVE-C | ❌ empty | ✅ Content Center | ❌ | ❌ | ENG-17 |
| 2 | Decision Intelligence | ✅ | ✅ LIVE-C | ❌ selects `[]` | ⚠️ partial | ❌ | ❌ | ENG-17 + ENG-25 |
| 3 | Explainability / traces | ✅ | ✅ LIVE-C | ✅ | ✅ coach only | ❌ | ⚠️ | ENG-10 |
| 4 | Program Intelligence / DPB | ✅ | ✅ LIVE-C | ⚠️ | ❌ **no materialize caller** | ❌ | ❌ | **ENG-01** |
| 5 | Continuous Coaching | ✅ | ✅ LIVE-C | ⚠️ partial | ✅ | ❌ | ❌ | **ENG-02** |
| 6 | Predictive Intelligence | ✅ | ✅ LIVE-C | ❌ always `no_data` | ✅ Copilot | ❌ | ❌ | **ENG-02** |
| 7 | Communication Engine | ✅ | ✅ LIVE-C | ❌ always `no_feedback` | ✅ | ❌ | ❌ | **ENG-02** |
| 8 | AI memory / autocapture | ✅ | ⚠️ SQL only | ⚠️ | ✅ | ⚠️ | ❌ | ENG-15 + ENV-02 |
| 9 | Exercise content intelligence | ✅ | ✅ LIVE-C | ⚠️ 22 seeded | ✅ | ❌ | ❌ | ENG-25/26 |
| 10 | Certification / review pipeline | ✅ | ✅ LIVE-C | ✅ | ✅ | ❌ | ⚠️ | **ENG-07 — consumed by nobody** |
| 11 | Materialization + contract | ✅ | ✅ LIVE-C | ⚠️ | ❌ (see #4) | ✅ | ⚠️ | ENG-01 |
| 12 | Engine → client presentation | ❌ | — | — | ❌ | ❌ | ❌ | **ENG-10 — not built** |
| 13 | AI explanation layer | ✅ | ❌ **404 LIVE-C** | ❌ | ✅ (degrades) | ❌ | ❌ | **ENG-15** |

**One-line summary of the matrix.** Eleven of thirteen layers are *built and deployed to
QA*. None of them is *tested for behaviour*. Two of them (the client presentation of engine
output, and the AI runtime) are *absent from the running environment entirely*. And a
single unwritten column — `weekly_feedback.subject_id` — silently disables three of them.

---

## 4. The deterministic-vs-AI boundary — where it holds and where it does not

**The invariant, from `product-bible.md` §2.1 and `movement-intelligence-engine.md`:**
*the engine decides; the LLM explains.*

### Where the boundary is correctly enforced (SRC)

| Mechanism | Enforcement |
|---|---|
| `build_workout` / `score_exercise` / `plan_program` / `evaluate_week` / `predict_client` / `assemble_weekly_review` | **No LLM anywhere in the path.** Pure SQL. Verified by reading every function body |
| `explain-decision` | input is only `decision_traces.{context, result, trace, rules_triggered}`, flattened by `buildContext()` into a fixed line-set; SYSTEM prompt forbids introducing exercises, reasons or numbers |
| `generate-communication` | input is only `communications.brief` — itself assembled deterministically by `assemble_weekly_review` |
| `ai-generate-workout` | *"Do NOT prescribe a load. Weight is the deterministic engine's decision, not yours."* Output validated to the canonical contract; non-integer sets/reps are **dropped**, and zero survivors is a 502, not a half-workout |
| `materialize_program_week` (post-119) | emits `weight_kg: null` rather than a number it cannot justify; **raises** rather than writing an empty workout |
| Persistence | `decision_traces` / `predictions` / `program_versions` have **no client write policy** — engine provenance cannot be forged (117) |
| Knowledge | `enrich-exercise-*` write `status = 'ai_generated'`, never `approved`; approval flows through `review_attribute` → `finalize_intelligence` |

This is a genuinely well-drawn boundary. It should be preserved as-is.

### Where the boundary is blurred, contradicted, or unenforced

| # | Where | What actually happens |
|---|---|---|
| **B-1** | `ai-coaching-engine` *daily_insight* | Claude emits `focus` and `intensity_delta`. Per `ai_coaching_architecture.md` §8 these flow to `coachAdjustmentProvider` → the **active-workout load cue** and into `generate_client_plan()`'s **program structure** (077's focus bias). An LLM output is modulating training volume and program shape. Whether that is "communication" or a "coaching decision" is a product question, not a code question — recorded in §12 as **A-3** |
| **B-2** | Coach Copilot `_approve()` | The Flutter UI writes `{'sets': 3, 'reps': 10, 'rest_seconds': 90}` for every selected exercise ([`coach_copilot_screen.dart:99`](../apps/mobile/lib/features/coach/presentation/coach_copilot_screen.dart#L99)). Migration 119 went to real lengths to stop the *engine* fabricating a prescription; the *presentation layer* fabricates one instead, and the canonicalizing trigger stamps it as canonical. **ENG-03** |
| **B-3** | Knowledge gate | Nothing gates on `exercise_certifications`, and no engine query filters `exercise_intelligence.status = 'approved'`. AI-drafted, unreviewed intelligence is consumed as production truth the instant it is written. Product bible principle 4 is unenforced. **ENG-07** |
| **B-4** | `explain-decision` cache | The explanation is generated under the caller's RLS but **written with the service role**, permanently, onto a shared row. Combined with ENG-09 (any coach reads any trace) a coach unrelated to the subject can mint and pin the client-facing explanation of another coach's client's workout. **ENG-22** |

---

## 5. Findings

Severity: **P0** blocks the journey · **P1** blocks release · **P2** important · **P3** hygiene.
Category: **A** code defect · **B** missing QA data · **C** missing deployment/config ·
**D** missing product decision · **E** missing implementation.

| ID | Sev | Cat | Finding | Evidence |
|---|---|---|---|---|
| **ENG-01** | P0 | A/E | **`materialize_program_week` has no caller anywhere in the app.** The Dynamic Program Builder plans, versions and saves an engine program; nothing ever materializes a week. Its own success message tells the coach to *"materialize week 1 from Coach Copilot / the client program view"* — **no such affordance exists in either screen.** An engine-generated program reaches the client with zero `program_workouts` rows | SRC — grep for `materializeWeek` across `lib/` returns only its definition in `coach_program_service.dart:40` |
| **ENG-02** | P0 | A | **`weekly_feedback.subject_id` is never written.** `submitWeeklyFeedback` upserts `{program_id, week, completion_pct, recovery, energy, pain}` and no more; the Continuous Coaching screen has no client selector; no trigger or default fills it. Four consequences: (a) `predict_client` filters `subject_id = p_subject` → **always `no_data`**; (b) `assemble_weekly_review` filters the same → **always `no_feedback`**, so no weekly review can ever be created from feedback entered in-app; (c) `evaluate_week` reads `coaching_mode` via `fb.subject_id` → NULL → **`needs_approval` never fires for coach-guided clients**, silently disabling the approval matrix; (d) `regenerate_program` stamps `decision_traces.subject_id` NULL → the subject can never read the trace of their own program change | SRC — `coach_program_service.dart:109`; `094:41,105`; `095`; `096` |
| **ENG-03** | P1 | A | **Coach Copilot invents a prescription in the UI**: `sets: 3, reps: 10, rest_seconds: 90` for every exercise the engine selected. Contradicts the closed Q-A decision (§12) that the engine is the prescription authority, and re-introduces the exact fabricated defaults 119 removed from the engine path | SRC — `coach_copilot_screen.dart:97-100` |
| **ENG-04** | P1 | A | **Copilot approval destroys the client's program assignment.** `_approve()` calls `assignProgram`, which sets every existing `active` assignment for that client to `replaced`. Approving one recommended session therefore detaches the client from their multi-week program | SRC — `coach_copilot_screen.dart:101-104` → `coach_program_service.dart:assignProgram` |
| **ENG-05** | P2 | A | Copilot writes `day_of_week: 'monday'` (lowercase). `getTodaysWorkout()` matches capitalized day names; migration 119's normalizing trigger only rewrites `'1'..'7'`. A Copilot session can never be "today's workout" | SRC — `coach_copilot_screen.dart:106`; `coach_program_service.dart:_dayName`; `119` §4 |
| **ENG-06** | P1 | A | **Every session in a materialized week is identical.** `materialize_program_week` builds one `v_ctx` and reuses it for all `i` in the split; it never varies the context by `v_split->>i`. `build_workout` is deterministic, so Push / Pull / Legs select the same exercises. **The split is a title.** Unchanged by 119 | SRC — `093:150-160`, `119` §7 |
| **ENG-07** | P1 | A/D | **The certification and review pipeline gates nothing.** `exercise_certifications` is referenced by no migration other than 084/086 and by no engine function. Neither `build_workout` nor `rank_exercises` filters `exercise_intelligence.status`. Draft, heuristic and AI-drafted intelligence is production truth. Directly contradicts product bible §2.4 and the MIE doc's stated consumer contract | SRC — repository-wide grep |
| **ENG-08** | P2 | A | Migration 121 restored the unique-day-title legibility contract **only inside `generate_client_plan`**. `plan_program` at `frequency = 6` emits `['Push','Pull','Legs','Push','Pull','Legs']`, so `materialize_program_week` writes two `"Week N · Push"` rows. There is no DB unique index (052/121 do title-suffixing in the function, not in an index), so this is ambiguity rather than an error | SRC — `093:70`, `121` |
| **ENG-09** | P2 | A | **`decision_traces` SELECT is platform-wide for staff.** Migration 089's policy grants read to `subject_id = auth.uid() OR created_by = auth.uid() OR role ∈ (admin, content_manager, coach)` — **any** coach, not the subject's coach. Untouched by 117 and 118 | SRC — `089:33-36`; grep of 117/118 |
| **ENG-10** | P1 | E | **No client-facing surface for any engine output.** Nothing in `lib/` reads `decision_traces`, `predictions`, `communications` or `weekly_feedback` on the client side, despite `communications`' RLS existing precisely to serve a client their `sent` reviews. Product bible §4 "show the grounding" is unimplemented for clients | SRC |
| **ENG-11** | P1 | E | **`validate_week`, `build_workout` and `rank_exercises` have no UI caller.** The cross-day rules validator (no back-to-back high-fatigue hinge days; ≤3 spinal-loading days/week) never runs against a materialized program. Weekly safety rules exist and are never applied | SRC |
| **ENG-12** | P1 | D | **PAR-Q risk does not constrain prescription.** `build_workout`'s context has no risk term; `score_exercise`'s injury factor keys off `injuries[]`/`contraindications` only. Recorded as CON-04 / Q-4 / contract gap **G-4** | SRC |
| **ENG-13** | P2 | A/E | **`regenerate_program` implements only two of its own actions.** `evaluate_week` can return `REPLACE_EXERCISES` (`INJURY_ADAPTATION` — *"substitute via movement graph"*) and `REDUCE_COMPLEXITY`; the regenerator only mutates `volume_multiplier` and `is_deload`. No exercise is ever substituted, and no week is ever re-materialized after adaptation | SRC — `094:80-140` |
| **ENG-14** | P2 | A | The coach approval matrix in `evaluate_week` is inert for the mode it exists to protect — see ENG-02(c). Injury-triggered approval still fires (it keys off `rules`, not mode) | SRC |
| **ENG-15** | P1 | C | **Zero Edge Functions deployed to QA.** All 19 return `404 NOT_FOUND`. Layer 13 and the AI half of Layers 1 and 8 cannot execute at all | **LIVE-C** |
| **ENG-16** | P1 | C | The per-project Vault secrets (`project_url`, `service_role_key`) that 076/080 require appear unset, leaving the coaching crons inert. Correct fail-closed behaviour, but unverified — `vault.decrypted_secrets` is service-role only | **OPEN** (ENV-02) |
| **ENG-17** | P0 | B | **The intelligence substrate is unpopulated in QA**, so `build_workout` returns `selected: []` and `materialize_program_week` now raises. **This is not evidence of a broken engine** | **LIVE-P** — migration 119 header; `PHASE_2_WORKOUT_RECONCILIATION.md` §W3 (`build_workout({size:4,recovery:80}) → {"selected":[]}`) |
| **ENG-18** | P2 | A | **The bootstrap has an undocumented ordering dependency and no guard.** `seed_warmup_library()` silently `continue`s for any pattern whose node does not exist, so running it before `rebuild_movement_graph()` produces zero edges and reports success. Same shape for `rebuild_exercise_intelligence` before the library is seeded | SRC — `088:26-30` |
| **ENG-19** | P2 | A | `build_workout` reports `warmup: []` with no signal distinguishing "this workout needs no warm-up" from "the warm-up library was never seeded". The trace records nothing about it | SRC |
| **ENG-20** | P1 | E | **There is no engine test suite.** Zero tests exercise `score_exercise`, `build_workout`, `plan_program`, `evaluate_week`, `predict_client`, `assemble_weekly_review`, trace completeness, or LLM groundedness. The 514-test Flutter suite covers the workout contract, security statics and app logic; `supabase/tests/security/` covers authorization. **Engine behaviour is entirely uncovered** | SRC — grep across `apps/mobile/test`, `apps/api` |
| **ENG-21** | P3 | A | `predict_client`'s arithmetic is deterministic but unvalidated: `finish = current_date + ceil(weeks_left)*7` is uncapped (a near-zero pace yields an absurd date), and `confidence` sums a pace ratio with two raw percentages. No test pins any of it | SRC — `095:96-120` |
| **ENG-22** | P2 | A | `explain-decision` reads the trace under caller RLS but **writes the cache with the service role**. With ENG-09, an unrelated coach can generate and permanently pin the client-audience explanation on another coach's client's trace | SRC — `explain-decision/index.ts:97-104` |
| **ENG-23** | P3 | A | Doc drift: `movement-intelligence-engine.md` §"Deploy / bootstrap order" says *"apply migrations 082 → 092"*. The engine is now 083–099 plus 119/120/121, and the certification/review UX depends on 086/091 | SRC |
| **ENG-24** | P3 | A | `rank_exercises` calls `score_exercise` **three times per candidate row** (select, breakdown, order-by). At library scale this is a 3× cost on a function that itself does per-row lookups against `exercise_intelligence` and `custom_exercises` | SRC — `087:170-178` |
| **ENG-25** | **P0** | A | **Equipment vocabulary mismatch — the engine will still select nothing after the substrate is populated.** `score_exercise` tests `(p_context->'equipment') ? ex.equipment`, an exact string membership. The seeded library stores `equipment` as the **first element of `equipment_required`**: `dumbbells`, `cable_machine`, `barbell`. Coach Copilot supplies `['barbell','dumbbell','cable','machine','bodyweight']` (home: `['dumbbell','bodyweight','band']`). Only `barbell` matches. Everything else scores `equipment_match = 0` and is rejected under `EQUIPMENT_CONSTRAINT` | SRC — `087:120-126`; `063:129,176`; `064` seed data; `coach_copilot_screen.dart:52-54` |
| **ENG-26** | P2 | A | **Warm-up pattern vocabulary mismatch.** `seed_warmup_library` keys on nine slugs (`hip-hinge`, `squat`, `horizontal-push`, `horizontal-pull`, `vertical-push`, `vertical-pull`, `lunge`, `carry`, `rotation`). The seeded library's patterns slugify to `hinge`, `hip-extension`, `anti-extension`, `rear-delt`, `unilateral`, `carry`, `horizontal-push`, `horizontal-pull`, `vertical-push`, `vertical-pull`. **Five of ten never match** — most importantly `hinge` ≠ `hip-hinge` — and `squat` / `lunge` / `rotation` drills attach to nothing | SRC — `088:26-42`; seed batches 064–073 |

---

## 6. Data dependency map

Every arrow is a hard prerequisite. A dashed box is empty or absent in QA today.

```
  custom_exercises  (22 migration-seeded; QA total unknown)
        │
        │ rebuild_movement_graph()          rebuild_exercise_intelligence()
        │        [content editor]                   [content editor]
        ▼                                            ▼
  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ┐                    ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
    movement_nodes                          exercise_intelligence     ◀── ENG-17 empty
    movement_edges  │                     │  (status='draft')        │
  └ ─ ─ ─ ─ ─ ─ ─ ─ ┘                    └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
        │  seed_warmup_library()                     │
        │  ◀── ENG-26 vocabulary mismatch            │  ◀── ENG-07: no approval gate
        ▼                                            ▼
   generate_warmup() ──────────────▶  score_exercise() ◀── ENG-25 equipment mismatch
                                              │
                                              ▼
                                       build_workout()  ──▶ selected[] + trace[]
                                              │
                            ┌─────────────────┼─────────────────┐
                            ▼                 ▼                 ▼
                     generate_workout   materialize_       validate_week()
                            │            program_week()      ◀── ENG-11 no caller
                            ▼                 │
                     decision_traces          │  ◀── ENG-01 no caller
                            │                 ▼
                            │          program_workouts (canonical contract, 119)
                            │                 │
                            │                 ▼
                            │          workout_sessions ──▶ workout_set_logs
                            │                 │
                            │                 ▼
                            │       ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
                            │         weekly_feedback              ◀── ENG-02
                            │         (subject_id ALWAYS NULL)   │
                            │       └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
                            │            │            │
                            │            ▼            ▼
                            │     evaluate_week   predict_client ──▶ (always no_data)
                            │            │            │
                            │            ▼            ▼
                            │     regenerate_    assemble_weekly_review
                            │      program            │  (always no_feedback)
                            │            │            ▼
                            │            │      communications.brief
                            │            │            │
                            └────────────┴────────────┤
                                                      ▼
                                    ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
                                      explain-decision                ◀── ENG-15
                                    │ generate-communication         │     404 in QA
                                    └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
                                                      │
                                                      ▼
                                              coach surfaces only     ◀── ENG-10
                                              (client: nothing)
```

---

## 7. The critical question — one complete client journey, traced

A hypothetical client, **Maya**, self-guided-to-coach-guided, goal *hypertrophy*, home gym,
one previously injured shoulder, PAR-Q clean.

| # | Step | What the architecture intends | What happens today | Break |
|---|---|---|---|---|
| 1 | **Client profile** | onboarding writes `user_profiles` | works — but `CON-02` (onboarding marks itself complete on a failed save) and `CON-03` (`dietary_restrictions` serializer) mean the profile can be empty while flagged complete | inherited, Phase 3 |
| 2 | **Goals** | `fitness_goal` → engine context | works. Copilot maps free text → `hypertrophy` | — |
| 3 | **Health constraints** | injuries → `injuries[]` in context; PAR-Q risk → a constraint | injuries flow. **PAR-Q risk does not reach the engine at all** | **ENG-12** (D) |
| 4 | **Movement intelligence** | graph + per-exercise intelligence | **empty in QA** | **ENG-17** (B) |
| 5 | **Decision** | `build_workout` selects 5 movements under 5 rules and emits a trace | returns `selected: []`. **And after the substrate is populated it will still return `[]`**, because the seeded equipment vocabulary cannot match the context's | **ENG-17** (B) **+ ENG-25** (A) |
| 6 | **Program** | `plan_program` → 12 weeks of mesocycles; saved with `engine_generated = true` | works. Coach reaches it at `/program-designer` | — |
| 7 | **Week materialization** | `materialize_program_week` writes each session as canonical prescriptions | **never called by anything.** The program has zero sessions | **ENG-01** (A/E) |
| 7b | *(if it were called)* | one distinct session per split day | all sessions in the week would be **identical**; the split would be a title | **ENG-06** (A) |
| 7c | *(if it were called)* | `weight_kg: null`, structure from the caller's context | correct per 119 — but the engine still assigns no sets/reps/rest of its own | **G-1** (§12) |
| 8 | **Workout** | client opens the session; canonical codec decodes it | this half is **solid** — 119/120/121 + the contract test suite. Nothing here is broken | ✅ |
| 9 | **Completed sets** | `workout_set_logs` keyed on `(session_id, set_id)`; completed history immutable | **solid** — 103–108, 111, 120, plus `SEC-11`'s DB-side immutability from Phase 1 | ✅ |
| 10 | **Observation** | a completed week becomes `weekly_feedback` | **only a coach can enter it, through `/continuous-coaching`, and `subject_id` is never written.** There is no client-side weekly feedback surface at all | **ENG-02** (A) + **ENG-10** (E) |
| 11 | **Learning** | `evaluate_week` reads feedback → an action; `predict_client` builds an outlook | `evaluate_week` finds the row (keyed on `program_id`+`week`) and works, **but its coaching-mode lookup resolves NULL**, so coach approval never triggers. `predict_client` finds **zero** rows and returns `no_data` for every client, forever | **ENG-02** (A) |
| 12 | **Adaptation** | future weeks regenerate; completed weeks locked; version + trace + diff | volume and deload adapt correctly and immutability holds. **`REPLACE_EXERCISES` and `REDUCE_COMPLEXITY` do nothing to exercises**, and no week is re-materialized, so an injury adaptation changes a multiplier and not a single movement | **ENG-13** (A/E) |
| 13 | **Explanation to client** | `explain-decision` narrates the trace in the client's language; the weekly review is sent and the client reads it | `assemble_weekly_review` returns `no_feedback` (ENG-02); `generate-communication` and `explain-decision` are **404 in QA** (ENG-15); and **even fully working, no client screen reads a trace, an explanation, a prediction or a communication** | **ENG-02 + ENG-15 + ENG-10** |

### The chain, scored

Of thirteen links, **four hold** (steps 2, 6, 8, 9 — plus step 12's immutability), and
**nine break**. The breaks are not evenly distributed: they cluster at exactly three places.

1. **The substrate is empty and its vocabulary does not match the caller's** — steps 4–5.
2. **Two functions have no caller** — step 7 (`materialize_program_week`) and step 11's
   validator, and **one column is never written** — step 10 (`subject_id`), which alone
   disables steps 11, 12's approval gate and 13's brief.
3. **The client end of the product does not exist** — steps 10 and 13.

Everything between step 6 and step 9 — planning, the prescription contract, the session,
set identity, immutability — is in good shape. The engine's *middle* is sound. Its
*intake* is starved and its *outlet* is unbuilt.

---

## 8. The known QA condition, investigated and classified

The brief asked for three specific conditions to be investigated explicitly.

### 8.1 "Intelligence substrate may be empty" → **CONFIRMED. Category B (missing QA data).**

- `exercise_intelligence` is unpopulated; `build_workout` returns `selected: []` (**LIVE-P**,
  migration 119 header and `PHASE_2_WORKOUT_RECONCILIATION.md` §W3). Could not be
  re-measured this session (no authenticated QA session).
- **This is not a code defect and it is not evidence of a broken engine.** The engine
  executed, applied its rules and correctly reported an empty selection.
- **Crucially, the fix does not require any Edge Function.** `rebuild_movement_graph()`
  and `rebuild_exercise_intelligence()` are pure SQL, exist in QA (LIVE-C), and are
  reachable from the Content Center as a content editor. One session there populates the
  graph and a draft profile for every exercise.
- **Two things must be decided before doing it**, and they are why it is not a pure data
  task: (a) `rebuild_exercise_intelligence` writes `status = 'draft'`, and because nothing
  gates on status (**ENG-07**) those heuristic profiles become production truth the moment
  they are written; (b) even fully populated, **ENG-25** means the engine will still select
  nothing until the equipment vocabulary is reconciled.

### 8.2 "`build_workout` may select nothing" → **CONFIRMED, with a second, independent cause.**

| Cause | Category | Note |
|---|---|---|
| Empty `exercise_intelligence` — the inner join yields no candidates | **B** | ENG-17. Fixed by populating |
| **Equipment string mismatch** — `dumbbells`/`cable_machine` vs `dumbbell`/`cable` | **A** | **ENG-25. Survives populating the substrate.** This is the finding that matters: fixing the data alone will not fix the symptom |
| Warm-up returns `[]` for five of ten seeded patterns | **A** | ENG-26 — affects `warmup`, not `selected` |

### 8.3 "Edge Functions may not be deployed" → **CONFIRMED LIVE. Category C.**

All 19 functions in `supabase/functions/` return `HTTP 404 NOT_FOUND` on QA (**LIVE-C**).
This is deployment, not code: every function's source is present and coherent. Blocked on
it: `explain-decision`, `generate-communication`, `ai-generate-workout`,
`ai-coaching-engine`, `ai-coach`, and all four `enrich-exercise-*`. Also required and
separately unverified: the `ANTHROPIC_API_KEY` secret (per-project) and the Vault
`project_url` / `service_role_key` pair (ENG-16 / ENV-02) — **QA values only, never
production values.**

### 8.4 Full classification of every finding

| Category | Findings |
|---|---|
| **A — code defect** | ENG-01, ENG-02, ENG-03, ENG-04, ENG-05, ENG-06, ENG-08, ENG-09, ENG-13, ENG-14, ENG-18, ENG-19, ENG-21, ENG-22, ENG-23, ENG-24, **ENG-25**, ENG-26 |
| **B — missing QA data** | **ENG-17** |
| **C — missing deployment / configuration** | **ENG-15**, ENG-16 |
| **D — missing product decision** | **ENG-12** (PAR-Q policy, Q-4), ENG-07 (partly — the *mechanism* is a code fix, the *gate policy* is a decision), plus A-1…A-4 in §12 |
| **E — missing implementation** | **ENG-10** (client presentation), **ENG-11** (weekly validator never invoked), **ENG-20** (no engine tests), ENG-01 and ENG-13 in part, and contract gaps **G-1 / G-2 / G-3** |

**The distribution is the headline.** The QA condition everyone expected — *empty
substrate, undeployed functions* — accounts for **three** findings. Eighteen are code
defects that no amount of QA data or deployment will resolve, and the two most severe of
those (ENG-01, ENG-02) are single missing call sites and a single unwritten column.

---

## 9. QA gaps

| Gap | Status | Owner action |
|---|---|---|
| Edge Functions not deployed (all 19) | **LIVE-C** | Deploy to QA; set `ANTHROPIC_API_KEY` as a QA secret |
| Vault `project_url` / `service_role_key` unset | **OPEN** | One-time per-project setup; **QA values only** |
| `exercise_intelligence` / `movement_nodes` / `movement_edges` unpopulated | **LIVE-P** | Content Center: Rebuild graph → Rebuild intelligence → Seed warm-up library — *after* deciding §12 A-2 |
| Exercise library thin (22 migration-seeded; QA total unmeasured) | **OPEN** | Count once an authenticated QA session is available; the `program_generator` certification needs `alternatives`, and `ai_coach` needs cues + mistakes + alts |
| No authenticated QA credential available to this workstream | **blocker for re-measurement** | Provide a QA content-editor and a QA coach credential, or run `supabase/tests/security/setup-identities.mjs` and share the fixture ids |
| `weekly_feedback` has no rows with a usable `subject_id` | consequence of ENG-02 | Fix the writer before generating any fixture data, or the fixtures will encode the defect |
| No engine behaviour fixtures | ENG-20 | Build a fixture set of legitimate product data — per the execution plan, *fixtures will not be fabricated to make tests pass* |

---

## 10. Production readiness gaps

Production was **not contacted**. These are recorded, not acted on.

1. **Migrations 113–121 are not in production.** Every Phase 1 security finding
   (SEC-01…SEC-05, SEC-11) is a property of the migration source and is therefore live in
   production. Production rollout is a separate, explicitly authorized activity.
2. **The engine's own gaps are production gaps too.** ENG-01, ENG-02, ENG-07, ENG-25 and
   ENG-26 are source-level and exist wherever the code runs. ENG-02 in particular means any
   production coach entering weekly feedback today produces data the predictor and the
   review engine cannot see.
3. **Migration 083's retarget never applied in production either.** By its own header,
   083/084/086/087/090/091/097/099 *"never applied in any environment"* before the in-place
   correction. QA now has them (LIVE-C). **Production almost certainly does not** — meaning
   production has no content pipeline, no certification view, no `exercise_intelligence`
   table and no per-attribute review. This should be confirmed before any rollout plan is
   written, and it is the single largest schema divergence in the engine surface.
4. **Migration 076's `B2-6` in-place fix does not self-apply** to an environment that
   already ran the old 076 — carried forward from the Phase 0 reconciliation §6.
5. **No engine behaviour test exists to gate a release** (ENG-20). Per
   `REMEDIATION_EXECUTION_PLAN.md` Phase 4 step 3, the "engine decides, AI explains"
   invariant is supposed to acquire a standing test. It has none yet.
6. **`decision_traces` cross-coach readability (ENG-09)** ships to production with the
   engine. It should be closed in the same change that closes the rest of Phase 1.

---

## 11. Recommended next steps

Ordered by dependency, not by severity. Each step is small, and each one unblocks the next.

### Step C-0 — Make the chain observable *(no behaviour change)*
Obtain an authenticated QA content-editor credential and re-measure what this audit could
not: substrate row counts, library size, certification summary, Vault secret presence.
Everything below is cheaper once those numbers are real rather than inferred.

### Step C-1 — Reconcile the vocabularies **(ENG-25, ENG-26)** — *before* populating anything
This is first because populating the substrate without it produces a *populated engine that
still selects nothing*, which is a much harder thing to debug than an empty one. Decide
whether the canonical vocabulary lives in the library (`equipment`, `movement_pattern`) or
in the caller's context, then converge — one direction, in one place. Add a standing test
that every seeded `equipment` value and every seeded `movement_pattern` slug is a member of
the vocabulary the engine queries with.

### Step C-2 — Deploy the QA runtime **(ENG-15, ENG-16)**
Deploy all Edge Functions to QA; set `ANTHROPIC_API_KEY` and the Vault pair with **QA
values only**. Then verify each of the five AI functions answers, and that the crons are no
longer inert.

### Step C-3 — Populate the substrate **(ENG-17)**, having first answered §12 A-2
Content Center: Rebuild graph → Rebuild intelligence → AI-enrich → Knowledge Review → Seed
warm-up library, in that order. Add the ordering guard ENG-18 asks for so a step run out of
order reports rather than silently succeeds.

### Step C-4 — Close the two P0 code defects **(ENG-01, ENG-02)**
Both are small and neither requires a product decision.
- **ENG-02:** write `subject_id` at the one writer, and give the Continuous Coaching screen
  a client selector so it has a subject to write. Add a `NOT NULL` constraint or a trigger
  so the column can never silently go unwritten again. Regression test: feedback submitted
  in-app is visible to `predict_client`, `assemble_weekly_review` and `evaluate_week`'s
  coaching-mode lookup.
- **ENG-01:** give `materializeWeek` a caller — the Dynamic Program Builder's own success
  path is the natural home, since its message already promises it. Regression test: an
  engine program created through the UI has `program_workouts` rows the client codec can
  decode.

### Step C-5 — Fix the Copilot path **(ENG-03, ENG-04, ENG-05)**
Stop the UI authoring a prescription; stop a one-session approval replacing a multi-week
assignment; write a capitalized `day_of_week`. ENG-03's *correct* fix depends on §12 A-1 —
until that is answered, the honest interim is to emit `sets`/`reps` from the coach's own
input rather than from a constant.

### Step C-6 — Make review mean something **(ENG-07)**
Gate `build_workout` / `rank_exercises` / `materialize_program_week` on
`exercise_certifications` and/or `exercise_intelligence.status`. The *mechanism* is a
one-line predicate; **which gate** (certification module, profile status, or both) is §12
A-2 and is a product decision.

### Step C-7 — Build the engine test suite **(ENG-20)**
The suite the remediation plan's Phase 4 already specifies: deterministic engine first, AI
explanation second, and the boundary between them third — provenance, failure handling, and
a standing assertion that no LLM output alters a decision. Model it on
`supabase/tests/security/`, which is the right shape and already proves it works.

### Step C-8 — Complete the adaptation loop **(ENG-11, ENG-13)**
Invoke `validate_week` on a materialized week; implement `REPLACE_EXERCISES` against the
movement graph and re-materialize affected weeks. Both are engine work with their own
scope; neither should be improvised.

### Step C-9 — Build the client end **(ENG-10)**
The trace, the explanation, the prediction and the sent weekly review all exist, are all
correctly authorized for a client to read, and none is rendered. Per
`product-bible.md` §7 these are *presentation layers over existing engines* — the cheapest
large win in this report, and the one that makes the differentiator visible to the person
it is for.

---

## 12. Unresolved authority decisions

**Q-A is CLOSED and this audit does not reopen it.** `docs/WORKOUT_DOMAIN_CONTRACT.md` §8
records the product-authority decision of 2026-08-24: *the deterministic coaching /
program intelligence engine **is** authoritative for workout prescription* — selection,
order, sets, reps/ranges, rest, tempo, RPE/RIR, load, progression/regression, coaching
constraints and warm-up. AI is not an independent prescription authority. Load follows
§3.6: `null` means no prescribed load, `0` means a prescribed zero, and **the engine must
not invent a load merely because the field exists.**

What remains open is not *whether* the engine prescribes — it is **by what rule**. Below is
every place that unanswered methodology touches architecture, plus the decisions this audit
surfaced that no existing document settles. **None is decided here.**

### A-1 · The prescription model itself (contract gap G-1)
`build_workout` selects movements and assigns no sets, reps, load, rest, RPE or tempo.

**Where it touches architecture:**
- `build_workout` (089) — a prescription stage would sit after selection and before the
  trace, so that *why these numbers* is recorded alongside *why these movements*.
- `decision_traces.trace[]` — the trace format would need prescription events, or
  explanations will narrate selection while the client is looking at numbers the trace
  cannot account for. This is the load-bearing one: **the explainability guarantee is
  only as complete as the trace.**
- `materialize_program_week` (119 §7) — currently takes `sets`/`reps`/`rest_seconds` from
  the *caller's context*, explicitly so they are the caller's numbers and not invented. A
  prescription model replaces that source.
- `plan_program`'s `volume_multiplier` and `intensity` (093) — already computed per week
  and currently consumed **only** to scale `size`. A prescription model is where they
  would finally mean something.
- `scoring_version` / `rules_version` — a new deterministic stage means a version bump so
  historical traces stay reproducible.
- **ENG-03** — until this is answered, some layer is inventing 3×10. Today it is the
  Flutter UI, which is the worst of the available places for it to live.

### A-2 · What gates the engine's knowledge (ENG-07)
`rebuild_exercise_intelligence` writes `status = 'draft'`; `enrich-exercise-intelligence`
writes `ai_generated`; the review pipeline produces `approved`. **Nothing in the engine
distinguishes them.** Product bible §2.4 says reviewed knowledge is production truth.

**The decision:** does the engine consume (a) only `status = 'approved'` profiles, (b) only
exercises whose `exercise_certifications.program_generator` / `.ai_coach` is true, (c) both,
or (d) draft profiles with a recorded confidence caveat in the trace?

**Where it touches architecture:** the join predicate in `build_workout` /
`rank_exercises`; whether the trace records the provenance of the knowledge each decision
rested on; and, immediately, **whether it is safe to bootstrap the QA substrate at all** —
under (a) or (b), Step C-3 produces an engine that still selects nothing until a human
reviews 22+ exercises.

### A-3 · Does an LLM-derived `intensity_delta` count as a coaching decision? (§4 B-1)
`ai-coaching-engine`'s daily insight emits `focus` and `intensity_delta` from a Claude call,
and `ai_coaching_architecture.md` §8 documents both reaching the active-workout load cue and
`generate_client_plan`'s structure. Read strictly against product bible §6 (*"AI may NOT
invent or alter programming, sets/reps, or progression"*), that is an LLM altering training.
Read as *communication*, it is a tone/emphasis hint.

**Where it touches architecture:** whether `coachAdjustmentProvider` is a presentation
concern or an engine input; whether 077's focus bias is legitimate; and whether daily
insight generation must move behind a deterministic gate before beta.

### A-4 · Rep ranges and RIR (contract gaps G-2, G-3)
The closed Q-A decision names *"reps / rep ranges"* and *"RPE/RIR"* as engine outputs. The
product implements a single integer `reps` and `rpe` only. `"8-12"` is a contract violation,
correctly refused rather than silently resolved. Representing a range needs a schema shape,
a client rendering and a logging semantic; whether RIR is a distinct field or a presentation
of RPE is the same decision. **Both belong to A-1's scope, not to a contract repair.**

### A-5 · PAR-Q policy (CON-04 / Q-4 / G-4) — still open
The *mechanism* is clear and cheap: a risk term in `build_workout`'s context plus a
deterministic exclusion. The *policy* — gate training entirely, cap intensity and exclude
contraindicated patterns, or advise the coach only — carries clinical weight and is not
settled by any document in this repository.

### A-6 · Who may read a decision trace (ENG-09)
Migration 089 grants every account with role `coach` read access to **every** trace
platform-wide. Fixing it to the subject's active coach is mechanical. Whether platform staff
(`admin`, `content_manager`) retain blanket read for engine QA — and whether that survives
into production — is a policy call, and it interacts with ENG-22's cache-write path.

---

## 13. What this audit did not do

- **Did not redesign the engine.** No architectural alternative is proposed; every
  recommendation is either a repair to stated intent or a decision handed back.
- **Did not invent a coaching rule.** Where a rule is absent it is recorded as absent.
- **Did not decide the Q-A prescription methodology.** §12 A-1 lists the six places it
  lands and stops there.
- **Did not contact production.**
- **Did not write a migration or change behaviour.** The only file added is this report.
- **Did not fabricate fixtures.** Substrate population is recommended as a deliberate,
  reviewed act — per the execution plan, *fixtures will not be fabricated to make tests
  pass*.

---

## 14. Bottom line

The deterministic coaching intelligence system is **more built than it is broken, and more
broken than it is wired**.

Eleven of thirteen layers are implemented and deployed to QA — verified live, not assumed.
The deterministic core is genuinely deterministic: no LLM touches a decision anywhere in
Layers 2–7, the trace is complete and unforgeable, and the AI functions are hard-constrained
to it. Migration 119's prescription contract and the Phase 1 authorization work are both
high-quality and should not be disturbed.

What stands between that and a working product is smaller than it looks, and different from
what was expected. The anticipated blockers — an empty substrate and undeployed Edge
Functions — are real (both confirmed, one live this session) and are a data task and a
deployment task. The blockers that actually sever the client journey are three code defects
of a few lines each: **a function nobody calls** (ENG-01), **a column nobody writes**
(ENG-02), and **two vocabularies that do not match** (ENG-25). And the reason none of this
was caught is the fifth finding: **the engine has no behavioural test coverage at all**
(ENG-20).

The engine decides. AI explains. Today, the engine decides nothing because it has nothing to
decide over, and the explanation reaches no client because no client screen was built to
receive it. Both are fixable without redesigning anything.
