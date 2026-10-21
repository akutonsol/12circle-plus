# 12 Circle Fitness — Screen Gap Summary

**Executive summary.** Baseline `0aa844a`, 2026-09-24. Read-only: no production file was
created, modified or deleted. Machine-readable twin:
[`FINAL_SCREEN_INVENTORY.json`](FINAL_SCREEN_INVENTORY.json) (v3.0).

---

## 1 · The two registers, kept separate

> **A designed anchor that is unimplemented is an IMPLEMENTATION gap, not a missing screen.**
> **A required product surface with no design frame is a DESIGN COMMISSION.**

| | Count |
|---|---|
| **SECTION 1 — existing designs requiring implementation** | **32 anchors at 0/N**, plus 56 partial |
| **SECTION 2 — NEW SCREEN DESIGNS REQUIRED** | **48** |

A route is **not** "implemented" because its `GoRoute` exists or its widget renders.
Completeness is measured against the declared design surface.

---

## 2 · Required counts

| Measure | Value |
|---|---|
| **Total known product surfaces** | **148** |
| **Complete** | **19 anchors** (routes: `/active-workout` is the only fully-built area) |
| **Partial** | **56 anchors** |
| **Designed but substantially unimplemented** | **32 anchors**, across 20 targets |
| **Completely missing from design** | **48** (8 missing both · 40 implemented-but-undesigned) |
| **Stub / placeholder** | **5** (3 on designed routes, 2 undesigned) |
| **Orphaned** | **7 routes**, stranding **6 anchors** |
| **Duplicate / dead** | **9** |
| **Future capabilities** | **15** |
| **⇒ EXACT NEW SCREEN DESIGNS REQUIRED** | **48** |

Supporting: 91 routes (89 in release) · 45 carry ≥1 anchor · 46 carry none ·
287/600 interactions present · 10 of 29 locked anchors complete **and** reachable ·
34 of 230 providers never consumed.

---

## 3 · The findings that drive both registers

1. **The design package is client-only.** Of ~21 coach surfaces it contains **two** —
   FIT-032 Coach dashboard and FIT-033 Check-in review — and **zero** admin or vendor
   anchors. This is the single largest design gap and accounts for 19 of the 48 commissions.

2. **Whole designed areas are unbuilt.** All 5 `/class-detail` anchors, all 4 `/pods`, both
   `/action-items`, both `/grocery-list`, both `/ai-nutrition` sit at 0/N. These are
   **implementation** work — the designs exist.

3. **Six anchors are designed, built, complete and unreachable** — FIT-006 Welcome (2/2,
   locked), FIT-019 Log a meal (4/5, locked), FIT-071…074 Pods, FIT-086 Event ticket.
   Finished work no user can open.

4. **A paying `selfGuided` customer cannot log a meal.** `/log-meal` is a 23-line redirect
   stub, orphaned, against a **locked** anchor at 4/5.

5. **34 of 230 providers are declared and never consumed, clustering exactly where the design
   is unbuilt** — `liveHabitsProvider`↔FIT-058 0/5, `selectedPostProvider`↔FIT-066 3/9,
   `weightLogsProvider`↔FIT-055 0/2. Two independent evidence streams, neither derived from
   the other.

6. **Content moderation and account deletion do not exist** in code, schema or design. Both
   are app-store review gates.

---

## 4 · Discipline applied — what was NOT commissioned

Four candidates from the previous pass were **withdrawn** because an anchor already covers
them: *my assigned programme* (FIT-014/015), *my nutrition plan* (FIT-091…093), *check-in
history* (FIT-023), *pending coach request* (a **state**, per FIT-028/FIT-097). Their unused
providers are implementation gaps.

Eleven "collapsed surfaces" from the previous pass were **moved to Section 1** — FIT-066,
067, 071, 072, 087, 088, 055, 056, 103, 104, 105/106 are all designed; they need building,
not commissioning. Two of them (FIT-087/088, FIT-055/056) are **modals**, not screens, as
their own anchor names state.

Three remain **open questions, not commissioned**: *my bookings* (FIT-080 may subsume it as a
tab), *food search* (may be a sub-surface of FIT-019), and the `/nutrition` gateway (a delete
candidate).

Also excluded with reason: 20 substrate tables behind RPCs · Dark Mode / Language / Sound
Effects (controls, not screens) · Terms of Service (route exists, link missing) ·
notification routing (blocked by H-07) · 4 dead-end CTAs in files nothing imports · global
search (**no evidence**) · 3 legal pages and 4 system routes (design not required).

---

## 5 · Owner decisions

**Gating the whole design phase — OD-38:** every manifest entry cites
`referenceImage: screens/FIT-0NN.png`; the package has **no `screens/` directory**, and
*"Matches `screens/<ID>.png`"* is the first item of every Definition of Done. **No screen can
be accepted today — including the 19 that are complete.**

Others: **OD-33** `/pods` entry or retire · **OD-34** FIT-019 identity · **OD-35** commission
the 8 missing-both surfaces · **OD-32** delete the 9 dead/duplicate surfaces · **OD-36**
reclaim disk (98% full) · **OD-37** sequence the concurrent session. Re-confirmed: **OD-4**
event-ticket navigation · **OD-30** coach access to PAR-Q (blocks N-07) · **OD-31** FIT-006.

---

## 6 · Carried forward, unresolved

Security findings remain unremediated: **S-1** a free account self-promotes to the top paid
tier with one INSERT; **S-2** five AI tables holding `injury | constraint` memories have no
RLS. Both HIGH.

---

## 7 · Verification status

`VERIFIED` route table, provider consumption, dead-end controls, settings rows, schema gaps,
anchor–route mapping · `LOCALLY_VERIFIED` FIT coverage and orphan counts (repo tools
executed) · `RUNTIME_VERIFIED` **none** — volume 98% full, 448 MB free; project practice is
that under ~3 GB device verification cannot run and must not be claimed · `CI_VERIFIED`
**none** · `OWNER_DECISION_REQUIRED` 9 items.
