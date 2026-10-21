# 12 Circle Fitness — Screen Design Gaps (SECTION 1: implementation backlog)

> **Scope note.** Everything in this document is **already designed**. It is the
> implementation backlog, not a design commission. Surfaces needing *new* design are in
> [`MISSING_SCREEN_REGISTER.md`](MISSING_SCREEN_REGISTER.md) §Section 2.

**Screens that EXIST but need redesign, completion, or materially different states.**
Baseline `0aa844a`. Measured with `dart tool/fit_backlog.dart` against the authoritative
manifest.

Distinct from `MISSING_SCREEN_REGISTER.md`: those screens do not exist. **These do — and are
materially incomplete against their own approved design.**

## 1 · Headline

| Measure | Value |
|---|---|
| Anchors **complete** (n/n) | **19 of 110** |
| Anchors **partial** (0<n<total) | **56** |
| Anchors at **0/N — design effectively unbuilt** | **32** across 18 routes |
| Declared interactions present | **287 / 600** |
| LOCKED anchors complete **and reachable** | **10 of 29** |

> The repo's own tool warns text-presence is *"weak evidence of presence"* but *"reasonably
> strong evidence of absence"*. The **0/N rows below are therefore high-confidence**; the
> partial rows are a worklist, not a closure claim.

## 2 · Zero-coverage anchors — the design is not built

| Anchor | Coverage | Screen | Route |
|---|---|---|---|
| FIT-095 | **0/15** | Grocery list — built | `/grocery-list` |
| FIT-100 | **0/9** | Action items — what your coach set | `/action-items` |
| FIT-089 | **0/7** | AI nutrition — conversation | `/ai-nutrition` |
| FIT-071 | **0/6** | Pods hub | `/pods` |
| FIT-072 | **0/5** | Pod detail | `/pods` |
| FIT-058 | **0/5** | Habits | `/habits` |
| FIT-103 | **0/5** | AI Coach — today | `/ai-coach` |
| FIT-088 | **0/5** | Cancellation — confirm → cancelled | `/class-detail` |
| FIT-104 | **0/5** | AI Coach — the week | `/ai-coach` |
| FIT-090 | **0/4** | AI nutrition — a turn that failed | `/ai-nutrition` |
| FIT-085 | **0/4** | Events hub | `/events` |
| FIT-110 | **0/4** | AI Coach — coming back | `/ai-coach` |
| FIT-046 | **0/3** | Photo source | `sheet — /intake, /progress` |
| FIT-063 | **0/3** | Women's health | `/womens-health` |
| FIT-082 | **0/3** | Class — full / waitlist | `/class-detail` |
| FIT-076 | **0/3** | Challenge detail — active | `/challenge-detail` |
| FIT-083 | **0/3** | Class — booked / live / cancelled | `/class-detail` |
| FIT-086 | **0/3** | Event ticket | `event_ticket_screen (unrouted)` |
| FIT-098 | **0/2** | Booking — nothing open, and loading | `/appointments` |
| FIT-055 | **0/2** | Log weight | `/progress` |
| FIT-093 | **0/2** | Meal plan — it didn’t build | `/meal-plan` |
| FIT-059 | **0/2** | Goals | `/goals` |
| FIT-081 | **0/2** | Class detail | `/class-detail` |
| FIT-074 | **0/2** | Pods — empty + loading | `/pods` |
| FIT-101 | **0/2** | Action items — empty, loading, failed | `/action-items` |
| FIT-087 | **0/2** | Booking sheet — confirm → confirmed | `/class-detail` |
| FIT-061 | **0/1** | Insights | `/insights` |
| FIT-077 | **0/1** | Who else is in | `/challenge-detail` |
| FIT-078 | **0/1** | Challenge — upcoming · completed · expired | `/challenges` |
| FIT-034 | **0/1** | Intake welcome | `/intake` |
| FIT-060 | **0/1** | Score | `/score` |
| FIT-049 | **0/1** | Generating plan | `/intake` |

**32 anchors across 20 implementation targets — 18 registered routes plus 2 unrouted (`event_ticket_screen`, and the photo-source sheet shared by `/intake` and `/progress`).**

## 3 · State-completeness gaps — a cross-cutting design need

**FIT-022 "Loading & failure" declares a cross-cutting pattern the codebase does not have.**

| Finding | Evidence |
|---|---|
| **No shared empty/error/loading/retry widget exists anywhere** | `_EmptyState` privately re-declared **10×** with 10 different constructor signatures |
| **Zero offline handling app-wide** | no `connectivity_plus`, no `SocketException` handling — 0 of 98 screens |
| **25 major screens have no error state at all** | incl. `booking_screen.dart` (949 lines, zero `error:`) and `intake_flow_screen.dart` (one `error:` branch in 5,841 lines) |
| **Loading renders as "unauthorized"** | 5 role-gated screens reject on a `null` role before the profile arrives — a real coach sees *"Coaches only."* |
| **Error conflated with empty** | 4 places tell the user there is nothing there when a fetch failed |

This is **one design deliverable** (a state system) that resolves a defect class across the
whole product, and it is already design-supported by FIT-022.

## 4 · Screens carrying several product jobs

Each hosts jobs the product would normally separate. Detail in
`MISSING_SCREEN_REGISTER.md` §4.

| Screen | Lines | Distinct jobs crammed in |
|---|---|---|
| `intake_flow_screen.dart` | 5,841 | **27 steps, only 19 designed anchors** — 8 steps have no design |
| `community_screen.dart` | — | feed + **create post** + **post detail/comments** |
| `ai_coach_screen.dart` | — | conversation + **memory management** + **Today brief** + **Week brief** |
| `progress_screen.dart` | — | 3 tabs + **log weight** + **log measurements** |
| `class_detail_screen.dart` | — | detail + **booking confirm** + **cancellation confirm** + waitlist |
| `meals_dashboard_screen.dart` | 1,443 | dashboard + logging (absorbing the `/log-meal` stub) |
| `create_exercise_screen.dart` | 1,143 | 4-tab creation, **no error state** |

## 5 · Undesigned intake steps

The implementation has **27 steps**; **19** anchors are designed. Steps with no designed
anchor include the weight-goal summary, activity level, training location, lifestyle,
protein confidence, biggest challenges, **"Generating plan"** and **consent**.

`FIT-049 "Generating plan"` is designed at **0/1** — and the implemented step is theatre:
`_runProgress()` walks a hardcoded `[20,45,70,90,100]` on 700 ms delays while the real
`generate_client_plan` RPC fires two steps later **and its failure is swallowed**.

## 6 · Fabricated data presented as measured

Design-relevant because a design cannot be accepted against invented data.

| Screen | Evidence |
|---|---|
| `/activity` | `stepsProvider = StateProvider<int>(6240)`, water counter — **no table, no persistence, resets every launch**. FIT-064 measures **1/12** |
| `/coach-business` | `coach_revenue_service.dart:68` returns an all-zero map on failure → renders **$0 MRR / 0 subscribers** as if measured |
| `DashboardScreen` (dead) | `dashboard_service.dart:3` returns 100% hardcoded literals |

## 7 · Blocker on all design acceptance

Every manifest entry cites `referenceImage: screens/FIT-0NN.png`. **The package contains no
`screens/` directory** — the PNGs must be generated by `node capture-references.mjs`.
*"Matches `screens/<ID>.png`"* is the **first item of the per-screen Definition of Done**, so
**no screen can currently be accepted — including the 19 complete ones.** → **OD-38**
