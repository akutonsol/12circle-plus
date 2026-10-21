# 12 Circle Fitness — Screen Ecosystem FINAL Audit

**Phase completion report.** Baseline `0aa844a` (2026-09-23 23:56).
Router **unchanged** since `fbee6d5` — verified by `git diff --stat`, so the 91-route
inventory carried forward intact.

**Status vocabulary — never collapsed:**
`VERIFIED` (direct inspection at baseline) · `LOCALLY_VERIFIED` (a repository tool was run
and its output read) · `RUNTIME_VERIFIED` (executed on a device/emulator) · `CI_VERIFIED` ·
`BLOCKED` · `POST-QA` · `OWNER_DECISION_REQUIRED`.

---

## 1 · Phase outcome, stated plainly

**The authorized implementation scope is empty, and that is a finding rather than a
shortfall.**

The canonical inventory establishes that **Category C — design exists, implementation
missing — is ZERO**. All 45 designed routes are built. No designed screen awaits
implementation.

Every remaining candidate fails one of the directive's own gates:

| Candidate class | Count | Why not autonomously implementable |
|---|---|---|
| Designed-but-unbuilt screens | **0** | None exist |
| Stranded screens (built, designed, unreachable) | 4 | No declared entry point exists in the package. Adding one = inventing product navigation → **Phase 9 forbids** |
| Surfaces absent from the design package | 6 | `MISSING_DESIGN` → **Phase 9 requires a specification, not a production design** |
| Implemented-but-undesigned routes | 35 | Nothing to implement; they need *design* |
| Duplicate/dead surfaces | 9 | Correct disposition is **deletion** → **Phase 10 (4)** destructive, needs approval |

The genuine remaining backlog is **interaction-level, not screen-level**: 287 of 600
declared interactions are present. That workstream is **actively owned by another session**
(§7).

Accordingly this phase delivered the reconciliation, the canonical inventory, the design
requirements and the escalations — and implemented nothing, because nothing was
implementable without violating the directive's own constraints.

---

## 2 · Phase 1 — reconciliation results

| Item | Result | Status |
|---|---|---|
| Repository HEAD | `0aa844a` | `VERIFIED` |
| Another writer active? | Session `d1740817` committed 10× on 2026-09-23 up to 23:56, then **idle 18+ min**, 0 new commits during this phase | `VERIFIED` |
| Stable baseline established | `0aa844a`; router byte-identical to `fbee6d5` | `VERIFIED` |
| Router routes | **91** (89 in a release build) | `VERIFIED` |
| Distinct widgets built | **88** (3 aliases) | `VERIFIED` |
| Designed routes | **45** | `LOCALLY_VERIFIED` — `dart tool/fit_backlog.dart` |
| **FIT-001 / `home_org.dart`** | **RESOLVED** — see §3 | `LOCALLY_VERIFIED` |
| **Orphan count** | **RESOLVED at 7** — see §4 | `LOCALLY_VERIFIED` — `dart tool/orphan_route_sweep.dart` |
| FIT interaction backlog | 287/600; LOCKED 129/179; **only 10 of 29 locked anchors complete AND reachable** | `LOCALLY_VERIFIED` |
| Unreachable FIT anchors | **6** — FIT-006, 019, 071, 072, 073, 074 | `LOCALLY_VERIFIED` |

---

## 3 · FIT-001 discrepancy — RESOLVED

`DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` mapped FIT-001 Home to `home_org.dart`, which is
**dead** (zero real importers; `app_scaffold.dart:4` names it dead). The router imports
`home_screen.dart:24`. Cause: **two classes named `HomeScreen`** defeated a filename-based
resolver.

`dart tool/fit_backlog.dart` resolves through the router's builder and reports
**FIT-001 → `/home` 9/9 [34 files]** — correct. The new tooling supersedes the old matrix.

**Residual:** `home_org.dart` still exists and will defeat the next resolver → **OD-32**.

---

## 4 · Orphan discrepancy — RESOLVED at 7

Three independent methods agree — this audit's navigation pass, hand verification of each
contested route, and the repository's own sweep:

```
registered 91 · navigated 79 · externally entered 5 · ORPHANED 7
```

`/coach` · `/coach-business` · `/food-search` · `/log-meal` · `/nutrition-overview` ·
`/onboarding` · `/pods`

The earlier 11-vs-5 spread is explained: `directory_screen.dart` navigates through a
data-driven `const _Module(route: …)` list invisible to a literal call-scan (hence
`/insights`, `/action-items`, `/events` are **not** orphans), and `qa_suites.dart` is a
gated-route **test manifest, not navigation**. `/activity`, `/meal-plan` and `/goals` were
fixed by the concurrent workstream before this baseline.

---

## 5 · Required deliverable lists

### 5.1 Screens implemented this phase — **0**

`VERIFIED`. No production file was created, modified or deleted. Reason in §1.

### 5.2 Screens still missing — **10**

| ID | Screen | Class | Status |
|---|---|---|---|
| MCS-01 | Pods (4 anchors) | Built, designed, **unreachable** | `OWNER_DECISION_REQUIRED` (OD-33) |
| MCS-02 | Log a meal | Stub, locked anchor, **unreachable** | `OWNER_DECISION_REQUIRED` (OD-34) |
| MCS-03 | Welcome | Built, locked, **unreachable** | `OWNER_DECISION_REQUIRED` (OD-31, pre-existing) |
| MCS-04 | Event ticket | Built, unrouted | `OWNER_DECISION_REQUIRED` (OD-4, pre-existing) |
| MCS-05 | Report / moderate | Absent | `BLOCKED` — MISSING_DESIGN + policy |
| MCS-06 | Client message inbox | Absent | `BLOCKED` — MISSING_DESIGN |
| MCS-07 | Coach profile & reviews | Absent | `BLOCKED` — MISSING_DESIGN |
| MCS-08 | Class check-in pass | Absent | `BLOCKED` — MISSING_DESIGN + CG-01 |
| MCS-09 | Delete account & export | Absent | `BLOCKED` — MISSING_DESIGN + legal |
| MCS-10 | Community group detail | Absent | `BLOCKED` — MISSING_DESIGN |

### 5.3 Designs with no implementation — **0**

`LOCALLY_VERIFIED`. Category C is empty; all 45 designed routes are built.

### 5.4 Implementations with no design — **41**

13 client routes · 14 coach routes · 8 unrouted screens · 6 required-but-absent surfaces.
Enumerated in [`DESIGN_CAPABILITY_GAPS.md`](DESIGN_CAPABILITY_GAPS.md) §4.

### 5.5 Unsupported design features preserved — **6**

`POST-QA`. None was designed downward. Detail in `DESIGN_CAPABILITY_GAPS.md` §3.
The largest is **FIT-022 "Loading & failure"**: the design declares a cross-cutting pattern;
the codebase has **no shared loading/empty/error/retry widget** (`_EmptyState` is privately
re-declared 10× with 10 signatures), **zero offline handling**, and **25 major screens with
no error state at all**.

### 5.6 Missing designs requiring future design work — **41**

`OWNER_DECISION_REQUIRED` (OD-35 commissions them). Same 41 as §5.4, viewed as design demand.

---

## 6 · Verification status — honest reporting

| Verification | Status | Detail |
|---|---|---|
| Mechanical inventory | `LOCALLY_VERIFIED` | `orphan_route_sweep.dart` and `fit_backlog.dart` executed; outputs read |
| Unit / widget tests | **`BLOCKED`** | **Not run.** See §6.1 |
| Mutation tests | **`BLOCKED`** | No new guards were written (nothing implemented), so none to mutate |
| Device runtime | **`BLOCKED`** | Emulator needs ~7.4 GB free; 448 MB available |
| CI | `CI_VERIFIED` — **not claimed** | No CI run was triggered or observed by this phase |
| Security | `VERIFIED` (source only) | §8. No database contacted |
| Accessibility | `VERIFIED` (source only) | §9 |

### 6.1 Environmental blocker — disk

**The volume is 98% full with 448 MB free.**

