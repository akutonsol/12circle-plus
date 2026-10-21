# Wave 3B work package — `WRK-07` / `EC-11` / `EC-05` · domain audit

| | |
|---|---|
| **Date** | 2026-09-09 |
| **Baseline** | `43b48a7d240efac7fb8f5ba54846267cd4375c45` on `chore/qa-environments-secure-ai-backend` |
| **Disposition** | **AUDIT COMPLETE · REMEDIATION BLOCKED — NO PRODUCTION CODE CHANGED** |
| **Requirements** | `WRK-07` **PARTIAL** (provider half closed, screen half live) · `EC-11` **BLOCKED** · `EC-05`/`N-07` **BLOCKED** |
| **Live QA writes** | none |
| **Files changed** | this file only |

---

## 1. Executive summary

All three requirements were traced end to end through the real implementation, and the
live QA database was read (read-only) to confirm the one constraint the findings depend on.

**`WRK-07` is half-closed and has been since Phase 2.** The provider layer genuinely
propagates — verified, not assumed. Its *screen* half is live: two surfaces render a failed
lookup as "nothing to resume". That half is pinned by `EC-G6` as two deliberate DEFECT tests
and **has no tracking row in any governance document**.

**`EC-11` cannot start.** Owner ruling **D-3** (registry §7.14) sets its dependency to
`I-WRK-01` + `I-COM-01` + `I-CHK-01`. `I-WRK-01` is `VERIFIED_CLOSED`; the other two are
**mechanically proven still open** by `known-violations.json`, which is checked in both
directions. §7.14 says so in terms: *"`EC-11` is not authorized to start."*

**`EC-05` cannot start either, for a different reason.** Its own dependency column is `—`,
but `MASTER_REMEDIATION_WAVES.md` §Wave 3B is **strictly ordered** and places `EC-05` in
stage **3B-3**, behind **3B-1** (`ERR-2`/`ERR-3`/`ERR-4`, itself gated on `SEC-R2`, which is
not `VERIFIED_CLOSED`) and **3B-2** (`EC-08`, `EC-09`, `EC-12`, all still open P1 rows).
Wave 3B's own prerequisite — *"3A complete"* — is also unmet: task **3A-11 / migration 131**
is unauthored, and creating it is outside this package.

The audit nevertheless produced **four findings the source reports do not contain**, two of
which correct the record: `EC-05`'s blast radius includes a **persisted score write** nobody
had recorded, and **two of `EC-05`'s stated impacts are not reproducible in the current
tree** — the mechanism is real, but it is not the mechanism the registry describes.

---

## 2. Scope

| | |
|---|---|
| **IN SCOPE** | `WRK-07`, `EC-11`, `EC-05`/`N-07`, and the guards that pin them (`EC-G1`, `EC-G5`, `EC-G6`, `EC-G7`, `EC-G8`) |
| **OUT OF SCOPE** | every other `EC-*`, `ERR-*`, Wave 3B stage, `docs/design/**`, migration 131, `expected_applied.json` |
| **PRE-EXISTING** | ` M supabase/expected_applied.json` · `?? docs/design/` — untouched, not mine |
| **DEFERRED** | see §9 |
| **BLOCKED** | all three requirements — see §4 |

---

## 3. Baseline

```
repo    /Users/dmac/Documents/projects/12circle-fitness
branch  chore/qa-environments-secure-ai-backend
HEAD    43b48a7d240efac7fb8f5ba54846267cd4375c45   (ahead of origin by 1, not pushed)
tree     M supabase/expected_applied.json      (pre-existing)
        ?? docs/design/                        (pre-existing)
```
Regression baseline on this unchanged tree: `flutter test` **792 passed / 9 skipped / 0
failed**; `flutter analyze` **0 errors**, 15 warnings, 160 infos; `npm run test:contract`
PASS with a 3-entry allowlist.

---

## 4. Governing requirements, and the blocking chain

