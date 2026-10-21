#!/usr/bin/env bash
set -euo pipefail

# DAT-2 / I-INT-02 (and the I-INT-01 half that lived in the same allowlist
# entry) — negative control for the schema-contract column guard, Wave 3A
# task 3A-4.
#
# QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that "fails against
# the pre-fix tree and passes against the post-fix tree, IN CI". The column
# guard in supabase/tests/contract/run.mjs passes on the fixed tree, but the
# pre-fix tree carried `user_profiles.goal` and `user_profiles.equipment`
# INSIDE the known-violations allowlist, so on its own the guard never
# demonstrates the failure. This harness supplies the missing half: it installs
# the pre-fix Edge Function against the POST-FIX allowlist, requires both named
# failures, restores byte-identically and requires the pass again.
#
# It follows nut01_negative_control.sh and uix1_negative_control.sh exactly. It
# does not touch application behaviour, does not weaken the guard, adds no
# allowlist entry, and contacts nothing.
#
# THE PRE-FIX STATE IS REAL, NOT SYNTHETIC. ai-generate-workout/index.ts at the
# reference below carries the actual defect:
# `.from('user_profiles').select('fitness_goal, goal, equipment, …')`, while
# `user_profiles` has neither `goal` nor `equipment` — 000_baseline defines
# `fitness_goal` and no ADD COLUMN since has ever added either name (001's
# `user_profiles` block is a shadow CREATE TABLE IF NOT EXISTS that never
# executes). A defective tree is therefore recoverable from history and **G-3
# is NOT invoked**. This step must never be filed alongside the WKT-204 and
# M-1/M-2/M-3 steps, which are of that synthetic class.
#
# No credential, no network, no toolchain: `npm run test:contract` is
# `node supabase/tests/contract/run.mjs`, which imports only node builtins and
# reads no environment variable.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
REL="supabase/functions/ai-generate-workout/index.ts"
FN="$ROOT/$REL"
PRE_FIX_REF="${INT02_PRE_FIX_REF:-c678102}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT"

# A dirty tree can never be mistaken for evidence.
git diff --quiet -- "$REL" || die "$REL already modified"
git diff --cached --quiet -- "$REL" || die "$REL already staged"

# The pre-fix blob must be reachable. A shallow checkout would silently turn
# this harness into a no-op, so it is asserted rather than assumed.
git cat-file -e "$PRE_FIX_REF:$REL" 2>/dev/null \
  || die "$PRE_FIX_REF:$REL is unreachable — the checkout needs fetch-depth: 0"

TMP_FN="$(mktemp)"
cleanup() {
  if [[ -f "$TMP_FN" ]]; then
    cp "$TMP_FN" "$FN" 2>/dev/null || true
    rm -f "$TMP_FN"
  fi
}
trap cleanup EXIT

cp "$FN" "$TMP_FN"

echo "baseline: the contract guard must pass"
npm run --silent test:contract

echo
echo "installing the pre-fix Edge Function from $PRE_FIX_REF"
git show "$PRE_FIX_REF:$REL" > "$FN"

# The mutation must actually reinstate the defect's shape. If the pre-fix file
# ever stops carrying the phantom columns, this harness stops being evidence
# and says so instead of reporting a pass.
grep -Fq "select('fitness_goal, goal, equipment," "$FN" \
  || die "$PRE_FIX_REF's function carries no user_profiles goal/equipment select — not the pre-fix condition"
git diff --quiet -- "$REL" \
  && die "the pre-fix function is identical to the committed one — nothing was reinstated"
echo "pre-fix tree reads user_profiles.goal and user_profiles.equipment — the pre-remediation condition"

echo
echo "pre-fix: the contract guard must fail"

set +e
OUTPUT="$(npm run --silent test:contract 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

# The exit code is the authoritative failure signal; the two named assertions
# prove the pre-fix tree broke the intended guard rather than something
# incidental. An unrelated failure fails this harness; it is never tolerated.
[[ "$RC" -ne 0 ]] || die "the contract guard unexpectedly passed against the pre-fix tree"

for COL in goal equipment; do
  printf '%s\n' "$OUTPUT" \
    | grep -Fq "column   user_profiles.$COL is referenced but does not exist" \
    || die "expected DAT-2 / I-INT-02 failure not observed: user_profiles.$COL"
done

# The pre-fix run must fail for these two reasons ALONE. Any other FAIL line
# means an unrelated defect is in play and this run is not clean evidence.
OTHER="$(printf '%s\n' "$OUTPUT" | grep -F 'FAIL   ' \
  | grep -Fv 'user_profiles.goal' \
  | grep -Fv 'user_profiles.equipment' || true)"
[[ -z "$OTHER" ]] || die "the pre-fix run carries unrelated failures:"$'\n'"$OTHER"

echo
echo "restore: committed implementation"
cp "$TMP_FN" "$FN"
git diff --quiet -- "$REL" || die "$REL was not restored exactly"

echo
echo "restored: the contract guard must pass"
npm run --silent test:contract

echo
echo "RESULT: PASS"
echo "Evidence class: DAT-2 / I-INT-02 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI (G-3 not invoked)"
