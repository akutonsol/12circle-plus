# Phase 2 — Workout Domain Test Matrix

**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environment:** QA `eyqtldjqpgpljlqvpowh`. **Production was not contacted.**

Baseline before Phase 2: **Flutter 558 passed · API 58 unit + 6 e2e passed.**
After Phase 2: **Flutter 591 passed · API 58 unit + 6 e2e passed · `flutter analyze` 0 errors, 0 warnings.**
Live QA: **20/20 AFTER assertions PASS** (migrations 119 + 120 applied 2026-08-24).

---

## 1. The 20 required cases

| # | Required coverage | Where | Status |
|---|---|---|---|
| 1 | duplicate exercise names | `workout_domain_contract_test.dart` · WKT-203 "the same movement prescribed twice is two instances"; live probe **BEFORE-1** | ✅ |
| 2 | repeated exercise instances | WKT-203 "two instances that explicitly claim the same id are separated" | ✅ |
| 3 | duplicate set numbers | WKT-203 "repeated set numbers within one exercise stay distinguishable" | ✅ |
| 4 | stable set identity | WKT-203 "identity is deterministic", "identity survives the snapshot round trip, repeatedly"; `workout_set_identity_test.dart` QA-CL-006 | ✅ |
| 5 | exercise swap | WKT-204 (7 tests) | ✅ |
| 6 | swap completed-state isolation | WKT-204 "completed state does NOT follow the swap"; WKT-205 "a log from the replaced exercise is not seated on the new one" | ✅ |
| 7 | `saveSetLog` | migration 120 (identity key, required `set_id`); `workout_service.dart` argument guard; live probes **AFTER-2/3/5** | ✅ live |
| 8 | restoration | `workout_restoration_test.dart`, `workout_session_persistence_test.dart` WKT-100/101; WKT-205 | ✅ |
| 9 | `resumePosition` | `workout_restoration_test.dart`; WKT-204 "a cursor pointing into the replaced exercise no longer resolves" | ✅ |
| 10 | malformed JSON | WKT-201 "a malformed row fails explicitly instead of decoding to nothing" (6 shapes) | ✅ |
| 11 | String reps rejection | WKT-201 "a rep RANGE is a violation"; migration 119 CHECK; live probes **BEFORE-4 → AFTER-1a/1b/1c** | ✅ live |
| 12 | numeric reps acceptance | WKT-201 "an integer rep count is accepted", "a rep count that is unambiguously a number is read, and reported" | ✅ |
| 13 | prescribed weight | WKT-202 (4 tests) — null ≠ 0, seed load survives | ✅ |
| 14 | rest | WKT-201 legacy `rest` → `rest_seconds`; WKT-202 seed `rest_seconds` survives; ambiguity refused | ✅ |
| 15 | RPE / RIR | WKT-202 "RPE and tempo survive the round trip". **RIR is not modelled** — contract §8 gap G-2 | ✅ (gap recorded) |
| 16 | session snapshot | WKT-206 (4 tests); migration 120 snapshot-immutability trigger | ✅ |
| 17 | completed history immutability | `workout_set_immutability_test.dart`; migration 120 `workout_set_logs_protect_history`; live probes **BEFORE-3 → AFTER-4a/4b/4c** | ✅ live |
| 18 | end-workout state transitions | `active_workout_screen._endWorkout` / `_leaveForNow`; migration 120 terminal-status trigger (live **AFTER-6a/6b/6c**); `workout_active_session_authority_test.dart` | ✅ (UI half: §4) |
| 19 | one-active-session constraint | `workout_session_persistence_test.dart` WKT-105; `InMemoryWorkoutSessionStore` reproduces the unique index | ✅ |
| 20 | program authorization | `phase1_security_boundary_test.dart` SEC-027 "no Phase 2 migration widens the Phase 1 authorization boundary"; live probes **AUTH-1/2**, re-run as **AFTER-8a/8b/8c** | ✅ live |

