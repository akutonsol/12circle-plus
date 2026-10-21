# 12Circle Fitness — Complete Mobile UI/Screen Audit

**Status:** AUDIT ONLY — no designs created, no code modified
**Repository:** `/Users/dmac/Documents/projects/12circle-fitness`
**Branch / HEAD:** `chore/qa-environments-secure-ai-backend` @ `bbe0448ff4722b843324de9e888b00302f051b1e`
**Method:** static source inspection of `apps/mobile/lib/` — 98 screen files staged and searched, plus `app_router.dart`, navigation calls, sheets and dialogs.
**Audit date:** 2026-09-09

---

## 1. Executive Summary

| Metric | Count |
|---|---:|
| `GoRoute` registrations in `app_router.dart` | **91** |
| `*_screen.dart` files under `lib/features/` | **98** |
| Screen **classes** declared (2 files declare 2 each) | **100** |
| Screen classes referenced by the router | **88** |
| Screen classes NOT referenced by the router | **12** |
| — of those, reachable via `Navigator.push` | **8** |
| — of those, orphaned / no inbound reference | **4** |
| Navigation calls | `context.go` ×103, `context.push` ×79, `Navigator.push` ×15 |
| Files containing `showModalBottomSheet` / `showDialog` | **20** |
| Intake pages inside `IntakeFlowScreen` | **27** (`_totalSteps = 26`) |

### Coverage against the 29 locked designs

The 29 locked entries resolve to **22 distinct screen classes** plus one wrapper (`PaywallGate`), one embedded widget (`ai_scan_view`) and five pure states. Several locked entries are states of the same class:

- #2 / #13 / #14 → `ActiveWorkoutScreen`
- #10 / #11 → `TrainHubScreen`
- #5 / #24 → `MessagingScreen`
- #8 / #9 → `IntakeFlowScreen`
- #23 → `ClassesScreen` + `EventsScreen` + `ChallengesScreen`
- #17 `PaywallGate` is a wrapper; #16 `ai_scan_view` is a widget; #18 / #21 are cross-cutting states

| Classification | Count |
|---|---:|
| Covered by the 29 locked designs | **22 classes** |
| Client/coach classes with **no** design | **≈63** |
| QA / debug | **2** |
| Admin / internal | **6** |
| Vendor | **3** |
| Orphaned / unused classes | **4** |
| Intake pages with no design (of 27) | **25** — 12 fit the locked archetype, **15 genuinely distinct** |

**Headline finding:** the previously assumed "51 routes pattern-covered" does not survive source inspection. A large share of uncovered routes are materially different user tasks, and `IntakeFlowScreen` alone contains 27 pages — not one archetype.

---

## 2. The 29 Locked Designs

| # | Name | Route | Resolves to |
|---:|---|---|---|
| 1 | Home | `/home` | `HomeScreen` |
| 2 | Active Workout | `/active-workout` | `ActiveWorkoutScreen` |
| 3 | Nutrition | `/meals-dashboard` | `MealsDashboardScreen` |
| 4 | Check-In | `/daily-checkin` | `DailyCheckinScreen` |
| 5 | Connect | `/messages` | `MessagingScreen` |
| 6 | Welcome | `/onboarding` | `OnboardingScreen` |
| 7 | Sign in (+ session-expired, OAuth-error) | `/login` | `LoginScreen` |
| 8 | Intake (archetype) | `/intake` | `IntakeFlowScreen` |
| 9 | Intake complete | — | `IntakeFlowScreen` page 27 |
| 10 | Workouts hub | `/train` | `TrainHubScreen` |
| 11 | Workouts empty | `/train` | `TrainHubScreen` (state) |
| 12 | Workout detail | `/workout-detail` | `WorkoutDetailScreen` |
| 13 | Rest | `/active-workout` | state |
| 14 | Session complete | `/active-workout` | state |
| 15 | Log a meal | `/log-meal` | `LogMealScreen` |
| 16 | AI meal scan | `ai_scan_view` | widget |
| 17 | Entitlement gate | `PaywallGate` | wrapper |
| 18 | Loading + failure | — | cross-cutting |
| 19 | Check-in hub | `/checkins` | `CheckinScreen` |
| 20 | Check-in detail | `/checkin-detail` | `CheckinDetailScreen` |
| 21 | Awaiting reply | — | state |
| 22 | Conversation | `/chat` | `ChatScreen` |
| 23 | What's on | `/classes` `/events` `/challenges` | 3 classes |
| 24 | Connect — no coach | `/messages` | state |
| 25 | Profile | `/profile` | `ProfileScreen` |
| 26 | Settings | `/settings` | `SettingsScreen` |
| 27 | Plans | `/upgrade` | `UpgradeScreen` |
| 28 | Coach dashboard | `/coach-dashboard` | `CoachDashboardScreen` |
| 29 | Coach check-in review | `/coach-checkin-review` | `CoachCheckinReviewScreen` |

