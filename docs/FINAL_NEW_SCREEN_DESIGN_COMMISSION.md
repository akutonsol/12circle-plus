# 12 Circle Fitness — FINAL New Screen Design Commission

**Authoritative input to the design phase.** Baseline `0aa844a`, 2026-09-24.
Read-only audit — no production file was created, modified or deleted; no screen was designed.

**48 provisional candidates → 40 confirmed → 8 reclassified.**

---

## 0 · OD-38 — RESOLVED

The gate blocking all design acceptance is closed.

| | |
|---|---|
| FIT reference images found anywhere on the machine | **0 of 110** |
| `screens/` directory in either package | **absent** |
| **Regenerated from the authoritative board** | **110 of 110** ✅ |
| Verification | avg 158 KB, min 52 KB, **none blank**, 1170 px wide (390 × `deviceScaleFactor: 3`, matching the manifest viewport) |

**The images were never lost — they are derived artifacts.** The board
`12Circle Fitness - Complete Board.dc.html` is the source of truth, and
`capture-references.mjs` regenerates them. The generator asserts
`frames.length === manifest.screens.length`; the board contains **exactly 110 `.phone`
frames** and the assertion passed, which independently confirms board and manifest are in
sync.

Regeneration command (≈3 minutes, from the package root):

```bash
npm i -D playwright && npx playwright install chromium && node capture-references.mjs
```

Currently generated to the session scratchpad at
`design-pkg/fitness-handoff/screens/`. **Not copied into the repository**, consistent with
`DESIGN_INTAKE_REPORT.md` (*"nothing was copied into this repository"*).
**OD-39 (new, minor):** decide where the baseline images should live durably — they are
regenerable on demand, so this is a convenience decision, not a blocker.

> The earlier disk blocker (OD-36) has also cleared on its own: **5.6 GB free, 76% used**
> (was 448 MB / 98%).

---

## 1 · Reconciliation outcome

Each of the 48 was re-tested against the complete design evidence, now including the
rendered reference images.

| Verdict | Count | Disposition |
|---|---|---|
| **A — definitely requires a new design** | **40** | **COMMISSIONED** |
| B — already represented by another anchor | 0 | — |
| C — should be an implementation of an existing design | 0 | (14 were already moved to Section 1 in the prior pass) |
| D — should be a state/modal/sheet | 0 | (4 were already downgraded in the prior pass) |
| **E — requires an owner decision before design** | **7** | admin/vendor scope |
| **F — insufficient evidence, do not commission** | **1** | N-08 |

### 1.1 · The evidence upgrade

Re-reading the manifest against the renders showed that **existing LOCKED anchors declare
several candidates as destinations without designing them.** This is materially stronger
evidence than "a route exists with no design":

| Declaring anchor | Declares | Candidate it requires |
|---|---|---|
| **FIT-001 Home** (locked) | `Directory` | `/directory` |
| **FIT-014 Workouts hub** (locked) | `History`, `Exercise library` | `/workout-history`, `/exercise-library` |
| **FIT-015** (locked) | `Browse the exercise library` | `/exercise-library` |
| **FIT-029 Profile** (locked) | `Personal information`, `Connected apps 2` | `/personal-info`, `/integrations` |
| **FIT-032 Coach dashboard** (locked) | `Adherence`, `Programs`, `All 24 clients`, `Review` | `/compliance`, `/program-builder`, `ClientDetailScreen` |
| **FIT-033 Check-in review** (locked) | `Adjust plan` | programme-adjust surface |
| **FIT-023 Check-in hub** | `Measurements` | measurement surface (→ Section 1, FIT-056 exists) |

### 1.2 · Reclassified — 8

| Item | Verdict | Reason |
|---|---|---|
| **N-08** Exercise moderation review log | **F — insufficient evidence** | `exercise_reviews` (058:111) has no reader, no navigation, no workflow, and the admin surfaces use `ai_reviews` / RPC `review_exercise_content` instead. One orphaned table is not enough to commission a screen |
| `/admin-dashboard`, `/admin-exercise-review`, `/content-center`, `/observability`, `/content-review`, `/knowledge-review`, `/vendor-portal` | **E — owner decision** | The package contains **zero** admin or vendor anchors. That may be deliberate scoping (internal tooling), not an oversight. **OD-40:** is admin/vendor tooling in the design scope at all? |

