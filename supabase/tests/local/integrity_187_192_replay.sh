#!/usr/bin/env bash
# Runs integrity_187_192_replay.sql against a LOOPBACK scratch replay. LOCAL EVIDENCE ONLY.
# Refuses any non-loopback target and any QA/production credential.
#
#   integrity_187_192_replay.sh              run against an existing replay ($QAX_DB, default lr)
#   integrity_187_192_replay.sh --build NNN  first (re)build $QAX_DB from shim.sql + migrations 000-NNN
#                                            (same build as beta_manual_loop_replay.sh; NNN=186 gives
#                                            the pre-fix replay, NNN=192 the post-fix one)
#
#   exit 0 every assertion PASSed   1 an assertion FAILed   2 a credential is set
#   3 no server   5 psql failed   6 too few results   7 build failed
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
for v in QA_DB_URL QA_URL QA_SERVICE QA_ANON QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
PSQL=(psql -h 127.0.0.1 -p "${QAX_PGPORT:-55433}" -U postgres -X -tA -q)
DB="${QAX_DB:-lr}"
"${PSQL[@]}" -c 'select 1' postgres >/dev/null 2>&1 || { echo "NO-SERVER|127.0.0.1 unreachable" >&2; exit 3; }

if [[ "${1:-}" == "--build" ]]; then
  through="${2:?--build needs a migration version, e.g. 192}"
  "${PSQL[@]}" -c "drop database if exists $DB" -c "create database $DB" postgres >/dev/null
  "${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$HERE/shim.sql" "$DB" >/dev/null 2>&1 || { echo "BUILD|shim.sql failed" >&2; exit 7; }
  "${PSQL[@]}" -v ON_ERROR_STOP=1 "$DB" >/dev/null <<'SQL' || { echo "BUILD|default privileges failed" >&2; exit 7; }
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
SQL
  for f in "$REPO"/supabase/migrations/*.sql; do
    v="$(basename "$f")"; v="${v%%_*}"
    [[ "$v" > "$through" ]] && continue
    "${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$f" "$DB" >/dev/null 2>&1 || { echo "BUILD|$(basename "$f") did not replay" >&2; exit 7; }
  done
  echo "BUILT|$DB = shim + platform default privileges + migrations 000-$through"
fi

out=$("${PSQL[@]}" -f "$HERE/integrity_187_192_replay.sql" "$DB" 2>&1) || { echo "PSQL-ERROR" >&2; exit 5; }
if grep -q 'ERROR' <<<"$out"; then grep 'ERROR' <<<"$out" | head -5 >&2; echo "PSQL-ERROR|a statement outside run_as() failed" >&2; exit 5; fi
res=$(printf '%s\n' "$out" | grep -E '^(PASS|FAIL)\|' || true)
printf '%s\n' "$res"
n=$(printf '%s\n' "$res" | grep -c . || true)
(( n >= ${MIN_RESULTS:-33} )) || { echo "TOO-FEW|$n results" >&2; exit 6; }
! printf '%s\n' "$res" | grep -q '^FAIL|' || exit 1
echo "ALL $n PASSED"
