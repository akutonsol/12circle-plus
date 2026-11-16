# 12Circle Plus — Beta Completion Ledger

The single running ledger for the core-beta completion mission. **Read this first after a
context reset; continue from "Next autonomous action".** Every status here cites its
evidence. Nothing is marked complete without it.

## Snapshot (update at every milestone)

| | |
|---|---|
| `origin/main` | `8f2c8a0` (PR #159), CI run `43792727007` **7/7 success** |
| Live QA evidence on main | security **1173/1173**, AI **51/51**, ENV-3 L-1..L-5 PASS (ledger 188 rows; frontier 192; 182–186 declared excluded) |
| Open PRs | #14 (owner's, untouched) · #160–#166, each CI 7/7 on its exact head — **none of this mission's PRs are to be merged without explicit authorization** |
| QA migrations | applied through **192** (182–186 excluded). **Pending, not applied:** 193, 194, 195, 196 |
| QA Edge Functions | **1 of 19 deployed** (`ai-nutrition` v18, deployed ~2026-09-30 from the pre-rename path) |
| QA function secrets | `ANTHROPIC_API_KEY` + Supabase defaults only. **No Stripe, no email provider, no `APP_URL`, no YouTube** |
| QA vault | **empty** — the three AI cron jobs run hourly/daily and skip (`service_role_key` / `project_url` not set) |
| Vercel | **not used by this repository** — no `vercel.json` or Vercel config is tracked; the Vercel connector is unauthenticated here. Nothing to audit. |

## Phase status

| Phase | Status |
|---|---|
| 0 — Reconciliation & audit | **Done** for repo/CI/infra; module inventory below |
| 1 — Database & authorization | #160 (AI plan gate), #161 (196 assignment self-grant); K-05/K-25 recorded (need decision 5 + migration) |
| 2 — Payments, entitlements, AI | Payments **blocked** (no Stripe config on QA); AI entitlements → #160 |
| 3 — Client & coach experience | Prior cycles #92–#159 merged; this mission: plan refresh after ending coaching, live coach dashboard; continuing |
| 4 — Beta validation | CI-level validation on every PR head; build/distribution readiness recorded below; manual QA and payments blocked |

## Module inventory and integration coverage (2026-11-16)

Columns: **Impl** implemented in code · **Unit** unit/widget tests · **Int** integration
test against a real backend (local replay or live QA) · **Live** exercised live in CI
against QA · **Man** manually verified · **Block** what stops it (EXT external config ·
DEC Julia · MIG migration approval). "—" = none exists. Historical statuses from earlier
reports are superseded by this table.

| # | Module | Impl | Unit | Int | Live | Man | Block |
|---|---|---|---|---|---|---|---|
| 1 | Auth & account creation | yes | yes | — | fixtures only (pre-made identities) | — | EXT (email provider; native deep links) |
| 2 | Client onboarding (intake) | yes | yes (EC-03 negative control) | — | — | — | — |
| 3 | Coach onboarding | yes | partial | — | — | — | — |
| 4 | Relationships | yes | yes | replay (193/194) | security suite (boundaries) | — | MIG 193/194; DEC 3, 4 |
| 5 | Membership & entitlements | yes | yes | replay (193/195) | security suite | — | MIG 193/195; EXT deploy #160 |
| 6 | Payments & subscriptions | yes | source-shape + node (#165) | — | — | — | EXT Stripe test mode + deploy |
| 7 | Coach dashboard | yes | yes (#163) | — | — | — | — |
| 8 | Client dashboard (Home) | yes | yes | — | — | — | — |
| 9 | Program Builder & assignment | yes | yes | replay (196, 185) | — | — | MIG 196, 185 |
| 10 | Workout execution & history | yes | yes | — | **I-WRK-01 every CI run** | — | — |
| 11 | Exercise library | yes | yes | — | — | — | content (see below) |
| 12 | Nutrition & meals | yes | yes | — | — | — | EXT (`analyze-food-image` not deployed) |
| 13 | Habits | yes | yes | — | — | — | — |
| 14 | Check-ins | yes | yes | — | — | — | DEC 6 |
| 15 | Progress | yes | yes | — | — | — | — |
| 16 | Scoring & achievements | yes | yes | — | — | — | DEC 9 (client-written points) |
| 17 | Challenges & community | yes | yes | — | — | — | DEC 9 |
| 18 | Booking & scheduling | yes | yes | replay (187/195) | **UIX-1 end-to-end leg** | — | MIG 195; DEC 5 (credits) |
| 19 | Classes & events | yes | yes | replay (188) | security suite (registration integrity) | — | — |
| 20 | Messaging | yes | yes | — | security suite (message text integrity) | — | DEC 2, 7 |
| 21 | Notifications | partial (in-app) | yes | — | — | — | EXT push + email |
| 22 | AI coaching | yes | node (#160) | — | AI suite (decision integrity, 51) | — | EXT deploy + vault; DEC 1 |
| 23 | Profile & settings | yes | yes (#157/#158/#162) | — | — | — | — |
| 24 | Admin & ops | yes | yes (release-route gate) | — | security suite (admin matrix) | — | — |

**Not one module is manually verified**: Julia's week-1 walkthrough has not run. No module is
beta-ready on this evidence alone.

### Journey gaps found (2026-11-16)

| Journey | Gap | Status |
|---|---|---|
| Program creation → assignment → execution | Assigned movements showed no form/steps: program rows carry no description, instructions or library id | **fixed** for library-covered names → #166 (`fix/workout-brief-uses-the-library`); linking programs to library ids is open |
| Client activation → termination | Ending coaching from Profile left coaching features unlocked | **fixed** → #162 |
| Workout completion / check-in → coach | Open coach dashboard did not update | **fixed** → #163 |
| Coach invitation → acceptance | needs 194 applied + email provider + deployed `send-invite-email` | MIG + EXT |
| Subscription purchase → cancellation | no Stripe on QA; functions not deployed | EXT |
| AI coaching / AI workout | functions not deployed; AI workout tier undecided | EXT + DEC 1 |

## Completed in this mission

| PR / branch | What | Evidence | Status |
|---|---|---|---|
| #160 `fix/ai-functions-check-the-plan` | AI functions refuse callers the app's paywall refuses (K-03): `ai-coach`, `ai-coaching-engine` ≥ AI-Guided; `ai-nutrition`, `analyze-food-image` ≥ Self-Guided; coaches pass | node test 11/11; 4 of 11 fail on main's sources; CI 7/7 (`43794773571`) | open — **not deployed** |
| #161 `fix/clients-cannot-self-assign-programs` | Migration 196: a client cannot assign itself another coach's program (that row unlocked reading the program) | replay 3 FAIL → 8/8, also on QA's shape; CI 7/7 (`43795976485`) | open — **not applied** |
| #162 `fix/ending-coaching-refreshes-the-plan` | Profile's Cancel Coach re-reads the plan — coaching features no longer stay unlocked | widget test fails on main; suite 2685; CI 7/7 (`43798002991`) | open |
| #163 `fix/coach-dashboard-follows-workouts-and-checkins` | Open coach dashboard shows a client's finished workout / new check-in (realtime) | 2 FAIL on main → 3/3; suite 2686; CI 7/7 (`43798857589`) | open |
| #164 `docs/beta-completion-ledger` | This ledger | CI 7/7 (`43877270117` at `25acfc7`) | open |
| #165 `fix/webhook-reads-current-subscription` @ `3fa490a` | Webhook writes the subscription as Stripe holds it now — a late `updated` event can no longer restore access after `past_due` | node test 4/4 (wiring case fails on main); Flutter webhook source tests 55; CI 7/7 (`43880220835`) | open |
| #166 `fix/workout-brief-uses-the-library` @ `6b172df` | An assigned movement's brief shows the built-in library's form and steps (exact normalised name match) | 2 FAIL on main → 7/7; suite 2690; CI 7/7 (`43881848146`) | open |

## Migration readiness, 182–196

Live ledger (ENV-3, run `43792727007`): QA applied through **192**; 182–186 **excluded**
(declared, gated); 193–196 **pending**. Each was replay-verified locally; none is on QA.
**Production:** `expected_applied.json` declares no production environment, and production is
off-limits to inspection under the standing rules — its state is **undeclared**. Earlier records
say production never received the P0 security fixes; treat production as unpatched until
someone with authority declares it.

| # | Purpose | Objects | Security effect | Order / deps | Data impact | Reversible | Proof |
|---|---|---|---|---|---|---|---|
| 182 | Exercise-certification view stops showing another coach's private drafts | view `exercise_certifications`, RPC | closes a read leak (QAX-SEC-06) | route A: 182→183→184→185→186, one push | none | redefine view | local replay |
| 183 | Restores the engine's empty-selection guard | `materialize_program_week_engine` | integrity | route A | none | redefine fn | local replay |
| 184 | `assign_nutrition_plan` requires an active relationship | definer fn | closes any-user plan takeover (QAX-SEC-01, P0) | route A | none | redefine fn | `od_qax2_od14_replay` |
| 185 | Coach write arms on 6 tables require an active relationship | 6 policies (ALTER) | closes coach→stranger writes (QAX-SEC-03) | route A | none; old rows stay readable | ALTER back | 47/47 replay; D24 live suite gated |
| 186 | Engine produces complete canonical days or fails | engine fns | integrity | **last** of route A | none | redefine fns | local replay |
| 187–192 | slots, seats, comms, PRs, realtime, price/source | — | — | — | — | — | **applied** 2026-11-15 |
| 193 | Paid access is not self-granted (`activated_by`; `client_plan()` ignores client-activated rows) | column + trigger + fn | decision 1 | before 195 | pre-193 active rows keep access (flagged) | drop column/trigger, restore fn | `policy_193_194` 21/21 |
| 194 | `accept_coach_invite(token)` + verified-email source | definer fn + trigger fn | decision 4; closes 0% commission spoof | after 193 | consumes invites when used | drop fn, restore trigger fn | same replay |
| 195 | A client books a coach only with Coach-Guided access to them | fn + trigger | decision 1 at the bookings write | after 193 | none (inserts only) | drop trigger/fn | same replay; `integrity_187_192` 34/34 |
| 196 | A client cannot assign itself another coach's program | 2 restrictive policies | closes program-content read | independent; composes with 185 | none | drop 2 policies | `assignment_196` 8/8 (also QA shape) |

**Safe application plan (needs Julia's approval of the exact batch and window):**
1. Window A — 193, 194, 195 in order, then 196 (or 196 alone first: it is independent).
2. Per migration: dry-run in a rolled-back transaction, apply with its ledger row in the
   same transaction, move `applied_through`/`pending` in `expected_applied.json` in the same
   PR, then one CI run (live suites + ENV-3).
3. Route A (182–186) stays separately gated and is applied only as its own ordered push.

## Subscription lifecycle (code trace, 2026-11-16; nothing exercisable on QA)

**Correction to the 2026-11-15 entry:** subscriptions never write `payments` rows — not at
checkout either. Coach revenue reads subscription income from `subscriptions.coach_payout`
(active/trialing) and one-time income from `payments`; so unhandled renewals do **not**
under-count revenue. What is missing is a per-charge history for subscriptions (Gate 4.9).

| Stage | Implemented | Tested | Missing |
|---|---|---|---|
| Checkout initiation | `create-checkout`; 409 `already_subscribed` guard | source-shape | live test (EXT) |
| Subscription creation | `checkout.session.completed` retrieves the subscription, upserts on `stripe_subscription_id` | source-shape | — |
| Signature verification | `constructEventAsync` before any DB access; 400 otherwise | source-shape | — |
| Initial payment | subscription row status from Stripe; one-time kinds mark `payments` paid | source-shape | — |
| Renewal | `customer.subscription.updated` moves the period | node (#165) | per-charge record (`invoice.paid`) |
| Failed renewal | Stripe sets `past_due` → `updated` stores it | node (#165) | `invoice.payment_failed` notice; **grace period = DEC 11** |
| Cancellation | `cancel-subscription` → `cancel_at_period_end` (decision 2) | unit | live |
| Refund | — | — | `charge.refunded` not handled; **revoke or not = DEC 11** |
| Expiration | `deleted` → `canceled` + `canceled_at`; coaching relationship ends | source-shape | — |
| Entitlement revocation | `client_plan()` reads live subscriptions; relationship ends on `deleted` | replay (193) | live |
| Duplicate events | every grant has a conflict target; credits `ignoreDuplicates` | source-shape | — |
| Out-of-order events | `canceled` terminal (K-23); **all other statuses now read current (#165)** | node (#165) | — |

**Stripe test-mode validation: NOT performed** — QA has no Stripe configuration. No claim of
test-mode evidence is made anywhere in this ledger.

## Build and distribution readiness

| Item | State | Evidence |
|---|---|---|
| QA web build | **verified automatically** on every CI run: build, credential scan, "names no project other than QA" | CI `flutter` job |
| Hosting / deployment pipeline | **none** — no deploy workflow, no Vercel/Netlify/Firebase/Cloudflare config; the QA web bundle exists only as a CI build | `.github/workflows` = `ci.yml`, `supabase-keepalive.yml` |
| Android | `applicationId com.twelvecircle.circle_fitness`; **release is signed with the debug key** | `android/app/build.gradle.kts` |
| iOS | bundle `com.twelvecircle.circleFitness`; **no development team set** | `project.pbxproj` |
| Deep links | **none on iOS/Android** (no URL types, no intent-filter hosts); password-recovery redirect is web-only, so native recovery/confirmation links open the web app | `auth_service.dart:50`, `forgot_password_screen.dart:39` |
| Push notifications | **not configured** (no Firebase/APNs packages or config) | `pubspec.yaml` |
| Environments | `dart_defines/{dev,qa,prod}.json`; ENV-4/ENV-5 guards keep production out of defaults | static guards |

**Which platforms the controlled beta runs on (web only, or TestFlight/Play internal) is a
decision for Julia**; each native platform then needs signing, deep links and push.

## Exercise content readiness (measured on QA, read-only, 2026-11-16)

Two libraries exist:

| Library | Size | Complete content | Media | Notes |
|---|---|---|---|---|
| Database (`custom_exercises`, global, approved) | **621** | **20** have description + instructions + cues + mistakes (`content_status` published 20 / draft 601) | **0** images, **0** videos | all 621 have category, muscle group, equipment, difficulty, movement pattern; **0** human-reviewed; **no duplicate names** |
| Built-in (bundled in the app) | **46** | description, instructions, cues, mistakes | image assets; video = YouTube *search* links, not videos | what the Exercise Library screen shows clients |

The certification view (`exercise_certifications`) rates **20** ready for the workout builder
and library, **0** for self-guided and **0** for AI coach (average completeness 1%). The old
"~22/623" figure was close but stale.

**What "complete" means here** (the certification view's own checks): instructions, cues,
mistakes, alternatives, beginner and advanced variants, image, video, muscle, equipment.

**Program ↔ library is not linked.** Program rows name movements in free text; of the 25
most-used movement names in programs and logged sets, about half match no library name
exactly ("Push Up", "Bench Press", "Bent-Over Row"). #166 bridges exact normalised matches to
the built-in library; it does not invent matches.

**Content plan (no content is fabricated — every item needs a human source):**
1. Priority set: the movements programs actually use (top 25 by use above) plus the bundled 46.
2. Reconcile names: map each program name to one library entry (a reviewed table, not fuzzy
   matching); then programs can carry a library id.
3. Complete text for the priority set from a reviewed source (coach-authored, or AI-drafted
   then human-reviewed via the existing Knowledge Review queue), batch of 25 with
   `human_reviewed` set only after review.
4. Media: decide the source hierarchy (coach demo > licensed > none) — **DEC**; no automated
   source is wired.
5. Batches are safe as content-only updates (no schema change), but they are **QA writes** and
   need approval; the existing enrichment pipeline needs `enrich-*` functions deployed.

## Infrastructure setup checklist (nothing here was changed)

| Item | Current state (QA) | To do (owner/admin) |
|---|---|---|
| Edge Functions | 1 of 19 deployed (`ai-nutrition`, older build) | deploy all 19 from `main` after the open PRs are decided; check `verify_jwt` per `config.toml` |
| Stripe test configuration | none | test-mode account; `STRIPE_SECRET_KEY` (sk_test_…); five price ids |
| Webhook | none | endpoint `https://<qa-ref>.supabase.co/functions/v1/stripe-webhook`, its own `STRIPE_WEBHOOK_SECRET`; events: checkout.session.completed, customer.subscription.updated, customer.subscription.deleted |
| Email provider | none | provider key + verified sender domain; templates for invite, reminder, auth |
| `APP_URL` | not set | the hosted QA web URL (invite and redirect links) |
| QA vault | empty | `project_url` (QA ref) and `service_role_key` — then the three AI cron jobs run |
| Web hosting | none | choose host; build `--dart-define-from-file=dart_defines/qa.json`; add the URL to Supabase Auth redirect allow-list |
| Android signing | release uses the debug key | upload keystore + `key.properties` (kept out of git) |
| iOS signing | no development team | Apple team id, bundle `com.twelvecircle.circleFitness`, provisioning |
| Deep links | none on iOS/Android | URL scheme or universal/app links for auth recovery, confirmation and `?invite=` |
| Push notifications | none | FCM/APNs keys + device-token storage — product scope decision |

Secrets are never printed; names only.

## Decision briefs (alternatives · consequences · recommendation)

These are Julia's calls; the recommendation is engineering's view, not a decision.

| # | Question | A | B | Recommended |
|---|---|---|---|---|
| 5 | Session credits: which bookings consume one? (K-05/K-25) | **Package clients only** — a booking with a coach the client holds an unexhausted credit block with consumes one, atomically, refused at zero; subscription clients book freely | **Every booking** consumes a credit; subscriptions grant a monthly block | **A** — matches how packages are sold (sessions) vs subscriptions (ongoing coaching); smallest change: one `book_coaching_session()` RPC + dropping the coach UPDATE policy on credits |
| 9 | Points and challenge progress are client-written | **Accept for beta** (closed cohort; leaderboard is low stakes) and label scores as self-reported | **Server-side scoring**: triggers derive points from workout/check-in/nutrition rows; clients lose write access to `daily_scores`/`challenge_participants` progress | **A for the closed beta, B before any public leaderboard or prize** |
| 1 | AI workout generation tier | Keep it open to **every plan** (the button is on the ungated list today) | Gate at **AI-Guided** as `canGenerateProgram` says | **B** if AI cost matters for the beta; it is one line in the app + one in `plan_gate` |
| 4 | Coach reactivates a client-cancelled relationship | Allow (coach can win a client back) | Refuse: only the client may reactivate what the client cancelled | **B** — a cancelled client should not be re-billed or re-shared without consent |
| 11 | Payment failure / refund | Grace: keep access while `past_due` (Stripe retries) | No grace: `past_due` loses paid features at once | **Grace** while Stripe retries; **refund revokes** the refunded period |
| 3 | Relationships activated before 193 | Keep access (current flag) | Re-confirm each (coach approves again) | **Keep** — small QA population; production undecided anyway |

## Decisions required (Julia)

1. `ai-generate-workout` tier — the button is on the ungated `/workouts` (every plan) while `canGenerateProgram` says AI-Guided.
2. Coach messaging: which conversations are paid "Coach Messaging" (server enforcement).
3. Relationships activated before 193: keep access (flagged default) or not.
4. Can a coach reactivate a relationship the client cancelled?
5. Which bookings consume a session credit (package clients? subscription clients?) — unblocks K-05/K-25.
6. Check-in resubmission after review (PD8 / E-CHK-09; option A recommended).
7. Chat times/order; coach-facing load units.
8. Coach-to-coach program sharing (196 leaves it open).
9. Scores/challenge progress are client-written — accept for beta, or move scoring server-side.
10. Rollback strategy (PITR vs forward-only, PD-A26).
11. Payment failure grace period, and whether a refund revokes access.
12. Beta platforms (web only vs TestFlight / Play internal) and where the web app is hosted.
13. Exercise media source hierarchy, and approval for content batches (QA writes).

## Migration approvals required

| Batch | Contents | Gate |
|---|---|---|
| 193–195 | decisions 1 & 4; bookings need Coach-Guided | owner-approved QA window (193 before 195) |
| 196 | assignment self-grant | owner-approved QA window naming 196 |
| 182–186 | exercise cert scoping, engine guards, nutrition/coach write arms (185) | separate authorization; gates unchanged |

## External deployment / configuration required

- Deploy Edge Functions to QA (18 of 19 missing), after #160 if approved.
- QA Stripe **test-mode** account: secret key, webhook endpoint + signing secret, price ids. Confirm test mode at the source (Julia).
- Email provider + verified sender; `APP_URL`.
- QA vault: `project_url` (QA ref) and `service_role_key` so AI cron runs.
- Push notifications (APNs/FCM) and build signing for device distribution.

## Manual QA required

Julia's week-1 walkthrough (`docs/BETA_WEEK1_MANUAL_WALKTHROUGH.md`); sign-up with email
confirmation; coach invite acceptance (after 194 + email); payments once Stripe test mode
exists.

## Known risks

- Points and challenge progress are client-writable (leaderboard gaming).
- A coach can assign another coach's program to their client and read it (196 leaves open).
- QA's only deployed function was built from an older tree; QA's AI nutrition is not main's.
- Content: 20 of 621 database exercises complete, 0 with media; programs not linked to the library.

## Next autonomous action

Phase 3: client/coach journey audit for decision-free defects (cross-sync, false
success, dead ends), one focused PR each; update this ledger after each.
