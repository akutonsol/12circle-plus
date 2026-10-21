#!/usr/bin/env bash
set -euo pipefail

# UIX-1 / M-03 — negative control for the schema-contract embed guard.
#
# The production guard is the embedded-resource check in
# supabase/tests/contract/run.mjs: every embed head spelled `alias:column` must
# resolve through a foreign key whose target schema is `public`. It landed in
# 527438a, the same commit that removed the defect, so CI run #43 met it only
# on the fixed tree. QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check
# that "fails against the pre-fix tree and passes against the post-fix tree, IN
# CI" — this harness supplies the missing half.
#
# It follows ec23_negative_control.sh exactly: install the pre-fix state,
# require the declared failure, restore byte-identically, require the pass
# again. It does not touch application behaviour, does not weaken the guard,
# and contacts nothing.
#
# THE PRE-FIX STATE IS REAL, NOT SYNTHETIC. booking_screen.dart at f109f19
# carries the actual defect — `.select(... coach:coach_id(...))` on
# coach_client_relationships, whose coach_id is a foreign key to auth.users
# (000_baseline_preexisting_tables.sql:237), which PostgREST cannot traverse.
# A defective tree is therefore recoverable from history and **G-3 is NOT
# invoked**. This step must never be filed alongside the WKT-204 and M-1/M-2/M-3
# steps, which are of that synthetic class.
#
# No credential, no network, no toolchain: `npm run test:contract` is
# `node supabase/tests/contract/run.mjs`, which imports only node builtins and
# reads no environment variable.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
SCREEN="$ROOT/apps/mobile/lib/features/booking/presentation/booking_screen.dart"
REL="apps/mobile/lib/features/booking/presentation/booking_screen.dart"
PRE_FIX_REF="${UIX1_PRE_FIX_REF:-f109f19}"
ASSERTION="coach_client_relationships.coach_id is embedded but no foreign key reaches the public schema"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT"

# A dirty tree can never be mistaken for evidence.
git diff --quiet -- "$SCREEN" || die "$(basename "$SCREEN") already modified"
git diff --cached --quiet -- "$SCREEN" || die "$(basename "$SCREEN") already staged"

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

echo "baseline: the contract guard must pass"
npm run --silent test:contract

echo
echo "installing the pre-fix screen from $PRE_FIX_REF"
git show "$PRE_FIX_REF:$REL" > "$SCREEN"

# The mutation must actually reinstate the defect's shape. If the pre-fix file
# ever stops carrying the embed, this harness stops being evidence and says so
# instead of reporting a pass.
grep -Fq 'coach:coach_id(' "$SCREEN" \
  || die "$PRE_FIX_REF's screen carries no coach:coach_id( embed — not the pre-fix condition"
git diff --quiet -- "$SCREEN" \
  && die "the pre-fix screen is identical to the committed one — nothing was reinstated"
echo "pre-fix tree carries the coach:coach_id( embed — the pre-remediation condition"

echo
echo "pre-fix: the contract guard must fail"

set +e
OUTPUT="$(npm run --silent test:contract 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

# The exit code is the authoritative failure signal, and the named assertion
# below proves the pre-fix tree broke the intended guard rather than something
# incidental. An unrelated failure fails this harness; it is never tolerated.
[[ "$RC" -ne 0 ]] || die "the contract guard unexpectedly passed against the pre-fix tree"

printf '%s\n' "$OUTPUT" | grep -Fq "$ASSERTION" \
  || die "expected UIX-1 failure not observed: $ASSERTION"

# The pre-fix run must fail for this reason ALONE. Any other FAIL line means an
# unrelated defect is in play and this run is not clean evidence.
OTHER="$(printf '%s\n' "$OUTPUT" | grep -F 'FAIL   ' | grep -Fv "$ASSERTION" || true)"
[[ -z "$OTHER" ]] || die "the pre-fix run carries unrelated failures:"$'\n'"$OTHER"

echo
echo "restore: committed implementation"
cp "$TMP_SCREEN" "$SCREEN"
git diff --quiet -- "$SCREEN" || die "$(basename "$SCREEN") was not restored exactly"

echo
echo "restored: the contract guard must pass"
npm run --silent test:contract

echo
echo "RESULT: PASS"
echo "Evidence class: UIX-1 PRE-FIX / POST-FIX GUARD EVIDENCE, IN CI (G-3 not invoked)"
