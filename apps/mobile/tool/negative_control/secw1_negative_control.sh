#!/usr/bin/env bash
set -euo pipefail

# SEC-W1 / QAX-SEC-08 fourth rung — the negative control D-1 authorizes.
#
# OWNER DECISION 2026-10-11 · `D-1` = Option 4: "change SEC-W1's `setUpAll` to lazy reads,
# then delete". §365 recorded why the other three options were rejected — deleting the
# migration under an EAGER `setUpAll` exercises **0 of 15** assertions, because in
# `package:test` a failing `setUpAll` means the group's tests never run; an isolated worktree
# at the pre-fix commit has the same property; and mutating 132's text in place is UNSETTLED
# against §8 of the closure standard, which says never rewrite a migration in place unless
# the wave plan explicitly authorizes it.
#
# ── WHAT THIS PROVES, AND WHAT IT DOES NOT ─────────────────────────────────
#
# With lazy reads, deleting migration 132 makes each 132-dependent assertion fail ON ITS OWN.
# The failures arrive as `FileSystemException` — I/O errors — rather than as the guard's
# curated `reason:` strings. That is Option 4's documented cost, preserved by the
# authorization rather than hidden:
#
#   PROVES      the 132-dependent assertions execute, and fail when Wave 1 is reverted.
#   DOES NOT    prove they fail for the reason each one states.
#
# A stronger rung would need the mutation option, which is the one §8 does not permit.
#
# ── WHY ADDENDUM B MUST KEEP PASSING ───────────────────────────────────────
#
# D-3's group resolves the AUTHORITATIVE helper definitions, which live in 134. Deleting 132
# must not disturb it — and this harness requires that, because if Addendum B failed too the
# control would be demonstrating a blast radius rather than a reversion. The two halves of
# this guard assert different things and the control is where that becomes visible.
#
# Follows the convention of ec23/wrk02/ec03_negative_control.sh: mutate the committed tree,
# require the declared failure, restore byte-identically, require the pass again. It contacts
# nothing and needs no credential.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
M132="$ROOT/supabase/migrations/132_team_membership_lifecycle.sql"
TEST="$ROOT/apps/mobile/test/unit/team_membership_lifecycle_guard_test.dart"

# The assertion count that must execute and fail. Twelve tests read 132's text; Addendum B
# and the D-2 fixture group do not, and must survive.
MIN_FAILURES=12
ADDENDUM_B='the definition IN FORCE is 134'

die() { echo "ERROR: $*" >&2; exit 1; }

cd "$ROOT/apps/mobile"

git diff --quiet -- "$M132" || die "migration 132 already modified"
git diff --cached --quiet -- "$M132" || die "migration 132 already staged"

TMP="$(mktemp)"
JSON="$(mktemp)"
cleanup() {
  if [[ -f "$TMP" ]]; then
    cp "$TMP" "$M132" 2>/dev/null || true
    rm -f "$TMP"
  fi
  rm -f "$JSON"
}
trap cleanup EXIT

cp "$M132" "$TMP"

echo "baseline: the whole guard must pass"
flutter test "$TEST"

echo
echo "mutating: removing migration 132 — the Wave 1 reversion this guard exists to catch"
rm "$M132"
[[ ! -f "$M132" ]] || die "migration 132 was not removed"

echo
echo "mutated: the 132-dependent assertions must each fail, with D-3 splitting"

# ── THE JSON REPORTER, AND WHY THIS HARNESS USES IT ────────────────────────
#
# The first CI run of this control FAILED while the tree under test behaved exactly as
# designed. Locally `flutter test` prints the compact reporter (`00:00 +30 -13:`); in GitHub
# Actions it prints the GitHub reporter (`✅ <name>` lines and `30 tests passed, 13 failed.`).
# The parser read the compact form, found no count, and died — and worse, the "Failing tests:"
# block it used for the D-3 checks DOES NOT EXIST in the GitHub reporter, so those checks
# would have passed VACUOUSLY there.
#
# `--reporter json` is the same in every environment and carries each test's NAME and RESULT,
# so every assertion below names the test it judges instead of pattern-matching a summary
# line. A control whose verdict depends on which reporter is attached is not a control.
set +e
flutter test "$TEST" --reporter json > "$JSON" 2>/dev/null
RC=$?
set -e

[[ "$RC" -ne 0 ]] || die "the guard passed with migration 132 deleted"

