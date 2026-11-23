# P0 implementation packages — 12circle-plus controlled beta

How the P0 list maps onto the existing scope (`docs/CONTROLLED_BETA_SCOPE.md`, the ledger) and
onto the specialist team (`.claude/agents/cplus-*`, protocol in `.claude/skills/cplus-team-protocol`).
Nothing from the existing core is dropped: **bookings, session credits and payments stay in scope**
— they are blocked on decisions or external setup, not removed.

Status keys: **DONE-PR** fix ready in an open PR (unmerged) · **READY** decision-free work available
now · **BLOCKED-DEC** Julia's decision · **BLOCKED-MIG** migration apply · **BLOCKED-EXT** external
setup · **MQA** manual QA only.

| # | P0 area | Journeys | Owner | Status | Next package / blocker |
|---|---|---|---|---|---|
| 1 | Authentication & onboarding | 1, 2, 14 | flutter | MQA · BLOCKED-EXT | email provider + hosted URL; then walkthrough 1/2/14. Native deep links (`io.circle12.app`) only if native beta |
| 2 | Coach/client relationships & invitations | 3, 4, 5, 12 | supabase + flutter | **DONE-PR #172** (end coaching / request coach report what happened) · BLOCKED-MIG (193/194) · BLOCKED-EXT (email) | after apply: live verification; DEC 3, DEC 4 |
| 3 | Coach & client dashboards | 8, 11 | flutter | DONE-PR (#162, #163) | UX review package (ux-reviewer) of Home + coach dashboard states |
| 4 | Exercise library | 7 | flutter + content | DONE-PR (#166, #168 Edit gating) | content batches (DEC 13, QA writes); name mapping review (`docs/exercise_content/`) |
| 5 | Program creation & assignment | 6 | supabase + flutter | DONE-PR (#161, #169) · BLOCKED-MIG (196–197, 200) | DEC 8 (program sharing) |
| 6 | Workout execution, completion, history | 7, 8 | flutter | verified live (I-WRK-01); units/brief DONE-PR | — |
| 7 | Check-ins & coach review | 9, 10 | flutter | READY for a live leg only with QA-write approval; MQA | DEC 6 (resubmission) |
| 8 | Progress tracking | 11 | flutter | MQA | — |
| 9 | Basic messaging | — | supabase + flutter | BLOCKED-DEC | DEC 2 (which conversations are paid Coach Messaging), DEC 7 (chat times/order) |
| 10 | Settings & notifications | — | flutter + supabase | **DONE-PR #171** (`send-checkin-reminder` refuses non-service callers) | idempotency = DEC D-5; deploy = BLOCKED-EXT; push = BLOCKED-EXT/DEC |
| 11 | Secure backend integration | all | supabase + security | DONE-PR (#160, #165, #167, #168) · BLOCKED-MIG/EXT | apply 193–200; deploy functions |
| 12 | **Bookings** | (booking) | supabase + flutter | DONE (screen live, UIX-1); 195 BLOCKED-MIG | — |
| 13 | **Session credits** | (booking) | supabase | 198 DONE-PR; consumption BLOCKED-DEC | DEC 5 / 5b → `book_coaching_session()` package (design in ledger) |
| 14 | **Payments** | 12 (paid) | supabase | BLOCKED-EXT (Stripe test mode) · BLOCKED-DEC 11 | runbook §4 |
| 15 | Coach media privacy | — | supabase + flutter | **READY** (design): move transformation photos to their own public bucket, then make `coach-media` private (DEC 15b path) | needs a migration + data move → apply approval |

## The first packages the team can run now (decision-free, no apply/deploy needed)

1. **`send-checkin-reminder` refuses non-service callers** — `cplus-supabase-engineer`
   (node test + wiring test, CI step), verified by `cplus-qa-verifier`, reviewed by
   `cplus-security-reviewer`. Removes a deployment blocker.
2. **Coach-media privacy path, step 1 (prepared, not applied)** — `cplus-supabase-engineer`
   (migration for a `coach-public` bucket + policies; replay) then `cplus-flutter-engineer`
   (`coach_business_screen` uploads to it; test). Ordered: backend contract first.
3. **UX review of the P1 journeys** — `cplus-ux-reviewer` across journeys 5–12 on `main`,
   findings → small Flutter packages for `cplus-flutter-engineer`.

Each package follows `cplus-team-protocol`: one branch/worktree per owner, contract before
cross-layer work, failing-first tests, independent verification, the report block, no merges.

## Cycle 1 log (2026-11-16) — first agent-led packages

Mechanism: each specialist ran as a real Claude Code session started **as the agent**
(`claude -p --agent cplus-…`) in its own worktree containing these definitions (this lead session
predates them and cannot load them through its Agent tool). Lead = main session.

| Package | Agent | Responsibility | Branch / commits | Files changed | Tests | Independent review | Remaining |
|---|---|---|---|---|---|---|---|
| P0-SEC-1 reminder caller check | `cplus-supabase-engineer` | implement | `fix/checkin-reminder-service-only` 374ab19, 371ed6b → **PR #171** (CI 7/7, run `43987746265`) | `send-checkin-reminder/index.ts`, `service_caller.mjs`, `supabase/tests/functions/checkin_reminder_caller.test.mjs`, `ci.yml` (1 step), `config.toml` (comments) | node 10/10; wiring test fails on main (9/10); 12 QA mutants all caught | security **APPROVE-WITH-NOTES**; QA **VERIFIED** ×2 | D-5 idempotency; deploy |
| R-0 find the top P1 defect | `cplus-ux-reviewer` | review journeys 5, 9, 10, 12 on main | — (read-only) | — | — | lead re-read finding 1 on main | findings 3–5 queued (5 needs DEC) |
| P0-FL-1 relationship writes report what happened | `cplus-flutter-engineer` | implement + 2 follow-ups | `fix/ending-coaching-reports-what-happened` 2db7021, 49d1228, a39435d → **PR #172** | `coach_relationship_service.dart`, `profile_screen.dart`, `manage_subscription_screen.dart`, `intake_flow_screen.dart`, 3 new + 5 updated tests | full suite 2695 pass; analyze 291; new tests fail on main / on 2db7021 | security **APPROVE-WITH-NOTES**; UX **PASS-WITH-NOTES** (F1/F2 fixed); QA **VERIFIED** ×2 | pricing writes' silent no-op; UX findings 3/4 |

Runtime (device/simulator) verification: **not performed** — the fixed paths need QA data states
(ended or refused relationships) that would require unauthorized QA writes; covered by widget and
unit tests against fake backends.

## Cycle 2 log (2026-11-16) — P0-FL-2 and P0-FL-3

Same mechanism as cycle 1 (`claude -p --agent cplus-…`, one worktree per agent, explicit tool lists, no
push/gh/supabase for agents). Reviews ran in parallel; every material finding was fixed and re-verified
before the PR opened. The lead ran the static guards (headless agents cannot) and made two small,
disclosed changes on #174.

| Package | Agent | Responsibility | Branch / commits | Files changed | Tests | Independent review | Remaining |
|---|---|---|---|---|---|---|---|
| P0-FL-2 requests tab + check-in history recover from errors (R-0 findings 3, 4) | `cplus-flutter-engineer` | implement + 1 follow-up | `fix/requests-and-history-recover-from-errors` 913a0d9, 918c8dc → **PR #173** (CI 7/7 on 918c8dc, run `44001635796`) | `coach_dashboard_screen.dart`, `checkin_hub_sections.dart`, `coach_requests_recover_test.dart` (new), `checkin_hub_sections_test.dart` | full suite 2696 pass; analyze 291; 6 tests fail on main, 6 more on 913a0d9 | security **APPROVE-WITH-NOTES** (F2 fixed); UX **PASS-WITH-NOTES** (U1/U4/U5 fixed); QA **VERIFIED** ×2 (negative controls caught) | raw `e.toString()` on leaderboard / community / create-exercise; Requests badge `valueOrNull` |
| P0-FL-3 price writes report what happened (backlog inspection of signed-out pricing writes) | `cplus-flutter-engineer` + lead | implement + 1 follow-up; lead: spinner label + its test | `fix/price-writes-report-what-happened` (stacked on #172) e239eed, 44483d0, 0b89742, 4d1d992 → **PR #174** (CI 7/7 on 4d1d992, run `44002583036`) | `coach_relationship_service.dart` (two price methods), `coach_pricing_sheet.dart`, `client_detail_screen.dart` (custom-price dialog), 2 new + 1 updated test files | full suite 2714 pass; analyze 291; tests fail on a39435d (11) and on e239eed's screens (10) | security **APPROVE-WITH-NOTES** (local replay of 113/192); UX **PASS-WITH-NOTES** (U1–U3, U5 fixed); QA **VERIFIED** ×2 (16 negative controls caught) | F1 custom price impossible for invited clients (migration); F2 + $0 price (decisions); `coach_business_screen` same bug |

Runtime (device/simulator/live QA) verification: **not performed** — the failure paths need failing or
0-row QA reads and writes, which are not authorized; covered by widget and fake-PostgREST unit tests that
assert inside the sheet/dialog.

### Next decision-free packages found this cycle

1. **P0-FL-4** `coach_business_screen` `_save`: 0-row update says "Profile updated!", an unparseable
   price is saved as `0`, signed-out is silent — `cplus-flutter-engineer` (same pattern as FL-3).
2. **P0-FL-5** raw `e.toString()` on the coach leaderboard tab, `community_screen`, `create_exercise_screen`
   — `cplus-flutter-engineer` (same pattern as FL-2).
3. **P0-SB-2** let a coach set `monthly_price` on an active coach-initiated relationship without reopening
   self-activation (113 UPDATE check vs 192) — `cplus-supabase-engineer`, migration + replay. **Held: no migration is
   created or applied until Julia resolves Decisions 17 and 18 and explicitly authorizes the work.**

## Cycle 3 log (2026-11-16) — P0-FL-4 and P0-FL-5

Same mechanism. New this cycle: the lead's static-guard run caught a regression the agents could not see
(contract guard 32 > 31 unseen write sites, from a helper passing an update payload by variable); and the QA
verifier's temporary product-code mutations were blocked by its session's auto-mode classifier, so the **lead ran the
code mutants** (the lead wrote none of this code) and the verifier did everything else.

| Package | Agent | Responsibility | Branch / commits | Files changed | Tests | Independent review | Remaining |
|---|---|---|---|---|---|---|---|
| P0-FL-4 Business Profile reports what happened | `cplus-flutter-engineer` | implement + 3 follow-ups | `fix/business-profile-reports-what-happened` 97321b1, dd9a333, d0a2722, 06ca1af → **PR #176** (CI 7/7 on 06ca1af, run `44014296382`) | `coach_business_screen.dart`; `business_profile_reports_what_happened_test.dart` (new, 50 tests) | full suite 2733 pass; analyze 287; contract 31 ≤ 31; coordinator 268/268; 20 tests fail on main | security **APPROVE-WITH-NOTES** (local replay); UX **PASS-WITH-NOTES** ×2; QA **REJECTED** → **VERIFIED** ×2; lead mutants 7/7 caught | Decision 18 (clear price/years, $0); SR-2/3/4; photo orphan (15b); 4 sibling unchecked updates |
| P0-FL-5 no raw exception text (leaderboard, community feed, create exercise) | `cplus-flutter-engineer` | implement + 1 follow-up | `fix/no-raw-errors-leaderboard-community-exercise` (stacked on #173) a9e69be, 87cda02 → **PR #175** (CI 7/7 on 87cda02, run `44012398498`) | `coach_dashboard_screen.dart` (leaderboard), `community_screen.dart`, `create_exercise_screen.dart`, `custom_exercise_service.dart` (lastError only); 3 new widget + 1 new unit test files | full suite 2725 pass; analyze 291; 10 fail on 918c8dc, 13 on a9e69be | security **APPROVE-WITH-NOTES**; UX **PASS-WITH-NOTES** ×2; QA **REJECTED** → **INCONCLUSIVE** (mutants blocked); lead mutants 5/5 caught | media failures shown as success (F4); members list failure shown as empty; PD-A24 redaction; resubmit-for-review control (decision) |

Runtime (device/simulator/live QA): **not performed**; journey completion unchanged (2 of 14).

## Cycle 4 log (2026-11-17) — P0-FL-6 to P0-FL-9 + SR-4 investigation

Four implementers ran in parallel (one worktree each), then 8 read-only UX/security reviews in parallel, then 4 QA
verifications in each package's worktree. New this cycle: the QA verifier's candidate code mutants were run by the
lead (verifier sessions cannot edit product code); **13 survived** across the four packages — all test gaps, none a
product defect — and a **test-only** engineer round per package closed them (lead re-run: **13/13 caught**; runner
validated with a control mutant). FL-9's Home baseline needed a test hook on the base file, so the lead built it
(4d1d992 + hook only → 0/5 pass). Two read-only QA reads by the lead (schema dump; one aggregate count).

| Package | Agent | Responsibility | Branch / commits | Files changed | Tests | Independent review | Remaining |
|---|---|---|---|---|---|---|---|
| P0-FL-6 pricing-sheet failed read + Requests label | `cplus-flutter-engineer` | implement + review fixes + test-only | `fix/pricing-load-and-requests-badge-report-failures` (on #174) af83748, 739996f, 7844f17 → **PR #177** (CI 7/7 on 7844f17, `44029419873`) | `coach_pricing_sheet.dart`, `coach_dashboard_screen.dart` (label); 2 new + 1 updated tests | 2744 pass; analyze 291; 12 fail on 4d1d992 | security APPROVE-WITH-NOTES; UX PASS-WITH-NOTES; QA VERIFIED; mutants 4/4 caught | Custom Price dialog copy split; ~7 s postgrest retry |
| P0-FL-7 exercise media failures | `cplus-flutter-engineer` | implement + review fixes + test-only | `fix/exercise-media-failures-are-not-success` (on #175) 255fc35, 098f758, ca3ca97 → **PR #178** (CI 7/7 on ca3ca97, `44030338977`) | `create_exercise_screen.dart`, `custom_exercise_service.dart` (`updateExerciseMedia`); 1 new test file | 2746 pass; analyze 291; 16 fail on 87cda02 | security APPROVE-WITH-NOTES; UX **FAIL → PASS-WITH-NOTES** (retry duplicate fixed); QA VERIFIED; mutants 2/2 caught | 072 media authz until 199; auto-review of new coach exercises (decision) |
| P0-FL-8 community members failure | `cplus-flutter-engineer` | implement + feed rule + test-only | `fix/community-members-failure-is-not-empty` (on #175) 53af301, 0ca4425, 8d2eb09 → **PR #179** (CI 7/7 on 8d2eb09, `44031390664`) | `community_provider.dart`, `community_screen.dart`; 1 new + 1 updated test | 2744 pass; analyze 291; 11 fail on 87cda02 | security APPROVE-WITH-NOTES; UX PASS-WITH-NOTES; QA VERIFIED; mutant caught | groups failure shown as "no groups" (Community + Activity); dead `postListProvider`; member listing unscoped (decision) |
| P0-FL-9 updates verify a changed row | `cplus-flutter-engineer` | implement + review fixes + test-only | `fix/updates-verify-changed-row` (on #174) 3cb4e4e, 2585107, 12b098d, e8ef987 → **PR #180** (CI 7/7 on e8ef987, `44032450976`) | `settings_screen.dart`, `home_screen.dart` (review dialog), `intake_flow_screen.dart` (`_saveProgress`); test support + 3 new tests | 2733 pass; analyze 291; contract sites 172 → 171 | security APPROVE-WITH-NOTES (replay; **proved the rating defect**); UX PASS-WITH-NOTES; QA INCONCLUSIVE → lead baseline 0/5; mutants 6/6 caught | **rating rollup defect (migration)**; who may review a coach (decision) |
| SR-4 coach writes client profile (investigation) | `cplus-security-reviewer` | read-only investigation + local replay | — | none | replay: 78 columns classified; 24 non-active rows unchanged; client control | lead confirmed against live QA schema (read-only dump) | **Decision 19** (A/B/B′/C); no migration until approved |

Runtime (device/simulator/live QA): **not performed**; journey completion unchanged (2 of 14).

## Cycle 5 log (2026-11-17) — P0-FL-10, P0-FL-12, P0-FL-11, silent-error inventory, investigations

New this cycle: an **integration branch** `integration/p0-flutter-stack` (origin/main + every open Flutter PR head,
merged locally, nothing into main) gave P0-FL-11 one correct base; the lead ran its full suite and read CI twice
(f4cf7b1: 2895 pass, CI 7/7; e606fe5: 2954 pass, CI 7/7). Reviews ran against the **exact final commits**; reviewers
read from commits (`git show`) while QA used the worktree. Read-only investigations by `cplus-security-reviewer` (×2)
and `cplus-supabase-engineer` (scratch-database validation only); the lead added read-only QA catalog reads.

| Package | Agent | Responsibility | Branch / commits | Files changed | Tests | Independent review (final head) | Remaining |
|---|---|---|---|---|---|---|---|
| P0-FL-10 group-list failure states | `cplus-flutter-engineer` | implement + leave row check + review/mutant round | `fix/groups-failure-is-not-empty` (on #179) 14d8518, 452a87a, 2ff8080, 8e62718, 4c3a7c2 → **PR #181** (CI 7/7 on 4c3a7c2, `44231208557`) | community provider/screen, activity screen, live_community_service; 2 new + 1 updated tests | 2781 pass; analyze 291; mutants 8/8 | UX PASS; security APPROVE-WITH-NOTES; QA VERIFIED | group membership readable by all (decision) |
| P0-FL-12 client-detail never wipes plan/habits | `cplus-flutter-engineer` | implement + review/mutant round | `fix/client-detail-prefill-failure-never-wipes` (on #180) 90e307a, 23dd969 → **PR #182** (CI 7/7 on 23dd969, `44232187464`) | client_detail_screen, coach_program_service; 1 new test file | 2755 pass; analyze 291; mutants 6/6 (+1 documented) | UX PASS-WITH-NOTES; security APPROVE-WITH-NOTES; QA VERIFIED | multi-coach plan ownership (decision 21); QA lacks 184/185 (QAX-SEC-01/03 live) |
| P0-FL-11 shared error-handling cleanup | `cplus-flutter-engineer` | implement | `fix/shared-network-failure-and-cleanup` (on integration e606fe5) 2ecd6e2 → **PR #183, base = integration branch** (CI 7/7 on 2ecd6e2, `44236734289`) | new core helper + test; 9 lib files; 1 test expectation | 2969 pass; analyze 287; mutants 3/3 | UX PASS-WITH-NOTES; security APPROVE-WITH-NOTES; QA VERIFIED | rebase onto main after the stack lands |
| Silent-error inventory | `cplus-flutter-engineer` (read-only) | inventory + grouping | — → `docs/SILENT_ERROR_INVENTORY.md` (ledger PR #164) | — | — | lead verified the P1 sites | P0-FL-13 … P0-FL-19 |
| Decision 19 brief, Decision 20 + member list, P0-SB-3 design | `cplus-security-reviewer` ×2, `cplus-supabase-engineer` | read-only investigations | none (scratch only) | none | replays: D20 29+5+14 cases; SB-3 option D 25/25 on 4 shapes | lead confirmed coach_reviews policies and QA migration state read-only | Decisions 19–24 (Julia); SB-3 after D20; F1 PAR-Q clear (P1, migration) |

Runtime (device/simulator/live QA): **not performed**; journey completion unchanged (2 of 14).

## Cycle 6 log (2026-11-18/19): P0-FL-19, P0-FL-37, P0-FL-13/15/18/14/16/17

**How the cycle ran.**
- Every package started from #183's head (`2ecd6e2`). Each PR targets #183's branch, except P0-FL-17, which targets P0-FL-16's.
- **Batches.** Four engineers ran in parallel (batch A), then three, then FL-17.
- **Reviews.** Every package got independent UX, security and QA review at its exact final head, then a fix round and narrow re-checks.
- **Lead-run checks.**
  - Code mutants, using the test list taken from the package's diff.
  - CI's 10 negative-control scripts, run locally.
  - Static guards.
- **Combined evidence branch.** `integration/p0-flutter-stack-c6` = `e606fe5` + `2ecd6e2` + the eight final heads:
  - @ `6f8918f`: 3192 tests pass, analyze 287, guards 0, CI **7/7** (push run `44463329197`).
  - It caught one cross-package defect, which was fixed test-only on FL-15 (`c117cfb`).

| Package | Agent | Branch, final head, PR | Files | Tests (full) | Independent review (final head) | Lead mutants | CI (exact head) |
|---|---|---|---|---|---|---|---|
| P0-FL-19 intake photos / resume / coach list | `cplus-flutter-engineer` ×2 rounds | `fix/intake-photos-and-resume-tell-the-truth` `e3d5636` → **#185** | `intake_flow_screen.dart`, `coach_provider.dart` | 2983 | UX PASS-WITH-NOTES · sec APPROVE · QA VERIFIED (first QA pass caught an EC-03 break) | all caught | 7/7 `44446529335` |
| P0-FL-37 assessment only via the logged RPC | engineer ×3 rounds + lead (coordinator pin, CON-03 fact update, EC-04 probe) | `fix/coach-reads-assessment-through-logged-route` `ef3d67a` → **#187** | `coach_ecosystem_provider.dart`, `client_detail_screen.dart`, coordinator test, CON-03 memo, EC-04 probe | 2987 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 7/7 | 7/7 `44451418256` |
| P0-FL-13 messaging inbox/send | engineer ×2 | `fix/messaging-inbox-and-send-truth` `72fed97` → **#184** | `messaging_service.dart`, `messaging_screen.dart`, `chat_screen.dart` | 2988 | UX PASS · sec APPROVE-WITH-NOTES · QA VERIFIED | 6/6 | 7/7 `44444119951` |
| P0-FL-15 sign-in routing | engineer ×2 + lead (test teardown) | `fix/sign-in-role-read-failure-not-guessed` `c117cfb` → **#186** | `login_screen.dart`, `app_router.dart` | 3002 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 9/10 + 1 equivalent | 7/7 `44459402632` |
| P0-FL-18 progress views | engineer ×2 | `fix/progress-reads-failure-not-empty` `b556bca` → **#188** | `workout_service.dart`, 3 screens, new `section_load_failure.dart` | 3002 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 9/9 | 7/7 `44453836812` |
| P0-FL-16 profile read passes failures on | engineer ×3 | `fix/profile-read-failure-not-member-defaults` `3f357ee` → **#189** | `auth_provider.dart`, 4 screens, new notice widget | 3005 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | all single-surface + all-layers-off caught; 3 equivalent | 7/7 `44454848750` |
| P0-FL-14 coach notifications + availability | engineer ×3 | `fix/coach-notifications-and-availability-truth` `beb2a3f` → **#190** | `coach_dashboard_screen.dart`, `coach_availability_screen.dart` | 3000 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | all caught | 7/7 `44456761740` |
| P0-FL-17 plan label never "Free" when unknown | engineer ×2 (lead rebase onto FL-16) | `fix/plan-label-unknown-not-free` `d307187` → **#191** (base #189) | 5 payments/profile/settings screens | 3044 | UX PASS · sec APPROVE-WITH-NOTES · QA VERIFIED | 8/8 | 7/7 `44461871147` |

**Read-only work.** The QA migration discrepancy report (`docs/QA_MIGRATION_DISCREPANCY_REPORT.md`, on #164) was produced by the lead using read-only CLI queries. Nothing was applied.

**Runtime evidence.** No device, simulator or live-QA run. Journey completion is unchanged at 2 of 14.

## Cycle 7 log (2026-11-19): P0-FL-38, P0-FL-39, P0-FL-40

**How the cycle ran.**
- Every package started from `integration/p0-flutter-stack-c6` @ `6f8918f` and targets that branch.
- Three engineers ran in parallel, each followed by independent UX, security and QA review at the final head, fix rounds, and narrow re-checks.
- The lead ran mutants (test lists taken from each package's diff), CI's 10 negative-control scripts locally, and the static guards.
- **Combined branch `integration/p0-flutter-stack-c7`** @ `df35d5f`: 3335 tests pass, analyze 287, guards 0, CI **7/7** (push run `44497593361`).
  - It surfaced one cross-package conflict: an import block in `coach_copilot_screen.dart` (FL-38 vs FL-40), resolved by keeping both imports.

| Package | Agent | Branch, final head, PR | Tests (full) | Independent review (final head) | Lead mutants | CI (exact head) |
|---|---|---|---|---|---|---|
| P0-FL-38 health data only via the logged route; Requests crash; injury parse | `cplus-flutter-engineer` ×5 rounds + lead (coordinator message, decision-free readings) | `fix/coach-health-reads-through-logged-route` `a58db40` → **#194** | 3213 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 6/7 + 1 equivalent | 7/7 `44492737057` |
| P0-FL-39 writes confirmed before success | engineer ×2 | `fix/writes-confirm-they-persisted` `6b82a6d` → **#192** | 3242 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 9/9 | 7/7 `44486090822` |
| P0-FL-40 failed reads not shown as role or plan facts | engineer ×2 | `fix/failed-reads-not-shown-as-role-or-plan-facts` `6189d19` → **#193** | 3264 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 12/12 | 7/7 `44488770104` |

**Lead (read-only):** `docs/QA_184_185_WINDOW_DECISION_BRIEF.md` (on #164), the owner decision brief for the QA window. Nothing executed.

**Runtime evidence:** none (no device, simulator or live QA). Journeys unchanged at 2 of 14.

## Cycle 8 log (2026-11-22): P0-FL-41 to P0-FL-44

**How the cycle ran.**
- Every package started from `integration/p0-flutter-stack-c7` @ `df35d5f` and targets that branch.
- Four engineers ran in parallel, followed by independent UX, security and QA review at the final heads, fix and test rounds, and narrow re-checks.
- The lead ran mutants (test lists from each package's diff, plus per-site revert mutants where single layers are equivalent), CI's negative controls locally, and the static guards.
- **Combined branch `integration/p0-flutter-stack-c8`** @ `185261e`: 3456 tests, analyze 287, guards 0, CI **7/7** (`45100790460`). No cross-package defect.

| Package | Agent | Branch, final head, PR | Tests (full) | Independent review (final head) | Lead mutants | CI (exact head) |
|---|---|---|---|---|---|---|
| P0-FL-41 joined-profile crashes | `cplus-flutter-engineer` | `fix/leaderboard-missing-profile-never-crashes` `e9fcb30` → **#195** | 3340 | UX PASS-WITH-NOTES · sec APPROVE · QA VERIFIED | per-site reverts 3/3 | 7/7 `45076272294` |
| P0-FL-42 client cancel confirmed | engineer ×2 | `fix/client-booking-cancel-confirmed` `1e5199a` → **#196** | 3346 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 4/4 | 7/7 `45097658625` |
| P0-FL-43 copilot generate failure | engineer ×3 + lead scope correction | `fix/copilot-services-report-failures` `d8af61d` → **#197** | 3340 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 3/3 | 7/7 `45098982386` |
| P0-FL-44 failed or stale role reads | engineer ×3 (incl. 70 transition tests) | `fix/role-read-failure-not-a-role-fact` `9cae07a` → **#198** | 3435 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED | 4/4 | 7/7 `45099911540` |

**Runtime evidence:** none (no device, simulator or live QA). Journeys unchanged at 2 of 14.

## Cycle 9 log (2026-11-22/23): P0-FL-45a, P0-FL-45b, P0-FL-46 to P0-FL-48

**How the cycle ran.**
- Every package started from `integration/p0-flutter-stack-c8` @ `185261e` and targets that branch.
- Five engineers ran in parallel. Each package then got independent UX, security and QA review, one review round, and narrow re-checks (QA on every package; UX on every package; security on FL-45a/45b).
- The lead ran mutants twice:
  - once at the first heads, where the 3 survivors in FL-45b exposed identity-matrix gaps;
  - once at the final heads, with test lists from each package's diff and a multi-layer mutant where two layers are redundant.
- The lead also ran CI's negative controls locally and the static guards.
- Identity changes (FL-45a/45b) carry the full matrix: both switch directions, the new member's read in flight / failed / succeeded, the previous member's late answer, sign-out only, a same-member failed refresh, a mismatched row, and session isolation.
- **Combined branch `integration/p0-flutter-stack-c9`** @ `1b94044`: 4393 tests, analyze 287, guards 0, negative controls 0, CI ****7/7** run `45132607442` on `1b94044`**. No cross-package defect.

| Package | Agent | Branch, final head, PR | Tests (full) | Independent review (final head) | Lead mutants | CI (exact head) |
|---|---|---|---|---|---|---|
| P0-FL-45a member-confirmed role gate, 9 screens | engineer ×2 | `fix/role-gates-member-confirmed` `f980611` → **#199** | 3926 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED (NOT VERIFIED at round 1) | 8/9 + multi-layer 1/1 | 7/7 `45126666339` |
| P0-FL-45b member-confirmed profile/role reads (fixed P0: A's details saved into B's row) | engineer ×2 | `fix/role-reads-member-confirmed` `991192d` → **#200** | 3891 | UX PASS-WITH-NOTES · sec APPROVE-WITH-NOTES · QA VERIFIED (NOT VERIFIED at round 1) | 10/11 (round 1: 3/6) | 7/7 `45127825008` |
| P0-FL-46 coach cancel status + booking errors | engineer ×2 | `fix/booking-cancel-and-errors-honest` `0f0c13c` → **#201** | 3468 | UX PASS · sec APPROVE-WITH-NOTES · QA VERIFIED | 5/5 | 7/7 `45129070292` |
| P0-FL-47 coach reviews failure + leaderboard ticker | engineer ×2 | `fix/coach-reviews-and-leaderboard-truth` `a75650b` → **#202** | 3464 | UX PASS · sec APPROVE · QA VERIFIED | 5/5 | 7/7 `45130262805` |
| P0-FL-48 accessibility (AuthButton, 44px, 2× overflows) | engineer ×2 | `fix/accessibility-overflows-and-semantics` `03b9369` → **#203** | 3468 | UX PASS · sec APPROVE-WITH-NOTES · QA VERIFIED | 5/6 | 7/7 `45131357900` |

**Runtime evidence:** none (no device, simulator or live QA). Journeys are unchanged at 2 of 14 and beta conditions at 0 of 4.

### Backlog after cycle 9 (decision-free first)

1. **P0-FL-49: remaining member-unconfirmed reads.** `activity_screen` notif_* readers and `messaging_screen:122`. Home's Women's Health gender read is protected and stays untouched.
2. **P0-FL-50: swallowed reads.** `CustomExerciseService` (null on failure), `ai_coach_service:177` and `custom_exercise_service:250/662/916` ([] on failure). Also the staff-screen error copy: "Assign failed." and empty pickers on a failed read.
3. **Accessibility and cosmetic.** `_CoachingModePage` 2× overflow; Compliance row 2×; deflake the business-profile and messaging photo tests under load; leaderboard tick on `coach_client_relationships`; then the P3 backlog.
4. **Needs Julia.**
   - The SEC-R3 / Wave 3B-4 ruling, which also gates the Copilot `_explain` / `_approve` session guard; the 184/185 QA window.
   - Decisions 17–24; P0-SB-2; P0-SB-3; member list; server-side PHI read enforcement; client call-status transitions.
   - New this cycle: the Workout Zone unit lock; `coaching_calls` column authority (011 FOR ALL); the 42501 wording; Action Center density at 1x.

### Backlog after cycle 8 (decision-free first)

1. **P0-FL-45:** about 15 remaining role reads move to `confirmedRoleRead` (stale-role P2).
2. **P0-FL-46:** coach-side cancel status filter, `_book` copy, `coachReviewsProvider` swallow, leaderboard ticker.
3. **Accessibility and cosmetic,** then the P3 backlog.
4. **Needs Julia.**
   - The SEC-R3 / Wave 3B-4 ruling (`predictClient` and siblings); the 184/185 QA window.
   - Decisions 17–24; P0-SB-2; P0-SB-3; member list.
   - Server-side PHI read enforcement; client call-status transitions.

### Backlog after cycle 7 (decision-free first)

1. **Data integrity.** `score_service.dart:114` leaderboard missing-profile crash; client booking cancel (0-row check and voice); `generateWorkout` and `predictClient` swallow errors.
2. **Role reads.** Sibling `valueOrNull?['role']` reads (`paywall_gate.dart:31` first).
3. **Accessibility and cosmetic.** Shared gate helper; 2× overflows; `AuthButton` Semantics; deflake the business-profile photo test; then P0-FL-20 … P0-FL-36.
4. **Needs Julia.**
   - The 184/185 QA window (decision brief).
   - Decisions 17–24; P0-SB-2; P0-SB-3; member list.
   - Server-side PHI read enforcement; roster risk logging; Q-H1; copilot blocking.

### Backlog after cycle 6 (decision-free first)

1. **P0-FL-38: unlogged PHI reads.** `coach_copilot_screen.dart`, `coach_relationship_service.dart`; `coach_dashboard_screen.dart` roster `risk_level` needs a decision first, so report it.
2. **P0-FL-39: false-success writes.** Notification `_saveToggle`; Personal Info avatar and save; notification-sheet mark read, mark all, swipe delete, clear all; `_cancelSession`.
3. **P0-FL-40: failures shown as false facts.** Role-gated "Coaches only." on a profile failure; empty Manage subscription lists; `train_hub` activeSession (EC-G6).
4. **Cosmetic and accessibility.** 2× overflows (photo step, client page, Profile and Settings headers, notification sheet header); `AuthButton` Semantics; then the P3 backlog P0-FL-20 … P0-FL-36.
5. **Needs Julia.** The 184/185 QA window (Option S or R); Decision 19 / F1; server-side PHI read enforcement; P0-SB-2 (Decisions 17, 18); P0-SB-3 (Decision 20); member list (Decision 22); Decisions 21, 23 and 24.

### Backlog after cycle 5 (decision-free first)

1. **P0-FL-19** intake (the remaining **P1**: baseline photos silently lost) + resume failure + coach list — on #180.
2. **P0-FL-13** messaging inbox/send · **P0-FL-15** sign-in routing · **P0-FL-18** progress views — from `origin/main`.
3. **P0-FL-14** coach notifications + availability (integration base) · **P0-FL-16/17** profile read + plan labels (on #180).
4. **P0-FL-37** coach PAR-Q tab via the logged `get_client_assessment()` RPC (F3; fixes the PHI ledger's false CLOSED).
5. Migrations needing approval: 184/185 QA window (QAX-SEC-01/03 live), P0-SB-3 (after Decision 20), Decision 19
   (F1 PAR-Q clear), P0-SB-2 (Decisions 17/18).

### Backlog after cycle 4 (FL-10/11 done in cycle 5)

1. **P0-SB-3 (migration, needs approval)** coach rating rollup blocked by 115's pin — fix option A + backfill; after
   Decision 20 (who may review a coach).
2. **SR-4 (decision 19)** — no work until Julia picks A/B/B′/C.
3. **P0-SB-2** — still blocked on Decisions 17 and 18 and explicit authorization.
4. **P0-FL-10** `groupNotifierProvider` failure shown as "no groups" (Community Groups tab + Activity).
5. **P0-FL-11** move `isNetworkFailure` to one shared helper (after #175/#176/#177/#179/#180 merge); delete
   `postListProvider`; Set Custom Price dialog copy split.
6. Remaining silent `catch (_) {}` in `lib/` (46 sites, ~20 files) — triage into packages.

### Backlog after cycle 3 (FL-6..FL-9 done in cycle 4)

1. **P0-FL-6** pricing sheet `_load` failed read (`catch (_) {}` → indistinguishable from "no price") and the Requests
   tab badge (`pendingRequestsProvider.valueOrNull` → a failed read shows as no requests).
2. **P0-FL-7** create exercise: media upload/attach/sync failures after a save reported as success.
3. **P0-FL-8** community members list: every error becomes "No members yet".
4. **P0-FL-9** unchecked updates: `settings_screen.dart:69`, `home_screen.dart:1329`,
   `coach_relationship_service.dart:218`, `intake_flow_screen.dart:163`.
