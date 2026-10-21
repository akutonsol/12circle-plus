# Wave 1 — first parallel batch (tasks 2–9) · closure record

**Completed:** 2026-08-24 · **Board:** [`REMEDIATION_PROGRESS.md`](REMEDIATION_PROGRESS.md) §11
· **Wave definition:** [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) "WAVE 1"

This file is the closure record for the eight batch tasks only. It modifies no
ARCH-owned document and no historical report.

## 0. Task-ID note

`REMEDIATION_PROGRESS.md` §11 numbers this batch **1–9**, where 1 is custody
(complete). `MASTER_REMEDIATION_WAVES.md` separately numbers a *sequential
spine* W1-T1/T2/T3, where W1-T2 is migration 123 and W1-T3 is the QA ledger.
The two numbering schemes collide at 2 and 3.

This batch is **§11 tasks 2–9**, per the board's own "Next action: Wave 1
parallel batch tasks 2–9 (§11). W1-T2 (migration 123) and W1-T3 (QA ledger)
follow the batch." Migration 123 and the QA ledger were **not** started; §11
excludes them from the first batch by design.

## 1. Status

| # | Task | Findings | Status |
|---:|---|---|---|
| 2 | `APP_ENV` → `dev`; prod constants out of the binary; ENV-012 inverted | ENV-4, `K-26` | ✅ COMPLETE |
| 3 | Three harnesses take their target from env and refuse production | ENV-5 | ✅ COMPLETE |
| 4 | `ci.yml` | ENV-6 | ✅ COMPLETE (live-QA job skips pending EB-1) |
| 5 | `[functions.*] verify_jwt` per function | `E-09` | ✅ COMPLETE |
| 6 | `.temp` untracked; seed guard refuses a non-QA target | `LRE-34`, `REL-36` | ✅ COMPLETE |
| 7 | Release-mode route gate | REL-3 | ✅ COMPLETE |
| 8 | Correct the false account-deletion claims | UIX-2 (text half) | ✅ COMPLETE |
| 9 | Leaked-password protection on QA | `R-06` | ⛔ **BLOCKED** — no Management API credential |

## 2. Evidence

| Suite | Before | After |
|---|---|---|
| `flutter test` | 730 pass · 9 skip · 0 fail | **750 pass · 9 skip · 0 fail** |
| `flutter analyze` | 0 errors · 171 infos | 0 errors · 171 infos |
| `npm run test:api` | 58 + 6 | 58 + 6 |
| `npm run check:guards` | *(did not exist)* | 10 assertions, all pass |

**Twenty net-new tests**, every one behavioral or a source-reading static guard.
No replica tests were added. Each inverted guard was run against the restored
defect and observed to fail before being accepted:

| Guard | Failed against the defect |
|---|---|
| `env_config_test.dart` ENV-001/003 | 4 tests |
| `qa_environment_isolation_test.dart` ENV-012 | 4 tests |
| `harness_environment_guard_test.dart` ENV-020 | 2 tests |
| `account_deletion_claims_test.dart` UIX-2 | 1 test |

### Measured outcome, not asserted

A QA web bundle was built from the pre-remediation `app_env.dart` and from the
current one:

```
BEFORE: the QA artifact CONTAINS the production project ref
AFTER : the QA artifact does NOT contain the production project ref
```

## 3. Task 9 — `R-06`, blocked

**Not done. No workaround was attempted.**

Enabling leaked-password (HIBP) protection is a Management API / dashboard
setting. Two routes exist and both were rejected:

1. **Management API `PATCH /v1/projects/{ref}/config/auth`
   `{"password_hibp_enabled": true}`.** Requires a personal access token. The
   CLI is authenticated, but its token is held in the macOS keychain;
   extracting it to authenticate an out-of-band call is exactly the
   "work around the restriction" the programme forbids.
2. **`supabase config push`.** The only config-writing command this CLI has,
   and it pushes **the whole of `config.toml`** to the linked project. The
   committed `config.toml` declares no `[auth]` block, so a push would reset
   QA's entire auth configuration — site URL, redirect allowlist, JWT expiry,
   providers, email templates — to CLI defaults. That is an unreviewed
   configuration overwrite well outside "one project setting".

An HIBP key was **deliberately not added to `config.toml`**: the key name could
not be validated offline (`config push` has no dry-run), and an unrecognised key
would break every CLI command that parses the file — including the new reset
wrapper.