python3 - "$JSON" "$MIN_FAILURES" <<'PY'
import json, sys

path, min_failures = sys.argv[1], int(sys.argv[2])
names, results, errors = {}, {}, []
for line in open(path):
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        e = json.loads(line)
    except Exception:
        continue
    t = e.get('type')
    if t == 'testStart':
        names[e['test']['id']] = (e['test']['name'], bool(e['test'].get('metadata', {}).get('skip')))
    elif t == 'testDone':
        results[e['testID']] = (names.get(e['testID'], ('?', False))[0], e.get('result'), e.get('hidden'))
    elif t == 'error':
        errors.append(str(e.get('error', '')))

visible = {i: r for i, r in results.items() if not r[2]}
failed = {n for (n, res, _) in visible.values() if res != 'success'}
hidden_failed = [n for (n, res, h) in results.values() if h and res != 'success']

def die(msg):
    print('ERROR: ' + msg, file=sys.stderr)
    sys.exit(1)

# 1 · the assertions RAN. Under the eager setUpAll this was 1, named "(setUpAll)", with
#     zero assertions executed. That is the whole point of D-1 Option 4.
if len(failed) < min_failures:
    die(f'only {len(failed)} assertions failed; at least {min_failures} must, or the '
        f'lazy-read change did not take effect and this control proves nothing')
print(f'    {len(failed)} assertions failed individually (>= {min_failures} required)')

# 2 · and they failed as I/O errors — Option 4's documented caveat. PathNotFoundException is
#     the Dart 3 FileSystemException subtype for a missing path, and its toString names the
#     subclass; the first version of this check matched only the parent name.
if not any('PathNotFoundException' in e or 'FileSystemException' in e for e in errors):
    die("no PathNotFoundException/FileSystemException among the errors — Option 4's "
        'documented failure shape has changed, and the evidence class recorded for this '
        'rung no longer describes it')
print('    failures arrive as PathNotFoundException (a FileSystemException subtype) —')
print("    Option 4's documented I/O-error caveat, intact")

# 3 · the setUpAll trap is gone. A hidden failure named (setUpAll) means the eager read is
#     back, and checks 1 and 2 could then be satisfied while the assertions never ran.
if any('setUpAll' in n for n in hidden_failed):
    die('a (setUpAll) failure is present — the eager read has returned, which is the exact '
        'condition D-1 Option 4 removed')
print('    no (setUpAll) failure — the eager-read trap stays removed')

# 4 · D-3 SPLITS, and the first run of this harness is what showed the coarse check was
#     wrong. The property tests read the definition in force, which is in 134, so they must
#     still PASS. The coverage ratchet must FAIL, because the definer set really did change
#     (102,132,134 -> 102,134) — a ratchet that stayed green when a defining migration was
#     deleted would not be a ratchet.
property_tests = [n for (n, _, _) in visible.values() if 'the definition IN FORCE is 134' in n]
ratchet_tests = [n for (n, _, _) in visible.values()
                 if 'the set of migrations redefining it is exactly as recorded' in n]
if len(property_tests) < 2:
    die(f'found {len(property_tests)} D-3 property tests; both helpers must be judged')
if len(ratchet_tests) < 2:
    die(f'found {len(ratchet_tests)} D-3 ratchet tests; both helpers must be judged')
leaked = [n for n in property_tests if n in failed]
if leaked:
    die("D-3's property tests failed when 132 was deleted. They resolve the AUTHORITATIVE "
        'definition in 134 and must be independent of 132 — that is a blast radius, not a '
        'reversion: ' + '; '.join(leaked))
print("    D-3's property tests passed — they read 134, not 132")
silent = [n for n in ratchet_tests if n not in failed]
if silent:
    die("D-3's coverage ratchet stayed GREEN with a defining migration deleted, so it is "
        'not ratcheting: ' + '; '.join(silent))
print('    the D-3 coverage ratchet fired — a deleted defining migration is visible to it')
PY

echo
echo "restore: committed migration"
cp "$TMP" "$M132"
git diff --quiet -- "$M132" || die "migration 132 was not restored exactly"

echo
echo "restored: the whole guard must pass"
flutter test "$TEST"

echo
echo "RESULT: PASS"
echo "Evidence class: SEC-W1 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI"
echo "Caveat (D-1 Option 4, authorized): failures are I/O errors, so this proves the"
echo "assertions EXECUTE and FAIL — not that each fails for the reason it states."
