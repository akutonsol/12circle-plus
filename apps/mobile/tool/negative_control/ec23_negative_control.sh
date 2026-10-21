#!/usr/bin/env bash
set -euo pipefail

# EC-23 / ERR-1 — negative control for the failure-sink guard.
#
# The production guard is the EC-23 group in
# apps/mobile/test/unit/error_sink_test.dart: "no print() call site remains in
# lib/". It landed in 580932f, in the same commit that removed the seven
# pre-ERR-1 print() call sites, so no CI run has ever observed it fail.
# QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that "fails against
# the pre-fix tree and passes against the post-fix tree, IN CI" — this harness
# supplies the missing half.
#
# It follows the accepted convention of wrk02_negative_control.sh exactly:
# mutate the committed tree, require the declared failure, restore
# byte-identically, require the pass again. It does not touch application
# behaviour, does not weaken the guard, and contacts nothing.
#
# THE MUTATION recreates the historical condition rather than a synthetic one.
# The seven sites ERR-1 converted are one-for-one the seven pre-ERR-1 print()
# offenders, so re-inserting one print() beneath each `reportError(...)` call
# reproduces exactly seven offenders in exactly the two files that carried them
# — while leaving `reportError` in place, so that the OTHER EC-23 assertion
# ("the sanctioned swallows named by §5.1 report through the sink") still
# passes. One variable moves, and exactly one assertion is required to break.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
CHECKIN="$ROOT/apps/mobile/lib/features/checkins/data/checkin_service.dart"
MESSAGING="$ROOT/apps/mobile/lib/features/messaging/data/messaging_service.dart"
TEST="$ROOT/apps/mobile/test/unit/error_sink_test.dart"
EXPECTED_OFFENDERS=7

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT/apps/mobile"

for f in "$CHECKIN" "$MESSAGING"; do
  git diff --quiet -- "$f" || die "$(basename "$f") already modified"
  git diff --cached --quiet -- "$f" || die "$(basename "$f") already staged"
done

TMP_CHECKIN="$(mktemp)"
TMP_MESSAGING="$(mktemp)"
cleanup() {
  if [[ -f "$TMP_CHECKIN" ]]; then
    cp "$TMP_CHECKIN" "$CHECKIN" 2>/dev/null || true
    rm -f "$TMP_CHECKIN"
  fi
  if [[ -f "$TMP_MESSAGING" ]]; then
    cp "$TMP_MESSAGING" "$MESSAGING" 2>/dev/null || true
    rm -f "$TMP_MESSAGING"
  fi
}
trap cleanup EXIT

cp "$CHECKIN" "$TMP_CHECKIN"
cp "$MESSAGING" "$TMP_MESSAGING"

echo "baseline: the EC-23 guard must pass"
flutter test "$TEST" --plain-name "EC-23"

echo
echo "mutating: re-introducing the seven pre-ERR-1 print() call sites"

python3 - "$CHECKIN" "$MESSAGING" "$EXPECTED_OFFENDERS" <<'PY'
from pathlib import Path
import re
import sys

paths = sys.argv[1:-1]
expected = int(sys.argv[-1])
anchor = re.compile(r"^(\s*)reportError\('([^']+)', e\);$")

inserted = 0
for name in paths:
    p = Path(name)
    out = []
    for line in p.read_text().split('\n'):
        out.append(line)
        m = anchor.match(line)
        if m:
            indent, origin = m.group(1), m.group(2)
            method = origin.split('.')[-1]
            out.append("%sprint('%s error: $e');" % (indent, method))
            inserted += 1
    p.write_text('\n'.join(out))

if inserted != expected:
    raise SystemExit(
        'mutation anchor count is %d, expected %d — the harness refuses to '
        'assert against a tree it did not mutate as declared' % (inserted, expected))
PY

OFFENDERS="$(grep -rn --include=*.dart -E '(^|[^[:alnum:]_.])print[[:space:]]*\(' \
  "$ROOT/apps/mobile/lib" | grep -cv '//' || true)"
[[ "$OFFENDERS" -eq "$EXPECTED_OFFENDERS" ]] \
  || die "the mutated tree carries $OFFENDERS print() call sites, expected $EXPECTED_OFFENDERS"
echo "mutated tree carries $OFFENDERS print() call sites — the pre-ERR-1 condition"

echo
echo "mutated: the EC-23 guard must fail"

set +e
OUTPUT="$(flutter test "$TEST" --plain-name "EC-23" 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

# The exit code is the authoritative failure signal — Flutter's summary format
# differs between local and CI runners — and the named assertion below proves
# the mutation broke the intended guard rather than something incidental.
[[ "$RC" -ne 0 ]] || die "the EC-23 guard unexpectedly passed against the mutated tree"

for assertion in \
  "no print() call site remains in lib/"; do
  if ! printf '%s\n' "$OUTPUT" | grep -Fq "$assertion"; then
    die "expected EC-23 failure not observed: $assertion"
  fi
done

echo
echo "restore: committed implementation"
cp "$TMP_CHECKIN" "$CHECKIN"
cp "$TMP_MESSAGING" "$MESSAGING"

for f in "$CHECKIN" "$MESSAGING"; do
  git diff --quiet -- "$f" || die "$(basename "$f") was not restored exactly"
done

echo
echo "restored: the EC-23 guard must pass"
flutter test "$TEST" --plain-name "EC-23"

echo
echo "RESULT: PASS"
echo "Evidence class: EC-23 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI"
