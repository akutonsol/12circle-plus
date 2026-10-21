# 12 Circle Fitness — Product Screen Ecosystem Audit

**Read-only audit.** No repository file was modified, renamed or deleted; no database was
contacted; nothing was implemented or designed. The seven audit documents are the only
artifacts produced.

| | |
|---|---|
| **Baseline commit** | `fbee6d5cc51d6c3aee468c95c12e2d55b52e1f89` |
| **Branch** | `chore/qa-environments-secure-ai-backend` |
| **Date** | 2026-09-23 |
| **Scope** | `apps/mobile` (Flutter + GoRouter + Supabase), `apps/api` (NestJS), `supabase/**` |
| **Method** | 8 parallel investigations + 1 independent second pass, reconciled |

### ⚠ Concurrency notice — read first

**Another agent session was committing to this worktree throughout the audit** (commits at
23:11, 23:14, 23:24 and 23:39 on 2026-09-23, touching `active_workout_screen.dart`,
`meals_dashboard_screen.dart`, `profile_screen.dart`), and was writing
`apps/mobile/tool/orphan_route_sweep.dart` and `test/unit/orphan_route_guard_test.dart` —
**tooling for the same orphan routes catalogued here.** Its commit messages read *"a second
orphaned route"*, *"a third orphaned route"*.

All figures describe the pinned baseline. Findings on the churning files may already be
stale. This is an owner decision item (§H).

---

## Companion documents

| Document | Contents |
|---|---|
| [`SCREEN_INVENTORY.json`](SCREEN_INVENTORY.json) | Machine-readable, 91 route records |
| [`SCREEN_ROUTE_GRAPH.md`](SCREEN_ROUTE_GRAPH.md) | Full route/navigation graph, orphans, deep links |
| [`MISSING_SCREEN_REGISTER.md`](MISSING_SCREEN_REGISTER.md) | 30 classified entries with evidence |
| [`FUTURE_CAPABILITIES.md`](FUTURE_CAPABILITIES.md) | 14 capabilities + unreachable infrastructure |
| [`DESIGN_IMPLEMENTATION_RECONCILIATION.md`](DESIGN_IMPLEMENTATION_RECONCILIATION.md) | Design ↔ code, and one material correction |
| [`SCREEN_DATA_REQUIREMENTS.md`](SCREEN_DATA_REQUIREMENTS.md) | Screen → table/provider/RPC, 3 gap lists |

---

## 1 · Quantitative summary

| Measure | Value |
|---|---|
| **TOTAL DISTINCT PRODUCT SURFACES** | **148** |
| TOTAL LIVE SURFACES | 132 |
| TOTAL ROUTES | **91** (89 in a release build) |
| Distinct widgets those routes build | 88 (3 aliases) |
| Screens reachable **only** by `Navigator.push` (unrouted) | **9** |
| TOTAL DESIGN-SUPPORTED SCREENS | **45 routes** (110 FIT frames) |
| TOTAL IMPLEMENTED WITHOUT CURRENT DESIGN | **46 routes** |
| TOTAL DESIGNED BUT NOT IMPLEMENTED | **0** |
| TOTAL MISSING-DESIGN CANDIDATES | **41** (§I) |
| TOTAL MISSING-BOTH CANDIDATES | **7** |
| TOTAL FUTURE CAPABILITIES | **14** |
| TOTAL DEAD / ORPHANED SURFACES | **7 dead + 7 orphan routes + 5 redirect stubs** |
| TOTAL ROLE-SPECIFIC SCREENS | 14 coach-routed + 9 admin/vendor + 4 role-gated |
| TOTAL STATE VARIANTS | 11 screen variants · 37 flow steps · 52 modals · 13 paywall-locked states |
| Routes with a path parameter | **0** |
| Deep-link destinations | **0** |

### Surface classification (inclusion rule in §2)

