# 12 Circle Fitness — Master Remediation Waves

**Wave 0 deliverable. The dependency-aware execution plan.**
**Date:** 2026-08-24 · **Companion to** [`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md)

**Production `nxdbooufqzkpslkcogxc` is not touched by any wave in this document.**
QA `eyqtldjqpgpljlqvpowh` is the only environment permitted for live verification, and
every write to it must be preceded by an independent confirmation that the linked project
is QA.

---

## 0. The sequencing argument

Ten waves. The order is not severity order, and three of the reorderings are
counter-intuitive enough to state before the plan.

**1. Custody before security.** The entire Phase 1 security remediation — migrations
113–118, six live test suites, the Dart guards — is **untracked** (ENV-1, re-verified).
It is one `git clean -fd` from non-existence, it cannot be reviewed in a PR, and it
cannot be deployed from CI. Writing migration 124 into that tree adds value that has the
same half-life as everything already in it. **Custody is Wave 1 Task 1 and nothing else
begins until it lands.**

**2. Schema truth before error truth.** Workstream H proved the dependency runs this way
and it is easy to get backwards. Four columns the client names do not exist; every call
site swallows the resulting 400 into an empty value. Fixing the *swallows* first
(Workstream B's EC-11) converts four silent failures into four **permanent visible
errors** — a user-facing regression delivered by a correctness fix. So Wave 3 is split:
**3A schema truth, then 3B error contract, then 3C fabrication removal.**

**3. Inputs before deployment.** Deploying the Edge Functions before the input and safety
fixes **converts a visibly dead system into an invisibly wrong one.** Every failure mode
in the AI domain today produces confident output with no error anywhere: a missing column
is a default, a failed read is an empty array, an empty constraint set is a permissive
one, and the confidence score is computed from the same emptied arrays. QA would then be
grading a model that was handed empty context, and those findings are expensive to
un-file. **AI deployment is Wave 5, after Wave 3A.**

**4. Safety-input plumbing before safety policy.** A member currently **cannot declare an
injury or a pregnancy** — `derive_parq_risk` throws `22P02` and the `BEFORE UPDATE`
trigger rejects the whole profile write (SEC-R2). There is no point wiring a PAR-Q
constraint into `build_workout` while the data is unrecordable. **SEC-R2 is Wave 2; the
policy it feeds is Wave 5 and blocked on D-4.**

### 0.1 The parallelization rule, applied strictly

**PARALLEL-SAFE** requires all five: separate files · no shared migration number · no
conflicting contract · no unresolved product decision · no shared architectural primitive
being rewritten.

**SEQUENTIAL** if any one holds: downstream depends on an upstream contract · schema must
exist before code · a security guard must exist before a deployment · an environment must
exist before live verification · a product decision determines the implementation · a
migration changes a contract another fix consumes.

**Where uncertain, sequential.** Two specific consequences that recur below:
- **Migration numbers are a shared resource.** Two owners writing "the next migration"
  concurrently is a merge conflict at best and a silent ordering defect at worst
  (§4.2 of the registry is exactly what a silent ordering defect costs). Numbers are
  **assigned in this document** and are not negotiable at implementation time.
- **A file already modified in the working tree is not parallel-safe** until Wave 1 Task 1
  commits it. That currently includes `workout_service.dart`, `coach_program_service.dart`,
  `coach_provider.dart`, `messaging_service.dart`, `active_workout_screen.dart`,
  `community_provider.dart`, `directory_screen.dart`, `supabase/config.toml`,
  `tool/live_integration_test.dart`, `package.json`, `dart_defines/qa.json`,
  `supabase/functions/ai-generate-workout/index.ts` and 15 migrations.

### 0.2 Migration number assignment

| # | Wave | Contents | Owner |
|---|---|---|---|
| **123** | 1 | Forward-delta carrying the semantic changes of the 15 in-place-edited migrations (ENV-2) | database — **one owner, do not split** |
| **124** | 2 | Security regression closure: SEC-R1 guard restore, SEC-R2 + SEC-R3 casts, `ai_adjust_nutrition` REVOKE + `search_path`, `messages` UPDATE `WITH CHECK` | database/security |
| **125** | 2 | `decision_traces` policy scoping (**blocked on D-7**) | database/security |
| **126** | **2** | PAR-Q risk-flag typed append (`F-J-17`) — **as authored**, `c7c1058` | database/security |
| **127** | **2** | Typed rule-accumulator appends (`F-J-07` / SEC-R3) — **as authored**, `e909f9a` | database/security |
| **128** | **2** | `decision_traces` scope, PD-A05 option (a) (`F-J-12`) — **as authored**, `f38841f` | database/security |
| **129** | 3A | Task **3A-9** — missing objects: `messages.metadata`, `may_notify()` extension, duplicate completion trigger drop, `trg_detect_pr` timing. **`custom_exercises.approved_by` is NOT added — see B3 below** | database |
| **130** | 3A | Task **3A-10** — storage buckets: **private** `progress-photos` and `chat-media` | database |
| **131** | 3A | Task **3A-11** — identity constraints: UNIQUE on the active nutrition plan, `cycle_logs`, the conversation participant pair, `payment_id` | database |
| **132+** | 4+ | Assigned at wave entry, never before |

**Amendment 2026-08-31 — B1, migration renumbering (registry §7.22).** Rows 126/127/128
previously assigned those numbers to Wave 3A. **Wave 2 consumed all three** — `c7c1058`,
`e909f9a`, `f38841f` — each taking the next contiguous number at the time, which is the
same practice already applied when 125 was spent and PD-A05 option (a) landed at 128. The
three rows above are **corrected to what the tree contains; nothing is renumbered**, which
Gate 0.9 forbids in terms (`check-migration-hygiene.sh`: *"Do not renumber an existing
migration to close a gap"*). Wave 3A's three migrations move to **129 → 130 → 131** and
Wave 4+'s floor moves to **132+**. The numbers are not chosen: the QA frontier is 128 and
Gate 0.9 requires a contiguous authored sequence, so 129/130/131 are the only values
possible. **Each remains subject to `expected_applied.json` declaration as `pending` at
authoring time — silence is not a state.**

---

## WAVE 0 — Reconciliation *(this deliverable)*

| | |
|---|---|
| **Purpose** | One canonical finding registry, one root-cause model, one decision list, one gate ladder, one closure standard, one status board |
| **Findings** | All 310 |
| **Dependencies** | none |
| **Prerequisites** | the A–N reports |
| **Parallel tracks** | none — a single reconciliation, by design |
| **Files touched** | six new files in `docs/` only |
| **QA requirements** | none. **No environment was contacted** |
| **Retest** | none |
| **Exit criteria** | ✅ Registry, waves, decisions, gates, closure standard and progress board exist · ✅ every A–N finding maps to a canonical ID and a root cause · ✅ duplicates collapsed and recorded · ✅ regressions identified · ✅ blockers separated from defects · ✅ decisions extracted and owned · ✅ **no implementation begun** |

**Status: COMPLETE.**

---

## WAVE 1 — Custody, Environment & Release Safety

| | |
|---|---|
| **Purpose** | Make the programme's output durable, make the environment default safe, and put a mechanical gate under everything that follows. **Nothing in this wave changes product behaviour.** |
| **Findings** | ENV-1…ENV-6, ENV-10, REL-3, `E-09`, `K-26`, `R-06`, `REL-36`, `LRE-34`, `LRE-41`, `LRE-35`, EB-1, EB-6, and the text half of UIX-2 |
| **Prerequisites** | none |
| **Exit** | G-01, G-02, G-03, G-04, G-05, G-16 (see [`RELEASE_GATES.md`](RELEASE_GATES.md)) |

### Sequential spine

**W1-T1 · Commit the working tree.** `ENV-1`. **Alone, first, blocking.**
Four reviewable slices: (1) migrations `000` + `104`–`122`; (2) the 22 test files;
(3) `workout_restoration.dart` + `workout_contract.dart` — production source the app does
not compile without; (4) the 18 `docs/` reports + these six artifacts. Nothing is deleted,
squashed or rewritten. **Verify before committing that no file was authored by a session
still running** — re-read anything whose mtime is inside the last hour.

**W1-T2 · Forward migration 123.** `ENV-2`. One owner. Enumerate the semantic delta of
each of the 15 in-place edits and carry every one idempotently. Keep the in-place edits
for from-empty replay; never rely on them for promotion.

**W1-T3 · QA migration ledger.** `ENV-3`. Insert the ten version rows for 113–122 into
`supabase_migrations.schema_migrations` **on QA only**, after independently confirming the
linked ref. Requires W1-T1 and W1-T2 so the ledger describes a committed tree.

### Parallel track A — environment defaults *(after W1-T1)*

| Task | Finding | Files | Conflicts |
|---|---|---|---|
| **W1-A1** | ENV-4 | `app_env.dart`, `dart_defines/*.json`, `env_config_test.dart`, `qa_environment_isolation_test.dart` | none once committed. **Invert ENV-012**, which currently certifies the defect |
| **W1-A2** | ENV-5 | `tool/live_integration_test.dart`, `tool/qa_self_guided.dart`, `tool/qa_entitlements.dart`, `harness_environment_guard_test.dart` | `live_integration_test.dart` is modified in-tree → strictly after W1-T1 |
| **W1-A3** | REL-3 | `app_router.dart` + a release-mode route test | none |
| **W1-A4** | K-26 | `app_env.dart` → **conflicts with W1-A1. Merge into W1-A1** |

### Parallel track B — mechanical gates *(after W1-T1)*

| Task | Finding | Files |
|---|---|---|
| **W1-B1** | ENV-6 — `ci.yml`: `flutter analyze`, `flutter test`, `npm run test:api`, `check:web-secrets` on a QA web build, plus the migration-hygiene, production-ref and route guards | `.github/workflows/ci.yml` |
| **W1-B2** | EB-1 — provision a **scoped QA service-role key** as a repository secret; add the environment-gated CI job running `test:security`, `test:ai`, `test:contract`. **This is the first execution of 188 live assertions since Phase 1** | CI secrets, `ci.yml` |
| **W1-B3** | `E-09` — `[functions.*] verify_jwt` declared per function in `config.toml`, `stripe-webhook` explicitly `false` | `supabase/config.toml` (modified in-tree → after W1-T1) |
| **W1-B4** | `LRE-34` `git rm --cached supabase/.temp`; `REL-36` seed guard refusing a non-QA ref; `LRE-35` reset-wrapper link guard | `.gitignore`, `supabase/` scripts |
| **W1-B5** | `R-06` enable leaked-password protection on QA (one project setting) | none |
| **W1-B6** | UIX-2 **text half only** — correct the false help-centre and privacy-policy claims that account deletion exists. *The feature is Wave 7; the false statement should not survive Wave 1* | `help_center_screen.dart`, `privacy_policy_screen.dart` |
| **W1-B7** | `LRE-41` root README + environment runbook | `docs/` |

### Decision-gated, opened in this wave

`ENV-8`/EB-6 (D-2 · API platform) and `ENV-9` (D-3 · PITR vs forward-only) are Wave 1
work that **cannot start** until those decisions land. They are opened here so the
decision clock starts now.

### QA requirements

Read-only until W1-T3. W1-T3 and W1-B2 write to QA: W1-T3 inserts ledger rows;
W1-B2's `setup-identities.mjs` creates and tears down four fixture identities. Both
require the QA-ref confirmation. **No production request.**

### Retest

`flutter test` ≥ 730 · `flutter analyze` 0 errors · `npm run test:api` 58 + 6 ·
`npm run test:security` **executes and passes** (first time ever) ·
`npm run test:contract` passes with the known-violations file unchanged ·
`git status --porcelain supabase/migrations` empty · a `flutter run` with no defines
resolves to **dev** and a release build with no `APP_ENV` **fails**.

### Exit criteria

✅ Zero untracked migrations, tests or production source · ✅ migration 123 applied to QA
and idempotent on replay · ✅ QA ledger matches the tree · ✅ `APP_ENV` defaults to `dev`
and prod constants are out of the binary · ✅ all three harnesses refuse production and a
CI guard enforces it · ✅ CI runs on every push and PR · ✅ the live security suite runs in
CI and passes · ✅ `verify_jwt` declared per function · ✅ no route in a release build
resolves to `/qa-center` or `/mie-debugger` · ✅ the app no longer claims a deletion path
it does not have.

---

## WAVE 2 — Security Regression & Boundary Re-assertion

| | |
|---|---|
| **Purpose** | Close the five findings where a later change undid closed work, and install the class guard that makes the next one impossible. **This is not a re-audit of Phase 1** — Phase 1's 24 closures stand |
| **Findings** | SEC-R1, SEC-R2, SEC-R3, `E-NUT-17`, `I-NOT-04`, `I-MIG-03`, `F-J-12`, `H-11` (RLS half), `EC-05`/`N-07` and `EC-11` are deferred to 3B because they are Dart, not policy |
| **Prerequisites** | Wave 1 complete. **W1-B2 in particular** — without the live suite in CI there is no way to prove this wave landed |
| **Exit** | Gate 2 security row |

### Parallel tracks

| Track | Tasks | Why parallel-safe |
|---|---|---|
| **2A · migration 124** | SEC-R1 (restore `can_act_on_program` over `materialize_program_week_engine` + `SET search_path` + re-REVOKE the engine name) · SEC-R2 (`::text` casts + backfill) · SEC-R3 (`::text` cast) · `E-NUT-17` (forward `REVOKE EXECUTE … FROM authenticated` + `SET search_path`, plus an in-place comment on 079 pointing at it, per the convention 111 established) · `I-NOT-04` (`WITH CHECK` + column restriction on `messages` UPDATE — **needs Q-10**, so ship the `WITH CHECK` that pins authorship and defer the edit-window question) | One migration, one owner, one file. **Not parallel *within* itself** — these are five statements in one file |
| **2B · the class guard** | `I-MIG-03` — generalise `SEC-027`. A standing source test asserting that **no function carrying an authorization wrapper, a `search_path` pin or a security trigger may be redefined by a later migration without carrying them forward.** Plus: extend `d04-rpc-execution.mjs` to assert all five 116 wrappers **as a class**, not individually | Test-only, disjoint from 2A. **This is the most important task in the wave** — it is the only reason to believe the next Phase-1-equivalent will hold |
| **2C · migration 125** | `F-J-12` — scope the `decision_traces` role arm to `is_active_coach_of(subject_id)` | Separate migration number. **Blocked on D-7** |
| **2D · scoring RLS** | `H-11` RLS half — `daily_scores`' `FOR ALL` policy. **Blocked on Q-H4**; the policy narrowing depends on which score is canonical | Blocked |

### Sequential

2A → live re-verification → 2B's assertions promoted from "records the posture" to
"enforces it". 2B's guard must be **written against the pre-2A tree first**, so it is
demonstrated to fail on the regression it exists to catch.

### QA requirements

124 and 125 applied to QA under the ref confirmation. Live probes for SEC-R1 (unrelated
client → 403), SEC-R2 (three flag writes succeed), SEC-R3 (recovery 59/60/61).
Destructive probes use transaction rollback.

### Exit criteria

✅ All five §4.2 regressions closed **and pinned by a test that fails against the
pre-fix tree** · ✅ `test:security` green in CI including the new class assertions ·
✅ a member can declare an injury, a pregnancy and a postpartum state · ✅
`build_workout` returns 200 at recovery 59 with `RECOVERY_REDUCTION` in `rules` · ✅ no
public routine is `authenticated`-executable outside 116's allowlist, asserted live.

---

## WAVE 3 — Contract Truth

Three sub-waves, strictly ordered. **3A → 3B → 3C.**

### WAVE 3A — Schema-contract truth

| | |
|---|---|
| **Purpose** | Make the database contain everything the application names. This is the prerequisite for the error contract: until it holds, honest error surfacing produces visible permanent errors |
| **Findings** | DAT-2 (column half), DAT-3, DAT-4, `I-COM-03`, `I-WRK-01`, `I-NUT-01`, `F-J-04`, `I-NOT-01`, `I-NOT-02`, `I-NOT-03`, `I-WRK-02`, `H-04`, `H-05`, `H-06` (client half), `UIX-1`, `I-NUT-04`, `I-WMH-01`, `I-NOT-05`, `I-PAY-01` constraint half, `I-MIG-02`, `I-USR-02` |
| **Prerequisites** | Wave 1 (CI + `test:contract` running); Wave 2 for the migration-number discipline |
| **Exit** | `known-violations.json` empty except decision-gated entries; `npm run test:contract` green with an **empty** allowlist |

**Parallel batch — nine independent one-file changes.** All verified disjoint:

| Task | Finding | File | Change |
|---|---|---|---|
| 3A-1 | `I-NUT-01` | `supabase/functions/ai-coaching-engine/index.ts` | `protein_g`→`protein`, `carbs_g`→`carbs`, `fat_g`→`fat` |
| 3A-2 | `I-INT-01` | same file | `goal`→`fitness_goal` — **merge with 3A-1, same file** |
| 3A-3 | `F-J-04` | same file | five per-table ordering keys; `recent()` distinguishes a failed read from an empty one — **merge with 3A-1** |
| 3A-4 | `DAT-2` column half | `supabase/functions/ai-generate-workout/index.ts` | `goal`/`equipment`; add injuries to the generator's prompt context |
| 3A-5 | `I-WRK-01` | `workout_service.dart:237,243,246` | `created_at`→`logged_at`. **Must land before EC-11** |
| 3A-6 | `DAT-4` | `event_ticket_screen.dart` | `ticket_code`→`qr_code`; **delete the fabricating `catch`.** Pair with BIL-3 |
| 3A-7 | `H-06` client half | four client surfaces | repoint at `public_profiles`, drop `email` |
| 3A-8 | `UIX-1` | `booking_screen.dart:55-58` | drop the `coach:coach_id(...)` embed; read from `public_profiles` |
| 3A-9 | migration **129** | `custom_exercise_service.dart` | `messages.metadata jsonb`; extend `may_notify()`; drop the duplicate completion trigger; `trg_detect_pr` → `AFTER INSERT OR UPDATE`. **`I-COM-03`(a): repoint the client write to the existing `last_reviewed_by` — do NOT add an `approved_by` column** (B3, registry §7.22) |
| 3A-10 | migration **130** | — | **private** `progress-photos` and `chat-media` buckets. **Neither may be public — both hold body photography** |
| 3A-11 | migration **131** | — | identity constraints (CRC-06): partial UNIQUE on the active nutrition plan, UNIQUE+CHECK on `cycle_logs`, UNIQUE on the conversation pair, UNIQUE on `payment_id` |

**Sequential inside 3A:** 129 → 130 → 131 (migration numbers; renumbered 2026-08-31, §0.2 amendment / registry §7.22). 3A-5 → *(Wave 3B EC-11)*.
`I-WRK-03` (populate `program_workout_id`) **must not land** — blocked on Q-7, because the
FK is `NO ACTION` and populating it makes `generate_client_plan()`'s delete fail with
23503 for any client who has trained.

### WAVE 3B — Error contract

| | |
|---|---|
| **Purpose** | Install the four-outcome contract — **Ok · Failed · Refused · Unavailable** — as a per-layer obligation, and stop the repository reporting success it has not earned |
| **Findings** | ERR-1…ERR-4, `EC-05`…`EC-26`, `M-10`, `F-J-16`, `EC-11` |
| **Prerequisites** | **3A complete** (the H dependency) · Wave 1's observability decision (D-5(L)) for the sink's destination |
| **Exit** | Gate 2 error row |

**Strictly ordered — this is Workstream B's sequence and it is correct:**

- **3B-0 · Observability first.** `ERR-1`. An `AppFailure` type and one `reportFailure()`
  sink; wire the five sanctioned swallow categories to it. **No propagation changes yet.**
  Additive, cannot change behaviour, and it is what makes every subsequent step
  *verifiable*. Nothing else in 3B may start first.
- **3B-1 · Safety inputs (rule S).** `ERR-2`, `ERR-3`, `ERR-4`. Edge Functions check
  `error` on every PostgREST destructure and **refuse rather than degrade**;
  `risk_level ?? 'low'` becomes "not assessed" at all four sites; onboarding stops
  marking itself complete on a failed save. **Depends on CON-03 (the serializer mismatch
  that triggers it today) and on SEC-R2 (the trigger throw that is the second trigger).**
- **3B-2 · Verified writes (rule W).** `EC-08`, `EC-09`, `EC-12`. Generalise the two
  in-tree reference implementations. **Moderation and platform-settings writes first.**
- **3B-3 · Persisted transitions (rules T, D, M).** `EC-05`/`N-07`, `EC-06`, `EC-07`,
  `EC-14`, `EC-22`, `M-10`, `K-07` UI half.
- **3B-4 · Service-layer sweep (rule L2).** `EC-11` *(after 3A-5)*, `EC-13`, `EC-15`,
  `EC-16`, `EC-18`, `EC-19`, `EC-21`, `EC-25`, `F-J-16`.
- **3B-5 · Contract enforcement.** Promote the guards from "record the baseline" to
  "enforce the rule"; ratchet `EC-G5` down at each step. **Fix `EC-G5`'s blind spot
  first** — it matches `catch` blocks and cannot see Riverpod's `error: (_,__) =>` or
  `.valueOrNull`, so 150 sites are invisible to it (N-03).

**Parallel-safe within 3B:** the sites inside 3B-2 and 3B-4 touch disjoint service files
and can be split by file. **3B-0 → 3B-1 → {3B-2 ∥ 3B-3} → 3B-4 → 3B-5** is the spine.

### WAVE 3C — Fabrication removal

| | |
|---|---|
| **Purpose** | Delete every runtime demo fallback. **The product must never present invented data as the user's own** |
| **Findings** | `H-07`, `H-08`, `H-13`, `H-14`, `M-05`, `EC-17` |
| **Prerequisites** | 3B (an empty state needs an honest error state beside it) |
| **Decisions** | `H-08`→**Q-H2**, `H-14`→**Q-H6**. `H-07`, `H-13`, `M-05` need none |
| **Shape** | One remediation for all four: **delete the fallback, design the empty state**, and where a starter set is genuinely wanted, seed it as real rows with real (zero) history |
| **Sequential** | `H-07` → then `H-08`/`H-13` on one shared empty-state component |
| **Exit** | No code path substitutes fixture data for a real query result. A source guard asserts it |

---

## WAVE 4 — Core Member Journey

| | |
|---|---|
| **Purpose** | A member completes onboarding → plan → assignment → train → log → complete → check-in → nutrition, end to end, in QA. **No UI polish** |
| **Findings** | `CON-03`, `ERR-3` completion, DAT-1 cluster (`I-CHK-01`…`I-CHK-04`, `E-CHK-01`…`E-CHK-04`), `E-NUT-01`, `E-NUT-02`, `E-NUT-03`, `E-NUT-05` data half, `E-NUT-10`, `E-NUT-13`, `E-NUT-14`, `I-NUT-03`, AI-1, AI-2, `ENG-03`…`ENG-06`, `N-08`, `R-08`, `EC-16`, `I-WRK-02` |
| **Prerequisites** | Waves 1–3 · **Q-1, Q-2, Q-3, Q-4, Q-E2** answered |
| **Exit** | Gate 2 journey row |

### Sequential track — check-in *(one change, one root cause)*

`I-CHK-03` **column contract** → `I-CHK-01` **rewire** → `E-CHK-04` **form fields
including weight** → delete the orphaned service → fix the in-app QA suite → let read
paths surface. **Blocked on Q-1 and Q-2**, and `I-CHK-04` must be fixed in the same
change or the fixtures continue to mask it.

### Sequential track — onboarding

`CON-03` (one serializer, one type; the forward migration must converge from **either**
starting type because production's is unknown) → `ERR-3` completion semantics → PAR-Q
data verified reaching `user_profiles` (needs SEC-R2 from Wave 2).

### Parallel track — nutrition correctness

`E-NUT-01` (keep the unit in the type; a quantity is **required** to produce a log entry
— and rewrite the test that currently asserts the defective mapping), `E-NUT-03` (a real
date parameter on `logMeal`; reject future dates), `E-NUT-13`, `E-NUT-10`. `E-NUT-02`
(correction path) is blocked on **Q-E2**.

### Parallel track — engine wiring

AI-1 (`materialize_program_week` gets a caller and an affordance), AI-2 (`subject_id`
written — **before any fixture data is generated**), `ENG-03` (stop the Copilot UI
inventing 3×10 — this contradicts the closed Q-A decision), `ENG-04` (**stop Copilot
approval detaching the client from their multi-week program**), `ENG-05` (day-name
vocabulary), `ENG-06` (vary the context per split day, or the split is a title).

### Sequential dependency to respect

`E-NUT-05`'s **data half is unconditional and lands here**: the profile's declared
allergies must reach the prompt. The **block-vs-annotate guard** is Wave 5 and blocked on
Q-E5/D-6.

### Exit criteria

✅ A QA member completes the full journey with no fabricated state and no swallowed
failure · ✅ a check-in written by the app is readable by the coach queue, the Insights
panel and the AI context · ✅ a coach-authored program and an engine-materialized program
both reach the client with a valid prescription · ✅ a mis-logged meal can be corrected
*(or the decision to defer it is recorded)*.

---

## WAVE 5 — AI / Intelligence

| | |
|---|---|
| **Purpose** | Correct inputs and authorization **first**, then deploy, then verify. Never the other way round |
| **Findings** | 44 AI/engine + 20 Edge Function findings |
| **Prerequisites** | Waves 1–4 · EB-2, EB-3, EB-4, EB-7, P-11 · **D-1, D-2(D), D-4, D-8 answered** · **W1B-N5 resolved** *(added 2026-08-24, Wave 1 batch: `config.toml` reconciled with QA's live configuration; until then the `[functions.*]` block deploys only per function via `supabase functions deploy` — never `supabase config push`, which would silently reset QA's auth configuration)* |
| **Exit** | Gate 3 |

**Sub-waves, strictly ordered. This is Workstream D §6 and J §11 reconciled.**

| # | Sub-wave | Contents | Deploys? |
|---|---|---|---|
| **5.0** | Configuration | EB-2 QA secrets; EB-3 QA Vault (**QA values only**); EB-7 Resend domain; P-11 a QA-scoped Anthropic key **with a budget cap**; confirm 113–128 applied. **Entry precondition W1B-N5:** reconcile `config.toml` with QA's live configuration first; deploy `[functions.*]` only via `supabase functions deploy` per function — **`supabase config push` is forbidden** (registry §7.7) | **no** |
| **5.1** | Vocabulary | `ENG-25` equipment, `ENG-26` warm-up patterns, `ENG-18` bootstrap ordering guard. **Without these, populating the substrate still yields an engine that selects nothing** | no |
| **5.2** | Substrate | `rebuild_exercise_intelligence` → `rebuild_movement_graph` → `seed_warmup_library` → batched enrichment at `limit ≤ 5` → review. `F-J-23` first, or the injury rule can never fire. **Blocked on D-1.** Fixtures are legitimate product data, never fabricated to make a test pass | no |
| **5.3** | RED remediation | `E-04`/`F-J-12` (Wave 2 if D-7 landed), `E-05` audience gate, `E-01`/`E-02` (**D-4(D)/D-5(D)** — deletion or a service-role gate + idempotency), `E-03` (**D-3(D)**), `E-10` non-empty guard | no |
| **5.4** | GREEN deploy | `analyze-food-image`, `ai-generate-workout` — neither writes. If the key, the platform injection or the exercise fixture is wrong, this wave says so cheaply and reversibly | **yes, 2** |
| **5.5** | Enrichment deploy | `enrich-exercise-content`, `enrich-exercise-intelligence`, `enrich-exercise-videos` at `limit: 5` | **yes, 3** |
| **5.6** | YELLOW AI deploy | `explain-decision`, `generate-communication` (post-5.3), `ai-coaching-engine` (post-`E-10`), `ai-coach` (post-**D-2(D)**). **Gate: do not begin AI *quality* assessment until `F-J-04` and `I-NUT-01` are fixed** — grading a model handed empty context produces findings about the wrong layer | **yes, 4** |
| **5.7** | Safety wiring | AI-6 (`F-J-05`) risk + allergies into every assembled context and a PAR-Q **rejection rule** — not a score penalty — in `build_workout`; `F-J-09` gates reject on NULL with a distinct label; `F-J-13` server-side subject snapshot; `F-J-22` status predicate; `E-NUT-05` allergen guard. **Blocked on D-4, D-6, D-1** | no |
| **5.8** | Contract & provenance | AI-5 (`F-J-08`, **D-2**), `F-J-10`, `F-J-14`/`F-J-25`, `F-J-20` refusal detection, `F-J-21` timeouts, `ENG-10` client surface for engine output, `ENG-11` `validate_week` caller, `ENG-13` unimplemented adaptations, `ENG-19`, `ENG-21` | no |
| **5.9** | Scheduled paths | Populate Vault, verify `pg_cron`/`pg_net`, let the crons fire once. **Assert in `cron.job_run_details` that the target host is the QA ref and not `nxdbooufqzkpslkcogxc`. This is the single most important production-safety check in the programme** | — |

**Parallel-safe:** 5.1 ∥ 5.3 (SQL vs TypeScript, disjoint files). Within 5.3 the five
items touch five different functions. **Sequential everywhere else** — every sub-wave is
a precondition for the next, and 5.4–5.6 are ordered by blast radius.

### Exit criteria

✅ Every deployed function returns 401 without a token and 200 with one · ✅ a forced
safety-input read failure produces a 502 and **no workout** · ✅ the same read returning
`[]` still produces a workout (proves rule S did not over-trigger) · ✅ `build_workout`
returns a non-empty, rule-justified selection · ✅ every decision writes a complete,
replayable trace with a recorded model id · ✅ no coach reads a trace outside their
active relationships · ✅ `npm run test:ai`'s characterizations are inverted to invariants
in the same commit that fixes each one.

---

## WAVE 6 — Billing & Entitlements

| | |
|---|---|
| **Purpose** | No free-account path consumes paid resources; billing state transitions are server-authoritative |
| **Findings** | 35 |
| **Prerequisites** | Waves 1–3 · EB-5 · **D-K2, D-K3, D-K4, D-K7, D-K8, D-K9 answered.** D-K1 (iOS) is *deliberately last* |
| **Exit** | Gate 4 billing row |

| Stage | Contents | Parallel? |
|---|---|---|
| **6.0** | EB-5 — QA Stripe runbook (QA ref, test-mode price ids, QA webhook endpoint and its **own** signing secret), `dart_defines/staging.json`. `E-09` already landed in Wave 1 | sequential, first |
| **6.1** | **Four disjoint files, four concurrent owners:** BIL-2 `K-03` server-side plan checks on the four AI functions and inside `generate_client_plan()` · BIL-3 `K-04` + DAT-4 (**one change, one table**) · BIL-1 `K-01` processed-event store + idempotent credit grant · BIL-4 `K-05`+`K-25` `book_coaching_session()` RPC consuming credits under a row lock | **yes, 4-way** |
| **6.2** | `K-07` (never mark cancelled locally when Stripe refused) · `K-08` (refuse duplicate checkouts; partial unique index) · `K-02` (`invoice.paid` / `invoice.payment_failed`; `payments` becomes a real ledger) · then `K-11` (**D-K3**), `K-06` (**D-K4**), `K-23`, `K-27` | 8–10 parallel; 11–13 depend on `K-02`'s event store |
| **6.3** | `K-09`(**D-K8**), `K-13`, `K-17`, `K-19`(after `K-02`), `K-15`, `K-18`+`K-20`(**D-K7**), `K-22`, `K-24`, `K-14`, `E-07`/`K-21`, `K-28`, `E-NUT-07`, `K-10`, `K-30` | mostly parallel |
| **6.4** | **REL-2 / D-K1 — the iOS purchase architecture.** Weeks of work in option (a), and it adds a **second entitlement source of truth on top of a webhook that must already be idempotent.** Not before 6.1 and 6.2 close | sequential, last |

**Never run a real production Stripe transaction. Test mode and QA credentials only.**

### Exit criteria

✅ A replayed `checkout.session.completed` grants exactly one credit block · ✅ a free
account cannot invoke a paid AI function, proven server-side · ✅ a member cannot
self-grant a paid ticket · ✅ booking a session consumes a credit atomically and is refused
at zero · ✅ a Stripe cancel failure leaves local access intact and says so.

---

## WAVE 7 — Secondary Surfaces & Compliance

| | |
|---|---|
| **Purpose** | Every shipped surface either works or is deliberately hidden. **Remove or hide misleading features rather than fabricating behaviour** |
| **Findings** | Women's health (25), product integrity residue, events, community, moderation, account deletion, integrations, pods, dead routes |
| **Prerequisites** | Waves 1–4 · **Q-H2…Q-H8, Q-9…Q-12, E-1…E-5, D-3(G), D-6(G) answered** |
| **Exit** | Gate 4 |

| Track | Contents | Parallel? |
|---|---|---|
| **7A · Women's health** | F's own sequence, which is well-ordered and adopted verbatim: `F-03` (silent destruction of the user's own health log — small, self-contained, no policy input) → `F-08` (render the computed window; **does not wait on E-1**) → `F-09`+`F-13`+`F-02` (carry log age; refuse to extrapolate from a future start; **the threshold waits on E-2, the mechanism does not**) → `F-01` (one migration: every missing CHECK plus the UNIQUE that also closes `F-04`) → `F-18`/`F-19` (project only needed fields, honour `tracking_enabled`, stop passing a cycle row as `recovery`; **consent waits on E-4**) → `F-10`/`F-11`/`F-12` (rewrite the derivation off a single ovulation anchor) → the missing surfaces → `F-15`/`F-16` (fold into the shared date helper; inject the clock) → presentation | internally sequential; **fully parallel with 7B–7E** |
| **7B · Compliance** | UIX-2 account deletion **feature** (needs Q-7's FK decision and Q-8's contract) · REL-5 report/block/moderation + EULA + 24-hour SLA (**D-3**) · REL-6 hosted privacy/terms/support URLs (**D-4(G)**) · `REL-31` bucket privacy review | parallel |
| **7C · Product integrity** | `H-09` challenges (**Q-H3**) · `H-10` notification preferences (**Q-H7**) · `H-12` marketplace admission (**Q-H5**) · `H-16` pods and coach-client-workouts (**Q-H8**) · `H-17` inert Settings controls · `H-18` dead code · `SEC-12` demo filter · `R-01`/`H-11` scoring reconciliation (**Q-H4**) | parallel |
| **7D · Data model** | `I-COM-03` moderation gate (**Q-9**) · `I-COM-04` capacity/waitlist/enrolment RPC (CRC-09) · `I-COM-05`, `I-COM-06` · `I-LEG-01` (**Q-11**, six readers move together) · `I-LEG-02`, `I-LEG-03` (**Q-12**) · `I-USR-01`, `I-USR-03` (**Q-6, Q-7**) | parallel |
| **7E · UI reachability** | `M-05` integrations (**D-6(G)** — recommend hiding unapproved providers) · `M-12` dead buttons · `M-13` QA Center · `E-CHK-05`/`E-CHK-06`/`H-20` routes · M's R-15…R-20 orphan removal | parallel |

**Exit:** ✅ No route reaches a placeholder · ✅ no control is inert · ✅ every UGC surface
has a report and block path or is disabled · ✅ account deletion works end to end,
including Stripe cancellation and storage cleanup.

---

## WAVE 8 — Testing Maturity & Release Engineering

| | |
|---|---|
| **Purpose** | Make the critical tests execute the real product boundary they claim to protect, and make a release reproducible |
| **Findings** | `N-06`, `N-09`, `N-10`, `ENG-20`, EB-8, EB-11, `LRE-09`…`LRE-42`, `REL-01`…`REL-03`, `REL-08`…`REL-15`, `REL-24`…`REL-48`, ENV-10 |
| **Prerequisites** | Wave 1 (CI) · **D-2, D-3, D-4(G), D-4(L), D-5(L), D-6(L)** |
| **Exit** | Gates 5 and 6 |

**Testing — priority order, and it is not test count:**

1. **Seams (`N-10`).** Constructor-injected clients for `WorkoutService`,
   `NutritionService`, `WeeklyCheckinService` — one parameter each, defaulting to
   `Supabase.instance.client`. Not a behavioural refactor. **Unblocks three P1 findings
   and `saveSetLog`, the one Phase 2 case with no Dart coverage.**
2. **Failure injection.** A `failNext` flag on `InMemoryWorkoutSessionStore` turns the
   existing 30-test persistence suite into a persistence-*failure* suite for almost no
   cost, and is the prerequisite for pinning `EC-05`/`N-07`.
3. **`deno test` (EB-8).** `stripe-webhook` replayed twice asserting one credit row;
   `notify-coach-email` and `send-checkin-reminder` rejecting an unauthenticated request;
   HTML escaping of attacker-supplied fields.
4. **UI error-surface widget tests.** `ProviderScope` overrides that throw; assert an
   error card with a retry. The two Resume surfaces first.
5. **Route-table test.** Every `context.push` target resolves; auth-guarded routes
   redirect. Cheap, and it would have caught the placeholder-screen findings.
6. **Engine behaviour suite (`ENG-20`).** Zero tests currently exercise `score_exercise`,
   `build_workout`, `plan_program`, `evaluate_week`, `predict_client`,
   `assemble_weekly_review` or trace completeness.
7. **Migration replay** 000→128 against a scratch project in CI.
8. **Replica conversion (`N-06`).** 259 tests, **converted file by file, never deleted.**
   Each replica names the production symbol it mirrors; point it at the real one and
   delete the copy. Where the real symbol is unreachable, *that is the finding*, not the
   test's problem. **Deleting them lowers the count without raising the confidence.**

**Release engineering:** flavors with per-environment ids · beta defined (**D-4(L)**) ·
automated build numbers · artifact provenance (`APP_ENV` + build SHA) · iOS build chain
(REL-1) · Android release signing (ENV-10) · privacy manifest and export compliance ·
one product name and one bundle id **before the App ID is registered** · observability in
all three tiers (**D-5(L)**) · rollback per layer, rehearsed · secret and price-id
manifests committed and diffed.

---

## WAVE 9 — Manual QA Gate

| | |
|---|---|
| **Purpose** | Human QA tests the product, rather than discovering architectural defects |
| **Prerequisites** | Gates 0–5 met |
| **Exit** | Gate 6 |

**Entry is not permitted until:** every P0 is `VERIFIED_CLOSED` · every P1 is
`VERIFIED_CLOSED` or explicitly `DEFERRED` with an owner and a date · CI is green
including the live QA suites · a staging environment exists and is seed-free · every
product decision that gates a shipped surface is answered.

**Matrix — 22 surfaces × 10 conditions.** Surfaces: authentication · onboarding · PAR-Q ·
program generation · workout · set logging · swap · resume · completion · check-in ·
nutrition · AI · messaging · coach workflow · events · billing · account deletion ·
community · women's health · settings · failure/recovery · deep links.
Conditions: happy path · invalid input · network failure · persistence failure ·
authorization failure · retry · refresh · app restart · concurrent action ·
offline/poor connection.

**Standing rule for every cell:** a success state may be shown **only** when authoritative
evidence confirms the underlying operation succeeded. A tester who sees a success message
must be able to confirm the row.

---

## Dependency graph

```
                    ┌──────────────────────────────────────────┐
                    │  W1-T1  COMMIT THE TREE  (ENV-1)         │
                    │  nothing else starts until this lands    │
                    └───────────────────┬──────────────────────┘
                                        │
      ┌─────────────────┬───────────────┼───────────────┬──────────────────┐
      ▼                 ▼               ▼               ▼                  ▼
  ENV-4 default     ENV-5 harness   ENV-6 CI       mig 123 (ENV-2)    config.toml
  → dev             → QA-only       + EB-1 key      forward delta      verify_jwt
      │                 │               │               │                  │
      └─────────────────┴───────┬───────┴───────────────┘                  │
                                ▼                                          │
                    QA ledger reconciled (ENV-3) ◄─────────────────────────┘
                                │
                                ▼
              ┌─────────  WAVE 2  SECURITY REGRESSION  ─────────┐
              │  mig 124: SEC-R1 guard · SEC-R2/R3 casts        │
              │  I-MIG-03 class guard ◄── the only durable fix  │
              └───────────────────┬────────────────────────────-┘
                                  │
                                  ▼
        WAVE 3A  SCHEMA TRUTH  (columns, buckets, identity constraints)
                                  │
                                  ▼           ← H's proven ordering:
        WAVE 3B  ERROR CONTRACT     3B-0 sink → 3B-1 safety → 3B-2/3 → 3B-4
                                  │              schema BEFORE swallow removal
                                  ▼
        WAVE 3C  FABRICATION REMOVAL
                                  │
                                  ▼
        WAVE 4  CORE MEMBER JOURNEY  ◄── Q-1 Q-2 Q-3 Q-4 Q-E2
                                  │
                                  ▼
        WAVE 5  AI / INTELLIGENCE  ◄── D-1 D-4 D-8 · EB-2 EB-3 EB-4
          5.0 secrets → 5.1 vocabulary → 5.2 substrate → 5.3 RED fixes
                    → 5.4/5.5/5.6 deploy → 5.7 safety → 5.8 provenance
                                  │
        ┌─────────────────────────┼──────────────────────────┐
        ▼                         ▼                          ▼
  WAVE 6 BILLING            WAVE 7 SURFACES           WAVE 8 TESTING
  ◄── EB-5, D-K2…D-K9       ◄── Q-H*, E-*, D-3(G)     ◄── EB-8, EB-11
        └─────────────────────────┼──────────────────────────┘
                                  ▼
                          WAVE 9  MANUAL QA GATE
```

### The four required sub-graphs, stated explicitly

**Release environment → QA credentials → Edge deployment → AI validation → Billing validation → End-to-end QA**
```
ENV-1 commit ─► ENV-6 CI ─► EB-1 QA_SERVICE ─► live security suite executes
                              │
                              ├─► EB-2 secrets + deploy ─► AI validation (Wave 5)
                              └─► EB-5 Stripe QA ────────► billing validation (Wave 6)
                                                                   │
                                                     end-to-end QA (Wave 9) ◄┘
```

**Schema contract → service contract → provider contract → UI contract → behavioural test**
```
migration 126/127/128 ─► service reads/writes the real column (3A)
        ─► provider propagates instead of defaulting (3B-4)
        ─► UI renders loading / data / error+retry (3B-5)
        ─► widget test with an overridden failing provider (Wave 8)
```
*Every step is a precondition for the next. `EC-11` after `I-WRK-01` is the concrete
instance: reversing them ships a permanent visible error.*

**Security authorization → Edge Function deployment → live AI testing**
```
SEC-R1 guard restored (Wave 2)
   └─► E-04/E-05/E-01/E-02/E-10 closed (5.3)
         └─► functions deployed (5.4-5.6)
               └─► AI behaviour graded (5.6 gate: only after F-J-04 + I-NUT-01)
```

**Product decisions → implementation → QA acceptance**
```
Q-1/Q-2 ─► check-in rewire (Wave 4) ─► coach queue + AI context assertions
D-1     ─► substrate population (5.2) ─► engine returns a non-empty selection
D-4     ─► PAR-Q rejection rule (5.7) ─► high-risk member's plan is constrained
D-K1    ─► iOS purchase (6.4)        ─► Gate 4 external review
```

---

## First safe parallel batch

Per §24 of the programme brief: **do not launch parallel work merely because two findings
have different IDs.** Every item below was checked against the five parallel-safe
criteria and against the current working tree's modified-file list.

### The batch

| # | Task | Finding | Files touched | Conflicts with | Prereq | Retest |
|---|---|---|---|---|---|---|
| **1** | **Commit the tree** | ENV-1 | git index only | **everything** | none | `git status` clean for migrations; suites still 730 |
| **2** | `APP_ENV` → `dev`, prod constants out of the binary, ENV-012 inverted | ENV-4, `K-26` | `app_env.dart`, `dart_defines/*.json`, `env_config_test.dart`, `qa_environment_isolation_test.dart` | none — no other batch item reads `app_env.dart` | **1** | no-defines run resolves to dev; release build with empty `APP_ENV` fails |
| **3** | Harnesses take their target from env and refuse production | ENV-5 | `tool/live_integration_test.dart`, `tool/qa_self_guided.dart`, `tool/qa_entitlements.dart`, `harness_environment_guard_test.dart` | none | **1** (`live_integration_test.dart` is modified in-tree) | ENV-020…022 flipped from recording to asserting |
| **4** | `ci.yml` | ENV-6 | `.github/workflows/ci.yml` | none | **1** | CI green on a PR |
| **5** | `[functions.*] verify_jwt` declared per function | `E-09` | `supabase/config.toml` | none | **1** (modified in-tree) | a guard asserts every function in `supabase/functions/` has an entry |
| **6** | `.temp` untracked; seed guard refusing a non-QA ref | `LRE-34`, `REL-36` | `.gitignore`, `supabase/` scripts | none | **1** | `git ls-files supabase/.temp` empty |
| **7** | Release-mode route gate | REL-3 | `app_router.dart`, one new test | none | **1** | release-mode route table excludes both routes |
| **8** | Correct the false account-deletion claims | UIX-2 text half | `help_center_screen.dart`, `privacy_policy_screen.dart` | none | **1** | a source guard asserts neither file promises a path that does not exist |
| **9** | Leaked-password protection on QA | `R-06` | none (project setting) | none | none | Supabase advisor clean |

### Why each is safe in parallel — and why three plausible candidates are **excluded**

**Safe:** items 2–8 touch nine files between them with **zero overlap**, no shared
migration number, no shared contract, and no open decision. Item 9 touches no file at all.
Items 2 and 3 are the two halves of environment isolation and are frequently proposed as
one task — they are genuinely disjoint (`lib/core/config` vs `tool/`) and can run
concurrently, but **both must be reviewed together**, because passing one and failing the
other leaves the contamination path open.

**Excluded — migration 123 (ENV-2).** Superficially parallel: a new file, no conflicts.
It is **not** in the batch, because enumerating the semantic delta of 15 in-place-edited
migrations is a single analytical act. Split across owners, a missed delta is silent and
surfaces in production. **One owner, sequentially, after the batch.**

**Excluded — migration 124 (Wave 2).** It could technically be written concurrently with
123. It is excluded because two owners writing "the next migration" is precisely the
class of ordering hazard that produced §4.2 of the registry. **Numbers are assigned; 123
lands before 124 is written.**

**Excluded — the schema column renames (3A).** Five one-line fixes, no decisions, and the
most tempting parallel batch in the programme. They are excluded from the *first* batch
for two reasons: `known-violations.json` is a single shared file that all five must edit
(the guard fails if an entry is removed without the fix **or** fixed without the removal),
and `ai-coaching-engine/index.ts` receives three of them, so they are one task, not three.
They become the first batch of Wave 3A, sequenced behind CI so the ratchet has something
to enforce against.

### Batch exit

The batch is complete when: the tree is committed · CI runs on every push and PR · the
live security suite has executed for the first time · no build can silently reach
production · no harness can reach production · and the app no longer states something
about itself that is untrue.

**After the batch, and only after it, Wave 1's sequential spine (123 → ledger) runs, and
Wave 2 begins.**
