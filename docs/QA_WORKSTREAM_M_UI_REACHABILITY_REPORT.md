# QA Workstream M — UI → Backend Reachability Audit

**Scope:** Does every important user-facing feature have a real end-to-end path
(UI → provider/controller → service → API/RPC/table → persistence → response → UI)?

| | |
|---|---|
| **Date** | 2026-08-24 |
| **Branch** | `chore/qa-environments-secure-ai-backend` |
| **App** | `apps/mobile` (Flutter, go_router + Riverpod + Supabase) |
| **Backend probed** | **QA only** — Supabase project `eyqtldjqpgpljlqvpowh` ("12Circle QA") |
| **Production contacted** | **NO.** See [Production-contact statement](#production-contact-statement). |
| **Method** | Static reachability analysis + read-only replay of every UI query shape against QA |
| **Phases 0/1/2** | Not re-opened. Migrations 113–121 untouched. |
| **Files changed** | This report only. No source, test, migration or config file was modified. |

---

## 1. Executive summary

The app is large and mostly wired: **173 distinct query shapes were extracted from the UI
and replayed read-only against the QA backend; 161 succeeded.** All 47 RPCs the client calls
exist on QA. There are no broken static navigation targets (every `context.go/push` literal
resolves to a declared route).

Nine things are genuinely broken, and they are not cosmetic:

| # | Finding | Severity |
|---|---|---|
| M-01 | **Zero Edge Functions are deployed to QA** — all 19 return `NOT_FOUND`. AI, payments, invites, enrichment are all dead on QA. | **P0 (env)** |
| M-02 | **`public.checkins` does not exist.** The Check-In bottom-nav tab can never save. | **P0** |
| M-03 | **Booking screen (`/appointments`, `/book-call`) is dead for every client** — a PostgREST embed with no backing FK. | **P0** |
| M-04 | **Event ticketing writes to non-existent columns** and then *fabricates a ticket* in the catch block. | **P1** |
| M-05 | **Integrations screen marks a service "connected" after launching a `YOUR_CLIENT_ID` OAuth URL.** | **P1** |
| M-06 | **Delete Account is documented in Help Center but does not exist anywhere in the app.** | **P1** |
| M-07 | **Strength Progression charts are permanently empty** — `workout_set_logs.created_at` does not exist (column is `logged_at`). | **P1** |
| M-08 | **`public.coach_tips` does not exist** — the Home "coach tip" card always shows a hardcoded string. | **P2** |
| M-09 | **Admin "approve exercise to global library" always fails** — `custom_exercises.approved_by` does not exist. | **P2** |

Plus a substantial dead-code surface: **8 unreachable routes, 12 orphaned widget/screen files
(~2,400 lines), 40 orphaned providers, 1 orphaned service, and a complete second bottom-nav
implementation that is never rendered.**

Tests: `flutter test` → **623 passed, 0 failed.** `flutter analyze` → **0 errors, 15 warnings**
(all pre-existing `unnecessary_non_null_assertion` in `tool/` + one in `active_workout_screen.dart`).

---

## 2. Method & evidence base

Runtime UI execution was unavailable, so reachability was established three ways:

1. **Static graph analysis** over `apps/mobile/lib` (287 Dart files):
   route table ↔ navigation call sites ↔ screen classes ↔ providers (transitive closure from
   the presentation layer) ↔ services ↔ `.from()` / `.rpc()` / `functions.invoke()` targets.
2. **Schema diff** — every table/view/function the client references vs. every object created
   across `supabase/migrations/*.sql` (123 migrations).
3. **Read-only replay against QA.** Every `(table, select-list)` pair and every
   `(table, write-payload-keys)` set extracted from the client was issued as a `GET` against
   the QA PostgREST endpoint, authenticated as the two seeded QA accounts
   (`test@12circle.app` = client, `coach@12circle.app` = coach). RPC existence was probed with
   `GET /rest/v1/rpc/<fn>?<params>`; Edge Function deployment with `OPTIONS /functions/v1/<fn>`.

**Methodology caveats, stated honestly:**

- A first RPC probe with *no* parameters produced 26 false `PGRST202` "missing function"
  results. Re-probing with each function's real parameter names resolved **all 47** to
  `42501 permission denied` or a real result — i.e. **every RPC exists**. The zero-arg probe
  result is discarded; it is recorded here only so it is not mistaken for a finding.
- `select=*` on `coach_client_relationships` returns `42501` because migration 113 grants
  *column-level* SELECT (excluding `invite_token`). Every production code path uses an explicit
  column list and works. Only `lib/features/qa/domain/qa_suites.dart` uses `select('*')` there —
  see M-13.
- Writes were **not** executed. Write-shape verification was done by probing each payload key as
  a `select` column, which proves column existence but not constraint/RLS acceptance.
- Two `PGRST100` parse failures in the replay were extractor artifacts (Dart string
  interpolation); both were re-issued by hand and **passed**.

---

## 3. Feature inventory

| Surface | Routes | Screens | Provider/controller | Service | Backend objects |
|---|---|---|---|---|---|
| Onboarding | `/splash` `/onboarding` `/login` `/signup` `/forgot-password` `/reset-password` `/intake` | Splash, Onboarding, Login, Signup, ForgotPassword, ResetPassword, IntakeFlow | `authProvider`, `intake_data` | `AuthService` | `auth.*`, `user_profiles`, `generate_client_plan()` |
| Home | `/home` | HomeScreen | `coach_provider`, `workout_provider`, `nutrition_provider`, `score_provider` | several | `user_profiles`, `workout_sessions`, `coach_tips`✗, `daily_scores` |
| Dashboard (client) | *(none — orphaned)* | DashboardScreen ×2 | `dashboard_provider` | `DashboardService` | `classes`, `events` |
| Dashboard (coach) | `/coach-dashboard` `/coach-directory` `/compliance` | CoachDashboard, CoachDirectory, ClientDetail, ComplianceDashboard | `coach_provider`, `coach_ecosystem_provider`, `compliance_provider` | `CoachRelationshipService`, `ComplianceService`, `ScoreService` | `coach_client_relationships`, `coach_client_ai_signals()`, `weekly_checkins` |
| Directory hub | `/directory` | DirectoryScreen | `dashboard_provider` | — | `classes`, `events` |
| Workouts | `/train` `/workouts` `/workout-detail` `/active-workout` `/workout-history` `/exercise-library` `/exercise-database` `/exercise-detail` `/strength-progression` `/coach-client-workouts` `/create-exercise` | 11 screens | `workout_provider`, `workout_session_manager` | `WorkoutService`, `WorkoutSessionStore`, `CustomExerciseService`, `ExerciseDatabaseService` | `workout_sessions`, `workout_set_logs`, `exercises`, `custom_exercises`, 20+ RPCs |
| Nutrition | `/nutrition` `/meals-dashboard` `/nutrition-overview` `/food-search` `/log-meal` | NutritionSplash, MealsDashboard, Nutrition, FoodSearch, LogMeal | `nutrition_provider` | `NutritionService` | `nutrition_logs`, `foods`, `analyze-food-image` |
| AI Nutrition | `/ai-nutrition` `/meal-plan` `/grocery-list` | AiNutrition, MealPlan, GroceryList | `ai_nutrition_provider` | `AiNutritionService` | **NestJS API** `/ai/nutrition/message` |
| Check-ins | `/checkins` `/daily-checkin` `/checkin-form` `/checkin-detail` `/coach-checkin-review` | 5 screens | `checkin_provider` | `CheckinService`✗, `WeeklyCheckinService` | `checkins`✗, `weekly_checkins`, `coaching_calls` |
| Women's health | `/womens-health` | WomensHealthScreen | `cycle_provider` | `CycleService` | `cycle_settings`, `cycle_logs`, `cycle_symptoms` |
| Progress | `/progress` | ProgressScreen | `progress_provider` | `ProgressService` | `weight_logs`, `body_measurements`, `progress_photo_logs` |
| Habits | `/habits` | HabitScreen | `habit_provider` | `HabitService`, `HabitReminderService` | `client_habits`, `habit_logs` |
| Messaging | `/messages` `/chat` | Messaging, Chat | `messaging_provider` | `MessagingService` | `conversations`, `messages`, `conversation_participant_profiles` |
| Notifications | `/notifications` `/notification-preferences` | Notifications, NotificationPreferences | `notification_provider` | `NotificationService` | `notifications`, `user_profiles.notif_*` |
| Community | `/community` `/pods` `/challenges` `/challenge-detail` | Community, Pods, Challenges, ChallengeDetail | `community_provider`, `challenge_provider` | `LiveCommunityService`, `LiveChallengeService` | `community_posts`, `post_reactions`, `post_comments`, `accountability_pods`, `challenges` |
| Marketplace | `/coach-marketplace` `/coach-packages` `/upgrade` | CoachMarketplace, ChoosePackage, CoachPackages, Upgrade | `package_provider`, `payment_provider` | `PackageService`, `PaymentService` | `marketplace_coaches()`, `coach_packages`, `create-checkout` |
| Coach tools | `/coach-copilot` `/program-builder` `/program-designer` `/continuous-coaching` `/weekly-review` `/coach-business` `/coach-classes` `/coach-payments` `/action-items` | 9+ screens | `coach_provider`, `package_provider` | `CoachProgramService`, `ActionItemService`, `CoachNoteService` | `workout_programs`, `action_items`, 12 program RPCs, `generate-communication` |
| Profile / settings | `/profile` `/settings` `/personal-info` `/integrations` `/privacy-policy` `/terms-of-service` | 6 screens | `profile_provider` | `ProfileService` | `user_profiles`, `user_integrations`, storage `avatars` |
| Subscription | `/subscription` `/upgrade` `/coach-plan` `/payment-success` `/payment-cancel` | ManageSubscription, Upgrade, CoachPlan, PaymentResult | `payment_provider`, `entitlements` | `PaymentService` | `subscriptions`, `payments`, `client_plan()`, 5 Stripe fns |
| AI features | `/ai-coach` | AICoachScreen, AiBriefingSheet | `ai_insights` | `AICoachService` | `ai-coach`, `ai-coaching-engine`, `ai_profiles`, `ai_insights`, `ai_memories` |
| Help / support | `/help-center` | HelpCenterScreen | — | — | *(static content, no backend)* |
| Account lifecycle | *(sign-out only)* | SettingsScreen, ProfileScreen | `authProvider` | `AuthService` | `auth.signOut()` |
| Admin / vendor / QA | `/admin-dashboard` `/observability` `/content-center` `/content-review` `/mie-debugger` `/knowledge-review` `/admin-exercise-review` `/vendor-portal` `/qa-center` | 9 screens | `admin_provider`, `vendor_provider`, `qa_suites` | `AdminService`, `VendorService`, `SessionService` | `admin_platform_stats()`, `event_registrations`, `platform_settings` |

✗ = backend object does not exist. Totals: **91 routes, 98 screen files, 37 services, 224 providers,
78 tables referenced, 47 RPCs, 19 Edge Functions.**

---

## 4. UI ↔ backend reachability matrix

Status legend: **PASS** end-to-end verified · **FAIL** demonstrated break · **BLOCKED** infrastructure
missing on QA · **PARTIAL** works but with a real gap · **QUESTION** needs a product decision.

### 4.1 Confirmed FAIL / BLOCKED

| Feature | UI entry | Route | Provider | Service | Backend object | Persists | Expected | Actual | Status | Sev | Parallel |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Daily/weekly check-in | Bottom-nav **Check-In** tab | `/daily-checkin` | `checkin_provider` | `CheckinService` | `public.checkins` | none | row inserted | `PGRST205` table missing → `saveWeeklyCheckin()` returns false → "Failed to save." | **FAIL** | P0 | yes |
| Book a call with coach | Directory → **Bookings**; AppScaffold nav | `/appointments`, `/book-call` | — (screen-local) | — | `coach_client_relationships` embed `coach:coach_id(...)` | n/a (read) | coach + open slots | `PGRST200` no FK → `catch` → state `noSlots` for *every* client | **FAIL** | P0 | yes |
| All AI features | AI Coach / AI briefs | `/ai-coach` | `ai_insights` | `AICoachService` | `ai-coach`, `ai-coaching-engine` | n/a | AI response | `404 NOT_FOUND` (not deployed to QA) | **BLOCKED** | P0 | no |
| All payments/subscription | Upgrade, Marketplace, Coach Plan | `/upgrade` `/subscription` `/coach-plan` | `payment_provider` | `PaymentService` | `create-checkout`, `cancel-subscription`, `create-portal-session`, `update-subscription`, `stripe-connect` | none | Stripe session | `404 NOT_FOUND`; `STRIPE_PK` also empty in `qa.json` | **BLOCKED** | P0 | no |
| AI Nutrition coach | Meals → AI | `/ai-nutrition` | `ai_nutrition_provider` | `AiNutritionService` | NestJS `/ai/nutrition/message` | none | chat reply | `API_BASE_URL` is `""` in **qa.json *and* prod defaults** → throws "AI coach is unavailable" | **BLOCKED** | P0 | no |
| Food photo scan | Meals → scan | `/meals-dashboard` | `nutrition_provider` | `NutritionService` | `analyze-food-image` | none | macros | `404 NOT_FOUND` | **BLOCKED** | P1 | no |
| Event ticket / register | Events → event card | *(Navigator.push)* | — | `PaymentService` | `event_registrations.ticket_code` | **no** | ticket row | `42703 column does not exist`; catch **fabricates** `TKT-DEMO-…` and sets `_registered = true` | **FAIL** | P1 | yes |
| Vendor check-in list | Vendor portal | `/vendor-portal` | `vendor_provider` | `VendorService` | `event_registrations.ticket_code`, `.attended` | n/a | attendee list | `42703` → `catch` → empty list | **FAIL** | P1 | yes |
| Integrations connect | Profile → Integrations | `/integrations` | — | — | `user_integrations` | **yes, falsely** | OAuth token | Launches `…client_id=YOUR_CLIENT_ID…`, then unconditionally writes `connected: true` | **FAIL** | P1 | yes |
| Delete account | *(none)* | *(none)* | — | — | — | — | account deleted | Help Center documents "Profile → Settings → Account → Delete Account"; no such control or code exists | **FAIL** | P1 | yes |
| Strength progression chart | Train → Strength Progression | `/strength-progression` | `exerciseProgressionProvider` | `WorkoutService.getExerciseProgression` | `workout_set_logs.created_at` | n/a | per-day volume | `42703` (column is `logged_at`) → `catch` → `[]` → empty chart, no error | **FAIL** | P1 | yes |
| Home "coach tip" card | Home | `/home` | `coachTipProvider` | — | `public.coach_tips` | none | coach's tip | `PGRST205` → `null` → hardcoded "Stay consistent…" always shown | **FAIL** | P2 | yes |
| Approve exercise to global library | Admin → Global Library Review | `/admin-exercise-review` | — | `CustomExerciseService` | `custom_exercises.approved_by` | **no** | approved | `42703` → returns false → "Action failed. Please try again." | **FAIL** | P2 | yes |
| Coach client invite email | Coach dashboard → Invite a Client | `/coach-dashboard` | — | `CoachRelationshipService.sendInvite` | `coach_invites` + `send-invite-email` | row only | invite row **and** email | Row persists; `functions.invoke` failure swallowed; UI says **"Invite sent!"** | **PARTIAL** | P1 | yes |
| Downgrade to Free | Upgrade → Free | `/upgrade` | `payment_provider` | `PaymentService.cancelSubscription` | `cancel-subscription` | none | subs cancelled | Return value **ignored**; UI unconditionally shows "Switched to the Free plan." | **FAIL** | P1 | yes |
| In-app QA Center relationship checks | QA Center | `/qa-center` | `qa_suites` | — | `coach_client_relationships` via `select('*')` | n/a | rows | `42501 permission denied` (migration 113 column-level grants) | **FAIL** | P2 | yes |
| Habit complete / value | Habits | `/habits` | `habitsProvider` | `HabitService` | `habit_logs` | maybe | tick persists | Optimistic state set **before** write; `catch (_) {}` with no rollback → tick shows even when the write fails | **PARTIAL** | P2 | yes |
| Live workout-set ticker | Active workout | `/active-workout` | `tableTickerProvider('workout_set_logs')` | — | realtime publication | n/a | live tick | `workout_set_logs` is **not** in `supabase_realtime` → ticker never fires | **PARTIAL** | P3 | yes |
| Join a booked class (JOIN button) | Check-ins calendar | `/checkins` | — | — | — | — | joins the call | `onTap: () {}` — no-op | **FAIL** | P2 | yes |
| Class QR code button | Class detail | `/class-detail` | — | — | — | — | shows QR | `onPressed: () {}` — no-op | **FAIL** | P3 | yes |
| Post overflow menu | Community feed | `/community` | — | — | — | — | report/delete | `onPressed: () {}` — no-op | **FAIL** | P3 | yes |
| Check-in detail | Check-ins → a check-in | `/checkin-detail` | — | — | — | — | check-in detail | Screen body is literally `Text("Check-in details coming soon")` | **FAIL** | P2 | yes |
| Coach pricing editor | *(none)* | *(none)* | — | `CoachRelationshipService` | `user_profiles.pricing_monthly` | yes | edit rate | `showCoachPricingSheet()` has **zero callers** — the screen exists and works but nothing opens it | **FAIL** | P2 | yes |
| Password-reset / OAuth return on native | Email link | `/reset-password` | router | — | Supabase auth | n/a | app opens | No `CFBundleURLSchemes` in `Info.plist`, no `BROWSABLE` intent-filter in `AndroidManifest.xml` → deep link cannot reach a native build (web works via `Uri.base`) | **FAIL** | P1 | yes |
| Stripe checkout return on native | Upgrade → checkout | `/payment-success` | — | `PaymentService._returnUrls` | — | n/a | back in app | `_returnUrls()` returns `(null, null)` off-web and no URL scheme is registered | **FAIL** | P1 | yes |

### 4.2 PASS (verified end-to-end against QA)

All of the following had their exact query shapes replayed against QA and returned data or a
correct, authenticated result:

`user_profiles` (78 columns; every onboarding field exists) · `workout_sessions` · `workout_set_logs`
(except `created_at`) · `workout_programs` · `workout_program_assignments` · `program_workouts` ·
`exercises` (621 rows) · `custom_exercises` (621) · `nutrition_logs` (21) · `foods` (21) ·
`weekly_checkins` (3) · `coaching_calls` (3) · `client_habits` (10) · `habit_logs` (61) ·
`weight_logs` (30) · `body_measurements` (7) · `progress_photo_logs` (7) · `cycle_settings` /
`cycle_logs` / `cycle_symptoms` · `conversations` (1) · `conversation_participant_profiles` ·
`messages` (25) · `notifications` (22/24) · `community_posts` (10) · `post_comments` (5) ·
`post_reactions` (30) · `community_groups` (5) · `accountability_pods` (1) / `_members` (3) ·
`challenges` (3) / `challenge_participants` (7) · `classes` (3) / `class_bookings` (1) ·
`events` (3) · `badges` (11) · `daily_scores` (30) · `coach_availability` (10) ·
`coach_reviews` (5) · `coach_invites` (4, coach only) · `coach_client_workout_stats` ·
`public_profiles` (14) · `platform_settings` · `client_nutrition_plans` · `action_items` ·
`goals` · `ai_*` tables · `subscriptions` · `payments` · `user_integrations`.

**All 47 RPCs exist on QA** — `client_plan`, `active_membership`, `coach_plan_tier`,
`marketplace_coaches`, `coach_active_client_counts`, `admin_platform_stats`, `admin_recent_users`,
`award_points`, `penalize_points`, `leaderboard_global`, `leaderboard_coach`, `plan_program`,
`materialize_program_week`, `snapshot_program_version`, `create_weekly_review`, `evaluate_week`,
`validate_week`, `regenerate_program`, `predict_client`, `record_prediction`, `send_communication`,
`update_communication`, `generate_workout`, `build_workout`, `rank_exercises`, `movement_graph`,
`movement_graph_stats`, `rebuild_movement_graph`, `intelligence_*`, `certification_summary`,
`exercise_certification`, `exercise_content_stats`, `review_*`, `sync_exercise_relations`,
`update_exercise_media`, `resolve_exercise_media`, `finalize_intelligence`, `attribute_review_state`,
`decision_analytics`, `seed_warmup_library`, `deactivate_self_generated_plan`, `generate_client_plan`.

Live plan resolution confirmed: `client_plan()` → `"coach_guided"` for the QA client,
`"free"` for the QA coach. `PaywallGate` fails **open** on error, so a backend hiccup will not
lock out a paying user — correct behaviour, verified by reading
`lib/features/payments/presentation/paywall_gate.dart:44`.

---

## 5. Findings (detail)

### M-01 — No Edge Functions are deployed to the QA project — **P0, BLOCKED**

**Evidence.** `OPTIONS https://eyqtldjqpgpljlqvpowh.supabase.co/functions/v1/<name>` for all 19
functions in `supabase/functions/` returns
`{"code":"NOT_FOUND","message":"Requested function was not found"}` — byte-identical to the
response for a deliberately bogus name (`zzz-does-not-exist`), with and without `apikey`.

**Blast radius on QA:** AI Coach, AI daily briefs/weekly reviews, AI workout generation, food-photo
analysis, every Stripe flow (checkout, cancel, portal, tier change, Connect onboarding), coach
client invite emails, the whole exercise-enrichment content pipeline (`/content-center`,
`/content-review`, `/knowledge-review`, `/mie-debugger`), coach communication generation, and
`explain-decision`.

**Remediation.** `supabase functions deploy --project-ref eyqtldjqpgpljlqvpowh` for all 19, then set
the function secrets (`ANTHROPIC_API_KEY`, `STRIPE_SECRET_KEY`, `RESEND_API_KEY`/equivalent,
`SUPABASE_SERVICE_ROLE_KEY`). Until then every AI/billing finding below is untestable, not fixed.

**Decision required:** does QA get its own Stripe test account and Anthropic key, or do those
surfaces stay explicitly out of QA scope? **Parallelizable: no** (gates several other tests).

---

### M-02 — `public.checkins` does not exist; the Check-In tab can never save — **P0, FAIL**

**Evidence.**
```
GET /rest/v1/checkins?select=*&limit=0
{"code":"PGRST205","message":"Could not find the table 'public.checkins' in the schema cache"}
```
The table is created by **no** migration and appears nowhere in `supabase/`. Five call sites in
[checkin_service.dart](apps/mobile/lib/features/checkins/data/checkin_service.dart) target it
(`:18` insert, `:42` select, `:62` select, `:86` insert, `:112` select, `:141` select), plus
[coach_dashboard_screen.dart:108](apps/mobile/lib/features/dashboard/presentation/coach_dashboard_screen.dart#L108).

**Path.** Bottom-nav **Check-In** → `/daily-checkin` → `DailyCheckinScreen` →
`CheckinService.saveWeeklyCheckin()` → `from('checkins').insert(...)` → **PGRST205** → `catch`
returns `false` → the screen correctly shows *"Failed to save. Please try again."*
The error message is honest; the feature is 100% non-functional.

**Duplicate implementation.** `WeeklyCheckinService` writes to `weekly_checkins`, which **does**
exist and holds 3 seeded rows, and the coach review screen reads from it. So the product has two
check-in implementations — one live, one pointed at a table that was never created.

**Remediation.** Decide (below), then either add a `checkins` migration or repoint
`CheckinService` at `weekly_checkins` and delete the duplicate.

**Decision required:** is the daily check-in a distinct entity from the weekly check-in, or was
`checkins` an abandoned earlier design? The two services collect *identical* fields
(mood/energy/stress/sleep/notes), which suggests the latter. **Parallelizable: yes.**

---

### M-03 — Booking screen is dead for every client — **P0, FAIL**

**Evidence.** `coach_client_relationships.coach_id` has a FK to **`auth.users`**, not
`public.user_profiles` (`000_baseline_preexisting_tables.sql:237`). PostgREST therefore cannot
resolve the embed used at
[booking_screen.dart:55-58](apps/mobile/lib/features/booking/presentation/booking_screen.dart#L55-L58):

```
GET /rest/v1/coach_client_relationships
    ?select=coach_id,status,pending_at,activated_at,coach:coach_id(first_name,last_name,…)
    &client_id=eq.5470a95f-…
{"code":"PGRST200","details":"Searched for a foreign key relationship between
 'coach_client_relationships' and 'coach_id' in the schema 'public', but no matches were found."}
```
The identical query **without** the embed returns the client's real active relationship:
`[{"coach_id":"f626acd9-…","status":"active","activated_at":"2026-08-24T07:38:22Z"}]`.

**Consequence.** `_load()` throws → `catch (_)` at
[booking_screen.dart:105](apps/mobile/lib/features/booking/presentation/booking_screen.dart#L105)
sets `_state = _BookingState.noSlots`. A Coach-Guided client with an active coach sees "no slots",
never the pending or active coach state. This is the paywalled `ClientPlan.coachGuided` feature
reached from the Directory hub **and** from the `AppScaffold` bottom nav.

**Remediation.** Two options: (a) migration adding
`coach_client_relationships_coach_id_profiles_fkey` to `public.user_profiles` (mirroring what
`weekly_checkins` already does), or (b) drop the embed and fetch coach profiles in a second query
against `public_profiles` — the pattern already used in `coach_relationship_service.dart:69-72`.
**(b) is the smaller, safer change and needs no migration.**

**Decision required:** (a) or (b). **Parallelizable: yes.**

---

### M-04 — Event ticketing writes non-existent columns and fabricates a ticket — **P1, FAIL**

**Evidence.** `event_registrations` has `qr_code`, not `ticket_code`, and has no `attended`:
```
GET /rest/v1/event_registrations?select=ticket_code  → 42703 column does not exist
GET /rest/v1/event_registrations?select=attended     → 42703 column does not exist
GET /rest/v1/event_registrations?select=qr_code      → [] (exists)
```
`ticket_code` is added only in `supabase/APPLY_MISSING.sql:147`, which is **not** a migration and
was never applied.

**The serious part** — [event_ticket_screen.dart:66-72](apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L66-L72):
```dart
} catch (_) {
  // Demo fallback
  final code = 'TKT-DEMO-${DateTime.now().millisecondsSinceEpoch...}';
  setState(() { _registered = true; _ticketCode = code; });
}
```
The insert fails, and the app shows the user a ticket code and "You're registered" anyway. Nothing
is persisted. `VendorService.getAttendees` (`vendor_service.dart:41`) then fails on the same
columns, so the vendor's check-in list is empty.

**Remediation.** Fold `APPLY_MISSING.sql`'s `ticket_code` (and `attended`) into a numbered
migration ≥123, **and delete the demo fallback** — a failed registration must surface as a failure.
**Decision required:** keep `ticket_code` or standardise on the existing `qr_code`.
**Parallelizable: yes.**

---

### M-05 — Integrations screen fakes a successful OAuth connection — **P1, FAIL**

**Evidence.** [integrations_screen.dart:257-264](apps/mobile/lib/features/profile/presentation/integrations_screen.dart#L257-L264)
— every OAuth URL literally contains `client_id=YOUR_CLIENT_ID`. At `:332-340`:
```dart
if (await canLaunchUrl(uri)) {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
  // In production, handle the deep link callback here to store tokens
  if (mounted) await _toggleConnect(id, true);
}
```
The app launches an invalid authorization URL and then **writes `connected: true` to
`user_integrations`** regardless of outcome. There is also no registered
`com.12circle.app://auth/...` scheme (see M-11), so the callback could never arrive even with real
client IDs. Spotify, Strava, MyFitnessPal, WHOOP, Garmin and Polar all show as "Connected" while
importing nothing.

**Remediation.** Gate the whole screen behind a "coming soon" state until real client IDs and a
callback handler exist, or remove `_toggleConnect(id, true)` so nothing is persisted without a
token. **Decision required:** ship the screen as a roadmap teaser, or hide it.
**Parallelizable: yes.**

---

### M-06 — Delete Account is documented but does not exist — **P1, FAIL**

**Evidence.** [help_center_screen.dart:45](apps/mobile/lib/features/settings/presentation/help_center_screen.dart#L45):
> *"Go to Profile → Settings → Account → Delete Account. All your data is permanently removed within 30 days."*

A repo-wide search for `deleteAccount`, `Delete Account`, `deleteUser` finds **only that FAQ string**.
`SettingsScreen`'s "Account" section (`:131-175`) contains Profile, Subscription and
notification rows — no delete. The only account-lifecycle operation implemented anywhere is
`auth.signOut()`.

This is both a broken promise to the user and an App Store / Play Store account-deletion
requirement.

**Remediation.** Either implement deletion (an Edge Function with the service-role key calling
`auth.admin.deleteUser` + cascade — note `user_profiles.id` already cascades from `auth.users`),
or correct the Help Center copy. **Decision required:** in-app deletion vs. an email-request flow.
**Parallelizable: yes.**

---

### M-07 — Strength Progression charts are permanently empty — **P1, FAIL**

**Evidence.** `workout_set_logs` was created with `logged_at timestamptz DEFAULT now()`
(`001_full_ecosystem.sql:168`) and has no `created_at`:
```
GET /rest/v1/workout_set_logs?select=weight_kg,reps,created_at
{"code":"42703","message":"column workout_set_logs.created_at does not exist"}
```
[workout_service.dart:237,243,246](apps/mobile/lib/features/workout/data/workout_service.dart#L237)
selects, orders by and reads `created_at`. `getExerciseProgression()` therefore always throws →
`catch (_) { return []; }` → `exerciseProgressionProvider` yields `[]` →
`/strength-progression` renders an empty chart with no error.

**Scope note.** This is a *newly demonstrated* backend break in a read path, not a re-opening of the
Phase 2 workout contract. The exercise **list** (`getLoggedExerciseNames`, selects `exercise_name`)
works; only the per-exercise chart is dead. Every other `workout_set_logs` query in the codebase
uses valid columns.

**Remediation.** Three-token change: `created_at` → `logged_at` at lines 237, 243, 246.
**Decision required:** none. **Parallelizable: yes.**

---

### M-08 — `public.coach_tips` does not exist — **P2, FAIL**

**Evidence.** `PGRST205` on QA; the string `coach_tips` appears **nowhere** in `supabase/`.
[coach_provider.dart:64](apps/mobile/lib/features/coach/domain/coach_provider.dart#L64) reads it;
`catch (_) → null`; [home_screen.dart:1099-1100](apps/mobile/lib/features/home/presentation/home_screen.dart#L1099)
then falls back to the hardcoded *"Stay consistent. Small daily actions create lasting results."*
Every client sees the same sentence attributed to their coach, forever. There is also **no write
path anywhere** — no coach UI can author a tip.

**Remediation.** Either build the feature (table + coach authoring UI) or delete
`coachTipProvider` and label the card as generic motivation. **Decision required:** is "coach tip"
a real product feature? **Parallelizable: yes.**

---

### M-09 — Admin exercise approval always fails — **P2, FAIL**

**Evidence.** `GET /rest/v1/custom_exercises?select=approved_by` → `42703`, with PostgREST hinting
*"Perhaps you meant to reference the column custom_exercises.approved_at."*
[custom_exercise_service.dart:772](apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L772)
writes `'approved_by': _uid`. `approveGlobalExercise` returns `false`; the UI correctly reports
*"Action failed. Please try again."* No coach submission can ever reach the global library.
**Remediation:** add `approved_by uuid` in a new migration, or drop the field from the payload.
**Decision required:** is approver attribution needed? **Parallelizable: yes.**

---

### M-10 — Success states that do not reflect persistence

| Site | Behaviour |
|---|---|
| [upgrade_screen.dart:135-143](apps/mobile/lib/features/payments/presentation/upgrade_screen.dart#L135-L143) | Loops `cancelSubscription()` (returns `bool`), **ignores every result**, then unconditionally shows *"Switched to the Free plan."* On QA nothing is cancelled. |
| [coach_dashboard_screen.dart:1002-1006](apps/mobile/lib/features/dashboard/presentation/coach_dashboard_screen.dart#L1002-L1006) | *"Invite sent!"* after `sendInvite()`, whose `functions.invoke('send-invite-email')` failure is swallowed at `coach_relationship_service.dart:89`. The row persists, the email does not. |
| [event_ticket_screen.dart:66](apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L66) | Fabricated ticket on failure (M-04). |
| [integrations_screen.dart:337](apps/mobile/lib/features/profile/presentation/integrations_screen.dart#L337) | Persists `connected: true` with no token (M-05). |
| [habit_provider.dart:118-144](apps/mobile/lib/features/habits/domain/habit_provider.dart#L118-L144) | Optimistic state set **before** the write, `catch (_) {}` with **no rollback**. |

**Remediation.** Check the boolean before showing success; roll back optimistic state on failure.
**Severity P1** for upgrade/invite, **P2** for habits. **Parallelizable: yes.**

---

### M-11 — No custom URL scheme registered → native deep links cannot return — **P1, FAIL**

`ios/Runner/Info.plist` contains no `CFBundleURLSchemes`; `android/app/src/main/AndroidManifest.xml`
has a single `<intent-filter>` (the standard `MAIN`/`LAUNCHER`) and **no** `BROWSABLE` filter or
`android:scheme`. `main.dart` derives deep-link state from `Uri.base`, which only carries
information on web.

Broken on native builds: password-reset email links (`/reset-password`), OAuth sign-in return,
the OAuth callbacks the Integrations screen advertises, and the Stripe Checkout return —
`PaymentService._returnUrls()` at `payment_service.dart:17-21` explicitly returns `(null, null)`
when `!kIsWeb`.

**Remediation.** Register `com.12circle.app` (or a universal/app link) in both platform manifests
and add `app_links`/`uni_links` handling in `main()`. **Decision required:** custom scheme vs.
universal links. **Parallelizable: yes.**

---

### M-12 — Dead buttons (no-op handlers)

| Site | Control |
|---|---|
| [checkin_screen.dart:406](apps/mobile/lib/features/checkins/presentation/checkin_screen.dart#L406) | **JOIN** on an upcoming coaching call — `onTap: () {}` |
| [checkin_screen.dart:312](apps/mobile/lib/features/checkins/presentation/checkin_screen.dart#L312) | Premium FAB — `onTap: () {}` |
| [class_detail_screen.dart:273](apps/mobile/lib/features/classes/presentation/class_detail_screen.dart#L273) | **QR Code** on a booked class — `onPressed: () {}` |
| [post_card.dart:113](apps/mobile/lib/features/community/presentation/widgets/post_card.dart#L113) | Post overflow `…` menu — `onPressed: () {}` |
| `dashboard_screen.dart:117`, `dash_org.dart:100`, `upcoming_class_card.dart:75`, `upcoming_event_card.dart:65` | No-ops inside already-dead files (M-14) |

The JOIN button is the notable one: `coaching_calls` rows exist on QA (3 seeded) and render
correctly, but there is no way to actually join a call. **Parallelizable: yes.**

---

### M-13 — In-app QA Center is broken by migration 113 — **P2, FAIL**

`qa_suites.dart:420` (`_fetch`) and `:685` (`_rowExists`) issue `select('*')` against
`coach_client_relationships`. Migration 113 revoked the table-level grant and re-granted
**column-level** SELECT excluding `invite_token`, so `*` now returns
`42501 permission denied for table coach_client_relationships` (hint: *"Grant the required
privileges…"*). Every production code path already uses explicit column lists and is unaffected;
only the QA tooling regressed.

**Remediation.** Replace `select('*')` with the explicit column list in those two helpers.
Do **not** widen the grant — the column-level grant is the intended Phase 1 posture.
**Parallelizable: yes.**

---

## 6. Orphaned code

### 6.1 Unreachable routes (declared in `app_router.dart`, referenced nowhere else)

| Route | Screen | Note |
|---|---|---|
| `/coach` | `TrainHubScreen` | Duplicate alias of `/train` |
| `/coach-business` | `CoachBusinessScreen` | Screen **is** reachable — via `Navigator.push` from 3 sites; the route is dead |
| `/coach-client-workouts` | `CoachClientWorkoutScreen` | No entry point at all |
| `/pods` | `PodsScreen` | Accountability Pods — real tables, seeded data (1 pod, 3 members), **no way in** |
| `/food-search` | `FoodSearchScreen` | No entry point |
| `/log-meal` | `LogMealScreen` | No entry point |
| `/nutrition-overview` | `NutritionScreen` | No entry point (only the orphaned `home_org.dart` embeds it) |
| `/onboarding` | `OnboardingScreen` | `SplashScreen` goes straight to `/signup` or `/login`; the router comment *"the splash hands off to /onboarding itself"* is stale |

Legitimately reached without a literal `context.go`: `/splash` (`initialLocation`),
`/reset-password` (router redirect), `/payment-success` / `/payment-cancel` (Stripe return URL,
web only), and 16 routes reached via `context.go(module.route)` from the Directory hub.

### 6.2 Orphaned files (never imported or instantiated)

| File | Lines | Note |
|---|---|---|
| `dashboard/presentation/dashboard_screen.dart` | 589 | Client dashboard, superseded by `home_screen.dart` |
| `dashboard/presentation/dash_org.dart` | 142 | **Third** copy of `DashboardScreen` |
| `home/presentation/home_org.dart` | 105 | Second `HomeScreen`; sole importer of the two above |
| `profile/presentation/subscription_screen.dart` | 254 | Superseded by `manage_subscription_screen.dart` |
| `messaging/presentation/widgets/message_bubble.dart` | 130 | |
| `progress/presentation/widgets/weight_chart.dart` | 130 | |
| `messaging/presentation/widgets/conversation_tile.dart` | 121 | |
| `progress/presentation/widgets/log_weight_sheet.dart` | 114 | Duplicate of private `_LogWeightSheet` in `progress_screen.dart` |
| `progress/presentation/widgets/measurement_card.dart` | 100 | |
| `workout/presentation/widgets/workout_card.dart` | 99 | |
| `checkins/presentation/widgets/checkin_card.dart` | 164 | |
| `exercise_database/presentation/widgets/exercise_{category_card,detail_card,filter_bar}.dart` | 217 | |
| `nutrition/presentation/widgets/{food_item_card,macro_ring_chart,meal_card}.dart` | 93 | |
| `ai_nutrition/presentation/widgets/meal_plan_card.dart` | 68 | |
| `workout/presentation/widgets/exercise_card.dart` | 67 | |
| `payments/presentation/embedded_checkout_screen.dart` | 33 | |
| **Total** | **~2,436** | |

### 6.3 Orphaned providers (40 of 224, no path from the presentation layer)

Computed as a transitive closure: seed = every provider named in `presentation/`, `core/router/`,
`core/widgets/`, `core/notifications/` or `main.dart`; then expand through provider bodies.

`checkinServiceProvider` `checkinStreakProvider` `recentCheckinsProvider` `hasCheckedInTodayProvider`
`weeklyCheckinsProvider` `currentWeekCheckinProvider` · `challengeServiceProvider`
`selectedChallengeTabProvider` · `classFilterProvider` `classNotifierProvider` `selectedClassTabProvider`
`myBookingsProvider` · `myRelationshipProvider` `myAssignedProgramProvider` `myNutritionPlanProvider`
`myHabitsProvider` `todayHabitLogsProvider` `habitsWithStatusProvider` `scoreServiceProvider`
(all of `coach_ecosystem_provider.dart` except two) · `pendingCoachProvider` · `livePostsProvider`
`postListProvider` `selectedPostProvider` `selectedCommunityTabProvider` · `liveHabitsProvider` ·
`weightLogsProvider` `measurementsProvider` `measurementNotifierProvider` `selectedProgressTabProvider` ·
`exercisesProvider` `exerciseSearchProvider` `filteredExercisesProvider` `totalVolumeProvider`
`programAdherenceProvider` · `selectedCategoryProvider` `exerciseDbSearchProvider`
`filteredExerciseDbProvider` · `coachSubscriptionProvider` `hasMembershipProvider` ·
`todaySymptomsProvider`.

### 6.4 Orphaned services and mock-data paths

- **`PlatformSettingsService`** (`admin/data/platform_settings_service.dart`) — zero references anywhere.
- **`ChallengeService.getSampleChallenges()`** and **`CommunityService.getSamplePosts()`** — hardcoded
  demo content. Neither is ever called: `PostNotifier` takes a `CommunityService` and discards it
  (`community_provider.dart:27`, parameter named `_`). Screens use the `Live*` services. **No mock
  data reaches the user** — this is dead code, not a data-integrity problem.
- **`ClassService.getSampleClasses()`** — *is* called, but only by `classNotifierProvider`, which is
  itself orphaned (6.3). `classes_screen.dart` uses `liveClassesFromDbProvider`.
- **`AppBottomNav`** + its `_AnimatedFab` / `_FabArcPainter` stack in `shared/widgets/app_scaffold.dart`
  (~110 lines) — a complete second bottom-nav implementation that `AppScaffold.build()` never renders.
  Consequently `AppScaffold`'s **`navIndex` parameter is dead**: it is declared and required, nine
  screens pass it, and `build()` never reads it. Its route set (`/home`, `/appointments`, `/progress`,
  `/messages`) also disagrees with the live `AppShell` nav (`/home`, `/train`, `/activity`,
  `/daily-checkin`).
- **`showCoachPricingSheet()`** (`coach/presentation/coach_pricing_sheet.dart`) — fully implemented,
  writes `user_profiles.pricing_monthly`, **zero callers**.
- **`ClientPlanCaps.canTrackProgressBasic`** — declared, never read.
- **`upcomingClassesProvider` is declared twice** — `dashboard_provider.dart:47`
  (`FutureProvider<List<Map>>`) and `class_provider.dart:107` (`Provider<List<FitnessClass>>`).
  `activity_screen.dart` and `directory_screen.dart` import only `dashboard_provider`, so the
  `class_provider` version is unreachable. No compile error, but the name collision is a trap.

### 6.5 Backend capabilities with zero callers

| Object | Note |
|---|---|
| `supabase/functions/notify-coach-email` | Zero references in Dart, SQL, cron or the API |
| `supabase/functions/send-checkin-reminder` | Zero references — check-in reminders are never sent |
| `supabase/functions/stripe-webhook` | Called by Stripe, not the app — **expected**, listed for completeness |
| `workout_set_logs` realtime | `tableTickerProvider('workout_set_logs')` is watched at `workout_provider.dart:50`, but the table is **not** in the `supabase_realtime` publication (18 tables are; this is not one) → the ticker never fires |

---

## 7. Blockers

| ID | Blocker | Blocks | Owner |
|---|---|---|---|
| B-1 | No Edge Functions deployed to QA (M-01) | AI, payments, invites, enrichment, food scan — ~6 surfaces | DevOps |
| B-2 | `API_BASE_URL` empty in `dart_defines/qa.json` **and** in `kEnvironmentDefaults[prod]` (`app_env.dart:144`) | AI Nutrition in *every* environment | DevOps / Product |
| B-3 | `STRIPE_PK` empty in `qa.json` | Embedded Checkout; forces hosted redirect, itself blocked by B-1 | DevOps |
| B-4 | No runtime UI harness (no integration-test driver, no device) | Everything in §5 is static + query-replay evidence; none of it was observed on a running screen | QA |
| B-5 | No write access to QA from this session (blocked by policy) | Insert/update payloads were verified by column existence only, not by executing writes | QA |

---

## 8. Product decisions required

1. **`checkins` vs `weekly_checkins` (M-02).** One entity or two? Both services collect identical
   fields. *Recommendation: delete `CheckinService`, repoint `/daily-checkin` at `weekly_checkins`.*
2. **Booking coach embed (M-03).** Add the FK to `user_profiles`, or drop the embed and do a second
   query? *Recommendation: drop the embed — no migration, matches the existing pattern in
   `coach_relationship_service.dart`.*
3. **Event tickets (M-04).** Standardise on the existing `qr_code`, or add `ticket_code`?
4. **Integrations (M-05).** Ship as a "coming soon" teaser, or hide the screen until real OAuth exists?
5. **Account deletion (M-06).** In-app deletion, or amend the Help Center to an email-request flow?
   *(Store policy makes in-app the safer answer.)*
6. **Coach tips (M-08).** Real feature (needs table + coach authoring UI) or delete?
7. **Accountability Pods.** Fully built, real tables, seeded data, **no entry point**. Ship it (add a
   Community tab or Directory module) or remove it?
8. **`/coach-client-workouts`, `/food-search`, `/log-meal`, `/nutrition-overview`.** Wire up or delete?
9. **Nav consolidation.** `AppShell._PersistentNav` vs `AppScaffold`/`AppBottomNav` — the two disagree
   on destinations. Pick one.
10. **QA Stripe/Anthropic credentials (B-1/B-2/B-3).** Provision, or declare those surfaces
    out of QA scope?
11. **`checkin_detail_screen`** is a `"coming soon"` stub reachable from a live route. Build or unlink?
12. **Class JOIN / QR buttons (M-12).** Is joining a call in-scope for v1, or should the buttons go?

---

## 9. Remediation candidates

Ordered by value-per-effort. **None of these were applied** — this workstream is read-only.

| # | Change | Files | Effort |
|---|---|---|---|
| R-1 | Deploy the 19 Edge Functions to QA + set secrets | infra | S |
| R-2 | `created_at` → `logged_at` (3 tokens) | `workout_service.dart:237,243,246` | XS |
| R-3 | Drop the `coach:coach_id(...)` embed; fetch coach profiles from `public_profiles` | `booking_screen.dart:55-58` | S |
| R-4 | Delete the "Demo fallback" catch in `_register()` | `event_ticket_screen.dart:66-72` | XS |
| R-5 | Remove `_toggleConnect(id, true)` after `launchUrl` | `integrations_screen.dart:337` | XS |
| R-6 | `select('*')` → explicit column list ×2 | `qa_suites.dart:420,685` | XS |
| R-7 | Check the `cancelSubscription` result before "Switched to the Free plan." | `upgrade_screen.dart:135-143` | XS |
| R-8 | Surface `sendInvite`'s email failure instead of "Invite sent!" | `coach_relationship_service.dart:86-92`, `coach_dashboard_screen.dart:1002` | S |
| R-9 | Roll back optimistic habit state on write failure | `habit_provider.dart:118-158` | S |
| R-10 | Resolve `checkins` (decision 1) | `checkin_service.dart` + `daily_checkin_screen.dart` **or** a new migration | M |
| R-11 | Add `custom_exercises.approved_by` (or drop from the payload) | new migration ≥123 **or** `custom_exercise_service.dart:772` | XS |
| R-12 | Fold `APPLY_MISSING.sql`'s `ticket_code`/`attended` into a numbered migration | new migration ≥123 | S |
| R-13 | Register a URL scheme + deep-link handler | `Info.plist`, `AndroidManifest.xml`, `main.dart` | M |
| R-14 | Implement or document-away account deletion | new Edge Function + `settings_screen.dart` | M |
| R-15 | Delete the ~2,436 lines of orphaned files (§6.2) and 40 orphaned providers (§6.3) | 20 files | M |
| R-16 | Remove `AppBottomNav`/`_AnimatedFab` and the dead `navIndex` parameter | `app_scaffold.dart` + 9 call sites | S |
| R-17 | Wire up or delete `/pods`, `/coach-client-workouts`, `/food-search`, `/log-meal`, `/nutrition-overview`, `/coach`, `/onboarding` | `app_router.dart` + hubs | M |
| R-18 | Rename one of the two `upcomingClassesProvider` declarations | `class_provider.dart:107` | XS |
| R-19 | Add `workout_set_logs` to the realtime publication, or drop the ticker | new migration **or** `workout_provider.dart:50` | XS |
| R-20 | Wire up `showCoachPricingSheet()` or delete it | `coach_business_screen.dart` / `coach_pricing_sheet.dart` | S |

**Parallelizable:** R-2 … R-9, R-11, R-18, R-19 are independent single-file changes and can be done
concurrently. R-1 gates any *verification* of the AI/payments surfaces. R-10 and R-17 depend on
product decisions.

---

## 10. Tests

**No tests were added, modified or deleted.** Existing suite, run on the current working tree:

```
$ flutter test --no-pub
00:04 +623: All tests passed!

$ flutter analyze --no-pub
171 issues found. (ran in 1.9s)
  errors:   0
  warnings: 15   (14 × unnecessary_non_null_assertion in tool/live_integration_test.dart,
                  1 × unnecessary_null_comparison + 1 × unnecessary_non_null_assertion
                    at active_workout_screen.dart:1212)
  info:     156  (avoid_print in tool/, curly_braces_in_flow_control_structures)
```

None of the failures in §5 are covered by a test. The suite is heavily weighted to the Phase 2
workout domain (session persistence, restoration, set-tracker widgets, error contracts); there is
no test asserting that a screen's query shape matches the live schema, which is exactly the class
of bug M-02/M-03/M-04/M-07/M-09 belong to.

**Suggested (not written):** a schema-contract test that walks every `.from(table).select(cols)`
pair in `lib/` and asserts each column exists in a checked-in schema snapshot. That would have
caught five of the nine top findings at CI time.

---

## 11. Files changed

| File | Change |
|---|---|
| `docs/QA_WORKSTREAM_M_UI_REACHABILITY_REPORT.md` | **Added** (this report) |

No source, test, migration, seed, config or `dart_defines` file was touched. Migrations 113–121 are
untouched. `git status` shows the same 114 pre-existing entries as at session start, plus this file.
All uncommitted work from other workstreams was preserved.

---

## 12. QA mutations and cleanup

| Action | Target | Reversible | Cleanup |
|---|---|---|---|
| `POST /auth/v1/token?grant_type=password` × 4 | QA `test@12circle.app`, `coach@12circle.app` | Creates GoTrue refresh-token rows and updates `last_sign_in_at` | None needed; tokens expire (1 h). Not revoked so the seed accounts stay usable. |
| ~260 `GET` requests to `/rest/v1/*` | QA PostgREST | Read-only | None |
| 47 `GET /rest/v1/rpc/*` | QA | `GET` only — PostgREST rejects `VOLATILE` functions over `GET`, and every call returned `42501` or a value; **no function body executed a write** | None |
| 19 `OPTIONS /functions/v1/*` | QA | CORS preflight; all returned 404 before reaching any handler | None |

**No rows were inserted, updated or deleted on QA.** One write test (a `PATCH` to probe the
`dietary_restrictions` text-vs-array question, §13) was attempted and **blocked by policy**; it was
not retried, and that question is left open rather than answered by guesswork.

---

## 13. Open question — `dietary_restrictions` type mismatch

Not promoted to a finding because it could not be confirmed without a write.

`013_health_assessment.sql:15` declares `dietary_restrictions TEXT NOT NULL DEFAULT ''`, and the live
QA value is the **string** `"{}"` — consistent with `TEXT`. But `IntakeData` writes it two different ways:

- `toSupabasePartial()` (`intake_data.dart:211-214`) sends a **List**, with the comment
  *"Live column is text[] — send a real array, not a comma-joined string."*
- `toSupabase()` (`intake_data.dart:252`) — used by the **final** onboarding upsert at
  `intake_flow_screen.dart:217-218` — sends `dietaryRestrictions.join(',')`, a **String**.

One of the two is wrong. If the column is `TEXT` (as the migration says), the per-step autosave may
be storing a serialised array or failing; if it is `text[]`, the final upsert that completes
onboarding may 400 out. `IntakeData.fromSupabase` defensively handles both shapes, which is why this
has stayed invisible.

**Verification needed:** one authenticated `PATCH` against a QA profile with each payload shape, or
a `information_schema.columns` read. **Decision required:** settle on one type and make both writers
agree. **Parallelizable: yes.**

---

## Production-contact statement

**Production was not contacted at any point during this workstream.**

- Every network request in this audit went to `https://eyqtldjqpgpljlqvpowh.supabase.co`, which
  `supabase/.temp/linked-project.json` identifies as **`{"ref":"eyqtldjqpgpljlqvpowh","name":"12Circle QA"}`**
  and which matches `SUPABASE_URL` in `apps/mobile/dart_defines/qa.json`.
- The production project reference (`nxdbooufqzkpslkcogxc`, hardcoded as a fallback in
  `app_env.dart:117`) was **never** used as a request host. `dart_defines/prod.json` carries empty
  `SUPABASE_URL` / `SUPABASE_ANON_KEY`, so no production endpoint is even resolvable from this tree.
- Only the two seeded QA accounts from `supabase/seeds/test_accounts.sql` were authenticated.
- All QA traffic was read-only (§12). No migration was applied, rolled back or edited; migrations
  113–121 are byte-identical to their state at session start.