| Class | Count |
|---|---|
| LIVE | 132 |
| DEAD | 7 |
| REDIRECT-STUB | 5 |
| DUPLICATE | 2 |
| DEBUG-ONLY | 2 |
| PARTIAL | 0 |
| UNKNOWN | 0 |

---

## 2 · Method, and what counts as a screen

A surface qualifies if **any** of: (R1) a public widget whose `build` returns a `Scaffold`;
(R2) it is pushed as a full page or built by a `GoRoute`; (R3) it is a modal sheet/dialog
that is a distinct product surface — own task, own data write, own dismissal; (R4) it is a
nested full surface owning its parent's entire body.

**Excluded:** cards, tiles, chips, buttons, rings, badges, painters, chrome, and section
fragments rendering inside a parent's scroll view. Borderline calls were enumerated
explicitly rather than absorbed silently.

**Evidence hierarchy applied** (live router → reachable code → authoritative design → FIT
manifest → providers → schema → tests → comments → dead code). Dead code was **not** counted
as a live screen merely for containing a `Screen` widget, and a design frame was **not**
counted as implemented merely because a similarly named Dart file exists — a rule that
caught the FIT-001 error in §5.

### 2.1 Two-pass reconciliation

A second pass ran independently, forbidden from reading the first pass's outputs and
directed at different sources (the in-app QA manifest, the test suite, `pubspec.yaml`,
platform manifests, git history).

| Measure | Pass 1 | Pass 2 | Resolved |
|---|---|---|---|
| `GoRoute` declarations | 91 | 91 | **91** ✅ |
| Distinct routed widgets | 88 | 88 | **88** ✅ |
| Dangling nav targets | 0 | 0 | **0** ✅ |
| Orphan routes | 11 zero-inbound / 7 genuine | 14 zero-inbound / 5 genuine | **11 zero-inbound, 7 genuine** |

**The one disagreement, and its cause.** Pass 2 found that `directory_screen.dart` holds a
15-entry `const _Module(route: …)` table that is the **sole entry point** for `/insights`,
`/action-items` and `/events` — invisible to a `context.go` grep. I verified each contested
route directly: those three **are** navigable; `qa_suites.dart` references are a gated-route
**test manifest, not navigation**. Pass 1's 7 genuine orphans stands; pass 2's stricter 5
excluded `/coach-business` (live screen, dead path) and `/log-meal` (nav-highlight reference
only) on judgment. **The underlying facts never conflicted.**

### 2.2 What a router+Scaffold sweep would have missed — ~52 surfaces

Recorded because it justifies the 148 figure: 9 push-only screens · 9 sheet/dialog files
with no Scaffold (the entire `coach_notes` feature is a sheet, no screen) · 27 intake flow
steps behind one route · 13 PaywallGate locked states · the role-switched shell (two
different bottom navs from one `ShellRoute`) · 6 `dart.library.html` conditional-export
pairs · **2 hand-written HTML pages users actually land on** (`web/stripe_checkout.html`,
`web/checkout_complete.html`) · the `_Module` table.

Conversely a raw `Scaffold` count **over**-counts: naive grep gives 105 files, of which 11
are false positives and 5 are fully dead.

---

## 3 · A. Complete screen inventory

Full records: [`SCREEN_INVENTORY.json`](SCREEN_INVENTORY.json) (91 routes) and
[`SCREEN_ROUTE_GRAPH.md`](SCREEN_ROUTE_GRAPH.md) §2 (full route table).

**Domains discovered — 34 feature modules**, more than the brief anticipated:
`action_items` `activity` `admin` `ai_coach` `ai_nutrition` `auth` `booking` `challenges`
`checkins` `classes` `coach` `coach_notes` `coaching_mode` `community` `compliance`
`dashboard` `exercise_database` `goals` `habits` `home` `insights` `messaging`
`notifications` `nutrition` `onboarding` `payments` `profile` `progress` `qa` `scoring`
`settings` `vendor` `womens_health` `workout`.

Two required explanation and are **not** missing screens: `coach_notes` is a bottom-sheet
feature (no screen by design, correctly), and `coaching_mode` is domain-only, surfaced
through a settings sheet.

