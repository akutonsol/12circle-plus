# 12Circle Plus — Beta Completion Ledger

The single running ledger for the core-beta completion mission. **Read this first after a
context reset; continue from "Next autonomous action".** Every status here cites its
evidence. Nothing is marked complete without it.

## Snapshot (update at every milestone)

| | |
|---|---|
| `origin/main` | `8f2c8a0` (PR #159), CI run `43792727007` **7/7 success** |
| Live QA evidence on main | security **1173/1173**, AI **51/51**, ENV-3 L-1..L-5 PASS (ledger 188 rows; frontier 192; 182–186 declared excluded) |
| Open PRs | #14 (owner's, untouched) · #160 · #161 · three more queued (see below) — **none of this mission's PRs are to be merged without explicit authorization** |
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
| 4 — Beta validation | Not started |

## Module inventory

Statuses: **CV** complete & verified (live evidence) · **INT** implemented, not
integration-tested · **PART** partially implemented · **MISS** missing · **DEC** blocked by
Julia's decision · **MIG** blocked by migration approval · **EXT** blocked by external
deployment/configuration · **MQA** needs manual QA.

| # | Module | Status | Evidence / what remains |
|---|---|---|---|
| 1 | Auth & account creation | INT · MQA | Email sign-up/login/reset routes exist; QA requires email confirmation (memory: client first-day audit). No live sign-up test in CI (fixtures are pre-made). |
| 2 | Client onboarding (intake) | INT · MQA | EC-03 intake false-completion guard in CI negative control. |
| 3 | Coach onboarding | INT · MQA | Coach profile/packages screens; no live coach-signup leg. |
| 4 | Relationships | INT · MIG · DEC | Request/approve paths and decision 1 (data sharing only) in 193 — **pending**. Coach can reactivate a client-cancelled relationship via API (needs migration + decision). |
| 5 | Membership & entitlements | INT · MIG | `client_plan()` + `PaywallGate`; decision 1 needs 193 applied. AI server enforcement → #160. |
| 6 | Payments & subscriptions | **EXT** | Code: checkout, webhook (idempotent grant), cancel-at-period-end (#149). **QA has no Stripe keys, no webhook secret, no deployed Stripe functions.** Cannot be exercised. |
| 7 | Coach dashboard | INT | Many truth/refresh fixes merged (#92–#152). |
| 8 | Client dashboard (Home) | INT | Today card, weekly bars (#151). |
| 9 | Program Builder & assignment | INT · MIG | Assignment self-grant hole → **196**; coach write arms need **185** (182–186 batch). |
| 10 | Workout execution & history | **CV** (core path) | I-WRK-01 live leg on QA fixture every CI run. Units fixed (#157/#158). |
| 11 | Exercise library | INT | A-Z + failed-read notice (#153). Content ~22/623 complete (beta-readiness §1) — **content gate**. |
| 12 | Nutrition & meals | INT · EXT | Logging + targets; AI meal plan needs `ai-nutrition` (deployed, older build); food-photo analysis (`analyze-food-image`) **not deployed**. |
| 13 | Habits | INT | Coach-assigned habits; live refresh fixed earlier. |
| 14 | Check-ins | INT · DEC | Weekly loop works; resubmission after review (PD8/E-CHK-09) undecided. |
| 15 | Progress measurements | INT | Ordering/latest fixes merged. |
| 16 | Scoring & achievements | INT · risk | Leaderboards follow changes (#147). **`daily_scores` is client-writable (own rows)** — points can be self-set; server-side scoring is a design decision. |
| 17 | Challenges & community | INT · risk | `challenge_participants` own rows client-writable (progress self-set). |
| 18 | Booking & scheduling | **CV** (screen) · MIG · DEC | UIX-1 end-to-end leg live. Entitlement needs **195**. Credits never consumed (K-05) and coach can rewrite balance/owner (K-25) — needs migration + "which bookings consume a credit". |
| 19 | Classes & events | INT | Seat integrity (188) applied; registration integrity trigger live. |
| 20 | Messaging | INT · DEC | Coach-messaging server enforcement (B) and chat times/order undecided. |
| 21 | Notifications | PART · EXT | In-app table + realtime; **push not configured** (no APNs/FCM); email reminders/invites need an email provider + deployed functions. |
| 22 | AI coaching | **EXT** · #160 | Only `ai-nutrition` deployed on QA; `ai-coach`, `ai-coaching-engine`, `ai-generate-workout`, `analyze-food-image` not deployed; vault empty so cron skips. Server plan gate → #160. `ai-generate-workout` tier → DEC. |
| 23 | Profile & settings | INT | Unit preference now drives load display (#157/#158). |
| 24 | Admin & ops tools | INT | `/qa-center`, `/mie-debugger` excluded from release routes (release_route_gate_test). |

## Completed in this mission

| PR / branch | What | Evidence | Status |
|---|---|---|---|
| #160 `fix/ai-functions-check-the-plan` | AI functions refuse callers the app's paywall refuses (K-03): `ai-coach`, `ai-coaching-engine` ≥ AI-Guided; `ai-nutrition`, `analyze-food-image` ≥ Self-Guided; coaches pass | node test 11/11; 4 of 11 fail on main's sources; CI 7/7 (`43794773571`) | open — **not deployed** |
| #161 `fix/clients-cannot-self-assign-programs` | Migration 196: a client cannot assign itself another coach's program (that row unlocked reading the program) | replay 3 FAIL → 8/8, also on QA's shape | open — **not applied** |
| `fix/ending-coaching-refreshes-the-plan` | Profile's Cancel Coach re-reads the plan — coaching features no longer stay unlocked | widget test fails on main; suite 2685 | PR queued |
| `fix/coach-dashboard-follows-workouts-and-checkins` | Open coach dashboard shows a client's finished workout / new check-in (realtime) | 2 FAIL on main → 3/3; suite 2686 | PR queued |
| `docs/beta-completion-ledger` | This ledger | — | PR queued |

## Migration readiness, 182–196

Live ledger (ENV-3, run `43792727007`): QA applied through **192**; 182–186 **excluded**
(declared, gated); 193–196 **pending**. Each was replay-verified locally; none is on QA.

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

## Subscription lifecycle (code trace; nothing exercisable on QA)

| Stage | Code path | State |
|---|---|---|
| New subscription / checkout | `create-checkout` (409 `already_subscribed` guard) → `checkout.session.completed` | implemented; idempotent grants (conflict targets); **not deployed on QA** |
| Signature validation | `constructEventAsync` before any DB access; 400 on a bad signature | implemented |
| Upgrade / downgrade | `update-subscription` → `customer.subscription.updated` | implemented |
| Renewal | `customer.subscription.updated` moves the period | state follows; **`invoice.paid` not handled → renewals never reach `payments`** (coach revenue under-counts) |
| Payment failure | Stripe sets `past_due` → `subscription.updated` | status stored; **`invoice.payment_failed` not handled** (Gate 4.9); grace period is a policy question |
| Cancel at period end | `cancel-subscription` sets `cancel_at_period_end` (decision 2, #149) | implemented; **not deployed** |
| Expiration | `customer.subscription.deleted` ends a coaching relationship (`cancelled_by 'billing'`) | implemented |
| Refund | — | **not handled** (`charge.refunded`); whether a refund revokes access is a decision |
| Duplicate prevention | 409 guard in checkout/update; webhook `.neq('status','canceled')` | implemented |

Blocked on: a QA Stripe **test-mode** account, keys, webhook secret, price ids, and function
deployment. Validation script once those exist: checkout → webhook grant → renewal → failed
renewal → cancel at period end → expiry, each read back from `subscriptions` and
`client_plan()`.

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
- Content: ~22 of 623 exercises complete — the beta-readiness "real gate".

## Next autonomous action

Phase 3: client/coach journey audit for decision-free defects (cross-sync, false
success, dead ends), one focused PR each; update this ledger after each.
