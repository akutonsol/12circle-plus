# 12Circle Plus — Beta Completion Ledger

The single running ledger for the core-beta completion mission. **Read this first after a
context reset; continue from "Next autonomous action".** Every status here cites its
evidence. Nothing is marked complete without it.

## Snapshot (update at every milestone)

| | |
|---|---|
| `origin/main` | `8f2c8a0` (PR #159), CI run `43792727007` **7/7 success** |
| Live QA evidence on main | security **1173/1173**, AI **51/51**, ENV-3 L-1..L-5 PASS (ledger 188 rows; frontier 192; 182–186 declared excluded) |
| Open PRs | #14 (owner's, untouched) · #160–#218, all unmerged. Flutter P0 stack CI 7/7 on each exact head. #183 targets `integration/p0-flutter-stack`; #184–#190 target #183's branch; #191 targets #189's; #192–#194 target `-c6`; #195–#198 target `-c7`; #199–#203 target `-c8`; #204–#208 target `-c9`; #209–#213 target `-c10`; #214–#218 target `-c11`. Combined branches `-c6` @ `6f8918f`, `-c7` @ `df35d5f`, `-c8` @ `185261e`, `-c9` @ `1b94044`, `-c10` @ `b7ec6ef`, `-c11` @ `f191d48`, `-c12` @ `a82f993`, all CI 7/7. **None to be merged without explicit authorization** |
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

### Cycle 3 — P0-FL-4 and P0-FL-5 (2026-11-16)

| PR | Package | Commits (author) | Files changed | Tests (automated) | Independent verdicts | CI (exact head) |
|---|---|---|---|---|---|---|
| #176 | **P0-FL-4** coach Business Profile reports what happened: a failed/empty load no longer shows an editable blank form (one Save used to overwrite the real profile with blanks); every `user_profiles` update row-checked; signed-out writes refused with a message; a blank price/years is no longer written as `0`, a non-empty unparseable/negative one is refused inline (explicit 0 unchanged — Decision 18); certification add/remove restores on failure; photo 0-row reported; a failed invite insert sends no email; Add Certification no longer crashes (disposed controller) | flutter-engineer: 97321b1, dd9a333, d0a2722, 06ca1af | `apps/mobile/lib/features/coach/presentation/coach_business_screen.dart`; `apps/mobile/test/widget/business_profile_reports_what_happened_test.dart` (new, 50 tests) | 20 fail on main's screen; full suite **2733 pass / 7 skip**; analyze **287** (baseline 291); contract guard PASS 31 ≤ 31; coordinator 268/268; static guards 0 failures (lead, after dd9a333 fixed a contract-guard regression 32 > 31 found by the lead) | security **APPROVE-WITH-NOTES** (local replay 000–195: own row 1, other coach 0, no 115 refusal); UX **PASS-WITH-NOTES** ×2 (N1–N9, N1a, N10b fixed); QA **REJECTED** (dd9a333: `.select('id')` drop undetected) → **VERIFIED** ×2 (d0a2722, 06ca1af); lead-run code mutants 7/7 caught | 7/7 on 06ca1af (`44014296382`) |
| #175 | **P0-FL-5** (stacked on #173) no raw exception text: coach Leaderboard (busy-aware retry, recorded once), Community feed (announced, scrolls), Create exercise (PostgREST/Storage text never shown; connection hint only for network failures; signed-out says so; review-submission copy no longer points at a missing control; stale `lastError` cleared) | flutter-engineer: a9e69be, 87cda02 | `coach_dashboard_screen.dart` (leaderboard tab), `community_screen.dart`, `create_exercise_screen.dart`, `custom_exercise_service.dart` (lastError clearing only); tests `coach_leaderboard_no_raw_error_test.dart`, `community_feed_no_raw_error_test.dart`, `create_exercise_no_raw_error_test.dart` (new), `unit/custom_exercise_last_error_test.dart` (new) | 10 fail on 918c8dc, 13 more on a9e69be; full suite **2725 pass / 7 skip**; analyze **291**; contract PASS; static guards 0 failures | security **APPROVE-WITH-NOTES**; UX **PASS-WITH-NOTES** ×2; QA **REJECTED** (a9e69be: per-rebuild recording undetected) → **INCONCLUSIVE** (87cda02: its code mutants were blocked by the session classifier); lead-run mutants 5/5 caught (M4 + 4 controls) | 7/7 on 87cda02 (`44012398498`) |

**Acceptance evidence is automated only** — widget and fake-PostgREST unit tests, negative-control mutants,
static/contract guards, CI. **No device, simulator or live-QA run** (the failure paths need failing or 0-row QA
reads/writes, which are not authorized). The security replay ran on a local database copy, not QA.
**Journey completion is not increased by this cycle.**

Backlog recorded this cycle (decision-free unless marked):
- **Pricing sheet `_load` failed read** — `coach_pricing_sheet.dart` `catch (_) {}` shows an empty price field after a
  failed read, so the coach cannot tell "no price set" from "could not read". Next Flutter package.
- **Requests badge** — the coach dashboard Requests tab badge reads `pendingRequestsProvider` with `valueOrNull`, so a
  failed read shows no badge (a failure shown as zero). Next Flutter package.
- Create exercise: media upload/attach/sync failures after a save are ignored and the success dialog still shows
  (security F4 on #175).
- Community: `liveMembersProvider` turns every error into `[]` ("No members yet") — error-contract breach.
- Same unchecked-update pattern (QA on #176): `settings_screen.dart:69`, `home_screen.dart:1329`,
  `coach_relationship_service.dart:218`, `intake_flow_screen.dart:163`.
- `reportError` sink must redact PostgREST details before any vendor sink is chosen (**decision PD-A24**).
- No "submit for review" control for a saved draft whose submission failed (**decision**); PostgREST 502/503 copy
  (support vs connection hint) (**decision**).
- SR-4: 015 "coaches can update client profiles" lets an active coach write a client's bio etc. (**ties to
  Decision 17**); SR-2 `send-invite-email` does not require a saved invite (E-15, D-7(D)); SR-3 any signed-in user can
  insert a team invite for themselves (Wave 2).
- **P0-SB-2** (custom price impossible for invited clients — 113 UPDATE check vs 192) stays separate: **no migration
  is created or applied until Julia resolves Decisions 17 and 18 and authorizes the work.**

**P0 acceptance after cycle 3: unchanged — 2 of 14 journeys (14%), 0 of 4 beta-ready conditions.**

### Cycle 4 — P0-FL-6 to P0-FL-9 and the SR-4 investigation (2026-11-17)

| PR | Package | Commits (author) | Files changed | Automated evidence | Independent verdicts | CI (exact head) |
|---|---|---|---|---|---|---|
| #177 | **P0-FL-6** (stacked on #174) Coach Pricing sheet: a failed read shows "Couldn't load your current price" + Try again in place of the field and Save (was an empty field = "no price set"); signed-out message; Save copy network/other split; scrolls at 2x. Requests tab label: failed read shows an error icon + "Requests — couldn't load" (was "no requests"); no dot flicker on reload | flutter-engineer: af83748, 739996f, 7844f17 (tests) | `coach_pricing_sheet.dart`, `coach_dashboard_screen.dart` (tab label only); `pricing_sheet_load_failure_test.dart`, `requests_tab_label_failed_read_test.dart` (new), `price_writes_report_outcome_test.dart` | 12 tests fail on 4d1d992; full suite **2744 / 7 skip**; analyze 291; `.valueOrNull` −1; contract 31 ≤ 31 | security **APPROVE-WITH-NOTES**; UX **PASS-WITH-NOTES**; QA **VERIFIED**; lead mutants 4 survived → test-only round → **4/4 caught** | 7/7 on 7844f17 (`44029419873`) |
| #178 | **P0-FL-7** (stacked on #175) create exercise: every media/relations step after a save is checked (incl. the media RPC's `found=false`); any failure → no "Exercise Saved!", one message naming what failed + "Save again"; media-only failure → "nothing was changed"; after a create the screen edits that row (a retry no longer creates a second exercise) | flutter-engineer: 255fc35, 098f758, ca3ca97 (tests) | `create_exercise_screen.dart`, `custom_exercise_service.dart` (`updateExerciseMedia` only); `create_exercise_media_failures_test.dart` (new) | 16 fail on 87cda02 (+ test seam), 4 on 255fc35; full suite **2746**; analyze 291 | security **APPROVE-WITH-NOTES**; UX **FAIL** (retry duplicated) → **PASS-WITH-NOTES**; QA **VERIFIED**; lead mutants 2 survived → **2/2 caught** | 7/7 on ca3ca97 (`44030338977`) |
| #179 | **P0-FL-8** (stacked on #175) Community Members: a failed read is an error state (copy split, busy-aware Try again, live region, 2x), not "No members yet."; `addPost` no longer fakes a feed of one; feed error follows the same rule | flutter-engineer: 53af301, 0ca4425, 8d2eb09 (tests) | `community_provider.dart`, `community_screen.dart`; `community_members_failure_test.dart` (new), `community_feed_no_raw_error_test.dart` | 11 fail on 87cda02; full suite **2744**; analyze 291 | security **APPROVE-WITH-NOTES**; UX **PASS-WITH-NOTES**; QA **VERIFIED**; lead mutant (ClientException) survived → **caught** | 7/7 on 8d2eb09 (`44031390664`) |
| #180 | **P0-FL-9** (stacked on #174) settings unit toggle, client "Rate Your Coach" upsert and intake progress saves request their row back and report failure; the client's no-op write of the coach's `rating_avg` removed; `setGlobalPrice` already fixed by #174 (verified) | flutter-engineer: 3cb4e4e, 2585107, 12b098d, e8ef987 (tests) | `settings_screen.dart`, `home_screen.dart` (review dialog), `intake_flow_screen.dart` (`_saveProgress`); `test/support/row_checking_postgrest.dart` + 3 new widget tests | settings +1 −5 and intake +1 −3 on 4d1d992; Home 0/5 on 4d1d992 + hook (lead); full suite **2733**; analyze 291; contract write sites 172 → 171 | security **APPROVE-WITH-NOTES** (local replay 000–192); UX **PASS-WITH-NOTES**; QA **INCONCLUSIVE** (Home hook) → resolved by the lead's baseline; lead mutants 6 survived → **6/6 caught** | 7/7 on e8ef987 (`44032450976`) |

**Evidence is automated only** (widget/unit tests on fakes, mutants, guards, CI, two local database replays and two
read-only QA reads by the lead: a schema dump and one aggregate count). **No device, simulator or live-QA write.**
**Journey completion is not increased by this cycle.**

**New backend defect (P2, not fixed — needs a migration and Julia's approval): coach ratings stop updating after 115.**
045's `recalc_coach_rating()` runs from the `coach_review_rollup` trigger while `auth.uid()` is the reviewing client,
so 115's `enforce_profile_privilege()` pins `rating_avg`/`review_count` to OLD. Proven by local replay (R2/R4 FAIL;
controls R8 no-uid and R9 trigger-off pass). **QA, read-only count: 3 coaches have reviews, 1 has a stale stored
rating.** Fix options: A pin only for `authenticated`/`anon` (recommended), B transaction-local flag, C compute on
read — each with a backfill. Prerequisite decision: who may review a coach (today any signed-in user, with or without a
relationship — `001` "clients manage own reviews").

**SR-4 investigation — active coach writing a client's profile (read-only; no permission changed).**
- Live QA (read-only schema dump by the lead) and a local replay of migrations 000–181 + 187–192 agree: policy
  "coaches can update client profiles" (015) — `FOR UPDATE TO authenticated USING/WITH CHECK id IN (client_id of an
  ACTIVE relationship with coach_id = auth.uid())`; `GRANT ALL ON user_profiles TO authenticated`; no column grants.
  193–200 do not change it. The only enforcement is 115's trigger.
- Of 78 columns, an active coach: **REFUSED 9** (`role`, `membership_tier`, `marketplace_commission_rate`, five
  `stripe_*`, `is_demo`); **silently kept 7** (`id`, `email`, `created_at`, `rating_avg`, `review_count`,
  `ai_client_summary`, `assigned_coach_id`); **recomputed 3** (`risk_score`, `risk_level`, `risk_flags`);
  **WRITABLE 59** — incl. all 32 health/intake columns (`parq_answers`, `medical_conditions`, injuries, body metrics,
  `date_of_birth`, `consent_agreed`/`consent_date`, goals…), identity (names, `phone`, `avatar_url`), onboarding and
  notification flags, coach-only fields, `updated_at`.
- Consequences proven: the coach can clear the PAR-Q and drop the client from high to low risk; can set consent;
  injury edits become permanent AI memories in the client's name that the coach cannot delete.
- Pending/ended/no-relationship coaches change nothing (0 rows). **No app screen writes a client's profile as the
  coach** — nothing in the app depends on this policy.
- Recorded already as registry R-05 (P3, linked to the wrong question Q-H1). **Decision for Julia (Decision 19 below):
  A remove the policy; B an explicit allow-list (today empty); B′ keep it but block safety/consent/coach-only fields;
  C status quo.** No migration until approved.

Backlog added this cycle: `groupNotifierProvider` failure shown as "no groups" (Community + Activity); dead
`postListProvider`; shared `isNetworkFailure` helper after the stacked PRs merge; Set Custom Price dialog copy split;
postgrest-dart ~7 s retry before a network failure shows; 46 other `catch (_) {}` in `lib/` (~20 files);
`public_profiles` member listing is unscoped (decision); auto-review of newly created coach exercises (decision).
P0-SB-2 **remains blocked** on Decisions 17 and 18 and explicit authorization.

**P0 acceptance after cycle 4: unchanged — 2 of 14 journeys (14%), 0 of 4 beta-ready conditions.**

### Cycle 5 — P0-FL-10, P0-FL-12, P0-FL-11, silent-error inventory, read-only investigations (2026-11-17)

**Integration branch (new).** `integration/p0-flutter-stack` = `origin/main` + every open Flutter PR head merged (no
PR merged into `main`). Evidence it composes: **f4cf7b1** (#172–#180) — analyze 287, **2895** tests pass, static
guards 0, CI **7/7** (push run `44225771776`); **e606fe5** (+ #181, #182) — analyze 287, **2954** pass, guards 0,
CI **7/7** (push run `44234316826`). It exists so P0-FL-11 could target one base.

| PR | Package | Base | Commits (author) | Files | Automated evidence | Independent verdicts (at the final head) | CI (exact head) |
|---|---|---|---|---|---|---|---|
| #181 | **P0-FL-10** group list loading/failed/loaded on Community Groups and Activity (was "no groups" / "not joined"); join/leave failures reported; `leaveGroup` 0 rows = failure + list re-read; 23505 by error code; Join pill a named 44 px button | #179 | flutter-engineer: 14d8518, 452a87a, 2ff8080, 8e62718, 4c3a7c2 | `community_provider.dart`, `community_screen.dart`, `activity_screen.dart`, `live_community_service.dart`; 2 new + 1 updated tests | base +2 −12; full **2781**; analyze 291; lead mutants **8/8** caught | UX **PASS**; security **APPROVE-WITH-NOTES** (replay of 016); QA **VERIFIED** | 7/7 on 4c3a7c2 (`44231208557`) |
| #182 | **P0-FL-12** client-detail: a failed prefill read no longer lets Save **overwrite the client's nutrition plan or switch off their habits** (data loss reproduced on e8ef987); inputs and Save locked until loaded; paid-plan check failure honest and fail-closed | #180 | flutter-engineer: 90e307a, 23dd969 | `client_detail_screen.dart`, `coach_program_service.dart` (`clientHasPaidPlan`); 1 new test file (22 tests) | base +3 −5 (90e307a), +8 −14 (23dd969 vs 90e307a); full **2755**; analyze 291; lead mutants **6/6** caught (M5 second-layer guard documented) | UX **PASS-WITH-NOTES**; security **APPROVE-WITH-NOTES**; QA **VERIFIED** | 7/7 on 23dd969 (`44232187464`) |
| #183 | **P0-FL-11** one shared `isNetworkFailure` (`core/observability/network_failure.dart`) replaces 8 identical private copies; dead `postListProvider` removed (no references); Set Custom Price dialog network/other split | **integration/p0-flutter-stack @ e606fe5** | flutter-engineer: 2ecd6e2 | 12 files (helper + test new; 9 lib files; 1 test expectation) | dialog test base +12 −1; full **2969**; analyze 287; lead mutants **3/3** caught | UX **PASS-WITH-NOTES**; security **APPROVE-WITH-NOTES**; QA **VERIFIED** | 7/7 on 2ecd6e2 (`44236734289`) |

**Evidence is automated only** (widget/unit tests on fakes, mutants, guards, CI on each PR and on the integration
branch, local database replays, read-only QA catalog reads by the lead). **No device, simulator or live-QA write. No
journey completion is claimed from these.**

**Silent-error inventory** — `docs/SILENT_ERROR_INVENTORY.md` (new): every swallowed failure at f4cf7b1 traced to
file:line, consequence, priority, fix, package and PR. **P1 3, P2 21, P3 ≈111.** #182 closes 2 P1 + 1 P2; P0-FL-13 …
P0-FL-19 cover the remaining 1 P1 (intake baseline photos silently lost) and 20 P2.

**Read-only investigations (no repo, policy, migration or data change):**
- **Decision 19 brief** (coach writes client profile): no app, Edge Function, AI function or RPC depends on 015's coach
  UPDATE arm; options A (drop), B (empty allow-list trigger), B′ (16 writable / 43 refused, fail-closed), C (status quo
  + changed-columns-only audit) with SQL sketches, breakage, PHI and test plans. **New: F1 P1 defect** — an active
  coach can clear a client's PAR-Q (high→low risk), contradicting 115's recorded rule (member owns the answers); closed
  by A/B/B′ only, needs a migration + approval. **F3 P2 defect** — the coach's PAR-Q tab reads health data via
  `select('*')`; the logged `get_client_assessment()` has 0 app callers, yet `SECURITY_LEDGER_PHI.md` SEC-PHI-AUDIT
  says VERIFIED_CLOSED — the ledger status is wrong (app-side fix is decision-free; package P0-FL-37). AI-memory capture
  (075) needs its own decision (memories persist after clearing, no authorship, likely re-created after deletion).
- **Decision 20** (who may review a coach) — replay + **live QA catalog confirmed** (policies `all read reviews`
  USING true; `clients manage own reviews` FOR ALL USING client_id = auth.uid(); unique (coach_id, client_id); rating
  1–5; triggers rollup + notify): any signed-in user can review any user incl. self, competitors, non-coaches; move a
  review to another coach; backdate it; each review notifies the target with chosen text; reviewer identity is public.
  Options A status quo / B active-or-past relationship / C B + minimum, plus add-ons.
- **Member-list access** — `public_profiles` has no row filter: every signed-in user lists all users incl. roles
  (admins), sign-up times, demo accounts (demo filter app-side only); 8 tables expose user ids readable by all. Options
  A status quo / B scoped / C opt-in / D column split.
- **P0-SB-3** (coach ratings frozen since 115) — new **option D** (the guard computes the true totals itself; nothing a
  caller sends can be stored) validated on a scratch database: 25/25 on four schema shapes, all 7 existing replays
  unchanged; A also 25/25; B 24/25 (raw-SQL GUC forge). Backfill and rollback designed. **Should land with or after
  Decision 20** — fixing it publishes today's unrestricted reviews in the rankings. Next number 201, after 200.
- **QA migration state (read-only)**: `schema_migrations` = …180, 181, 187–192 — **182–186 are not applied**.
  (CORRECTED 2026-11-18: this line first said main's `expected_applied.json` "still says applied_through 181" — false; that
  was read from a stale checkout. Main declares frontier **192** with 182–186 **excluded**, each with a reason and gate, which
  matches QA. See `docs/QA_MIGRATION_DISCREPANCY_REPORT.md`.) So on QA **QAX-SEC-01/03 are live**: any signed-in user can
  call `assign_nutrition_plan` for any client and insert `client_habits` / `client_nutrition_plans` naming themselves
  as coach (older FOR ALL policies). 184/185 need an owner-approved QA window. **Multi-coach plan overwrite** (a coach
  sees only its own plans; Save replaces another coach's active plan) needs a plan-ownership decision.

Backlog added: P0-FL-13 … P0-FL-19 (beta-journey silent errors, see inventory); P0-FL-37 (PAR-Q tab via the logged
RPC); habit rows lack semantics and locked rows not dimmed (#182 UX); custom-price timeout wording (may have committed —
copy decision); group-membership readable by all (decision).

**P0 acceptance after cycle 5: unchanged — 2 of 14 journeys (14%), 0 of 4 beta-ready conditions.**

### Cycle 6: P0-FL-19, P0-FL-37, P0-FL-13/15/18/14/16/17 and the QA migration discrepancy report (2026-11-18/19)

**Base.** Every package starts from #183's head (`2ecd6e2` = `integration/p0-flutter-stack` + the shared `isNetworkFailure`). Each PR **targets `fix/shared-network-failure-and-cleanup`** (#183's branch), so its diff shows one package. P0-FL-17 targets P0-FL-16's branch because they share files. #183 still targets `integration/p0-flutter-stack`, unchanged.

**Do not merge into a PR's own base.** Merging a PR's head into its base branch would make GitHub mark that PR merged.

**Combined evidence branch.** `integration/p0-flutter-stack-c6` = `integration/p0-flutter-stack` (`e606fe5`, unchanged) + #183's head `2ecd6e2` + the eight cycle-6 final heads (`72fed97`, `e3d5636`, `c117cfb`, `ef3d67a`, `b556bca`, `3f357ee`, `beb2a3f`, `d307187`), merged locally. Nothing went into `main` or into any PR base.
- **@ `6f8918f`:** analyze **287**, **3192** tests pass, static guards 0, CI's 10 negative controls 0 (run locally). CI (push): **7/7** run `44463329197` on `6f8918f`.
- **It caught a composition defect that per-PR CI could not see:**
  - FL-14's notification stream re-opens itself on a back-off timer.
  - FL-15's coach routing test kept its provider container alive past the tree, so the test ended with "A Timer is still pending".
  - Fixed test-only on FL-15 (`c117cfb`): the test disposes the container with the tree. It passes with and without FL-14.

| PR | Package | Final head | Commits (author) | Independent verdicts at the final head | Lead mutants | Tests (full suite) | CI (exact head) |
|---|---|---|---|---|---|---|---|
| #185 | **P0-FL-19** intake: a baseline-photo upload failure keeps the user on the step and says what was and wasn't saved (Try again re-sends only failed slots; "Continue anyway"); a failed resume read shows a retry-only notice and **no save can write blank answers over stored ones**; coach-list failure is not "No coaches" | `e3d5636` | engineer 1646e59, 36fdfce, e3d5636 | UX PASS-WITH-NOTES · security APPROVE · QA **VERIFIED** (first pass NOT VERIFIED: the new copy broke CI's EC-03 negative control; fixed) | all caught (incl. markIncomplete 0-row/throw, double-fire, notice reveal) | 2983 | 7/7 `44446529335` |
| #187 | **P0-FL-37** the coach reads a client's assessment (PAR-Q, risk, medical, injuries…) only through the logged `get_client_assessment` RPC (writes `assessment_access_log`); the profile read is an explicit non-assessment column list; 42501 / no row / not completed / failure states, with RISK UNKNOWN or RISK HIDDEN, never low risk. Authorization unchanged (live QA: both paths admit exactly `is_active_coach_of`) | `ef3d67a` | engineer 8748c9b, b581580, b5c6c49; lead d9655ad (coordinator now pins one RPC caller; CON-03 memo fact update, decision still PENDING), ef3d67a (EC-04 device probe override) | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | 7/7 (×3 heads) | 2987 | 7/7 `44451418256` (first run on b5c6c49 failed EC-04, fixed) |
| #184 | **P0-FL-13** inbox failure is an error state, not "No conversations yet"; a saved message whose preview update fails counts as sent (no false "not sent", no duplicate resend); chat send copy split network/other | `72fed97` | engineer 23eceae, d55791f, f77496d, 8c439b0, 72fed97 | UX PASS · security APPROVE-WITH-NOTES · QA **VERIFIED** | 6/6 | 2988 | 7/7 `44444119951` |
| #186 | **P0-FL-15** a failed role read after sign-in never routes a coach, admin or vendor to the client `/home`. The login screen shows "Couldn't load your account" with Try again and Sign out, a loading state instead of the credentials form, and an account-switch guard. The router redirect stops guessing. | `c117cfb` | engineer 77bfb49, 3fecf0a, 1ea045c; lead c117cfb (test teardown) | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** (first pass NOT VERIFIED: coverage) | 9/10 + 1 equivalent | 3002 | 7/7 `44459402632` |
| #188 | **P0-FL-18** five `WorkoutService` reads rethrow; strength, coach J11 and train-hub sections show scoped failures with retry (not "No data yet", "No personal records yet" or "No sessions recorded") | `b556bca` | engineer 7827c94, b556bca | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | 9/9 | 3002 | 7/7 `44453836812` |
| #189 | **P0-FL-16** the profile read rethrows. Profile shows a failure, not "Member" defaults. Personal Info, Notifications and Settings units are **locked until the profile loads** (touch, screen reader and handler layers), so no default can be saved over the real profile. | `3f357ee` | engineer 28ad13e, 4db8348, c9dd151, 3f357ee | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | all single-surface caught; all-layers-off caught; 3 single-layer survivors equivalent (another layer still blocks) | 3005 | 7/7 `44454848750` |
| #190 | **P0-FL-14** coach notification failures reach the bell (unknown, not 0) and the sheet (retry); the dead stream re-opens with back-off (2 s to 1 min, reset on data). Availability failure is a retry state, with Add slot disabled. A 0-row or thrown slot delete is told. | `beb2a3f` | engineer 86d6610, 5e02026, beb2a3f | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | all caught (8) | 3000 | 7/7 `44456761740` |
| #191 | **P0-FL-17** an unknown plan is never shown as "Free": "…" / "—" with retry on five screens; Upgrade marks nothing Current and offers nothing while unknown; entitlements and paywall unchanged | `d307187` | engineer 0b8b8e1 (lead rebase onto 3f357ee → 967a8b2), d307187 | UX PASS · security APPROVE-WITH-NOTES · QA **VERIFIED** | 8/8 | 3044 | 7/7 `44461871147` |

All final heads: flutter analyze **287** (= base), contract guard exit 0 with unseen 31, coordinator 268/268, static guards 0, CI's 10 negative controls 0 (run locally by the lead).

**What the evidence covers:** automated evidence only — widget and unit tests on fakes, lead-run mutants, guards, and CI on each PR and on the combined branch.
- No device, simulator or live-QA run.
- Not observed: that a real coach page open writes one `assessment_access_log` row.
- **Journey completion is unchanged: 2/14, beta-ready conditions 0/4.**

**Silent-error inventory:** the last **P1** (intake baseline photos) is closed by #185. All 21 P2 rows now have a PR (#182, #184–#190, #191). Remaining: ≈111 P3 (P0-FL-20 … P0-FL-36) plus the new follow-ups below.

**QA migration discrepancy report** (`docs/QA_MIGRATION_DISCREPANCY_REPORT.md`, read-only):
- **QA state:** QA ledger 000–181 + 187–192 (188 rows). 182–186 are absent, and 193–195 are authored but pending.
- **Main's `expected_applied.json` is accurate** (frontier 192; 182–186 excluded with gates). The cycle-5 claim that it "still says 181" was **false** (read from a stale checkout) and is corrected.
- **Security exposure:** QAX-SEC-01 (P0, 184) and QAX-SEC-03 (P1, 185) are live on QA. The report lists the exact live predicates, tables, operations and roles.
- **Proposed sequences, both for Julia to choose:**
  - **Option S:** 184 → 185 only.
  - **Option R:** the manifest's 182 → 186 batch.
  - Both use per-file apply with a ledger row, read-back, live suites alone, then CI. Never `supabase db push`.

**New follow-ups (engineering, decision-free):**
- **P0-FL-38:** unlogged assessment reads in `coach_copilot_screen.dart` (injuries, goal, experience, location), `coach_dashboard_screen.dart` (roster `risk_level`) and `coach_relationship_service.dart` (`fitness_goal`, `weight_kg`).
- Notification-sheet write callbacks (mark read, mark all, swipe delete, clear all) and `_cancelSession` voice.
- `notification _saveToggle` and the avatar/save paths: no 0-row checks.
- Ten role-gated screens say "Coaches only." when the profile read failed.
- Manage subscription draws nothing when the subscriptions or coaches reads fail.
- `train_hub` activeSession failure (EC-G6).
- Pre-existing 2× overflows: photo step, client page, Profile and Settings headers, notification sheet header.
- `AuthButton` Semantics when `onTap` is null; the router redirect's own account-switch check.

**New decisions for Julia (not taken):**
- Server-side enforcement that coach PHI reads go through the RPC (column privileges or a view; a migration).
- Whether profile basics stay visible when the assessment is gated.
- Unit preference when the profile read fails (workouts default to lb).
- "Couldn't refresh" cues for Profile and plan after a good read.
- Sign out on intake's resume-failure screen.
- A server trigger for the conversation preview.
- Brand-button contrast.

### Cycle 7: P0-FL-38, P0-FL-39, P0-FL-40 and the 184/185 owner brief (2026-11-19)

**Base.** All three packages start from the cycle-6 combined branch `integration/p0-flutter-stack-c6` @ `6f8918f` and **target it**, so each PR's diff shows one package. They depend on the cycle-6 PRs (#184–#191) being integrated first.

**Combined evidence branch.** `integration/p0-flutter-stack-c7` = `6f8918f` + `a58db40` + `6b82a6d` + `6189d19`.
- @ `df35d5f`: analyze **287**, **3335** tests pass, static guards 0, CI's 10 negative controls 0 (run locally). CI (push): **7/7** run `44497593361` on `df35d5f`.
- **Cross-package defect:** FL-38 and FL-40 conflict in `coach_copilot_screen.dart`'s import block only. Both added imports at the same place. Resolved in the combined merge commit by keeping both; the suite passes. **Whichever of #194 and #193 lands second needs the same one-line resolution.**

| PR | Package | Final head | Commits | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|---|
| #194 | **P0-FL-38** health data only through the logged route. The copilot reads goal, experience, location and injuries only via the single logged `get_client_assessment` caller, and is blocked only when that read fails (other states warn). Pending requests read `public_profiles` (no health fields or email). **Fixed the Requests-tab crash** under the live policy (every pending request crashed the tab) and the **injury parse bug** (injury areas stored as comma-joined text were never read, so every client reached the engine as uninjured) | `a58db40` | engineer ×5 rounds (4a4e70e … a58db40); lead ade875e (coordinator message) | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES (no defects; coach reads of client data reduced) · QA **VERIFIED** (crash reproduced on base) | 6/7 + 1 equivalent | 3213 | 7/7 `44492737057` |
| #192 | **P0-FL-39** writes report success only after the server confirms them: notification preferences (toggle reverted), Personal Info avatar and Save, the coach notification sheet (swipe restored, banner, guards), availability cancel (partial outcome kept visible) | `6b82a6d` | engineer bd5893b, e80ceaf, 6b82a6d | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | 9/9 | 3242 | 7/7 `44486090822` |
| #193 | **P0-FL-40** a failed read is never a role or plan fact: nine role-gated screens show loading or a profile-failure notice (fail closed, back control) instead of "Coaches only."; Manage subscription failures shown with retry; train-hub active-session failure scoped | `6189d19` | engineer 1e8bcf6, 6189d19 | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES (no gate opens on error) · QA **VERIFIED** | 12/12 | 3264 | 7/7 `44488770104` |

All final heads: analyze **287**, contract guard exit 0 (unseen 31), coordinator 268/268, static guards 0, negative controls 0.

**Lead decisions applied (decision-free readings, recorded):**
- FL-38's first version **blocked** copilot generation for clients with no completed assessment, or an injury without an area. That is a product change, so the lead restored the previous behaviour (generation allowed) with honest notices. **The stricter option is Julia's call.**
- For not-completed assessments, the answers on file are used, as before.

**Security findings (read-only, no permission or policy change):**
- After FL-37/FL-38, coach code reads no client health column from `user_profiles` except the dashboard roster's `risk_level` (left unchanged: decision).
- PHI logging is still enforced **app-side only**. The live `user_profiles` SELECT policy still lets an active coach select every column directly. Closing that needs a migration and approval.

**What the evidence covers:** automated only. No device, simulator or live-QA run. **Journey completion unchanged: 2/14, beta-ready conditions 0/4.**

**Owner decision brief:** `docs/QA_184_185_WINDOW_DECISION_BRIEF.md`.
- Option S (184 → 185) or Option R (182 → 186).
- Covers the product consequences, risks (incl. CI's ENV-3 L-2/L-5 failing on every open branch until the manifest change is merged), validation steps and a complete rollback.
- Nothing executed.

**New decisions for Julia:**
- Roster `risk_level` logging.
- Q-H1: may a coach see a pending requester's goal or email?
- Copilot blocking for incomplete or injury-without-area assessments.
- Admin copilot defaults.
- Web deep link onto a gate (no back destination).

**Engineering follow-ups:**
- `score_service.dart:114`: leaderboard crash class for a missing profile.
- `generateWorkout` and `predictClient` swallow errors.
- Sibling `valueOrNull?['role']` reads (`paywall_gate.dart:31`).
- Six gated screens start fetching before the role is known.
- The gate helper is duplicated in nine files.
- Client booking cancel copy and 0-row check.
- The load-sensitive business-profile photo test.
- Tighten FL-14's sheet-overflow test allowance (no longer needed).

### Cycle 8: P0-FL-41 to P0-FL-44 (2026-11-22)

**Base.** All four packages start from `integration/p0-flutter-stack-c7` @ `df35d5f` and **target it**, so each PR's diff shows one package.

**Combined evidence branch.** `integration/p0-flutter-stack-c8` = `df35d5f` + `e9fcb30` + `1e5199a` + `d8af61d` + `9cae07a`. All four merge without conflict.
- @ `185261e`: analyze **287**, **3456** tests pass (= 3335 + 5 + 11 + 5 + 100, so nothing overlaps or is lost), static guards 0, contract exit 0, coordinator 268/268, CI's 10 negative controls 0 (run locally).
- CI (push): **7/7** run `45100790460` on `185261e`. **No cross-package defect found.**

| PR | Package | Final head | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|
| #195 | **P0-FL-41** no crash when a client's profile is missing from a joined list. The coach Leaderboard tab crashed while building; the same crash class was fixed in the active-coaches list and coach reviews | `e9fcb30` | UX PASS-WITH-NOTES · security APPROVE · QA **VERIFIED** | per-site revert caught at all 3 sites (single-layer mutants are equivalent) | 3340 | 7/7 `45076272294` |
| #196 | **P0-FL-42** a client's booking cancel is confirmed before "Session cancelled.": `.select('id')`, plus `.eq('status','scheduled')` (lead: decision-free). 0 rows → told + reload, no coach notice; throw → reported, split copy; double-tap guarded | `1e5199a` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | 4/4 | 3346 | 7/7 `45097658625` |
| #197 | **P0-FL-43** the copilot's failed recommendation is recorded once and explained (network/other), and a stale `lastError` is never reused. **`predictClient` deliberately unchanged:** coordinator §15 pins its swallow as the SEC-R3 / Wave 3B-4 blocker awaiting the owner ruling, so the lead removed the engineer's change to it | `d8af61d` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES (agrees with the scope) · QA NOT VERIFIED → **VERIFIED** after a test round | 3/3 | 3340 | 7/7 `45098982386` |
| #198 | **P0-FL-44** a failed or stale role read is never a role fact. Paywall and app shell use `confirmedRoleRead`: a role counts only when it is read for the **current** member. Security found a **previous-member role leak** after sign-out/sign-in; fixed. The failure bar keeps Profile; paywall Back falls back to Profile. **70 transition tests:** coach↔client, the new member's read failed / in flight / succeeded, a delayed previous-member response, sign-out only | `9cae07a` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** (explicit transition matrix) | 4/4 (incl. the member-id check removed) | 3435 | 7/7 `45099911540` |

All final heads: analyze 287, contract exit 0 (unseen 31), coordinator 268/268, static guards 0, negative controls 0.

**What the evidence covers:** automated only. No device, simulator or live-QA run. **Journeys 2/14, beta-ready conditions 0/4, unchanged.**

**New decisions for Julia:**
- **SEC-R3 / Wave 3B-4 ruling** (§7.10): needed before `predictClient`, `evaluateWeek` and `regenerateProgram` can report failures. A failed copilot outlook shows nothing until then.
- **Server-side status transitions on a client's own `coaching_calls` row** (FL-42 S-1).
- **"Couldn't notify your coach" note to the client** after a cancel.

**Engineering follow-ups:**
- About 15 other screens should take the role via `confirmedRoleRead` (FL-44 F-1, P2).
- Coach-side cancel: add a status filter.
- `_SlotCard`: overflows at 320 px and 2× text.
- `_book`'s error copy.
- `coachLeaderboardProvider` live ticker mismatch.
- `coachReviewsProvider` swallows read failures.
- `coach_focus_section`: initState role race.
- `train_hub` wrong-role tile.

### Cycle 9: P0-FL-45a/45b, P0-FL-46 to P0-FL-48 (2026-11-22/23)

**Base.** All five packages start from `integration/p0-flutter-stack-c8` @ `185261e` and **target it**, so each PR's diff shows one package.

**Combined evidence branch.** `integration/p0-flutter-stack-c9` = `185261e` + `f980611` + `991192d` + `0f0c13c` + `a75650b` + `03b9369`. All five merge without conflict, and no two packages touch the same file.
- @ `1b94044`: analyze **287**, **4393** tests pass. That is 3456 + 470 + 435 + 12 + 8 + 12, so nothing overlaps or is lost. Static guards 0, contract exit 0 (unseen 31), coordinator 268/268, CI's 10 negative controls 0 (run locally).
- CI (push): ****7/7** run `45132607442` on `1b94044`**. **No cross-package defect found.**

| PR | Package | Final head | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|
| #199 | **P0-FL-45a**: one member-confirmed role gate (`core/widgets/role_gate.dart`) for the 9 role-only screens: Observability, Copilot (**gate only**), Continuous Coaching, Program Builder, Weekly Review, Review Queue, Content Center, Intelligence Review, MIE Debugger. `RoleConfirmedLoad.gate` keys each screen's loaded state to the admitted member: a same-role A→B switch clears and re-reads, and A's late answers are dropped. The denied state keeps its AppBar and back | `f980611` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA NOT VERIFIED (session isolation, coach-denied gaps) → **VERIFIED** after a review round | 8/9; the survivor is caught as a multi-layer mutant (re-key + gate-close are redundant layers) | 3926 | 7/7 `45126666339` |
| #200 | **P0-FL-45b**: the other role and profile reads count only for the member signed in now (`confirmedRoleRead`; new `confirmedProfileRead` / `confirmedCurrentProfileProvider`). **P0 found and fixed:** Personal Info Save wrote member A's details into member B's row after a sign-out/sign-in; Notifications did the same with toggles. Also: the Workout Zone unit (B's set converted with A's unit, security P2), name and avatar in the scaffold, top nav, greeting and coach dashboard, Coach Focus late answer, Settings unit save refused for another account, and Profile/Settings 2× headers | `991192d` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES (confirmed the P0 fixed) · QA NOT VERIFIED (identity-matrix gaps) → **VERIFIED** after a review round | 10/11; the survivor is the Notifications row check, a defence-in-depth layer Riverpod cannot reach | 3891 | 7/7 `45127825008` |
| #201 | **P0-FL-46**: coach `_cancelSession` adds `.eq('status','scheduled')`, so a call the client already cancelled takes the honest 0-row path and the client gets no false notice. `_book` records the failure and uses one voice: connection hint only on network failure, neutral 42501 refusal held 8s, 23505 unchanged. `_SlotCard` stacks at 2×; coach cancel failures are live regions | `0f0c13c` | UX PASS · security APPROVE-WITH-NOTES · QA **VERIFIED** | 5/5 | 3468 | 7/7 `45129070292` |
| #202 | **P0-FL-47**: `coachReviewsProvider` reports and rethrows, and the sheet says "Couldn't load reviews — …" with a busy-aware retry, scrollable at 2× (never "No reviews yet" on a failure). **Leaderboard investigation:** the ticker watched `user_scores` (written only by RPCs) while the tab reads `daily_scores`; it now ticks on `daily_scores` (published in 037, coach-readable by 100). App-only, no migration | `a75650b` | UX PASS · security APPROVE · QA **VERIFIED** | 5/5 | 3464 | 7/7 `45130262805` |
| #203 | **P0-FL-48**: `AuthButton` is announced disabled when `onTap` is null; `AuthFooterLink` gets a 44px button; the client-detail 2× overflows (8) are fixed with per-item action names and an "Add action item" label; the intake photo-step 2× overflows are fixed; 1x pins for `_GradientButton` (54px) and the score ring (72dp) | `03b9369` | UX PASS · security APPROVE-WITH-NOTES · QA **VERIFIED** | 5/6; the survivor is the ring fixed at 72dp, which the restacked layout tolerates (cosmetic) | 3468 | 7/7 `45131357900` |

All final heads: analyze 287, contract exit 0 (unseen 31), coordinator 268/268, static guards 0, negative controls 0. Mutant test lists were taken from each package's test diff.

**What the evidence covers:** automated only. No device, simulator or live-QA run. Realtime leaderboard delivery is reasoned from migrations 037 and 100, not observed. **Journeys 2/14, beta-ready conditions 0/4, unchanged.**

**Cross-package defects:** none at the combined head. Two overlaps were found and resolved during the cycle:
- the FL-45b QA flagged the 9 staff screens as the "same defect elsewhere"; these are FL-45a's scope and are fixed in the combined branch;
- FL-45b's confirmed-profile provider needed test fixtures to carry the member `id`, which the real query returns.

**New decisions for Julia:**
- **Workout Zone unit while unconfirmed** (FL-45b): should set entry lock until the member's unit is confirmed? Today it uses the existing lb default, so a metric member who types a set in that window has it stored as lb.
- **`coaching_calls` column authority** (FL-46 security #4): policy 011 is `FOR ALL` with no WITH CHECK, so either party can change any column through the API. This is pre-existing.
- **Wording of the 42501 booking refusal** (FL-46).
- **Action Center at 1x** is taller because its 44px buttons sit under the item text (FL-48).
- **"Member" label for admin/content_manager** on Profile/Settings (pre-existing).
- **How loud a role-read failure should be on Exercise Detail / Coach Focus**: today the section simply stays hidden.

**Engineering follow-ups:**
- Copilot `_explain` and `_approve` lack a session guard, so a late answer for A can land after a direct A→B swap. This was left alone because of the SEC-R3 Copilot scope limit and needs Julia's ruling.
- `activity_screen` notif_* readers and `messaging_screen:122` still read the profile without the member check.
- `CustomExerciseService` and `ai_coach_service:177` swallow read errors as null or [].
- The leaderboard doesn't tick on `coach_client_relationships`.
- `_CoachingModePage` overflows at 2×; the Compliance row at 2× is unverified.
- Pre-existing error copy on the staff screens: "Assign failed." and empty pickers on a failed read.
- `business_profile_reports_what_happened_test` and a messaging photo-upload test are flaky under full-suite load; both pass alone.

### Cycle 10: P0-FL-49 to P0-FL-52 (2026-11-23)

**Base.** All five packages start from `integration/p0-flutter-stack-c9` @ `1b94044` and **target it**, so each PR's diff shows one package.

**Combined evidence branch.** `integration/p0-flutter-stack-c10` = `1b94044` + `85d32f0` + `36fbcd2` + `7b8e5fd` + `eed4f60` + `e44588d`. All five merge without conflict, and no file is touched by two packages.
- @ `b7ec6ef`: analyze **287**, **4660** tests pass. That is 4393 + 126 + 69 + 44 + 0 + 28, so nothing overlaps or is lost. Static guards 0, contract exit 0 (unseen 31), coordinator 268/268, CI's 10 negative controls 0 (run locally).
- CI (push): ****7/7** run `45240757852` on `b7ec6ef`. **No cross-package defect found.****.

| PR | Package | Final head | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|
| #207 | **P0-FL-49**: Activity › Challenges (`notif_challenges` prompt) and Activity › Community (`notif_community` hide) read `confirmedCurrentProfileProvider`. The Messages empty state (plan pitch vs neutral) uses `confirmedRoleRead` and needs a signed-in user. Base defects: signed out with nobody signing in was pitched a plan; a same-member failed refresh dropped the pitch; A's held `notif_*` decided B's Activity. 126-test identity matrix | `85d32f0` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED**; re-verified after a test round (36 regression guards for same-member in-flight refresh and late answers while B's read failed or was in flight) | 10/10 (7 + 3 guard mutants) | 4519 | 7/7 `45235853373` |
| #208 | **P0-FL-50a**: `CustomExerciseService`, 14 swallow sites. Reads record and rethrow; best-effort reads keep their default but record; observability failed figures are "—" and never 0; deletes and approve/reject treat 0 rows as failure. **Fixed a data-loss path:** a failed Edit Exercise prefill opened a blank form whose Save overwrote the exercise. Save is now held and announced disabled until the exercise loads. One failure component (`SectionLoadFailure` + optional `detail`). KPI tiles grow with large text | `36fbcd2` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES → **PASS** · QA NOT VERIFIED (held-Save loading untested; no positive control) → NOT VERIFIED (FittedBox shrank 2× text) → **VERIFIED** after two rounds | 12/13; the survivor keeps 2 columns at 2× (tiles still grow and the text isn't shrunk; only the 1-column choice is unpinned) | 4462 | 7/7 `45238824608` |
| #205 | **P0-FL-50b**: the member AI Coach. 7 reads record and rethrow; 3 writes `.select()` and treat 0 rows as failure. Base defects: a failed persona read offered chips that saved the default over the member's real persona; a failed brief or review read **generated** a new one; a failed history read looked like a new chat. History retry orders earlier exchanges first and drops this session's duplicates | `7b8e5fd` | UX PASS-WITH-NOTES ×2 · security APPROVE-WITH-NOTES · QA NOT VERIFIED (retry ordering untested) → **VERIFIED** after a review round | 9/9 | 4437 | 7/7 `45231184605` |
| #204 | **P0-FL-51**: flaky tests. Root cause: fixed pump/runAsync budgets waited on real `dart:io` reads (`XFile.readAsBytes`) and isolate JSON decoding (`functions.invoke`), which only advance inside runAsync windows. `pumpUntil` (30 s real-time bound, zero-step pumps) waits for the outcome in 7 files. Test-only; no assertion changed | `eed4f60` | UX PASS-WITH-NOTES · security APPROVE-WITH-NOTES · QA **VERIFIED** | 5/6; the survivor is a 200 `cancel-subscription` reply without `ok:true`, which no test before or after sends (pre-existing gap) | 4393 | 7/7 `45223386821` |
| #206 | **P0-FL-52**: intake Coaching Mode at large text: the option title wraps (overflowed by 33–197px at 1.3×/2×); Continue grows instead of clipping; options and Continue carry button/selected/enabled semantics. **Compliance row at 2×:** no overflow at 1.0/1.3/2.0× on 320/390dp (pinned). Labels broke mid-word at 2×/320dp, so the tiles go 2×2 above 1.5×; each tile is announced as "Workout: 30 of 30". Action Center untouched (44px kept) | `e44588d` | UX PASS-WITH-NOTES ×2 · security APPROVE · QA NOT VERIFIED (button-height check couldn't fail) → **VERIFIED** after a review round | 8/8 (the round-1 survivor, a fixed 56px button, is caught at the final head) | 4421 | 7/7 `45233436801` |

All final heads: analyze 287, contract exit 0 (unseen 31), coordinator 268/268. `reportFailure(` still has 0 callers outside `core/observability`; `valueOrNull` in lib went 116 → 114. Mutant test lists were taken from each package's test diff.

**What the evidence covers:** automated only. No device, simulator or live-QA run. The flake fix is proven by a deterministic reproduction (photo reads held 1 s: 13 base failures → 0; edge-function replies held 600 ms: 9 → 0). Natural load didn't reproduce it within 20 runs, though the FL-49 QA full run (without the fix) hit the business-profile flake once. Real-font fit at 2× (Compliance tiles, KPI tiles, Coaching Mode) needs a device check. **Journeys 2/14, beta-ready conditions 0/4, unchanged.**

**Security and account isolation:**
- **Copilot late responses** (L1–L4): documented with a screen-only remediation proposal for Julia in `docs/COPILOT_LATE_RESPONSE_REMEDIATION_PROPOSAL.md`. L2 shows A's client explanation (PHI) to B; L3 runs an approval's remaining writes under B's session. **Not implemented**: SEC-R3 / Wave 3B-4 holds Copilot.
- **`home_screen.dart:817`** is the last decision on a held profile value (Women's Health). Protected; Julia's call.
- **`coach_business_screen.dart:189`** keeps a `select('*')` profile row in widget state that could outlive a coach switch (P2, follow-up).
- No database permission was changed and no `coaching_calls` column decision was made.

**Accessibility:** every new retry and button is ≥ 44px. No 44px target was reduced. Action Center layout options for Julia are in `docs/ACTION_CENTER_LAYOUT_OPTIONS.md` (recommended: keep).

**New decisions for Julia:**
- **Copilot late-response remediation**: option A, B or C, plus Q1 (partly created programs) and Q2 (telling the coach who left).
- **Action Center density at 1×**: option A (keep), B, C or D.
- **Unconfirmed Activity defaults** (FL-49 UX, low): while the profile read is unconfirmed, the challenge-alerts prompt is hidden and Community is shown.
- **Observability sub-reads**: telling "RPC absent" (PGRST202) apart from "failed" for the decision, certification and intelligence figures.
- **AI Coach offline**: one grouped error banner instead of up to eight section notices.

**Engineering follow-ups:**
- `getCoachOverlay` / `resolveExerciseMedia` failed reads show "Add your coaching".
- `createCoachingPack` result is ignored; `submitForGlobalLibrary` has no 0-row check; `_enrich` shows raw `res.error`; `lastError` is shared between overlapping approve and reject calls.
- A failed challenges read shows "No active challenges"; Activity "Enable" / "See All", persona and memory chips are under 44px with no button role.
- Keep the add-memory dialog open on failure.
- The intake picker `catch (_) {}` (~4123) is unrecorded; the business transformation-photo upload has no in-flight guard.
- No test sends a 200 `cancel-subscription` reply without `ok:true`.
- `_IntakeStepBar` overflows at 3× on 320dp.
- `MyExercisesNotifier.delete` has no screen caller.
- The history dedupe compares the server's `created_at` with the device clock.

### Cycle 11: P0-FL-53a/b/c, P0-FL-54, P0-FL-55 (2026-11-24)

**Base.** Verified before any branch was cut: `origin/integration/p0-flutter-stack-c10` = `b7ec6ef`, and `-c11` did not exist. All five packages start from `b7ec6ef` and **target `integration/p0-flutter-stack-c10`**, so each PR's diff shows one package. Cycle 9 and cycle 10 branches, PRs and targets were not touched.

**Combined evidence branch.** `integration/p0-flutter-stack-c11` = `b7ec6ef` + `94c3fd9` + `79b45d3` + `dcba6ae` + `ab19413` + `bf98d9a` (`--no-ff`, in that order). All five merge without conflict, and no file is touched by two packages.
- @ `f191d48`: analyze **285**, **4917** tests pass. That is 4660 + 52 + 66 + 54 + 41 + 44, so nothing overlaps or is lost. Static guards 0, contract exit 0 (unseen 31), coordinator 268/268, CI's 10 negative controls 0 (run locally). `reportFailure(` has 0 callers outside `core/observability`; `valueOrNull` in lib stays 114.
- CI (push): **7/7 success**, run `45342689729` on `f191d48`. **No cross-package defect found.**

| PR | Package | Final head | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|
| #209 | **P0-FL-53a**: exercise library. `getCoachOverlay` / `resolveExerciseMedia` record and rethrow (a missing row is still null), so Coach Focus shows `SectionLoadFailure` ("Editing is paused until it loads.") instead of "Add your coaching" and never offers saved coaching for overwrite; `_loadSeq` makes the newest read win. `createCoachingPack` and `submitForGlobalLibrary` treat 0 rows as failure. `_enrich` uses `couldntMessage` (no backend text) and a failed slug back-fill stops enrichment. A failed Save coaching keeps the sheet open with the text; a failed voice-note removal is said in the sheet | `94c3fd9` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES → **PASS** · QA VERIFIED → **VERIFIED** (r3 closed the low item and QA's mutant-9 gap) | 10/10 · 12/12 · 1/1, plus QA's 9/9 | 4712 | 7/7 `45328683630` |
| #213 | **P0-FL-53b**: Activity › Challenges: a failed read shows `SectionLoadFailure`; a failed refresh keeps the member's own earlier list ("Showing the challenges loaded earlier."); a genuine empty stays "No active challenges"; failed joins are recorded and signed-out joins throw. Booking `_load` / `_selectCoach` are recorded and blame the network only for a network failure. Staff writes: Packages delete/save, Availability publish/delete (0 rows = failure), Video Response (notification separated from save; "has been notified" only when true). Failures are said inside the sheet. Add-slot sheet and video Done view fit 320–430dp × 1.0–2.0 text | `79b45d3` | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES ×2 → **PASS** (r3) · QA VERIFIED ×2 → NOT VERIFIED (r3 overflow assertion vacuous: `byType(Flex)`) → **VERIFIED** (r4) | 13/13 · 15/15 · 6/6 | 4726 | 7/7 `45339040341` |
| #210 | **P0-FL-53c**: intake photo picker failures are recorded per source (`intake.photos.pick.camera` / `.gallery` / `.webGalleryFallback`, `intake.photos.read`) and said inline with Try again; a denied permission says so; a cancel stays silent and keeps an earlier photo; single-flight. `_IntakeStepBar` moves its label to its own line rather than shrinking pills below 3px, is announced "Step N of 24", and Skip is a 44px labelled button. FL-52's 3×/320dp exception removed | `dcba6ae` | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES → **PASS** · QA VERIFIED → **VERIFIED** | 9/9 · 9/9 | 4714 | 7/7 `45331379755` |
| #211 | **P0-FL-54**: `CoachBusinessScreen` follows sign-in. It forgets coach A's profile on a switch or sign-out before rendering; load sequence + uid drop late responses; `confirmedProfileRead` gates every apply; an ownership gate never shows A while B's read is pending or failed; a same-coach failed refresh keeps the data with Retry. Every write checks the profile shown belongs to the signed-in coach; the invite re-checks after the insert and after `send-invite-email` (security F1). Upload busy state is per coach (`_uploadingFor`, A→B→A). Tests drive real `signedIn`/`signedOut` transitions, held responses, failures and positives, not only a loading state | `ab19413` | security APPROVE-WITH-NOTES ×2 (F1 fixed) · UX PASS-WITH-NOTES ×2 · QA VERIFIED → NOT VERIFIED (single-slot upload guard; G4/G5 untested) → **VERIFIED** (r3) | 5/10 → 17/17 | 4701 | 7/7 `45334522037` |
| #212 | **P0-FL-55**: AI Coach chips. Persona chips 44px with button/selected/mutually-exclusive semantics ("Coach style: <name>") and a save guard; memory delete 44×44 "Delete memory: <text>" plus a custom semantics action, per-memory guard and spinner; "Add memory" a 44px labelled button; coach card and daily brief headers wrap. Overflow matrix 320/360/390/430dp × 1.0/1.3/2.0 with rendered text size pinned (no `FittedBox`, no shrinking). A test pins that `cancel-subscription` needs `ok: true` (kills the FL-51 survivor; no lib change) | `bf98d9a` | security APPROVE-WITH-NOTES · UX PASS-WITH-NOTES → **PASS** · QA VERIFIED → **VERIFIED** | 9/9 · 11/11, plus QA's 7/7 | 4704 | 7/7 `45336281515` |

Mutant test lists were taken from each package's test diff. **Surviving mutants at final heads: none.** The FL-51 survivor from cycle 10 (a 200 `cancel-subscription` reply without `ok:true`) is now caught by #212's test. **Flakes: none observed.** Two full runs stalled under disk pressure with 0 failures; their reruns from zero passed.

**What the evidence covers:** automated only. No device, simulator or live-QA run, and nothing here counts as manual or live verification. Real-font fit at 1.3×/2× (step bar at 320dp, chips, Add-slot sheet) needs a device check. **Journeys 2/14, beta-ready conditions 0/4, unchanged.**

**Scope held:**
- Women's Health code untouched; `home_screen.dart:817` stays out of scope.
- SEC-R3: Copilot screen, `predictClient`, `evaluateWeek`, `regenerateProgram`, the `reportFailure()` sink and the AI workout-build path untouched. The staff "Assign failed." copy lives in `coach_copilot_screen.dart`, so it stays open under SEC-R3; `continuous_coaching_screen` and `weekly_review_screen` (via `coach_program_service`) also untouched. Risk recorded, no workaround.
- No migration, QA or production write, Edge Function deploy, secret, Vault, Stripe, email-provider, app-URL or external-configuration change. No merge, no auto-merge. PR #14 untouched.
- Action Center layout unchanged; `docs/ACTION_CENTER_LAYOUT_OPTIONS.md` still awaits Julia (recommended A).

**Accessibility:** every new retry, button and chip is ≥ 44px; no 44px target was reduced; no `FittedBox` or text shrinking was added.

**New decisions for Julia:**
- **S-53a-4:** any owner can self-publish to the global library, with no moderation step.
- **Copy:** "Showing the challenges loaded earlier." and "Your response is saved, but <name> wasn't notified — let them know another way."
- **Photo permission:** an "Open Settings" action for a permanently denied permission (needs a new dependency).
- **`send-invite-email` sends to any address** (backend behaviour).
- **Signed-out business screen:** a Sign in button (routing).
- **S-55-1:** a coaching memory is deleted with one tap, no confirm or undo.

**Engineering follow-ups:**
- Unguarded `pickImage`: `progress_screen` :337/:381, `personal_info` :237, `chat_screen` :265, `ai_nutrition` :84, `ai_scan_view` :177.
- `enrichWithAI` stringifies errors; `updateExercise` doesn't record failures; S-53a-5 (`storage.remove` result ignored on voice-note clear, own package); S-53a-6 (a lost reply to a successful clear can leave "Couldn't remove" up).
- `challengeNotifierProvider` on the Challenges screen is not member-keyed (S-53b-I1).
- `package_service` has no row checks and `saveSessionTiers` can save partially; a failed `coach_packages` read has no retry; `coach_marketplace`, `choose_package_screen` `saveSchedule` and `coach_pricing_sheet` swallow failures; video record/pick have no catches; the video note field doesn't rebuild.
- `PaymentService.cancelSubscription` catch doesn't call `reportError`; `cancelCoach` message is partial with several subscriptions.
- Overflows that existed before this cycle: Availability slot cards, the video form action buttons, the Activity Performance ring at 2×. Activity Browse/Join/Log food/Explore are under 44px.
- FL-54: N7 (a refresh overwrites unsaved typed fields), the certification dialog shows A's list until closed, S1 (signed-out `cloud_off` icon), the coach-media storage policy checks only the bucket (backend).

### Cycle 12: P0-FL-56a/b, P0-FL-57a/b, P0-FL-58 (2026-11-24)

**Base.** Verified before any branch was cut: `origin/integration/p0-flutter-stack-c11` = `f191d48`, and `-c12` did not exist. #209–#213 are open and unmerged with no auto-merge, and still target `-c10`. All five packages start from `f191d48` and **target `integration/p0-flutter-stack-c11`**, so each PR's diff shows one package. Main, PR #14 and the earlier cycle branches were not touched.

**Combined evidence branch.** `integration/p0-flutter-stack-c12` is `f191d48` plus `fc32118`, `ace9295`, `feb216c`, `c959d4a` and `b1996f2`, merged `--no-ff` in that order. All five merge without conflict, and no file is touched by two packages.
- @ ``a82f993``: analyze **284**, **5557** tests pass. That is 4917 + 98 + 117 + 116 + 100 + 209 = 5557, so nothing overlaps or is lost.
- Static guards 0, contract exit 0 (unseen 31), coordinator 268/268, CI's 10 negative controls 0 (run locally).
- `reportFailure(` has 0 callers outside `core/observability`. `valueOrNull` in lib is 111 (114 at base).
- CI (push): **7/7 success**, run `45437860682` on `a82f993`. **No cross-package defect found.**

| PR | Package | Final head | Independent verdicts at the final head | Lead mutants | Tests (full) | CI (exact head) |
|---|---|---|---|---|---|---|
| #214 | **P0-FL-57a**: identity and storage. `challengeNotifierProvider`, `selectedChallengeProvider`, `myExercisesNotifierProvider` and `editingExerciseProvider` are keyed to the signed-in uid. Loads are sequenced and late responses dropped; a same-member failed refresh keeps the list. A join or progress finishing after a switch no longer awards points as B, and challenge detail gives B no feedback for A's join. Pending challenges show loading, not "No challenges here". `clearCoachVoice` checks an empty `remove()` by exact-name list (not `exists()`). `enrichWithAI` keeps the network error. `createExercise`'s slug update is 0-row checked. The exercise service records its failures, and exercise detail no longer records them twice | `fc32118` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES ×2 · QA VERIFIED ×2 | 11/11 · 11/11, plus QA's 7/7 | 5015 | 7/7 `45426409472` |
| #215 | **P0-FL-56b**: `package_service` 0-row and signed-out writes throw, and only 23503 deactivates (announced). Partial tier save names the saved and unsaved tiers. The editor waits for its tier read; a failed read used to blank prices so Save **deleted every tier**. The packages list keeps data on a failed refresh. Marketplace pauses requests while the status is unread. Choose Package records and says save, schedule-read and checkout failures, and nothing follows an unconfirmed save; a generation check stops A→B→A opening a second checkout. The view sheet reads once per opening. Pricing sheet and `cancelSubscription` record. Providers use the call form, so `per_user_provider_scope_test` sees them again | `ace9295` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES → **PASS** · QA NOT VERIFIED (tear-offs blinded the identity guard) → **VERIFIED** | 9/12 → 9/12, plus QA's 5/5 and a two-guard 1/1. Survivors: 56b-6 equivalent (exception type), 56b-8 unreachable (QA agrees), 56b-9 redundant beside the generation check | 5034 | 7/7 `45428406655` |
| #216 | **P0-FL-56a**: all seven picker sites record and say pick, read, upload and write failures. A denied permission points to Settings; cancel is silent and keeps the earlier photo; one picker opens at a time. The member is fixed before the pick and re-checked after the upload: chat no longer posts as B in A's conversation, and avatar, progress and both AI pickers drop late results for B. Cleanup sends nothing under another login and uses an exact-name list. Chat speaks in one voice. Log Meal shows its notices inline. Progress has a Refresh action. Exercise Save waits for an in-flight read | `feb216c` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES ×2 · QA VERIFIED ×2 | 9/10 → 11/11, plus QA's 9/9 | 5033 | 7/7 `45431012051` |
| #218 | **P0-FL-57b**: Business Profile. A switch closes the certification and invite dialogs (lead decision), and they open only over the signed-in coach's own profile. A same-coach refresh keeps unsaved typing, and a different coach clears everything first; this fixes the round-1 regression where A's late text saved into B's row. The uploaded photo is removed exactly once, only after a definite refusal or 0 rows, only as its owner. **No answer, or an answer that says nothing about the write, never deletes** (lead decision): network, PGRST00x/PGRSTX, 08/57P/58/XX, 40003 and any bare HTTP status. Picker failures are said | `c959d4a` | security **REJECT** (S1 regression, S2) → APPROVE-WITH-NOTES → **APPROVE** · UX PASS-WITH-NOTES ×2 · QA VERIFIED ×3 | 8/8 · 10/10 · 12/12 | 5017 | 7/7 `45435339840` |
| #217 | **P0-FL-58**: Activity, Availability, Video Response and the Coach Focus sheet. Every target is ≥ 44×44, with a label that starts with its visible words and a screen-reader tap action. The water dots are one adjustable control. No overflow at 320–430dp × 1.0/1.3/2.0/3.0; content stacks or wraps, nothing shrinks. Video Send follows the note. Record and pick failures are recorded and said; controls are disabled while uploading. Add Slot is disabled after a failed load. Fields keep accessible names. Width checks are font-independent | `b1996f2` | security APPROVE-WITH-NOTES ×2 · UX PASS-WITH-NOTES ×2 · QA VERIFIED ×2 | 10/11 → 11/11, plus QA's 8/8 | 5126 | 7/7 `45433049005` |

Mutant test lists were taken from each package's test diff. One lead mutant from round 1 (56b-6) did not compile, and the FL-56b engineer caught it; it was rewritten. **Surviving mutants at final heads:** the three FL-56b items above, each explained; none is a missed behaviour. **Flakes:** none observed. Disk fell to 220 MB once during five parallel suites; the guard cleared temp files and no run was lost.

**What the evidence covers:** automated only. No device, simulator or live-QA run; nothing here counts as manual or live verification. Real-font fit at large text, screen-reader passes and FAB clearance over a bottom inset need a device check. **Journeys 2/14, beta-ready conditions 0/4, unchanged.**

**Scope held:**
- Women's Health code untouched; `home_screen.dart:817` stays out of scope.
- SEC-R3: Copilot screen, `coach_program_service`, `predictClient`, `evaluateWeek`, `regenerateProgram`, the `reportFailure()` sink and the AI workout-build path untouched.
- No migration, QA or production write, Edge Function deploy, secret, Vault, Stripe, email-provider, app-URL or hosting change. No storage policy or backend authorization change. No merge, no auto-merge. PR #14 untouched.
- Action Center not touched.

**Accessibility:** no 44px target was reduced, and no `FittedBox`, `scaleDown` or text shrinking was added.

**Lead decisions (engineering, not product rules):**
- A switch closes the invite dialog like the certification dialog.
- An uploaded photo is never deleted after no answer or an ambiguous one; the orphan is recorded.
- After a switch, chat cleanup sends nothing under B and records it.
- Storage cleanup checks by exact-name list, never `exists()`, which reads any 400 as absent.

**New decisions for Julia:**
- **Business Profile:** the same field edited on two devices is last-write-wins with no notice.
- **Copy:** "Hidden from clients", "Can't delete a package clients are using — hidden from clients instead." and "Schedule saved. <reason>".
- **Packages:**
  - `getSessionTiers` re-offers deactivated tiers;
  - a mistyped price saves as 0 / free, and an empty name does nothing;
  - "Your coach will be notified" shows even when notification fails;
  - saving a schedule replaces one held with another coach;
  - an all-tiers transaction needs an RPC.
- **OD-57:** note-only video response Send is now reachable but still says "Video Sent!", the client notification says "video", and nothing reads `coach_video_responses`.
- **Activity water control:** keep the bars (segments about 10–13px wide on the half-width card) or use −/+ steppers.
- **Progress:** a refused progress row leaves its file in storage.

**Backend or migration (record only):**
- **Server-side challenge award** from the participant row. It closes the remaining small timing window.
- **Messages INSERT policy** (migration 003) lacks a participant check (S3).
- **Public `coach-media` bucket:** recorded orphans need a sweep.
- **Owner list/read** on own `voice/<uid>/` must survive any SELECT narrowing; pending 199 keeps it.
- **Migration 185** is not applied on QA.

**Engineering follow-ups:**
- **Account-switch sweep (57a, read-only):** `selectedWorkoutProvider` / `activeWorkoutProvider` / rest timer, `selectedConversationProvider`, intake save-on-pause, `coach_availability` / `integrations` / `coach_pricing_sheet` load-as-A-save-as-current, `whats_on` previous value, `selectedClassProvider`, the progress / check-in / AI coach / booking / tickets / pods `initState` loads, client-detail sheets, and kept-alive client/program families.
- **Exercise screens:** `create_exercise_screen` keeps A's open edit form (S-57a-2) and records some failures twice.
- **Challenges:** `challenge_card` and Activity join feedback have no member check.
- **Payments:** `startCheckout` launches its URL after a switch (payments package).
- **Progress and AI nutrition:**
  - Progress tells B about A's failed upload, and its state is not member-keyed.
  - `StorageException` hides the connection hint.
  - `AiNutritionNotifier` records nothing.
  - A missing scan calorie value reads as 0; the scan idle view overflows at 2×.
- **Activity:** shows 0 or vanishes on failed streak, nutrition and upcoming reads.
- **Shared components:** `SectionLoadFailure` Try again has no screen-reader tap action. The `coach_voice.dart` recorder and player are unnamed and long-press only.
- **Coach Business:** the invite email `catch (_)` is unrecorded.

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
18. Is $0 a valid coaching price? The Custom Price dialog accepts 0; the Pricing sheet refuses it (UX U4, #174); may a coach clear a saved price or years of experience? (#176 keeps a blank field's saved value and says so)
19. SR-4: may an active coach edit a client's profile fields at all, and which? (A none — remove the 015 policy; B an explicit allow-list; B′ block safety, consent and coach-only fields; C status quo.) No app screen uses it today.
20. Who may review a coach (any signed-in user today, with or without a relationship) — decide before the rating-rollup fix lands.
21. Multi-coach plan ownership: when a client has (or had) more than one coach, whose nutrition plan / habits win, and may a coach replace another coach's active plan? (#182 security N1)
22. Member directory scope (public_profiles has no row filter) and group-membership visibility (A status quo … D column split).
23. AI injury memories (075): keep after the field is cleared? record who wrote them? may they be sent to the model provider?
24. Is payment enforcement required server-side for coaching services (today only an active relationship is checked)?

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

**Cycle 13 recommendation (2026-11-24).** Cycle 12 is done:
- P0-FL-57a is #214, FL-56b #215, FL-56a #216, FL-57b #218 and FL-58 #217, all targeting `-c11`.
- Combined `-c12` @ `a82f993`, CI 7/7 (run 45437860682).

Decision-free work, identity and data integrity first:

1. **P0-FL-59: account-switch sweep, HIGH items (57a read-only sweep).**
   - `selectedWorkoutProvider`, `activeWorkoutProvider` and the rest timer (A's workout restored as B);
   - `selectedConversationProvider`;
   - intake save-on-pause writing A's answers as B;
   - `coach_availability`, `integrations` and `coach_pricing_sheet`, which load as A and save with the current uid;
   - the `create_exercise_screen` open edit form (S-57a-2);
   - `challenge_card` and Activity join feedback.
2. **P0-FL-60: remaining swallows.**
   - Activity streak, upcoming classes and upcoming events show 0 or vanish on failure.
   - `AiNutritionNotifier` records nothing.
   - `StorageException` connection hint.
   - Other `PaymentService` catches, and `startCheckout` after a switch.
   - Invite email `catch (_)`.
   - `coach_voice.dart` catches.
   - `create_exercise_screen` double recording.
   - Progress state keyed to the member, and its notices to B.
3. **P0-FL-61: shared accessibility.**
   - `SectionLoadFailure` Try again screen-reader tap action.
   - `coach_voice.dart` recorder and player names and roles.
   - Bell reduce-motion.
   - Scan idle view at 2×; a missing scan calorie value reads as 0.

**Blocked on Julia (read-only):**
- the **Copilot late-response remediation** (`docs/COPILOT_LATE_RESPONSE_REMEDIATION_PROPOSAL.md`, options A/B/C);
- the **SEC-R3 / Wave 3B-4 ruling** for `predictClient`, `evaluateWeek` and `regenerateProgram` (and the Copilot "Assign failed." copy);
- the **184/185 QA window** (`docs/QA_184_185_WINDOW_DECISION_BRIEF.md`);
- **Action Center density** (`docs/ACTION_CENTER_LAYOUT_OPTIONS.md`);
- Decision 19 / F1; server-side PHI read enforcement; client `coaching_calls` status transitions and column authority (011 FOR ALL);
- P0-SB-2 (Decisions 17, 18), P0-SB-3 (Decision 20) and member list (Decision 22); Decisions 21, 23 and 24;
- cycle 9 questions: the Workout Zone unit lock, the 42501 wording, the admin/content_manager "Member" label;
- cycle 10 questions: unconfirmed Activity defaults, observability PGRST202 reading, AI Coach grouped offline banner;
- cycle 11 questions: S-53a-4 global-library self-publish, the two copy lines, "Open Settings" for photo permission, `send-invite-email` to any address, a Sign in button on the signed-out business screen, S-55-1 one-tap memory delete;
- cycle 12 questions: Business Profile two-device edits, the packages copy and five packages rules, OD-57 note-only video response, the Activity water control, a refused progress row's file;
- backend (each needs a migration): server-side challenge award, messages INSERT participant check (S3), `coach-media` orphan sweep, migration 185 on QA;
- `home_screen.dart:817` (Women's Health held-profile read);
- merge order for the open stack #172–#218.
