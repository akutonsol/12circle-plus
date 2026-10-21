#!/usr/bin/env bash
#
# Verifies that a compiled Flutter web bundle carries no server secret.
#
# The AI integration lives behind the NestJS API, so the Anthropic key must
# never reach a client artifact. This scans everything `flutter build web`
# emitted — the compiled JS, the service worker, and any asset — for credential
# material.
#
# Usage:
#   flutter build web --dart-define-from-file=dart_defines/qa.json
#   tool/check_web_build_secrets.sh [build-dir]     # default: build/web
#
# Exit status: 0 clean, 1 a secret was found, 2 nothing to scan.

set -uo pipefail

BUILD_DIR="${1:-build/web}"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "✗ No build to scan at '$BUILD_DIR'. Run 'flutter build web' first." >&2
  exit 2
fi

# Credential material that must never appear in a client bundle, as extended
# regexes. Patterns are anchored on a word boundary and require a realistic key
# tail so unrelated symbols in Flutter's own canvaskit bundle (for example
# `ps_mask_test_bit`, which contains "sk_test_") are not reported as leaks.
#
# The *name* ANTHROPIC_API_KEY is deliberately not listed: admin screens
# reference it as the name of a Supabase Edge Function secret, which is not
# itself a secret. A key, the Anthropic host, or the key header would be.
PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{8,}|Anthropic API key'
  'api\.anthropic\.com|direct call to the Anthropic API'
  '(^|[^A-Za-z0-9_-])x-api-key([^A-Za-z0-9_-]|$)|Anthropic credential header'
  'anthropic-version|Anthropic API version header'
  '(^|[^A-Za-z0-9_])(sk|rk)_(live|test)_[A-Za-z0-9]{16,}|Stripe secret or restricted key'
  '(^|[^A-Za-z0-9_])service_role([^A-Za-z0-9_]|$)|Supabase service-role key'
)

found=0
for entry in "${PATTERNS[@]}"; do
  regex="${entry%|*}"
  description="${entry##*|}"
  if matches=$(grep -rlE -- "$regex" "$BUILD_DIR" 2>/dev/null); then
    echo "✗ Found $description in the web build:" >&2
    echo "$matches" | sed 's/^/    /' >&2
    grep -rhoE -- "$regex" "$BUILD_DIR" 2>/dev/null | sort -u | head -5 |
      sed 's/^/      match: /' >&2
    found=1
  fi
done

if [[ $found -ne 0 ]]; then
  echo "" >&2
  echo "A server secret leaked into the client bundle. Move it behind the API." >&2
  exit 1
fi

file_count=$(find "$BUILD_DIR" -type f | wc -l | tr -d ' ')
echo "✓ No server secrets in '$BUILD_DIR' ($file_count files scanned)."
