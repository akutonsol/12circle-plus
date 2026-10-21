# 12 Circle — Workout Domain Contract

**Status:** canonical · **Contract version:** `2` · **Established:** Phase 2B, 2026-08-24
**Supersedes:** the undocumented `program_workouts.exercises` dialects catalogued in
[`PHASE_2_WORKOUT_RECONCILIATION.md`](PHASE_2_WORKOUT_RECONCILIATION.md) §2.

This document is the single authority for the workout domain. Database, Program
Intelligence Engine, Program Builder, materialization, Flutter models and codecs,
session, set logging, restoration, history, API and tests all conform to *this*, and
disagreements are resolved against *this* rather than against each other.

> **Architectural rule — THE ENGINE DECIDES. AI EXPLAINS.**
> *(Product authority, closed 2026-08-24 — see §8.)*
>
> The deterministic coaching / program intelligence engine **is** authoritative for
> workout prescription. Where sufficient authoritative information exists it determines
> exercise selection, exercise order, sets, reps / rep ranges, rest, tempo, RPE/RIR,
> load, progression and regression, coaching constraints and cues, and warm-up
> requirements.
>
> **AI is not an independent prescription authority.** AI may explain, contextualize,
> communicate, summarize and assist with adaptation, only within the governed
> deterministic architecture.
>
> Where the engine has insufficient authoritative information to determine a value, the
> contract carries `null` — **never a fabricated default** — and the client renders an
> absence, not a number.

---

## 1. Domain model

```
Program ─┬─ ProgramWorkout ──── ExercisePrescription ──── SetPrescription
         │       (a day)              (an instance)            (a set)
         │
         └─ (assignment) ─── WorkoutSession ─── WorkoutSetLog
                                  │                  │
                            snapshot of         one per set
                          the prescription       performed
```

| Entity | Backing store | Nature |
|---|---|---|
| `Program` | `workout_programs` | Prescription. Coach- or engine-authored. |
| `ProgramWorkout` | `program_workouts` (one row = one day) | Prescription. |
| `ExercisePrescription` | `program_workouts.exercises[]` | Prescription. One **instance** of a movement in a day. |
| `SetPrescription` | `exercises[].set_details[]`, or expanded from `sets`/`reps` | Prescription. |
| `WorkoutSession` | `workout_sessions` | Execution. Owns a frozen snapshot of the prescription. |
| `WorkoutSetLog` | `workout_set_logs` | Execution. What was actually performed. |

**Prescription and execution never share a field.** A `SetPrescription` has no
`completed`, no logged reps and no logged load. A `WorkoutSetLog` has no target. The
only thing they share is the **set identity** that links them.

---

## 2. Identity

| Entity | Identity | Authority | Stability |
|---|---|---|---|
| Program | `workout_programs.id` (uuid) | server | permanent |
| ProgramWorkout | `program_workouts.id` (uuid) | server | permanent |
| Session | `workout_sessions.id` (uuid) | server | permanent |
| SetLog | logical key `(session_id, set_id)`; surrogate `workout_set_logs.id` | server | permanent |
| **Exercise instance** | `exercise_instance_id` (text) | writer of the prescription | **immutable for the life of the instance** |
| **Set instance** | `set_id` (text) | writer of the prescription | **immutable for the life of the set** |
| Library exercise | `exercise_id` (uuid → `exercises.id`) — a **reference**, not an identity | server | permanent |

### 2.1 Rules — non-negotiable

1. **Set identity is never `exercise name + set number`.** It is never a list index, an
   arrival order, or a set number alone.
2. **Exercise identity is never the exercise name.** A workout may legitimately contain
   the same movement twice; those are two instances with two identities.
3. `set_id` is **unique at workout scope**, not merely within one exercise.
4. A `set_id` and an `exercise_instance_id` **survive** persistence, restoration,
   rehydration, session reload and re-snapshotting. They are stored and read back
   verbatim; they are never re-derived from a position.
