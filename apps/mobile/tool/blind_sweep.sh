#!/bin/bash
#
# Blind every ratchet's detector and check that it FAILS.
#
# A guard that still passes with its patterns unable to match anything has no
# floor: it would certify a codebase it can no longer read. Three guards in
# this programme were found blind AFTER being declared at baseline — H-D1
# (matched a declaration form nothing in the codebase used), A-G8 (recorded
# overstatement) and BACK-G1 (a `\b` that could not match one of four
# spellings, hiding 11 of 41 controls).
#
# Run from apps/mobile:   bash tool/blind_sweep.sh
#
# NOTE ON WHAT THIS DOES NOT CATCH. This only tests TOTAL blindness. All three
# failures above were PARTIAL — the detector matched most of the codebase and
# missed a slice, so a floor asserting "found something" passes. Partial
# blindness is caught only by a floor the detector does not compute: see the
# cross-check in back_control_guard_test.dart, which counts the same glyph by
# plain substring splitting and requires the two counts to agree.
set -u
GUARDS=$(grep -rln "A-G8\|A-G9\|EC-G7\|EC-G8\|SEC-G1\|SEC-G2\|SEC-G3\|SEC-G4\|H-D1\|H-D2\|NAV-G1\|ROUTE-G1\|DEAD-G1\|TAP-G1\|BACK-G1" test/unit)
fails=0
for g in $GUARDS; do
  cp "$g" /tmp/blind.bak
  python3 - "$g" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"RegExp\(\s*r('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")",
         "RegExp(r'ZZZ_NEVER_MATCHES_ZZZ'", s)
open(p,'w').write(s)
PY
  out=$(flutter test "$g" 2>&1); rc=$?
  cp /tmp/blind.bak "$g"
  if echo "$out" | grep -qE "Compilation failed|Failed to load|Dart compiler exited"; then
    echo "  INVALID  $g  (blinding broke compilation — check by hand)"
  elif [ $rc -ne 0 ]; then
    echo "  ok       $g"
  else
    echo "  NO FLOOR $g  <-- passes with its detector blinded"; fails=$((fails+1))
  fi
done
echo
[ $fails -eq 0 ] && echo "all guards fail when blinded" || echo "$fails guard(s) have no floor"
exit $fails
