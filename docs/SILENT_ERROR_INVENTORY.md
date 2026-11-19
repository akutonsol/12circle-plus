# Silent error-handling inventory — 12circle-plus Flutter app

Traceable record of every place the app swallows a failure (no message to the user, nothing recorded), with the
user-facing consequence, priority, proposed fix and the PR that carries it.

- **Inventory basis:** `integration/p0-flutter-stack` @ `f4cf7b1` (= `origin/main` 8f2c8a0 + open PRs #172–#180), so
  sites already fixed by those PRs are not counted. Produced read-only by `cplus-flutter-engineer` (2026-11-17);
  the lead verified the P1 sites. 354 `catch` sites + `catchError`/`onError`/`.then`/`valueOrNull ??` reads scanned;
  every suspect read with its caller. Limits: `custom_exercise_service` `lastError` callers spot-checked; unawaited
  futures grep-based.
- **Priority:** P1 = false success or data loss on a beta journey (`docs/CONTROLLED_BETA_SCOPE.md`); P2 = failure
  shown as empty/zero/wrong state on a beta journey; P3 = off-journey, or best-effort that should at least be recorded.
- **Rule for every fix:** a behaviour test that fails on the base commit, independent review, CI — no broad
  catch-replacement without testing the affected behaviour.
- **Women's Health / cycle:** `womens_health_screen.dart:386` (`recentSymptomsProvider.valueOrNull ?? []` — a failed
  read shows as "no recent symptoms") is **noted only**; that area is out of scope.

## Already fixed by open PRs (cycles 1–5)

| PR | Package | What was silent |
|---|---|---|
| #172 | P0-FL-1 | ending coaching / requesting a coach: 0-row and signed-out writes reported as success |
| #173 | P0-FL-2 | coach Requests tab raw error; check-in history failure without retry |
| #174 | P0-FL-3 | coach price writes: 0-row / signed-out saves reported as "Pricing updated" / "Custom price set" |
| #176 | P0-FL-4 | Business Profile: failed load = editable blank form (Save overwrote the profile); 0-row saves; invite insert swallowed |
| #175 | P0-FL-5 | raw exception text on leaderboard, community feed, create exercise |
| #177 | P0-FL-6 | pricing sheet `_load` `catch (_) {}`; Requests label `valueOrNull` |
| #178 | P0-FL-7 | create exercise: media/relations failures followed by "Exercise Saved!" |
| #179 | P0-FL-8 | `liveMembersProvider` `catch → []` ("No members yet") |
| #180 | P0-FL-9 | settings unit, rate-coach upsert, intake progress: no row check / `catch (_) {}` |
| #181 | P0-FL-10 | `groupNotifierProvider` `whenData` ignored errors ("no groups" / "not joined"); `leaveGroup` 0-row = "left" |
| #182 | P0-FL-12 | client-detail prefill failures → Save wiped the client's plan / habits; paid-plan check `catch → false` |

## Remaining beta-journey sites (P1 / P2)

| # | Site (`apps/mobile/lib/…` @ f4cf7b1) | Operation | User-facing consequence | Journey | Pri | Package | PR |
|---|---|---|---|---|---|---|---|
| 1 | `features/dashboard/presentation/client_detail_screen.dart:1861` | read `client_nutrition_plans` (prefill `.then`, no onError) | blank form; Save overwrote the client's plan | J6 | **P1** | P0-FL-12 | #182 |
| 2 | `client_detail_screen.dart:2023` | read `client_habits` (prefill) | nothing pre-selected; Save switched off all active habits | J6 | **P1** | P0-FL-12 | #182 |
| 3 | `features/onboarding/presentation/intake_flow_screen.dart:3635` | storage upload of baseline photos | intake continues as if uploaded; photos silently lost | J1 / J11 | **P1** | P0-FL-19 | #185 |
| 4 | `features/coach/data/coach_program_service.dart:514` + `client_detail_screen.dart:230` | read `subscriptions`/`payments` | "unlocks once this client subscribes"; Assign Program hidden | J6 | P2 | P0-FL-12 | #182 |
| 5 | `intake_flow_screen.dart:158` | read `user_profiles` (resume) | intake restarts blank; later saves overwrite stored answers | J1 | P2 | P0-FL-19 | #185 |
| 6 | `features/coach/domain/coach_provider.dart:168` | read `public_profiles` + counts | "No coaches available right now" | J5 | P2 | P0-FL-19 | #185 |
| 7 | `features/auth/presentation/login_screen.dart:70` | read role | a coach is routed to the client `/home` | J2 / J14 | P2 | P0-FL-15 | #186 |
| 8 | `core/router/app_router.dart:259` | read role (redirect) | same | J2 / J14 | P2 | P0-FL-15 | #186 |
| 9 | `features/auth/domain/auth_provider.dart:103` | read `user_profiles` (`→ null`) | Profile shows "Member" defaults; its error branch unreachable | J11 / J12 | P2 | P0-FL-16 | #189 |
| 10 | `features/messaging/data/messaging_service.dart:55` | read `conversations` (`→ []`) | "No conversations yet" | messaging | P2 | P0-FL-13 | #184 |
| 11 | `messaging_service.dart:177` | message insert ok, preview update fails → false | "Not sent" though saved; resend duplicates | messaging | P2 | P0-FL-13 | #184 |
| 12 | `features/dashboard/presentation/coach_dashboard_screen.dart:48–49` | `notifications` stream `handleError` + `catch → []` | empty sheet, badge 0, stream dead | J5 / J10 | P2 | P0-FL-14 | #190 |
| 13 | `coach_dashboard_screen.dart:1868` | consumer of #12 (`?? []`) | "No notifications" | J5 / J10 | P2 | P0-FL-14 | #190 |
| 14 | `features/coach/presentation/coach_availability_screen.dart:58` | read slots + `coaching_calls` | no slots, no upcoming calls | booking | P2 | P0-FL-14 | #190 |
| 15 | `features/workout/data/workout_service.dart:323` | `getExerciseProgression` | empty chart; error reads "No data yet" | J11 | P2 | P0-FL-18 | #188 |
| 16 | `workout_service.dart:339` | `getLoggedExerciseNames` | strength screen empty state | J11 | P2 | P0-FL-18 | #188 |
| 17 | `workout_service.dart:490` | `getClientPersonalRecords` | coach sees "No personal records yet" | J11 | P2 | P0-FL-18 | #188 |
| 18 | `workout_service.dart:503` | `getClientRecentSessions` | coach sees "No sessions recorded" | J11 | P2 | P0-FL-18 | #188 |
| 19–23 | `clientPlanProvider.valueOrNull ?? ClientPlan.free` in `manage_subscription_screen.dart:152`, `upgrade_screen.dart:56`, `profile/presentation/subscription_screen.dart:70`, `profile_screen.dart:55`, `settings_screen.dart:146` | RPC `client_plan()` | a coached client shown "Free"; upgrade offers a plan they have | J12 / J13 | P2 ×5 | P0-FL-17 | #191 |

