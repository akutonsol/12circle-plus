# QA Workstream J — AI / Intelligence Decision Integrity

**Scope** — the AI and intelligence system audited as a *governed decision pipeline*:
inputs, validation, safety constraints, the deterministic-engine boundary, provenance,
subject identity, failure behaviour, and whether any of it reaches the product.

**Not in scope** — whether the model's prose is good. Nothing in this report is a
judgement about writing quality.

**Environment** — all live evidence was gathered against the **QA** project
`eyqtldjqpgpljlqvpowh` (`12Circle QA`). Production was not contacted; see §15.

**Date** — 2026-08-24. **Baseline** — Phase 0, Phase 1 security remediation
(migrations 113–118) and Phase 2 workout reconciliation (119–122) are complete and were
verified, not assumed. Nothing in those phases was undone.

---

## 1. Executive summary

The intelligence architecture is well conceived. The separation it claims — *the
deterministic engine decides, the LLM explains* — is real in the two places it matters
most: `explain-decision` and `generate-communication` are hard-constrained to a recorded
trace or a deterministic brief, they read under the caller's RLS, and they cannot write a
decision. `ai-generate-workout` validates the model's output against a contract rather
than passing it through, and refuses to prescribe load. Phase 1's authorization work holds
almost everywhere it was applied. The design is not the problem.

The problem is that **almost nothing in the pipeline is actually wired up, and several of
the things that are wired up fail on exactly the safety path they exist to protect.**

Six facts, each verified live this session:

1. **A member cannot declare an injury.** `PATCH user_profiles {has_injuries: true,
   injury_locations: 'left knee'}` is rejected with `22P02 malformed array literal:
   "active_injuries"`. The PAR-Q classifier (`derive_parq_risk`, migration 115) appends
   three of its flags — `pregnancy`, `postpartum`, `active_injuries` — as untyped literals
   to a `text[]`, which Postgres resolves as `anyarray || anyarray` and then fails to
   parse. `apply_parq_risk()` is a `BEFORE INSERT OR UPDATE` trigger, so the throw rejects
   the whole write. Onboarding intake writes exactly these columns. **(F-J-17)**

2. **The deterministic engine throws whenever recovery is low.** The same bug, again:
   `build_workout` appends `'RECOVERY_REDUCTION'` the same way. `recovery = 60` returns
   200; `recovery = 59` returns `22P02`. The single rule that protects an under-recovered
   member is the only rule in the function that cannot run. **(F-J-07)**

3. **The AI coach is told nothing about the member.** Both `ai-generate-workout` and
   `ai-coaching-engine` select `user_profiles.goal`, which does not exist (the column is
   `fitness_goal`); the workout generator also selects `equipment`, which does not exist.
   PostgREST answers `42703`, supabase-js returns `{ data: null }` without throwing, and
   the code's `?? 'general'` / `?? {}` turns a hard schema error into a confident default.
   Every AI workout is generated for a "general"-goal, "Bodyweight"-equipped,
   "intermediate" gym-trainee with no injuries, whoever the member actually is. **(F-J-02)**

4. **The safety substrate exists, is correct, and is read by nothing.** `risk_level`,
   `risk_flags` (including `pregnancy`, `postpartum`, `doctor_advised_no_exercise`) and
   `food_allergies` are captured, server-classified and stored. No AI prompt reads them.
   `score_exercise` has no PAR-Q dimension at all — passing `risk_level: 'high'` changes
   no score by a single point. The nutrition coach that produces meal plans and grocery
   lists receives no subject context whatsoever. **(F-J-05, F-J-26)**

5. **The engine has nothing to plan from.** `exercise_intelligence` holds 0 profiles
   against 621 exercises; the movement graph holds 0 nodes and 0 edges. `build_workout`
   answers **HTTP 200 with `selected: []`** — no error, no status field, no triggered
   rule. Nine decision traces are recorded on QA; every one of them is an empty decision
   with no rule triggered and nothing rejected. Separately, the only automated way to
   populate the substrate — `rebuild_exercise_intelligence()` — writes neither
   `contraindications` nor `joint_stress`, the two columns the injury rule reads. Even
   fully populated by that path, `injury_compatibility` would be 100 for every exercise
   and `INJURY_PREVENTION` could never fire. **(F-J-06, F-J-08, F-J-23)**

6. **None of the nine AI edge functions is deployed.** All seven probed return
   `404 NOT_FOUND` from the functions gateway. Every AI surface in the product is dead on
   QA, and no AI behaviour can be verified end-to-end until they are deployed. **(F-J-15)**

Two further findings sit outside the AI pipeline proper but were found through it and are
serious:

- **`materialize_program_week` lost its authorization guard.** Migration 116 §4 wrapped
  five engine functions in `can_act_for` / `can_act_on_program` and warned in its own
  comment that a later `CREATE OR REPLACE` by the public name would replace the wrapper
  and silently drop the guard. Migration 119 did exactly that. Migration 122 caught the
  `search_path` and `EXECUTE` halves of the same escape and not this one. Live: an
  unrelated authenticated client reaches the engine body against another coach's program,
  while all four sibling functions correctly return `403`. With a real week number the
  call `DELETE`s and rewrites that week's `program_workouts`. **(F-J-01)**

- **Any coach reads every member's decision traces.** `decision_traces`' SELECT policy
  grants an unscoped role arm — `role in ('admin','content_manager','coach')` — unlike
  `predictions`, `communications`, `program_versions` and `weekly_feedback`, which all
  check the owning program or an active relationship. Live: a probe coach with **zero**
  relationship rows read all 9 traces across 2 unrelated subjects. **(F-J-12)**

**Overall posture.** The AI pipeline is not shippable and, importantly, is also not
currently dangerous *in production terms*, because none of it runs. The risk is that the
five defects in the input and safety layers are individually invisible — a missing column
is a default, a failed read is an empty array, an empty constraint set is a permissive
one — so deploying the edge functions would turn a dead system directly into a confidently
wrong one, with no error anywhere to signal it. The sequencing in §11 exists to prevent
that specific order of events.

---

## 2. Architecture map

```
                            ┌───────────────────────────────────────────────┐
                            │  SAFETY SUBSTRATE (exists, correct, orphaned) │
                            │  user_profiles.parq_answers                   │
                            │    → derive_parq_risk()  [115, BEFORE trigger]│
                            │    → risk_level / risk_flags / risk_score     │
                            │  user_profiles.food_allergies      [013]      │
                            │  user_profiles.has_injuries / injury_locations│
                            └───────────────┬───────────────────────────────┘
                                            ╎  ← F-J-05: NOTHING reads these
                                            ╎  ← F-J-17: writing them throws
                                            ╎
  ┌─────────────────────────────────────────┴────────────────────────────────────┐
  │                            DETERMINISTIC LAYER                                │
  │                                                                               │
  │  custom_exercises (621) ──┬─► exercise_intelligence (0)  ◄── F-J-06 EMPTY     │
  │  movement_nodes (0)       │      ▲                                            │
  │  movement_edges (0)       │      └── rebuild_exercise_intelligence()  [087]   │
  │                           │             └─ writes no contraindications /      │
  │                           │                joint_stress          ◄── F-J-23   │
  │                           │      └── enrich-exercise-intelligence (AI, [fn])  │
  │                           │             └─ status='ai_generated', unreviewed, │
  │                           │                consumed anyway        ◄── F-J-22   │
  │                           ▼                                                   │
  │  score_exercise(ex, ctx)  ──► {goal, equipment, recovery, experience,         │
  │       [087]                    injury_compatibility, movement_balance}        │
  │                           ▼                                                   │
  │  build_workout(ctx)  [089]  rules: RECOVERY_REDUCTION ◄── F-J-07 THROWS       │
  │                             EQUIPMENT_CONSTRAINT / INJURY_PREVENTION          │
  │                             MAX_SYSTEMIC_FATIGUE / MOVEMENT_VARIETY           │
  │                             gates read NULL → accept   ◄── F-J-09             │
  │                           ▼                                                   │
  │  generate_workout(ctx, subject)  [089 → guarded 116]                          │
  │                           ├──► decision_traces (subject, 4 version stamps,    │
  │                           │      context, result, trace, rules_triggered)     │
  │                           │      context is caller-supplied ◄── F-J-13        │
  │                           │      read scope unscoped        ◄── F-J-12        │
  │                           ▼                                                   │
  │  materialize_program_week(program, week, ctx)  [093 → 116 → 119]              │
  │      ◄── F-J-01 guard dropped by 119        ──► program_workouts              │
  │  plan_program / evaluate_week / regenerate_program / predict_client /         │
  │  assemble_weekly_review / create_weekly_review    (guards intact)             │
  └───────────────────────────────────────────────────────────────────────────────┘
                                            │
                     ┌──────────────────────┴───────────────────────┐
                     ▼                                              ▼
  ┌──────────────────────────────────┐        ┌──────────────────────────────────┐
  │  L4 / L8 — LLM AS EXPLAINER      │        │  LLM AS AUTHOR (no engine input) │
  │  (correct by construction)       │        │                                  │
  │  explain-decision   → trace only │        │  ai-generate-workout   F-J-02/10 │
  │  generate-communication → brief  │        │  ai-coaching-engine    F-J-02/03 │
  │    only, draft only, caller RLS  │        │  ai-coach              F-J-18/28 │
  │  explain_model IS recorded       │        │  analyze-food-image    F-J-27    │
  └──────────────────────────────────┘        │  /ai/nutrition/message F-J-26    │
                     │                        │  no provenance         F-J-14/25 │
                     ▼                        └──────────────────────────────────┘
            ALL NINE EDGE FUNCTIONS: 404 NOT DEPLOYED  ◄── F-J-15
```

Two independent AI runtimes exist and do not know about each other:

| Runtime | Where the key lives | Auth | Subject context |
|---|---|---|---|
| Supabase Edge Functions (Deno) | `ANTHROPIC_API_KEY` edge secret | Supabase JWT via `auth.getUser()` | assembled per function (§4) |
| NestJS API `apps/api` | `ANTHROPIC_API_KEY` server env | `SupabaseAuthGuard` | **none** (F-J-26) |

The NestJS route is the security-correct one — Workstream "QA environments" moved the
Anthropic key off the Flutter client and behind it, and that work holds: the key is
server-only, never returned, never logged, and the route is guarded at the controller.
Its defect is informational, not credential-related.

