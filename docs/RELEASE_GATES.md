# 12 Circle Fitness — Release Gates

**Wave 0 deliverable. Gate 0 through Gate 9.**
**Date:** 2026-08-24 · **Companion to** [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) and [`QA_CLOSURE_STANDARD.md`](QA_CLOSURE_STANDARD.md)

> **A gate is a mechanism, not a belief.** A gate row is met when a named check passes in
> CI, or when a named artifact exists and has been reviewed. "Someone ran it locally and
> it was green" satisfies no row in this document.
>
> Today **every** gate row is a promise. `.github/workflows/` contains one file — a daily
> production keep-alive ping. That is why Gate 0 is Wave 1's deliverable and why nothing
> above it can be honestly claimed until Gate 0 is mechanized.

---

## 0. Gate map

| Gate | Name | Blocks | Owning wave | Supersedes |
|---|---|---|---|---|
| **Gate 0** | Merge to `main` | any commit reaching the trunk | 1 | G's Gate 0 |
| **Gate 1** | QA promotion — contract truth | any claim that a domain works | 1–4 | G's Gate 1 |
| **Gate 2** | QA verification — security & error contract | any AI or billing deployment | 2–4 | new |
| **Gate 3** | AI enablement | any AI quality judgement, any AI-facing beta | 5 | new |
| **Gate 4** | Commerce enablement | any real or test-mode money movement beyond a smoke test | 6 | new |
| **Gate 5** | Release candidate → staging | any distributable artifact | 8 | G's Gate 2 |
| **Gate 6** | Manual QA sign-off | any human beta | 9 | new |
| **Gate 7** | TestFlight internal | any device distribution | 8 | G's Gate 3 |
| **Gate 8** | TestFlight external / Beta App Review | any external tester | 8 | G's Gate 4 |
| **Gate 9** | App Store submission → production rollout | public availability | 10 | G's Gates 5 + 6 |

Workstream L's `G-01`…`G-16` are **mechanical conditions**, not gates. They are cited in
the rows below as the checks that satisfy them.

**The hard chain, and it is not negotiable:**

```
Gate 0 ─► Gate 1 ─► Gate 2 ─┬─► Gate 3 ─┐
                            └─► Gate 4 ─┴─► Gate 5 ─► Gate 6 ─► Gate 7 ─► Gate 8 ─► Gate 9
```

Gates 3 and 4 are independent of each other and may be met in either order or in parallel.
**Everything else is strictly sequential.**

---

## Gate 0 — Merge to `main`

*Every row must be an automated check running on every push and pull request.*

| # | Requirement | Mechanism | Today |
|---|---|---|---|
| 0.1 | Flutter suite green | `flutter test` in CI | ❌ manual — **730 passed / 9 skipped / 0 failed** measured 2026-08-24 |
| 0.2 | `flutter analyze` — 0 errors | CI | ❌ absent · 0 errors, 15 warnings today |
| 0.3 | API unit + e2e green | `npm run test:api` | ❌ manual — 58 + 6 |
| 0.4 | Schema-contract guard green | `npm run test:contract` | ❌ manual — exists, 2 relations + 8 columns allowlisted |
| 0.5 | Web-artifact secret scan clean | `npm run check:web-secrets` on a QA web build | ❌ manual |
| 0.6 | **No production ref** outside `app_env.dart`, the keep-alive workflow, and tests asserting *about* it | new static guard | ❌ absent — **3 harnesses currently violate it** |
| 0.7 | `git status --porcelain supabase/migrations` empty | CI | ❌ **20 untracked, 15 modified today** |
| 0.8 | No tracked migration modified relative to its merge-base | CI | ❌ absent |
| 0.9 | No duplicate migration prefix; the sequence is contiguous | CI | ❌ absent |
| 0.10 | Every function in `supabase/functions/` has an explicit `verify_jwt` in `config.toml` | CI | ❌ **no `[functions]` block exists** |
| 0.11 | Release-mode route table contains neither `/qa-center` nor `/mie-debugger` | new test | ❌ absent |
| 0.12 | Repository secret scan clean | CI | ❌ absent |
| 0.13 | Code review approved | branch protection | ❌ none observed |
| 0.14 | **A guard-preservation check:** no migration redefines a function carrying an authorization wrapper, a `search_path` pin or a security trigger without carrying them forward | generalise `SEC-027` | ❌ absent — **its absence is what produced all five §4.2 regressions** |