### 1.3 · Confirmed against a dedup challenge

Two candidates were challenged and **survived**:

- **`/exercise-library` vs `/exercise-database`** — distinct. Library (288 lines) is the
  client browse declared by FIT-014/015, reached from the directory and train hub. Database
  (495 lines, titled *"Exercise Database"*) carries custom-exercise management and is reached
  from the **coach dashboard**. Different audiences, different jobs.
- **`/workouts` vs `/train`** — distinct. `/train` is the designed hub (FIT-014/015);
  `/workouts` is a sub-surface pushed **from** it (3 call sites in `train_hub_screen.dart`)
  plus the directory and workout history.

---

# THE COMMISSION — 40 SCREENS

## Group 1 · Missing from both design and implementation — 7

| ID | Screen | Role | Area | Evidence | Pri | Conf |
|---|---|---|---|---|---|---|
| **N-01** | Report / moderate content | Shared | Community | `post_card.dart:113` overflow `onPressed: () {}`; **zero** moderation objects across 132 migrations. App-store gate | **P0** | high |
| **N-02** | Client message inbox | Client | Coach comms | `096_communication_engine.sql:13-29` stores `client_text` + `sent`; writer `coach_program_service.dart:70,78`; **Dart readers: 0**. *Placement (own screen vs a Connect section) is an open design question; the surface is required either way* | **P0** | high |
| **N-05** | Delete account & data export | Client | Account | `help_center_screen.dart:44` FAQ; `privacy_policy_screen.dart:87` promises export; FIT-030 Settings declares neither. **App Store 5.1.1(v)** | **P0** | high |
| **N-07** | Coach client assessment (intake / PAR-Q) | Coach | Coaching | `intake_data.dart:157-241` collects PAR-Q, medical history, injuries; `client_detail_screen.dart:204,414` shows rollups only. **Blocked by OD-30** (privacy) | **P0** | high |
| **N-03** | Coach profile & reviews | Client | Marketplace | `coach_reviews.review_text` written `home_screen.dart:1319`, **never rendered**. FIT-048 *"Choose coach"* is intake-time selection, not a profile | P1 | high |
| **N-04** | Class check-in pass | Client | Classes | `class_detail_screen.dart:272-279` promises *"Show QR code at check-in"*; button `onPressed: () {}`; no `qr_code` column. FIT-086 is **events**, a different entity | P1 | high |
| **N-06** | Community group detail | Client | Community | `016_community_groups.sql`; `connect_sections.dart:95-97` teaser opens nothing; FIT-005 declares a *"Tues Lifters"* row. FIT-071…074 design **pods**, a different entity | P1 | high |

## Group 2 · Client surfaces implemented with no design — 13

| ID | Route | Design evidence | Pri |
|---|---|---|---|
| **N-C01** | `/directory` | **Declared by FIT-001 Home (locked) as "Directory"**; the app's largest hub — 15-module table, sole entry for 3 routes | **P1** |
| **N-C02** | `/workout-history` | **Declared by FIT-014 (locked) as "History"** | **P1** |
| **N-C03** | `/exercise-library` | **Declared by FIT-014/015 (locked) as "Exercise library"** | **P1** |
| **N-C04** | `/personal-info` | **Declared by FIT-029 (locked) as "Personal information"** | **P1** |
| **N-C05** | `/integrations` | **Declared by FIT-029 (locked) as "Connected apps 2"** | **P1** |
| **N-C06** | `/workouts` | Sub-surface pushed from the designed hub (3 sites in `train_hub_screen.dart`) | P2 |
| **N-C07** | `/exercise-detail` | Destination of the exercise library; `exercise_detail_screen.dart` | P2 |
| **N-C08** | `/exercise-database` | Coach-facing catalogue with custom exercises; reached from coach dashboard | P2 |
| **N-C09** | `/create-exercise` | 1,143-line 4-tab creation surface, 3 entry points, **no error state** | P2 |
| **N-C10** | `/strength-progression` | Progress domain; no seed data | P2 |
| **N-C11** | `/coach-marketplace` | Coach browsing; distinct from FIT-048 intake selection | P2 |
| **N-C12** | `/subscription` | FIT-029 shows plan status; **management (cancel/change) is undesigned**. FIT-031 Plans is the *selling* surface | P2 |
| **N-C13** | `/notification-preferences` | Implemented and routed; **not declared by FIT-030 Settings** | P2 |

