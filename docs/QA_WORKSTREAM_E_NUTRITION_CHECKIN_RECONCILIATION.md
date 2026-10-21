# 12 Circle Fitness — QA Workstream E
## Nutrition & Check-In Subsystem Reconciliation

**Phase: discovery. No code changed. No environment contacted.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Companion to:** [`MASTER_QA_RECONCILIATION.md`](MASTER_QA_RECONCILIATION.md) · [`REMEDIATION_EXECUTION_PLAN.md`](REMEDIATION_EXECUTION_PLAN.md)

---

## 0. Method, evidence class, and honesty statement

Every finding below is **source-verified (`SRC`)** against the working tree: Flutter
client, NestJS API, Supabase migrations `000`–`121`, and the Deno Edge Functions.

**No environment was contacted this run — not QA, not production.** Where a prior
document recorded a live probe I cite it as inherited evidence and label it. Nothing
here is marked `LIVE` on my own authority. Several findings (notably the RLS posture
on `weekly_checkins`) are *source-correct* and still require a live QA probe before
they can be called closed, because source and live are known to diverge in this
project.

Where I could not reproduce a previously reported defect, I say so rather than
restating it. Where I found the previously reported defect to be *differently shaped*
than recorded, §7 states the correction explicitly.

Defect IDs are namespaced `E-CHK-nn` / `E-NUT-nn` so they do not collide with the
master document's `CON-`/`SEC-` series. §7 maps them onto the existing canonical IDs.

---

## 1. Executive summary

**Check-In is non-functional end to end.** The only check-in surface a user can reach
writes to `public.checkins`, a table no migration creates. The only service that
writes correctly — `WeeklyCheckinService.submitWeeklyCheckin()` — has **zero callers**.
The consequence is not "some check-ins fail"; it is that **no check-in can be created
by the application at all**, and therefore the coach review queue, compliance scoring,
the at-risk roster, the Insights panel, the AI coach's grounding packet, the check-in
component of the 12 Circle Score, and the nutrition auto-adjustment all consume an
input that is structurally empty.

Compounding this, `weekly_checkins` carries **two mutually exclusive column families**
(a pre-existing set and a set added by migration `001`). The one writer uses one
family; four readers — including two AI paths — use the other. Even if the write path
were repointed today, the coach notification, the Insights card, and the AI system
prompt would still read `NULL`, and the AI prompt would receive the literal string
`undefined`.

**Nutrition works, but records the wrong numbers and cannot correct them.** Barcode
scans log per-100 g macros as "1 serving". A meal logged while viewing a past date is
written to today and then disappears from the screen the user is looking at. There is
no edit and no delete path anywhere in the feature, although the database grants both.
The AI meal-suggestion engine reads four nutrition columns that do not exist, so it
believes every user has eaten nothing, every day.

**The most serious nutrition finding is a safety one.** The AI meal-plan generator
never reads the user's onboarded `food_allergies` or `dietary_restrictions`. It sends
`Dietary restrictions: None` unless the user manually re-selects from six hard-coded
chips on that screen. This is materially worse than the previously recorded finding,
which assumed the data reached the prompt and was merely unvalidated.

**Security posture is better than the prior report implies, in one specific and
fragile way.** The `ai_adjust_nutrition(p_uid)` authorization hole is closed — but it
is closed by migration `116` omitting the function from its `EXECUTE` allowlist, **not**
by any check inside the function. Migration `079`'s `grant execute … to authenticated`
still stands in the tree. See §6, which is the single most important operational
paragraph in this document.

| Severity | Check-In | Nutrition | Total |
|---|---|---|---|
| P0 | 1 | 0 | **1** |
| P1 | 3 | 6 | **9** |
| P2 | 4 | 9 | **13** |
| P3 | 3 | 2 | **5** |
| **Total** | **11** | **17** | **28** |

Four items require a product decision before they can be fixed (§8).

---

## 2. CHECK-IN — complete audit

### 2.1 Canonical table

**`public.weekly_checkins` is the one and only check-in table.** It is real, populated,
and correctly secured as of migrations `114` and `118`.

`public.checkins` **does not exist**. No migration in `000`–`121` creates it. The prior
report's live probe (`GET /rest/v1/checkins` → HTTP 404 `PGRST205`) is consistent with
the source. There is no second check-in table and no view.

Schema, assembled across migrations:

| Column | Origin | Written by app? | Read by |
|---|---|---|---|
| `id`, `user_id`, `week_number`, `week_start_date`, `status` | `000` baseline | yes | all |
| `mood`, `energy`, `sleep_hours_avg` | `000` baseline | **yes** | nothing |
| `overall_score`, `submitted_at` | `000` baseline | yes | `_fromRow` |
| `feedback_message`, `feedback_recommendations`, `reviewed_at`, `coach_name` | `000` baseline | yes (coach) | `_fromRow` |
| `created_at` | `000` baseline | default | compliance, AI, `079` |
| `coach_id` | `001`:32 | **no** | `004` notify trigger |
| `weight_kg` | `001`:33 | **no** | `079`, insights, `004`, `ai-coach` |
| `energy_level` | `001`:34 | **no** | insights, `004`, `ai-coach` |
| `stress_level` | `001`:35 | yes | insights, `ai-coach` |
| `sleep_hours` | `001`:36 | **no** | insights, `ai-coach` |
| `hunger_level` | `001`:37 | **no** | nothing |
| `compliance_percent` | `001`:38 | **no** | `004`, `ai-coach` |
| `notes` | `001`:39 | yes | `_fromRow` |

Uniqueness: `weekly_checkins_user_week_unique (user_id, week_start_date)` — `000`:231.
This is the constraint `submitWeeklyCheckin`'s upsert targets, and it is correct.

### 2.2 Canonical service

**`WeeklyCheckinService`** — [weekly_checkin_service.dart](apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart).
It is the correct implementation: real table, correct conflict target, correct
coach-feedback update, server-side notification via the DB trigger rather than a
client insert. **It has no callers for any of its write or read methods except
`getSubmittedCheckinsForCoach` and `submitCoachFeedback`.**

**`CheckinService`** — [checkin_service.dart](apps/mobile/lib/features/checkins/data/checkin_service.dart)
— is the legacy duplicate. All six of its data methods target `checkins`. It is the
one the live UI uses.

### 2.3 Canonical route and navigation entry points

