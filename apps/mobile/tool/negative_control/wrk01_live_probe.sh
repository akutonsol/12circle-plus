#!/usr/bin/env bash
# I-WRK-01 · VERIFIED LIVE — post-fix and pre-fix legs against ONE live QA fixture.
#
# `QA_CLOSURE_STANDARD.md` §2 defines VERIFIED LIVE as "a real request against QA
# [that] reproduces the correct behaviour, **and the same probe demonstrably
# failed before the fix**". This script produces both halves and refuses to
# report either one unless it is genuine.
#
# ── WHAT RUNS ───────────────────────────────────────────────────────────────
#   1. POST-FIX  the current tree, mode=seed-and-read. Creates the fixture and
#                asserts the full progression. Must PASS.
#   2. PRE-FIX   a git worktree at 654b09c^ (the REAL parent — no fabricated
#                copy, no history rewrite), mode=read-only, SAME fixture rows.
#                Must FAIL, and must fail for the one right reason.
#   3. CLEANUP   the current tree, mode=cleanup. Deletes the fixture and proves
#                zero rows remain.
#
# The probe file is copied into the pre-fix worktree because it did not exist
# historically. That copy is the TEST; the `lib/` under test is genuinely
# acd2cc5's, which is the half that matters. Both legs execute a byte-identical
# probe against byte-identical fixture rows.
#
# ── DISCRIMINATION ──────────────────────────────────────────────────────────
# A non-zero exit is NOT evidence. The pre-fix leg counts only if every one of
# these is true, and the script checks each:
#     BOOT ok              Flutter started and Supabase initialised
#     AUTH ok              the fixture identity authenticated
#     FIXTURE present=4    the same rows the post-fix leg asserted are readable
#     SERVICE-CALLED       the real getExerciseProgression() was invoked
#     RESULT len=0         it returned [] — the historical signature
#     ASSERT-NONEMPTY FAIL the non-empty expectation is what failed
#     exit != 0
# Anything else — a compile error, an auth failure, a network failure, a missing
# fixture, a THROW instead of [] — is INFRASTRUCTURE FAILURE and the script
# exits non-zero WITHOUT claiming pre-fix evidence. If the pre-fix tree returns
# data, that is a hard failure too: it would mean the fixture is not being read.
#
#   apps/mobile/tool/negative_control/wrk01_live_probe.sh
#
# Exit 0 only when all three legs did exactly what they must.
set -uo pipefail

PRE_FIX_REF="${PRE_FIX_REF:-654b09c^}"
PROBE="integration_test/wrk01_progression_live_test.dart"
DEVICE="${PROBE_DEVICE:-linux}"
DEFINES="--dart-define-from-file=dart_defines/qa.json"
EXPECT_ROWS=4

: "${PROBE_RUN_ID:?PROBE_RUN_ID is required — the fixture must be run-scoped}"

ROOT="$(git rev-parse --show-toplevel)"
MOBILE="$ROOT/apps/mobile"
WT="$(mktemp -d)/prefix-tree"
LOG_POST="$(mktemp)"; LOG_PRE="$(mktemp)"; LOG_CLEAN="$(mktemp)"

hr() { printf '%s\n' "──────────────────────────────────────────────────────────────────────────"; }
die() { hr; echo "FAIL — $*"; hr; exit 1; }
infra() { hr; echo "INFRASTRUCTURE FAILURE — $*"; echo "This is NOT pre-fix evidence."; hr; exit 1; }

cleanup_always() {
  local rc=$?
  hr; echo "  CLEANUP (always) — fixture ${PROBE_RUN_ID}"
  cd "$MOBILE" || return $rc
  local crc
  flutter test "$PROBE" -d "$DEVICE" $DEFINES \
      --dart-define=PROBE_RUN_ID="$PROBE_RUN_ID" \
      --dart-define=PROBE_MODE=cleanup 2>&1 | tee "$LOG_CLEAN"
  crc=${PIPESTATUS[0]}
  grep -E 'WRK01-MARK (CLEANUP|AUTH|BOOT)' "$LOG_CLEAN" || true
  if ! grep -qF 'WRK01-MARK CLEANUP verified remaining=0' "$LOG_CLEAN"; then
    echo "FAIL — cleanup did not prove zero remaining fixture rows (rc=$crc)."
    echo "       Its full output is above. Layer B (the workflow's if:always()"
    echo "       step) is the independent backstop and still runs."
    rc=1
  else
    echo "  OK — fixture removed, remaining=0"
  fi
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  exit $rc
}
trap cleanup_always EXIT

hr; echo "  I-WRK-01 · VERIFIED LIVE probe"
echo "  fixture id : $PROBE_RUN_ID"
echo "  pre-fix ref: $PRE_FIX_REF -> $(git -C "$ROOT" rev-parse "$PRE_FIX_REF")"
echo "  device     : $DEVICE"; hr

# ── 0 · PREFLIGHT ───────────────────────────────────────────────────────────
#
# Run #37 failed here with `flutter test` exiting 1 after emitting nothing but
# its pub-get lines, so the cause was not recoverable from the run. The probe
# now states its environment and proves its device BEFORE it depends on either,
# so a repeat cannot be silent. This asserts; it configures nothing.
echo; echo "STEP 0 — PREFLIGHT"
echo "  flutter: $(flutter --version 2>&1 | head -1)"
echo "  command: flutter test $PROBE -d $DEVICE $DEFINES --dart-define=PROBE_RUN_ID=… --dart-define=PROBE_MODE=…"
echo "  cwd    : $MOBILE"
echo "  target : $MOBILE/$PROBE"
[[ -f "$MOBILE/$PROBE" ]] || infra "the probe target does not exist at $MOBILE/$PROBE."
echo "  --- flutter devices ---"
DEVICES="$(cd "$MOBILE" && flutter devices 2>&1)"
printf '%s\n' "$DEVICES"
grep -qE "(^|[^a-z0-9_-])${DEVICE}([^a-z0-9_-]|$)" <<<"$DEVICES" \
  || infra "no device matching '$DEVICE' is available to this runner. \
Flutter cannot execute the probe, so nothing here is evidence either way."
echo "  OK — a '$DEVICE' device is present."

