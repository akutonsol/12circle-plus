# QA Workstream B — Error Contract & Failure-Semantics Audit

**Root cause under audit:** **RC-C — "errors are returned as valid empty values."**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Scope:** `apps/mobile/lib`, `apps/mobile/tool`, `apps/api/src`, `supabase/functions`,
RPC callers, providers/notifiers, services/repositories, and the workout / program /
nutrition / check-in / community / AI flows.
**Environments:** static source audit only. **Production `nxdbooufqzkpslkcogxc` was not
contacted. QA `eyqtldjqpgpljlqvpowh` was not written to.** No live probe was needed —
every finding below is proven from committed source, and every line reference is a
verified location in this working tree.

**Baseline measured this session:** Flutter `apps/mobile` **610 passed, 0 failed** ·
API `apps/api` **58 passed, 0 failed**. After this workstream's additions:
**623 passed, 0 failed** (13 new static guards) · API unchanged.

**This is a discovery/reconciliation workstream. No product behaviour was changed.**
The only code added is `apps/mobile/test/unit/error_contract_guard_test.dart` — static
guards that read committed source and assert facts already true of the tree.

---

## 0. What RC-C actually is

The Phase 2 reconciliation named it in one line. Having now audited the whole
repository, the defect is sharper than "some catch blocks return `[]`", and it has
**two mechanically distinct halves** that need different fixes:

| Half | Mechanism | Where it lives |
|---|---|---|
| **C-1 · Swallowed exception** | A thrown failure is caught and converted into a value the domain treats as legitimate — `[]`, `null`, `false`, `0`, `{}`, `''`, a synthetic model object, or a discarded `void`. | **234 sites**, Dart and TypeScript |
| **C-2 · Silent write drop** | No exception is ever thrown. PostgREST answers an RLS-filtered or id-missed `UPDATE`/`DELETE` with **HTTP 200 and zero rows**. `await db.update(...); return true;` therefore reports a write that never happened. | Every unverified write; ~20 consequential call sites |

C-2 is the more dangerous half because no amount of `catch` discipline finds it. It is
already understood in this codebase — two call sites solve it correctly and say so in a
comment — but the pattern was never generalised.

Both halves collapse to one sentence, which is the axiom this report builds on:

> **An empty value must be an answer, never a symptom.**

### 0.1 The amplifier: there is no observability at all

`apps/mobile` has **no error-reporting infrastructure of any kind** — no Sentry, no
Crashlytics, no logger package in `pubspec.yaml`, no `debugPrint`, no `developer.log`.
Diagnostics amount to **7 `print()` calls**, which are stripped or ignored in release
builds.

So all 234 swallow sites are invisible **twice over**: the user cannot tell a failure
from an empty state, and neither can the operator — ever, in any environment, after the
fact. Every finding in this report is currently unmeasurable in production.

This is why §6 sequences the observability sink **first**. It is not a nice-to-have
ordered by taste; without it, no other item in this report can be verified as fixed in
the field, and no regression in it can be detected.

### 0.2 The inventory

Measured across `apps/mobile/lib`, `apps/mobile/tool`, `apps/api/src` and
`supabase/functions` (excluding `node_modules`, `build`, `*.spec.ts`):

| Failure converted to | Sites |
|---|---:|
| discarded entirely (empty `catch` body, `void`) | 80 |
| `null` | 57 |
| `false` | 43 |
| `[]` | 42 |
| `0` | 9 |
| `''` | 2 |
| a synthetic fallback object | 1 |
| **Total** | **234** |

| Layer | Sites |
|---|---:|
| service / repository | 147 |
| UI / presentation | 49 |
| provider / notifier / domain | 21 |
| core / util | 9 |
| Edge Function | 7 |
| tooling | 1 |

Concentration is extreme and is itself a finding: **one file
(`custom_exercise_service.dart`, 816 lines) holds 54 of the 234** — 23% of the
repository's total in 1.4% of its Dart source.

### 0.3 What Phase 2 already fixed — and the shape of what it left

Phase 2 closed RC-C **at the provider layer of the workout domain only**, and did it
well: `workout_provider.dart` now contains no `catch` at all, `generateAiWorkout`
raises, `getSessionCompletedSets` and `saveSetLog` propagate, `materializeWeek`
propagates the engine's new `RAISE`.

But the swallow **moved down a layer rather than away**. `WorkoutService` still holds
**13 swallow sites**, and the providers Phase 2 did not name are layered directly on
top of them:

```
completionRateProvider  ──►  WorkoutService.getCompletionRate()  ──►  catch (_) { return 0; }
personalRecordsProvider ──►  WorkoutService.getPersonalRecords() ──►  catch (_) { return []; }
workoutHistoryProvider  ──►  WorkoutService.getWorkoutHistory()  ──►  catch (_) { return []; }
```

Those providers are *error-blind by construction*: they cannot produce
`AsyncValue.error` because nothing beneath them can throw. **A partial fix at one layer
does not compose.** This is the central lesson for the remediation sequence in §6 and
the reason the contract in §4 is expressed as a per-layer obligation rather than a list
of call sites.

### 0.4 What is already right — the reference implementations

Four places in this tree already implement the contract. They are not exceptions to be
tolerated; they are **the specification, written in code**, and §4 generalises them.