### 3.1 The structural fact that shapes everything

**No route takes a path parameter — not one of 91.** Every parameterised destination is
therefore reached by `Navigator.push(MaterialPageRoute)` outside GoRouter. This single
decision produces: the 9 unrouted screens, the absence of deep linking, the inability to
route notifications to a destination, and the fact that no entity screen is bookmarkable or
survives a web refresh.

---

## 4 · B. Missing screen build list

30 classified entries in [`MISSING_SCREEN_REGISTER.md`](MISSING_SCREEN_REGISTER.md).
Headlines:

- **Content moderation does not exist** — full UGC (posts, comments, reactions) with no
  report, flag, block, hide or delete anywhere in the app or across 132 migrations. The post
  overflow menu is a no-op. Also an app-store review gate.
- **A coach can send a client a message the client cannot open** — `communications` is
  written by `send_communication()` and **read by no Dart code**.
- **A paying `selfGuided` user has no in-app route to log a meal** — `/food-search` and
  `/log-meal` are 23-line redirect stubs with zero inbound navigation.
- **Coach review text is collected and never rendered.**
- **Delete-account and data-export are promised in the Help Centre and privacy policy and
  exist in neither.**

---

## 5 · C. Design gaps

Full analysis in
[`DESIGN_IMPLEMENTATION_RECONCILIATION.md`](DESIGN_IMPLEMENTATION_RECONCILIATION.md).

The authoritative package re-verified by hash (exact match), 110 screens, 29 locked. The
existing matrix's headline numbers are **confirmed**, with three caveats:

> **Material correction.** `DESIGN_ROUTE_IMPLEMENTATION_MATRIX.md` maps **FIT-001 Home — the
> flagship locked anchor — to `home_org.dart`, which is dead code** (zero importers;
> `app_scaffold.dart:4` calls it "dead… never instantiated"). A duplicate `class HomeScreen`
> in two files defeated its resolver. Re-resolved all 45: **44 correct, this one wrong.**

Also: "50 distinct routes" should read **45**; the design's gated-route count of 12 should
read **13**; and **the acceptance baseline is unbuildable** — every screen's Definition of
Done requires matching `screens/FIT-0NN.png`, and **that directory does not exist in the
package** (the PNGs must be generated via `capture-references.mjs`).

**Coverage: 45 of 91 routes (49.5%) have design. 0 designed screens are unbuilt.**

---

## 6 · D. Feature gaps

14 future capabilities in [`FUTURE_CAPABILITIES.md`](FUTURE_CAPABILITIES.md). **None was
removed**, per instruction.

The dependency that matters: **FC-07 (path parameters + deep links) is the structural
prerequisite** for notification routing, invite acceptance, and entity-addressable screens.
Four separate register items cannot be built until it lands.

Also of note: **9 of 25 declared dependencies have zero imports.** `google_sign_in` +
`sign_in_with_apple` + `crypto` together are the fingerprint of a native social sign-in
surface planned and never built — both providers currently run through Supabase's
`signInWithOAuth` web redirect, the form Apple review rejects on iOS.

---

## 7 · E. Data gaps

Full analysis in [`SCREEN_DATA_REQUIREMENTS.md`](SCREEN_DATA_REQUIREMENTS.md).

**Four screens are broken by schema gaps** — they render wrong, not merely empty:

| Screen | Cause |
|---|---|
| `/daily-checkin` | **Submits to a `checkins` table that does not exist** in any of 132 migrations |
| `/coach-dashboard` (check-ins panel) | Same missing table |
| `/vendor-portal` (attendees) | Missing column `event_registrations.ticket_code` |
| `/home` (coach tip) | Missing table `coach_tips`; error swallowed, card silently never appears |

**Three surfaces present fabricated data as measured:** `/activity` steps
(`StateProvider<int>(6240)`, no table, resets every launch) and water; `/coach-business`
renders **$0 MRR / 0 subscribers** on any failure; the dead `DashboardScreen` returns 100%
hardcoded literals.