---

## 3. AI feature inventory

| # | Feature | Surface | Model | Deployed (QA) | Reachable from UI | Persists |
|---|---|---|---|---|---|---|
| 1 | Conversational coach + memory extraction | `ai-coach` | `claude-haiku-4-5-20251001` ×2 | **no** | `/ai-coach` (PaywallGate: `aiGuided`) | `ai_conversations`, `ai_memories` |
| 2 | Daily insight / weekly review / goal prediction / accountability / risk / meals / progress | `ai-coaching-engine` | `claude-sonnet-4-6` | **no** | home briefing sheet + AI Coach screen | `ai_insights`, `ai_reviews`, `ai_goal_predictions`, `notifications` |
| 3 | One-off AI session generator | `ai-generate-workout` | `claude-sonnet-4-6` | **no** | Train hub → `generateAiWorkout` | **nothing** |
| 4 | Food photo → calories + macros | `analyze-food-image` | `claude-sonnet-4-6` | **no** | Nutrition → AI scan | via `logMeal` → `nutrition_logs` (unlabelled) |
| 5 | Decision-trace narration (L4) | `explain-decision` | `claude-sonnet-4-6` | **no** | MIE debugger, coach copilot | `decision_traces.explanation_*`, `explain_model` |
| 6 | Weekly-review phrasing (L8) | `generate-communication` | `claude-sonnet-4-6` | **no** | coach program service | `communications.client_text/coach_text`, `llm_version` |
| 7 | Exercise intelligence enrichment | `enrich-exercise-intelligence` | `claude-sonnet-4-6` | **no** | exercise DB admin | `exercise_intelligence` (+ `evidence_source`, `ai_version`) |
| 8 | Exercise content enrichment | `enrich-exercise-content` | `claude-sonnet-4-6` | **no** | exercise DB admin | `exercise_content` |
| 9 | Exercise seed enrichment | `enrich-exercise` | `claude-sonnet-4-6` | **no** | exercise DB admin | `custom_exercises` |
| 10 | AI Nutrition Coach (chat, meal plans, grocery lists) | `POST /ai/nutrition/message` (NestJS) | `DEFAULT_ANTHROPIC_MODEL = claude-sonnet-4-6`, overridable | n/a (API) | AI Nutrition screen | **nothing** |
| 11 | "AI-Guided" daily suggestions / weekly review | `ai_insights.dart` (Dart) | none — deterministic Riverpod providers | n/a | home + progress | nothing |

Feature 11 is branded "AI-Guided" in the UI and contains no AI. That is a labelling
question, not a defect; it is noted because it makes "does the AI work?" hard to answer
from the app alone — the AI-looking cards on the home screen render fine while every real
AI surface is dead.

Model identifiers: three distinct strings across ten call sites, each a per-file literal
(F-J-25). `claude-haiku-4-5-20251001` is the date-suffixed form of `claude-haiku-4-5`;
both resolve, but pinning the two Haiku call sites in one form and the eight Sonnet call
sites in another is the kind of drift a central constant exists to prevent.

---

## 4. Input matrix

What each AI decision surface is *supposed* to receive, against what it *actually*
receives. "Silently empty" means the read fails and the code substitutes a default without
surfacing anything.

