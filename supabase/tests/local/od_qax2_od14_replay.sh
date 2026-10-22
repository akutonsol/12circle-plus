#!/usr/bin/env bash
# Runs od_qax2_od14_replay.sql against a LOOPBACK scratch replay of migrations 000-185.
# LOCAL EVIDENCE ONLY. Refuses any non-loopback target and any QA/production credential.
#   exit 0  every assertion PASSed        1  an assertion FAILed
#   3 no server   4 not a 000-185 replay  5 psql failed   6 too few results
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for v in QA_DB_URL QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
HOST=127.0.0.1; PORT="${QAX_PGPORT:-55433}"; DB="${QAX_DB:-lr}"
PSQL=(psql -h "$HOST" -p "$PORT" -U postgres -X -tA -q)
"${PSQL[@]}" -c 'select 1' "$DB" >/dev/null 2>&1 || { echo "NO-SERVER|$HOST:$PORT/$DB unreachable" >&2; exit 3; }
have=$("${PSQL[@]}" -c "select count(*) from pg_proc where proname='assign_nutrition_plan' and prosrc like '%is_active_coach_of%'" "$DB" 2>/dev/null || echo 0)
[[ "$have" == "1" ]] || { echo "NO-REPLAY|migration 184 is not present in $DB" >&2; exit 4; }
out=$("${PSQL[@]}" -f "$HERE/od_qax2_od14_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${QAX_MIN_RESULTS:-40} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }
! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
echo "ALL $n PASSED"
