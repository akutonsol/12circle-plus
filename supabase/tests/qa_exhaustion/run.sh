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
# Exit codes, so a caller can tell the four outcomes apart:
#   0 every expected probe ran and none failed
#   1 a probe FAILed, or a SQL ERROR appeared (a reproduced defect)
#   2 usage (unknown fix-sim, or a refused credential above)
#   3 no server / connection refused      4 connected but not a 000-131 replay
#   5 psql itself failed                  6 fewer probe results than expected
# An empty output stream is NEVER success: before this, a refused connection
# printed nothing and exited 0, which is indistinguishable from an all-pass run.
PSQL=(psql -h 127.0.0.1 -p "$PGPORT_" -U postgres -X -tA -q)
FLOOR="${QAX_MIN_PROBES:-37}"   # the suite emits exactly 37 results in every
                                # configuration (bare and each --mutate). Raise it
                                # when probes are added: a floor below the real count
                                # is slack a truncated run can hide in.

"${PSQL[@]}" -c 'select 1' "$DB" >/dev/null 2>&1 \
  || { echo "NO-SERVER|127.0.0.1:$PGPORT_/$DB unreachable" >&2; exit 3; }

# The probes are meaningless against anything but the documented replay.
have=$("${PSQL[@]}" -c "select count(*) from pg_views where schemaname='public' and viewname in ('exercises','exercise_certifications')" "$DB" 2>/dev/null || echo 0)
[[ "$have" == "2" ]] \
  || { echo "NO-REPLAY|expected replay views missing ($have/2) -- see run.sh header" >&2; exit 4; }

set +e
out=$({ echo 'begin;'; cat "$HERE/fixtures.sql"; [[ -n "$MUT" ]] && cat "$MUT"; cat "$HERE/probes.sql"; echo 'rollback;'; } \
      | "${PSQL[@]}" "$DB" 2>&1)
rc=$?
set -e
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\||ERROR' || true)
[[ -n "$res" ]] && printf '%s\n' "$res"

(( rc == 0 )) || { echo "PSQL-ERROR|psql exited $rc" >&2; exit 5; }
n=$(printf '%s\n' "$res" | grep -cE '^(PASS|FAIL)\|' || true)
(( n >= FLOOR )) || { echo "TRUNCATED|$n probe results, expected >= $FLOOR" >&2; exit 6; }
if printf '%s\n' "$res" | grep -qE '^FAIL\||ERROR'; then exit 1; fi
exit 0