Project memory records that `flutter test` on a full disk **hangs with no output and never
returns**, with `.dart_tool/flutter_build` growing to ~7 GB. `.dart_tool` currently holds
only 170 MB, so it is not the consumer.

The suite was **deliberately not run**. Running it would likely hang and could destabilise
the machine; reclaiming space is destructive and requires approval (**Phase 10 (4)**).

> This plausibly also affects the concurrent session, which had been committing
> test-bearing work every 10–15 minutes and stopped at 23:56. Worth checking before it is
> assumed to have finished.

---

## 7 · Concurrency — the governing constraint

Session `d1740817` committed 10 times on 2026-09-23 (`23:11`, `23:14`, `23:24`, `23:39`,
`23:45`, `23:56`, …) implementing FIT anchors and building
`tool/orphan_route_sweep.dart` + `test/unit/orphan_route_guard_test.dart`.

**That is the same workstream any screen-integration work here would touch.** Repository
governance is explicit — `COWORK_AGENT_REGISTRY.md` §21: *"Parallel agents must not modify
the same high-conflict file… If ownership conflicts: STOP."*

Its orphan guard is a **shrinking allowlist checked in both directions**: an unlisted orphan
fails as new, **and a listed one that gains a door also fails**. So any orphan fix must
update the guard in the same change — a coupling owned by that session.

**Two audits run blind to each other converged**: its sweep reports exactly the same 7
orphans, and it independently identified the data-driven `_Module` list as the reason
`/events` looked orphaned. That convergence is the strongest available evidence that both
inventories are correct.

**Files deliberately not touched:** `app_router.dart`, any screen, `docs/QA_EVIDENCE.md`,
`docs/FIT_INTERACTION_COVERAGE.md`, `tool/*`. Only **new** documents were written.

---

## 8 · Security findings — source-verified, carried forward

Unchanged at this baseline and **not yet remediated**. Full evidence in
[`SCREEN_ECOSYSTEM_AUDIT.md`](SCREEN_ECOSYSTEM_AUDIT.md) §10.

| ID | Finding | Severity |
|---|---|---|
| S-1 | **Tier escalation by one INSERT** — migration 113's policy lets a client create their own `active` `coach_client_relationships` row naming any enumerable coach; `client_plan()` then resolves `coach_guided`. **A free account unlocks every gated route** | **HIGH** |
| S-2 | **Five AI tables with no RLS** — `ai_profiles`, `ai_memories`, `ai_insights`, `ai_reviews`, `ai_goal_predictions` (074). `ai_memories.kind` includes `injury \| constraint`. Any authenticated client reads/writes every member's AI coaching memory. **Not in the existing ledger** | **HIGH** |
| S-3 | **Two unauthenticated orphan edge functions** — `notify-coach-email` reads no Authorization header and interpolates caller input raw into mail to every coach; `send-checkin-reminder` likewise, never scheduled | **MEDIUM-HIGH** |
| S-4 | **Zero of 91 routes carries a role guard**; 3 of 7 admin/vendor screens self-guard not at all; **12 routes enforced at no layer**, 5 of which let a client create coach-owned records | **MEDIUM** |
| S-5 | `/intake` and `/onboarding` are in `isAuthRoute` → reachable **unauthenticated** | **LOW-MEDIUM** |

**Memory correction, re-confirmed:** the 115/119 regressions were real, but **124 restored
`materialize_program_week`'s guard and 126 fixed `derive_parq_risk()`**. The "unfixed" note
is stale *in source terms*; production state was not checked — no database was contacted.

---

## 9 · Accessibility findings — source-verified

| Finding | Status |
|---|---|
| **No shared loading/empty/error/retry widget exists** — `_EmptyState` privately re-declared 10× with 10 signatures | `VERIFIED` |
| **25 major screens have no error state at all**, incl. `booking_screen.dart` (949 lines, zero `error:`) and the intake flow (one `error:` branch in 5,841 lines) | `VERIFIED` |
| **Zero offline handling app-wide** — no `connectivity_plus`, no `SocketException` handling, 0 of 98 screens | `VERIFIED` |
| **Loading renders as "unauthorized"** on 5 role-gated screens — a real coach sees *"Coaches only."* until the profile arrives | `VERIFIED` |
| **Error conflated with empty** in 4 places — a failed fetch tells the user there is nothing there | `VERIFIED` |
| Screen-reader labels / contrast / touch targets | **`BLOCKED`** — requires device runtime (§6.1) |

