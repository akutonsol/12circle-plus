# 12 Circle Fitness — Workstream L
## Release Engineering & Environment Integrity

**Deliverable type:** audit / readiness. **No code changed. No production contact. No deployment. No migration applied or reverted. Nothing installed.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend` · **HEAD:** `39ca39c`
**Environments referenced:** QA `eyqtldjqpgpljlqvpowh` (linked project) · Production `nxdbooufqzkpslkcogxc` — **not contacted; every statement about it is inferred from repository source and marked as such.**

Companion to [`MASTER_QA_RECONCILIATION.md`](MASTER_QA_RECONCILIATION.md), [`REMEDIATION_EXECUTION_PLAN.md`](REMEDIATION_EXECUTION_PLAN.md) and [`QA_WORKSTREAM_G_APP_STORE_PRODUCTION_READINESS.md`](QA_WORKSTREAM_G_APP_STORE_PRODUCTION_READINESS.md). Workstream G is treated here as **historical evidence**: every G claim this report relies on was re-verified against current source this session, and where the tree has moved since G it is called out. This document owns the `LRE-` ID space (Workstream **L** — **R**elease / **E**nvironment). `SEC-`, `CON-`, `WRK-`, `HYG-`, `ENV-` and `REL-` IDs are referenced, never restated.

---

## 0. Method, scope and evidence marks

**Question asked:** can this repository move dev → QA → beta → production reliably, without environment cross-contamination, missing configuration, unsafe defaults, or undocumented manual steps?

Everything below was derived from repository source read this session, or from a command executed locally against the working tree. No network call was made to any Supabase project, Stripe, Apple, or any other external service, with one deliberate exception noted in §15 (a guard test that exits before its first network call).

| Mark | Meaning |
|---|---|
| **SRC** | Proven from repository source this session, cited to `file:line` |
| **EXEC** | Proven by a command run locally this session, output quoted |
| **ABSENT** | Proven not to exist by exhaustive `find` / `grep` over the tree |
| **UNVERIFIABLE** | Requires a dashboard, console or live project this workstream may not touch — converted to a gate, never asserted as fact |

**One-line answer.** No. The repository can build a QA web bundle and it can pass its own test suites, but it cannot yet *promote* anything: twenty migrations including every Phase 1 security patch exist only as untracked files in one working tree; fifteen already-shipped migrations were edited in place so production can never receive their corrections by replay; the client's default environment is production; three QA harnesses write to and delete from production; the API that holds the only Anthropic key has no deployment target in any environment; Android release builds are signed with the debug keystore; and the single CI workflow in the repository is a cron that pings production.

**Verified-positive, so it is not re-litigated below:** the runtime environment resolver, the client/server secret split, and the live security harness's production guard are all sound and tested. Details in §14.

---

## 1. Environment matrix

Four tiers are implied by the mission (dev → QA → beta → production). **Three exist**, and `beta` is not one of them.

| Dimension | dev | QA | beta | production |
|---|---|---|---|---|
| Exists as a named config | yes | yes | **no** — `staging` is an alias that resolves to `qa` ([`app_env.dart:37`](../apps/mobile/lib/core/config/app_env.dart#L37)) | yes |
| Flutter `APP_ENV` | `dev` | `qa` | — | `prod` (**and the default**, LRE-01) |
| Supabase project | none | `eyqtldjqpgpljlqvpowh` | — | `nxdbooufqzkpslkcogxc` |
| Supabase URL source | define, empty | [`qa.json`](../apps/mobile/dart_defines/qa.json) | — | **baked-in constant** [`app_env.dart:117`](../apps/mobile/lib/core/config/app_env.dart#L117) |
| Anon key source | define, empty | `qa.json` (QA-issued, ref-checked by test) | — | **baked-in constant** `app_env.dart:118` |
| Stripe publishable key | empty | **empty** (LRE-33) | — | `pk_test_51TjY6f…` — **a test-mode key** (LRE-15) |
| `API_BASE_URL` | `http://localhost:3000` | **empty** | — | **empty** (LRE-14) |
| API `APP_ENV` | `dev` (also the fallback) | `qa` | — | `prod` |
| API deployment target | local `npm run api` | **ABSENT** | — | **ABSENT** (LRE-06) |
| Edge Functions | n/a (not run locally) | UNVERIFIABLE | — | UNVERIFIABLE (LRE-13) |
| Auth redirect / OAuth allowlist | dashboard | dashboard, untracked | — | dashboard, untracked (LRE-19) |
| Keep-alive against free-tier pause | n/a | **none** (LRE-18) | — | daily cron |
| Mobile bundle ID | `com.twelvecircle.circleFitness` | **same** | — | **same** (LRE-16) |
| Seed data auto-applied on `db reset` | yes | yes | — | yes, if ever linked (LRE-35) |
| Observability | none | none | — | none (LRE-27) |

**Isolation verdict.** *Runtime* isolation is genuinely good and genuinely tested: `resolveEnvConfig` is pure, an unknown `APP_ENV` throws, `dev` and `qa` ship no backend defaults so an unconfigured QA build fails at boot rather than falling through, and [`qa_environment_isolation_test.dart`](../apps/mobile/test/unit/qa_environment_isolation_test.dart) cross-checks the `ref` claim inside the anon-key JWT against the URL so a pasted production key is caught even when the URL looks right. That work holds up.

*Everything around* the resolver is where separation fails: the default is production, the tooling is hardcoded to production, the artifacts are indistinguishable between environments, and the two projects share one bundle identifier.

---

## 2. Secret matrix

