# 12CIRCLE FITNESS — FINAL QA COMPLETION REPORT

**Date:** 2026-09-27 · **Branch:** `reconcile/12circle-integrated` · **HEAD:** `07f5bfb` (unchanged)
**Scope:** 12 Circle Fitness only. Production ref `nxdbooufqzkpslkcogxc` never contacted.

> **NOT A HIPAA COMPLIANCE STATEMENT.** No compliance claim is made in this document.

---

## 1 · FINAL QA PERCENTAGE

### **FINAL QA STATUS: 90.0%**
### **QA STATE: QA COMPLETE WITH OPEN FINDINGS**

**Superseded figures (historical, retained deliberately):** 78.9%, 84%, 90.5%, 89.3%.
The 78.9%/84% pair additionally inherited an arithmetic error (divided by 19 while
enumerating 21 domains). **This report is authoritative.**

## 2 · DENOMINATOR

**21 QA domains.** Scored 1.0 / 0.9 / 0.75 / 0.5 / 0. Inherited from the prior enumeration
so the figure stays comparable; disclosed so a reader can re-score.

| Score | Domains | Points |
|---|---|---|
| 1.0 | 15 (13 carried + CI/CD + app runtime) | 15.00 |
| 0.9 | test completeness | 0.90 |
| 0.75 | PHI table access · supply chain | 1.50 |
| 0.5 | AI/processors · privacy alignment · replay harness | 1.50 |
| **Total** | **21** | **18.90** |

**18.90 / 21 = 90.0%**

### Why the state is COMPLETE at 90%

The two measure different things, and conflating them is the error this report avoids:

* **The percentage measures evidence density** — how much of each domain is backed by
  executed evidence.
* **The state measures whether QA has anything left it can legitimately do.** It does not.

Every one of the 21 domains now holds a terminal disposition — VERIFIED, VERIFIED WITH
FINDING, or BLOCKED WITH A DOCUMENTED REASON. **The entire residual 10% is boundary-blocked**,
and every boundary is one QA was instructed not to cross or the environment does not provide:
writes to shared QA, installing tooling, Docker, and (newly discovered) **HTTPS egress being
down in this environment**. §18 itemises each with the exact authorization or provisioning
that would close it. Reaching 100% requires **permission or infrastructure, not further
analysis**.

### What changed from 89.3% → 90.0%

| Gain | Evidence |
|---|---|
| API tier verified **at HEAD** | 64 tests executed locally (§6) |
| Contract tier verified **at HEAD** | offline suite executed (§9) |
| All **six** blinded static gates evidenced | run independently — **all PASS** (§12) |
| The 2 remaining tiers precisely diagnosed | authorization vs network egress, not "unknown" (§7–8) |
| 9 skipped tests programmatically adjudicated | assertion-level replication (§10) |

The gain is modest because the large remaining items are authorization-bound, not
analysis-bound. **Two findings were corrected downward in the process** (§12, §10) — the work
removed as much overstatement as it added coverage.

---

## 3 · COMPLETE DOMAIN LEDGER

| # | Domain | Status | Evidence | Remaining blocker |
|---|---|---|---|---|
| 1 | Direct authorization | VERIFIED WITH FINDING | live `pg_policies` sweep | — |
| 2 | Composition / chains | VERIFIED WITH FINDING | P0, F-03b, NEW-2 chains traced live | — |
| 3 | RLS coverage | VERIFIED | 91 tables, 0 RLS-disabled, 0 zero-policy | — |
| 4 | `FOR ALL` / `WITH CHECK` shape | VERIFIED WITH FINDING | 37 policies / 34 tables enumerated live | — |
| 5 | SECURITY DEFINER / RPC | VERIFIED | 0 mutable `search_path` | — |
| 6 | Storage | VERIFIED | `storage.buckets` read; 3 public / 2 private | — |
| 7 | D-02 role escalation | VERIFIED | live probe (prior wave) | — |
| 8 | Correction rights | VERIFIED WITH FINDING | CORR-1/2/3 adjudicated | — |
| 9 | Error handling | VERIFIED | ERR-G2, 38 sites closed | — |
| 10 | Lifecycle | VERIFIED | prior wave | — |
| 11 | PHI egress | VERIFIED | prior wave | — |
| 12 | Audit logging | VERIFIED WITH FINDING | prior wave | — |
| 13 | Data-subject rights | VERIFIED | prior wave | — |
| 14 | CI/CD | VERIFIED WITH FINDING | run `36093979157` + 6 gates run locally | — |
| 15 | App runtime | VERIFIED | mobile suite executed | — |
| 16 | **Test completeness** | **0.9 — VERIFIED WITH FINDING** | 3 of 5 tiers executed at HEAD | 2 tiers: shared-QA mutation + HTTPS egress |
| 17 | **PHI table access** | **0.75 — PARTIAL** | universal RLS coverage proven | per-table demos need writes to shared QA |
| 18 | **Supply chain** | **0.75 — PARTIAL** | SBOM ABSENT (6/6 questions answered); npm audit | SBOM tooling forbidden; no Dart-tree scanner |
| 19 | **AI / processors** | **0.5 — PARTIAL** | traced statically | disclosure is an owner decision |
| 20 | **Privacy alignment** | **0.5 — PARTIAL** | matrix complete | owner decision |
| 21 | **Replay harness** | **0.5 — BLOCKED** | no Postgres server; Docker down | Docker; installing forbidden |

