# 12 Circle Fitness — Screen / Route Graph

**Read-only audit deliverable.** Baseline `fbee6d5cc51d6c3aee468c95c12e2d55b52e1f89`.
Scope: `apps/mobile` (Flutter + GoRouter). Source of truth: `apps/mobile/lib/core/router/app_router.dart`.

> **Concurrency warning.** Another agent session was committing to this worktree during the
> audit (commits at 23:11, 23:14, 23:24, 23:39 on 2026-09-23) and was writing
> `apps/mobile/tool/orphan_route_sweep.dart` and `test/unit/orphan_route_guard_test.dart` —
> which address the same orphan routes catalogued below. Figures here describe the pinned
> baseline.

---

## 1 · Topology

**Every route in the application is declared in one file.** A repo-wide `grep -rn "GoRoute("
lib` returns 91 hits, all in `app_router.dart`. There is no secondary router, no
`onGenerateRoute`, and no nested `GoRoute` children.

| Measure | Value |
|---|---|
| `GoRoute` declarations | **91** |
| Routes in a **release** binary | **89** (`/mie-debugger`, `/qa-center` are `!kReleaseMode`) |
| Distinct widget classes built | **88** (3 aliases) |
| Inside `ShellRoute` (AppShell + bottom nav) | **73** |
| Outside the shell (no nav chrome) | **18** |
| Wrapped in `PaywallGate` | **13** |
| **Path parameters** | **0** — no route is entity-addressable |

### 1.1 The single most consequential structural fact

**No route takes a path parameter.** Not one of the 91. Every parameterised destination —
a specific client, program, event, class, conversation — is therefore reached by
`Navigator.push(MaterialPageRoute(...))` with constructor arguments, **outside GoRouter**.

Three consequences follow directly, and they explain most of the gaps in this audit:

1. Nine real screens have no route at all (§4).
2. No deep link can target an entity, so push-notification-to-screen is not buildable
   without route work first.
3. No entity screen appears in a web URL, is bookmarkable, or survives a refresh.

---

## 2 · Route table

### 2.1 Outside the shell — 18

| Path | Widget | Notes |
|---|---|---|
| `/splash` | `SplashScreen` | `initialLocation`. Goes to `/signup` or `/login` |
| `/onboarding` | `OnboardingScreen` | **ORPHAN.** Router comment claims splash hands off here — it does not |
| `/login` | `LoginScreen` | |
| `/signup` | `SignupScreen` | |
| `/forgot-password` | `ForgotPasswordScreen` | |
| `/reset-password` | `ResetPasswordScreen` | Forced by `passwordRecoveryNotifier` |
| `/intake` | `IntakeFlowScreen` | 27 steps in one `PageView`. Reachable **unauthenticated** |
| `/admin-dashboard` | `AdminDashboardScreen` | Admin landing. **No role guard** |
| `/admin-exercise-review` | `ExerciseReviewScreen` | **No role guard** |
| `/content-center` | `ExerciseContentCenterScreen` | Widget guard `:118` |
| `/observability` | `ObservabilityScreen` | Widget guard `:43` |
| `/content-review` | `ContentReviewQueueScreen` | Widget guard `:76` |
| `/knowledge-review` | `IntelligenceReviewScreen` | Widget guard `:78` |
| `/vendor-portal` | `VendorPortalScreen` | Vendor landing. **No role guard** |
| `/mie-debugger` | `MieDebuggerScreen` | Debug/profile only |
| `/qa-center` | `QaCenterScreen` | Debug/profile only |
| `/payment-success` | `PaymentResultScreen(success:true)` | Stripe return (web) |
| `/payment-cancel` | `PaymentResultScreen(success:false)` | Stripe return (web) |

Admin and vendor landing routes sit **outside** the `ShellRoute`, so those roles get no
persistent navigation at all.

### 2.2 Inside the shell — 73

Client core: `/home` `/activity` `/directory` `/train` `/workouts` `/workout-detail`
`/active-workout` `/workout-history` `/exercise-library` `/exercise-database`
`/exercise-detail` `/strength-progression` `/progress` `/score` `/goals` `/habits`
`/insights` `/checkins` `/daily-checkin` `/checkin-form` `/checkin-detail`
`/womens-health` `/community` `/pods` `/challenges` `/challenge-detail` `/classes`
`/class-detail` `/events` `/notifications` `/messages` `/chat` `/action-items`
`/appointments` `/book-call` `/booking-handoff` `/compliance`