**22 surfaces render empty in QA for lack of seed data** — so an empty screen in QA is
currently ambiguous between "defect" and "unseeded".

---

## 8 · F. Route / navigation gaps

| Gap | Count |
|---|---|
| Genuine orphan routes | 7 |
| Screens with no route | 9 |
| Route building the wrong class (`/program-builder` → `ProgramLibraryScreen`) | 1 |
| Redundant aliases | 2 |
| Redirect stubs occupying a route | 5 |
| Deep-link destinations | 0 |
| Routes unreachable from persistent navigation | 78 of 91 (86%) |

**Clients lose the top navigation when they leave Home** — `_CoachTopBar` renders only for
coaches, and its sole client mount is `home_screen.dart:245`. `/directory`, the app's
largest hub, and `/notifications` are Home-only for clients.

---

## 9 · G. Dead / duplicate surfaces

**7 dead screen classes, ~1,270 dead lines:** `HomeScreen` (`home_org.dart`),
`DashboardScreen` ×2, `SubscriptionScreen`, `EmbeddedCheckoutScreen`,
`showCoachPricingSheet`, `LogWeightSheet`. Plus the entire `profile` data+domain layer
(`profile_service.dart` and `profile_provider.dart` are **0 bytes**).

**Duplicate class names are an active hazard, not a tidiness issue.** `HomeScreen` and
`DashboardScreen` are each declared twice; the `HomeScreen` collision is what produced the
FIT-001 mis-mapping in §5, and will produce it again for any future resolver.

**Nutrition is four classes**, one a genuine duplicate: `NutritionSplashScreen` is a
gateway, `MealsDashboardScreen` is the real product, `AiNutritionScreen` is a distinct
product, and **`NutritionScreen` (637 lines at `/nutrition-overview`) is a second, older,
self-contained logger** with its own private providers that nothing routes to.

**No screen file has ever been deleted** across all 202 mobile commits. The failure mode is
pure accretion.

---

## 10 · Role matrix and authorization

*Phase 9 produced findings that outrank the screen audit and are recorded here in full.*

**Zero of the 91 routes carries a role guard.** The only registration-time gate is build
mode (`!kReleaseMode`) for the two QA routes. `redirect()` reads `role` **only inside the
`isAuthenticated && isAuthRoute` branch**, so an authenticated client navigating directly to
an admin route falls through and the route resolves.

| Admin/vendor route | Router | Widget | Server |
|---|---|---|---|
| `/admin-dashboard` | ABSENT | **ABSENT** | RPC raises 42501 |
| `/admin-exercise-review` | ABSENT | **ABSENT** | RLS |
| `/vendor-portal` | ABSENT | **ABSENT** | RLS |
| `/content-center`, `/observability`, `/content-review`, `/knowledge-review` | ABSENT | present | partial |

**12 routes have authorization enforced at no layer at all.** For five of them a client can
**successfully create** coach-owned records (`workout_programs`, `classes`,
`coach_packages`, `coach_team_members` are `FOR ALL … USING (coach_id = auth.uid())` with no
`WITH CHECK`).

### Three security findings

1. **Tier escalation by one INSERT (HIGH).** `client_plan()` resolves `coach_guided` from
   `coach_client_relationships`, and migration 113's INSERT policy permits
   `client_id = auth.uid() AND initiated_by='client' AND status IN ('pending','active')` for
   any coach id enumerable from `public_profiles`. **A free account self-promotes to the top
   tier and unlocks every gated route.**
2. **Five AI tables have no RLS at all (HIGH).** `ai_profiles`, `ai_memories`, `ai_insights`,
   `ai_reviews`, `ai_goal_predictions` (migration 074), all `user_id`-keyed;
   `ai_memories.kind` includes `injury | constraint`. Any authenticated client can read or
   write **every member's AI coaching memory**. **This is not in the existing ledger** —
   migration 117 covered different tables.