**Read-only verification attempted:** `GET /auth/v1/settings` on QA returns
provider flags only and does not expose HIBP state, so the current setting could
not be confirmed either way. R-06's premise is **unverified**, not disproven.

**Handoff — one action for the DevOps owner:**
Supabase dashboard → project `eyqtldjqpgpljlqvpowh` (12Circle QA) → Authentication
→ Policies → enable **"Prevent use of leaked passwords"**. Then record the
before/after state here.

## 4. New findings

| ID | Sev | Finding |
|---|---|---|
| **W1B-N1** | **P1** | `supabase/STRIPE_SETUP.md` instructs `supabase link --project-ref nxdbooufqzkpslkcogxc` — a runbook that points the CLI at **production**. Allowlisted in the production-ref guard so CI is honest rather than red; it is not correct. No batch task owns this file. |
| **W1B-N2** | **P2** | `/admin-exercise-review` and `/vendor-portal` are registered unconditionally and their screens contain **no role check at all** (`/observability`, `/admin-dashboard`, `/content-review`, `/knowledge-review` have one each). Server-side RLS is the real control, so this is attack surface and UX, not presumed data exposure — but it needs confirming against Phase 1's policies. Out of REL-3's scope (QA tooling), raised from its "audit should be broad" instruction. |
| **W1B-N3** | **P2** | `privacy_policy_screen.dart` §5 "Access" and "Data Portability" claim data export "from Profile → Settings → Account" and "in JSON or CSV format on request". The same non-existent path UIX-2 removed for deletion, for a different right. Left standing deliberately: UIX-2 authorises only the deletion half. |
| **W1B-N4** | **P3** | `supabase-keepalive.yml`'s header comment says the anon key is "already shipped inside the mobile app binary + `app_constants.dart`". Untrue since ENV-4. The workflow was not edited — it is the one production-targeting file in the tree and no batch task owns it. |
| **W1B-N5** | **P2** | `supabase config push` pushes the entire `config.toml`, which declares almost no `[auth]`/`[db]` settings. Anyone running it to deploy the new `[functions.*]` block would silently reset QA's auth configuration. The new `[functions.*]` block should be deployed with `supabase functions deploy`, **not** `config push`, until `config.toml` is reconciled with QA's live settings. |

`W1B-N5` is the most load-bearing: it is a foot-gun created *by* task 5's
otherwise-correct change, and it should be resolved before Wave 5 deploys
functions.

## 5. Cross-task dependency recorded

Task 2 (ENV-4) changed `AppEnv`'s default, which invalidated two guards living
in task 3's file (`harness_environment_guard_test.dart` ENV-021 asserted that
"AppEnv defaults to prod" composed into a production write; ENV-022 allowed
`app_env.dart` to name both projects). **Task 3 owns that file and made both
edits.** No file was written by two tasks.

## 6. Environment & production

**Production was not contacted.** No production database, PostgREST, Edge
Function, Stripe, Anthropic or configuration endpoint was called.

Two calls reached Supabase infrastructure, both read-only:

| Call | Target | Why |
|---|---|---|
| `supabase projects list` | account-level Management API | to establish whether a credential existed for R-06. Returned metadata for both projects, production included. **A listing, not a project operation.** |
| `GET /auth/v1/settings` | QA `eyqtldjqpgpljlqvpowh` only | R-06 read-only state check. Target confirmed against `.temp/project-ref`, `config.toml` and `qa.json` before the call. |

**No QA mutation of any kind.** No row written, no user created, no setting
changed, no migration applied, no function deployed.

The two seed guards and the reset wrapper were verified **without touching QA**:
the SQL guards in a throwaway local Postgres container (removed afterwards), the
wrapper against a temporarily-rewritten local `.temp/project-ref` that was
restored and diffed byte-for-byte.

## 7. Concurrent work

`docs/COWORK_AGENT_REGISTRY.md`, `docs/COWORK_ENGINEERING_GOVERNANCE.md` and
`docs/COWORK_FILE_OWNERSHIP.md` appeared mid-session (mtime 19:09) from a
concurrent architecture session. **They were not read into scope, modified or
committed by this batch.** The changes here fall inside the ENV, JOURNEY and QA
domains that map defines, which is what §11 assigns. No migration was touched
and no ARCH-owned document was rewritten.