### 4.1 Sources, in precedence order

| Source | Bearing |
|---|---|
| `MASTER_REMEDIATION_WAVES.md` §Wave 3B | Prerequisites and the **strict stage order**. Governing for *when*. |
| `MASTER_REMEDIATION_REGISTRY.md` §4.2, §7.2, §7.14 | Regression register, per-finding `Dep` / `∥` / wave, owner ruling **D-3**. Governing for *dependency*. |
| `QA_WORKSTREAM_B_ERROR_CONTRACT_REPORT.md` | The requirement text and the layer contract (L0–L4, rules W/D/M/N/T/X/O/B/S). Frozen evidence (§10.2). |
| `QA_WORKSTREAM_N_TEST_COVERAGE_REPORT.md` | N-02, N-07 — the coverage gaps. Frozen evidence. |
| `QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md` :810, :873 | The substantive ordering argument for `EC-11`. |

### 4.2 The blocking chain, with the evidence for each link

**Link 1 — Wave 3B's prerequisite is unmet.**
`MASTER_REMEDIATION_WAVES.md`: *"**Prerequisites** | **3A complete** (the H dependency) ·
Wave 1's observability decision (D-5(L))"*. 3A's task list ends at **3A-11 · migration 131 ·
identity constraints**. `ls supabase/migrations | grep '^13[1-9]'` → **nothing**. 3A is not
complete, and this package is forbidden from creating 131.

**Link 2 — the stage order puts `EC-05` third of four, behind two open stages.**
*"Strictly ordered — this is Workstream B's sequence and it is correct"*:

| Stage | Contents | State |
|---|---|---|
| **3B-0** Observability | `ERR-1` | ✅ `VERIFIED_CLOSED` 2026-08-27 (registry §7.13) |
| **3B-1** Safety inputs | `ERR-2`/`ERR-3`/`ERR-4`, *"Depends on CON-03 … and on SEC-R2"* | ❌ `SEC-R2` is not `VERIFIED_CLOSED` — four of five states, `VERIFIED END-TO-END` absent (§7.10) |
| **3B-2** Verified writes | `EC-08`, `EC-09`, `EC-12` | ❌ all three are open P1 rows (registry :1299, :1300, :1302) |
| **3B-3** Persisted transitions | **`EC-05`/`N-07`**, `EC-06`, `EC-07`, `EC-14`, `EC-22` | ← the target |
| **3B-4** Service sweep | **`EC-11`** *(after 3A-5)*, `EC-13`, `EC-15`, … | ← the target |

**Link 3 — `EC-11`'s own dependency is open, and provably so.**
Owner ruling **D-3** (2026-08-27, registry §7.14) sets `EC-11`'s `Dep` to
`I-WRK-01` + `I-COM-01` + `I-CHK-01`. Executed at this HEAD:

```
$ npm run test:contract
  known  relation checkins                          I-CHK-01  (7 sites)
  known  relation coach_tips                        I-LEG-03  (1 site)
  known  column   event_registrations.ticket_code   I-COM-01  (1 site)
PASS  no unknown relation or column outside the 3-entry known-violations allowlist
```

`known-violations.json`'s own header: *"an entry listed here that no longer reproduces
**ALSO** fails the guard"*. The guard passes, therefore `I-CHK-01` and `I-COM-01`
**still reproduce**. `I-WRK-01`, the one dependency that *is* closed, has no entry — which
is what a closed dependency looks like in this mechanism. Registry §7.14 states the
conclusion directly: **"`EC-11` is not authorized to start."**

**Link 4 — the substantive reason, not merely the bureaucratic one.**
`QA_WORKSTREAM_H…:810`: *"EC-11's swallows before H-01, H-02 and EC-10 converts silent
empty states into permanent visible errors."* `:873`: *"**Do not** start Workstream B's
EC-11 swallow remediation before step 2."* Un-swallowing a read whose column or table does
not exist replaces an invisible defect with a permanent visible one for every user.