## Group 3 · Coach surfaces implemented with no design — 12

**The coach product is almost entirely undesigned** — of ~21 coach surfaces the package holds
**two**: FIT-032 and FIT-033.

| ID | Route | Design evidence | Pri |
|---|---|---|---|
| **N-K01** | `/compliance` | **Declared by FIT-032 (locked) as "Adherence"** | **P1** |
| **N-K02** | `/program-builder` | **Declared by FIT-032 (locked) as "Programs"**. Note the route builds `ProgramLibraryScreen`, a *different* class | **P1** |
| **N-K03** | `/coach-directory` | Coach roster; FIT-032 declares *"All 24 clients"* | **P1** |
| **N-K04** | `/coach-classes` | Class management | P2 |
| **N-K05** | `/coach-payments` | Payouts | P2 |
| **N-K06** | `/coach-packages` | Package/pricing management | P2 |
| **N-K07** | `/coach-plan` | Coach's own subscription | P2 |
| **N-K08** | `/coach-client-workouts` | Per-client workout view | P2 |
| **N-K09** | `/coach-copilot` | AI coaching assistant | P2 |
| **N-K10** | `/program-designer` | Dynamic programme builder | P2 |
| **N-K11** | `/continuous-coaching` | Ongoing coaching surface | P2 |
| **N-K12** | `/weekly-review` | Weekly review; FIT-033 declares *"Adjust plan"* | P2 |

## Group 4 · Built but unrouted, with no design — 8

Reached only by `MaterialPageRoute` — no route, no deep link, no shell nav, no router auth.
`EventTicketScreen` excluded: FIT-086 covers it.

| ID | Screen | Role | Design evidence | Pri |
|---|---|---|---|---|
| **N-U01** | `ClientDetailScreen` | Coach | **Declared by FIT-032 (locked) — "Review", "All 24 clients"**. Hosts 5 sub-surfaces incl. the coach-notes sheet | **P1** |
| **N-U02** | `ProgramBuilderScreen` | Coach | The real builder; `/program-builder` builds a different class from the same file | **P1** |
| **N-U03** | `ChoosePackageScreen` | Client | Purchase path; pairs with N-03 | **P1** |
| **N-U04** | `CoachAvailabilityScreen` | Coach | Availability management | P2 |
| **N-U05** | `CreateClassScreen` | Coach | Class creation | P2 |
| **N-U06** | `CoachVideoResponseScreen` | Coach | Video feedback | P2 |
| **N-U07** | `EventAgendaScreen` | Client | Event agenda | P2 |
| **N-U08** | `EventAttendeesScreen` | Vendor/Coach | Attendee list | P2 |

---

## 2 · Explicitly NOT commissioned

| Item | Status |
|---|---|
| 7 admin/vendor routes | **E — OD-40**: is admin/vendor tooling in design scope? |
| Exercise moderation review log | **F** — one orphaned table, no reader, no nav |
| My bookings · Food search · `/nutrition` gateway | **Open questions** — FIT-080 may subsume; FIT-019 may subsume; gateway is a delete candidate |
| 14 items moved to Section 1 in the prior pass | Designed already — FIT-066, 067, 071, 072, 055, 056, 087, 088, 103, 104, 105/106, 019, 099, 004 |
| My assigned programme · My nutrition plan · Check-in history · Pending coach | Covered by FIT-014/015, FIT-091…093, FIT-023; pending coach is a **state** |
| 3 legal pages, 4 system routes, 2 debug routes | Design not required |
| 9 duplicate/dead surfaces | **OD-32** — deletion |
| 15 future capabilities | Preserved — [`FUTURE_SCREEN_CAPABILITIES.md`](FUTURE_SCREEN_CAPABILITIES.md) |