# ── 1 · POST-FIX ────────────────────────────────────────────────────────────
echo; echo "STEP 1 — POST-FIX leg (current tree, seed-and-read)"
cd "$MOBILE" || die "cannot enter $MOBILE"
# tee, not a bare redirect: the output must reach the CI log even when the
# command dies without a message, which is exactly how run #37 was lost.
flutter test "$PROBE" -d "$DEVICE" $DEFINES \
    --dart-define=PROBE_RUN_ID="$PROBE_RUN_ID" \
    --dart-define=PROBE_MODE=seed-and-read 2>&1 | tee "$LOG_POST"
POST_RC=${PIPESTATUS[0]}
grep -E 'WRK01-MARK' "$LOG_POST" || true
[[ "$POST_RC" -eq 0 ]] || die "post-fix leg did not pass (rc=$POST_RC). Its full output is above."
grep -qF 'WRK01-MARK ASSERT-ALL PASS' "$LOG_POST" \
  || die "post-fix leg exited 0 without reaching ASSERT-ALL PASS."
grep -qE 'WRK01-MARK FIXTURE (seeded|already-present) rows='"$EXPECT_ROWS" "$LOG_POST" \
  || die "post-fix leg did not establish the $EXPECT_ROWS-row fixture."
echo "  OK — the real getExerciseProgression() returned the seeded progression."

# ── 2 · PRE-FIX ─────────────────────────────────────────────────────────────
echo; echo "STEP 2 — PRE-FIX leg ($PRE_FIX_REF, read-only, SAME fixture)"
git -C "$ROOT" worktree add --detach "$WT" "$PRE_FIX_REF" >/dev/null 2>&1 \
  || infra "could not create a worktree at $PRE_FIX_REF."

# The probe did not exist historically; the lib/ under test is genuinely the
# parent's. Assert that, so this can never silently become a self-test.
if grep -q "logged_at" "$WT/apps/mobile/lib/features/workout/data/workout_service.dart"; then
  infra "$PRE_FIX_REF's workout_service.dart already names logged_at — that is not a pre-fix tree."
fi
grep -q "created_at" "$WT/apps/mobile/lib/features/workout/data/workout_service.dart" \
  || infra "$PRE_FIX_REF's workout_service.dart does not name created_at; the premise is wrong."
cp "$MOBILE/$PROBE" "$WT/apps/mobile/$PROBE"

cd "$WT/apps/mobile" || infra "cannot enter the pre-fix worktree."
flutter pub get > /dev/null 2>&1 || infra "flutter pub get failed in the pre-fix worktree."
flutter test "$PROBE" -d "$DEVICE" $DEFINES \
    --dart-define=PROBE_RUN_ID="$PROBE_RUN_ID" \
    --dart-define=PROBE_MODE=read-only 2>&1 | tee "$LOG_PRE"
PRE_RC=${PIPESTATUS[0]}
grep -E 'WRK01-MARK' "$LOG_PRE" || true

# Every discrimination gate, in order. Each failure is INFRASTRUCTURE, not evidence.
grep -qF 'WRK01-MARK BOOT ok' "$LOG_PRE" || infra "the pre-fix run never initialised Supabase."
grep -qF 'WRK01-MARK AUTH ok' "$LOG_PRE" || infra "the pre-fix run never authenticated."
grep -qF "WRK01-MARK FIXTURE present rows=$EXPECT_ROWS" "$LOG_PRE" \
  || infra "the pre-fix run could not read the $EXPECT_ROWS fixture rows — it did not test the same fixture."
grep -qF 'WRK01-MARK SERVICE-CALLED getExerciseProgression' "$LOG_PRE" \
  || infra "the pre-fix run never reached getExerciseProgression()."
grep -qF 'WRK01-MARK RESULT len=' "$LOG_PRE" \
  || infra "getExerciseProgression() THREW instead of returning [] — not the historical signature."
grep -qF 'WRK01-MARK RESULT len=0' "$LOG_PRE" || {
  echo "  observed: $(grep -F 'WRK01-MARK RESULT len=' "$LOG_PRE")"
  die "the pre-fix tree RETURNED DATA. Either it is not the pre-fix tree, or the probe is not reading the fixture."
}
grep -qF 'WRK01-MARK ASSERT-NONEMPTY FAIL' "$LOG_PRE" \
  || infra "the non-empty expectation was not the assertion that failed."
[[ "$PRE_RC" -ne 0 ]] || die "the pre-fix leg exited 0. A pre-fix tree that passes is not evidence."

echo "  OK — pre-fix: fixture readable, real service called, returned [], non-empty assertion failed."

# ── 3 · VERDICT (cleanup runs from the EXIT trap, pass or fail) ──────────────
hr
echo "  RESULT: PASS — I-WRK-01 VERIFIED LIVE legs both established."
echo "    post-fix $(git -C "$ROOT" rev-parse --short HEAD): progression returned, all assertions pass"
echo "    pre-fix  $(git -C "$ROOT" rev-parse --short "$PRE_FIX_REF"): same fixture, real service, [] , assertion failed"
hr
exit 0