**Conclusion.** Remediation of `EC-11` and `EC-05` is **not** *"clearly supported by the
governing requirements"*, which is this package's own authorization test. Both are recorded
and specified below, and neither was implemented.

---

## 5. Requirement traceability matrix

| ID | Requirement | Source | Acceptance | Domain | Implementation | Security property | Tests | Status |
|---|---|---|---|---|---|---|---|---|
| **WRK-07(a)** | Workout providers must not return `[]` on error | B §4.2 L3; registry :263 | `workout_provider.dart` contains no `catch` | Client / provider | `workout_provider.dart` — 0 real `catch` | none (integrity) | `EC-G1` ×3 | ✅ **CLOSED, verified** |
| **WRK-07(b)** | The surfaces reading it must render error ≠ empty | B §4.2 L4; provider's own comment | error arm ≠ empty arm, with a retry | Client / UI | `train_hub_screen.dart:169`, `resume_workout_banner.dart:48` — **both collapse** | none | `EC-G6` ×2, written as DEFECT | ❌ **LIVE** |
| **EC-11** | `WorkoutService` propagates; a service returns domain answers only | B EC-11; rule **L2** | 13 swallow sites removed; 9 providers gain error states | Client / service | `workout_service.dart` — **14 `catch (` sites**, 13 domain + 1 `logWorkout` | none directly | none — `EC-G5` ratchet only | ⛔ **BLOCKED** (§4.2 link 3) |
| **EC-05** | A transition is not announced until persisted | B EC-05; rule **T** | `completeSession` failure ⇒ no celebration, session left resumable | Client / UI + service | `active_workout_screen.dart:611-619` `catch (_) {}`; `:608` unguarded | none | none — no seam (N-07) | ⛔ **BLOCKED** (§4.2 links 1–2) |

---

## 6. Implementation trace

### 6.1 `EC-05` — the completion path, verbatim

`apps/mobile/lib/features/workout/presentation/active_workout_screen.dart`

```
:608   await _workoutService.logWorkout(log);        // whole body is catch (_) {}
:610   if (_sessionId != null) {
:611     try {
:612       await _sessions.completeSession(...);      // ← the state transition
:618     } catch (_) {}                              // ← EC-05, the swallow
:619   }
:621   await ScoreService().addWorkoutPoints();      // unconditional
:622   await ScoreEngine().workoutCompleted(...);    // unconditional
:623   ref.read(activeWorkoutProvider.notifier).reset();
:630   ref.invalidate(activeSessionProvider);
:631   ref.invalidate(activeWorkoutRestorationProvider);
:633   if (mounted) showDialog(... _WorkoutCompleteDialog ...);   // the celebration
```

**The transition itself already propagates correctly** — verified through all three layers:

| Layer | File | Behaviour |
|---|---|---|
| Store | `workout_session_store.dart:208` | `await _db.from('workout_sessions').update(...)` — **no catch** |
| Manager | `workout_session_manager.dart:91` | bare `=>` delegation — **no catch** |
| Call site | `active_workout_screen.dart:618` | **`catch (_) {}`** ← the only swallow |

So `EC-05`'s remediation is exactly what Workstream B says it is: delete a catch and gate
the four unconditional steps on success. **The plumbing beneath it is already correct.**

### 6.2 `EC-11` — the 14 sites and their blast radius

`workout_service.dart` (440 lines) — `catch (` count **14**, at
`:65 :211 :225 :258 :273 :290 :319 :328 :347 :376 :392 :404 :425 :438`, matching
Workstream B's enumeration exactly. `:65` is `logWorkout` (a write); the other 13 are reads
returning `[]` or `0`.

