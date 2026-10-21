#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
MODEL="$ROOT/apps/mobile/lib/features/workout/data/models/workout_model.dart"
TEST="$ROOT/apps/mobile/test/unit/workout_domain_contract_test.dart"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT/apps/mobile"

git diff --quiet -- "$MODEL" || die "model already modified"
git diff --cached --quiet -- "$MODEL" || die "model already staged"

TMP="$(mktemp)"
cleanup() {
  if [[ -f "$TMP" ]]; then
    cp "$TMP" "$MODEL" 2>/dev/null || true
    rm -f "$TMP"
  fi
}
trap cleanup EXIT

cp "$MODEL" "$TMP"

echo "baseline: WKT-204 must pass"
flutter test "$TEST" --plain-name "WKT-204"

python3 - "$MODEL" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()

old = """sets: [for (final s in sets) s.asStructureForNewMovement()],"""
new = """sets: sets,"""

if old not in text:
    raise SystemExit("mutation anchor not found")

p.write_text(text.replace(old, new, 1))
PY

echo
echo "mutated: WKT-204 must fail"

set +e
OUTPUT="$(flutter test "$TEST" --plain-name "WKT-204" 2>&1)"
RC=$?
set -e

printf '%s\n' "$OUTPUT"

[[ "$RC" -ne 0 ]] || die "WKT-204 unexpectedly passed after mutation"

# Flutter's failure summary differs between local and CI runners.
# The exit code is the authoritative failure signal; the four named
# assertions below prove the mutation broke the intended contract.

for assertion in \
  "the replacement carries new identities throughout" \
  "the prescribed structure carries over; the load does not" \
  "completed state does NOT follow the swap" \
  "a cursor pointing into the replaced exercise no longer resolves"; do
  if ! printf '%s\n' "$OUTPUT" | grep -Fq "$assertion"; then
    die "expected WKT-204 failure not observed: $assertion"
  fi
done

echo
echo "restore: committed implementation"
cp "$TMP" "$MODEL"

git diff --quiet -- "$MODEL" || die "model was not restored exactly"

echo
echo "restored: WKT-204 must pass"
flutter test "$TEST" --plain-name "WKT-204"

echo
echo "RESULT: PASS"
echo "Evidence class: SYNTHETIC PRE-FIX-EQUIVALENT DART CI EVIDENCE"