One case (#18) is fully covered at the database and store level but has no
widget test for the dialog itself — recorded honestly in §4 rather than claimed.

---

## 2. Live QA — BEFORE

All four ran inside a single `DO $$ … $$` block on QA that ends by raising, so
the whole probe **rolled back**. Nothing was left behind.

| ID | Defect | Result |
|---|---|---|
| **BEFORE-1** | duplicate exercise names collide | `insert … ('Bench Press', set 1, set_id 'inst-a:s1')` then `('Bench Press', set 1, set_id 'inst-b:s1')` → **23505 on `uq_workout_set_logs_set`** (the migration-051 ordinal index). Two legitimately different sets were the same row. |
| **BEFORE-2** | exercise swap collides | after a swap the name changes and the set id does not: `('Dumbbell Press', set 1, set_id 'inst-a:s1')` → **23505 on `uq_workout_set_logs_set_identity`**. Hard error on the first set logged after any swap. |
| **BEFORE-3** | completed history is mutable | `update workout_set_logs set completed=false …` → **succeeded**. A confirmed set was un-confirmed by a plain PostgREST-reachable update. |
| **BEFORE-4** | out-of-contract row accepted | `insert … exercises '[{"name":"Bench Press","sets":3,"reps":"10","rest":60}]'` → **accepted verbatim**; stored as `{"name":"Bench Press","reps":"10","rest":60,"sets":3}`, `day_of_week` left as `'3'`. This row makes the client's whole program undecodable. |

Read-only observations, same session:

| ID | Observation |
|---|---|
| **OBS-1** | `program_workouts` holds exactly two element shapes: `{name,sets,reps,rest_seconds}` (22 elements, self-guided generator) and `{name,sets,reps,weight_kg,rest_seconds}` (20 elements, seed). **Neither carries `weight`**, which is the only load key the codec read — so every prescribed load in QA reached the client as 0 kg. |
| **OBS-2** | the seed program's `day_of_week` is `"1"`,`"2"`,`"4"`,`"5"`; `getTodaysWorkout()` compares against `'Monday'`…. It can never match. |
| **OBS-3** | the client's **active** assignment is the `coach_id IS NULL` self-guided program, whose generator emits no load field at all. |
| **OBS-4** | the self-guided program has duplicate day titles — "Upper Body" ×2, "Lower Body" ×2. `programSessionStatusProvider` keys sessions **by title**, so starting one marks both in progress. Migration 052 fixed this; migration 077 rewrote the generator from 048 and dropped the fix. |
| **OBS-5** | `build_workout({size:4, recovery:80})` → `"selected": []`. `materialize_program_week` would insert four empty days and report `sessions_created: 4`. Silent materialization failure, exactly as reported. |
| **AUTH-1** | anon `GET /program_workouts` → **401** (`permission denied`). Phase 1 boundary intact. |
| **AUTH-2** | client `GET /program_workouts` → **200**, 8 rows — own + assigned only, via `can_read_program()`. Coach sees the same 8 through the coach branch. |

---

## 3. Live QA — AFTER

Migrations **119** and **120** were applied to QA on 2026-08-24, then
`supabase/tests/workout/phase2-contract.sql` was run. **All 20 assertions PASS.**
The probe ends by raising, so it rolled back and left nothing behind.

```
PASS AFTER-7a  non-canonical program_workouts rows: 0
PASS AFTER-7b  numeric day_of_week rows: 0
PASS AFTER-7c  seeded 60kg bench press readable as weight_kg: 1
PASS AFTER-7d  exercise elements with no instance id: 0
PASS AFTER-8a  can_read_program() still present
PASS AFTER-8b  program_workouts SELECT still gated by can_read_program
PASS AFTER-8c  anon grants on program_workouts: 0
PASS AFTER-1a  legacy row canonicalised: {"rpe": null, "name": "Bench Press",
               "reps": 10, "sets": 3, "notes": null, "tempo": null,
               "position": 0, "weight_kg": null, "rest_seconds": 60,
               "duration_seconds": null,
               "exercise_instance_id": "ex-bench-press-0"}  day=Wednesday
PASS AFTER-1b  rep range refused by the CHECK
PASS AFTER-1c  unnamed exercise refused
PASS AFTER-2   duplicate exercise names no longer collide
PASS AFTER-3   post-swap set log inserts cleanly
PASS AFTER-3b  the replaced exercise keeps its own completed log
PASS AFTER-5   set log without an identity refused
PASS AFTER-4a  un-completing a confirmed set refused
PASS AFTER-4b  re-attribution to another instance refused
PASS AFTER-4c  an explicit correction is still permitted
PASS AFTER-6a  re-opening a completed session refused
PASS AFTER-6b  finished session snapshot is immutable
PASS AFTER-6c  abandoning preserves set logs: 3 rows
```

### Load semantics — all three states verified live

Across every exercise element in QA (`program_workouts`, 57 elements):

| State | Count | Meaning | Source |
|---|---|---|---|
| `weight_kg` key missing | **0** | — the key is always present | — |
| `weight_kg: null` | **37** | no specific load prescribed | self-guided generator, which has no authoritative basis for one |
| `weight_kg: 0` | **3** | zero external load deliberately prescribed | coach seed — Plank, Pull-Ups, Ab Wheel |
| `weight_kg: <positive>` | **17** | that specific load prescribed | coach seed |

The same movement appears under more than one state — "Plank" as `null` from the
generator and as `0` from the coach; "Bench Press" as `null` and as `60` — which is the
proof the three are genuinely distinguished rather than collapsed. Before Phase 2 all 57
read as `0` to the client.

### Client-facing REST re-probe (same credentials as the BEFORE run)

| Before | After |
|---|---|
| two element dialects, neither carrying the key the codec read | **one** canonical shape across all 8 rows |
| `weight_kg: 60` present but read as **0 kg** | `weight_kg: 60` read as **60 kg**; `weight_kg: null` where nothing prescribes load; `weight_kg: 0` preserved for Pull-Ups |
| `day_of_week` `"1"`,`"2"`,`"4"`,`"5"` | `"Monday"`, `"Tuesday"`, `"Thursday"`, `"Friday"` |
| generated days titled "Full Body"×3 / "Upper Body"×2 | "Full Body A/B/C", "Upper Body A/B", "Lower Body A/B" |
| no exercise element carried an identity | every element carries `exercise_instance_id` and `position` |
| anon → 401, client → 8 rows | **unchanged** |

### What each AFTER assertion was pinned against

| ID | Assertion |
|---|---|
| **AFTER-1** | the BEFORE-4 row is now **canonicalised**: `reps: "10"` is canonicalised to `10`, `rest: 60` to `rest_seconds: 60`, `weight_kg: null` is added, an `exercise_instance_id` is minted, and `day_of_week '3'` becomes `'Wednesday'`. A row with `reps: "8-12"` is **refused** by `program_workouts_exercises_canonical`. |
| **AFTER-2** | duplicate exercise names no longer collide — two instances' set 1 both insert, under their own `set_id`s. |
| **AFTER-3** | the post-swap insert succeeds: a new instance's set carries a new `set_id`, so there is nothing to collide with. |
| **AFTER-4** | `update workout_set_logs set completed=false` is **refused** by `workout_set_logs_protect_history`; re-attributing a row to another instance is refused; moving it between sessions is refused. |
| **AFTER-5** | `insert into workout_set_logs` with no `set_id` is **refused** by `workout_set_logs_require_identity`. |
| **AFTER-6** | re-opening a `completed`/`abandoned` session is **refused**; editing a terminal session's snapshot is **refused**. |
| **AFTER-7** | every existing `program_workouts` row satisfies `is_canonical_exercise_prescription`; the seed's 60 kg bench press reads back as 60 kg; no `day_of_week` matches `^[1-7]$`. |
| **AFTER-8** | AUTH-1/AUTH-2 re-run unchanged — the boundary is exactly where Phase 1 left it. |

The probe script is `supabase/tests/workout/phase2-contract.sql` (§6).

---

## 4. Known gaps in coverage

| Gap | Why | Disposition |
|---|---|---|
| **End Workout has no widget test** (#18) | The Workout Zone screen is 1900 lines with live Supabase, timer and audio dependencies; a faithful widget test needs a seam that does not exist yet. The *state machine* is covered at the store level and now enforced by migration 120's terminal-status trigger. | Recommend extracting the exit decision into a testable controller in the UI phase, then pinning it. Recorded, not silently skipped. |
| **`saveSetLog` has no unit test** (#7) | `WorkoutService` resolves `Supabase.instance.client` directly and has no injectable seam. Its identity contract is enforced by migration 120 instead, which is the stronger place for it. | Recommend the same seam treatment as `WorkoutSessionStore`. |
| **Live security suite not re-run** | `supabase/tests/security/run.mjs` requires `QA_SERVICE` (the service-role key), which is not present in this environment (`.env` and `.env.local` are both empty). | Must be re-run before Phase 2 sign-off. Nothing in 119/120 touches a policy, and SEC-027's new static guard asserts that. |
| **Engine prescription** | The engine emits no sets/reps/load/rest. Contract §8 gap **G-1**, escalated as **Q-A**. | Blocked on a product decision. Migration 119 makes the engine fail loudly instead of writing empty workouts, and does **not** invent a prescription. |

---

## 5. Reproduction commands

```bash
# Flutter
cd apps/mobile && flutter analyze && flutter test

# API
npm run test:api

# Live security regression (needs QA_URL / QA_ANON / QA_SERVICE)
npm run test:security

# Live QA workout-domain probes (QA only)
supabase db query --linked --file supabase/tests/workout/phase2-contract.sql
supabase db query --linked --file supabase/tests/workout/plan-day-titles.sql
```

---

## 6. Test inventory added by Phase 2

`apps/mobile/test/unit/workout_domain_contract_test.dart` — 29 tests:

| Group | Covers |
|---|---|
| **WKT-201** the codec validates the canonical type | 5 tests — integer reps, unambiguous numeric-string reps (reported as a deviation), rep ranges refused, six malformed shapes refused, `rest`/`rest_seconds` contradiction refused |
| **WKT-202** no prescribed load is null, never 0 kg | 4 tests — absent → null, prescribed 0 preserved, seed `weight_kg` survives, RPE/tempo round trip |
| **WKT-203** duplicate exercises get distinct identities | 5 tests — same movement twice, colliding explicit ids, repeated set numbers, determinism, round-trip stability |
| **WKT-204** a swap is a new instance | 7 tests — new identities, structure copied / load not, slot order, superset & circuit membership, completed-state isolation, stale cursor misses, workout-scope uniqueness after swap |
| **WKT-205** logs stay with the exercise performed | 2 tests — replaced exercise's log not re-seated, two instances kept apart |
| **WKT-206** the snapshot is the frozen prescription | 4 tests — per-set variation, contract version stamped, snapshot decodes with zero deviations, explicit per-set null load |
| **WKT-207** prescription carries no execution state | 2 tests — `WorkoutSet` has no completion field, snapshots never write one |
| **WKT-208** session status is looked up by identity | 3 tests — two days sharing a title do not share a status, pre-103 sessions still resolve by title, an id entry beats a title entry naming another workout |

`apps/mobile/test/unit/phase1_security_boundary_test.dart` — 1 test added:
**SEC-027 "no Phase 2 migration widens the Phase 1 authorization boundary"** —
asserts no post-118 migration names the production project, opens a
`USING (TRUE)` policy, grants to `anon`, disables RLS, or drops
`can_read_program`.

**SEC-027 "a migration that redefines `generate_client_plan()` keeps the unique
day-title rule"** — the 077/052 drift pinned at source. Finds the latest
migration that redefines the function and asserts it uses `plan_day_titles` and
applies it *after* the focus bias. Migration 077 passed review precisely because
its header said "Reproduces 048 verbatim"; this is the check that was missing.

`supabase/tests/workout/plan-day-titles.sql` — 12 live assertions (§3).
