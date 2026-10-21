# 12 Circle Fitness — Design → Implementation Final Matrix

**Phase 2 deliverable — the canonical screen inventory.** Baseline `0aa844a`
(router **unchanged** since `fbee6d5`; verified by `git diff --stat`).

Every registered route is classified into **exactly one** category. Categories are not
collapsed. Where a route qualifies for several, this precedence applies — most specific
disposition first:

`I` debug → `F` duplicate/alias → `H` redirect/stub → `G` dead/unreachable →
`J` admin/vendor → `L` legal → `E` system → `K` coach → design status (`A`/`B`/`D`).

Design status is resolved by **`dart tool/fit_backlog.dart`** against the authoritative
`manifest.json`, i.e. by the route's actual builder widget — not by filename. This is what
corrects the historical FIT-001 error (§4).

## Category counts — 91 routes

| Cat | Category | Count |
|---|---|---|
| **A** | DESIGN + IMPLEMENTATION EXISTS | **35** |
| **B** | DESIGN EXISTS + IMPLEMENTATION PARTIAL | **2** |
| **C** | DESIGN EXISTS + IMPLEMENTATION MISSING | **0** |
| **D** | IMPLEMENTATION EXISTS + DESIGN MISSING | **13** |
| **E** | IMPLEMENTATION EXISTS + DESIGN NOT REQUIRED | **4** |
| **F** | DUPLICATE / ALIAS | **3** |
| **G** | DEAD / UNREACHABLE | **3** |
| **H** | REDIRECT / STUB | **5** |
| **I** | DEBUG / QA ONLY | **2** |
| **J** | ADMIN / VENDOR / NON-CLIENT PRODUCT | **7** |
| **K** | COACH PRODUCT | **14** |
| **L** | LEGAL / SYSTEM | **3** |
| **M** | BLOCKED BY OWNER DECISION | *see §5 — cross-cutting, not a route category* |
| **N** | POST-QA FEATURE/CAPABILITY GAP | *see `DESIGN_CAPABILITY_GAPS.md` — not a route category* |
| | **TOTAL** | **91** |

> **`C` = 0 is the headline of this phase.** Every one of the 45 designed routes is built.
> **No designed screen is unimplemented.** The remaining design work is therefore
> *interaction-level*, not screen-level — 287 of 600 declared interactions are present.

`M` and `N` are dispositions that attach to routes already counted above (a route can be
`A` *and* blocked by an owner decision), so counting them as route categories would
double-count. They are enumerated separately in §5 and in `DESIGN_CAPABILITY_GAPS.md`.

## Full route table

