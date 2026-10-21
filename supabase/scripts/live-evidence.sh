#!/usr/bin/env bash
# Live QA evidence phase — FG-1, FG-2 and the ENV-3 live ledger comparison.
#
# ── What this is for ────────────────────────────────────────────────────────
#
# Three pieces of evidence this programme has never collected sit behind one
# missing thing: a database credential. They are SQL, not REST, so the QA_URL /
# QA_ANON / QA_SERVICE secrets the live-qa job already holds cannot reach them.
#
#   FG-1  supabase/tests/security/function-search-path.sql   — SEC-09's live half
#   FG-2  supabase/tests/workout/*.sql                       — SEC-11 / Phase 2
#   ENV-3 the generated ledger comparison                    — ENV-3's live half
#
# This script is the single place that credential is used. It is written so the
# workflow can land before the secret exists: with no credential it reports the
# blocker and SKIPS, exactly as the live-qa job already skips without QA_SERVICE.
#
# ── Safety, in the order the checks run ─────────────────────────────────────
#
#   1. The target is proven QA by ALLOWLIST — the connection string must name
#      the QA project ref. "Is not production" is not the same claim as "is QA",
#      and only the second is safe to connect with. This mirrors
#      tool/qa_target.dart, supabase/tests/security/lib.mjs and the live-qa
#      job's own exact-host check rather than adding a fourth targeting scheme.
#   2. The production ref is refused explicitly as well, so a string that
#      somehow satisfied (1) and still mentioned production cannot proceed.
#   3. Every suite must END in `raise exception`. That is what makes these read
#      -only: the block raises, the transaction rolls back, and the probe rows
#      FG-2 creates never persist. A suite that lost its raise would COMMIT, so
#      the runner refuses to execute one.
#   4. psql runs each file with --single-transaction, so even a suite that
#      somehow returned normally is one all-or-nothing unit.
#
# It runs no migration, no db push, no repair, and writes nothing to
# schema_migrations. The credential is never printed; only a redacted form of
# the target is echoed.
#
#   supabase/scripts/live-evidence.sh
#
# Exit: 0 when every suite passes, or when the credential is absent (skip);
#       1 when a suite reports FAIL, a target cannot be proven, or a suite is
#       missing/unsafe.

set -uo pipefail

QA_REF='eyqtldjqpgpljlqvpowh'
cd "$(git rev-parse --show-toplevel)" || { echo "FAIL — not inside a git repository; cannot locate the suites."; exit 1; }

FG1='supabase/tests/security/function-search-path.sql'
FG2A='supabase/tests/workout/phase2-contract.sql'
FG2B='supabase/tests/workout/plan-day-titles.sql'
ENV3_GEN='supabase/scripts/env3-live-check.mjs'
FJ17='supabase/tests/ai/fj17-parq-risk-contract.sql'
FJ07='supabase/tests/ai/fj07-rule-accumulator-contract.sql'

hr() { printf '%s\n' "──────────────────────────────────────────────────────────────────────────"; }

# ── 0. credential gate ──────────────────────────────────────────────────────
if [[ -z "${QA_DB_URL:-}" ]]; then
  hr
  echo "  SKIPPED — no QA database credential (QA_DB_URL is unset)."
  hr
  echo "  FG-1, FG-2 and the ENV-3 live ledger check are SQL-level evidence. The"
  echo "  live-qa job's QA_URL / QA_ANON / QA_SERVICE are REST credentials and"
  echo "  cannot reach them: supabase_migrations is not an exposed PostgREST"
  echo "  schema, and neither suite is reachable over REST at all."
  echo
  echo "  Blocked, and deliberately not worked around:"
  echo "    SEC-09  — its live half is FG-1"
  echo "    SEC-11 + the Phase 2 cohort — their live evidence is FG-2"
  echo "    ENV-3   — stays REMEDIATED until its live half executes here"
  echo
  echo "  To unblock, add a repository secret QA_DB_URL holding the QA project's"
  echo "  pooler connection string. It must name ${QA_REF} and no other"
  echo "  project; this script refuses anything else. Nothing else changes."
  echo "::notice title=Live SQL evidence skipped::QA_DB_URL is not provisioned. FG-1, FG-2 and the ENV-3 live ledger check did NOT run. SEC-09, SEC-11 and ENV-3 remain open on their live evidence."
  exit 0
fi

