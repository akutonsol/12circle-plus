#!/usr/bin/env bash
# Runs engine_materialize_replay.sql against a LOOPBACK scratch replay. LOCAL EVIDENCE ONLY.
# Refuses any QA/production credential. Exit 0 = all PASS, 1 = a FAIL, 3 = no server, 5 = psql failed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for v in QA_DB_URL QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
PSQL=(psql -h 127.0.0.1 -p "${QAX_PGPORT:-55433}" -U postgres -X -tA -q)
DB="${QAX_DB:-lr}"
"${PSQL[@]}" -c 'select 1' "$DB" >/dev/null 2>&1 || { echo "NO-SERVER|127.0.0.1/$DB unreachable" >&2; exit 3; }
out=$("${PSQL[@]}" -f "$HERE/engine_materialize_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-28} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }
! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
echo "ALL $n PASSED"
