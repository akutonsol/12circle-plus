# 12 Circle Fitness — Working-Tree Custody Manifest

**W1-T1 deliverable. The inventory of what was placed under Git custody, and why.**
**Date:** 2026-08-24 · **Companion to** [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) Wave 1 Task 1

> **No environment was contacted to produce this document.** It is derived entirely from
> the local repository. Production `nxdbooufqzkpslkcogxc` was not connected to, queried,
> migrated, deployed to or configured.

---

## 1. Repository state at inspection

| | |
|---|---|
| **Branch** | `chore/qa-environments-secure-ai-backend` |
| **HEAD before custody** | `39ca39cfed0f60805d8202d025eb99999057697a` (`39ca39c` — *fix: make workout session persistence deterministic*) |
| **Inspection timestamp** | 2026-08-24T23:26:25Z |
| **`git status --porcelain` entries** | 122 |
| **Tracked modified** | **50** |
| **Tracked deleted** | **0** |
| **Staged before this task** | **0** |
| **Untracked (status entries)** | 72 |
| **Untracked (actual files)** | **96** |

### 1.1 ⚠ Correction to Wave 0's custody figures

Wave 0 reported *"20 migrations, 22 test files, 2 production source files, 18 reports"* —
**62 files**. The true figure is **96**.

The undercount has a specific cause worth recording, because it will recur:
**`git status` collapses a wholly-untracked directory into a single entry.** Wave 0
counted status lines. `supabase/tests/` — 25 files across four harness suites, including
**every live security and AI probe in the repository** — appeared as *one* line and was
counted as one item. `docs/` was likewise counted as 18 reports when it holds 29 files.

**Correct counts, from `git ls-files --others --exclude-standard`:**

| Category | Wave 0 said | Actual |
|---|---:|---:|
| Untracked migrations | 20 | **20** ✓ |
| Untracked Dart test files | 22 | **20** (18 unit + 2 widget) |
| Untracked production source | 2 | **2** ✓ |
| Untracked documents | 18 | **29** |
| Untracked Supabase test harnesses | *not counted* | **25** |
| **Total** | **62** | **96** |

The registry and progress board are updated to the corrected figures.

---

## 2. Protected tracked changes — 50 modified, 0 deleted

Every one is preserved. Nothing was reverted, discarded or overwritten.

### 2.1 Supabase migrations edited in place — **15 files · HIGH RISK**

`001_full_ecosystem` · `002_ecosystem_additions` · `003_fk_and_rls_fixes` ·
`009_activate_client_relationships` · `076_ai_coaching_cron` · `080_accountability_timing` ·
`083_exercise_content_pipeline` · `084_exercise_certification` · `086_certification_projected` ·
`087_mie_programming_intelligence` · `090_mie_knowledge_enrichment` · `091_mie_attribute_review` ·
`096_communication_engine` · `097_coach_exercise_media` · `102_restrict_user_profiles`

| | |
|---|---|
| **Why it matters** | These are the **STAGE B.3 / B.4 replay corrections**. Each carries an in-file rationale. They fix a from-empty rebuild and do **nothing** for an environment that already ran the originals — which is why production still holds every defect they fix, including 076's cross-environment cron target and its `created_at`→`started_at` bug |
| **Workstream** | L (`LRE-04`, `LRE-09`), master reconciliation (`HYG-02`) |
| **Phase** | Wave 1 · finding **ENV-2** · **P0** |
| **Commit now?** | **Yes — and isolated in their own commit**, see §5 |

### 2.2 Application source — 16 files

All under `apps/mobile/lib/`: the workout domain (`workout_model`, `workout_log_model`,
`workout_service`, `workout_session_store`, `workout_snapshot`, `workout_provider`,
`workout_session_manager`, `active_workout_screen`, `set_tracker_row`,
`workout_list_screen`), plus `coach_program_service`, `coach_provider`,
`program_builder_screen`, `community_provider`, `directory_screen`, `messaging_service`.

**Why it matters:** the Phase 2 workout-contract remediation and the Phase 1 supporting
change. `coach_provider.dart` in particular is the **minimum client change migration 113
requires** — under the parties-only SELECT policy the old cross-coach capacity read would
silently return zero for every coach. Losing it re-breaks coach discovery.
**Workstream:** Phase 1, Phase 2. **Commit now: yes.**

### 2.3 Supabase configuration and Edge Function — 2 files

`supabase/config.toml` (adds the explicit `[db.seed]` block with its ordering rationale) ·
`supabase/functions/ai-generate-workout/index.ts` (canonical-contract output validation).
**Commit now: yes.**

### 2.4 Seed fixtures — 2 files · **see §6.2 before reviewing**