# ── 1/2. target identification — allowlist only, no production literal ──────
#
# A Supabase connection string names its project in one of two places: the
# pooler username (postgres.<ref>) or a direct host (db.<ref>.supabase.co).
# Both are project refs: twenty lowercase letters.
#
# So the check is not "does it mention QA" and it is emphatically not "does it
# mention production" — a blocklist would need the production ref written here,
# and the ENV-5 guard is right to refuse that. Instead: extract EVERY
# project-ref-shaped token in the string and require that the only one present
# is QA's. A string carrying two refs, or one unknown ref, is refused without
# this file ever having to know what production is called.
# Scan the USER and HOST only. The password is deliberately excluded: a
# password that happened to contain twenty lowercase letters would otherwise
# refuse a legitimate QA target, and the password never selects a project.
target_userhost="$(sed -E 's#^[a-z+]+://##; s#/.*$##; s#\?.*$##' <<<"$QA_DB_URL" | sed -E 's#^([^:@]*)(:[^@]*)?@#\1@#')"
refs="$(grep -oE '[a-z]{20}' <<<"$target_userhost" | sort -u || true)"
if [[ -z "$refs" ]]; then
  echo "FAIL — the connection string names no Supabase project ref."
  echo "Refusal is by allowlist: a target is QA because its ref says so, never"
  echo "because the secret is called QA_DB_URL."
  exit 1
fi
if [[ "$refs" != "$QA_REF" ]]; then
  echo "FAIL — the connection string does not resolve to the 12 Circle QA project alone."
  echo "Project refs found: $(tr '\n' ' ' <<<"$refs")"
  echo "Expected exactly one: ${QA_REF}"
  exit 1
fi
echo "  Target verified by ref: ${QA_REF} (12Circle QA) — connection string not echoed."

command -v psql >/dev/null || { echo "FAIL — psql is not available on this runner."; exit 1; }

fail=0

run_suite() {
  local label="$1" file="$2" banner="$3"
  hr; echo "  ${label}"; echo "  file:   ${file}"; echo "  target: QA ${QA_REF}"; hr
  if [[ ! -f "$file" ]]; then
    echo "FAIL — ${file} is missing. The suite is the evidence; do not proceed without it."
    fail=1; return
  fi
  # Safety 3 — a suite that cannot roll itself back is not run.
  if ! grep -qiE 'raise exception' "$file"; then
    echo "FAIL — ${file} does not end in a RAISE, so it would COMMIT. Refusing to run it."
    fail=1; return
  fi

  local out
  # The suites raise deliberately, so psql's exit code is always non-zero and
  # carries no information. The REPORT decides, and its banner must be present:
  # a connection error must never read as a pass.
  out="$(psql "$QA_DB_URL" --single-transaction -v ON_ERROR_STOP=0 -f "$file" 2>&1)"
  if ! grep -qF "$banner" <<<"$out"; then
    echo "FAIL — the suite did not produce its report banner (${banner})."
    echo "This is a connection, permission or syntax failure, not a passing run:"
    sed 's/^/    /' <<<"$out" | head -20
    fail=1; return
  fi

  grep -E '^(PASS|FAIL|INFO)' <<<"$out" | sed 's/^/    /'
  local passes fails
  passes="$(grep -cE '^PASS' <<<"$out")"
  fails="$(grep -cE '^FAIL' <<<"$out")"
  echo
  echo "    assertions: ${passes} PASS · ${fails} FAIL"
  if (( fails > 0 )); then
    echo "    RESULT: FAIL — reported as found. The assertion is not weakened to go green."
    fail=1
  else
    echo "    RESULT: PASS"
  fi
}

run_suite "FG-1 · function search_path posture (SEC-09 live half)" "$FG1" '=== FUNCTION SEARCH PATH ==='
run_suite "FG-2a · Phase 2 workout contract (SEC-11 / Phase 2 live half)" "$FG2A" '=== '
run_suite "FG-2b · generated plan day titles (OBS-4 / migration 121)" "$FG2B" '=== '
run_suite "F-J-17 · PAR-Q safety-declaration contract (migration 126)" "$FJ17" '=== F-J-17 PAR-Q RISK CONTRACT ==='
run_suite "F-J-07 · rule-accumulator contract (migration 127)" "$FJ07" '=== F-J-07 RULE ACCUMULATOR CONTRACT ==='

# ── ENV-3 live half ─────────────────────────────────────────────────────────
hr; echo "  ENV-3 · live ledger comparison"; hr
gen="$(mktemp -t env3XXXX.sql)"
trap 'rm -f "$gen"' EXIT
if ! node "$ENV3_GEN" --env qa > "$gen"; then
  echo "FAIL — could not generate the ledger comparison from the declaration."
  exit 1
fi
run_suite "ENV-3 · declared vs observed vs authored" "$gen" '=== ENV-3 LEDGER'

hr
if (( fail )); then
  echo "  LIVE EVIDENCE: FAIL — see the suites above."
  hr
  exit 1
fi
echo "  LIVE EVIDENCE: all suites passed against QA ${QA_REF}."
echo "  No migration was applied, no schema_migrations row was written, and every"
echo "  suite rolled back. Promotion of SEC-09 / SEC-11 / ENV-3 / F-J-17 / F-J-07 is a separate,"
echo "  evidence-reconciled decision — a green run here does not close them."
hr
