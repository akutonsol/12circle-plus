#!/usr/bin/env bash
#
# negative-control.sh — SYNTHETIC PRE-FIX-EQUIVALENT CI EVIDENCE.
#
# ── WHAT THIS IS ─────────────────────────────────────────────────────────────
# QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that fails against the
# pre-fix tree and passes against the post-fix tree, in CI. For the Phase 2
# workout guards there IS no pre-fix tree: migrations 119/120 entered version
# control in a single custody commit, and the guards were written after the
# defects were already remediated. A historical red is not obtainable.
#
# Owner ruling, 2026-08-25 (G-3 negative-control exception): in exactly that
# situation the rung may be satisfied by a negative control instead. This script
# is that control. For each declared mutation it
#
#     1. builds an ephemeral, runner-local database,
#     2. replays the COMMITTED migrations 000-121 unmodified,
#     3. loads the committed seeds,
#     4. proves the suite passes 20/20 clean,
#     5. reintroduces exactly one declared defect,
#     6. runs the EXISTING suite unmodified,
#     7. requires the exact declared FAIL set — set equality, both directions,
#     8. restores by re-applying the COMMITTED migration unmodified,
#     9. requires 20/20 again.
#
# ── WHAT THIS IS NOT ─────────────────────────────────────────────────────────
# It is NOT historical pre-fix evidence and must never be recorded as such. The
# real QA BEFORE->AFTER evidence is a separate rung (VERIFIED LIVE), obtained at
# commit 2a8d0b6 and untouched by this script.
#
# It never contacts QA or production. It has no connection string, reads no
# credential, and refuses to start if one is present in its environment. Every
# connection is loopback, to a cluster this script created and destroys.
#
# ── EXIT CODES ───────────────────────────────────────────────────────────────
#   0  every mutation behaved exactly as declared, and every clean run was 20/20
#   1  a check failed (report says which)
#   2  the harness could not run (missing tool, missing file, credential present)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
LOCAL="$REPO/supabase/tests/local"
CONTRACT="$LOCAL/mutations.json"

PGHOST_=127.0.0.1
PGPORT_=55432
PGUSER_=postgres
PGDB_=nc_harness

WORK=""; PG_USER_OWNER=""; INSTALLED_STUBS=(); CREATED_OS_USER=""

say()  { printf '%s\n' "$*"; }
die()  { printf 'FAIL — %s\n' "$*" >&2; exit 1; }
die2() { printf 'FAIL — %s\n' "$*" >&2; exit 2; }

# ── cleanup runs on success, on failure and on cancellation (contract item 12) ─
cleanup() {
  local rc=$?
  set +e
  if [[ -n "$WORK" && -d "$WORK/pgdata" ]]; then
    if [[ -n "$PG_USER_OWNER" ]]; then
      su "$PG_USER_OWNER" -c "$PGCTL -D '$WORK/pgdata' stop -m immediate" >/dev/null 2>&1
    else
      "$PGCTL" -D "$WORK/pgdata" stop -m immediate >/dev/null 2>&1
    fi
  fi
  [[ -n "$WORK" ]] && rm -rf "$WORK"
  for f in "${INSTALLED_STUBS[@]:-}"; do [[ -n "$f" ]] && { rm -f "$f" 2>/dev/null || sudo rm -f "$f" 2>/dev/null; }; done
  [[ -n "$CREATED_OS_USER" ]] && userdel -r "$CREATED_OS_USER" >/dev/null 2>&1
  if [[ $rc -eq 0 ]]; then say ""; say "  cleanup: ephemeral cluster stopped, data directory removed, stubs removed."; fi
  exit $rc
}

# ── 1. This harness must never be able to reach QA or production ─────────────
assert_no_credentials() {
  local v
  for v in QA_DB_URL QA_URL QA_SERVICE QA_ANON SUPABASE_DB_URL SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY DATABASE_URL PGURL; do
    if [[ -n "${!v:-}" ]]; then
      die2 "$v is set in this environment. The negative-control harness must run in a job that carries no environment credentials at all; a set variable means the job scope has widened and the harness refuses rather than proceeding."
    fi
  done
  # The script builds every connection from the constants above and accepts no
  # host argument, so there is no path to a remote project. Assert it anyway.
  [[ "$PGHOST_" == "127.0.0.1" || "$PGHOST_" == "localhost" ]] \
    || die2 "the target host is not loopback ($PGHOST_)."
  say "  targeting: ${PGHOST_}:${PGPORT_}/${PGDB_} — a cluster this script creates and destroys."
  say "  no credential variable is set; the Supabase CLI is never invoked; no connection string is read."
}

