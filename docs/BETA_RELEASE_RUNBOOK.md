# Controlled-beta release runbook

Prepared 2026-11-16 from live state (read-only). **Nothing here has been executed.** Each
section names the authorization it needs. Secrets are referred to by name only.

State at preparation: `origin/main` **8f2c8a0** (CI 7/7, run `43792727007`); `main` has **no
branch protection** — the merge gate below is the procedure; QA ledger frontier **192**, 182–186
declared excluded, 193–200 authored and pending; 1 of 19 Edge Functions deployed on QA.

---

## 1. Merge runbook (PRs #160–#169) — needs: Julia's merge authorization per PR

**Simulated:** all ten heads merged in the order below onto `8f2c8a0` with `git merge-tree`
(git 2.39) — **no textual conflict**; the result changes 45 files.

| Order | PR | Head | CI run (7/7) | Depends on | What merging changes on QA | Revert |
|---|---|---|---|---|---|---|
| 1 | #165 webhook reads current subscription | `3fa490a` | `43880220835` | — | nothing until `stripe-webhook` is deployed | `git revert -m 1` |
| 2 | #160 AI functions check the plan | `7fa984a` | `43794773571` | — | nothing until the 4 AI functions are deployed | `git revert -m 1` |
| 3 | #162 ending coaching re-reads the plan | `06fddb8` | `43798002991` | — | app build only | `git revert -m 1` |
| 4 | #163 live coach dashboard | `9d86d6a` | `43798857589` | — | app build only | `git revert -m 1` |
| 5 | #166 assigned movement brief uses the library | `6b172df` | `43881848146` | — | app build only | `git revert -m 1` |
| 6 | #161 migrations 196–197 | `029e613` | `43933430201` | — | **none** — migrations are declared pending; CI never applies them | revert (not applied) |
| 7 | #167 migration 198 | `779fe1b` | `43934713294` | #161 | none (pending) | revert (not applied) |
| 8 | #168 migration 199 + Edit gating | `c9e9277` | `43949289273` | #167 | app: Edit shows only where allowed (works before 199 too) | revert |
| 9 | #169 migration 200 | `eb20110` | `43950958877` | #168 | none (pending) | revert (not applied) |
| 10 | #164 ledger and runbooks | (latest) | read at merge time | — | docs only | revert |