Nine providers in `workout_provider.dart` are thin wrappers and therefore cannot produce an
error state no matter how clean that file is: `weeklyWorkoutCountProvider`,
`currentStreakProvider`, `totalWorkoutCountProvider`, `personalRecordsProvider`,
`totalVolumeProvider`, `completionRateProvider`, `programAdherenceProvider`,
`exerciseProgressionProvider`, `loggedExerciseNamesProvider`, plus three `.family`
providers for the coach surfaces (`clientWorkoutStatsProvider`,
`clientPersonalRecordsProvider`, `clientRecentSessionsProvider`).

`getCompletionRate()` (`:332-348`) is the sharpest case and is quoted in full because the
fabrication is structural, not incidental:

```dart
if (all.isEmpty) return 0;                       // "no sessions"  → 0
...
} catch (_) { return 0; }                        // "could not read" → 0
```

Three different facts — *no data*, *0% completed*, *read failed* — all render as `0`. A
coach reads "0% completion" for a client whose sessions merely could not be fetched.

### 6.3 `WRK-07(b)` — the live screen half

`activeSessionProvider` (`workout_provider.dart:400-410`) carries its promise in a comment:
*"Surfaces here become an error state with a retry."* Neither surface honours it:

- `train_hub_screen.dart:169` — `error: (_, __) => const SizedBox.shrink()`; error arm and
  no-session arm render the identical widget.
- `resume_workout_banner.dart:48` — `.valueOrNull` then `if (session == null) return const
  SizedBox.shrink()`; error-null and no-session-null take the same branch.

The reference implementation is in the same feature: `workout_list_screen.dart` renders
`_AssignedErrorCard` — *"Your program could not be loaded"* + `Try again` wired to
`ref.invalidate`. `EC-G6` pins all three, the first two as DEFECT tests carrying delete-me
instructions for whoever closes the finding.

---

## 7. Database, RLS, storage and authorization audit

**No security defect was found in any of the three requirements.** All three are integrity
and honesty defects on the client, not authorization defects. Recorded explicitly so the
absence is evidence rather than silence:

| Surface | Finding |
|---|---|
| RLS on `workout_sessions` / `workout_logs` / `workout_set_logs` | untouched by this package; migration 120's immutability triggers (`SEC-11`) stand |
| Authorization | none of the three findings crosses a trust boundary; every path is the authenticated owner acting on their own rows |
| Storage | not involved |
| Edge Functions / API | not involved |
| Live QA read (read-only, this audit) | `workout_sessions_one_active_per_user` **confirmed present**: `CREATE UNIQUE INDEX … ON public.workout_sessions USING btree (user_id) WHERE (status = 'in_progress'::text)` |

That last row matters: the index `EC-05`'s stated impact depends on **does** exist. What
does *not* hold is the consequence the registry draws from it — see **F-06**.

---

## 8. Findings register

Severity uses the registry's scale. Category letters are this package's classification set.

### F-01 · `EC-11` is dependency-blocked · **Sev P1** · Category **L + H**
Owner ruling D-3 sets `Dep` = `I-WRK-01` + `I-COM-01` + `I-CHK-01`. `I-WRK-01` closed;
`I-COM-01` and `I-CHK-01` provably open via the bidirectional allowlist (§4.2 link 3).
Registry §7.14: *"`EC-11` is not authorized to start."*
**Remediation:** close `I-COM-01` and `I-CHK-01`, then `EC-11` at stage 3B-4.
**Authorization:** REQUIRES AUTHORIZATION — and a dependency waiver would be unsafe, per
Workstream H:810.

### F-02 · Wave 3B's prerequisite ("3A complete") is unmet · **Sev P1** · Category **H**
3A-11 / migration 131 is unauthored; creating it is outside this package.
**Remediation:** complete 3A-11, or obtain an explicit prerequisite waiver.
**Authorization:** REQUIRES AUTHORIZATION.

