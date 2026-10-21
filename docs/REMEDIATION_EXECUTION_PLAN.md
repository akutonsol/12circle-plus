# 12 Circle Fitness — Remediation Execution Plan

Companion to [`MASTER_QA_RECONCILIATION.md`](MASTER_QA_RECONCILIATION.md). Canonical IDs are defined there.

**Rule for every step:** reproduce the defect first, fix at the authoritative layer, re-verify, add the standing regression test, then re-run the full suite. A security finding is closed only when the boundary is verified live in QA — never when a unit test passes.

**Environment:** QA `eyqtldjqpgpljlqvpowh` only. Production `nxdbooufqzkpslkcogxc` is untouched throughout. No commits without your say-so.

---

## Sequencing logic

Three dependencies drive the order and none of them are negotiable:

1. **SEC-01 gates SEC-04.** The authorization fix for the intelligence RPCs uses `is_active_coach_of()`, which is only trustworthy once its backing table is protected.
2. **SEC-02 gates SEC-07.** Content-write policies keyed on `role` are meaningless while `role` is self-writable.
3. **CON-02/CON-03 gate CON-04 and CON-08.** PAR-Q and allergy enforcement have nothing to enforce until onboarding reliably persists the data.

Everything else is grouped so that one root cause is closed per step, rather than one symptom.

---

## Step 0 — Baseline & hygiene *(no behaviour change)*

| | |
|---|---|
| **Items** | HYG-01, HYG-02, HYG-03 |
| **Do** | Record the measured baseline (Flutter 514 / API 58, both green). Propose committing the nine untracked test files and `workout_restoration.dart` as one change so the baseline is reproducible. Add `supabase/.temp/` to `.gitignore`. Nothing deleted, nothing reset, nothing stashed. |
| **Gate** | Suites still green; working tree otherwise unchanged. |

---

## Phase 1 — P0 security containment

> Nothing in Phases 2–4 starts until every item here is verified closed **live in QA**.

### 1A — Close the authorization root
**SEC-01** · forward migration · `coach_client_relationships`

Enable RLS; parties-only `SELECT`/`UPDATE`/`DELETE`; `INSERT WITH CHECK` that forbids naming an unconsenting counterparty (invite created by one party, activated by the other); revoke `anon`.

*Verify:* re-run the D-01 reproduction — anon read → denied; unrelated authenticated user's forge insert → denied; the victim health reads that jumped 0 → 7/30/21 stay at 0. Confirm a genuine coach still sees their own clients.

### 1B — Close role escalation
**SEC-02** · forward migration · `user_profiles`

`BEFORE UPDATE` trigger rejecting any change to `role`, `membership_tier`, `marketplace_commission_rate`, `stripe_*`, `is_demo`, `risk_*` unless the session is `service_role`. Trigger rather than policy-only, so it covers every write path including RPCs and survives a later policy edit.

*Verify:* `PATCH {role:'admin'}` → rejected, row unchanged; `admin_recent_users` still refuses the client; ordinary profile edits still succeed.

### 1C — Database-wide RLS sweep
**SEC-03, SEC-06, SEC-07, SEC-08** · forward migration

Audit **every** table for RLS (the source audit found 17 without it; re-run it against the live catalogue, since source and live are known to diverge). Then, per table:

- `weekly_checkins` — owner + active coach read; owner-only writes; coach-only feedback columns.
- `ai_profiles`/`ai_memories`/`ai_insights`/`ai_reviews`/`ai_goal_predictions` — owner read/write; coach read via `is_active_coach_of`; engine writes as `service_role`.
- `exercise_*` substrate — `authenticated` read; write restricted to `service_role` + content-manager (depends on 1B).
- `workouts` — pending **Q-2**; drop if confirmed.

*Verify:* for each table, anon read/insert/delete rejected; unrelated authenticated user reads 0 rows; the legitimate owner/coach/engine paths still work. Write probes are marked and reverted; final state verified clean.

### 1D — Function execution privileges
**SEC-05, SEC-09, SEC-10** · forward migration

Enumerate every routine in `public`; `REVOKE ALL … FROM PUBLIC, anon`; grant `EXECUTE` back to exactly the roles that need it. **Revoking `PUBLIC` alone is proven insufficient here** — the Supabase default grants `anon` directly, which is why migration 100's revoke on `is_active_coach_of()` did not take. Mirror migration 112's auditable `DO`-block shape. Add `SET search_path` to `SECURITY DEFINER` functions. Scope `coach_availability` read to `authenticated`.

*Verify:* anon `POST /rpc/is_active_coach_of`, `/rpc/predict_client`, `/rpc/marketplace_coaches` — all currently **HTTP 200** — must become denied. Authenticated and service-role paths unaffected. Standing test: no `public` routine is anon-executable outside a named allowlist.

### 1E — Subject authorization on intelligence RPCs
**SEC-04, CON-05 (authorization half)** · forward migration · *requires 1A*

Each of the seven functions defaults its subject to `auth.uid()` and permits another subject only for an active coach of that subject or `service_role`. Preserve the cron/engine paths in 076/080 exactly.

*Verify:* per function — A→B rejected, A→self allowed, coach-of-A→A allowed, `service_role` allowed, anon rejected. Specifically confirm `ai_adjust_nutrition` can no longer move another user's calorie target.

