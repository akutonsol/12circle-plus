# 12Circle Fitness — Autonomous QA Exhaustion Report

**Branch:** `claude/dreamy-ptolemy-3sk1vz`

| Run | Date | Phase | Range |
|---|---|---|---|
| 1 | 2026-09-25 | discovery only | `cafcfe9` → `8a27f31` |
| 2 | 2026-09-25 | discovery + governed client-side remediation + guard mutation audit | `8a27f31` → `3895e92` (+ this documentation commit) |

Run 2 appears first; Run 1's original report follows unchanged below it, as the historical record.

## CURRENT STATUS (end of Run 2)

> **12CIRCLE FITNESS QA — NOT EXHAUSTED.**
>
> **Remaining executable work:** one low-priority item. The workout behavioural suites
> (`workout_*_test.dart`, 9 files) have not been individually mutation-audited. They exercise
> real `lib/` code and are partly covered by the wrk02 negative control (§R2-10).
>
> Every other class executable in this environment was executed in Run 1 or Run 2 (§R2-9),
> including a mutation audit of **23 guards**. It found **7 vacuous or blind guards**, and all 7
> are fixed and re-proven (§R2-10).
>
> **Blocked work:**
> - **Every VERIFIED LIVE rung.** The QA host is network-denied, and there are no QA credentials.
> - **Every database remediation** (QAX-SEC-01…10, QAX-BIL-01, the atomic half of QAX-ERR-02). Migration numbers **132+ are "assigned at wave entry, never before"** (`MASTER_REMEDIATION_WAVES.md` §0.2).
> - **Device/runtime E2E.** No emulator; the Docker daemon is not running.
> - **Nine owner decisions** (§R2-7).
>
> **Next phase:** Wave entry for the QAX security migrations (authorize 132+) and an owner session for the OD-QAX items. Then the live rerun of `supabase/tests/qa_exhaustion` on QA as the d09 suite, per §R2-8.

This is not a claim of HIPAA certification or production readiness.

---

## R2-1. What changed in the environment (Run 2)

| Blocker (Run 1) | Run 2 status | Evidence |
|---|---|---|
| No Flutter SDK (EB-QAX-2) | **LIFTED.** Flutter **3.44.4** / Dart 3.12.2, CI's pinned version, installed to `/opt/flutter`, outside the repo. | `flutter --version` |
| DB mutation harness `negative-control.sh` "ENVIRONMENT-BLOCKED locally" (`MOBILE_QA_SWEEP_2026-09-22.md` §1) | **LIFTED.** It runs. **PASS:** M-1…M-3 each produce exactly the declared failures, and every restore gives 20/20. `--self-test` 5/5. | `/usr/lib/postgresql/16/bin` exists in this image |
| QA host network-denied (EB-QAX-1) | **STILL BLOCKED.** CONNECT 403, and no `QA_*` / service credentials are in the environment. | re-probed at session start |
| Device / emulator; Docker daemon | **STILL BLOCKED** | `docker info`: no server |

## R2-2. Baselines

| Metric | Start of Run 2 (`8a27f31`) | End of Run 2 (`3895e92`) |
|---|---|---|
| `flutter test` | **822 passed / 9 skipped / 0 failed** | **861 passed / 9 skipped / 0 failed** (+39 new tests; the 9 skips are the documented K-series open specs in `billing_entitlement_contract_test`) |
| `flutter analyze` | 0 errors · 16 warnings · 160 infos | **identical** (no new issue introduced) |
| API unit / e2e | 58/58 · 6/6 | unchanged (no API change) |
| `test:contract`, `check:guards` | PASS | PASS |
| Repo negative controls (7) + DB harness | not runnable locally | **all PASS locally** (wrk02, ec23, uix1, nut01, int02, icom01, i3a11; DB M-1…M-3) |
| QAX local probe suite | 12 defect FAIL / 6 PASS | **15 defect FAIL + FIX-08 contract FAIL / 8 PASS** (3 new findings pinned) |
| QAX static guards | 1 (guarded-write) | 3 (guarded-write v2, per-user-provider class guard, strengthened UIX-2 deletion-claims guard) + REL-3 source contract |

**Correction of record (R-13).** `MOBILE_QA_SWEEP_2026-09-22.md` §1 records "0 errors, **0 warnings**,
160 infos". On a clean checkout with CI's Flutter 3.44.4 the tree has **16 warnings**:
- 14 unnecessary `!` or null-checks;
- one pubspec entry for an `assets/icons/` directory that is not in git.

CI's own comment (`ci.yml:206`) counts "171 pre-existing infos/warnings" and runs with
`--no-fatal-warnings`. This is not a regression; the sweep's figure was environment-specific.

## R2-3. Canonical QAX ledger (supersedes the Run 1 tables for status)

Classification vocabulary: VERIFIED · FIXED · FALSE POSITIVE/RETRACTED · OPEN · BLOCKED · OWNER
DECISION · NOT TESTABLE.

Evidence tags:
- **LR** = local replay of migrations 000–131;
- **WT** = widget/unit test on the real code;
- **ST** = static only;
- **MUT** = mutation-tested;
- **LIVE** = QA. **No QAX item is LIVE.**

| ID | Sev | Status | Evidence | Fix / dependency |
|---|---|---|---|---|
| QAX-SEC-02 progress-photo read by self-made or former coach | **P0** | VERIFIED · BLOCKED | LR + MUT | migration (wave entry 132+) · OD-QAX-1 |
| **QAX-SEC-08** self-made "team lead" reads any member's full profile: medical conditions, PAR-Q, phone *(new, Run 2)* | **P0** | VERIFIED · BLOCKED | LR + MUT (+ non-vacuous FIX-08 contract) | migration · OD-QAX-9 (what "team" means). Retracts H-06's "the policy is correct" (R-12). |
| QAX-SEC-01 `assign_nutrition_plan` cross-member supersede | **P0** | VERIFIED · BLOCKED | LR + MUT | migration · OD-QAX-2 |
| QAX-SEC-03 self-asserted coach_id writes (6 tables) | P1 | VERIFIED · BLOCKED | LR + MUT | migration |
| QAX-SEC-05 exercise-media overwrite/delete | P1 | VERIFIED · BLOCKED | LR + MUT | migration |
| QAX-SEC-07 enrich-exercise-* behind the self-selectable coach role | P1 | VERIFIED (ST) · BLOCKED | ST | Edge deploy is governance-gated · OD-QAX-3 |
| **QAX-SEC-09** event vendor reads registrants' medical/PAR-Q/DOB *(new)* | P1 | VERIFIED · BLOCKED | LR + MUT | migration · OD-QAX-10 (vendor's minimum-necessary view) |
| QAX-PRV-01 Privacy Policy inaccurate: correction, providers, wearables, security | P1 | OWNER DECISION | ST | Run 2 adds **Open Food Facts** (search terms/barcodes sent from device) and YouTube/Vimeo embeds to the undisclosed-recipient list |
| QAX-PRV-02 PHI to Anthropic undisclosed | P1 | OWNER DECISION | ST | extends PD-D06 |
| QAX-SEC-04 message injection into others' conversations | P2 | VERIFIED · BLOCKED | LR + MUT | migration |
| QAX-SEC-06 `exercises` view leaks private drafts | P2 | VERIFIED · BLOCKED | LR + MUT | migration |
| **QAX-BIL-01** one-tap vendor event delete cascades paid registrations; payment orphaned (`event_id → NULL`) *(new)* | P2 | VERIFIED · BLOCKED | LR (cascade reproduced) | migration (refuse or soft-cancel with paid registrations) · OD-QAX-11 (paid-event cancellation/refund policy). Distinct from K-06. |
| QAX-COR-01 Personal Info cleared fields kept; `?? 0` | P2 | **FIXED** | WT + MUT (`fdbd67b`) | — |
| QAX-COR-03 no post-onboarding health-history edit | P2 | OWNER DECISION | ST | OD-QAX-6 |
| QAX-COR-05 quick-add double tap duplicates | P2 | **FIXED** (quick-add); OPEN (edit/delete surface) | WT + MUT (`81dcf1f`); scan/barcode guards ST | edit/delete of meals = product surface |
| QAX-COR-07 baseline photo deleted before upload; gallery undeletable | P2 | **FIXED** (loss on replace); OPEN (gallery delete surface) | WT + MUT (`7e1507e`) | gallery delete = product surface |
| QAX-SES-01 cross-account cached providers after mobile logout | P2 | **FIXED** | class guard + MUT (`fb0a012`); device runtime NOT TESTED | — |
| QAX-PRV-03 no audit trail for corrections | P2 | OWNER DECISION | LR | OD-QAX-7 |
| QAX-REG-01 registry F-ID collision | P2 | OWNER DECISION | ST | OD-QAX-8. **Note:** the women's-health F-03 is now FIXED (`fc29b41`). |
| QAX-COR-02 set correction | P4 (was P3) | VERIFIED; reclassified | ST | The failure **is** surfaced ("Could not save set") after an optimistic "corrected"; fire-and-forget is the documented workout-domain design. Clearing reps/weight on a completed set = **OD-QAX-12**. |
| QAX-COR-04 injury AI memories never retracted | P3 | OPEN | LR | needs a migration (trigger retract) → BLOCKED (wave entry) |
| QAX-COR-06 weight/measurement silent failure; stuck spinner; duplicate-inviting points coupling | P3 | **FIXED** | WT + MUT (`fa593a7`); the signed-out refusal is ST | — |
| QAX-COR-08 goal actions unhandled; updateProgress false ignored | P3 | **FIXED** | WT + MUT (`50c5437`) | irreversibility / no delete confirm → OPEN (UX) |
| QAX-ERR-01 cycle writes fail silently | P3 | **FIXED** | WT + MUT (`b0954f5`) | also closes the thrown-error and signed-out halves of F-06, and F-22 |
| QAX-ERR-02 coach feedback 0-row success; habit assign null-uid success | P3 | **FIXED** (ST); atomicity BLOCKED | ST (`4df390b`) | atomic assign needs an RPC (migration) |
| **QAX-SEC-10** any user uploads into any coach's public coach-media folder *(new)* | P3 | VERIFIED · BLOCKED | LR + MUT | migration |
| **QAX-UI-01** weight sheet date/unit row overflows at every width ≤414 px (40 px at 375) *(new)* | P3 | OPEN | WT repro (`tool/qa_exhaustion/progress_sheet_overflow_repro_test.dart`, fails 6/6 by design) | layout owner |
| **QAX-UI-02** weight-ruler ticks overflow 2 px *(new)* | P4 | OPEN | same repro | layout owner |
| **QAX-UI-03** 8 `use_build_context_synchronously` sites *(new)* | P4 | VERIFIED (classified) | analyzer + read | 1 safe (lint noise); `upgrade_screen.dart:162` context after await; 6 meals/nutrition dialogs opened on a just-popped sheet's context (fragile, not demonstrated as user-visible) |
| QAX-H-01 / QAX-H-02 | P4 | OPEN / OD-QAX-1 | ST | — |