### F-03 · Wave 3B's strict order places `EC-05` behind two open stages · **Sev P1** · Category **H**
3B-1 is gated on `SEC-R2` (not `VERIFIED_CLOSED`); 3B-2's `EC-08`/`EC-09`/`EC-12` are all
open P1 rows. `EC-05` is 3B-3.
**Remediation:** complete 3B-1 and 3B-2, or obtain an explicit stage-order waiver.
**Authorization:** REQUIRES AUTHORIZATION.

### F-04 · `EC-05` reproduces exactly as reported · **Sev P1** · Category **B + C**
Confirmed at `active_workout_screen.dart:608-650` (§6.1). The swallow is the sole defect;
store and manager already propagate.
**Remediation (specified, not applied):** delete `:618`'s `catch (_) {}`; on failure show a
named error with a retry, leave `_sessionId` set, do **not** award score, do **not**
`reset()`, do **not** show `_WorkoutCompleteDialog`.
**Regression requirement:** a failing-store test proving the celebration is withheld — which
needs **F-09**'s seam first.

### F-05 · `EC-05` awards a persisted score for an un-persisted transition — **NEW** · **Sev P1** · Category **C**
Not recorded in Workstream B, Workstream N, or the registry. `:621-622` run unconditionally
after the swallowed failure:
`ScoreService.addWorkoutPoints()` → `_updatePoints({'workout_points': maxWorkout})` — a
**set**, not an increment — and `ScoreEngine().workoutCompleted(workout.id)`.
The 12 Circle Score is a headline surface feeding the coach leaderboard. This is
Workstream B's **rule D** (*"a value produced by a fallback may never become the input to a
persisted decision"*) in its sharpest form: the input is not merely defaulted, it is known
to be wrong. It also makes the score and `workout_sessions` permanently disagree.
**Remediation:** fold into F-04's gate — score writes move inside the success branch.
**Authorization:** REQUIRES AUTHORIZATION (same block as `EC-05`).

### F-06 · Two of `EC-05`'s stated impacts are not reproducible in the current tree · **Sev P2** · Category **M + J**
Registry §4.2 and Workstream B EC-05 both state: *"the Resume banner keeps offering a
finished workout, and `workout_sessions_one_active_per_user` then constrains the next one."*

The index exists (verified live, §7). The consequence does not follow, because
`WorkoutSessionManager.startWorkout` (`:29-51`) **abandons every other in-progress session
before inserting**: `supersededIds` → `abandonSessions` → `createSession`. A stale orphan
therefore does **not** produce a `23505` on the next workout.

**The real current-tree harm is different and was not recorded:** `_matchWorkout`
(`:133-145`) matches an open session by `workoutId`, and `startWorkout` **returns it
unchanged** rather than abandoning it. So a client who re-enters *the same* workout is
silently **resumed into the session they were just told was complete**, with its elapsed
time and logged sets — after `_leaveFinishedWorkout()` has already cleared their selection.
**The finding is real; the mechanism in the record is wrong.** A–N reports are frozen
(§10.2) — recorded here, not rewritten there.

### F-07 · `EC-05`'s adherence claim is directionally wrong · **Sev P3** · Category **J**
Both sources say *"`getCompletionRate()` never counts it, so adherence **overstates**"*.
`getCompletionRate()` filters `status IN ('completed','abandoned')`. An `in_progress` orphan
is excluded from numerator **and** denominator; once `startWorkout` abandons it, it enters
the **denominator only**. Both cases move the ratio **down**. Adherence **understates**.
Recorded, not rewritten (§10.2).

### F-08 · `WRK-07`'s live screen half has no tracking row · **Sev P2** · Category **G + J**
`N-02` appears in **no** governance document: `grep -c "N-02"` → `MASTER_REMEDIATION_WAVES.md`
**0**, `REMEDIATION_PROGRESS.md` **0**, `MASTER_REMEDIATION_REGISTRY.md` **3 — all false
matches on `CON-02`**. The N cohort's shared row (registry :1413) carries `N-06`, `N-08`,
`N-09`, `N-10` and **not** `N-02`. The defect is real, reproduced, and pinned by `EC-G6`,
and `WRK-07`'s own row reads *closed*. **A finding pinned only by a test that describes it
as a defect, with no row in the register, is invisible to every status count.**
**Remediation:** ARCH opens a row for `N-02` (or records it as `WRK-07(b)`).
**Authorization:** REQUIRES AUTHORIZATION — the registry is ARCH-owned.

