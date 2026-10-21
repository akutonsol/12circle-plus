# 12Circle Fitness — Correction-Rights Exhaustion Report

**Phase:** Priority 6 — data-subject correction / access rights. **Discovery only.**
**Branch** `chore/qa-environments-secure-ai-backend` · HEAD at writing `c8db15e`
**Live evidence:** QA `eyqtldjqpgpljlqvpowh`. Every mutation reversible; every restore proven.
**Production `nxdbooufqzkpslkcogxc` never contacted.**

> Technical control assessment, not a HIPAA compliance certification.
> **0 production files changed. 0 migrations changed.**

---

## 1 · Executive status

The Privacy Policy states: *"You may update your personal information directly within
the app."*

**The database grants the subject full correction rights over their own health record;
the application exposes a fraction of it.** That headline survives. But a second pass
that traced every UI → service → database path **cut the largest finding by 74 %** and
retracted three others outright. Those corrections are §9.

What survives with proof-grade evidence:

1. **A correction leaves no trace at all.** Live: correcting `phone` left
   `user_profiles.updated_at` unchanged. `set_updated_at` is attached to seven tables —
   **including `coach_notes`** — but not to `user_profiles`. The coach's private notes
   about a member are timestamped; the member's correction of their own health record
   is not.
2. **`saveSettings` has no callers.** Cycle length and period length are **read** by
   `cycle_provider:23–24` and defaulted to **28/5**. A member with a 35-day cycle gets
   28-day phase predictions and there is **no write path at all**.
3. **The UI deselects gender and the payload discards it** — the clearest instance of
   the guarded-write class, because the intent to clear is explicit in the UI.
4. **`CycleService` cannot report failure**, and on a null uid returns as though it
   succeeded.

---

## 2 · Governance / concurrency

Tree clean except another workstream's untracked `d09-assessment-access.mjs` —
untouched. Second worktree `wrk02-negative-control` @ `70a647b` — untouched. No
concurrent agent activity. All commits used explicit paths.

---

## 3 · Categories completed

| Category | Status |
|---|---|
| C — health/fitness correction rights | **COMPLETE** |
| D — deletion/correction interactions, failure surfacing | **COMPLETE** |
| Guarded-write class (systematic) | **COMPLETE, detector validated** |
| Privacy-policy correction claim | **COMPLETE** |
| Auditability of corrections | **COMPLETE (live)** |
| E — data-subject access (viewability) | **COMPLETE** |
| F — coach-authored records | **COMPLETE** |

---

## 4 · Correction-rights matrix

**(a)** UI corrects · **(b)** corrects but cannot clear · **(c)** backend permits, no UI ·
**(d)** intentionally prohibited · **(e)** not demonstrable

| Record | Edit | Clear | DB accepts | UI exposes | Failure surfaced | Auditable | Class |
|---|---|---|---|---|---|---|---|
| first / last name | ✓ | ✓ | ✓ | ✓ | ✓ snackbar | **✗** | (a) |
| **gender** | ✓ | **UI deselects, write discards** | ✓ | partial | ✓ | ✗ | **(b)** |
| phone, height, weight, goal weight | ✓ | **✗ silently ignored** | ✓ | partial | ✓ | ✗ | **(b)** |
| date_of_birth, fitness_goal, activity_level, training_location, nutrition_goal | ✓ | **no clear control exists** | ✓ | partial | ✓ | ✗ | (c)* |
| email | ✗ | ✗ | ✓ | **none** | — | ✗ | (c) |
| PAR-Q, medical_conditions, injury_description | ✗ | ✗ | **✓ incl. clearing** | **none** (intake unreachable) | — | ✗ | (c) |
| dietary_restrictions, food_allergies | ✗ | ✗ | ✓ | none | — | ✗ | (c) |
| consent_agreed / consent_date | ✗ | ✗ | ✓ **self-writable** | none | — | ✗ | (c) → §11 |
| weight_logs | ✗ | ✗ | UPDATE+DELETE ✓ | insert only | — | ✗ | (c) |
| body_measurements | ✗ | ✗ | ✓ | insert only | — | ✗ | (c) |
| nutrition_logs | ✗ | ✗ | ✓ | insert only | — | ✗ | (c) |
| **cycle_settings** | **✗** | ✗ | ✓ | **no caller — dead write path** | — | n/a | **(c) VERIFIED DEFECT** |
| cycle_logs | state only | ✗ | ✓ | `end_date` transition only | **✗** | ✗ | (c) |
| cycle_symptoms · `symptoms` | ✓ | **✓ works** | ✓ | ✓ | **✗** | ✗ | (a) |
| cycle_symptoms · `energy`/`mood` | ✓ | n/a — non-nullable, default 3 | ✓ | ✓ | ✗ | ✗ | (a)† |
| cycle_symptoms · `flow`/`notes` | ✗ | ✗ | ✓ | **no UI** | — | ✗ | (c) |
| weekly_checkins | ✓ upsert | ✓ `notes ?? ''` | ✓ | **gate blocks re-entry** | ✓ **correct** | ✗ | (c) |
| workout_set_logs | ✓ | — | ✓ | ✓ re-log corrects | — | ✗ | (a) |
| goals | ✓ | ✓ | ✓ | ✓ full CRUD | — | **✓ trigger** | (a) |
| ai_memories | ✓ | ✓ | ✓ | long-press only (OD-60) | ✓ (fixed) | ✗ | (a) |
| action_items `client_notes`/`proof_url` | ✗ | ✗ | ✓ | **never passed by the caller** | — | ✗ | (c) |
| coach_notes | ✗ | ✗ | — | **(d)** migration 018:25 — *"the client must never see these"* | — | ✓ trigger | **(d)** |

