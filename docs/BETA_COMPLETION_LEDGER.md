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
| Vercel | **no project for this repository** (verified 2026-11-16 via the Vercel connector, read-only): the one team holds `12circle-fitness-staging`, a **Next.js** project belonging to the separate 12 Circle Fitness product, not this Flutter app; no `vercel.json` is tracked here. Web hosting for 12circle-plus remains to be chosen (DEC 12). |

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

## Migration readiness, 182–200

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
| 197 | A coach assigns only a program it owns | 2 restrictive policies | closes coach→other coach's program read (O2) and unrelated-coach assignment (O6) | after 196; composes with 185 | none (existing rows untouched) | drop 2 policies | `assignment_196` 10/10 (also QA shape); ownership matrix |
| 198 | Session credits not coach-writable; balance in range | drop 1 policy; CHECK NOT VALID | closes K-25 (Gate 4.8) | independent | none (QA has 0 credit rows) | recreate policy (028); drop constraint | `credits_198` 8/8 (4 FAIL before) |
| 199 | Storage writes need ownership (exercise-media, coach-media); RPC respects private ownership | 8 storage policies, 2 helpers, 1 function | closes public-media tampering and coach-video listing | independent | none (QA: 0 exercise-media objects) | recreate 061/036 policies; restore 072 body | `storage_199` 29/29 (14 FAIL before), also QA shape |

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
| Built-in (bundled in the app) | **46** | description, instructions, cues, mistakes, alternatives, beginner/advanced variants | **6** image assets (corrected 2026-11-16; earlier said all 46); video = YouTube *search* links, not videos | what the Exercise Library screen shows clients |

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

## Round 2 (2026-11-16): review, ownership, credits, Stripe, security

### PR review findings

| PR | Finding | Action |
|---|---|---|
| #160 | correct; refusals carry CORS; coach exemption cannot be self-granted (d02); cron path exempt | none — deploy dependency |
| #161 | **did not close program ownership**: a coach could assign another coach's private program and read it (matrix O2) | **197 added to #161** (`029e613`) |
| #162 | safe after the sheet closes (container captured before awaits) | none |
| #163 | `workout_sessions` changes only at start/finish/abandon — no load concern | none |
| #164 | docs | this update |
| #165 | covers all subscription-object orderings (`updated` before checkout → harmless no-op, checkout retrieves; `deleted` before checkout → checkout writes canceled, no activation; `updated` after `deleted` → guard + retrieve). Invoice/refund events are not handled (below) | none |
| #166 | exact normalised match only; coach text wins | none |

### Program ownership matrix (`supabase/tests/local/program_ownership_matrix.sql`)

| Case | QA today | + 196 | + 196 + 197 | + 185 |
|---|---|---|---|---|
| O1 coach → own program → own client | ok | ok | ok | ok |
| O2 coach assigns another coach's private program, reads it | **leaks** | **leaks** | refused | refused |
| O3 explicitly shared program | — no sharing mechanism exists — | | | |
| O4 client self-assigns a coach's program | **leaks** | refused | refused | refused |
| O5 client reads another client's program | no | no | no | no |
| O6 unrelated coach assigns to someone's client | **leaks** | **leaks** | refused | refused |
| O7 client's NEW coach reads a former coach's program | yes | yes | yes | yes — **DEC 14** |
| O8 client keeps reading a former coach's program | yes | yes | yes | yes — **DEC 14** |

### Session credits (K-05 / K-25) — trace and design

Trace (QA, read-only): creation = Stripe webhook grant only (service role; `payment_id` unique,
`ignoreDuplicates`); owner = `client_id`; **no consumption path exists**; `coaching_calls` has no
credit link; no refunds; QA holds 0 credit rows. Clients: read own, no write. **Coaches: may
UPDATE any column except `coach_id`** (mint, reset, move a block to another client). No range
check.