### Grouped, as required

| Group | Count | Domains |
|---|---|---|
| **COMPLETED** (1.0) | **15** | direct authorization · composition · RLS coverage · FOR-ALL/WITH-CHECK · DEFINER/RPC · storage · D-02 · correction rights · error handling · lifecycle · PHI egress · audit logging · data-subject rights · CI/CD · app runtime |
| **PARTIALLY COMPLETED** | **5** | test completeness (0.9) · PHI table access (0.75) · supply chain (0.75) · AI/processors (0.5) · privacy alignment (0.5) |
| **BLOCKED** | **1** | replay harness (0.5 — credited for the diagnostic work; no Docker, no Postgres server) |
| **NOT APPLICABLE** | **0** | none — every defined domain applies to this system |

**Arithmetic:** (15 × 1.0) + 0.9 + 0.75 + 0.75 + 0.5 + 0.5 + 0.5 = **18.90**.
**18.90 / 21 = 0.9000 → 90.0%.**

**The residual 2.10 points** = test completeness 0.10 + PHI access 0.25 + supply chain 0.25 +
AI 0.50 + privacy 0.50 + replay 0.50 = **2.10**. Calculated from the ledger, not estimated.

**The percentage did not move in this continuation, and that is the correct result.** Phase C
converted the API tier from *"passed in CI at an older commit"* to *"executed at HEAD, twice,
hermetically"* — a real strengthening of evidence **quality** — but the tier was already scored
as verified when the API run was first completed, so no domain score changed. Inflating the
figure to reward re-verification would misreport it.

---

## 4 · TEST TIER STATUS

| Tier | Current HEAD | Execution status | Result | Blocker | Evidence |
|---|---|---|---|---|---|
| `test:mobile` | `07f5bfb` | **EXECUTED** | **VERIFIED PASS** — 1,675 pass / 9 skipped / 0 fail | — | run this mission, 1:13, ≈5 MiB disk |
| `test:api` | `07f5bfb` | **EXECUTED ×2** | **VERIFIED PASS** — 64 pass (58 unit + 6 e2e) | — | §6; passed with credentials unset and egress severed |
| `test:contract` | `07f5bfb` | **EXECUTED** | **VERIFIED PASS** — 91 tables / 5 views / 134 FKs | — | §9; header: *"Offline. Contacts no environment."* |
| `test:security` | `07f5bfb` | **NOT EXECUTED** | **BLOCKED** | **shared-QA mutation** (authorization) + network | suite header: *"arrange and tear down the same four identities and the same relationship rows"* |
| `test:ai` | `07f5bfb` | **ATTEMPTED, aborted** | **BLOCKED — not a failure** | **HTTPS egress unavailable** | 5 × `SUITE ERROR: fetch failed`; `api.github.com` → HTTP 000 |

**3 of 5 tiers VERIFIED PASS at current HEAD. 2 BLOCKED, each with a distinct documented cause.**
No tier is recorded as `VERIFIED FAIL`, because none produced a genuine assertion failure.

**Newly discovered environmental fact:** **outbound HTTPS (443) is unavailable in this
environment** — `api.github.com` and the Supabase REST endpoint both return HTTP 000 after a
12 s timeout, while the **PostgreSQL path works** (`psql` reached QA successfully). This is
why the catalog introspection in §15 is valid while the REST-based tiers are not runnable. It
is a second, independent blocker on the live tiers, distinct from the CI-secrets gap.

## 5 · MOBILE TEST RESULTS

**1,675 PASS · 9 SKIPPED · 0 FAIL.** Runtime 1:13. Disk 5094 → 5089 MiB ≈ **5 MiB**.
Analyzer: 0 errors, 312 infos.

**Retraction carried forward:** attributing disk exhaustion to `flutter test` is **withdrawn**;
measured consumption is ≈5 MiB. Not repeated.

## 6 · API TEST RESULTS — **VERIFIED PASS AT HEAD**

Executed at HEAD `07f5bfb`, **twice**, reproducibly:

| | |
|---|---|
| Unit | `jest` — **8 suites, 58 tests, all pass** (1.5 s, then 1.25 s) |
| E2E | `jest --config ./test/jest-e2e.json` — **2 suites, 6 tests, all pass** (1.1 s, then 0.45 s) |
| **Total** | **64 tests, 0 failures** |