### F-09 · `EC-05` has no test seam · **Sev P1** · Category **F**
`InMemoryWorkoutSessionStore` has exactly one throw — a faithful reproduction of
`workout_sessions_one_active_per_user` in `createSession` (`:136-152`). There is **no
failure injection for `completeSession`**, so no test can drive `EC-05`'s failure path.
Confirms N-07 (*"no test covers it, and there is no seam to add one"*) and Workstream N's
recommendation **R-4** (a `failNext` flag). The seam belongs to the N-10 cohort, **Wave 8**.
**Authorization:** REQUIRES AUTHORIZATION — remediating `EC-05` without it would ship an
unverifiable fix, which §4 of the closure standard forbids.

### F-10 · `EC-05` and `EC-11` overlap at `logWorkout` · **Sev P2** · Category **H**
`workout_service.dart:65` is simultaneously `EC-11` site #1 and, per `EC-05`'s own card,
part of `EC-05`'s remediation (*"only the two call-site catches and `logWorkout`'s need
removing"*). `EC-11` is blocked; `EC-05` is not blocked by dependency. **A fully authorized
`EC-05` fix still cannot be completed without entering `EC-11`'s blocked file.**
The transition half (rule T, `active_workout_screen.dart`) and the data-loss half
(`workout_service.dart:65`) are separable, but **splitting them is an owner decision, not an
implementer's.** Recorded, not resolved.

### F-11 · `EC-G1`'s "no catch" assertion has no blind spot — checked and cleared · **Informational** · Category **M**
A naive `grep -c "catch (" workout_provider.dart` returns **1**. The hit is inside a doc
comment at `:146` (*"This used to `catch (_) { return []; }`"*), and `EC-G1`'s `_hasCatch`
strips line comments before matching. **`EC-G1` is sound.** Recorded so a future auditor
does not re-raise it.

### Summary

| Severity | Count | IDs |
|---|---|---|
| Critical (P0) | **0** | — |
| High (P1) | **6** | F-01, F-02, F-03, F-04, F-05, F-09 |
| Medium (P2) | **3** | F-06, F-08, F-10 |
| Low (P3) | **1** | F-07 |
| Informational | **1** | F-11 |

**Security defects (category A/D): zero.** All findings are integrity, honesty, governance,
or coverage.

---

## 9. Test inventory and execution

Every command was run at `43b48a7d` on the unchanged tree.

| Command | Purpose | Result |
|---|---|---|
| `flutter test test/unit/error_contract_guard_test.dart` | `EC-G1`…`EC-G5` | **+13 PASS** |
| `flutter test test/unit/ui_error_surface_guard_test.dart` | `EC-G6`…`EC-G8` (WRK-07(b)) | **+9 PASS** |
| `flutter test test/unit/workout_session_persistence_test.dart` | session state machine | **+30 PASS** |
| `flutter test test/unit/workout_restoration_test.dart` | restoration / WKT-112 | **+33 PASS** |
| `flutter test test/unit/workout_active_session_authority_test.dart` | migration 108 authority | **+15 PASS** |
| `flutter test test/unit/workout_domain_contract_test.dart` | Phase 2 contract | **+32 PASS** |
| `flutter test test/widget/active_workout_hydration_test.dart` | screen mount | **+4 PASS** |
| `flutter test` | full regression | **792 passed / 9 skipped / 0 failed** |
| `flutter analyze` | static analysis | **0 errors**, 15 warnings, 160 infos |
| `npm run test:contract` | schema contract + `EC-11` dependency gate | **PASS**, 3-entry allowlist |
| `supabase db query --linked` (read-only) | `workout_sessions` indexes | index confirmed present |

