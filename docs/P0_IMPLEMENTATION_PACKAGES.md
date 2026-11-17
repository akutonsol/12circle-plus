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

### Backlog after cycle 4

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