### Phase C interrogation — all eight questions, with evidence

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | What changed `8641c17..07f5bfb`? | **5 files** | `M settings_screen.dart` · `M correction_rights_guard_test.dart` · `A privilege_chain_guard_test.dart` · `M docs/proposed/SEC_PHI_1_*.sql` · `M docs/proposed/SEC_PHI_9_*.sql` |
| 2 | Could any changed file affect API behaviour? | **No** | nothing under `apps/api/`, no `package.json`/`package-lock.json`, no `supabase/functions/`. Three mobile files and two **unapplied proposal** SQL documents |
| 3 | Can it run safely at current HEAD? | **Yes — and it did** | 64 pass, two consecutive runs |
| 4 | Requires Docker? | **No** | no `testcontainers`/`dockerode`/`docker-compose`/`GenericContainer` reference anywhere in `apps/api` |
| 5 | Requires network egress? | **No — positively proven** | the suite passed **while outbound HTTPS was down** (`api.github.com` → HTTP 000). A pass under a severed network is direct proof of independence, not an assumption |
| 6 | Requires credentials? | **No — positively proven** | 4 env vars are referenced (`ANTHROPIC_API_KEY`, `APP_ENV`, `JWT_SECRET`, `SUPABASE_JWT_SECRET`); re-run with `env -u ANTHROPIC_API_KEY -u JWT_SECRET -u SUPABASE_JWT_SECRET` → **still 64 pass** |
| 7 | Mutates shared QA? | **No** | no live client is constructed in the test path; the suite is hermetic, which #5 and #6 jointly demonstrate |
| 8 | Can it run isolated/locally? | **Yes** | it is fully local; that is how both runs were performed |

**Status: VERIFIED PASS.** Two independent arguments establish this as *current-HEAD* evidence:
direct execution at HEAD, **and** the API surface being byte-identical to the green CI commit.

> **Neither inference was used.** Current-HEAD success was **not** inferred from the older CI
> result — the suite was actually run. And current-HEAD failure was **not** inferred from the
> earlier lack of execution. Both are recorded as the brief requires.

## 7 · SECURITY TEST RESULTS — **BLOCKED** (not failed)

| | |
|---|---|
| Command | `node supabase/tests/security/run.mjs` |
| Blocker 1 | **shared-state mutation.** Its own header: the suites *"arrange and tear down the same four identities and the same relationship rows."* Writes to shared QA were declined earlier and were not routed around |
| Blocker 2 | **HTTPS egress unavailable** (§4) |
| Credentials | present locally — **credentials were never the blocker** |
| Last verified evidence | prior waves' individual live probes (D-01…D-09) |
| Current-HEAD status | **NOT EXECUTED — BLOCKED** |

## 8 · AI TEST RESULTS — **BLOCKED** (not failed)

| | |
|---|---|
| Command | `node supabase/tests/ai/run.mjs` |
| Write safety | **read-only by default** — `ALLOW_WRITES = process.env.AI_ALLOW_WRITES === '1'`, and the suites contain **zero** unconditional write calls. Authorization was **not** the blocker |
| Attempted | **yes**, with `AI_ALLOW_WRITES` unset |
| Observed | all 5 suites: `SUITE ERROR: fetch failed`, summary `-5/0` |
| Interpretation | **BLOCKED, NOT VERIFIED FAIL.** `fetch failed` is transport, not assertion. The `-5/0` is an infrastructure artifact and is **explicitly not recorded as a failure** |
| Current-HEAD status | **BLOCKED — HTTPS egress** |

## 9 · CONTRACT TEST RESULTS — **VERIFIED PASS AT HEAD** (new)

`node supabase/tests/contract/run.mjs` — header: *"Offline. Contacts no environment."*
No credentials, no network, no mutation.

```
Schema contract guard — 91 tables + 5 views + 134 foreign keys derived from supabase/migrations
  known  relation checkins                         I-CHK-01  (7 sites)
  known  relation coach_tips                       I-LEG-03  (1 site)
  known  column   event_registrations.ticket_code  I-COM-01  (1 site)
PASS  no unknown relation or column outside the 3-entry known-violations allowlist
```

Its independently-derived **91 tables** matches the live catalog count in §15 exactly — a
useful cross-validation of source-derived and database-derived inventories.

## 10 · THE 9 SKIPPED TESTS — DISPOSITIONS

All nine sit in `test/unit/billing_entitlement_contract_test.dart` under *"OPEN SPECS — each
is the regression guard for a finding that is still open. Remove the `skip:` when the fix
lands."* All are **intentional**, **not environment-dependent**, and **security- or
billing-integrity-relevant**. None is obsolete. **None can be executed without editing the
repository**, which is forbidden — so each assertion was **replicated programmatically in a
scratchpad** against the same files the test reads.

| Spec | Assertion replicated | Would | Can execute now? |
|---|---|---|---|
| K-01 | literal `'event.id'` present **and** no bare `client_session_credits.insert(` | **FAIL** — literal `event.id` = **0** | no (skip) — **genuinely open** |
| K-02/K-06 | 4 Stripe events present | **FAIL** — all 4 absent | no — genuinely open |
| K-03 | `active_membership`/`client_plan` in 3 AI fns | **FAIL** — absent in all 3 | no — genuinely open |
| K-04 | exact policy string absent from migration 001 | **FAIL** — present at `001:399` | no — genuinely open (live-confirmed §15) |
| K-05 | `client_session_credits` in booking screen | **FAIL** — absent | no — genuinely open |
| K-07 | "continuing to mark local" log absent | **FAIL** — present | no — genuinely open |
| K-09 | `max_clients` in the `subscription.deleted` branch | **PASS** | **STALE SKIP** |
| K-12 | `[functions.stripe-webhook]` + `verify_jwt = false` | **PASS** | **STALE SKIP** |
| K-ENV-1 | `qa_entitlements.dart` free of the production ref | **PASS** | **STALE SKIP** |

**3 stale · 6 genuinely open.**

