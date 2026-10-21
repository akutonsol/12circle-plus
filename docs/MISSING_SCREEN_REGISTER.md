# 12 Circle Fitness — Screen Gap Register (CANONICAL)

> **Superseded for the commission list.** Section 2 below is the **provisional 48**.
> The authoritative post-reconciliation list is the **40** in
> [`FINAL_NEW_SCREEN_DESIGN_COMMISSION.md`](FINAL_NEW_SCREEN_DESIGN_COMMISSION.md):
> N-08 withdrew on insufficient evidence and the 7 admin/vendor surfaces await OD-40.
> Section 1 (implementation backlog) is unchanged and remains authoritative.

Baseline `0aa844a`. Read-only audit. **Supersedes** all earlier files of this name.

**The governing distinction, applied throughout:**

> A designed anchor that is unimplemented is an **IMPLEMENTATION** gap, not a missing screen.
> A required product surface with **no design frame** is a **DESIGN COMMISSION**.

These are separated into Section 1 and Section 2 and are never mixed.

**A route is NOT "implemented" merely because its `GoRoute` exists or its widget renders.**
Completeness is measured by `dart tool/fit_backlog.dart` against the declared design surface.

---

## 0 · Measured position

| Measure | Value |
|---|---|
| FIT anchors | 110 |
| Anchors **complete** | **19** |
| Anchors **partial** (0 < n < total) | **56** |
| Anchors at **0/N** — design effectively unbuilt | **32** |
| Anchors with nothing declared (0/0) | **3** |
| Interactions present | **287 / 600** |
| LOCKED anchors complete **and reachable** | **10 of 29** |
| Registered routes | 91 |
| Routes carrying ≥1 anchor | **45** |
| Routes with **no** anchor | **46** |

**The design package is client-only.** Of ~21 coach surfaces it contains **two** —
FIT-032 Coach dashboard and FIT-033 Check-in review. It contains **zero** admin or vendor
anchors.

---

# SECTION 1 — EXISTING DESIGNS REQUIRING IMPLEMENTATION

These screens **are designed**. They must be built, not commissioned. **No new design work.**

## 1.1 · Designed, substantially unimplemented (Class C) — 32 anchors

| Anchor | Coverage | Screen | Route |
|---|---|---|---|
| FIT-095 | **0/15** | Grocery list — built | `/grocery-list` |
| FIT-100 | **0/9** | Action items — what your coach set | `/action-items` |
| FIT-089 | **0/7** | AI nutrition — conversation | `/ai-nutrition` |
| FIT-071 | **0/6** | Pods hub | `/pods` ⚠ orphaned |
| FIT-088 | **0/5** | Cancellation — confirm → cancelled | `/class-detail` |
| FIT-058 | **0/5** | Habits | `/habits` |
| FIT-103 | **0/5** | AI Coach — today | `/ai-coach` |
| FIT-104 | **0/5** | AI Coach — the week | `/ai-coach` |
| FIT-072 | **0/5** | Pod detail | `/pods` ⚠ orphaned |
| FIT-110 | **0/4** | AI Coach — coming back | `/ai-coach` |
| FIT-090 | **0/4** | AI nutrition — a turn that failed | `/ai-nutrition` |
| FIT-085 | **0/4** | Events hub | `/events` |
| FIT-086 | **0/3** | Event ticket | unrouted ⚠ OD-4 |
| FIT-083 | **0/3** | Class — booked / live / cancelled | `/class-detail` |
| FIT-082 | **0/3** | Class — full / waitlist | `/class-detail` |
| FIT-076 | **0/3** | Challenge detail — active | `/challenge-detail` |
| FIT-063 | **0/3** | Women's health | `/womens-health` |
| FIT-046 | **0/3** | Photo source | sheet — `/intake`, `/progress` |
| FIT-101 | **0/2** | Action items — empty, loading, failed | `/action-items` |
| FIT-098 | **0/2** | Booking — nothing open, and loading | `/appointments` |
| FIT-093 | **0/2** | Meal plan — it didn't build | `/meal-plan` |
| FIT-087 | **0/2** | Booking sheet — confirm → confirmed | `/class-detail` |
| FIT-081 | **0/2** | Class detail | `/class-detail` |
| FIT-074 | **0/2** | Pods — empty + loading | `/pods` ⚠ orphaned |
| FIT-059 | **0/2** | Goals | `/goals` |
| FIT-055 | **0/2** | Log weight | `/progress` |
| FIT-078 | **0/1** | Challenge — upcoming · completed · expired | `/challenges` |
| FIT-077 | **0/1** | Who else is in | `/challenge-detail` |
| FIT-061 | **0/1** | Insights | `/insights` |
| FIT-060 | **0/1** | Score | `/score` |
| FIT-049 | **0/1** | Generating plan | `/intake` |
| FIT-034 | **0/1** | Intake welcome | `/intake` |

