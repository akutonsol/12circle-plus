#!/usr/bin/env bash
# Upgrade check for migration 187 — LOCAL EVIDENCE ONLY, loopback scratch cluster.
#
#   QAX_DB=<a 000-186 replay> engine_gate_upgrade_check.sh
#
# Clones the given 000-186 replay (CREATE DATABASE ... TEMPLATE, so the source is
# never written), approves one profile the OLD way — model self-confidence 99, no
# human review — applies 187 and 188 to the CLONE, and checks that the legacy
# approval was withdrawn while a properly human-reviewed one survived. Drops the
# clone afterwards. Refuses any QA/production credential and any non-loopback host.
# Exit 0 = both checks PASS, 1 = a FAIL, 2 = credential set, 3 = no server, 4 = wrong replay.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
for v in QA_DB_URL QA_URL QA_SERVICE QA_ANON QA_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY DATABASE_URL SUPABASE_DB_URL; do
  [[ -n "${!v:-}" ]] && { echo "refusing: $v is set" >&2; exit 2; }
done
PSQL=(psql -h 127.0.0.1 -p "${QAX_PGPORT:-55433}" -U postgres -X -tA -q)
SRC="${QAX_DB:-lr}"; CLONE="gate_upgrade_$$"
"${PSQL[@]}" -c 'select 1' "$SRC" >/dev/null 2>&1 || { echo "NO-SERVER" >&2; exit 3; }
[[ $("${PSQL[@]}" -c "select (to_regprocedure('public._intel_required_attributes()') is null
     and to_regprocedure('public.materialize_program_week_engine(uuid,integer,jsonb)') is not null)::int" "$SRC") == 1 ]] \
  || { echo "WRONG-REPLAY|$SRC must be a 000-186 replay without 187" >&2; exit 4; }
trap '"${PSQL[@]}" -c "drop database if exists $CLONE" postgres >/dev/null 2>&1' EXIT
"${PSQL[@]}" -c "create database $CLONE template $SRC" postgres

"${PSQL[@]}" -v ON_ERROR_STOP=1 "$CLONE" <<'SQL'
insert into auth.users(id,email) values ('ad000000-0000-0000-0000-0000000000e1','upgrade-editor@local') on conflict do nothing;
update public.user_profiles set role='content_manager' where id='ad000000-0000-0000-0000-0000000000e1';
insert into public.custom_exercises(id, name, visibility, submission_status) values
  ('ab000000-0000-0000-0000-0000000000f1', 'upgrade legacy', 'global', 'approved'),
  ('ab000000-0000-0000-0000-0000000000f2', 'upgrade reviewed', 'global', 'approved');
insert into public.exercise_intelligence(exercise_id, attribute_confidence, status) values
  ('ab000000-0000-0000-0000-0000000000f1', '{"joint_stress":99,"fatigue":99,"contraindications":99,"rep_ranges":99,"programming_goals":99,"biomechanics":99,"loading":99,"coaching":99}', 'ai_generated'),
  ('ab000000-0000-0000-0000-0000000000f2', '{"joint_stress":50,"fatigue":50,"contraindications":50,"rep_ranges":50,"programming_goals":50,"biomechanics":50,"loading":50,"coaching":50}', 'ai_generated');
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-0000-0000-0000000000e1","role":"authenticated"}', false);
set role authenticated;
select public.finalize_intelligence('ab000000-0000-0000-0000-0000000000f1');      -- old path: approved on self-confidence
select public.review_attribute('ab000000-0000-0000-0000-0000000000f2', a, 'approved')
  from unnest(array['programming_goals','fatigue','joint_stress','contraindications','rep_ranges','biomechanics','loading','coaching']) a;
select public.finalize_intelligence('ab000000-0000-0000-0000-0000000000f2');
reset role;
SQL
before=$("${PSQL[@]}" -c "select string_agg(right(exercise_id::text,2)||'='||status, ',' order by 1) from public.exercise_intelligence where exercise_id::text like 'ab000000-0000-0000-0000-0000000000f%'" "$CLONE")
for m in 187_intelligence_approval_contract.sql 188_engine_certification_gate_and_session_focus.sql; do
  "${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$REPO/supabase/migrations/$m" "$CLONE" 2>&1 | grep -E 'NOTICE|ERROR' || true
done
s1=$("${PSQL[@]}" -c "select status from public.exercise_intelligence where exercise_id='ab000000-0000-0000-0000-0000000000f1'" "$CLONE")
s2=$("${PSQL[@]}" -c "select status from public.exercise_intelligence where exercise_id='ab000000-0000-0000-0000-0000000000f2'" "$CLONE")
echo "before 187: $before"
bad=0
if [[ "$s1" == "under_review" ]]; then echo "PASS|U01 a self-confidence-only approval made before 187 is withdrawn by 187|$s1"
else echo "FAIL|U01 a self-confidence-only approval made before 187 is withdrawn by 187|$s1"; bad=1; fi
# Pre-187 reviews carry no fingerprint, so even a fully human-reviewed profile must
# be re-reviewed once: the contract cannot vouch for what a review covered.
if [[ "$s2" == "under_review" ]]; then echo "PASS|U02 a pre-187 human-reviewed approval is also withdrawn (its reviews carry no fingerprint)|$s2"
else echo "FAIL|U02 a pre-187 human-reviewed approval is also withdrawn (its reviews carry no fingerprint)|$s2"; bad=1; fi
exit $bad