> **CORRECTION TO THIS REPORT'S PREVIOUS REVISION.** It said **4 stale / 5 open**, counting
> K-01 as stale. That was **my own detector error**: I used `grep -c "event.id"`, where `.` is
> a regex wildcard, so it matched `event_id` (3 occurrences). The Dart assertion is a
> **literal** `contains('event.id')`, and literal occurrences are **0**. K-01 is **genuinely
> open**. Caught by replicating the assertion exactly instead of approximating it — the
> seventh detector-precision error in this programme, and the first found by assertion-level
> replication.

**Precision limit, and where the residual risk actually sits.** Two of the three stale specs
turn out to have **redundant live coverage**, which narrows NEW-7 considerably:

| Stale spec | Redundant coverage | Residual regression risk |
|---|---|---|
| **K-12** | **E-09 gate** (§12) — verifies the webhook's `verify_jwt` posture is declared and unique. Independently **PASS** | **low** — double-covered |
| **K-ENV-1** | **ENV-5 gate** — `git grep -l --fixed-strings --untracked` over the whole repo with a shrinking allowlist that does **not** include `qa_entitlements.dart`. A reintroduced ref there **would fail the gate**, and this gate is the one that actively runs | **low** — double-covered |
| **K-09** | **none found** | **this is where NEW-7's real risk concentrates** |

So NEW-7 remains a valid finding on two grounds — three guards are inert, and the ledger
**overstated open findings by three** — but the *regression-detection* exposure is essentially
**K-09 alone**.

**K-09's assertion is additionally a proxy**: the presence of `max_clients` inside the
`customer.subscription.deleted` branch is not proof the capacity logic is correct.
**Do not auto-close on a passing proxy** — it needs remediation review, not an unskip.

**Also noted, not claimed as closure:** the webhook *does* carry partial idempotency —
`meta.event_id` with `onConflict: 'event_id,user_id'` — so K-01 may be partly addressed even
though its spec fails. That is a remediation-review question.

## 11 · CI/CD STATUS

Run `36093979157`, commit `8641c17`. **CONFIGURED ≠ EXECUTED ≠ PASSED.**

| Job | Configured | Executed | Result |
|---|---|---|---|
| Flutter — analyze, test, QA web build | ✅ | ✅ | **SUCCESS** |
| API — unit + e2e | ✅ | ✅ | **SUCCESS** |
| Static guards | ✅ | ✅ | **FAILURE** |
| Negative control | ✅ | ❌ | skipped |
| I-WRK-01 live progression | ✅ | ❌ | skipped |
| Live QA suites | ✅ | ❌ | skipped |
| UIX-1 booking e2e | ✅ | ❌ | skipped |

**7 configured · 3 executed · 2 passed · 1 failed · 4 never executed.**

### ENV-5 — the failing gate (documented, NOT fixed)

| | |
|---|---|
| Gate | **Production-ref guard (ENV-5)**, `.github/scripts/check-production-refs.sh` — **step 1 of 7** |
| Affected file | `apps/mobile/tool/anon_least_privilege.py` |
| Why it fails | names the production ref as a **refusal constant**, outside the shrinking allowlist |
| Why allowlisting is prohibited | the gate states *"Do not add an entry to silence a failure — repoint the file."* An allowlist entry is explicitly **not a fix** |
| Prescribed remediation | resolve the target from the environment with **no default** — the `resolveQaTarget()` pattern that closed LRE-02/REL-18 |
| QA impact | see §12 — **latent, not active** |

## 12 · STATIC-GUARD STATUS — CI EXECUTION ≠ UNDERLYING GATE STATUS

> **BOTH FACTS ARE TRUE AND BOTH ARE RETAINED. Neither erases the other.**
>
> | | |
> |---|---|
> | **A. CI execution status** | **`static-guards` FAILED.** ENV-5 failed at step 1 and short-circuited the remaining six steps, which CI therefore records as **unevaluated**. The CI job did **not** pass, and this report does **not** claim it did |
> | **B. Independent underlying gate status** | **6 / 6 PASS**, established locally, read-only |
>
> The distinction matters: **"unevaluated in CI" is not "failing"**, and **"the underlying
> check passes" is not "CI is green."** The repository's *gate logic* is sound; its *gate
> execution* is broken.

### All six independently VERIFIED PASS

`static-guards` declares **no `continue-on-error` and no `if:`** on any step, so ENV-5's
failure at step 1 aborts the job and six later gates **never execute in CI**. Rather than
infer their behaviour, each was run locally, read-only, from the repository as-is (the four
inline `run:` blocks were extracted to a scratchpad; the repository was not modified):

| Gate | Mechanism | Result |
|---|---|---|
| ENV-1 migration hygiene | `check-migration-hygiene.sh` | **PASS** — tracked & clean; filenames conform; 132 migrations, unique; contiguous 000–131 |
| I-MIG-03 migration durability | inline | **PASS (enforcing)** — 0 recorded known-open, 0 unrecorded, 1 sweep-claimed |
| ENV-3 migration state declaration | inline | **PASS** — every authored migration declared and vice versa (static half only) |
| Schema contract guard | inline | **PASS** — 91 tables / 5 views / 134 FKs; 3 allowlisted knowns |
| **E-09 Edge Function JWT posture** | `check-edge-function-config.sh` | **PASS** — 19 functions declare a posture; no missing; no duplicates; **`stripe-webhook` is the only `verify_jwt = false`** and still verifies its Stripe signature |
| ENV-4 no baked-in project | inline | **PASS** — `app_env.dart` carries no baked-in project |