**Whole designed areas unbuilt:** all **5** `/class-detail` anchors · all **4** `/pods` ·
both `/action-items` · both `/grocery-list` · both `/ai-nutrition`.

## 1.2 · Designed surfaces collapsed into a host screen (Class B)

Designed as distinct anchors, implemented inside a shared screen. **Implementation work** —
the design exists.

| Anchor | Surface | Host | Coverage | Distinct surface or state? |
|---|---|---|---|---|
| FIT-067 | Create post | `/community` | 4/10 | **Distinct** — authoring job |
| FIT-066 | Post detail + comments | `/community` | 3/9 | **Distinct** — `selectedPostProvider` unused |
| FIT-071/072 | Pods hub / detail | `/pods` | 0/6, 0/5 | **Distinct** — two surfaces |
| FIT-055/056 | Log weight / measurements | `/progress` | 0/2, 1/4 | **Modal** — logging sheets |
| FIT-087/088 | Booking / cancellation confirm | `/class-detail` | 0/2, 0/5 | **Modal** — the anchor names a *sheet* |
| FIT-105/106 | AI Coach memory | `/ai-coach` | 7/15, 5/7 | **Distinct** — management job |
| FIT-103/104 | AI Coach Today / Week | `/ai-coach` | 0/5, 0/5 | **Distinct** — periodic briefs |
| FIT-052/053/054 | Progress tabs | `/progress` | 5/5, 5/7, 4/11 | **State** — tabs of one screen |
| FIT-069/070 | Community empty / error | `/community` | 8/11, 3/4 | **State** |
| FIT-101, FIT-094, FIT-079, FIT-084 | empty/loading/error variants | various | — | **State** |

## 1.3 · Stubs occupying a designed route (Class E) — 3

| Route | Implementation | Anchor | Action |
|---|---|---|---|
| `/log-meal` | **23-line redirect stub** → `/meals-dashboard` | **FIT-019 LOCKED 4/5** | Build the designed screen, or re-anchor — **OD-34** |
| `/booking-handoff` | 3 s handoff → `/appointments` | FIT-099 0/0 | Confirm it should exist |
| `/checkin-form` | 35-line redirect stub → `/daily-checkin` | covered by **FIT-004** | Delete the route — no new screen |

## 1.4 · Designed but unreachable (Class F) — 6 anchors

Designed, built, complete — **no user can open them**.

| Anchor | Coverage | Route | Decision |
|---|---|---|---|
| FIT-006 Welcome | **2/2 LOCKED** | `/onboarding` orphaned | **OD-31** |
| FIT-019 Log a meal | **4/5 LOCKED** | `/log-meal` orphaned | **OD-34** |
| FIT-071…074 Pods | 0/6, 0/5, 0/0, 0/2 | `/pods` orphaned | **OD-33** |
| FIT-086 Event ticket | 0/3 | unrouted | **OD-4** |

## 1.5 · The cross-cutting state system (Class C) — FIT-022

FIT-022 *"Loading & failure"* declares a cross-cutting pattern. The codebase has **no shared
empty/error/loading/retry widget** — `_EmptyState` is privately re-declared **10×** with 10
signatures, there is **zero offline handling** (0 of 98 screens), and **25 major screens have
no error state**. Designed; unimplemented. **One implementation resolves a defect class
product-wide.**

---

# SECTION 2 — NEW SCREENS NOT REPRESENTED IN THE DESIGN PACKAGE

Every entry is a product surface with **no FIT anchor**. Each cites evidence.

## 2.1 · Missing from both design and implementation — 8

