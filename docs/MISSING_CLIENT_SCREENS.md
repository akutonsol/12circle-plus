# 12 Circle Fitness — Missing Client Screens

**Phase 3 deliverable.** Baseline `0aa844a`. Derived from
[`DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md`](DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md).

**Rule applied:** a screen is listed only where repository or design evidence requires the
surface. No screen is listed because a route exists, and none is omitted merely for lacking
a route where authoritative design evidence requires it.

---

## 0 · The finding that governs this document

**Category C — design exists, implementation missing — is ZERO.**

All 45 designed routes are built. There is **no designed client screen awaiting
implementation**. Everything below is therefore one of:

- a surface the product demonstrably requires that **the 110-screen package does not
  contain** (→ needs design first, per Phase 9), or
- a designed-and-built surface that **nothing can reach** (→ needs a declared entry point,
  which the package also does not contain).

Consequently **no missing client screen is implementable without first resolving a design or
owner decision.** Each record below states which.

---

## 1 · Stranded screens — built, designed, unreachable

These are the highest-value items in the document: the design exists, the implementation
exists and measures complete, and **no user can open them**.

### MCS-01 · Pods hub / detail / joined-state / empty-state

| Field | Value |
|---|---|
| **Proposed ID** | MCS-01 |
| **Route** | `/pods` — registered |
| **Route status** | **ORPHAN** — confirmed by `dart tool/orphan_route_sweep.dart` |
| **Design evidence** | FIT-071 Pods hub · FIT-072 Pod detail · FIT-073 joined vs not joined · FIT-074 empty + loading. All four resolve to `community/presentation/pods/pods_screen.dart` |
| **Why required** | Four designed anchors; a complete implementation reading `accountability_pods`; `notification_preferences_screen.dart:182` ships copy promising the feature to users |
| **Related FIT** | FIT-071…074 (non-locked); adjacent FIT-065…070 `/community` |
| **Existing components** | `pods_screen.dart`, `live_community_service.dart` |
| **Existing domain/data** | `accountability_pods` table — exists and is read |
| **Existing nav entry** | **NONE** |
| **Backend support** | ✅ exists |
| **Only presentation missing?** | ❌ — presentation exists too. **Only the entry point is missing** |
| **New domain capability** | none |
| **New schema** | none |
| **New RLS** | none |
| **Implementable without owner decision?** | **NO** |
| **Blocker** | **The 110-screen package declares no control anywhere that opens `/pods`.** All pod references in FIT-005 Connect are sample-row copy (*"your pod"*, *"Tues Lifters"*) which `FIT_INTERACTION_COVERAGE.md` explicitly calls *"a ceiling, not a backlog"*. Adding an entry point means inventing product navigation → forbidden by Phase 9 |
| **Dependencies** | OD-33 (below) |
| **Acceptance criteria** | A declared control opens `/pods`; `orphan_route_guard_test.dart` allowlist loses `/pods` in the same change; FIT-071…074 remain ≥ current coverage |
| **QA requirements** | Widget test for the entry control; device-runtime verification that the route opens; mutation test — remove the control, guard must fail |

### MCS-02 · Log a meal

| Field | Value |
|---|---|
| **Proposed ID** | MCS-02 |
| **Route** | `/log-meal` — registered |
| **Route status** | **ORPHAN**, and the screen is a **23-line redirect stub** whose `initState` immediately `context.go('/meals-dashboard')` |
| **Design evidence** | **FIT-019 "Log a meal" — LOCKED, measures 4/5** |
| **Why required** | A **paying `selfGuided` user has no in-app route to log a meal.** The gated route exists, is paid for, and has no door |
| **Related FIT** | FIT-019 (locked); FIT-020 AI meal scan is an embedded widget of this screen; FIT-003 `/meals-dashboard` |
| **Existing components** | `log_meal_screen.dart` (stub), `meals_dashboard_screen.dart` (1,443 lines — the real product) |
| **Existing domain/data** | `meals`, `meal_items`, `foods` — exist |
| **Existing nav entry** | **NONE** |
| **Backend support** | ✅ exists |
| **Only presentation missing?** | **Yes** — the stub must become a real screen, *or* FIT-019 must be re-anchored to `/meals-dashboard` |
| **New domain capability** | none |
| **New schema** | none |
| **New RLS** | none |
| **Implementable without owner decision?** | **NO** |
| **Blocker** | A locked anchor's identity: is FIT-019 a distinct screen, or is `/meals-dashboard` the screen? Re-anchoring a **locked** anchor is a design-authority decision → OD-34 |
| **Dependencies** | OD-34 |
| **Acceptance criteria** | FIT-019's 5 interactions present on a reachable surface; allowlist loses `/log-meal` |
| **QA requirements** | Widget + device test that a `selfGuided` client can reach meal logging from persistent nav; mutation-verified |

### MCS-03 · Welcome

| Field | Value |
|---|---|
| **Proposed ID** | MCS-03 |
| **Route** | `/onboarding` — registered |
| **Route status** | **ORPHAN** |
| **Design evidence** | **FIT-006 "Welcome" — LOCKED, measures 2/2** |
| **Why required** | Locked anchor, fully built, unreachable |
| **Existing nav entry** | **NONE** — the router comment at `app_router.dart:186` claims the splash hands off here; `splash_screen.dart:141,146` goes to `/signup` or `/login` |
| **Implementable without owner decision?** | **NO — already adjudicated** |
| **Blocker** | **OD-31, already open.** The design package documents the conflict itself: FIT-010's annotation reads *"the shipped implementation is a different screen entirely, and it orphans locked Welcome."* The existing guard test records this as *"not a defect to fix here"* |
| **Note** | Listed for completeness. **No action — owned by OD-31** |

