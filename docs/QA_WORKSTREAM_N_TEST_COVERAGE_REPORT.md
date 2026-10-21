# 12 Circle Fitness — QA Workstream N
## Test-Coverage & Regression-Gap Audit

**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Measurement window:** 13:38 – 13:55 local, on a **shared, concurrently-edited** working tree (see §13).
**Production `nxdbooufqzkpslkcogxc` was not contacted.** QA `eyqtldjqpgpljlqvpowh` was not contacted either — no credentials were available this session (see §14).

---

## 0. The question this workstream answers

Not "how many tests are there." The question is:

> **If each defect the QA programme already found were reintroduced tomorrow, would `flutter test` / `npm test` go red?**

For most of them the answer is **no** — and in four cases a test that was *written to catch exactly that defect* cannot detect it, because the defect moved one layer away from where the test looks. Those four are the substance of this report.

The audit is source-and-execution based. Every claim below was re-derived from the tree and, where it is a behavioural claim, confirmed by running the suite. Nothing is carried on the authority of a prior report; where this audit independently reproduces a prior finding, it says so, and where it could not reproduce one, it says that too.

---

## 1. Baseline test counts — measured, not quoted

Measured with the Dart JSON reporter and the Jest JSON reporter at 13:55, counting non-hidden tests only.

| Suite | Command | Total | Skipped | Failing |
|---|---|---:|---:|---:|
| Flutter | `cd apps/mobile && flutter test` | **699** | 9 | **0** |
| API unit | `npm test --workspace apps/api` | **58** | 0 | **0** |
| API e2e | `npm run test:e2e --workspace apps/api` | **6** | 0 | **0** |
| **Executable total** | | **763** | 9 | **0** |
| Live DB security | `npm run test:security` | **188 assertions** | — | **not run — no credentials** |
| Live workout SQL | `supabase db query --file supabase/tests/workout/*.sql` | **32 assertions** | — | **not run — no credentials** |
| Edge Function | *(none exist)* | **0** | — | no Deno runtime installed |

`flutter analyze`: **0 errors, 15 warnings, 156 infos.** All 15 warnings pre-date this workstream — 14 in `tool/`, 1 in production workout code (§8, N-08). *Note: `PHASE_2_WORKOUT_TEST_MATRIX.md` records "0 errors, 0 warnings"; that is no longer the measurement, whether because the scope differed or because the tree moved.*

### Reconciling 699 against the prior baseline

| Reading | Count |
|---|---:|
| Phase 2 matrix, recorded after migrations 119/120 | 591 |
| This audit's first measurement, 13:38 | **623** |
| Added concurrently by another session (Workstream K billing) at 13:46 | +29 |
| Added by this workstream (§11) | +47 |
| **This audit's final measurement, 13:55** | **699** |

The 591 → 623 delta was already in the tree when this audit started and is not attributable to it.

---

## 2. Suite composition — the number that matters more than the total

Every Flutter test was classified by **what it actually executes**.

| Class | Tests | Share | What it proves |
|---|---:|---:|---|
| **Behavioural** — imports `package:circle_fitness/…` and runs the real code | **268** | 38.3% | The product behaves as asserted |
| **Static source guards** — parses committed `.dart` / `.sql` / `.ts` as text | **172** | 24.6% | The committed source *cannot express* a known hole |
| **Replica / self-referential** — defines a copy of the logic inside the test file and asserts against the copy | **259** | **37.1%** | **Nothing about the product** |

The API suite:

| Class | Tests |
|---|---:|
| Behavioural (`ai.controller` 20, `api-config` 18, `ai-nutrition.service` 15) | **53** |
| Nest scaffold `should be defined` | **5** |
| e2e through the real application graph | **6** |

### The replica block, by file

These 259 tests import **zero** production code. Each defines its own `WorkoutSession`, `macrosFromFood`, `ScoreService` constants, `_MessageBubble`, or a Dart transcription of a TypeScript Edge Function, and asserts against that.

| File | Tests | What it actually tests |
|---|---:|---|
| `unit/formatters_test.dart` | 34 | local copies of `_formatTime`, `coachButtonLabel` |
| `unit/spec_marketplace_test.dart` | 31 | a literal coach fixture + local filter functions |
| `unit/progress_helpers_test.dart` | 30 | "Replicated helpers" — its own header says so |
| `unit/score_logic_test.dart` | 30 | "replicate the formulas from score_service.dart" |
| `unit/spec_community_challenge_test.dart` | 26 | local `habitPoints`, `rankLeaderboard` |
| `unit/spec_nutrition_logic_test.dart` | 24 | local `macrosFromFood` |
| `unit/spec_security_guards_test.dart` | 18 | a local `guardedQuery` that no service calls |
| `unit/spec_score_compliance_test.dart` | 17 | mirrored constants |
| `unit/spec_workout_logic_test.dart` | 17 | a `WorkoutSession` class defined in the test file |
| `unit/edge_function_logic_test.dart` | 13 | a Dart transcription of `send-checkin-reminder/index.ts` |
| `widget/message_bubble_test.dart` | 11 | `TestMessageBubble`, a local copy |
| `widget/filter_chip_test.dart` | 7 | `TestFilterChip`, a local copy |
| `widget_test.dart` | 1 | `expect(true, isTrue)` |

These files are honest about it — most say "replicated" or "mirrors" in the header. They were a reasonable stopgap when the services had no seams. But **37% of the Flutter suite is green regardless of what the product does**, and that is the single largest source of false confidence in the tree. `score_service.dart` could be deleted and `score_logic_test.dart` would still pass.

**They are not deleted or weakened by this workstream** (see the standing rules). §10 records the migration path.