3. **Two unauthenticated orphan edge functions.** `notify-coach-email` reads no
   Authorization header and interpolates caller-controlled input raw into an email sent to
   every coach; `send-checkin-reminder` is likewise unauthenticated and never scheduled.

**Correction to project memory:** the 115/119 regressions were real, but **migration 124
restored `materialize_program_week`'s guard verbatim and 126 fixed `derive_parq_risk()`'s
untyped append.** The "unfixed" note is stale in source terms. Production state was not
checked — no database was contacted.

`/intake` and `/onboarding` are in `isAuthRoute`, so an **unauthenticated** caller reaches
both. A fifth role, `content_manager`, exists in the schema and in five widget guards but
**has no branch in the router redirect**. There is **no `AppRole` enum and no `isCoach`
provider** — role is a raw `String?` read through **8 distinct idioms**, one of which
(`profile_screen.dart:47`) falls back to the JWT metadata that migration 115 repudiated.

---

## 11 · State inventory

| Class | Count |
|---|---|
| SCREEN | 91 routed + 9 unrouted |
| SCREEN VARIANT | 11 |
| FLOW STEP | 37 (27 intake + 10 modal-hosted) |
| MODAL | 52 |
| STATE | 22 |
| Destructive confirmations | 11 (all correctly gated) |

**The intake flow has 27 steps**, not the 19 the design package maps onto it. Its in-file
`// N —` comments are **off by one from index 8**, and `_totalSteps = 26` is the last index,
not the count.

**Step 24 "Generating Plan" is theatre** — `_runProgress()` walks a hardcoded
`[20,45,70,90,100]` on 700 ms delays; the four phase labels are backed by no call. The real
`generate_client_plan` RPC fires two steps later and **its failure is swallowed**.

**There is no shared empty/error/loading/retry widget anywhere.** `_EmptyState` is privately
re-declared **10 times with 10 different signatures**. **Zero offline handling app-wide** —
no `connectivity_plus`, no `SocketException` handling, 0 of 98 screens. **25 major screens
have no error state at all**, including `booking_screen.dart` (949 lines, zero `error:`) and
the intake flow itself (one `error:` branch in 5,841 lines).