### MCS-04 · Event ticket

| Field | Value |
|---|---|
| **Proposed ID** | MCS-04 |
| **Route** | none — `EventTicketScreen` is push-only |
| **Design evidence** | **FIT-086** — built but unrouted |
| **Implementable without owner decision?** | **NO — already adjudicated** |
| **Blocker** | **OD-4, already open**: *"Navigation entry for the event ticket (not router-addressable)"* |
| **Note** | Listed for completeness. **No action — owned by OD-4** |

---

## 2 · Surfaces the product requires that the design package does not contain

Each is evidenced in the repository. **None is in the 110-screen package**, so per Phase 9 a
design requirement is recorded rather than a production design invented. Full specifications
are in [`DESIGN_CAPABILITY_GAPS.md`](DESIGN_CAPABILITY_GAPS.md).

| ID | Screen | Evidence | Backend? | New schema? | New RLS? | Blocker |
|---|---|---|---|---|---|---|
| **MCS-05** | Report / moderate content | `post_card.dart:113` overflow menu wired to a no-op; full UGC across `001_full_ecosystem.sql`; **zero** moderation matches in 132 migrations | ❌ | ✅ reports table | ✅ | MISSING-DESIGN + product policy (categories, retention, action model) |
| **MCS-06** | Client message inbox | `096_communication_engine.sql:13-29` stores `client_text` + `sent`; writer `coach_program_service.dart:70,78`; **readers: 0** | ✅ partial | ❌ | ✅ client read policy | MISSING-DESIGN (inbox IA, read semantics) |
| **MCS-07** | Coach profile & reviews | `coach_reviews.review_text` written at `home_screen.dart:1319`, **never rendered**; `coach_marketplace_screen.dart:344` jumps straight to purchase | ✅ | ❌ | ❌ | MISSING-DESIGN |
| **MCS-08** | Class check-in pass | `class_detail_screen.dart:272-279` promises *"Show QR code at check-in"*; the QR button is `onPressed: () {}`; `class_bookings` has no `qr_code` column | ❌ | ✅ column | ❌ | MISSING-DESIGN + FC-03 (real QR) |
| **MCS-09** | Delete account & data export | `help_center_screen.dart:44` FAQ asks how to delete; `privacy_policy_screen.dart:87` promises export; neither exists. **App Store 5.1.1(v)** | ❌ | ❌ | ✅ deletion path | MISSING-DESIGN + legal/retention decision |
| **MCS-10** | Community group detail | `016_community_groups.sql`; read at `live_community_service.dart:145,175`; `connect_sections.dart:95-97` renders a `groupLine()` teaser with nothing to open; FIT-005 declares a *"Tues Lifters"* group row | ✅ | ❌ | ❌ | MISSING-DESIGN |

---

## 3 · Excluded, with reason

Listed so the exclusions are auditable rather than silent.

| Excluded | Reason |
|---|---|
| `/coach`, `/nutrition-overview` | **Duplicates**, not missing screens. `/coach` is an alias of `/train`; `/nutrition-overview` is an older self-contained logger superseded by `/meals-dashboard`. Correct disposition is **deletion** → OD-32 |
| `/coach-business`, `/food-search` | Screens exist and are reached (or are stubs); the route is redundant or doorless. Not missing screens |
| 13 category-`D` client routes | **Implemented**; they lack *design*, not implementation. Listed in the final matrix and in `DESIGN_CAPABILITY_GAPS.md` §4 |
| 14 category-`K` coach routes | Implemented; coach product is out of the client-screen scope of this document |
| 8 push-only screens | Implemented. The gap is *routing*, not the screen — and routing them requires path parameters (FC-07) |
| Language picker, dark mode | Blocked by FC-04 / FC-05 — unsupported capabilities, not missing screens |
| Attendee QR scanner | Blocked by FC-03 |
| Notification routing, ToS link | Not screens |
| 7 dead classes | Dead code → OD-32 |

---

## 4 · Owner decisions raised by this document

Numbered to continue the existing register in `docs/QA_EVIDENCE.md` (OD-1…OD-31).

| ID | Decision | Blocks |
|---|---|---|
| **OD-32** | Delete the dead/duplicate surfaces? `home_org.dart` (caused the FIT-001 error and will recur), `dash_org.dart`, `dashboard_screen.dart`, `profile/subscription_screen.dart`, `embedded_checkout_screen.dart`, `coach_pricing_sheet.dart`, `log_weight_sheet.dart`, and the alias routes `/coach`, `/nutrition-overview`. **Destructive — requires approval** | Matrix §4 residual risk |
| **OD-33** | `/pods` has four designed anchors and no declared entry anywhere in the package. Add a Connect/Community entry (requires a design decision on placement), or retire the feature? | MCS-01 |
| **OD-34** | Is **FIT-019 "Log a meal"** a distinct screen, or should the locked anchor be re-anchored to `/meals-dashboard`? A paying user currently cannot log a meal by any route | MCS-02 |
| **OD-35** | Commission the six missing-design surfaces (MCS-05…10) as a design package addendum? Two are store-review gates (MCS-05 moderation, MCS-09 deletion) | MCS-05…10 |

Already open and re-confirmed by this audit: **OD-4** (event ticket navigation, = MCS-04)
and **OD-31** (FIT-006 Welcome orphan, = MCS-03).