---

## 3. Domain coverage matrix

Legend — **B** behavioural · **S** static-only · **R** replica (no product code) · **L** live-only (needs credentials, not run) · **—** none.

| Domain | Existing | Meaningful behavioural | Static-only | Missing | Highest-risk uncovered behaviour | Recommended test | Addable independently? |
|---|---|---|---|---|---|---|---|
| **Workout — set identity & contract** | 129 B + 8 S | Yes, strongest in the tree. `workout_domain_contract` (32), `workout_set_identity` (38), `workout_restoration` (33), `workout_set_immutability` (21) | migration text pins in `workout_set_ordering` | `saveSetLog` itself (no seam — `WorkoutService` resolves `Supabase.instance.client` directly) | An `UPDATE`-then-`INSERT` upsert that regresses to the 051 ordinal key. Enforced by migration 120's trigger, unverifiable in Dart | Inject the Postgrest client into `WorkoutService`, then a fake-transport test asserting the upsert conflict target | **No** — needs a seam (production change) |
| **Workout — session state machine** | 30 B + 15 B/S | Yes. `workout_session_persistence` covers WKT-100…109 against a real store double | `workout_active_session_authority` pins migration 108 | **Persistence *failure*.** `InMemoryWorkoutSessionStore` has no failure injection — nothing ever throws | `_completeWorkout` swallows a `completeSession` failure and shows the celebration anyway (EC-05, still live at `active_workout_screen.dart:613`) | A failing store double + a controller-level test that the celebration is withheld | **No** — the exit/finish decision has no testable seam (Phase 2 recorded this gap) |
| **Workout — presentation** | 11 B (widget) | `set_tracker_row` (7), `active_workout_hydration` (4) | — | The 1900-line Workout Zone; End Workout dialog | Error arms on `train_hub_screen` (§7, N-02) | Extract the exit decision into a controller and pin it | Partly — the static half **was** added (§11) |
| **Onboarding / intake / PAR-Q** | **0 → 24 B** (added §11) | Now yes: risk engine, both serializers, consent timestamp | — | The screen's fail-open branch (`intake_flow_screen.dart:216`) | CON-02: `onboarding_complete = true` written after the profile save throws, discarding PAR-Q, allergies and consent | A widget/controller test with a failing profile write asserting the flag stays false | Screen half **no** (needs a seam); domain half **done** |
| **Nutrition** | 24 R + 13 B (AI transport only) | Only `ai_nutrition_client` (13) — and that tests the *client transport*, not nutrition | — | **All of `nutrition_service.dart`** | CON-09/E-NUT-01: `lookupBarcode` returns per-100 g values under unqualified keys `{calories, protein, …}`; a consumer logs 100 g as one serving | Behavioural test of the barcode mapper, once the service takes an injected client | **No** — `nutrition_service.dart` binds `Supabase.instance.client` and `Dio` internally |
| **Nutrition — AI safety inputs** | 0 | — | — | Everything | CON-08/E-NUT-05: no allergen/restriction guard exists anywhere. `NUTRITION_SYSTEM_PROMPT` does not mention allergies; `AiNutritionService.reply()` performs no post-generation check | A Jest test: a request stating an allergen, a stubbed model response containing it, assert the API **rejects** | **No** — there is no guard to test. The test is written *with* the guard |
| **Check-in** | 0 B; 1 S (EC-G2 allowlist); 27 L | — | The phantom-table allowlist naming `checkins` | Everything behavioural | E-CHK-01: the only reachable check-in surface writes to a table no migration creates; every caller swallows the 404 | Blocked on Q-1 (daily vs. weekly). Once resolved: a service test that an unreachable table surfaces an error | **No** — blocked on a product decision |
| **Women's health** | 16 B | Yes — `cycle_phase_logic_test` is the model this audit recommends elsewhere: characterization, `DEFECT:`-tagged, fails-when-fixed | — | The write paths (`cycle_settings` is write-dead, F-05); symptom-sheet overwrite (F-03) | F-09: no staleness bound — a 400-day-old log still reports a confident current phase. **Pinned**, so a fix will be deliberate | Already pinned. Add write-path tests when the service gets a seam | Calculation half **done**; write half **no** |
| **Security / RLS / authorization** | 103 S + 188 L | The live suite is excellent — 188 assertions over real REST with real JWTs, written to fail pre-remediation | `profile_access_boundary` (55), `phase1_security_boundary` (48) parse migrations 100–122 as text | **Execution.** The live half needs `QA_SERVICE`, which does not exist in this environment, and runs in no CI | Nothing proves the policies, grants, triggers and PostgREST *compose*. A static assertion that migration 116 contains a `REVOKE` is not the same as anon being refused | Run `npm run test:security` in CI against QA with a scoped service key | **No** — needs credentials + CI (§10, N-01) |
| **AI subject scoping** | 6 S (added §11) + 31 L | — | `SEC-024` (7 tests) pins migration 116's text; **N** adds `SEC-031` pinning that `ai-coaching-engine` derives `p_uid` from the verified token, never from the request body | `ai_adjust_nutrition` / `ai_detect_patterns` are **not** in SEC-024's named list, though they are two of SEC-04's seven functions | A caller naming an arbitrary `p_subject` and being refused — provable only live | Extend `d04-rpc-execution.mjs` to cover both, and run it | Static half **done**; live half **no** |
| **Edge Functions** | **0** | — | — | **All 19 functions** | E-01/E-02: `notify-coach-email` and `send-checkin-reminder` have **no authentication** — anon-triggered mass email with unescaped attacker HTML | `deno test` per function: signature verification, auth rejection, HTML escaping, idempotency | **No** — Deno is not installed in this environment |
| **Billing / webhook idempotency** | 20 S + 9 skipped (added concurrently by Workstream K) | — | Tier ladder, capacity limits, commission split, parsed from committed TS/SQL | **Behavioural.** No test replays a webhook | E-08: `stripe-webhook/index.ts:130` inserts `client_session_credits` with no event-id dedupe. Stripe retries on any non-2xx; a retry **double-grants** paid sessions | A Deno test replaying the same `checkout.session.completed` twice and asserting one credit row | **No** — needs Deno + an idempotency key that does not exist yet |
| **Environment / release guards** | 27 B/S + 8 S (added §11) | `env_config` (20) drives the real `AppEnv` resolver | `qa_environment_isolation` (7) parses `dart_defines/*.json`; **N** adds `ENV-020…022` for the harnesses | The guards covered the *app build* and nothing else | **N-05**: all three `tool/` harnesses hardcode the **production** ref and write; `integration_test/service_logic_test.dart` resolves through `AppEnv`, which defaults to prod, and its own instructions pass no defines file | Ratchet added (§11); the fix is to repoint them | **Yes — done** |
| **Navigation** | **0** | — | — | Everything | No test asserts a route resolves, a guard redirects an unauthenticated user, or a deep link lands. E-CHK-05/06 record placeholder screens on live routes | A router table test: every `context.push` target exists in the route table | **Yes** — `go_router` configuration is inspectable without a device |
| **Data contracts** | 32 B + 12 SQL(L) | `workout_domain_contract` (32) is the reference — six malformed shapes refused, `rest`/`rest_seconds` contradiction refused | migration 119's `CHECK` pinned at source | Every contract except `program_workouts.exercises` | CON-03: `dietary_restrictions` has two serializers emitting different Dart types. **Now pinned** (§11) | Done for intake; barcode and check-in contracts still open | Intake **yes — done**; others no |
| **Error paths** | 13 S + 9 S (added §11) | — | `error_contract_guard` (13) pins provider-layer propagation | **The presentation layer** — see §7, N-03 | The Resume affordance hides itself on a failed lookup, the exact defect the restoration work exists to prevent | Widget tests with an overridden failing provider asserting an error card renders | Ratchet **yes — done**; widget tests need `ProviderScope` overrides — feasible, larger |
| **State machines** | 30 B | Yes — WKT-100…109 plus migration 120's terminal-status trigger | — | Failure transitions | Same as persistence-failure above | Failing-store double | **No** |
| **Safety inputs** | 24 B (added §11) + 16 B | PAR-Q risk engine and allergy payloads now pinned; cycle inputs pinned | `SEC-023` pins `derive_parq_risk` as server authority | **Consumption.** CON-04: nothing reads `risk_level` as a training constraint | A `build_workout` test proving a high-risk PAR-Q constrains selection | **No** — blocked on Q-4/A-5, a clinical product decision |
| **Retry / idempotency** | **0** | — | — | Everything | E-08 (above); also no test that a retried `saveSetLog` is idempotent under migration 120's identity key | Webhook replay test; duplicate-set-log insert test | **No** — Deno / live DB |
| **Empty / null / malformed data** | 48 B | Genuinely good — WKT-201's six malformed shapes; `cycle_phase` null and future-dated input; `api-config` missing-settings | — | Malformed data from the *network* (barcode JSON, AI responses) | `lookupBarcode` returns `null` for every failure mode — not-found, network error, and malformed JSON are one answer | Fixture-driven mapper tests | **No** — no seam |
| **Concurrent writes** | 10 B (simulated) | `InMemoryWorkoutSessionStore` reproduces the one-active-session unique index; WKT-105 exercises it | — | Real concurrency | Two devices completing the same session; a webhook racing a client write | Live DB test with parallel connections | **No** — needs a live DB |
| **Migration regression** | 49 S + 32 L | — | `SEC-027` is the strongest guard in the tree: it finds the *latest* migration redefining `generate_client_plan()` and asserts it still applies `plan_day_titles` — the check whose absence let 077 silently revert 052 | Migration **replay**. Nothing asserts 000→122 applies cleanly to an empty database | The 15 in-place-modified historical migrations (HYG-02) have no test that the edited replay still produces the schema the forward migrations assume | `supabase db reset` against a scratch project in CI, then the contract SQL | **No** — needs a project + CI |