---

## 6. Intake Audit — 27 pages (the largest single gap)

`IntakeFlowScreen` is 5,791 lines, `_totalSteps = 26`, driving a `PageView` with **27 children** and `NeverScrollableScrollPhysics` (programmatic navigation only). Resume is supported — the controller re-inits at a `savedStep`.

| # | Page class | Experience | Archetype? |
|---:|---|---|---|
| 0 | `_WelcomePage` | Intake welcome | **Distinct** |
| 1 | `_ProfileInfoPage` | Name, gender, date of birth | **Distinct** (form) |
| 2 | `_PARQPage` | PAR-Q medical screening | **Distinct** (yes/no questionnaire) |
| 3 | `_MedicalHistoryPage` | Medical conditions | Multi-select variant |
| 4 | `_InjuriesPage` | Injuries: flag + locations + free text | **Distinct** (conditional) |
| 5 | `_Step1Page` | Primary goal | Archetype (single-select) |
| 6 | `_ActivitiesPage` | Activities | Multi-select variant |
| 7 | `_TargetTimelinePage` | Target timeline | Archetype |
| 8 | `_ExperiencePage` | Experience level + worked-with-coach | **Distinct** (2-part) |
| 9 | `_HeightPage` | **Vertical scrolling ruler** picker | **Distinct** |
| 10 | `_WeightPage` | **Vertical scrolling ruler** picker | **Distinct** |
| 11 | `_TargetWeightPage` | **Horizontal scrolling ruler** picker | **Distinct** |
| 12 | `_WeightGoalPage` | Weight-goal summary | **Distinct** |
| 13 | `_Step2Page` | Activity level | Archetype |
| 14 | `_Step3Page` | Training frequency | Archetype |
| 15 | `_Step4Page` | Training location | Archetype |
| 16 | `_LifestylePage` | Sleep, stress, occupation | **Distinct** (3 inputs) |
| 17 | `_Step5Page` | Nutrition goal | Archetype |
| 18 | `_DietaryRestrictionsPage` | Restrictions + allergies | Multi-select variant |
| 19 | `_Step6Page` | Protein confidence | Archetype |
| 20 | `_Step7Page` | Biggest challenges | Multi-select variant |
| 21 | `_Step8Page` | **Progress photos** — camera/gallery/upload | **Distinct** |
| 22 | `_CoachingModePage` | Coaching mode (can skip to 24) | Archetype + branch |
| 23 | `_Step9Page` | Choose coach | **Distinct** |
| 24 | `_Step10Page` | Generating plan | **Distinct** (progress) |
| 25 | `_ConsentPage` | Consent | **Distinct** (legal) |
| 26 | `_Step11Page` | Final / enter app | Locked #9 |

**Breakdown:** 8 archetype-covered · 4 multi-select variants · **15 genuinely distinct** · 27 total.
Height, Weight and Target Weight are three *different* animated ruler mechanics (two vertical, one horizontal) — confirmed by `ScrollController` + `_rulerH` / `_rulerW` and `LayoutBuilder` sizing.

---

## 7. Body Measurement Audit

Body measurements are a **full post-onboarding sub-product**, not an intake step. Located in `progress_screen.dart` (87 KB) against the `body_measurements` table.

- **Three tabs:** Weight · Measurements · Photos (`['Weight','Measurements','Photos']`)
- **Fields:** `waist_cm`, `hips_cm`, `chest_cm`, `thighs_cm`, `arms_cm` (also `body_fat`, `forearms`, `neck` referenced elsewhere)
- **Editing:** `_LogMeasurementSheet` modal, seeded from `_latestMeasurements`
- **History:** `_measurementHistory` list, charted
- **Derived insight:** waist-to-hip ratio with healthy-range interpretation (≤0.85)
- **Also:** `_showLogWeightSheet`, photo-source sheet (`showModalBottomSheet<ImageSource>`)
- **Coach view:** `client_detail_screen.dart` reads the same data

**None of this is covered by any of the 29.**

---

## 8. Photo / Upload Audit

Nine files perform image capture or upload:

| File | Purpose | Bucket |
|---|---|---|
| `intake_flow_screen.dart` | Intake progress photos (front/side/back) | `progress-photos` |
| `progress_screen.dart` | Baseline + gallery photos, replace via delete-then-insert | `progress-photos` |
| `chat_screen.dart` | Chat photo message | `chat-media` |
| `personal_info_screen.dart` | Avatar | `avatars` |
| `coach_business_screen.dart` | Coach media | `coach-media` |
| `coach_video_response_screen.dart` | Coach video response | `coach-media` |
| `create_exercise_screen.dart` | Exercise media | `exercise-media` |
| `ai_scan_view.dart` | AI meal scan (locked #16) | — |
| `ai_nutrition_screen.dart` | AI nutrition image | — |

Shared pattern: `ImagePicker` → source sheet (camera/gallery) → `uploadBinary` → signed URL (private buckets) or public URL. **Upload progress / success / failure states exist in code but have no design.**

---

## 9. Authentication Audit

| Screen | Route | Covered? |
|---|---|---|
| `SplashScreen` | `/splash` | **No** — animated, hands off to `/onboarding` |
| `OnboardingScreen` | `/onboarding` | Locked #6 |
| `LoginScreen` | `/login` | Locked #7 |
| `SignupScreen` | `/signup` | **No** |
| `ForgotPasswordScreen` | `/forgot-password` | **No** |
| `ResetPasswordScreen` | `/reset-password` | **No** — pinned by `passwordRecoveryNotifier` |

Router `redirect` forces `/login` when unauthenticated; auth routes are `/login`, `/signup`, `/forgot-password`, `/onboarding`, `/intake`. Post-login role routing: coach → `/coach-dashboard`, admin → `/admin-dashboard`, vendor → `/vendor-portal`. **No in-app email-verification screen exists** — handled by Supabase out of app.

---

## 10. Community Audit

| Experience | Location | Covered? |
|---|---|---|
| Community feed — **3 tabs** (`TabController(length: 3)`) | `community_screen.dart` | **No** |
| Post card, comments, reactions | `post_card.dart`, `reaction_bar.dart` | **No** |
| Pods list + **join pod** | `pods_screen.dart` (`_joinPod`) | **No** |
| Pod card / empty state | `_PodCard`, `_EmptyPods` | **No** |
| Challenges list | `challenges_screen.dart` | Locked #23 (partial) |
| Challenge detail — progress %, **leaderboard**, join | `challenge_detail_screen.dart` | **No** |

Community is **not** covered by locked Connect (#5/#24), which is the messaging surface.

---

## 3–4. Route & Screen-File Audit — classification summary

### Not referenced by the router (12 classes)

**Reachable via `Navigator.push` (8) — all need classification as real destinations:**

| Class | Pushed from |
|---|---|
| `ChoosePackageScreen` | `coach_marketplace_screen` |
| `ClientDetailScreen` | `coach_dashboard`, `compliance_dashboard` |
| `CoachAvailabilityScreen` | `coach_dashboard`, `coach_directory` |
| `CoachVideoResponseScreen` | `client_detail` |
| `CreateClassScreen` | `coach_classes`, `classes` |
| `EventAgendaScreen` | `event_ticket`, `vendor_portal` |
| `EventAttendeesScreen` | `vendor_portal` (declared inside `vendor_portal_screen.dart`) |
| `EventTicketScreen` | `events_screen` |

**Orphaned — no inbound reference outside their own file (4):**

| Class | Note |
|---|---|
| `DashboardScreen` | superseded by `HomeScreen` / `CoachDashboardScreen` |
| `ProgramBuilderScreen` | router uses `ProgramLibraryScreen` from the same file |
| `SubscriptionScreen` | router uses `ManageSubscriptionScreen` for `/subscription` |
| `EmbeddedCheckoutScreen` | may be reached via conditional web import — **verify** |

### Wrappers, aliases and states

- **`PaywallGate`** wraps 13 routes: `/nutrition`, `/meals-dashboard`, `/nutrition-overview`, `/food-search`, `/log-meal`, `/ai-nutrition`, `/insights`, `/appointments`, `/messages`, `/chat`, `/action-items`, `/ai-coach`, `/book-call`. Wrapper, not a screen (locked #17).
- **`/coach` → `TrainHubScreen`** — route alias of `/train`.
- **`/payment-success` + `/payment-cancel` → `PaymentResultScreen`** — one screen, two states.
- **`BookingHandoffScreen`** (2 KB) — thin handoff, likely wrapper.
- **`NutritionSplashScreen`** — splash preceding `/meals-dashboard`.

---

## 13. Vendor / Admin / QA Audit

| Category | Screens |
|---|---|
| **QA/debug (2)** — gated by `kQaToolingEnabled = !kReleaseMode`, built by `buildQaToolingRoutes()` | `QaCenterScreen` (`/qa-center`), `MieDebuggerScreen` (`/mie-debugger`) |
| **Admin/internal (6)** | `AdminDashboardScreen`, `ExerciseReviewScreen`, `ObservabilityScreen`, `ExerciseContentCenterScreen`, `ContentReviewQueueScreen`, `IntelligenceReviewScreen` |
| **Vendor (3)** | `VendorPortalScreen`, `EventAgendaScreen`, `EventAttendeesScreen` |

Excluded from the client design backlog; documented so nothing is lost.

---

## 12. Coach Product Audit

Only #28 and #29 are designed. Uncovered coach surfaces:

`CoachBusinessScreen` · `CoachCopilotScreen` · `CoachMarketplaceScreen` · `CoachPackagesScreen` · `CoachPlanScreen` · `CoachPaymentsScreen` · `CoachClassesScreen` · `CoachClientWorkoutScreen` · `CoachDirectoryScreen` · `ContinuousCoachingScreen` · `WeeklyReviewScreen` · `DynamicProgramBuilderScreen` · `ProgramLibraryScreen` · `ComplianceDashboardScreen` · `ClientDetailScreen` (89 KB, 5 sheets) · `CoachAvailabilityScreen` · `CoachVideoResponseScreen` · `ChoosePackageScreen` · `CreateClassScreen`
Plus sheets: `coach_notes_sheet`, `assign_action_item_sheet`, `coach_pricing_sheet`, `coach_packages_view_sheet`.

---

## 16. Missing Design Inventory

Genuine unique user-facing experiences with no locked design.

### Priority 1 — client core journeys

| Name | Feature | Route/File | Why not covered |
|---|---|---|---|
| Splash | auth | `/splash` | Animated entry; distinct from Welcome |
| Sign up | auth | `/signup` | Locked #7 is sign-in only |
| Forgot password | auth | `/forgot-password` | Not covered |
| Reset password | auth | `/reset-password` | Recovery-pinned flow |
| Intake — 15 distinct pages | onboarding | `intake_flow_screen.dart` | Locked #8 is one archetype |
| Progress — Weight tab | progress | `/progress` | No locked design |
| Progress — Measurements tab | progress | `/progress` | Body measurement sub-product |
| Progress — Photos tab | progress | `/progress` | Photo gallery + compare |
| Log measurement sheet | progress | `_LogMeasurementSheet` | Distinct data-entry task |
| Log weight sheet | progress | `_showLogWeightSheet` | Distinct |
| Photo source sheet | progress/intake | `showModalBottomSheet<ImageSource>` | Shared pattern, undesigned |
| Habits | habits | `/habits` | No locked design |
| Goals | goals | `/goals` | No locked design |
| Score | scoring | `/score` | No locked design |
| Insights | insights | `/insights` | No locked design |
| Notifications | notifications | `/notifications` | No locked design |
| Women's health | womens_health | `/womens-health` | No locked design |
| Activity | activity | `/activity` | 56 KB, no locked design |

### Priority 2 — client secondary

Community feed (3 tabs) · Post + comments + reactions · Pods · Challenge detail · Class detail · Event ticket (QR) · Booking (`/appointments`, `/book-call`, 40 KB) · Booking handoff · Nutrition overview · Nutrition splash · Food search · AI nutrition · Meal plan · Grocery list · Exercise database · Exercise detail · Exercise library · Create exercise · Workout list · Workout history · Strength progression · Directory · AI coach · Action center · Payment result · Personal info · Notification preferences · Manage subscription · Integrations · Help centre · Privacy policy · Terms of service

### Priority 3 — coach product

The 19 coach screens + 4 sheets listed in §12.

---

## 17. Ambiguities

1. **`EmbeddedCheckoutScreen`** — no inbound reference found; may be reached through the conditional web import (`embedded_checkout.dart` / `_web.dart` / `_stub.dart`). Needs confirmation before classifying as unused.
2. **`DashboardScreen`, `ProgramBuilderScreen`, `SubscriptionScreen`** — no inbound references. Recommend owner confirmation that they are dead before excluding them.
3. **Sheet-vs-screen boundary** — 20 files use sheets/dialogs. Some (log measurement, log weight, photo source) are full data-entry tasks; others are confirmations. A design rule is needed for which warrant full artboards.
4. **`/coach` alias** — resolves to `TrainHubScreen`. Whether this is intentional or legacy is not determinable from source.
5. **Locked-design contents unseen** — `docs/design/` does not exist in the repo and no design board artifact exists. Coverage judgements here are made from route/class identity, not from the visual designs.
6. **Shell wedged** — `device_bash` failed 7 consecutive times; all analysis was performed on staged copies. Route/class extraction used regex, so a screen constructed dynamically would be missed.

---

*Audit complete. No designs created. No production code, routes, migrations or assets modified.*
