# 12 Circle Fitness — Screen Evidence Matrix

Every proposed surface traced to the artifact that requires it. Baseline `0aa844a`.
**No entry rests on "a generic app would have this."**

Evidence classes: **CODE** · **ROUTER** · **SCHEMA** · **PROVIDER** · **COMPONENT** ·
**DESIGN** (a FIT anchor or annotation) · **WORKFLOW** · **OD** · **DOC**.

> **Read with the governing rule.** Evidence that a *designed* anchor is unimplemented
> supports an **implementation** claim (Section 1). Only evidence that a required surface has
> **no design frame** supports a **design commission** (Section 2).

---

## 0 · Reclassifications made in this pass

Recorded because they change the commission count.

| Candidate | Previous | Now | Reason |
|---|---|---|---|
| Create post, Post detail, Pods hub/detail, Log weight/measurements, Booking & cancellation confirm, AI Coach memory/Today/Week | "needs new design" | **Section 1** | FIT-067, 066, 071, 072, 055, 056, 087, 088, 105/106, 103, 104 **all exist as anchors** |
| Log a meal | "needs new design" | **Section 1** | FIT-019 exists and is **locked** |
| Booking handoff | "needs new design" | **Section 1** | FIT-099 exists |
| Check-in form | "needs new design" | **Section 1 / delete** | FIT-004 covers it; the route is a redirect stub |
| My assigned programme | commissioned | **withdrawn** | FIT-014/015 cover it; `myAssignedProgramProvider` unused = implementation gap |
| My nutrition plan | commissioned | **withdrawn** | FIT-091…093 cover it |
| Check-in history & streak | commissioned | **withdrawn** | FIT-023 Check-in hub covers it |
| Pending coach request | commissioned | **withdrawn — STATE** | a status value; FIT-028/FIT-097 design the no-coach condition |
| My bookings | commissioned | **open question** | FIT-080 may subsume it as a tab — needs a product ruling |
| Food search | commissioned | **open question** | plausibly a sub-surface of FIT-019 |

## 1 · Section 2 — missing from both design and implementation

| ID | Surface | Evidence classes | Primary citation | Corroborating citation | Strength |
|---|---|---|---|---|---|
| N-01 | Report / moderate | CODE · SCHEMA · DESIGN | `community/presentation/widgets/post_card.dart:113` — overflow menu `onPressed: () {}` | **zero** moderation objects across 132 migrations; full UGC in `001_full_ecosystem.sql` | **high** |
| N-02 | Client message inbox | SCHEMA · CODE | `096_communication_engine.sql:13-29` stores `client_text` + status `sent` | writer `coach/data/coach_program_service.dart:70,78`; **Dart readers: 0** | **high** |
| N-03 | Coach profile & reviews | SCHEMA · CODE | `coach_reviews.review_text` col `001_full_ecosystem.sql:206` | written `home_screen.dart:1319-1325`; `coach_marketplace_screen.dart:35,344` renders aggregates only | **high** |
| N-04 | Class check-in pass | CODE · DESIGN | `classes/presentation/class_detail_screen.dart:272-279` — *"Show QR code at check-in"*, button `onPressed: () {}` | `class_bookings` has **no `qr_code`** (`001_full_ecosystem.sql:254-261`) | **high** |
| N-05 | Delete account & export | DOC · CODE | `settings/presentation/help_center_screen.dart:44` FAQ *"How do I delete my account?"* | `privacy_policy_screen.dart:87` promises export; no code path; App Store 5.1.1(v) | **high** |
| N-06 | Community group detail | SCHEMA · PROVIDER · DESIGN | `016_community_groups.sql` | read `live_community_service.dart:145,149,175`; teaser `messaging/domain/connect_sections.dart:95-97`; FIT-005 declares a *"Tues Lifters"* row | **high** |
| N-08 | Exercise moderation review log | SCHEMA | `exercise_reviews` created `058_exercise_normalized_schema.sql:111` | referenced only by its own index and an RLS loop at `:141` — **no reader anywhere** | **medium** |
| N-07 | Coach client assessment | WORKFLOW · CODE · OD | 27-step intake collects PAR-Q/medical/injuries — `onboarding/domain/intake_data.dart:157-241` | `coach/presentation/client_detail_screen.dart:204,414` shows rollups only; blocked by OD-30 | **high** |

## 2 · Section 1 — designed surfaces collapsed into a host screen

**These are NOT design commissions.** Each has an anchor; the evidence supports building it as a distinct surface.

| ID | Surface | Evidence | Strength |
|---|---|---|---|
| DC-01 | Create post | DESIGN FIT-067 *"Create post"* **4/10** — a distinct authoring job inside `community_screen.dart` | **high** |
| DC-02 | Post detail + comments | DESIGN FIT-066 **3/9** + PROVIDER `selectedPostProvider` declared, **never consumed** — two independent streams | **high** |
| DC-03 | Pods hub | DESIGN FIT-071 **0/6** | **high** |
| DC-04 | Pod detail | DESIGN FIT-072 **0/5** | **high** |
| DC-05 | Booking confirmation | DESIGN FIT-087 *"Booking sheet — confirm → confirmed"* **0/2** | **high** |
| DC-06 | Cancellation confirmation | DESIGN FIT-088 *"Cancellation — confirm → cancelled"* **0/5** | **high** |
| DC-07 | Log weight | DESIGN FIT-055 **0/2** + PROVIDER `weightLogsProvider` unused | **high** |
| DC-08 | Log measurements | DESIGN FIT-056 **1/4** + PROVIDER `measurementsProvider`, `measurementNotifierProvider` unused | **high** |
| DC-09 | AI Coach — memory | DESIGN FIT-105 **7/15** + FIT-106 *"Add to memory"* **5/7** — a management job, not a chat state | **medium** |
| DC-10 | AI Coach — Today | DESIGN FIT-103 **0/5** | **high** |
| DC-11 | AI Coach — Week | DESIGN FIT-104 **0/5** | **high** |