| Reference | What it establishes |
|---|---|
| **`apps/api/src`** — the entire NestJS layer | The complete failure taxonomy. A misconfigured server is `503`, not `401` ([`supabase-token.service.ts:57-74`](../apps/api/src/auth/supabase/supabase-token.service.ts#L57-L74), with the rule stated in its own comment). An empty AI answer is **refused**, not returned as success ([`ai-nutrition.service.ts:113-118`](../apps/api/src/ai/ai-nutrition.service.ts#L113-L118)). Upstream detail is **logged, not returned** (`toClientSafeError`). **Two catch blocks in the whole package**, both of which re-raise as a typed exception. |
| **`activeWorkoutRestorationProvider`** [`workout_provider.dart:458-474`](../apps/mobile/lib/features/workout/domain/workout_provider.dart#L458-L474) | The three-state UI contract: loading / data-`null` / **error with retry**, documented in the provider's own doc comment. Backed by widget tests (`WKT-112`). |
| **`CoachingModeNotifier.setMode`** [`coaching_mode_provider.dart:71-87`](../apps/mobile/lib/features/coaching_mode/domain/coaching_mode_provider.dart#L71-L87) | The C-2 solution: `.select('id')` → zero rows → `throw` → **roll back the optimistic state** → `rethrow`. |
| **`CustomExerciseService.updateExercise`** [`custom_exercise_service.dart:716-726`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L716-L726) | The C-2 solution stated in a comment: *".select() so an RLS-filtered update (0 rows, no error) is detectable."* Applied in exactly one of that file's ~20 write methods. |

All four are now pinned by the guards added in §8, so they cannot be quietly undone.

---

## 1. Classification key

Per the brief:

| | Class | Meaning |
|---|---|---|
| **A** | Legitimate empty state | The empty value genuinely *is* the domain answer. Leave alone. |
| **B** | Recoverable error | Transient; the honest answer is "couldn't load — retry". |
| **C** | Fatal / domain error | A domain invariant or contract was violated. Must not be papered over. |
| **D** | Security-sensitive | Authorization, entitlement, moderation, or privilege state. |
| **E** | Data-loss risk | User work is destroyed, overwritten, or unrecoverably not persisted. |
| **F** | Observability-only | Suppressing it is defensible; suppressing it *silently and unrecorded* is not. |

**The brief's guardrail is respected throughout: no legitimate empty state is
reclassified as an error.** Class A sites are named in §3.5 and explicitly left alone.

---

## 2. High-severity findings

Every finding carries: exact file · exact function · current behaviour · expected
behaviour · impact · root cause · proposed canonical error contract · dependencies ·
priority.

---

### EC-01 · There is no error-reporting sink, so every swallowed failure is permanently invisible
**Class: F (repo-wide) · Priority: P0 · Layer: platform**

| | |
|---|---|
| **File** | `apps/mobile/pubspec.yaml`; all of `apps/mobile/lib` |
| **Function** | n/a — an absent capability |
| **Current** | No Sentry, no Crashlytics, no logging package, no `debugPrint`, no `developer.log`. 7 `print()` calls total, inert in release. 234 failure sites report to nothing. |
| **Expected** | One `reportFailure(AppFailure)` sink that every sanctioned swallow calls, and that every propagated failure passes through on its way to the UI. |
| **Impact** | Nothing in this report is measurable in the field. A fix cannot be verified as effective; a regression cannot be detected. The `catch (_) {}` sites that *are* legitimate (§3.5) are indistinguishable from the ones that are not. |
| **Root cause** | Observability was never introduced; `catch (_) {}` became the cheapest way to make a crash stop. |
| **Contract** | §4 rule **O**: no swallow is sanctioned unless it records. |
| **Dependencies** | **None. This blocks nothing and unblocks everything.** |
| **Priority** | **P0 — do this first.** It is additive, cannot change behaviour, and makes every subsequent phase verifiable. |

---

### EC-02 · AI decision inputs degrade silently to empty — the client's injuries are dropped and the workout is still generated
**Class: C + D · Priority: P0 · Layer: Edge Function**

| | |
|---|---|
| **File** | [`supabase/functions/ai-coaching-engine/index.ts:22-27`](../supabase/functions/ai-coaching-engine/index.ts#L22-L27) and [`:129-170`](../supabase/functions/ai-coaching-engine/index.ts#L129-L170); [`supabase/functions/ai-generate-workout/index.ts:62-80`](../supabase/functions/ai-generate-workout/index.ts#L62-L80) |
| **Function** | `recent()` in the coaching engine; the `Promise.all` context load in the workout generator |
| **Current** | `recent()` is literally `try { … return data ?? []; } catch { return []; }` — and it ignores the destructured PostgREST `error` besides. In the workout generator, six parallel reads are destructured as `{ data }` with **`error` never inspected**, then defaulted: `const mem = (memRes.data ?? [])`, `const library = ((libRes.data ?? []) …)`. A failed read of `ai_memories` therefore yields `injuries: []`. |
| **Expected** | A failed read of an input that **constrains a safety decision** must fail the decision closed — `502`, not a `200` carrying a workout built without the constraint. |
| **Impact** | The system prompt instructs the model to *"AVOID anything contraindicated by their injuries"* and the engine hands it an empty injury list. **A transient RLS or network failure produces a real training prescription for a real injured client with their injuries silently absent, returned as HTTP 200 and persisted as an `ai_insights` row.** The same path drops `contraindications` when `libRes` fails, and an empty library produces an ungrounded selection — nothing verifies the returned exercise names against the library, so "select ONLY from the LIBRARY" is a prompt instruction with no enforcement. |
| **Amplifier** | The coaching engine's confidence score ([`:182-196`](../supabase/functions/ai-coaching-engine/index.ts#L182-L196)) is computed **from the lengths of those same silently-emptied arrays**. A failed read is scored identically to a brand-new user. The number that exists to tell a client how much to trust the advice is computed from data whose absence may be a bug, and cannot tell the difference. |
| **Governance** | Directly violates decision-log invariants *"the engine decides, the AI explains"* and *"every recommendation produces a decision trace"* — a trace recorded over silently-degraded inputs is not an audit record. |
| **Root cause** | RC-C, applied to engine inputs rather than to UI reads. |
| **Contract** | §4 rule **S — the Safety Input Rule** (new; see §4.4). Plus rule **E1**: every PostgREST destructure in an Edge Function checks `error`. |
| **Dependencies** | Needs the ENV-01/02 QA Edge Function deployment to live-verify (Phase 4). The **source fix is independent** and can land now. |
| **Priority** | **P0** |

---

### EC-03 · Onboarding still marks itself complete after the save fails, discarding PAR-Q, allergies and consent
**Class: E + D · Priority: P0 · Layer: UI/service · Status: CON-02, re-verified UNFIXED**

| | |
|---|---|
| **File** | [`apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart:215-228`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L215-L228); `_saveProgress` at [`:150-173`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L150-L173) |
| **Function** | `_finish()`, `_saveProgress()` |
| **Current** | If the full profile upsert throws, the handler explicitly writes `{'onboarding_complete': true, 'onboarding_step': 0}` and routes to `/home`. `_saveProgress` Phase 2 is `catch (_) {}`, dropping the whole step's data on any one field's type rejection. |
| **Expected** | Completion is a fact about the **data**, not about the navigation. Never set `onboarding_complete` on a failed save; keep the answers in memory; state the failure; offer retry. Preserve the good half — the Phase 1 step/flag write that keeps resume working. |
| **Impact** | PAR-Q answers, medical conditions, injuries, allergies, dietary restrictions, goal, experience **and consent** are discarded while the user is recorded as fully onboarded and can never return to the flow. This is the parent of CON-04 and CON-08 and is the input side of EC-02 and EC-04. |
| **Root cause** | RC-C, with the fail-open made explicit in a comment ("at minimum mark onboarding done so the user isn't looped back here"). The intent is sound; the implementation trades correctness for it silently. |
| **Contract** | §4 rules **W** (a write that must land is verified) and **U** (a failed write is stated, never navigated past). |
| **Dependencies** | **CON-03** (`dietary_restrictions` serializer/type mismatch) is the failure that triggers this today, so 3A precedes 3B in the existing plan. That ordering stands. |
| **Priority** | **P0** |

---

### EC-04 · Absent risk data renders to the coach as "low risk"
**Class: C + D · Priority: P0 · Layer: UI**

| | |
|---|---|
| **File** | [`client_detail_screen.dart:31`](../apps/mobile/lib/features/dashboard/presentation/client_detail_screen.dart#L31), [`:73`](../apps/mobile/lib/features/dashboard/presentation/client_detail_screen.dart#L73), [`:206`](../apps/mobile/lib/features/dashboard/presentation/client_detail_screen.dart#L206), [`:789`](../apps/mobile/lib/features/dashboard/presentation/client_detail_screen.dart#L789) |
| **Function** | the risk-badge builders — `d['risk_level'] as String? ?? 'low'` at four call sites |
| **Current** | A null `risk_level` renders as **`'low'`**. `currentUserProfileProvider` ([`auth_provider.dart:103-105`](../apps/mobile/lib/features/auth/domain/auth_provider.dart#L103-L105)) already returns `null` for the entire profile on any read failure, so "the read failed" and "the client is low risk" are the same pixel. |
| **Expected** | Absent risk data renders as **"not assessed"** and is visually distinct from an assessed `low`. Never a fabricated clinical grade. |
| **Impact** | Product bible §3: *"A great coach protects the client. Injury signals and low recovery override progression."* A high-risk PAR-Q is the strongest safety signal the product collects. Combined with EC-03 — which is the reason `risk_*` is frequently null — **a coach is affirmatively told a client is low risk when the client's PAR-Q was never saved.** The default points in exactly the wrong direction: it is fail-*open* on a safety signal. |
| **Root cause** | RC-C at the render boundary: a null-coalescing default that invents a domain value. |
| **Contract** | §4 rule **N**: `??` may supply a *presentation* default (a label, a placeholder), never a *domain* value — and never a graded safety value. This mirrors the load rule the Workout Domain Contract already adopted (`null` ≠ `0`). |
| **Dependencies** | Fixing the display is independent and safe. Making the value *reliable* depends on EC-03 → CON-03. The *policy* half (what a high-risk PAR-Q should do to training) is **CON-04 / Q-4 and remains product authority — not in scope here.** |
| **Priority** | **P0** for the display honesty; the policy stays blocked on Q-4. |

---

### EC-05 · Finishing a workout swallows both persistence steps and shows the celebration anyway
**Class: E + C · Priority: P1 · Layer: UI + service**

| | |
|---|---|
| **File** | [`active_workout_screen.dart:608-620`](../apps/mobile/lib/features/workout/presentation/active_workout_screen.dart#L608-L620); [`workout_service.dart:52-66`](../apps/mobile/lib/features/workout/data/workout_service.dart#L52-L66) |
| **Function** | `_completeWorkout()`; `WorkoutService.logWorkout()` |
| **Current** | `await _workoutService.logWorkout(log)` — whose entire body is wrapped in `catch (_) {}`. Then `await _sessions.completeSession(...)` inside its own `catch (_) {}`. Both failures are discarded; execution continues to award score points, reset state, invalidate the session providers, and **show the "Workout Complete" dialog**. |
| **Expected** | Completion is a persisted fact. If `completeSession` does not land, the client is told, the session row is left resumable, and the celebration is not shown. |
| **Impact** | **This resurrects WKA-04 — the orphaned `in_progress` session — through the error path, after Phase 2 closed it through the happy path.** The client is told the workout is complete; the session row stays `in_progress`; the Resume banner keeps offering a finished workout; `workout_sessions_one_active_per_user` then constrains the next workout's start; and `getCompletionRate()` never counts it, so adherence overstates. The `workout_logs` row can be lost independently, taking streak and weekly-count with it. |
| **Root cause** | RC-C in the one place the domain is least tolerant of it: the transition that makes training history real. |
| **Contract** | §4 rule **T**: a state-machine transition may not be reported to the user until it is persisted. |
| **Dependencies** | None. `completeSession` already propagates from the store; only the two call-site catches and `logWorkout`'s need removing. |
| **Priority** | **P1** |

---

### EC-06 · A failed nutrition read silently zeroes the day's earned nutrition score
**Class: E · Priority: P1 · Layer: service**

| | |
|---|---|
| **File** | [`nutrition_service.dart:75-103`](../apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L75-L103) and [`:105-129`](../apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L105-L129); [`score_service.dart:43-46`](../apps/mobile/lib/features/coach/data/score_service.dart#L43-L46) and [`:64-84`](../apps/mobile/lib/features/coach/data/score_service.dart#L64-L84) |
| **Function** | `_awardNutritionScore()` → `getTodayTotals()` → `ScoreService.addNutritionPoints()` |
| **Current** | `getTodayTotals()` returns `{calories:0, protein:0, carbs:0, fat:0}` on any read failure. `_awardNutritionScore` consumes that, computes `completionPct == 0`, and calls `addNutritionPoints(0)`. `_updatePoints` **sets** `nutrition_points` (it does not increment) and upserts the merged row. |
| **Expected** | A failed read must not be an input to a scoring write at all. Either the read propagates, or the scoring step is skipped when its input is not trustworthy. |
| **Impact** | One transient read failure at meal-log time **permanently overwrites the day's earned nutrition score with 0**, recomputes `total_score`, and persists it. The 12 Circle Score is a headline product surface and feeds the coach leaderboard. The user sees points disappear with no cause and no path to recovery. |
| **Root cause** | RC-C compounded by a read-modify-write that trusts a defaulted read. |
| **Contract** | §4 rule **D**: a defaulted value may never become the input to a persisted decision. This is the client-side statement of the same rule EC-02 states for the engine. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

### EC-07 · A failed check-in read fabricates a "pending" week, and re-submitting overwrites a reviewed check-in
**Class: E · Priority: P1 · Layer: service**

| | |
|---|---|
| **File** | [`weekly_checkin_service.dart:39-62`](../apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart#L39-L62) and [`:65-102`](../apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart#L65-L102) |
| **Function** | `getCurrentWeekCheckin()`; `submitWeeklyCheckin()` |
| **Current** | On a read failure, `getCurrentWeekCheckin()` swallows (`catch (_) {}`) and **falls through to construct a synthetic `WeeklyCheckin` with `status: CheckinStatus.pending`** and a `'pending-…'` id — a valid-looking domain object indistinguishable from a genuinely un-submitted week. `submitWeeklyCheckin()` then upserts on `(user_id, week_start_date)` with `'status': 'submitted'`. |
| **Expected** | A failed read propagates. `pending` must mean "this week has no check-in", nothing else. |
| **Impact** | A user whose read failed is shown an empty check-in form for a week they already submitted. Submitting it overwrites their answers **and resets `status` from `reviewed` back to `submitted`** — so the coach's `feedback_message` stops rendering (the model only surfaces feedback when `status == reviewed`), and the coach is re-notified to review a check-in they already reviewed. Health data the client entered is replaced; coaching work is hidden. |
| **Root cause** | RC-C producing a **synthesised domain object** — the most severe form, because it survives every downstream type check. |
| **Contract** | §4 rule **M**: a service may never manufacture a domain entity to stand in for a failure. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

### EC-08 · Coach feedback reports success when the write matched zero rows
**Class: C + D · Priority: P1 · Layer: service · The clearest instance of C-2**

| | |
|---|---|
| **File** | [`weekly_checkin_service.dart:145-171`](../apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart#L145-L171) |
| **Function** | `submitCoachFeedback()` |
| **Current** | `update({...}).eq('id', checkinId).select('user_id').maybeSingle()`. If the update matches **zero rows** — RLS denial, wrong id, a row deleted mid-flight — PostgREST returns success, `maybeSingle()` yields `null`, `clientId` is null, the client notification is skipped, and the method **`return true`**. |
| **Expected** | Zero rows is a refusal. Return false (or raise), state it in the UI, and never claim the feedback was delivered. |
| **Impact** | A coach writes feedback and recommendations, the UI confirms success, the client never receives it and is never notified. Coaching work is destroyed with a positive confirmation. **The fix is two lines** — the call already performs `.select('user_id')`; it simply never acts on the null. |
| **Root cause** | C-2. The verification is present; the check on it is missing. |
| **Contract** | §4 rule **W**. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

### EC-09 · The C-2 class — unverified writes reported as success
**Class: C, D where moderation/entitlement is involved · Priority: P1 · Layer: service**

The same shape as EC-08 across the repository. A PostgREST `UPDATE`/`DELETE` that
matches nothing is a **success response**, so every `await db.from(X).update(...);
return true;` is a false success under RLS denial or a stale id.

| Site | Why it matters |
|---|---|
| [`custom_exercise_service.dart:764-772`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L764-L772) `approveGlobalExercise` | **D.** An admin approves an exercise into the global library; the write is dropped; the UI says approved. Moderation state diverges from what the admin believes. Feeds the engine's L1 content per the MIE document. |
| [`custom_exercise_service.dart:777-785`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L777-L785) `rejectGlobalExercise` | **D.** The mirror: rejected content stays globally visible while the admin is told it was withdrawn. |
| [`custom_exercise_service.dart:738-750`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L738-L750) `submitForGlobalLibrary` | **D.** Comment says "goes live for all clients immediately" — unverified. |
| [`custom_exercise_service.dart:731-735`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L731-L735) `deleteExercise` | A deletion the coach believes happened. |
| [`goal_service.dart:54-67`](../apps/mobile/lib/features/goals/data/goal_service.dart#L54-L67) `updateProgress` | Goal progress silently not recorded. |
| [`action_item_service.dart:80-95`](../apps/mobile/lib/features/action_items/data/action_item_service.dart#L80-L95) | Coach-assigned action items marked done that were not. |
| [`messaging_service.dart:165-170`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L165-L170) | The `conversations.last_message` update — a conversation list that never advances. |
| [`ai_coach_service.dart:104-111`](../apps/mobile/lib/features/ai_coach/data/ai_coach_service.dart#L104-L111) `setPersona`, [`:158-167`](../apps/mobile/lib/features/ai_coach/data/ai_coach_service.dart#L158-L167) `addMemory` | **A dropped `addMemory('injury', …)` write is a safety input that silently never exists.** |
| [`platform_settings_service.dart:19-28`](../apps/mobile/lib/features/admin/data/platform_settings_service.dart#L19-L28) | **D.** Platform configuration believed changed and not changed. |

| | |
|---|---|
| **Expected** | Every write whose success is asserted to a user appends `.select(<pk>)` and treats zero rows as a refusal — the pattern `updateExercise` and `setMode` already implement. |
| **Root cause** | C-2. A PostgREST semantic that is easy to miss and was solved twice without being generalised. |
| **Contract** | §4 rule **W**. |
| **Dependencies** | None mechanically. Each site's *UI* response is a small behaviour change — from "saved" to "couldn't save" — which is a correction toward truth, but is user-visible; see §9. |
| **Priority** | **P1** (**P0** for `approveGlobalExercise` / `rejectGlobalExercise` / `platform_settings` if the moderation surface is in beta scope). |

---

### EC-10 · Two tables do not exist; every caller swallows the 404 forever
**Class: C + F · Priority: P1 · Layer: service/database · Status: CON-01 re-verified UNFIXED, plus its twin**

| | |
|---|---|
| **File** | [`checkin_service.dart`](../apps/mobile/lib/features/checkins/data/checkin_service.dart) — six call sites on `checkins`; [`coach_provider.dart:58-73`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L58-L73) — `coach_tips` |
| **Function** | `saveDailyCheckin`, `hasCheckedInToday`, `hasCheckedInThisWeek`, `saveWeeklyCheckin`, `getCheckinStreak`, `getRecentCheckins`; `coachTipProvider` |
| **Current** | Neither table is created by any migration. **This was verified exhaustively:** a cross-check of all 78 table names and all 47 RPC names referenced anywhere in `apps/mobile/lib` against every `CREATE TABLE/VIEW` and `CREATE FUNCTION` in `supabase/` finds **exactly these two missing, and zero missing RPCs.** Every call returns HTTP 404 `PGRST205` and every caller swallows it into `false` / `[]` / `0` / `null`. |
| **Expected** | Resolve the table question, then let a genuine failure surface. A feature that cannot reach its store must say so once, not report a plausible empty state forever. |
| **Impact** | `hasCheckedInThisWeek()` is permanently `false`; `getCheckinStreak()` permanently `0`; the coach dashboard's check-in count permanently zero; the coach tip permanently invisible. The daily check-in screen's **write** path is the one honest surface here — it shows "Failed to save. Please try again." — which is precisely why the read paths' silence is the defect. |
| **Root cause** | RC-C **masking** a schema gap. Without the swallow this would have been a 404 on day one. |
| **Contract** | §4 rule **B**: a store-unreachable error is never an empty domain answer. |
| **Dependencies** | **Blocked on Q-1** (is there a daily check-in distinct from the weekly one?). The reconciliation's recommendation — retire `checkin_service.dart`, migrate callers to `weekly_checkins` — stands. `coach_tips` needs the same call and has no product statement anywhere. |
| **Priority** | **P1**, blocked on product authority. **The guard added in §8 makes any *new* phantom table fail `flutter test` immediately.** |

---

### EC-11 · `WorkoutService` still swallows beneath now-propagating providers; `getCompletionRate()` fabricates an adherence figure
**Class: B, with C for the metrics · Priority: P1 · Layer: service**

| | |
|---|---|
| **File** | [`workout_service.dart`](../apps/mobile/lib/features/workout/data/workout_service.dart) — 13 sites: `:65`, `:211`, `:225`, `:258`, `:273`, `:290`, `:319`, `:328`, `:347`, `:376`, `:392`, `:404`, `:425`, `:438` |
| **Function** | `logWorkout`, `getWorkoutHistory`, `getSessionSetLogs`, `getExerciseProgression`, `getLoggedExerciseNames`, `getWeeklyWorkoutCount`, `getCurrentStreak`, `getTotalWorkoutCount`, `getCompletionRate`, `getPersonalRecords`, `getTotalVolumeLifted`, `getClientWorkoutStats`, `getClientPersonalRecords`, `getClientRecentSessions` |
| **Current** | Each returns `[]` or `0` on failure. Nine providers in `workout_provider.dart` are thin wrappers over them and therefore **cannot** produce an error state, despite that file having been cleaned of `catch` by Phase 2. |
| **Expected** | Propagate. The providers above them are already shaped to carry it; the UI states already exist for `activeWorkoutRestorationProvider`. |
| **Impact** | `getCompletionRate()` returning `0` is a **fabricated adherence figure**, not an absent one — the coach reads "0% completion" for a client whose sessions could not be read. `getTotalVolumeLifted()` → `0 kg`, `getPersonalRecords()` → "no PRs", `getCurrentStreak()` → "streak broken". These are the numbers the product is *about*. `logWorkout`'s `catch (_) {}` is the EC-05 data-loss path. |
| **Root cause** | RC-C, one layer below where Phase 2 stopped. **This is the concrete evidence that a per-layer fix does not compose.** |
| **Contract** | §4 rule **L2**: a service returns domain answers only. |
| **Dependencies** | None. The providers already propagate; only the service and the UI's empty-state widgets change. |
| **Priority** | **P1** |

---

### EC-12 · Habit writes are optimistic, swallow failure, and then award score from the un-persisted state
**Class: E · Priority: P1 · Layer: provider**

| | |
|---|---|
| **File** | [`habit_provider.dart:118-146`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L118-L146), [`:148-159`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L148-L159) |
| **Function** | `toggleComplete()`, `updateValue()` |
| **Current** | State is updated optimistically, the write is attempted, and failure is `catch (_) {}` with **no rollback**. `toggleComplete` then computes `completed` from the *optimistic in-memory* list and calls `addHabitPoints(completed, total)`. |
| **Expected** | The `setMode` pattern: on failure, roll back and surface. Do not derive a persisted score from unpersisted state. |
| **Impact** | The UI asserts a habit is complete; the database disagrees; the next `_load()` silently reverts it, so the user watches their own entry vanish. Meanwhile score points **were** written for the phantom completion, so the score and the habit log disagree permanently. |
| **Root cause** | RC-C plus optimistic-update-without-rollback — the exact failure `setMode` was written to avoid. |
| **Contract** | §4 rules **W** and **D**. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

### EC-13 · A failed message read renders as an empty conversation
**Class: B + E(perceived) · Priority: P1 · Layer: service**

| | |
|---|---|
| **File** | [`messaging_service.dart:178-188`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L178-L188), [`:18-57`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L18-L57), [`:222-233`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L222-L233) |
| **Function** | `getMessages()`, `getConversations()`, `getUnreadCount()` |
| **Current** | `[]`, `[]`, `0` on failure. `getConversations` `print()`s first — inert in release. |
| **Expected** | Propagate; the thread shows "couldn't load messages — retry". |
| **Impact** | The coach↔client channel is the relationship. A client opening a thread and seeing **nothing** concludes their coach never replied, or that their own messages were lost. `getUnreadCount() → 0` suppresses the badge that would have prompted them to look. Nothing is actually deleted, which is why this is *perceived* rather than actual data loss — but the user cannot know that. |
| **Root cause** | RC-C. |
| **Contract** | §4 rule **L2**. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

### EC-14 · Stripe Connect failures render as a real £0.00 balance and a disconnected account
**Class: C + F · Priority: P1 · Layer: service**

| | |
|---|---|
| **File** | [`payment_service.dart:101-115`](../apps/mobile/lib/features/payments/data/payment_service.dart#L101-L115) |
| **Function** | `connectBalance()`, `connectStripeStatus()` |
| **Current** | `connectBalance()` returns `{'pending': 0, 'available': 0}` on any failure. `connectStripeStatus()` returns `{'connected': false, 'charges_enabled': false, 'payouts_enabled': false}`. |
| **Expected** | Financial figures are never defaulted. Absent balance renders as "—" or "couldn't load". Connect status is tri-state: connected / not connected / **unknown**. |
| **Impact** | A coach with money in their Connect account is shown **a zero balance stated as fact** — the highest-trust number in the product, fabricated from a network error. A connected coach shown `connected: false` is prompted to re-run onboarding they have already completed. |
| **Root cause** | RC-C producing a synthetic object (same shape as EC-07). |
| **Contract** | §4 rules **M** and **N**. |
| **Dependencies** | None. |
| **Priority** | **P1** |

---

## 3. Full findings register

### 3.1 P0 — must close before further remediation phases

| ID | Finding | Class | Layer |
|---|---|---|---|
| **EC-01** | No error-reporting sink exists anywhere in `apps/mobile` | F | platform |
| **EC-02** | AI decision inputs (injuries, contraindications, library) degrade silently to empty; confidence is scored over them | C·D | edge fn |
| **EC-03** | Onboarding marks itself complete after a failed save (CON-02, unfixed) | E·D | UI/service |
| **EC-04** | `risk_level ?? 'low'` — absent safety data renders as an assessed low grade | C·D | UI |

### 3.2 P1 — release blockers

| ID | Finding | Class | Layer |
|---|---|---|---|
| **EC-05** | Workout completion swallows both persistence steps, shows the celebration | E·C | UI/service |
| **EC-06** | Failed nutrition read zeroes the day's persisted nutrition score | E | service |
| **EC-07** | Failed check-in read fabricates `pending`; re-submit overwrites a reviewed check-in | E | service |
| **EC-08** | `submitCoachFeedback` returns `true` on a zero-row update | C·D | service |
| **EC-09** | The C-2 class — ~10 unverified writes reported as success (incl. moderation, platform settings) | C·D | service |
| **EC-10** | `checkins` and `coach_tips` do not exist; all callers swallow the 404 (CON-01) | C·F | service/db |
| **EC-11** | `WorkoutService`'s 13 swallows sit beneath the providers Phase 2 fixed; `getCompletionRate` fabricates adherence | B·C | service |
| **EC-12** | Habit optimistic writes swallow failure, no rollback, score derived from unpersisted state | E | provider |
| **EC-13** | Failed message read renders as an empty conversation | B·E | service |
| **EC-14** | Stripe Connect failures render as a real zero balance / disconnected account | C·F | service |

### 3.3 P2 — important

| ID | Finding | Class | Detail |
|---|---|---|---|
| **EC-15** | Silent entitlement downgrade | D·B | [`payment_service.dart:190-196`](../apps/mobile/lib/features/payments/data/payment_service.dart#L190-L196) `clientPlan()` → `'free'` on error; [`:178-186`](../apps/mobile/lib/features/payments/data/payment_service.dart#L178-L186) `activeMembership()` → `null`; [`coach_program_service.dart:445-471`](../apps/mobile/lib/features/coach/data/coach_program_service.dart#L445-L471) `clientHasPaidPlan()` → `false`. **The direction is correct — all three fail *closed*, which is the right security posture.** The defect is the silence: a paying client is downgraded to free with no statement, and a coach is told a client has not paid when the check could not run. Contract: fail closed **and say so** (rule **X**). |
| **EC-16** | Plan generation failure ends onboarding silently | B·C | [`intake_flow_screen.dart:234-238`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L234-L238) — `generate_client_plan()` inside `catch (_) {/* generation must never block finishing onboarding */}`. The client lands on Home with no program and no retry. Compounds with Phase 2's (correct) change making `assignedWorkoutsProvider` return `[]` for "no program": the empty state is now *honest*, and the failure that caused it is invisible. |
| **EC-17** | `detectRisks()` fabricates a risk assessment, and its parser cannot work | C | [`ai_coach_service.dart:53-67`](../apps/mobile/lib/features/ai_coach/data/ai_coach_service.dart#L53-L67). Non-200 → `{'risk_level':'unknown','flags':[],'recommendation':''}`. Separately, `Uri.splitQueryString()` is applied to a **JSON** string — it splits on `&`/`=` and cannot yield `risk_level` from any well-formed response, so the `catch` branch fires on every call. **Currently unreferenced** — latent, not live. Delete or rewrite; do not leave a broken safety-assessment API in the tree. |
| **EC-18** | Nested fallback hides the real error | F | [`weekly_checkin_service.dart:120-142`](../apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart#L120-L142) — a failed join retries without the join and, failing again, returns `[]`. The retry is reasonable; discarding both causes is not. |
| **EC-19** | `custom_exercise_service.dart` — 54 swallow sites in 816 lines | B·D | 23% of the repository total. Its `lastError` field is a partial mitigation applied to ~30 of them and read by only some callers. Needs a single pass under the contract rather than 54 individual decisions. |
| **EC-20** | Notification inserts swallowed throughout | F | [`notification_service.dart:86-97`](../apps/mobile/lib/features/notifications/data/notification_service.dart#L86-L97), [`live_community_service.dart:136-138`](../apps/mobile/lib/features/community/data/live_community_service.dart#L136-L138), `active_workout_screen.dart:1731`, and others. **Sanctioned category (§5.1)** — a notification must not fail a user action. But unrecorded, so a systemically broken notification path is undetectable. Needs rule **O**, not propagation. |
| **EC-21** | The QA harness itself swallows | F | [`qa_suites.dart:337-341`](../apps/mobile/lib/features/qa/domain/qa_suites.dart#L337-L341) — `client_plan` RPC failure → `live = ClientPlan.free`, so an entitlement probe can certify the wrong tier for a paying tester. A QA tool that swallows produces false PASSes. Note `_table()` at [`:12-30`](../apps/mobile/lib/features/qa/domain/qa_suites.dart#L12-L30) does this **correctly** — it distinguishes a missing table (`42P01`/`PGRST205`) from an RLS denial. Apply that discipline to the rest of the file. |
| **EC-22** | Workout feedback dialog reports submitted on failure | C | `active_workout_screen.dart:1725-1732` — `catch (_) {}` immediately followed by `_submitted = true`. Feedback feeds `workout_feedback`, which the AI engine reads as a recovery signal. |

### 3.4 P3 — hygiene

| ID | Finding | Class |
|---|---|---|
| **EC-23** | 7 `print()` calls are the only diagnostics; inert in release. Subsumed by EC-01. | F |
| **EC-24** | `_saveElapsed` (`active_workout_screen.dart:570-575`), `_saveCursor`, `_cacheFoods` (`nutrition_service.dart:203-211`) — sanctioned best-effort persistence. Keep the behaviour; add rule **O** recording and a comment stating the cost. | F |
| **EC-25** | `directoryProvider` (`community_provider.dart:100-102`), `upcomingClassesProvider` / `upcomingEventsProvider` (`dashboard_provider.dart:57-59`, `:73-75`), `getGroups`, `coachReviewsProvider` — `[]` on failure. Same class, low stakes; fold into the L2 sweep. | B |
| **EC-26** | `_resnapshotSession` (`active_workout_screen.dart:1234-1243`) returns `false` on failure — **this one is already handled correctly**: the caller surfaces *"Swapped to X — but the change could not be saved. Reloading will bring back Y."* Named here as a model of an honest boolean, not as a defect. | A |

### 3.5 Class A — legitimate empty states, explicitly left alone

Per the brief's guardrail, these were examined and are **correct as written**. Nothing
in the remediation sequence touches them.

| Site | Why it is legitimate |
|---|---|
| `rest_alarm_web.dart`, `rest_alarm_stub.dart` (8 sites) | Platform-capability probes. An unavailable Web Audio / notification API genuinely means "this platform cannot do it", which is an answer, not a failure. |
| `CustomExerciseService.metaForName` → `(rpe: true, pr: true)` | Documented product default for an exercise with no metadata record. The default is stated in the doc comment and is the permissive-but-harmless direction. |
| `AICoachService.getPersona` → Nova/motivational/supportive | A persona is presentation, not a domain decision. The fallback is the product's stated default. |
| `LiveCommunityService.joinGroup` treating `23505` as `true` | Correct: a duplicate-key violation on a join **means** the user is already a member. Reading the error and mapping it to the right domain answer is exactly what the contract asks for. |
| `ScoreEngine._award` / `_penalize` (`score_engine.dart:26`, `:38`) | Documented — *"scoring never blocks the user action"*. Sanctioned under §5.1; needs rule **O** recording, not propagation. |
| `getSampleWorkouts` / `getSampleFoods` / `getSampleMessages` | In-memory fixtures with no failure mode. |
| `assignedWorkoutsProvider` returning `[]` for a null program | Post-Phase-2, this is the *correct* empty state: `[]` now means exactly "no assigned program". |

---

## 4. The 12 Circle Error Contract (proposed, v1)

> **Axiom.** *An empty value is an answer. It must never be a symptom.*
> If a caller cannot distinguish "there is nothing" from "I could not find out",
> the contract is broken regardless of what the code returns.

### 4.1 Four outcomes

Every domain read and write resolves to exactly one of:

| Outcome | Meaning | Retry? |
|---|---|---|
| **Ok(value)** | The answer, **including legitimately empty answers** (`[]`, `null`, `0`, `false`). | n/a |
| **Failed(cause)** | The answer could not be obtained. Transient or infrastructural. | Yes |
| **Refused(reason)** | The operation was understood and declined — authorization, entitlement, contract violation, zero-row write. | Not as-is |
| **Unavailable(reason)** | A dependency is not configured or not deployed. Distinct from *Refused*: nothing the user does changes it. | No |

`apps/api` already implements all four (`ServiceUnavailableException` /
`UnauthorizedException` / typed success / logged detail). The Dart and Edge layers
implement only *Ok*.

In Dart this needs no new `Result` type. Riverpod's `AsyncValue` already carries
loading / data / error, and Dart exceptions already carry cause. The contract is
therefore expressed as **layer obligations**, not as a new abstraction:

### 4.2 Layer obligations

| Layer | Obligation |
|---|---|
| **L0 · Database / RPC** | **Raise.** Never `coalesce` a failure into a default. Precedent: migration 119 made `materialize_program_week` raise on an empty selection rather than report `sessions_created: 4` with zero exercises. |
| **L1 · Edge Function** | Check `error` on **every** PostgREST destructure — rule **E1**. Map to the four outcomes by status: `500` Unavailable (not configured), `401` Refused, `502` Failed (upstream), `502` Refused (contract violation, with the rejected payload). Never return `200` with a degraded body. Precedent: `ai-generate-workout`'s contract validation already does this for the model's *output*; it must also do it for its *inputs*. |
| **L2 · Service / repository (Dart)** | **Propagate by default.** A method's return type carries domain answers only: `null` = "no such row", `[]` = "no rows", `false` = "**refused**" — never "it failed". A `catch` here requires a written justification against §5. |
| **L3 · Provider / notifier** | Represent failure as `AsyncValue.error`. Never catch-and-default. Precedent: `activeWorkoutRestorationProvider`, `PostNotifier`, `CoachingModeNotifier`. |
| **L4 · UI** | Minimum three states: loading · data (including empty) · **error with a named failure and a retry**, per product bible §4. Precedent: `WKT-112`'s widget tests. |

### 4.3 Cross-cutting rules

| | Rule | Statement |
|---|---|---|
| **W** | **Verified write** | Any write whose success is asserted to a user appends `.select(<pk>)` and treats **zero rows as *Refused***. PostgREST answers an RLS-filtered write with 200 and no rows. *(Already implemented by `setMode` and `updateExercise`.)* |
| **D** | **No defaulted decision input** | A value produced by a fallback may never become the input to a persisted decision or a scoring write. *(EC-02, EC-06.)* |
| **M** | **No manufactured entities** | A service may never synthesise a domain object to stand in for a failure. *(EC-07, EC-14.)* |
| **N** | **`??` is for presentation** | `??` may supply a label or a placeholder. It may never supply a **domain** value — and never a graded safety value. *(EC-04. Mirrors the Workout Domain Contract's `null` ≠ `0` load rule.)* |
| **T** | **Transitions are persisted before they are announced** | A state-machine transition is not reported to the user until the row reflects it. *(EC-05.)* |
| **X** | **Fail closed, out loud** | An authorization or entitlement check that cannot run denies **and states that it could not run**. "Denied" and "couldn't verify" are different answers. *(EC-15.)* |
| **O** | **No silent swallow** | Every sanctioned swallow calls `reportFailure()`. A swallow that records is an engineering decision; a swallow that does not is an outage nobody will ever see. *(EC-01.)* |
| **B** | **Reachability is not emptiness** | A store-unreachable error (`PGRST205`, `42P01`, connection failure) is never an empty domain answer. *(EC-10. `qa_suites._table` already distinguishes these correctly.)* |

### 4.4 Rule S — the Safety Input Rule *(the load-bearing new rule)*

> **An input that constrains a safety decision is REQUIRED, not optional.
> If it cannot be read, the decision fails closed — it does not proceed with an
> empty constraint set.**

Safety inputs, enumerated:

- injuries and injury locations (`ai_memories.kind = 'injury'`, `user_profiles.injury_locations`, `has_injuries`)
- exercise contraindications (`custom_exercises.contraindications`, `exercise_intelligence`)
- PAR-Q answers and derived `risk_*`
- allergies and dietary restrictions (`food_allergies`, `dietary_restrictions`)

For these, `[]` from a failed read and `[]` from "this client has none" **must never be
the same value**. A decision consuming them must be able to tell, and must refuse when
it cannot.

This is the rule that turns EC-02 and EC-04 from "swallowed errors" into a stated
architectural invariant, and it is the single most important output of this workstream.
It is why §10 recommends an ADR rather than a ticket.

---

## 5. When a swallow is allowed

Exactly five cases. Anything else is a defect under this contract.

### 5.1 The sanctioned exceptions

1. **Fire-and-forget secondary effects** — notifications, telemetry, cache warming,
   score awards. Must be genuinely secondary, must call `reportFailure()`, must carry a
   comment saying why, and **must not feed a subsequent decision** (rule D).
   *(EC-20, `ScoreEngine._award`.)*
2. **Optional-by-design lookups** where absence is the documented product answer.
   *(`metaForName`, `getPersona`.)*
3. **Best-effort persistence of ephemeral UI state** — scroll cursor, elapsed seconds.
   Must document the cost. *(EC-24.)*
4. **Platform capability probes.** *(`rest_alarm_*`.)*
5. **Deliberate fail-closed defaults** — must be fail-*closed*, must record, and must be
   distinguishable in the UI from a genuine denial (rule X). *(EC-15.)*

### 5.2 What is never sanctioned

- Swallowing an error that reaches a **safety** decision (rule S).
- Reporting a write as successful without verifying it landed (rule W).
- Synthesising a domain entity in place of a failure (rule M).
- Any swallow that does not record (rule O).

---

## 6. Recommended implementation sequence

Sequenced by dependency, not by severity. **Nothing here is implemented; this is the
proposed plan.**

### Phase B0 — Observability *(additive; zero behaviour change)*
Add a minimal `AppFailure` value type and a single `reportFailure()` sink; wire the
sanctioned swallows (§5.1) to it. **No propagation changes yet.**
*Closes EC-01, EC-23. Blocks nothing. Makes everything after it verifiable.*
**Gate:** suites green; a deliberately-failed read appears in the sink.

### Phase B1 — Safety inputs *(rule S)*
`ai-coaching-engine.recent()` and `ai-generate-workout`'s context load check `error` and
refuse rather than degrade. `risk_level ?? 'low'` becomes "not assessed" at all four
sites. Onboarding stops marking itself complete on a failed save.
*Closes EC-02, EC-03, EC-04.*
**Depends on:** CON-03 (`dietary_restrictions` type/serializer) precedes EC-03, exactly
as the existing plan's 3A→3B ordering already states.
**Gate:** a forced read failure produces a 502, never a workout; a null `risk_level`
never renders a grade.

### Phase B2 — Verified writes *(rule W)*
Generalise `setMode`/`updateExercise` across the ~10 EC-09 sites plus EC-08 and EC-12.
Moderation and platform-settings writes first.
*Closes EC-08, EC-09, EC-12.*
**Gate:** each site returns *Refused* under a simulated zero-row response; the UI states
it.

### Phase B3 — Persisted-transition integrity *(rules T, D, M)*
Workout completion; nutrition score; the check-in `pending` fabrication; Stripe Connect
figures.
*Closes EC-05, EC-06, EC-07, EC-14, EC-22.*
**Gate:** a failed `completeSession` leaves the session resumable and shows no
celebration; a failed `getTodayTotals` writes no score.

### Phase B4 — Service-layer sweep *(rule L2)*
`WorkoutService` (13), `MessagingService` (8), `NutritionService` (7),
`CoachProgramService` (12), `PaymentService` (9), `AICoachService` (11),
`CustomExerciseService` (54), and the P3 stragglers. Each site is resolved as
*propagate* or *sanctioned-with-a-recorded-reason*.
*Closes EC-11, EC-13, EC-15, EC-16, EC-18, EC-19, EC-21, EC-25; lowers the EC-G5 ratchet
in step.*

### Phase B5 — Check-in reconciliation
`checkins` / `coach_tips`. **Blocked on Q-1** and its `coach_tips` twin.
*Closes EC-10.*

### Phase B6 — Contract enforcement
Promote the §8 guards from "record the baseline" to "enforce the rule": every write with
an asserted success has `.select()`; no `??` supplies a graded safety value; every Edge
Function PostgREST destructure checks `error`. Ratchet the EC-G5 baseline down at each
phase.

---

## 7. Tests needed

### 7.1 Added by this workstream *(present and green)*

`apps/mobile/test/unit/error_contract_guard_test.dart` — 13 static guards. See §8.

### 7.2 Required per remediation phase *(not yet written)*

| Phase | Test |
|---|---|
| B0 | A forced failure in a sanctioned swallow reaches the sink with its cause. |
| B1 | **Edge (Deno):** stub `ai_memories` to return an error → the function returns 502 and no workout. Stub it to return `[]` → a workout **is** generated (the legitimate empty state is preserved — this is the test that proves rule S did not over-trigger). |
| B1 | **Widget:** a client detail with `risk_level: null` shows "not assessed" and no grade chip; with `'low'` shows the low chip. |
| B1 | **Widget/unit:** with the profile upsert failing, `onboarding_complete` stays false, the answers survive in memory, an error is shown, retry succeeds. |
| B2 | **Unit, per site:** a stubbed zero-row update yields `false`/raises and never `true`. Extend `in_memory_workout_session_store.dart`'s approach to a fake PostgREST that can return 200-with-zero-rows. |
| B3 | **Widget:** `completeSession` failing → no celebration dialog, session still resumable, an error stated. |
| B3 | **Unit:** `getTodayTotals` failing → `_awardNutritionScore` writes nothing (assert `addNutritionPoints` is not called). |
| B3 | **Unit:** `getCurrentWeekCheckin` read failure → raises; never returns a `pending` model. |
| B4 | **Widget:** with the history query failing, the history surface shows error + retry, never "no workouts". Mirrors `WKT-112`. |
| B4 | **Unit:** `getCompletionRate` failing → the provider is in error; the coach UI shows "—", never "0%". |
| B5 | Once Q-1 is answered: a check-in save that cannot reach its table surfaces an error; a successful save reads back; the coach count matches. |
| B6 | A source guard asserting every `.update(`/`.delete(` in a `Future<bool>` method is followed by `.select(`. |

### 7.3 Live QA verification *(Phase 4/5, under the authorized QA workflow)*

Rule S and rule W cannot be fully certified statically — they depend on how PostgREST,
the grants and the policies compose. The B1 and B2 gates need a live counterpart in
`supabase/tests/`, in the same shape as the existing security suites: force an RLS
denial on a real QA row, assert the client reports *Refused* and not success.
**Production is not to be contacted for any of this.**

---

## 8. What was added to the tree

**One file. Static guards only. No product code changed.**

`apps/mobile/test/unit/error_contract_guard_test.dart` — 13 tests, all green, in the
same shape as the existing `phase1_security_boundary_test.dart`: they parse committed
source, need no database or credentials, and assert only what is **already true today**.

| Guard | Asserts | Why it is safe |
|---|---|---|
| **EC-G1** (6 tests) | `workout_provider.dart` contains no `catch`; `assignedWorkoutsProvider`, `generateAiWorkout`, `getSessionCompletedSets`, `saveSetLog`, `materializeWeek` still propagate | Pins the Phase 2 RC-C fixes. A future "make the crash go away" edit would look like a bug fix; this makes it fail CI with the reason attached. |
| **EC-G2** (1 test) | Every table name used in `apps/mobile/lib` has a `CREATE` in `supabase/`, except a **shrinking allowlist** of `{checkins, coach_tips}` | Records EC-10 without asserting a fix. Closing CON-01 is a one-line deletion. A *new* phantom table fails immediately instead of shipping as a dead feature. The allowlist is checked in both directions, so it cannot rot into a permanent excuse. |
| **EC-G3** (2 tests) | `setMode` and `updateExercise` keep `.select()` + zero-row detection + rollback/refusal | Pins the two in-tree reference implementations of rule W. |
| **EC-G4** (3 tests) | `apps/api` keeps: misconfigured ≠ unauthorized; an empty AI answer is refused; an unconfigured key is refused before the request is built | Pins the only layer that already implements the full contract. |
| **EC-G5** (1 test) | The repo-wide count of error-to-empty-value sites is **≤ 234** | The ratchet. Verified to report exactly 234, matching an independent scan. It may fall; it may not rise. This is what stops the inventory drifting back up between phases. |

**Verification:** `flutter test` 610 → **623 passed, 0 failed**. `apps/api` **58 passed,
0 failed**, unchanged. The ratchet was checked by temporarily setting the baseline to 1
and confirming it reports `234`.

---

## 9. Fix-now vs. product authority

### 9.1 Safe to fix immediately — no product decision, no user-visible surprise

| Item | Why it is safe |
|---|---|
| **EC-01** observability sink | Purely additive. |
| **EC-02** Edge `error` checks | Changes a silently-wrong 200 into a 502. The current behaviour is not a product decision anyone made. |
| **EC-04** risk display | "Not assessed" vs a fabricated "low" — restoring truth. No policy change (that is Q-4). |
| **EC-08** coach feedback zero-row check | Two lines. The verification query is already there. |
| **EC-05** completion transition | Removes two `catch (_) {}` in a path whose intended semantics are already documented by Phase 2. |
| **EC-06** nutrition score input | Skipping a score write on an untrustworthy read cannot make anything worse. |
| **EC-11** `WorkoutService` propagation | The providers above already carry errors; the UI states already exist. |
| **EC-17** `detectRisks` | Unreferenced dead code with a parser that cannot work. Delete or rewrite. |
| **EC-24** documentation + `reportFailure` on sanctioned swallows | Behaviour-preserving. |

### 9.2 Needs a product call before implementing

| Item | The question |
|---|---|
| **EC-10** | **Q-1**, still open. Is there a daily check-in distinct from the weekly one? And its twin: was `coach_tips` ever a real feature? The reconciliation's recommendation (retire the duplicate, migrate to `weekly_checkins`) stands and is cheap; it just is not mine to make. |
| **EC-09** moderation sites | Turning "approved" into "couldn't approve" is correct, but it is a **user-visible change to an admin flow**. Confirm the moderation surface is in beta scope before changing what admins see. |
| **EC-15** entitlement | Rule X says fail closed *and say so*. What a downgraded paying client should actually be shown — a blocking error, a degraded-mode banner, a silent retry — is a product decision. The **fail-closed direction is not in question**; only the messaging. |
| **EC-13** messaging | Propagation is right. Whether a failed thread load shows an inline retry or a full error screen is a design call. |
| **EC-03** | The *fix* is not in question. The **UX of a failed onboarding save** — retry in place, save-and-resume, or a support path — is a product decision, and the current fail-open exists precisely because someone worried about looping the user. That concern is legitimate and needs an answer, not an override. |

### 9.3 Explicitly out of scope for this workstream

- **CON-04 / Q-4** — what a high-risk PAR-Q *does* to training. EC-04 fixes only how an
  absent value is displayed. The policy remains product authority.
- **Q-3 / Q-A** — the engine's prescription model. Closed 2026-08-24; the residual gaps
  G-1/G-2/G-3 are recorded in the Workout Domain Contract §8.
- Anything already closed by Phase 1 (migrations 113–118) or Phase 2 (119–122). Nothing
  in this report re-litigates a completed fix.

---

## 10. Should this become an ADR?

**Yes — one ADR, not several, and it should be added to `docs/decision-log.md` under
*Core invariants*, not under *Notable engineering calls*.**

The reasoning:

1. **It constrains all future work, which is the log's own stated bar** ("append a row
   when a decision is load-bearing… or would be expensive to reverse"). Every future
   service method, provider and Edge Function is governed by it. Retrofitting it later
   costs 234 sites — the exact position we are in now.

2. **Rule S belongs beside the existing safety invariants.** The log already carries
   *"the engine decides, the AI explains"*, *"every recommendation produces a decision
   trace"* and *"knowledge is human-reviewed before the engine trusts it."* All three are
   **defeated by a silently-emptied input**: a trace over degraded inputs is not an audit
   record, and a reviewed knowledge base that fails open to `[]` is not reviewed. Rule S
   is the invariant that makes the other three enforceable rather than aspirational.

3. **The trade-off is real and must be recorded honestly**, in the log's style: more
   error states reach the user, and some flows that currently "just work" will start
   saying they did not. That is the correct trade — a fitness product that quietly
   forgets a client's injuries is worse than one that says "couldn't load, try again" —
   but it is a trade, and future maintainers are owed the reasoning rather than a rule
   that looks like pedantry.

**Proposed rows:**

| Date | Decision | Why |
|------|----------|-----|
| 2026-08 | **An empty value is an answer, never a symptom.** Errors propagate to a stated failure with a retry; they are never returned as `[]`, `null`, `false`, `0` or a synthesised entity. | "No data" and "couldn't load" are different facts and the client is owed the difference. 234 sites conflated them; one of them dropped a client's injuries from a generated workout. |
| 2026-08 | **Safety Input Rule — inputs that constrain a safety decision are required, not optional. If one cannot be read, the decision fails closed.** | Injuries, contraindications, PAR-Q risk and allergens are the inputs that make "the engine decides" safe. An input that silently degrades to `[]` makes a decision trace an audit record of nothing. |
| 2026-08 | **A write whose success is asserted to the user is verified** (`.select()`, zero rows = refused). | PostgREST answers an RLS-filtered update with 200 and no rows, so an unverified write reports work that never happened — including coach feedback and content moderation. |

---

## 11. Blocked / not done

| Item | Blocker |
|---|---|
| Live verification of rule S against a running Edge Function | ENV-01/ENV-02 — QA Edge Functions are not deployed and the per-project Vault secrets are unset. Phase 4. |
| Live verification of rule W under real RLS | Requires authorized QA write probes with cleanup. Deliberately not performed in a discovery workstream. |
| `coach_tips` product intent | No statement anywhere in `docs/`. Escalated with Q-1. |
| Runtime measurement of how often these paths actually fire | EC-01 — there is no sink. This is the concrete cost of the missing observability, and the reason B0 is first. |
| `custom_exercise_service.dart`'s 54 sites, individually classified | Deferred to the B4 sweep by design: 54 individual judgements made before the contract exists would be 54 guesses. |

---

## 12. Statement of method

Every finding was derived from committed source in this working tree and every file:line
reference was opened and read. The 234-site inventory was produced by an independent
scan and then **reproduced by the Dart guard in §8, which reports the same number**.
The phantom-table finding was proven by cross-checking all 78 table names and all 47 RPC
names referenced in `apps/mobile/lib` against every `CREATE` statement in `supabase/` —
which is also how the report can state that **no RPC is missing**, only two tables.

No behaviour was changed. No product requirement was invented; where a decision is
required it is named and left open. No legitimate empty state was reclassified as an
error — §3.5 lists the ones examined and deliberately left alone.
**Production was not contacted. QA was not written to.**