| Secret | Class | Sanctioned home | Actual home today | In git? | Per-env record? |
|---|---|---|---|---|---|
| Supabase URL (prod) | public | build define | **source constant** `app_env.dart:117` + keep-alive workflow | yes, by design | n/a |
| Supabase anon key (prod) | public, RLS-protected | build define | **source constant** `app_env.dart:118` + [`supabase-keepalive.yml`](../.github/workflows/supabase-keepalive.yml) | yes, by design | n/a |
| Supabase URL + anon key (QA) | public | build define | [`qa.json`](../apps/mobile/dart_defines/qa.json) | yes, by design | n/a |
| Stripe publishable key | public | build define | source constant `app_env.dart:120` — **test-mode key in the prod slot** | yes | **no** |
| Supabase **service_role** key | **secret** | Edge Function secret + Vault | dashboard; also read from `SERVICE_ROLE_KEY` by [`qa_self_guided.dart`](../apps/mobile/tool/qa_self_guided.dart) and [`qa_entitlements.dart`](../apps/mobile/tool/qa_entitlements.dart) — **pointed at production** | no | **no** |
| Supabase JWT signing secret | **secret** | API env `SUPABASE_JWT_SECRET` | `apps/api/.env` (untracked) | no | **no** |
| `ANTHROPIC_API_KEY` | **secret** | API env, and Edge Function secret for 9 functions | dashboard + a local `.env`; **the API that holds it runs nowhere** | no | **no** |
| `JWT_SECRET` (API's own) | **secret** | API env | `apps/api/.env` — present, and required at boot, for a dead auth stack (LRE-38) | no | **no** |
| `STRIPE_SECRET_KEY` | **secret** | Edge Function secret (6 functions) | dashboard | no | **no** |
| `STRIPE_WEBHOOK_SECRET` | **secret** | Edge Function secret | dashboard | no | **no** |
| 6 × `STRIPE_*_PRICE_ID` | config, billing-critical | Edge Function secret | dashboard | no | **no** (LRE-30) |
| `RESEND_API_KEY`, `EMAIL_FROM` | **secret** / config | Edge Function secret (3 functions) | dashboard | no | **no** |
| `YOUTUBE_API_KEY` | **secret** | Edge Function secret | dashboard | no | **no** |
| `APP_URL` | config | Edge Function secret | dashboard; defaults to `https://12circle.app` in source | no | **no** |
| Vault `project_url`, `service_role_key` | **secret** | pg_cron Vault, per project | created **by hand**, documented only inside migration 076 | no | **no** (LRE-21) |

**Verified clean (EXEC):** a repo-wide scan for `sk-ant-`, `sb_secret_`, `sk_live_`/`sk_test_`/`rk_*`, and inline `service_role` JWTs returned only test fixtures, guard-test pattern strings, and the one Stripe **publishable** key. `.env`, `.env.local` and `apps/api/.env` are all untracked and gitignored; `apps/api/.env` contains `JWT_SECRET` and `PORT` and nothing else.

**Structural gap:** 15 distinct Edge Function secrets exist with **no manifest anywhere in the repository** and no per-environment record of which are set. There is no `.env.example` for the functions tier, no `supabase/functions/.env.example`, and `config.toml` declares nothing. Standing up a second environment is a memory exercise.

---

## 3. Migration readiness

123 forward migration files, `000` through `122`, no duplicate prefixes. **`122_repin_function_search_path.sql` is new since Workstream G** (G counted through 121); it re-pins `search_path` and revokes `PUBLIC`/`anon` EXECUTE on the 15 functions that migrations 119–121 silently unpinned by `CREATE OR REPLACE`. That is a good catch and it is also a demonstration of the failure mode this section is about: a correctness property that lives in a migration is only as durable as the ledger that replays it.

### 3.1 The ledger does not exist in git (EXEC)

```
$ git status --porcelain supabase/migrations | grep '^??' | wc -l
      20
$ git status --porcelain supabase/migrations | grep '^ M' | wc -l
      15
```

- **20 untracked files**: `000_baseline_preexisting_tables.sql`, and `104` through `122`. This includes **113–118, the entire Phase 1 security remediation**, and **119–121**, the Phase 2 workout contract.
- **15 tracked files modified in place**: `001`, `002`, `003`, `009`, `076`, `080`, `083`, `084`, `086`, `087`, `090`, `091`, `096`, `097`, `102`.

`HYG-02` in `MASTER_QA_RECONCILIATION.md` reviewed the in-place edits and accepted them for a QA rebuilt from empty. That judgement is sound for QA and is not contested here. What this workstream adds is the **promotion** consequence, which HYG-02 flags for 076 only but which applies to all fifteen: **replay is not a promotion mechanism for any environment that has already run the original.**

### 3.2 What that means for production (inferred, UNVERIFIABLE)

| Migration | In-place correction | Reaches production by replay? |
|---|---|---|
| `001` | `SET search_path = public, extensions` so `gen_random_bytes` resolves | irrelevant — already applied |
| `076` | `created_at` → `started_at` in `ai_cron_generate`; **hardcoded production URL replaced by a per-project Vault lookup** | **no** — the corrected function body must be applied explicitly |
| `080` | cron/Vault parity with 076 | **no** |
| `102` | widened preconditions, team-lead/event-host readers | **no** |
| `083`,`084`,`086`,`087`,`090`,`091`,`096`,`097` | replay corrections | **no** |
| `113`–`118` | Phase 1 security | not applicable — **never committed at all** |

### 3.3 Out-of-band application path

Three dashboard-paste scripts are in the tree and are the documented mechanism by which schema historically reached the remote project:

- [`APPLY_TO_REMOTE.sql`](../supabase/APPLY_TO_REMOTE.sql) — *"PASTE THIS ENTIRE FILE INTO THE SUPABASE DASHBOARD SQL EDITOR AND RUN IT."*
- [`APPLY_MISSING.sql`](../supabase/APPLY_MISSING.sql) — *"Generated 2026-06-17 after a live audit of the remote DB (nxdbooufqzkpslkcogxc)."*
- [`APPLY_ALL.sql`](../supabase/APPLY_ALL.sql) — *"pending migrations (028 → 043)."*

Every one is idempotent, which is good practice, and every one applies schema **without writing to `supabase_migrations.schema_migrations`**. The ledger and the database diverge by construction. `000_baseline_preexisting_tables.sql` already records that 001–110 were authored against a database that pre-existed the tracked sequence.

### 3.4 Reproducibility

`config.toml` makes a QA rebuild one operation (`supabase db reset --linked`) with both seeds declared in order — genuinely good, and the comment explaining why they are listed explicitly rather than globbed is the right kind of documentation. The reproducibility caveats are: the seeds create `auth.users` at pinned UUIDs with source-committed passwords, `db reset` targets **whatever is currently linked**, and nothing guards the link target.

### 3.5 Rollback

**Zero down migrations across 123 files** (ABSENT). Forward-only, no reverse path, and per the standing project note the projects are on the free tier with no PITR (UNVERIFIABLE from repo — treat as a gate, §12).

---

## 4. Edge Function readiness

19 functions. Inventory with the secrets each requires (EXEC, extracted from `Deno.env.get` call sites):

| Function | Secrets | Auth posture | CORS |
|---|---|---|---|
| `ai-coach` | `ANTHROPIC_API_KEY`, `SERVICE_ROLE`, URL, ANON | caller JWT | `*` |
| `ai-coaching-engine` | same | caller JWT | `*` |
| `ai-generate-workout` | same | caller JWT | `*` |
| `analyze-food-image` | `ANTHROPIC_API_KEY`, URL, ANON | caller JWT | `*` |
| `enrich-exercise` | `ANTHROPIC_API_KEY`, URL, ANON | caller JWT | `*` |
| `enrich-exercise-content` | + `SERVICE_ROLE` | caller JWT | `*` |
| `enrich-exercise-intelligence` | + `SERVICE_ROLE` | caller JWT | `*` |
| `enrich-exercise-videos` | `YOUTUBE_API_KEY`, `SERVICE_ROLE` | caller JWT | `*` |
| `explain-decision` | `ANTHROPIC_API_KEY`, `SERVICE_ROLE` | caller JWT | `*` |
| `generate-communication` | `ANTHROPIC_API_KEY`, `SERVICE_ROLE` | caller JWT | `*` |
| `create-checkout` | `STRIPE_SECRET_KEY` + 4 price IDs, `SERVICE_ROLE` | caller JWT | `*` |
| `update-subscription` | `STRIPE_SECRET_KEY` + 2 price IDs, `SERVICE_ROLE` | caller JWT | `*` |
| `cancel-subscription` | `STRIPE_SECRET_KEY`, `SERVICE_ROLE` | caller JWT | `*` |
| `create-portal-session` | `STRIPE_SECRET_KEY`, `SERVICE_ROLE` | caller JWT | `*` |
| `stripe-connect` | `STRIPE_SECRET_KEY`, `APP_URL`, `SERVICE_ROLE` | caller JWT | `*` |
| `send-invite-email` | `RESEND_API_KEY`, `EMAIL_FROM`, `APP_URL`, `SERVICE_ROLE` | caller JWT | `*` |
| `notify-coach-email` | `RESEND_API_KEY`, `SERVICE_ROLE` | **no caller auth** (invoked server-side) | none |
| `send-checkin-reminder` | `RESEND_API_KEY`, `SERVICE_ROLE` | **no caller auth** (cron-invoked) | none |
| `stripe-webhook` | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SERVICE_ROLE` | **Stripe signature only** | none |

**Deployment configuration: ABSENT.** [`config.toml`](../supabase/config.toml) declares a `project_id` and two seed paths and nothing else — no `[functions.*]` block for any of the 19.

Three consequences, in order of severity:

1. **`stripe-webhook` cannot work under the CLI default.** `verify_jwt` defaults to `true`; the function reads no `Authorization` header and verifies the Stripe signature itself ([`stripe-webhook/index.ts:37-47`](../supabase/functions/stripe-webhook/index.ts#L37)). It can only be live if it was deployed by hand with `--no-verify-jwt`. That flag is a **required, undocumented, per-environment manual step** with no source-of-truth — exactly the class of thing that is remembered in the environment where it was first done and forgotten in the next one.
2. **No deployment automation and no deployment record.** Which functions are deployed to QA, which to production, and at which revision, is UNVERIFIABLE. There is no `supabase functions deploy` in any script or workflow.
3. **Dependencies are not reproducible.** Functions import from `https://esm.sh/@supabase/supabase-js@2` — a floating major — with no import map and no lock. Two deploys of identical source can resolve different library code. `stripe@16.12.0` is correctly pinned; `supabase-js@2` is not.

`APP_URL` defaults to `https://12circle.app` in source, so the checkout success/cancel and account URLs a QA-deployed function emits point at the production domain unless the secret is set per project (SRC, [`create-checkout/index.ts`](../supabase/functions/create-checkout/index.ts)).

**Positive:** the fail-closed pattern is consistent — every function reads its secrets with `?? ''` and the Stripe webhook rejects on a missing or bad signature before touching the database.

---

## 5. API readiness (NestJS)

| Dimension | State |
|---|---|
| Build | `nest build` → `dist/`. Builds clean. |
| Deployment target | **ABSENT.** No Dockerfile, docker-compose, Procfile, `fly.toml`, `vercel.json`, `render.yaml`, `app.yaml`, or `*.tf` anywhere in the tree (proven by exhaustive `find`). |
| Runtime env contract | Good — one place, [`api-config.ts`](../apps/api/src/config/api-config.ts), pure and unit-tested. `APP_ENV` authoritative, `NODE_ENV` consulted only when it names a known environment, unknown value is a hard error. |
| Required settings | `JWT_SECRET`, `SUPABASE_JWT_SECRET`, `ANTHROPIC_API_KEY`. Missing ones **warn at boot and the features 503** — fail-closed, correct. |
| Health check | **ABSENT.** `GET /` returns the literal string `Hello World!` from the unmodified Nest template ([`app.service.ts`](../apps/api/src/app.service.ts)). No version, no environment, no dependency probe, nothing to gate a deploy on or point a monitor at. |
| Auth | `SupabaseAuthGuard` verifies the caller's Supabase access token against `SUPABASE_JWT_SECRET`. Tested against missing / forged / expired / anon / service-role tokens. Sound. |
| Supabase config | `SUPABASE_URL` is informational only; the API never calls Supabase. Only the JWT secret matters. |
| CORS | `origin: config.corsOrigins.length > 0 ? config.corsOrigins : true` ([`app.setup.ts:28`](../apps/api/src/app.setup.ts#L28)) — **reflect-any-origin whenever `CORS_ORIGINS` is unset, in every environment including prod.** `CORS_ORIGINS` is not in `missingRequiredSettings`, so nothing warns. |
| Log hygiene | Good — `describeApiConfig` reduces every secret to `<set>`/`<unset>` before the boot log. |
| Dead weight | `firebase-admin`, `passport-jwt`, `bcryptjs`, a second JWT strategy, `auth.controller`, `users.controller`, and a **required** `JWT_SECRET`, none of which serve the one real endpoint. |
| Docs | `apps/api/README.md` is the unmodified NestJS scaffold, advertising `mau deploy`. There is **no root README** and no runbook. |

**The load-bearing fact:** `POST /ai/nutrition/message` is the app's flagship AI surface and the only sanctioned home for `ANTHROPIC_API_KEY`. `API_BASE_URL` is empty in `qa.json`, empty in `prod.json`, and empty in the `prod` default table. The service is therefore **unreachable in every buildable environment**, and the process that holds the key **runs nowhere**. The security architecture is correct and entirely unexercised outside tests.

---

## 6. Mobile release readiness

### iOS
| Item | State |
|---|---|
| Bundle ID | `com.twelvecircle.circleFitness` ([`project.pbxproj:385`](../apps/mobile/ios/Runner.xcodeproj/project.pbxproj#L385)) |
| Deployment target | `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (`project.pbxproj:363`) |
| Signing | `CODE_SIGN_STYLE = Automatic`; `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` (legacy); **no `DEVELOPMENT_TEAM`, no provisioning profile** |
| Entitlements | **ABSENT** — no `.entitlements` in the tree |
| Privacy manifest | **ABSENT** — no `PrivacyInfo.xcprivacy` |
| CocoaPods | **ABSENT** — no `Podfile`, no `Podfile.lock` |
| Deep links | **ABSENT** — no `CFBundleURLTypes`, no associated domains |
| Flavors / schemes | **ABSENT** — one target, one bundle ID for all environments |

G's REL-01/02/03 re-verified: still true, unchanged.

### Android
| Item | State |
|---|---|
| Application ID | `com.twelvecircle.circle_fitness` — **diverges from the iOS bundle ID** |
| Release signing | **`signingConfig = signingConfigs.getByName("debug")`** ([`build.gradle.kts:32`](../apps/mobile/android/app/build.gradle.kts#L32)), with the scaffold TODO still in place |
| Keystore | **ABSENT** — no `key.properties`, no `.jks` |
| Flavors | **ABSENT** |
| Deep links | **ABSENT** — no `android:scheme`, no App Links |

### Web
Three build scripts exist and the QA one was **executed successfully this session** (EXEC). No hosting configuration, no CDN config, no `_headers`/`_redirects`, no deploy step, and no SPA-fallback configuration in the repository.

### Cross-cutting
- **Version is static `1.0.0+1`** ([`pubspec.yaml:4`](../apps/mobile/pubspec.yaml#L4)). No build-number automation, no tagging, no changelog. Two different builds can carry identical version metadata — which, with no crash reporting, means a field report cannot be tied to a build.
- **Three display names**: iOS `Circle Fitness`, Android `circle_fitness`, in-app `12 Circle Fitness`.
- **`kReleaseMode` appears nowhere in `lib/`** (EXEC: `grep -rn kReleaseMode apps/mobile/lib` → 0 hits), while `/qa-center` and `/mie-debugger` are unconditionally registered at [`app_router.dart:204,207`](../apps/mobile/lib/core/router/app_router.dart#L204).
- **Artifacts carry every environment's configuration.** Verified empirically on the QA bundle built this session (EXEC): `build/web/main.dart.js` contains the production project ref, the production anon key **and** the production Stripe publishable key, alongside the QA values it was built with. This is not a secret leak — the credential scanner passes — but it means a build's target environment cannot be determined by inspecting the artifact, and there is no provenance marker to compensate.

---

## 7. CI/CD readiness

**One workflow exists**, and it is [`supabase-keepalive.yml`](../.github/workflows/supabase-keepalive.yml): a daily cron that curls the **production** project's PostgREST and GoTrue endpoints to prevent free-tier auto-pause.

| Gate | State |
|---|---|
| Unit / widget tests | **ABSENT from CI.** `npm test` exists and passes (§14) — manual. |
| Security regression suite | **ABSENT from CI.** `npm run test:security` exists, guards itself against production — manual, and needs QA credentials CI does not hold. |
| Client secret scan | **ABSENT from CI.** `npm run check:web-secrets` exists and passes — manual, and covers the client bundle only. |
| Lint / format | **ABSENT from CI.** |
| Build check (web / iOS / Android) | **ABSENT.** |
| Migration deploy | **ABSENT.** |
| Migration hygiene (duplicate prefix, untracked file, in-place edit of an applied migration) | **ABSENT** — and every one of those three failure modes is live in the tree right now. |
| Edge Function deploy | **ABSENT.** |
| Dependency / secret scanning | **ABSENT.** |
| Release tagging, changelog, artifact retention | **ABSENT.** |
| Deployment gates / environment protection rules | **ABSENT.** |
| Static guard: "no build without an explicit `APP_ENV`" | **ABSENT** — and the default is `prod`. |

The automation surface is therefore: *one job, whose only action is to contact production.* Every gate proposed in §12 is currently a promise.

---

## 8. QA safety

### The harnesses that are safe
[`supabase/tests/security/lib.mjs`](../supabase/tests/security/lib.mjs) is the model. It takes its target from `QA_URL`/`QA_ANON`/`QA_SERVICE`, refuses to start if any is missing, and **refuses outright if the URL contains the production ref**. Verified this session (EXEC):

```
$ npm run test:security
QA_URL, QA_ANON and QA_SERVICE must be set. See supabase/tests/security/README.md

$ QA_URL=https://nxdbooufqzkpslkcogxc.supabase.co QA_ANON=x QA_SERVICE=y node supabase/tests/security/run.mjs
REFUSING TO RUN: nxdbooufqzkpslkcogxc is the production project.
```

Both refusals happen before any network call.

### The harnesses that are not
Three Dart QA tools hardcode the **production** project URL and anon key as constants, accept no override, and carry no guard of any kind:

| Tool | Line | What it does |
|---|---|---|
| [`live_integration_test.dart`](../apps/mobile/tool/live_integration_test.dart#L15) | `:15` | CRUD round-trips across 14 modules; **14 `DELETE` calls** against `workout_sessions`, `nutrition_logs`, `community_posts`, `challenge_participants`, `class_bookings`, `event_registrations`, `action_items`, `goals`, `coach_notes`, `workout_programs`, `events`, `event_sessions` |
| [`qa_self_guided.dart`](../apps/mobile/tool/qa_self_guided.dart#L22) | `:22` | Creates a user, runs the whole Self-Guided journey, then deletes rows and — with `SERVICE_ROLE_KEY` set — **deletes the auth user via `/auth/v1/admin/users/$uid`** |
| [`qa_entitlements.dart`](../apps/mobile/tool/qa_entitlements.dart#L27) | `:27` | Admin-deletes `subscriptions` and `coach_client_relationships` rows by `user_id`, then deletes the auth user |

Their headers describe the target as "the real Supabase **dev** instance" and "the LIVE Supabase **dev** instance". The ref they point at is production. This is precisely the audit's "production scripts named QA/live" category, inverted: QA scripts aimed at production.

They authenticate as the seeded fixtures `test@12circle.app / Test1234!` and `coach@12circle.app / Coach1234!`, whose passwords are committed in [`test_accounts.sql`](../supabase/seeds/test_accounts.sql). Because the harnesses point at production, those are production credentials in source control.

`live_integration_test.dart` was **modified in this working tree during Phase 2** (the prescription-contract fix) and still targets production — the file was touched and the target was not questioned. That is the strongest argument that this is a latent trap rather than a known, managed risk.

### Other QA-safety surfaces
- `config.toml` enables seeding on `db reset`. `db reset --linked` targets whatever `supabase link` last pointed at, and `supabase/.temp/linked-project.json` — the record of that — is **tracked in git**, so the link target travels between machines as a committed diff.
- `/qa-center` and `/mie-debugger` ship in the production router (LRE-26).

---

## 9. Observability

**Nothing exists, in any tier.** Verified by dependency and source grep across `apps/mobile/pubspec.yaml`, `apps/api/package.json`, and all 19 Edge Functions:

| Capability | Mobile | API | Edge Functions | Database |
|---|---|---|---|---|
| Crash reporting | ABSENT | ABSENT | ABSENT | n/a |
| Error tracking (Sentry/Bugsnag/…) | ABSENT | ABSENT | ABSENT | n/a |
| Product analytics | ABSENT | ABSENT | ABSENT | n/a |
| Structured logging | ABSENT | Nest `Logger` → stdout, no destination | `console.log`/`console.error` → Supabase log viewer, no retention policy | n/a |
| Log aggregation | ABSENT | ABSENT | ABSENT | ABSENT |
| Uptime / synthetic monitoring | ABSENT | ABSENT | ABSENT | keep-alive cron is the only liveness signal, and only for prod |
| Alerting | ABSENT | ABSENT | ABSENT | ABSENT |
| **Audit log** | — | — | — | **ABSENT** — no audit/event/activity-log table in 123 migrations |
| Release health / adoption | ABSENT — no version telemetry, and versions aren't distinct anyway | ABSENT | ABSENT | n/a |

The audit-log gap deserves emphasis: 17 of 19 Edge Functions hold the service-role key and bypass RLS, the Stripe webhook writes subscription and payment state with it, and there is no durable record of any of those writes beyond the rows they change.

**Positive:** the API's boot-time config log is correctly redacted, and `ai-nutrition.service.spec.ts` pins that the Anthropic key never reaches a response or a log line.

---

## 10. Rollback

| Layer | Forward path | Rollback path |
|---|---|---|
| Database schema | forward-only migrations + dashboard paste scripts | **NONE.** Zero down migrations. Free tier ⇒ no PITR (UNVERIFIABLE — gate G-11). Recovery is a hand-written reverse script under incident pressure. |
| Database data | seeds (QA only) | **NONE.** No documented backup or restore procedure anywhere in the repository. |
| Edge Functions | `supabase functions deploy`, by hand | **NONE.** No version pinning, no deployment record, no previous-revision reference. Recovery means finding the prior source and redeploying by hand. |
| NestJS API | none — no deployment target | **N/A**, because there is no forward path either. |
| Web app | `flutter build web`, by hand | **NONE.** No versioned hosting configured in-repo, no immutable deploy IDs, no aliasing. |
| Mobile app | not buildable for release (LRE-07, LRE-25) | **N/A.** Note for later: store rollback is always "ship a new build", so mobile rollback is bounded by review time and depends on being able to *make* a signed build at all. |
| **Payment code** | Stripe price IDs as dashboard-held Edge Function secrets | **NONE, and invisible.** A changed price ID takes effect on the next checkout with no source-controlled record, no diff, no audit row (§9), and no way to prove after the fact what a customer was charged against. |
| Client ↔ schema coupling | — | Migration 102's own header states it breaks the community feed, class list, pods, coach reviews, check-ins and messaging for any client on an older binary. **A schema rollback would break newer clients symmetrically**, and there is no version-negotiation or feature-flag layer to soften either direction. |

---

## 11. Findings

Severity: **P0** release-blocking · **P1** must be resolved before the gate named · **P2** should be resolved · **P3** hygiene.
"Parallelizable" = can be worked concurrently with other findings without contending for the same files or decisions.

### P0

---
**LRE-01 — The Flutter client's default environment is production**
- **Severity:** P0 · **Environment:** all
- **Expected:** an unspecified environment is a build error, or resolves to the least-privileged environment.
- **Actual:** `String.fromEnvironment('APP_ENV', defaultValue: 'prod')` — any `flutter run`, `flutter build`, `flutter test` or IDE launch without `--dart-define-from-file` silently resolves to the production project, using the anon key and Stripe key baked in at `app_env.dart:117-121`.
- **Evidence:** [`app_env.dart:151`](../apps/mobile/lib/core/config/app_env.dart#L151); prod constants at `:117`, `:118`, `:120`. Codified as intended behaviour by `qa_environment_isolation_test.dart` ENV-012 ("the default run (no defines) proves it resolves to production").
- **Reproduction:** `cd apps/mobile && flutter run -d chrome` → the app connects to `nxdbooufqzkpslkcogxc`.
- **Risk:** a developer, a CI job, a new contributor, or an automated tool reads and writes production data believing it is local. This is the single highest-probability contamination path in the repository, because it requires no mistake — only an omission.
- **Remediation:** default `APP_ENV` to `dev`. Make an empty/absent `APP_ENV` in a *release* build a hard failure. Invert the ENV-012 assertion to prove the default is **not** production.
- **Release gate:** G-01 · **Product decision:** no · **Parallelizable:** yes
- **Note:** re-verified against current source; identical to G's REL-07, unchanged since.

---
**LRE-02 — Three QA harnesses are hardcoded to production and perform destructive writes**
- **Severity:** P0 · **Environment:** production
- **Expected:** every QA tool takes its target from the environment and refuses the production ref, as `supabase/tests/security/lib.mjs` does.
- **Actual:** `live_integration_test.dart:15`, `qa_self_guided.dart:22` and `qa_entitlements.dart:27` each hardcode `https://nxdbooufqzkpslkcogxc.supabase.co` plus the production anon key, with no override and no guard. Between them they issue 20+ `DELETE` calls, and two delete an `auth.users` row via the admin API when `SERVICE_ROLE_KEY` is set. Their own headers call the target "the real Supabase **dev** instance".
- **Evidence:** files cited; `grep -n "'DELETE'" apps/mobile/tool/*.dart` (20 hits); `qa_self_guided.dart:442`, `qa_entitlements.dart:320` (admin user deletion).
- **Reproduction:** `cd apps/mobile && dart run tool/live_integration_test.dart` — do **not** run this; it writes to and deletes from production.
- **Risk:** irreversible destruction of production user data by a routine QA command, with no audit trail (§9) and no restore path (§10).
- **Remediation:** repoint all three at `QA_URL`/`QA_ANON` env vars and copy `lib.mjs`'s production-ref refusal verbatim into each. Add a repo-wide static guard that fails CI on any occurrence of the production ref outside `app_env.dart`, the keep-alive workflow, and tests that assert *about* it.
- **Release gate:** G-02 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-03 — 20 migrations, including every Phase 1 security patch, are untracked**
- **Severity:** P0 · **Environment:** all
- **Expected:** every migration that has been applied to any environment is committed.
- **Actual:** `000` and `104`–`122` are untracked (`??`). This includes `113`–`118` (the SEC-01…SEC-05 remediation) and `119`–`121` (the Phase 2 workout contract).
- **Evidence:** `git status --porcelain supabase/migrations | grep '^??' | wc -l` → `20`.
- **Reproduction:** `git stash -u` or a fresh clone produces a tree with no security remediation in it.
- **Risk:** the entire security phase is one `git clean -fd` from being lost. It cannot be deployed from CI, reviewed in a PR, or applied to production, because it does not exist anywhere except this working tree.
- **Remediation:** commit them. This is the lowest-effort, highest-value action in this report.
- **Release gate:** G-03 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-04 — 15 already-shipped migrations were edited in place, so production cannot receive their corrections**
- **Severity:** P0 · **Environment:** production
- **Expected:** a defect in an applied migration is fixed by a new forward migration.
- **Actual:** `001, 002, 003, 009, 076, 080, 083, 084, 086, 087, 090, 091, 096, 097, 102` are modified in the working tree. Replay fixes a from-empty rebuild; it does nothing for an environment that already ran the originals.
- **Evidence:** `git status --porcelain supabase/migrations | grep '^ M' | wc -l` → `15`; `git diff supabase/migrations/076_ai_coaching_cron.sql`.
- **Reproduction:** apply the current tree to a database at version 122 — no statement runs; the corrections never land.
- **Risk:** production silently retains every defect these edits fix, including 076's `created_at` → `started_at` bug (which raises `ERROR: column "created_at" does not exist` on every scheduled run once Vault is configured) and 076's cross-environment cron target (LRE-09).
- **Remediation:** enumerate the semantic deltas and emit forward migration(s) `123+` carrying every one, idempotently. Keep the in-place edits for replay; do not rely on them for promotion. `MASTER_QA_RECONCILIATION.md` HYG-02 flags this for 076 only — it applies to all fifteen.
- **Release gate:** G-04 · **Product decision:** no · **Parallelizable:** partly (one owner should do the delta enumeration)

---
**LRE-05 — No CI/CD, and the only workflow contacts production**
- **Severity:** P0 · **Environment:** all
- **Expected:** tests, security suite, secret scan, build and migration hygiene run on every change; deployments are gated.
- **Actual:** one workflow exists, `supabase-keepalive.yml`, a daily production ping. No test, lint, build, migration, function-deploy, or scanning workflow.
- **Evidence:** `ls .github/workflows/` → one file (ABSENT for the rest).
- **Reproduction:** open a PR that deletes migration 118 and hardcodes a production URL in a service — nothing objects.
- **Risk:** every finding in this report was reachable precisely because nothing mechanical was watching. Without CI, the remediations here decay the same way.
- **Remediation:** a single `ci.yml` — `npm test`, `npm run check:web-secrets` on a QA web build, plus the static guards in LRE-31 — is enough to hold the line. Add QA-credentialed `test:security` as a second, environment-scoped job.
- **Release gate:** G-05 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-06 — The NestJS API has no deployment target in any environment**
- **Severity:** P0 · **Environment:** dev / QA / prod
- **Expected:** the service holding `ANTHROPIC_API_KEY` and `SUPABASE_JWT_SECRET` runs somewhere addressable per environment.
- **Actual:** no Dockerfile, docker-compose, Procfile, `fly.toml`, `vercel.json`, `render.yaml`, `app.yaml`, or Terraform anywhere in the tree. `API_BASE_URL` is empty in `qa.json`, `prod.json` and the `prod` default table.
- **Evidence:** exhaustive `find` (ABSENT); [`qa.json`](../apps/mobile/dart_defines/qa.json), [`prod.json`](../apps/mobile/dart_defines/prod.json), `app_env.dart` prod default `apiBaseUrl: ''`.
- **Reproduction:** build any environment and open the AI Nutrition Coach — `hasApiBaseUrl` is false and the feature is unavailable.
- **Risk:** the flagship AI surface is non-functional in every shippable build, and the correct, well-tested secret architecture built to support it is entirely unexercised outside the test suite.
- **Remediation:** choose a target, add its config to the repo, deploy dev and QA, set `API_BASE_URL` per environment. Add the health endpoint (LRE-23) at the same time.
- **Release gate:** G-06 · **Product decision:** **yes — D-2** (which platform, what it costs) · **Parallelizable:** yes, once D-2 is settled

---
**LRE-07 — Android release builds are signed with the debug keystore**
- **Severity:** P0 · **Environment:** production
- **Expected:** a release keystore, held outside the repo, referenced via `key.properties`.
- **Actual:** `buildTypes { release { signingConfig = signingConfigs.getByName("debug") } }`, with the Flutter scaffold TODO still above it. No `key.properties`, no `.jks`.
- **Evidence:** [`build.gradle.kts:32`](../apps/mobile/android/app/build.gradle.kts#L32).
- **Reproduction:** `flutter build appbundle --release` → an artifact signed with the debug key.
- **Risk:** Play rejects it. Worse, if a debug-signed build ever reached any distribution channel, the signing identity is a well-known key that cannot be rotated — the app would have to be republished under a new package name.
- **Remediation:** generate a release keystore, store it in the secret manager, wire `key.properties`, and fail the build when it is absent in release mode.
- **Release gate:** G-07 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-08 — No database rollback path**
- **Severity:** P0 · **Environment:** all
- **Expected:** a reverse script per risky migration, or a point-in-time restore, or both.
- **Actual:** zero down migrations across 123 files; no documented backup or restore procedure; free tier implies no PITR (UNVERIFIABLE from repo).
- **Evidence:** ABSENT (no `*down*`/`*rollback*`/`*revert*` file); standing project note on free-tier/no-PITR.
- **Reproduction:** apply 113–122 to production and attempt to undo one.
- **Risk:** the security rollout — the highest-value change pending — is a one-way door. Migration 102's own header documents that it breaks older clients on the way in; the way out is unwritten.
- **Remediation:** write reverse scripts for 113–122 and rehearse them on a QA clone. Independently, resolve whether PITR is available; if it is not, that is a product decision about the acceptable blast radius of a production migration.
- **Release gate:** G-08 · **Product decision:** **yes — D-3** (pay for PITR, or accept forward-only) · **Parallelizable:** yes

### P1

---
**LRE-09 — Migration 076 shipped a hardcoded production URL into a pg_cron job; the fix is uncommitted and production's state is unknown**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** every environment's scheduled jobs target that environment.
- **Actual:** per 076's own new header, the migration "previously hardcoded the PRODUCTION project URL… Replaying it into any non-production project silently created cron jobs that POST to PRODUCTION edge functions with a service_role bearer token." The Vault-based fix exists **only as an uncommitted in-place edit** (LRE-03, LRE-04).
- **Evidence:** `git diff supabase/migrations/076_ai_coaching_cron.sql`; `cron.schedule` at `076:106-107` and `080:124`.
- **Reproduction:** inspect `cron.job` on any project that replayed the old 076 (do not run against production).
- **Risk:** a QA project firing service-role-authenticated writes at production on a schedule — a live cross-contamination channel, not a hypothetical one. Production's current function body is UNVERIFIABLE.
- **Remediation:** commit the fix; carry it in the forward migration from LRE-04; then audit `cron.job` in each environment under explicit authorization.
- **Release gate:** G-04, G-09 · **Product decision:** no · **Parallelizable:** no (depends on LRE-04)

---
**LRE-10 — No production migration ledger**
- **Severity:** P1 · **Environment:** production
- **Expected:** a recorded, verifiable statement of which migrations production has applied.
- **Actual:** none. `000_baseline_preexisting_tables.sql` records that 001–110 were written against a pre-existing database; §3.3's paste scripts applied schema without touching `schema_migrations`; `MASTER_QA_RECONCILIATION.md` already lists two suspected prod drifts (109's trigger, Q-6's `dietary_restrictions` type).
- **Evidence:** as cited; ABSENT for any ledger artifact.
- **Reproduction:** attempt to answer "is production at 112 or 122?" from the repository alone.
- **Risk:** applying 113–122 to production is an uncontrolled operation. A migration that assumes a prior state that is not there fails mid-transaction on a database with no rollback (LRE-08).
- **Remediation:** under explicit authorization, dump production's `supabase_migrations.schema_migrations` plus a schema diff against a QA clone, commit the reconciliation as a dated artifact, and derive the production rollout from it.
- **Release gate:** G-09 · **Product decision:** no · **Parallelizable:** no (must precede any production migration)

---
**LRE-11 — Dashboard-paste scripts are a sanctioned out-of-band schema path**
- **Severity:** P1 · **Environment:** production
- **Expected:** one application mechanism, ledger-recorded.
- **Actual:** `APPLY_TO_REMOTE.sql`, `APPLY_MISSING.sql` and `APPLY_ALL.sql` instruct the operator to paste SQL into the Supabase SQL Editor. `APPLY_MISSING.sql`'s header names the production ref.
- **Evidence:** file headers quoted in §3.3.
- **Reproduction:** n/a — historical practice, still present and still runnable.
- **Risk:** guarantees ledger/database divergence; is the most likely explanation for the drift in LRE-10.
- **Remediation:** move them to `supabase/archive/` with a header stating they are historical and must not be run, and make `supabase db push` (or a CI job) the only sanctioned path.
- **Release gate:** G-09 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-12 — `stripe-webhook` requires a deploy flag that no config declares**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** `[functions.stripe-webhook] verify_jwt = false` in `config.toml`.
- **Actual:** `config.toml` declares no `[functions.*]` block at all. `verify_jwt` defaults to `true`; the function reads no `Authorization` header and verifies the Stripe signature itself, so it works only if deployed by hand with `--no-verify-jwt`.
- **Evidence:** [`config.toml`](../supabase/config.toml) (6 non-comment lines); [`stripe-webhook/index.ts:37-47`](../supabase/functions/stripe-webhook/index.ts#L37).
- **Reproduction:** `supabase functions deploy stripe-webhook` with the tree as-is, then send a Stripe test event — it is rejected before reaching the handler.
- **Risk:** payment reconciliation silently stops in whichever environment the manual flag was forgotten. Subscriptions are created in Stripe and never recorded in Supabase; entitlements diverge from billing.
- **Remediation:** declare `verify_jwt` explicitly for all 19 functions in `config.toml` — `false` for `stripe-webhook`, and deliberately for the two cron/server-invoked functions, `true` everywhere else.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-13 — No Edge Function deployment automation or per-environment deployment record**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** functions deployed from CI at a known revision, per environment.
- **Actual:** no deploy step in any script or workflow; no record of which of the 19 are live where.
- **Evidence:** ABSENT; `package.json` scripts.
- **Reproduction:** attempt to determine from the repo which function revision is serving production.
- **Risk:** source and deployed behaviour drift invisibly; a security fix in a function's source is not evidence it is live; there is no rollback reference (§10).
- **Remediation:** add a deploy workflow keyed on environment, and record the deployed git SHA per function.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-14 — `API_BASE_URL` is unset everywhere, and the boot check fails open on it**
- **Severity:** P1 · **Environment:** dev / QA / prod
- **Expected:** a setting declared required is required.
- **Actual:** `missingSettings()` lists `API_BASE_URL` ([`app_env.dart:99`](../apps/mobile/lib/core/config/app_env.dart#L99)), but the boot guard tests `canInitialiseSupabase`, which ignores it ([`main.dart:19`](../apps/mobile/lib/main.dart#L19)). The app starts and the AI Nutrition Coach is silently unavailable.
- **Evidence:** as cited; `qa.json` and `prod.json` both have `"API_BASE_URL": ""`.
- **Reproduction:** `npm run build:web:qa`, open the app, open AI Nutrition Coach.
- **Risk:** a feature ships disabled without anyone being told, in production, with no telemetry (§9) to reveal it.
- **Remediation:** once LRE-06 gives the API a home, set `API_BASE_URL` per environment and make the boot guard assert `missingSettings().isEmpty` in release builds.
- **Release gate:** G-06 · **Product decision:** no · **Parallelizable:** no (depends on LRE-06)

---
**LRE-15 — The production Stripe publishable key is a test-mode key**
- **Severity:** P1 · **Environment:** production
- **Expected:** the `prod` slot holds `pk_live_…`.
- **Actual:** `_prodStripePublishableKey = 'pk_test_51TjY6f…'`.
- **Evidence:** [`app_env.dart:120-121`](../apps/mobile/lib/core/config/app_env.dart#L120).
- **Reproduction:** read the constant; confirm the mode in the Stripe dashboard (outside this workstream).
- **Risk:** exactly one of two things is true, and both matter. Either production is running Stripe in test mode — no real money has moved, and every subscription record is fictitious — or the constant is wrong and Embedded Checkout in production is initialised against test mode while the Edge Functions use live secret keys, which fails at checkout. This is the audit's "test keys labeled prod" category, confirmed present.
- **Remediation:** determine the intended mode, then either supply `pk_live_…` via the build define or record explicitly that production is deliberately in test mode until launch.
- **Release gate:** G-11 · **Product decision:** **yes — D-1** (is production live-billing yet?) · **Parallelizable:** yes

---
**LRE-16 — No build flavors; one bundle identifier for every environment**
- **Severity:** P1 · **Environment:** QA, beta, production
- **Expected:** per-environment application IDs (`…circleFitness.qa`, `.beta`) so builds coexist and are attributable.
- **Actual:** one iOS target, one bundle ID, one Android applicationId, no flavors, no schemes.
- **Evidence:** `project.pbxproj:385`; `build.gradle.kts` `applicationId`; ABSENT for flavors.
- **Reproduction:** install a QA build over a prod build on one device — same app, same keychain, same shared prefs, silent replacement.
- **Risk:** a tester cannot hold QA and production side by side; cached sessions and local state cross environments on-device; crash and analytics data (once they exist) cannot be separated; TestFlight cannot host distinct QA and beta tracks.
- **Remediation:** add `dev`/`qa`/`beta`/`prod` flavors with suffixed IDs and display names, wired to the matching `dart_defines` file so environment and identity cannot disagree.
- **Release gate:** G-12 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-17 — "beta" is not an environment**
- **Severity:** P1 · **Environment:** beta
- **Expected:** the promotion path dev → QA → beta → production has four configurations.
- **Actual:** three exist. `AppEnvironment.tryParse` maps `staging` onto `qa`, and there is no beta project, no beta define file, no beta API target.
- **Evidence:** [`app_env.dart:30-46`](../apps/mobile/lib/core/config/app_env.dart#L30); `ls apps/mobile/dart_defines/` → `dev.json`, `qa.json`, `prod.json`.
- **Reproduction:** attempt to build for beta.
- **Risk:** beta testers necessarily run either a QA build (fixture data, seeded accounts, `/qa-center` exposed) or a production build (real data, unpatched security defects per `MASTER_QA_RECONCILIATION.md` §6). Neither is a beta.
- **Remediation:** decide what beta *is* — a third Supabase project, or production data behind a flagged build — then give it a config identity either way.
- **Release gate:** G-12 · **Product decision:** **yes — D-4** · **Parallelizable:** no (blocked on D-4)

---
**LRE-18 — QA has no keep-alive; only production does**
- **Severity:** P1 · **Environment:** QA
- **Expected:** the environment QA depends on stays awake.
- **Actual:** `supabase-keepalive.yml` pings `nxdbooufqzkpslkcogxc` (production) daily. Nothing pings `eyqtldjqpgpljlqvpowh`.
- **Evidence:** [`supabase-keepalive.yml`](../.github/workflows/supabase-keepalive.yml) `env:` block.
- **Reproduction:** leave QA idle seven days.
- **Risk:** the QA project auto-pauses mid-cycle. Every live security suite, every harness, every QA build stops working, and the failure looks like a regression rather than an outage.
- **Remediation:** parameterise the workflow over both projects, or add a QA job. Trivial change; note it makes the workflow's production contact explicit and reviewable rather than incidental.
- **Release gate:** G-05 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-19 — Auth redirect and OAuth configuration is untracked, and mobile has no return path**
- **Severity:** P1 · **Environment:** all
- **Expected:** `site_url` and `additional_redirect_urls` declared per environment in `config.toml`; a registered URL scheme or associated domain for device builds.
- **Actual:** `config.toml` declares no `[auth]` section. The client passes `redirectTo: kIsWeb ? Uri.base.origin : null` for password reset and `_oauthRedirect` for Google/Apple. No `CFBundleURLTypes`, no `android:scheme`, no associated domains.
- **Evidence:** [`auth_service.dart:50,58-67`](../apps/mobile/lib/features/auth/data/auth_service.dart#L50); [`forgot_password_screen.dart:37`](../apps/mobile/lib/features/auth/presentation/forgot_password_screen.dart#L37); ABSENT for URL schemes; `config.toml`.
- **Reproduction:** on web, serve a QA bundle from a host not in QA's allowlist and request a password reset. On device, start Sign in with Apple.
- **Risk:** the allowlist is dashboard-managed and unreviewable, so QA and production drift silently and a new QA host breaks auth with no source change to point at. On device, the primary sign-in path and password reset have no way back into the app. Corroborates G's REL-08 — re-verified, unchanged.
- **Remediation:** declare `[auth]` `site_url` and `additional_redirect_urls` per environment in config; register a URL scheme and associated domain; pass a non-null `redirectTo` on device.
- **Release gate:** G-12, G-13 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-20 — 15 Edge Function secrets with no manifest and no per-environment record**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** a checked-in manifest of required function secrets, and a record of which are set where.
- **Actual:** neither exists. Discovered for this report by extracting `Deno.env.get` call sites (§4).
- **Evidence:** §4 table; ABSENT for any manifest.
- **Reproduction:** stand up a new Supabase project from this repo and try to make the functions work.
- **Risk:** standing up beta, or rebuilding QA, or migrating production, silently omits a secret. Functions fail closed, which is good, but they fail *quietly*, and with no alerting (§9) the first signal is a user report.
- **Remediation:** commit `supabase/functions/.env.example` enumerating all 15 with per-function annotations, plus a script that diffs it against `supabase secrets list` for a given project.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-21 — pg_cron Vault secrets are a hand-run, per-project step documented only inside a migration**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** a documented, checklisted environment-setup step, verifiable after the fact.
- **Actual:** `select vault.create_secret(…)` for `project_url` and `service_role_key`, run by hand per project. The only documentation is a comment block in `076`.
- **Evidence:** `076_ai_coaching_cron.sql` header; `cron.schedule` at `076:106-107`, `080:124`.
- **Reproduction:** rebuild QA and check whether daily briefs generate.
- **Risk:** the functions fail closed with a notice (correct design), so three scheduled AI features are simply absent with no error surfaced anywhere. Conversely, pasting production's values into QA re-creates LRE-09 by hand — and the comment has to warn against exactly that, which tells you how easy it is.
- **Remediation:** add a `supabase/ENVIRONMENT_SETUP.md` runbook, and a verification query that asserts both secrets exist and `project_url` matches the current project.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-22 — API CORS reflects any origin whenever `CORS_ORIGINS` is unset, in every environment**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** an explicit allowlist is mandatory outside `dev`.
- **Actual:** `origin: config.corsOrigins.length > 0 ? config.corsOrigins : true`. `CORS_ORIGINS` is absent from `missingRequiredSettings`, so nothing warns at boot.
- **Evidence:** [`app.setup.ts:28`](../apps/api/src/app.setup.ts#L28); [`api-config.ts` `missingRequiredSettings`](../apps/api/src/config/api-config.ts).
- **Reproduction:** boot with `APP_ENV=prod` and no `CORS_ORIGINS`; any origin is reflected.
- **Risk:** any web page can invoke the AI endpoint from a victim's browser. The bearer token is not a cookie, so this is not classic CSRF, but it removes an intended layer and makes the deployment posture depend on an env var nobody is reminded about. `.env.example` calls empty "acceptable for local dev only" — the code does not enforce that.
- **Remediation:** require a non-empty `CORS_ORIGINS` when `environment !== 'dev'`, and add it to `missingRequiredSettings`.
- **Release gate:** G-06 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-23 — No health or readiness endpoint on the API**
- **Severity:** P1 · **Environment:** all
- **Expected:** `GET /health` reporting version, environment and dependency readiness.
- **Actual:** `GET /` returns `Hello World!` from the untouched Nest scaffold.
- **Evidence:** [`app.service.ts`](../apps/api/src/app.service.ts), [`app.controller.ts`](../apps/api/src/app.controller.ts).
- **Reproduction:** `curl localhost:3000`.
- **Risk:** no deployment gate can verify a rollout succeeded, no load balancer can route on health, no monitor can alert, and no one can confirm which build and environment is serving.
- **Remediation:** add `GET /health` returning `{ status, environment, version, missingSettings }` — reusing `describeApiConfig`, which is already redaction-safe.
- **Release gate:** G-06 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-24 — Static version, no release tagging, no changelog**
- **Severity:** P1 · **Environment:** all
- **Expected:** an incrementing build number per artifact, a git tag per release, a changelog.
- **Actual:** `version: 1.0.0+1` fixed in `pubspec.yaml`; no tags in the log; no `CHANGELOG.md`.
- **Evidence:** [`pubspec.yaml:4`](../apps/mobile/pubspec.yaml#L4); `git log --oneline -20`.
- **Reproduction:** build twice from different commits — identical version metadata.
- **Risk:** artifacts are not identifiable. With no crash reporting (LRE-27) and no provenance in the bundle (LRE-32), a field report cannot be tied to a build at all. Store uploads additionally reject duplicate build numbers.
- **Remediation:** derive the build number in CI, tag releases, and keep a changelog.
- **Release gate:** G-05, G-12 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-25 — iOS release surface does not exist**
- **Severity:** P1 · **Environment:** production
- **Expected:** a signable, archivable target.
- **Actual:** no `DEVELOPMENT_TEAM`; legacy `CODE_SIGN_IDENTITY = "iPhone Developer"`; no entitlements file; no `PrivacyInfo.xcprivacy`; no `Podfile`.
- **Evidence:** `project.pbxproj:349,363,385,397`; exhaustive `find` (ABSENT).
- **Reproduction:** `flutter build ipa`.
- **Risk:** no iOS artifact can be produced at all, so no iOS release gate can even be attempted.
- **Remediation:** owned by Workstream G (REL-01/02/03), whose remediation stands. Re-verified unchanged this session; recorded here only because it blocks the release path this workstream audits.
- **Release gate:** G-12 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-26 — Internal QA screens ship in the production router**
- **Severity:** P1 · **Environment:** production
- **Expected:** debug surfaces compiled out of release builds.
- **Actual:** `/qa-center` and `/mie-debugger` registered unconditionally; `kReleaseMode` appears **nowhere** in `lib/`.
- **Evidence:** [`app_router.dart:204,207`](../apps/mobile/lib/core/router/app_router.dart#L204); `grep -rn kReleaseMode apps/mobile/lib` → 0 hits (EXEC).
- **Reproduction:** navigate to `/qa-center` in a production web build.
- **Risk:** internal tooling reachable by any user who guesses a URL; on web, no authentication step stands between them and the route table. Corroborates G's REL-06 — re-verified, unchanged.
- **Remediation:** gate both routes on `!kReleaseMode` or on an admin role check performed at route level, and add a test asserting they are absent from a release-mode route table.
- **Release gate:** G-13 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-27 — No observability anywhere**
- **Severity:** P1 · **Environment:** all
- **Expected:** crash reporting and error tracking at minimum, before any external tester touches the app.
- **Actual:** nothing in any tier — see §9's matrix.
- **Evidence:** dependency grep over `pubspec.yaml`, `apps/api/package.json`, all 19 functions (ABSENT).
- **Reproduction:** cause a crash in a QA build; nothing records it.
- **Risk:** beta produces no usable signal. A production incident is invisible until a user reports it, and then undiagnosable because there are no logs, no traces, and no way to identify the build (LRE-24, LRE-32).
- **Remediation:** one error-tracking SDK across client, API and functions, with the environment and release tagged on every event — which requires LRE-16 and LRE-24 to be meaningful.
- **Release gate:** G-14 · **Product decision:** **yes — D-5** (vendor, cost, data-residency) · **Parallelizable:** yes

---
**LRE-28 — No audit log**
- **Severity:** P1 · **Environment:** all
- **Expected:** a durable record of privileged actions.
- **Actual:** no audit, event-log or activity-log table in 123 migrations. 17 of 19 functions hold the service-role key and bypass RLS; the Stripe webhook writes subscription and payment state with it.
- **Evidence:** ABSENT; §4 table.
- **Reproduction:** ask who changed a user's role, or what a customer was charged against, last Tuesday.
- **Risk:** no forensics after a security incident, no billing dispute evidence, no way to detect misuse of the service-role key — which is the key with the widest blast radius in the system.
- **Remediation:** an append-only `audit_log` table written by the service-role paths (role changes, subscription mutations, admin operations), with RLS permitting no client reads.
- **Release gate:** G-14 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-29 — No rollback for Edge Functions, the API, or the web app**
- **Severity:** P1 · **Environment:** QA, production
- **Expected:** a previous known-good revision reachable in one operation per layer.
- **Actual:** none — see §10.
- **Evidence:** ABSENT.
- **Reproduction:** attempt to revert a bad function deploy.
- **Risk:** every deploy is one-way; recovery is "find the old source and redeploy by hand", under incident pressure, with no record of what the old revision was (LRE-13).
- **Remediation:** record the deployed git SHA per layer per environment; prefer a host with immutable deploys and aliasing for the web app; keep the previous function source reachable by tag.
- **Release gate:** G-15 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-30 — Payment configuration has no source-controlled record and no rollback**
- **Severity:** P1 · **Environment:** production
- **Expected:** price IDs versioned per environment; billing-affecting changes reviewable.
- **Actual:** six `STRIPE_*_PRICE_ID` values live only as dashboard-held function secrets. No manifest (LRE-20), no audit row (LRE-28), no deployment record (LRE-13).
- **Evidence:** §4 table; `create-checkout/index.ts`, `update-subscription/index.ts`.
- **Reproduction:** change a price ID secret — checkout prices change on the next request with no diff anywhere.
- **Risk:** an unreviewable, unloggable, silent change to what customers are charged, in the layer with the least visibility in the system. Compounded by LRE-15: which Stripe mode production is in is itself unresolved.
- **Remediation:** commit a per-environment price-ID manifest (IDs are not secrets), diff it against the live secrets in CI, and write every subscription mutation to the audit log.
- **Release gate:** G-11, G-15 · **Product decision:** **yes — D-1** · **Parallelizable:** yes

---
**LRE-31 — No static guards on the failure modes that are currently live**
- **Severity:** P1 · **Environment:** all
- **Expected:** CI mechanically rejects the mistakes this audit found.
- **Actual:** no guard against a production ref outside its three sanctioned homes; no guard against an untracked or duplicate-prefixed migration; no guard against modifying an already-committed migration; no guard requiring an explicit `APP_ENV`.
- **Evidence:** ABSENT; each corresponding failure mode is present in the tree today (LRE-01, LRE-02, LRE-03, LRE-04).
- **Reproduction:** all four conditions hold right now and nothing reports them.
- **Risk:** the remediations above regress the moment attention moves on.
- **Remediation:** four small shell checks in the CI job from LRE-05. Each is a handful of lines and each pins a P0.
- **Release gate:** G-05 · **Product decision:** no · **Parallelizable:** yes

### P2

---
**LRE-32 — Every environment's configuration is compiled into every artifact; no provenance marker**
- **Severity:** P2 · **Environment:** all
- **Expected:** an artifact contains its own environment's configuration, and states which environment it is.
- **Actual:** the per-environment default table is a runtime map, so dart2js retains all three entries. **Verified empirically (EXEC):** the QA bundle built this session contains the production ref, the production anon key and the production Stripe publishable key. No `APP_ENV` marker is emitted anywhere in the artifact.
- **Evidence:** `grep -rl nxdbooufqzkpslkcogxc apps/mobile/build/web` → `main.dart.js`; same for `pk_test_51TjY6f`. `dart_defines/README.md` documents and accepts this.
- **Reproduction:** `npm run build:web:qa && grep -c nxdbooufqzkpslkcogxc apps/mobile/build/web/main.dart.js`.
- **Risk:** not a secret leak — the scanner passes and these values are public by design. The real cost is that a bundle's target cannot be determined by inspection, so a mis-deployed artifact is undetectable, and LRE-01's default-to-prod has no artifact-level tripwire.
- **Remediation:** emit `APP_ENV` and the build SHA into a `build-info.json` or a `<meta>` tag beside the bundle, and add a CI check that a QA artifact declares `qa`. Optionally make the default table a `const` selected at compile time so unused entries tree-shake.
- **Release gate:** G-12 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-33 — QA carries no Stripe publishable key, so QA does not exercise the production payment path**
- **Severity:** P2 · **Environment:** QA
- **Expected:** QA exercises the same checkout path as production.
- **Actual:** `STRIPE_PK` is `""` in `qa.json`, so `hasStripeKey` is false and the app silently falls back to hosted redirect checkout instead of Embedded Checkout.
- **Evidence:** [`qa.json`](../apps/mobile/dart_defines/qa.json); [`app_env.dart:75`](../apps/mobile/lib/core/config/app_env.dart#L75).
- **Reproduction:** start a checkout in a QA build; observe the hosted redirect.
- **Risk:** the payment path QA certifies is not the one production runs. Embedded Checkout ships untested.
- **Remediation:** set a QA (test-mode) publishable key in `qa.json`, or make the fallback loud in non-prod.
- **Release gate:** G-11 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-34 — Supabase CLI link state is tracked in git**
- **Severity:** P2 · **Environment:** all
- **Expected:** `.temp/` is local state.
- **Actual:** `.gitignore` contains `**/.temp/`, but eight files under `supabase/.temp/` were tracked before that rule existed, so it has no effect on them. `linked-project.json` and `pooler-url` are committed and currently show as modified.
- **Evidence:** `git ls-files supabase/.temp` → 8 files; `.gitignore`.
- **Reproduction:** `supabase link --project-ref <other>` → a committable diff to the shared link target.
- **Risk:** the destructive commands in this repo (`db reset --linked`, seeded) act on the link target. Distributing that target through git means one commit can silently repoint everyone's local tooling.
- **Remediation:** `git rm -r --cached supabase/.temp` (files stay on disk; nothing is destroyed) so the existing ignore rule takes effect.
- **Release gate:** G-16 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-35 — Seeding is enabled and unguarded against the link target**
- **Severity:** P2 · **Environment:** QA, production
- **Expected:** fixture seeding cannot reach production.
- **Actual:** `[db.seed] enabled = true` with two seed files; `db reset --linked` targets whatever is linked (LRE-34). The seeds create `auth.users` at pinned UUIDs with source-committed passwords.
- **Evidence:** [`config.toml`](../supabase/config.toml); [`test_accounts.sql`](../supabase/seeds/test_accounts.sql).
- **Reproduction:** do not reproduce. Read `config.toml` and `git ls-files supabase/.temp`.
- **Risk:** `db reset --linked` against production would be catastrophic and is one mislink away. The explicit `project_id = "eyqtldjqpgpljlqvpowh"` in `config.toml` is a real mitigation — it is not a guard.
- **Remediation:** add a wrapper script that reads `.temp/project-ref`, refuses the production ref, and is the only documented way to reset.
- **Release gate:** G-16 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-36 — 16 of 19 Edge Functions send `Access-Control-Allow-Origin: *`**
- **Severity:** P2 · **Environment:** QA, production
- **Expected:** origins scoped per environment.
- **Actual:** a shared `corsHeaders` constant with `'*'` in 16 functions.
- **Evidence:** EXEC grep across `supabase/functions/*/index.ts`.
- **Reproduction:** preflight any function from any origin.
- **Risk:** same shape as LRE-22 — every function is invocable from any page in a signed-in user's browser. Bounded by the fact that a valid JWT is still required, but the browser supplies one.
- **Remediation:** derive allowed origins from an `ALLOWED_ORIGINS` function secret per environment.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-37 — Edge Function dependencies are not reproducible**
- **Severity:** P2 · **Environment:** QA, production
- **Expected:** pinned versions or an import map with a lock.
- **Actual:** `https://esm.sh/@supabase/supabase-js@2` — a floating major — across all functions. No `deno.json`, no import map, no lock. `stripe@16.12.0` is correctly pinned.
- **Evidence:** EXEC grep of function imports.
- **Reproduction:** deploy the same source twice across a `supabase-js` release.
- **Risk:** identical source produces different behaviour; a rollback to a prior source does not roll back the dependency. Compounds LRE-29.
- **Remediation:** pin exact versions and add a `deno.json` import map committed to the repo.
- **Release gate:** G-10 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-38 — A dead parallel auth stack ships in the deployable and inflates the secret surface**
- **Severity:** P2 · **Environment:** all
- **Expected:** the deployable contains what it uses.
- **Actual:** `firebase-admin`, `passport-jwt`, `bcryptjs`, a second JWT strategy, `auth.controller`, `users.controller`, and a `JWT_SECRET` that `missingRequiredSettings` marks **required** — none of which serve `POST /ai/nutrition/message`, the one real endpoint, which is guarded by `SupabaseAuthGuard`.
- **Evidence:** [`package.json`](../apps/api/package.json); `src/auth/`; [`api-config.ts` `missingRequiredSettings`](../apps/api/src/config/api-config.ts).
- **Reproduction:** boot without `JWT_SECRET` — a warning fires for a stack nothing calls.
- **Risk:** a second credential to provision, rotate and leak in every environment; a second authentication path to review; a larger image and dependency-scanning surface for no functional return.
- **Remediation:** decide whether the register/login stack is product direction. If not, remove it and drop `JWT_SECRET` from the required set. If yes, that is D-2's scope.
- **Release gate:** G-06 · **Product decision:** **yes — D-2** · **Parallelizable:** yes

---
**LRE-39 — Three product names and divergent platform identifiers**
- **Severity:** P2 · **Environment:** production
- **Expected:** one product name; matching identifiers where practical.
- **Actual:** iOS `Circle Fitness`, Android `circle_fitness`, in-app `12 Circle Fitness`; `com.twelvecircle.circleFitness` vs `com.twelvecircle.circle_fitness`.
- **Evidence:** `Info.plist`, `AndroidManifest.xml`, `main.dart`, `build.gradle.kts`.
- **Reproduction:** compare the three.
- **Risk:** `circle_fitness` is a scaffold artifact that would ship as a user-visible app name. Divergent IDs complicate deep links, OAuth client registration and store setup.
- **Remediation:** settle the display name once and apply it across all three; fix them in the same change as LRE-16's flavors, since both touch the same files.
- **Release gate:** G-12 · **Product decision:** **yes — D-6** (the canonical store name) · **Parallelizable:** yes

---
**LRE-40 — Secret scanning is manual and covers only the client bundle**
- **Severity:** P2 · **Environment:** all
- **Expected:** every commit and every artifact scanned.
- **Actual:** `check_web_build_secrets.sh` and `client_secret_hygiene_test.dart` are good and both pass — but they are manual, and they scan the Flutter client only. Nothing scans the API image, the Edge Function sources, or the git history.
- **Evidence:** [`check_web_build_secrets.sh`](../apps/mobile/tool/check_web_build_secrets.sh); `package.json` scripts; ABSENT for CI.
- **Reproduction:** commit a key into a function and push.
- **Risk:** the tier holding the most secrets — Edge Functions, 15 of them — has the least scanning.
- **Remediation:** run both in CI (LRE-05) and add a history/tree-wide scanner covering all three tiers.
- **Release gate:** G-05 · **Product decision:** no · **Parallelizable:** yes

---
**LRE-41 — No root README and no runbook; the API README is the stock scaffold**
- **Severity:** P2 · **Environment:** all
- **Expected:** a top-level orientation document and an environment runbook.
- **Actual:** no root README. `apps/api/README.md` is the unmodified NestJS template advertising `mau deploy`. The genuinely good documentation that exists — [`docs/qa-environments.md`](qa-environments.md), [`dart_defines/README.md`](../apps/mobile/dart_defines/README.md), [`supabase/tests/security/README.md`](../supabase/tests/security/README.md) — is discoverable only if you already know it is there.
- **Evidence:** `ls README*` → none; `apps/api/README.md`.
- **Reproduction:** clone and try to determine how to run anything.
- **Risk:** every manual step in this report is tribal knowledge. That is the mechanism by which LRE-12, LRE-21 and LRE-35 become incidents.
- **Remediation:** a root README indexing the existing docs, plus `supabase/ENVIRONMENT_SETUP.md` collecting the per-project manual steps (Vault, function secrets, `verify_jwt`, auth redirect URLs).
- **Release gate:** G-16 · **Product decision:** no · **Parallelizable:** yes

### P3

---
**LRE-42 — Fixture credentials are committed in source**
- **Severity:** P3 standalone, **P0 in combination with LRE-02** · **Environment:** QA, production
- **Expected:** fixture passwords generated per run, or held as CI secrets.
- **Actual:** `test@12circle.app / Test1234!`, `coach@12circle.app / Coach1234!`, and `p1-*@qa.12circle.test / P1-Probe-*-2026!` are committed.
- **Evidence:** [`test_accounts.sql`](../supabase/seeds/test_accounts.sql); [`lib.mjs`](../supabase/tests/security/lib.mjs) `IDENT`.
- **Reproduction:** read the files.
- **Risk:** low while these identities exist only in QA. **Not low today**, because the three harnesses in LRE-02 authenticate as `test@`/`coach@` against **production** — which means, if those accounts exist there, publicly-committed production credentials.
- **Remediation:** fix LRE-02 first. Then generate fixture passwords per run, or hold them as CI secrets, and confirm these identities do not exist in production.
- **Release gate:** G-02 · **Product decision:** no · **Parallelizable:** no (ordered after LRE-02)

---

## 12. Release gates

Each gate is a mechanical condition. A gate is met when its check passes in CI, not when someone believes it is true.

| Gate | Blocks | Condition |
|---|---|---|
| **G-01** | any build | `APP_ENV` defaults to `dev`; a release build without an explicit environment fails. (LRE-01) |
| **G-02** | any QA run | No production ref appears outside `app_env.dart`, the keep-alive workflow, and tests asserting about it; all three Dart harnesses take their target from env and refuse production. (LRE-02, LRE-42) |
| **G-03** | any promotion | `git status --porcelain supabase/migrations` is empty. (LRE-03) |
| **G-04** | production migration | Every in-place correction to an applied migration is carried by an idempotent forward migration ≥ 123. (LRE-04, LRE-09) |
| **G-05** | any release | CI exists and runs: `npm test`, QA web build + `check:web-secrets`, and the four static guards. QA keep-alive is live. (LRE-05, LRE-18, LRE-24, LRE-31, LRE-40) |
| **G-06** | AI feature in any env | API has a deployment target, a health endpoint, enforced CORS outside dev, and `API_BASE_URL` is set per environment. (LRE-06, LRE-14, LRE-22, LRE-23, LRE-38) |
| **G-07** | Android release | Release keystore wired via `key.properties`; debug signing fails a release build. (LRE-07) |
| **G-08** | production migration | Reverse scripts exist for 113–122 and have been rehearsed on a QA clone; PITR status resolved. (LRE-08) |
| **G-09** | production migration | Production `schema_migrations` dumped and reconciled against source; paste scripts archived. **G-04 and G-08 must both be met first.** (LRE-10, LRE-11) |
| **G-10** | function deploy | `verify_jwt` declared per function; secrets manifest committed and diffed; deps pinned; deploy automated with a recorded SHA; Vault runbook written. (LRE-12, LRE-13, LRE-20, LRE-21, LRE-36, LRE-37) |
| **G-11** | any billing traffic | Stripe mode resolved per environment; price-ID manifest committed and diffed; QA exercises the production checkout path. (LRE-15, LRE-30, LRE-33) |
| **G-12** | beta distribution | Flavors with per-environment IDs; beta defined and configured; build numbers automated; artifacts carry provenance; iOS release surface exists; one product name. (LRE-16, LRE-17, LRE-24, LRE-25, LRE-32, LRE-39) |
| **G-13** | beta distribution | `/qa-center` and `/mie-debugger` absent from release builds; auth redirect config declared per environment and mobile has a return path. (LRE-19, LRE-26) |
| **G-14** | beta distribution | Error tracking live in all three tiers, tagged by environment and release; audit log in place. (LRE-27, LRE-28) |
| **G-15** | production launch | A documented, rehearsed rollback for each layer: database, functions, API, web, payment config. (LRE-29, LRE-30) |
| **G-16** | — hygiene | `.temp` untracked; reset wrapper guards the link target; root README and environment runbook exist. (LRE-34, LRE-35, LRE-41) |

**Ordering.** G-03 → G-04 → G-08 → G-09 is a strict chain and it is the critical path to the production security rollout. G-01, G-02, G-05 are independent, cheap, and should land first because they stop the bleeding. G-06, G-07, G-10, G-11, G-12 parallelize freely once their product decisions are settled.

---

## 13. Product decisions required

These cannot be resolved by engineering and are **not** decided here.

| ID | Decision | Why it is a product decision | Blocked work |
|---|---|---|---|
| **D-1** | Is production billing live, or deliberately in Stripe test mode until launch? | The `prod` slot holds a `pk_test_` key. Either real money has never moved, or the constant is wrong. Determines whether existing subscription records are real. | LRE-15, LRE-30, LRE-33 · G-11 |
| **D-2** | Where does the NestJS API run, and does the dead auth stack stay? | Platform choice carries recurring cost and an ops commitment; keeping register/login is a product direction, not a cleanup. | LRE-06, LRE-14, LRE-22, LRE-23, LRE-38 · G-06 |
| **D-3** | Is forward-only acceptable for production, or is PITR being paid for? | Determines the acceptable blast radius of every production migration, starting with the security rollout. | LRE-08 · G-08 |
| **D-4** | What *is* beta — a third Supabase project with its own data, or production data behind a flagged build? | Testers currently must run either a fixture-laden QA build or an unpatched production build. Neither is a beta, and the choice is about who sees whose data. | LRE-17 · G-12 |
| **D-5** | Which observability vendor, at what cost, with what data-residency posture? | Health and fitness data implies a privacy review of anything that leaves the device. | LRE-27 · G-14 |
| **D-6** | What is the canonical product name in the stores? | `Circle Fitness` / `circle_fitness` / `12 Circle Fitness` are all shipping today. | LRE-39 · G-12 |

Two decisions already recorded by Workstream G remain open and gate the same path: **G's D-1** (Stripe vs. In-App Purchase for digital subscriptions) and the account-deletion / moderation compliance work. They are referenced, not re-decided.

---

## 14. Tests

### Executed this session

| Command | Result |
|---|---|
| `npm run test:api` | **PASS** — 8 suites / 58 unit tests, then 2 suites / 6 e2e tests. Exit 0. |
| `cd apps/mobile && flutter test` | **PASS** — 623 tests. Exit 0. |
| `npm run build:web:qa` | **PASS** — exit 0, 85 files emitted. |
| `npm run check:web-secrets` | **PASS** — "No server secrets in 'build/web' (85 files scanned)." |
| `npm run test:security` (no credentials) | **Refused correctly** — "QA_URL, QA_ANON and QA_SERVICE must be set." No network call. |
| `node supabase/tests/security/run.mjs` with `QA_URL` set to the production ref | **Refused correctly** — "REFUSING TO RUN: nxdbooufqzkpslkcogxc is the production project." Guard fires before any network call. |
| `grep -rl nxdbooufqzkpslkcogxc apps/mobile/build/web` | `main.dart.js` — the QA bundle carries production strings (LRE-32, as documented). |
| `grep -rn kReleaseMode apps/mobile/lib` | 0 hits (LRE-26). |
| `git status --porcelain supabase/migrations` | 20 untracked, 15 modified (LRE-03, LRE-04). |

**Nothing was skipped and nothing failed.** The suites that exist are healthy. That is precisely the point of §7: they are healthy and they are not wired to anything.

### Tests that do not exist and should

| Proposed | Pins |
|---|---|
| `APP_ENV` unset ⇒ resolves to `dev`, and a release build without it fails | LRE-01 |
| No production ref outside its three sanctioned homes | LRE-02 |
| `git status --porcelain supabase/migrations` is empty | LRE-03 |
| No tracked migration modified relative to its merge-base | LRE-04 |
| No duplicate migration prefix; the sequence is contiguous | migration hygiene |
| Release-mode route table contains neither `/qa-center` nor `/mie-debugger` | LRE-26 |
| Every function in `supabase/functions/` has an explicit `verify_jwt` in `config.toml` | LRE-12 |
| Every `Deno.env.get` name appears in the committed function-secret manifest | LRE-20 |
| Committed price-ID manifest matches the live secrets for the target environment | LRE-30 |
| A built artifact declares its `APP_ENV` and build SHA | LRE-32 |
| API boots with `APP_ENV=prod` and empty `CORS_ORIGINS` ⇒ hard failure | LRE-22 |
| `GET /health` returns environment, version and readiness | LRE-23 |

---

## 15. Production-contact statement

**Production Supabase project `nxdbooufqzkpslkcogxc` was not contacted at any point during this workstream.**

- No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it.
- No migration was applied, reverted, or pushed to any project.
- `supabase` CLI commands that contact a project were not run. The linked project remains `eyqtldjqpgpljlqvpowh` (12Circle QA), unchanged.
- No Edge Function was deployed anywhere.
- No Stripe, Apple, Google, Resend, YouTube or Anthropic API was called.
- The three Dart harnesses identified in LRE-02 were **read, never executed**, precisely because they target production.
- **One deliberate near-contact, disclosed in full:** `supabase/tests/security/run.mjs` was invoked once with `QA_URL` set to the production URL, to verify its refusal guard. The process exited with the refusal message before constructing any request. `QA_ANON` and `QA_SERVICE` were set to the literal placeholders `x` and `y`; no production credential was present in the environment. This was the test of the guard, not a use of the harness.
- Every statement about production's live state in this report is marked **UNVERIFIABLE** and inferred from repository source alone.

**Working tree preserved.** Nothing was reset, stashed, discarded, reverted or overwritten. No migration was renamed, deleted or edited. No tracked file was modified. The only filesystem writes were `apps/mobile/build/web/` (gitignored build output, from `npm run build:web:qa`) and this report.
