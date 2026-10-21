# SEC-R2 / SEC-R3 · end-to-end evidence matrices (C1 preparation)

**Neither finding is promoted by this document, and neither has its fifth state.** No QA write, no
live probe, and no registry status change was made. C1 (§7.25 Ruling C) is a **per-row acceptance
route**; it is not blanket Step 4 authorization and waives no evidence state.

**Headline: the two findings are not symmetric.** SEC-R2's failure leg is already implemented
correctly in the product. **SEC-R3's is not** — its call sites swallow a failed safety input into a
benign default, so a faithful failure-leg assertion would fail against current code. That is a
prerequisite, not a test defect.

---

## Reusable patterns found in the precedents

| precedent | pattern worth reusing |
|---|---|
| `integration_test/uix1_booking_e2e_test.dart` | **Reach the surface through the real route.** Its own header: *"the driver reaches BookingScreen through the REAL route: the real `CircleFitnessApp` → `MaterialApp.router` → `routerProvider` → `/appointments` → `PaywallGate` → `BookingScreen`. Mounting BookingScreen directly is explicitly NOT the acceptance path: authorization is a named link in §2's chain, and a direct mount skips it."* |
| `tool/negative_control/uix1_booking_e2e.sh` | **Refuse to report success over an infrastructure failure.** Marker lines are emitted by the probe; absent markers exit as INFRASTRUCTURE failure, *"because a green exit code over a screen nobody mounted is the most expensive kind of false evidence."* |
| `tool/negative_control/ec04_risk_badge_e2e.sh` | **A counter-example, recorded so it is not reused by mistake.** It is labelled a VERIFIED END-TO-END runner but states: *"the probe overrides `clientDetailProvider` with an in-memory profile. NOTHING IS SIGNED IN, no backend is written."* It proves rendering, not the chain. |
| `integration_test/wrk01_progression_live_test.dart` | signs in and traverses a real read path; the pattern for a live, authenticated probe |

**Cost of the UIX-1 pattern:** it performs **QA writes** (`coach_client_relationships` INSERT,
`coach_availability` INSERT/DELETE). **This milestone forbids QA writes**, so neither probe below
was executed.

---

## Matrix 1 · SEC-R2 / F-J-17 — PAR-Q risk and flags

| field | established |
|---|---|
| **Canonical finding** | Migration 115 made risk server-authoritative in a BEFORE INSERT OR UPDATE trigger on `user_profiles`. Its classifier appended three narrative flags as **untyped literals** to a `text[]`, so PostgreSQL resolved `anyarray‖anyarray` and raised **22P02 malformed array literal**. *"The throw happened in the write path, so the member could not save the declaration at all."* Migration **126** casts the three appends to `::text` |
| **Entry point** | `IntakeFlowScreen`, route **`/intake`** (`lib/features/onboarding/presentation/intake_flow_screen.dart`) |
| **State** | `_data` (`IntakeData`), `_step`, `_saving`, `_saveError` |
| **Service boundary** | `_finish()` → `Supabase.instance.client.from('user_profiles').upsert({'id': uid, ..._data.toSupabase()})` (`:279-281`) |
| **Authorization** | RLS on `user_profiles`, plus an explicit null-session refusal at `:265-275`. **Note:** `/intake` is in the router's `isAuthRoute` set, so the route is deliberately open — the guard, not the router, is the authorization link here |
| **DB / function** | the 115 trigger, as fixed by 126 |
| **Persistence** | `risk_level` and the flag array, **server-owned** — the client never supplies them |
| **Expected response** | success, or the caught exception |
| **Expected UI state** | `IntakeCompletePage`; on failure **`_saveError` with Retry and NOT complete** |
| **Failure leg — ALREADY CORRECT** | `_finish()`'s catch is annotated *"NOT marked complete. The intake is not finished, because it was not saved"*, and the null-uid arm refuses with its own message. **This satisfies §2.1's "correct failure behaviour" for this row** |
| **Anti-vacuity** | assert `risk_level` is **server-computed** (client sends none and a value appears); assert the flag array is non-empty for a declaring input; on the failure leg assert `_saveError` is **non-null** *and* `IntakeCompletePage` is **absent** — not merely that no exception escaped |
| **Existing tests** | `supabase/tests/ai/fj17-parq-risk-contract.sql` (offline/QA, rolls back); `ec03_intake_false_completion_e2e_test.dart`; `ec03_negative_control.sh` |
| **A caveat not to gloss** | `_saveProgress()`'s Phase 2 per-step write is `try { … } catch (_) {}` (`:168-174`, *"best-effort persist"*). That is **not** the authoritative declaration write — `_finish()` is — but it means an intermediate PAR-Q write can fail silently. It is in **Phase B4**'s swallow-sweep scope, not this row's |
| **Remaining for acceptance** | (1) a probe through the real route performing the upsert — **needs a QA write**; (2) a per-row owner ruling on the §7.13/§7.18 pattern |