| Route | Widget | Shell | Paywall | Designed | Cat |
|---|---|---|---|---|---|
| `/action-items` | ActionCenterScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/active-workout` | ActiveWorkoutScreen | SHELL | — | ✅ | **A** |
| `/activity` | ActivityScreen | SHELL | — | ✅ | **A** |
| `/ai-coach` | AICoachScreen | SHELL | ClientPlan.aiGuided | ✅ | **A** |
| `/ai-nutrition` | AiNutritionScreen | SHELL | ClientPlan.aiGuided | ✅ | **A** |
| `/appointments` | BookingScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/challenge-detail` | ChallengeDetailScreen | SHELL | ClientPlan.aiGuided | ✅ | **A** |
| `/challenges` | ChallengesScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/chat` | ChatScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/checkin-detail` | CheckinDetailScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/checkins` | CheckinScreen | SHELL | — | ✅ | **A** |
| `/class-detail` | ClassDetailScreen | SHELL | — | ✅ | **A** |
| `/classes` | ClassesScreen | SHELL | — | ✅ | **A** |
| `/community` | CommunityScreen | SHELL | — | ✅ | **A** |
| `/events` | EventsScreen | SHELL | — | ✅ | **A** |
| `/forgot-password` | ForgotPasswordScreen | ROOT | — | ✅ | **A** |
| `/goals` | GoalsScreen | SHELL | — | ✅ | **A** |
| `/grocery-list` | GroceryListScreen | SHELL | — | ✅ | **A** |
| `/habits` | HabitScreen | SHELL | — | ✅ | **A** |
| `/insights` | InsightsScreen | SHELL | ClientPlan.selfGuided | ✅ | **A** |
| `/intake` | IntakeFlowScreen | ROOT | — | ✅ | **A** |
| `/login` | LoginScreen | ROOT | — | ✅ | **A** |
| `/meal-plan` | MealPlanScreen | SHELL | — | ✅ | **A** |
| `/meals-dashboard` | MealsDashboardScreen | SHELL | ClientPlan.selfGuided | ✅ | **A** |
| `/messages` | MessagingScreen | SHELL | ClientPlan.coachGuided | ✅ | **A** |
| `/notifications` | NotificationsScreen | SHELL | — | ✅ | **A** |
| `/profile` | ProfileScreen | SHELL | — | ✅ | **A** |
| `/progress` | ProgressScreen | SHELL | — | ✅ | **A** |
| `/score` | ScoreScreen | SHELL | — | ✅ | **A** |
| `/settings` | SettingsScreen | SHELL | — | ✅ | **A** |
| `/signup` | SignupScreen | ROOT | — | ✅ | **A** |
| `/train` | TrainHubScreen | SHELL | — | ✅ | **A** |
| `/upgrade` | UpgradeScreen | SHELL | — | ✅ | **A** |
| `/womens-health` | WomensHealthScreen | SHELL | — | ✅ | **A** |
| `/workout-detail` | WorkoutDetailScreen | SHELL | — | ✅ | **A** |
| `/daily-checkin` | DailyCheckinScreen | SHELL | ClientPlan.selfGuided | ✅ | **B** |
| `/home` | HomeScreen | SHELL | — | ✅ | **B** |
| `/coach-marketplace` | CoachMarketplaceScreen | SHELL | — | — | **D** |
| `/create-exercise` | CreateExerciseScreen | SHELL | — | — | **D** |
| `/directory` | DirectoryScreen | SHELL | — | — | **D** |
| `/exercise-database` | ExerciseDatabaseScreen | SHELL | — | — | **D** |
| `/exercise-detail` | ExerciseDetailScreen | SHELL | ClientPlan.selfGuided | — | **D** |
| `/exercise-library` | ExerciseLibraryScreen | SHELL | — | — | **D** |
| `/integrations` | IntegrationsScreen | SHELL | — | — | **D** |
| `/notification-preferences` | NotificationPreferencesScreen | SHELL | — | — | **D** |
| `/personal-info` | PersonalInfoScreen | SHELL | — | — | **D** |
| `/strength-progression` | StrengthProgressionScreen | SHELL | — | — | **D** |
| `/subscription` | ManageSubscriptionScreen | SHELL | — | — | **D** |
| `/workout-history` | WorkoutHistoryScreen | SHELL | — | — | **D** |
| `/workouts` | WorkoutListScreen | SHELL | — | — | **D** |
| `/payment-cancel` | PaymentResultScreen | ROOT | — | — | **E** |
| `/payment-success` | PaymentResultScreen | ROOT | — | — | **E** |
| `/reset-password` | ResetPasswordScreen | ROOT | — | ✅ | **E** |
| `/splash` | SplashScreen | ROOT | — | ✅ | **E** |
| `/book-call` | BookingScreen | SHELL | ClientPlan.coachGuided | — | **F** |
| `/coach` | TrainHubScreen | SHELL | — | — | **F** |
| `/nutrition-overview` | NutritionScreen | SHELL | ClientPlan.selfGuided | — | **F** |
| `/coach-business` | CoachBusinessScreen | SHELL | — | — | **G** |
| `/onboarding` | OnboardingScreen | ROOT | — | ✅ | **G** |
| `/pods` | PodsScreen | SHELL | — | ✅ | **G** |
| `/booking-handoff` | BookingHandoffScreen | SHELL | — | ✅ | **H** |
| `/checkin-form` | CheckinFormScreen | SHELL | — | — | **H** |
| `/food-search` | FoodSearchScreen | SHELL | ClientPlan.selfGuided | — | **H** |
| `/log-meal` | LogMealScreen | SHELL | ClientPlan.selfGuided | ✅ | **H** |
| `/nutrition` | NutritionSplashScreen | SHELL | ClientPlan.selfGuided | — | **H** |
| `/mie-debugger` | MieDebuggerScreen | ROOT | — | — | **I** |
| `/qa-center` | QaCenterScreen | ROOT | — | — | **I** |
| `/admin-dashboard` | AdminDashboardScreen | ROOT | — | — | **J** |
| `/admin-exercise-review` | ExerciseReviewScreen | ROOT | — | — | **J** |
| `/content-center` | ExerciseContentCenterScreen | ROOT | — | — | **J** |
| `/content-review` | ContentReviewQueueScreen | ROOT | — | — | **J** |
| `/knowledge-review` | IntelligenceReviewScreen | ROOT | — | — | **J** |
| `/observability` | ObservabilityScreen | ROOT | — | — | **J** |
| `/vendor-portal` | VendorPortalScreen | ROOT | — | — | **J** |
| `/coach-checkin-review` | CoachCheckinReviewScreen | SHELL | — | ✅ | **K** |
| `/coach-classes` | CoachClassesScreen | SHELL | — | — | **K** |
| `/coach-client-workouts` | CoachClientWorkoutScreen | SHELL | — | — | **K** |
| `/coach-copilot` | CoachCopilotScreen | SHELL | — | — | **K** |
| `/coach-dashboard` | CoachDashboardScreen | SHELL | — | ✅ | **K** |
| `/coach-directory` | CoachDirectoryScreen | SHELL | — | — | **K** |
| `/coach-packages` | CoachPackagesScreen | SHELL | — | — | **K** |
| `/coach-payments` | CoachPaymentsScreen | SHELL | — | — | **K** |
| `/coach-plan` | CoachPlanScreen | SHELL | — | — | **K** |
| `/compliance` | ComplianceDashboardScreen | SHELL | — | — | **K** |
| `/continuous-coaching` | ContinuousCoachingScreen | SHELL | — | — | **K** |
| `/program-builder` | ProgramLibraryScreen | SHELL | — | — | **K** |
| `/program-designer` | DynamicProgramBuilderScreen | SHELL | — | — | **K** |
| `/weekly-review` | WeeklyReviewScreen | SHELL | — | — | **K** |
| `/help-center` | HelpCenterScreen | SHELL | — | — | **L** |
| `/privacy-policy` | PrivacyPolicyScreen | SHELL | — | — | **L** |
| `/terms-of-service` | TermsOfServiceScreen | SHELL | — | — | **L** |

## 4 · FIT-001 discrepancy — RESOLVED

`DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` mapped **FIT-001 Home** to
`home/presentation/home_org.dart`. That file is **dead**: zero real importers (the only
matches are comments in `shared/widgets/app_scaffold.dart:4` and
`test/unit/client_nav_contract_guard_test.dart` naming it dead), while the router imports
`home/presentation/home_screen.dart:24`.

**Cause:** two classes named `HomeScreen` exist —
`home_org.dart:14` and `home_screen.dart:140` — and a filename-based resolver picked the
wrong one.

**Resolution:** `dart tool/fit_backlog.dart` resolves through the router's builder and now
reports **FIT-001 → `/home` 9/9 [34 files]**, correctly. The new tooling is authoritative;
`DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` remains stale on this row and should be superseded
by this document.

**Residual risk:** `home_org.dart` still exists with the duplicate class name and will
defeat the next resolver written. Removal is a deletion → owner approval (OD-32).

## 5 · Orphan routes — RESOLVED at 7

Three independent methods agree: this audit's navigation pass, hand verification of each
contested route, and the repository's own `dart tool/orphan_route_sweep.dart`:

```
registered 91 · navigated 79 · externally entered 5 · ORPHANED 7
```

`/coach` · `/coach-business` · `/food-search` · `/log-meal` · `/nutrition-overview` ·
`/onboarding` · `/pods`

The earlier 11-vs-5 discrepancy is explained and closed: `directory_screen.dart` navigates
through a data-driven `const _Module(route: …)` list that a literal call-scan cannot see
(this is why `/insights`, `/action-items` and `/events` appeared orphaned and are not), and
`qa_suites.dart` is a **gated-route test manifest, not navigation**.

`/activity`, `/meal-plan` and `/goals` were orphans fixed by the concurrent workstream
before this baseline.

Under the precedence rule these 7 appear as `F` (`/coach`, `/nutrition-overview`),
`H` (`/food-search`, `/log-meal`) and `G` (`/coach-business`, `/onboarding`, `/pods`).

**Six FIT anchors are stranded behind them — designed, built, measured complete, and
unreachable:** FIT-006 (2/2, locked), FIT-019 (4/5, locked), FIT-071, FIT-072, FIT-073,
FIT-074.
