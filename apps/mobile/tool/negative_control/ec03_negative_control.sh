#!/usr/bin/env bash
set -euo pipefail

# EC-03 — negative control for the intake false-completion end-to-end rung.
#
# The production guard is apps/mobile/test/widget/ec03_intake_false_completion_e2e_test.dart.
# Its second arm landed in the SAME commit that closed the defect it describes, so no CI run
# has ever observed it fail. QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that
# "fails against the pre-fix tree and passes against the post-fix tree, IN CI" — this harness
# supplies the missing half. It follows wrk02/ec23's convention exactly: mutate the committed
# tree, require the declared failure, restore byte-identically, require the pass again.
#
# THE MUTATION IS THE HISTORICAL SHAPE, NOT A SYNTHETIC ONE. Before the fix, `_finish()`
# wrapped the entire save in `if (uid != null) { … }` and set the completion state
# unconditionally afterwards — so a null uid skipped the save and the flow still rendered
# IntakeCompletePage. Re-collapsing the explicit null arm back into that wrapper restores
# precisely that tree, and nothing else about the method changes.
#
# EXACTLY ONE OF THE TWO ARMS MUST BREAK. The first arm covers a save that was ATTEMPTED and
# failed, which the original EC-03 fix already handled; it must keep passing against the
# mutated tree. If both arms fail, the mutation reached further than declared and the harness
# refuses the run — a control that breaks everything proves nothing about what it aimed at.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
FLOW="$ROOT/apps/mobile/lib/features/onboarding/presentation/intake_flow_screen.dart"
TEST="$ROOT/apps/mobile/test/widget/ec03_intake_false_completion_e2e_test.dart"

ARM_SESSION='a SESSION LOST MID-FLOW'
ARM_FAILED_SAVE='a SAVE THAT FAILS'

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT/apps/mobile"

git diff --quiet -- "$FLOW" || die "intake_flow_screen.dart already modified"
git diff --cached --quiet -- "$FLOW" || die "intake_flow_screen.dart already staged"

TMP_FLOW="$(mktemp)"
cleanup() {
  if [[ -f "$TMP_FLOW" ]]; then
    cp "$TMP_FLOW" "$FLOW" 2>/dev/null || true
    rm -f "$TMP_FLOW"
  fi
}
trap cleanup EXIT

cp "$FLOW" "$TMP_FLOW"

echo "baseline: both EC-03 arms must pass"
flutter test "$TEST"

echo
echo "mutating: collapsing the explicit null-uid arm back into 'if (uid != null)'"

python3 - "$FLOW" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
src = p.read_text()

# SCOPED TO `_finish()` FIRST, and the harness's own self-check is what forced this.
# `if (uid == null) {` is NOT unique to the file — `_loadProgress` opens with the identical
# line, and it comes first, so an unscoped search mutated the wrong method entirely. The
# post-mutation assertion caught it ("the null-uid arm survived"), which is exactly the job
# of a check that states what it expects to find.
fn = src.find('Future<void> _finish() async {')
if fn < 0:
    raise SystemExit('_finish() was not found — the contract must be reviewed, not the guard')

start = src.find('    if (uid == null) {', fn)
if start < 0:
    raise SystemExit('the null-uid arm was not found inside _finish() — the fix may have '
                     'moved; the contract must be reviewed, not the guard')
end = src.find('    {\n', start)
if end < 0:
    raise SystemExit('the bare block that replaced the old wrapper was not found')

mutated = src[:start] + '    if (uid != null) {\n' + src[end + len('    {\n'):]
if mutated == src:
    raise SystemExit('the mutation changed nothing')

# COUNTED, NOT SLICED — and two earlier drafts of this check were wrong in opposite
# directions. `if (uid == null) {` occurs THREE times in this file: `_loadProgress` before
# `_finish()` and a third method after it. An unscoped `in` test reported the arm as
# surviving when it had been removed; scoping to "everything after `_finish()`" still saw
# the third. A count says exactly what is meant: one occurrence left, the other two intact.
before_n = src.count('    if (uid == null) {')
after_n = mutated.count('    if (uid == null) {')
if after_n != before_n - 1:
    raise SystemExit('expected the null-uid arm count to fall from %d to %d, got %d — the '
                     'mutation reached the wrong method' % (before_n, before_n - 1, after_n))