> **FINDING NEW-8 DOWNGRADED P2 → P3.** The previous revision recorded the blast radius as six
> blinded gates and left their state unknown, correctly refusing to infer failure. **All six
> actually PASS.** So nothing is being hidden *today*: the defect is **latent** — a future
> regression in any of these six would go undetected — not active breakage. This is precisely
> the "unexecuted ≠ failing" trap, and the downgrade is the evidence-led result.

**E-09 independently corroborates K-12** (§10): the gate confirms the webhook's `verify_jwt`
posture is declared and unique. Two independent confirmations that K-12 is closed.

## 13 · LIVE-QA STATUS — **BLOCKED**

| | |
|---|---|
| Jobs | Negative control · I-WRK-01 · Live QA suites · UIX-1 (4 of 7) |
| Gate | `steps.creds.outputs.present == 'true'`, from repo secrets `QA_URL` / `QA_ANON` / `QA_SERVICE` |
| Why never executed | the secrets are **not configured** — the jobs skipped |
| Second blocker | **HTTPS egress unavailable locally** (§4), so the tier cannot be reproduced outside CI either |
| Actions taken | **none.** No secret added, exposed, copied or fabricated; gate not bypassed; CI never pointed at production |

**Non-secret static evidence that does cover parts of these domains:** the contract tier
(§9), the six static gates (§12), the live *catalog* introspection over the Postgres path
(§15), and the mobile/API tiers (§5–6). What remains genuinely unverified: **runtime
request/response behaviour of the deployed QA stack** — live RLS decisions under real JWTs,
Edge Function responses, and the booking paywall end-to-end. Those need either CI secrets or
HTTPS egress.

## 14 · SBOM STATUS — **ABSENT** (final disposition)

| Question | Evidence | Answer |
|---|---|---|
| Any artifact qualifying as an SBOM? | `git ls-files` for `sbom\|cyclonedx\|spdx\|bom.json\|bom.xml` → **0 tracked** | **No** |
| Any CI job generating one? | workflow grep for `sbom\|cyclonedx\|spdx\|syft\|trivy\|grype\|snyk\|codeql\|dependency-review\|osv` → **0 matches** | **No** |
| Any release artifact containing SBOM data? | no SBOM step in any job; no release workflow emits one | **No** |
| Do lockfiles provide partial inventory? | `package-lock.json` 12,033 lines; `pubspec.lock` 1,689 lines | **Partial inventory only** — resolved versions + integrity hashes, but no component identity, licence, supplier or relationship data. **A lockfile is not an SBOM** |
| Does `npm audit` give useful evidence? | **17 advisories — 7 high, 9 moderate, 1 low.** Direct deps: `@nestjs/platform-express`, `firebase-admin`. High: multer DoS, brace-expansion DoS, browserslist, fast-uri host confusion, form-data CRLF injection, js-yaml quadratic DoS | **Yes — preserved** |
| Is SBOM capability genuinely absent? | `cyclonedx-npm`, `syft`, `trivy`, `cdxgen` all **not installed**; installing is forbidden | **Yes — ABSENT** |

**`npm audit` is NOT an SBOM and is not claimed as one.** It enumerates *known vulnerabilities*
in the npm tree; an SBOM enumerates *components*. Different questions; neither substitutes.

**Residual gap:** **no vulnerability evidence exists for the Dart/Flutter tree** — no `pub
audit` equivalent without tooling — and that is where the mobile app's dependencies live.
`npm audit` covers the API/Node surface only. This is why the domain scores 0.75.

## 15 · RLS STATUS

Live catalog, read-only (`default_transaction_read_only=on`, verified in-band), over the
Postgres path. The `postgres` role (`rolbypassrls = t`) was used **only to read catalog
metadata** — never to satisfy a policy or take an authorization decision.

| Check | Result |
|---|---|
| Public tables | **91** — all `relkind='r'`; no partitioned or foreign tables, so the sweep missed none |
| RLS disabled | **0** |
| RLS enabled but **zero policies** | **0** |
| Policies granted to `anon` / `PUBLIC` | **0** |
| `anon` table grants | **0** |
| SECURITY DEFINER with mutable `search_path` | **0** |
| 5 AI tables | RLS enabled, 1 policy each — **confirms the SEC-DRIFT-1 retraction** |
| Buckets | `avatars`, `coach-media`, `exercise-media` **public**; `chat-media`, `progress-photos` **private** |
| `FOR ALL` / no-`WITH CHECK` | **37 policies across 34 tables**; source analysis counted 33 — the catalog reveals 3 tables carrying two matching policies each (`coach_availability`, `coaching_calls`, `nutrition_logs`) |
| The 18 look-alikes | **remain DISPROVED** for the F-21 class (all compare `user_id`) |

## 16 · P0 / P1 SECURITY FINDINGS

### P0 (1) — QAX-SEC-08 · self-assertion → team-lead → PHI read