| Input | `ai-generate-workout` | `ai-coaching-engine` | `ai-coach` | `analyze-food-image` | `/ai/nutrition` | `build_workout` |
|---|---|---|---|---|---|---|
| Profile (goal, experience, location) | **silently empty** F-J-02 | **silently empty** F-J-02 | ✅ `select('*')` | ✗ none | ✗ none | caller-supplied |
| Equipment | **silently empty** F-J-02 | ✗ | ✅ (in `*`, unused in prompt) | ✗ | ✗ | caller-supplied |
| Goals (`goals` table) | ✗ | **silently empty** F-J-04 (`user_id` absent) | ✗ | ✗ | ✗ | ✗ |
| Injuries (structured `injury_locations`) | read then **discarded** F-J-02 | ✗ | ✅ (in `*`, unused) | ✗ | ✗ | caller-supplied, never sent |
| Injuries (`ai_memories` free text) | ✅ | ✅ | ✅ (writes them) | ✗ | ✗ | ✗ |
| Contraindications (exercise-level) | ✅ library string | ✗ | ✗ | ✗ | ✗ | via `exercise_intelligence` — **empty** F-J-06/23 |
| PAR-Q answers / risk classification | ✗ **F-J-05** | ✗ **F-J-05** | ✅ (in `*`, unused) | ✗ | ✗ | ✗ **F-J-05** |
| Food allergies | ✗ | ✗ **F-J-05** | ✅ (in `*`, unused) | ✗ | ✗ **F-J-26** | n/a |
| Nutrition plan targets | ✗ | ✅ (`meal_suggestion`) | ✅ | ✗ | ✗ **F-J-26** | n/a |
| Nutrition logs (today's intake) | ✗ | **silently zero** F-J-03 | ✗ | ✗ | ✗ | n/a |
| Workout history | last feedback row ✅ | **silently empty** F-J-04 (`workout_sessions.created_at`) | ✅ (`started_at`) | ✗ | ✗ | ✗ |
| Set logs (`progress_insight`) | ✗ | **silently empty** F-J-04 | ✗ | ✗ | ✗ | ✗ |
| Check-ins | ✗ | ✗ | ✅ | ✗ | ✗ | ✗ |
| Cycle / women's-health | ✗ | ✅ (`cycle_logs`, 0 rows on QA) | ✗ | ✗ | ✗ | ✗ |
| Habits | ✗ | **silently empty** F-J-04 (`habit_logs.created_at`) | ✅ | ✗ | ✗ | ✗ |
| Daily / lifetime score | ✗ | daily ✅ / lifetime **silently empty** F-J-04 | ✗ | ✗ | ✗ | ✗ |
| Preferences (likes/dislikes) | ✅ | ✅ | ✅ (writes them) | ✗ | ✗ | ✗ |
| Coach instructions | ✗ | ✗ | assigned habits + plan ✅ | ✗ | ✗ | ✗ |
| Coach persona | ✗ | ✅ | ✗ | ✗ | ✗ | n/a |
| Intelligence substrate | ✗ | ✗ | ✗ | ✗ | ✗ | **empty** F-J-06 |
| Conversation history | ✗ | ✗ | ✗ (stored, never replayed) | ✗ | ✅ client-supplied |  n/a |

Two structural notes:

- **`ai-generate-workout` reads `has_injuries` and `injury_locations` and then never puts
  them in the prompt.** Even if the enclosing select were fixed, the context object it
  builds (`goal, experience, equipment, location, duration_minutes, focus,
  intensity_delta, recovery, memory`) has no injury field. Structured injuries reach the
  model only if the member happened to mention them in chat and the memory extractor
  caught it.
- **The candidate library is an arbitrary 220 of 621 exercises** — `.limit(220)` with no
  `.order()`. Which 220 is unspecified by Postgres, unrecorded, and can change between
  calls. **(F-J-29)**

---

## 5. Safety-input matrix

| Safety input | Captured | Server-authoritative | Writable by member | Read by any decision surface | Failure mode |
|---|---|---|---|---|---|
| PAR-Q answers (8 questions) | ✅ `parq_answers` jsonb | ✅ classified by trigger | ✅ | **no** | — |
| Risk score / level / flags | ✅ derived | ✅ `derive_parq_risk` (115) | ✗ (correct) | **no** F-J-05 | narrative flags **throw** F-J-17 |
| `doctor_advised_no_exercise` | ✅ flag 7 | ✅ → `risk_level = 'high'` | ✗ | **no** | — |
| Pregnancy | ✅ `medical_conditions` | ✅ → moderate + flag | ✅ | **no** | **write rejected** F-J-17 |
| Postpartum | ✅ `medical_conditions` | ✅ → flag | ✅ | **no** | **write rejected** F-J-17 |
| Injuries (has / locations) | ✅ columns | ✅ → `active_injuries` flag | ✅ | discarded F-J-02 | **write rejected** F-J-17 |
| Injury free-text (`ai_memories`) | ✅ | ✗ (model-inferred) | ✅ | ✅ prompt only | inferred, unreviewed |
| Food allergies | ✅ `food_allergies` | n/a | ✅ | **no** F-J-05/26 | — |
| Medical conditions | ✅ | feeds risk level | ✅ | **no** | — |
| Per-exercise contraindications | ✅ `custom_exercises.contraindications` (prompt) / `exercise_intelligence.contraindications` (engine) | reviewable | ✗ | engine: **table empty** F-J-06 | — |
| Per-joint stress | schema only | reviewable | ✗ | engine: **table empty** F-J-06/23 | — |
| Recovery (feedback / cycle) | ✅ | ✗ caller-supplied to engine | ✅ | engine: **throws below 60** F-J-07 | — |

**The load-bearing conclusion.** Every path by which a safety constraint could become an
empty constraint set is open, and none of them announces itself:

| Path | Mechanism | Result |
|---|---|---|
| Missing column | PostgREST `42703` → supabase-js `{data: null}` → `?? {}` | full profile replaced by defaults |
| Failed read in `recent()` | `try/catch` → `data ?? []` | history replaced by "member has no history" |
| Empty substrate | inner join yields no rows | `selected: []`, HTTP 200 |
| Missing score keys | `NULL = 0` and `NULL < 40` are both false | candidate accepted without an equipment or injury check |
| Rejected safety write | `22P02` from a `BEFORE` trigger | `has_injuries` stays `false` forever |
| Model refusal | `content?.[0]?.text ?? '{}'` parses to `{}` | empty coaching artifact persisted with a confidence score |

---

## 6. Provenance matrix

| Artifact | Subject | Creator | Input snapshot | Engine versions | Model id | Confidence | Rationale | Timestamp | Replayable |
|---|---|---|---|---|---|---|---|---|---|
| `decision_traces` | ✅ | ✅ | ✗ caller context only, `{"size":3}` in 8/9 live rows — **F-J-13** | ✅ all four | ✗ **F-J-14** | ✗ | ✅ per-candidate rule + reason | ✅ | **no** |
| `decision_traces.explanation_*` | inherits | — | — | — | ✅ `explain_model` | ✗ | ✅ trace-constrained | ✅ `explained_at` | n/a |
| AI-generated workout | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | model `notes` only | ✗ | **no record at all** — F-J-10 |
| `ai_insights` | ✅ `user_id` | implicit | ✗ | ✗ | ✗ **F-J-25** | ✅ `data.confidence` (+ reasons) | body text | `for_date` (absent on `risk`/`progress` — **F-J-31**) | no |
| `ai_reviews` | ✅ | implicit | ✗ | ✗ | ✗ | ✗ | summary | period | no |
| `ai_goal_predictions` | ✅ | implicit | ✗ | ✗ | ✗ | ✅ model-asserted | summary | ✅ | no |
| `predictions` | ✅ | — | ✅ full prediction jsonb | ✅ `engine_version` | n/a deterministic | ✅ | ✅ | ✅ | yes |
| `communications` | ✅ | ✅ coach | ✅ `brief` + `source_refs` | via brief | ✗ (`llm_version` only) | ✗ | ✅ brief | ✅ | partial |
| `exercise_intelligence` | n/a | — | ✅ source exercise | — | ✅ `evidence_source` + `ai_version` | ✅ overall + per-attribute | — | ✅ | yes |
| `ai_memories` | ✅ | `source: 'inferred'` | ✗ no source message | — | ✗ | ✗ | ✗ | ✅ | no |
| `nutrition_logs` from a photo | ✅ | — | ✗ no image ref | — | ✗ | ✗ discarded | ✗ | ✅ | **no — F-J-27** |
| `ai_conversations` | ✅ | — | ✅ user message | — | ✗ | ✗ | ✅ reply | ✅ | partial |

Two artifacts get this right and are the pattern for the rest: `exercise_intelligence`
(`evidence_source` + `ai_version` + per-attribute confidence) and
`decision_traces.explain_model`. Both prove the cost of doing it is one column.

The most consequential gap is **F-J-13**: a decision trace records the *caller's* context,
not a snapshot of the member's state. Live, 8 of 9 traces record `{"size": 3}` and nothing
else — no goal, no recovery, no injuries, no equipment. The trace can tell you which
exercises the engine picked and which rule rejected which candidate; it cannot tell you
what the member's safety state was when it decided, and it cannot be replayed. For a
training decision about a person's body, that is the part of the audit record that matters.

**F-J-27** deserves a specific note: a model's photo-derived calorie estimate is written to
`nutrition_logs` through the same `logMeal()` path as a manually entered meal, with the
`confidence` field the model returned discarded at the client. Downstream,
`ai-coaching-engine` reads those rows as ground truth for macro arithmetic and weight-trend
coaching. There is no column that distinguishes an estimate from a measurement.

---

## 7. Failure-mode matrix

| Failure | Detected | Behaviour | Fails | Finding |
|---|---|---|---|---|
| `ANTHROPIC_API_KEY` unset | 8 of 9 fns | `500 AI not configured` | closed | — |
| `ANTHROPIC_API_KEY` unset — `ai-coach` | **no** | calls Anthropic, 401 → `500` with the upstream body in `detail` | open (leaks upstream detail) | F-J-28 |
| Unauthenticated caller | ✅ all | `401` | closed | — |
| Anthropic non-2xx | ✅ | `502` (or `500` in `ai-coach`) | closed | — |
| **Model refusal** (`stop_reason: 'refusal'`, HTTP 200) | **no** | `text ?? '{}'` → `{}` → `ai_insights` row titled "Today's Coaching" with an empty body **and a confidence score** | **open** | F-J-20 |
| Output truncated (`max_tokens`) | indirectly | invalid JSON → `502` | closed | — |
| Malformed / fenced JSON | ✅ fence-strip + brace-slice + try/catch | `502` | closed | — |
| Model returns unusable exercises | ✅ per-item contract check | `502` with the rejected list | closed | — |
| **Request timeout / hang** | **no** — no `AbortSignal` on any call | held until the platform kills it; caller sees a generic failure | open | F-J-21 |
| Retry / idempotency | none | a retried `daily_insight` deletes and re-inserts (fine); `risk`/`progress` accumulate unboundedly | partial | F-J-31 |
| DB read fails inside a function | swallowed | `?? []` / `?? {}` → model told "no data" | **open** | F-J-04 |
| Column does not exist | swallowed | whole select returns null → defaults | **open** | F-J-02, F-J-03 |
| Substrate empty | **no** | `200` + `selected: []` | **open** at `build_workout`; **closed** downstream — 119 makes `materialize_program_week` raise | F-J-08 |
| `score_exercise` early return | **no** | `NULL` gates fall through to accept | **open** | F-J-09 |
| PAR-Q classifier throws | n/a | the member's profile write is rejected | closed, but the *wrong* thing closes | F-J-17 |
| `ai_detect_patterns` / `ai_adjust_nutrition` RPC fails | ✅ `.then(()=>{}, ()=>{})` | continues without refreshed patterns, silently | open (advisory only) | — |
| Edge function not deployed — workout | ✅ | `generateAiWorkout` **throws**, UI shows a real error | closed | — (the good pattern) |
| Edge function not deployed — coaching engine | **no** | `generate()` returns `null`, UI renders "no insight yet" | **open** | F-J-16 |
| Stale cache | n/a | `explain-decision` / `generate-communication` serve a cached explanation forever; no invalidation if the trace changes | acceptable (traces are immutable) | — |

---

## 8. Findings

Severity: **P0** blocks any AI/engine launch and has a live safety or authorization
consequence. **P1** produces wrong decisions or unauditable ones. **P2** is a real defect
with bounded or latent impact.

---

### F-J-17 — The PAR-Q classifier throws, so a member cannot declare an injury or a pregnancy

| | |
|---|---|
| **Severity** | **P0** |
| **AI feature** | Safety substrate (all consumers) |
| **Expected** | Setting `has_injuries` + `injury_locations`, or a `Pregnancy` / `Postpartum` medical condition, stores the value and derives `risk_flags`. |
| **Actual** | The write is rejected with `22P02 malformed array literal`. The flag is never set and the profile change is lost. |
| **Root cause** | `derive_parq_risk` (migration 115) declares `v_flags text[] := '{}'` and appends three flags as untyped literals: `v_flags := v_flags || 'pregnancy'`. Postgres resolves `anyarray \|\| anyarray` for an unknown-typed literal and then fails to read it as an array literal. The numbered PAR-Q flags append `v_labels[i]`, a typed array element, and work — which is why the fault hides. `apply_parq_risk()` is a `BEFORE INSERT OR UPDATE` trigger on `user_profiles`, so the throw aborts the write. |
| **Evidence (live, QA)** | `rpc derive_parq_risk` with `Pregnancy` → `400 22P02 malformed array literal: "pregnancy"`; with `Postpartum` → same; with `has_injuries: true, injury_locations: 'left knee'` → `"active_injuries"`. `PATCH /user_profiles {has_injuries:true, injury_locations:'left knee'}` as the member → `400 22P02`, row unchanged. A heart-condition PAR-Q answer (numbered flag) correctly returns `{risk_score:1, risk_level:'high', risk_flags:'heart_condition'}`. |
| **Evidence (source)** | `supabase/migrations/115_profile_privilege_boundary.sql:141-144` |
| **User impact** | Onboarding intake writes exactly these columns (`intake_data.dart:202-204`). A member with an injury, or who is pregnant or postpartum, cannot complete or update their health profile. |
| **Safety** | Maximal. The most important safety input a training AI can have cannot be entered at all, and the three flags that never get set are precisely pregnancy, postpartum and active injury. |
| **Provenance** | `risk_flags` is permanently incomplete, so any future consumer inherits a silently partial record. |
| **Dependency** | none |
| **Decision needed** | no — pure implementation defect |
| **Remediation** | Cast all three literals: `v_flags := v_flags \|\| 'pregnancy'::text;` (and `postpartum`, `active_injuries`). Then backfill: `UPDATE user_profiles SET risk_score = risk_score` re-fires the trigger and re-derives flags for existing rows. |
| **Parallelizable** | yes |

---

### F-J-01 — `materialize_program_week` lost the authorization guard migration 116 gave it

| | |
|---|---|
| **Severity** | **P0** |
| **AI feature** | Program Intelligence (engine output → `program_workouts`) |
| **Expected** | `403 not authorized for this program` for a caller who is neither the program's coach, an assigned client, that client's active coach, nor an admin — the behaviour of all four sibling functions. |
| **Actual** | The caller reaches the engine body. Live it aborted on `program has no plan`; with a plan present it would `DELETE FROM program_workouts WHERE program_id = … AND week_number = …` and re-materialize. |
| **Root cause** | Migration 116 §4 renamed five engine bodies to `<name>_engine` and kept the public name as a thin `can_act_on_program` wrapper, with a comment predicting that a later `CREATE OR REPLACE` by the public name would replace the wrapper and drop the guard. Migration 119 §7 rewrote `public.materialize_program_week` from the 093 base to fix the prescription contract, and did exactly that. Migration 122 diagnosed the same 119/120/121 escape for `search_path` and `EXECUTE` and repaired those two properties, not this one. |
| **Evidence (live, QA)** | as `p1-attacker` (a client with no relationships) against coach `f626acd9`'s program: `evaluate_week` → `403 not authorized for this program`; `regenerate_program` → `403`; `predict_client` → `403`; `generate_workout` (other subject) → `403`; **`materialize_program_week` → `400 P0001 "program has no plan"`**. |
| **Evidence (source)** | `119_workout_prescription_contract.sql:403-483` — no `can_act_on_program`, no `SET search_path`; `116_rpc_execution_security.sql:355-372` — the wrapper it replaced. |
| **User impact** | Any authenticated account can destroy and rewrite any coach's materialized program week. The coach's product is their programming. |
| **Safety** | The rewritten week is what the client trains from. |
| **Provenance** | Each rewritten session also writes a `decision_traces` row; `generate_workout`'s own `can_act_for` still holds, so the traces are attributed to the caller — the program is corrupted while the audit trail points elsewhere. |
| **Dependency** | none |
| **Decision needed** | no |
| **Remediation** | Add as the first statement of 119's body: `IF NOT public.can_act_on_program(p_program_id) THEN RAISE EXCEPTION 'not authorized for this program' USING ERRCODE = '42501'; END IF;` — matching the four siblings. Add `SET search_path = public, pg_temp` in the same statement so a future `CREATE OR REPLACE` does not re-drop what 122 re-pinned by `ALTER`. Then extend `supabase/tests/security/d04-rpc-execution.mjs` to assert the guard on all five, so the *class* is pinned rather than this instance. |
| **Parallelizable** | yes — independent of everything else in this report |

---

### F-J-07 — `build_workout` throws whenever recovery is below the deload threshold

| | |
|---|---|
| **Severity** | **P0** |
| **AI feature** | Movement Intelligence Engine — `build_workout`, and everything built on it |
| **Expected** | `recovery < 60` triggers `RECOVERY_REDUCTION`, `volume_factor` drops to 0.8 and the target size shrinks. |
| **Actual** | `400 22P02 malformed array literal: "RECOVERY_REDUCTION"`. |
| **Root cause** | Identical to F-J-17: `rules text[] := '{}'` then `rules := rules \|\| 'RECOVERY_REDUCTION'` with an untyped literal. The rejection rules in the same loop append the declared `rule text` variable and work correctly. |
| **Evidence (live, QA)** | `build_workout({recovery: 59})` → `400 22P02`; `build_workout({recovery: 60})` → `200`. `generate_workout({recovery: 50})` → `400`. |
| **Evidence (source)** | `089_mie_decision_intelligence.sql:56` |
| **User impact** | Every downstream caller fails for an under-recovered member: `generate_workout`, `materialize_program_week` (whole week aborts), the MIE debugger's recovery slider below 60. |
| **Safety** | The one rule that exists to reduce load on an under-recovered member is the one rule that cannot execute. The failure is closed rather than silently permissive, which is the only mercy here. |
| **Provenance** | No trace is written, so the engine has no record of ever having been asked. |
| **Dependency** | none |
| **Decision needed** | no |
| **Remediation** | `rules := rules \|\| 'RECOVERY_REDUCTION'::text;`. Grep the migration set for the same shape before closing — F-J-17 is the second instance and there may be more. |
| **Parallelizable** | yes |

---

### F-J-02 — The AI's profile read fails entirely, and the failure looks like a default member

| | |
|---|---|
| **Severity** | **P0** |
| **AI feature** | `ai-generate-workout`, `ai-coaching-engine` |
| **Expected** | The model receives the member's goal, equipment, experience, training location and injury state. |
| **Actual** | Both selects `42703`. `profile` is `null`. The generator falls through to `goal: 'general'`, `equipment: 'Bodyweight'`, `experience: 'intermediate'`, `location: 'gym'`; the coaching engine's `context.profile` is `{}` — no name, no weight, no gender, no age. |
| **Root cause** | Both name `user_profiles.goal`, which does not exist (the column is `fitness_goal`); the generator also names `equipment`, which does not exist. PostgREST rejects the *whole* select on one unknown column, and supabase-js returns `{data: null}` rather than throwing, so `?? 'general'` / `?? {}` converts a schema error into a plausible member. |
| **Evidence (live, QA)** | Column-by-column: `fitness_goal` OK, **`goal` MISSING**, **`equipment` MISSING**, `experience_level` OK, `training_location` OK, `has_injuries` OK, `injury_locations` OK, `first_name`/`gender`/`date_of_birth`/`height_cm`/`weight_kg`/`membership_tier` OK. |
| **Evidence (source)** | `ai-generate-workout/index.ts:63`, `ai-coaching-engine/index.ts:126` |
| **User impact** | Every AI workout and every AI insight is generated for a generic person. A member who set up a barbell home gym for strength is programmed bodyweight general fitness. |
| **Safety** | The read that fails also carries `has_injuries` and `injury_locations`. Even repaired, they never enter the prompt (see below). |
| **Provenance** | Nothing records that the profile read failed; the output is indistinguishable from a genuinely sparse member. |
| **Dependency** | none |
| **Decision needed** | no |
| **Remediation** | Drop `goal` and `equipment` from both selects; use `fitness_goal` and resolve equipment from its real source. Then **put the injury fields into the prompt context** — `ai-generate-workout` reads them and never sends them. Longer term, the class matters more than the instance: an edge function should assert on `error` from every `.select()` and fail closed, not read `data` and default. |
| **Parallelizable** | yes |

---

### F-J-15 — No AI edge function is deployed

| | |
|---|---|
| **Severity** | **P0 (environment)** |
| **AI feature** | all nine |
| **Expected** | An authenticated `POST` reaches the function. |
| **Actual** | `404 {"code":"NOT_FOUND","message":"Requested function was not found"}` for all seven probed. |
| **Root cause** | The functions were never deployed to the QA project. |
| **Evidence (live, QA)** | `ai-coach`, `ai-coaching-engine`, `ai-generate-workout`, `analyze-food-image`, `explain-decision`, `generate-communication`, `enrich-exercise-intelligence` — all `404 NOT_FOUND`. |
| **User impact** | Every AI surface in the product is dead on QA. |
| **Safety** | Neutral today; it is what keeps every other finding here latent. |
| **Provenance** | No AI provenance can exist because nothing runs. |
| **Dependency** | **This blocks behavioural verification of F-J-02, F-J-03, F-J-04, F-J-16, F-J-18, F-J-20, F-J-21, F-J-24, F-J-26, F-J-28.** They are proven at source and by schema probe; they cannot be proven end-to-end until deployment. |
| **Decision needed** | no |
| **Remediation** | `supabase functions deploy <name> --project-ref eyqtldjqpgpljlqvpowh` and `supabase secrets set ANTHROPIC_API_KEY=…`. **Deploy after the input and safety fixes, not before** — see §11. |
| **Parallelizable** | no — it is the gate for the verification pass |

---

### F-J-05 — The PAR-Q classification and the structured allergies are read by nothing

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | every decision surface, deterministic and AI |
| **Expected** | A member classified `risk_level = 'high'`, or flagged `doctor_advised_no_exercise` / `pregnancy` / `postpartum`, constrains what may be prescribed. A declared food allergy constrains what may be recommended. |
| **Actual** | No AI prompt reads `risk_level`, `risk_flags` or `food_allergies`. `score_exercise` has no PAR-Q dimension: its documented context keys are goal, equipment, recovery, experience, injuries, recent_patterns. |
| **Root cause** | The classifier was built by Phase 1 as a *privilege boundary* (the member must not be able to overwrite their own risk classification) and correctly achieves that. No consumer was ever added. |
| **Evidence (live, QA)** | `score_exercise(ex, {goal:'strength'})` and `score_exercise(ex, {goal:'strength', risk_level:'high', risk_flags:'heart_condition,doctor_advised_no_exercise,pregnancy'})` return byte-identical breakdowns. |
| **Evidence (source)** | no occurrence of `risk_flags` in any of `supabase/functions/*/index.ts`; `food_allergies` absent from every AI surface. The single `risk_level` occurrence is in `ai-coach`'s `risk_detection` prompt — as a key the *model* is asked to invent, which is the inverse of reading the server's classification. |
| **User impact** | A member who answered yes to "has your doctor said you should only do physical activity recommended by a doctor?" is programmed identically to one who did not. A member with a declared nut allergy can be recommended a meal containing nuts. |
| **Safety** | This is the central safety-governance gap in the system. |
| **Provenance** | No decision records the risk state it was made under, so it cannot be shown after the fact that a constraint was respected. |
| **Dependency** | F-J-17 (the flags cannot even be set until it is fixed) |
| **Decision needed** | **yes — D-4 and D-6.** What each risk level and flag *means* for programming, and whether an allergy is advisory or a hard block, are clinical/product policy. This audit identifies where the policy must attach; it does not invent one. |
| **Remediation** | Once policy exists: add `risk_level` / `risk_flags` / `food_allergies` to the assembled context of every AI surface; add a PAR-Q dimension to `score_exercise` and a corresponding hard rule to `build_workout` (a hard *rejection*, not a score penalty — a score penalty can be outvoted by a high goal-fit). |
| **Parallelizable** | the plumbing yes; the policy is a blocking prerequisite |

---

### F-J-06 — The intelligence substrate is empty, so the engine has nothing to decide from

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | Movement Intelligence Engine |
| **Expected** | `exercise_intelligence` is populated and reviewed; the movement graph has nodes and edges. |
| **Actual** | `profiled: 0` of `total_exercises: 621`, `engine_ready: 0`, `avg_confidence: null`. `movement_graph_stats` → `{nodes: 0, edges: 0}`. |
| **Root cause** | The bootstrap (`rebuild_exercise_intelligence`) and the graph build (`rebuild_movement_graph`) have never been run on QA. Both are content-editor gated and manual. |
| **Evidence (live, QA)** | `intelligence_stats` as admin; `movement_graph_stats` as admin; `rank_exercises({goal:'strength'})` → `[]`. |
| **User impact** | Every engine plan is empty. |
| **Safety** | An empty candidate set cannot violate a constraint, but it also cannot satisfy one — and the empty result is reported as success (F-J-08). |
| **Provenance** | The nine recorded traces are all empty decisions. |
| **Dependency** | blocks live verification of F-J-09 and F-J-22 |
| **Decision needed** | no for QA; **yes for production** — the enrichment pipeline's review gate is D-1 |
| **Remediation** | As a content editor: `rebuild_exercise_intelligence()` → `rebuild_movement_graph()` → `seed_warmup_library()` → `enrich-exercise-intelligence` in batches. Note the ordering trap in F-J-30. This is a deliberate change to shared QA engine state and was **not** performed by this workstream (§14). |
| **Parallelizable** | yes |

---

### F-J-23 — The only automated substrate builder writes no injury data at all

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | `score_exercise` → `INJURY_PREVENTION` |
| **Expected** | Populating `exercise_intelligence` makes the injury rule operable. |
| **Actual** | `rebuild_exercise_intelligence()`'s `INSERT` column list covers goal fit, fatigue and technical complexity. It writes neither `contraindications` nor `joint_stress` — the only two columns `score_exercise`'s injury branch reads. Both keep their `'{}'` defaults, `penalty` stays 0, `injury_compatibility` is 100 for every exercise, and `ic < 40` can never be true. |
| **Root cause** | The bootstrap derives from `goal_tags` and `exercise_type`, which carry no biomechanical information. Injury data can only come from `enrich-exercise-intelligence` (a model) or a human reviewer. |
| **Evidence (source)** | `087_mie_programming_intelligence.sql:54-88` (writer) vs `:139-150` (reader) |
| **User impact** | Running the documented bootstrap produces an engine that looks operational — plans come back full — and has no injury protection whatsoever. |
| **Safety** | High, and worse than the empty state: an empty engine visibly does nothing, whereas a bootstrapped one confidently returns a plan with the injury gate silently disabled. |
| **Provenance** | The trace would show `INJURY_PREVENTION` in `rules_applied` (a static list) while never appearing in `rules_triggered`. |
| **Dependency** | F-J-06 |
| **Decision needed** | **partly — D-1.** Whether model-authored contraindications may be engine-eligible before human review. |
| **Remediation** | Do not treat `rebuild_exercise_intelligence()` as making the engine ready. Gate engine-eligibility on the presence of injury data — e.g. `build_workout` should refuse to plan from a profile whose `contraindications` and `joint_stress` are both empty, rather than scoring it as risk-free. Add `engine_ready` (already reported by `intelligence_stats`) as a hard precondition. |
| **Parallelizable** | after D-1 |

---

### F-J-08 — An unplannable request returns HTTP 200 with an empty plan

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | `build_workout` / `generate_workout` |
| **Expected** | The caller can tell "no exercise suits this member" from "the engine has no library". |
| **Actual** | `{selected: [], warmup: [], trace: [], rules_triggered: [], volume_factor: 1.0, target_size: 5, rules_applied: [4 static strings]}` at HTTP 200. There is no `status` field and no error. |
| **Root cause** | `build_workout` returns whatever the loop produced with no post-condition. |
| **Evidence (live, QA)** | as above; `decision_analytics` → `total_generations: 9, most_triggered_rule: null, most_rejected_exercise: null, avg_recovery: null`. |
| **User impact** | Bounded downstream: migration 119 made `materialize_program_week` **raise** on an empty selection rather than write four empty days, and `coach_program_service.materializeWeek` deliberately propagates that. That fix is real and holds. `build_workout` and `generate_workout` themselves still answer 200, and the MIE debugger renders an empty plan as a plan. |
| **Safety** | Low directly; high as a masking effect — it is why the substrate being empty was not obvious. |
| **Provenance** | Nine traces record decisions that decided nothing, indistinguishable from a genuine "nothing suitable". |
| **Dependency** | none |
| **Decision needed** | **yes — D-2.** Refuse, degrade, or return a typed "cannot plan" result? |
| **Remediation** | Add a discriminated outcome (`status: 'ok' \| 'no_candidates' \| 'substrate_empty'`) with the reason, and stop persisting a trace for a decision with no candidates — or persist it explicitly marked as such. |
| **Parallelizable** | after D-2 |

---

### F-J-03 — `meal_suggestion` reads macro columns that do not exist, so intake always sums to zero

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | `ai-coaching-engine` type `meal_suggestion` |
| **Expected** | `remaining = plan target − today's logged intake`. |
| **Actual** | The intake read `42703`s, `todays` is `null`, every `sum()` is 0, and `remaining_*` equals the full daily target regardless of what the member has eaten. |
| **Root cause** | `.select('calories, protein_g, carbs_g, fat_g')` on `nutrition_logs`, whose columns are `calories, protein, carbs, fat`. (`client_nutrition_plans` genuinely uses the `_g` suffix — the two tables disagree and the code follows the wrong one.) |
| **Evidence (live, QA)** | `nutrition_logs`: `calories` OK, `protein` OK, `carbs` OK, `fat` OK; `protein_g` MISSING, `carbs_g` MISSING, `fat_g` MISSING. `client_nutrition_plans.protein_g` OK. |
| **Evidence (source)** | `ai-coaching-engine/index.ts:150` |
| **User impact** | A member who has eaten their entire day's calories is told they have their entire day's calories remaining, and is offered three more meals to fit them. |
| **Safety** | Moderate — systematic over-recommendation against a coach-assigned plan. |
| **Provenance** | The wrong `remaining` is persisted into `ai_insights.data.remaining`, so the error is durable. |
| **Dependency** | none |
| **Decision needed** | no |
| **Remediation** | Select `calories, protein, carbs, fat` and map. Consider renaming one side so the two tables agree. |
| **Parallelizable** | yes |

---

### F-J-04 — `recent()` silently returns `[]` for five of the nine inputs it gathers

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | `ai-coaching-engine` (all seven types) |
| **Expected** | The last 14 workouts, 14 habit logs, lifetime score, 60 set logs and 5 goals reach the model. |
| **Actual** | All five are always `[]`. |
| **Root cause** | `recent()` orders every table by `created_at`; `workout_sessions`, `habit_logs`, `user_scores` and `workout_set_logs` do not have that column. `goals` is filtered on `user_id`, which it does not have. Each failure is caught and returns `[]`. |
| **Evidence (live, QA)** | `?order=created_at.desc` → `42703` on `workout_sessions`, `habit_logs`, `user_scores` (hint: `updated_at`), `workout_set_logs`. `goals?select=user_id` → `42703`. Meanwhile the member genuinely has 30 `daily_scores`, 61 `habit_logs`, 21 `nutrition_logs` and 3 `weekly_checkins`. |
| **Evidence (source)** | `ai-coaching-engine/index.ts:27-33` and `:131-141` |
| **User impact** | Adherence coaching is delivered to a model that believes the member has never trained. `progress_insight` — whose entire premise is "from the client's recent workout set logs" — is asked to find a data-grounded insight in an empty array. |
| **Safety** | Moderate: recovery- and load-related advice is given without any training history. |
| **Provenance** | **Compounding.** The confidence score is computed from these same arrays: `workouts.length >= 8` (+28), `goals.length > 0` (+10), and it is persisted into `ai_insights.data.confidence` with human-readable `confidence_reasons`. An active member is scored as low-confidence with the reason "limited data", and that false attestation is the artifact a coach reads. |
| **Dependency** | none |
| **Decision needed** | **partly — D-9.** Whether a confidence score computed from known-empty inputs may be shown or persisted at all. |
| **Remediation** | Fix the sort keys (`started_at` / `logged_at` / `updated_at` / the real ones) and the `goals` filter column. Then make `recent()` distinguish "no rows" from "the read failed" and refuse to produce a confidence score over failed reads. |
| **Parallelizable** | yes |

---

### F-J-20 — A model refusal is not detected and is persisted as coaching

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | all Anthropic call sites |
| **Expected** | A declined request is a reportable outcome, not an artifact. |
| **Actual** | The Messages API answers HTTP 200 with `stop_reason: 'refusal'` and no usable content. Every function reads `content?.[0]?.text ?? '{}'`; the parse succeeds; `out` is `{}`; `ai-coaching-engine` writes an `ai_insights` row titled "Today's Coaching" with an empty body — **and stamps a confidence score on it**. |
| **Root cause** | No call site inspects `stop_reason`. |
| **Evidence (source)** | no occurrence of `stop_reason` in any of `supabase/functions/*/index.ts`; `ai-coaching-engine/index.ts:216` (`title: out.title ?? 'Today's Coaching', body: out.body ?? ''`). The NestJS service is the counter-example — it checks for empty text and logs `stop_reason` before raising a 503. |
| **User impact** | A blank coaching card, or a blank notification, presented as today's brief. |
| **Safety** | A refusal is most likely on exactly the inputs that warrant one; converting it into a silent empty artifact discards the signal. |
| **Provenance** | A fabricated artifact with a confidence score and no record that the model declined. |
| **Dependency** | F-J-15 to observe live |
| **Decision needed** | no |
| **Remediation** | Check `stop_reason` before reading `content`; treat `refusal` and `max_tokens` as distinct reportable outcomes; never persist on either. Fold in F-J-21 (timeout) at the same time — both are one shared `callClaude()` helper. |
| **Parallelizable** | yes |

---

### F-J-12 — Any coach reads every member's decision traces

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | Decision Intelligence (provenance) |
| **Expected** | Subject-scoped, like every sibling engine-output table. |
| **Actual** | The SELECT policy's role arm is `role in ('admin','content_manager','coach')` with no relationship or program check. |
| **Root cause** | Migration 089's policy. Migration 117 audited the engine-output tables for *write* exposure, concluded correctly that "no write policy means deny", and recorded `decision_traces` as already correct — the read scope was not the question it asked. |
| **Evidence (live, QA)** | `p1-coach` has **0** rows in `coach_client_relationships` and reads all 9 `decision_traces` across 2 unrelated subjects. `p1-attacker` (a client) reads 0, so the non-role arms are correct. Contrast: `predictions` (095), `communications` (096), `program_versions` (093) and `weekly_feedback` (117) all check the owning program or `is_active_coach_of`. |
| **User impact** | A trace carries the member's decision context and the per-candidate rejection reasons — including injury-based rejections once the substrate is populated. Any account with the coach role reads all of it for everyone. |
| **Safety** | Health-adjacent disclosure. |
| **Provenance** | Provenance data is meant to be the auditable record; an over-broad read scope makes it a disclosure surface. |
| **Dependency** | none |
| **Decision needed** | **yes — D-7.** Should an admin or content manager see another member's trace at all, and should a coach see only their active clients'? |
| **Remediation** | Replace the role arm with `public.is_active_coach_of(subject_id) OR public.is_admin()`, matching 117's `weekly_feedback` shape. Add the assertion to `supabase/tests/security/d05-intelligence-substrate.mjs`. |
| **Parallelizable** | after D-7 |

---

### F-J-13 — A decision trace is not an input snapshot and cannot be replayed

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | Decision Intelligence |
| **Expected** | The trace records what the engine knew about the member when it decided. |
| **Actual** | `context` is verbatim whatever the caller passed. Live, 8 of 9 traces record `{"size": 3}` — no goal, no recovery, no equipment, no injuries. |
| **Root cause** | `generate_workout` persists `p_context` unchanged and never reads the subject's own state. |
| **Evidence (live, QA)** | the 9 rows; `decision_analytics.avg_recovery: null` (no trace's context even contains `recovery`). |
| **User impact** | A coach reviewing why a session was built cannot see what it was built from. |
| **Safety** | It cannot be demonstrated after the fact that a safety constraint was applied — the record does not say the member had an injury, only that no candidate was rejected for one. |
| **Provenance** | This is the core provenance defect. Everything else in `decision_traces` (versions, subject, rules, per-candidate reasons) is well designed. |
| **Dependency** | F-J-05 (the snapshot should include the risk state, which requires the policy) |
| **Decision needed** | partly — what belongs in the snapshot is bounded by D-4 |
| **Remediation** | Have `generate_workout` resolve the subject's profile, injuries and risk classification server-side and record them in `context` alongside the caller's request, rather than trusting the caller to supply them. That also closes the "caller-supplied constraint" weakness in §5. |
| **Parallelizable** | after D-4 |

---

### F-J-10 — The AI generator names the deterministic engine as the load authority and never calls it, and records nothing

| | |
|---|---|
| **Severity** | **P1** |
| **AI feature** | `ai-generate-workout` |
| **Expected** | Either the engine prescribes load, or the contract does not claim it does. |
| **Actual** | The system prompt says *"Do NOT prescribe a load. Weight is the deterministic engine's decision, not yours."* No engine RPC is invoked. `weight_kg` is `null` for every exercise, permanently — not "the engine decided no load", but "nothing decided". No `decision_traces` row, no `ai_insights` row, no model identifier, no input snapshot: the function writes nothing at all. |
| **Root cause** | The AI generator was built as a standalone path parallel to the engine, not on top of it. |
| **Evidence (source)** | `ai-generate-workout/index.ts` — no occurrence of `generate_workout`, `build_workout`, `score_exercise`, `rank_exercises`, `decision_traces`, or any `.insert(`. |
| **User impact** | Generated sessions carry no load guidance. `programWorkoutToWorkout` renders `weight_kg: null` as an absence, which migration 119 established as correct — so the behaviour is honest, just empty. |
| **Safety** | Moderate: the member is the one deciding load, with no guardrail and no record. |
| **Provenance** | An AI-authored workout a member can start is completely unauditable. Nothing downstream can even tell it was AI-authored. |
| **Dependency** | F-J-06 (the engine must be able to plan before it can be consulted) |
| **Decision needed** | **yes — D-3 and D-8.** Does the engine prescribe load, and by what rule? Is an AI-generated workout a prescription that must write a trace? |
| **Remediation** | Per D-8, write a `decision_traces` row (or a peer `ai_generations` table) with the assembled context, the model id, the library slice, and the rejected exercises the contract check already collects. Per D-3, either invoke the engine for load or stop naming it. |
| **Parallelizable** | after D-3/D-8 |

---

### F-J-09 — The rejection gates are null-permissive

| | |
|---|---|
| **Severity** | **P2** (latent — reachable if the join or the scorer changes) |
| **AI feature** | `build_workout` |
| **Expected** | A candidate whose suitability cannot be computed is rejected, not accepted. |
| **Actual** | `em := (rec.bd->>'equipment_match')::int` is `NULL` whenever `score_exercise` took an early return. `IF NULL = 0` and `IF NULL < 40` are both false, so control falls through to `decision := 'accepted'` with reason `'top-ranked available candidate'`. Absence of evidence reads as absence of risk. |
| **Root cause** | `score_exercise` has two early returns — exercise-not-found and no-profile — and neither emits `equipment_match` or `injury_compatibility`. |
| **Evidence (live, QA)** | `score_exercise('00000000-…', {injuries:['knee']})` → `{"error":"exercise not found"}` — no gate keys. `score_exercise(<real id>, …)` on the empty substrate → `{"final_score":0,"no_profile":true,"name":"Seated Cable Row"}` — likewise. |
| **Why latent** | `build_workout` inner-joins `exercises` (a view over `custom_exercises`, 621 rows, same ids — verified) with `exercise_intelligence`, so today neither early return is reachable from inside the loop. It becomes live the moment the join is loosened to a `LEFT JOIN`, the view diverges from `custom_exercises`, or the candidate source changes. |
| **Safety** | If reached, the equipment and injury rejections are silently skipped for that candidate. |
| **Dependency** | none |
| **Decision needed** | no |
| **Remediation** | `IF em IS NULL OR em = 0 THEN … ELSIF ic IS NULL OR ic < 40 THEN …`, with a distinct rule label (`SCORE_UNAVAILABLE`) so the trace says why. |
| **Parallelizable** | yes |

---

### F-J-22 — The engine plans from unreviewed, model-authored intelligence

| | |
|---|---|
| **Severity** | **P2** (governance; becomes P1 the moment the substrate is populated) |
| **AI feature** | `enrich-exercise-intelligence` → `build_workout` |
| **Expected** | Migration 090 defines a review lifecycle: `draft → ai_generated → under_review → approved`. The engine plans from certified data. |
| **Actual** | `enrich-exercise-intelligence` writes `contraindications`, `joint_stress` and every fatigue score at `status: 'ai_generated'`. `build_workout` joins `exercise_intelligence` with no `status` predicate, and so does `rank_exercises`. Unreviewed model output is treated as certified. |
| **Root cause** | The review lifecycle was built; the consumer was never gated on it. |
| **Evidence (source)** | `enrich-exercise-intelligence/index.ts:135`; `089:60-62`; `087:172-184` |
| **Safety** | This is the AI→deterministic boundary breach. The engine's authority over the AI is the architecture's central safety claim, and the AI writes the engine's inputs. `contraindications` in particular is the column the injury rule reads. |
| **Provenance** | To its credit the writer stamps `evidence_source`, `ai_version`, `confidence` and per-attribute confidence — the data to gate on already exists. |
| **Dependency** | F-J-06 |
| **Decision needed** | **yes — D-1.** Which statuses are engine-eligible, and is there a confidence floor? |
| **Remediation** | Add the predicate to `build_workout` and `rank_exercises` once D-1 answers it. Report `engine_ready` (already in `intelligence_stats`) as the readiness metric rather than `profiled`. |
| **Parallelizable** | after D-1 |

---

### F-J-14 / F-J-25 — Model identity is not recorded, and is not centrally pinned

| | |
|---|---|
| **Severity** | **P2** |
| **AI feature** | all |
| **Expected** | An artifact can be attributed to the model that produced it. |
| **Actual** | Three model strings across ten call sites, each a per-file literal. Only `explain-decision` (`explain_model`) and `enrich-exercise-intelligence` (`evidence_source` + `ai_version`) record what produced their output. `ai_insights`, `ai_reviews`, `ai_goal_predictions`, `ai_memories`, `ai_conversations` and AI-estimated `nutrition_logs` record nothing. |
| **Evidence (source)** | `claude-sonnet-4-6` ×8, `claude-haiku-4-5-20251001` ×2, plus `DEFAULT_ANTHROPIC_MODEL` in `apps/api/src/config/api-config.ts` (which does it right: one constant, `ANTHROPIC_MODEL`-overridable). |
| **Impact** | A model change is not auditable after the fact — no stored artifact can be attributed, and no cohort can be re-evaluated. |
| **Note** | `claude-haiku-4-5-20251001` is the date-suffixed form of `claude-haiku-4-5`. Both resolve; the inconsistency between the two Haiku sites and the eight Sonnet sites is the kind of drift a central constant prevents. |
| **Decision needed** | no |
| **Remediation** | One shared constant module for the edge functions (the NestJS side already has one), and a `model` / `ai_version` column on every AI-authored artifact. `explain-decision` shows the whole cost is one column. |
| **Parallelizable** | yes |

---

### F-J-21 — No Anthropic call is bounded by a timeout

| | |
|---|---|
| **Severity** | **P2** |
| **Actual** | Deno's `fetch` has no default timeout and no call passes an `AbortSignal`. A hung upstream holds the invocation until the platform's own wall clock kills it; the caller sees a generic failure with no signal that it was a timeout. The NestJS route inherits the SDK's 10-minute default and its two retries — a bound, if a generous one. |
| **Evidence (source)** | no `AbortSignal` / `AbortController` in any of `supabase/functions/*/index.ts`. |
| **Remediation** | `signal: AbortSignal.timeout(n)` on every call, with a distinct timeout-shaped response. Same shared `callClaude()` helper as F-J-20. |
| **Parallelizable** | yes |

---

### F-J-16 — The coaching-engine client cannot report a failure

| | |
|---|---|
| **Severity** | **P2** |
| **Actual** | `AICoachService.generate()` returns `null` for a 500, a 404, a network error and "the model had nothing to say" alike. The home briefing renders all four as "no insight yet" — which is also what a brand-new member sees. |
| **Contrast** | `generateAiWorkout` throws on a non-200 and the Train hub shows a real error. Its own comment states the principle: *"'the generator could not be reached' and 'the generator declined' are different answers and the client is owed the difference."* That is the contract the rest of the AI surface should adopt. |
| **Impact** | Today this is why F-J-15 is invisible in the app: every AI card degrades to a plausible empty state. |
| **Remediation** | Adopt the `generateAiWorkout` contract across `AICoachService`. |
| **Parallelizable** | yes |

---

### F-J-26 — The AI Nutrition Coach is given no subject context at all

| | |
|---|---|
| **Severity** | **P2** (P1 once D-6 answers the allergy question) |
| **Actual** | `POST /ai/nutrition/message` carries `message`, `history` and an optional `image`. The service never resolves the caller: no profile, no `client_nutrition_plans` target, no goal, no `food_allergies`. It then produces meal plans and grocery lists. The `history` array is client-supplied and replayed verbatim as prior turns. |
| **What is right** | The security half is correct and should not be disturbed: the key is server-held, never returned, never logged; the controller is guarded; upstream failures are mapped to a generic 503. |
| **Impact** | Generic nutrition advice presented as personalised coaching, and no allergen awareness. Nothing is persisted, so there is also no record of what was advised. |
| **Decision needed** | **yes — D-6.** |
| **Remediation** | Resolve the subject from the verified JWT (the guard already has it), load plan + goal + allergies, and persist the exchange with a model id. |
| **Parallelizable** | after D-6 |

---

### F-J-18 / F-J-19 — Two subject-identity defects in coach-facing AI, both currently unreachable

| | |
|---|---|
| **Severity** | **P2 (latent)** |
| **F-J-18** | `AICoachService.analyzeCheckins(clientId)` and `.detectRisks(clientId)` post `target_client_id`. `ai-coach` destructures only `{ message, mode }` and scopes every query to `user.id`. A coach asking for a client's check-in analysis or risk assessment would be served an analysis of **themselves**, labelled as the client's. |
| **F-J-19** | `detectRisks` parses the model's JSON verdict with `Uri.splitQueryString(jsonStr)`, which splits on `&` and `=`. A well-formed verdict never yields `risk_level` / `flags` / `recommendation`. |
| **Why latent** | Neither method has a call site anywhere in `lib/` — verified by a full-tree scan, which is now pinned as a test. Wiring either into a coach screen makes both live at once. |
| **Safety (if wired)** | High: a risk assessment attributed to the wrong person. |
| **Remediation** | Resolve the subject in `ai-coach` through `can_act_for` / `is_active_coach_of`, or delete both methods. Use `jsonDecode`, keeping the catch that degrades to `'unknown'`. |
| **Parallelizable** | yes |

---

### F-J-24 / F-J-28 — Two fail-open comparisons in edge-function auth

| | |
|---|---|
| **Severity** | **P2** |
| **F-J-24** | `ai-coaching-engine` computes `isService = authHeader === \`Bearer ${SUPABASE_SERVICE_KEY}\`` where the key defaults to `''`. If the secret were ever absent, `Authorization: Bearer ` matches and the caller names any subject they like in the body. The platform injects that secret today, so this is defence in depth, not a live hole — but an unset variable should not be one string comparison away from arbitrary subject targeting. Fix: `SUPABASE_SERVICE_KEY.length > 0 && …`. |
| **F-J-28** | `ai-coach` is the only AI function with no `ANTHROPIC_API_KEY` guard. It calls Anthropic with an empty key, gets a 401, and returns HTTP 500 with the upstream response body in `detail` — an internal failure shape handed to the client. It also logs key presence on every request. Fix: the same `if (!ANTHROPIC_API_KEY) return json({error:'AI not configured'}, 500)` the other eight use; drop `detail`. |
| **Parallelizable** | yes |

---

### F-J-27 / F-J-29 / F-J-30 / F-J-31 — Four smaller defects

| ID | Finding | Severity | Remediation |
|---|---|---|---|
| **F-J-27** | An AI photo-derived calorie estimate is written to `nutrition_logs` through the same `logMeal()` path as a manual entry. The model's own `confidence` is discarded at the client and no column marks the row as an estimate. `ai-coaching-engine` then reads it as ground truth for macro arithmetic and weight-trend coaching. | P2 | Add `source` (`manual` \| `ai_photo` \| `barcode`) and `estimate_confidence`; surface both. Requires **D-5**. |
| **F-J-29** | `ai-generate-workout` builds its candidate library with `.limit(220)` and **no `.order()`** against 621 exercises. Which 220 is unspecified by Postgres, unrecorded, and may differ between calls — a non-deterministic candidate set for a decision that claims to be grounded in the library. | P2 | Add a deterministic order and record the slice (count + ordering key) in whatever provenance F-J-10 introduces. |
| **F-J-30** | `enrich-exercise-intelligence` with no explicit `ids` targets rows in `exercise_intelligence` whose status is `draft` or source is `derived`. On an empty table that matches nothing, so it processes 0 and reports success. Its comment says "(or missing)", which the query cannot express. | P2 | Target `custom_exercises LEFT JOIN exercise_intelligence` so a missing profile is findable, or document that `rebuild_exercise_intelligence()` must run first. |
| **F-J-31** | `risk_assessment` and `progress_insight` insert into `ai_insights` with no `for_date` and no preceding delete, unlike the four types that de-duplicate by date. Repeated generation accumulates unboundedly, and `getLatestInsight` returns whichever is newest with no idempotency. | P2 | De-duplicate by `(user_id, type, for_date)` as the other types do. |

---

## 9. Decisions required

These are **policy**, not defects. This audit identifies exactly where a decision has to
attach and what depends on it; it does not invent clinical or product policy.

| ID | Decision | Owner | Blocks | Why it cannot be inferred |
|---|---|---|---|---|
| **D-1** | Which `exercise_intelligence` statuses are engine-eligible (`approved` only? `ai_generated` above a confidence floor?), and is there a per-attribute floor for `contraindications` specifically? | Product + clinical | F-J-22, F-J-23, F-J-06 (prod) | The review lifecycle exists and the confidence data exists; nothing states the threshold. Choosing one is a safety-risk-vs-coverage tradeoff. |
| **D-2** | What must the engine do when it cannot plan — refuse, degrade to a template, or return a typed "cannot plan"? | Product | F-J-08 | 119 already chose "refuse" for `materialize_program_week`. Whether `build_workout` should agree is a contract choice. |
| **D-3** | Does the deterministic engine prescribe load, and by what rule (e2RM, %1RM, RPE-anchored, last-session progression)? | Product + coaching | F-J-10, WORKOUT_DOMAIN_CONTRACT §8 G-1 | Explicitly left open by migration 119. |
| **D-4** | **Clinical.** What does each PAR-Q risk level and flag mean for programming? Specifically: does `risk_level = 'high'` or `doctor_advised_no_exercise` gate AI programming behind clearance? What movement classes are contraindicated for `pregnancy` / `postpartum`, and by trimester/stage? | **Clinical/medical owner** | F-J-05, F-J-13 | This is medical policy. It must not be inferred from the model, from the code, or from this audit. |
| **D-5** | Is a model's photo-derived calorie estimate allowed to be an input to coaching decisions, and must it be visibly labelled as an estimate to the member and the coach? | Product | F-J-27 | Accuracy expectations and disclosure are product/legal calls. |
| **D-6** | Must a nutrition surface hard-block on a declared allergy, or advise? Who owns the allergen→ingredient mapping, and is a free-text `food_allergies` field sufficient to enforce against? | Product + clinical | F-J-05, F-J-26 | A free-text field cannot be enforced against reliably; whether to enforce, and how, is policy. |
| **D-7** | Who may read another member's `decision_traces` — active coach only, or any coach/content manager/admin? | Product + privacy | F-J-12 | Every sibling table chose "active coach or admin". Whether traces are deliberately broader was not recorded. |
| **D-8** | Is an AI-generated workout a "prescription" for audit purposes — must it write a decision trace with a model id and an input snapshot? | Product + compliance | F-J-10, F-J-14 | Determines whether AI generation is an auditable decision or a suggestion. |
| **D-9** | May a confidence score be displayed and persisted when it is computed from inputs the system knows failed to load? | Product | F-J-04 | Once F-J-04 is fixed the number becomes meaningful; the question is what to do with a score whose inputs are degraded. |

---

## 10. Blockers

| # | Blocker | Blocks | Owner |
|---|---|---|---|
| B-1 | **No AI edge function is deployed to QA** (F-J-15) | End-to-end verification of F-J-02, F-J-03, F-J-04, F-J-16, F-J-18, F-J-20, F-J-21, F-J-24, F-J-26, F-J-28 | DevOps / release |
| B-2 | **`ANTHROPIC_API_KEY` is not set as a QA edge secret** (inferred — the functions do not exist, so it cannot be confirmed) | Any live model behaviour on QA | DevOps / release |
| B-3 | **The intelligence substrate is empty** (F-J-06) | Live verification of F-J-09, F-J-22, and any real engine decision. Deliberately **not** populated by this workstream (§14). | Content owner |
| B-4 | **D-4 (clinical PAR-Q policy) is undefined** | F-J-05 and F-J-13 remediation | Clinical owner |
| B-5 | **D-1 (engine-eligible review status) is undefined** | F-J-22 and F-J-23 remediation, and safe substrate population in production | Product + clinical |
| B-6 | **`QA_SERVICE` was not available to this workstream** | Re-running the Phase 1 suite (`npm run test:security`) as a regression control for F-J-01. The new AI suite deliberately needs only `QA_ANON`. | Whoever holds the QA keys |

---

## 11. Remediation sequencing

The ordering is not arbitrary. **Deploying the edge functions before the input and safety
fixes converts a visibly dead system into an invisibly wrong one** — every failure mode in
§7 that is currently "open" produces confident output with no error anywhere.

**Wave 0 — stop the bleeding (no dependencies, all parallelizable, all one-line-ish)**
1. F-J-17 — cast the three `derive_parq_risk` flag literals to `::text`; backfill existing rows.
2. F-J-07 — cast `'RECOVERY_REDUCTION'::text`; grep the migration set for the same shape.
3. F-J-01 — restore `can_act_on_program` on `materialize_program_week`, with `SET search_path`; extend `d04-rpc-execution.mjs` to assert all five guards as a class.

Wave 0 needs no product input and unblocks the entire safety-input path.

**Wave 1 — make the inputs real (parallel with Wave 0)**
4. F-J-02 — fix both profile selects; add injuries to the generator's prompt context.
5. F-J-03 — fix the nutrition macro column names.
6. F-J-04 — fix the five sort/filter keys in `recent()`; make it distinguish a failed read from an empty one.
7. Class fix: assert on `error` from every `.select()` in an edge function and fail closed. This is what makes 4–6 stay fixed.

**Wave 2 — make failure legible (parallel)**
8. F-J-20 + F-J-21 + F-J-28 + F-J-24 — one shared `callClaude()` helper with a timeout, a `stop_reason` check, a key guard, and no upstream detail in responses.
9. F-J-16 — adopt the `generateAiWorkout` failure contract across `AICoachService`.
10. F-J-31 — de-duplicate `risk` / `progress` insights by date.

**Wave 3 — decisions land** — D-1, D-2, D-4, D-7 in particular. Nothing below can be
correctly built before them.

**Wave 4 — safety wiring (needs D-1, D-4)**
11. F-J-05 — risk classification + allergies into every assembled context; a PAR-Q *rejection rule* (not a score penalty) in `build_workout`.
12. F-J-23 — gate engine-eligibility on the presence of injury data; stop treating `rebuild_exercise_intelligence()` as readiness.
13. F-J-22 — status predicate on `build_workout` and `rank_exercises`.
14. F-J-13 — `generate_workout` resolves and snapshots the subject's state server-side instead of trusting `p_context`.
15. F-J-09 — make the gates reject on NULL with a distinct rule label.
16. F-J-12 — scope the `decision_traces` read policy (needs D-7).

**Wave 5 — substrate (needs D-1, and Wave 4 §12–13 so it is populated behind a gate)**
17. F-J-30 — fix the enrichment targeting.
18. F-J-06 — `rebuild_exercise_intelligence()` → `rebuild_movement_graph()` → `seed_warmup_library()` → batched `enrich-exercise-intelligence` → review.

**Wave 6 — deploy and verify**
19. F-J-15 / B-1 / B-2 — deploy the nine functions with the secret set.
20. Re-run `npm run test:ai`. Every characterization that was pinned red-side-up should now flip; invert each one and promote it to an invariant in the same commit.
21. F-J-08, F-J-10, F-J-14, F-J-25, F-J-26, F-J-27, F-J-29 — provenance and contract work, which is only meaningfully testable once something runs.

**Wave 7 — latent**
22. F-J-18 / F-J-19 — fix before wiring `analyzeCheckins` / `detectRisks` into any screen. The call-site guard in the test suite is the tripwire.

---

## 12. Tests

Two new suites, both green, following the existing static/live pairing that
`phase1_security_boundary_test.dart` and `supabase/tests/security/` established.

### 12.1 Static — `apps/mobile/test/unit/ai_decision_integrity_test.dart` (31 tests)

Runs in `flutter test` with no credentials. Parses the committed SQL, the committed
edge-function TypeScript, the NestJS source and the Flutter client.

Two kinds of test, stated in each test name:

- **`[invariant]`** — a property the system holds and must keep holding.
- **`[characterizes F-J-nn]`** — a defect found by this workstream, pinned exactly as the
  source reads today. It goes red the moment the source changes, which is the point:
  whoever remediates F-J-nn inverts the test in the same commit. Each carries a
  `REMEDIATION:` comment saying what the fix is.

Nothing is skipped and nothing is marked as an expected failure. A red test nobody can act
on protects nothing; a characterization that flips has an owner.

| Group | Covers |
|---|---|
| `AI-J-001` | all five 116 wrappers keep their guard (invariant); 119 dropped one (F-J-01); no later migration restores it — asserted over the whole migration chain, not one file |
| `AI-J-002` | the untyped `text[]` appends in `build_workout` (F-J-07) and `derive_parq_risk` (F-J-17); the PAR-Q trigger stays `BEFORE` and server-owned (invariant) |
| `AI-J-003` | the generator's output contract and load refusal (invariant); it never calls the engine and writes no provenance (F-J-10); unreviewed intelligence is consumed (F-J-22); the bootstrap writes no injury data (F-J-23); null-permissive gates (F-J-09) |
| `AI-J-004` | the safety substrate is declared (invariant); no AI reads the PAR-Q classification or the allergies (F-J-05); the nutrition service loads no subject (F-J-26) while its auth guard stays in place (invariant) |
| `AI-J-005` | `ai-coach` ignores `target_client_id` (F-J-18); the risk verdict is parsed as a query string (F-J-19); **neither method has a call site** (invariant — the tripwire for Wave 7); the service-mode key comparison (F-J-24) |
| `AI-J-006` | every function authenticates (invariant); parse failures are 502s (invariant); no `stop_reason` check (F-J-20); no timeout (F-J-21); `ai-coach` has no key guard and echoes upstream detail (F-J-28); the client swallows failures (F-J-16) |
| `AI-J-007` | `explain-decision` and `generate-communication` stay trace/brief-only, caller-RLS, draft-only, and `explain_model` is recorded (invariants); every other model id is a scattered literal that is never persisted (F-J-25) |

### 12.2 Live — `supabase/tests/ai/` (47 assertions, 5 suites)

`npm run test:ai`, needs only `QA_URL` + `QA_ANON`. Reuses the four `p1-*` fixtures from
`supabase/tests/security`; **no service key required**. Read-only by default.

| Suite | Covers |
|---|---|
| `j01-input-assembly` | every column each AI feature selects, probed against the real schema — F-J-02, F-J-03, F-J-04 |
| `j02-safety-inputs` | the substrate exists and the classifier works for numbered flags (invariants); the three narrative flags throw and a member cannot save an injury (F-J-17); the engine ignores risk entirely (F-J-05); the substrate is empty (F-J-06) |
| `j03-engine-boundary` | the recovery threshold crash isolated to exactly `< 60` (F-J-07); the empty 200 (F-J-08); the missing gate keys (F-J-09) |
| `j04-provenance-authz` | unscoped trace reads with a zero-relationship coach, against a client control (F-J-12); version stamps and subject/creator present (invariants); context is not a snapshot (F-J-13); no model id (F-J-14); every recorded decision is empty (F-J-08); **four sibling guards hold and `materialize_program_week` does not** (F-J-01) |
| `j05-product-path` | deployment of all seven AI functions (F-J-15) |

Safety properties of the live suite: it refuses to run against the production ref; the
program probe uses a week number that is in no plan so the engine aborts before its
`DELETE`; the one profile-write probe restores the prior value if it ever succeeds; and
everything that writes is behind `AI_ALLOW_WRITES=1`.

### 12.3 Results

| Suite | Before | After |
|---|---|---|
| `flutter test` (mobile) | 699 passed, 9 skipped | **730 passed, 9 skipped** (+31, all in the new file) |
| `npm run test:api` | 58 unit + 6 e2e passed | **58 + 6 passed** (unchanged) |
| `npm run test:ai` (new) | — | **47/47 passed**; 20/20 characterized defects reproduce |
| `npm run test:security` | — | **not run** — needs `QA_SERVICE`, which this workstream did not have (B-6) |

No existing test was modified, weakened, skipped or deleted.

---

## 13. Working-tree changes

The tree was shared and dirty throughout. Nothing was reset, stashed, discarded, reverted
or overwritten; no existing file's content was changed except the one line noted below.

**Added:**

| Path | What |
|---|---|
| `apps/mobile/test/unit/ai_decision_integrity_test.dart` | static suite, 31 tests |
| `supabase/tests/ai/lib.mjs` | live harness (auth, REST/RPC/Functions, column probes, reporting) |
| `supabase/tests/ai/j01-input-assembly.mjs` | |
| `supabase/tests/ai/j02-safety-inputs.mjs` | |
| `supabase/tests/ai/j03-engine-boundary.mjs` | |
| `supabase/tests/ai/j04-provenance-authz.mjs` | |
| `supabase/tests/ai/j05-product-path.mjs` | |
| `supabase/tests/ai/run.mjs` | runner |
| `supabase/tests/ai/README.md` | how to run, safety properties, layout |
| `docs/QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md` | this report |

**Modified:**

| Path | Change |
|---|---|
| `package.json` | one line added: `"test:ai": "node supabase/tests/ai/run.mjs"`, placed next to the existing `test:security`. Nothing else touched. |

Shared-tree note: `git diff package.json` shows **three** added script lines, not one. `test:security` was already present in the working tree when this workstream read the file (uncommitted, from the Phase 1 work), and `test:contract` — with `supabase/tests/contract/` — was added by a concurrent workstream after this edit. Both are intact; only `test:ai` is this workstream's. Nothing belonging to another workstream was overwritten, and the file's formatting is unchanged.

**Deliberately not changed.** No migration was added, edited or applied. No edge function,
no application source, no existing test. Every remediation in §8 is written out as SQL or
a described change and left for its owner — F-J-01 and F-J-17 in particular are P0s whose
fixes are two- and three-line casts, but applying them means adding a migration and
running it against shared QA, which is the owner's call and not an audit's.

---

## 14. QA mutations and cleanup

**Mutations performed: none.** Every probe was read-only or was rejected before it wrote.
Verified after the fact:

| Action | Effect | Verified |
|---|---|---|
| Signed in as `test@12circle.app`, `coach@12circle.app`, `p1-victim`, `p1-attacker`, `p1-coach`, `p1-admin` | auth sessions / refresh tokens only; no data rows | — |
| `build_workout`, `score_exercise`, `rank_exercises`, `derive_parq_risk`, `decision_analytics`, `intelligence_stats`, `movement_graph_stats`, `certification_summary`, `intelligence_review_queue`, `coach_client_ai_signals` | `STABLE` / read-only | — |
| `generate_workout` ×2 | both rejected — one `400` on F-J-07, one `403` on the subject guard. No trace written. | `decision_traces` count **9 before, 9 after** |
| `materialize_program_week` ×1 (week 99, another coach's program) | aborted on `program has no plan`, before the `DELETE` | `program_workouts` for that program **4 rows, unchanged** |
| `PATCH user_profiles` ×1 (`p1-victim`, `has_injuries` + `injury_locations`) | **rejected** `400 22P02`; row unchanged | re-read: `has_injuries: false`, `injury_locations: ""`, `risk_level: "low"` |
| `ai_detect_patterns`, `ai_adjust_nutrition` | `403 permission denied` | — |
| Edge-function probes ×7 | `404 NOT_FOUND` — nothing executed | — |

**Cleanup required: none.**

**Left for the owner, deliberately not done:**

- **Populating the intelligence substrate** (F-J-06). Running
  `rebuild_exercise_intelligence()` would write 621 rows into shared QA engine state that
  other workstreams may be observing, and — per F-J-23 — would produce an engine that
  looks ready and has no injury protection. That is a decision with a prerequisite (D-1),
  not a QA convenience.
- **Running `npm run test:ai` with `AI_ALLOW_WRITES=1`.** The J-03E block records one
  `decision_traces` row per run to demonstrate F-J-11 (an empty selection persisted as
  provenance). `decision_traces` has no client `DELETE` policy by design, so those rows
  are not removable without service role. It is off by default for that reason; the nine
  existing rows on QA predate this session.

---

## 15. Production-contact statement

**Production was not contacted at any point during this workstream.**

- Every live call went to `https://eyqtldjqpgpljlqvpowh.supabase.co` — the project
  `supabase/.temp/linked-project.json` identifies as **"12Circle QA"** and
  `apps/mobile/dart_defines/qa.json` configures as `APP_ENV=qa`.
- The production project ref is `nxdbooufqzkpslkcogxc`, per the `PROD_REF` constant in
  `supabase/tests/security/lib.mjs`. No request was issued to that host, to any
  `*.supabase.co` host other than the QA one, or to `api.anthropic.com`.
- The new live harness carries the same refusal as the security harness: it exits 2 if
  `QA_URL` contains `nxdbooufqzkpslkcogxc`, before any network call.
- No migration was applied anywhere. No edge function was deployed anywhere. No production
  secret was read, requested or written.
- Credentials used were the QA anon key committed at `apps/mobile/dart_defines/qa.json`
  and the QA fixture passwords committed at `supabase/tests/security/lib.mjs`. No service
  role key was available to or used by this workstream.

*Note for the release owner, outside this workstream's scope:*
`apps/mobile/tool/live_integration_test.dart` hard-codes `nxdbooufqzkpslkcogxc` and
describes it as "the real Supabase dev instance", while `supabase/tests/security/lib.mjs`
names the same ref as production. One of the two is wrong, and a tool that seeds and
mutates data should not be pointed at a project whose role is in dispute.