`supabase/seeds/test_accounts.sql` · `supabase/seeds/full_test_data.sql`.
Load-bearing for `supabase db reset --linked`, which `config.toml` now drives.
**These diffs introduce QA fixture-account passwords that are not in `HEAD`.**
**Commit now: yes, with the classification in §6.2 recorded.**

### 2.5 Test fixtures and harness — 5 files

`test/support/in_memory_workout_session_store.dart` · `test/unit/ai_nutrition_client_test.dart` ·
`test/unit/env_config_test.dart` · `test/unit/workout_session_persistence_test.dart` ·
`tool/live_integration_test.dart`.

⚠ **`tool/live_integration_test.dart` is one of the three harnesses hardcoded to
production** (finding **ENV-5** / `LRE-02`). Its working-tree diff is a *contract* fix to
the probe payload and **does not** change the production target. It is committed **as-is**;
repointing it is Wave 1 batch task 3, deliberately not performed here.
**Commit now: yes.**

### 2.6 Build and dependency configuration — 2 files

`package.json` (adds `test:security`, `test:ai`, `test:contract`) ·
`.gitignore` (adds `supabase/tests/security/ids.json`, the generated fixture-id file).
Both belong with the QA harnesses they enable. **Commit now: yes.**

### 2.7 Supabase CLI scratch — 7 files · **generated, but tracked**

`supabase/.temp/`: `gotrue-version`, `linked-project.json`, `pooler-url`,
`postgres-version`, `project-ref`, `rest-version`, `storage-version`.

| | |
|---|---|
| **Classification** | **Generated CLI scratch.** `.gitignore:29` already carries `**/.temp/`, but these eight files were committed before that rule existed, and **a tracked file overrides its ignore rule** — which is precisely finding `LRE-34`, here confirmed exactly as reported |
| **Credential scan** | **Clean.** All nine files in the directory were classified; none contains a `user:pass@host` pattern, a JWT, or any `service_role`/`sk_`/`whsec_` token. `pooler-url` (92 bytes) carries no embedded password |
| **Content** | They now record that the CLI is linked to **QA** `eyqtldjqpgpljlqvpowh` |
| **Commit now?** | **Yes**, and the reasoning is deliberate: leaving them modified leaves a permanently dirty tree that would mask the next concurrent change, and committing the **QA** link is strictly safer than a `git checkout` restoring the previous value. Untracking them (`git rm --cached`) is **Wave 1 batch task 6** and is not pre-empted here |

---

## 3. Protected untracked files — 96

### 3.1 Documentation and evidence — 29 files · `docs/`

| Group | Files | Why it matters |
|---|---:|---|
| **Wave 0 orchestration artifacts** — `MASTER_REMEDIATION_REGISTRY`, `MASTER_REMEDIATION_WAVES`, `MASTER_PRODUCT_DECISIONS`, `RELEASE_GATES`, `QA_CLOSURE_STANDARD`, `REMEDIATION_PROGRESS` | 6 | The canonical operational layer for the whole programme. Their loss ends the programme's ability to track itself |
| **A–N workstream reports** — `QA_WORKSTREAM_A` … `QA_WORKSTREAM_N` | 14 | **Frozen evidence.** Every finding in the registry traces to one of these. Not rewritten, not summarised, not replaced |
| **Phase artifacts** — `MASTER_QA_RECONCILIATION`, `REMEDIATION_EXECUTION_PLAN`, `PHASE_1_SECURITY_AUDIT`, `PHASE_2_WORKOUT_RECONCILIATION`, `PHASE_2_WORKOUT_TEST_MATRIX`, `WORKOUT_DOMAIN_CONTRACT` | 6 | The BEFORE/AFTER evidence for 52 already-fixed findings, and the canonical workout contract |
| **Approved roadmaps** — `ROADMAP_AI_MONETIZATION_UNIT_ECONOMICS`, `ROADMAP_WEARABLE_INTELLIGENCE` | 2 | Standing approved commercial and product architecture. `PD-E08` was raised because the first conflicts with the shipped tier ladder |
| **Superseded** — `qa-workstream-d-report` | 1 | The original Workstream D report. Superseded by the master reconciliation but retained as evidence |

**Workstreams:** all · **Phase:** Wave 0 · **Commit now: yes.**

### 3.2 Database migrations — 20 files · **HIGHEST RISK IN THE REPOSITORY**