\* the guard is *moot* for these: the UI offers no clear affordance, so this is a missing
control rather than a discarded correction.
† a slider that defaults to 3 records "3" even if untouched — "neutral" is
indistinguishable from "not answered". Minor, recorded.

---

## 5 · Guarded-write findings (validated)

**Detector validated before use** (instruction 9): 3/3 known-positives matched
(`gender`, `energy`, `phone`), 4/4 known-negatives correctly rejected (unconditional
write, `notes ?? ''`, `uid == null` guard, plain map entry).

| Candidate | Verdict |
|---|---|
| `phone`, `height_cm`, `weight_kg`, `weight_goal_kg` | **TRUE DEFECT** — TextFields the user can empty; the clear is discarded |
| **`gender`** | **TRUE DEFECT, strongest** — `_gender = _gender == 'Male' ? null : 'Male'` is a deliberate deselect; `if (_gender != null)` then drops it |
| `date_of_birth`, `fitness_goal`, `activity_level`, `training_location`, `nutrition_goal` | **NOT this class** — no clear affordance exists; separate (lesser) gap |
| `avg_cycle_length`, `avg_period_length` | **MOOT** — `saveSettings` is unreachable |
| `energy`, `mood` (symptoms) | **FALSE POSITIVE** — non-nullable locals (`int energy = 3`), guard can never fire |
| `flow`, `notes` (symptoms) | **FALSE POSITIVE** — no UI passes them; unimplemented, not un-clearable |
| `client_notes`, `proof_url` | **FALSE POSITIVE** — the only caller passes neither |
| `p_program`, `p_subject`, `p_note`, `token` | **EXCLUDED** — RPC parameters / invite token, not user data |
| `advanced_progression`, `beginner_modification`, `image_url` | **EXCLUDED** — exercise-library content, not subject PHI |

**Validated true set: 5 fields** (was reported as 19).

---

## 6 · Silent-failure findings — a taxonomy, not one label

Instruction: *do not call something a silent failure merely because there is no
try/catch*. Following the actual `Future` error-propagation path gives four distinct
behaviours. **There is no global handler** — no `runZonedGuarded`, `FlutterError.onError`
or `PlatformDispatcher.onError` in `main.dart` or `core/` — so an unhandled async error
reaches the console only.

| # | Behaviour | Where | Severity |
|---|---|---|---|
| 1 | **Silent success** — method returns normally, sheet pops, refresh fires, **nothing written** | `CycleService` × 3 when `uid == null` | **High** |
| 2 | **No feedback, sheet stays open** — `await` rethrows, so `Navigator.pop` never runs; no message | `CycleService` × 3 on a DB error | Medium |
| 3 | **No feedback, wrong state persists** — `setState` flips first, `_saveToggle` **not awaited**, never reverted | `notification_preferences_screen` × 6; `_persistUnit` (fully silent `catch (_) {}`) | Medium |
| 4 | **No feedback, state self-corrects** — `bool` discarded, then `ref.invalidate` refetches truth so the tick reverts unexplained | `action_center_screen:218–226` | Low |

Type 4 is notable because the *service* is correct (`completeActionItem` returns `bool`,
try/catch, `return false` on null uid) and the **caller throws the signal away** — the
mirror image of `CycleService`, where the callers are fine and the service cannot speak.