if 'not signed in' in mutated:
    raise SystemExit('the post-fix message survived, so the mutation under-reached')
p.write_text(mutated)
PY

grep -Fq 'if (uid != null) {' "$FLOW" \
  || die "the mutated tree does not carry the pre-fix wrapper"
# `! grep … || die`, NOT `grep … && die`: under `set -e` the second form exits 1 on the
# HAPPY path, because a failing grep is the last command of the && list and its non-zero
# status becomes the list's. The harness would then fail precisely when the mutation was
# correct.
! grep -Fq 'not signed in' "$FLOW" \
  || die "the mutated tree still carries the post-fix message — the mutation under-reached"
echo "mutated tree carries the pre-fix 'if (uid != null)' wrapper"

echo
echo "mutated: the session-lost arm must fail, and the failed-save arm must NOT"

# VERDICTS COME FROM `--reporter json`, NOT FROM THE SUMMARY TEXT (V5 §202, §208).
# The previous form of this block asserted set equality by extracting Flutter's
# "Failing tests:" section and checking the failed-save arm was absent from it. That
# section is printed by the EXPANDED/COMPACT reporters and NOT by the GitHub reporter
# CI attaches — so in CI the extraction yielded an empty string, the grep matched
# nothing, the `if` was false, and the harness printed "only the session-lost arm
# failed, exactly as declared" WITHOUT HAVING CHECKED ANYTHING. The same defect was
# found and fixed in secw1 at §202; this is its sibling.
#
# The positive direction was weak too: grepping the whole output for an arm's NAME
# matches when the test merely RUNS, because every reporter prints the name either
# way. So both directions are now read from per-test RESULTS.
JSON="$(mktemp)"
trap 'rm -f "$JSON"' EXIT
set +e
flutter test "$TEST" --reporter json > "$JSON" 2>/dev/null
RC=$?
set -e

[[ "$RC" -ne 0 ]] || die "the EC-03 guard unexpectedly passed against the mutated tree"

python3 - "$JSON" "$ARM_SESSION" "$ARM_FAILED_SAVE" <<'PY'
import json, sys

path, arm_session, arm_failed_save = sys.argv[1], sys.argv[2], sys.argv[3]
names, results = {}, {}
for line in open(path):
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

rows = [(names[i], r) for i, r in results.items() if i in names]
if not rows:
    sys.exit('no per-test results were parsed -- the control cannot judge anything')

def find(fragment):
    hits = [(n, r) for n, r in rows if fragment in n]
    if not hits:
        sys.exit(f'the arm {fragment!r} did not RUN at all. Absence is not evidence: '
                 f'a renamed or removed test would otherwise read as success. '
                 f'Observed: ' + '; '.join(n for n, _ in rows))
    if len(hits) > 1:
        sys.exit(f'{fragment!r} matched {len(hits)} tests; the arm must be unambiguous')
    return hits[0]

sname, sresult = find(arm_session)
fname, fresult = find(arm_failed_save)

if sresult == 'success':
    sys.exit(f'the session-lost arm PASSED against the mutated tree: {sname!r}. '
             f'The mutation under-reached, or the arm does not test what it claims.')
if fresult != 'success':
    sys.exit(f'the failed-save arm did not pass: {fname!r} -> {fresult}. The mutation '
             f'reached further than declared -- the original fix already closed that arm -- '
             f'so this run proves nothing about the arm under test.')

print(f'   session-lost arm FAILED as declared    : {sname}')
print(f'   failed-save arm still PASSED           : {fname}')
print(f'   {len(rows)} test(s) judged by per-test result, not by summary text')
PY
echo "only the session-lost arm failed, exactly as declared"

echo
echo "restore: committed implementation"
cp "$TMP_FLOW" "$FLOW"
git diff --quiet -- "$FLOW" || die "intake_flow_screen.dart was not restored exactly"

echo
echo "restored: both EC-03 arms must pass"
flutter test "$TEST"

echo
echo "RESULT: PASS"
echo "Evidence class: EC-03 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI"
