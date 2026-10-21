# Phase 2 — Workout Domain Reconciliation

**§1–§8 are the Phase 2A reconnaissance, written before any implementation.
§9 records what was then built and live-verified.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` — authenticated read-only probes.
**Production `nxdbooufqzkpslkcogxc` was not contacted.**

Verification legend: **LIVE** = reproduced against QA this session · **SRC** = proven
from source · **OPEN** = suspected, needs a probe or a decision.

---

## 1. The shared root cause

The eleven reported defects are not eleven bugs. They are **three contract failures**
that each fan out across the chain, plus one lifecycle omission.

| # | Contract failure | Symptoms it produces |
|---|---|---|
| **RC-A** | `program_workouts.exercises` is untyped `jsonb` with **six writers and four readers, none agreeing** on key names or value types | String-reps codec crash · empty client workout · 0 kg prescription · missing rest · engine sessions with no prescription · silent materialization failure · `program_workouts` JSON divergence |
| **RC-B** | **Two live set-identity keys** — migration 051's ordinal `(session_id, exercise_name, set_number)` and migration 106's `(session_id, set_id)` — both enforced as unique indexes, and the writer uses the *ordinal* one | duplicate set identity · exercise-swap collision · 23505 · completed-state inheritance on swap · resume seating the wrong row |
| **RC-C** | **Errors are returned as valid empty values** at the domain boundary | a decode failure becomes "you have no program"; a failed session read becomes "nothing to resume" |
| **RC-D** | The **session state machine is written down but not closed** — `abandoned` exists in the schema and in `WorkoutSessionManager`, and no UI path reaches it | "End Workout" leaves an `in_progress` row forever; one-active-session index then blocks or mis-resolves the next workout |

RC-A and RC-B are the *same architectural mistake applied at two layers*: **a
human-readable label is being used as an identity**. `exercise_name` identifies a set
log; `workout_title` identifies a session (`programSessionStatusProvider`); a name-slug
mints an exercise id. Every collision below is an instance of that.

Anything fixed as an individual symptom re-breaks at the next writer. This is the
justification for a single canonical contract rather than eleven patches.

---

## 2. Writer / reader matrix — `program_workouts.exercises`

Column definition: `exercises jsonb DEFAULT '[]'` (migration 001:89). **No CHECK, no
schema, no validation function, no NOT NULL on elements.**

### 2.1 Writers

| ID | Writer | Layer | Element shape emitted | Verified |
|---|---|---|---|---|
| **W1** | `_plan_day_exercises()` — migrations 047 → 077, called by `generate_client_plan()` (SECURITY DEFINER) | database | `{name:text, sets:int(3), reps:int, rest_seconds:int}` | **LIVE** — 22 elements in QA |
| **W2** | `program_builder_screen.dart` `_ExerciseDialog` → `CoachProgramService.addWorkoutToProgram` / `updateWorkout` | Flutter coach UI | `{name:String, sets:int, reps:` **String** `, rest:int?}` | **SRC** — [`program_builder_screen.dart:701-706`](../apps/mobile/lib/features/coach/presentation/program_builder_screen.dart#L701-L706) |
| **W3** | `materialize_program_week()` — migration 093:160, inserting `build_workout()->'selected'` (089:102) | Program Intelligence Engine | `{id:uuid, name, pattern, score, systemic_fatigue}` — **no prescription at all** | **LIVE** — `build_workout` returns `selected: []` in QA |
| **W4** | `supabase/seeds/test_accounts.sql:146-166` | seed fixture | `{name, sets:int, reps:int,` **`weight_kg`**`:num, rest_seconds:int}` | **LIVE** — 20 elements in QA |
| **W5** | `tool/live_integration_test.dart:413` (PRG-002 probe) | test tooling | `{name, sets:int, reps:` **String** `, rest:int}` | **SRC** |
| **W6** | `ai-generate-workout` Edge Function | AI (returned in-band, not persisted to `program_workouts`, but fed to the **same codec** via `generateAiWorkout`) | `{name, sets, reps, rest_seconds, tempo, notes, superset_group, is_superset}` — `reps`/`sets` are **whatever the model emitted**; `e.reps ?? 10` preserves a String | **SRC** |

### 2.2 Readers

| ID | Reader | Layer | Element shape expected |
|---|---|---|---|
| **R1** | `programWorkoutToWorkout()` — [`workout_snapshot.dart:23`](../apps/mobile/lib/features/workout/data/workout_snapshot.dart#L23). **The only structural reader.** Serves `assignedWorkoutsProvider`, `generateAiWorkout`, and `WorkoutSessionManager.workoutForSession` (snapshot restore) | codec | `{exercise_id\|id, name, category, muscle_group, equipment, difficulty, description, instructions[], sets:int, reps:int, weight:num, rest_seconds:int, tempo, set_details[], is_superset, superset_group, is_circuit, circuit_group, circuit_rounds, notes}` |
| **R2** | `program_builder_screen.dart:387,611` — coach's own list rendering | Flutter UI | `{name, sets, reps, rest}` |
| **R3** | `qa_suites.dart:514` — `ProgramIntegritySuite` "exercises missing rest" | QA harness | `{name, rest_seconds}` |
| **R4** | `workoutToSnapshot()` — [`workout_snapshot.dart:104`](../apps/mobile/lib/features/workout/data/workout_snapshot.dart#L104) — writes the **snapshot** dialect of the same shape, read back by R1 | codec | emits the full R1 shape *plus* `set_details[]` with per-set `id` |

`workoutToSnapshot` (R4) is the **only writer in the system that emits the shape R1
actually reads.** It is the de-facto canonical form and the correct basis for §3 of the
contract document.

### 2.3 Field-by-field divergence

| Field | Emitted as | Read as | Consequence |
|---|---|---|---|
| **rest** | `rest_seconds` (W1, W4, W6) · **`rest`** (W2, W5) · absent (W3) | `rest_seconds` (R1, R3) · `rest` (R2) | Coach-authored rest is **silently discarded**; codec substitutes 90 s. Coach sets 60 s, client rests 90 s. |
| **load** | **`weight_kg`** (W4) · absent (W1, W2, W3, W5, W6) | **`weight`** (R1) | **No writer in the system emits `weight`.** `((e['weight'] as num?) ?? 0)` yields **0.0 for every exercise of every program**, from every source. The seed's real `weight_kg: 60` is dropped on the floor. **LIVE-confirmed.** |
| **reps** | `int` (W1, W4) · **`String`** (W2, W5) · absent (W3) · model-typed (W6) | `e['reps'] as int?` (R1) | Dart's `as int?` **throws** on a String — it does not yield null. One coach-authored exercise crashes the whole program decode. |
| **sets** | `int` count (W1, W2, W4, W5, W6) · absent (W3) | `(e['sets'] as int?) ?? 3` (R1) | Engine-materialized sessions silently become 3 sets. |
| **exercise identity** | `id:uuid` (W3) · absent (W1, W2, W4, W5, W6) | `exercise_id` ?? `id` ?? mint-from-name (R1) | Identity is derived from a **name slug** for 5 of 6 writers. Two rows with the same name in one workout are disambiguated only by list position. |
| **rpe / rir** | never emitted by any writer | never read by R1 | Field exists on `WorkoutSet` and on `workout_set_logs`; **no prescription path reaches it.** |
| **tempo** | W6 only | R1 | Effectively AI-only today. |
| **`day_of_week`** (sibling column, same contract failure) | `'Monday'` (W1, W2) · **`'1'`..`'5'`** (W4 seed) | `w['day_of_week'] == 'Monday'` (`getTodaysWorkout()`) | **LIVE-confirmed** in QA: seed program stores `"1"`, `"2"`, `"4"`, `"5"`. `getTodaysWorkout()` can never match it. |

---

## 3. Live QA state — the BEFORE evidence

Authenticated as `test@12circle.app` (client `5470a95f…`) and `coach@12circle.app`.

```
workout_program_assignments (client):
  4818d97f… coach f626acd9…  status = superseded   ← coach's "Summer Shred 8-Week"
  48099a62… coach null       status = ACTIVE       ← self-guided "Fat Loss Program"