---

## 10 · Owner decisions

### New — raised by this phase

| ID | Decision | Blocks |
|---|---|---|
| **OD-32** | **Delete the dead/duplicate surfaces?** `home_org.dart` (caused the FIT-001 error and will recur), `dash_org.dart`, `dashboard_screen.dart`, `profile/subscription_screen.dart`, `embedded_checkout_screen.dart`, `coach_pricing_sheet.dart`, `log_weight_sheet.dart`, and alias routes `/coach`, `/nutrition-overview`. **Destructive** | §3 residual; 9 surfaces |
| **OD-33** | **`/pods`** — four designed anchors, **no declared entry anywhere in the package**. Add a Connect/Community entry (a design decision), or retire? | MCS-01 |
| **OD-34** | **FIT-019 "Log a meal"** — a distinct screen, or re-anchor the locked anchor to `/meals-dashboard`? **A paying `selfGuided` user currently cannot log a meal by any route** | MCS-02 |
| **OD-35** | **Commission the 6 missing-design surfaces** (MCS-05…10) as a package addendum? Two are store-review gates | MCS-05…10 |
| **OD-36** | **Reclaim disk** (98% full, 448 MB free) so tests and device runtime can execute? Destructive | §6.1 — all runtime verification |
| **OD-37** | **Pause or sequence the concurrent session** so screen-integration work has a single owner | §7 — all implementation |
| **OD-38** | **Generate the 110 reference PNGs** (`node capture-references.mjs`) — without them **no screen can be accepted**, including the 45 already built | All design acceptance |

### Pre-existing, re-confirmed

**OD-4** event-ticket navigation (= MCS-04) · **OD-31** FIT-006 Welcome orphan (= MCS-03).

---

## 11 · What moves to the next engineering phase

| Workstream | Owner | Gate |
|---|---|---|
| FIT interaction backlog (287/600) | Concurrent session `d1740817` | OD-37 |
| Orphan route remediation (7) | Blocked | OD-32/33/34 |
| Design addendum — 41 surfaces | Design | OD-35 |
| Security S-1…S-5 | Security | **S-1, S-2 are HIGH and unremediated** |
| Capability gaps CG-01…06, FC-01…14 | `POST-QA` | Preserved, not designed downward |
| Runtime + a11y verification | Blocked | OD-36 |
| Design acceptance | Blocked | OD-38 |

---

## 12 · Deliverables

| Document | Phase |
|---|---|
| `SCREEN_ECOSYSTEM_FINAL_AUDIT.md` | this |
| [`DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md`](DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md) | 2 — canonical inventory, 91 routes, A–N |
| [`MISSING_CLIENT_SCREENS.md`](MISSING_CLIENT_SCREENS.md) | 3 — 10 records, full schema |
| [`DESIGN_CAPABILITY_GAPS.md`](DESIGN_CAPABILITY_GAPS.md) | 5 + 9 — 6 CG, 14 FC, 6 preserved, 41 MD |
| [`SCREEN_ECOSYSTEM_AUDIT.md`](SCREEN_ECOSYSTEM_AUDIT.md) | prior-phase input, superseded on FIT-001 and orphan count |
| [`SCREEN_INVENTORY.json`](SCREEN_INVENTORY.json) · [`SCREEN_ROUTE_GRAPH.md`](SCREEN_ROUTE_GRAPH.md) | prior phase |

FIT backlog evidence and QA evidence remain in `FIT_INTERACTION_COVERAGE.md` and
`QA_EVIDENCE.md`, **owned by the concurrent session and deliberately not edited here**.

---

*Audit and specification only. No screen was implemented or designed. No production file was
created, modified or deleted. No database was contacted. Nothing was committed or pushed.*