**Per-PR gate (the procedure used for #139–#159):** re-read `main`; PR open at the exact head
above; exact-head CI 7/7; mergeable; auto-merge off; scope = the PR's own files;
`git merge-tree` clean against current `main`; `gh pr merge N --merge --match-head-commit <head>`.
After each merge: wait for **main CI 7/7** (Static guards; Flutter; Negative control; Live QA
suites — security, AI, Live SQL evidence incl. ENV-3 L-1..L-5; UIX-1; EC-04; I-WRK-01) and an
idle repo before the next. **Stop on the first red gate.**

Expected main CI after each migration PR: ENV-3 static lists the new version as **PENDING**;
the live ledger check still passes (frontier 192, pending versions are not expected applied);
D24-style suites gated on unapplied migrations stay **SKIPPED**, never passed.

Stacked heads: #167/#168/#169 contain their predecessors' commits; after the predecessor
merges, GitHub shows only their own diff. Do not rebase or force-push them — merge in order.

## 2. QA migration runbook — needs: an owner-approved QA window naming the exact versions

Order: **193 → 194 → 195 → 196 → 197 → 198 → 199 → 200**. 182–186 stay excluded and are a
separate, separately approved push (route A: 182→183→184→185→186, never alone).
**199 must be applied before any beta exercise or coach media is uploaded.**
Apply from `main` after the corresponding PRs merge (the files must be on `main`).

### Pre-application checks (read-only; values at preparation 2026-11-16)

| Check | Expect | Today |
|---|---|---|
| linked project ref | `eyqtldjqpgpljlqvpowh` (QA); never the production ref | QA |
| ledger max version / any of 193–200 present | 192 / none | 192 / 0 |
| `coach_client_relationships.activated_by` exists | no (193 adds it) | no |
| active relationships (become pre-193, keep access — decision 3) | report | **619** |
| pending invites (194 can redeem them) | report | 3 |
| assignments a client wrote on a program it does not own (196) | 0 | 0 |
| assignments a coach wrote on a program it does not own (197) | 0 | 0 |
| credit rows out of range (198, CHECK is NOT VALID) | 0 | 0 |
| objects in `exercise-media` / `coach-media` (199) | report | 0 / 0 |
| the 5 storage policies 199 drops exist by exact name | 5 | 5 |
| `trg_coaching_calls_client_needs_access` absent (195 creates it) | 0 | 0 |

### Application (one migration at a time, the 187–192 method)

1. Save the pre-apply definitions of every function a migration replaces (`client_plan`,
   `set_relationship_client_source`, `update_exercise_media`, `can_read_program`, the storage
   policies) — the forward-recovery source.
2. For each version: the file must end in `COMMIT;`; compose it with the ledger row
   `INSERT INTO supabase_migrations.schema_migrations(version, name, statements)` **inside the
   same transaction**; run with `supabase db query --linked -f`; stop on the first error.
3. After each: confirm its ledger row exists.

### Expected schema / policy changes and read-back

| Version | Read-back after apply |
|---|---|
| 193 | column `activated_by` + trigger `set_relationship_activated_by`; `client_plan()` ignores client-activated rows |
| 194 | function `accept_coach_invite(text)`; `set_relationship_client_source` reads `auth.users` email |
| 195 | `has_coach_guided_access(uuid,uuid)`; trigger `trg_coaching_calls_client_needs_access` |
| 196 | policies `client writes assignments only for own programs (insert|update)` (RESTRICTIVE) |
| 197 | policies `coach writes assignments only for own programs (insert|update)` (RESTRICTIVE) |
| 198 | policy `coach updates client credits` gone; constraint `client_session_credits_balance_in_range` (NOT VALID) |
| 199 | 5 old storage policies gone; `exercise-media write/overwrite/delete by exercise editor`, `coach media upload to own folder`, `coach media overwrite own folder`, `coach media read, videos by coach and client`; helpers `can_write_exercise_media`, `can_delete_exercise_media`; `update_exercise_media` uses `is_content_editor()` for platform exercises |
| 200 | `can_read_program` body contains `p.coach_id IS NULL OR p.coach_id = a.client_id` |

### Post-application verification

1. In the **same PR** that applies them: move `applied_through` to `200` and remove 193–200 from
   `pending` in `supabase/expected_applied.json` (protected path: exceptions opened and closed in
   the PR); regenerate `.skills-agent/migration-coverage.json`.
2. One CI run (one runner at a time on QA): ENV-3 L-1..L-5 pass with the new frontier; the live
   security suite's migration-gated sections become strict.
3. Replays already proven locally on QA's exact shape: `policy_193_194` 21, `integrity_187_192` 34,
   `assignment_196` 10, `credits_198` 8, `storage_199` 37, `program_history_200` 11, ownership
   matrix O1–O10.
4. App smoke on QA: invite link `?invite=` redeems (194); a client-activated relationship shows the
   paywall (193); coach Edit visible only on own/editable exercises (199).

### Failure handling and recovery

- A failed migration rolls back with its own transaction (ledger row included) — the ledger
  stays consistent; stop the window and report.
- **No point-in-time recovery** on the free tier (decision 10 open): recovery is **forward**.
  Each migration header states its reversal (drop the policies / restore the saved definition /
  drop the trigger, column or constraint); a reversal is itself a new, approved migration.
- Do not hand-edit `schema_migrations` to make a check green.

## 3. Edge Function deployment readiness — needs: deployment approval per group

All 19 declare `verify_jwt` in `supabase/config.toml` (`stripe-webhook` = false, verified by Stripe
signature; the other 18 = true). **QA today:** only `ai-nutrition` v18 is deployed (built ~2026-09-30
from the pre-rename path — not `main`'s source).

| Function | QA | Secrets (names) | Database dependencies | Caller check in code | Needs | PRs |
|---|---|---|---|---|---|---|
| ai-coach | — | ANTHROPIC_API_KEY | ai_conversations, ai_memories, client_habits, client_nutrition_plans, user_profiles, weekly_checkins, workout_sessions | JWT; plan ≥ AI-Guided (#160) | — | #160 |
| ai-coaching-engine | — | ANTHROPIC_API_KEY | ai_* tables, client_nutrition_plans, notifications, nutrition_logs; rpc ai_adjust_nutrition, ai_detect_patterns | JWT or service role; plan ≥ AI-Guided (#160) | vault for cron | #160 |
| ai-generate-workout | — | ANTHROPIC_API_KEY | ai_insights, ai_memories, ai_profiles, custom_exercises, user_profiles, workout_feedback | JWT (tier undecided — DEC 1) | — | — |
| ai-nutrition | v18 (old) | ANTHROPIC_API_KEY, ANTHROPIC_MODEL, ANTHROPIC_MAX_TOKENS | — | JWT; plan ≥ Self-Guided (#160) | redeploy from `main` | #160 |
| analyze-food-image | — | ANTHROPIC_API_KEY | — | JWT; plan ≥ Self-Guided (#160) | — | #160 |
| cancel-subscription | — | STRIPE_SECRET_KEY | coach_client_relationships, notifications, subscriptions, user_profiles | JWT, own subscription | Stripe test mode | #149 (merged) |
| create-checkout | — | STRIPE_SECRET_KEY, STRIPE_SELF_GUIDED_PRICE_ID, STRIPE_AI_GUIDED_PRICE_ID, STRIPE_COACH_STARTER/GROWTH/ELITE_PRICE_ID | coach_client_relationships, coach_packages, events, payments, platform_settings, subscriptions, user_profiles | JWT | Stripe test mode; 192 applied ✓ | — |
| create-portal-session | — | STRIPE_SECRET_KEY | user_profiles | JWT | Stripe | — |
| update-subscription | — | STRIPE_SECRET_KEY, STRIPE_SELF_GUIDED_PRICE_ID, STRIPE_AI_GUIDED_PRICE_ID | subscriptions | JWT | Stripe | — |
| stripe-webhook | — | STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET | client_session_credits, coach_client_relationships, event_registrations, notifications, payments, subscriptions, user_profiles | **Stripe signature** (verify_jwt false) | Stripe endpoint + secret | #165 |
| stripe-connect | — | STRIPE_SECRET_KEY, APP_URL | user_profiles | JWT; coach | Stripe Connect | — |
| enrich-exercise | — | ANTHROPIC_API_KEY | custom_exercises, user_profiles; rpc seed_exercise | JWT; role check | — | — |
| enrich-exercise-content | — | ANTHROPIC_API_KEY | exercises, user_profiles; rpc snapshot_exercise_content | JWT; role check | — | — |
| enrich-exercise-intelligence | — | ANTHROPIC_API_KEY | exercise_intelligence, exercises, user_profiles | JWT; coach/admin/content_manager | — | — |
| enrich-exercise-videos | — | YOUTUBE_API_KEY | exercise_videos, user_profiles | JWT; coach/admin | YouTube key | — |
| explain-decision | — | ANTHROPIC_API_KEY | decision_traces | JWT (trace scope per SEC-G11) | — | — |
| generate-communication | — | ANTHROPIC_API_KEY | communications | JWT; role check | — | — |
| send-invite-email | — | RESEND_API_KEY, EMAIL_FROM, APP_URL | user_profiles | JWT | email provider; **APP_URL must be set** (falls back to `https://12circle.app`) | — |
| send-checkin-reminder | — | RESEND_API_KEY | coach_client_relationships, notifications, user_profiles, weekly_checkins | **none — see blocker** | fix first | — |

**Deployment blocker (new finding 2026-11-16):** `send-checkin-reminder` performs no caller check.
`verify_jwt` accepts any valid project JWT — any signed-in user's (and, with the legacy JWT-format
anon key, the public anon key) — so any account could
make it notify and email **every active client**, repeatedly. Its header says it is meant for a
cron job using the service-role key. **Do not deploy it** until it refuses any caller but the
service role (the `ai-coaching-engine` pattern) — a small, decision-free code fix; not made in this
preparation round.

**Safe deployment groups (in order):**
1. **AI read-only analysis** — `explain-decision`, `ai-nutrition` (redeploy), `analyze-food-image`
   — needs #160 merged; secret present (ANTHROPIC_API_KEY).
2. **AI coaching** — `ai-coach`, `ai-coaching-engine` (#160), then set the QA vault so cron runs;
   `ai-generate-workout` after DEC 1.
3. **Content pipeline** — `enrich-exercise*`, `generate-communication` (+ YOUTUBE_API_KEY for videos).
4. **Email** — `send-invite-email` (after RESEND/EMAIL_FROM/APP_URL); `send-checkin-reminder` only
   after its caller fix.
5. **Billing** — `create-checkout`, `update-subscription`, `create-portal-session`,
   `cancel-subscription`, `stripe-webhook` (#165), `stripe-connect` — only after the Stripe
   test-mode checklist below; deploy `stripe-webhook` before the others.

Tests per group: node `plan_gate` / `current_subscription` tests (in CI), the Flutter source tests
that read function code, then the live AI suite and a manual smoke per function on QA.

## 4. Stripe test mode and email — needs: Julia (external configuration)

**Stripe test-mode checklist** (nothing configured today; no purchase of any kind until all pass):

- [ ] A Stripe account in **test mode**; confirm at the source (dashboard shows "Test mode";
      secret begins `sk_test_`) — never inferred from a name.
- [ ] QA secrets: `STRIPE_SECRET_KEY` (test), `STRIPE_WEBHOOK_SECRET` (from the QA endpoint),
      price ids `STRIPE_SELF_GUIDED_PRICE_ID`, `STRIPE_AI_GUIDED_PRICE_ID`,
      `STRIPE_COACH_STARTER_PRICE_ID`, `STRIPE_COACH_GROWTH_PRICE_ID`, `STRIPE_COACH_ELITE_PRICE_ID`;
      app define `STRIPE_PK` (test publishable key) in `dart_defines/qa.json`.
- [ ] Webhook endpoint `https://eyqtldjqpgpljlqvpowh.supabase.co/functions/v1/stripe-webhook`,
      events: `checkout.session.completed`, `customer.subscription.updated`,
      `customer.subscription.deleted` (add `invoice.paid`, `invoice.payment_failed`,
      `charge.refunded` only when handled — DEC 11).
- [ ] Test script (test cards only, test clock for time):
  1. checkout (card 4242…) → `subscriptions` row active; `client_plan()` reflects the tier;
  2. duplicate checkout → 409 `already_subscribed`;
  3. renewal (advance test clock) → `current_period_end` moves;
  4. failed renewal (card that fails on renewal) → status `past_due` (grace = DEC 11);
  5. cancel → `cancel_at_period_end` true; access until period end (decision 2);
  6. expiry (advance past period end) → `deleted` → status canceled; coaching relationship ends;
  7. refund → **not handled** (DEC 11) — record only;
  8. replay an old `updated` event after a newer one (Stripe CLI `events resend`) → state unchanged
     (#165); redeliver `checkout.session.completed` → one grant (idempotent).

**Email:** a provider key `RESEND_API_KEY`, a verified sender domain, `EMAIL_FROM` on it;
**`APP_URL` = the hosted QA web URL** (invite links are `${APP_URL}/#/signup?invite=<token>`;
unset, they point at `https://12circle.app`). Supabase Auth SMTP for confirmation/recovery mail
uses the same provider. Do not send to real customers.

## 5. Web hosting recommendation — needs: Julia (DEC 12)

Facts: the app is **Flutter web** built by CI (`flutter build web --dart-define-from-file=dart_defines/qa.json`);
output is static (`build/web`); routing uses the **hash URL strategy** (`/#/route`, no
`usePathUrlStrategy`), so **no server rewrites are needed**; `index.html` uses `$FLUTTER_BASE_HREF`;
build-time config is four defines (`APP_ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `STRIPE_PK`) —
public values, no runtime secrets. The Vercel team has no project for this app (its one similar
project is the separate Next.js product).

| Option | Deploy workflow | Env vars | Auth redirects | Domain | Rollback |
|---|---|---|---|---|---|
| **A. Vercel static (recommended)** — new project, framework "Other", deploy the CI-built `build/web` via `vercel deploy --prebuilt` from a GitHub Action | GitHub Action after main CI | none at runtime (defines baked at build) | add the URL to Supabase Auth **Site URL / Redirect URLs** | `*.vercel.app` or a QA subdomain | instant promote of a previous deployment |
| B. Cloudflare Pages | Git or direct upload of `build/web` | none at runtime | same | `*.pages.dev` / custom | rollback to a previous deployment |
| C. Firebase Hosting | `firebase deploy` from CI | none at runtime | same | `*.web.app` / custom | release history rollback |
| D. GitHub Pages | Action publishes `build/web` | none | same | `*.github.io` (private repo needs a paid plan) | redeploy an earlier commit |

**Recommendation: A** — the team already uses Vercel, SSO deployment protection is available
(keep it **on** for QA so the beta URL is not public), and prebuilt static deploys match the CI
build exactly. Whatever host: set `APP_URL` and the Supabase Auth Site URL / redirect list to the
hosted origin before inviting anyone; never point QA defines at the production project
(ENV-4/ENV-5 guards already enforce this in CI).

## 6. Native release readiness — needs: Julia (accounts, keys) and DEC 12

| Item | State | Required |
|---|---|---|
| Android signing | release build uses the **debug** key | upload keystore + `key.properties` (never committed); Play Console app `com.twelvecircle.circle_fitness` |
| iOS signing | **no development team** | Apple Developer team id, bundle `com.twelvecircle.circleFitness`, provisioning profiles |
| Deep links | **none** registered | iOS URL type / Android intent-filter for **`io.circle12.app`** — the app already sends OAuth to `io.circle12.app://login-callback`, which no platform registers, so Google/Apple sign-in cannot return to a native app; plus universal/app links for recovery and `?invite=` |
| Supabase Auth | — | add `io.circle12.app://login-callback` to Redirect URLs |
| Push | **none** (no FCM/APNs) | product scope decision; FCM project + APNs key + token storage |
| Validation without production credentials | — | debug builds on simulator/emulator against QA defines; deep-link tests with `xcrun simctl openurl` / `adb shell am start`; Android/iOS release builds can be produced **unsigned** for size/compile checks |

Native distribution is not needed for a **web-only** controlled beta (DEC 12).