**Prepared (decision-free): migration 198** (`fix/session-credits-not-coach-writable`, stacked on
#161): drops the coach UPDATE policy, adds `CHECK (0 <= used <= total, total >= 0)` NOT VALID.
Replay `credits_198_replay.sh`: 4 FAIL before → 8/8 after (K1 balance, K2 owner move, K5/K6 range;
client already blocked, server grant still works).

**Designed, not implemented (needs DEC 5):** `book_coaching_session(p_slot uuid)` SECURITY
DEFINER — caller = client with an active relationship to the slot's coach; `SELECT … FOR UPDATE`
the oldest block with `sessions_used < sessions_total` for (client, coach); refuse at zero; increment
`sessions_used`, insert the call with a new `coaching_calls.credit_id`, in one transaction (double
consumption impossible under the row lock; the slot's own lock (187) prevents double booking);
cancellation returns the credit only inside a refund window (**DEC 5b**); a credit block is never
transferable (owner fixed by 198). Tests to add with it: concurrent book of the last credit → one
succeeds; zero balance → refused; ineligible booking (no block with that coach) → refused or free
per DEC 5.

### Stripe lifecycle completeness

| Event | Handled | Ordering / duplicates | Missing (and why) |
|---|---|---|---|
| `checkout.session.completed` | yes — retrieves the subscription; upserts on `stripe_subscription_id`; grants idempotent | safe in any order with `updated`/`deleted` | — |
| `customer.subscription.created` | no (checkout covers it) | — | only needed if subscriptions are created outside Checkout (Portal/dashboard); not the case today |
| `customer.subscription.updated` | yes — **current state read from Stripe (#165)**; never un-cancels | safe | — |
| `customer.subscription.deleted` | yes — canceled + `canceled_at`; ends coaching | safe | — |
| `invoice.paid` | no | — | per-charge history; **adding rows to `payments` would double-count coach revenue** unless revenue reads change — design with the revenue screen, not alone |
| `invoice.payment_failed` | no (status arrives via `updated` → `past_due`) | — | user notice; grace period = DEC 11 |
| `charge.refunded` | no | — | revoke or not = DEC 11 |

No Stripe configuration exists on QA; no test-mode evidence is claimed.

### Security and data-integrity audit (new this round)

| Area | Finding | Severity | Path |
|---|---|---|---|
| Storage `exercise-media` (public) | **any signed-in user can UPDATE or DELETE any object** (policies check only the bucket) — a client could replace or wipe the images every user is served | P1 | **fixed in 199** (see Storage section) |
| Storage `coach-media` (public) | any signed-in user could INSERT anywhere and list/sign coach videos to clients | P1 | **fixed in 199** (own-folder writes, videos to coach + client) |
| Storage `progress-photos`, `chat-media`, `avatars` | owner / participant / own-folder scoped; coach reads active clients' photos | ok | — |
| Edge Functions | 18 of 19 require a JWT; `stripe-webhook` verifies the Stripe signature | ok | plan checks → #160 |
| Scores / challenge progress | client-writable own rows | DEC 9 | — |
| Session credits | coach-writable | fixed in 198 | apply |
| Program content | O2/O4/O6 | fixed in 196–197 | apply |

## Storage and program history (2026-11-16, round 3)

### Storage authorization — migration 199 (`fix/storage-writes-need-ownership`, stacked on #167)

**What was established (QA read-only + code):**
- Platform exercises are `custom_exercises` rows with `coach_id` null; private ones carry the
  coach. Media paths are `exercises/<exercise id>/<file>` (`CustomExerciseService`), uploaded
  **after** the row exists, with `upsert: true` (overwrite).
- Who may set media today: `update_exercise_media` (072) — **any coach or admin, on any
  exercise**; `content_manager` is not included anywhere. It is SECURITY DEFINER, so it also let a
  coach change another coach's **private** exercise media.
- Exercises are shared only as platform entries; nothing references media from programs
  (program rows carry no media), so deleting media breaks exercise display, not programs.
- coach-media paths are `<kind>/<uploader id>/…` (`coach-transformations`, `coach-videos/<coach>/<client>`,
  `voice`); coach videos have no player (OD-57).

**Bucket behaviour after 199** (both stay **public**: an object URL serves without a session):

| Bucket | Policy (exact name) | Who |
|---|---|---|
| exercise-media | `exercise-media public read` (061, unchanged) | everyone |
| exercise-media | `exercise-media write by exercise editor` (INSERT) | admin; a private exercise's coach; for a platform exercise, a coach or admin — path must name an existing exercise |
| exercise-media | `exercise-media overwrite by exercise editor` (UPDATE) | same |
| exercise-media | `exercise-media delete by owner or admin` (DELETE) | admin; a private exercise's coach. Platform media: admin only |
| coach-media | `coach media upload to own folder` (INSERT) | a coach/admin, only under `<kind>/<own id>/` |
| coach-media | `coach media overwrite own folder` (UPDATE, new) | same (a coach's own upsert now works) |
| coach-media | `coach media manage own` (DELETE, 036, unchanged) | the uploader |
| coach-media | `coach media read, videos by coach and client` (SELECT) | `coach-videos/<coach>/<client>/…` only that coach or client; other paths any signed-in user |

Dropped: `exercise-media auth write`, `exercise-media auth update`, `exercise-media auth delete`,
`coach media insert`, `coach media read`. Helpers: `can_write_exercise_media(text)`,
`can_delete_exercise_media(text)` (definer, search_path pinned, EXECUTE to authenticated only).
`update_exercise_media` now also requires the owner or an admin on a private exercise.

**Tests** (`supabase/tests/local/storage_199_replay.sh`, 29 assertions, writes as `authenticated`):
14 FAIL on 000-198 — unauthorized upload (E1, E2, M1), cross-coach upload (E3, M2), unauthorized
overwrite (E4, E5), unauthorized delete (E6, E7, E8), cross-client/coach video listing (M5, M6),
own-file re-upload blocked (Q2), RPC cross-coach media (R1) — and **29/29 on 000-199 and on QA's
shape**. Other replays unchanged on 000-199 (21/21, 34/34, 10/10, 8/8).

**Still open (decisions):** buckets public (URL access without a session — making coach-media
private breaks public transformation images; DEC 15b); any coach may replace platform-exercise
media and `content_manager` cannot edit it (DEC 15).

### Program history — O7 / O8 (proposal, not a migration)

`docs/proposals/program_history_O7_O8.sql` measures today and a proposed `can_read_program()`
inside a rolled-back transaction (QA shape and 000-199, same result):

| Case | Today | Proposed |
|---|---|---|
| O7 new coach reads former coach's private program | 1 (silent access) | **0** |
| O8 client keeps reading it (history) | 1 | 1 |
| O11 active coach reads the client's generated (unowned) plan | 1 | 1 |
| O12 author reads its own program | 1 | 1 |
| H1 client's workout history (own sessions) | 1 | 1 |

The proposal narrows the active-coach arm to programs the client owns or that have no owner.
Workout history reads `workout_sessions` (own rows), never the program tables, so it is unaffected.
Applying it is **owner decision 14**; it would become migration 200 with this file as its test.

## Ownership and storage — final policy (round 4, 2026-11-16)

Direction given in chat on 2026-11-16 for decisions **14, 15, 15b**. Implemented as
**prepared, unapplied** changes; each still needs Julia's approval and a decision-log entry
(§2) when approved. Nothing is applied or merged.

### Decision 15 — exercise media (revised migration 199, PR #168)

| Exercise | Upload / replace / delete media | Read |
|---|---|---|
| **Platform** (`coach_id` null, shared) | **content editors only** — `is_content_editor()`: `admin` or `content_manager` | everyone (public) |
| **Private** (coach-owned) | **its coach, or an admin** | everyone (public) |
| Other coaches | cannot replace shared or another coach's media | read / use |

- `content_manager` is a real, implemented role: assigned only by `admin_set_user_role()`
  (`handle_new_user` never lets a registrant pick it); `is_content_editor()` (083) already
  authorizes the content pipeline (`review_exercise_content`, `review_attribute`,
  `finalize_intelligence`, `rebuild_*`, `seed_warmup_library`); the app gates the Content Center,
  review queue and intelligence review to `admin`/`content_manager`. **Gap closed:** before 199 the
  role had *no* working media path (`update_exercise_media` refused it — replay S3 FAILS on 000-198).
- Server paths covered: storage INSERT/UPDATE/DELETE policies and `update_exercise_media` (one rule:
  `can_write_exercise_media`); `can_delete_exercise_media` delegates to it.
- App: the exercise screen's **Edit** button shows only where the database accepts the edit
  (`canEditExercise`; `test/unit/exercise_edit_rights_test.dart` — wiring fails on main).
- Replay `storage_199_replay.sh`: **37 assertions — 20 FAIL on 000-198, 37/37 on 000-199 and QA shape.**
  Manifest: the existing `199` entry's reason updated; no new entry.

### Decision 15b — coach media stays public (documented, no change)

| Path | Who writes (after 199) | Who reads | Public-URL dependency |
|---|---|---|---|
| `coach-transformations/<coach>/…` | that coach | anyone (shown in the coach directory) | **yes** — `getPublicUrl` stored in `user_profiles.transformation_photo_urls` (coach_business_screen) |
| `voice/<coach>/…` | that coach | signed at render time | legacy rows may hold a public URL; `coachVoiceSigningPath` accepts both forms |
| `coach-videos/<coach>/<client>/…` | that coach | API: that coach and client only (199) | none — path stored, no player (OD-57) |

QA holds **0** coach-media objects. **Path to private media:** (1) move transformation photos to
their own public bucket (e.g. `coach-public`) and rewrite `transformation_photo_urls`; (2) backfill
any voice rows that still hold public URLs to paths; (3) then set `coach-media` `public = false`
— videos and voice are already signed. Until (1) lands, `coach-media` stays public, as directed.

### Decision 14 — program history (migration 200, PR stacked on #168)

| Who | Reads a program assigned to the client |
|---|---|
| author | yes (unchanged) |
| the client — its history (O8) | yes (unchanged) |
| the assigning coach | yes (unchanged) |
| the client's **active** coach | only client-owned or unowned/generated programs (O11) — **not another coach's (O7)** |
| admins | yes |

Replay `program_history_200_replay.sh`: **2 FAIL on 000-199 (H1, H2) → 11/11 on 000-200 and QA shape.**
Ownership matrix with 200, both shapes: O1 ok; O2/O4/O6 refused; O5 0; **O7 0**; O8 1; O9 1; O10 0.
Workout history reads the client's own session rows — K6 intact.

### Migration chain (all unapplied)

`196, 197` (#161) → `198` (#167) → `199` (#168, revised) → `200` (new PR). Each PR adds exactly
its own `qa.pending` key; exclusions 182–186 unchanged; `applied_through` 192 unchanged. On
000-200 and on QA's shape every replay passes: program_history_200 11, storage_199 37, credits_198 8,
assignment_196 10, policy_193_194 21, integrity_187_192 34.

## Controlled-beta release preparation (2026-11-16)

Prepared, nothing executed: **`docs/BETA_RELEASE_RUNBOOK.md`** (merge runbook, QA migration
runbook, Edge Function deployment plan, Stripe/email checklist, hosting recommendation, native
checklist) and **`docs/WEEK1_ACCEPTANCE_WALKTHROUGH.md`** (the 14 journeys, P1 first).

- **Merge order simulated:** #165, #160, #162, #163, #166, #161, #167, #168, #169, #164 onto `8f2c8a0`
  with `git merge-tree` — no textual conflict. `main` has no branch protection; the per-PR gate is the
  procedure.
- **QA pre-flight (read-only):** ledger max 192, none of 193–200; 619 active relationships (would be
  pre-193 — decision 3); 3 pending invites; 0 assignments or credit rows that the new rules would
  refuse; 0 objects in exercise-media / coach-media; the 5 policies 199 drops exist by name.

**New findings this round**

| Finding | Severity | Path |
|---|---|---|
| `send-checkin-reminder` has **no caller check**: any valid project JWT can make it notify and email every active client, repeatedly | P1 (not deployed) | **fixed in PR #171** (service-role caller only); idempotency remains D-5 |
| `send-invite-email` falls back to `APP_URL = https://12circle.app` when unset — QA invites would link to a production-looking domain | P2 | set `APP_URL` to the hosted QA URL before any invite |
| Native OAuth redirects to `io.circle12.app://login-callback`, which neither iOS nor Android registers | P2 (web unaffected) | register the scheme + add it to Supabase Auth redirects before native beta |
| Sign-up may self-select `client`, `coach` or `vendor` (staff roles cannot be chosen) | info | recorded in the walkthrough |

## Agent-led cycle 1 (2026-11-16)

Specialists ran as real Claude Code sessions started as each `cplus-*` agent (definitions in PR #170;
log with commits in `docs/P0_IMPLEMENTATION_PACKAGES.md` on that branch).

| PR | What | Agents | Independent verdicts | CI |
|---|---|---|---|---|
| #171 | `send-checkin-reminder` refuses every caller but the service role (EDGE-2; was a deploy blocker) | supabase-engineer | security APPROVE-WITH-NOTES · QA VERIFIED ×2 | 7/7 (`43987746265`) |
| #172 | ending coaching / requesting a coach report what actually happened; intake keeps a saved link linked | ux-reviewer (found it) · flutter-engineer | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES · QA VERIFIED ×2 | 7/7 (`43991115899`) |

### Cycle 2 — P0-FL-2 and P0-FL-3 (2026-11-16)

| PR | What | Agents | Independent verdicts | CI (exact head) |
|---|---|---|---|---|
| #173 | **P0-FL-2** coach Requests tab and check-in History: no raw exception text; "Couldn't load …" + Try again (disabled with progress while in flight); sent invites no longer show a failure as empty; History has a loading state and an announced failure; no overflow at 2× text; each failure recorded once (`reportError`) | flutter-engineer (913a0d9, 918c8dc) | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES (U1/U4/U5 fixed) · QA VERIFIED ×2 | 7/7 on 918c8dc (`44001635796`) |
| #174 | **P0-FL-3** (stacked on #172) coach price writes: signed-out and 0-row saves throw; the Pricing sheet and Custom Price dialog show the reason **inside** the modal instead of "Pricing updated." / "Custom price set to $X/mo." (a 0-row custom price had told the coach a price checkout would not charge) | flutter-engineer (e239eed, 44483d0) · lead (0b89742 label, 4d1d992 test) | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES (U1–U3, U5 fixed) · QA VERIFIED ×2 | 7/7 on 4d1d992 (`44002583036`) |

Evidence is automated only (widget + fake-PostgREST unit tests; full suite 2696 / 2714 pass; analyze 291;
new tests fail on the previous heads; QA negative controls caught). **No device, simulator or live-QA run:**
the failure paths need failing or 0-row QA reads/writes, which are not authorized.

Found by these reviews, not fixed (recorded):
- **Custom price impossible for invited clients** (security F1, pre-existing): 113's coach UPDATE check
  refuses a `monthly_price` write on an active relationship with `initiated_by='coach'` — the normal
  invite path (194) — contradicting 192 (coach sets the price). Fails safe (standard rate charged, the
  dialog now says it failed). Needs a migration → `cplus-supabase-engineer`, then an apply approval.
- `coach_business_screen` `_save`: "Profile updated!" on a 0-row update; saves `pricing_monthly = 0`
  when the price field does not parse; silent when signed out. Decision-free → next Flutter package.
- Raw `e.toString()` still shown on the coach leaderboard tab, `community_screen`, `create_exercise_screen`.
- Pricing sheet `_load` swallows read errors (`catch (_) {}`); Requests badge reads `valueOrNull`.

**P0 acceptance status (from `docs/CONTROLLED_BETA_SCOPE.md`, not from PR counts):** of the 14
journeys, **2** have integration evidence (7 workout execution, 8 completion — I-WRK-01 live);
**0** have a recorded manual run; the four "beta-ready" conditions are **0 of 4** met (migrations
193–200 unapplied, functions undeployed, email/APP_URL/vault unset, walkthrough not run). This cycle
removed defects in journeys 5 and 12 and a deployment blocker; it did not add integration evidence
(that needs QA writes or a manual run). **P0 acceptance: 2 of 14 journeys (14%).**
Cycle 2 (#173, #174) removed further defects in journeys 5 and 9 and in coach pricing; it added no
integration evidence either. **P0 acceptance unchanged: 2 of 14 journeys (14%), 0 of 4 beta-ready conditions.**

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
12. Beta platforms (web only vs TestFlight / Play internal) and where the web app is hosted (runbook §5 recommends Vercel static, SSO-protected).
13. Exercise media source hierarchy, and approval for content batches (QA writes).
14. Does program history follow the client (new coach reads a former coach's program; client keeps it) or stay private to its author?
15. Who may change media on platform exercises (today any coach; content_manager excluded)? 15b. Make coach-media private (breaks public transformation images unless they move)?
16. Credit refund window when a booked session is cancelled (5b).
17. May a coach write `pricing_monthly` on an active client's profile (015 "coaches can update client profiles"; matters when the client is also a coach)? (security F2, #174)
18. Is $0 a valid coaching price? The Custom Price dialog accepts 0; the Pricing sheet refuses it (UX U4, #174).

## Migration approvals required

| Batch | Contents | Gate |
|---|---|---|
| 193–195 | decisions 1 & 4; bookings need Coach-Guided | owner-approved QA window (193 before 195) |
| 196–197 | program ownership (PR #161) | owner-approved QA window naming 196, 197 |
| 198 | session credits not coach-writable (PR #167, stacked on #161) | owner-approved QA window naming 198 |
| 199 | storage writes need ownership + decision 15 (PR #168, stacked on #167) | owner-approved QA window naming 199 — **before any beta media is uploaded** |
| 200 | program history stays with its author — decision 14 (PR stacked on #168) | owner-approved QA window naming 200, after 196–197 |
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
- Nutrition sync verified (2026-11-16): every meal-logging path calls `refreshAfterMealLogged`; no defect.

## Next autonomous action

Phase 3: client/coach journey audit for decision-free defects (cross-sync, false
success, dead ends), one focused PR each; update this ledger after each.
