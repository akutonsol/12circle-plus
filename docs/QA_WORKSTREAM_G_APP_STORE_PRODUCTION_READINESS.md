# 12 Circle Fitness — Workstream G
## App Store, TestFlight & Production Readiness

**Deliverable type:** readiness / discovery / architecture. **No code changed. No production contact. No production writes. Nothing submitted to Apple.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments referenced:** QA `eyqtldjqpgpljlqvpowh` (source-of-truth for applied migrations) · Production `nxdbooufqzkpslkcogxc` **not contacted; state inferred from repository source only.**

Companion to [`MASTER_QA_RECONCILIATION.md`](MASTER_QA_RECONCILIATION.md) and [`REMEDIATION_EXECUTION_PLAN.md`](REMEDIATION_EXECUTION_PLAN.md). Canonical defect IDs (`SEC-`, `CON-`, `WRK-`, `HYG-`, `ENV-`) are defined there and are **referenced, not restated**. This document introduces its own ID space, `REL-`, for release-surface findings that no other workstream owns.

---

## 0. Method and evidence base

Every finding below was derived from repository source read this session. Where a claim could be proven mechanically (a podspec minimum, a missing file, a hardcoded constant) it is cited to `file:line`. Where a claim depends on state I am not permitted to inspect — production Supabase, the Apple Developer account, the Stripe dashboard, the Supabase dashboard's auth/function settings — it is marked **UNVERIFIABLE FROM REPO** and converted into a checklist item rather than asserted as fact.

| Mark | Meaning |
|---|---|
| **SRC** | Proven from repository source this session |
| **ABSENT** | The artifact does not exist in the tree (proven by exhaustive find) |
| **UNVERIFIABLE FROM REPO** | Requires dashboard/console access outside this workstream's authority |

Two structural facts frame everything that follows, and both were proven rather than assumed:

1. **This is a web application today.** `apps/mobile/build/` contains `web/`, `macos/`, and test artifacts — **no `ios/` output has ever been produced** (SRC). The only build scripts in `package.json` are `build:web:dev|qa|prod`. There is no iOS or Android build script, no `Podfile`, no `Podfile.lock`, no `Pods/`, and the `pod` binary is not installed on this machine (SRC).
2. **The authoritative QA documents contain no App Store, TestFlight, mobile-release, or production-infrastructure workstream.** `MASTER_QA_RECONCILIATION.md` §0 records that four of six claimed workstreams left no report; none of the six covered release surface. Workstream G is therefore a **first statement of result**, not a re-test. There is no prior baseline to regress against.

**Reported explicitly, as instructed:** there is no updated feature blueprint in the repository. `docs/product-bible.md` (July 2026) and `docs/movement-intelligence-engine.md` remain the only authoritative product documents, and neither addresses distribution, pricing mechanics on iOS, or launch. No requirement in this document is invented; anything that would require inventing product policy is escalated in §10 instead.

---

## 1. Current state

### 1.1 One-line summary

The product is a functioning web application with a mature Supabase backend and a large, mostly-complete feature surface. **The iOS release surface does not exist yet** — not "is incomplete", does not exist: no signing identity, no entitlements, no CocoaPods integration, no deep-link configuration, no privacy manifest, no in-app account deletion, no App Store-compliant purchase path, and internal QA tooling wired into the production router. Separately, **there is no CI, no CD, no deployment target for the API, and no observability in any environment.** Production Supabase carries the unpatched P0 security defects that QA has already been patched for.

Distance to TestFlight is measured in weeks of release engineering, not days of polish. Distance to App Store approval additionally depends on two product-authority decisions (§10) that no amount of engineering can settle.

### 1.2 Mobile client — as configured

