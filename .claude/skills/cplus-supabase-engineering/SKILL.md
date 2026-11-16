---
name: cplus-supabase-engineering
description: How to author, prove and declare 12circle-plus database migrations, RLS policies, RPCs and Edge Functions without applying or deploying anything — protected-path procedure, the expected_applied manifest, local loopback replays on QA's exact migration shape, read-only QA inspection, and function testing. Use for any 12circle-plus Supabase task.
---

# Supabase engineering in 12circle-plus

Also load `supabase:supabase-postgres-best-practices` for general Postgres/RLS rules.

## Facts

- QA project ref `eyqtldjqpgpljlqvpowh`. Production ref is never touched or queried.
- QA ledger frontier and pending versions live in `supabase/expected_applied.json`
  (`applied_through`, `excluded` 182–186, `pending`). ENV-3 (CI) reconciles it with QA's ledger.
- Nothing is applied or deployed by an agent. Applying needs Julia's window naming the versions
  (`docs/BETA_RELEASE_RUNBOOK.md` §2); deploying needs per-group approval (§3).

## Authoring a migration

1. Next number after the highest in `supabase/migrations/`. One open migration package at a time
   (or stack branches) — the manifest conflicts textually otherwise.
2. `supabase/migrations` and `supabase/expected_applied.json` are **protected paths**: add the exact
   paths to `scripts/protected-paths.json` `exceptions` in one commit, write, then restore the file
   from the base in the same PR (net diff empty).
3. Header: defect (with the proving test), the rule and why it takes nothing the product uses, what
   is NOT changed, how to reverse. `BEGIN; … COMMIT;` and must end in `COMMIT;`.
4. Declare it: `environments.qa.pending["NNN"] = {reason, gate}`; regenerate
   `node scripts/check-migration-wave-coverage.mjs --json > .skills-agent/migration-coverage.json`.
5. Guards that bite: SEC-027 (no `USING (true)` anywhere), function posture (definer functions pin
   `search_path`, no anon EXECUTE; `REVOKE … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated`
   for helpers used in policies), I-MIG-03 durability (a redefinition carries the pin and any
   authorization wrapper forward), SEC-024 (every RPC the app calls is granted in a migration).
6. Prefer **RESTRICTIVE** policies to narrow a permissive arm another (possibly unapplied)
   migration also edits — they compose in either apply order.

## Proving it: local loopback replay

Homebrew `postgresql@18`, port 55433, socket `-k /tmp/pgr12`, `LC_ALL=en_US.UTF-8`; copy the four
files in `supabase/tests/local/ext-stubs/` into `/opt/homebrew/share/postgresql@18/extension/`
for the run and remove them **by explicit path** afterwards. Runners refuse to start while QA
credentials are in the environment — run them in `bash -c 'unset QA_URL QA_ANON QA_SERVICE …; …'`.
Pattern: `supabase/tests/local/<name>_replay.{sh,sql}` — one rolled-back transaction, writes issued
`as authenticated` with `request.jwt.claims`, `PASS|id|detail` lines, a positive control for every
refusal, each destructive check on its own object. Run on `--build <N-1>` (must FAIL) and
`--build <N>` (must PASS), **and on QA's shape** (000–181 + 187–N, skipping excluded 182–186).
Re-run the existing replays (`policy_193_194`, `integrity_187_192`, `assignment_196`,
`credits_198`, `storage_199`, `program_history_200`) on the new tip.

## Reading QA (read-only)

`supabase db query --linked "set default_transaction_read_only = on; <sql>"` — catalog, policies,
counts. Never print secret values (secret **names** only). No writes, ever.

## Edge Functions

Deno, `supabase/functions/<name>/index.ts`; `verify_jwt` declared per function in
`supabase/config.toml` (E-09). A function that acts for a user verifies the JWT **and** applies the
same rule the app does (e.g. `supabase/functions/plan_gate.mjs`, PR #160); a cron/service function must refuse any caller but the
service role. Put pure decision logic in a plain `.mjs` module and test it with `node --test` (no
Deno locally); add the test to Static guards in `ci.yml`.