find_pg() {
  local d
  PGCTL=""; INITDB=""; PSQL="$(command -v psql || true)"
  for d in /usr/lib/postgresql/*/bin /usr/pgsql-*/bin; do
    [[ -x "$d/pg_ctl" ]] && { PGCTL="$d/pg_ctl"; INITDB="$d/initdb"; break; }
  done
  [[ -z "$PGCTL" ]] && { PGCTL="$(command -v pg_ctl || true)"; INITDB="$(command -v initdb || true)"; }
  [[ -x "$PGCTL" && -x "$INITDB" && -n "$PSQL" ]] \
    || die2 "PostgreSQL server binaries (initdb/pg_ctl) or psql are not available on this runner."
  say "  postgres: $("$INITDB" --version)"
}

psql_() { "$PSQL" -h "$PGHOST_" -p "$PGPORT_" -U "$PGUSER_" -d "${1:-$PGDB_}" "${@:2}"; }

start_cluster() {
  WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/nc-XXXXXX")"
  mkdir -p "$WORK/sock"
  if [[ "$(id -u)" -eq 0 ]]; then
    # initdb refuses to run as root. Use an unprivileged owner for the cluster.
    PG_USER_OWNER=ncpg
    if ! id "$PG_USER_OWNER" >/dev/null 2>&1; then useradd -m "$PG_USER_OWNER"; CREATED_OS_USER="$PG_USER_OWNER"; fi
    chown -R "$PG_USER_OWNER" "$WORK"
    su "$PG_USER_OWNER" -c "$INITDB -D '$WORK/pgdata' -U $PGUSER_ -A trust" >"$WORK/initdb.log" 2>&1 \
      || { tail -5 "$WORK/initdb.log"; die2 "initdb failed."; }
    su "$PG_USER_OWNER" -c "$PGCTL -D '$WORK/pgdata' -o \"-p $PGPORT_ -c listen_addresses=$PGHOST_ -c unix_socket_directories=$WORK/sock\" -l '$WORK/pg.log' start" >/dev/null 2>&1
  else
    "$INITDB" -D "$WORK/pgdata" -U "$PGUSER_" -A trust >"$WORK/initdb.log" 2>&1 \
      || { tail -5 "$WORK/initdb.log"; die2 "initdb failed."; }
    "$PGCTL" -D "$WORK/pgdata" -o "-p $PGPORT_ -c listen_addresses=$PGHOST_ -c unix_socket_directories=$WORK/sock" -l "$WORK/pg.log" start >/dev/null 2>&1
  fi
  local i
  for i in $(seq 1 30); do psql_ postgres -Atqc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
  psql_ postgres -Atqc 'select 1' >/dev/null 2>&1 || { tail -10 "$WORK/pg.log"; die2 "the ephemeral cluster did not start."; }
}

install_ext_stubs() {
  local share dest e
  if command -v pg_config >/dev/null 2>&1; then share="$(pg_config --sharedir)"
  else share="$(dirname "$(dirname "$INITDB")")/share/postgresql"; [[ -d "$share" ]] || share=/usr/share/postgresql/16; fi
  dest="$share/extension"
  [[ -d "$dest" ]] || die2 "the extension directory $dest does not exist."
  for e in pg_cron pg_net; do
    for f in "$e.control" "$e--1.0.sql"; do
      if [[ -e "$dest/$f" ]]; then
        say "  note: $dest/$f already exists (a real extension is installed); leaving it untouched."
      else
        cp "$LOCAL/ext-stubs/$f" "$dest/$f" 2>/dev/null || sudo cp "$LOCAL/ext-stubs/$f" "$dest/$f" \
          || die2 "cannot install the CI-local stub $f into $dest."
        INSTALLED_STUBS+=("$dest/$f")
      fi
    done
  done
}