`daily_checkin_screen` + `submitWeeklyCheckin` get both halves right, which is what makes
all four deviations rather than an absent convention.

---

## 7 · Privacy-policy matrix

| Claim | Actual control | DB support | UI support | Failure feedback | Status |
|---|---|---|---|---|---|
| *"update your personal information directly within the app"* | name + some profile fields | **full** | **partial** | yes | **DISCREPANCY — High** |
| *"...request a full export ... from Profile → Settings → Account"* | none | n/a | **none** | n/a | **DISCREPANCY — High** |
| *"...disable marketing notifications from Profile → Settings → Notification Preferences"* | exists | ✓ | ✓ | **optimistic, never reverted; silent on null uid** | **DISCREPANCY — Medium** |
| *"We provide data exports in JSON or CSV format on request."* | manual channel | n/a | n/a | n/a | not contradicted |
| *"Deleting your account from inside the app is not available yet."* | email channel | n/a | n/a | n/a | **ACCURATE** |

No legal copy was read beyond these phrases, and none was altered.

---

## 8 · Live verification evidence

Protocol: capture → mutate → observe → restore → re-read → assert. Every run below ended
with restoration proven.

| Test | Result |
|---|---|
| Subject corrects 7 intake/health fields on own row | PERMITTED 7/7 · `MATCHES ORIGINAL: True` |
| Subject clears `parq_answers`→`{}`, `activities`→`[]` | PERMITTED · restored |
| Subject clears `phone`/`medical_conditions`/`dietary_restrictions`→`''` | PERMITTED · restored |
| Subject writes `email` | PERMITTED at DB level |
| DELETE grant across 9 health tables | 8 granted; **`weekly_checkins` denied `42501`** |
| End-to-end erasure with negative control | attacker DELETE on owner's real row → **0 rows**; owner → **1 row**; net state unchanged |
| **Correction timestamping** | `phone` corrected → **`updated_at` did NOT move**; restored |
| Privileged columns (`role`, billing, Stripe) | rejected `42501` |

`weekly_checkins` DELETE being deliberately denied while the other eight are granted is
the strongest evidence those grants are **intended**, not accidental.

---

## 9 · False positives and retractions

Four of my own claims did not survive the disproof pass. Recorded, not quietly dropped.

| Claim | Retraction |
|---|---|
| *"19 PHI-relevant un-clearable fields"* | **Overclaim → 5.** Tracing each UI path showed most candidates have no clear affordance, non-nullable sources, no UI at all, or are RPC parameters. |
| *"CORR-7: `client_notes` written only at completion, no later edit"* | **WRONG.** The only caller passes neither `notes` nor `proofUrl`, so the field is **never written**. It is an unimplemented feature, not a write-once field. |
| *"cycle symptoms `energy`/`mood`/`flow`/`notes` are un-clearable"* | **FALSE POSITIVE.** `energy`/`mood` are non-nullable locals; `flow`/`notes` have no UI. |
| *"`submitCheckin` / `hasSubmittedThisWeek` are dead code"* (previous turn) | **MY ERROR** — I grepped names that do not exist. Real: `submitWeeklyCheckin`, `weekStatus`, both called. |

**Methodology correction:** I grepped a non-existent method name **twice**
(`submitCheckin`, `completeItem`). Method names are now enumerated from the source
before any caller trace. Both errors were caught before reaching a finding.

**Mutation correction:** an earlier M2 recorded as "SURVIVED" was an **invalid
mutation** — it inserted `try {` and never a `catch`, so the assertion was correctly
unmoved. Re-run properly: KILLED.

---

## 10 · Runtime / environment blockers

| Blocker | State |
|---|---|
| Disk | **288 MiB, 99 %** — fell from 822 MiB during this phase |
| Docker | DOWN |
| Devices/simulators | 0 |
| `QA_SERVICE` | absent |

### The disk problem is probably not this repository

`df` reports **245 GB total, 18 GB used, 288 MB available, 99 % full** — roughly
**211 GB unaccounted for**. `tmutil listlocalsnapshots /` shows **three APFS local
snapshots**, one of them `com.apple.os.update-MSUPrepareUpdate` — a **staged macOS
update**. That is the likely holder of the missing space.

This repository's caches total **362 MB** (`.dart_tool` 267 MB, `build` 95 MB), so
deleting them would not meaningfully help and would force a full rebuild the volume
may not have room to complete. **I did not delete anything.** Clearing the staged
update or its snapshots is a system-level action on the owner's machine and is theirs
to take — flagged, not performed.