**Exit:** every row automated and green. **Owning wave: 1.**
**Satisfies:** `G-01`, `G-02`, `G-03`, `G-05`, `G-16`.

---

## Gate 1 — QA promotion (contract truth)

*The database contains everything the application names, and the tree is durable.*

| # | Requirement | Mechanism |
|---|---|---|
| 1.1 | Gate 0 met and mechanized |
| 1.2 | Every migration applied to QA is recorded in `supabase_migrations.schema_migrations` | `supabase migration list --linked` shows local and remote in step |
| 1.3 | Forward migration 123 exists, carries every semantic delta of the 15 in-place edits, and is idempotent on replay | applied twice to QA, second run a no-op |
| 1.4 | `npm run test:contract` passes with `known-violations.json` **empty** | CI |
| 1.5 | `checkins` and `coach_tips` are resolved — retired or created — and the allowlist entries are gone | 1.4 |
| 1.6 | Every storage bucket referenced by shipped code exists, and **`progress-photos` and `chat-media` are private** | a live bucket probe in CI's QA job |
| 1.7 | A member can write `has_injuries`, `injury_locations`, a pregnancy and a postpartum state without error | live QA assertion |
| 1.8 | Reverse scripts exist for 113–128 and have been rehearsed on a QA clone | artifact + a rehearsal record |
| 1.9 | Rollback strategy resolved: PITR purchased, or forward-only accepted in writing | **PD-A26** |

**Exit:** the application and the database agree, and a change to either can be undone.
**Owning waves: 1, 3A.** **Satisfies:** `G-03`, `G-04`, `G-08` (partly).

---

## Gate 2 — QA verification (security & error contract)

*The authorization boundary is proven live, and the product does not report success it has not earned.*

| # | Requirement | Mechanism |
|---|---|---|
| 2.1 | Gate 1 met |
| 2.2 | `npm run test:security` **executes in CI against QA and passes** — 188+ assertions across six suites | environment-gated CI job with a scoped QA service key |
| 2.3 | All five §4.2 regressions closed, **each pinned by a test that fails against the pre-fix tree** | `d04-rpc-execution.mjs` extended to assert the five 116 wrappers as a class |
| 2.4 | Zero `public` routines executable by `anon`; zero definer functions with a mutable `search_path`; zero tables without RLS | live catalog assertions |
| 2.5 | No routine is `authenticated`-executable outside migration 116's allowlist, **and `ai_adjust_nutrition` is specifically asserted absent from it** | live |
| 2.6 | `decision_traces` reads are scoped to subject + active coach (+ admin if **PD-A05** so decides) | live, with a probe coach holding zero relationships |
| 2.7 | A conversation participant cannot alter the other party's message text | live |
| 2.8 | An error-reporting sink exists and a deliberately-failed read appears in it | integration assertion |
| 2.9 | Every write whose success is asserted to a user verifies it landed; a simulated zero-row response yields *Refused* | per-site unit tests + a source guard |
| 2.10 | No user-facing success state is shown without authoritative evidence — **workout completion, invite sent, event registered, connected, switched to Free, check-in submitted** each proven | widget tests + live |
| 2.11 | No code path substitutes fixture data for a real query result | source guard |
| 2.12 | A high-risk PAR-Q renders as a grade only when assessed; absent risk renders "not assessed" | widget test |
| 2.13 | `EC-G5`'s blind spot closed — the ratchet sees Riverpod `error: (_,__) =>` and `.valueOrNull`, not only `catch` | guard change, then ratchet down |

**Exit:** Phase 1's evidence is re-established as *live and standing* rather than
*point-in-time*, and the error contract holds at every layer.
**Owning waves: 2, 3B, 3C.**

> **This is the gate the programme currently fails most badly**, because 2.2 has never
> run. Everything Phase 1 proved is presently unverifiable, and §4.2 shows the posture has
> drifted since it was proved.

---

## Gate 3 — AI enablement

*Correct inputs and proven authorization before any model runs, and before any judgement of model quality.*