**Existing registry rows affected by Run 2:**

| Row | Change |
|---|---|
| **F-03** (women's-health, P1) | **FIXED** `fc29b41`. WT + MUT: seeded sheet; failed read opens no blank sheet; out-of-range stored values (no DB constraint, F-01) clamped instead of crashing — a hazard the fix itself would otherwise have introduced. |
| **F-06** | thrown-error and signed-out halves FIXED `b0954f5` |
| **F-22** | FIXED `b0954f5` |
| **UIX-2** (text half) | **was not complete.** Terms of Service §9 still claimed in-app deletion; the guard was vacuous for that phrasing (split string literal + narrow regex). FIXED `810430d`, with a mutation proving the new literal-joining step is load-bearing. |
| Workstream B `goal_service.updateProgress` row | FIXED `50c5437` |
| EC-G5 ratchet | not raised by any Run 2 change |

## R2-4. Retractions and corrections (Run 2)

| # | Claim | Evidence |
|---|---|---|
| R-12 | H-06: `user_profiles` SELECT policy "is correct and must not be relaxed" | Correct about relaxing, wrong about safety: its `is_team_lead_of` arm is exploitable (QAX-SEC-08) and its `hosts_event_for` arm over-discloses (QAX-SEC-09) |
| R-13 | Sweep 2026-09-22: "0 warnings" | 16 warnings on a clean checkout (§R2-2) |
| R-14 | Run 1 QAX-COR-02 "P3 false success" | It is an optimistic confirmation followed by a surfaced failure, by documented design → P4 + OD-QAX-12 |
| R-15 | UIX-2 guard green ⇒ no false deletion claim | Vacuous for the Terms wording; proven by mutation |
| R-16 | Own instrument: guarded-write scanner v1 | Blind once writes moved into an extracted payload builder; it reported still-guarded selectors as "fixed". Fixed (`updatePayloadBuilders`, body-span fix) and re-mutated. |
| R-17 | Own instrument: the first POS-08 | Vacuous: it passed via the active-coach arm. Replaced by the non-vacuous FIX-08 contract, proven to fail when the team arm is removed. |
| R-18 | Own instrument: the first UIX-2 mutation run | The mutation silently did not apply (the guard still contained `replaceAll`). Re-run correctly: blind without joining, catching with it. |
| R-20 | REL-3 guard (`release_route_gate_test`) green ⇒ QA tooling cannot ship in release | **Vacuous.** `kQaToolingEnabled => true` (QA centre in RELEASE builds) passed all 8 tests. Fixed `ab92e88` with a comment-stripped source contract, mutation-proven (`true`, `kDebugMode`, and `true` with the old text in a comment all fail). |
| R-21 | EC-G5 swallow ratchet | Slack of 2 (232 vs 234) admitted new swallows; the one-line `catch (_) {}` shape was counted only by coincidence (20 of 103 invisible). Tightened and EC-G5b added (`61888a6`). |
| R-22 | I-G1/I-G2 identity guard; AI-J-001 invariant | Each read a single migration (131 / 116), so a LATER migration undoing it stayed green (the 116→119 shape). End-state checks added (`42be528`). |
| R-23 | K/TIER "six purchase kinds" | Substring matched the type union and a comment; the handling branch could be deleted. Now requires a `kind ===` dispatch (`3895e92`). |
| R-24 | A-G1 tooltip drift | Decided per file; an unused tooltip hid beside a consuming widget. Now per class (`3895e92`). |
| R-25 | Own tooling incident | The session's mutation driver restored with a blanket `git checkout -- .` and silently discarded the uncommitted K/TIER hardening. Detected by re-checking each hardening marker; re-applied and re-proven. **Lesson:** restore only the mutated path. |
| R-19 | Own risk read: `risk_level` / `risk_score` / `risk_flags` accepted a client write | `apply_parq_risk` recomputes on every write; a later "low" persists as `high/2`. Server-authoritative, VERIFIED CORRECT. |

## R2-5. Mutation evidence (Run 2)

| Target | Mutations (each FAILS; restore PASSES) |
|---|---|
| ERR-01 | rethrow instead of surfacing · no-open-period as success · never close on success (caught **only** by the positive controls) |
| COR-01 test | phone guard restored · unreadable→0 restored |
| COR-01 static guard v2 | guard back in builder · new guarded write in builder · renamed builder · renamed helper. A commented plant correctly PASSES. |
| COR-07 | remove-before-upload · cleanup includes the new file · silent cleanup swallow |
| COR-06 | points back inside the save · no inline error |
| COR-05 | guard removed from `_logFood` |
| COR-08 | update result ignored · rethrow in the menu handler |
| SES-01 | watch removed · watch commented out (the self-test also plants both) |
| F-03 | symptoms not seeded · read failure opens a blank sheet (clamp hazard proven first) |
| UIX-2 | split claim restored without joining → blind; with joining → caught |
| Pre-existing guards | EC-G1 (catch planted in workout_provider → FAIL) · SEC-007 (Anthropic host planted in lib/ → FAIL) · REL-3 (**vacuous**; fixed, R-20). A first REL-3 mutation only broke compilation and was discarded as non-evidence. |
| DB suite | 10 fix-sims, each flips only its own probes; catalog fingerprint `8d4237ee…` unchanged after every run |

## R2-6. Files and commits (Run 2)

- **Commits:** `e609aa5` `b0954f5` `fdbd67b` `7e1507e` `fa593a7` `81dcf1f` `50c5437` `4df390b` `fb0a012` `fc29b41` `810430d` `8ada4a9` `ab92e88` `b60ff14` `61888a6` `42be528` `3895e92` (plus this documentation commit). All pushed.
- **Production Dart files changed (client-side fixes only):**
  - `womens_health/{data/cycle_service,presentation/womens_health_screen}.dart`
  - `profile/presentation/personal_info_screen.dart`
  - `progress/{data/baseline_photo_replace (new),presentation/progress_screen}.dart`
  - `nutrition/{presentation/meals_dashboard_screen,domain/nutrition_provider}.dart`
  - `goals/{data/goal_service,presentation/goals_screen}.dart`
  - `checkins/data/weekly_checkin_service.dart`
  - `coach/{data/coach_program_service,domain/coach_ecosystem_provider}.dart`
  - `dashboard/{presentation/client_detail_screen,presentation/coach_dashboard_screen,domain/dashboard_provider}.dart`
  - `home/presentation/home_screen.dart`, `insights/domain/insights_provider.dart`, `workout/domain/workout_provider.dart`
  - `settings/presentation/terms_of_service_screen.dart` — legal copy, under the existing W1-B6 authorization only
- **Migrations created/applied: none.** SQL/RLS/policy: unchanged. Edge functions: unchanged.
- **QA/production contact: none.**

## R2-7. Owner decisions outstanding

| ID | Decision | Run |
|---|---|---|
| OD-QAX-1 | Is "coach" (and "vendor") a self-service role? | 1 |
| OD-QAX-2 | May a coach assign plans or programs to a `pending` client? | 1 |
| OD-QAX-3 | Who may trigger global exercise-library enrichment? | 1 |
| OD-QAX-4 | Privacy Policy corrections (extended in Run 2) | 1 |
| OD-QAX-5 | PHI to Anthropic (disclosure, consent, BAA/DPA) | 1 |
| OD-QAX-6 | In-app health-history edit and PAR-Q re-screen | 1 |
| OD-QAX-7 | Audit/retention posture for corrections | 1 |
| OD-QAX-8 | Registry F-ID namespace edit | 1 |
| OD-QAX-9 | What a coaching "team" is, and how membership is consented | **2** |
| OD-QAX-10 | What an event host may see about registrants | **2** |
| OD-QAX-11 | Cancellation/refund policy for events with paid registrations | **2** |
| OD-QAX-12 | May reps/weight on a completed set be cleared? | **2** |

## R2-8. Exact next phase

0. (Low) Mutation-audit the 9 `workout_*` behavioural suites. Convert the six `spec_*` copy-of-product files to exercise `lib/` (closure standard: convert, never delete).
1. **Wave entry for the QAX security migrations.** Assign 132+ per §0.2 and declare each as `pending` in `expected_applied.json`. Priority order:
   1. SEC-02 and SEC-08 (P0 PHI reads)
   2. SEC-01 + SEC-03
   3. SEC-09
   4. SEC-05, SEC-04, SEC-06, SEC-10
   5. BIL-01, COR-04

   Use `supabase/tests/qa_exhaustion/fixsim/*` as starting points, not reviewed fixes. Each migration must preserve grants, `search_path` and comments (governance §9, §18).
2. **Lift EB-QAX-1** (allow the QA host; provide QA test-user credentials), then port `probes.sql` into `supabase/tests/security/` as d09. Record BEFORE on QA, apply, record AFTER. Only then does any QAX security row reach VERIFIED LIVE.
3. **Owner session** for OD-QAX-1…12.
4. **Device run** (EB-QAX-2 remainder) for QAX-SES-01 end-to-end, and for the UI-level failure states now covered by widget tests.
5. **Layout owners:** QAX-UI-01/02 (the repro test becomes a regression test once fixed).

## R2-10. Guard mutation audit (Run 2)

Each guard was mutated with the regression it names. A mutation that did not actually apply
(e.g. it hit a comment, missed its anchor, broke only compilation, or fell outside the guard's
declared scope) was discarded and redone; four such invalid first attempts are not counted as
evidence.

| Guard | Planted regression | Verdict |
|---|---|---|
| SEC-020 / SEC-027 | anon grant reopened by a later migration | caught |
| SEC-010 | blanket `user_profiles` read reopened | caught |
| SEC-007 | Anthropic host in `lib/` | caught |
| SEC-030 | user-JWT Edge client calls a non-allowlisted RPC | caught |
| ENV-010/011 | `qa.json` pointed at production | caught |
| ENV-020 | a harness names production | caught |
| ENV-001 / ENV-4 | absent `APP_ENV` defaults to prod | caught |
| H-G1 | phantom column in a client select | caught |
| EC-G1 | a catch in `workout_provider` | caught |
| EC-01 | sink call removed | caught |
| EC-23 | `print()` in `lib/` | caught |
| EC-G6 / EC-G7 | error branch renders nothing | caught (EC-G6's reference check is fooled by a comment; EC-G7 still catches) |
| INT-300 | Q7 dropped from PAR-Q high risk | caught |
| 3A-10 chat path | uploader segment dropped | caught |
| AI-001 | endpoint re-pointed at Anthropic | caught |
| **UIX-2** | split-literal deletion claim | **vacuous → fixed** (`810430d`) |
| **REL-3** | QA tooling enabled in release | **vacuous → fixed** (`ab92e88`) |
| **EC-G5** | new swallow | **slack / blind shape → fixed** (`61888a6`) |
| **I-G1/I-G2** | later migration drops a 131 constraint | **blind → fixed** (I-G6, `42be528`) |
| **AI-J-001** | later unguarded redeclaration | **blind → fixed** (`42be528`) |
| **K/TIER** | checkout branch removed | **wrong occurrence → fixed** (`3895e92`) |
| **A-G1** | unused tooltip beside a consuming widget | **file-level → fixed** (`3895e92`) |
| Repo negative controls (wrk02, ec23, uix1, nut01, int02, icom01, i3a11) + DB harness M-1…M-3 + self-test | their own declared mutations | all PASS locally |

## R2-9. Exhaustion checklist (Run 2)

| Question | Answer |
|---|---|
| Unexamined routes? | none new. Reachability is Workstream M's; dead or unreachable surfaces were re-checked only where fixes touched them. |
| Unexamined services? | every PHI write service is traced (Run 1 matrix plus Run 2 fixes) |
| Unexamined RPCs? | none. **66/66** definer functions probed cross-subject (Run 1). **16/16** invoker functions classified; the two leaderboards were probed (stranger 0, coach 1, unfiltered 1). |
| PHI tables unmapped? | none. 21-table former/stranger/active sweep, now complete: `habit_logs` seeded in Run 2 (unfiltered 1 · active coach 1 · cancelled coach 0 · stranger 0) |
| Storage buckets untested? | none. avatars (owner-scoped ✓), coach-media (SEC-10), exercise-media (SEC-05), progress-photos (SEC-02), chat-media (3A-10, 42/42 live earlier) |
| Column-level privileges? | none exist; protection is trigger-based. All billing, role, Stripe and demo columns are refused. `max_clients` is writable (existing Workstream K row). Risk columns are server-recomputed (R-19). |
| Team-lead / vendor / admin boundaries? | probed: SEC-08, SEC-09; admin role self-assignment refused |
| PHI in URLs / notifications / logs / local storage / analytics? | none found. Routes carry no PHI. Notification bodies carry PR lift weights only. No `print` in `lib/` (the 88 are in tools/tests). No PHI persisted on device. No analytics SDK. |
| Green-but-unmutated guards? | **23 guards mutation-audited (§R2-10); 7 vacuous or blind, all fixed and re-proven.** Residual: the workout behavioural suites (low). The six `spec_*` files (133 tests) import nothing from `lib/` and cannot fail. That is the known "tests execute a copy of the product" class (closure standard §4), recorded, not mutated. |
| Findings copied forward unverified? | none. Every carried row was re-read against the tree (§R2-3). |
| Reports contradicting the tree? | R-12, R-13, R-15 recorded |
| Other agents' work during the session? | none. Remote branches unchanged; no concurrent writer. |

---

# Run 1 report (historical record, unchanged below)

## Run 1 — original header

**Date:** 2026-09-25 · **Branch:** `claude/dreamy-ptolemy-3sk1vz` · **Phase:** DISCOVERY — no production
code, SQL, migration, policy, copy or behaviour was changed.

## FINAL STATUS

> **QA BLOCKED — EXECUTABLE SURFACE REMAINS**

Everything executable **in this environment** has been examined, and it produced **2 new P0s,
5 new P1s** and a set of P2/P3 defects. The status is not "exhausted", for one reason: the
QA Supabase host (`eyqtldjqpgpljlqvpowh.supabase.co`) is **denied by this session's network
policy** (CONNECT 403), and there is no Flutter SDK. So every database result below is
**LOCAL-REPLAY VERIFIED** (committed migrations 000–131 replayed into a scratch PostgreSQL 17.9),
not **VERIFIED LIVE** on QA. The live rung, and the whole runtime/device class, remain
executable once access is granted (§18, §25).

---

## 1. Executive summary

| # | Severity | ID | One line |
|---|---|---|---|
| 1 | **P0** | QAX-SEC-02 | Any user who signs up as a coach can read **any client's private progress (body) photos**: they create a `pending` relationship (the policy permits it), and the storage policy never checks status. Former and cancelled coaches keep access too. Migration 130 created the bucket on QA, which made this reachable. |
| 2 | **P0** | QAX-SEC-01 | `assign_nutrition_plan` (migration 131, applied to QA) lets **any signed-in user deactivate any member's coach-assigned nutrition plan** and install their own targets and notes. It grants more than the direct-table path allows, although 131's header says it "reproduces the existing policy exactly". |
| 3 | P1 | QAX-SEC-03 | Six tables authorize on a self-asserted `coach_id = auth.uid()`. Any user can push habits, action items (which fire a notification), calls, video responses, nutrition plans and **workout program assignments** into another member's account. |
| 4 | P1 | QAX-SEC-05 | Any signed-in user can overwrite or delete **any object in the public `exercise-media` library** that every member is served. |
| 5 | P1 | QAX-SEC-07 | Three `enrich-exercise-*` Edge Functions gate on `role = 'coach'`, which anyone can self-select, and then write the **global** exercise library as service role. Content with model confidence over 90 is auto-approved. |
| 6 | P1 | QAX-PRV-01/02 | The Privacy Policy's correction, provider, wearable and security claims are inaccurate. Injuries, allergies, DOB, gender, weight, cycle data, check-in metrics and food photos go to **Anthropic**, which is disclosed nowhere. |
| 7 | P2 | QAX-COR-01/03 | The five "guarded-write" profile fields named in the handoff are **re-derived with evidence**. Separately, there is **no post-onboarding surface at all** to correct medical conditions, injuries, allergies, dietary restrictions or PAR-Q answers. |
| 8 | P2 | QAX-SEC-04/06, QAX-SES-01, QAX-REG-01, … | Message injection into other people's conversations. The `exercises` view leaks private drafts. Cross-account cached state on mobile logout. A registry ID collision marks a P1 as `VERIFIED_CLOSED`. |

**Six prior claims are retracted with evidence (§13). Two of them are closure statements that
the new P0s contradict.** Every new DB finding is pinned by a guard. Each guard was
mutation-tested in both directions and has positive controls (§14).

---

## 2. Exact baseline

| Item | Value |
|---|---|
| Session start HEAD | `9dc7515` (= `main`), branch `claude/dreamy-ptolemy-3sk1vz`, clean tree |
| QA programme branch | `origin/chore/qa-environments-secure-ai-backend` @ `cafcfe9` — **97 commits ahead, 0 behind** HEAD |
| Action | `git merge --ff-only` of that branch into this branch (no other branch touched) |
| Audited tree | `cafcfe9` (migrations contiguous 000–131, 19 Edge Functions) |
| Concurrency | No other writer was observed. The last programme commit was 2026-09-22 21:11 −0500. No untracked files at start. |
| **Handoff's "authoritative" reports** | `QA_CORRECTION_RIGHTS_EXHAUSTION_REPORT.md`, `QA_SECURITY_HIPAA_EXHAUSTION_REPORT.md`, `QA_SECURITY_HIPAA_REMEDIATION_REPORT.md`, `QA_REMEDIATION_FINAL_REPORT.md`, `SECURITY_LEDGER_PHI.md` — **exist in no commit on any branch** (`git log --all -- '*<name>*'` = 0 for each). The "5 guarded-write defects" and other handoff "known state" were therefore **unverifiable as given** and were re-derived from the code (§7). |
| Offline gates at baseline | `check:prod-refs` OK · `check:migrations` OK (132, contiguous) · `check:functions` OK · `test:contract` PASS (3-entry allowlist) · API unit **58/58** · API e2e **6/6** (identical to `MOBILE_QA_SWEEP_2026-09-22.md`) |

## 3. Exact ending state

- **Production code, SQL, migrations, policies, copy: unchanged.** `git diff cafcfe9 -- apps/mobile/lib apps/api/src supabase/migrations supabase/functions` is empty.
- **Added (QA-only evidence tools):**
  - `supabase/tests/qa_exhaustion/{run.sh,fixtures.sql,probes.sql,fixsim/*.sql}`: loopback-only probe suite, one transaction, always rolled back.
  - `apps/mobile/tool/qa_exhaustion/{guarded_write_scan.mjs,guarded_write_manifest.json}`: static guard (Node).
- **Added/updated docs:** this report · `MASTER_REMEDIATION_REGISTRY.md` §7.23 (additive) · `REMEDIATION_PROGRESS.md` (one row).
- The guards are **not wired into CI**. Wiring them is a remediation-phase decision (§25).

## 4. QA classes examined

All 60 classes in the handoff sweep were considered. The table below records what was
executed, grouped.

| Group (handoff #) | Instrument | Result |
|---|---|---|
| Correction rights / Cat. C–D (18,19, 4 priority areas 1–13) | code trace UI→service→DB + local DB probes + static guard | §7 (QAX-COR-*, QAX-ERR-01) |
| Authorization / IDOR / RLS / grants (2,3,5–10) | full `pg_policy` catalog dump + behavioural write/read probes as attacker/victim/former/active coach | QAX-SEC-01/03/04 |
| SECURITY DEFINER RPCs (4) | behavioural sweep of **all 66** authenticated-callable definer functions, called cross-subject | 1 defect (SEC-01); 65 guarded or subject-free |
| Admin boundaries (10) | definer sweep + `enforce_profile_privilege` probe | correct (role self-escalation refused) |
| Storage / signed-public URLs / upload-delete (11–13) | `storage.objects` policy dump + behavioural probes | QAX-SEC-02, QAX-SEC-05; `coach-media` delete correctly owner-scoped |
| Views (3) | definer-view enumeration + behavioural read | QAX-SEC-06; `coach_client_workout_stats` correct |
| Former/revoked coach (9) | 21 PHI tables × {cancelled, active, stranger} | **tables correct**; storage wrong (SEC-02) |
| PHI leakage, AI PHI transmission, AI memory (14–17) | Edge Function audit (all 19) + policy + trigger reads | QAX-PRV-02, QAX-COR-04; `ai_memories` owner-only (verified) |
| Data-subject access/correction/erasure/consent/audit/retention (18–24) | code + policy text + catalog | QAX-PRV-01, QAX-PRV-03; export/deletion = existing W1B-N3 / UIX-2 |
| Privacy Policy / Terms accuracy (24,25,58) | line-by-line against code | QAX-PRV-01 |
| Notifications, logs, analytics, local storage (26–30) | grep + read | no PHI persisted on device; one `debugPrint` of failures; no analytics SDK; email PHI = first name only |
| Session lifecycle (1,32) | router + logout + provider-lifetime scan | QAX-SES-01 |
| Swallowed exceptions / unhandled Futures / duplicate submits / stale state (33–37) | per-table matrix (15 tables) | QAX-COR-02/05/06/07/08, QAX-ERR-01/02 + re-verified EC-12, EC-22 |
| Edge Functions / API (auth, cost, email, billing) (53,54) | full static audit | QAX-SEC-07; EDGE-1/EDGE-2/E-15/REL-29 re-verified + expanded |
| Registry integrity (59,60) | ID cross-reference | QAX-REG-01 |

## 5. QA classes exhausted (for this environment)

These classes were exhausted at the committed-code and local-replay level: authorization/RLS
catalog, definer RPCs, storage policies, definer views, former-coach table access,
correction-rights write paths, Privacy Policy claims, Edge Function static authorization,
client persistence and logging.

## 6. QA classes blocked

| Class | Blocker |
|---|---|
| **VERIFIED LIVE for everything in §7** | QA host denied by network policy (EB-QAX-1) |
| Runtime / device / E2E: async lifecycle, mounted-state, offline, deep links, accessibility, media/voice/video playback, UI rendering of failure states | no Flutter SDK, no emulator, no Docker daemon (EB-QAX-2) |
| Billing live (Stripe test mode) | pre-existing `P-8`, plus network |
| Edge Function runtime behaviour (deployed config, env, CORS in practice) | network plus the known ENV-7 deployment state |
| Storage API composition (signed URL issuance through the real storage-api) | the local shim models `storage.objects` RLS only (§15 fidelity) |

---

## 7. All verified defects — new findings

IDs use the new prefix `QAX-`. Nothing in §7 duplicates an existing registry row. Where a
finding **expands** an existing row, it says so and names the row.

Evidence classes used below:
- **LOCAL-REPLAY:** committed migrations 000–131 replayed onto the repo's own `supabase/tests/local/shim.sql`, plus Supabase's platform default privileges.
- **STATIC:** read in code.
- **LIVE:** not obtained (EB-QAX-1).

### QAX-SEC-02 — Progress-photo storage: any self-registered coach, and every former coach, can read a client's private body photos

| Field | Value |
|---|---|
| **SEVERITY** | **P0** |
| **CATEGORY** | Security / PHI exposure (storage authorization) |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED; not yet VERIFIED LIVE |
| **AFFECTED FILES** | `supabase/migrations/029_progress_photos_storage_rls.sql` (policy `coach reads client progress photos`); `130_private_storage_buckets.sql:121-135` (creates the bucket; states 029's policy "is not touched"); `115_profile_privilege_boundary.sql:326-327` (`coach` is self-selectable at signup); relationship INSERT policy `relationship parties create` |
| **AFFECTED TABLES/RPCS** | `storage.objects` (bucket `progress-photos`), `coach_client_relationships` |
| **USER/ROLE** | Any registrant who picks "coach" at signup; any former coach |
| **PRECONDITION** | Victim user id. It is enumerable by any signed-in user through `public_profiles` (verified: 3/3 ids visible to a client; anon denied). |
| **EXPECTED** | Only the owner and an **active** coach of the folder owner can read `progress-photos/<uid>/…` |
| **ACTUAL** | The policy is `EXISTS (SELECT 1 FROM coach_client_relationships r WHERE r.coach_id = auth.uid() AND r.client_id::text = foldername[1])`, with **no status check**. `relationship parties create` lets a coach insert `(coach_id=self, client_id=<anyone>, status='pending', initiated_by='coach')`. |
| **REPRODUCTION** | `supabase/tests/qa_exhaustion/run.sh` → `FAIL\|QAX-SEC-02a\|cancelled coach sees 1 photo object(s)` and `FAIL\|QAX-SEC-02b\|stranger coach with self-made pending row sees 1 photo object(s)` |
| **EVIDENCE** | Control: the same cancelled coach sees **0** `user_profiles` rows for the client, so the table-level fix `f9ed501`/`100_rls_harden_client_data.sql` holds. The 21-table former-coach sweep is all 0. Storage was never brought into line. |
| **SECURITY/HIPAA IMPACT** | Unauthorized disclosure of body photography for every member, by any registrant. It needs no relationship consent from the victim. |
| **DATA IMPACT** | Read-only exposure; no integrity loss |
| **WHY THIS IS REAL** | Both policy expressions were read from the replayed catalog and exercised as the `authenticated` role with PostgREST-shaped JWT claims. Storage-API reads and signed-URL issuance are authorized by `storage.objects` SELECT RLS evaluated under the caller's JWT, which is the object probed here. |
| **FALSE-POSITIVE CHECK** | (a) The instrument discriminates: CTRL-1 is denied, and POS-02 (active coach) reads 1. (b) The storage-API layer is modelled by the shim, not run. The API enforces this exact RLS on `storage.objects`, but that composition is not VERIFIED LIVE. (c) Before 130 the bucket did not exist on QA (H-05), so the hole became reachable only when 130 was applied. |
| **MUTATION RESULT** | `run.sh --mutate QAX-SEC-02` (policy adds `r.status='active'`) → 02a and 02b **PASS**; all other probes unchanged; POS-02 still PASS. Restored run is byte-identical; catalog fingerprint unchanged. |
| **RUNTIME STATUS** | NOT TESTED (EB-QAX-2) |
| **RECOMMENDED REMEDIATION** | A forward migration that replaces the policy with an `is_active_coach_of(foldername[1]::uuid)` predicate (same shape as migration 100). Add a live probe to the security suite for former, pending and stranger coaches. Separately, the owner should decide whether a `pending` coach-initiated row may carry any read right (it should not). |
| **DEPENDENCIES** | none. Owner decision OD-QAX-1 (coach vetting) reduces exposure but does not replace the fix. |
| **OWNER DECISION REQUIRED** | NO for the fix. YES for OD-QAX-1. |

### QAX-SEC-01 — `assign_nutrition_plan` lets any signed-in user replace another member's active nutrition plan

| Field | Value |
|---|---|
| **SEVERITY** | **P0** (same class and rating as registry SEC-R1: a definer function that writes a subject without authorizing the caller) |
| **CATEGORY** | Security / authorization regression introduced by a remediation (registry §4.2 class) |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED |
| **AFFECTED FILES** | `supabase/migrations/131_identity_constraints.sql:200-280`; caller `apps/mobile/lib/features/coach/data/coach_program_service.dart:266-280`; readers `nutrition/domain/nutrition_provider.dart:17-28`, `nutrition/data/nutrition_service.dart:81-90`, `supabase/functions/ai-coach/index.ts:44`, `ai-coaching-engine/index.ts:163` |
| **AFFECTED TABLES/RPCS** | `assign_nutrition_plan(uuid,int,int,int,int,int,text)` SECURITY DEFINER; `client_nutrition_plans` |
| **USER/ROLE** | Any authenticated user (a plain client is enough) |
| **EXPECTED** | Only the victim's active coach may supersede their plan |
| **ACTUAL** | The function checks only `auth.uid() IS NOT NULL`. As definer it runs `UPDATE … SET is_active=false WHERE client_id = p_client_id`, **bypassing RLS**, and then inserts the caller's plan as the only active one. |
| **REPRODUCTION** | Differential probe, same attacker and victim. **Direct-table path:** `UPDATE 0` (RLS), and the second active insert is refused by `client_nutrition_plans_one_active_per_client`. **RPC path:** the real coach's plan becomes `active=false`, and the attacker's `kcal=800, notes='attacker note'` becomes active. `run.sh` → `FAIL\|QAX-SEC-01\|stranger replaced the victim's active plan`. |
| **EVIDENCE** | The d08 live suite (`supabase/tests/security/d08-identity-constraints.mjs:182-225`) only tests coach A superseding **A's own** plan. It never tests a third party. |
| **SECURITY/HIPAA IMPACT** | Cross-member write to health-affecting prescriptions. It surfaces as the victim's own calorie and macro goals, and as AI coaching context. The attacker controls the `notes` text shown as a coach note. |
| **DATA IMPACT** | The legitimate plan is silently deactivated. There is no audit trail (QAX-PRV-03). |
| **WHY THIS IS REAL** | The function body was read from the catalog, and the effect was reproduced as `authenticated`. |
| **FALSE-POSITIVE CHECK** | 131's authors reasoned that it matches the table policy, which is loose (QAX-SEC-03). That holds for the **insert** half only. The supersede half grants a power the direct path lacks. See retraction R-6. |
| **MUTATION RESULT** | fix-sim adds `is_active_coach_of(p_client_id)` → SEC-01 PASS; POS-01 (active coach assigns) still PASS. A deliberately **over-blocking** fix-sim (revoke EXECUTE) turns SEC-01 green but **fails POS-01**, so the positive control catches over-correction. |
| **RUNTIME STATUS** | NOT TESTED |
| **RECOMMENDED REMEDIATION** | A forward migration that adds `IF NOT public.is_active_coach_of(p_client_id) THEN RAISE … '42501'`, preserving `search_path`, grants and comment (governance §9 Function Replacement Rule). The coach may need to assign before `active`; if the owner wants that, use an explicit `pending`-relationship arm, not no check. Add a third-party probe to d08. |
| **DEPENDENCIES** | QAX-SEC-03 (the underlying policy) should be fixed in the same wave |
| **OWNER DECISION REQUIRED** | YES, narrowly: may a coach assign a plan to a `pending` client? |

### QAX-SEC-03 — Self-asserted-actor policies let any user write into another member's coaching record

| Field | Value |
|---|---|
| **SEVERITY** | P1 |
| **CATEGORY** | Authorization / cross-member integrity |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED (6 tables) |
| **AFFECTED TABLES** | `client_habits` (`coach client habits`), `action_items` (`coach manages assigned action items`), `coaching_calls` (two ALL policies), `coach_video_responses` (INSERT), `client_nutrition_plans` (`coach client nutrition`), `workout_program_assignments` (`coaches manage assignments`); each authorizes the write arm on `coach_id = auth.uid()` alone |
| **USER/ROLE** | Any authenticated user |
| **EXPECTED** | The coach arm requires an active relationship with `client_id` |
| **ACTUAL** | All six inserts targeting victim B were ALLOWED for plain client A. **Victim-side:** B sees every injected row. `notify_action_assigned` delivered "🔔 New Action Item Assigned" to B. B can read A's program through `can_read_program`. `workout_program_assignments` has **no uniqueness on active rows**, and `getMyAssignedProgram()` (`coach_program_service.dart:218-230`) calls `.eq('status','active').maybeSingle()`. So an injected row either **becomes** the victim's program, or (if they already have one) makes `.maybeSingle()` return 2 rows and **throw**, which blanks the real coach's program. |
| **REPRODUCTION** | `run.sh` → six `FAIL\|QAX-SEC-03.<table>` lines |
| **SECURITY/HIPAA IMPACT** | Stranger-authored prescriptions (workouts, nutrition) and notifications inside a member's account. Harassment and phishing surface. |
| **FALSE-POSITIVE CHECK** | No RESTRICTIVE policies exist on these tables, and no triggers authorize. Controls: `goals` and `cycle_logs` cross-writes are **denied** in the same run. The fake `coach_reviews` insert (W8) was also allowed, but did **not** move the coach's `rating_avg`, so its reputational impact is **NOT DEMONSTRATED** and it is excluded from this finding. |
| **MUTATION RESULT** | fix-sim `QAX-SEC-03` → all six PASS; POS-03 (active coach writes habit) still PASS |
| **RECOMMENDED REMEDIATION** | Rewrite each coach arm as `coach_id = auth.uid() AND is_active_coach_of(client_id)`. Add a partial unique index for one active assignment per client. The client-side supersede (`assignProgram`) should become an RPC with the same guard as SEC-01. |
| **OWNER DECISION REQUIRED** | NO |
| **RETRACTS** | Workstream E's "`client_nutrition_plans` — RLS, owner + active coach — Sound" (R-2) |

### QAX-SEC-04 — Any user can post into a conversation they are not part of

| Field | Value |
|---|---|
| **SEVERITY** | P2 (exploitation needs the target conversation UUID, which no read path exposes to a non-participant) |
| **CATEGORY** | Authorization |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED |
| **AFFECTED** | `messages` policy `authenticated can send messages` = `WITH CHECK (sender_id = auth.uid())`, with no membership test (`003_fk_and_rls_fixes.sql:91-94`) |
| **ACTUAL** | Non-participant A inserted into the B↔D conversation. B sees the message, and `trg_notify_on_message` delivered "New message from …". |
| **MUTATION RESULT** | fix-sim adds a participant subquery → PASS; POS-04 (participant posts) still PASS |
| **REMEDIATION** | Add `conversation_id IN (… participant_1 = auth.uid() OR participant_2 = auth.uid())` to the WITH CHECK |
| **RELATION** | Distinct from I-NOT-04 (UPDATE scope) and K-10 (entitlement). **Retracts** the I-NOT-04 row's statement "No cross-tenant … write" (R-4). |
| **OWNER DECISION REQUIRED** | NO |

### QAX-SEC-05 — Any signed-in user can overwrite or delete any object in the public `exercise-media` bucket

| Field | Value |
|---|---|
| **SEVERITY** | P1 (platform-wide integrity of media served to every member; content-safety exposure) |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED |
| **AFFECTED** | `061_exercise_media_bucket.sql`: policies `exercise-media auth update` / `auth delete` are `USING (bucket_id='exercise-media')`, with no owner test. The bucket is `public=true`. |
| **ACTUAL** | Plain client A updated and deleted an object uploaded by coach D. The `coach-media` control (owner-scoped delete) is correctly **denied**. |
| **MUTATION RESULT** | fix-sim restricts to `owner = auth.uid()` → PASS |
| **REMEDIATION** | Owner-scope update and delete. Restrict insert to content editors, or to the coach's own prefix. |
| **OWNER DECISION REQUIRED** | NO |

### QAX-SEC-06 — The `exercises` definer view exposes every coach's private and draft exercises

| Field | Value |
|---|---|
| **SEVERITY** | P2 (coach content confidentiality; no PHI columns in `custom_exercises`) |
| **STATUS** | DISCOVERED — LOCAL-REPLAY VERIFIED |
| **AFFECTED** | `058_exercise_normalized_schema.sql:23` and `083_exercise_content_pipeline.sql:63`: `create or replace view public.exercises as select * from custom_exercises`, with no WHERE. The owner is the table owner, so RLS is bypassed (`relforcerowsecurity = f`). |
| **ACTUAL** | Private draft invisible through the table (0), visible through the view (1) |
| **MUTATION RESULT** | fix-sim adds the RLS-equivalent WHERE → PASS; POS-06 (owner sees own draft) still PASS |
| **RETRACTS** | Phase 1 §8 "`exercises` — shared library — OK", and Workstream I's statement that "the `exercises` view … gate[s] on `visibility='global' AND submission_status='approved'`" (R-5) |
| **OWNER DECISION REQUIRED** | NO |

### QAX-SEC-07 — The `enrich-exercise-*` functions let any self-registered coach rewrite the global library as service role

| Field | Value |
|---|---|
| **SEVERITY** | P1 |
| **STATUS** | DISCOVERED — STATIC (code read; not executed) |
| **AFFECTED** | `enrich-exercise-content/index.ts:101-105` (`['coach','admin']`), `:113` (service-role client), `:118-123` (caller-chosen `ids` / `force`), `:137` (`confidence > 90 ? 'approved'`), `:152` (`admin.from('exercises').update(patch)`); `enrich-exercise-intelligence/index.ts:87,97-98,139` (can reset certified rows to `ai_generated`); `enrich-exercise-videos/index.ts:83,109,113` (re-points video mappings) |
| **EXPECTED** | Library writes follow the DB's content-editor boundary (`is_content_editor()` = admin/content_manager, `083:86-90`) |
| **ACTUAL** | `coach` is self-selectable (`115:326-327`). The functions accept it, then write with the service role, so the DB boundary is bypassed. |
| **FALSE-POSITIVE CHECK** | The attacker cannot author text directly (it is model output), but can force regeneration over human-reviewed content, flip review status, and spend paid-model quota. |
| **REMEDIATION** | Gate on `is_content_editor()` through an RPC call under the caller's JWT, and remove confidence-based auto-approval. The owner should decide whether coaches may enrich at all. |
| **OWNER DECISION REQUIRED** | YES (who may trigger library enrichment) |

### QAX-COR-01 — Personal Info: clearing phone, height, weight, goal weight or gender keeps the old value and reports success

| Field | Value |
|---|---|
| **SEVERITY** | P2 |
| **CATEGORY** | Correction rights / false success |
| **STATUS** | DISCOVERED — STATIC + LOCAL-REPLAY (DB half) |
| **AFFECTED FILES** | `apps/mobile/lib/features/profile/presentation/personal_info_screen.dart:168-176` (guards), `:188-192` ("Profile updated successfully") |
| **AFFECTED TABLES** | `user_profiles` (`phone`, `height_cm`, `weight_kg`, `weight_goal_kg`, `gender`) |
| **EXPECTED** | Clearing a field removes the stored value, or the UI says it cannot be cleared |
| **ACTUAL** | `if (_phoneCtrl.text.trim().isNotEmpty) payload['phone'] = …` (and the same pattern for the three numeric fields). The gender chip toggles to `null`, and `if (_gender != null)` then omits it. The stored value survives. Secondary: `double.tryParse(text) ?? 0` writes **0** for formatter-legal but unparsable input (`.`, `70..5`). |
| **DB HALF** | As the owner, `UPDATE … SET phone=NULL, height_cm=NULL, weight_kg=NULL, weight_goal_kg=NULL, gender=NULL` **succeeds**. The UI's omitted-field payload leaves `555\|180\|80\|75\|Male`. RLS and the privilege trigger are not the cause. |
| **SECURITY/HIPAA IMPACT** | Correction right not honoured for health and contact data, with a false confirmation |
| **FALSE-POSITIVE CHECK** | DOB and the four option selectors cannot produce null in the UI, so they are **no-clear-affordance** items, not guarded-write defects (classified in the manifest). The formatter `[0-9.]` blocks letters, so "70kg" is untypeable (retraction R-8 of an agent claim). |
| **MUTATION RESULT** | Static guard `guarded_write_scan.mjs`. M1 plant a new guarded write → FAIL. M2 fix `phone` without shrinking the manifest → FAIL (stale). M3 plant inside a comment → PASS (comments ignored). M4 remove the declared indirect writer → FAIL. Restored → PASS. |
| **RUNTIME STATUS** | NOT TESTED |
| **REMEDIATION** | Send `null` for cleared fields. Replace `?? 0` with validation. |
| **OWNER DECISION REQUIRED** | NO |
| **NOTE** | This is the handoff's "5 guarded-write defects", **re-derived**. The handoff's source report does not exist (§2). |

### QAX-COR-02 — Set correction: reps and weight cannot be cleared; "corrected" shows before the save

P3 · STATIC.
- `workout/domain/workout_provider.dart:318-319` has `if (reps != null) 'reps'…` / `if (weight != null) 'weight'…`. rpe and notes have explicit `clearRpe`/`clearNotes` arms; reps and weight do not.
- `active_workout_screen.dart:1411-1414`: `_persistFromState` is not awaited, and the "Set N corrected" SnackBar shows first. A failure later toasts "Could not save set", so this is optimistic, not permanently silent.
- Pinned by the static guard through its declared indirect writer.

### QAX-COR-03 — No post-onboarding correction path for medical conditions, injuries, allergies, dietary restrictions or PAR-Q

| Field | Value |
|---|---|
| **SEVERITY** | P2 |
| **STATUS** | DISCOVERED — STATIC |
| **EVIDENCE** | The only writers are `onboarding/domain/intake_data.dart` (`toSupabasePartial` / `toSupabase`). `/intake` is reached only through login and signup redirects when `onboarding_complete == false` (`login_screen.dart:52-61`, `app_router.dart:197-218`). No settings or profile screen writes these columns. The coach reads them (`client_detail_screen.dart:668-796`). |
| **IMPACT** | Stale safety data drives coaching and AI. It contradicts the Privacy Policy "Correction — You may update your personal information directly within the app" (QAX-PRV-01). |
| **OWNER DECISION REQUIRED** | YES (product surface for health-history edits; clinical re-screening on PAR-Q change) |

### QAX-COR-04 — Injury AI memories are never retracted when the injury is corrected

P3 · LOCAL-REPLAY (function body).
- `capture_injury_memory()` only inserts `ai_memories(kind='injury')` rows (`075_ai_memory_autocapture.sql`), `ON CONFLICT DO NOTHING`. Nothing deletes them when `has_injuries` or `injury_locations` change.
- `ai-generate-workout` and `ai-coaching-engine` read these memories.
- Mitigation: the user can long-press to delete a memory in the AI Coach screen. A delete failure is swallowed (`ai_coach_service.dart:181`), but the list reloads, so it is **not a false success**.

### QAX-COR-05 — Nutrition logs cannot be edited or deleted, and quick-add double-taps duplicate

P2 · STATIC.
- `nutrition_service.dart:53` is the only writer (insert). No update or delete exists anywhere in `lib/`, although RLS permits both.
- `meals_dashboard_screen.dart:1074,1147`: `onQuickAdd` is not gated by `_saving`, and the table has no unique key.
- A mis-logged meal permanently counts in `getTodayTotals` and in scoring.

### QAX-COR-06 — Weight and measurement entries: no correction, and failures are silent

P3 · STATIC.
- `progress_screen.dart:1195-1196` and `:1339-1340`: `catch (_) { setState(() => _saving = false); }` with no message.
- `uid == null` returns before resetting `_saving`, so the spinner is stuck (`:1180`, `:1327`).
- For measurements: if the post-insert score upsert throws, the row exists but the sheet reports nothing, and a retry duplicates it (`:1189-1190`).
- There is no edit or delete UI for either table.

### QAX-COR-07 — Progress photos: gallery photos cannot be deleted, and replacing a baseline photo deletes the old one before the upload

| Field | Value |
|---|---|
| **SEVERITY** | P2 (private body images the user cannot remove; data loss on a failed replace) |
| **EVIDENCE** | `progress_screen.dart:329-333`: `storage.remove(existing)` (errors swallowed), then `uploadBinary(...)`. A failed upload loses the original even though the policy allows `upsert:true` without deleting first. No code deletes `progress_photo_logs` rows or gallery objects, although the owner-delete storage policy exists (029). |
| **DEPENDENCY** | Gated on QA by H-05, now bucket-created by 130 |
| **OWNER DECISION REQUIRED** | NO |

### QAX-COR-08 — Goals: "Mark achieved" is irreversible, delete has no confirmation, and both fail silently

P3 · STATIC.
- `goals_screen.dart:109` hides the whole menu once a goal is completed.
- `:116-120`: `complete` and `deleteGoal` are awaited with no try/catch. A failure is an unhandled async error, and the user sees nothing.

### QAX-ERR-01 — Cycle writes: failures leave the sheet open with no message; migration 131 turned a double-tap duplicate into this failure

P3 · LOCAL-REPLAY + STATIC.
- After 131, logging an existing start date raises `23505 cycle_logs_one_period_per_start` (reproduced).
- `womens_health_screen.dart:183-186` / `:229-235` have no try/catch, and the app has **no global error handler** (no `runZonedGuarded`, `PlatformDispatcher.onError` or `FlutterError.onError`). So the exception escapes `onPressed`, `Navigator.pop` never runs, and the user gets **no message**.
- 131's header ("the index makes the double tap fail rather than duplicate … No client change is required") is correct about the data but omits this user-facing outcome.
- **Also corrects F-06** (R-1).

### QAX-ERR-02 — Coach habit assignment and coach check-in feedback report success on failure or on zero rows

P3 · STATIC.
- `coach_program_service.dart:322-333`: deactivate-then-insert is not atomic, and `coachId == null` returns silently into "Habits assigned!" (`client_detail_screen.dart:1934-1938`).
- `weekly_checkin_service.dart:152-169`: an update that matches 0 rows returns `true` ("Feedback submitted!") if the relationship ended between loading the list and submitting. This is a narrow timing window.

### QAX-SES-01 — Mobile logout keeps cached per-user state; the next account can see the previous account's data

| Field | Value |
|---|---|
| **SEVERITY** | P2 (shared-device PHI exposure; mobile only) |
| **STATUS** | DISCOVERED — STATIC; runtime NOT DEMONSTRATED |
| **EVIDENCE** | Logout on web calls `reloadForLogout()` (state cleared). On mobile it calls `context.go('/login')` only (`settings_screen.dart:455-460`), and the single root `ProviderScope` (`main.dart:62`) survives. **12** non-autoDispose providers read `currentUser` without watching auth state, including `insightsProvider`, `nutritionGoalsProvider`, `coachClientsProvider`, `activeSessionProvider` and `streakProvider`. No invalidation occurs on sign-in (`login_screen.dart`, `app_router.dart`). |
| **FALSE-POSITIVE CHECK** | Individual screens may invalidate on open. That was not verified for all 12, so runtime is required. |
| **REMEDIATION** | Watch an auth-user provider in every per-user provider, or rebuild the `ProviderScope` on user change |
| **OWNER DECISION REQUIRED** | NO |

### QAX-PRV-01 — The Privacy Policy misstates what the app does (correction, providers, wearables, security)

| Field | Value |
|---|---|
| **SEVERITY** | P1 (legal/regulatory misrepresentation about health data) |
| **STATUS** | DISCOVERED — STATIC. **Owner/legal decision.** |
| **EVIDENCE** (`privacy_policy_screen.dart`) | **§5 Correction** (L85): "update your personal information directly within the app". False for PHI (QAX-COR-03) and partial for profile fields (QAX-COR-01). **§3 Service Providers** (L72) lists "Supabase, **Expo**, and selected analytics providers". Expo was removed (`9dc7515`). No analytics SDK exists. **Anthropic** (PHI), **Resend** (email and names) and **Stripe** (payments, email) are **not listed**. **§1/§4** describe heart-rate and step data synced from wearables and Apple Health. No HealthKit or Health Connect integration exists, and integrations are placeholder "connected" rows (existing M-05). **§4/§7** claim "AES-256", "TLS 1.3" and "regular security audits": unverifiable from the repo; owner must attest. |
| **RELATION** | Export and deletion claims are existing **W1B-N3** and **UIX-2**, and are not duplicated here |
| **OWNER DECISION REQUIRED** | YES |

### QAX-PRV-02 — Health data is sent to Anthropic with no disclosure, consent or processor determination

| Field | Value |
|---|---|
| **SEVERITY** | P1 |
| **STATUS** | DISCOVERED — STATIC. **Owner/legal decision** (expands F-18 / PD-D06 beyond cycle data) |
| **EVIDENCE** | `ai-coaching-engine/index.ts:143,153,195,244`: gender, DOB, height, weight, a full `cycle_logs` row, injury memories. `ai-coach/index.ts:40-111`: nutrition-plan notes, check-in weight, energy, stress and sleep, free text. `ai-generate-workout/index.ts:93-116`: injury memories. `analyze-food-image/index.ts:56-83`: food photos. NestJS `/ai/nutrition/message`: messages and images. |
| **IMPACT** | A third-party processor receives health data. The policy is silent, there is no consent gate, and no BAA/DPA status is recorded. |
| **OWNER DECISION REQUIRED** | YES |

### QAX-PRV-03 — Corrections to health data leave no audit trail

P2 · LOCAL-REPLAY.
- `pg_tables` has **0** tables matching `audit|history|change_log`.
- `user_profiles` triggers are only `capture_injury_memory`, `enforce_profile_privilege` and `apply_parq_risk`.
- Overwritten PAR-Q answers, injuries and supersessions (including QAX-SEC-01's) are unrecoverable and unattributable.
- Owner decision on the retention and audit posture (links PD-C04).

### QAX-REG-01 — Registry ID collision: a P1 women's-health defect reads as `VERIFIED_CLOSED`

| Field | Value |
|---|---|
| **SEVERITY** | P2 (governance: it can close a live P1 by lookup) |
| **EVIDENCE** | `MASTER_REMEDIATION_REGISTRY.md:224` and `:1479-1485` promote `F-01, F-03, F-05, F-06, F-07, F-08` to `VERIFIED_CLOSED`. These are the **Phase-1F security** items (e.g. `:251` "F-03 · notifications INSERT WITH CHECK (true)"). The **same IDs** name open Workstream-F women's-health defects in row `:1369` and in `MASTER_REMEDIATION_WAVES.md:449` ("7A … `F-03` (silent destruction of the user's own health log)"). |
| **VERIFIED** | Women's-health F-03 is **still open in code**: `todaySymptomsProvider` (`cycle_provider.dart:33`) has no consumer, and the sheet initialises empty. F-05 is also still open: `saveSettings` has no caller. |
| **REMEDIATION** | Namespace the Phase-1F rows (e.g. `1F-F-03`), in an owner-authorized registry edit |
| **OWNER DECISION REQUIRED** | YES (registry edit authority) |

### Hardening (P4)

- **QAX-H-01:** The 13+ age limit is enforced only by the DOB picker's `lastDate`. The DB accepts any `date_of_birth`, and a missing DOB is never age-checked.
- **QAX-H-02:** Coach self-registration is unvetted. This is the enabling condition for QAX-SEC-02b and QAX-SEC-07 → OD-QAX-1.

---

## 8. All security findings

- **New:** QAX-SEC-01 (P0), QAX-SEC-02 (P0), QAX-SEC-03 (P1), QAX-SEC-05 (P1), QAX-SEC-07 (P1), QAX-SEC-04 (P2), QAX-SEC-06 (P2), QAX-SES-01 (P2), QAX-H-01/02 (P4).
- **Re-verified existing, still open (static):**
  - **EDGE-1:** `notify-coach-email` never reads Authorization; unescaped HTML at L43/49/52.
  - **EDGE-2:** `send-checkin-reminder` has no auth and no idempotency.
  - **R-01:** `award_points` self-credit reproduced on the local replay.
  - **K-09:** `subscription.deleted` leaves the relationship active.
  - **K-03:** no entitlement or rate limit on paid AI.
  - **E-07:** open redirect URLs.
  - **E-14:** cancel-subscription local/Stripe divergence.
- **Expanded existing:**
  - **E-15** (P3): `send-invite-email` also interpolates caller-controlled `first_name`/`last_name` and `token` **unescaped** into HTML and into an `href` attribute (`:45,:49,:51-56,:68-73`), with `reply_to` set to the caller. This is an attribute breakout and phishing surface.
  - **REL-29** (P1, P3 while undeployed per ENV-8): concrete chain. `POST /auth/register {role:'admin'}` is accepted (DTO `IsEnum` includes admin, no ValidationPipe on the controller; `auth.service.ts:22` spreads the DTO). `GET /users` (admin) returns full user objects **including bcrypt hashes** (`users.service.ts:44-46`). JWT secret falls back to `'your-secret-key'` (`auth.module.ts:14`, `jwt.strategy.ts:11`).

## 9. All HIPAA/privacy findings

QAX-SEC-02, QAX-PRV-01, QAX-PRV-02, QAX-PRV-03, QAX-COR-03, QAX-COR-07, QAX-SES-01, and the
expansion of F-18/PD-D06. Existing and still open: W1B-N3 (export claim), UIX-2/REL-04
(deletion), F-18 (cycle to LLM).

## 10. All data-integrity findings

QAX-SEC-01, QAX-SEC-03, QAX-SEC-05, QAX-COR-01, QAX-COR-02, QAX-COR-04, QAX-COR-05, QAX-COR-06,
QAX-COR-07 (loss on replace). Re-verified existing: F-03 (symptom overwrite), F-04/I-WMH-01
(now constrained by 131), EC-05, EC-12, EC-22.

## 11. All UX/correctness findings

QAX-COR-02, QAX-COR-06, QAX-COR-08, QAX-ERR-01, QAX-ERR-02.

## 12. All owner decisions

| ID | Decision |
|---|---|
| OD-QAX-1 | Is "coach" a self-service role, or is it vetted/verified? It governs SEC-02b and SEC-07 exposure. |
| OD-QAX-2 | May a coach assign plans or programs to a `pending` client (SEC-01/03 fix shape)? |
| OD-QAX-3 | Which users may trigger global-library enrichment (SEC-07)? |
| OD-QAX-4 | Privacy Policy corrections: provider list, correction, wearable and security claims (PRV-01) |
| OD-QAX-5 | Health data to Anthropic: disclosure, consent, BAA/DPA (PRV-02; extends PD-D06) |
| OD-QAX-6 | In-app health-history editing and PAR-Q re-screening (COR-03) |
| OD-QAX-7 | Audit and retention posture for corrections (PRV-03; links PD-C04) |
| OD-QAX-8 | Authorize the registry namespace edit for the F-ID collision (REG-01) |

## 13. False positives discovered and retracted

**Prior claims contradicted by evidence** (recorded here; the source documents are not edited):

| # | Prior claim | Where | Evidence against |
|---|---|---|---|
| R-1 | "An RLS or network failure closes the sheet exactly as a success does" | `QA_WORKSTREAM_F_WOMENS_HEALTH_REPORT.md` F-06 | A thrown error escapes `onPressed` **before** `Navigator.pop`, so the sheet stays open silently. Only the `uid == null` branch and the no-open-period "Period ended" no-op close as if successful. |
| R-2 | "`client_nutrition_plans` — RLS, owner + active coach — Sound" | Workstream E :446 | The policy is `coach_id = auth.uid() OR client_id = auth.uid()` (QAX-SEC-03) |
| R-3 | 029's progress-photo RLS is "owner-scoped + coach-scoped" and safe once the bucket is private | Workstream H H-05; migration 130 comment | Coach scope has no status check (QAX-SEC-02) |
| R-4 | messages: "No cross-tenant … write" | Workstream H (I-NOT-04 row) | INSERT has no membership check (QAX-SEC-04) |
| R-5 | `exercises` view "OK" / "gates on visibility+approved" | Phase 1 §8; Workstream I I-COM-03 | The view has no WHERE (QAX-SEC-06) |
| R-6 | `assign_nutrition_plan` "reproduces the existing policy exactly" | `131_identity_constraints.sql:206-219`; `WAVE_3A_11_EXECUTION_EVIDENCE.md:133-143` | The definer supersede bypasses RLS (QAX-SEC-01) |

**False positives from this session's own instruments** (caught before recording):

| # | Instrument | What happened | Resolution |
|---|---|---|---|
| R-7 | Static regex over definer bodies | Flagged `rebuild_movement_graph`, `rebuild_exercise_intelligence`, `seed_warmup_library`, `sync_exercise_relations` and `finalize_intelligence` as unguarded (the regex missed their guard spelling) | The behavioural sweep shows all refuse a plain client (`forbidden` / `not authorized`). **Not a finding.** |
| R-8 | Delegated static agent | Claimed that `cycle_logs` "has no unique key" and that "70kg writes 0" | Migration 131's unique index was hit in the C1 probe. The `[0-9.]` input formatter makes letters untypeable. **Both retracted.** |
| R-9 | First probe draft | Results written inside rolled-back savepoints vanished (5 probes silently absent) | Results are now carried across rollback via psql `\gset`; all 12 defect probes print |
| R-10 | First seed of the former-coach sweep | A `workout_set_logs.set_id` trigger aborted the whole transaction, so every count was void | Each seed is isolated in its own savepoint. `habit_logs` had **no seed**, so its 0 is recorded **NOT DEMONSTRATED**. |
| R-11 | Static guarded-write scanner v1 | Missed `workout_provider.dart` reps/weight (writes through a `_write` helper) | Added a declared, both-direction-checked `indirectWriters` list. That surfaced `notes`, which was then classified CORRECT (`clearNotes` arm). |

**Verified equivalent, not a defect:** `get_or_create_conversation(B)` as a stranger creates a
conversation, but direct `INSERT INTO conversations` is equally permitted. 131 did not widen
anything; open messaging is K-10/REL-5 territory.

## 14. Mutation-testing evidence

**DB probe suite** (`supabase/tests/qa_exhaustion/run.sh`)

Base run: `CTRL-1` PASS, 12 defect probes FAIL, 5 positive controls PASS.

| Mutation (`--mutate`) | Probes flipped FAIL→PASS | Others | POS / CTRL |
|---|---|---|---|
| QAX-SEC-01 | SEC-01 | unchanged | all PASS |
| QAX-SEC-02 | SEC-02a, SEC-02b | unchanged | all PASS |
| QAX-SEC-03 | 6 × SEC-03.* | unchanged | all PASS |
| QAX-SEC-04 | SEC-04 | unchanged | all PASS |
| QAX-SEC-05 | SEC-05 | unchanged | all PASS |
| QAX-SEC-06 | SEC-06 | unchanged | all PASS |
| *over-blocking* (revoke RPC EXECUTE; ad hoc, not kept) | SEC-01 → PASS | — | **POS-01 → FAIL** (the positive control catches over-correction) |

Restored run: byte-identical to base. Catalog fingerprint (md5 over all policies, public
function bodies and the `exercises` view): `8d4237ee…` before = after.

**Instrument self-test:** a planted `SECURITY DEFINER` function is reported anon-executable
(`true`) and then rolled back, which proves the "0 anon-executable definer functions" result
is not an artefact of the shim.

**Static guard** (`apps/mobile/tool/qa_exhaustion/guarded_write_scan.mjs`)

Mutations were run on a scratch copy of `lib/` (`QAX_ROOT`). Base: 28 hits = 28 classified →
PASS.

| Mutation | Result |
|---|---|
| M1: new guarded write | FAIL (unclassified) |
| M2: fix `phone` without shrinking the manifest | FAIL (stale) |
| M3: guarded write inside a comment | PASS (correctly ignored) |
| M4: rename declared helper | FAIL |

Real tree restored → PASS; `git status apps/mobile/lib` clean.

**Not mutation-testable here:** anything needing Flutter (widget/runtime), and anything needing
QA (live). Stated, not assumed.

## 15. Live database evidence

**None obtained.** `eyqtldjqpgpljlqvpowh.supabase.co:443` → proxy `CONNECT 403` (policy denial),
recorded in the proxy status at 2026-09-25T01:15:16Z. No QA credential exists in the environment
(no `QA_DB_URL`, service key or test-user secrets). Production was never contacted.

**Substitute instrument (LOCAL-REPLAY), and its fidelity limits:**

- PostgreSQL 17.9 (npm `@embedded-postgres/linux-x64`, run as an unprivileged user, loopback port 55433).
- The repo's `supabase/tests/local/shim.sql` unmodified.
- Plus Supabase platform default privileges: `ALL` on tables, sequences and functions to anon/authenticated/service_role. **Without these, every denial would be a false "secure".**
- Then migrations 000–131 unmodified. Result: `REPLAY OK 000-131`, 91 public tables, all RLS-enabled.

Fidelity limits:
1. `auth.uid()` and `auth.role()` are the shim's claim readers, not GoTrue.
2. The storage API and PostgREST are not running. Probes evaluate the same RLS the services enforce, but composition is not proven.
3. QA may diverge from the committed migrations (ENV-2/ENV-3 history). **Every §7 DB result therefore needs a VERIFIED LIVE rerun.**

## 16. Runtime evidence

None. No Flutter SDK or emulator exists, and the Docker daemon is not running. No build was
attempted (disk: 30 GB free, so disk was not the blocker this time).

## 17. Environment blockers

| ID | Blocker | Remedy |
|---|---|---|
| EB-QAX-1 | QA Supabase host denied by the session network policy | Allow `eyqtldjqpgpljlqvpowh.supabase.co` in the environment's Network access settings, and provide QA test-user credentials (and `QA_DB_URL` if SQL-level probes are wanted) as environment secrets |
| EB-QAX-2 | No Flutter SDK or emulator; Docker daemon not running | Use a CI runner (the existing `ci.yml` jobs), or an environment whose setup installs Flutter |
| EB-QAX-3 (existing) | `QA_SERVICE`/fixture provisioning; Stripe test mode (`P-8`) | unchanged |

## 18. Untestable surfaces (this environment)

- Every VERIFIED LIVE rung.
- Storage-API signed-URL issuance.
- Deployed Edge Function behaviour and secrets (e.g. whether `STRIPE_WEBHOOK_SECRET` is set; whether stripe-node rejects an empty key, agent note D9: **unverified**).
- Push/email delivery.
- UI rendering of every failure state in §7.
- The 12 providers of QAX-SES-01 at runtime.
- Accessibility.
- Offline behaviour.
- Media playback.

## 19. Existing findings reconciled

| Existing | Status observed now | Instrument |
|---|---|---|
| SEC-R2 / F-J-17 | **Does not reproduce** on 000–131: a PAR-Q/injury/pregnancy declaration succeeds with `risk_level=high` and three flags. Consistent with its recorded FIXED IN CODE / VERIFIED IN CI (vocabulary-gap status). | LOCAL-REPLAY |
| R-01 (self-award points) | still reproduces | LOCAL-REPLAY |
| F-03 (symptom overwrite), F-05 (cycle_settings write-dead), F-21 (no period edit/delete), F-22 | still open | STATIC |
| F-04 / I-WMH-01 | duplicates now **refused** by 131's index. User-facing effect is QAX-ERR-01. | LOCAL-REPLAY |
| EC-05, EC-12, EC-22, M-05, E-14, K-03, K-09, E-07 | still open | STATIC |
| EDGE-1, EDGE-2 | still open | STATIC |
| E-15, REL-29 | still open; **expanded** (§8) | STATIC |
| H-05 | bucket created by 130; the policy it endorsed is QAX-SEC-02 | LOCAL-REPLAY |
| I-NOT-04 | UPDATE-scope finding unchanged; its "no cross-tenant write" sentence retracted (R-4) | LOCAL-REPLAY |
| ERR-3 | Onboarding `_finish` still marks complete after a failed save (`intake_flow_screen.dart:214-227`) | STATIC |
| Handoff "cycle_settings has no reachable user write path" | **confirmed** (= F-05) | STATIC |
| Handoff "5 guarded-write defects" | **confirmed and re-derived** (QAX-COR-01), source report absent | STATIC + LOCAL-REPLAY |

## 20. Duplicate findings reconciled

Delegated audit candidates folded into existing rows rather than re-filed:
- habit optimism → EC-12
- workout feedback → EC-22
- integrations "connected" → M-05
- cancel-subscription divergence → E-14 (Workstream D)
- subscription.deleted relationship → K-09
- paid-AI limits → K-03
- redirect URLs → E-07
- invite email → E-15 (expanded)
- NestJS stack → REL-29 (expanded)
- check-in table → I-CHK-01
- cycle items → F-03/F-04/F-05/F-21/F-22

## 21. Recommended remediation order

1. **QAX-SEC-02** (P0; body photos). One policy migration plus a live probe.
2. **QAX-SEC-01 + QAX-SEC-03** (P0/P1). One migration: the RPC guard, the six coach arms, and the active-assignment unique index. Resolve OD-QAX-2 first, or implement the strict form.
3. **QAX-SEC-05**, then **QAX-SEC-04**, then **QAX-SEC-06** (policy and view migrations).
4. **QAX-SEC-07** (Edge Functions; OD-QAX-3) and the **EDGE-1/EDGE-2/E-15** email set.
5. **QAX-PRV-01/02** (legal copy and processor posture; owner-led, can run in parallel).
6. **QAX-COR-01, -05, -07, -03**, then **QAX-SES-01**.
7. P3 set: QAX-COR-02/04/06/08, QAX-ERR-01/02, QAX-PRV-03, QAX-REG-01.

## 22. Required migrations (authoring only in the remediation phase)

| Migration | Purpose |
|---|---|
| M-A | `storage.objects` progress-photo coach policy → `is_active_coach_of` (SEC-02) |
| M-B | `assign_nutrition_plan` guard (SEC-01) + coach-arm rewrites on six tables + `workout_program_assignments` partial unique `(client_id) WHERE status='active'` (SEC-03) |
| M-C | `messages` INSERT membership check (SEC-04) |
| M-D | `exercise-media` owner-scoped update/delete (SEC-05) |
| M-E | `exercises` view WHERE (SEC-06) — preserve grants (112) and `security_barrier` choices |
| M-F (decision-gated) | audit table/trigger for PHI corrections (PRV-03) |

Each must follow governance §9 (preserve `search_path`, grants and comments), and each must
update `expected_applied.json` (ENV-3).

## 23. Required fixtures and credentials

- QA test users: a client victim, a stranger client, a stranger self-registered coach, an active coach and a cancelled coach. The live suite's existing fixture pattern (d0x) suffices.
- One uploaded `progress-photos` object and one `exercise-media` object on QA.
- Network access to the QA host (EB-QAX-1).

## 24. Required product/legal decisions

OD-QAX-1…8 (§12), plus the existing PD-D06 (extended by PRV-02) and PD-C04.

## 25. Exact next remediation phase

1. **Unblock live evidence first.** With EB-QAX-1 lifted, port `supabase/tests/qa_exhaustion/probes.sql` into the live security harness (`supabase/tests/security/`) as d09. Record BEFORE on QA. Probes that reproduce on QA become VERIFIED LIVE defects; any that do not are reconciled against QA's catalog (ENV-3).
2. **Wave "QAX-A" (security):** migrations M-A…M-E in the order of §21. Each change is closed per `QA_CLOSURE_STANDARD.md` §2.1 (FIXED IN CODE → FIXED ON QA → VERIFIED LIVE → VERIFIED IN CI). The local suite's fix-sims are **starting points, not reviewed fixes**.
3. **Wire the two QA guards into CI** in the enforcing direction (fail on defect), shrinking their manifests as fixes land. The DB suite runs where `negative-control.sh` already has a server.
4. **Owner session** for OD-QAX-1…8 before the privacy-copy and correction-surface work.
5. Runtime verification (EB-QAX-2) of QAX-SES-01, QAX-ERR-01 and the COR-* UI outcomes.

**No remediation was performed in this phase.**