| ID | Name | Role | Area | Evidence source | Evidence location | Why existing screens cannot satisfy it | Route | Data model | Provider/service | Nav trigger | States | Interactions | Deps | OD | Supported? | Pri | Conf |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **N-01** | Report / moderate content | Shared | Community | CODE + SCHEMA | `post_card.dart:113` overflow `onPressed: () {}`; **zero** moderation objects in 132 migrations | FIT-065…070 design the feed only; no anchor has any moderation affordance | — | none | none | post overflow menu | form, submitted, duplicate, admin queue | select reason, submit, block, hide | new tables | OD-35 | ❌ | **P0** | high |
| **N-02** | Client message inbox | Client | Coach comms | SCHEMA + CODE | `096_communication_engine.sql:13-29` stores `client_text`+`sent`; writer `coach_program_service.dart:70,78`; **Dart readers: 0** | FIT-005 Connect and FIT-026 Conversation are the coach *chat*; `communications` is a separate one-way channel with no surface | — | `communications` | `send_communication()` | Connect / notification | empty, unread, read, error | open, mark read | client SELECT policy | OD-35 | ⚠ | **P0** | high |
| **N-03** | Coach profile & reviews | Client | Marketplace | SCHEMA + CODE | `coach_reviews.review_text` col `001_full_ecosystem.sql:206`, written `home_screen.dart:1319`, **never rendered**; `coach_marketplace_screen.dart:344` jumps straight to purchase | **No anchor exists for any marketplace surface.** FIT-096…098 are booking, not coach selection | — | `coach_reviews` | marketplace service | marketplace card tap | loading, empty-reviews, populated | read reviews, view packages | — | OD-35 | ✅ | **P1** | high |
| **N-04** | Class check-in pass | Client | Classes | CODE + SCHEMA | `class_detail_screen.dart:272-279` promises *"Show QR code at check-in"*; button `onPressed: () {}`; `class_bookings` has **no `qr_code`** | FIT-086 Event ticket is a *different entity* (events, not classes) | — | `class_bookings` | — | class detail | valid, used, expired, cancelled | show, refresh | H-01 | OD-35 | ❌ | **P1** | high |
| **N-05** | Delete account & data export | Client | Account | DOC + CODE | `help_center_screen.dart:44` FAQ *"How do I delete my account?"*; `privacy_policy_screen.dart:87` promises export | FIT-030 Settings designs the settings list; **no anchor covers deletion or export**. App Store 5.1.1(v) | — | ~40 user-keyed tables | none | settings | confirm, destructive-confirm, in-progress, done, error | confirm, export, cancel | H-05 | OD-35 | ❌ | **P0** | high |
| **N-06** | Community group detail | Client | Community | SCHEMA + PROVIDER + DESIGN | `016_community_groups.sql`; read `live_community_service.dart:145,175`; teaser `connect_sections.dart:95-97`; FIT-005 declares a *"Tues Lifters"* row | FIT-071…074 design **pods**, a different entity. No anchor covers groups | — | `community_groups`, `_members` | `live_community_service` | Connect group row | loading, empty, member, non-member | open, join, leave, post | — | OD-35 | ✅ | **P1** | high |
| **N-07** | Coach client assessment (intake / PAR-Q) | Coach | Coaching | WORKFLOW + CODE | 27-step intake collects PAR-Q, medical history, injuries — `intake_data.dart:157-241`; `client_detail_screen.dart:204,414` shows rollups only | **No coach anchor exists** beyond FIT-032/033. A coach designs programmes blind to declared injuries | — | intake tables | intake providers | client detail | loading, populated, restricted | read, filter, flag | — | **OD-30** | ✅ | **P0** | high |
| **N-08** | Exercise moderation review log | Admin | Content | SCHEMA | `exercise_reviews` created `058_exercise_normalized_schema.sql:111`, referenced only by its own index and an RLS loop — **no reader anywhere** | No admin anchor exists at all | — | `exercise_reviews` | none | — | queue, reviewed, empty | review, approve, reject | — | OD-35 | ✅ | **P3** | med |

## 2.2 · Implemented client surfaces with no design — 13

Built and reachable; **no anchor**. Each needs a design frame.

`/directory` (the largest hub — a 15-module table, sole entry for 3 routes) · `/workouts` ·
`/workout-history` · `/exercise-library` · `/exercise-database` · `/exercise-detail` ·
`/create-exercise` (1,143 lines, 4-tab, no error state) · `/strength-progression` ·
`/coach-marketplace` · `/personal-info` · `/notification-preferences` · `/subscription` ·
`/integrations`

## 2.3 · Implemented coach surfaces with no design — 12

**The coach product is almost entirely undesigned** — only FIT-032 and FIT-033 exist.

`/coach-directory` · `/compliance` · `/program-builder` · `/coach-plan` · `/coach-packages` ·
`/coach-classes` · `/coach-payments` · `/coach-copilot` · `/program-designer` ·
`/continuous-coaching` · `/weekly-review` · `/coach-client-workouts`