---

## 4. The 21 audited categories, scored

| # | Category | Verdict |
|---|---|---|
| 1 | Flutter unit | **Strong but polarised** — 268 behavioural against 259 replica |
| 2 | Flutter widget | **Weak** — 29 tests, 18 of them replicas of private widgets; 11 real |
| 3 | Flutter integration | **Present and dangerous** — 1 file, no CI, defaults to **production** (N-05) |
| 4 | API Jest | **Good where it exists** — 53 substantive + 6 e2e; auth/users services are scaffolds only |
| 5 | Edge Function | **Absent** — 19 functions, 0 tests, no runtime |
| 6 | SQL / security | **Excellent and unexecuted** — 188 live assertions, no credentials, no CI |
| 7 | Migration regression | **Partial** — source-level discipline guarded; replay unguarded |
| 8 | AI behavioural | **Transport only** — the client's HTTP contract is tested; no model-output guard exists to test |
| 9 | Billing | **Static only, added mid-audit** — 20 active + 9 skipped; zero behavioural |
| 10 | Environment / release | **Good for builds, blind for harnesses** — closed by this workstream |
| 11 | Navigation | **Absent** |
| 12 | Data contract | **Excellent for one contract**, absent for the rest |
| 13 | Error paths | **Half-covered — and the covered half hides the uncovered half** (N-02, N-03) |
| 14 | State machine | **Strong for the happy path**, absent for failure transitions |
| 15 | Authorization | **Best-in-tree, and never runs** |
| 16 | Safety inputs | **Inputs now pinned; consumption absent** |
| 17 | Persistence failure | **Absent** — no failure injection exists anywhere |
| 18 | Retry / idempotency | **Absent** |
| 19 | Empty / null / malformed | **Good** in the workout and config domains, absent elsewhere |
| 20 | Concurrent write | **Simulated only** |
| 21 | Regression for known defects | **See §5** |

