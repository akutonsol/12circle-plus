# 12 Circle Fitness — Screen Data Requirements

**Read-only audit deliverable.** Baseline `fbee6d5`. Source analysis only — **no database
was contacted**, neither QA nor production.

---

## 1 · The data surface

| Measure | Count |
|---|---|
| Feature modules | 34 |
| Riverpod provider declarations | 234 |
| Supabase access call sites | **529** (386 literal table, 46 dynamic, 53 RPC, 22 invoke, 22 storage) |
| Distinct tables/views the app touches | 77 |
| Distinct RPCs called | 49 |
| Edge functions invoked | 16 of 19 on disk |
| Tables created in migrations | 91 (+5 views) |
| Functions created in migrations | 123 |
| Tables with seed rows | 34 |

**Method caveat, stated because it affects every row below:** screen→table resolution is
**class-level, not method-level**. A screen touching one method of a fat service is credited
with every table that class reaches. It also does not follow into child widgets in other
files. Treat per-screen table lists as an upper bound.

---

## 2 · Gap 1 — called but does not exist

Triple-checked: `create table` grepped across all 132 migrations, then the bare identifier
grepped across the whole `supabase/` tree, then cross-checked against the repo's own
`supabase/tests/contract/known-violations.json`.

### 2.1 Missing tables — 2

| Table | Called from | Impact |
|---|---|---|
| **`checkins`** | `checkins/data/checkin_service.dart:19` (insert), `:43`, `:63`, `:87` (insert), `:113`, `:142`; `dashboard/presentation/coach_dashboard_screen.dart:113` (select) | **`/daily-checkin` submits to a table that does not exist.** `weekly_checkins` exists and is a *different* table. Logged as finding I-CHK-01 |
| **`coach_tips`** | `coach/domain/coach_provider.dart:66` | The Home coach-tip card silently never appears — the error is swallowed at `coach_provider.dart:74`. Logged as I-LEG-03 |

### 2.2 Missing column — 1

| Column | Called from | Impact |
|---|---|---|
| `event_registrations.ticket_code` | `vendor/data/vendor_service.dart:43` | `/vendor-portal` attendee list. The table has `qr_code` (`001_full_ecosystem.sql:285`); **no migration ever adds `ticket_code`**. Logged as I-COM-01 |

### 2.3 Missing RPCs / edge functions — none

All 49 RPCs resolve, including `get_or_create_conversation`
(`131_identity_constraints.sql:303`, which only appears with a multi-line-safe grep). All 22
`functions.invoke` calls have a matching edge function.

All 46 dynamic `.from(var)` sites were checked: 43 are Dart `List`/`Map.from(...)`
constructors, not Supabase calls. The 3 real ones are the QA harness, exercise-database
introspection, and `storage.from(chat-media)` (created in `130_private_storage_buckets.sql`).

---

## 3 · Gap 2 — exists but no screen reads it

21 tables. **18 are legitimate server-side substrate** reached via an RPC, view or edge
function, and imply no missing screen: `communications`*, `decision_traces`,
`exercise_analytics`, `exercise_certifications`, `exercise_content_versions`,
`exercise_equipment`, `exercise_intelligence`, `exercise_media`, `exercise_modifications`,
`exercise_muscles`, `exercise_progressions`, `exercise_substitutions`, `exercise_tags`,
`intelligence_attribute_reviews`, `movement_edges`, `movement_nodes`, `predictions`,
`program_versions`, `score_cycles`.

Three are findings:

| Table | Finding |
|---|---|
| **`communications`** | Written by `send_communication()`, **read by no Dart code**. This is MSR-02 — a coach sends a message the client has no surface to open |
| **`workouts`** | **Legacy.** No app read at all; the app models plans as `workout_programs` + `program_workouts`. The `coach_client_workout_stats` view still joins it |
| **`exercise_reviews`** | **Genuinely orphaned.** Created at `058_exercise_normalized_schema.sql:111`, referenced only by its own index and an RLS loop. No app read, no function, no view, no edge function. The only schema object signalling a screen never built (MSR-26) |

---

## 4 · Gap 3 — orphan edge functions

| Function | Status |
|---|---|
| `stripe-webhook` | **Expected** — called externally by Stripe |
| `notify-coach-email` | **True orphan.** Declared only at `supabase/config.toml:115`. No app invoke, no `cron.schedule`, no `net.http_post`, no trigger. Reads **no Authorization header** and interpolates caller-controlled input raw into an email sent to every coach |
| `send-checkin-reminder` | **True orphan, never scheduled.** Its own header documents a `net.http_post` cron that exists in no migration. Also unauthenticated |

---

## 5 · Screens whose data cannot be provided

### 5.1 Broken — renders wrong, not merely empty (4)

| Screen | Cause |
|---|---|
| `/daily-checkin` | Submit writes to the non-existent `checkins` |
| `/coach-dashboard` — today's check-ins panel | `clientCheckinsProvider` selects `checkins` |
| `/vendor-portal` — attendee list | Selects non-existent `event_registrations.ticket_code` |
| `/home` — coach-tip card | `coach_tips` missing; error swallowed, so the card silently never appears |

### 5.2 Fabricated data presented as measured (3)

