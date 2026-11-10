#!/usr/bin/env bash
# Runs program_ownership_replay.sql (migration 192) against a LOOPBACK scratch
# replay. LOCAL EVIDENCE ONLY — refuses any QA/production credential.
#
#   program_ownership_replay.sh                     the DB must contain 192; every check must PASS
#   program_ownership_replay.sh --negative-control  the DB must NOT contain 192 (but must contain
#                                                   187-190); every check in NEGATIVE_EXPECTED must
#                                                   FAIL — each confirmed bypass reproduces
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
base=$("${PSQL[@]}" -c "select (to_regprocedure('public._engine_client_clearance(uuid)') is not null)::int" "$DB")
has=$("${PSQL[@]}" -c "select (to_regprocedure('public._assignment_program_ownership()') is not null)::int" "$DB")
[[ "$base" == "1" ]] || { echo "WRONG-REPLAY|$DB lacks 187-190" >&2; exit 4; }

# Every bypass the audit confirmed. O05/O06, R02-R04, A06-A08, V06/V07 and P01
# are positive controls (legitimate owner, client and admin workflows) that must
# hold on both sides — except where they need a 192 object.
NEGATIVE_EXPECTED=(O01 O02 O03 O04 O07 O08 R01 A01 A02 A03 A04 A05 V01 V02 V03 V04 V05 V08)

if [[ "$MODE" == "--negative-control" ]]; then
  [[ "$has" == "0" ]] || { echo "WRONG-REPLAY|--negative-control needs a replay WITHOUT 192" >&2; exit 4; }
else
  [[ "$has" == "1" ]] || { echo "WRONG-REPLAY|$DB lacks migration 192" >&2; exit 4; }
fi

out=$("${PSQL[@]}" -f "$HERE/program_ownership_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-31} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }

if [[ "$MODE" == "--negative-control" ]]; then
  bad=0
  for id in "${NEGATIVE_EXPECTED[@]}"; do
    if ! printf '%s\n' "$res" | grep -q "^FAIL|$id "; then echo "NOT-DETECTED|$id passed without 192" >&2; bad=1; fi
  done
  (( bad == 0 )) || exit 1
  echo "NEGATIVE CONTROL OK — all ${#NEGATIVE_EXPECTED[@]} listed checks FAIL without 192"
else
  ! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
  echo "ALL $n PASSED"
fi