| Route | Screen | Reaches | Entry points |
|---|---|---|---|
| `/daily-checkin` | `DailyCheckinScreen` | `CheckinService` → **`checkins`** ✗ | bottom nav tab 5 ([app_shell.dart:151](apps/mobile/lib/core/router/app_shell.dart#L151)); Home "Weekly Check-In +10 pts" ([home_screen.dart:766](apps/mobile/lib/features/home/presentation/home_screen.dart#L766)); Directory "Weekly Check-ins" ([directory_screen.dart:66](apps/mobile/lib/features/dashboard/presentation/directory_screen.dart#L66)); `CheckinFormScreen` |
| `/checkins` | `CheckinScreen` | **`coaching_calls`** — an appointments calendar | [daily_checkin_screen.dart:262](apps/mobile/lib/features/checkins/presentation/daily_checkin_screen.dart#L262); `home_org.dart:65` (dead file) |
| `/checkin-form` | `CheckinFormScreen` | placeholder → `/daily-checkin` | `CheckinCard` (orphaned) |
| `/checkin-detail` | `CheckinDetailScreen` | placeholder, "coming soon" | `CheckinCard` (orphaned) |
| `/coach-checkin-review` | `CoachCheckinReviewScreen` | `WeeklyCheckinService` → **`weekly_checkins`** ✓ | coach bottom nav ([app_shell.dart:103](apps/mobile/lib/core/router/app_shell.dart#L103)); coach directory |

`app_shell.dart:68-70` maps `/daily-checkin`, `/checkin*` **and** `/appointments` to the
same nav index, which is how an appointments calendar came to sit under the "Check-In"
tab.

`home_org.dart` is dead — nothing imports it.

### 2.4 Dependency graph

```
                         WRITE SIDE (client)
   bottom nav ─┐
   Home CTA   ─┼─► /daily-checkin ─► DailyCheckinScreen
   Directory  ─┘                          │
                                          ▼
                              CheckinService.saveWeeklyCheckin()
                                          │
                                          ▼
                                 public.checkins  ✗ DOES NOT EXIST
                                          │
                                          ✗ (nothing downstream ever runs)

                         WRITE SIDE (correct, unused)
   (no caller) ─────────► WeeklyCheckinService.submitWeeklyCheckin()
                                          │
                            ┌─────────────┼──────────────┐
                            ▼             ▼              ▼
                  weekly_checkins   ScoreService     ScoreEngine
                    (upsert)        .addCheckinPoints  .weeklyCheckin
                            │        (+10 daily)       (+25, deduped)
                            ▼
                  trg_notify_coach_on_checkin (004, AFTER INSERT)
                            │    reads weight_kg / energy_level / compliance_percent
                            ▼    ── all NULL → "Weight: —kg | Energy: —/5"
                     insert_notification(coach)

                         READ SIDE (all consume the empty table)
   weekly_checkins ─┬─► WeeklyCheckinService.getSubmittedCheckinsForCoach()
                    │      └─► coachSubmittedCheckinsProvider
                    │            └─► CoachCheckinReviewScreen  ── permanently empty
                    │            └─► CoachDashboardScreen
                    ├─► compliance_service.dart:126 ── at-risk roster, compliance %
                    ├─► insights_provider.dart:74 ── reads energy_level/sleep_hours/weight_kg (never written)
                    ├─► coach_ecosystem_provider.dart:169 ── client detail timeline
                    ├─► send-checkin-reminder (Edge, Sunday cron) ── reminds everyone, forever
                    ├─► ai-coach (Edge) ── injects `undefined` into the Claude system prompt
                    ├─► ai_adjust_nutrition(p_uid) (079) ── reads weight_kg → always no-ops
                    └─► admin_dashboard (019) ── `checkins_week` stat, always 0

                         PARALLEL / MISFILED
   /checkins ─► CheckinScreen ─► coaching_calls   (duplicates /appointments → BookingScreen)
```

### 2.5 Weekly vs daily relationship

There is **no daily check-in** in this product, in any layer:

- The product bible does not mention one.
- No table, column, or migration supports one.
- `CheckinService.saveDailyCheckin()` and `hasCheckedInToday()` exist but have **zero
  callers**; the only screen that touches `CheckinService` calls `saveWeeklyCheckin`.
- The screen at `/daily-checkin` is named `DailyCheckinScreen`, its state class is
  `_WeeklyCheckinState`, its success dialog says **"Weekly Check-In Complete!"**, and
  Directory labels it **"Weekly Check-ins"**.
- `getCheckinStreak()` computes a *daily* consecutive-day streak over rows a weekly
  cadence could never satisfy — it would report a streak of 1 forever.

The "daily" concept is naming residue on a weekly feature, not a second requirement.
**The architecture proves the duplicate is redundant** — which is the bar the brief set
for proposing retirement. Recommendation and the residual product question are in §8
(Q-E1).

### 2.6 AI consumers

| Consumer | Reads | State |
|---|---|---|
| `ai-coach` Edge fn, all five modes | `weekly_checkins.*` → prompt block "Latest Check-In" | Reads `weight_kg`, `energy_level`, `stress_level`, `sleep_hours`, `compliance_percent`. With no rows the block is omitted; **with a row it interpolates `undefined`** into the system prompt (JS template literal over absent keys). |
| `AICoachService.analyzeCheckins(clientId)` | — | **Zero callers.** The Edge function **ignores `target_client_id` entirely** and grounds on `user.id`. Fail-safe today; a trap tomorrow (E-CHK-07). |
| `ai_adjust_nutrition(p_uid)` (079) | `weekly_checkins.weight_kg`, `created_at` | Requires ≥2 rows with non-null `weight_kg` in 35 days. `weight_kg` is written by **nothing**. Structurally can never fire. |
| `ai-coaching-engine` Edge fn | `weekly_checkins` not read | — |

### 2.7 Coach consumers

`CoachCheckinReviewScreen`, `CoachDashboardScreen` (`clientCheckinsProvider` →
**`checkins`**, and `coachSubmittedCheckinsProvider` → `weekly_checkins`),
`ComplianceService` (at-risk roster), `coach_ecosystem_provider` (client detail),
`client_detail_screen` (two render sites), `send-checkin-reminder` (weekly email +
notification), `admin_dashboard` (`checkins_week`).

`getSubmittedCheckinsForCoach()` issues an **unfiltered** `status='submitted'` query and
relies entirely on RLS for scoping. Under migration `114` that is now correct
(owner ∪ active-coach). Before `114` it returned the whole platform. Its `catch`
fallback re-issues the same query without the join, so a genuine RLS denial is
indistinguishable from a relationship-name mismatch.

### 2.8 Security and RLS

Source-correct as of `114` + `116` + `118`. **Not verified live this run.**

- **RLS enabled**, `anon` revoked from the table (`114`:126) and schema-wide (`118`:262).
- `SELECT`: `user_id = auth.uid() OR is_active_coach_of(user_id)`.
- `INSERT`: owner only — a coach cannot fabricate a client's compliance history.
- `UPDATE`: both parties, column-partitioned by the `trg_checkin_authorship`
  `BEFORE UPDATE` trigger — client may re-answer but not author, forge, or clear the
  coach's review, and cannot self-mark `reviewed`; coach may write **only** the six
  review columns.
- **No `DELETE` grant** — deliberate; this is health-record history.
- The trigger's `auth.uid() IS NULL` early return preserves the service-role/engine path.

This closes SEC-03 / D-03 at the source layer. **Live QA probe is still required**
before the item is marked closed, per the execution plan's own rule.

One residual: `is_active_coach_of()` is only trustworthy because migration `113` closed
`coach_client_relationships`. That dependency is real and already recorded as SEC-01.

### 2.9 Write paths

| Path | Target | Status |
|---|---|---|
| `DailyCheckinScreen._submit` → `CheckinService.saveWeeklyCheckin` | `checkins` | ✗ nonexistent table |
| `WeeklyCheckinService.submitWeeklyCheckin` | `weekly_checkins` | ✓ correct, **no caller** |
| `WeeklyCheckinService.submitCoachFeedback` | `weekly_checkins` | ✓ correct, live, in use |
| `CheckinService.saveDailyCheckin` | `checkins` | ✗ nonexistent table, no caller |
| service_role / seeds | `weekly_checkins` | ✓ how the populated rows got there |

### 2.10 Tests

| File | Covers | Verdict |
|---|---|---|
| `edge_function_logic_test.dart` | `send-checkin-reminder` week boundaries, notification row shape | Re-implements the TypeScript in Dart. Tests the replica, not the function. Would not catch a column rename. |
| `phase1_security_boundary_test.dart` | Asserts migration `114` text contains the RLS/revoke statements | Tests the migration *file*, not the database. Correct as a drift guard; not a boundary test. |
| `spec_score_compliance_test.dart`, `score_logic_test.dart` | check-in point arithmetic | Pure arithmetic, correct, but the code path that awards them is orphaned. |
| **Absent** | Any test that a check-in save reaches a table; any test the coach queue is populated; any test of the writer↔reader column contract | — |

`qa_suites.dart:807` — the app's own in-product QA journey probes
`_mHasRow('Check-in submitted', 'checkins', 'client_id')`: nonexistent table **and** a
column name (`client_id`) that `weekly_checkins` does not use (`user_id`).

### 2.11 Dead / orphaned code

Zero-caller inventory in `features/checkins/`:

- `CheckinService` — entire class, once `DailyCheckinScreen` is repointed. `saveDailyCheckin` and `hasCheckedInToday` are already unreachable.
- `WeeklyCheckinService.submitWeeklyCheckin`, `.getCurrentWeekCheckin`, `.getWeeklyCheckins`
- Providers: `checkinStreakProvider`, `recentCheckinsProvider`, `hasCheckedInTodayProvider`, `weeklyCheckinsProvider`, `currentWeekCheckinProvider`, `selectedCheckinProvider`
- Widgets: `CheckinCard`, `CheckinStatusBadge`
- Screens: `CheckinFormScreen`, `CheckinDetailScreen` (placeholders on live routes)
- `AICoachService.analyzeCheckins()`
- `home_org.dart` (whole file, unimported)

**Not dead, but misfiled:** `CheckinScreen` — a working coaching-calls calendar living
under `features/checkins/` at `/checkins`.

### 2.12 Do duplicate check-in concepts exist?

**Yes — three, and they are different kinds of duplicate:**

1. **Two services for one table concept.** `CheckinService` (`checkins`, nonexistent)
   and `WeeklyCheckinService` (`weekly_checkins`, real). Genuine redundancy; the
   architecture proves it — one target does not exist.
2. **Two column families inside one real table.** Baseline (`mood`/`energy`/
   `sleep_hours_avg`) vs migration-`001` (`energy_level`/`sleep_hours`/`weight_kg`/…).
   **Not resolvable by retirement** — live readers depend on the `001` family and the
   only writer uses the baseline family. This needs a contract decision, not a delete.
3. **Two appointment surfaces.** `/checkins` (`CheckinScreen`) and `/appointments`
   (`BookingScreen`) both render scheduled coaching calls. Redundancy is likely but
   `BookingScreen` was out of this workstream's scope — flagged, not adjudicated.

---

## 3. NUTRITION — complete audit

### 3.1 Surface inventory

| Route | Screen | Gate | Reached from |
|---|---|---|---|
| `/nutrition` | `NutritionSplashScreen` → redirects by coaching mode | `selfGuided` | Directory, Activity |
| `/meals-dashboard` | **`MealsDashboardScreen`** — the real dashboard | `selfGuided` | splash, redirect stubs |
| `/nutrition-overview` | `NutritionScreen` — earlier, weaker build | `selfGuided` | **nothing but the QA suite** |
| `/food-search` | `FoodSearchScreen` — 23-line redirect stub | `selfGuided` | nothing |
| `/log-meal` | `LogMealScreen` — 23-line redirect stub | `selfGuided` | nothing |
| `/ai-nutrition` | `AiNutritionScreen` — LLM chat | **`aiGuided`** | splash, meals dashboard banner |
| `/meal-plan` | `MealPlanScreen` | **none** | `/ai-nutrition`, `/grocery-list` |
| `/grocery-list` | `GroceryListScreen` | **none** | `/ai-nutrition`, `/meal-plan` |

### 3.2 Food logging, manual entry, meals

`NutritionService.logMeal()` → `nutrition_logs`. Three call sites in
`MealsDashboardScreen` (`_logFood`, `_logFromScan`, `_logFromBarcode`) and one in
`NutritionScreen._log`. `logged_at` is **hardcoded** to `DateTime.now()`
([nutrition_service.dart:63](apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L63));
the selected date is never passed in. Custom foods (`addCustomFood`) live in an
in-memory `List<Food>` on a service instance the providers re-create — they do not
survive a rebuild and are never persisted.

### 3.3 Meal scan (AI)

`ai_scan_view.dart` → `NutritionService.analyzeFood()` → Edge function
`analyze-food-image` → Claude (`claude-sonnet-4-6`, a valid current model ID — **not**
a defect; verified) with a structured-JSON system prompt. Auth is enforced
(`userDb.auth.getUser()` → 401). The function correctly refuses to fabricate: "If you
cannot identify any food, return calories 0 and confidence 0."

The client shows a `confidence` score and a `0.25×–3.0×` portion slider, scales the
macros by it (`ScanResult.scaled`), then discards the multiplier at write time
(E-NUT-13). `mediaType` is forwarded to Anthropic unvalidated (E-NUT-16).

### 3.4 Barcode scanning

`BarcodeScanView` (`mobile_scanner`) → `NutritionService.lookupBarcode(code)`:
local `foods` table first, then OpenFoodFacts, then cache. The returned map's keys are
the unqualified `{name, calories, protein, carbs, fat}` while the values are strictly
**per 100 g**. `_logFromBarcode` writes them with `servingSize: 1, servingUnit:
'serving'`. The unit is lost at the boundary (E-NUT-01). The `foods` cache is
world-writable and can never refresh (E-NUT-08, E-NUT-09).

### 3.5 Meal plans and grocery lists

`AiNutritionService.generateMealPlan()` / `.generateGroceryList()` — both build a
prompt string and call `POST /ai/nutrition/message`; both **return `String`**. Held in
`StateNotifier<String?>`. **Never persisted, never parsed into a model, never written
to any table, no bridge to `nutrition_logs`.** `GroceryListScreen` line-parses the
prose to render categories. Error strings become the state and are then fed back to
Claude as "the meal plan" (E-NUT-12).

### 3.6 Nutrition auto-adjustment

`ai_adjust_nutrition(p_uid)` — migration `079`. Reads the weekly weight trend from
`weekly_checkins`, nudges `client_nutrition_plans.calories_target` by ±120–150 (floored
at 1200), recomputes protein/fat/carbs, writes an `ai_insights` row.

**Three independent reasons it cannot run:**

1. **No caller.** Not `ai_cron_generate` (076), not `ai_cron_accountability` (080), not
   any Edge Function, not the API, not the Flutter client. Grepped the entire tree.
2. **No input.** Requires ≥2 `weekly_checkins` rows with non-null `weight_kg` in 35
   days. Nothing writes `weight_kg` to that table, and no check-in UI collects weight.
3. **No client EXECUTE.** Migration `116` revoked schema-wide and did not re-grant it.

See §6 — this is the item the brief's security rule is about.

### 3.7 Macros, calorie targets, goals

`client_nutrition_plans` (`001`:105, + `water_target_oz` in `034`) is the single source
of macro targets. RLS: `FOR ALL … USING (coach_id = auth.uid() OR client_id =
auth.uid())` — correct.

- Writer: `coach_program_service.dart:263-311` (coach assigns/updates/deactivates).
- Readers: `nutritionGoalsProvider`, `NutritionService._awardNutritionScore`,
  `MealPlanScreen._loadGoalsOnce`, `ai-coach`, `ai-coaching-engine`,
  `coach_ecosystem_provider`.
- Fallback when no plan exists: `2000 / 120 / 220 / 65`, duplicated in **three**
  places (`nutrition_provider.dart:35`, `nutrition_service.dart:81`,
  `meals_dashboard_screen.dart:116-119`) with two different protein defaults in play.

`water_target_oz` is coach-settable and read by **no** client surface (E-NUT-14).

### 3.8 Weekly trend inputs

Nutrition contributes to the trend only through the 12 Circle Score:
`logMeal` → `ScoreEngine.mealLogged` (+5, dedup defeated — E-NUT-10) and
`_awardNutritionScore` → `ScoreService.addNutritionPoints(completionPct)` (0–30, set
not incremented, so idempotent) plus `proteinGoalHit` (+15) and
`nutritionDayComplete` (+20) once per day.

`getTodayTotals()` builds local-midnight bounds and compares them to a `timestamptz`
column with no conversion — the RC-8 day-window skew applies to every macro ring,
every adherence percentage, and every score award.

### 3.9 Edit / delete

**Absent.** Zero `.update(` and zero `.delete(` calls exist anywhere under
`features/nutrition/` or `features/ai_nutrition/`. The database permits both:
`nutrition_logs` RLS is `FOR ALL TO authenticated USING (user_id = auth.uid())`
(`006`, re-asserted `111`:47) and `authenticated` holds the table grant. This is a pure
client-side gap (E-NUT-02).

### 3.10 Coach visibility

`nutrition_logs` SELECT: `user_id = auth.uid() OR is_active_coach_of(user_id)`
(`100`:47, re-asserted `111`:52). Correct and tight. Migration `006`'s original
`USING (true)` is superseded.

`MealsDashboardScreen` shows a coach-guided banner: *"Coach-Guided — your coach can
view your nutrition logs."* Accurate.

**But no coach screen reads `nutrition_logs`.** `coach_ecosystem_provider` pulls the
client's *plan*, not their logs; `client_detail_screen` renders no meal history. The
banner promises a visibility the coach UI does not implement.

### 3.11 AI behaviour, determinism, and the architectural boundary

Measured against product bible §2 and §6:

| Bible rule | Nutrition subsystem |
|---|---|
| "The engine decides. AI explains." | **Violated.** Meal plans, grocery lists and food macro estimates are direct, unconstrained LLM output. No deterministic engine participates. |
| "Every recommendation is explainable… from a recorded decision trace." | **Violated.** No `decision_traces` row is written for any nutrition decision. |
| "AI may not fabricate metrics." | **Violated in effect.** `analyzeFood`'s LLM estimate is written into `nutrition_logs` as fact, then consumed by the *deterministic* score (`addNutritionPoints`, `proteinGoalHit`, `nutritionDayComplete`). An LLM estimate is a direct input to a deterministic score. |
| "AI may not bypass the coach approval matrix for coach-guided clients." | **Violated.** `/meal-plan` has no gate and no approval step at any coaching mode. |
| "Recommend only within certified knowledge." | **Violated.** No certification or allergen constraint is applied to generated food. |

The `analyze-food-image` prompt's "return 0 / confidence 0 if you cannot identify"
instruction is the one place the subsystem does honour "if data is missing, it says so."

### 3.12 Authorization

| Surface | Auth | Verdict |
|---|---|---|
| `POST /ai/nutrition/message` (NestJS) | `SupabaseAuthGuard` at controller level; `ValidationPipe` with `whitelist` + `forbidNonWhitelisted`; DTO caps message 8 000 chars, history 40 turns, image ~5 MB, media type allow-listed | **Sound.** Key is server-held, never logged, errors mapped to a generic 503. No rate limit and no plan check (E-NUT-07). |
| `analyze-food-image` (Edge) | `auth.getUser()` → 401 | Sound. `mediaType` unvalidated (E-NUT-16). |
| `ai-coach` (Edge) | `auth.getUser()` → 401, then grounds strictly on `user.id` | Sound, and safe in the fail-closed direction. Ignores the `target_client_id` the client sends. |
| `nutrition_logs`, `client_nutrition_plans` | RLS, owner + active coach | Sound. |
| `foods` | `SELECT true`, **`INSERT WITH CHECK (true)`**, no UPDATE/DELETE policy | **Not sound** — E-NUT-08. Migration `118` accepted the *SELECT* policy as shared-catalog read; the unrestricted INSERT is a separate, uncovered issue. |
| `ai_adjust_nutrition(p_uid)` | No `auth.uid()` check in the body; no client EXECUTE after `116` | Closed **by privilege only**. See §6. |

### 3.13 Edge Functions

| Function | Role | State |
|---|---|---|
| `analyze-food-image` | meal photo / description → macros | Live path. Sound auth. |
| `ai-coach` | five-mode chat, grounds on `weekly_checkins` + `client_nutrition_plans` | Ignores `target_client_id`; interpolates `undefined` from unwritten check-in columns. |
| `ai-coaching-engine` | `meal_suggestion` remaining-macro computation | **Reads `nutrition_logs.protein_g/carbs_g/fat_g` — columns that do not exist** (E-NUT-04). |
| `send-checkin-reminder` | Sunday cron | Correct against `weekly_checkins`; reminds every client forever because no client can check in. |

### 3.14 Nutrition dependency graph

```
   Directory / Activity ─► /nutrition ─► NutritionSplashScreen
                                              │  (by coachingMode)
                          ┌───────────────────┴────────────────────┐
                          ▼                                        ▼
                  /meals-dashboard                          /ai-nutrition  [aiGuided]
                  MealsDashboardScreen                      AiNutritionScreen
                          │                                        │
        ┌─────────────────┼─────────────────┐          ┌───────────┴───────────┐
        ▼                 ▼                 ▼          ▼                       ▼
   manual search    AiScanView       BarcodeScanView  /meal-plan  ──────►  /grocery-list
   (built-ins +          │                 │          [NO GATE]            [NO GATE]
    foods cache +        │                 │              │                     │
    OpenFoodFacts)       │                 │              ▼                     ▼
        │                ▼                 ▼        generateMealPlan     generateGroceryList
        │        analyze-food-image   lookupBarcode        │                     │
        │          (Edge, Claude)     foods → OFF          └──────┬──────────────┘
        │                │                 │                     ▼
        │                │                 │           POST /ai/nutrition/message
        │                │                 │              (NestJS + SupabaseAuthGuard)
        │                │                 │                     │
        │                │                 │                     ▼
        │                │                 │              Claude · free text
        │                │                 │                     │
        │                │                 │                  String?  ── in memory only,
        │                │                 │                             never persisted
        └────────────────┴─────────────────┘
                         ▼
              NutritionService.logMeal()
                logged_at := now()  ← selected date discarded
                         │
                         ▼
                  nutrition_logs ──► coach SELECT via is_active_coach_of()  (no coach UI reads it)
                         │
        ┌────────────────┼──────────────────────────┬────────────────────────┐
        ▼                ▼                          ▼                        ▼
  getTodayTotals   _awardNutritionScore      ai-coaching-engine        home_screen
  (local-midnight  ├─► addNutritionPoints    reads protein_g/carbs_g   weekly meal count
   vs timestamptz) ├─► proteinGoalHit        /fat_g ── DO NOT EXIST
                   └─► nutritionDayComplete  → remaining == full target

   client_nutrition_plans ──► nutritionGoalsProvider, _awardNutritionScore,
     ▲                        MealPlanScreen macros, ai-coach, ai-coaching-engine
     │
   coach_program_service (coach assigns)        water_target_oz ──► (no reader)

   ai_adjust_nutrition(p_uid) ──► client_nutrition_plans + ai_insights
     ▲ no caller · no client EXECUTE (116) · input weight_kg never written
```

---

## 4. Defect register — CHECK-IN

### E-CHK-01 · P0 · functional · The only reachable check-in surface writes to a table that does not exist
**Evidence:** `SRC` (inherited `LIVE`: `PGRST205` on `/rest/v1/checkins`)
**Layer:** service · **Corroborates:** CON-01

[daily_checkin_screen.dart:63](apps/mobile/lib/features/checkins/presentation/daily_checkin_screen.dart#L63)
calls `CheckinService.saveWeeklyCheckin`, which inserts into `checkins`
([checkin_service.dart:86](apps/mobile/lib/features/checkins/data/checkin_service.dart#L86)).
No migration creates that table. The screen is the bottom-nav "Check-In" tab, the Home
card, and the Directory tile — every route a user has.

**Root cause.** Two services were built for one feature and the UI was wired to the
legacy one. Nothing in CI or the test suite asserts that a save reaches a table.

**Blast radius.** Not degraded — *zero*. No check-in row can be created by the app.
Coach review queue empty; compliance and at-risk scoring have no input; Insights
check-in card empty; `ai-coach` grounding has no check-in block; the Sunday reminder
nags every client forever; the check-in component of the 12 Circle Score never awards;
`ai_adjust_nutrition` has no weight trend. The `weekly_checkins` rows that do exist on
QA arrived by seed or service_role, not through the product.

**Exact fix.** Repoint `DailyCheckinScreen._submit` to
`WeeklyCheckinService.submitWeeklyCheckin`; repoint `_load` to
`getCurrentWeekCheckin()`/`getWeeklyCheckins()`; delete `CheckinService` and its three
orphaned providers; repoint `coach_dashboard_screen.dart:108` `clientCheckinsProvider`
to `weekly_checkins` keyed on `user_id`; fix `qa_suites.dart:807`.

**Dependencies.** E-CHK-03 (column contract) must be decided in the same change or the
repointed writer still fails the four readers. E-CHK-04 (field coverage) rides along.
**Product decision:** Q-E1.

**Regression test.** A check-in save that cannot reach its table raises; a successful
save is readable back within the same week window; the coach queue count equals the
number of submitted rows for that coach's active clients; `weekly_checkins` gains
exactly one row per user per `week_start_date`.

---

### E-CHK-02 · P1 · functional · The correct check-in write path has zero callers
**Evidence:** `SRC` · **Layer:** provider/UI · **New — not in any prior report**

`WeeklyCheckinService.submitWeeklyCheckin()` — the only method in the codebase that
writes a valid check-in — is called from nowhere. So are `getCurrentWeekCheckin()`,
`getWeeklyCheckins()`, `currentWeekCheckinProvider`, `weeklyCheckinsProvider`,
`selectedCheckinProvider`, `CheckinCard`, `CheckinStatusBadge`, `checkinStreakProvider`,
`recentCheckinsProvider`, `hasCheckedInTodayProvider`, `CheckinService.saveDailyCheckin`,
`CheckinService.hasCheckedInToday`, and `AICoachService.analyzeCheckins`.

**Root cause.** A rewrite landed the new service and providers but never re-wired the
screen. No orphan/dead-code gate exists.

**Why it matters independently of E-CHK-01.** This is *why* E-CHK-01 survived: a
reviewer reading `weekly_checkin_service.dart` sees a correct implementation and stops.

**Exact fix.** Absorbed by E-CHK-01's rewiring; then delete what remains unreferenced.
Add `dart analyze` dead-code / unused-element enforcement to CI.

**Dependencies.** None. **Product decision:** no.

---

### E-CHK-03 · P1 · functional · `weekly_checkins` has two column families; the writer and the readers use different ones
**Evidence:** `SRC` · **Layer:** database contract · **New**

| | Columns | Used by |
|---|---|---|
| **Baseline** (`000`:146) | `mood`, `energy`, `sleep_hours_avg` | the only writer (`submitWeeklyCheckin`) |
| **Migration 001** (`001`:32-39) | `energy_level`, `stress_level`, `sleep_hours`, `hunger_level`, `weight_kg`, `compliance_percent`, `notes`, `coach_id` | every reader |

`stress_level` and `notes` are the only two columns both sides agree on.

**Downstream, each independently broken:**
- `insights_provider.dart:75` reads `energy_level, sleep_hours, weight_kg` — three
  permanently `NULL` fields on the client's Insights panel.
- `trg_notify_coach_on_checkin` (`004`:154) builds the coach's notification body from
  `weight_kg`, `energy_level`, `compliance_percent` → **"Weight: —kg | Energy: —/5 |
  Compliance: —%"**. The coach is notified of nothing.
- `ai-coach/index.ts:78-82` interpolates the same fields into the Claude **system
  prompt** with no null guard: `Energy: ${latest.energy_level}/5` renders
  `Energy: undefined/5`. Product bible §6 forbids fabricating metrics; feeding a model
  `undefined` is worse than omitting the field.
- `ai_adjust_nutrition` (`079`:21) gates on `weight_kg` — never non-null, so it always
  returns at `v_n < 2`.

**Exact fix.** Pick one family as canonical, then: forward migration back-filling the
retired family from the canonical one, a `GENERATED`/trigger bridge or a view for the
transition, and update all four readers. Recommend the **`001` family** as canonical —
four readers depend on it against one writer, and it is the superset (it alone carries
`weight_kg`, `compliance_percent`, `hunger_level`).

**Dependencies.** Must land with or before E-CHK-01, or the repointed writer produces
rows the readers still cannot see. **Product decision:** no — this is a contract
choice, but the recommendation is unambiguous.

**Regression test.** For each of the four readers, a check-in written by the canonical
writer produces a non-null value; a guard test asserts writer keys ⊆ reader keys.

---

### E-CHK-04 · P1 · functional · The check-in form collects data it silently discards, and never collects weight
**Evidence:** `SRC` · **Layer:** service · **New**

`DailyCheckinScreen` renders a `_GoalToggle` for "worked out" and "hit water goal" and
passes both into `saveWeeklyCheckin(workedOut:, hitWaterGoal:)`
([checkin_service.dart:74-101](apps/mobile/lib/features/checkins/data/checkin_service.dart#L74)).
The method accepts both parameters and **includes neither in the insert map**. The
user answers two questions that go nowhere.

Separately, **no check-in surface anywhere collects weight**, so `weekly_checkins.weight_kg`
is structurally unfillable. Weight exists only in `weight_logs` (via `ProgressScreen`),
which `ai_adjust_nutrition` does not read.

**Exact fix.** Either persist `worked_out` / `hit_water_goal` (new columns or fold into
`compliance_percent`) or remove the controls. Add a weight field to the check-in form
writing `weekly_checkins.weight_kg` — **or** change `ai_adjust_nutrition` to source
its trend from `weight_logs`, which is already populated.

**Dependencies.** E-CHK-03. Gates any future work on E-NUT-17 / auto-adjustment.
**Product decision:** Q-E3 — is weight a check-in field or a `weight_logs` concern?

---

### E-CHK-05 · P2 · UX · `/checkins` is an appointments calendar filed and routed as check-in
**Evidence:** `SRC` · **Layer:** routing · **Corrects a prior finding**

`CheckinScreen` ([checkin_screen.dart:118](apps/mobile/lib/features/checkins/presentation/checkin_screen.dart#L118))
queries `coaching_calls` and renders a week-strip appointments calendar. It lives in
`features/checkins/`, is routed at `/checkins`, and `app_shell.dart:69` maps `/checkin*`
to the "Check-In" nav index. Two places push a user there expecting check-in:
`daily_checkin_screen.dart:262` and the dead `home_org.dart:65`. It duplicates
`/appointments` → `BookingScreen`.

**Exact fix.** Move it to `features/appointments/`, rename, route under `/appointments*`
or retire it in favour of `BookingScreen`; remove `/checkin` from the Check-In nav
prefix match; repoint `daily_checkin_screen.dart:262`.

**Dependencies.** Retirement in favour of `BookingScreen` needs a comparison that was
outside this workstream. **Product decision:** Q-E4.

---

### E-CHK-06 · P2 · functional · Placeholder screens on live routes
`CheckinFormScreen` (37 lines, a button to `/daily-checkin`) and `CheckinDetailScreen`
(23 lines, "Check-in details coming soon") are registered GoRoutes. Reachable only from
`CheckinCard`, itself orphaned — so unreachable in practice, but live in the route table
and therefore deep-linkable.
**Fix:** delete both routes and both files, or build `CheckinDetailScreen` against
`selectedCheckinProvider` as part of E-CHK-01's rewiring. **Product decision:** no.

---

### E-CHK-07 · P2 · functional (security-adjacent) · Coach check-in analysis silently analyses the coach's own data
**Evidence:** `SRC` · **Layer:** Edge Function

`AICoachService.analyzeCheckins(clientId)` sends `target_client_id`. The `ai-coach`
Edge function **never reads that field** — every one of its five context queries is
`.eq(…, user.id)`. A coach would receive an analysis of their own check-ins labelled as
their client's.

**This is not a live authorization hole and must not be reported as one.** It fails
closed, and the method has zero callers, so user impact today is nil.

**It is a trap.** The obvious fix — honour `target_client_id` — creates a real
cross-tenant read. Per the brief's security rule: **any change here must first verify
`is_active_coach_of(target_client_id)` server-side** (the `can_act_for()` predicate
migration `116` introduced is the right shape), and must derive the subject from
`auth.uid()` when the parameter is absent.

**Fix:** either delete `analyzeCheckins` (no callers) or, if the coach feature is
wanted, add the server-side authorization check **before** wiring the parameter.
**Product decision:** Q-E4 (is coach-side AI check-in analysis in scope for beta?).

---

### E-CHK-08 · P2 · functional · The in-app QA suite probes a table and column that do not exist
`qa_suites.dart:807` — `_mHasRow('Check-in submitted', 'checkins', 'client_id')`.
Wrong table *and* wrong key (`weekly_checkins` uses `user_id`). The Coach-Guided
journey reports a false failure. **Fix:** `('weekly_checkins', 'user_id')`.

---

### E-CHK-09 · P3 · functional · Re-submission semantics
`submitWeeklyCheckin` upserts `status: 'submitted'`. Re-submitting an already-`reviewed`
check-in reverts the status without clearing the coach's feedback, leaving a row that is
`submitted` yet carries `feedback_message` and `reviewed_at`. The `004` notify trigger is
`AFTER INSERT` only, so the coach is not told a client revised their answers.
**Fix:** decide whether re-submission is permitted; if so, clear review fields on
revert (service_role or a trigger, since `114` blocks client writes to them) and add an
`AFTER UPDATE` notification arm.

---

### E-CHK-10 · P3 · functional · Read paths mask failure
`hasCheckedInThisWeek`, `getCheckinStreak`, `getRecentCheckins`, `getWeeklyCheckins`,
`getCurrentWeekCheckin`, `getSubmittedCheckinsForCoach` all `catch → false / 0 / []`.
A missing table, an RLS denial, and "genuinely no check-ins" are indistinguishable.

**Correction to the prior characterisation:** the *write* path does **not** mask —
`saveWeeklyCheckin` returns `false` and `_submit` shows *"Failed to save. Please try
again."* The masking is on the read side only, which is what produces the "not checked
in yet, forever" symptom. Follow the pattern `activeWorkoutRestorationProvider`
establishes: propagate, render error + retry.

---

### E-CHK-11 · P3 · UX · The success dialog claims a notification that was never sent
`daily_checkin_screen.dart:_showSuccess` renders *"Your coach has been notified about
your levels"* from a purely client-side `needsCoachAttention(energy ≤ 2 || stress ≥ 4)`
inference. No notification is sent on that path. The real notification is the
unconditional `004` DB trigger on `weekly_checkins` INSERT, which has nothing to do
with the threshold and (per E-CHK-01) never fires.
**Fix:** either implement threshold-based escalation server-side or remove the claim.

---

## 5. Defect register — NUTRITION

### E-NUT-01 · P1 · functional · Barcode scans record per-100 g macros as one serving
**Evidence:** `SRC` · **Layer:** service + UI · **Corroborates:** CON-09

`lookupBarcode` ([nutrition_service.dart:216-259](apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L216))
reads `calories_per_100g` / `protein_per_100g` / … and returns them under the
unqualified keys `{calories, protein, carbs, fat}`. `_logFromBarcode`
([meals_dashboard_screen.dart:849](apps/mobile/lib/features/nutrition/presentation/meals_dashboard_screen.dart#L849))
writes those values with `servingSize: 1, servingUnit: 'serving'`.

A 28 g protein bar scans as ~100 g of it. The record is also internally inconsistent:
`amount_g = 1` alongside macros for 100 g. Every downstream number — the macro rings,
adherence %, `proteinGoalHit`, `nutritionDayComplete`, the coach's view, the AI's
remaining-macro math — inherits the error.

**Root cause.** The unit is dropped at the type boundary: `lookupBarcode` returns
`Map<String, dynamic>` rather than a `Food` (which carries `servingSize`/`servingUnit`)
and there is no quantity prompt between scan and log.

**The test suite locks the bug in.** `spec_nutrition_logic_test.dart:34`
(`barcodeToMealLog`) reproduces exactly the defective mapping and asserts it correct.
The *correct* algorithm exists in the same file at line 8 (`macrosFromFood`, per-100 g
→ per-serving) and is used **nowhere in production**.

**Exact fix.** Return a `Food` with `servingSize: 100, servingUnit: 'g'`; route barcode
hits through the same `_FoodDetail` quantity sheet manual search uses; require a
quantity before a log entry can be produced. Delete `barcodeToMealLog` from the test and
replace it with a test that imports the real path.

**Dependencies.** None. **Product decision:** no.
**Regression test.** A 220 kcal/100 g barcode logged at 28 g records 61.6 kcal and
`amount_g = 28`, `serving_unit = 'g'`.

---

### E-NUT-02 · P1 · functional · No edit or delete path, although the database grants both
**Evidence:** `SRC` · **Layer:** service + UI · **Corroborates:** CON-07 (second half)

Zero `.update(` and zero `.delete(` calls in `features/nutrition/` or
`features/ai_nutrition/`. `nutrition_logs` RLS is `FOR ALL TO authenticated USING
(user_id = auth.uid())` (`006`:24, re-asserted `111`:47) and `authenticated` holds the
table grant, so owner UPDATE and DELETE are permitted at the database.

A mis-scanned meal — and given E-NUT-01 every barcode scan is one — is permanent.

**Reconciliation with product bible §2.6 ("completed history is immutable").** Nutrition
logs are *user-entered records*, not engine decisions. The immutability principle
protects the engine's record, not a user's typo. A correction path is in scope, and it
should be an explicit audited correction mirroring `applyCorrection` + migration `111`,
not a silent overwrite.

**Exact fix.** `NutritionService.updateLog(id, …)` / `.deleteLog(id)`; swipe-to-delete
and tap-to-edit on `_MealCard`; re-run `_awardNutritionScore()` after either;
`ScoreEngine` must reverse the `mealLogged` award on delete (see E-NUT-10 — the dedup
key must become stable first).

**Dependencies.** E-NUT-10 (stable dedup key). **Product decision:** Q-E2 — audited
correction row vs plain mutation.

---

### E-NUT-03 · P1 · functional · A meal logged on a past date is written to today and then disappears
**Evidence:** `SRC` · **Layer:** service + UI · **Corroborates:** CON-06 + CON-07

`MealsDashboardScreen._showAddSheet` does not pass `_selectedDate` to `_AddMealSheet`,
and `logMeal` hardcodes `'logged_at': DateTime.now().toIso8601String()`
([nutrition_service.dart:63](apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L63)).

The failure is doubly silent: the row lands on today, **and** the screen then invalidates
`_logsForDateProvider(_selectedDate)` — the past date — which cannot contain it. The
user sees a success dialog and an unchanged, empty list.

Compounded by RC-8: `getLogsForDate`/`getTodayTotals` construct local-midnight
`DateTime` bounds and compare them to a `timestamptz` column with no UTC conversion, so
even correctly dated rows fall outside the window by the local offset.

**Exact fix.** Add a `DateTime loggedAt` parameter to `logMeal`; thread `_selectedDate`
through `_showAddSheet` → `_AddMealSheet` → all three log paths; convert day bounds to
UTC via the shared helper RC-8 introduces. Disallow future dates.

**Dependencies.** Belongs with step 3C of the execution plan (RC-8, ~60 call sites).
**Product decision:** no.

---

### E-NUT-04 · P1 · functional · The AI meal-suggestion engine reads nutrition columns that do not exist
**Evidence:** `SRC` · **Layer:** Edge Function · **New**

[`ai-coaching-engine/index.ts:148`](supabase/functions/ai-coaching-engine/index.ts#L148)
selects `calories, protein_g, carbs_g, fat_g` from `nutrition_logs`. The table's columns
are `calories, protein, carbs, fat` (`012`/`014`). PostgREST rejects the select
(`42703`), `todays` is `null`, every `sum()` returns 0, and:

```
remaining_calories = calories_target − 0 = the full daily target
```

Every `meal_suggestion` is generated as if the user has eaten nothing, all day, every
day. The error is swallowed by destructuring `{ data: todays }` without checking
`error`.

**Exact fix.** `select('calories, protein, carbs, fat')` and key `sum()` on the same
names. Check the PostgREST `error` and fail loudly rather than computing from `null`.
Add a schema-drift guard test that asserts the Edge Function's column list against the
migration DDL.

**Dependencies.** None. **Product decision:** no.

---

### E-NUT-05 · P1 · **safety** · Allergies and dietary restrictions never reach the AI meal-plan generator
**Evidence:** `SRC` · **Layer:** UI + API · **Supersedes and escalates CON-08**

`MealPlanScreen._restrictions` initialises to `[]`
([meal_plan_screen.dart:23](apps/mobile/lib/features/ai_nutrition/presentation/meal_plan_screen.dart#L23))
and is populated **only** by six hard-coded chips (`Vegetarian, Vegan, Gluten-Free,
Dairy-Free, Nut-Free, Halal`) that the user must re-select on that screen.

`user_profiles.dietary_restrictions` and `user_profiles.food_allergies` (`013`:15-16)
are collected at intake (`intake_flow_screen.dart:433`, including a **free-text allergy
field**) and are read by the coach's client-detail screen — but `_loadGoalsOnce` loads
macro targets and nothing else. There is **no provider, no query, and no code path**
that carries the user's declared allergies into `generateMealPlan`.

A client who wrote "peanuts, shellfish" at intake receives a plan generated from
`Dietary restrictions: None`.

Secondarily — and this is the part CON-08 already recorded — even when restrictions
*are* selected they are passed as free prose
([ai_nutrition_service.dart:124](apps/mobile/lib/features/ai_nutrition/data/ai_nutrition_service.dart#L124)),
and neither `apps/api/src/ai/` nor the client validates the response. The free-text
allergy field has no representation in the six chips at all.

**Root cause.** The meal-plan screen was built as a standalone generator with its own
inputs, disconnected from the intake profile, and nothing enforces that a safety-bearing
input is present.

**Exact fix.**
1. Load `dietary_restrictions` + `food_allergies` from `user_profiles` into
   `MealPlanScreen`, non-removable, shown to the user as locked context.
2. Send allergies as a distinct, emphatic constraint — not merged into "restrictions".
3. Add a deterministic post-generation allergen guard: scan the returned plan against
   the declared allergen terms and their common synonyms; on a hit, refuse to display
   and regenerate or fail closed. This is the "deterministic first" half of the bible's
   principle #7 and the only part that does not depend on model compliance.
4. Same treatment for `ai-coach` in `nutrition` mode, which grounds on the profile but
   does not surface allergies either.

**Dependencies.** CON-03 (`dietary_restrictions` has two serialisations —
`intake_data.dart:213` writes a `List`, `:252` writes a comma-joined `String`) must be
converged first or the load will be type-unstable. CON-02 (onboarding must not mark
itself complete on a failed save).
**Product decision:** **Q-E5** — does the allergen guard block the plan or annotate it?

---

### E-NUT-06 · P1 · architecture · Nutrition operates outside the "engine decides, AI explains" boundary
**Evidence:** `SRC` · **Layer:** architecture · **New**

Four concrete boundary crossings, in ascending order of consequence:

1. **No decision trace.** No nutrition path writes a `decision_traces` row. Product
   bible principle #2 ("nothing reaches a user without a recorded decision trace") is
   unenforceable for the entire subsystem.
2. **Unconstrained generation.** Meal plans and grocery lists are free-text LLM output
   with no deterministic engine, no brief, no certified-knowledge constraint, and no
   coach approval — including for coach-guided clients, which §6 explicitly forbids.
3. **LLM output becomes a deterministic input.** `analyzeFood`'s estimate is written to
   `nutrition_logs` as fact and then consumed by the deterministic 12 Circle Score
   (`addNutritionPoints`, `proteinGoalHit`, `nutritionDayComplete`). The score is no
   longer derived only from recorded facts.
4. **No provenance flag.** A `nutrition_logs` row carries no indication of whether its
   macros came from a curated database, a barcode, a user's typing, or a vision model
   guess. A coach reviewing the log cannot tell.

**Exact fix (staged, and the staging matters).**
- *Minimum, no product decision needed:* add a `source` column to `nutrition_logs`
  (`manual` | `catalog` | `barcode` | `ai_estimate`) plus `confidence` for the AI path;
  surface it in the UI and to the coach; exclude or down-weight `ai_estimate` rows in
  the deterministic score until confirmed by the user.
- *Full alignment:* route meal-plan generation through a deterministic planner that
  selects from certified foods against the client's targets and constraints, records a
  decision trace, and uses the LLM only to narrate the result — the pattern
  `explain-decision` already establishes.

**Dependencies.** The full fix is a Phase 4 item and depends on E-NUT-05.
**Product decision:** **Q-E6** — this is the largest gap between the nutrition subsystem
and the stated architecture, and how far to close it before beta is not my call.

---

### E-NUT-07 · P2 · security / cost · `/meal-plan` and `/grocery-list` bypass the AI paywall
**Evidence:** `SRC` · **Layer:** routing

`/ai-nutrition` is wrapped in `PaywallGate(required: ClientPlan.aiGuided)`
([app_router.dart:244](apps/mobile/lib/core/router/app_router.dart#L244)). The two
screens it links to are **bare** `GoRoute`s (`:246`, `:247`). On the Flutter web build
the URL bar reaches them directly; on mobile a deep link does. Both spend the
server-held Anthropic key.

The API tier authenticates correctly but does **not** rate-limit and does **not** check
the caller's plan — `AiController` has no throttler and `NutritionMessageDto` caps
per-request size only. A free-tier account can generate unlimited 7-day plans.

**Exact fix.** Wrap both routes in `PaywallGate(required: ClientPlan.aiGuided)`; add a
per-user rate limit on `POST /ai/nutrition/message` (NestJS `ThrottlerGuard`), and
enforce the plan server-side — a client-side gate is a UX affordance, not a control.

**Dependencies.** None. **Product decision:** no (limits are a config choice).

---

### E-NUT-08 · P2 · security / data integrity · Any authenticated user can poison the shared barcode cache
**Evidence:** `SRC` · **Layer:** database

`foods` (`003`:162) has `INSERT … WITH CHECK (true)` for `authenticated` and no
`UPDATE`/`DELETE` policy. `lookupBarcode` consults `foods` **before** OpenFoodFacts, so a
forged row wins permanently for every user of that barcode — with no refresh path
(E-NUT-09) and no provenance column.

Migration `118`:48 explicitly accepted `foods`' `USING (true)` **SELECT** policy as
shared-catalog read. **The unrestricted INSERT is a different policy and is not covered
by that acceptance** — it is a write surface on data every user's macro tracking depends
on.

**Exact fix.** Add `created_by uuid DEFAULT auth.uid()` and `source text`; restrict
INSERT to `created_by = auth.uid()`; make `lookupBarcode` prefer `source = 'openfoodfacts'`
/ service-role-seeded rows over user-contributed ones, or move caching to a service-role
Edge Function so the client never writes `foods` at all (the cleanest option, and it
fixes E-NUT-09 for free).

**Dependencies.** Coordinate with E-NUT-09 — same table, one migration.
**Product decision:** no.

---

### E-NUT-09 · P2 · functional · The barcode cache can never refresh, and fails silently
`_cacheFoods` uses `.upsert(rows, onConflict: 'barcode')`
([nutrition_service.dart:209](apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L209)).
With no `UPDATE` policy on `foods`, the conflict arm is denied (`42501`) and the whole
statement aborts. `catch (_) {}` swallows it. In `searchFoodsOnline` a batch of up to 25
rows fails **wholesale** as soon as one barcode is already cached — so after the first
few searches, caching stops working entirely and nobody finds out.
**Fix:** absorbed by E-NUT-08's service-role caching path; otherwise add an UPDATE
policy and stop swallowing the error. **Product decision:** no.

---

### E-NUT-10 · P2 · functional · Meal-log scoring is not deduplicated
`logMeal` calls `ScoreEngine().mealLogged(DateTime.now().microsecondsSinceEpoch.toString())`
([nutrition_service.dart:66](apps/mobile/lib/features/nutrition/data/nutrition_service.dart#L66)).
`ScoreEngine.mealLogged` builds `dedupKey: 'meal:$mealId'` — designed around a **stable**
meal identifier. A fresh timestamp makes every key unique, so the server-side dedup never
engages: the same meal logged N times awards 5N points. Note `addNutritionPoints` *is*
idempotent (it sets rather than increments), so only the `ScoreEngine` award leaks.
**Fix:** return the inserted row's `id` from `logMeal` and pass it as `mealId`. This is
also a prerequisite for reversing the award on delete (E-NUT-02).

---

### E-NUT-11 · P2 · functional · AI meal plans and grocery lists are never persisted
`MealPlanNotifier` and `GroceryListNotifier` hold `String?` in memory
([ai_nutrition_provider.dart:101,138](apps/mobile/lib/features/ai_nutrition/domain/ai_nutrition_provider.dart#L101)).
No table, no row, no reload; a 7-day plan is gone on app restart or provider disposal.
There is also no bridge from a generated plan into `nutrition_logs` — the user must
re-enter every meal by hand.
**Fix:** a `meal_plans` table (owner + active-coach RLS) storing the structured plan;
parse the generation into a model at the boundary rather than line-scraping prose in
`GroceryListScreen._parseGroceryList`; add "log this meal" from a plan entry.
**Product decision:** Q-E6 (scope) — a structured plan model is a prerequisite for the
deterministic planner.

---

### E-NUT-12 · P2 · functional · Generation errors become content, and the spinner never spins
On failure `MealPlanNotifier.generateMealPlan` sets `state` to the literal
`'Error generating meal plan. Please try again.'`. `GroceryListScreen._generateList`
then passes that string to Claude as *"Based on this meal plan…"*, spending a request to
build a grocery list from an error message. Separately, `isLoading` is a plain field on
both notifiers, **outside** `state`, so mutating it never triggers a rebuild — the
screens compensate with a second local `_isLoading`, which works only because
`_generatePlan` awaits.
**Fix:** model the notifier state as `AsyncValue<MealPlan>`; guard `_generateList`
against a non-plan state.

---

### E-NUT-13 · P2 · functional · The AI-scan portion multiplier is dropped from the record
`ai_scan_view` scales macros by `_portion` (0.25×–3.0×) before `onAccept(disp)`, but
`_logFromScan` writes `servingSize: 1, servingUnit: 'serving'`
([meals_dashboard_screen.dart:823](apps/mobile/lib/features/nutrition/presentation/meals_dashboard_screen.dart#L823)).
A 2.5× portion is recorded as one serving. Macros are correct; the quantity is not — so
the record cannot be re-derived or corrected. Same class as E-NUT-01, lower severity.
**Fix:** pass the multiplier as `servingSize` with `servingUnit: 'serving'`.

---

### E-NUT-14 · P2 · functional · Water tracking is decorative
`_water` is local `setState` in both `meals_dashboard_screen.dart:44` and
`nutrition_screen.dart:31` — never written anywhere, reset on every rebuild.
`client_nutrition_plans.water_target_oz` (`034`) is coach-settable via
`client_detail_screen` and read by **no** client surface — the card is hardcoded to
8 glasses. `ScoreEngine.waterGoalHit()` is reachable only through a habit whose name
happens to contain "water".
**Fix:** persist water intake; read `water_target_oz` as the goal; wire `waterGoalHit`.
Or remove the card. **Product decision:** Q-E7 — is water tracking in scope for beta?

---

### E-NUT-15 · P2 · functional · Two nutrition dashboards of unequal capability, one orphaned
`MealsDashboardScreen` (`/meals-dashboard`) has barcode scan, AI scan, a date strip,
cached + online food search, the coach card and the water card. `NutritionScreen`
(`/nutrition-overview`) is an earlier build with **none** of it — still routed, still
`PaywallGate`d, reachable only from the QA suite's route list. `/food-search` and
`/log-meal` are 23-line redirect stubs kept alive for the same list.
**Fix:** retire `NutritionScreen`, `FoodSearchScreen`, `LogMealScreen` and their routes;
update `qa_suites.dart:235-239`. Verified redundant: `MealsDashboardScreen` is a strict
superset, and nothing but the QA route table references them.

---

### E-NUT-16 · P3 · security · Unvalidated media type forwarded to a paid credential
`ai_scan_view._analyze` may compute `'image/heic'`;
[`analyze-food-image/index.ts:60`](supabase/functions/analyze-food-image/index.ts#L60)
forwards `mediaType` straight to Anthropic, which accepts only `jpeg`/`png`/`gif`/`webp`.
Reachability is low (`imageQuality: 80` makes `image_picker` re-encode to JPEG) so this
is unlikely to be a live iOS failure — but it is an unvalidated client-supplied value on
a path that spends money, and the NestJS tier validates the same field correctly
(`SUPPORTED_IMAGE_MEDIA_TYPES`). The Edge Function should match.
**Fix:** allow-list `mediaType` in the Edge Function; drop the `heic` branch client-side.

---

### E-NUT-17 · P3 · security (latent) · `ai_adjust_nutrition` is dead code carrying a stale grant
**See §6.** Kept at P3 because there is no live exposure; it is a replay-ordering and
maintenance hazard, not a current hole. Its promotion path is what matters.

---

## 6. ⚠️ Security rule compliance — `ai_adjust_nutrition(p_uid)`

The brief's standing rule: *if an existing function accepts a subject UUID, verify
`auth.uid()` authorization before proposing any schema or behaviour change that could
make it more powerful.* This function is the reason that rule exists. Findings:

**1 · The function body contains no authorization check of any kind.**
[`079_nutrition_autoadjust_and_coach_signals.sql:7-63`](supabase/migrations/079_nutrition_autoadjust_and_coach_signals.sql#L7)
is `SECURITY DEFINER`, takes `p_uid uuid`, trusts it unconditionally, and **writes** —
it rewrites that user's active `client_nutrition_plans` calories and macros and inserts
an `ai_insights` row. It has no `SET search_path`.

**2 · The exposure is closed, but only by privilege.** Migration `116` revoked `EXECUTE`
schema-wide from `PUBLIC`, `anon` and `authenticated`, then re-granted from an explicit
allowlist. `ai_adjust_nutrition` is **not on that allowlist** — it is treated as class D
(service-role/engine only). That is a correct and deliberate decision. Contrast with
`generate_workout`, `create_weekly_review`, `record_prediction` and `predict_client`,
which `116` gave in-body `can_act_for()` guards **and** kept on the allowlist.

**3 · The stale grant still stands in the tree.**
`079:65` — `grant execute on function public.ai_adjust_nutrition(uuid) to authenticated,
service_role;` — was never removed or commented. Any replay, environment rebuild, or
selective re-application that runs `079` after `116` **silently re-opens the hole**.
`ALTER DEFAULT PRIVILEGES` does not protect against an explicit `GRANT`. This is
precisely the failure mode `116`'s own header warns about for `is_active_coach_of`:
*"Revoking PUBLIC alone is proven insufficient here."*

**4 · The function is entirely dead.** Zero callers: not `ai_cron_generate` (`076`), not
`ai_cron_accountability` (`080`), not any of the 19 Edge Functions, not the NestJS API,
not the Flutter client. Grepped the whole tree.

**5 · Its only input is structurally unfillable.** It gates on ≥2 `weekly_checkins` rows
with non-null `weight_kg` in 35 days. Nothing writes `weight_kg` to that table and no
check-in UI collects weight (E-CHK-04). It could not fire even if called.

**6 · The previously reported "incorrect schema reference" is NOT REPRODUCED — again.**
`weekly_checkins.weight_kg` (`001`:33) and `created_at` (`000` baseline) both exist, as
do `user_profiles.fitness_goal`/`goal`. The master document reached the same conclusion.
A schema defect of this exact shape **does** exist in the nutrition subsystem, but it is
in `ai-coaching-engine` (E-NUT-04), not here.

### Mandatory sequencing before this function is touched

**Do not add a caller, restore a grant, change the schema it reads, or "fix" it to use
`weight_logs` until all three of the following are true:**

1. It derives its subject: `p_uid uuid DEFAULT NULL`, `v_uid := COALESCE(p_uid,
   (SELECT auth.uid()))`, then `IF NOT public.can_act_for(v_uid) THEN RAISE EXCEPTION …
   USING ERRCODE = '42501'; END IF;`. `can_act_for` (migration `116`) already encodes
   exactly the right predicate, including the `auth.uid() IS NULL` engine arm.
2. `SET search_path = public, pg_temp` is added — it is one of the definer functions
   `116` was meant to pin.
3. `079:65`'s grant is neutralised by a forward migration (`REVOKE EXECUTE … FROM
   authenticated`) **and** `079` carries an in-place comment pointing at it, matching the
   convention migration `111` established for `076`.

`can_act_for` is only trustworthy because migration `113` closed
`coach_client_relationships`. **SEC-01 remains a hard prerequisite**, exactly as the
execution plan's step 1E states.

---

## 7. Reconciliation with the known findings and prior reports

| # | Reported finding | Verdict |
|---|---|---|
| 1 | Check-In navigation previously targeted `public.checkins` | **CONFIRMED.** Still true today, on the live route. Six call sites in `checkin_service.dart` plus `coach_dashboard_screen.dart:108` and `qa_suites.dart:807`. → E-CHK-01, E-CHK-08 |
| 2 | `public.checkins` was reported nonexistent | **CONFIRMED** from source across `000`–`121`. Consistent with the inherited live `PGRST205`. |
| 3 | A working `/checkins` screen existed but was orphaned | **CORRECTED — materially wrong.** `/checkins` → `CheckinScreen` is **not a check-in screen**: it queries `coaching_calls` and renders an appointments calendar. It is *not* orphaned either — two entry points reach it, one of them from inside the check-in flow. The genuinely orphaned check-in code is the *service layer*: `submitWeeklyCheckin` and ten other symbols have zero callers. → E-CHK-05, E-CHK-02 |
| 4 | Nutrition auto-adjustment had an authorization/schema concern | **SPLIT.** *Authorization* — **CONFIRMED and closed by privilege only**, with a live replay hazard (§6). *Schema* — **NOT REPRODUCED** in `079`, for the second independent time. A real schema defect of that shape exists at `ai-coaching-engine/index.ts:148` (E-NUT-04). A third, worse problem is new: the function is dead and its input column is never written. → E-NUT-17, E-NUT-04, E-CHK-04 |
| 5 | Barcode scanning had serving-unit correctness concerns | **CONFIRMED**, and worse than recorded: the defect is present in the *logging* path, not just the lookup return, and the test suite asserts the defective mapping as correct. → E-NUT-01 |
| 6 | Nutrition lacked edit/delete UX despite database capability | **CONFIRMED** exactly as stated. Zero `.update(`/`.delete(` in either nutrition feature; `FOR ALL` RLS + table grant permit both. → E-NUT-02 |
| 7 | AI nutrition includes meal planning/grocery/auto-adjustment beyond meal scan | **CONFIRMED**, and the surface is larger than the phrasing suggests: five distinct AI paths across two backends (NestJS `/ai/nutrition/message`; Edge `analyze-food-image`, `ai-coach`, `ai-coaching-engine`) plus one dead RPC. None writes a decision trace; none is deterministic; two have no paywall. → E-NUT-06, E-NUT-07, E-NUT-11 |

### Master-document ID mapping

| Master ID | This workstream | Change |
|---|---|---|
| CON-01 | E-CHK-01 (+02, +05, +08) | Confirmed; scope widened; prior "orphaned screen" reading corrected |
| CON-05 | E-NUT-17 (+E-NUT-04) | Authorization closed by privilege only; schema half re-confirmed NOT REPRODUCED in `079` |
| CON-06 | E-NUT-03 | Confirmed; the silent-disappearance mechanism is new |
| CON-07 | E-NUT-02, E-NUT-03 | Confirmed unchanged |
| CON-08 | **E-NUT-05 (escalated)** | Restrictions do not merely go unvalidated — allergies never reach the prompt at all |
| CON-09 | E-NUT-01 | Confirmed; test-suite lock-in is new |
| SEC-03 / D-03 | §2.8 | **Source-correct as of `114`+`118`. Requires a live QA probe before it is marked closed.** |
| SEC-04 | §6 | `ai_adjust_nutrition` half closed by allowlist omission, not by an in-body guard; `079`'s grant is a live replay hazard |

**Not reproduced anywhere in this workstream:** any live cross-tenant read or write in
the nutrition or check-in subsystems. The one subject-UUID surface that remains reachable
by a client (`ai-coach`'s `target_client_id`) fails **closed**.

---

## 8. Product decisions required

**Q-E1 · Is `CheckinService`/`public.checkins` retired, or is a daily check-in a real requirement?**
*Blocks:* E-CHK-01. *Evidence:* no table, no column, no migration, no product-bible
mention; every user-visible label already says "Weekly"; the "daily" methods have zero
callers; `getCheckinStreak` computes a daily streak that a weekly cadence can never
satisfy. **The architecture proves the duplicate is redundant** — which is the bar the
brief set. *Recommendation:* **retire** `CheckinService`, migrate all callers to
`WeeklyCheckinService`/`weekly_checkins`. Low risk: the retired path has never
successfully written a row, so no user data is affected. *This is a confirm, not an open
question — but it changes user-visible behaviour, so it needs your word.*

**Q-E2 · Nutrition correction: audited correction row, or plain mutation?**
*Blocks:* E-NUT-02. Product bible §2.6 says completed history is immutable; nutrition
logs are user-entered records rather than engine decisions, so a correction path is in
scope. The question is whether it mirrors migration `111`'s `applyCorrection` pattern
(original preserved, correction recorded, coach can see both) or is a simple
UPDATE/DELETE. *Recommendation:* audited correction — a coach reviewing adherence needs
to see that a 2 400 kcal day was edited down to 1 400 after the fact.

**Q-E3 · Is weight a check-in field, or a `weight_logs` concern?**
*Blocks:* E-CHK-04, and any revival of nutrition auto-adjustment. `weekly_checkins.weight_kg`
exists and is read by four consumers but is collected nowhere; `weight_logs` is populated
by `ProgressScreen` and read by neither `ai_adjust_nutrition` nor the coach's check-in
view. *Recommendation:* add weight to the check-in form (it is the natural weekly cadence
and the coach review screen already expects it) **and** point `ai_adjust_nutrition` at
`weight_logs` as a fallback. But one source must be declared canonical.

**Q-E4 · Are `/checkins` (appointments calendar) and coach-side AI check-in analysis in scope for beta?**
*Blocks:* E-CHK-05, E-CHK-07. Both are working-or-nearly-working code with no clear
product owner. `/checkins` overlaps `/appointments`; `analyzeCheckins` has no caller and
its activation requires a server-side authorization change first (§6 pattern).
*Recommendation:* move `/checkins` out of the check-in feature and adjudicate against
`BookingScreen` separately; delete `analyzeCheckins` until the coach-side AI story is
designed.

**Q-E5 · Does the allergen guard block a generated plan, or annotate it?**
*Blocks:* E-NUT-05. A deterministic post-generation scan will produce false positives
("nut-free" contains "nut"; "coconut" is not a tree nut for most allergy purposes).
Blocking is safer and more annoying; annotating is friendlier and shifts risk to the
user. *This is a genuine safety-policy decision and I will not manufacture it.* My
engineering input: whatever is chosen, the declared allergies must reach the prompt
first — that fix is unconditional and does not wait on this answer.

**Q-E6 · How far does nutrition move toward "the engine decides, AI explains" before beta?**
*Blocks:* the full form of E-NUT-06, E-NUT-11. The minimum (a `source`/`confidence`
column so an LLM estimate is never silently indistinguishable from a measured value,
and is excluded from the deterministic score until confirmed) is cheap and I recommend
it regardless. A deterministic meal planner with recorded decision traces is a Phase 4
engine, and the product bible §7 explicitly says new foundational engines are not
pre-beta work. *Recommendation:* do the minimum now, schedule the planner post-beta,
and stop describing generated plans as coaching output in the interim.

**Q-E7 · Is water tracking in scope for beta?**
*Blocks:* E-NUT-14. Coaches can already set `water_target_oz` and the UI shows a water
card, so the product currently *promises* the feature. Either wire it (small) or remove
the card (smaller). *Recommendation:* wire it — the coach-facing half already exists and
a visible-but-inert control is worse than no control.

---

## 9. Proposed remediation sequencing

Slots into the existing execution plan without reordering its phases.

| Step | Items | Notes |
|---|---|---|
| **1C-verify** | §2.8 | Live-probe `weekly_checkins` RLS in QA before SEC-03 is marked closed. Source is correct; the plan's own rule requires the live check. |
| **1E-amend** | E-NUT-17 | Forward `REVOKE EXECUTE ON ai_adjust_nutrition FROM authenticated` + `SET search_path`; in-place comment on `079` pointing at it. Add a standing test that no `public` routine is `authenticated`-executable outside `116`'s allowlist. **Do not add the `can_act_for` guard yet — no caller needs it, and adding one invites re-granting.** |
| **3A (existing)** | CON-03 | Prerequisite for E-NUT-05. |
| **3C (existing)** | E-NUT-03 | Folds into the RC-8 sweep. `logMeal` gains a real date parameter. |
| **3D (existing)** | E-CHK-01, 02, 03, 04, 08, 10, 11 | **One change, one root cause.** Order within it: E-CHK-03 (column contract) → E-CHK-01 (rewire) → E-CHK-04 (fields) → delete orphans → fix QA suite → propagate read errors. Blocked on **Q-E1** and **Q-E3**. |
| **3E (existing)** | E-NUT-01, E-NUT-13 | Keep the unit in the type; a quantity is required to produce a log entry. Rewrite `spec_nutrition_logic_test.dart` to import the real path. |
| **3F (existing)** | **E-NUT-05** | **Escalate within 3F: loading the profile's allergies is unconditional and does not wait on Q-E5.** The guard's block-vs-annotate behaviour does. |
| **3J (new)** | E-NUT-02 | Nutrition correction path. Blocked on **Q-E2**; depends on E-NUT-10. |
| **3K (new)** | E-NUT-04, E-NUT-08, E-NUT-09, E-NUT-10 | Data-contract and integrity cluster: Edge Function column names, `foods` write surface, cache refresh, score dedup. Independent of everything above; can run in parallel. |
| **3L (new)** | E-NUT-07 | Paywall the two AI routes; rate-limit the API. Small, independent, do it early. |
| **Hygiene** | E-CHK-05, 06, 09; E-NUT-11, 12, 14, 15, 16 | Dead-route and dead-code removal; notifier state modelling. Blocked on **Q-E4**, **Q-E7**. |
| **Phase 4** | E-NUT-06 | Architecture alignment. Blocked on **Q-E6**. |

---

## 10. Standing regression tests this workstream requires

Each must **fail before** the fix and **pass after**.

**Check-in**
1. A check-in save whose target table is unreachable **raises** — it does not return `false` into a snackbar and it does not return `[]`.
2. A saved check-in is readable back through the same week window; a second save in the same week updates rather than duplicating (`user_week_unique`).
3. Writer keys ⊆ reader keys: a guard test enumerating every column `submitWeeklyCheckin` writes against every column `insights_provider`, `004`'s trigger, `ai-coach`, and `079` read. No `NULL` on either side of the contract.
4. The coach queue count equals submitted check-ins for that coach's **active** clients, and zero for a coach with none.
5. Boundary (live QA): anon read/insert/delete on `weekly_checkins` rejected; an unrelated authenticated user reads 0 rows; a client cannot write `feedback_message` or set `status='reviewed'`; an active coach can write only the six review columns.
6. No `public` routine is `authenticated`-executable outside migration `116`'s allowlist — and `ai_adjust_nutrition` is specifically asserted absent from it.

**Nutrition**
7. A 220 kcal/100 g barcode logged at 28 g records **61.6 kcal**, `amount_g = 28`, `serving_unit = 'g'`. Written against the real `lookupBarcode`→`logMeal` path, not a replica.
8. A meal logged while a past date is selected lands on **that date** and appears in that date's list. Future dates are rejected.
9. A logged meal can be edited and deleted; totals and the day's score recompute; the `ScoreEngine` award is reversed on delete.
10. A profile carrying `food_allergies = 'peanuts'` produces a meal-plan request whose prompt contains that allergen constraint — asserted on the outbound request body, not the model's reply.
11. `ai-coaching-engine`'s `remaining_*` reflects rows already logged today; a column-drift guard asserts its select list against the `nutrition_logs` DDL.
12. `/meal-plan` and `/grocery-list` are unreachable for a non-`aiGuided` plan, and the API rejects an over-rate caller.
13. A second authenticated user cannot overwrite a `foods` row another user created.
14. The same meal logged twice awards `mealLogged` points once.

---

## 11. Scope statement — what this workstream did not do

- **No environment was contacted.** No QA probe, no production probe, no writes anywhere. Every `LIVE` claim reproduced here is attributed to the master document.
- **No code was changed.** Discovery only, per the brief.
- **Nothing was retired.** E-CHK-05's `/checkins` overlap with `BookingScreen` and Q-E4's coach-AI question are flagged, not adjudicated — retirement needs a dependency analysis of `BookingScreen` that was outside this scope.
- **The 12 Circle Score engine was audited only where nutrition and check-in feed it.** `ScoreService`/`ScoreEngine` internals belong to another workstream.
- **Onboarding was audited only at the boundary** where `dietary_restrictions` / `food_allergies` enter nutrition. CON-02 and CON-03 remain owned by steps 3A/3B.
- **`claude-sonnet-4-6` was verified as a valid current model ID** before it could be mis-reported as a defect. `analyze-food-image` uses Sonnet 4.6, `ai-coach` uses Haiku 4.5, the NestJS default is Sonnet 4.6 — all valid. Whether to move any of them to a newer model is a cost/quality choice, not a defect, and is not raised as one.