| Screen | Evidence |
|---|---|
| `/activity` | `stepsProvider = StateProvider<int>(6240)` and `waterIntakeProvider = StateProvider<int>(0)` — **no table, no persistence, reset every launch** |
| `/coach-business` | `coach_revenue_service.dart:68` returns an all-zero map on any failure → renders **$0 MRR / 0 subscribers** as if measured |
| `DashboardScreen` (dead) | `dashboard_service.dart:3` returns 100% hardcoded literals. Dead, but the mock would ship if the tab shell were revived |

### 5.3 Empty in QA for lack of seed data (22)

`/score` · `/goals` · `/action-items` · `/womens-health` · `/coach-payments` ·
`/coach-packages` · choose-package · `/upgrade` · `/subscription` · `/coach-plan` ·
`/coach-business` (Team tab) · coach video response · coach notes sheet · `/ai-coach` ·
event agenda · `/integrations` · `/workout-history` and `/strength-progression` (no
`workout_logs` / `workout_set_logs`) · `/insights` (workout-trend panel) · `/community`
(Groups tab) · `/observability` · `/content-review` + `/knowledge-review`.

This matters for QA interpretation: **an empty screen in QA is currently ambiguous** — it
may be a defect or merely unseeded. Twenty-two surfaces cannot be distinguished without
seeding.

---

## 6 · Architectural notes

- **`ai_nutrition` does not touch Supabase at all.** It posts to the NestJS API at
  `apps/api/src/ai/ai.controller.ts:36` (`POST /ai/nutrition/message`). The conversation and
  grocery list are **never persisted** — the only feature on a different backend.
- **`profile/data/profile_service.dart` and `profile/domain/profile_provider.dart` are 0
  bytes.** `ProfileScreen` and `PersonalInfoScreen` talk to Supabase directly, bypassing the
  feature's own data layer.
- **Dead providers:** `checkinStreakProvider`, `recentCheckinsProvider`,
  `hasCheckedInTodayProvider` are declared and watched by nothing — all three read the
  missing `checkins` table.
- **No cost or usage table exists** in any of the 132 migrations, while 19 edge functions
  call models unmetered (FC-14).

---

## 7 · Per-screen requirements — principal surfaces

| Screen | Entities / tables | Providers | Data status |
|---|---|---|---|
| `/home` | `user_profiles`, `coach_tips`✗, programs, score | multiple | **BROKEN** (coach tip) |
| `/train`, `/workouts`, `/workout-detail` | `workout_programs`, `program_workouts`, `exercises` | `workout_provider` | OK |
| `/active-workout` | `workout_logs`, `workout_set_logs`, `program_workouts` | `workout_provider` | OK |
| `/workout-history`, `/strength-progression` | `workout_logs`, `workout_set_logs` | — | No seed data |
| `/exercise-database`, `/exercise-detail` | `exercises` + 10 normalised satellites | `custom_exercise_service` | OK |
| `/meals-dashboard`, `/log-meal` | `meals`, `meal_items`, `foods` | nutrition providers | OK |
| `/ai-nutrition`, `/meal-plan`, `/grocery-list` | **none** — NestJS API | — | Not persisted |
| `/daily-checkin`, `/checkins` | **`checkins`✗**, `weekly_checkins` | `checkin_service` | **BROKEN** |
| `/progress` | `body_measurements`, `progress_photos`, `workout_logs` | — | OK |
| `/insights` | aggregates over logs + check-ins | — | Partial (no seed) |
| `/messages`, `/chat` | `conversations`, `messages`, `chat-media` bucket | messaging providers | OK |
| `/community`, `/pods`, `/challenges` | `community_posts`, `community_groups`, `accountability_pods`, `challenges` | `live_community_service` | Partial (Groups unseeded) |
| `/classes`, `/class-detail`, `/events` | `classes`, `class_bookings`, `events`, `event_registrations` | — | OK |
| `/appointments`, `/book-call` | `coaching_calls`, coach availability | booking providers | OK |
| `/coach-dashboard` | `coach_client_relationships`, **`checkins`✗** | coach providers | **BROKEN** (panel) |
| `/coach-business`, `/coach-payments` | `payments`, `subscriptions`, revenue rollups | `coach_revenue_service` | Fabricated on error |
| `/vendor-portal` | `events`, `event_registrations.ticket_code`✗ | `vendor_service` | **BROKEN** |
| `/womens-health` | cycle/symptom tables | — | No seed data |
| `/upgrade`, `/subscription` | `subscriptions`, Stripe edge functions | `payment_service` | No seed data |
| `/admin-dashboard`, `/observability` | admin RPCs, `platform_settings` | `admin_service` | No seed data |

---

## 8 · Recommended data actions

Nothing below was performed.

| # | Action | Severity |
|---|---|---|
| 1 | Resolve `checkins` — create the table or repoint the service at `weekly_checkins` | **P0** — the daily check-in submit path is broken |
| 2 | Resolve `event_registrations.ticket_code` vs `qr_code` | P1 |
| 3 | Resolve `coach_tips` — create, or remove the card and its swallowed catch | P2 |
| 4 | Persist `/activity` steps and water, or stop presenting them as measured | P1 — fabricated data |
| 5 | Make `coach_revenue_service` fail visibly rather than returning zeros | P1 — $0 MRR reads as measured |
| 6 | Seed the 22 unseeded surfaces so empty ≠ ambiguous in QA | P2 |
| 7 | Decide whether `ai_nutrition` should persist | Owner decision |
| 8 | Remove or wire the two unauthenticated orphan edge functions | **P1 — security** |
