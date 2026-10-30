#!/usr/bin/env bash
# Runs engine_gate_replay.sql (migrations 187 + 188) against a LOOPBACK scratch
# replay. LOCAL EVIDENCE ONLY — refuses any QA/production credential.
#
#   engine_gate_replay.sh                     the DB must contain 187 + 188; every check must PASS
#   engine_gate_replay.sh --negative-control  the DB must NOT contain them; every check in
#                                             NEGATIVE_EXPECTED must FAIL — proof that each one
#                                             detects the old behaviour instead of passing vacuously
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
has=$("${PSQL[@]}" -c "select (to_regprocedure('public._intel_required_attributes()') is not null)::int
                          + (to_regprocedure('public._engine_focus_patterns(text)') is not null)::int" "$DB")

# The checks the OLD engine and review functions must FAIL. Each is a behaviour
# 187/188 changes; a check missing from this list either passes on both (a
# positive control, e.g. B07, B12, P01) or depends on a 187/188 object. D13 (every
# focused day has a compound) is NOT listed: the old engine's identical days happen
# to include a compound decoy, so it passes there by coincidence — D15/D16/D17 are
# the checks that discriminate the compound rule.
NEGATIVE_EXPECTED=(A01 A02 A03 A04 A05 A06 A07 A08 A09 A10 A11 A12 A13 A14 A15 A16 A17 A18 A19 A20
                   D02 D03 D04 D05 D06 D07 D09 D10 D11 D14 D15 D16 D17 E01 E02
                   B01 B02 B03 B04 B05 B06 B08 B09 B10 B11 B13 B14 B16
                   R01 R02 R03 R04 R05)

if [[ "$MODE" == "--negative-control" ]]; then
  [[ "$has" == "0" ]] || { echo "WRONG-REPLAY|--negative-control needs a replay WITHOUT 187/188" >&2; exit 4; }
else
  [[ "$has" == "2" ]] || { echo "WRONG-REPLAY|$DB lacks migration 187 and/or 188" >&2; exit 4; }
fi

out=$("${PSQL[@]}" -f "$HERE/engine_gate_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-73} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }

if [[ "$MODE" == "--negative-control" ]]; then
  bad=0
  for id in "${NEGATIVE_EXPECTED[@]}"; do
    if ! printf '%s\n' "$res" | grep -q "^FAIL|$id "; then echo "NOT-DETECTED|$id passed on the old behaviour" >&2; bad=1; fi
  done
  (( bad == 0 )) || exit 1
  echo "NEGATIVE CONTROL OK — all ${#NEGATIVE_EXPECTED[@]} listed checks FAIL without 187/188"
else
  ! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
  echo "ALL $n PASSED"
fi
