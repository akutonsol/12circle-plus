#!/usr/bin/env bash
# Runs assignment_guard_replay.sql (migrations 189 + 190) against a LOOPBACK scratch
# replay. LOCAL EVIDENCE ONLY — refuses any QA/production credential.
#
#   assignment_guard_replay.sh                     the DB must contain 189 + 190; every check must PASS
#   assignment_guard_replay.sh --negative-control  the DB must contain NEITHER; every check in
#                                                  NEGATIVE_EXPECTED must FAIL (the defects reproduce)
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
has=$("${PSQL[@]}" -c "select (to_regprocedure('public._engine_client_clearance(uuid)') is not null)::int
  + (exists (select 1 from pg_policy where polrelid = 'public.workout_program_assignments'::regclass
              and polname = 'clients read own program assignments'))::int" "$DB")

# What 189 + 190 change. G09/G10/G14/G15, H01/H05-H08 and the P checks are
# positive controls that hold on both sides.
NEGATIVE_EXPECTED=(G01 G02 G03 G04 G05 G06 G07 G08 G11 G12 G13
                   K01 K02 K03 K04 K05 K06 K07 K08
                   H02 H03 H04)

if [[ "$MODE" == "--negative-control" ]]; then
  [[ "$has" == "0" ]] || { echo "WRONG-REPLAY|--negative-control needs a replay WITHOUT 189/190" >&2; exit 4; }
else
  [[ "$has" == "2" ]] || { echo "WRONG-REPLAY|$DB lacks migration 189 and/or 190" >&2; exit 4; }
fi

out=$("${PSQL[@]}" -f "$HERE/assignment_guard_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-34} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }

if [[ "$MODE" == "--negative-control" ]]; then
  bad=0
  for id in "${NEGATIVE_EXPECTED[@]}"; do
    if ! printf '%s\n' "$res" | grep -q "^FAIL|$id "; then echo "NOT-DETECTED|$id passed without 189/190" >&2; bad=1; fi
  done
  (( bad == 0 )) || exit 1
  echo "NEGATIVE CONTROL OK — all ${#NEGATIVE_EXPECTED[@]} listed checks FAIL without 189/190"
else
  ! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
  echo "ALL $n PASSED"
fi