`000_baseline_preexisting_tables` · `104_workout_set_completion` · `105_workout_session_warmup` ·
`106_workout_set_identity` · `107_workout_session_cursor` ·
`108_workout_session_started_at_authority` · `109_auth_user_profile_trigger` ·
`110_profile_demo_flag` · `111_replay_corrections` · `112_view_grants_read_only` ·
**`113_rls_coach_client_relationships`** · **`114_rls_weekly_checkins`** ·
**`115_profile_privilege_boundary`** · **`116_rpc_execution_security`** ·
**`117_rls_intelligence_substrate`** · **`118_security_sweep`** ·
`119_workout_prescription_contract` · `120_workout_set_identity_authority` ·
`121_restore_unique_plan_day_titles` · `122_repin_function_search_path`

| | |
|---|---|
| **Why it matters** | **113–118 are the entire Phase 1 P0 security remediation** — the RLS closures, the privilege boundary, the RPC execution allowlist, the intelligence-substrate scoping and the security sweep. **119–122 are the entire Phase 2 workout-contract remediation** plus the `search_path` repin. They exist nowhere but this working tree. They are applied to QA and cannot be reviewed, deployed from CI, or promoted to production while untracked |
| **Workstream** | Phase 1, Phase 2, A |
| **Phase** | Wave 1 · finding **ENV-1** · **P0** |
| **Commit now?** | **Yes — first among the code slices** |
| **Not done here** | Not re-applied. Not re-numbered. **No body modified.** Migration-history reconciliation is **ENV-3** (Wave 1 spine) and the forward delta is **ENV-2** (migration 123) — both later tasks |

### 3.3 Production source required for compilation — 2 files

| File | Imported by |
|---|---|
| `apps/mobile/lib/features/workout/data/workout_contract.dart` | `workout_snapshot.dart:3` |
| `apps/mobile/lib/features/workout/domain/workout_restoration.dart` | `workout_provider.dart:8`, `active_workout_screen.dart:12` |

**Verified this session by import scan, not assumed.** Both are imported by *tracked,
modified* source. **The application does not compile without them, and both look
disposable to a cleanup.** They are additionally imported by five test files.
**Workstream:** Phase 2 · **Commit now: yes.**

### 3.4 Dart test files — 20 files

**Unit (18):** `ai_decision_integrity` · `backend_reachability_guard` ·
`billing_entitlement_contract` · `cycle_phase_logic` · `error_contract_guard` ·
`harness_environment_guard` · `intake_contract` · **`phase1_security_boundary`** ·
`product_contract_guard` · `profile_access_boundary` · `qa_environment_isolation` ·
`ui_error_surface_guard` · `workout_active_session_authority` · `workout_domain_contract` ·
`workout_restoration` · `workout_set_identity` · `workout_set_immutability` ·
`workout_set_ordering`
**Widget (2):** `active_workout_hydration` · `set_tracker_row`

**Why it matters:** these are the **static half of every standing guard in the
programme** — `SEC-020…SEC-027`, `EC-G1…EC-G5`, `ENV-010…ENV-022`, `WKT-*`, `INT-302`,
`AI-002`, `SEC-030`, `SEC-031`. They are a large part of the 730-test baseline.
`SEC-027` — the guard that catches a later migration silently reverting an earlier fix —
lives here and is the single strongest guard in the tree.
**Workstreams:** Phase 1, Phase 2, A, B, F, H, I, J, K, L, N · **Commit now: yes.**

### 3.5 Supabase QA harnesses — 25 files · **not counted by Wave 0**

| Suite | Files | Contents |
|---|---:|---|
| `supabase/tests/security/` | 11 | `lib.mjs`, `run.mjs`, `setup-identities.mjs`, `d01`–`d06`, `function-search-path.sql`, `README` — **188 live authorization assertions** |
| `supabase/tests/ai/` | 8 | `lib.mjs`, `run.mjs`, `j01`–`j05`, `README` — the AI decision-integrity suite |
| `supabase/tests/contract/` | 4 | `run.mjs`, `schema.mjs`, `known-violations.json`, `README` — the offline schema-contract guard and its shrinking allowlist |
| `supabase/tests/workout/` | 2 | `phase2-contract.sql`, `plan-day-titles.sql` — 32 live workout assertions |

**Why it matters:** the live security suite is, in Workstream N's assessment, **the best
test asset in the repository** — written to fail against the pre-remediation database and
pass after. `lib.mjs` also carries the **production-ref refusal guard** that every future
QA harness is supposed to copy. Losing this directory loses the ability to ever re-verify
Phase 1.
**Workstreams:** Phase 1, A, I, J · **Commit now: yes.**

---

## 4. Generated artifacts — explicitly excluded, explicitly not deleted

Distinguished from source per the task brief. **None is deleted; all remain on disk.**

