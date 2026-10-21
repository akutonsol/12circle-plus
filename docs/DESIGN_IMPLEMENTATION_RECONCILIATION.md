# 12 Circle Fitness — Design ↔ Implementation Reconciliation

**Read-only audit deliverable.** Baseline `fbee6d5`.

Supersedes nothing. This document **verifies and corrects**
[`DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md`](DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md) rather than
replacing it, and records one material error in it.

---

## 1 · Which design package is authoritative — verified

| | |
|---|---|
| Package | `~/Downloads/12circle-fitness-new-screens.zip` → `fitness-handoff/` |
| sha256 | `d4438803deee0984875998fa93c63548fc011eef55d34f5e766510d5fad88d32` — **re-verified, exact match** |
| Size / files | 1,826,216 bytes · 21 files |
| Manifest | `manifest.json`, **110 screens**, FIT-001…FIT-110, no gaps |
| Locked anchors | 29 · Waves 33 / 31 / 24 / 13 / 9 |

**The intake report's authority claim stands.** The hash still matches, so
`DESIGN_INTAKE_REPORT.md` is not invalidated.

### 1.1 The "rejected" legacy package is not a conflict

`~/Documents/projects/helix-design-references/12circle fitness/fitness-app-board/` was
compared file by file: **15 of 17 files are byte-identical**, including the board itself
(same sha `edcce7a5…`) and all seven design documents. Only `README.txt` and a logo PNG
differ.

The authoritative package = the legacy package **plus** `manifest.json`,
`DESIGN_HANDOFF.md`, `IMPLEMENT-THIS.md` and `capture-references.mjs`.

**Recommendation:** restate it in `DESIGN_INTAKE_REPORT.md` as **superseded**, not
**rejected** — "rejected" implies a competing design, and there is none.

### 1.2 `docs/design/12CIRCLE-FITNESS-COMPLETE-UI-AUDIT.md` — older and narrower

Two premises in circulation about this file are wrong. It **is tracked** (`git ls-files`
returns it), and it is an **older, narrower** document (2026-09-09, HEAD `bbe0448`),
numbered #1–29, never using FIT ids, covering only the 29 locked anchors.

Its own §17 is decisive: *"`docs/design/` does not exist in the repo and no design board
artifact exists"* — **its author never saw the board.** Its §16 "Missing Design Inventory"
is therefore **largely obsolete**: it lists Splash, Sign-up, Progress tabs, Habits, Goals,
Score, Community and AI Coach as undesigned, and the 110-screen package covers all of them.

Still valuable in it: the 13-route PaywallGate list, the orphan/alias inventory, and the
identification of `/coach` as an alias of `/train`.

---

## 2 · The existing matrix — confirmed, with three caveats

| Matrix claim | Verdict |
|---|---|
| 110 FIT screens | ✅ confirmed |
| 105 mapped to a route | ✅ confirmed |
| 5 unmapped | ✅ confirmed |
| 29 locked anchors | ✅ confirmed |
| 45 distinct implementing files | ✅ confirmed |
| 91 `GoRoute` declarations | ✅ confirmed |
| *"Every design route already exists in the application"* | ✅ **confirmed — all 45 designed routes are registered; zero missing** |

### CAVEAT A — "50 distinct repo routes" is misleading

Arithmetically true but semantically wrong: it counts the 5 pseudo-routes that the same
document marks `NO-ROUTE`. **The real number of distinct designed routes is 45.**
(Confusingly, distinct implementing *files* is also 45 — two different 45s.)

### CAVEAT B — the PaywallGate count is stale by one

The design package records 12 gated routes. **The router wraps 13.** `/ai-coach`
(`aiGuided`) and `/book-call` (`coachGuided`) are the two beyond the design's count.

### CAVEAT C — **material error: FIT-001 is mapped to dead code**

`DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` resolves **FIT-001 Home** — the flagship locked
anchor — to `home/presentation/home_org.dart`.

**That file is dead.** It has zero importers, `shared/widgets/app_scaffold.dart:4` names it
"dead… never instantiated", and the router imports `home/presentation/home_screen.dart:24`.
A **duplicate `class HomeScreen` declared in both files** defeated the matrix's resolver.

All 45 designed routes were re-resolved during this audit: **44 correct, this one wrong.**
Any integration work driven by the matrix would have been applied to a file no user reaches.