5. **An exercise replacement mints a NEW `exercise_instance_id` and NEW `set_id`s.**
   Reusing them is what produced the 23505 collisions and the inherited completion
   state.
6. `workout_title` is **not** an identity. Nothing may key a session, a status or a
   progress figure on it.

### 2.2 Minting

Ids are minted **once**, by whoever first writes the prescription, and never again:

| Source | `exercise_instance_id` | `set_id` |
|---|---|---|
| Engine (`materialize_program_week`) | `gen_random_uuid()::text` | `<instance>:s<n>` |
| Self-guided generator | `gen_random_uuid()::text` | `<instance>:s<n>` |
| Program Builder (coach) | `gen_random_uuid()::text` | `<instance>:s<n>` |
| Legacy row with no id | `ex-<name-slug>` (deterministic), position as tie-break | `<instance>:s<n>`, uniquified at workout scope |
| Exercise swap | fresh `swap-<uuid>` | `<new instance>:s<n>` |

The legacy mint is deterministic so re-reading an un-migrated row yields the same ids
and its existing logs still find their sets. **Migration 119 freezes these mints into
the rows**, after which nothing is minted from a name again.

---

## 3. Canonical JSON — `program_workouts.exercises`

`exercises` is a JSON **array**. Every element is an `ExercisePrescription`.
Enforced in the database by `public.is_canonical_exercise_prescription(jsonb)` and a
`CHECK` constraint (migration 119).

### 3.1 `ExercisePrescription`

| Key | Type | Class | Notes |
|---|---|---|---|
| `exercise_instance_id` | `text` non-empty | **required**, immutable, server-authoritative | identity |
| `name` | `text` non-empty | **required**, client-editable (coach) | display + `workout_set_logs.exercise_name` |
| `exercise_id` | `text` \| `null` | optional | reference into the exercise library |
| `position` | `int ≥ 0` | **derived** | array index; ordering authority |
| `sets` | `int ≥ 1` | **required** | count of `SetPrescription`s when `set_details` is absent |
| `reps` | `int ≥ 0` | **required** | `0` means the work is timed — see `duration_seconds` |
| `weight_kg` | `number ≥ 0` \| `null` | **required key, nullable value** | See §3.6. `null` = no specific load prescribed · `0` = zero external load deliberately prescribed · a number = that load. Never `0` for "unknown". |
| `rest_seconds` | `int ≥ 0` \| `null` | optional | `null` = not prescribed; the client shows no rest timer |
| `rpe` | `number 1–10` \| `null` | optional | RPE. RIR has no representation yet — see §8 G-2 |
| `tempo` | `text` \| `null` | optional | free text, e.g. `"3-1-1"` |
| `duration_seconds` | `int ≥ 1` \| `null` | optional | timed work (plank, carry); mutually meaningful with `reps: 0` |
| `notes` | `text` \| `null` | optional | coaching cue |
| `is_superset` | `bool` | optional, default `false` | |
| `superset_group` | `text` \| `null` | optional | |
| `is_circuit` | `bool` | optional, default `false` | |
| `circuit_group` | `text` \| `null` | optional | |
| `circuit_rounds` | `int ≥ 1` | optional, default `1` | |
| `set_details` | `array<SetPrescription>` \| absent | optional | present ⇒ authoritative; `sets`/`reps`/`weight_kg` become the summary |

Descriptive library fields (`category`, `muscle_group`, `equipment`, `difficulty`,
`description`, `instructions`) are **optional and non-authoritative** — a cache of the
library row, carried in session snapshots so a session survives a library change.

### 3.2 `SetPrescription` (`set_details[]`)

| Key | Type | Class |
|---|---|---|
| `id` | `text` non-empty | **required**, immutable — the `set_id` |
| `set_number` | `int ≥ 1` | **required** — display ordinal, **never identity** |
| `reps` | `int ≥ 0` | **required** |
| `weight_kg` | `number ≥ 0` \| `null` | **required key, nullable value** |
| `rest_seconds` | `int ≥ 0` \| `null` | optional |
| `rpe` | `number 1–10` \| `null` | optional |
| `tempo` | `text` \| `null` | optional |
| `duration_seconds` | `int ≥ 1` \| `null` | optional |
| `notes` | `text` \| `null` | optional |