Nutrition: `/nutrition` `/meals-dashboard` `/nutrition-overview` `/food-search`
`/log-meal` `/ai-nutrition` `/meal-plan` `/grocery-list` `/ai-coach`

Coach: `/coach-dashboard` `/coach-directory` `/coach-checkin-review` `/coach-classes`
`/coach-payments` `/coach-business` `/coach-copilot` `/coach-client-workouts`
`/coach-marketplace` `/coach-packages` `/coach-plan` `/program-builder`
`/program-designer` `/continuous-coaching` `/weekly-review` `/coach`

Account: `/profile` `/personal-info` `/settings` `/notification-preferences`
`/subscription` `/integrations` `/upgrade` `/privacy-policy` `/terms-of-service`
`/help-center` `/create-exercise`

### 2.3 Aliases — 3 widgets serving 2 routes each

| Widget | Routes | Verdict |
|---|---|---|
| `TrainHubScreen` | `/train`, `/coach` | `/coach` is dead — the string appears nowhere in `lib` |
| `BookingScreen` | `/appointments`, `/book-call` | Both live, same `coachGuided` gate. Redundant |
| `PaymentResultScreen` | `/payment-success`, `/payment-cancel` | Legitimate variant (boolean arg) |

---

## 3 · Redirect and guard logic

`redirect()` in `app_router.dart` is the only router-level gate.

```
/splash                          -> pass through (splash self-navigates)
passwordRecoveryNotifier == true -> force /reset-password
!authenticated && !isAuthRoute   -> /login
authenticated && isAuthRoute     -> role lookup on user_profiles:
                                      coach  -> /coach-dashboard
                                      admin  -> /admin-dashboard
                                      vendor -> /vendor-portal
                                      else   -> /intake if onboarding_complete == false
                                                /home otherwise
```

`isAuthRoute` = `/login` `/signup` `/forgot-password` `/onboarding` `/intake`.

**Two defects in this logic, both verified:**

1. **The role branch runs only inside `authenticated && isAuthRoute`.** `/admin-dashboard`
   is not an auth route, so an authenticated *client* navigating there falls through to
   `return null` and the route resolves. Role affects only the post-login landing.
2. **`/intake` and `/onboarding` are in `isAuthRoute`**, so an **unauthenticated** caller
   reaches both screens with no session.

A fifth role, `content_manager`, exists in the migration 115 CHECK constraint and in five
widget guards but **has no branch in this redirect**.

---

## 4 · Navigation edges

| Measure | Value |
|---|---|
| `context.go/push/replace/pushReplacement` call sites | **242** (237 literal, 5 computed) |
| Resolved route edges | **258** |
| `Navigator.push(MaterialPageRoute)` — off-router | **15** |
| **Dangling targets** (nav to an unregistered path) | **0** |

**Zero dangling targets**, verified four ways: all 237 literals registered; all 21 paths
from the 5 computed targets registered; no `goNamed`/`pushNamed`/double-quoted/interpolated
call sites escaped the regex; and every `'/xxx'` literal in `lib` diffed against the
registered set — the only non-matches are unit strings (`/mo`, `/month`, `/session`) and
four `location.startsWith()` prefix tests in `app_shell.dart`.

### 4.1 The nine push-only screens — reachable, unrouted

These have no path, no deep link, no shell chrome, and no router-level auth:

`ChoosePackageScreen` · `ClientDetailScreen` · `CoachAvailabilityScreen` ·
`CoachVideoResponseScreen` · `CreateClassScreen` · `EventAgendaScreen` ·
`EventAttendeesScreen` · `EventTicketScreen` · `ProgramBuilderScreen`

`ClientDetailScreen` is the most significant: it is the coach's per-client surface, hosts
five sub-surfaces including the coach-notes sheet, and is unaddressable.

### 4.2 `/program-builder` builds the wrong class

`app_router.dart:304` builds **`ProgramLibraryScreen`**, which merely shares the file
`coach/presentation/program_builder_screen.dart` (`:19`). The actual `ProgramBuilderScreen`
(`:161`) is reached only by `MaterialPageRoute` at `:91` and `:111`. The route name and the
file name both describe the class that the route does **not** build.