program_workouts, 8 rows, exactly two element shapes:
  [22]  name:string, reps:number, rest_seconds:number, sets:number                    ← W1
  [20]  name:string, reps:number, rest_seconds:number, sets:number, weight_kg:number   ← W4

program 4818d97f (coach, W4 seed): day_of_week = "1" "2" "4" "5"
program 48099a62 (self-guided, W1): day_of_week = "Monday" "Tuesday" "Thursday" "Friday"
                                    titles      = "Upper Body" ×2, "Lower Body" ×2

build_workout({size:4, recovery:80})  →  200 { "selected": [], "target_size": 4, … }
plan_program(…)                       →  200, 8 weeks of mesocycle structure — no prescription
exercise_intelligence                 →  unreadable to a client; substrate empty (ENV-03)

anon GET /program_workouts            →  401  (117 boundary intact)
client GET /program_workouts          →  200, 8 rows (own + assigned only)
workout_set_logs (client)             →  200, [] — no logged sets to regress against yet
```

### What this establishes

1. **0 kg is live, and it is a key-name mismatch, not a missing value.** The seed
   prescribes 60 kg bench press. The codec reads `weight`. The row says `weight_kg`.
   The client is shown a 0 kg target. **LIVE.**
2. **The active program is the self-guided one**, which emits no load field at all — so
   even fixing the key name leaves that path with no prescription. **LIVE.**
3. **The engine materializes nothing.** `build_workout` returns `selected: []` because
   `exercise_intelligence` is unpopulated. `materialize_program_week` inserts
   `coalesce(v_result->'selected','[]')` and **reports `sessions_created: 4`** — four
   program days containing zero exercises, with no error anywhere. This is the "silent
   workout materialization failure" in its exact mechanical form: the engine has no
   failure path for an empty selection. **LIVE.**
4. **Duplicate day titles are back.** Migration 052 fixed this (A/B/C suffixes);
   migration 077 rewrote `generate_client_plan()` from **048**, not 052, and dropped the
   fix. QA now has "Upper Body" ×2 and "Lower Body" ×2 in one program.
   `programSessionStatusProvider` keys sessions **by `workout_title`**, so starting one
   marks both as in progress. **LIVE — a regression not previously recorded.**
5. **The 117 authorization boundary is intact and Phase 2 does not need to widen it.**
   Client reads own + assigned via `can_read_program()`; anon is refused at the grant
   level.

---

## 4. Set-identity chain — every reader and writer

| Stage | Component | Identity it uses | Verdict |
|---|---|---|---|
| mint | `WorkoutSet.mintId(exerciseId, setNumber)` | `exerciseId:sN` | Uniquified **within one `WorkoutExercise` only** (`_identify`). Two `WorkoutExercise` entries sharing an `exercise.id` mint **identical set ids**. Must be workout-scoped. |
| mint | `_mintExerciseId(name, index, taken)` | name slug, position as tie-break | Only reached when the row carries no `exercise_id`/`id` — i.e. **5 of 6 writers**. |
| snapshot write | `workoutToSnapshot` → `set_details[].id` | `set.id` | ✅ correct |
| snapshot read | `programWorkoutToWorkout` → `_nonEmpty(s['id']) ?? mintId(...)` | stored id wins | ✅ correct |
| in-memory state | `ActiveWorkoutNotifier` — `Map<setId, …>` | `set.id` | ✅ correct |
| **persist** | **`WorkoutService.saveSetLog`** | **UPDATE `.eq(session_id).eq(exercise_name).eq(set_number)`**, with `set_id` written only as a payload column | ❌ **the defect.** Uses the 051 ordinal as the key; `set_id` is cargo. |
| DB constraint | `uq_workout_set_logs_set` (051) | `(session_id, exercise_name, set_number)` | still enforced |
| DB constraint | `uq_workout_set_logs_set_identity` (106) | `(session_id, set_id) WHERE set_id IS NOT NULL` | also enforced |
| read back | `getSessionCompletedSets` | groups by `exercise_id ?? exercise_name` | ✅ |
| seat | `seatSetLogs` → `_matchSet` | `set_id` first, `set_number` fallback | ✅ correct |
| resume | `resumePosition(…, cursorSetId)` | `current_set_id`, falls back to first outstanding | ✅ correct |
| advance | `advancePosition` | forward from completed set id | ✅ correct |
| **swap** | **`_swapExercise`** — `sets: we.sets` | **reuses the replaced exercise's `WorkoutSet` objects verbatim** | ❌ **the defect.** New exercise inherits old set ids. |

### The 23505, precisely

1. Client logs set 1 of "Bench Press" → row `(session, 'Bench Press', 1, set_id='ex-bench-press:s1')`.
2. Client swaps Bench Press → Dumbbell Press. `_swapExercise` keeps `we.sets`, so the new
   exercise's set 1 **still has `id = 'ex-bench-press:s1'`**.
3. Client logs set 1 of Dumbbell Press. `saveSetLog` UPDATEs on
   `exercise_name = 'Dumbbell Press'` → **matches nothing** (the row says 'Bench Press').
4. Falls through to INSERT with `set_id = 'ex-bench-press:s1'` →
   **violates `uq_workout_set_logs_set_identity` → 23505.** Hard error, every set after
   any swap.

The same two defects produce **completed-state inheritance** without touching the
database: `activeWorkoutProvider` is keyed by `set.id`, the swap preserves `set.id`, so
the new exercise's sets render as already completed — and `_editableWhenCompleted` then
locks values the client never entered for that movement.

And **duplicate set identity** needs no swap at all: a workout with the same exercise
twice mints the same ids for both blocks, so one block's set 1 overwrites the other's on
both indexes.

---

## 5. Session lifecycle — the state machine as built

| State | Written by | Reached from UI? |
|---|---|---|
| `in_progress` | `createSession` (store) | ✅ Start / Resume |
| `completed` | `completeSession` ← `_completeWorkout` ("Complete Workout" / "Finish Early") | ✅ |
| `abandoned` | `abandonSessions` ← `WorkoutSessionManager.startWorkout` superseding, and `activeSession` de-duping | ⚠️ **only as a side effect of starting a different workout** |
| paused / resumable | **does not exist as a state** — resumability is `in_progress` + a stored cursor | n/a |

**`_showEndDialog`** ([`active_workout_screen.dart:1414-1436`](../apps/mobile/lib/features/workout/presentation/active_workout_screen.dart#L1414-L1436)) is the defect:

- It tells the client **"Your progress won't be saved."** That is **false** — every set
  was already persisted to `workout_set_logs` on completion *and* on edit (migration 051
  / 104). Nothing is discarded.
- On confirm it calls `ActiveWorkoutNotifier.reset()` and navigates home. It **never
  touches the session row.** The session stays `in_progress` indefinitely.
- Consequence: the Resume banner keeps offering a workout the client explicitly ended;
  `workout_sessions_one_active_per_user` then makes the *next* workout's start depend on
  the supersede path; and `getCompletionRate()` (completed ÷ completed+abandoned) never
  counts the abandonment, so adherence metrics overstate.

There are therefore **two distinct client intents collapsed into one button**, and the
dialog implements neither: *"I'm stepping away, keep this"* (pause — today's actual
behaviour, mislabelled) and *"I'm done with this one, close it"* (abandon — what the
button says, and what it does not do).

This is the only defect in the cluster that is a **product-semantics** question rather
than a contract violation. §7 Q-B.

---

## 6. Error-swallowing inventory (RC-C)

| Site | On failure returns | Indistinguishable from |
|---|---|---|
| `assignedWorkoutsProvider` | `[]` | "you have no program" |
| `generateAiWorkout` | `null` | "generation declined" |
| `programSessionStatusProvider` | `{}` | "no sessions" |
| `activeSessionProvider` | `null` | **"nothing to resume"** |
| `WorkoutService.getWorkoutHistory` / `getSessionSetLogs` / `getExerciseProgression` / `getPersonalRecords` / `getTotalVolumeLifted` / `getCompletionRate` / `getClient*` | `[]` / `0` | "no history" |
| `CoachProgramService.planProgram` / `materializeWeek` / `createEngineProgram` / `evaluateWeek` / `regenerateProgram` | `null` | "engine declined" |
| `_saveCursor` | swallowed | acceptable — documented, costs a scroll |
| `_resnapshotSession` | swallowed | **not** acceptable — a lost re-snapshot means a restore rebuilds the *pre-swap* workout |

The correct pattern already exists in-tree and should become the rule:
`activeWorkoutRestorationProvider` distinguishes loading / null / **error**, and
`getSessionCompletedSets` documents why it lets reads throw.

---

## 7. Product-authority decisions

**Q-A · Does the deterministic engine prescribe load and volume?**
### ✅ CLOSED — product authority, 2026-08-24

**The deterministic coaching / program intelligence engine IS authoritative for workout
prescription.** Where sufficient authoritative information exists it determines exercise
selection, exercise order, sets, reps / rep ranges, rest, tempo, RPE/RIR, load,
progression and regression, coaching constraints and cues, and warm-up requirements.

**AI is not an independent workout-prescription authority.** It may explain,
contextualize, communicate, summarize and assist with adaptation only within the governed
deterministic architecture.

**Load rule.** `weight_kg` remains nullable: `null` = no specific load prescribed;
`0` = zero external load intentionally prescribed (bodyweight); a number = that load.
**The engine must not invent a load merely because the field exists** — with insufficient
authoritative information it emits `null`.

This is exactly the shape the Phase 2 contract was built to, so nothing had to be
redesigned. What it changes is the classification of the remaining engine work: the
absence of a prescription model in `build_workout` is no longer an open question about
*where* prescription belongs — it is a **known shortfall against the engine's own
mandate**, recorded as gaps G-1/G-2/G-3 in
[`WORKOUT_DOMAIN_CONTRACT.md`](WORKOUT_DOMAIN_CONTRACT.md) §8.

<details><summary>The question as it stood before the decision</summary>

`build_workout` selects movements and applies volume/fatigue/injury rules. It emits **no
sets, reps, load, rest, RPE or tempo.** The MIE document makes the engine the source of
truth for "every workout recommendation… and progression", and Phase 2's own rule is
**THE ENGINE DECIDES**. A prescription is a recommendation — so architecturally it
belongs in the deterministic layer. But no prescription model exists today, and writing
one is **coaching methodology**, which Phase 2 explicitly forbids me from inventing.

Options:
- **(a)** Engine prescribes sets/reps and an intensity target (%1RM or RPE) from a new
  deterministic rule set. *Requires a coaching model that does not exist — out of scope
  under the non-negotiables.*
- **(b)** Engine prescribes **structure** (exercise, sets, reps, rest); **load is derived
  from the client's own logged history** by a progression rule. Deterministic,
  explainable, uses `workout_set_logs` which already exists, and matches "progression" as
  an existing engine responsibility.
- **(c)** Coach-authored programs carry load; engine-generated ones show none.

**Recommendation: (b)**, with **(c) as the interim contract** — i.e. `load` is `null`
(not `0`) wherever nothing prescribes it, and the client renders "—", never "0 kg".

</details>

**Q-B · What should "End Workout" mean?**
Evidence (§5) says the button's label and its dialog copy both misdescribe what it does.
The smallest contract consistent with what the product already supports — the schema
already has `abandoned`, and `getCompletionRate()` already reads it — is:

- **Pause / "Leave for now"** → session stays `in_progress`, cursor + elapsed saved,
  Resume banner offers it. *(This is today's actual behaviour.)*
- **End / "Discard this session"** → session set `abandoned`, **set logs preserved**
  (product bible §2.6: completed history is never deleted), Resume banner stops offering
  it, adherence counts it.
- **Complete** → unchanged.

**Recommendation: implement both paths behind an honest two-choice dialog, and correct
the false "your progress won't be saved" copy.** This is a behaviour change to a
client-visible flow, so I want the call — but note that *not* deciding leaves an
orphaned `in_progress` row, which the Phase 2 non-negotiables explicitly forbid.

**Q-C · What happens to set logs recorded against a swapped-out exercise?**
They are completed history and must not be deleted. The open question is whether they
remain visible in the session summary as work performed (recommended — the client did
that work), or are excluded from *program adherence* because the prescribed movement
changed. **Recommendation: retain, attribute to the exercise actually performed, count
toward volume, exclude from "prescribed sets completed".**

---

## 8. Scope confirmed clean

- **`can_read_program()` boundary (2I):** live-verified intact. Every Phase 2 read path
  (`getMyAssignedProgram` → `getProgramWorkouts`, `assignedWorkoutsProvider`,
  `workoutForSession`) goes through `program_workouts` SELECT under 117 and returns the
  correct rows for the client and the coach. **No RLS change is required and none will
  be made.**
- **Already remediated, do not re-fix:** session determinism (103, 108), warm-up
  acknowledgement (105), set-identity column + index (106), cursor (107), restoration
  seating and resume/advance rules (`workout_restoration.dart`), client-side completed-set
  immutability (`_editableWhenCompleted` / `applyCorrection`).
- **`resumePosition` is not itself corrupt.** Its inputs are: a stale cursor after a swap
  is handled correctly (`locateSet` misses → falls back), and the reported corruption is
  the *downstream* effect of RC-B — set ids that survive a swap make a stale cursor
  resolve to a set that visually exists but belongs to the replaced exercise.

---

## 9. Outcome

Phases 2B–2G, 2I and 2J are **implemented and live-verified on QA**. See
[`WORKOUT_DOMAIN_CONTRACT.md`](WORKOUT_DOMAIN_CONTRACT.md) for the contract and
[`PHASE_2_WORKOUT_TEST_MATRIX.md`](PHASE_2_WORKOUT_TEST_MATRIX.md) for the
BEFORE/AFTER evidence (20/20 live assertions pass).

| Defect | Root cause | Status |
|---|---|---|
| WKA-01 duplicate set identity | RC-B | **fixed** — workout-scope identity + `(session_id, set_id)` as the only key; live AFTER-2 |
| WKA-02 exercise swap collision | RC-B | **fixed** — `WorkoutExercise.replacedBy` mints new identities; live AFTER-3 |
| WKA-03 String reps → empty workout | RC-A + RC-C | **fixed** — canonicalizing trigger + CHECK + propagating provider; live AFTER-1a/1b |
| WKA-04 End Workout | RC-D | **fixed** — honest two-choice exit; an ended session is `abandoned`; live AFTER-6 |
| 0 kg prescription | RC-A | **fixed** — `weight_kg` canonical, `null` ≠ `0`; live AFTER-7c and the REST re-probe |
| missing rest values | RC-A | **fixed** — `rest` → `rest_seconds` at the boundary; live AFTER-1a |
| completed-state inheritance on swap | RC-B | **fixed** — new set ids mean no state to inherit; WKT-204 |
| resumePosition corruption | RC-B | **fixed** — a stale cursor now misses cleanly and the swap re-points it |
| 23505 set identity collisions | RC-B | **fixed** — migration 120 retires the 051 ordinal index; live AFTER-2/3 |
| silent materialization failures | RC-A + RC-C | **fixed** — `materialize_program_week` raises on an empty selection; `materializeWeek` propagates |
| `program_workouts` JSON divergence | RC-A | **fixed** — one canonical shape, enforced in the database |
| OBS-4 duplicate generated day titles (found in Phase 2) | title-as-identity | **fixed** — identity half by `sessionStatusFor`; data half by migration 121 (§10) |

---

## 10. Migration 077 / 052 drift — investigation and resolution

### 10.1 What each migration did

Function bodies extracted and diffed directly (`generate_client_plan()` only):

| | 048 | 052 | 077 |
|---|---|---|---|
| lines | 122 | 131 | 142 |

**048 → 052 — what 052 added.** Exactly four declarations (`j`, `v_occ`, `v_total`,
`v_title`) and one counting loop that suffixes a day title A/B/C when its training focus
repeats in the split. Everything else in the diff is comment and whitespace churn. 052
added **one behaviour and nothing else**.

**052 → 077 — what 077 changed.** Added `v_focus` / `v_focus_day`, the coach-focus bias
block, and the program-description suffix — **and removed 052's four declarations and its
counting loop.** Everything else is comment/whitespace restoration.

### 10.2 Was the regression intentional?

**No.** 077's own header states it *"Reproduces 048 verbatim + the bias block"* — it
branched from **048**, which predates 052, and so silently carried 052's absence forward.
Nothing in 077 reads, depends on, or benefits from ambiguous titles. `077 = 048 + bias`,
and the loss of 052 is collateral.

### 10.3 Callers and consumers

`generate_client_plan()` callers: `intake_flow_screen.dart:236` (onboarding),
`coaching_mode_provider.dart:94` (switching to self/AI), and the QA tools
`qa_self_guided.dart` / `qa_entitlements.dart`. It is also listed in migration 116's
RPC-execution security set. **No caller reads or asserts on titles.**

**There is no database constraint on `program_workouts.title`** — despite migration 052's
filename, the mechanism was only ever the generator's own suffixing.

Every remaining title-reading path, after Phase 2:

| Site | Use | Depends on uniqueness? |
|---|---|---|
| `sessionStatusFor` (`workout_provider.dart`) | title fallback, **guarded** by an owner-id check | No |
| `WorkoutSessionManager.workoutForSession:86` | fallback for sessions with no snapshot | No — id is tried first |
| `WorkoutSessionManager._matchWorkout:143` | fallback, **guarded** by `s.workoutId.isEmpty` | No |
| `workout_history_screen`, `coach_client_workout_screen` | display of `workout_sessions.workout_title` | No |
| `workout_list_screen:315` | matches a static browse card to a static sample workout by title | No — both sides are hardcoded in-repo and collision-free. Noted as a residual title-as-identity pattern; not data-driven. |

**Conclusion for step 8: after Phase 2, no downstream behaviour depends on title
uniqueness for correctness.**

### 10.4 Data-generation defect, presentation defect, or both?

**It was both. One half was already fixed; the other was real and still live.**

- *Presentation-of-status half* — 052's stated motivation was that session status was
  keyed by `workout_title`, so starting one day marked all its twins in progress.
  **Fixed by Phase 2**, and fixed better: status is keyed by workout id, with a guarded
  title fallback (`sessionStatusFor`, WKT-208). This is **not** re-litigated by 121.
- *Data-generation half* — the generator emitted labels a client cannot tell apart.
  Independent of how status is keyed, and **not** fixed by the identity work. Three cards
  reading "Full Body" is a defect in the generated data.

Live QA before the fix — **two** self-generated programs regressed, not one:

```
211206c2…  3-day   "Full Body",  "Full Body",  "Full Body"
48099a62…  4-day   "Upper Body", "Lower Body", "Upper Body", "Lower Body"
4818d97f…  coach   unaffected (day-specific titles)
```

### 10.5 Resolution — migration 121

052's rule is still part of the canonical product contract (it is a recorded product
decision, nothing reversed it deliberately, and its client-facing rationale stands
independently of identity keying), so it is restored by a **forward migration**. No
historical migration was modified.

1. **`public.plan_day_titles(text[])`** — 052's loop extracted into one authority, shared
   by the generator, the backfill and the regression suite. A rule living in three copies
   is a rule that drifts again.
2. **`generate_client_plan()`** — 077's body verbatim, with the title rule put back.
3. **One deliberate improvement:** titles are computed from the split **as finally set**,
   i.e. *after* 077's bias block. 077's bias rewrites the last day
   (`v_split[v_days] := v_focus_day`), which can manufacture duplicates 052 never saw — an
   `upper/lower/upper/lower` week biased toward upper becomes `upper/lower/upper/upper`.
   This is 052's own rule applied to 077's own data; no new naming scheme is introduced.
4. **Backfill** of already-generated rows, scoped to `coach_id IS NULL`. A coach's titles
   are theirs and are never rewritten. `workout_sessions.workout_title` is deliberately
   **not** rewritten — that column is history.
5. **Title-based identity is not reintroduced.** 121 adds no constraint, no lookup and no
   key on titles, and `program_workouts.title` is documented as a label.

**Regression coverage.** `supabase/tests/workout/plan-day-titles.sql` (12 live
assertions, rolls back) plus a source-level guard in `phase1_security_boundary_test.dart`
asserting that **any** migration redefining `generate_client_plan()` carries the rule and
applies it after the bias — the check 077's review did not have.

### 10.6 Residual

- `workout_list_screen:315` still matches a browse card to a sample workout by title.
  Both sides are hardcoded and collision-free, so it is not a live defect; it is a
  residual title-as-identity pattern worth removing during UI work.
- `workout_sessions.workout_title` rows for the renamed days still carry the old label.
  That is intended — it records what the client trained. The narrow consequence is that a
  pre-migration-103 session (no `workout_id`) will no longer match a renamed day by title.