---

## 5. Critical regression matrix

For each item the prompt names: would the suite go red if the defect returned?

| Defect | Guard that exists | Would it catch a reintroduction? | Verdict |
|---|---|---|---|
| **Phase 1 P0 — SEC-01** `coach_client_relationships` no RLS | `SEC-020` (static, migration 113 text) + `d01` (41 live assertions) | Static: **yes**, if the regression is an edit to 113. **No**, if a *new* migration disables RLS — `SEC-027` checks post-118 migrations for `DISABLE ROW LEVEL SECURITY`, so partially. Live: yes, and it never runs | **Partial** |
| **Phase 1 P0 — SEC-02** role self-escalation | `SEC-022` + `d02` (33 live) | Same shape | **Partial** |
| **Phase 1 P0 — SEC-03** `weekly_checkins` no RLS | `SEC-021` + `d03` (27 live) | Same shape | **Partial** |
| **SEC-04** RPC subject scoping | `SEC-024` (7 static) + `d04` (31 live) + **`SEC-031`** (new) | `SEC-024` names 5 of the 7 functions; `ai_adjust_nutrition` and `ai_detect_patterns` are **not** named. `SEC-031` now pins that the Edge caller derives the subject from the token | **Improved, still partial** |
| **SEC-05** anon EXECUTE on functions | `SEC-024` static + `d04`/`d06` live | Static asserts the `REVOKE` text is present. It cannot assert the database's actual grant state | **Insufficient alone** |
| **Phase 2 workout contract** — WRK-03/04/05 | `WKT-201/202` (9 behavioural) + migration 119 `CHECK` + 20 live assertions | **Yes.** This is the best regression coverage in the repo: a rep range, a `rest`/`rest_seconds` contradiction, and six malformed shapes are all refused by real codec code | **Yes** |
| **Phase 2 workout contract** — WRK-01/02 set identity | `WKT-203/204/205` (14 behavioural) + migration 120 triggers | Yes at the domain layer. **No** at `saveSetLog`, which has no seam — the DB trigger is the only guard | **Yes (domain) / DB-only (service)** |
| **Error contract — WRK-07 provider swallow** | `EC-G1` (6 static) | **No.** `EC-G1` asserts `workout_provider.dart` contains no `catch`. The defect now lives in the *screens*, which `EC-G1` does not read. Both Resume surfaces reproduce it today | **INSUFFICIENT — see N-02** |
| **Error contract — the swallow ratchet** | `EC-G5` (baseline 234) | **No** for the presentation layer. Its regex matches `catch` blocks; Riverpod swallows via `error: (_,__) =>` and `.valueOrNull`, which contain no `catch`. 16 + 134 sites are invisible to it | **INSUFFICIENT — see N-03** |
| **Check-in failures — CON-01 / E-CHK-01** | `EC-G2` phantom-table allowlist | **Partially.** It stops a *new* phantom table. It cannot detect that the existing feature reports success-shaped failure, and the allowlist makes the current breakage permanent-looking | **Partial** |
| **Nutrition safety inputs — CON-08 / E-NUT-05** | none | **No.** No guard exists in the client, the API or the Edge layer. `NUTRITION_SYSTEM_PROMPT` does not mention allergies | **NONE** |
| **Nutrition — allergy data reaching the payload** | **`INT-302`** (new, 4 tests) | Yes — allergies are now pinned into both write paths, which is the precondition any future guard depends on | **New** |
| **Women's-health calculations** | `cycle_phase_logic_test` (16 behavioural) | **Yes**, and unusually well: F-08…F-14 are each pinned as `DEFECT:` characterization, so a fix must be deliberate and a silent regression is impossible | **Yes** |
| **AI subject scoping (client side)** | `AI-002` (3 behavioural) | Yes for the mobile client — it refuses to send without a session and never sends an Anthropic header | **Yes** |
| **Billing / webhook idempotency — E-08** | Workstream K's static guards (concurrent) | **No.** No test replays a webhook. A retry still double-grants `client_session_credits` | **NONE** |
| **Release / environment contamination (app build)** | `ENV-001…006`, `ENV-010…012` (27) | **Yes** — the strongest environment guarding in the tree | **Yes** |
| **Release / environment contamination (harnesses)** | **`ENV-020…022`** (new, 8 tests) | Now ratcheted. The existing contamination is recorded, not fixed | **New — N-05** |
| **UI / backend reachability (Flutter)** | `SEC-024` "every RPC the app calls is on the allowlist" | **Yes** for `apps/mobile/lib` | **Yes** |
| **UI / backend reachability (Edge)** | **`SEC-030`** (new, 3 tests) | The Flutter-only scan missed `enrich-exercise` → `seed_exercise`, which is genuinely unreachable today. Now ratcheted | **INSUFFICIENT before — see N-04** |

---

## 6. Weak / false-confidence tests