---

## Matrix 2 · SEC-R3 / F-J-07 — recovery-state rule accumulation

| field | established |
|---|---|
| **Canonical finding** | `v text[] := '{}'` then `v := v ‖ 'LABEL'` resolves to `anyarray‖anyarray` and raises **22P02**. **Eleven sites, three functions**: `build_workout` 089:55 · `evaluate_week(_engine)` 094:52,55,60,65 · `predict_client(_engine)` 095:125,127-131. Migration **127** casts all eleven to `::text` |
| **Entry points** | `build_workout` → `custom_exercise_service.dart:505` · `evaluate_week` → `coach_program_service.dart:119` · `predict_client` → `coach_program_service.dart:88` |
| **Authorization** | **traversed in the product path**: the Dart callers use the **public wrapper names**, which 116 published over `*_engine` with `can_act_for` / `can_act_on_program` |
| **Important divergence from the contract suite** | `fj07-rule-accumulator-contract.sql` states it *"calls the ENGINES, because they are where the defect lived… **Authorization** is the wrappers' contract and is **deliberately not re-tested here**."* §2.1 names authorization as a chain link, so **the contract suite cannot serve as the end-to-end evidence** — an END-TO-END probe must go through the wrappers |
| **Persistence** | `build_workout` writes `decision_traces`; `evaluate_week` is **read-only** (verified: zero mutating keywords in its body) |
| **Expected response** | jsonb carrying `rules_triggered` with the labels present |
| **Failure leg — NOT SATISFIABLE TODAY** | every call site swallows into a benign default: `predict_client` `:92` `catch (_) { return null; }` · `evaluate_week` `:122` `catch (_) { return null; }` · `record_prediction` `:102` `catch (_) { return null; }` · `:113` `catch (_) { return false; }`. So a 22P02 from the accumulator becomes **`null`**, and the surface renders a "no data" state. **This is precisely "a failed safety input silently becoming a benign default"** |
| **Anti-vacuity** | assert the specific labels (`RECOVERY_PROTECTION`, `RECOVERY_REDUCTION`) are **present in the response**, not merely that a map returned; assert the branch was entered by seeding the recovery input that triggers it; on the failure leg assert the UI shows a **refusal**, never an empty recommendation |
| **Existing tests** | `supabase/tests/ai/fj07-rule-accumulator-contract.sql`; `d04` §8 and `d23` cover the wrappers' authorization |
| **Remaining for acceptance** | (1) **a product change** so a failed accumulation refuses rather than returning `null` — this is **Wave 3B-1**'s *"refuse rather than degrade"* and **Phase B4**'s swallow sweep, both currently blocked; (2) a probe through a real surface — needs a QA write; (3) a per-row owner ruling |

---

## What was NOT done, and why

**No probe was written into CI.** Two independent reasons, per finding:

* **SEC-R2** — the probe must perform the `user_profiles` upsert to exercise the trigger. That is a
  **QA write**, which this milestone forbids. The design is complete; execution awaits
  authorization for a live probe, with the QA target independently established from a tracked
  source (`supabase/expected_applied.json` → `environments.qa.ref = eyqtldjqpgpljlqvpowh`).
* **SEC-R3** — a faithful failure-leg assertion **would fail against current code**, because the
  service swallows to `null`. Wiring a failing test into CI would break the build; writing a
  passing test that avoids the failure leg would be the vacuous evidence this programme keeps
  finding. **The prerequisite is a product fix, not a test.**

**Neither is labelled end-to-end.** No contract test and no partial chain is presented as the fifth
state.

## Conflict recorded, not resolved

The §7.10 Step 4 prohibition and the §7.18 per-row precedent remain in tension, as §7.25 preserved
them. SEC-R3's situation adds a practical observation to that record: **C1 gives these rows a route,
but SEC-R3 cannot travel it until a blocked product change lands.** C1 is an acceptance mechanism,
not a substitute for the behaviour it would accept.