| Path | Classification | Ignore status |
|---|---|---|
| `dist/` | build output | ignored ✓ |
| `apps/api/dist/` | NestJS build output (~28 tracked-ignored entries) | ignored ✓ |
| `apps/mobile/build/` | Flutter build output — **known to carry production strings in the QA bundle** (`LRE-32`) | ignored ✓ |
| `apps/mobile/.dart_tool/` | Dart tool cache | ignored ✓ |
| `node_modules/` | dependencies | ignored ✓ |
| `supabase/.temp/cli-latest` | CLI scratch, **untracked** — the only `.temp` file the ignore rule actually reaches | ignored ✓ |
| `supabase/tests/security/ids.json` | **generated fixture identities** from `setup-identities.mjs` | ignored ✓ by the new `.gitignore` line |
| `.claude/settings.local.json` | local editor settings | ignored ✓ |
| `.env`, `.env.local`, `apps/api/.env` | **local secrets** | ignored ✓ · **verified: no `.env` file is tracked; only `apps/api/.env.example`** |

---

## 5. High-risk file register

| Class | Count | Files | Risk if lost | Slice |
|---|---:|---|---|---|
| **Security migrations** | 6 | 113–118 | The entire Phase 1 P0 remediation. Production is already unpatched (`ENV-11`); losing these means QA joins it | 2 |
| **Contract migrations** | 4 | 119–122 | The entire Phase 2 remediation, plus the `search_path` repin | 2 |
| **Baseline / interim migrations** | 10 | 000, 104–112 | A from-empty rebuild becomes impossible; `000` is the pre-existing-tables baseline | 2 |
| **In-place-edited migrations** | 15 | §2.1 | The replay corrections, **and the input to migration 123's delta enumeration** | 3 |
| **Live security harnesses** | 11 | `supabase/tests/security/` | 188 assertions; the only way to ever prove Phase 1 again | 5 |
| **Static security guards** | 2 | `phase1_security_boundary_test`, `profile_access_boundary_test` | 103 source-level assertions incl. `SEC-027` | 5 |
| **Compilation-critical source** | 2 | §3.3 | **The app will not build.** Both look disposable | 4 |
| **Environment configuration** | 4 | `dart_defines/qa.json`, `supabase/config.toml`, `.gitignore`, `package.json` | The QA environment definition and every QA script entry point | 4, 5 |
| **Production-targeting QA harness** | 1 | `tool/live_integration_test.dart` | **Actively dangerous** — finding `ENV-5`. Committed unchanged; repointing is Wave 1 task 3 | 5 |
| **Evidence reports** | 21 | A–N + phase artifacts | Every finding in the registry loses its proof | 1 |
| **Orchestration artifacts** | 6 | Wave 0 outputs | The programme loses its tracking layer | 1 |

---

## 6. Security review of committed content

A pattern scan was run over **all 146 pre-existing commit candidates** (50 modified + 96 untracked); this manifest, written afterwards, is the 147th and contains no credential literal by construction.

### 6.1 Credential-shaped literals — two files, both cleared

| File | Finding | Classification |
|---|---|---|
| `apps/mobile/dart_defines/qa.json` | 2 JWT literals | **Decoded: `role=anon`, `ref=eyqtldjqpgpljlqvpowh`.** A Supabase **anon/publishable** key for **QA**. Not a secret. This is the intended QA environment configuration and the diff is what populates it |
| `apps/mobile/tool/live_integration_test.dart` | 2 JWT literals | **Decoded: `role=anon`, `ref=nxdbooufqzkpslkcogxc`.** A Supabase **anon/publishable** key for **production**. Not a secret — but its presence *is* finding `ENV-5`, and it was already in `HEAD` |

**No `service_role` key, no `sk_live_`/`sk_test_`, no `whsec_`, no `sk-ant-`, and no
connection string containing a password appears anywhere in the committed set.**

Twelve further files matched on the *name* `service_role_key` / `sk-ant-`; each was
inspected and every one is a false positive — a Vault secret **name** (`076`, `080`), a
regex inside a guard test asserting the pattern is *absent*, or prose in a report.

### 6.2 ⚠ QA fixture passwords newly introduced by the seed diffs