## 3 · Section 1 — stubs on designed routes

| ID | Surface | Evidence | Strength |
|---|---|---|---|
| E-01 | Log a meal | CODE 23-line stub, `initState` → `context.go('/meals-dashboard')` · DESIGN FIT-019 **locked 4/5** · ROUTER orphan | **high** |
| E-02 | Food search | CODE 23-line stub · ROUTER orphan | **high** |
| E-03 | Check-in form | CODE 35-line stub; its own doc comment says *"a redirect, not a screen"* | **high** |
| E-04 | Nutrition gateway | CODE 1.8 s splash forwarding to two targets | **medium** |
| E-05 | Booking handoff | CODE 3 s handoff → `/appointments` · DESIGN FIT-099 0/0 | **medium** |


## 3b · Section 2 — implemented surfaces with no design frame (40)

Evidence class **ROUTER + DESIGN-ABSENCE**, derived mechanically: the route is registered and
its widget renders, and the route appears in **none** of the 110 manifest entries. Verified by
diffing the router's 91 paths against the anchor route set (45).

| Group | Count | Evidence |
|---|---|---|
| Client routes undesigned | 13 | registered in `app_router.dart`; absent from `manifest.json` |
| **Coach routes undesigned** | **12** | the package holds only FIT-032 `/coach-dashboard` and FIT-033 `/coach-checkin-review` of ~21 coach surfaces |
| Admin / vendor routes undesigned | 7 | no admin or vendor anchor exists in the package |
| Unrouted screens undesigned | 8 | reached only by `MaterialPageRoute`; no route **and** no anchor. `EventTicketScreen` excluded — FIT-086 covers it |

Excluded from this group with reason: 3 legal pages (static text — design not required),
4 system/external-entry routes (`/splash`, `/reset-password`, both Stripe returns),
2 debug-only routes (`!kReleaseMode`), 3 aliases/duplicates, 1 dead route.


## 3c · Evidence class: DESTINATION DECLARED BY A LOCKED ANCHOR

The strongest evidence found in this pass. An existing **locked** anchor names a destination
that has **no anchor of its own** — the design requires the surface and does not design it.

| Declaring anchor | Declared label | Required surface |
|---|---|---|
| FIT-001 Home (locked) | `Directory` | `/directory` |
| FIT-014 Workouts hub (locked) | `History` · `Exercise library` | `/workout-history` · `/exercise-library` |
| FIT-015 (locked) | `Browse the exercise library` | `/exercise-library` |
| FIT-029 Profile (locked) | `Personal information` · `Connected apps 2` | `/personal-info` · `/integrations` |
| FIT-032 Coach dashboard (locked) | `Adherence` · `Programs` · `All 24 clients` · `Review` | `/compliance` · `/program-builder` · `ClientDetailScreen` |
| FIT-033 Check-in review (locked) | `Adjust plan` | programme-adjust surface |

Verified against the regenerated reference images (110/110) as well as the manifest.

## 4 · Evidence deliberately rejected

Recorded so exclusions are auditable.

| Considered | Rejected because |
|---|---|
| 20 tables with no screen reader | **Substrate** reached through RPCs/views/edge functions — `_sync_exercise_relations`, `rank_exercises`, `award_points`, `assemble_weekly_review` etc. No screen implied |
| `workouts` table | **Legacy** — the app models plans as `workout_programs` + `program_workouts` |
| Sample rows in FIT-005 (*"Priya…"*, *"Tues Lifters…"*) | **Sample copy, not controls.** The repo's own `FIT_INTERACTION_COVERAGE.md` calls them *"a ceiling, not a backlog"* |
| Dark Mode / Language settings rows | **Controls, not screens** — and blocked by H-10/H-11 |
| Terms of Service | Route **exists**; only the Settings link is missing |
| Notification → destination | **Routing**, not a screen; blocked by H-07 |
| 4 dead-end CTAs in `dashboard_screen.dart` / `dash_org.dart` | Reachable only through `home_org.dart`, which nothing imports — **no user reaches them** |
| Attendee QR scanner | Capability H-02, not a missing screen |
| Global search | **No evidence** in code, schema or design of an intended search surface — recorded as an open question, not a gap |

## 5 · Convergence check

The two strongest streams were derived independently and agree:

| Unused provider (code) | Zero/low anchor (design) |
|---|---|
| `liveHabitsProvider` | FIT-058 Habits **0/5** |
| `todaySymptomsProvider` | FIT-063 Women's health **0/3** |
| `selectedPostProvider` | FIT-066 Post detail **3/9** |
| `weightLogsProvider`, `measurementsProvider` | FIT-055 **0/2**, FIT-056 **1/4** |
| `myBookingsProvider`, `myClassBookingsProvider` | FIT-098 **0/2**, FIT-080 **1/12** |
| `selectedChallengeTabProvider`, `challengeServiceProvider` | FIT-075 **1/5**, FIT-078 **0/1** |
| `postListProvider`, `selectedCommunityTabProvider` | FIT-065 **11/20**, FIT-067 **4/10** |

**34 of 230 providers are never consumed, and they cluster precisely where the design is
unbuilt.** Neither stream was derived from the other.