| Test set | Tests | Why it is false confidence |
|---|---:|---|
| The replica block (§2) | **259** | Executes no product code. Green whatever the app does |
| Nest scaffold specs | 5 | `expect(controller).toBeDefined()` |
| `widget_test.dart` | 1 | `expect(true, isTrue)` |
| `spec_security_guards_test.dart` | 18 | Named "security guards"; tests a `guardedQuery` helper defined in the test file that no service calls. The name implies authorization coverage that does not exist |
| `edge_function_logic_test.dart` | 13 | A Dart transcription of TypeScript. It can pass while the deployed function is broken, and the function it mirrors (`send-checkin-reminder`) has **no authentication at all** — E-02, which the test does not examine |
| Skipped "open specs" | 9 | Legitimate as documentation and correctly kept out of the pass count, but they are **not coverage**. Reporting them inside a 699 total overstates the suite by 1.3% |

`spec_security_guards_test.dart` is the one worth calling out by name. Its own header is honest ("Supabase RLS cannot be unit-tested without a real DB connection") — but the file name and 18 green ticks read, on a dashboard, as security coverage.

---

## 7. Insufficient tests — written for the defect, unable to detect it

These are the four findings that justify this workstream.

### N-02 · [P1] WRK-07 is fixed at the provider and live at the screen — and `EC-G1` cannot tell

`workout_provider.dart:404-408` now propagates, with a comment stating the intent verbatim:

> *"A failed lookup returned as `null` is indistinguishable from 'there is nothing to resume', and hiding the Resume affordance from a client who is mid-workout is the exact failure the restoration work exists to prevent. **Surfaces here become an error state with a retry.**"*

Both surfaces that read it do the opposite:

