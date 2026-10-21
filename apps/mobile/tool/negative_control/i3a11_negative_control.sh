#!/usr/bin/env bash
set -euo pipefail

# 3A-11 — negative control for the identity-constraint guards (I-G1…I-G5).
#
# QA_CLOSURE_STANDARD §2 defines VERIFIED IN CI as a check that "fails against
# the pre-fix tree and passes against the post-fix tree, IN CI". The guards in
# apps/mobile/test/unit/identity_constraint_guard_test.dart land in the same
# commit that adds migration 131 and the three writer changes, so on their own
# no run has ever seen them fail. This harness supplies the missing half.
#
# THE PRE-FIX STATE IS REAL, NOT SYNTHETIC. Every defect these guards pin has
# existed since long before this task: `client_nutrition_plans` has had no
# uniqueness since 023/024, `cycle_logs` none since 033, `conversations` none
# since 000, and `client_session_credits` none since 028 — and all three writer
# call sites carry their original check-then-insert / bare-insert shape at the
# implementation commit's own PARENT. A defective tree is therefore recoverable
# from history and **G-3 is NOT invoked**. This step must never be filed
# alongside the WKT-204 and M-1/M-2/M-3 steps, which are of that synthetic class.
#
# It follows icom01_negative_control.sh exactly: install the pre-fix state,
# require the declared failure, restore byte-identically, require the pass
# again. It does not touch application behaviour and contacts nothing.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"

MIGRATION_REL="supabase/migrations/131_identity_constraints.sql"
MESSAGING_REL="apps/mobile/lib/features/messaging/data/messaging_service.dart"
COACH_REL="apps/mobile/lib/features/coach/data/coach_program_service.dart"
WEBHOOK_REL="supabase/functions/stripe-webhook/index.ts"
TEST_REL="apps/mobile/test/unit/identity_constraint_guard_test.dart"

MIGRATION="$ROOT/$MIGRATION_REL"
TEST="$ROOT/$TEST_REL"
PRE_FIX_REF="${I3A11_PRE_FIX_REF:-43b48a7}"

die() { echo "ERROR: $*" >&2; exit 1; }

# `flutter test` must run from the package root, so this script does not sit at
# the repository root. Git pathspecs are CWD-relative, so every `git diff` below
# is given an ABSOLUTE path — the convention icom01/ec23/wrk02 already use from
# this same directory. `<rev>:<path>` is root-relative by definition.
cd "$ROOT/apps/mobile"

# A dirty tree can never be mistaken for evidence.
for rel in "$MESSAGING_REL" "$COACH_REL" "$WEBHOOK_REL"; do
  git diff --quiet -- "$ROOT/$rel" || die "$rel already modified"
  git diff --cached --quiet -- "$ROOT/$rel" || die "$rel already staged"
done

# The pre-fix blobs must be reachable. A shallow checkout would silently turn
# this harness into a no-op, so it is asserted rather than assumed.
for rel in "$MESSAGING_REL" "$COACH_REL" "$WEBHOOK_REL"; do
  git cat-file -e "$PRE_FIX_REF:$rel" 2>/dev/null \
    || die "$PRE_FIX_REF:$rel is unreachable — the checkout needs fetch-depth: 0"
done

# Migration 131 must NOT exist at the pre-fix ref. If it does, the ref is wrong
# and the whole comparison is meaningless.
if git cat-file -e "$PRE_FIX_REF:$MIGRATION_REL" 2>/dev/null; then
  die "$PRE_FIX_REF already carries $MIGRATION_REL — wrong PRE_FIX_REF"
fi

TMP_DIR="$(mktemp -d)"
cp "$ROOT/$MESSAGING_REL" "$TMP_DIR/messaging.dart"
cp "$ROOT/$COACH_REL"     "$TMP_DIR/coach.dart"
cp "$ROOT/$WEBHOOK_REL"   "$TMP_DIR/webhook.ts"
cp "$MIGRATION"           "$TMP_DIR/131.sql"

restore() {
  cp "$TMP_DIR/messaging.dart" "$ROOT/$MESSAGING_REL"
  cp "$TMP_DIR/coach.dart"     "$ROOT/$COACH_REL"
  cp "$TMP_DIR/webhook.ts"     "$ROOT/$WEBHOOK_REL"
  cp "$TMP_DIR/131.sql"        "$MIGRATION"
  rm -rf "$TMP_DIR"
}
trap restore EXIT

echo "── 3A-11 negative control ─────────────────────────────────────────────"
echo "   pre-fix ref: $PRE_FIX_REF"
echo

# ── 1 · the guard must PASS on the tree as committed ────────────────────────
echo "1. post-fix tree — the guard must PASS"
flutter test "$TEST" >/dev/null 2>&1 \
  || die "the guard fails on the post-fix tree; nothing below would mean anything"
echo "   PASS"

# ── 2 · install the real pre-fix state ──────────────────────────────────────
echo "2. installing the pre-fix state from $PRE_FIX_REF"
git show "$PRE_FIX_REF:$MESSAGING_REL" > "$ROOT/$MESSAGING_REL"
git show "$PRE_FIX_REF:$COACH_REL"     > "$ROOT/$COACH_REL"
git show "$PRE_FIX_REF:$WEBHOOK_REL"   > "$ROOT/$WEBHOOK_REL"
rm -f "$MIGRATION"

# The mutation must be real. If nothing changed, the harness proves nothing.
git diff --quiet -- "$ROOT/$MESSAGING_REL" "$ROOT/$COACH_REL" "$ROOT/$WEBHOOK_REL" \
  && die "no differences were installed — the mutation did not take"
[[ -f "$MIGRATION" ]] && die "migration 131 was not removed"
echo "   three writers reverted; migration 131 removed"

# ── 3 · the guard must FAIL ─────────────────────────────────────────────────
echo "3. pre-fix tree — the guard must FAIL"
if flutter test "$TEST" >/dev/null 2>&1; then
  die "the guard PASSED against the pre-fix tree — it cannot detect the defect"
fi
echo "   FAIL, as required"

# ── 4 · restore byte-identically and pass again ─────────────────────────────
echo "4. restoring and re-running"
restore
trap - EXIT

git diff --quiet -- "$ROOT/$MESSAGING_REL" "$ROOT/$COACH_REL" "$ROOT/$WEBHOOK_REL" \
  || die "restore was not byte-identical"
[[ -f "$MIGRATION" ]] || die "migration 131 was not restored"

flutter test "$TEST" >/dev/null 2>&1 || die "the guard fails after restore"
echo "   PASS"
echo
echo "── 3A-11 negative control: the guard fails pre-fix and passes post-fix ──"