## 2.4 · Unrouted screens with no design — 8

Built, pushed via `MaterialPageRoute`, no route, no anchor. `EventTicketScreen` is excluded —
FIT-086 covers it.

Coach/vendor: `ClientDetailScreen` (hosts 5 sub-surfaces incl. the coach-notes sheet) ·
`ProgramBuilderScreen` (the route `/program-builder` builds a *different* class) ·
`CreateClassScreen` · `CoachAvailabilityScreen` · `CoachVideoResponseScreen` ·
`EventAttendeesScreen`
Client: `ChoosePackageScreen` · `EventAgendaScreen`

## 2.5 · Admin / vendor surfaces with no design — 7

`/admin-dashboard` · `/admin-exercise-review` · `/content-center` · `/observability` ·
`/content-review` · `/knowledge-review` · `/vendor-portal`

---

## 3 · NEW SCREEN vs NEW STATE — adjudications

Recorded so the discipline is auditable.

| Candidate | Verdict | Reason |
|---|---|---|
| Pending coach request | **STATE, not a screen** | `coach_client_relationships.status` is a value; FIT-028 *"Connect — no coach"* and FIT-097 already design the no-coach condition. `pendingCoachProvider` being unused is an **implementation** gap |
| My assigned programme | **COVERED** | FIT-014 Workouts hub / FIT-015 *"no plan yet"* already design it. `myAssignedProgramProvider` unused = implementation gap |
| My nutrition plan | **COVERED** | FIT-091…093 Meal plan |
| Check-in history & streak | **COVERED** | FIT-023 Check-in hub. Five unused check-in providers = implementation gap |
| My bookings | **OPEN QUESTION** | `myBookingsProvider` + `myClassBookingsProvider` unused, but FIT-080 *"Classes hub + schedule"* may subsume it as a tab. **Not commissioned** — needs a product ruling |
| Food search | **OPEN QUESTION** | `/food-search` is an orphaned stub; food search is plausibly a sub-surface of FIT-019 Log a meal. **Not commissioned** |
| Nutrition gateway `/nutrition` | **DELETE CANDIDATE** | 1.8 s splash forwarding to two targets; no anchor. Likely should not exist |
| Booking/cancellation confirm | **MODAL, designed** | FIT-087 names a *sheet*; Section 1 |
| Log weight / measurements | **MODAL, designed** | FIT-055/056; Section 1 |
| Progress tabs | **STATE** | FIT-052/053/054 are tabs of one screen |
| Dark Mode, Language, Sound Effects | **CONTROLS** | not screens; blocked by H-10/H-11 |
| Terms of Service | **LINK** | route exists; only the Settings entry is missing |
| Notification → destination | **ROUTING** | blocked by H-07 (no path parameters) |
| 20 substrate tables | **NO SCREEN** | reached through RPCs/views — `_sync_exercise_relations`, `rank_exercises`, `award_points` etc. |
| 4 dead-end CTAs in `dashboard_screen.dart` | **NO SCREEN** | reachable only through `home_org.dart`, which nothing imports |
| Global search | **NO EVIDENCE** | no code, schema or design evidence of an intended search surface |

---

## 4 · Duplicate / dead (Class G) — 9

`home_org.dart` (duplicate `HomeScreen`; caused the FIT-001 mis-mapping) · `dash_org.dart` ·
`dashboard_screen.dart` · `profile/subscription_screen.dart` · `embedded_checkout_screen.dart` ·
`coach_pricing_sheet.dart` · `log_weight_sheet.dart` · routes `/coach`, `/nutrition-overview`.
Deletion is destructive → **OD-32**.

**Excluded from the design commission — legal/system (7):** `/privacy-policy`,
`/terms-of-service`, `/help-center` (static text, design not required), `/splash`,
`/payment-success`, `/payment-cancel`, `/reset-password` (system/external entry).

---

## 5 · Totals

| Section | Count |
|---|---|
| **SECTION 1 — implementation backlog** | **32 anchors at 0/N** plus 56 partial, 3 stubs, 6 unreachable, 1 state system |
| **SECTION 2 — new design candidates (provisional)** | **48** → **40 confirmed** |
| — missing from both | 8 |
| — client routes undesigned | 13 |
| — coach routes undesigned | 12 |
| — unrouted screens undesigned | 8 |
| — admin/vendor undesigned | 7 |
| Open questions (not commissioned) | 3 |
| Duplicate/dead | 9 |
| Future capabilities | 15 |