---

## 3 · Design status by route

Classification per the audit schema:
**A** current design exists · **B** design exists, implementation missing ·
**C** implementation exists, current design missing · **D** both exist ·
**E** design outdated/conflicting · **F** no design discovered · **G** unknown

| Status | Count | Meaning here |
|---|---|---|
| **D — design + implementation** | **45** | All designed routes are built |
| **C — implementation, no current design** | **46** | Built surfaces the package does not cover |
| **B — design, no implementation** | **0** | No designed screen is unbuilt |
| **E — outdated/conflicting** | **1** | FIT-001 → dead file (Caveat C) |
| **F / G** | 0 | — |

**Coverage: 45 of 91 routes (49.5%).**

### 3.1 The 46 undesigned routes are not 46 units of work

| Category | Count | Note |
|---|---|---|
| Coach product surfaces | ~17 | A coherent undesigned product area |
| Admin / vendor / QA | 9 | 2 never ship (`!kReleaseMode`) |
| Aliases & duplicates | 3 | `/coach`, `/book-call`, `/nutrition-overview` |
| Legal / static | 3 | privacy, terms, help |
| **Genuine undesigned client surfaces** | **~15** | The real design gap |

### 3.2 Design concentration

The 110 screens map onto only 45 routes, very unevenly:

| Route | FIT screens |
|---|---|
| `/intake` | **19** |
| `/ai-coach` | 9 |
| `/progress` | 6 |
| `/community` | 6 |
| `/class-detail` | 5 |
| `/pods` | 4 |
| 26 other routes | 1 each |

**`/intake` carries 19 FIT screens — and the implementation has 27 steps.** The design
package does not cover the whole flow. Steps present in code but not in the design include
the weight-goal summary, the "Generating plan" screen and the consent step.

---

## 4 · The 5 FIT screens with no route — all deliberate

| FIT | Screen | Why it has no route |
|---|---|---|
| FIT-020 | AI meal scan | Embedded widget inside `/log-meal` |
| FIT-021 | Entitlement gate | The `PaywallGate` wrapper itself |
| FIT-022 | Loading & failure | Cross-cutting pattern, not a destination |
| FIT-046 | Photo source | Reusable sheet shared by `/intake` and `/progress` |
| **FIT-086** | **Event ticket** | **Built but unrouted** — `EventTicketScreen` is push-only. Open owner decision |

Only FIT-086 is a real gap; it is MSR-08 in the missing-screen register.

---

## 5 · Blocker — the acceptance baseline is unbuildable

Every one of the 110 manifest entries cites `referenceImage: screens/FIT-0NN.png`.

**There is no `screens/` directory in the package.** The 110 PNGs must be generated by
running `node capture-references.mjs`.

Since *"Matches `screens/<ID>.png`"* is the **first item of the per-screen Definition of
Done**, no screen can currently be accepted against the design. This blocks verification of
all 45 designed routes, not merely new work.

---

## 6 · Reconciliation actions

Nothing below was performed — this is an audit.

| # | Action | Rationale |
|---|---|---|
| 1 | Correct FIT-001's mapping to `home_screen.dart` | Caveat C — flagship anchor points at dead code |
| 2 | Generate the 110 reference PNGs | §5 — acceptance is otherwise impossible |
| 3 | Restate the legacy package as *superseded* | §1.1 — it is a byte-identical subset |
| 4 | Correct the matrix's "50 distinct routes" to 45 | Caveat A |
| 5 | Update the design's gated-route count to 13 | Caveat B |
| 6 | Mark `12CIRCLE-FITNESS-COMPLETE-UI-AUDIT.md` §16 obsolete | §1.2 — written without sight of the board |
| 7 | Decide whether `/intake` design covers 19 or 27 steps | §3.2 |
| 8 | Delete or design the duplicate-class dead files | MSR-21/22 — `home_org.dart` caused Caveat C and will cause it again |

> **Note.** A concurrent session is actively generating `docs/FIT_INTERACTION_COVERAGE.md`
> from `apps/mobile/tool/fit_backlog.dart`, which measures FIT interaction-label presence
> per route. That document and this one are complementary: it measures *coverage depth*
> within designed routes; this measures *which routes have a design at all*. Its own header
> warns its text-presence heuristic is "weak evidence of presence" with seven false
> positives already found — treat its per-screen numbers accordingly.
