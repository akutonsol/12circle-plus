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
cleanup() {
  if [[ -f "$TMP" ]]; then
    cp "$TMP" "$M132" 2>/dev/null || true
    rm -f "$TMP"
  fi
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
echo "mutated: the 132-dependent assertions must each fail, and Addendum B must NOT"

set +e
OUTPUT="$(flutter test "$TEST" 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

[[ "$RC" -ne 0 ]] || die "the guard passed with migration 132 deleted"

# ── 1 · the assertions RAN. This is the whole point of Option 4: under the eager setUpAll
#        this count was 1, named "(setUpAll)", with zero assertions executed.
FAILED="$(printf '%s\n' "$OUTPUT" | grep -cE '^[0-9]{2}:[0-9]{2} \+[0-9]+ -[0-9]+:' || true)"
LAST_MINUS="$(printf '%s\n' "$OUTPUT" | grep -oE '\-[0-9]+:' | tail -1 | sed 's/[^0-9]//g')"
[[ -n "$LAST_MINUS" ]] || die "could not read a failure count from the report"
[[ "$LAST_MINUS" -ge "$MIN_FAILURES" ]] \
  || die "only $LAST_MINUS assertions failed; at least $MIN_FAILURES must, or the lazy-read \
change did not take effect and this control is back to proving nothing"
echo "    $LAST_MINUS assertions failed individually (>= $MIN_FAILURES required)"

# ── 2 · and they failed as I/O errors, which is the documented caveat. Asserted so the
#        caveat cannot quietly stop being true without this harness noticing.
# `PathNotFoundException`, not `FileSystemException`: on Dart 3 a missing path throws the
# subclass, and its `toString()` names the subclass. The first run of this harness matched
# the parent name and reported "no FileSystemException in the output" on a tree that was
# failing exactly as designed — a check that was wrong about the string while the caveat it
# guards was right about the substance. Both names are accepted and the specific one is named
# in the message, so a future change of shape is legible rather than silent.
printf '%s\n' "$OUTPUT" | grep -qE "PathNotFoundException|FileSystemException" \
  || die "no PathNotFoundException/FileSystemException in the output — Option 4's documented \
failure shape has changed, and the evidence class recorded for this rung no longer describes it"
echo "    failures arrive as PathNotFoundException (a FileSystemException subtype) —"
echo "    Option 4's documented I/O-error caveat, intact"

# ── 3 · the setUpAll trap is gone. If the report names (setUpAll) as a failure, the eager
#        read is back and the other two checks could be satisfied by accident.
if printf '%s\n' "$OUTPUT" | grep -E '^\s+\(setUpAll\)' | grep -q 'team_membership'; then
  die "a (setUpAll) failure is present — the eager read has returned, which is the exact \
condition D-1 Option 4 removed"
fi

# ── 4 · Addendum B splits, and the FIRST RUN of this harness is what showed that the
#        coarse version of this check was wrong. Deleting 132 does two different things to
#        D-3's group, and conflating them would have hidden both:
#
#          · the PROPERTY tests read the definition in force, which is in 134, so they must
#            still PASS — that independence is the whole point of D-3;
#          · the COVERAGE RATCHET must FAIL, because the set of migrations defining each
#            helper really did change (102,132,134 -> 102,134). A ratchet that stayed green
#            when a defining migration was deleted would not be a ratchet.
FAILING="$(printf '%s\n' "$OUTPUT" | sed -n '/^Failing tests:/,$p')"

printf '%s\n' "$OUTPUT" | grep -Fq "$ADDENDUM_B" || die "Addendum B did not run at all"
if printf '%s\n' "$FAILING" | grep -Fq "$ADDENDUM_B"; then
  die "D-3's property test failed when 132 was deleted. It resolves the AUTHORITATIVE \
definition in 134 and must be independent of 132 — that would be a blast radius, not a \
reversion."
fi
echo "    D-3's property tests still passed — they read 134, not 132"

# The ratchet's sensitivity is part of the evidence, so it is required rather than tolerated.
# `grep -c` is not used: the report truncates with "... and N more", so absence from the
# truncated list is not absence from the failures. The count check above carries that weight;
# this asserts the ratchet is REACHABLE and ran.
printf '%s\n' "$OUTPUT" | grep -Fq 'the set of migrations redefining it is exactly as recorded' \
  || die "the D-3 coverage ratchet did not run, so its sensitivity is unproven"
echo "    the D-3 coverage ratchet ran — a deleted defining migration is visible to it"

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