## 3 · Owner decisions blocking design — 3

| OD | Decision | Blocks |
|---|---|---|
| **OD-30** | May a coach read a client's PAR-Q / medical history? | **N-07** |
| **OD-40** *(new)* | Is admin/vendor tooling in the design scope? | 7 surfaces |
| **OD-39** *(new, minor)* | Where should the regenerated baseline images live durably? | nothing — regenerable on demand |

The remaining 39 of 40 can be designed without any owner decision.

## 4 · Recommended sequence

1. **FIT-022 state system** (Section 1, designed) — resolves a defect class across every screen
2. **P0 group**: N-01, N-02, N-05 (two are store gates), N-07 once OD-30 rules
3. **Anchor-declared destinations**: N-C01…C05, N-K01…K03, N-U01, N-U02 — the design already
   points at these, so they close open loops in locked anchors
4. **The coach package** as one coherent commission (N-K01…K12 + N-U01, N-U02, N-U04…N-U06)
5. Remaining client surfaces

---

## 5 · Board reconciliation (2026-09-24) — 156-screen board vs this commission

The design board now holds **156 screens** (169 with V-01…V-13 voice): **117** original
anchors + **39** commissioned. Reconciled against the confirmed 40:

**39 of 40 are on the board. One is absent.**

| Missing | Why it matters |
|---|---|
| **N-07 — Coach client assessment (intake / PAR-Q review)** | **P0.** The 27-step intake collects PAR-Q, medical history and injuries (`intake_data.dart:157-241`); `client_detail_screen.dart:204,414` shows rollups only. A coach designs programmes blind to declared injuries. **Blocked by OD-30** (privacy ruling), which is why it was not drawn — the block is real, not an oversight |

The board's 117 = the 110 manifest anchors **+7 new state variants**, nothing dropped:
`Log a meal — Recent` · `Community hub — members` · `Challenges hub — upcoming` ·
`Challenges hub — done` · `Activity — Training` · `Activity — Food` · `Activity — Check-ins`.

Correctly absent, per this audit's own findings: the 7 admin/vendor surfaces (**OD-40**),
the withdrawn exercise-moderation log (**F**), and the 3 open questions (My bookings ·
Food search · `/nutrition` gateway).

### 5.1 · AUDIT CORRECTION — voice capability exists and is undesigned

This audit previously reported no voice capability. **That was wrong.** Voice is implemented
and backed end to end, with **no FIT anchor**:

| Evidence | Location |
|---|---|
| `speech_to_text ^7.4.0`, `record ^7.1.1`, `audioplayers ^6.8.1` | `pubspec.yaml:45,48,49` — all **consumed**, not orphaned |
| Voice input to AI nutrition — `initialize / listen / stop`, 30 s cap | `ai_nutrition_screen.dart:22,43,120,129` |
| `CoachVoiceRecorder` + `CoachVoicePlayer` — hold-to-record coach notes on an exercise | `exercise_database/presentation/widgets/coach_voice.dart:32,124`, hosted by `coach_focus_section.dart:11` |
| Persistence | `097_coach_exercise_media.sql:19` `voice_url` |
| Permissions | iOS `NSMicrophoneUsageDescription` — *"log meals and send messages to your AI nutrition coach by voice"*; Android `RECORD_AUDIO` |

The widget's own header records the constraint: *"audio capture/playback is
device/browser-specific and cannot be verified headlessly — this needs on-device testing."*

**Consequence:** V-01…V-13 are not speculative. They design an existing capability, and at
least two surfaces already have working implementations to design against — AI-nutrition
voice input and coach exercise voice notes. Treat those two as **Section 1 (implementation
exists, design missing)** rather than greenfield.

**Why the audit missed it:** the sweep tested providers for consumption and dependencies for
*non*-use. These dependencies **are** used, so they never surfaced — and `coach_voice.dart`
sits under `presentation/widgets/`, which the surface inventory excluded as component-level.