There is **no `completed`, no logged `reps`, no logged `weight` in a `SetPrescription`.**
Execution lives in `workout_set_logs` only.

### 3.3 Field classification summary

| Class | Fields |
|---|---|
| **Required** | `exercise_instance_id`, `name`, `sets`, `reps`, `weight_kg` (key), and on a set: `id`, `set_number`, `reps`, `weight_kg` (key) |
| **Optional** | `exercise_id`, `rest_seconds`, `rpe`, `tempo`, `duration_seconds`, `notes`, superset/circuit fields, `set_details`, library descriptors |
| **Derived** | `position` (array index), `sets` when `set_details` is present |
| **Server-authoritative** | `exercise_instance_id`, `set_id`, `position`, and every id in §2 |
| **Client-editable** | `name`, `sets`, `reps`, `weight_kg`, `rest_seconds`, `rpe`, `tempo`, `notes` — **by a coach, on a program**. A *client* never edits a prescription; they log against it. |
| **Immutable** | every identity; and the whole prescription once a session has snapshotted it (§5) |

### 3.4 Canonical types — no ambiguity

| Concept | Canonical representation | Rejected |
|---|---|---|
| reps | `int` | `"10"`, `"8-12"`, `10.0` |
| sets | `int ≥ 1` | `"3"`, `0`, `null` |
| load | `weight_kg`, `number` kilograms, or `null` | `weight`, `load`, `lbs`, `0`-as-unknown |
| rest | `rest_seconds`, `int` seconds, or `null` | `rest`, `"60"`, `"1min"` |
| RPE | `rpe`, `number` 1–10, or `null` | `rir`, `"8"`, `"RPE8"` |
| tempo | `text`, or `null` | structured objects |
| duration | `duration_seconds`, `int`, or `null` | `duration`, `"45s"` |
| day of week | `day_of_week`, full English name `'Monday'`…`'Sunday'` | `'1'`, `1`, `'mon'` |

**Kilograms are the only stored unit.** `lb` exists solely as a display preference and
is converted at the widget boundary.

### 3.5 Legacy dialects — accepted, recorded, migrated

The codec runs a single **explicit** normalization pass before strict decoding. Each
conversion it makes is reported as a `ContractDeviation` — it is never silent.

| Legacy | Canonical | Source |
|---|---|---|
| `id` (exercise level) | `exercise_instance_id` | engine (W3) |
| `rest` | `rest_seconds` | Program Builder (W2), integration probe (W5) |
| `weight` | `weight_kg` | pre-contract snapshots (R4) |
| numeric-string `sets`/`reps`/`rest*`/`weight*` that parses **exactly** | the `int`/`number` | Program Builder (W2), AI (W6) |
| element missing `weight_kg` entirely | `weight_kg: null` — **not `0`** | all pre-contract writers |
| `set_details[].weight` | `set_details[].weight_kg` | pre-contract snapshots |

Anything the normalizer cannot convert **unambiguously** — `reps: "8-12"`, `reps: ""`,
a missing `name`, `sets: 0`, a non-array `exercises` — is left as it is and the strict
decoder raises `WorkoutContractViolation` naming the workout, the exercise, the field
and the value.

**A contract violation is never converted into an empty workout.** See §7.

### 3.6 Load semantics — `weight_kg`

Settled by product authority, 2026-08-24. `weight_kg` is nullable and the three
values are three different statements:

| Value | Means | Client renders |
|---|---|---|
| `null` | **No specific load is prescribed.** The engine had insufficient authoritative information to determine one. | an absence — "—", never a number |
| `0` | **Zero external load is intentionally prescribed** — a bodyweight movement. | bodyweight / "BW" |
| a number ≥ 0 | **That specific load is prescribed**, in kilograms. | the value |