## Packages (beta value first; all decision-free unless noted)

| Package | Files | Sites | Fix pattern | Base | Status |
|---|---|---|---|---|---|
| **P0-FL-12** client-detail assignment honesty | `client_detail_screen.dart`, `coach_program_service.dart` | #1, #2, #4 | prefill failure → notice + retry, inputs and Save disabled until loaded; paid-plan check rethrows → honest retry state | on #180 | **#182** — UX/security/QA passed at 23dd969; CI 7/7 |
| P0-FL-13 messaging inbox and send | `messaging_service.dart`, `messaging_screen.dart` | #10, #11 | rethrow → inbox error state; preview-update failure after a saved insert = success + recorded | `origin/main` | **PR open, unmerged** — #184 · head 72fed97 · CI 7/7 (cycle 6) |
| P0-FL-14 coach notifications + availability | `coach_dashboard_screen.dart`, `coach_availability_screen.dart` | #12–#14 | stream errors reach the sheet (retry); availability error state | integration base | **PR open, unmerged** — #190 · head beb2a3f · CI 7/7 (cycle 6) |
| P0-FL-15 sign-in routing | `login_screen.dart`, `app_router.dart` | #7, #8 | failed role read → stay + "Couldn't load your account — Try again", no guessed route | `origin/main` | **PR open, unmerged** — #186 · head c117cfb · CI 7/7 (cycle 6) |
| P0-FL-16 profile read passes errors on | `auth_provider.dart`, `profile_screen.dart` | #9 | report + rethrow; profile failure banner; audit `.when` consumers | on #180 | **PR open, unmerged** — #189 · head 3f357ee · CI 7/7 (cycle 6) |
| P0-FL-17 plan label honesty | 5 subscription/profile/settings screens | #19–#23 | plan unknown → "—" + retry; never "Free"; upgrade offers nothing as current | on FL-16 | **PR open, unmerged** — #191 · head d307187 · CI 7/7 (cycle 6) |
| P0-FL-18 progress views | `workout_service.dart`, strength / coach-client workout / train hub screens | #15–#18 (+ `:439`) | `catch → []` removed; error arms with retry | `origin/main` | **PR open, unmerged** — #188 · head b556bca · CI 7/7 (cycle 6) |
| P0-FL-19 intake | `intake_flow_screen.dart`, `coach_provider.dart` | #3, #5, #6 (+ `:96`) | photo failure told (non-blocking); resume failure → retry; coach list rethrows | on #180 | **PR open, unmerged** — #185 · head e3d5636 · CI 7/7 (cycle 6) |
| P0-FL-20 … P0-FL-36 | services and screens off the beta journeys | ~111 P3 sites | `reportError` at minimum; error states where shown as empty; dead providers deleted | various | backlog |

Totals at f4cf7b1: **P1 3, P2 21, P3 ≈111, fine ≈30, Women's Health 1 (noted only).** FL-12 closes 2 of the 3 P1 and
1 P2; P0-FL-13 … P0-FL-19 cover the remaining 1 P1 and 20 P2.

**Status 2026-11-19 (cycle 6):** every P1 and P2 row above now has an open, unmerged PR with CI 7/7 on its exact head
(#182, #184–#191). Combined branch `integration/p0-flutter-stack-c6` @ 6f8918f (all of them together): 3192 tests,
CI 7/7 (run 44463329197). Automated evidence only — no device or live-QA run; nothing is merged. Remaining: ≈111 P3
(P0-FL-20 … P0-FL-36) and the cycle-6 follow-ups in the ledger (P0-FL-38 unlogged assessment reads first).

**Status 2026-11-19 (cycle 7).** The cycle-6 follow-ups are now in PRs, all CI 7/7 on their exact heads:
- **#194 (P0-FL-38):** unlogged coach health reads, the Requests-tab crash on a missing profile, and the copilot injury parse.
- **#192 (P0-FL-39):** false-success writes in notification preferences, Personal Info, the coach notification sheet and availability cancel.
- **#193 (P0-FL-40):** role gates and Manage subscription showing a failed read as a fact, and the train-hub active session.

Combined branch `integration/p0-flutter-stack-c7` @ df35d5f: 3335 tests, CI 7/7 (run 44497593361). Remaining: the P3 backlog and the cycle-8 list in the ledger.