| | |
|---|---|
| Root cause | `002:146` — `FOR ALL USING (coach_id = auth.uid())`, **no `WITH CHECK`** → `USING` reused as the INSERT check |
| Live confirmation | `pg_policies.with_check` **IS NULL** |
| Exploitability | **any authenticated account — no role of any kind required.** `has_role_check = false`: the predicate calls neither `is_coach_profile()` nor any `role` test |
| Chain | self-asserted row → `is_team_lead_of()` (**live body: no status/active condition**) → `user_profiles` SELECT arm |
| Affected data | `parq_answers`, `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`, `membership_tier`, billing flags |
| Test status | **NOT EXECUTED** — needs an INSERT into shared QA (declined). **LIVE-CATALOG-CONFIRMED at all three links** |
| Residual | **full** — unremediated |

### P1 (4)

| ID | Evidence / status | Test status | Residual |
|---|---|---|---|
| **F-03b** | `may_notify()` trusts `coach_team_members` (self-assertable) and `coach_client_relationships` at **any status** → `notifications` INSERT. Live body read: **neither anchor filters status** | NOT EXECUTED; links live-confirmed | full |
| **QAX-SEC-09** | vendor over-disclosure, **not attacker-forgeable** — `events` `FOR ALL` *has* a `WITH CHECK` requiring `vendor_id = auth.uid()` **and** `role IN ('vendor','admin')` (`020:18–26`). `role='vendor'` is self-selectable, so "legitimate vendor" is a low bar; the binding constraint is the victim's voluntary registration | **STILL NOT TESTABLE** — `events.vendor_id` is NULL on both QA events, so `hosts_event_for()` can never be true | full |
| **SEC-PHI-9 / SEC-PHI-10** | the only two policies joining `coach_client_relationships` without a status predicate — `storage.objects` and `score_events`; the other three require `status='active'`. Live-confirmed | 9 **VERIFIED live**; 10 **INCONCLUSIVE** — all 8 `score_events` belong to the *active*-relationship client; the `cancelled` client has 0 | 9 full; 10 unproven |
| **SEC-AI-1** | carried from the AI privacy audit | carried | full |

### Classification under the required taxonomy

| Finding | Classification | Justification |
|---|---|---|
| **QAX-SEC-08** (P0) | **OPEN / PARTIALLY VERIFIED** | every link of the chain read from the live catalog (`with_check` NULL; `is_team_lead_of` body; the `user_profiles` arm; `has_role_check = false`). The **composed exploit was not executed** — that needs a write to shared QA. Not "INFERRED": the mechanism is catalog-confirmed, not deduced from migration text |
| **F-03b** (P1) | **OPEN / PARTIALLY VERIFIED** | `may_notify`'s body read live; neither anchor filters status; the `notifications` INSERT policy confirmed. Exploit not executed |
| **QAX-SEC-09** (P1) | **OPEN / BLOCKED** | not attacker-forgeable (the `events` `WITH CHECK` requires `vendor_id = auth.uid()` **and** `role IN ('vendor','admin')`). **Cannot be tested at all** with current fixtures: `events.vendor_id` is NULL on both QA events, so `hosts_event_for()` can never return true |
| **SEC-PHI-9** (P1) | **OPEN / VERIFIED** | reproduced live in a prior wave — a `cancelled`-relationship coach signed a client's progress-photo object (200) while being correctly denied that client's profile, PAR-Q, check-ins, weights, measurements and AI data. Policy text re-confirmed in the live catalog this wave |
| **SEC-PHI-10** (P1) | **OPEN / INFERRED** | policy text live-confirmed to omit the status predicate, but **no execution is possible**: all 8 `score_events` rows belong to the *active*-relationship client (where coach access is correct); the `cancelled` client has 0 rows. Source-confirmed only — **explicitly not recorded as reproduced** |
| **SEC-AI-1** (P1) | **OPEN / INFERRED** | carried from the AI privacy audit; the AI tier could not be executed (§8) |

**No finding was downgraded or closed because exploitation was not attempted.** SEC-PHI-9 is the
only one carrying live reproduction, and it is the only one marked VERIFIED.

**Phase H conclusion — the QA question, not the fix question.** For the P0 and F-03b the
evidence gap **narrowed** this wave (catalog-confirmed at every link) but did not close: both
remain **unexecuted**, and closing that needs a write to shared QA. QAX-SEC-09 is **provably
not testable** with current fixtures. SEC-PHI-10 is inconclusive **for a precisely known
reason**. All four are therefore **sufficiently tested and documented for QA purposes**, while
remaining **open for remediation**. No finding was closed because a proposal exists.

### P2 / P3

| ID | Sev | Finding |
|---|---|---|
| NEW-2 | P2 | self-assignment → read of any coach's program: `workout_program_assignments` `with_check` NULL, **0 triggers, 0 check constraints**, INSERT granted, `status` ignored by `can_read_program()`, which gates `workout_programs` + `program_workouts`. Write direction was F-21b; the **read** direction is new |
| NEW-5 | P2 | `SEC_PHI_1` proposal **non-functional as written** — `security_invoker = on` plus dropping the base arms makes both views return `200 []` for the users they serve. House pattern (SEC-G4) is `off` + `security_barrier` + predicate inside the view |
| NEW-7 | P2 | **3** stale skips (K-09, K-12, K-ENV-1) — regression guards inert |
| QAT-1 / ENV-5 | P2 | `anon_least_privilege.py` names the production ref; blocks step 1 of static-guards |
| **NEW-8** | **P3** *(downgraded)* | ENV-5 blinds six gates — **all six verified PASS**, so latent not active |
| NEW-9 | P3 | live-QA CI tier never executed (secrets absent) |
| NEW-3 | P3 | `coach_reviews` not gated on a completed relationship; `recalc_coach_rating()` feeds a published rating |
| K-01, K-02/K-06, K-03, K-04, K-05, K-07 | P2/P3 | 6 genuinely open billing/entitlement specs |

