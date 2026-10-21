# 12 Circle Fitness — QA Workstream H
## Product-Integrity & Feature-Contract Audit

**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` — read-only probes + two seeded-fixture logins.
**Production `nxdbooufqzkpslkcogxc` was not contacted. See §14.**

---

## 1. Scope

This workstream audits whether the application's **actual behaviour** matches the
product bible, the authoritative `docs/`, the database contracts in
`supabase/migrations`, the existing tests, and the behaviour implied by the current
UI and service architecture — **outside** the two closed clusters:

- **Phase 1 (security/RLS)** — closed, verified on QA. Not re-opened. Where a Phase 1
  migration *caused* a downstream product regression, that regression is reported here
  as a product defect (§5, H-06), not as a security finding, and the Phase 1 posture is
  not proposed for rollback.
- **Phase 2 (workout domain contract)** — closed, verified on QA. The set-identity,
  session-lifecycle and prescription contracts were not re-audited. Two findings touch
  workout code (H-01, H-14); both are **outside** the Phase 2 contract surface and are
  marked as such.

Areas A–U of the brief were all entered. Where a prior workstream already owns an area
in depth (E — nutrition/check-in; F — women's health; D — coach/community/marketplace
authorization; B — error semantics; C — engine; G — release), this report **verifies
current status and cross-references** rather than re-deriving. Those cross-references are
in §7.

**Nothing about the product was invented.** Every "expected behaviour" below traces to
`docs/product-bible.md`, a migration comment, an in-app string the product itself shows
the user, or an existing test. Where expected behaviour is genuinely undecided, the
finding is filed as **OWNER DECISION** and no behaviour is assumed (§9).

---

## 2. Current repository state

| | |
|---|---|
| Branch | `chore/qa-environments-secure-ai-backend` |
| HEAD | `39ca39c` *fix: make workout session persistence deterministic* |
| Working tree at audit start | **dirty and shared** — 108 entries (50 modified, 58 untracked) |
| Working tree at report close | 114 entries (50 modified, 64 untracked) |
| Untracked work from other workstreams | 20 test files, 2 lib files, 21 docs, migrations `000`, `104`–`122`, `supabase/tests/` |
| Migrations on disk | `000` … `122` |
| Migrations applied to QA (per Workstreams A/B) | through `122` |

**The tree moved underneath this audit.** Workstreams **J** (AI decision integrity), **K**
(billing & entitlement), **L** (release/environment) and **N** (test coverage) landed
their reports and test files while this workstream was running — 6 docs and 5 test files
appeared between the §2 snapshot and this one. Their contents were read at close and
cross-referenced where they interlock with a finding here (§7, and the correction to
**H-02** below). Nothing of theirs was modified. Findings in this report were derived
independently and before those artefacts existed; where a later artefact reaches the same
place, both are cited.

The tree was **not** reset, stashed, checked out, reverted or cleaned at any point. No
existing file was deleted or weakened. Untracked files belonging to other workstreams
were read but never modified. The only write this workstream made to the tree is the one
new test file listed in §12.

---

## 3. What was audited

| Brief area | Method | Depth |
|---|---|---|
| A Authentication & onboarding | `auth_service`, `auth_provider`, `app_router` redirect, migrations 044/109/115 | full |
| B Profile / account lifecycle | `personal_info`, `profile_screen`, settings, migration 102 policy | full |
| C Coach ↔ client relationship lifecycle | `coach_relationship_service`, `coach_provider`, `coach_ecosystem_provider`, RLS 100/102/113 | full, **live-probed** |
| D Home / dashboard | `home_screen`, `directory_screen`, `home_org` | full |
| E Coach dashboard / client management | `coach_dashboard_screen`, `dashboard_provider`, `compliance_service` | full |
| F Messaging & notifications | `messaging_service`, `chat_screen`, `notification_service`, prefs screen, RLS 003 | full |
| G Community / social | `live_community_service`, `community_provider`, `pods_screen` | full |
| H Marketplace / discovery | `marketplace_coaches()` (041/046/116), `coach_marketplace_screen`, `coach_provider` | full |
| I Nutrition | surface + contract check only | cross-ref Workstream E |
| J Check-in flows | contract + reachability check only | cross-ref Workstream E |
| K Women's health | contract check only | cross-ref Workstream F |
| L Progress / measurements / photos | `progress_screen`, `progress_service`, storage buckets | full, **live-probed** |
| M Habits / scores / challenges / gamification | `habit_provider`, `score_engine`, `score_service`, `live_challenge_service` | full |
| N Workout entry points & navigation (outside Phase 2) | `home_screen` session card, `workout_service` analytics reads | targeted |
| O Settings / help / account lifecycle | `settings_screen`, `help_center_screen`, `privacy_policy_screen` | full |
| P Nav-present but non-functional | 88-route reachability sweep vs every `context.go/push` | full |
| Q UI with missing backend | phantom-table, phantom-column and phantom-bucket sweeps | full, **live-probed** |
| R Backend with no UI | granted-RPC-vs-caller sweep, unreferenced screen/service sweep | full |
| S Writer/reader disagreement | column-level client-vs-migration diff; dual-scoring analysis | full |
| T Success-shaped masking | fabricated-fallback sweep (`getSample*` / `getDefault*` / demo fallbacks) | full |
| U Fixture data mistaken for a defect | classified per finding; seeded QA rows read live | full |

Structural sweeps run, and their headline results:

| Sweep | Result |
|---|---|
| 74 client tables vs every `CREATE TABLE/VIEW` | 2 phantom (`checkins`, `coach_tips`) — **reproduces Workstream B EC-10 exactly**, nothing new |
| 52 client `.rpc()` calls vs every `CREATE FUNCTION`, **including parameter names** | **0 mismatches.** Recorded as a PASS (§5.6) |
| ~600 client column references vs the migration column map | **3 phantom columns** (H-01, H-02, H-03) + 1 not statically visible (H-04) |
| 5 client storage buckets vs `INSERT INTO storage.buckets` | **2 phantom** (H-04, H-05) |
| 88 declared routes vs every `context.go/push` | 16 never navigated to; 10 explained, **2 features genuinely unreachable** (H-16) |
| 76 functions granted `EXECUTE` vs all callers | 24 uncalled; 22 are RLS/internal helpers, 2 cross-referenced to Workstream C |
| All `*_screen.dart` / `*_service.dart` vs their referrers | 1 unreferenced screen, 2 empty files (H-18) |

---

## 4. Evidence sources

**Repository (authoritative):** `docs/product-bible.md`, `docs/movement-intelligence-engine.md`,
`supabase/migrations/000`–`122`, `supabase/seeds/*`, `apps/mobile/lib/**`, `apps/mobile/test/**`,
`apps/api/**`.

**Prior QA artefacts (treated as authoritative for their own areas, and as *superseded*
wherever post-remediation behaviour differs):** `MASTER_QA_RECONCILIATION.md`,
`PHASE_1_SECURITY_AUDIT.md`, `PHASE_2_WORKOUT_RECONCILIATION.md`, `WORKOUT_DOMAIN_CONTRACT.md`,
`QA_WORKSTREAM_A/B/C/D/E/F/G`, `qa-workstream-d-report.md`.

**Live QA, read-only.** Two evidence techniques, both non-mutating:

1. **PostgREST column oracle.** PostgREST resolves the `select=` column list *before* it
   checks the table grant. A column that exists but is not granted answers
   `42501 permission denied`; a column that does not exist answers
   `42703 column … does not exist`. Anonymous `GET` requests therefore prove column
   existence without any privilege and without touching a row.
2. **Storage bucket oracle.** `GET /storage/v1/object/public/<bucket>/<missing-key>`
   answers `NoSuchKey` when the bucket exists and `NoSuchBucket` when it does not.

Verbatim QA responses, 2026-08-24:

```
workout_set_logs?select=created_at   400 {"code":"42703","message":"column workout_set_logs.created_at does not exist"}
workout_set_logs?select=logged_at    401 {"code":"42501","message":"permission denied for table workout_set_logs"}
event_registrations?select=ticket_code 400 {"code":"42703","message":"column event_registrations.ticket_code does not exist"}
event_registrations?select=qr_code     401 {"code":"42501", …}
messages?select=metadata             400 {"code":"42703","message":"column messages.metadata does not exist"}
messages?select=content              401 {"code":"42501", …}
custom_exercises?select=approved_by  400 {"code":"42703","hint":"Perhaps you meant … approved_at"}
checkins?select=id                   404 {"code":"PGRST205"}      (known — EC-10)
coach_tips?select=id                 404 {"code":"PGRST205"}      (known — EC-10)

storage/object/public/avatars/…         NoSuchKey     (bucket exists)
storage/object/public/coach-media/…     NoSuchKey     (bucket exists)
storage/object/public/exercise-media/…  NoSuchKey     (bucket exists)
storage/object/public/progress-photos/… NoSuchBucket  (bucket ABSENT)
storage/object/public/chat-media/…      NoSuchBucket  (bucket ABSENT)
```

**Two seeded-fixture logins** (`test@12circle.app`, `coach@12circle.app` — credentials
published in `supabase/seeds/test_accounts.sql`), used for `GET` requests only. See §13.

```
as CLIENT (relationship to the seeded coach = 'active'):
  coach_client_relationships?client_id=eq.<self>  200 [{"coach_id":"f626acd9…","status":"active"}]
  user_profiles?id=eq.<coach>                     200 []           <-- H-06
  user_profiles?id=eq.<self>                      200 [{"first_name":"Jordan"}]
  public_profiles?id=eq.<coach>                   200 [{"first_name":"Alex","role":"coach"}]

as COACH:
  user_profiles?select=id,first_name,role         200 [self, the ACTIVE client]   (correct)
```

---

## 5. Findings, ordered by severity

Every finding carries: severity · feature · expected · actual · repro · root cause ·
evidence · live? · user impact · security/privacy · dependencies · fixed elsewhere? ·
remediation · owner decision? · parallelisable?

### 5.1 P0

**None new.** Every P0-class defect found in this audit's areas was already closed by
Phase 1 on QA, and re-verified here (§7). The standing P0 exposure is unchanged and
belongs to a different workstream: **production has not received migrations 113–122**
(recorded in `PHASE_1_SECURITY_AUDIT.md` and in the project memory). This workstream did
not act on it.

Two findings below (H-19, H-11) are *security-adjacent data-integrity* defects of the
same class Phase 1 remediated. They are filed **P2** because both require an
authenticated, already-authorised participant and neither crosses a tenant boundary — but
they should be routed to a security workstream rather than fixed as product work. See §10.

---

### 5.2 P1

---

#### H-02 · P1 · Event registration writes a column that does not exist, then fabricates a ticket

| | |
|---|---|
| **Feature** | Events — register / ticket / vendor check-in (area H, Q, T) |
| **Expected** | Registering for a free event persists an `event_registrations` row and shows the ticket that row carries. The vendor's attendee list shows who registered. |
| **Actual** | `event_registrations` has `qr_code`, not `ticket_code`. Three call sites name `ticket_code`. The **write** 400s, is caught, and the `catch` block — commented `// Demo fallback` — invents `TKT-DEMO-<millis>`, sets `_registered = true`, and renders a ticket. Nothing was persisted. On reopening the screen the read also 400s, so the user is offered "Register & Get Ticket" again. The vendor's `getRegistrations()` does **not** catch, so the attendee list throws. |
| **Reproduction** | `/directory` → Events → any free event → *Register & Get Ticket* → a ticket with a `TKT-DEMO-…` code appears → leave and re-enter the screen → the register button is back. |
| **Root cause** | Writer/reader disagreement on a column name (`ticket_code` vs `qr_code`), *masked* by a fabricating `catch`. RC-C in Workstream B's taxonomy, with a fabricated success rather than an empty state. |
| **Evidence** | [`event_ticket_screen.dart:41`](../apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L41), [`:61`](../apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L61), [`:69`](../apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart#L69) (`// Demo fallback`); [`vendor_service.dart:41`](../apps/mobile/lib/features/vendor/data/vendor_service.dart#L41); schema [`001_full_ecosystem.sql:281`](../supabase/migrations/001_full_ecosystem.sql#L281). QA: `42703`. |
| **Live?** | **Yes** — column absence confirmed on QA read-only. |
| **User impact** | Free event registration is completely non-functional while *appearing* to succeed. The user believes they hold a ticket. The vendor sees an error instead of an attendee list and cannot check anyone in. |
| **Security / privacy** | None *in this client code path*. **Scope note, added at close:** the paid purchase path in the client is unaffected — it goes through Stripe Checkout and the webhook grants the row server-side. That is **not** a claim that paid tickets are safe. Workstream **K-04 (P0)** independently found that `event_registrations` carries `FOR ALL … USING (user_id = auth.uid())` with no `WITH CHECK`, so any authenticated user can `POST` themselves a row with `paid: true`. **K-04's finding stands and is more severe than this one.** |
| **Dependencies** | **Interlocks with K-04 — same table, and the fixes must be written together.** Also a correction to K-04's published reproduction: its payload includes `ticket_code:'TKT-X'`, which makes the request fail `PGRST204` rather than return `201`. The policy hole is real; the same `POST` **without** `ticket_code` is the one that succeeds. K-04's repro should drop that key. |
| **Fixed elsewhere?** | No. The column defect is not in any prior report; the adjacent policy defect is K-04. |
| **Remediation** | Rename the three client references to `qr_code` **or** add `ticket_code`; then delete the fabricating `catch` so a failed registration says so. The `// Demo fallback` block must go regardless of which side moves. |
| **Owner decision?** | No — `qr_code` already exists and already has a DB default. |
| **Parallel?** | Yes, fully isolated. |

---

#### H-03 · P1 · An admin can reject a submitted exercise but can never approve one

| | |
|---|---|
| **Feature** | Global exercise library review (area R; product bible §2.4 — *"Knowledge is reviewed before it becomes production truth"*) |
| **Expected** | An admin reviewing a coach's submitted exercise can approve it into the global library. |
| **Actual** | `approveGlobalExercise()` writes `approved_by`; `custom_exercises` has `approved_at` but no `approved_by`. The update 400s, is caught, returns `false`, and the screen shows **"Action failed. Please try again."** — forever. `rejectGlobalExercise()` writes no such column and works. |
| **Reproduction** | Sign in as `admin` → `/admin-exercise-review` → any pending submission → *Approve* → "Action failed. Please try again." *Reject* on the same row succeeds. |
| **Root cause** | Writer names a column that does not exist. |
| **Evidence** | [`custom_exercise_service.dart:766-773`](../apps/mobile/lib/features/exercise_database/data/custom_exercise_service.dart#L766-L773); [`exercise_review_screen.dart:34-47`](../apps/mobile/lib/features/admin/presentation/exercise_review_screen.dart#L34-L47). QA: `42703`, with PostgREST's own hint *"Perhaps you meant … approved_at"*. |
| **Live?** | **Yes.** |
| **User impact** | The human review pipeline the product bible makes load-bearing has a one-way valve: content can only be rejected. Coach-submitted exercises can never reach the global library through the UI. |
| **Security / privacy** | None. Fails closed. |
| **Dependencies** | Cross-references Workstream C Layer 10 (certification / review pipeline) — C found the pipeline under-populated; this is why its *approval* half cannot run at all. |
| **Fixed elsewhere?** | No. |
| **Remediation** | `ALTER TABLE custom_exercises ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES user_profiles(id);` — the column is genuinely wanted (it records *who* approved, which §2.2 "every recommendation is explainable" argues for). Alternatively drop the key from the payload. |
| **Owner decision?** | Minor — keep the reviewer identity or not. Recommend keeping it. |
| **Parallel?** | Yes. |

---

#### H-05 · P1 · The `progress-photos` bucket is created by no migration and does not exist on QA

| | |
|---|---|
| **Feature** | Progress photos; onboarding baseline photos; the coach's view of client photos (area L) |
| **Expected** | A client captures front/side/back baseline photos during intake and gallery photos from `/progress`; the coach sees them on the client detail screen. |
| **Actual** | Six client call sites use the `progress-photos` bucket. **Migration 029 writes `storage.objects` RLS policies *for* that bucket but nothing anywhere creates it.** QA answers `NoSuchBucket`. Every upload fails; every `createSignedUrl` fails and is swallowed into "no photo yet". |
| **Reproduction** | `/progress` → *Add photo* → pick an image → "Failed to upload photo". Onboarding photo step: the upload fails and the flow continues. `/progress` → Comparison Tool → permanently empty. |
| **Root cause** | **Architectural gap, not an environment blocker.** The migration sequence itself assumes the bucket exists — 029 is meaningless without it — and three sibling buckets (`avatars` 043, `coach-media` 036, `exercise-media` 061) *are* created by migrations. `progress-photos` was created out-of-band and then lost, exactly like the `on_auth_user_created` trigger that migration 109 had to recover. |
| **Evidence** | [`029_progress_photos_storage_rls.sql:1`](../supabase/migrations/029_progress_photos_storage_rls.sql#L1); [`progress_screen.dart:102`](../apps/mobile/lib/features/progress/presentation/progress_screen.dart#L102), [`:283`](../apps/mobile/lib/features/progress/presentation/progress_screen.dart#L283), [`:323`](../apps/mobile/lib/features/progress/presentation/progress_screen.dart#L323); [`intake_flow_screen.dart:3378`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L3378), [`:3434`](../apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart#L3434); [`coach_ecosystem_provider.dart:140`](../apps/mobile/lib/features/coach/domain/coach_ecosystem_provider.dart#L140), [`:153`](../apps/mobile/lib/features/coach/domain/coach_ecosystem_provider.dart#L153). QA: `NoSuchBucket`. |
| **Live?** | **Yes on QA.** |
| **User impact** | Progress photography — a headline transformation feature and an input to the coach's assessment — does not work at all in QA. A rebuilt environment, a preview branch or a local stack will behave the same way. |
| **Security / privacy** | The RLS the bucket *should* have is already written (029) and is owner-scoped + coach-scoped. Creating the bucket must set `public = false`, unlike the other three. Creating it public would expose every client's body photos. **Flagged explicitly.** |
| **Dependencies** | None. |
| **Fixed elsewhere?** | No. **Correcting Workstream G:** `QA_WORKSTREAM_G_APP_STORE_PRODUCTION_READINESS.md:64` states QA has four buckets including a private `progress-photos`. The live probe above shows only three exist. G's other bucket claims match. |
| **Remediation** | One migration: `INSERT INTO storage.buckets (id,name,public) VALUES ('progress-photos','progress-photos',false) ON CONFLICT (id) DO UPDATE SET public = false;` placed **before** 029 in effect (a new forward-only migration is fine — 029's policies are `CREATE POLICY` on `storage.objects` and do not require the bucket row to pre-exist). Then re-run the intake and progress photo paths. |
| **Owner decision?** | No. |
| **Parallel?** | Yes. |

---

#### H-06 · P1 · Migration 102 closed the client → coach profile read; four client surfaces still use it and now render empty

| | |
|---|---|
| **Feature** | "Your Coach" on Home, the coach card on `/directory` and `/profile`, "My Coaches" in Settings/Subscription, coach review author names, **and the coach's incoming-request list** (areas B, C, D, E) |
| **Expected** | A client with an active coach sees their coach's name, title, avatar and rate. A coach receiving a request sees who is asking. |
| **Actual** | Migration 102's SELECT policy on `user_profiles` is `id = auth.uid() OR is_active_coach_of(id) OR is_team_lead_of(id) OR hosts_event_for(id)`. It is **one-directional**: the coach may read their **active** client; the client may never read the coach, and a coach may not read a **pending** requester. Four client-side surfaces still read the base table and now silently get zero rows. |
| **Reproduction** | **Live-verified.** Signed in as the seeded client whose relationship to the seeded coach is `active`: `GET user_profiles?id=eq.<coach>` → `200 []`, while `GET public_profiles?id=eq.<coach>` → the coach's row. In the app: Home → the coach card treats the client as having no coach. |
| **Root cause** | 102's own header lists the surfaces it expected to be migrated to `public_profiles` / `conversation_participant_profiles` first — *"community feed, class list, pods, coach reviews, check-ins and the message list"*. The **assigned-coach** surfaces and the **pending-request** surface are not on that list and were not migrated. This is a completeness gap in a correct security change, not a fault in the policy. |
| **Evidence** | Policy: [`102_restrict_user_profiles.sql:166-173`](../supabase/migrations/102_restrict_user_profiles.sql#L166-L173); predicate: [`100_rls_harden_client_data.sql:21-35`](../supabase/migrations/100_rls_harden_client_data.sql#L21-L35) (`AND r.status = 'active'`). Broken readers: [`coach_provider.dart:26-30`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L26-L30) (`assignedCoachProvider`), [`:47-51`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L47-L51) (`pendingCoachProvider`), [`:92-96`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L92-L96) (`coachReviewsProvider` author names), [`coach_relationship_service.dart:68-72`](../apps/mobile/lib/features/coach/data/coach_relationship_service.dart#L68-L72) (`getPendingRequests`), [`:154-158`](../apps/mobile/lib/features/coach/data/coach_relationship_service.dart#L154-L158) (`getMyActiveCoaches`). Downstream consumers: `home_screen:1092`, `directory_screen:645`, `profile_screen:828`, `upgrade_screen:299`, `payment_result_screen:45`, `manage_subscription_screen:247`, `settings_screen:541`, `coach_marketplace_screen:496`, `coach_dashboard_screen:789`. |
| **Live?** | **Yes**, for the client→coach direction (probed). The coach→pending-requester direction is proven by the policy predicate; it was not exercised live because QA holds no pending relationship and creating one would be a QA mutation. |
| **User impact** | A paying coach-guided client is shown a product that behaves as if they have no coach: no coach card, no coach identity in the upgrade and post-payment flows, blank names in "My Coaches" and in the "End coaching with …" dialog. A coach sees incoming requests as an anonymous **"New Client"** card with no name, no email and no goal, and must accept or decline blind — `coach_dashboard_screen:825-849` renders `name.isEmpty ? 'New Client' : name`, so the fallback *looks* deliberate. |
| **Security / privacy** | **The policy is correct and must not be relaxed.** `assignedCoachProvider` currently asks for `email` among other columns; `public_profiles` deliberately excludes it. Any fix must move to the view, not widen the table. |
| **Dependencies** | Migrations 101/110 (`public_profiles`) are already applied — the destination exists. |
| **Fixed elsewhere?** | Partially: the same class of read was already migrated for community (`liveMembersProvider`), messaging (`conversation_participant_profiles`) and check-ins. These five sites were missed. |
| **Remediation** | Repoint all five reads at `public_profiles` and drop `email` from the column list. For the coach's pending-request list, `public_profiles` supplies name/avatar/role but **not** `fitness_goal` or `email`; deciding what a coach may see about someone who has requested them but is not yet their client is an **owner/policy decision** (§9, Q-H1). Minimum safe fix now: name + avatar from `public_profiles`, and stop rendering a blank subtitle. |
| **Owner decision?** | **Partly** — see Q-H1. The client→coach half needs no decision. |
| **Parallel?** | Yes; independent of every other finding. Guarded by test **H-G4**. |

---

#### H-07 · P1 · An empty or unreachable conversation renders four fabricated coach messages, including training advice

| | |
|---|---|
| **Feature** | Messaging (areas F, T) |
| **Expected** | A conversation with no messages shows a designed empty state (product bible §4 — *"Every state is designed: … empty …"*). |
| **Actual** | `chat_screen` substitutes `MessagingService.getSampleMessages()` — four hard-coded messages, three attributed to "Coach" — whenever the real message list is empty **and** whenever no conversation could be found or created at all. One of them is coaching advice: *"Make sure you're hitting your protein today for recovery."* |
| **Reproduction** | Open `/chat` on any coach-guided account with no messages yet, or with no active coach. Four messages appear, the newest marked unread, timestamped relative to now. |
| **Root cause** | A demo fallback left in a production path. `msgs.isNotEmpty ? msgs : _service.getSampleMessages()`. |
| **Evidence** | [`chat_screen.dart:76`](../apps/mobile/lib/features/messaging/presentation/chat_screen.dart#L76), [`:87`](../apps/mobile/lib/features/messaging/presentation/chat_screen.dart#L87); [`messaging_service.dart:237-245`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L237-L245). |
| **Live?** | **Yes** — pure client logic, no backend dependency. |
| **User impact** | The product fabricates a coaching relationship and puts health guidance in a named coach's mouth. The realtime stream replaces the fakes on the first genuine message, so this is invisible to anyone whose test account already has history — which is why it has survived. |
| **Security / privacy** | Not a data leak (the content is a literal in the binary). It is a **trust and liability** defect: unattributed health advice presented as coach communication. Directly contradicts product bible §6 (*AI/other layers may not fabricate*) and §4 (designed empty state). |
| **Dependencies** | Interacts with H-06: with `assignedCoachProvider` returning null, more users land on the `convId == null` branch. |
| **Fixed elsewhere?** | No. Workstream B **EC-13** recorded the *read-failure* half ("a failed message read renders as an empty conversation"); the fabrication half is not in EC-13. |
| **Remediation** | Delete `getSampleMessages()` and both call sites; render a designed empty state ("No messages yet — say hello") and, for `convId == null`, an explicit "You don't have a coach yet" with a route to `/coach-marketplace`. |
| **Owner decision?** | No. |
| **Parallel?** | Yes. |

---

#### H-08 · P1 · With no assigned habits, the app invents eight habits with invented streaks and schedules reminders for them

| | |
|---|---|
| **Feature** | Daily Habits (areas M, T, U) |
| **Expected** | A client with no coach-assigned habits sees an empty state or an "add a habit" affordance. |
| **Actual** | `liveHabitsProvider` and `LiveHabitNotifier._load()` both fall back to `HabitService.getDefaultHabits()` — eight fabricated habits carrying **fabricated current streaks** (7, 4, 12, 3, 9, 5, 6, 2 days), **fabricated longest streaks** (up to 30), **fabricated current values** (5 glasses of water, 6 240 steps, 85 g protein) and one marked already complete today. `HabitReminderService().scheduleHabitReminders(habits)` is then called on that list, so the device is scheduled to remind the user about habits they never set. |
| **Reproduction** | Any account with no `client_habits` rows → `/habits`. Eight habits with multi-day streaks appear on first launch. Toggling one optimistically marks it complete, the write fails on the non-UUID id, and the next reload silently reverts it. |
| **Root cause** | Demo seed used as a runtime fallback for a legitimately empty domain answer. Category **U** in the brief's taxonomy — but the fabrication is in the *application*, not in the fixtures, so it is an implementation defect, not a data blocker. |
| **Evidence** | [`habit_service.dart:4-18`](../apps/mobile/lib/features/habits/data/habit_service.dart#L4-L18); [`habit_provider.dart:24-26`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L24-L26), [`:83-85`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L83-L85), [`:108-110`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L108-L110) (reminder scheduling), [`:178`](../apps/mobile/lib/features/habits/domain/habit_provider.dart#L178). |
| **Live?** | **Yes** — pure client logic. |
| **User impact** | Fabricated adherence and streak metrics presented as the user's own health data, plus unsolicited device notifications. A 12-day step streak the user never earned is the single clearest violation of the product's own "every recommendation is explainable" principle. |
| **Security / privacy** | None. |
| **Dependencies** | Workstream B **EC-12** owns the *swallowed write* half ("habit writes are optimistic, swallow failure, then award score from un-persisted state"). Verified here: the score award is **not** reached for the fabricated habits, because `logHabit()` throws on the non-UUID id before `_score.addHabitPoints()` runs. EC-12's concern is real for genuine habits; it does not compound this finding. |
| **Fixed elsewhere?** | No. |
| **Remediation** | Replace the fallback with an empty state. If a starter habit set is wanted as a *product* feature, it must be seeded as real `client_habits` rows at onboarding with zero streaks — that is an **owner decision** (§9, Q-H2). |
| **Owner decision?** | **Yes**, for whether default habits should exist at all. Removing the fabricated streaks does not. |
| **Parallel?** | Yes. |

---

### 5.3 P2

---

#### H-01 · P2 · `workout_set_logs.created_at` does not exist, so the Strength Progression chart is permanently empty

*Outside the Phase 2 contract surface: this is an analytics read, not part of the
set-identity / session-lifecycle / prescription contract Phase 2 closed.*

| | |
|---|---|
| **Feature** | `/strength-progression` (area N) |
| **Expected** | The chart shows max weight and volume per date for a chosen exercise. |
| **Actual** | `getExerciseProgression()` selects and orders `created_at`; the column is `logged_at`. The request 400s, the `catch` returns `[]`, and the screen shows **"No sets logged yet for this exercise. Complete a workout to see progress."** The exercise picker above it works — it reads `exercise_name` — so the exercise is listed and its chart is always empty. |
| **Reproduction** | Log any set, then `/strength-progression` → pick that exercise → "No sets logged yet". |
| **Root cause** | Writer/reader column disagreement, masked by a swallow. |
| **Evidence** | [`workout_service.dart:231-243`](../apps/mobile/lib/features/workout/data/workout_service.dart#L231-L243); schema [`001_full_ecosystem.sql:158-169`](../supabase/migrations/001_full_ecosystem.sql#L158-L169) (`logged_at`, no `created_at`); consumer [`strength_progression_screen.dart:104-112`](../apps/mobile/lib/features/workout/presentation/strength_progression_screen.dart#L104-L112). QA: `42703`. |
| **Live?** | **Yes.** |
| **User impact** | A headline progress-tracking screen is permanently and convincingly empty. |
| **Security / privacy** | None. |
| **Dependencies** | Workstream B **EC-11** flags this file's swallows generically; it identifies the swallow, not the column. This finding is the *reason* the swallow is permanent rather than incidental. Fixing EC-11 without fixing this turns a silent empty chart into a visible permanent error. **Fix H-01 first.** |
| **Fixed elsewhere?** | No. |
| **Remediation** | Two edits in one method: `select('weight_kg, reps, logged_at')`, `order('logged_at', ascending: true)`, and read `row['logged_at']`. |
| **Owner decision?** | No. |
| **Parallel?** | Yes. Guarded by test **H-G1**. |

---

#### H-04 · P2 · Sending a photo in chat fails twice over and tells nobody

| | |
|---|---|
| **Feature** | Chat photo messages (areas F, Q, T) |
| **Expected** | Attaching a photo uploads it and posts a message the recipient can see. The message-bubble widget already supports it (`message_bubble_test.dart` — "UC13 photo messages"). |
| **Actual** | Two independent breaks. (1) `chat-media` is created by **no** migration and answers `NoSuchBucket` on QA. (2) `messages` has no `metadata` column, so even with the bucket the insert would 400. `sendMessage()` catches and returns `false`; **`_sendPhoto` never checks the return value**, so on the second failure mode nothing at all is shown. |
| **Reproduction** | `/chat` → attach a photo. Today the bucket failure is caught by `_sendPhoto`'s own `try`, so "Failed to send photo" *is* shown. Create the bucket without adding the column and the failure becomes completely silent. |
| **Root cause** | A feature shipped end-to-end in the UI and the widget tests with neither of its two backend prerequisites created. |
| **Evidence** | [`chat_screen.dart:140-165`](../apps/mobile/lib/features/messaging/presentation/chat_screen.dart#L140-L165); [`messaging_service.dart:145-160`](../apps/mobile/lib/features/messaging/data/messaging_service.dart#L145-L160); no `chat-media` anywhere in `supabase/`. QA: `NoSuchBucket` + `42703`. |
| **Live?** | **Yes**, both halves. |
| **User impact** | Photo messaging does not work. Coaches cannot receive form-check photos through chat. |
| **Security / privacy** | The bucket, when created, must be **private** with participant-scoped RLS — form-check photos are body images. A public `chat-media` bucket (matching the pattern of the other three) would publish them. **Flagged.** |
| **Dependencies** | None. |
| **Fixed elsewhere?** | No. |
| **Remediation** | One migration creating a private `chat-media` bucket with `shares_conversation_with()`-scoped object policies, plus `ALTER TABLE messages ADD COLUMN IF NOT EXISTS metadata jsonb;`, plus checking `sendMessage`'s boolean in `_sendPhoto`. |
| **Owner decision?** | Bucket visibility and retention — recommend private, and record it. |
| **Parallel?** | Yes. Guarded by tests **H-G2**, **H-G3**. |

---

#### H-09 · P2 · Challenges can be joined but never progress, never complete, and two of three tabs can never populate

| | |
|---|---|
| **Feature** | Challenges / gamification (areas M, P, R) |
| **Expected** | A joined challenge shows progress toward its target, a live leaderboard, and moves to Completed. |
| **Actual** | Three structural gaps, all confirmed by call-graph analysis: (1) `ChallengeNotifier.updateProgress()` and `LiveChallengeService.updateProgress()` have **zero callers** — nothing in the app ever advances `challenge_participants.current_progress`, so every joined challenge sits at 0 % and `ScoreEngine.completeChallenge()` (+100) is unreachable. (2) `getActiveChallenges()` queries `status='active'` and hard-codes `status: ChallengeStatus.active` on every row it builds, while `/challenges` renders three tabs fed by `activeChallengesProvider`, `upcomingChallengesProvider` and `completedChallengesProvider` — **"Upcoming (0)" and "Completed (0)" are structurally unreachable**. (3) `createChallenge()` has zero callers — there is no UI anywhere to create a challenge. |
| **Reproduction** | `/challenges` (QA has three seeded active challenges) → Join → progress bar stays at 0 % indefinitely; the Upcoming and Completed tabs are always empty; no create affordance exists for a coach or an admin. |
| **Root cause** | A presentation layer built ahead of its write paths. Not a data blocker — QA is seeded. |
| **Evidence** | [`challenge_provider.dart:46-59`](../apps/mobile/lib/features/challenges/domain/challenge_provider.dart#L46-L59), [`:74-84`](../apps/mobile/lib/features/challenges/domain/challenge_provider.dart#L74-L84); [`live_challenge_service.dart:8-66`](../apps/mobile/lib/features/challenges/data/live_challenge_service.dart#L8-L66), [`:89-99`](../apps/mobile/lib/features/challenges/data/live_challenge_service.dart#L89-L99), [`:100-108`](../apps/mobile/lib/features/challenges/data/live_challenge_service.dart#L100-L108); [`challenges_screen.dart:118-124`](../apps/mobile/lib/features/challenges/presentation/challenges_screen.dart#L118-L124). QA read as the seeded client: three `status='active'` rows. |
| **Live?** | **Yes.** |
| **User impact** | Challenges are joinable decoration. Every leaderboard entry additionally renders as the literal string **"Participant"** — `_buildLeaderboard` never resolves a display name (`live_challenge_service.dart:127`), which is also the correct post-102 behaviour for a name it cannot read, but it is not a designed one. |
| **Security / privacy** | None. |
| **Dependencies** | Name resolution shares a root with H-06 — use `public_profiles`. |
| **Fixed elsewhere?** | No. |
| **Remediation** | Decide what a challenge's progress *is* (workouts completed? steps? nutrition days?) — that is **owner input** (§9, Q-H3), because the deterministic source differs per `challenge_type` and the product bible forbids guessing it. Until then, the honest change is to hide the two unreachable tabs and label joined challenges "Tracking coming soon" rather than showing a 0 % bar. Resolve leaderboard names from `public_profiles`. |
| **Owner decision?** | **Yes** — Q-H3. |
| **Parallel?** | The tab/label/name half, yes. The progress half is blocked. |

---

#### H-10 · P2 · Six notification preferences are persisted and nothing honours them

| | |
|---|---|
| **Feature** | `/notification-preferences` (areas F, O, T) |
| **Expected** | Turning off "Coach Messages" stops coach-message notifications. |
| **Actual** | All six `notif_*` columns are written correctly. **No producer reads any of them.** An exhaustive search of `supabase/migrations`, `supabase/functions` and `apps/api` finds `notif_*` in exactly one file — migration 010, which *creates* the columns. The `trg_notify_on_message` trigger, `insert_notification()`, `send-checkin-reminder` and every `notifyUser()` call fire unconditionally. The only two consumers anywhere are UI-visibility checks in `activity_screen` for `notif_challenges` and `notif_community`. |
| **Reproduction** | Turn every toggle off. Have a coach send a message. The notification still arrives. |
| **Root cause** | A preferences surface built without the enforcement half. |
| **Evidence** | [`notification_preferences_screen.dart:41-56`](../apps/mobile/lib/features/profile/presentation/notification_preferences_screen.dart#L41-L56); [`010_profile_columns.sql:15-20`](../supabase/migrations/010_profile_columns.sql#L15-L20); [`004_notifications_and_triggers.sql:102-105`](../supabase/migrations/004_notifications_and_triggers.sql#L102-L105). |
| **Live?** | **Yes.** |
| **User impact** | The user believes they have opted out and has not. |
| **Security / privacy** | **Consent.** An un-honoured opt-out is a consent defect, and once push and email are wired (Workstream D's `send-checkin-reminder`, `notify-coach-email`) it becomes a communications-compliance problem too. Recorded as privacy-relevant. |
| **Dependencies** | Workstream D **E-01/E-02** (unauthenticated notification/email functions) touch the same producers; fixing those is the natural place to add the preference check. |
| **Fixed elsewhere?** | No. |
| **Remediation** | Add a `may_notify(recipient uuid, kind text)` helper (the name is already reserved — a function by that name exists and is granted but uncalled) and gate `insert_notification()` and each email function on it. Until then, the honest interim is to disable the toggles with "coming soon" rather than persist a promise that is not kept. |
| **Owner decision?** | The mapping from the six toggles to notification `type` values needs one pass of owner input. |
| **Parallel?** | Yes, but best sequenced with Workstream D's Wave 3. |

---

#### H-11 · P2 · Two parallel "12 Circle Score" systems, two disagreeing leaderboards, and one of them is client-writable

| | |
|---|---|
| **Feature** | 12 Circle Score, Insights, coach leaderboard (areas M, S) |
| **Expected** | One score. The product bible names "12 Circle Score" as a single concept and §2.1 states *"The engine decides."* |
| **Actual** | Two complete, independent systems, called side by side in the same handlers. **(A)** `ScoreEngine` → the `award_points` / `penalize_points` SECURITY DEFINER RPCs → `score_events` + `user_scores` + `score_cycles` + auto-granted badges. Server-authoritative, deduplicated, auditable. Read by `/score` and by the `leaderboard_global` / `leaderboard_coach` RPCs. **(B)** `ScoreService` → a client-side read-modify-write `upsert` into `daily_scores` with hard-coded category caps (30/30/20/10/10). Read by `/insights`, by the Home Wellness Pulse and by the coach dashboard's leaderboard. `PostNotifier.addPost` calls **both** (`ScoreEngine().communityPost()` *and* `_score.addCommunityPoints()`). |
| **Reproduction** | Compare `/score` (system A) with `/insights` (system B) on the same account — different numbers, different scales. Compare the coach dashboard leaderboard (B) with `leaderboard_coach` (A) — different orderings. |
| **Root cause** | System B predates system A and was never retired. |
| **Evidence** | A: [`score_engine.dart`](../apps/mobile/lib/features/scoring/data/score_engine.dart), [`035_scoring_engine.sql`](../supabase/migrations/035_scoring_engine.sql). B: [`score_service.dart:38-87`](../apps/mobile/lib/features/coach/data/score_service.dart#L38-L87), [`:89-110`](../apps/mobile/lib/features/coach/data/score_service.dart#L89-L110). Both called at [`community_provider.dart:71-75`](../apps/mobile/lib/features/community/domain/community_provider.dart#L71-L75). |
| **Live?** | **Yes.** |
| **User impact** | Two authoritative-looking scores that can and do disagree. A read-modify-write upsert with no concurrency control also loses category points under concurrent updates. |
| **Security / privacy** | **`daily_scores` carries `CREATE POLICY "users manage own scores" … FOR ALL … USING (user_id = auth.uid())` ([`001_full_ecosystem.sql:378`](../supabase/migrations/001_full_ecosystem.sql#L378)) — the client can `PATCH` their own `total_score` to any value, and the coach dashboard leaderboard reads exactly that column.** The leaderboard is therefore forgeable by any client. System A is not: `award_points` is a definer RPC on 116's allow-list. Phase 1 audited *which commands* each table exposes, not the column scope of a client-owned `FOR ALL` — this is a genuine gap, of the same class Phase 1 remediated. **Route to a security workstream, not to product.** |
| **Dependencies** | None technically; H-15 (unreachable scoring rules) is a symptom of the same drift. |
| **Fixed elsewhere?** | No. |
| **Remediation** | Two steps, in order. (1) **Decide which system is canonical** — Q-H4, owner decision, though the product bible's determinism principle points unambiguously at system A. (2) Retire the other; if B is retained for the daily 0–100 view, derive it server-side from `score_events` and revoke client `INSERT`/`UPDATE` on `daily_scores`. |
| **Owner decision?** | **Yes** — Q-H4. |
| **Parallel?** | The RLS half can be done immediately and independently. |

---

#### H-12 · P2 · The marketplace ranks demo fixtures and coaches who have closed their books alongside real ones

| | |
|---|---|
| **Feature** | Coach marketplace / discovery (area H) |
| **Expected** | `/coach-marketplace` lists coaches a client can actually engage. Migration 110 exists precisely so demo accounts can be excluded by an explicit flag. |
| **Actual** | `marketplace_coaches()` selects `FROM user_profiles p … WHERE p.role = 'coach'` and applies **no `is_demo` filter and no `is_accepting_clients` filter**. The client's fallback path (used when the RPC is unavailable) reads `public_profiles` and filters neither either. Meanwhile the *other* discovery surface, `availableCoachesProvider` (`/coach-directory`), filters `is_accepting_clients = true` and computes capacity via `coach_active_client_counts()` — but also does not filter `is_demo`. **Two discovery surfaces, two different admission rules, neither excluding fixtures.** |
| **Reproduction** | `/coach-marketplace` on QA lists the seeded marketplace fixture coaches; the same coaches appear whether or not they accept clients. |
| **Root cause** | 110 added the flag and refreshed `public_profiles`, but no consumer was updated. |
| **Evidence** | [`046_marketplace_package_pricing.sql:49-68`](../supabase/migrations/046_marketplace_package_pricing.sql#L49-L68); [`coach_marketplace_screen.dart:24-39`](../apps/mobile/lib/features/coach/presentation/coach_marketplace_screen.dart#L24-L39); [`coach_provider.dart:106-113`](../apps/mobile/lib/features/coach/domain/coach_provider.dart#L106-L113); [`110_profile_demo_flag.sql:37`](../supabase/migrations/110_profile_demo_flag.sql#L37). |
| **Live?** | **Yes.** |
| **User impact** | Clients can request a fixture account or a coach at capacity. Fixture coaches occupy ranked positions ahead of real ones. |
| **Security / privacy** | None new. |
| **Dependencies** | None. |
| **Fixed elsewhere?** | **This is Workstream D's D-04 (P3), still open.** Re-severitied to P2 here because the `is_accepting_clients` half and the two-surfaces-two-rules half were not part of D-04. `community_provider.liveMembersProvider` shows the intended pattern — it already filters `.eq('is_demo', false)`. |
| **Remediation** | Add `AND COALESCE(p.is_demo,false) = false` to `marketplace_coaches()`; decide whether it should also require `is_accepting_clients` (Q-H5) or surface a "not taking clients" badge; add `.eq('is_demo', false)` to both client fallbacks. |
| **Owner decision?** | Q-H5 only — show-but-disable vs hide. |
| **Parallel?** | Yes. |

---

#### H-14 · P2 · With no program, Home starts a hard-coded demo workout credited to a fictional coach

*Outside the Phase 2 contract surface: Phase 2 made this session log **correctly**
(migration 103 made `workout_sessions.workout_id` `text`, so sample id `'1'` persists
cleanly). The defect is what the session **is**, not how it is recorded.*

| | |
|---|---|
| **Feature** | Home "Start Circle" (areas D, N, T) |
| **Expected** | A self-guided client with no program is routed to plan generation — `coaching_mode_provider` already calls `generate_client_plan()` on mode selection. |
| **Actual** | `_FitnessSessionCard.onStart()` falls back to `workoutsProvider`, which is `WorkoutService.getSampleWorkouts()` — three hard-coded workouts whose `coachName` is **"Coach Sarah"**. The client trains it and logs real sets against it. |
| **Reproduction** | Self-guided account with no `workout_program_assignments` → Home → *Start Circle* → "Full Body Strength", attributed to Coach Sarah. |
| **Root cause** | Demo content on a production path, guarded by a comment reading *"fall back to the sample library only when no program exists yet (e.g. legacy accounts)"*. |
| **Evidence** | [`home_screen.dart:940-943`](../apps/mobile/lib/features/home/presentation/home_screen.dart#L940-L943), [`:966-971`](../apps/mobile/lib/features/home/presentation/home_screen.dart#L966-L971); [`workout_provider.dart:108-110`](../apps/mobile/lib/features/workout/domain/workout_provider.dart#L108-L110); [`workout_service.dart:27-52`](../apps/mobile/lib/features/workout/data/workout_service.dart#L27-L52). The same fallback exists at [`workout_list_screen.dart:156`](../apps/mobile/lib/features/workout/presentation/workout_list_screen.dart#L156). |
| **Live?** | **Yes.** |
| **User impact** | A generic template presented as the user's session, credited to a coach who does not exist — the exact thing the product positions itself against (*"a system that reasons like a coach instead of shuffling a static template"*). |
| **Security / privacy** | None. |
| **Dependencies** | The correct destination (`generate_client_plan`) exists and is on 116's allow-list. Workstream C's readiness caveats apply to what it will produce. |
| **Fixed elsewhere?** | No. Phase 2 §8 noted the sibling title-matching in `workout_list_screen:315` as a residual and explicitly did not treat the sample library itself. |
| **Remediation** | Replace the fallback with the plan-generation call plus a "Build my plan" state. Whether to keep a browsable demo library at all is **Q-H6**. |
| **Owner decision?** | **Yes** — Q-H6. |
| **Parallel?** | Yes, once Q-H6 is answered. |

---

#### H-19 · P2 · A conversation participant can rewrite the other party's message content

| | |
|---|---|
| **Feature** | Messaging integrity (area F; security-adjacent) |
| **Expected** | `markAsRead()` flips `is_read`. Nothing else about a message a participant did not send is theirs to change. |
| **Actual** | `CREATE POLICY "recipients can mark messages read" ON messages FOR UPDATE TO authenticated USING (conversation_id IN (my conversations))` — **no `WITH CHECK`, no column restriction**. Postgres reuses the `USING` expression as the check, so any participant may `PATCH` any message in their conversation, including `content` and `sender_id`, as long as `conversation_id` is unchanged. |
| **Reproduction** | By inspection of the policy. **Not exercised live** — proving it requires writing to QA, which this workstream did not do. |
| **Root cause** | An UPDATE policy written for one column and scoped to none. |
| **Evidence** | [`003_fk_and_rls_fixes.sql:96-104`](../supabase/migrations/003_fk_and_rls_fixes.sql#L96-L104). Confirmed still current: no later migration touches a `messages` policy. |
| **Live?** | Policy is live; effect not exercised. |
| **User impact** | The coaching conversation is not a reliable record. A client could alter what a coach instructed, or a coach what a client reported. |
| **Security / privacy** | **Data integrity within an authorised boundary.** No cross-tenant read or write; both parties are already entitled to the conversation. This is why it is P2 and not P0 — but it is the same *class* Phase 1 remediated (an `ALL`/unscoped policy on a table whose sensitive columns nobody meant to expose), and it belongs to a security workstream. `conversations.last_message` has the same shape. |
| **Dependencies** | None. |
| **Fixed elsewhere?** | No. Phase 1 §6 recorded `messages` as *"3 policies, INSERT/SELECT/UPDATE, no blanket-true"* — it audited policy presence, not UPDATE column scope. |
| **Remediation** | The Phase 1 pattern: a `BEFORE UPDATE` trigger pinning every column except `is_read` to `OLD` for `auth.uid() IS NOT NULL`, mirroring 115's PINNED class. **Do not fix as product work.** |
| **Owner decision?** | No. |
| **Parallel?** | Yes — hand to the security workstream. |

---

### 5.4 P3

| ID | Finding | Evidence | Notes |
|---|---|---|---|
| **H-13** | **Community Groups falls back to five fictional groups.** When `community_groups` is empty, `liveGroupsProvider` substitutes `getSampleGroups()` — five invented groups with invented member counts (248/183/142/321/97), **two of them pre-marked "Joined"**. Tapping *Join* calls `joinGroup('1')`; `group_id` is `uuid`, so the insert 400s, `joinGroup` returns `false`, and `toggleJoin` changes nothing and shows nothing. | [`community_provider.dart:112-121`](../apps/mobile/lib/features/community/domain/community_provider.dart#L112-L121), [`:170-176`](../apps/mobile/lib/features/community/domain/community_provider.dart#L170-L176); [`community_service.dart:110-118`](../apps/mobile/lib/features/community/data/community_service.dart#L110-L118); [`community_screen.dart:298-302`](../apps/mobile/lib/features/community/presentation/community_screen.dart#L298-L302) | **Latent on QA** — `community_groups` is seeded with real UUID rows (read live), so the fallback does not fire there. It fires on any fresh or unseeded environment. Category U. Same remediation shape as H-08/H-13/H-07: delete the fallback, design the empty state. |
| **H-15** | **Six scoring rules can never fire.** `allWorkoutsThisWeek` (+50), `attendEvent` (+50), `attendSession` (+25), `habitStreak7` (+50), `reviewCoachFeedback` (+5), `workoutResumeFinished` (+15) have zero callers; `completeChallenge` (+100) is reachable only from the callerless `updateProgress` (H-09). | [`score_engine.dart`](../apps/mobile/lib/features/scoring/data/score_engine.dart) — call-graph sweep of all 24 typed helpers | No published points table in the UI, so nothing the product *promises* is unmet. Dead-rule inventory; part of the H-11 drift. |
| **H-16** | **Two features are unreachable from anywhere in the UI.** `/pods` (`PodsScreen` — accountability pods, backed by `accountability_pods` / `accountability_pod_members` and migration 080) and `/coach-client-workouts` (`CoachClientWorkoutScreen`) have **no** `context.go/push` and no `MaterialPageRoute` anywhere outside their own files. Four further routes are dead but their screens are reachable another way: `/coach-business` (pushed directly from three screens), `/nutrition-overview`, `/food-search`, `/log-meal`. | 88-route sweep vs all navigation calls; class-reference sweep | Area R. Decide per feature: wire a nav entry or retire the route. `accountability_pods` holds 1 seeded row on QA. |
| **H-17** | **Three inert controls in Settings.** "Dark Mode" renders a static `ACTIVE` label with no control; "Sound Effects" is a toggle whose only effect is local `setState` — never persisted, never read; "Language" is a row showing "English (US)" with a chevron and no `onTap`. | [`settings_screen.dart:263-305`](../apps/mobile/lib/features/settings/presentation/settings_screen.dart#L263-L305) | Area O/T. Smaller sibling of H-10. |
| **H-18** | **Dead code inventory.** `profile_service.dart` and `profile_provider.dart` are **0-byte files**. `progress_provider.dart`'s five sample-backed providers have no consumers. `classNotifierProvider` + `upcomingClassesProvider` + `myBookingsProvider` in `class_provider.dart` are shadowed by live providers of the same name in `dashboard_provider.dart` and are unused. `LiveChallengeService.createChallenge()` and `MessagingService.getSampleMessages()` (once H-07 lands) have no legitimate callers. Two `print()` calls remain in `messaging_service.dart`. | file sweep; `apps/mobile/lib/features/profile/data/profile_service.dart` | Hygiene. Deleting the empty files and the sample progress providers is zero-risk. |
| **H-20** | **`/checkin-detail` is a live route rendering "Check-in details coming soon".** | [`checkin_detail_screen.dart:20`](../apps/mobile/lib/features/checkins/presentation/checkin_detail_screen.dart#L20) | **Already reported** — Workstream E **E-CHK-06**. Re-verified unchanged; listed for completeness only. |
| **H-21** | **`/directory` labels the daily check-in as "Weekly Check-ins".** The Daily Tools card titled *"Weekly Check-ins"*, described *"Reflect on your week and get coach feedback"*, routes to `/daily-checkin`. | [`directory_screen.dart:65-67`](../apps/mobile/lib/features/dashboard/presentation/directory_screen.dart#L65-L67) | Corroborates Workstream E's Q-1 (is there a daily check-in distinct from the weekly one?). Recorded as **evidence for E's open question**, not as a separate defect. |

---

### 5.5 Correction to a prior report

`QA_WORKSTREAM_G_APP_STORE_PRODUCTION_READINESS.md:64` states that QA holds **four**
storage buckets, *"`progress-photos` is private with owner-scoped RLS."* Live probe:
`progress-photos` answers `NoSuchBucket`. Three buckets exist. G's other bucket
statements are correct. Recorded here rather than edited into G's file, per the
no-rewriting-another-workstream's-artefact convention.

### 5.6 Verified good — worth pinning

These were checked and are correct; they are recorded so a future change that breaks them
is visibly a regression.

| Area | What holds |
|---|---|
| **RPC contract** | All 52 client `.rpc()` calls resolve to a defined function, **and every one of the 31 that passes `params` passes only parameter names the function declares.** Zero drift across the whole surface. |
| **Phase 1 role boundary** | `signUp()` still puts a caller-supplied `role` into `raw_user_meta_data` and `handle_new_user()` still reads it — but migration 115 constrains the vocabulary and pins the privileged columns, and self-service `client|coach|vendor` is the documented product model. **Not a finding.** |
| **Coach rating rollup** | `home_screen`'s post-review `user_profiles` write of `rating_avg`/`review_count` is a deliberate, documented no-op: migration 045's `coach_review_rollup` trigger owns the aggregate and 115 pins both columns to `OLD`. 115's header names this exact call site. **Not a finding.** |
| **Home featured card** | The `const progress: 0.65` in `directory_screen`'s `_featured` literal is fully overridden by live session state in `_FeaturedCard.build`. **Not a fabricated metric.** |
| **Messaging authorization** | `getConversations()` correctly reads `conversation_participant_profiles`, not `user_profiles`; `getOrCreateClientCoachConversation()` correctly resolves the *assigned active* coach rather than the first coach on the platform. Post-102 correct. |
| **Community member discovery** | `liveMembersProvider` correctly reads `public_profiles` and filters `is_demo` — the reference implementation the other surfaces in H-06/H-12 should follow. |
| **Capacity counting** | `availableCoachesProvider` correctly takes client counts from the `coach_active_client_counts()` aggregate rather than reading relationship rows, with migration 113's scoping written into the comment. Post-Phase-1 correct. |
| **Insights** | Reads entirely real data — no fabricated fallback anywhere in `insights_provider`. |
| **Goals** | Every write is owner-scoped (`.eq('client_id', uid)` on update *and* delete); no contract drift. |
| **Paid event tickets** | Unaffected by H-02 — the paid path goes through Stripe Checkout and the webhook grants the registration server-side. |

---

## 6. Root-cause clusters

Twenty-one findings reduce to five causes.

### RC-H1 · Fabricated fallback for an empty domain answer — *the dominant cluster*
**H-07, H-08, H-13, H-14**, and the latent halves of H-18.
A demo seed used at runtime when the real answer is legitimately "nothing yet". Every
instance produces *plausible* content — invented streaks, invented coach messages,
invented groups the user is already a member of, a workout by a coach who does not exist.
None is distinguishable from real data by looking at the screen, which is why all four
survived six prior workstreams. This is the direct product-integrity analogue of
Workstream B's RC-C (*a failure rendered as an empty state*): here a **nothing** is
rendered as a **something**. It contradicts product bible §4 (*"Every state is designed …
empty …"*) and §6 (*may not fabricate metrics*).
**Single remediation shape for all four:** delete the fallback, design the empty state,
and — where a starter set is genuinely wanted — seed it as real rows with real (zero)
history.

### RC-H2 · Column-level writer/reader drift, invisible because every caller swallows
**H-01, H-02, H-03, H-04.**
Four columns the client names that no migration creates. PostgREST answers each with a
400 that a `catch` converts into `[]`, `false`, or — in H-02 — a fabricated success.
Structurally identical to Workstream B's EC-10 (two *tables* that do not exist) one level
down, and it went unfound because EC-10's guard checks table names only. **H-G1 closes
that gap permanently.** Note the interaction: fixing B's swallows (EC-11) *before* these
columns converts four silent failures into four visible permanent errors.

### RC-H3 · A correct security change whose read-path migration was left half-done
**H-06**, and the leaderboard-name half of **H-09**.
Migration 102 is right and must stand. Its header lists the surfaces to be repointed at
`public_profiles`; five were missed, and the client→coach direction was never considered
at all. Every symptom is a silent zero-row read. The fix is mechanical and the
destination already exists.

### RC-H4 · Presentation shipped ahead of its write path
**H-09, H-10, H-16, H-17**, and `createChallenge` in H-18.
Tabs with no data source, toggles with no consumer, screens with no route, services with
no caller. In each case the read half and the UI exist and look finished. Distinguishing
mark: no error is ever produced, because no call is ever made.

### RC-H5 · Two systems for one concept, never reconciled
**H-11** (two scores, two leaderboards, one of them client-writable), **H-12** (two
discovery surfaces with different admission rules), and **H-15** as its residue. In each
case the newer, server-authoritative system was built and the older client-side one was
left running beside it.

---

## 7. Fixed / already-closed findings encountered

Verified current status rather than reopened, as instructed.

| Prior finding | Status now | Evidence |
|---|---|---|
| **D-01/D-02/D-03** (relationships, role escalation, `weekly_checkins`) — P0 | **CLOSED on QA.** `is_active_coach_of` requires `status='active'`; 115 pins the privileged columns and constrains the role vocabulary; anon holds no grant (every anon probe returned `42501`, not data). | migrations 113–118; live probes §4 |
| **F-07** (anon holds table grants across the schema) | **CLOSED.** Every anonymous probe in §4 answered `42501 permission denied`, never a row. | live |
| **EC-10 / CON-01** (`checkins`, `coach_tips` do not exist) | **UNFIXED, unchanged.** Both still 404 `PGRST205` on QA. My independent table sweep found **exactly these two and no others**, corroborating B's count. | live |
| **D-04** (demo coaches in the marketplace) — P3 | **UNFIXED.** Re-filed as **H-12** at P2 with two additional halves. | §5.3 |
| **D-06** (client can rewrite completed workout history) | **CLOSED by Phase 2** — migration 120's `workout_set_logs_protect_history`. Not re-audited. | 120 |
| **REL-04** (no in-app account deletion; help centre and privacy policy both promise a path that does not exist) | **UNFIXED, and confirmed by independent sweep** — `lib/` contains the two promise strings and no deletion UI, service or RPC. **Workstream G owns this.** Not re-filed. | `help_center_screen.dart:45`, `privacy_policy_screen.dart:86` |
| **E-CHK-06** (placeholder screens on live routes) | **UNFIXED.** Re-verified — listed as H-20 for completeness only. | live route `/checkin-detail` |
| **EC-11** (`WorkoutService` swallows) | **UNFIXED**, and now shown to have a *structural* cause at one of its sites — see H-01. | §5.3 |
| **EC-12** (habit writes optimistic + swallow + score from un-persisted state) | **UNFIXED** for genuine habits. Verified it does **not** compound H-08: for the fabricated habits `logHabit()` throws before the score call. | `habit_provider.dart:131-144` |
| **EC-13** (failed message read renders as empty conversation) | **UNFIXED**, and worse than recorded — see H-07. | §5.2 |
| **Coach rating written by the client** | **CLOSED by design** — a documented no-op behind migration 045's trigger and 115's PINNED class. Not a finding. | 115 header, lines 178-190 |
| **OBS-4 / migration 122 search-path regressions** | **CLOSED by Workstream A.** Not re-audited. | `QA_WORKSTREAM_A_OBS4_REPORT.md` |
| **K-04** (paid event ticket self-grantable) — P0, *landed during this run* | **OPEN, and confirmed adjacent to H-02.** Same table, different layer: K-04 is the RLS policy, H-02 is the column name. **Fix them in one change.** One correction to K-04's repro payload is recorded in H-02's Dependencies row. | `QA_WORKSTREAM_K_BILLING_ENTITLEMENT_REPORT.md:289` |

---

## 8. Environment blockers

Strictly separated from implementation defects, per the brief.

| # | Item | Class | Why it is *not* counted as a product defect |
|---|---|---|---|
| EB-1 | `supabase/tests/security/run.mjs` requires `QA_SERVICE` (a service-role key), which is not present in the working tree, and it creates and tears down four identities. | **Environment blocker** | Phase 1's regression suite; out of this workstream's scope and would have mutated QA. **Not run.** Reported as not run in §11. |
| EB-2 | QA holds no `pending` coach relationship, so the coach→pending-requester half of **H-06** could not be exercised live. | **Fixture blocker** | Creating one is a QA write. The policy predicate (`AND r.status = 'active'`) is unambiguous, so the finding stands on inspection and is labelled as such. |
| EB-3 | Edge Functions are not deployed to QA (Workstream C §8.3, D §3). | **Environment blocker** | Affects H-10's remediation sequencing only. No finding here depends on an Edge Function. |
| EB-4 | `apps/mobile/dart_defines/qa.json` has empty `STRIPE_PK` and `API_BASE_URL`. | **Environment blocker** | No finding in this report touches either. |

**Not** environment blockers, despite looking like them — the application itself
incorrectly assumes the infrastructure exists, which is the brief's stated test:

- **H-05** — migration 029 writes RLS *for* `progress-photos`; the sequence assumes a
  bucket it never creates. **Architectural gap → implementation defect.**
- **H-04** — `chat-media` is referenced by shipped UI and by passing widget tests, and
  created nowhere. **Architectural gap → implementation defect.**

---

## 9. Product decisions required (OWNER DECISION — nothing assumed)

| # | Question | Blocks | Why it cannot be decided here |
|---|---|---|---|
| **Q-H1** | What may a coach see about someone who has **requested** them but is not yet their client? Name only? Name + goal? Name + email? | The coach half of **H-06** | It is a privacy-policy call, not a technical one. `public_profiles` supplies name/avatar/role; `fitness_goal` and `email` would need a new scoped path. |
| **Q-H2** | Should a client with no coach-assigned habits get a **default starter habit set**? If yes, which habits, and seeded when? | **H-08** | The current eight are a demo fixture, not a product statement. Removing the fabricated streaks needs no decision; whether defaults exist at all does. |
| **Q-H3** | What is a challenge's **progress**, per `challenge_type`? Which deterministic source advances `current_progress`, and when? | The progress half of **H-09** | The bible forbids inventing a coaching rule. `challenges` carries both `type` and `challenge_type`, and both `unit` and `target_unit` — the vocabulary itself is unreconciled. |
| **Q-H4** | Which score is canonical — `score_events`/`user_scores` (server-authoritative) or `daily_scores` (client-written)? | **H-11** | Product bible §2.1 points hard at the former, but retiring `daily_scores` changes `/insights`, the Home Wellness Pulse and the coach leaderboard. Recommend: **A is canonical, B derived server-side.** |
| **Q-H5** | Should a coach who is not accepting clients be **hidden** from the marketplace or **shown as unavailable**? | Half of **H-12** | The `is_demo` half needs no decision — filter it. |
| **Q-H6** | Should the hard-coded sample workout library exist at all? If a demo library is wanted, must it be visibly labelled and non-loggable? | **H-14** | It is currently indistinguishable from a real program and fully loggable. |
| **Q-H7** | Which of the six notification preferences maps to which notification `type`? | The enforcement half of **H-10** | The columns and the `type` vocabulary were never reconciled. |
| **Q-H8** | Retire or wire: `/pods` (accountability pods) and `/coach-client-workouts`. | **H-16** | Both are built and unreachable; whether they are pre-beta scope is a roadmap call. |

---

## 10. Parallel remediation candidates

**Wave H-A — fully independent, no decision needed, no dependency on any other workstream.**
Each is a self-contained change; all five can proceed simultaneously.

| Finding | Change | Size |
|---|---|---|
| **H-01** | Three tokens in one method: `created_at` → `logged_at` | trivial |
| **H-03** | One migration adding `custom_exercises.approved_by` | trivial |
| **H-05** | One migration creating a **private** `progress-photos` bucket | trivial |
| **H-02** | `ticket_code` → `qr_code` at three sites + delete the fabricating `catch` | small |
| **H-06** (client half) | Repoint four reads at `public_profiles`, drop `email` | small |

**Wave H-B — independent, but each needs one owner answer first.**
H-08 (Q-H2) · H-12 (Q-H5) · H-14 (Q-H6) · H-09 tabs+names (Q-H3) · H-10 (Q-H7).

**Wave H-C — hand to the security workstream, not to product.**
H-19 (message tamper) and the RLS half of H-11 (`daily_scores` `FOR ALL`). Both are the
Phase 1 pattern and should be remediated with Phase 1's trigger/pin idiom, not by
application code.

**Wave H-D — sequenced, not parallel.**
H-07 → then the empty-state work in H-08/H-13 (one shared empty-state component).
H-01 → **before** Workstream B's EC-11, or EC-11 turns a silent empty chart into a
permanent visible error.
H-11 (Q-H4) → then H-15 falls out as cleanup.

**Cross-workstream sequencing.** H-10's enforcement belongs inside Workstream D's Wave 3
(the same `insert_notification()` / email producers). H-06's coach half should be decided
alongside Workstream E's Q-1, since both concern what a coach may see pre-relationship.

---

## 11. Tests executed and results

| Suite | Command | Result |
|---|---|---|
| Flutter — full suite, **before** this workstream's change | `flutter test` | **690 passed**, 9 skipped, 0 failed |
| Flutter — full suite, **after** | `flutter test` | **699 passed**, 9 skipped, 0 failed |
| Flutter — full suite, **re-measured at report close** | `flutter test` | **730 passed**, 9 skipped, 0 failed |
| Flutter — new guards in isolation (re-confirmed at close) | `flutter test test/unit/product_contract_guard_test.dart` | **9 passed** |
| API — unit | `npm test --workspace apps/api` | **58 passed**, 8 suites |
| API — e2e | `npm run test:e2e --workspace apps/api` | **6 passed**, 2 suites |
| Live security regression | `npm run test:security` | **NOT RUN** — requires `QA_SERVICE` (absent) and mutates QA. See EB-1. |

No existing test was deleted, weakened, skipped or modified. No untracked test file from
another workstream was touched.

**On the two mobile numbers:** 690 → 699 is this workstream's nine guards. 699 → 730 is
workstreams J/K/L/N landing 31 further tests in the shared tree during the run (§2). The
final measurement — **730 passing, 9 skipped, 0 failing** — is the state of the tree as
this report closes, with every workstream's tests in it. The guards were re-run in
isolation afterwards and still pass, so the concurrent arrivals neither broke nor
duplicated them.

**The nine new guards** (`H-G1`…`H-G4`) are static: they parse the committed source and
need no database, credentials or running app. Three of them are deliberately **shrinking
allowlists**, so closing a finding is a one-line deletion here rather than a test rewrite
— the same convention `error_contract_guard_test.dart` established.

| Guard | Asserts |
|---|---|
| **H-G1** (3 tests) | The migration parser produced a plausible schema (self-check, so a silently-parsing-nothing guard cannot pass forever); **no phantom column outside the recorded allowlist**; and each of the three recorded phantom columns is *still referenced and still missing*, so a stale allowlist entry fails too. |
| **H-G2** (2 tests) | `messages.metadata` specifically — H-G1's literal-map parser cannot see it because the row is built through a variable — and that `_sendPhoto` still ignores `sendMessage`'s boolean. |
| **H-G3** (1 test) | Every storage bucket the client uses is created by a migration, except `progress-photos` and `chat-media`. Asserts set equality, so a *newly created* bucket also fails until the allowlist is trimmed. |
| **H-G4** (3 tests) | Migration 102's policy text is the one this guard is about; the five recorded surfaces still read `user_profiles`; and no **new** coach-feature file starts reading it. |

The H-G1 parser was validated against a Python implementation of the same algorithm and
returns exactly three entries with zero false positives — PostgREST embedded-resource
syntax (`public_profiles!user_id(id, first_name)`), nested map payloads
(`'data': {'client_id': …}`) and ternary values (`x ? 'attended' : 'y'`) are all handled
explicitly rather than allowlisted away.

---

## 12. Files changed

**One file added. Nothing else in the repository was modified, moved or deleted.**

| File | Change | Why |
|---|---|---|
| `apps/mobile/test/unit/product_contract_guard_test.dart` | **new**, 9 tests | Characterization only. Establishes H-01…H-06 as facts about the current tree and prevents new instances of RC-H2 and RC-H3 from shipping silently. Changes no product behaviour. |
| `docs/QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md` | **new** | This report. |

No remediation was implemented. Per the brief, the only tree change is the minimum
test-only change needed to establish behaviour.

---

## 13. QA mutations and cleanup

**Reads and two logins. No row was created, updated or deleted; no schema object was
created, altered or dropped; no migration was applied; no Edge Function was deployed or
invoked.**

| Action | Count | Mutating? |
|---|---|---|
| Anonymous `GET /rest/v1/…` column-existence probes | 23 | No |
| Anonymous `GET /storage/v1/object/public/…` bucket probes | 5 | No |
| `POST /auth/v1/token?grant_type=password` as `test@12circle.app` | 2 | **Session only** |
| `POST /auth/v1/token?grant_type=password` as `coach@12circle.app` | 1 | **Session only** |
| Authenticated `GET /rest/v1/…` reads as those two identities | 10 | No |

**The three logins are the only side effect.** Each issued a GoTrue refresh token and
updated `last_sign_in_at` on the two **seeded fixture accounts** whose credentials are
published in `supabase/seeds/test_accounts.sql` — accounts that exist for exactly this
purpose. No access token was persisted outside this session's scratch directory, and the
tokens expire on their own (1 h access / GoTrue-default refresh).

**Cleanup:** the scratch directory holding the two tokens
(`…/scratchpad/{client,coach}_tok.txt`) is session-local, outside the repository, and is
discarded with the session. Nothing to revert in QA — there is no state to undo. If the
owner prefers, both fixture sessions can be revoked from the Supabase dashboard; nothing
in this report depends on them remaining valid.

---

## 14. Production-contact statement

**Production (`nxdbooufqzkpslkcogxc`) was not contacted in any way during this
workstream.**

- Every network request issued went to `https://eyqtldjqpgpljlqvpowh.supabase.co` — the
  QA project, and the only host that appears in any command run.
- The credentials used are QA's, read from `apps/mobile/dart_defines/qa.json` and
  `supabase/seeds/test_accounts.sql`. The production project ref appears in this
  repository only inside prior reports; it was never resolved, connected to, or supplied
  to any tool.
- `supabase/.temp/project-ref` is `eyqtldjqpgpljlqvpowh` and was not changed. No
  `supabase link`, `db push`, `db reset`, `functions deploy` or any other CLI command
  that could reach a remote project was run at any point.
- No migration was applied to any environment.

**Production's posture is unchanged by this workstream, and remains as prior reports
describe it: migrations 113–122 are not applied there.** That exposure is recorded, not
acted on, and is not this workstream's to close.

---

## 15. Recommended next phase

**Phase H-1 — "Stop fabricating" (RC-H1). The highest-value, lowest-risk work available.**

Four findings — H-07, H-08, H-13, H-14 — share one shape and one fix. Together they are
the only place in the audited surface where the product **asserts something false to the
user**: a coach conversation that never happened, streaks never earned, groups never
joined, a coach who does not exist. Every other finding in this report is a feature that
does not work; these are features that lie about working, and they are the ones a beta
coach will notice first and trust least. The fix is deletion plus one shared empty-state
component, it touches no schema, no policy and no engine, and it is directly mandated by
the product bible's own §4 and §6.

Sequence it as:

1. **H-1a — Wave H-A first (one afternoon, no decisions).** H-01, H-02, H-03, H-05, and
   the client half of H-06. Five isolated changes that turn five dead features back on.
   Run `flutter test` and trim the H-G1/H-G3/H-G4 allowlists as each lands — the guards
   are written so that a stale entry fails, which makes "did we actually fix it?"
   answerable by the test suite rather than by re-reading this document.
2. **H-1b — put Q-H2, Q-H4, Q-H6 in front of the owner** (defaults, canonical score, demo
   library). These three gate the largest remaining findings; the other five questions can
   wait.
3. **H-1c — the fabrication sweep** once Q-H2 and Q-H6 are answered.
4. **H-1d — hand Wave H-C to a security workstream.** H-19 and the `daily_scores`
   `FOR ALL` are Phase 1's pattern and should be fixed with Phase 1's idiom.

**Explicitly not recommended as the next phase:** Workstream B's error-contract
remediation. It is the right work, but H-01's dependency runs the wrong way — closing
EC-11's swallows before H-01, H-02 and EC-10 converts silent empty states into permanent
visible errors across the workout, event and check-in surfaces at once. Land Wave H-A
first; then B's Phase B0/B1 has clean ground.

---

## Executive summary

I audited the whole product surface outside the closed Phase 1 (security) and Phase 2
(workout contract) clusters, and found **21 findings: 0 new P0, 5 P1, 6 P2, 10 P3**, plus
one factual correction to a prior report and ten verified-good behaviours worth pinning.
Four structural sweeps (columns, RPC parameters, storage buckets, route reachability) that
no prior workstream had run account for most of what is new; nine of the findings were
confirmed **live on QA read-only**, using PostgREST's column-resolution order and
Storage's bucket-vs-key error as non-mutating existence oracles.

The five P1s are: event registration writes a column that does not exist and then
**fabricates a ticket** (H-02); an admin can reject but **never approve** a submitted
exercise (H-03); the `progress-photos` bucket is created by **no migration and does not
exist on QA**, so all progress and onboarding photography fails (H-05); migration 102
closed the client→coach profile read and **four client surfaces plus the coach's
incoming-request list were never repointed**, so a paying client is shown a product that
behaves as if they have no coach and a coach must accept requests from an anonymous "New
Client" (H-06, verified live); and two demo fallbacks that present **invented data as the
user's own** — four fabricated coach messages including training advice (H-07) and eight
fabricated habits with invented multi-day streaks that the app then schedules device
reminders for (H-08).

Everything reduces to five root causes, of which one dominates: **a demo seed used at
runtime whenever the real answer is legitimately "nothing yet."** That single pattern
produces four of the findings and is the only place the product tells the user something
untrue. The second cause — **four columns the client names that no migration creates,
every one swallowed into an empty or success-shaped answer** — is Workstream B's phantom-
*table* finding one level down, and it went unfound because B's guard checks table names
only.

I implemented **no remediation**. The only change to the tree is one new test file with
nine static guards that lock these facts in place and make any *new* phantom column,
phantom bucket, or new coach-profile read fail `flutter test` immediately. Three of the
guards are shrinking allowlists, so closing a finding is a one-line deletion. Full suite:
**730 mobile tests passing, zero failures** (690 before my change, 699 after it, then 730
as workstreams J/K/L/N landed 31 more tests in this shared tree during the run), **64 API
tests passing**, no existing test touched. **Production was not contacted.** QA received
reads and three logins to seeded fixture accounts; no row, schema object or migration was
changed.

One cross-workstream note: **K-04 (P0, landed during this run) and my H-02 are the same
table at different layers** — K-04 is the missing `WITH CHECK` that lets a user self-grant
a paid ticket, H-02 is the column name that makes free registration fabricate one. Fix
them together, and drop `ticket_code` from K-04's published repro payload (it makes that
request fail rather than succeed).

### Exact next actions

1. **Owner:** answer **Q-H2** (should default habits exist?), **Q-H4** (which score is
   canonical?) and **Q-H6** (should the demo workout library exist?). These three gate the
   largest remaining work; the other five questions in §9 can wait.
2. **Engineering, immediately and in parallel — Wave H-A, §10.** H-01 (`created_at` →
   `logged_at`), H-02 (`ticket_code` → `qr_code`, delete the fabricating `catch`) —
   **paired with Workstream K-04's policy fix on the same table** — H-03 (add
   `custom_exercises.approved_by`), H-05 (one migration creating a **private**
   `progress-photos` bucket), H-06 client half (repoint four reads at `public_profiles`,
   drop `email`). Trim the corresponding H-G allowlist entry as each lands.
3. **Do not** start Workstream B's EC-11 swallow remediation before step 2 — the
   dependency runs the wrong way (§15).
4. **Route H-19 and the `daily_scores` `FOR ALL` policy to a security workstream**, to be
   fixed with Phase 1's trigger/pin idiom rather than as application code.
5. **Do not create `chat-media` or `progress-photos` as public buckets.** Both hold body
   photography. H-04 and H-05 flag this explicitly.
