# 12 Circle Fitness — Design Capability Gaps

**Phase 5 + Phase 9 deliverable.** Baseline `0aa844a`.

Two distinct things are recorded here, deliberately not merged:

1. **§1–3 Capability gaps** — features the design or product evidently requires that the
   codebase cannot support. Per the directive these are **PRESERVED, not designed downward**.
2. **§4–5 Design gaps** — surfaces the product requires that the 110-screen package does not
   contain. Per Phase 9 a **design requirement** is recorded; no production design is invented.

---

## 1 · Capability gaps attached to a required screen

| ID | Screen | Feature | Design evidence | Current status | Missing capability | Domain model | API / data source | Persistence | Security implications | Safe to stub for QA? | Post-QA requirement |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **CG-01** | Class check-in pass (MCS-08) | Scannable entry pass | `class_detail_screen.dart:272-279` — *"Show QR code at check-in"*, button is `onPressed: () {}` | `mobile_scanner` installed; QR rendered elsewhere is a **drawn visual**, not encoded | Real QR generation + verification | `ClassPass{bookingId, code, issuedAt, usedAt}` | new RPC `issue_class_pass` / `redeem_class_pass` | `class_bookings.qr_code` column — **does not exist** | A pass is a bearer token: needs single-use semantics and coach-side redemption authority | ✅ — render a static placeholder pass, clearly marked | Encoded, single-use, redeemable pass |
| **CG-02** | Attendee scanner | Scan a pass | `vendor_portal_screen.dart:307` check-in is a **manual toggle**; `020_vendor_portal.sql:13` has `qr_code` + `checked_in_at` | Only scanner reads **food barcodes** (`barcode_scan_view.dart:16,57`) | Camera scan → redeem | reuse CG-01 | `redeem_class_pass` | `checked_in_at` exists | Redemption must be restricted to the class's coach/vendor | ✅ — manual toggle already stands in | Depends on CG-01 |
| **CG-03** | Client message inbox (MCS-06) | Client reads coach communications | `096_communication_engine.sql:13-29` stores `client_text`, status `sent` | Written by `send_communication()`; **zero Dart readers** | Client-side read + read-receipt | `Communication{id, clientId, type, clientText, sentAt, readAt}` | select on `communications` | table exists; **no `read_at`** | **Needs a client SELECT policy** — today the table is coach-written only | ✅ — seed against existing QA coach/client identities | Read receipts; the 5 unbuilt types (FC-08) |
| **CG-04** | Report / moderate (MCS-05) | Report, block, hide, remove | `post_card.dart:113` overflow menu = no-op | **Zero** moderation objects in 132 migrations | Report intake + moderation queue + enforcement | `Report{id, targetType, targetId, reporterId, reason, state}`; `Block{blockerId, blockedId}` | new RPCs | new tables | **Significant.** Blocks must filter reads; reporter identity must not leak; admin queue needs `is_admin()` | ⚠️ partial — intake can be stubbed; enforcement must not be faked | Full moderation pipeline. **App-store gate** |
| **CG-05** | Delete account / export (MCS-09) | Erase and export | `help_center_screen.dart:44`; `privacy_policy_screen.dart:87` | Neither exists | Cascading erase + export bundle | — | new edge function | cascade across ~40 user-keyed tables | **Highest-risk capability here.** Irreversible; must not orphan coach/billing records; export must not leak another user's data | ❌ — **must not be stubbed**. A fake delete is worse than none | Real erase + export. **App-store gate 5.1.1(v)** |
| **CG-06** | Coach reviews (MCS-07) | Render review text | `coach_reviews.review_text` written `home_screen.dart:1319` | Aggregates only | Read + moderate reviews | `CoachReview{coachId, authorId, rating, text}` | select | exists | Review text is UGC → inherits CG-04 | ✅ | Depends on CG-04 for moderation |

---

## 2 · Capability gaps with no screen attached

Preserved per the directive. Detail in
[`FUTURE_CAPABILITIES.md`](FUTURE_CAPABILITIES.md) (FC-01…FC-14).

| ID | Capability | Why it blocks screens |
|---|---|---|
| **FC-07** | **Path parameters + deep links** | **The structural prerequisite.** No route takes a parameter, so no entity is addressable. Blocks notification→screen routing, invite acceptance, and routing the 8 push-only screens |
| FC-01 / FC-12 | Health ingestion → wearable intelligence | `/integrations` ships 5 providers writing only a `connected` flag; no `health` package |
| FC-03 | Real QR | Blocks CG-01, CG-02 |
| FC-04 / FC-05 | Localisation, theming | Blocks the dead Language row and static Dark Mode |
| FC-08 | 5 declared communication types | Blocks CG-03's full scope |
| FC-14 | AI cost ledger | **No cost/usage table in 132 migrations** while 19 edge functions call models unmetered |

---

## 3 · Unsupported design features preserved — NOT designed downward

Recorded so no future pass mistakes them for scope creep. Each is declared in the design and
unsupported today; none was removed.