**The engine must not invent a load merely because the field exists.** With
insufficient authoritative information it emits `null`. That is a complete,
correct answer, not a gap to be papered over — and the whole reason the column
is nullable. A fabricated `0` is what made every program in the system read as
an instruction to lift nothing.

---

## 4. Set logging

`workout_set_logs` records execution. One row per set attempted in a session.

| Column | Role |
|---|---|
| `session_id` + **`set_id`** | **the identity.** Unique together (`uq_workout_set_logs_set_identity`, migration 106) |
| `exercise_instance_id` | which instance the set belonged to (migration 120) |
| `exercise_id`, `exercise_name` | recorded **attributes** of the movement performed, for history and PR lookups |
| `set_number` | recorded **display ordinal** |
| `reps`, `weight_kg`, `rpe`, `notes`, `tempo` | what was performed |
| `completed` | whether the client **confirmed** the set (migration 104). A row exists for a merely-edited set too. |
| `logged_at` | server-stamped |

### 4.1 Rules

1. `saveSetLog` upserts on **`(session_id, set_id)`**. It must never match on
   `exercise_name` or on `set_number`. *(Migration 051's ordinal unique index is retired
   by migration 120; it was the second, competing identity.)*
2. `set_id` is **required** for every row written from contract v2 onward. Historical
   rows keep `NULL` and continue to resume by their stored `set_number` — migration 106's
   stated intent, preserved.
3. `exercise_name` is a recorded attribute. Renaming or swapping a movement **never**
   rewrites a historical row.
4. **Completed history is immutable.** A confirmed set's `reps`/`weight_kg`/`rpe` change
   only through the explicit correction flow (`ActiveWorkoutNotifier.applyCorrection`);
   nothing else may rewrite them, and `completed` is never toggled back to false.
5. Rows are **never deleted** — not on swap, not on abandon, not on supersede.

---

## 5. Materialization and the session snapshot

```
Program prescription            ProgramWorkout row (canonical §3)
        │
        ▼  materialization  — engine or coach authors the day
program_workouts.exercises      canonical, CHECK-enforced
        │
        ▼  session start   — workoutToSnapshot()
workout_sessions.workout_snapshot   a FROZEN copy, canonical + set_details
        │
        ▼  execution
workout_set_logs                keyed by (session_id, set_id)
```

1. **The session snapshot is authoritative for a running session.** Once
   `workout_sessions.workout_snapshot` is written, the session is rebuilt from it and
   **never** from `program_workouts`. A coach editing the program mid-session cannot
   mutate a session already underway.
2. The snapshot is **lossless**: every exercise instance and every set is written with
   its id, so a rebuild returns the same entities.
3. The snapshot is re-written **only** by an in-session change the client themselves
   made (an exercise swap). That re-snapshot must succeed or be surfaced — a lost
   re-snapshot means a refresh rebuilds the pre-swap workout.
4. **A completed or abandoned session's snapshot and set logs are immutable.** Nothing
   re-snapshots a session that is not `in_progress`.

---

## 6. Exercise swap

Swapping replaces one `ExercisePrescription` **instance** with another.

### Produces
- a **new** `exercise_instance_id`
- a **new** `set_id` for every set

### May be copied from the replaced instance
- `position` (the new movement occupies the same slot)
- `sets` count, `reps`, `rest_seconds`, `rpe`, `tempo`, `duration_seconds`
  — *the prescribed structure*, which is what "keeps your sets" means to the client
- superset / circuit membership (`is_superset`, `superset_group`, `is_circuit`,
  `circuit_group`, `circuit_rounds`)
- coaching `notes` **only when they are not movement-specific** — the app copies
  exercise-level notes and drops per-set notes, which are execution commentary

### MUST NOT be copied
- `weight_kg` — load is movement-specific; a barbell squat's 100 kg is not a goblet
  squat's. The new instance's load is `null` (not prescribed) unless a rule prescribes
  one. *(Blocked on Q-A; see §8 G-1.)*
