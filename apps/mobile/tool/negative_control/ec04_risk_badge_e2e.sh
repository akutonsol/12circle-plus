#!/usr/bin/env bash
set -euo pipefail

# EC-04 — VERIFIED END-TO-END runner for the risk badge.
#
# QA_CLOSURE_STANDARD §2's "Error contract / false success" class requires
# FIXED IN CODE · VERIFIED IN CI · **VERIFIED END-TO-END for any user-facing success
# state**. SEC-G6 supplies the CI rung statically. This supplies the end-to-end one, by
# driving integration_test/ec04_risk_badge_device_test.dart on a real desktop target.
#
# WHAT THIS RUNG ADDS THAT THE HOST CANNOT. The accessibility guarantee — that a screen
# reader is TOLD the assessment is absent — is asserted on the host in
# test/widget/ec04_risk_badge_semantics_test.dart, because the semantics tree is readable
# there and a host test is debuggable and runs on every push. What only hardware can
# answer is whether "NOT ASSESSED" — longer than the "LOW RISK" it replaced — still fits
# its pill at the real font and a real device pixel ratio. The host harness renders in
# Ahem, where every glyph is a full em square, so it cannot. A clipped badge would put the
# fix back where it started: a coach unable to read that nobody assessed the client.
#
# IT REFUSES TO REPORT SUCCESS OVER AN INFRASTRUCTURE FAILURE. The probe emits
# EC04-MARKER lines; if they are absent, the driver never reached the surface and this
# exits as an INFRASTRUCTURE failure rather than a pass or an assertion failure. That
# distinction is uix1_booking_e2e.sh's, and it exists because a green exit code over a
# screen nobody mounted is the most expensive kind of false evidence.
#
# No credential of its own: it reads dart_defines/qa.json, and the probe overrides
# clientDetailProvider with an in-memory profile. NOTHING IS SIGNED IN, no backend is
# written, and no real client's risk is asserted.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
PROBE="integration_test/ec04_risk_badge_device_test.dart"
DEVICE="${PROBE_DEVICE:-linux}"
DEFINES="--dart-define-from-file=dart_defines/qa.json"

die()   { echo "FAIL: $*" >&2; exit 1; }
infra() { echo "INFRASTRUCTURE FAILURE: $*" >&2; exit 2; }

cd "$ROOT/apps/mobile"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "── EC-04 end-to-end · device=$DEVICE ────────────────────────────────"

# Preflight. `flutter devices` is read WITHOUT a pipe into grep -q: under pipefail an
# early-closing reader makes flutter die of SIGPIPE (141), which uix1 learned in run #46.
DEVLIST="$(flutter devices 2>&1 || true)"
case "$DEVLIST" in
  *"$DEVICE"*) : ;;
  *) infra "device '$DEVICE' is not present. flutter devices said:
$DEVLIST" ;;
esac

set +e
flutter test "$PROBE" -d "$DEVICE" $DEFINES 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

# ── the discrimination pass ────────────────────────────────────────────────
# A toolchain failure and a failed assertion are different findings, and neither may be
# reported as the other.
if grep -qiE "unable to find utility|xcodebuild|No supported devices|Failed to load" "$LOG"; then
  infra "the probe never ran — toolchain or device error, not an EC-04 result."
fi

MOUNTED=$(grep -c "EC04-MARKER mounted=client_detail" "$LOG" || true)
FITS=$(grep -c "EC04-MARKER fits=1" "$LOG" || true)
ASSESSED=$(grep -c "EC04-MARKER assessed_" "$LOG" || true)

if [ "$STATUS" -ne 0 ]; then
  if [ "${MOUNTED:-0}" -eq 0 ]; then
    infra "the driver never mounted the client-detail surface, so this run is not
       EC-04 evidence either way."
  fi
  die "the probe reached the surface and an assertion FAILED — this is a real EC-04
     regression. See the log above."
fi

# A zero exit is not enough. Every marker must be present, or the assertions did not
# actually execute the paths they claim to.
[ "${MOUNTED:-0}"   -ge 1 ] || infra "no mount marker — the surface was never reached."
[ "${FITS:-0}" -ge 1 ] || die "no fit marker — the physical measurement did not run, so
     nothing proves the badge fits its pill at the real font and dpr." 
[ "${ASSESSED:-0}"  -ge 2 ] || die "fewer than two assessed-state markers — the control
     cases (low, high) did not both run, so the fix is not shown to have preserved them."

echo "── EC-04 END-TO-END: PASS ───────────────────────────────────────────"
echo "   mounted=$MOUNTED  fits=$FITS  assessed_controls=$ASSESSED"
grep "EC04-MARKER fits=" "$LOG" || true
