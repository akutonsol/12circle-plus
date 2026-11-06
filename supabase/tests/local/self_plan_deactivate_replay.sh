#!/usr/bin/env bash
# Runs self_plan_deactivate_replay.sql (migration 191) against a LOOPBACK scratch
# replay. LOCAL EVIDENCE ONLY — refuses any QA/production credential.
#
#   self_plan_deactivate_replay.sh                     the DB must contain 191; every check must PASS
#   self_plan_deactivate_replay.sh --negative-control  the DB must NOT contain 191; every check in
#                                                      NEGATIVE_EXPECTED must FAIL (the 23503 defect)
#
# Exit 0 = expectation met, 1 = not met, 2 = credential set, 3 = no server,
#      4 = wrong replay for the mode, 5 = psql failed, 6 = too few results.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for v in QA_DB_URL QA_URL QA_SERVICE QA_ANON QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
MODE="${1:-}"
PSQL=(psql -h 127.0.0.1 -p "${QAX_PGPORT:-55433}" -U postgres -X -tA -q)
DB="${QAX_DB:-lr}"
"${PSQL[@]}" -c 'select 1' "$DB" >/dev/null 2>&1 || { echo "NO-SERVER|127.0.0.1/$DB unreachable" >&2; exit 3; }
has=$("${PSQL[@]}" -c "select (prosrc like '%v_progs%')::int from pg_proc where oid = 'public.deactivate_self_generated_plan()'::regprocedure" "$DB")

# D05, G02, G03, N01 and P01 hold on both sides (on the old function G02/G03 hold
# only because the whole call fails and rolls back).
NEGATIVE_EXPECTED=(D01 D02 D03 D04 D06 G01 G04)

if [[ "$MODE" == "--negative-control" ]]; then
  [[ "$has" == "0" ]] || { echo "WRONG-REPLAY|--negative-control needs a replay WITHOUT 191" >&2; exit 4; }
else
  [[ "$has" == "1" ]] || { echo "WRONG-REPLAY|$DB lacks migration 191" >&2; exit 4; }
fi

out=$("${PSQL[@]}" -f "$HERE/self_plan_deactivate_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-13} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }

if [[ "$MODE" == "--negative-control" ]]; then
  bad=0
  for id in "${NEGATIVE_EXPECTED[@]}"; do
    if ! printf '%s\n' "$res" | grep -q "^FAIL|$id "; then echo "NOT-DETECTED|$id passed without 191" >&2; bad=1; fi
  done
  (( bad == 0 )) || exit 1
  echo "NEGATIVE CONTROL OK — all ${#NEGATIVE_EXPECTED[@]} listed checks FAIL without 191"
else
  ! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
  echo "ALL $n PASSED"
fi
