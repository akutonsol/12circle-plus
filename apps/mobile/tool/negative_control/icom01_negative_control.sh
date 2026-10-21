#!/usr/bin/env bash
set -euo pipefail

# I-COM-01 / DAT-4 — negative control for the event-registration guard,
# Wave 3A task 3A-6.
#
# QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that "fails against
# the pre-fix tree and passes against the post-fix tree, IN CI". The guard in
# apps/mobile/test/unit/event_registration_contract_test.dart landed in the same
# commit that removed the defect, so on its own no run has ever seen it fail.
# This harness supplies the missing half.
#
# THE PRE-FIX STATE IS REAL, NOT SYNTHETIC. The fabricating catch has existed
# since the initial commit and was removed by this harness's sibling commit, so
# the implementation commit's own PARENT carries the genuine defect:
# `_register()` there invents a `TKT-DEMO-…` code and sets `_registered = true`
# inside its catch. A defective tree is therefore recoverable from history and
# **G-3 is NOT invoked**. This step must never be filed alongside the WKT-204
# and M-1/M-2/M-3 steps, which are of that synthetic class.
#
# It follows ec23_negative_control.sh and uix1_negative_control.sh exactly:
# install the pre-fix state, require the declared failure, restore
# byte-identically, require the pass again. It does not touch application
# behaviour, does not weaken the guard, and contacts nothing.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
REL="apps/mobile/lib/features/classes/presentation/event_ticket_screen.dart"
SCREEN="$ROOT/$REL"
TEST="$ROOT/apps/mobile/test/unit/event_registration_contract_test.dart"
PRE_FIX_REF="${ICOM01_PRE_FIX_REF:-4d6a7d5}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# `flutter test` must run from the package root, so this script does not sit
# at the repository root. Git pathspecs are CWD-relative, so every `git diff`
# below is given the ABSOLUTE $SCREEN — the convention ec23/wrk02 already use
# from this same directory. `<rev>:<path>` is root-relative by definition and
# keeps $REL. Run #54 step 11 failed because the mutation check was handed the
# root-relative path from here: it matched nothing, git reported "no
# differences", and the harness concluded nothing had been reinstated.
cd "$ROOT/apps/mobile"

# A dirty tree can never be mistaken for evidence.
git diff --quiet -- "$SCREEN" || die "$REL already modified"
git diff --cached --quiet -- "$SCREEN" || die "$REL already staged"

# The pre-fix blob must be reachable. A shallow checkout would silently turn
# this harness into a no-op, so it is asserted rather than assumed.
git cat-file -e "$PRE_FIX_REF:$REL" 2>/dev/null \
  || die "$PRE_FIX_REF:$REL is unreachable — the checkout needs fetch-depth: 0"

TMP_SCREEN="$(mktemp)"
cleanup() {
  if [[ -f "$TMP_SCREEN" ]]; then
    cp "$TMP_SCREEN" "$SCREEN" 2>/dev/null || true
    rm -f "$TMP_SCREEN"
  fi
}
trap cleanup EXIT

cp "$SCREEN" "$TMP_SCREEN"

echo "baseline: the I-COM-01 guard must pass"
flutter test "$TEST" --plain-name "I-COM-01"

echo
echo "installing the pre-fix screen from $PRE_FIX_REF"
git show "$PRE_FIX_REF:$REL" > "$SCREEN"

# The mutation must actually reinstate the defect's shape. If the pre-fix file
# ever stops carrying the fabricating catch, this harness stops being evidence
# and says so instead of reporting a pass.
grep -Fq 'TKT-DEMO-' "$SCREEN" \
  || die "$PRE_FIX_REF's screen generates no demo ticket code — not the pre-fix condition"
grep -Fq 'Demo fallback' "$SCREEN" \
  || die "$PRE_FIX_REF's screen carries no 'Demo fallback' catch — not the pre-fix condition"
git diff --quiet -- "$SCREEN" \
  && die "the pre-fix screen is identical to the committed one — nothing was reinstated"
echo "pre-fix tree fabricates a demo ticket after a failed write — the pre-remediation condition"

echo
echo "pre-fix: the I-COM-01 guard must fail"

set +e
OUTPUT="$(flutter test "$TEST" --plain-name "I-COM-01" 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

# The exit code is the authoritative failure signal — Flutter's summary format
# differs between local and CI runners — and the named assertions below prove
# the pre-fix tree broke the intended guard rather than something incidental.
[[ "$RC" -ne 0 ]] || die "the I-COM-01 guard unexpectedly passed against the pre-fix tree"

# All three prohibitions must be demonstrated, not just one: the demo code, the
# fabricated registered state, and the fabricated ticket code.
for assertion in \
  "a demo ticket code was reintroduced" \
  "sets _registered = true" \
  "assigns a ticket code"; do
  printf '%s\n' "$OUTPUT" | grep -Fq "$assertion" \
    || die "expected I-COM-01 failure not observed: $assertion"
done

# The positive anchor must still have passed: if the guard had failed because it
# could no longer find the handler, that is a broken guard, not evidence.
printf '%s\n' "$OUTPUT" | grep -Fq "the guard would be asserting against the wrong method" \
  && die "the pre-fix run failed on the anchor, not on the defect — not clean evidence"

echo
echo "restore: committed implementation"
cp "$TMP_SCREEN" "$SCREEN"
git diff --quiet -- "$SCREEN" || die "$REL was not restored exactly"

echo
echo "restored: the I-COM-01 guard must pass"
flutter test "$TEST" --plain-name "I-COM-01"

echo
echo "RESULT: PASS"
echo "Evidence class: I-COM-01 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI (G-3 not invoked)"
