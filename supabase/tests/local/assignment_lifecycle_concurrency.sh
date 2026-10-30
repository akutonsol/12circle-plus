#!/usr/bin/env bash
# Concurrency check for migration 195 — LOCAL EVIDENCE ONLY, loopback scratch cluster.
#
#   QAX_DB=<replay> assignment_lifecycle_concurrency.sh                     replay WITH 195
#   QAX_DB=<replay> assignment_lifecycle_concurrency.sh --negative-control  replay WITHOUT 195
#
# Clones the given replay (CREATE DATABASE ... TEMPLATE — the source is never
# written), commits a coach (K2), an active client (X) and three of K2's
# programmes, then runs genuinely concurrent sessions through the API login
# (`authenticator` -> SET ROLE authenticated, K2's claims):
#   C1  READ COMMITTED: A activates P1 and holds its transaction open for 2 s; B
#       activates P2 0.5 s later. With 195, B waits on the per-client lock and then
#       replaces A's row: exactly ONE active row, P2.   Without 195: TWO.
#   C2  REPEATABLE READ: an activation is refused (ASSIGNMENT_ISOLATION_UNSUPPORTED)
#       with 195. Without 195 it is accepted.
#   C3  SERIALIZABLE: the same overlap as C1. With 195 at most ONE active row
#       remains (PostgreSQL either serializes B behind A or aborts B with 40001).
# Drops the clone afterwards. Refuses any QA/production credential.
# Exit 0 = every expectation met, 1 = not met, 2 = credential set, 3 = no server, 4 = wrong replay.
set -euo pipefail
for v in QA_DB_URL QA_URL QA_SERVICE QA_ANON QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
MODE="${1:-}"
PSQL=(psql -h 127.0.0.1 -p "${QAX_PGPORT:-55433}" -U postgres -X -tA -q)
SRC="${QAX_DB:-lr}"; CLONE="lc_conc_$$"
"${PSQL[@]}" -c 'select 1' "$SRC" >/dev/null 2>&1 || { echo "NO-SERVER" >&2; exit 3; }
has=$("${PSQL[@]}" -c "select (to_regprocedure('public.retire_my_assignment(uuid)') is not null)::int" "$SRC")
if [[ "$MODE" == "--negative-control" ]]; then [[ "$has" == "0" ]] || { echo "WRONG-REPLAY|needs a replay WITHOUT 195" >&2; exit 4; }
else [[ "$has" == "1" ]] || { echo "WRONG-REPLAY|$SRC lacks 195" >&2; exit 4; }; fi
trap '"${PSQL[@]}" -c "drop database if exists $CLONE" postgres >/dev/null 2>&1' EXIT
"${PSQL[@]}" -c "create database $CLONE template $SRC" postgres

K2=a2000000-0000-0000-0000-00000000000b; X=a2000000-0000-0000-0000-0000000000a1
P1=a2100000-0000-0000-0000-0000000000b1; P2=a2100000-0000-0000-0000-0000000000b2; P3=a2100000-0000-0000-0000-0000000000b3
"${PSQL[@]}" -v ON_ERROR_STOP=1 "$CLONE" <<SQL
insert into auth.users(id,email) values ('$K2','conc-k2@local'), ('$X','conc-x@local');
update public.user_profiles set role='coach' where id='$K2';
insert into public.coach_client_relationships(coach_id,client_id,status,initiated_by) values ('$K2','$X','active','client');
insert into public.workout_programs(id, coach_id, name) values ('$P1','$K2','conc P1'), ('$P2','$K2','conc P2'), ('$P3','$K2','conc P3');
SQL

session() {  # session <isolation> <programme> <sleep-seconds>
  "${PSQL[@]}" "$CLONE" 2>&1 <<SQL
begin isolation level $1;
select set_config('request.jwt.claims', '{"sub":"$K2","role":"authenticated"}', true) is not null;
set local session authorization authenticator;
set local role authenticated;
insert into public.workout_program_assignments(program_id, client_id, coach_id, status, current_week)
values ('$2', '$X', '$K2', 'active', 1);
select pg_sleep($3);
commit;
SQL
}
active() { "${PSQL[@]}" -c "select count(*)||':'||coalesce(string_agg(right(program_id::text,2), ',' order by program_id), '') from public.workout_program_assignments where client_id='$X' and status='active'" "$CLONE"; }
reset_x() { "${PSQL[@]}" -c "delete from public.workout_program_assignments where client_id='$X'" "$CLONE"; }

bad=0
# C1 · READ COMMITTED overlap
reset_x
session "read committed" "$P1" 2 >/tmp/lc_a_$$ & A=$!
sleep 0.5
session "read committed" "$P2" 0 >/tmp/lc_b_$$ & B=$!
wait $A; wait $B
c1=$(active)
if [[ "$MODE" == "--negative-control" ]]; then
  [[ "$c1" == 2:* ]] && echo "FAIL|C1 READ COMMITTED overlap left $c1 active (the defect reproduces)" || { echo "NOT-DETECTED|C1 $c1"; bad=1; }
else
  [[ "$c1" == "1:b2" ]] && echo "PASS|C1 READ COMMITTED overlap: the later activation waited and replaced the first — $c1" || { echo "FAIL|C1 READ COMMITTED overlap left $c1"; bad=1; }
fi
# C2 · REPEATABLE READ
reset_x
c2=$(session "repeatable read" "$P3" 0 | grep -o 'ASSIGNMENT_ISOLATION_UNSUPPORTED' | head -1 || true)
c2n=$(active)
if [[ "$MODE" == "--negative-control" ]]; then
  [[ -z "$c2" && "$c2n" == "1:b3" ]] && echo "FAIL|C2 REPEATABLE READ activation accepted ($c2n) — no guard" || { echo "NOT-DETECTED|C2 $c2 $c2n"; bad=1; }
else
  [[ "$c2" == "ASSIGNMENT_ISOLATION_UNSUPPORTED" && "$c2n" == 0:* ]] && echo "PASS|C2 REPEATABLE READ activation refused, nothing written" || { echo "FAIL|C2 got '$c2' and $c2n"; bad=1; }
fi
# C3 · SERIALIZABLE overlap
reset_x
session "serializable" "$P1" 2 >/tmp/lc_c_$$ & A=$!
sleep 0.5
session "serializable" "$P2" 0 >/tmp/lc_d_$$ & B=$!
wait $A; wait $B
c3=$(active); c3err=$(grep -ho 'could not serialize[^"]*' /tmp/lc_c_$$ /tmp/lc_d_$$ | head -1 || true)
if [[ "$MODE" == "--negative-control" ]]; then
  echo "INFO|C3 SERIALIZABLE overlap without 195: $c3 ${c3err:+(one aborted: $c3err)}"
else
  [[ "$c3" == 1:* ]] && echo "PASS|C3 SERIALIZABLE overlap: one active row ($c3)${c3err:+ — the second was aborted: $c3err}" || { echo "FAIL|C3 SERIALIZABLE overlap left $c3"; bad=1; }
fi
rm -f /tmp/lc_a_$$ /tmp/lc_b_$$ /tmp/lc_c_$$ /tmp/lc_d_$$
if [[ "$MODE" == "--negative-control" ]]; then
  (( bad == 0 )) && echo "NEGATIVE CONTROL OK — the race and the missing isolation guard reproduce without 195"
else
  (( bad == 0 )) && echo "ALL CONCURRENCY CHECKS PASSED"
fi
exit $bad