# ── 2/3. Replay the COMMITTED migrations, then the COMMITTED seeds ───────────
build_baseline() {
  local through="$1" f v out
  # The mutation contract intentionally replays only through its declared
  # baseline (currently 121). Later migrations are outside this synthetic
  # workout-contract harness and are not replayed or mutated here.
  psql_ postgres -q -c "drop database if exists $PGDB_;" -c "create database $PGDB_;" >/dev/null 2>&1
  psql_ "$PGDB_" -v ON_ERROR_STOP=1 -q -f "$LOCAL/shim.sql" >"$WORK/shim.log" 2>&1 \
    || { grep -E 'ERROR' "$WORK/shim.log" | head -3; die "the CI-local shim failed to apply."; }
  for f in "$REPO"/supabase/migrations/*.sql; do
    v="$(basename "$f")"; v="${v%%_*}"
    [[ "$v" > "$through" ]] && continue
    out="$(psql_ "$PGDB_" -v ON_ERROR_STOP=1 -q -f "$f" 2>&1)" \
      || { grep -E 'ERROR|FATAL' <<<"$out" | head -3; die "migration $(basename "$f") did not replay. The harness does not repair migrations."; }
  done
  for f in $(python3 -c "import json;print(' '.join(json.load(open('$CONTRACT'))['baseline']['seeds']))"); do
    out="$(psql_ "$PGDB_" -v ON_ERROR_STOP=1 -q -f "$REPO/$f" 2>&1)" \
      || { grep -E 'ERROR' <<<"$out" | head -3; die "seed $f did not load."; }
  done
  say "  baseline: migrations 000-$through replayed and both seeds loaded (no repository file modified)."
}

# ── 6/7/8/9. Run the EXISTING suite and match the report against a declared set ─
#    The suite always ends in RAISE EXCEPTION so it rolls back; psql's exit code
#    therefore carries no information and the REPORT decides.
run_suite() { psql_ "$PGDB_" -q -f "$REPO/$SUITE" 2>&1; }

check_report() {                       # check_report <label> <expected-fail-ids...>
  local label="$1"; shift
  local expected=("$@") out pass_n fail_n got exp
  out="$(run_suite || true)"   # the suite always raises, so its exit code is meaningless
  printf '%s\n' "$out" > "$WORK/last-report.txt"
  grep -qF "$BANNER" <<<"$out" || { grep -E 'ERROR' <<<"$out" | head -2; die "$label: the suite produced no report banner, so it aborted rather than asserting."; }
  pass_n="$(grep -cE '^PASS +AFTER-' <<<"$out" || true)"
  fail_n="$(grep -cE '^FAIL +AFTER-' <<<"$out" || true)"
  (( pass_n + fail_n == ASSERTIONS )) \
    || die "$label: expected $ASSERTIONS assertions, the report carried $((pass_n+fail_n)). A short report is a broken harness, not a green run."
  got="$( { grep -oE '^FAIL +AFTER-[0-9a-z]+' <<<"$out" || true; } | awk '{print $2}' | sort -u | paste -sd, -)"
  exp="$(printf '%s\n' "${expected[@]-}" | { sed '/^$/d' || true; } | sort -u | paste -sd, -)"
  if [[ "$got" != "$exp" ]]; then
    printf 'FAIL — %s: declared FAIL set [%s], observed [%s].\n' "$label" "${exp:-none}" "${got:-none}" >&2
    grep -E '^FAIL' <<<"$out" | sed 's/^/    /' >&2
    exit 1
  fi
  say "    $label: ${pass_n} PASS / ${fail_n} FAIL — FAIL set [${exp:-none}] exactly as declared."
}

# ── self-test: the parser must be able to fail (contract idiom of this repo) ──
self_test() {
  local ok=0 n=0
  _probe() {   # _probe <name> <report-text> <expected-ids-csv> <should-pass 0|1>
    local name="$1" text="$2" ids="$3" want="$4" rc=0
    if ( BANNER='=== PHASE 2 WORKOUT CONTRACT ==='; ASSERTIONS=3
         run_suite() { printf '%s' "$text"; }
         WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
         arr=()
         if [[ -n "$ids" ]]; then
           IFS=, read -r -a arr <<<"$ids"
         fi
         if ((${#arr[@]})); then
           check_report "selftest" "${arr[@]}" >/dev/null 2>&1
         else
           check_report "selftest" >/dev/null 2>&1
         fi )
    then rc=0; else rc=$?; fi
    n=$((n+1))
    if [[ ( $want -eq 1 && $rc -eq 0 ) || ( $want -eq 0 && $rc -ne 0 ) ]]; then
      say "  ok   $name"; ok=$((ok+1))
    else say "  FAIL $name (rc=$rc, wanted $( [[ $want -eq 1 ]] && echo pass || echo fail ))"; fi
  }
  local good=$'=== PHASE 2 WORKOUT CONTRACT ===\nPASS AFTER-1a x\nPASS AFTER-2 x\nFAIL AFTER-5 x\n'
  say "harness self-test"
  _probe "declared FAIL set matches"            "$good" "AFTER-5"           1
  _probe "an undeclared FAIL is fatal"          "$good" ""                  0
  _probe "a declared FAIL that never occurs is fatal" \
        $'=== PHASE 2 WORKOUT CONTRACT ===\nPASS AFTER-1a x\nPASS AFTER-2 x\nPASS AFTER-5 x\n' "AFTER-5" 0
  _probe "a truncated report is fatal"          $'=== PHASE 2 WORKOUT CONTRACT ===\nPASS AFTER-1a x\n' "" 0
  _probe "a missing banner is fatal"            $'PASS AFTER-1a x\nPASS AFTER-2 x\nPASS AFTER-5 x\n'   "" 0
  say "self-test: $ok/$n"
  [[ $ok -eq $n ]] || die "the harness cannot reliably detect a failure, so it may not judge one."
}

# ─────────────────────────────────────────────────────────────────────────────
[[ -f "$CONTRACT" ]] || die2 "the mutation contract $CONTRACT is missing."
SUITE="$(python3 -c "import json;print(json.load(open('$CONTRACT'))['baseline']['suite'])")"
BANNER="$(python3 -c "import json;print(json.load(open('$CONTRACT'))['baseline']['banner'])")"
ASSERTIONS="$(python3 -c "import json;print(json.load(open('$CONTRACT'))['baseline']['assertions'])")"
THROUGH="$(python3 -c "import json;print(json.load(open('$CONTRACT'))['baseline']['through'])")"

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit 0; fi

trap cleanup EXIT INT TERM

say "═══════════════════════════════════════════════════════════════════════════"
say " NEGATIVE CONTROL — SYNTHETIC PRE-FIX-EQUIVALENT CI EVIDENCE"
say ""
say " This is NOT historical pre-fix evidence. Each defect below is reintroduced"
say " deliberately, into an ephemeral runner-local database, and reverted by"
say " re-applying the committed migration. The real QA BEFORE -> AFTER evidence"
say " is a separate rung (VERIFIED LIVE) and is not produced here."
say " QA and production are not contacted."
say "═══════════════════════════════════════════════════════════════════════════"
say ""
say "environment"
assert_no_credentials
find_pg
start_cluster
install_ext_stubs
say ""
say "baseline"
build_baseline "$THROUGH"
check_report "clean baseline"

mapfile -t IDS < <(python3 -c "import json;[print(m['id']) for m in json.load(open('$CONTRACT'))['mutations']]")
for id in "${IDS[@]}"; do
  eval "$(python3 - "$CONTRACT" "$id" <<'PY'
import json,sys,shlex
m=[x for x in json.load(open(sys.argv[1]))['mutations'] if x['id']==sys.argv[2]][0]
print(f"M_APPLY={shlex.quote(m['apply'])}")
print(f"M_REST={shlex.quote(m['restore_migration'])}")
print(f"M_FIND={shlex.quote(', '.join(m['findings']))}")
print(f"M_WHY={shlex.quote(m['why'])}")
print(f"M_EXPECT=({' '.join(shlex.quote(i) for i in m['expect_fail'])})")
print(f"M_COLL={shlex.quote(', '.join(m.get('collateral',[])) or 'none')}")
PY
)"
  say ""
  say "$id — $M_FIND"
  say "    defect reintroduced: $M_WHY"
  say "    declared FAIL set:   ${M_EXPECT[*]}   (declared collateral: $M_COLL)"
  psql_ "$PGDB_" -v ON_ERROR_STOP=1 -q -c "$M_APPLY" >/dev/null 2>&1 \
    || die "$id: the mutation could not be applied. The declared object may have moved; the contract must be reviewed, not the guard."
  check_report "$id mutated" "${M_EXPECT[@]}"
  psql_ "$PGDB_" -v ON_ERROR_STOP=1 -q -f "$REPO/supabase/migrations/$M_REST" >/dev/null 2>&1 \
    || die "$id: re-applying the committed migration $M_REST failed. Restoration is never hand-authored, so this is fatal."
  say "    restored by re-applying committed migration $M_REST (unmodified)."
  check_report "$id restored"
done

say ""
check_report "final clean run"
say ""
say "═══════════════════════════════════════════════════════════════════════════"
say " RESULT: PASS — every declared defect produced exactly its declared failures,"
say " and every restored state produced ${ASSERTIONS}/${ASSERTIONS}."
say " Evidence class: SYNTHETIC PRE-FIX-EQUIVALENT CI EVIDENCE (VERIFIED IN CI)."
say " No finding is promoted by this run. QA and production were not contacted."
say "═══════════════════════════════════════════════════════════════════════════"