| | |
|---|---|
| **Paths** | `supabase/seeds/test_accounts.sql`, `supabase/seeds/full_test_data.sql` |
| **Classification** | **QA seed-fixture account passwords.** Three distinct literals, passed to `crypt(…, gen_salt('bf'))` for seeded fixture accounts (`coach@12circle.app`, `*@marketplace.test`, `*@community.test` and four consumer-domain fixtures). Two of the three are **already published in `docs/`**; one is not documented |
| **Pre-existing?** | **No.** `HEAD` contains zero `crypt(`/`encrypted_password` lines in these files — the working-tree diff introduces them |
| **Is this a secret?** | **No production or third-party credential.** These accounts exist only where the seeds are applied, and `config.toml` runs the seeds on `supabase db reset` against the **linked** project |
| **The real risk, and it is already filed** | **`REL-36`** — the seeds are wired into `config.toml` and *nothing prevents them running against a non-QA project ref*. That guard does not exist yet |
| **Decision** | **Committed.** They are load-bearing for the QA rebuild path, and withholding them would break `supabase db reset --linked` while achieving nothing — the accounts and their passwords are already documented in the repository. **No literal is printed in this manifest or in any commit message** |
| **Action taken** | **`REL-36` is raised from P2 to P1** in the registry and pulled into Wave 1 batch task 6, on the grounds that a fixture password is now in Git history and the only remaining control is the seed-target guard |

### 6.3 Files deliberately **not** committed

| Path | Reason |
|---|---|
| `.env`, `.env.local`, `apps/api/.env` | Local secrets. Verified ignored; verified no `.env` is tracked |
| `supabase/tests/security/ids.json` | Generated fixture identities. Newly ignored by this branch's `.gitignore` change |
| `dist/`, `apps/api/dist/`, `apps/mobile/build/`, `.dart_tool/`, `node_modules/` | Build output and caches. **Left on disk, not deleted** |
| `.claude/settings.local.json` | Local editor settings |
| `supabase/.temp/cli-latest` | CLI scratch, untracked and ignored |

---

## 7. Commit strategy — **five slices, not four**

Wave 0 recommended four. The actual tree makes **five materially safer**, and the reason
is concrete rather than aesthetic.

**The deviation:** the 20 *new* migrations and the 15 *in-place-edited* migrations are
separated into two commits instead of one.

**Why.** Finding **ENV-2** (`LRE-04`, **P0**) requires someone to *"enumerate the semantic
delta of each of the 15 in-place edits and carry every one into forward migration 123."*
If those 15 files are committed alongside 20 new ones, that enumeration must be
reconstructed from a 35-file diff every time it is reviewed. Isolated, **`git show <slice-3>`
*is* the enumeration input** — permanently, reviewably, for the person who writes migration
123 and for everyone who reviews it afterwards. A 35-file mixed commit would make the next
P0 harder to do correctly, which is the opposite of what custody is for.

| # | Slice | Files | Contents |
|---:|---|---:|---|
| **1** | Documentation & evidence | 30 | All of `docs/` — orchestration artifacts, A–N evidence, phase artifacts, roadmaps, and this manifest |
| **2** | New database migrations | 20 | `000`, `104`–`122`. Additive only; no body modified |
| **3** | In-place migration corrections, seeds, Supabase config & CLI link | 25 | The 15 edited migrations · 2 seeds · `config.toml` · 7 `.temp` |
| **4** | Application source | 20 | 2 compilation-critical untracked files · 16 modified `lib/` files · `dart_defines/qa.json` · `functions/ai-generate-workout/index.ts` |
| **5** | Tests, QA harnesses & tooling | 52 | 20 Dart tests · 25 Supabase harness files · 4 modified test files · `tool/live_integration_test.dart` · `package.json` · `.gitignore` |
| | **Total** | **147** | |

**Ordering rationale.** Documentation first, so that if anything goes wrong in slices 2–5
the *reasoning* for every subsequent commit is already preserved and reviewable. Schema
before source before tests, so the tree becomes progressively coherent.

**Expected intermediate state.** Commits 1–4 are **not** individually test-green: slice 4
lands application changes whose matching test updates arrive in slice 5. This is correct
for a custody split, which optimises for recoverability and reviewability rather than for
a green build at every intermediate SHA. **Only the tree at slice 5 is expected green**,
and it is verified there.

---

## 8. What this task did **not** do

- **Did not apply, re-apply, re-order or re-number any migration.** 113–122 remain absent
  from the QA migration ledger; reconciling that is **ENV-3**
- **Did not modify any migration body** — including the 15 already edited in place
- **Did not fix any finding.** `ENV-4` (the `APP_ENV` default), `ENV-5` (the three
  production-targeting harnesses), `ENV-6` (CI), `LRE-34` (untracking `.temp`) and
  `REL-36` (the seed-target guard) are all still open and are Wave 1's next tasks
- **Did not rewrite, summarise or replace any historical report**
- **Did not delete, revert, stash, reset, clean or discard anything**
- **Did not contact any environment** — no Supabase, PostgREST, QA database, Edge
  Function, Stripe, Anthropic or browser access of any kind