- any `set_id` or `exercise_instance_id`
- completion state, logged reps/load/RPE, or any `workout_set_logs` identity
- the resume cursor, when it pointed into the replaced instance
- `exercise_id` and the library descriptors of the replaced movement

### After a swap
- no unique-constraint collision (`saveSetLog` inserts under fresh `set_id`s)
- `saveSetLog` succeeds on the first set of the new movement
- resume works: the cursor is re-pointed to the new instance's first outstanding set
- **the replaced movement's logs are untouched** and remain attributed to the exercise
  actually performed

---

## 7. Session state machine

```
                    ┌──────────────┐
   start / resume   │              │  "Leave for now"  (cursor + elapsed saved)
  ─────────────────▶│ in_progress  │◀──────────────────────────────┐
                    │              │                               │
                    └──┬────────┬──┘                               │
       "Complete /     │        │   "End workout"                  │  Resume
        Finish Early"  │        │   / superseded by another start  │
                       ▼        ▼                                  │
                 ┌───────────┐  ┌────────────┐                     │
                 │ completed │  │ abandoned  │                     │
                 └───────────┘  └────────────┘        ─────────────┘
                   terminal        terminal
```

| State | Meaning | Set logs | Resumable |
|---|---|---|---|
| `in_progress` | the one live session for a user (`workout_sessions_one_active_per_user`) | live | **yes** |
| `completed` | the client finished — fully or early | frozen, immutable | no |
| `abandoned` | the client ended it without completing, **or** it was superseded by starting a different workout | **preserved**, frozen | no |

There is **no separate `paused` state.** "Pause" is `in_progress` plus a stored cursor —
which is exactly what migrations 105/107 built. Adding a fourth state would duplicate it.

### Rules

1. **Exit is an explicit choice, and the copy must be true.** The client leaving the
   Workout Zone is asked to distinguish *keep this session* from *end this session*.
2. **A confirmed end must set `abandoned`.** Leaving an `in_progress` row behind after
   the client said "end" is forbidden — it keeps offering a workout they closed and
   corrupts `getCompletionRate()`.
3. **Abandon never deletes.** Set logs and the snapshot are retained; the work was
   performed and counts toward volume and history.
4. `completed` and `abandoned` are **terminal**. Nothing re-opens them.
5. Starting a *different* workout abandons the open session first — the existing
   `WorkoutSessionManager.startWorkout` behaviour, preserved.

---

## 8. Engine prescription — the decision, and what is not yet built

**Q-A — product authority decision, 2026-08-24 — CLOSED.** The deterministic
coaching / program intelligence engine **is** authoritative for workout prescription.
Where sufficient authoritative information exists it determines exercise selection,
exercise order, sets, reps / rep ranges, rest, tempo, RPE/RIR, load, progression and
regression, coaching constraints and cues, and warm-up requirements. AI is **not** an
independent prescription authority; it may explain, contextualize, communicate,
summarize and assist with adaptation within the governed deterministic architecture.
Load follows §3.6 — and the engine **must not invent a load merely because the field
exists**; with insufficient authoritative information it emits `null`.

Per the standing rule *"where information is missing, document the gap rather than
inventing a rule"*, these are the parts of that mandate the engine does not yet
implement:

**Q-A is CLOSED** (product authority, 2026-08-24): the deterministic engine **is** the
prescription authority, across selection, order, sets, reps/ranges, rest, tempo,
RPE/RIR, load, progression/regression, coaching constraints and warm-up. AI never
prescribes. Load follows §3.6, and the engine emits `null` rather than fabricating a
number.

The gaps below are what the engine does **not yet implement** of that mandate. They are
recorded, not invented around.

**G-1 · `build_workout` implements selection only.** Migration 089's `build_workout`
ranks movements under equipment / injury / systemic-fatigue / movement-variety rules and
emits `{id, name, pattern, score, systemic_fatigue}`. It assigns no sets, reps, load,
rest, RPE or tempo. Under the closed Q-A decision this is now a **known shortfall against
the engine's own mandate**, not an open question about where prescription belongs.