### Corrections and retractions (cumulative)

1. **NEW-1 (`public_profiles` RLS bypass) — RETRACTED IN FULL.** Mechanism real; finding wrong.
   Migration 101 documents the bypass as **deliberate**; **SEC-G4** already guards it; the one
   sensitive column is owner decision **OD-58**; and `transformation_photo_urls` is written at
   exactly one coach-only site. My premise — that the view layer was unexamined — was false.
2. **NEW-6 — NOT NEW.** The prior report already recorded SEC-G1's name filter as *"correct in
   effect but accidental in mechanism."*
3. **NEW-4 — WITHDRAWN.** `workout_feedback` compares `user_id`; covered by the 18/18 analysis.
4. **NEW-3 — DOWNGRADED** to P3; `client_id = auth.uid()` asserts no role, so not F-21 class.
5. **NEW-8 — DOWNGRADED** to P3 (§12): all six gates pass.
6. **K-01 reclassified stale → genuinely open** (§10); 4 stale became **3**.
7. **`may_notify` "mentions status"** was a detector matching a **comment**.
8. **Denominator** corrected (19 → 21).
9. **"Full suite" corrected** — 1,675 is `test:mobile` only.
10. **`test:ai`'s `-5/0` is NOT a failure** — transport error (§8).

## 17 · NOT-TESTABLE ITEMS — FINAL DISPOSITION (all 7)

| # | Item | Dependency now available? | Result | Final disposition |
|---|---|---|---|---|
| 1 | F-03b live execution | **No** — write declined | all 3 links catalog-confirmed | **PARTIALLY VERIFIED** |
| 2 | QAX-SEC-08 live execution | **No** — write declined | chain confirmed; **no role check at all** | **PARTIALLY VERIFIED** |
| 3 | 22 PHI tables, no fixture rows | **No** | 0 RLS-disabled, 0 zero-policy, 0 anon grants across **91** tables | **PARTIALLY VERIFIED** — coverage proven **universally** (stronger than the planned sampling); per-table boundary correctness undemonstrated |
| 4a | active-coach arm | **Yes** | `f626acd9`→`5470a95f` status `active` | **VERIFIED available** |
| 4b | team-lead arm | **No** | `coach_team_members` = **0 rows** | **STILL NOT TESTABLE** |
| 4c | event-host arm | **No** | 2 registrations exist but **`events.vendor_id` is NULL** | **DISPROVED as framed** — a registration is insufficient; a vendor-owned event is required |
| 5 | Cloud replay harness | **No** | no Postgres server; Docker down | **BLOCKED** — largely moot; schema purpose superseded by direct introspection. Unique remaining value is **fix-simulation** |
| 6 | All app runtime | **Yes** | 1,675 pass / 9 skipped | **VERIFIED** |
| 7 | private-vs-absent bucket | **Yes** | 3 public / 2 private, all 5 exist | **VERIFIED** |

**3 VERIFIED · 3 PARTIALLY VERIFIED · 1 DISPROVED-as-framed · 1 STILL NOT TESTABLE · 1 BLOCKED.**
The original "recovery converts ~6 of 7" expectation was **too optimistic**: the residual
blockers were **authorization**, not capability.

**The cautionary one — 4c.** `event_registrations` went 0 → 2 rows, which looked like an
unblock. It is not: `vendor_id` is NULL. **A row count is not a capability.**

## 18 · BLOCKERS — and exactly what would close each

| Blocker | Blocks | What would close it |
|---|---|---|
| Writes to shared QA declined | P0 + F-03b + NEW-2 execution; `test:security`; per-table PHI demos | authorization to create QA fixtures |
| **HTTPS egress unavailable** | `test:ai`; `test:security`; branch-protection re-verification | network egress on 443 |
| CI secrets absent | 4 live-QA jobs | configuring `QA_URL`/`QA_ANON`/`QA_SERVICE` as repo secrets |
| Docker / no Postgres server | replay **fix-simulation** | Docker, or a local Postgres |
| SBOM tooling forbidden | SBOM artifact; Dart-tree vulnerability scan | authorization to install `syft`/`cyclonedx`/`trivy` |
| Missing fixtures | team-lead arm; event-host arm; SEC-PHI-10 | 1 `coach_team_members` row; 1 `events.vendor_id`; `score_events` for the cancelled-relationship client |
| Owner decisions | AI disclosure; privacy alignment | OD-58, OD-14, OD-QAX-9 and the AI-disclosure decision |

### Branch protection — explicitly uncertain