| Surface | State | Evidence |
|---|---|---|
| Framework | Flutter 3.44.4 stable, Dart, Riverpod, go_router (93 routes) | SRC |
| iOS bundle ID | `com.twelvecircle.circleFitness` | [`project.pbxproj:385`](../apps/mobile/ios/Runner.xcodeproj/project.pbxproj#L385) |
| Android app ID | `com.twelvecircle.circle_fitness` — **diverges from iOS** | [`build.gradle.kts`](../apps/mobile/android/app/build.gradle.kts) |
| Display name | iOS `Circle Fitness`; Android `circle_fitness`; in-app title `12 Circle Fitness` — **three different names** | [`Info.plist`](../apps/mobile/ios/Runner/Info.plist), AndroidManifest, [`main.dart`](../apps/mobile/lib/main.dart) |
| Version | `1.0.0+1` in pubspec, wired through `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)` | [`pubspec.yaml:4`](../apps/mobile/pubspec.yaml#L4) |
| iOS deployment target | **13.0** | [`project.pbxproj:363`](../apps/mobile/ios/Runner.xcodeproj/project.pbxproj#L363) |
| Signing | `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "iPhone Developer"`, **no `DEVELOPMENT_TEAM`, no provisioning profile** | SRC |
| Entitlements | **ABSENT** — no `.entitlements` file exists in the project | ABSENT |
| Privacy manifest | **ABSENT** — no `PrivacyInfo.xcprivacy` | ABSENT |
| Permission strings | Microphone, speech recognition, camera, photo library (read + add) — all present and purpose-specific | [`Info.plist`](../apps/mobile/ios/Runner/Info.plist) |
| Deep links / URL types | **ABSENT** — no `CFBundleURLTypes`, no associated domains | ABSENT |
| App icons | Custom 1024×1024, 8-bit RGB, **no alpha channel** (App Store-valid) | SRC |
| Orientation | iPhone permits portrait + both landscapes | SRC |
| Push | Local notifications only (`flutter_local_notifications ^18.0.1`). No FCM/APNs, no push entitlement | SRC |
| Crash reporting / analytics | **ABSENT** — no Sentry, Crashlytics, PostHog, Amplitude, or equivalent in `pubspec.yaml` | ABSENT |

### 1.3 Backend — as configured

- **Supabase:** 122 forward migrations, `000` through `121`, no duplicate prefixes, **no down/rollback migrations anywhere** (SRC). `000_baseline_preexisting_tables.sql` documents that migrations 001–110 were written against a database that already existed — the tracked sequence is a patch stream over untracked history.
- **Edge Functions:** 19 functions, requiring **15 distinct environment secrets** across them (`SUPABASE_SERVICE_ROLE_KEY` in 17 of 19, `ANTHROPIC_API_KEY` in 9, `STRIPE_SECRET_KEY` in 6, `RESEND_API_KEY` in 3, plus six Stripe price IDs, `APP_URL`, `YOUTUBE_API_KEY`, `EMAIL_FROM`).
- **`supabase/config.toml` declares almost nothing** — a project ref and two seed paths. No `[auth]`, no `site_url`, no `additional_redirect_urls`, no `[functions.*]` blocks, no email template config, no storage config. **All auth and function configuration is dashboard-managed and therefore untracked, unreviewed, and unreproducible between QA and production.**
- **Storage:** four buckets. `avatars`, `coach-media`, and `exercise-media` are **public** (`public = true`); `progress-photos` is private with owner-scoped RLS.
- **Cron/Vault:** two migrations (`076`, `080`) schedule pg_cron jobs that read `project_url` and `service_role_key` from Vault. Per `076`'s own comments these secrets are created **by hand, per project**.
- **API (NestJS 11):** one real feature — `POST /ai/nutrition/message`, guarded by `SupabaseAuthGuard`. It also carries an **entirely separate, parallel auth stack**: `firebase-admin`, a custom JWT strategy with `JWT_SECRET`, `bcryptjs`, `auth.controller`, `users.controller`.
- **Stripe:** Checkout (hosted redirect) + Connect + Billing Portal via Edge Functions. Five purchase kinds: `self_guided` ($29/mo), `ai_guided` ($59/mo), `coach` (client→coach recurring), `coach_plan` (coach→platform, three tiers), `event_ticket` and `package` (one-time).

### 1.4 Pipeline and operations — as configured

There is **one** GitHub Actions workflow: [`supabase-keepalive.yml`](../.github/workflows/supabase-keepalive.yml), a daily cron that pings **production** to prevent free-tier auto-pause.

That is the entire automation surface. **ABSENT:** test workflow, lint workflow, build workflow, migration-deploy workflow, Edge Function deploy workflow, secret scanning, dependency scanning, release tagging, changelog, any deployment configuration for the API (no Dockerfile, no `fly.toml`, no `vercel.json`, no `render.yaml`, no `Procfile`), uptime monitoring, alerting, error tracking, log aggregation, and any documented restore or rollback procedure.

---

## 2. Blockers

A **blocker** here means: this cannot ship past the named gate until it is resolved, and no workaround exists.

### 2.1 Blockers to producing *any* iOS build

| ID | Blocker |
|---|---|
| **REL-01** | No CocoaPods integration and no CocoaPods installation. `flutter_local_notifications 18.0.1` and `record 7.1.1` ship no `Package.swift`, so Swift Package Manager alone cannot resolve the plugin graph — CocoaPods is mandatory for this dependency set. |
| **REL-02** | `mobile_scanner 6.0.11` declares `s.platform = :ios, '15.5.0'`; the project declares `IPHONEOS_DEPLOYMENT_TARGET = 13.0`. `pod install` will fail outright on the first attempt. |
| **REL-03** | No `DEVELOPMENT_TEAM`, no entitlements file, no provisioning profile, and a legacy `"iPhone Developer"` signing identity. An archive cannot be produced or uploaded. |

### 2.2 Blockers to TestFlight distribution

| ID | Blocker |
|---|---|
| **REL-04** | **No in-app account deletion.** App Store Guideline 5.1.1(v) makes this mandatory for any app that supports account creation. Worse: [`help_center_screen.dart:45`](../apps/mobile/lib/features/settings/presentation/help_center_screen.dart#L45) instructs users to "Go to Profile → Settings → Account → Delete Account" — **a path that does not exist** — and the privacy policy screen makes the same promise. This is simultaneously a compliance blocker and a false in-app statement. |
| **REL-06** | Internal QA tooling is wired unconditionally into the shipping router: `/qa-center` ([`app_router.dart:207`](../apps/mobile/lib/core/router/app_router.dart#L207)) and `/mie-debugger` ([`app_router.dart:204`](../apps/mobile/lib/core/router/app_router.dart#L204)). Neither is gated by `kReleaseMode` or a role check at the route level. |
| **REL-07** | **`APP_ENV` defaults to `prod`.** [`app_env.dart:151`](../apps/mobile/lib/core/config/app_env.dart#L151) — any build invoked without `--dart-define-from-file` silently resolves to the production Supabase project and its baked-in credentials at [`app_env.dart:117-121`](../apps/mobile/lib/core/config/app_env.dart#L117-L121). The safe default is inverted. |
| **REL-08** | **Password reset and OAuth have no return path on iOS.** [`auth_service.dart:50,60,67`](../apps/mobile/lib/features/auth/data/auth_service.dart#L50) and [`forgot_password_screen.dart:37`](../apps/mobile/lib/features/auth/presentation/forgot_password_screen.dart#L37) pass `redirectTo: kIsWeb ? … : null`. With no `CFBundleURLTypes` and no associated domain, a device build cannot complete either flow. Sign in with Apple and Google Sign-In are both in `pubspec.yaml`, so this affects the primary sign-in path, not an edge case. |

### 2.3 Blockers to App Store *approval*

| ID | Blocker |
|---|---|
| **REL-05** | **Digital subscriptions sold through Stripe.** `self_guided` ($29/mo) and `ai_guided` ($59/mo) are digital content/services delivered inside the app; Guideline 3.1.1 requires In-App Purchase, and `checkout_launcher.dart` redirects out to hosted Stripe Checkout. `coach` (client pays a human coach) has a plausible 3.1.3(e) person-to-person-services argument; `ai_guided` and `self_guided` almost certainly do not. **This is the single largest architectural item between the product and iOS distribution.** See §10 D-1 — it is a product decision with an engineering consequence, not an engineering choice. |
| **REL-16** | **No report / block / moderation surface for user-generated content.** The app ships community and 1:1 messaging (`lib/features/community/`, `lib/features/messaging/`), but an exhaustive search found no report-content, block-user, or mute affordance anywhere in `lib/`. Guideline 1.2 requires a content filter, a report mechanism, a block mechanism, a published EULA, and a documented 24-hour response commitment. |
| **REL-17** | **No hosted Privacy Policy URL, Terms URL, or Support URL.** Privacy policy and terms exist only as in-app Flutter screens; App Store Connect requires publicly reachable URLs. Edge Functions default their redirect targets to `https://12circle.app/payment-success` and `/payment-cancel` ([`create-checkout/index.ts`](../supabase/functions/create-checkout/index.ts)), implying a domain that this workstream cannot confirm is live or owned. **UNVERIFIABLE FROM REPO.** Settings also exposes Privacy Policy and Help Center but **not** Terms of Service, though the screen exists. |

### 2.4 Blockers to production launch (independent of Apple)

| ID | Blocker |
|---|---|
| **REL-20** | **No CI/CD of any kind.** No automated test gate, no build gate, no migration deployment, no function deployment, no secret scanning. `npm test`, `npm run test:security`, and `npm run check:web-secrets` all exist and are all manual. Every release gate proposed in §7 is currently a promise, not a mechanism. |
| **REL-21** | **Production carries the unpatched P0 security defects.** `MASTER_QA_RECONCILIATION.md` §6 records that SEC-01 through SEC-05 are properties of the migration source and are therefore live in production. Migrations 113–121 close them **on QA only**. This is the highest-severity item in the entire program and it belongs to Workstreams D/E; Workstream G's contribution is that **no production rollout may precede it**. |
| **REL-22** | **No production migration-history reconciliation and no rollback path.** Forward-only migrations, no down scripts, a documented pre-existing baseline (`000`), and at least two known or suspected production drifts (migration 109's trigger; Q-6's `dietary_restrictions` column type). Applying 113–121 to production without first reconciling history is an uncontrolled operation. |
| **REL-23** | **The NestJS API has no deployment target in any environment.** No container, no platform config, and `API_BASE_URL` is empty in both `qa.json` and `prod.json`. The AI Nutrition Coach — the app's flagship AI surface — is non-functional in every buildable environment. This also means the Anthropic key's only sanctioned home is a process that is not running anywhere. |

---

## 3. Readiness issues by priority

`REL-01`…`REL-23` above are restated here by severity with their remediation, followed by everything not severe enough to be a blocker.

### 3.1 P0 — must be closed before TestFlight

| ID | Area | Issue | Remediation |
|---|---|---|---|
| **REL-01** | iOS build | CocoaPods integration absent; CocoaPods not installed | Install CocoaPods on the build machine; run `flutter build ios --config-only` to generate the `Podfile`; commit `Podfile` and `Podfile.lock` |
| **REL-02** | iOS build | `mobile_scanner 6.0.11` needs iOS 15.5; project targets 13.0 | Raise `IPHONEOS_DEPLOYMENT_TARGET` to **16.0** (covers every plugin with headroom, and 16.0 is a defensible floor for a 2026 launch); set the matching `platform :ios` in the `Podfile` |
| **REL-03** | Signing | No team, no entitlements, no profile, legacy identity | Enrol/confirm the Apple Developer Program team; create App ID `com.twelvecircle.circleFitness`; add `Runner.entitlements` with Sign in with Apple and Associated Domains; set `DEVELOPMENT_TEAM`; adopt `CODE_SIGN_IDENTITY = "Apple Development"`/`"Apple Distribution"` |
| **REL-04** | Apple 5.1.1(v) | No account deletion; in-app help text and privacy policy both claim it exists | Build the deletion flow end-to-end: confirmation UI → an authenticated `SECURITY DEFINER` RPC or Edge Function that cancels Stripe subscriptions, deletes storage objects, deletes the `auth.users` row (FK cascades), and records an audit entry. Until it ships, **correct the false help-center and privacy-policy text** |
| **REL-05** | Apple 3.1.1 | Digital subscriptions sold via Stripe redirect | **Blocked on decision D-1 (§10).** Engineering paths: (a) IAP via StoreKit 2 for `self_guided`/`ai_guided` with server-side receipt validation and a subscription-state reconciler alongside the Stripe one; (b) restrict the iOS build to coach-guided (person-to-person) commerce only; (c) ship iOS as a free companion with no purchase surface at all |
| **REL-06** | Apple 2.3.1 | `/qa-center` and `/mie-debugger` ship in release builds | Gate both routes behind `kReleaseMode` **and** an admin role check; add a regression test asserting neither route resolves in a release-mode router |
| **REL-07** | Env isolation | `APP_ENV` defaults to `prod`; prod defaults baked into the binary | Remove the default (`String.fromEnvironment('APP_ENV')` with no fallback) so an unconfigured build fails at compile/startup; move the prod Supabase URL/key into `dart_defines/prod.json`; delete `_prodSupabaseUrl`/`_prodSupabaseAnonKey`/`_prodStripePublishableKey` constants. **Extend `env_config_test.dart` to assert that an empty `APP_ENV` throws.** |
| **REL-08** | Auth on device | No deep-link/universal-link return path; reset and OAuth dead on iOS | Add `CFBundleURLTypes` (custom scheme, e.g. `com.twelvecircle.circlefitness`), add Associated Domains + an `apple-app-site-association` file on the marketing domain, pass a non-web `redirectTo` on all four call sites, and register every redirect in Supabase Auth → URL Configuration |
| **REL-16** | Apple 1.2 | No report/block/moderation for UGC (community + messaging) | Add report-content and block-user affordances with backing tables and RLS, a moderation queue for admins, an EULA link, and a documented 24-hour takedown SLA |
| **REL-17** | Metadata | No hosted privacy/terms/support URLs; `12circle.app` unconfirmed | Publish all three on the marketing domain; verify domain ownership and DNS; add Terms of Service to the Settings menu alongside Privacy Policy |
| **REL-18** | Secrets | **Three scripts named `qa_*` / `live_*` are hardcoded to the production project.** [`tool/qa_entitlements.dart:27`](../apps/mobile/tool/qa_entitlements.dart#L27), [`tool/qa_self_guided.dart:22`](../apps/mobile/tool/qa_self_guided.dart#L22), [`tool/live_integration_test.dart:15`](../apps/mobile/tool/live_integration_test.dart#L15) all target `nxdbooufqzkpslkcogxc`. A QA operator running a script called `qa_self_guided.dart` hits **production**. | Parameterise the target from `--dart-define`/env with **no default**; add a guard that refuses to run against a project ref not on an explicit allowlist |
| **REL-20** | Pipeline | No CI/CD | See §5 and §7; this is the mechanism every other gate depends on |
| **REL-21** | Security | Production carries unpatched SEC-01…SEC-05 | Owned by Workstreams D/E. Workstream G's gate: **no production rollout, and no production-pointed build, until closed and verified** |
| **REL-22** | Migrations | No production history reconciliation, no rollback | Dump production's `supabase_migrations.schema_migrations` and its live catalogue; write a reconciliation report; produce an explicit, reviewed, reversible rollout script for 113–121 with a tested restore procedure |
| **REL-23** | Infra | API has no deployment target anywhere | Containerise `apps/api`; deploy QA and production instances; set `API_BASE_URL` in `qa.json`/`prod.json`; set `CORS_ORIGINS` explicitly per environment |
| **REL-33** | Android | Release builds sign with **debug keys** (`signingConfig = signingConfigs.getByName("debug")`) | Create an upload keystore, wire a `release` signing config from a `key.properties` file kept out of git. Blocks any Android beta, not only Play |

### 3.2 P1 — must be closed before public App Store submission

| ID | Area | Issue |
|---|---|---|
| **REL-09** | Apple privacy | No `PrivacyInfo.xcprivacy`. Required-reason APIs are reached through `path_provider`, `shared_preferences`, and `flutter_secure_storage`; Apple expects an app-level manifest declaring collected data types and any third-party SDK reasons |
| **REL-10** | TestFlight | `ITSAppUsesNonExemptEncryption` absent from `Info.plist` → an export-compliance prompt on **every** upload. Add `<false/>` if only standard HTTPS is used |
| **REL-11** | Branding | Three different app names across `CFBundleDisplayName` (`Circle Fitness`), `CFBundleName` (`circle_fitness`), Android `android:label` (`circle_fitness`), and `MaterialApp.title` (`12 Circle Fitness`). The Android label is a raw package name on the user's home screen |
| **REL-12** | Identity | Bundle identifiers diverge: iOS `com.twelvecircle.circleFitness` vs Android `com.twelvecircle.circle_fitness`. Fix **before** the App ID is registered — it is immutable afterwards |
| **REL-13** | Versioning | No build-number strategy. `1.0.0+1` in `pubspec.yaml` is the sole source; every TestFlight upload needs a manual bump, and a duplicate build number is a hard upload rejection |
| **REL-24** | Stripe | Webhook has **no idempotency store** (Stripe redelivers; `checkout.session.completed` re-processing re-inserts `client_session_credits`), does not handle `invoice.payment_failed` / `invoice.paid` / disputes, does not deactivate `coach_client_relationships` on `customer.subscription.deleted`, and returns 500 with no dead-letter or alert. `verify_jwt = false` for this function is dashboard-managed, not declared in `config.toml` |
| **REL-25** | Config as code | `supabase/config.toml` declares no auth, redirect-URL, email-template, or per-function configuration. QA↔production parity is unverifiable and drift is undetectable |
| **REL-26** | Observability | No crash reporting, analytics, APM, structured logging, uptime monitoring, or alerting in any environment. A production incident would be invisible until a user reported it |
| **REL-27** | Backups | Supabase free tier: daily backups, **no PITR** (recorded in project memory). No documented or rehearsed restore. A 24-hour RPO is being accepted implicitly rather than deliberately |
| **REL-28** | API hardening | `app.enableCors({ origin: true })` when `CORS_ORIGINS` is unset ([`app.setup.ts`](../apps/api/src/app.setup.ts)); no `helmet`, no rate limiting, no throttling on a route that spends Anthropic credits, 12 MB body limit; `ValidationPipe` is applied per-controller rather than globally |
| **REL-29** | API surface | A second, parallel auth stack ships alongside the Supabase one: `firebase-admin`, `passport-jwt` with `JWT_SECRET`, `bcryptjs`, `auth.controller`, `users.controller`. Unused authentication is unmaintained attack surface — audit and remove, or own it deliberately |
| **REL-30** | Auth architecture | The API verifies Supabase tokens with a shared HS256 `SUPABASE_JWT_SECRET`. Supabase is migrating to asymmetric signing keys with JWKS; this verification path will break on that migration and cannot be rotated without redeploying the API |
| **REL-31** | Storage | `avatars`, `coach-media`, and `exercise-media` are **public buckets** — every object is world-readable by URL. Confirm no coach-uploaded client media or personally identifying content is ever written to `coach-media` |
| **REL-32** | Push | No remote push infrastructure, yet Android requests `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, and `RECEIVE_BOOT_COMPLETED`. `SCHEDULE_EXACT_ALARM` requires a Play Console declaration and is commonly rejected for non-alarm apps |
| **REL-34** | Hygiene | `supabase/.temp/` is gitignored but **still tracked** (8 files, including `pooler-url` and `linked-project.json`). `git rm --cached` is needed for the ignore to take effect |

### 3.3 P2 — should be closed before general availability

| ID | Issue |
|---|---|
| **REL-35** | `create-checkout` responds with `Access-Control-Allow-Origin: '*'` on an authenticated, money-moving endpoint. Restrict to known origins |
| **REL-36** | Seed files are wired into `config.toml`'s `[db.seed]` and run on `supabase db reset`. Test accounts with published passwords (`test@12circle.app` / `Test1234!`) must be provably unreachable in production; add a guard that refuses to seed a non-QA project ref |
| **REL-37** | `NSUserTrackingUsageDescription` absent — correct today (no ATT SDKs). It must stay correct: adding any attribution SDK changes the privacy questionnaire answers |
| **REL-38** | iPhone build permits landscape in both directions; the UI is designed portrait-first. Either lock to portrait or QA every screen in landscape |
| **REL-39** | Wearable integrations (Strava, WHOOP, Garmin, Polar, Spotify, MyFitnessPal) present OAuth URLs in [`integrations_screen.dart`](../apps/mobile/lib/features/profile/presentation/integrations_screen.dart). Each provider requires an approved developer app and brand-usage compliance; an integration that appears connectable but is not is a Guideline 2.3.1 exposure |
| **REL-40** | `images.unsplash.com` referenced in `lib/` — confirm licensing and remove remote placeholder imagery from shipping screens |
| **REL-41** | 180 occurrences of `TODO`/`FIXME`/`mock`/`placeholder`/`coming soon` in `lib/`. Triage for anything user-visible before review; a "Coming Soon" screen is a 2.1/2.3.1 risk |
| **REL-42** | Only 4 uses of `kReleaseMode`/`kDebugMode` across the whole client — very little is release-gated. Audit debug affordances broadly, not only the two router entries in REL-06 |
| **REL-43** | No App Store Connect metadata prepared: screenshots (6.9" and 6.5" required), description, keywords, promotional text, subscription display names and localised descriptions, review notes, demo account |

### 3.4 P3 — post-launch

| ID | Issue |
|---|---|
| **REL-44** | No iPad support declared or tested, though `UISupportedInterfaceOrientations~ipad` is configured. Decide iPhone-only and set the device family explicitly |
| **REL-45** | No localisation (`CFBundleDevelopmentRegion` only). Single-locale launch is fine; declare it |
| **REL-46** | No App Store Connect API key / Fastlane / automated metadata delivery. Manual uploads are acceptable for the first releases and painful by the fifth |
| **REL-47** | No `macos`, `linux`, `windows` build intent despite scaffolds being present. Remove the unused platform directories or state the intent |
| **REL-48** | No accessibility audit, though the product bible §4 names accessibility a requirement rather than a polish item |

---

## 4. App Store checklist

Ordered as an execution list. Nothing here has been performed.

### 4.1 Apple Developer account and identifiers
- [ ] Apple Developer Program membership active; legal entity, D-U-N-S, and banking/tax complete (**required before paid subscriptions**)
- [ ] Decide and freeze the bundle identifier — **immutable after registration** (REL-12)
- [ ] Register the App ID with capabilities: Sign in with Apple, Associated Domains, (Push only if REL-32 is resolved)
- [ ] Create the App Store Connect app record, primary language, and SKU

### 4.2 Xcode project
- [ ] `DEVELOPMENT_TEAM` set; signing style chosen; `Apple Distribution` identity for Release (REL-03)
- [ ] `Runner.entitlements` created and referenced by both Debug and Release configurations
- [ ] `IPHONEOS_DEPLOYMENT_TARGET` raised to 16.0, `Podfile` platform matched (REL-02)
- [ ] `Podfile` and `Podfile.lock` generated and committed (REL-01)
- [ ] `CFBundleDisplayName`, `CFBundleName`, Android label, and `MaterialApp.title` reconciled (REL-11)
- [ ] `ITSAppUsesNonExemptEncryption` declared (REL-10)
- [ ] `CFBundleURLTypes` + Associated Domains configured; `apple-app-site-association` published (REL-08)
- [ ] `PrivacyInfo.xcprivacy` authored with data types and required-reason API declarations (REL-09)
- [ ] Device family and orientation locked deliberately (REL-38, REL-44)
- [ ] Launch screen reviewed on device (no default Flutter splash in the shipped build)

### 4.3 Guideline compliance
- [ ] **5.1.1(v)** In-app account deletion implemented and reachable in ≤3 taps from Settings (REL-04)
- [ ] **5.1.1(v)** Help-center and privacy-policy deletion text corrected to match reality (REL-04)
- [ ] **3.1.1 / 3.1.3(e)** Purchase architecture decided and implemented (REL-05 · decision **D-1**)
- [ ] **3.1.2** If IAP: subscription groups, localised display names, durations, and a functioning **Restore Purchases** control
- [ ] **1.2** Report content, block user, moderation queue, EULA, 24-hour response commitment (REL-16)
- [ ] **2.3.1** Debug/QA routes removed from release builds (REL-06)
- [ ] **4.8** Sign in with Apple offered wherever Google Sign-In is (already in `pubspec.yaml`; needs the entitlement)
- [ ] **5.1.1** Permission prompts requested in context, not at launch; each purpose string matches actual use
- [ ] **5.1.3** Women's-health cycle data handled as health data: no third-party sharing, no advertising use, explicit consent
- [ ] **1.4.1** Medical/physical-safety review: PAR-Q handling and training recommendations must not read as medical advice (interacts with decision **Q-4** in the remediation plan)

### 4.4 App Store Connect metadata
- [ ] Privacy Policy URL (public, hosted) · Terms of Use URL · Support URL · Marketing URL (REL-17)
- [ ] App Privacy questionnaire: health & fitness, contact info, identifiers, user content, photos, audio, usage data — declared per collection purpose and linkage
- [ ] Age rating questionnaire — expect **12+** given health/fitness content plus unmoderated-until-REL-16 UGC
- [ ] Screenshots for 6.9" and 6.5" (App Store minimum set), taken from a QA build with realistic non-fabricated data
- [ ] Description, keywords, promotional text, what's new
- [ ] **Demo account with full credentials in App Review Notes** — the reviewer must be able to reach coach-guided, AI-guided, and marketplace surfaces; a self-guided-only account will produce a 2.1 "incomplete information" rejection
- [ ] Review notes explaining the coaching model, what the AI does and does not decide, and how PAR-Q data is used
- [ ] Content-rights declaration for exercise media, video, and any third-party imagery (REL-40)

---

## 5. TestFlight checklist

### 5.1 Prerequisites (all of §4.2 plus)
- [ ] REL-01, REL-02, REL-03 closed — an archive can actually be produced
- [ ] REL-04 (account deletion) closed — Apple reviews TestFlight **external** builds against the same guideline
- [ ] REL-06 (QA routes) closed
- [ ] REL-07 (environment default) closed — **a TestFlight build must be provably pointed at QA/staging, never at production**
- [ ] REL-08 (deep links) closed — sign-in and password reset must work on device
- [ ] REL-33 if an Android internal track runs in parallel

### 5.2 Build configuration
- [ ] A dedicated `dart_defines/staging.json` exists, pointing at the staging Supabase project and staging Stripe (test-mode) keys
- [ ] Build number auto-increments (CI-derived, e.g. run number) — never hand-edited (REL-13)
- [ ] `flutter build ipa --dart-define-from-file=dart_defines/staging.json --export-method app-store` verified reproducible
- [ ] A build-artifact scan (the iOS analogue of `check_web_build_secrets.sh`) proves no production project ref, no service-role key, and no Anthropic key in the IPA
- [ ] dSYMs uploaded once crash reporting exists (REL-26)

### 5.3 Distribution
- [ ] Internal testing group (up to 100 App Store Connect users) — no Apple review required
- [ ] External group + Beta App Review — requires the full guideline set including REL-04, REL-05, REL-16
- [ ] Beta App Description, feedback email, and test instructions per build
- [ ] Test plan sourced from [`beta-test-checklist.md`](beta-test-checklist.md) and [`beta-readiness.md`](beta-readiness.md), re-scoped for device: camera, photo library, microphone/speech, barcode scanning, local notifications, background/foreground session restoration, offline and flaky-network behaviour, and the workout session persistence path that Workstream A/Phase 2 has been reworking
- [ ] Crash-free-session target agreed before the beta opens (a threshold you cannot measure yet — REL-26)

### 5.4 Explicit TestFlight non-goals
- Production Supabase must not be reachable from any TestFlight build.
- Live Stripe keys must not be present in any TestFlight build.
- The keep-alive workflow's production credentials must not be reused in any client build path.

---

## 6. Production infrastructure checklist

### 6.1 Environment topology (target)

| Environment | Supabase | API | Stripe | Client build | Purpose |
|---|---|---|---|---|---|
| dev | local / dev project | localhost:3000 | test | `dart_defines/dev.json` | Development |
| **qa** | `eyqtldjqpgpljlqvpowh` | QA deployment | test | `qa.json` | Automated + manual QA |
| **staging** | **does not exist — must be created** | staging deployment | test | `staging.json` | Release candidates, TestFlight |
| **prod** | `nxdbooufqzkpslkcogxc` | prod deployment | **live** | `prod.json` | Public |

**The staging environment does not exist.** Today QA is being used as both the QA target and the de-facto release candidate target, which means a release candidate cannot be validated against a clean, seed-free database. Standing one up is a prerequisite for the release-gate matrix in §7.

### 6.2 Supabase
- [ ] Production migration history dumped and reconciled against the repository sequence (REL-22)
- [ ] Migrations 113–121 applied to production **only after** QA verification passes, under an explicit, separately authorised rollout (REL-21)
- [ ] Rollback script authored and rehearsed for each migration in that rollout
- [ ] Auth configuration moved into `config.toml` where possible: site URL, redirect allowlist, JWT expiry, refresh-token rotation, password policy, rate limits, email templates (REL-25)
- [ ] Providers enabled and configured per environment: Google, Apple (Apple's Services ID, key, and return URL are distinct per environment)
- [ ] Custom SMTP configured for production (Supabase's built-in sender is rate-limited and not for production volume). `RESEND_API_KEY` already appears in three Edge Functions — decide whether Resend is also the auth mail transport
- [ ] Storage: confirm public/private posture per bucket (REL-31); set size and MIME restrictions; consider CDN/transform settings
- [ ] Upgrade off free tier before launch: PITR, larger compute, and connection pooling sized for real traffic (REL-27)
- [ ] Retire or repoint the production keep-alive cron once the project is on a paid plan
- [ ] Vault secrets (`project_url`, `service_role_key`) created per project and **verified to point at their own project** — `MASTER_QA_RECONCILIATION.md` §4 records that this was previously a QA-writes-to-production hazard

### 6.3 Edge Functions
- [ ] All 19 deployed per environment with a tracked, reviewable secret manifest for all 15 variables (REL-25)
- [ ] `verify_jwt` declared **in `config.toml`** per function — explicitly `false` for `stripe-webhook`, explicitly `true` everywhere else
- [ ] Function deployment automated in CI, not run from a laptop (REL-20)
- [ ] `APP_URL` correct per environment (it currently drives Stripe redirect targets)
- [ ] Anthropic, Stripe, Resend, and YouTube keys distinct per environment; test-mode Stripe never present in production and vice versa

### 6.4 Stripe
- [ ] Live-mode account activated; business details, tax, and bank account complete
- [ ] Products and prices recreated in live mode; the six `STRIPE_*_PRICE_ID` variables set to live IDs
- [ ] Live webhook endpoint registered with its own `STRIPE_WEBHOOK_SECRET`; the events actually handled are subscribed
- [ ] Webhook idempotency store added; `invoice.payment_failed`, `invoice.paid`, `charge.dispute.created`, and `customer.subscription.deleted` → relationship deactivation all handled (REL-24)
- [ ] Stripe Connect: production platform profile, onboarding flow, payout schedule, and the platform-fee/commission model verified against live rates
- [ ] Radar rules and SCA/3DS behaviour reviewed
- [ ] Reconciliation job comparing Stripe subscription state against the `subscriptions` table (the webhook is currently the only writer, with no repair path)

### 6.5 API
- [ ] Containerised and deployed for QA, staging, and production (REL-23)
- [ ] `CORS_ORIGINS` set explicitly per environment; never left empty in a deployed environment (REL-28)
- [ ] `helmet`, global `ValidationPipe`, and rate limiting on `/ai/*` added (REL-28)
- [ ] Health/readiness endpoint wired to the platform's probe
- [ ] Unused Firebase/JWT/bcrypt auth stack audited and removed or owned (REL-29)
- [ ] Migration plan for Supabase asymmetric JWT verification (REL-30)
- [ ] Secrets held in the platform's secret manager; `ANTHROPIC_API_KEY` rotatable without a redeploy

### 6.6 Observability, backup, rollback
- [ ] Crash reporting in the client with dSYM upload (REL-26)
- [ ] Error tracking in the API and Edge Functions
- [ ] Product analytics with a **documented event schema** — required for the App Privacy questionnaire to stay accurate
- [ ] Uptime checks: Supabase REST, Auth, the API health route, and the Stripe webhook endpoint
- [ ] Alert routing with a named on-call owner
- [ ] Log retention and PII-scrubbing policy (health data is in scope)
- [ ] **Restore drill performed and timed** on a non-production copy; RTO/RPO written down and accepted (REL-27)
- [ ] Rollback procedure for: client (previous App Store version / staged rollout halt), API (previous image), Edge Functions (previous deployment), database (forward-fix migration — **there is no down path**, REL-22)

---

## 7. Release-gate matrix

Each gate is **hard**: no artifact advances until every row is satisfied. "Automated" states whether a mechanism exists today.

### Gate 0 — Merge to `main`
| Requirement | Automated today |
|---|---|
| Flutter suite green (baseline 514) | ❌ manual (`npm run test:mobile`) |
| API unit + e2e green (baseline 58) | ❌ manual |
| `flutter analyze` clean | ❌ absent |
| Security probe suite green (`npm run test:security`) | ❌ manual |
| Web-artifact secret scan clean (`npm run check:web-secrets`) | ❌ manual |
| Repository secret scan clean | ❌ absent |
| Code review approved | ❌ no branch protection observed |

### Gate 1 — QA promotion
| Requirement | Owner |
|---|---|
| All P0 security items (SEC-01…SEC-12) verified **closed by live QA probe** | Workstream E |
| Workout integrity (WRK-01…WRK-07) regression tests failing-before/passing-after | Workstream A |
| Core contracts (CON-01…CON-10) closed or explicitly deferred with an ID | Workstream C |
| QA Edge Functions deployed, Vault secrets set, intelligence substrate populated (ENV-01/02/03) | Workstream B |
| No probe residue left in QA | Workstream E |

### Gate 2 — Release candidate → staging
| Requirement |
|---|
| Staging environment exists and is seed-free (§6.1) |
| Migrations apply cleanly to a **fresh** database from `000` — proves the sequence, not the accumulated QA state |
| RC built from a tagged commit with `dart_defines/staging.json` |
| Artifact scan: no production ref, no service-role key, no AI key |
| Full manual QA pass on staging against the [`beta-test-checklist.md`](beta-test-checklist.md) surface |
| Stripe test-mode end-to-end: checkout → webhook → entitlement → portal → cancel |

### Gate 3 — TestFlight (internal)
| Requirement |
|---|
| Gate 2 passed |
| REL-01, REL-02, REL-03 closed (an archive exists) |
| REL-06, REL-07 closed (no QA routes; provably staging-pointed) |
| REL-08 closed (sign-in and password reset verified **on device**) |
| Build number unique and CI-derived |
| Crash reporting live with dSYMs uploaded |

### Gate 4 — TestFlight (external / Beta App Review)
| Requirement |
|---|
| Gate 3 passed |
| REL-04 (account deletion) shipped and verified |
| REL-05 (purchase architecture) implemented per decision D-1 |
| REL-16 (report/block/moderation) shipped |
| REL-17 (privacy, terms, support URLs) live |
| REL-09, REL-10 (privacy manifest, export compliance) declared |
| Beta feedback channel staffed; [`beta-feedback-board.md`](beta-feedback-board.md) in use |

### Gate 5 — App Store submission
| Requirement |
|---|
| Gate 4 passed and a beta cycle completed with no open P0/P1 |
| Full §4 checklist complete |
| Production infrastructure §6 complete, **including REL-21 and REL-22** |
| Stripe live mode verified with a real low-value transaction and refund |
| Restore drill performed; rollback runbook written and rehearsed |
| Named on-call owner for launch week |

### Gate 6 — Production rollout
| Requirement |
|---|
| Phased release enabled (Apple's 7-day staged rollout) |
| Production migrations applied under explicit authorisation, with rollback ready |
| Monitoring dashboards live and watched |
| Kill switch identified for each risky surface (AI generation, marketplace, payments) |

---

## 8. Recommended launch sequence

Nine stages. The ordering is driven by dependency, not by preference: security precedes correctness because a fix on top of a broken authorisation boundary is unverifiable; correctness precedes release engineering because there is no point signing a build that fails QA; the purchase decision precedes iOS engineering because it can change what the iOS app *is*.

**Stage 1 — Finish the security phase (Workstreams D/E).**
Phase 1 of the remediation plan, verified live in QA. Nothing in this document may start its production half until this is closed. *Exit: every P0 verified closed by live probe; regression tests standing.*

**Stage 2 — Finish product correctness (Workstreams A/B/C).**
Phases 2–4 of the remediation plan. *Exit: full suite green against real QA data; every canonical ID classified.*

**Stage 3 — Answer the product-authority decisions (§10).**
D-1 (purchase architecture) is the long pole and gates Stage 6. Q-3 and Q-4 from the remediation plan gate the workout and PAR-Q surfaces a reviewer will exercise. *Exit: decisions recorded in [`decision-log.md`](decision-log.md).*

**Stage 4 — Build the pipeline (REL-20).**
CI first: test + analyze + security-probe + secret-scan on every PR, with branch protection. Then CD: migration deploy, function deploy, API deploy, web deploy. *Exit: Gate 0 and Gate 1 are mechanisms rather than promises.*

**Stage 5 — Stand up staging and deploy the API (REL-23, §6.1).**
A real staging Supabase project built by applying migrations `000`→`121` to an empty database — which also proves the sequence. Deploy the API to QA, staging, and (dormant) production. *Exit: Gate 2 executable.*

**Stage 6 — Make the iOS build exist (REL-01, 02, 03, 07, 08, 11, 12, 13).**
CocoaPods, deployment target, signing, entitlements, deep links, naming, versioning. Then the first archive and the first internal TestFlight build pointed at staging. *Exit: Gate 3.*

**Stage 7 — Close the App Store compliance surface (REL-04, 05, 06, 09, 10, 16, 17).**
Account deletion, purchase architecture per D-1, moderation, privacy manifest, hosted legal URLs, debug-route removal. *Exit: Gate 4 — external TestFlight through Beta App Review.*

**Stage 8 — Private beta.**
The milestone the product bible §8 already names: real coaches using the platform daily. Run it on staging + external TestFlight, not on production. *Exit: a beta cycle with no open P0/P1 and an agreed crash-free-session rate.*

**Stage 9 — Production cutover and submission.**
Production migration rollout under explicit authorisation with rollback ready; Stripe live mode; observability live; App Store submission; phased release. *Exit: Gate 5, then Gate 6.*

**Stages 4, 5, and 6 can run concurrently with Stages 1–2** — they touch no application logic and no production system. **Stage 7 cannot start before Stage 3**, because D-1 determines what gets built.

---

## 9. Dependencies on other QA workstreams

| Dependency | Workstream | Why Workstream G is blocked by it |
|---|---|---|
| SEC-01…SEC-12 closed in QA | **D / E** | REL-21. A production rollout plan cannot be written against a database whose authorisation boundary is still open. A TestFlight build against a vulnerable staging clone leaks real beta-tester health data |
| WRK-01…WRK-07 closed | **A** | Workout logging is the core loop and the primary surface a reviewer and every beta tester will exercise. A 23505 during a logged set is a 2.1 rejection and a beta-killer |
| CON-01 (`checkins` table) | **C** | [`coach_dashboard_screen.dart:108`](../apps/mobile/lib/features/dashboard/presentation/coach_dashboard_screen.dart#L108) still queries a table that has never existed. The coach dashboard is a demo-account surface for App Review |
| CON-02, CON-03 (onboarding persistence) | **C** | Onboarding is the reviewer's first screen. Failing open on a save is a 2.1 rejection |
| CON-04 (PAR-Q) + Q-4 | **C** | Guideline 1.4.1. What a high-risk PAR-Q result does determines whether the app reads as fitness or as medical advice |
| CON-08, CON-10 (allergens, women's health) | **C** | Health-data safety claims in the App Privacy questionnaire must be true |
| ENV-01/02/03 (QA functions, Vault, substrate) | **B** | Directly reusable as the staging build-out; also the only proof the 15-variable secret matrix is complete |
| "Engine decides, AI explains" standing test | **B** | The App Review notes must describe the AI's role accurately, and the product bible §6 makes it a hard constraint |
| HYG-01/02/03 (baseline reproducibility) | **Step 0** | REL-20. CI cannot gate on a baseline that is not reproducible from a clean checkout |
| Q-6 (`dietary_restrictions` prod type) | **C** | REL-22. Production's actual schema must be known before any migration is applied to it |

**What Workstream G supplies back:** the release-gate matrix (§7) that turns each workstream's exit criteria into an enforced mechanism; the staging environment those workstreams currently lack; and the CI harness that makes their regression tests standing rather than manual.

---

## 10. Items requiring Julia / product-authority decisions

These cannot be settled from repository evidence. Each carries a recommendation and the consequence of each option; none will be actioned without a decision.

---

**D-1 · How does the iOS app take money?** *(blocks REL-05, Gate 4, Stage 7 — the largest single item in this document)*

The product currently sells four things: two digital memberships (`self_guided` $29/mo, `ai_guided` $59/mo), a client→coach subscription, and a coach→platform plan — all through hosted Stripe Checkout.

Apple's Guideline 3.1.1 requires In-App Purchase for digital content and services consumed in the app. Guideline 3.1.3(e) exempts person-to-person real-time services. **`ai_guided` and `self_guided` are digital services and are very unlikely to qualify.** The coach subscription has a real argument. The coach *platform* plan is a business-facing purchase and may fall under 3.1.3(b)/enterprise reasoning.

| Option | Consequence |
|---|---|
| **(a) Add StoreKit 2 IAP for the digital tiers**, keep Stripe for coach commerce and for web | Apple takes 15–30%; requires receipt validation, a second subscription-state reconciler, and price-parity thinking. **Recommended** — it is the only option that ships the full product on iOS |
| **(b) iOS ships coach-guided commerce only** | Cleanest compliance story, smallest engineering change; abandons the self-serve revenue line on iOS, which is the scalable one |
| **(c) iOS ships free, no purchase surface; upgrades happen on the web** | Fastest to TestFlight; Apple prohibits *linking or referring* to external purchase from inside the app, so the app cannot even mention it. Weak conversion, and a "reader-app"-style argument that 12 Circle does not qualify for |

**Recommendation: (a).** It is the most work and the only option that does not amputate a revenue line. The decision must be made before Stage 6, because it changes what the iOS build contains.

---

**D-2 · What is the launch platform, and what is the App Store's role in it?**

The product is a working web application; iOS is greenfield. Options: (i) web-first launch now, iOS later; (ii) simultaneous; (iii) iOS-first. This determines whether Stages 6–7 sit on the critical path at all, and whether the private beta in the product bible §8 runs on web or through TestFlight.
**Recommendation: (i)** — launch the private beta on web where the product actually works, and treat iOS as the next milestone. It removes D-1 from the critical path for the beta while leaving it fully in scope for launch.

---

**D-3 · Is community/messaging in the v1 iOS scope?**

REL-16 (report, block, moderate, EULA, 24-hour SLA) is real engineering plus an operational commitment — someone must action reports within 24 hours. Options: build it; or ship v1 with community and 1:1 messaging disabled on iOS.
**Recommendation:** if D-2 is (i), defer moderation to the iOS milestone and keep community web-only for the beta. If iOS ships with community, moderation is non-negotiable and needs a named owner.

---

**D-4 · What is the product's actual name, and what domain does it own?**

Four spellings ship today (REL-11). `12circle.app` is referenced as a redirect target in Edge Functions but this workstream cannot confirm it is registered or controlled. The bundle identifier is immutable once registered (REL-12), and the display name drives the App Store listing.
**Needed:** one canonical display name, one canonical bundle identifier, and confirmation of the marketing domain — before Stage 6 begins.

---

**D-5 · What operational commitment is being made at launch?**

Backups (currently free-tier daily, no PITR), incident response, on-call, and support-response time. An app that holds cycle-tracking data, PAR-Q health history, and payment relationships is making implicit promises in its privacy policy that the infrastructure does not currently keep (REL-26, REL-27).
**Needed:** an accepted RPO/RTO, a named on-call owner for launch week, and a support channel behind the Support URL.

---

**D-6 · Are the wearable integrations real?** *(REL-39)*

Strava, WHOOP, Garmin, Polar, Spotify, and MyFitnessPal OAuth endpoints appear in the integrations screen. Each requires an approved developer application and brand compliance. Options: complete the partner approvals; hide the screen for v1; or mark them explicitly as roadmap.
**Recommendation:** hide unapproved providers for v1. A connect button that cannot connect is a Guideline 2.3.1 exposure and a trust cost.

---

**Also inherited, unchanged, from the remediation plan:** **Q-3** (does the engine prescribe load?) and **Q-4** (what a high-risk PAR-Q result does) are restated here because both are visible to App Review — Q-3 through the workout surface a reviewer will exercise, Q-4 through Guideline 1.4.1's physical-safety scope.

---

## Appendix A — Evidence index

| Claim | Evidence |
|---|---|
| No iOS build ever produced | `apps/mobile/build/` contains `web`, `macos`, `flutter_assets`, `test_cache`, `unit_test_assets` only; no `build/ios`, no `Podfile`, no `Podfile.lock`, no `Pods/`; `which pod` → not found |
| `mobile_scanner` needs iOS 15.5 | `~/.pub-cache/hosted/pub.dev/mobile_scanner-6.0.11/ios/mobile_scanner.podspec` → `s.platform = :ios, '15.5.0'`; no iOS `Package.swift` (macOS only) |
| CocoaPods mandatory | `flutter_local_notifications-18.0.1` and `record-7.1.1` ship no `Package.swift` |
| No entitlements / privacy manifest | `find ios -name '*.entitlements' -o -name 'PrivacyInfo.xcprivacy'` → empty |
| No `DEVELOPMENT_TEAM` | `grep DEVELOPMENT_TEAM ios/Runner.xcodeproj/project.pbxproj` → no match |
| `APP_ENV` defaults to `prod` | [`app_env.dart:150-151`](../apps/mobile/lib/core/config/app_env.dart#L150-L151) |
| Prod defaults baked into the binary, with a **test** Stripe key | [`app_env.dart:117-121`](../apps/mobile/lib/core/config/app_env.dart#L117-L121) |
| No account deletion | Exhaustive grep of `lib/` — only help-center, privacy-policy, and ToS *text*; no UI, no service, no RPC |
| QA routes shipped | [`app_router.dart:204,207`](../apps/mobile/lib/core/router/app_router.dart#L204-L207) |
| No moderation surface | Exhaustive grep for report/block/mute across `lib/` — only unrelated `moderate` intensity strings and admin exercise review |
| Digital subscriptions via Stripe | [`create-checkout/index.ts:1-6`](../supabase/functions/create-checkout/index.ts), `checkout_launcher.dart` |
| Webhook has no idempotency | [`stripe-webhook/index.ts`](../supabase/functions/stripe-webhook/index.ts) — no processed-event table, no `invoice.*` cases |
| Only one workflow exists | `ls .github/workflows` → `supabase-keepalive.yml` |
| API has no deployment target | `find` for Dockerfile/fly.toml/vercel.json/render.yaml/Procfile → only the keep-alive workflow matched |
| `API_BASE_URL` empty in qa and prod | `dart_defines/qa.json`, `dart_defines/prod.json` |
| Public buckets | `036` (`coach-media`), `043` (`avatars`), `061` (`exercise-media`) — all `public = true` |
| `qa_*` tools point at production | [`tool/qa_entitlements.dart:27`](../apps/mobile/tool/qa_entitlements.dart#L27), [`tool/qa_self_guided.dart:22`](../apps/mobile/tool/qa_self_guided.dart#L22), [`tool/live_integration_test.dart:15`](../apps/mobile/tool/live_integration_test.dart#L15) |
| Android signs release with debug keys | `android/app/build.gradle.kts` → `signingConfig = signingConfigs.getByName("debug")` |
| `supabase/.temp` still tracked | `git ls-files supabase/.temp` → 8 files |
| CON-01 still open | [`coach_dashboard_screen.dart:108`](../apps/mobile/lib/features/dashboard/presentation/coach_dashboard_screen.dart#L108) → `.from('checkins')` |
| No down migrations | Exhaustive grep across all 122 migration files → no rollback sections |

## Appendix B — What this workstream deliberately did not do

- Did not contact production Supabase, the production API, Stripe, or Apple.
- Did not run any migration, seed, or write probe against any environment.
- Did not create an App Store Connect record, App ID, or provisioning profile.
- Did not modify application code, configuration, or migrations.
- Did not redesign UI, per the brief.
- Did not verify DNS or ownership of `12circle.app`, since that resolves outward to a third party.
- Did not attempt an iOS build; doing so would install CocoaPods and generate a `Podfile`, which is a remediation act, not a discovery act.
