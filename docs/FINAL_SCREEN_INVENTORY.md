# 12 Circle Fitness — Final Screen Inventory

**The canonical list of every product surface.** Baseline `0aa844a`.
Machine-readable twin: [`FINAL_SCREEN_INVENTORY.json`](FINAL_SCREEN_INVENTORY.json).

## 0 · OD-38 — RESOLVED

All **110 of 110** reference images regenerated from the authoritative board via
`capture-references.mjs` (the board holds exactly 110 `.phone` frames; the generator's
manifest-count assertion passed). They are **derived artifacts**, never lost. Design
acceptance is unblocked.

## 1 · Totals

| Measure | Value |
|---|---|
| **Total product surfaces (all kinds)** | **148** |
| Registered routes | **91** (89 in a release build) |
| Distinct widgets those routes build | 88 (3 aliases) |
| Screens reachable only by `MaterialPageRoute` | **9** |
| Modal/sheet product surfaces | 52 |
| Flow steps (27 intake + 10 modal-hosted) | 37 |
| Nested tab roots / view-state scaffolds | 26 |
| FIT anchors | 110 |
| **NEW screen designs CONFIRMED** | **40** |
| Reclassified out of the commission | 8 (1 insufficient evidence · 7 owner decision) |
| Designed anchors awaiting implementation (Section 1) | **32** at 0/N + 56 partial |

## 2 · Route categories

| Cat | Category | Count |
|---|---|---|
| **A** | DESIGN + IMPLEMENTATION | 35 |
| **B** | DESIGN + IMPL PARTIAL | 2 |
| **D** | IMPL EXISTS + DESIGN MISSING | 13 |
| **E** | IMPL EXISTS + DESIGN NOT REQUIRED | 4 |
| **F** | DUPLICATE / ALIAS | 3 |
| **G** | DEAD / UNREACHABLE | 3 |
| **H** | REDIRECT / STUB | 5 |
| **I** | DEBUG / QA ONLY | 2 |
| **J** | ADMIN / VENDOR / NON-CLIENT | 7 |
| **K** | COACH PRODUCT | 14 |
| **L** | LEGAL / SYSTEM | 3 |

**Category `C` (designed, implementation missing) is 0 by route** — but that measures route
existence. Measured by *design implementation*, **32 anchors are at 0/N** and belong to
category `B`. See §4.

## 3 · Surfaces beyond the route table

| Kind | Count | Note |
|---|---|---|
| Push-only screens | 9 | `ClientDetailScreen`, `ProgramBuilderScreen`, `CreateClassScreen`, `CoachAvailabilityScreen`, `ChoosePackageScreen`, `CoachVideoResponseScreen`, `EventAgendaScreen`, `EventAttendeesScreen`, `EventTicketScreen` — no route, no deep link, no shell nav, no router auth |
| Modals / sheets | 52 | incl. 11 destructive confirmations (all correctly gated) |
| Intake flow steps | 27 | one `PageView`; only **19** have a designed anchor |
| PaywallGate locked states | 13 | each gated route renders feature **or** upgrade wall |
| Role-switched shell | 2 | `app_shell.dart` renders different client and coach bottom navs from one `ShellRoute` |
| Conditional-export pairs | 6 | `dart.library.html` — web-only variants |
| Hand-written HTML pages | 2 | `web/stripe_checkout.html`, `web/checkout_complete.html` — real landing surfaces, no Dart, no route |

## 4 · Design implementation — the corrected measure

> A route is **not** implemented because its `GoRoute` exists or its widget renders.
> Completeness is measured against the declared design surface.


| Measure | Value |
|---|---|
| Anchors **complete** (n/n) | **19 of 110** |
| Anchors **partial** (0<n<total) | **56** |
| Anchors at **0/N** | **32** across 20 targets |
| Anchors with nothing declared | 3 |
| Interactions present | **287 / 600** |
| LOCKED anchors complete **and reachable** | **10 of 29** |

The single fully-built area is `/active-workout` (FIT-002 5/5, FIT-017 2/2, FIT-018 4/4).

## 5 · Reachability

| State | Count | Detail |
|---|---|---|
| Orphan routes | **7** | `/coach` `/coach-business` `/food-search` `/log-meal` `/nutrition-overview` `/onboarding` `/pods` — confirmed by `dart tool/orphan_route_sweep.dart` |
| Unreachable FIT anchors | **6** | FIT-006 (2/2 locked), FIT-019 (4/5 locked), FIT-071…074 — designed, built, and no user can open them |
| Routes reachable from persistent nav | 13 of 91 | **86% are in-page-CTA-only** |
| Deep-link destinations | **0** | no intent filters, no URL schemes, no path parameters |

## 6 · Health of what exists

| Signal | Value |
|---|---|
| Dead screen classes | 7 (~1,270 lines) |
| Redirect stubs occupying a route | 5 |
| Duplicate class names | 2 (`HomeScreen`, `DashboardScreen`) — caused the FIT-001 mis-mapping |
| Providers declared and never consumed | **34 of 230** |
| Screens with no error state | 25 |
| Shared empty/error/loading widget | **none** — `_EmptyState` re-declared 10× |
| Offline handling | **none** — 0 of 98 screens |
| Screens broken by schema gaps | 4 |
| Surfaces with fabricated data | 3 |

## 7 · Companion documents

| Document | Contents |
|---|---|
| [`FINAL_NEW_SCREEN_DESIGN_COMMISSION.md`](FINAL_NEW_SCREEN_DESIGN_COMMISSION.md) | **The authoritative 40** — direct input to the design phase |
| [`MISSING_SCREEN_REGISTER.md`](MISSING_SCREEN_REGISTER.md) | **Section 1** implementation backlog · **Section 2** provisional candidates |
| [`SCREEN_DESIGN_GAPS.md`](SCREEN_DESIGN_GAPS.md) | 32 zero-coverage anchors; state-system gap |
| [`FUTURE_SCREEN_CAPABILITIES.md`](FUTURE_SCREEN_CAPABILITIES.md) | 15 capabilities preserved, not designed down |
| [`SCREEN_EVIDENCE_MATRIX.md`](SCREEN_EVIDENCE_MATRIX.md) | every claim traced to its artifact |
| [`MISSING_SCREEN_SUMMARY.md`](MISSING_SCREEN_SUMMARY.md) | executive summary |
| [`DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md`](DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md) | per-route classification table |