---

## 5 · Persistent navigation

**Client bottom nav (5):** Home `/home` · Workouts `/train` · Nutrition `/meals-dashboard`
· Check-In `/daily-checkin` · Connect `/messages`

**Coach bottom nav (5, `role == 'coach'`):** Clients `/coach-dashboard` · Compliance
`/compliance` · FAB `/coach-directory` · Programs `/program-builder` · Check-ins
`/coach-checkin-review`

**Top nav (4):** `/profile` · `/directory` · `/messages` · `/notifications`

Admin and vendor get **no shell branch** — their landing routes are outside the ShellRoute.

**Union = 13 of 91 routes. 86% of the surface is in-page-CTA-only.**

### 5.1 Clients lose the top nav when they leave Home

`_CoachTopBar` returns `SizedBox.shrink()` unless `role == 'coach'`. Its only client mount
is `home_screen.dart:245`. So `/directory` — the app's largest hub — and `/notifications`
are **Home-only** for clients.

### 5.2 The hidden navigation table

`directory_screen.dart` holds a 15-entry `const _Module(route: …)` list that is the **sole
entry point** for `/insights`, `/action-items` and `/events`. Any orphan analysis that does
not parse this table is wrong by three. Both audit passes initially disagreed here; this
table was the cause.

---

## 6 · Orphan routes — reconciled

**11 routes have zero in-app navigation.** Two independent passes produced 11 and 5; the
difference was judgment, not evidence. Reconciled below. `qa_suites.dart` references are a
**gated-route test manifest, not navigation**, and do not count as entry points.

| Route | Inbound | Verdict |
|---|---|---|
| `/splash` | 0 | **Benign** — `initialLocation` |
| `/reset-password` | 0 | **Benign** — forced by router redirect |
| `/payment-success` | 0 | **Benign** — external Stripe return |
| `/payment-cancel` | 0 | **Benign** — external Stripe return |
| `/onboarding` | 0 | **ORPHAN** — router comment claiming splash hands off here is false |
| `/coach` | 0 | **ORPHAN** — dead alias of `/train` |
| `/pods` | 0 | **ORPHAN** — complete feature, reads `accountability_pods`, no entry point |
| `/nutrition-overview` | qa_suites only | **ORPHAN** — older duplicate nutrition logger |
| `/food-search` | qa_suites only | **ORPHAN** — 23-line redirect stub |
| `/log-meal` | nav-highlight + qa_suites | **ORPHAN** — 23-line redirect stub |
| `/coach-business` | 0 | **ORPHAN PATH, LIVE SCREEN** — reached by `MaterialPageRoute` ×3 |

**7 genuine orphans.** The highest-impact pair is `/food-search` + `/log-meal`: both have
outbound edges back to `/meals-dashboard` and zero inbound, so **a paying `selfGuided` user
has no in-app route to log a meal**.

---

## 7 · Inbound routing — there is none

| Surface | Status |
|---|---|
| Android `intent-filter` with scheme/host | **NONE** |
| iOS `CFBundleURLSchemes` / associated domains | **NONE** |
| Notification → route dispatch | **NONE** — tap only marks read |
| OAuth callback `io.circle12.app://login-callback` | Declared at `auth_service.dart:10`, **registered in neither platform** |

Consequences: on **mobile**, `create-checkout` falls back to
`https://12circle.app/payment-success`, which opens a browser — so mobile users never see
`PaymentResultScreen`. `send-invite-email` builds `/#/signup?invite=<token>` and **nothing
in `lib` reads an `invite` query parameter**. `create-portal-session` returns to
`https://12circle.app/account` — **there is no `/account` route**.

---

## 8 · Route-level gaps — summary

| Gap | Count | Detail |
|---|---|---|
| Orphan routes (genuine) | 7 | §6 |
| Screens with no route | 9 | §4.1 |
| Routes building the wrong class | 1 | `/program-builder` |
| Redundant aliases | 2 | `/coach`, `/book-call` |
| Redirect stubs occupying a route | 5 | `/food-search` `/log-meal` `/checkin-form` `/nutrition` `/booking-handoff` |
| Routes with no path parameter | 91 | entity addressing impossible |
| Deep-link destinations | 0 | §7 |
| Routes unreachable from persistent nav | 78 | §5 |
