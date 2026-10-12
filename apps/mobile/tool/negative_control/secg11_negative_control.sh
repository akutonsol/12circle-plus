#!/usr/bin/env bash
set -euo pipefail

# SEC-G11 negative control — proves the decision_traces read-scope guard can fail.
#
# ── WHY THIS RUNG EXISTS ───────────────────────────────────────────────────
# `F-J-12` is VERIFIED_CLOSED, and migration 128 records the gap in its own header:
# the I-MIG-03 durability guard tracks FUNCTION properties only, so "nothing in this
# repository would notice if a later migration replaced this policy with a weaker
# one -- the exact mechanism that produced F-J-01". SEC-G11 is that notice. A notice
# nobody has seen fire is not evidence, so this harness fires it.
#
# ── THE MUTATION, AND WHY IT IS A NEW FILE ─────────────────────────────────
# The control adds a THROWAWAY HIGHER-NUMBERED migration that widens the policy. It
# does NOT edit 128 or 125. §8 of the closure standard says never rewrite a migration
# in place unless the wave plan explicitly authorizes it, and no authorization exists
# -- so the mutation is expressed the way a real regression would arrive: as a later
# migration. That makes this control stronger than an in-place edit would be, not
# weaker: it exercises the definer ratchet, which an edit would bypass entirely.
#
# ── THE REPORTER LESSON (§202) ─────────────────────────────────────────────
# Verdicts are read from `--reporter json`, which is identical in every environment
# and carries each test's NAME and RESULT. The GitHub reporter CI uses has no
# "Failing tests:" block, and a control that greps for one passes VACUOUSLY there.
# That defect already shipped once in this programme.

cd "$(dirname "$0")/../.."           # apps/mobile
MIG_DIR="../../supabase/migrations"
TEST="test/unit/decision_trace_read_scope_guard_test.dart"
PROBE="$MIG_DIR/994_secg11_negative_control_probe.sql"
GRANT_PROBE="$MIG_DIR/993_secg11_negative_control_grant_probe.sql"
JSON="$(mktemp)"

die() { echo "SEC-G11 CONTROL FAILED: $*" >&2; exit 1; }
cleanup() { rm -f "$PROBE" "$GRANT_PROBE" "$JSON"; }
trap cleanup EXIT

[[ -f "$TEST" ]] || die "guard not found at $TEST"

echo "── 0 · the clean tree must pass ─────────────────────────────────────────"
flutter test "$TEST" >/dev/null 2>&1 || die "the guard does not pass on a clean tree"
echo "   ok"

echo "── 1 · a later migration widens PD-A05 option (a) ──────────────────────"
cat > "$PROBE" <<'SQL'
-- THROWAWAY PROBE, written and deleted by secg11_negative_control.sh.
-- Simulates the silent-replacement mechanism SEC-G11 exists to notice.
CREATE POLICY "dtrace wide probe" ON public.decision_traces
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM user_profiles
                 WHERE id = auth.uid() AND role IN ('admin','content_manager','coach')));
SQL
grep -q 'content_manager' "$PROBE" || die "the probe was not written -- control is vacuous"

set +e
flutter test "$TEST" --reporter json > "$JSON" 2>/dev/null
RC=$?
set -e
[[ "$RC" -ne 0 ]] || die "THE GUARD PASSED WITH THE POLICY WIDENED. It is not guarding."
echo "   ok -- the guard rejected it"

# Exit status alone is weak: a crash, a missing migrations directory, or a typo
# in this script is also non-zero. Assert WHICH assertions failed, by name.
python3 - "$JSON" <<'PY'
import json, sys

names, results = {}, {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get('type') == 'testStart':
        t = e['test']
        names[t['id']] = t.get('name', '')
    elif e.get('type') == 'testDone' and not e.get('hidden'):
        results[e['testID']] = e.get('result')

failed = [names[i] for i, r in results.items() if r != 'success' and i in names]
if not failed:
    sys.exit('no individual test failed -- the non-zero exit came from somewhere else')

# Each phrase must appear in the name of at least one FAILED test. These are the
# four distinct properties a real widening would break.
required = [
    'content_manager is NOT granted',
    'the bare coach role is never sufficient',
    'no migration ever creates a write policy',
    'exactly the recorded migrations touch decision_traces policies',
]
missing = [p for p in required if not any(p in n for n in failed)]
if missing:
    print('FAILED tests were:', file=sys.stderr)
    for n in failed:
        print('   -', n, file=sys.stderr)
    sys.exit('these properties did NOT fail and should have: ' + '; '.join(missing))

# And the vacuity check must still have PASSED: if the corpus had silently become
# unreadable, everything would "fail" and this control would read as a success.
passed = [names[i] for i, r in results.items() if r == 'success' and i in names]
if not any('the migration corpus is actually found' in n for n in passed):
    sys.exit('the corpus-found assertion did not pass -- the failures above may be '
             'an unreadable tree rather than a detected widening')

print(f'   ok -- {len(failed)} assertion(s) failed, including all four required properties')
print('   ok -- and the corpus-found assertion still passed, so the tree was readable')
PY

rm -f "$PROBE"

echo "-- 1b . the OTHER widening vector: a table-level GRANT ----------------"
# The policy probe above leaves the GRANT assertion untriggered, because a policy
# and a GRANT are different vectors. Analysing which assertions did NOT fire under
# probe 1 is how that gap was found: the GRANT arm had never been shown to fire,
# and an assertion never seen to fail is not evidence. This probe exercises it, and
# the expectation is DELIBERATELY NARROW -- exactly one assertion, because a GRANT
# does not change the policy's shape. That narrowness is also the false-positive
# check.
cat > "$GRANT_PROBE" <<'SQL'
-- THROWAWAY PROBE, written and deleted by secg11_negative_control.sh.
GRANT SELECT ON TABLE public.decision_traces TO content_manager;
SQL
grep -q 'GRANT SELECT' "$GRANT_PROBE" || die "grant probe not written -- control is vacuous"

set +e
flutter test "$TEST" --reporter json > "$JSON" 2>/dev/null
RC=$?
set -e
[[ "$RC" -ne 0 ]] || die "THE GUARD PASSED WITH A ROLE-CLASS GRANT IN THE TREE."

python3 - "$JSON" <<'PY'
import json, sys
names, results = {}, {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get('type') == 'testStart':
        t = e['test']
        names[t['id']] = t.get('name', '')
    elif e.get('type') == 'testDone' and not e.get('hidden'):
        results[e['testID']] = e.get('result')

failed = [names[i] for i, r in results.items() if r != 'success' and i in names]
if not any('no migration GRANTs decision_traces to a role class' in n for n in failed):
    sys.exit('the GRANT assertion did not fire. Failed: ' + ('; '.join(failed) or '(none)'))
if len(failed) != 1:
    sys.exit('expected EXACTLY the GRANT assertion to fail -- a GRANT does not change '
             'the policy shape, so anything else failing is a false positive. Got: '
             + '; '.join(failed))
print('   ok -- exactly one assertion fired, and it was the GRANT arm')
PY
rm -f "$GRANT_PROBE"

echo "-- 2 . remove the probes and prove the guard is green again -----------"
rm -f "$PROBE" "$GRANT_PROBE"
[[ ! -f "$PROBE" && ! -f "$GRANT_PROBE" ]] || die "a probe was not removed"
flutter test "$TEST" >/dev/null 2>&1 || die "the guard does not pass after restoration"
echo "   ok -- restored and green"

echo
echo "SEC-G11 CONTROL PASSED -- the guard detects a widening of PD-A05 option (a)."
