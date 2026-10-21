#!/usr/bin/env bash
# QA-EXHAUSTION local-replay probe runner. QA-ONLY EVIDENCE TOOL.
#
#   run.sh                  run every probe against the loopback scratch DB
#   run.sh --mutate ID      additionally apply fixsim/ID.sql (a SIMULATED fix) first
#
# Everything runs in ONE transaction that is always ROLLED BACK. It connects only to
# 127.0.0.1 and refuses to start if a QA/production credential is in its environment.
# The target DB must be a replay of supabase/migrations/000-131 on the repo's
# supabase/tests/local/shim.sql plus Supabase's platform default privileges (see
# docs/QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md §15). It is NOT evidence about QA.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for v in QA_DB_URL QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
PGPORT_="${QAX_PGPORT:-55433}"; DB="${QAX_DB:-lr}"; MUT=""
[[ "${1:-}" == "--mutate" ]] && MUT="$HERE/fixsim/${2:?mutation id}.sql"
[[ -n "$MUT" && ! -f "$MUT" ]] && { echo "no such fix-sim: $MUT" >&2; exit 2; }
{ echo 'begin;'; cat "$HERE/fixtures.sql"; [[ -n "$MUT" ]] && cat "$MUT"; cat "$HERE/probes.sql"; echo 'rollback;'; } \
 | psql -h 127.0.0.1 -p "$PGPORT_" -U postgres -X -tA -q "$DB" 2>&1 | grep -E '^(PASS|FAIL)\||ERROR' || true