**The decisive observation: every one of these passes while all three findings are live.**
That is by design — `EC-G1` locks the half that is fixed, `EC-G6` characterises the half
that is not, and `EC-G5`/`EC-G7`/`EC-G8` are ratchets (baselines **234**, **16**, **134**)
that stop growth without requiring a fix. **No suite in this repository can currently fail
because of `EC-05`, and F-09 is the reason.**

Not run, with reasons: no test drives `_completeWorkout` (F-09 — no seam); Edge Function
tests (Deno absent, N-09); live mutation probes against `workout_sessions` (not authorized
and not needed — the audit's live need was one read-only index query).

---

## 10. Remediation performed

**None.** No production file, test, migration, policy or configuration was changed. The
sole artifact of this audit is this document.

Full remediation specifications are recorded in F-04, F-05 and F-08 so that the work is
ready to execute the moment the ordering question is answered.

---

## 11. Deferred, and requiring authorization

| Item | Why | Who decides |
|---|---|---|
| `EC-11` (13 sites) | F-01 — two dependencies open; H:810 says the fix is harmful first | Owner + ARCH |
| `EC-05` transition half | F-03 — stage order; F-09 — no seam | Owner |
| `EC-05` `logWorkout` half | F-10 — inside `EC-11`'s blocked file | Owner |
| `WRK-07(b)` screen half | F-08 — untracked; belongs to 3B's L4 obligation | ARCH opens a row first |
| R-4 failure seam | F-09 — Wave 8 (N-10 cohort) | Owner |
| Registry corrections F-06, F-07 | frozen A–N evidence, §10.2 | ARCH |
| Migration 131 / 3A-11 | F-02 — explicitly outside this package | Owner |

---

## 12. Residual risks

1. **`EC-05` is live and unpinned.** Nothing turns red if it regresses further, and nothing
   turns red when it is fixed. F-09 is the highest-leverage single item here.
2. **F-05 means the damage is wider than the record shows** — a persisted score write, not
   only a missed session update.
3. **F-06 means anyone planning `EC-05` from the registry will plan against the wrong
   mechanism** and may test for a `23505` that cannot occur.
4. **F-08 means `WRK-07` reads as closed in every status count** while half of it is live.
5. The ratchets hold the line but cannot lower it; `EC-G5`'s 234 will not fall until 3B runs.

---

## 13. Files

**Changed by this audit:** `docs/WAVE_3B_WRK07_EC11_EC05_AUDIT.md` (this file, new).

**Deliberately untouched:** `apps/mobile/lib/features/workout/**` · `apps/mobile/test/**` ·
`supabase/migrations/**` · `supabase/expected_applied.json` · `docs/design/**` ·
`known-violations.json` · every guard file.

**Live environment changes:** none. One read-only `pg_indexes` query against QA
`eyqtldjqpgpljlqvpowh`. Production not contacted.

---

## 14. Disposition and next action

**`WRK-07` PARTIAL · `EC-11` BLOCKED · `EC-05` BLOCKED. Audit complete; remediation not
authorized.**

The single next action is an **owner ruling on ordering**, in the shape of Ruling A for
migration 130 — either:

> **(i)** complete the prerequisites in order (3A-11, then 3B-1, then 3B-2), after which
> `EC-05` and `EC-11` become authorized in sequence with no waiver at all; **or**
> **(ii)** an explicit, recorded waiver of Wave 3B's prerequisite and stage order for a
> named subset — for which the defensible subset is **`EC-05`'s transition half plus F-09's
> test seam**, because it is the only slice that is dependency-free, failure-path-only, and
> verifiable once the seam exists.

**`EC-11` should not be waived under either branch.** Its dependency is not a formality:
Workstream H:810 establishes that un-swallowing reads over a missing table or column
converts a silent defect into a permanent visible one for every user.