- [`train_hub_screen.dart:169`](../apps/mobile/lib/features/workout/presentation/train_hub_screen.dart#L169) — `error: (_, __) => const SizedBox.shrink()`. The error arm and the "no session" arm render the identical widget.
- [`resume_workout_banner.dart:48`](../apps/mobile/lib/features/workout/presentation/resume_workout_banner.dart#L48) — `ref.watch(activeSessionProvider).valueOrNull`, then `if (session == null) return const SizedBox.shrink()`. Error-null and no-session-null take the same branch.

`EC-G1`'s six tests assert that `workout_provider.dart` contains no `catch` and that three named service methods propagate. All six pass. **The user-visible defect is unchanged from before the fix.** `workout_list_screen.dart:255` is the one surface that honours the contract — `_AssignedErrorCard`, "Your program could not be loaded", `Try again`.

Also affected, same shape: `train_hub_screen.dart:320` (personal records), `coach_client_workout_screen.dart:219,251`, and — corroborating E-14 — `manage_subscription_screen.dart:206,249`, where a Stripe failure renders as a real balance.

### N-03 · [P1] The `EC-G5` ratchet is structurally blind to the presentation layer

`EC-G5` counts `catch`-to-empty-value sites and holds them at 234. Riverpod's swallow contains no `catch`:

| Mechanism | Sites | Counted by EC-G5 |
|---|---:|---|
| `error: (…) => SizedBox…` | **16** | no |
| `.valueOrNull` | **134** | no |

Both numbers were measured by this audit's own scanner and are now ratcheted (§11, `EC-G7`/`EC-G8`). `.valueOrNull` is legitimate on a provider that cannot fail and is RC-C on one that does I/O — indistinguishable at the call site, which is the argument for a typed error state rather than a longer allowlist.

### N-04 · [P1] The reachability guard scans Flutter only, and the gap it left is already a live defect

`SEC-024`'s last test says it exists to *"stop a new `.rpc()` call site silently 404ing in production."* It scans `apps/mobile/lib`. Edge Functions also call RPCs — and one calls with the **end user's JWT**:

`enrich-exercise/index.ts:156` calls `seed_exercise` on `userDb`, a client built from the caller's `Authorization` header — so it runs as `authenticated`. Migration 116 revokes `EXECUTE … FROM authenticated` schema-wide (line 430) and grants back only an allowlist. **`seed_exercise` is not on that allowlist.** Every call returns 500 "Failed to save enrichment", for coaches and admins alike.

Independently derived here, and it corroborates Workstream D's E-03. The other three Edge RPC calls (`ai_detect_patterns`, `ai_adjust_nutrition`, `snapshot_exercise_content`) use service-role clients and are correctly unaffected — the revokes deliberately spare `service_role`.

### N-05 · [P1] Every write-capable test harness targets production

| Harness | Target | Writes |
|---|---|---|
| `tool/live_integration_test.dart:15` | hardcoded prod ref | POST/PATCH/DELETE on `workout_sessions`, `nutrition_logs`, `daily_scores`, `weekly_checkins`, `community_posts` |
| `tool/qa_self_guided.dart:22` | hardcoded prod ref | PATCH `user_profiles`, calls `generate_client_plan` |
| `tool/qa_entitlements.dart:27` | hardcoded prod ref | service-role DELETE on `subscriptions` and `coach_client_relationships` |
| `integration_test/service_logic_test.dart:42` | `AppConstants.supabaseUrl` → `AppEnv.current` | writes; **`AppEnv` defaults to prod** and the file's own run instructions pass no `--dart-define-from-file` |

Two of these are *named* `qa_*` and point at production. `env_config_test.dart` ENV-001 pins the default (`APP_ENV defaults to prod when no define file is used`) and `qa_environment_isolation_test.dart` proves a *build* resolves to one project — neither looks at `tool/` or `integration_test/`. The gap is exactly between the two guards.

No test in this tree contacted any project, and this audit did not run any of these harnesses.

---

## 8. Additional defects surfaced while auditing

| ID | Sev | Finding |
|---|---|---|
| **N-01** | **P0 (process)** | **There is no CI.** `.github/workflows/` contains one file, `supabase-keepalive.yml`, a daily read-only ping. No workflow runs `flutter test`, `npm test`, `npm run test:e2e` or `npm run test:security` on any push or PR. Every "standing guard" in this repo — `SEC-020…027`, `EC-G1…G5`, `ENV-010…012`, and the ones added here — protects only a developer who happens to run the suite locally. A live suite nobody runs protects nothing; that argument appears in `supabase/tests/security/README.md` itself, applied to the live suite. It applies to all of them. **This is the highest-leverage single change in the report.** |
| **N-06** | P2 | 259 tests (37% of the Flutter suite) execute no production code (§2) |
| **N-07** | P1 | **EC-05 is still live.** `active_workout_screen.dart:613` wraps `completeSession` in `catch (_) {}` and shows `_WorkoutCompleteDialog` regardless. `logWorkout` at line 608 is awaited unguarded. `EC-G1` does not read this file, so the guard passes. No test covers it, and there is no seam to add one |
| **N-08** | P3 | `active_workout_screen.dart:1212` — `_currentSetId == null \|\| we.setById(_currentSetId!) != null`, where `_currentSetId` is `String` initialised to `''` (line 152). The null arm is dead; the analyzer flags it. Effect: after an exercise swap performed **before any set is touched**, the cursor is not re-pointed and no cursor is saved. Low impact, but it is a live logic slip in a Phase-2 swap path, and `WKT-204`'s cursor test operates on domain objects so it cannot reach it. The likely intent is `_currentSetId.isEmpty`. **Not fixed here** — this workstream adds tests, not production changes |
| **N-09** | P1 | 19 Edge Functions, 0 tests, and **Deno is not installed** in this environment, so no Edge test could be written *and verified* today. Adding an unverified test file would be the same mistake as the replica block |
| **N-10** | P1 | `nutrition_service.dart`, `checkin_service.dart` and `weekly_checkin_service.dart` bind `Supabase.instance.client` internally. Zero behavioural coverage is possible for any of them without a seam. Three P1 findings (E-NUT-01, E-NUT-03, E-CHK-01) sit behind that one structural fact |

---

## 9. Missing-coverage register

Ordered by risk × addability.

| # | Gap | Risk | Blocked by |
|---:|---|---|---|
| 1 | No CI runs any suite | **Critical** | nothing — a workflow file |
| 2 | Live security suite (188 assertions) never executes | **Critical** | a scoped QA service key in CI secrets |
| 3 | Webhook idempotency (E-08) — retries double-grant paid sessions | High | Deno + an idempotency key |
| 4 | Unauthenticated Edge Functions (E-01, E-02) | High | Deno |
| 5 | Nutrition AI has no allergen guard to test | High | the guard does not exist (product/eng work) |
| 6 | Persistence-failure paths (EC-05, EC-12, N-07) | High | failure injection + a seam |
| 7 | Nutrition service behaviour (barcode units, past-date logging) | High | a seam in `nutrition_service.dart` |
| 8 | Check-in end to end | High | Q-1, a product decision |
| 9 | Migration replay 000→122 against an empty database | Medium | a scratch project + CI |
| 10 | Navigation / route reachability | Medium | nothing — `go_router` config is inspectable |
| 11 | PAR-Q risk consumed as a training constraint | Medium | Q-4/A-5, a clinical decision |
| 12 | Real concurrent writes | Medium | a live DB |
| 13 | API auth/users services (scaffolds only) | Medium | nothing — they are plain Nest providers |
| 14 | Women's-health write paths | Medium | a seam |

---

## 10. Recommended tests, prioritised

**R-1 — a CI workflow.** One file. `flutter analyze && flutter test`, `npm run test:api`, and — gated on a repository secret — `npm run test:security` against QA. Until this exists, every other recommendation compounds at zero interest. *(Not added here: creating a workflow that runs against QA is an operational decision with credential handling attached, and the standing rules confine this workstream to tests.)*

**R-2 — a `deno test` suite for the payment and email functions.** Minimum: `stripe-webhook` replayed twice asserting one credit row; `notify-coach-email` and `send-checkin-reminder` rejecting an unauthenticated request; HTML escaping of attacker-supplied fields. Needs Deno installed.

**R-3 — widget tests for the error surfaces.** `ProviderScope(overrides: [activeSessionProvider.overrideWith((_) => throw …)])` and assert an error card with a retry renders. Feasible today; the two Resume surfaces are the first two.

**R-4 — failure injection in `InMemoryWorkoutSessionStore`.** A `failNext` flag turns the existing 30-test persistence suite into a persistence-*failure* suite for almost no cost, and is the prerequisite for pinning EC-05/N-07.

**R-5 — seams for `WorkoutService`, `NutritionService`, `WeeklyCheckinService`.** Constructor-injected client, defaulting to `Supabase.instance.client`. Not a refactor of behaviour — one parameter each. It unblocks register items 6, 7 and 8, and `saveSetLog`, the one Phase 2 case with no Dart coverage.

**R-6 — a route-table test.** Every `context.push('/x')` target resolves; auth-guarded routes redirect. Cheap, and it would have caught the placeholder-screen findings (E-CHK-05/06).

**R-7 — retire the replica block, file by file.** Each replica names the production symbol it mirrors. Point it at the real one and delete the copy. Where the real one is unreachable (private methods in 1900-line screens), that is the finding, not the test's problem. **Do this by conversion, never by deletion** — deleting them lowers the count without raising the confidence.

**R-8 — extend `SEC-024`'s allowlist scan to `supabase/functions`.** Superseded by `SEC-030` below, but the two should eventually merge so there is one reachability check with one allowlist.

---

## 11. Tests added by this workstream

Four files, 47 tests, all passing, all test-only. No production source, migration, seed or configuration file was modified. No existing test was weakened, skipped or deleted.

| File | Tests | Closes |
|---|---:|---|
| `apps/mobile/test/unit/intake_contract_test.dart` | **24** | The onboarding domain's total absence of coverage |
| `apps/mobile/test/unit/ui_error_surface_guard_test.dart` | **9** | N-02, N-03 — the presentation half of the error contract |
| `apps/mobile/test/unit/harness_environment_guard_test.dart` | **8** | N-05 — production contact from test harnesses |
| `apps/mobile/test/unit/backend_reachability_guard_test.dart` | **6** | N-04 — reachability for non-Flutter callers |

### `intake_contract_test.dart` — INT-300 … INT-305

`IntakeData` has **zero imports** — pure Dart — so the serializers and the risk engine were directly testable all along. This is the only domain in the audit where a P1-parent finding had both no coverage and no obstacle to coverage.

Characterization tests in the idiom of `cycle_phase_logic_test.dart`: assertions that pin behaviour the reports classify as defective are tagged `DEFECT:` and are expected to flip when remediation lands.

- **INT-300** (7) — PAR-Q risk. High risk is exactly Q1/Q2/Q3/Q4/Q7; pregnancy, heart disease and hypertension raise risk without a PAR-Q yes; `riskFlags` ordering; an injury with no named location produces no `active_injuries` flag. Plus `DEFECT CON-02`: the whole `risk_*` block is omitted from the per-step save unless a PAR-Q question was answered.
- **INT-301** (4) — **CON-03 pinned.** `toSupabasePartial` emits `List<String>`, `toSupabase` emits `String`, for the same column. And a demonstrable consequence: a restriction containing a comma (`'no shellfish, no crab'`) survives the array path and is split in two by the string path.
- **INT-302** (4) — **safety inputs.** `food_allergies` is carried by both write paths and is not split on its commas. This is the precondition any future allergen guard (CON-08/E-NUT-05) depends on, pinned before the guard is built rather than after.
- **INT-303** (2) — **CON-02 pinned.** `toSupabase()` on an entirely empty intake still returns `onboarding_complete: true`. The per-step payload correctly claims only its step.
- **INT-304** (4) — **CON-06 pinned.** `consent_date` carries no zone marker and `DateTime.parse(...).isUtc` is false, on both write paths. `date_of_birth` is correctly a plain date, as the control.
- **INT-305** (3) — the blast radius: five comma-joined columns, with `activities` as the control that both paths already send as a real array. A medical condition containing a comma does not survive a round trip.

### `ui_error_surface_guard_test.dart` — EC-G6 … EC-G8

- **EC-G6** (5) — the two Resume surfaces pinned **by name** with the finding attached, plus the two that do it right (`workout_list_screen`'s `_AssignedErrorCard`, `active_workout_screen`'s restoration retry) so a regression in the good half is caught too. Each defect test carries: *"if this now fails because the arm renders an error state with a retry, delete this test — the finding is closed."*
- **EC-G7** (2) — silent-error-branch ratchet at the measured baseline **16**, plus a named list of the workout surfaces so fixing one is visible rather than absorbed by the count.
- **EC-G8** (2) — `.valueOrNull` ratchet at the measured baseline **134**, plus a named check that no *new* surface collapses an `activeSessionProvider` error to null.

Both ratchets are shrinking allowlists in the shape Workstream B established, and print the offending file:line on failure.

### `harness_environment_guard_test.dart` — ENV-020 … ENV-022

- **ENV-020** (3) — the set of prod-targeting harnesses under `tool/` and `integration_test/` has not grown; each recorded entry is genuinely write-capable; **no harness embeds a service-role key** (the line that must never be crossed).
- **ENV-021** (3) — the in-app harness resolves through `AppEnv` rather than a literal, and `DEFECT:` — it writes, `AppEnv` defaults to prod, and its own instructions pass no defines file.
- **ENV-022** (2) — only `lib/core/config/app_env.dart` may name either project ref in `lib/`; the keep-alive workflow stays a read-only GET with no service-role key.

### `backend_reachability_guard_test.dart` — SEC-030 … SEC-031

- **SEC-030** (3) — parses migration 116's allowlist, scans every `.rpc()` in `supabase/functions`, resolves the **caller's role** per call site (service-role clients are correctly exempt — the revokes spare `service_role` deliberately), and ratchets the unreachable set against `{seed_exercise}`. The service-role exemption is itself pinned, so a call site flipping to a user client cannot silently start hiding a break.
- **SEC-031** (3) — `ai-coaching-engine` derives `p_uid` from `.auth.getUser()` on the caller's own JWT, and a subject uuid is never read off the request body. These are the two SEC-04 functions `SEC-024` does not name, reached through the one path that can call them.

---

## 12. Test results

```
apps/mobile   flutter analyze   0 errors · 15 warnings · 156 infos   (all pre-existing)
apps/mobile   flutter test      699 passed · 9 skipped · 0 failed
apps/api      npm test          58 passed · 0 failed   (8 suites)
apps/api      npm run test:e2e   6 passed · 0 failed   (2 suites)
```

The 47 tests added by this workstream:

```
test/unit/intake_contract_test.dart              24 passed
test/unit/ui_error_surface_guard_test.dart        9 passed
test/unit/harness_environment_guard_test.dart     8 passed
test/unit/backend_reachability_guard_test.dart    6 passed
```

None of the new files produce an analyzer diagnostic. The suite was green before this workstream and is green after it; the delta is 652 → 699 with the concurrent Workstream K addition included.

**Not run, and why:**

| Suite | Reason |
|---|---|
| `npm run test:security` (188 live assertions) | `QA_SERVICE` is unset; `.env` and `.env.local` are both zero bytes; no `QA_*` variable exists in the environment. The harness also refuses to run against the production ref by design, so there was no way to run it wrongly |
| `supabase/tests/workout/*.sql` (32 live assertions) | Same — requires a linked project and credentials |
| `deno test` | Deno is not installed |
| `tool/*.dart`, `integration_test/*.dart` | **Deliberately not run.** All four target production (N-05) and all four write |

---

## 13. Working-tree interaction

The tree is shared and was **actively edited by another session during this audit**. That is recorded rather than smoothed over, because it affects the numbers.

| Time | Event |
|---|---|
| 13:38 | Audit began. `git status`: 50 modified, untracked test files and docs as listed in the Phase 0–2 record. Flutter suite measured at **623** |
| 13:46 | `apps/mobile/test/unit/billing_entitlement_contract_test.dart` appeared — **not created by this workstream**. 29 tests (20 active, 9 skipped), Workstream K |
| 13:51 | `docs/QA_WORKSTREAM_L_RELEASE_ENVIRONMENT_REPORT.md` appeared — not created by this workstream |
| 13:55 | Final measurement: **699**. `623 + 29 (K) + 47 (N) = 699` ✓ |

Consequences, stated plainly:

- The billing row in §3 and §5 reflects the tree **as of 13:55**. Workstream K's file did not exist when this audit's billing gap analysis began, and the analysis was updated rather than left stale. Its 9 skipped tests are counted as skipped, not as coverage.
- `docs/QA_WORKSTREAM_K_BILLING_ENTITLEMENT_REPORT.md` is referenced by that test file but **is not in the tree** at the time of writing — presumably still being written. This report does not cite it.
- A later reader re-running `flutter test` may see a different total. The composition analysis in §2 is a snapshot of 699.

**What this workstream did to the tree:** added four files under `apps/mobile/test/unit/` and this document. Nothing else. Verified after the fact: the modified-file count is unchanged at 50, nothing is staged, nothing was deleted, renamed or reverted, and the 15 in-place-edited historical migrations and migrations 113–122 are untouched. No `git` command other than `status`, `diff` and `branch` was run.

---

## 14. Production-contact statement

**No production system was contacted by this workstream, by any means, at any point.**

- Production project `nxdbooufqzkpslkcogxc` — **not contacted.** It is named in this document, in four existing test files and in `lib/core/config/app_env.dart` as a string; no request was issued to it.
- QA project `eyqtldjqpgpljlqvpowh` — **not contacted.** No credentials were available (`.env` and `.env.local` are zero bytes; no `QA_URL`/`QA_ANON`/`QA_SERVICE` in the environment), so neither the live security suite nor the live workout SQL probes were run.
- Stripe, Anthropic, OpenFoodFacts and every other third-party service — **not contacted.** The API's Anthropic tests use a stub transport; the mobile AI tests use a stubbed HTTP client.
- `tool/live_integration_test.dart`, `tool/qa_self_guided.dart`, `tool/qa_entitlements.dart` and `integration_test/service_logic_test.dart` — **deliberately not executed**, precisely because they target production and write (N-05). Discovering that is a finding of this audit, not a consequence of running them.
- Every test added by this workstream reads committed source from disk or runs pure Dart. None opens a socket. `ENV-020`'s third assertion exists specifically to keep it that way.
- No migration was applied anywhere. Migrations 113–122 were read as text and are otherwise untouched.

---

## 15. What this audit did not do

- **Did not fix any production defect.** N-02, N-04, N-05, N-07 and N-08 are all recorded and pinned, not repaired. Fixing them is remediation work with product-visible consequences, and this workstream's mandate is coverage.
- **Did not delete or weaken a single existing test**, including the 259 replicas. §10 R-7 gives the conversion path.
- **Did not add a trivially-passing assertion to raise a count.** The 47 added tests each pin a specific, named finding or its precondition. Where the honest answer was "no test can be written yet" — Edge Functions with no Deno runtime, the nutrition allergen guard that does not exist, `saveSetLog` with no seam — this report says so instead of writing a replica.
- **Did not make a product decision.** Q-1 (daily vs. weekly check-in), Q-3/A-1 (the prescription model), Q-4/A-5 (PAR-Q policy) and Q-5 (the clinical fertile window) each block a test that would otherwise be written; each is left open.
- **Did not create a CI workflow**, though N-01 is the report's highest-leverage finding. Wiring CI to QA involves credential handling and is an operational decision to be taken deliberately, not as a side effect of a coverage audit.

---

## Bottom line

The suite is **763 executable tests and 0 failures**, and that number is not a measure of safety.

- **37% of the Flutter suite tests copies of the product**, not the product.
- **The single best test asset in the repository — 188 live authorization assertions written to fail against the pre-remediation database — has never run in CI, and could not run at all this session.**
- **There is no CI.** Every standing guard in this repo is a guard only for whoever remembers to run it.
- Four guards written for specific defects **cannot detect those defects**, because in each case the defect is one layer away from where the guard looks. Two of the four are demonstrably live in the tree right now: the Resume affordance still hides itself on a failed lookup, and `enrich-exercise` is dead on arrival.

Where the coverage is genuinely good it is very good — the Phase 2 workout contract, the women's-health characterization suite, the API's failure taxonomy, and `SEC-027`'s "did a later migration silently revert an earlier fix" check are all the right shape. The gap is not craft. It is **reach**: the good tests stop at the layer boundary, and the defects live on the other side of it.