Two state-machine defects: **loading renders as "unauthorized"** on five role-gated screens
(they reject on a `null` role before the profile arrives, so a real coach sees "Coaches
only."), and **error is conflated with empty** in four places, telling the user there is
nothing there when a fetch failed.

### Failure-as-value — 10 cited instances

Worst is the intake completion: `intake_flow_screen.dart:226-234` wraps the answer upsert in
`catch (_)`, its fallback in a second `catch (_) {}`, then sets `_done = true`
**unconditionally** — the user is told *"That's everything we needed"* and promised a first
week, while the plan-generating RPC was swallowed. Also: `paywall_gate.dart:46` declares a
fail-**open** on entitlement error (dead code in practice, since `clientPlan()` returns
`'free'` on error — it fails closed, but the declared intent is wrong); habit completions
keep optimistic state and awarded points after a swallowed write; "Join pod" is a dead tap
on failure.

Verified **not** a defect: the documented F-23 regression in `active_workout_screen.dart` is
genuinely repaired.

---

## 12 · H. Owner decisions required

1. **The concurrent session.** Another agent is implementing FIT screens in this worktree
   now, including orphan-route tooling that overlaps §8. Pause it, or re-run the affected
   parts of this audit against a later baseline?
2. **Path parameters (FC-07).** Adopting them is a routing-architecture change that unblocks
   four register items. Approve?
3. **Coach intake visibility** — may a coach read a client's PAR-Q and medical history?
   Privacy decision; blocks MSR-27.
4. **In-app admin/role administration vs the Supabase console** (MSR-28).
5. **Coach-invite acceptance** — migration 040 auto-links by e-mail, so a screen may be
   unnecessary (MSR-29).
6. **`/intake` design scope** — 19 designed frames vs 27 implemented steps.
7. **`ai_nutrition` persistence** — it is the only feature on the NestJS backend and
   persists nothing.
8. **The three security findings in §10** — these are outside the screen audit's remit but
   were found by it, and two are HIGH.
9. **Generate the 110 reference PNGs**, without which no screen can be accepted (§5).

---

## 13 · I. Recommended design package to build next

**Build the coach product package.** It is the largest coherent undesigned area (14 routed
surfaces + 7 unrouted coach screens), it is where the workflow gap sits (MSR-27), and it is
where authorization is weakest (§10). The client package is already 45 routes deep; the
coach side has **zero** design coverage.

Sequence: **(1)** the 6 missing-entirely surfaces, since two are app-store gates; **(2)** the
coach package; **(3)** the 13 undesigned client surfaces; **(4)** anything dependent on
FC-07.

---

# SCREENS WE NEED TO DESIGN

Every entry below satisfies all five tests: the product requires the surface; no adequate
current authoritative design exists; it is not a duplicate or a state of another screen; it
is not merely an unsupported future capability; and it is not already covered by the
110-screen package.

**Excluded by those tests, with reason:** `/pods` and `/log-meal` (designed already);
`EventTicketScreen` (FIT-086 exists); `/coach`, `/onboarding`, `/nutrition-overview`,
`/food-search`, `/checkin-form` (aliases, duplicates or redirect stubs); language picker and
dark mode (blocked by FC-04/FC-05); attendee QR scanner (blocked by FC-03); notification
routing and the ToS link (not screens); the 7 dead classes; `/mie-debugger` and `/qa-center`
(never ship); `/payment-success` and `/payment-cancel` (web-only, unreachable on mobile).

---

## Tier 1 — Missing from both design and implementation (6)

| ID | Screen | Domain | Role | Why needed | Evidence | Entry point | Expected data | Known states | Related existing | What is missing |
|---|---|---|---|---|---|---|---|---|---|---|
| **D-01** | Report / moderate content | community | client + admin | Full UGC with no report, flag, block, hide or delete anywhere in app or DB. App-store gate | `post_card.dart:113` (no-op overflow); `001_full_ecosystem.sql`; 0 matches in 132 migrations | Post overflow menu | reports table (none), post, reporter | form, submitted, already-reported, admin queue | `/community`, FIT-065…070 | design, schema, screen |
| **D-02** | Client message inbox | coach comms | client | `communications` written by `send_communication()`, **read by no Dart code** | `096_communication_engine.sql:13-29`; writer `coach_program_service.dart:70,78` | Home / Connect / notification | `communications.client_text`, status | empty, unread, read, error | `/messages`, FIT-005/028 | design + client read path |
| **D-03** | Coach profile & reviews | marketplace | client | `coach_reviews.review_text` collected, never rendered; tapping a coach jumps straight to purchase | col `001_full_ecosystem.sql:206`; write `home_screen.dart:1319`; `coach_marketplace_screen.dart:344` | `/coach-marketplace` card tap | coach profile, reviews, packages | loading, empty-reviews, populated | `/coach-marketplace`, `ChoosePackageScreen` | design + detail screen |
| **D-04** | Class check-in pass | classes | client | Booking panel says *"Show QR code at check-in"*; the QR button is `onPressed: () {}` | `class_detail_screen.dart:272-279`; `001_full_ecosystem.sql:254-261` | `/class-detail` after booking | booking, class, pass code | valid, used, expired, cancelled | `/class-detail` FIT-081…088 | design, `qr_code` column, screen |
| **D-05** | Delete account & data export | settings | client | Help Centre FAQ asks how to delete; privacy policy promises export. Neither exists. App Store 5.1.1(v) | `help_center_screen.dart:44`; `privacy_policy_screen.dart:87` | `/settings` | account, owned data | confirm, destructive-confirm, in-progress, done, error | `/settings`, `/subscription` | design, backend, screen |
| **D-06** | Community group detail | community | client | `community_groups`/`community_group_members` modelled and read; FIT-005 renders a `groupLine()` teaser with nothing to open | `live_community_service.dart:145,175`; `connect_sections.dart:95-97`; `016_community_groups.sql` | Connect group row | group, members, posts | loading, empty, member, non-member | `/community` FIT-065…070 | design + screen |

## Tier 2 — Implemented but unrouted and undesigned (8)

Built and in use, pushed via `MaterialPageRoute` outside GoRouter — no deep link, no shell
nav, no router auth. All 14 push call sites cited in
[`SCREEN_ROUTE_GRAPH.md`](SCREEN_ROUTE_GRAPH.md) §4.1.

| ID | Screen | Role | Note |
|---|---|---|---|
| **D-07** | `ClientDetailScreen` | coach | **Highest value.** The coach's per-client surface; hosts 5 sub-surfaces incl. the coach-notes sheet; unaddressable |
| **D-08** | `ProgramBuilderScreen` | coach | `/program-builder` builds a *different* class (`ProgramLibraryScreen`) from the same file |
| **D-09** | `CreateClassScreen` | coach | |
| **D-10** | `CoachAvailabilityScreen` | coach | |
| **D-11** | `ChoosePackageScreen` | client | Purchase path — pairs with D-03 |
| **D-12** | `CoachVideoResponseScreen` | coach | |
| **D-13** | `EventAgendaScreen` | client | |
| **D-14** | `EventAttendeesScreen` | vendor / coach | |

## Tier 3 — Routed client surfaces with no design (13)

| ID | Route | Note |
|---|---|---|
| **D-15** | `/directory` | The app's largest hub; 15-module table; **sole entry point for 3 routes** |
| **D-16** | `/workouts` | |
| **D-17** | `/workout-history` | No seed data |
| **D-18** | `/strength-progression` | No seed data |
| **D-19** | `/exercise-library` | |
| **D-20** | `/exercise-database` | |
| **D-21** | `/exercise-detail` | |
| **D-22** | `/create-exercise` | 1,143 lines, 4-tab; no error state |
| **D-23** | `/nutrition` | Gateway/splash forwarding to two targets — design should confirm it should exist at all |
| **D-24** | `/personal-info` | |
| **D-25** | `/notification-preferences` | Toggles that do not persist (MSR-11) |
| **D-26** | `/subscription` | |
| **D-27** | `/integrations` | OAuth client_ids are placeholders; backing capability is FC-01 |

## Tier 4 — Routed coach surfaces with no design (14)

The coach product has **zero** design coverage. Recommended as one package (§13).

| ID | Route | | ID | Route |
|---|---|---|---|---|
| **D-28** | `/coach-dashboard` | | **D-35** | `/coach-plan` |
| **D-29** | `/coach-directory` | | **D-36** | `/compliance` |
| **D-30** | `/coach-checkin-review` | | **D-37** | `/coach-copilot` |
| **D-31** | `/coach-classes` | | **D-38** | `/program-designer` |
| **D-32** | `/coach-payments` | | **D-39** | `/continuous-coaching` |
| **D-33** | `/coach-business` | | **D-40** | `/weekly-review` |
| **D-34** | `/coach-packages` | | **D-41** | `/coach-client-workouts` |

`/coach-marketplace` is client-facing and covered by D-03.

## Pending owner decision — not counted (2)

| ID | Screen | Blocked by |
|---|---|---|
| **P-01** | Coach client-assessment / intake review | Privacy decision: may a coach read PAR-Q and medical history? (MSR-27, MSR-30) |
| **P-02** | Appointment join destination | Unknown whether this is a screen or an external video link. `checkin_screen.dart:457` empty `onTap` |

---

## Total

**41 screens require new design work** (Tier 1: 6 · Tier 2: 8 · Tier 3: 13 · Tier 4: 14),
plus **2 pending owner decisions** that would raise it to 43.

*Audit only. Nothing in this register was implemented or designed.*