| # | Requirement | Mechanism |
|---|---|---|
| 3.1 | Gate 2 met |
| 3.2 | QA function secrets set — Anthropic (**budget-capped**), YouTube, Resend + verified sender, `APP_URL`, Stripe test keys and the five QA price ids | `supabase secrets list` diffed against a committed manifest |
| 3.3 | QA Vault holds **QA's own** `project_url` and `service_role_key` | live |
| 3.4 | **`cron.job_run_details` proves every scheduled target host is the QA ref and not `nxdbooufqzkpslkcogxc`** | live · *the single most important production-safety check in the programme* |
| 3.5 | Every AI input column the functions select exists — no `42703` on any AI path | `test:contract` + a live probe per function |
| 3.6 | A forced safety-input read failure produces a **502 and no workout**; the same read returning `[]` still produces a workout | Deno test + live |
| 3.7 | The engine returns a non-empty, rule-justified selection for a realistic context, and `RECOVERY_REDUCTION` fires at recovery 59 | live |
| 3.8 | The engine consumes only knowledge admitted by **PD-A02**'s predicate | live |
| 3.9 | Every deployed function returns 401 without a token and 200 with one; the two currently-unauthenticated functions are deleted or gated per **PD-A13**/**PD-A14** | live, per function |
| 3.10 | `coach_text` reaches only the coach; audience is derived from the caller, not chosen by them | live |
| 3.11 | Every AI decision writes a complete, replayable trace with a recorded model id (per **PD-A07**) | live |
| 3.12 | No unbounded Anthropic call — every request carries a timeout, and a model refusal is detected rather than persisted as coaching | source + Deno test |
| 3.13 | `npm run test:ai` characterizations inverted to invariants, **in the same commit that fixes each one** | CI |
| 3.14 | Declared allergies reach the meal-plan prompt; the guard behaves per **PD-D02** | assert on the **outbound request body**, not the model's reply |
| 3.15 | PAR-Q risk constrains prescription per **PD-D01** | live |

**Exit:** AI produces correct, authorized, explainable, contract-valid output in QA.
**Owning wave: 5.**

> **Hard gate inside the gate:** rows 3.5 and 3.6 must pass **before** any AI *quality*
> assessment begins. Grading a model that was handed empty context produces findings about
> the wrong layer, and they are expensive to un-file.

---

## Gate 4 — Commerce enablement

| # | Requirement | Mechanism |
|---|---|---|
| 4.1 | Gate 2 met |
| 4.2 | A QA Stripe **test-mode** account, a QA webhook endpoint with its **own** signing secret, and five QA price ids exist; a QA runbook is committed | artifact |
| 4.3 | `verify_jwt = false` declared in `config.toml` for `stripe-webhook`, and `true` or explicit for the other 18 | Gate 0 row 0.10 |
| 4.4 | A replayed `checkout.session.completed` grants **exactly one** credit block | Deno test replaying a delivery + live |
| 4.5 | A free account cannot invoke a paid AI function — **proven server-side, not through the paywall UI** | live |
| 4.6 | A member cannot self-grant a paid event ticket | live, transaction-rolled-back |
| 4.7 | Booking a session consumes a credit atomically and is refused at zero balance | live |
| 4.8 | A coach cannot rewrite a credit balance or its owner | live |
| 4.9 | `invoice.paid` and `invoice.payment_failed` are handled; `payments` is a real ledger | live |
| 4.10 | A Stripe cancel failure leaves local access intact **and says so** | unit + live |
| 4.11 | A stale event cannot resurrect a cancelled subscription | live |
| 4.12 | Duplicate concurrent subscriptions are refused; **stacking behaves per PD-E06** | live |
| 4.13 | Tier representations reconciled — `client_plan()`, the Dart enum, the capability matrix, the paywall copy and the Stripe price ids agree (**PD-E08**) | static guard + live |
| 4.14 | Production billing mode resolved (**PD-E07**) | written answer |

**Exit:** no free-account path consumes paid resources, and billing state transitions are
server-authoritative. **Owning wave: 6.**
**No real production Stripe transaction at any point. Test mode only.**

---

## Gate 5 — Release candidate → staging

| # | Requirement |
|---|---|
| 5.1 | Gates 3 and 4 met |
| 5.2 | A staging environment exists, is **seed-free**, and is distinct from QA (**PD-A25**) |
| 5.3 | Migrations apply cleanly to a **fresh** database from `000` — this proves the sequence, not the accumulated QA state |
| 5.4 | The RC is built from a **tagged commit** with `dart_defines/staging.json` |
| 5.5 | Artifact scan: no production ref, no service-role key, no AI key, no Stripe secret |
| 5.6 | The artifact declares its `APP_ENV` and build SHA |
| 5.7 | Flavors exist with per-environment bundle identifiers; build numbers are CI-derived and unique |
| 5.8 | Error tracking is live in all three tiers, tagged by environment and release (**PD-A24**) |
| 5.9 | Every secret and price id is in a committed manifest, diffed against the live environment |
| 5.10 | Function deploys are automated with a recorded commit SHA; dependencies are pinned |
| 5.11 | A documented, rehearsed rollback exists **per layer** — database, functions, API, web, payment configuration |
| 5.12 | The NestJS API is deployed to staging with a health endpoint and enforced CORS (**PD-A17**) |
| 5.13 | Stripe test-mode end to end on staging: checkout → webhook → entitlement → portal → cancel |

**Exit:** a reproducible, provenance-carrying artifact pointing at a non-production
environment. **Owning wave: 8.** **Satisfies:** `G-06`, `G-10`, `G-11`, `G-12`, `G-14`, `G-15`.

---

## Gate 6 — Manual QA sign-off

*The gate the whole programme exists to reach.*

| # | Requirement |
|---|---|
| 6.1 | Gate 5 met |
| 6.2 | **Every P0 is `VERIFIED_CLOSED`** per [`QA_CLOSURE_STANDARD.md`](QA_CLOSURE_STANDARD.md) |
| 6.3 | **Every P1 is `VERIFIED_CLOSED` or explicitly `DEFERRED` with a named owner and a date** |
| 6.4 | Every product decision gating a **shipped** surface is answered and logged |
| 6.5 | Every shipped surface either works or is deliberately hidden — no route reaches a placeholder, no control is inert |
| 6.6 | The manual QA matrix is prepared: **22 surfaces × 10 conditions** |
| 6.7 | A full manual pass is executed on staging with no new P0 and no new P1 |
| 6.8 | Every defect found is filed against the registry with a canonical ID and a root cause |

**Matrix — surfaces:** authentication · onboarding · PAR-Q · program generation · workout ·
set logging · swap · resume · completion · check-in · nutrition · AI · messaging · coach
workflow · events · billing · account deletion · community · women's health · settings ·
failure & recovery · deep links.

**Matrix — conditions per surface:** happy path · invalid input · network failure ·
persistence failure · authorization failure · retry · refresh · app restart · concurrent
action · offline / poor connection.

**Standing rule for every cell:** *a success state may be shown only when authoritative
evidence confirms the underlying operation succeeded.* A tester who sees a success message
must be able to confirm the row exists.

**Exit:** human QA is testing the product, not discovering architectural defects.
**Owning wave: 9.**

---

## Gate 7 — TestFlight internal

| # | Requirement |
|---|---|
| 7.1 | Gate 6 met |
| 7.2 | An archive can be produced: CocoaPods integrated and committed (`Podfile` + `Podfile.lock`); `IPHONEOS_DEPLOYMENT_TARGET` raised to cover every plugin; team, entitlements and provisioning profile in place with a modern signing identity |
| 7.3 | Android release builds sign with a real upload keystore wired from `key.properties`; a debug-signed release build **fails** |
| 7.4 | No QA route resolves in a release build |
| 7.5 | The build is provably staging-pointed |
| 7.6 | Sign-in, Sign in with Apple, Google Sign-In and password reset are verified **on a device** — deep-link return path registered end to end |
| 7.7 | Build number unique and CI-derived |
| 7.8 | Crash reporting live with dSYMs uploaded |
| 7.9 | One canonical product name and one bundle identifier (**PD-F04**) — **settled before the App ID is registered, because it is immutable afterwards** |

**Exit:** internal testers can install and sign in. **Owning wave: 8.**

---

## Gate 8 — TestFlight external / Beta App Review

| # | Requirement |
|---|---|
| 8.1 | Gate 7 met |
| 8.2 | In-app account deletion shipped and verified end to end — including Stripe cancellation, storage cleanup and an audit record (**PD-B22**) |
| 8.3 | The purchase architecture is implemented per **PD-F01** |
| 8.4 | Report, block and moderation shipped for every UGC surface, with a published EULA and a **staffed** 24-hour takedown SLA (**PD-F03**, **PD-C04**) — or those surfaces are disabled on iOS |
| 8.5 | Hosted privacy policy, terms and support URLs are live on a domain the project provably controls; Terms of Service is reachable from Settings |
| 8.6 | `PrivacyInfo.xcprivacy` declares collected data types and required-reason API usage; `ITSAppUsesNonExemptEncryption` declared |
| 8.7 | The App Privacy questionnaire is answered truthfully — **every health-data safety claim in it must be true of the shipped build**, which is why Gates 2 and 3 precede it |
| 8.8 | No integration appears connectable unless it genuinely connects (**PD-B23**) |
| 8.9 | Beta feedback channel staffed; the feedback board is in use |

**Exit:** external testers can be admitted. **Owning wave: 8.**

---

## Gate 9 — App Store submission → production rollout

*Two stages. The second is the only point at which production is touched, and only under explicit, separate authorization.*

### 9A — Submission

| # | Requirement |
|---|---|
| 9A.1 | Gate 8 met and a beta cycle completed with no open P0 or P1 |
| 9A.2 | Full App Store Connect metadata prepared: screenshots at every required size, description, keywords, subscription display names and localised descriptions, review notes, and a working demo account |
| 9A.3 | The demo account exercises a coach dashboard that is **not** backed by a phantom table |
| 9A.4 | Accessibility audit complete — `product-bible.md` §4 names accessibility a requirement, not a polish item |
| 9A.5 | Every user-visible "TODO", "coming soon", mock and placeholder is triaged |

### 9B — Production rollout *(explicitly authorized, separately, in writing)*

| # | Requirement |
|---|---|
| 9B.1 | 9A met |
| 9B.2 | **Production's `supabase_migrations.schema_migrations` and live catalogue are dumped and reconciled against source**, and the reconciliation report is reviewed |
| 9B.3 | Every known or suspected production divergence is resolved: the `dietary_restrictions` column type (**PD-A22**); whether `083/084/086/087/090/091/097/099` ever applied; migration 109's trigger; 076's cron target and `B2-6` correction |
| 9B.4 | An explicit, reviewed, **reversible** rollout script exists for every migration production will receive, with a tested restore procedure |
| 9B.5 | The client release that migrations 102 and 113 require **ships first** — including the five surfaces `H-06` shows were never repointed |
| 9B.6 | A restore drill has been performed on a production-shaped clone |
| 9B.7 | Stripe live mode verified with a real low-value transaction **and a refund** |
| 9B.8 | Monitoring dashboards live and watched; a named on-call owner for launch week |
| 9B.9 | A kill switch is identified for each risky surface — AI generation, marketplace, payments |
| 9B.10 | Phased release enabled (Apple's staged rollout) |

**Exit:** public availability. **Owning wave: 10.**

> **Standing rule for the entire programme, restated here because this is the only gate
> where it can be violated:** production `nxdbooufqzkpslkcogxc` is not connected to,
> queried, migrated, deployed to, or configured by any wave before 9B, and 9B requires its
> own explicit authorization. **A script is not safe because its filename says QA** —
> three currently do, and all three target production.

---

## Appendix — Workstream L's mechanical conditions, mapped

| L condition | Gate row |
|---|---|
| `G-01` `APP_ENV` defaults to dev | 0.6, and Wave 1 W1-A1 |
| `G-02` no production ref outside three homes | 0.6 |
| `G-03` migrations tracked | 0.7 |
| `G-04` in-place corrections carried forward | 1.3 |
| `G-05` CI exists and runs | Gate 0 entire |
| `G-06` API deployment target, health endpoint, CORS, `API_BASE_URL` | 5.12 |
| `G-07` Android release keystore | 7.3 |
| `G-08` reverse scripts rehearsed; PITR resolved | 1.8, 1.9 |
| `G-09` production history reconciled | 9B.2 |
| `G-10` `verify_jwt`, secret manifest, pinned deps, automated deploy, Vault runbook | 0.10, 3.2, 5.9, 5.10 |
| `G-11` Stripe mode and price manifest per environment | 4.2, 4.13, 4.14 |
| `G-12` flavors, beta defined, build numbers, provenance, iOS surface, one name | 5.4–5.7, 7.9 |
| `G-13` QA routes absent; auth redirects declared | 0.11, 7.6 |
| `G-14` error tracking in all tiers; audit log | 5.8 |
| `G-15` rollback per layer | 5.11 |
| `G-16` `.temp` untracked; reset wrapper guarded; runbooks exist | Wave 1 W1-B4, W1-B7 |