**Degrading, and now affecting QA itself.** A `flutter test` run stalled at **0 % CPU with
no output** and had to be killed (exit 144); a second full-suite run exceeded its window
and was backgrounded. Disk pressure has crossed from blocking *runtime builds* to
slowing the *test suite*. No build was attempted.

**Runtime-unverified (all of §6):** whether the sheet visibly stays open on a DB error;
whether the toggle visibly stays flipped; whether the action-item tick visibly reverts.
All are source- and propagation-verified, none observed in a running app.

---

## 11 · Owner decisions

1. **Correction scope** — expose the DB-granted rights, or amend *"directly within the app"*.
2. **Erasure** — should a member delete a weight log, measurement, nutrition entry or
   cycle log? The DB permits it; `weekly_checkins` is the deliberate exception.
3. **PAR-Q amendment** — clinical; migration 115 derives `risk_level` from it for the
   coach and the AI, so a stale PAR-Q is a safety question.
4. **`consent_agreed` / `consent_date` self-writable** — should a consent record be
   client-writable, or server-stamped and append-only?
5. **Correction auditability** — should corrections to health fields be timestamped or
   logged? Today `coach_notes` is timestamped and the member's own record is not.
6. **`coach_notes`** — the product rule is explicit; whether PHI held about a subject who
   may never see it is acceptable is a legal question.
7. **Coach-authored records** — no correction/appeal workflow exists for a client who
   disputes what a coach recorded about them.
8. **Cycle settings** — `saveSettings` is unreachable and predictions run on 28/5
   defaults. Build the control, or state that cycle length is not configurable.

---

## 12 · Security / HIPAA implications

| Safeguard | Status |
|---|---|
| Least privilege on correction | **VERIFIED** — own row only; cross-user write → `rows=0` |
| Integrity of privileged fields | **VERIFIED** — `role`/billing/Stripe → `42501` |
| Amendment of records | **CONTROL GAP** — backend capable, product surface absent |
| **Integrity / auditability of amendments** | **CONTROL GAP — live-verified** — no audit table and `updated_at` does not move |
| Data-subject access to own record | **CONTROL GAP** — 17 fields neither viewable nor exportable |
| Consent-record integrity | **EVIDENCE REQUIRED** — self-writable |
| Failure transparency on PHI writes | **CONTROL GAP** — §6 types 1–4 |

---

## 13 · Remaining untestable items

| Item | Blocker |
|---|---|
| `coach_notes` client-invisibility | 0 rows — **NOT DEMONSTRATED**; policy source explicit |
| All §6 UI behaviours | runtime (disk) |
| Column-level grant introspection | Docker |
| Coach-authored correction workflow | none exists to test |

---

## 14 · Recommended next phase

1. **Reclaim disk** — it has now interrupted the test suite twice.
2. Remediation queue, in order: **CycleService failure reporting** (cheapest, highest
   consequence — `bool` + snackbar, matching `submitWeeklyCheckin` beside it), then the
   5 guarded-write fields, then `cycle_settings` reachability.
3. Put §11 to the owner; items 1 and 2 gate the rest.
4. `QA_SERVICE` + fixtures remains the highest-leverage unblock across all phases.

---

## 15 · Final status

| | |
|---|---|
| Tests | **1,631 pass / 9 skipped** — *last completed full run, earlier this session.* **The full suite did not complete this turn:** the run stalled and was killed at ~1,197 tests when free disk fell to 225 MiB. The new guard passes **7/7** in isolation; the two `gender` assertions added afterwards have **not** been through a full-suite run. |
| Analyzer | **0 errors** |
| Runtime | **BLOCKED** — disk 785 MiB, Docker down, 0 devices |
| Live schema | reachable via anon + fixture identities; introspection blocked |
| Production files changed | **0** |
| Migrations changed | **0** |
| Guard mutations | **8 killed + 1 correct no-alarm** |
| Open findings | CORR-1, CORR-2, CORR-3 (5 fields), CORR-4, CORR-5, CORR-6, CORR-8 (cycle settings), CORR-9 (no correction audit trail) |
| Retracted | 4 (§9) |
| Owner decisions | 8 (§11) |

**QA BLOCKED — CORRECTION-RIGHTS DISCOVERY EXHAUSTED.**

The correction-rights surface has been examined to the limit of this environment and no
further static or live-database evidence is available. **"Exhausted" is not claimed
outright** because a material test class — every UI behaviour in §6 — remains
runtime-unverified, and the environment that would verify it is degrading rather than
improving.