Until it is implemented, the contract behaves exactly as the decision requires:
`materialize_program_week` takes structure from the caller's context (never invented),
emits `weight_kg: null` because it has no authoritative basis for a load, and **raises**
rather than writing an empty workout. Building the prescription rules themselves is a
distinct piece of engine work with its own scope — it is not something to improvise
inside a contract-repair phase, and doing so would be inventing coaching methodology,
which remains forbidden.

**G-2 · RIR has no representation yet.** The Q-A decision names "RPE/RIR" as an engine
output. The product implements **RPE** end to end (`workout_set_logs.rpe`, the contract's
`rpe`, the set tracker's RPE input). Nothing in the schema, the engine, the Flutter models
or the tests references **RIR**, and no conversion between the two is defined anywhere in
the product. Adding one would be inventing coaching methodology, so RIR is recorded as
unimplemented rather than guessed at. When the engine gains a prescription model, whether
RIR is a distinct field or a presentation of RPE is a decision for that work.

**G-3 · Rep ranges have no representation yet.** The Q-A decision names "reps / rep
ranges" as an engine output. Today `reps` is a single integer everywhere — schema,
engine, Flutter models, tests — so `"8-12"` is a contract violation rather than a
supported prescription, and is refused rather than silently resolved to one end of the
range. Representing a range needs a schema shape (`reps_min`/`reps_max`, or a structured
value), a client rendering and a logging semantic; that is engine/product work, not a
contract repair, and is recorded here as the next thing the prescription model needs.

**G-4 · PAR-Q risk state does not constrain prescription.** Recorded in Phase 0 as
CON-04 / Q-4. Out of Phase 2 scope; the contract leaves room (`notes`, exclusion happens
at selection) but adds nothing.

**G-5 · `materialize_program_week` had no failure path.** An empty engine selection was
written as `exercises: []` and reported as a successful materialization. **Fixed** by
migration 119: an empty selection raises. It does **not** invent a fallback selection —
an engine that cannot select is a failure to surface, not a workout to fabricate.

---

## 9. Authorization

Phase 1 (migration 117) is the boundary and Phase 2 **does not widen it**:

- `workout_programs` SELECT → owner, coach, or `public.can_read_program(id)`
- `program_workouts` SELECT → `public.can_read_program(program_id)`
- `workout_sessions` / `workout_set_logs` → owner, or an active coach (migration 100)

Every read path in this contract — `getMyAssignedProgram` → `getProgramWorkouts`,
`assignedWorkoutsProvider`, `WorkoutSessionManager.workoutForSession` — goes through
those policies unchanged. Migration 119's validation function is `IMMUTABLE` and touches
no table, so it introduces no new privileged path.

---

## 10. Conformance

| Component | Conforms by |
|---|---|
| `program_workouts.exercises` | `CHECK (public.is_canonical_exercise_prescription(exercises))` — migration 119 |
| `_plan_day_exercises` / `generate_client_plan` | rewritten to emit §3 — migration 119 |
| `materialize_program_week` | emits §3 or fails explicitly — migration 119; never invents a load |
| `generate_client_plan` | emits §3 with `weight_kg: null`, and unique day titles — migrations 119 + 121 |
| Program Builder | `_ExerciseDialog` emits §3 types |
| `ai-generate-workout` | normalizes model output to §3 before returning |
| `programWorkoutToWorkout` / `workoutToSnapshot` | decode/encode through `WorkoutContract` |
| `WorkoutSet` / `WorkoutExercise` | workout-scoped identity; no execution fields |
| `saveSetLog` | upserts on `(session_id, set_id)` |
| Exercise swap | `WorkoutExercise.replacing()` mints fresh identities |
| End Workout | abandons the session (§7) |
| Seeds, integration probe | emit §3 |
| Tests | `docs/PHASE_2_WORKOUT_TEST_MATRIX.md` |