### 1F — Completed-history immutability at the database
**SEC-11** · forward migration

Trigger/policy: once `completed_at` is set, ordinary client updates to `workout_sessions` are rejected; corrections go through the sanctioned path only. `workout_program_assignments.current_week` and `status` become coach/service-writable.

*Verify:* the D-06 reproduction fails; the coach can still advance an assignment; the existing correction flow still works.

**Phase 1 exit criteria:** every P0 verified closed by live QA probe; permanent security regression tests added; full suite green; no probe residue left in QA.

---

## Phase 2 — Workout integrity

### 2A — One set identity
**WRK-01, WRK-02** · service + provider + forward migration

Upsert on `(session_id, set_id)`; retire migration 051's ordinal unique index; move set-id uniquification to workout scope; a swapped exercise gets fresh set identities carrying the prescription but not the id, completion, or logged values.

*Reproduce first:* (i) a workout repeating an exercise loses one block's set; (ii) logging a set after a swap raises 23505. Both must fail before and pass after.

### 2B — One program-exercise contract
**WRK-03, WRK-04, WRK-05, WRK-06 (partial)** · database contract + codec + writers

Define the canonical exercise-prescription shape; validate it at write time; make all three writers emit it; remove the codec's defensive casts. Where no load is prescribed, the client shows "—", never "0 kg".

**WRK-06 stops at Q-3.** I will normalize the contract and make the engine's output *valid* under it; whether the engine *prescribes* sets/reps/load is your decision. I will not invent a prescription model.

### 2C — Errors stop masquerading as empty
**WRK-07** · provider

Propagate in `assignedWorkoutsProvider`, `generateAiWorkout`, `programSessionStatusProvider`, `activeSessionProvider`; render error + retry. Follow the pattern `activeWorkoutRestorationProvider` already establishes.

### 2D — Re-verify what is already fixed
Confirm — do not re-fix — the lifecycle and client-side immutability work from migrations 103/105/107/108 and `workout_restoration.dart`, now that 2A has changed identity handling underneath it.

**Exit:** every confirmed workout defect has a regression test that fails before and passes after; full suite green; verified against real QA data.

---

## Phase 3 — Core product contracts

Ordered by dependency, not by severity.

| Step | Items | Note |
|---|---|---|
| **3A** | CON-03 | `dietary_restrictions`: one type, one serializer. Forward migration written to converge from either starting type (**Q-6** open for prod). |
| **3B** | CON-02 | Onboarding never marks itself complete on a failed save. Depends on 3A, which is the failure that triggers it today. |
| **3C** | CON-06, CON-07 | RC-8: UTC everywhere, explicit local day boundaries, a shared helper and a guard test. Nutrition gains a real date parameter and an audited correction path. ~60 call sites — one mechanical change, one guard. |
| **3D** | CON-01 | Check-In. **Blocked on Q-1** — recommendation: retire the duplicate service and migrate callers to `weekly_checkins`. |
| **3E** | CON-09 | Barcode: keep the unit in the type; a quantity is required to produce a log entry. |
| **3F** | CON-08 | Deterministic allergen/restriction guard on generated nutrition plans. Depends on 3A/3B for the input data. |
| **3G** | CON-04 | PAR-Q as a training constraint. **Blocked on Q-4.** Depends on 3B. |
| **3H** | CON-10 | Women's health: fix the modulo extrapolation and the future-dated start. Clinical window **blocked on Q-5**. |
| **3I** | SEC-12 | `marketplace_coaches()` honours `is_demo` and projects it. |

---

## Phase 4 — AI / intelligence

Only after Phases 1–3 are stable.

1. Deploy/configure QA Edge Functions (ENV-01); set the per-project Vault secrets (ENV-02) — **QA values only, never production values**.
2. Populate the intelligence substrate with **legitimate** product fixtures (ENV-03). An empty substrate is not evidence of a broken engine, and fixtures will not be fabricated to make tests pass.
3. Test the deterministic engine, then AI explanation, then the boundary between them: provenance, failure handling, and that no LLM output alters a decision. This is where the "engine decides, AI explains" invariant gets its standing test — the architecture is preserved, not redesigned.
4. Re-test the SEC-04/SEC-05 boundaries with the engine actually running.

---

## Phase 5 — Full AI QA retest

Re-run every workstream. Classify **every** canonical ID as FIXED / PARTIALLY FIXED / NOT FIXED / BLOCKED / INVALIDATED. Nothing disappears silently.

**Caveat recorded now:** for workstreams A/B/C/E there is no original report, so their re-test is a *first* statement of result, not a true before/after. Items I re-derived myself carry a real before/after because I recorded the reproduction.

---

## Phase 6 — Release readiness

Manual testing is the final gate and covers the full list in the brief. Release-ready requires **AI QA = PASS and Manual QA = PASS**. A production rollout plan for the Phase 1 migrations is a separate, explicitly authorized activity (see reconciliation §6).

---

## What I will stop and ask about

Q-1 (daily vs. weekly check-in) · Q-2 (`workouts` table) · Q-3 (does the engine prescribe load?) · Q-4 (PAR-Q policy) · Q-5 (cycle clinical parameters) · Q-6 (production column type).

Q-1, Q-2 and Q-6 have low-risk recommendations and can be answered quickly. **Q-3 and Q-4 are genuine product-authority decisions** and I will not manufacture either.