**Not asserted as fact.** An earlier read returned 404 "Branch not protected", but a 404 on
`/branches/main/protection` is returned **both** when a branch is genuinely unprotected **and**
when the caller's token lacks admin scope. Re-verification this wave failed: **GitHub is
unreachable (HTTPS egress down)**.

**Recorded status: *Branch protection could not be conclusively re-verified due to GitHub/API
availability and/or token-scope limitations.*** The response body favours "unprotected", and if
that is so it is a **release-control** finding (no required status checks, so the
`static-guards` failure cannot block a merge) — **not a QA defect**. Requires confirmation in
the GitHub UI. **Not modified.**

## 19 · REMEDIATION QUEUE (documented, NOT implemented)

1. **`coach_team_members` `WITH CHECK`** — one change closes the **P0** *and* **F-03b**. Needs
   OD-14 + OD-QAX-9 and a wave number (132+).
2. **Correct `SEC_PHI_1` before scheduling** — `security_invoker = off`, `security_barrier = true`,
   predicate inside the view. As written it breaks both screens it exists to preserve.
3. **QAT-1 / ENV-5** — repoint `anon_least_privilege.py` to resolve from the environment with no
   default. Then make `static-guards` fail-late (or reorder) so one gate cannot blind six.
4. **NEW-2** — `WITH CHECK` on `workout_program_assignments`; status predicate in `can_read_program()`.
5. **SEC-PHI-9 / SEC-PHI-10** — status predicate via option (b), a text-taking
   `is_active_coach_of(text)` returning false rather than raising.
6. **NEW-7** — unskip **K-12** and **K-ENV-1** (assertion = whole finding; K-12 corroborated by
   E-09). **Review K-09** first: its assertion is a proxy.
7. **The 6 open K specs** — K-01 (note the partial `meta.event_id` idempotency), K-02/K-06, K-03,
   K-04 (live-confirmed), K-05, K-07.
8. **NEW-9** — configure CI secrets so the live-QA tier runs.
9. **Guards** — re-derive the `FOR ALL`/no-`WITH CHECK` population from the **live catalog**;
   convert SEC-G1 to a column-shape test; widen CHAIN-G1 to `notifications`.
10. **Supply chain** — SBOM tooling; the 7 high npm advisories; a Dart dependency scanner.
11. **Release control** — confirm and then enable branch protection on `main` with required checks.
12. **Fixtures** — the three in §18.

## 20 · FINAL QA STATE

### **QA COMPLETE WITH OPEN FINDINGS**

**Why this and not "QA NOT COMPLETE".** The previous revision chose NOT COMPLETE because three
of five test tiers had no HEAD evidence and six static gates were unevaluated. **Both are now
resolved:** the API and contract tiers are VERIFIED PASS at HEAD, all six gates were run and
**all pass**, and the two remaining tiers have precise diagnosed blockers rather than unknown
status. Every one of the 21 domains now holds a terminal disposition, satisfying the stop
condition.

**Why this and not "QA COMPLETE".** Open findings remain: **1 P0, 4 P1**, plus P2/P3 items and
6 open billing specs. The state name carries them explicitly.

**What the 10% is.** Not unexamined surface — **boundary-blocked residue**, itemised in §18
with the exact authorization or provisioning that would close each. It is **not** the case that
89.3% + remaining = 100%; the figure is computed from the §3 ledger and lands at **90.0%**
because five domains remain legitimately partial.

**What QA does not assert.** That the system is secure; that the P0 is unexploitable; that
absent evidence is favourable evidence. The P0 and P1s are **catalog-confirmed but unexecuted**,
and that distinction is preserved throughout rather than rounded away.

---

## REPOSITORY INTEGRITY

| Check | Result |
|---|---|
| `git rev-parse HEAD` | `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f` — **unchanged** |
| `git branch --show-current` | `reconcile/12circle-integrated` — **no branch created** |
| `git log -1` | `07f5bfb fix(correction-rights): CORR-2 — a failed unit-preference save no longer lies` |
| Tracked modifications / staged | **0 / 0** |
| Application code changed | **none** |
| Security policies / CI / tests modified | **none** — the four inline CI gates were extracted to a **scratchpad** to run; `.github/workflows/ci.yml` untouched |
| Tooling installed | **none** |
| Commit / push / merge / branch | **none** |
| Database mutation | **none** — all queries read-only under `default_transaction_read_only=on`; `postgres` used for catalog reads only |
| Shared QA mutation | **none** — `test:security` deliberately not run; `test:ai` run with `AI_ALLOW_WRITES` unset |
| Production contact | **none** |
| Secrets added / exposed | **none** |

**Documentation files written this mission (uncommitted, untracked):**
`docs/QA_COMPLETION_REPORT_2026-09-27.md` (this file), `docs/QA_FINAL_RECONCILIATION_REPORT.md`.
Pre-existing untracked: `docs/RECONCILIATION_LOCAL_CLOUD_GITHUB.md`,
`supabase/tests/security/d09-assessment-access.mjs` (another workstream's; backed up externally
with SHA-256 recorded).

---

*1 P0 and 4 P1 findings remain open and unremediated. Three previously-open specs are closed
but their guards are inert. One finding was retracted in full, three downgraded, and one
reclassified from stale to open. No compliance conclusion is drawn. Remediation is a separate,
unauthorized phase.*