| Design element | Declared in | Unsupported because |
|---|---|---|
| Sample social rows (*"Priya Hit 70 kg on the hinge today"*, *"Tues Lifters Sam: anyone in at 7 tomorrow?"*) | FIT-005 Connect | These are **sample data, a ceiling not a backlog** — matching them requires fabricating exact rows. `FIT_INTERACTION_COVERAGE.md` says so explicitly |
| *"You're 3rd of 24 in your pod"* | FIT-005 | Pod standings have no provider; `/pods` itself is unreachable (MCS-01) |
| *"4 places left"* class capacity | FIT-005, FIT-027 | Capacity exists; live remaining-places is not computed client-side |
| AI meal scan | FIT-020 | Embedded in `/log-meal`, which is an orphaned stub (MCS-02) |
| Entitlement gate as a screen | FIT-021 | Implemented as the `PaywallGate` **wrapper** — correct, not a gap |
| Loading & failure pattern | FIT-022 | **No shared loading/empty/error/retry widget exists.** `_EmptyState` is privately re-declared 10× with 10 signatures; zero offline handling app-wide |

> **FIT-022 is the largest preserved gap.** The design declares a cross-cutting loading and
> failure pattern; the codebase has no shared implementation of it, and 25 major screens have
> no error state at all. This is design-supported work that should not be dropped.

---

## 4 · Design gaps — surfaces with no design (Phase 9)

**No production design was invented.** Each entry records the requirement, the nearest
existing design language, and is marked `MISSING_DESIGN`.

### 4.1 Required surfaces absent from the package — 6

| ID | Surface | Nearest existing design language | Status |
|---|---|---|---|
| **MD-01** | Report / moderate content | FIT-065…070 `/community` post cards; destructive-confirm pattern from `settings_screen.dart:616` | `MISSING_DESIGN` |
| **MD-02** | Client message inbox | FIT-005 Connect list rows; FIT-026 Conversation | `MISSING_DESIGN` |
| **MD-03** | Coach profile & reviews | FIT-096…098 booking/`ChoosePackageScreen`; coach marketplace cards | `MISSING_DESIGN` |
| **MD-04** | Class check-in pass | FIT-081…088 `/class-detail`; FIT-086 Event ticket is the closest built analogue | `MISSING_DESIGN` |
| **MD-05** | Delete account & data export | FIT settings rows; destructive-confirm pattern | `MISSING_DESIGN` |
| **MD-06** | Community group detail | FIT-065…070 `/community`; FIT-071…074 Pods detail is structurally identical | `MISSING_DESIGN` |

### 4.2 Implemented client routes with no design — 13 (category `D`)

Built and reachable; the package simply does not cover them. Not missing screens — **missing
designs**.

`/directory` (the largest hub — 15-module table, sole entry for 3 routes) · `/workouts` ·
`/workout-history` · `/strength-progression` · `/exercise-library` · `/exercise-database` ·
`/exercise-detail` · `/create-exercise` · `/personal-info` · `/notification-preferences` ·
`/subscription` · `/integrations` · `/nutrition`

### 4.3 Implemented coach routes with no design — 14 (category `K`)

The coach product has **zero** design coverage:

`/coach-dashboard` · `/coach-directory` · `/coach-checkin-review` · `/coach-classes` ·
`/coach-payments` · `/coach-business` · `/coach-copilot` · `/coach-client-workouts` ·
`/coach-packages` · `/coach-plan` · `/program-builder` · `/program-designer` ·
`/continuous-coaching` · `/weekly-review`

### 4.4 Unrouted screens with no design — 8

Built, pushed via `MaterialPageRoute`, undesigned. `EventTicketScreen` is excluded — FIT-086 covers it.

Coach/vendor: `ClientDetailScreen` · `ProgramBuilderScreen` · `CreateClassScreen` ·
`CoachAvailabilityScreen` · `CoachVideoResponseScreen` · `EventAttendeesScreen`
Client: `ChoosePackageScreen` · `EventAgendaScreen`

---

## 5 · Blocker preventing design acceptance

Every manifest entry cites `referenceImage: screens/FIT-0NN.png`. **The package contains no
`screens/` directory** — the 110 PNGs must be generated by `node capture-references.mjs`.

*"Matches `screens/<ID>.png`"* is the **first item of the per-screen Definition of Done**, so
**no screen can currently be accepted against the design** — including the 45 already built.
This blocks verification of existing work, not only new work.

---

## 6 · Summary

| Measure | Count |
|---|---|
| Capability gaps attached to a screen (CG) | 6 |
| Capability gaps with no screen (FC) | 14 |
| Unsupported design features preserved | 6 |
| Missing designs — required surfaces (MD) | 6 |
| Missing designs — implemented client routes | 13 |
| Missing designs — implemented coach routes | 14 |
| Missing designs — unrouted screens | 8 |
| **Total surfaces requiring new design work** | **41** |
| Capabilities safe to stub for QA | 4 of 6 CG |
| Capabilities that must **not** be stubbed | 1 — CG-05 account deletion |
