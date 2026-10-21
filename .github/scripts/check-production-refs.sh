#!/usr/bin/env bash
# ENV-5 · production-ref guard.
#
# Fails if the production Supabase project is named anywhere it has no business
# being named. The three `tool/` harnesses each used to open with
# `const _url = 'https://<production ref>.supabase.co'`, and every one of them
# writes; the repository's own "QA certification harness" seeded subscription
# rows into production. Nothing structural stopped that, so this is the
# structural thing.
#
# The allowlist below is a SHRINKING one. Every entry carries the reason it is
# allowed. Do not add an entry to silence a failure — repoint the file.
#
#   .github/scripts/check-production-refs.sh      (or: npm run check:prod-refs)
set -euo pipefail

PROD_REF='nxdbooufqzkpslkcogxc'
cd "$(git rev-parse --show-toplevel)"

# path                                        | why it may name production
ALLOW=(
  '.github/workflows/supabase-keepalive.yml'  # the one sanctioned production contact: a daily read-only GET that stops free-tier auto-pause
  '.github/scripts/check-production-refs.sh'  # this guard; it holds the ref in order to look for it
  'apps/mobile/dart_defines/prod.json'        # ENV-4: where the production build configuration lives now, reachable only via --dart-define-from-file
  'apps/mobile/tool/qa_target.dart'           # ENV-5: refusal constant. Names production so the harnesses can reject it
  'supabase/tests/security/lib.mjs'           # refusal constant, same job, for the Node security suite
  'supabase/tests/ai/lib.mjs'                 # refusal constant, same job, for the Node AI suite
  'supabase/APPLY_MISSING.sql'                # a dated comment recording which DB was audited; not a target
  'supabase/STRIPE_SETUP.md'                  # NEW FINDING (Wave 1): this runbook instructs `supabase link --project-ref <production>`. Allowlisted so CI is honest rather than red, NOT because it is correct. See the Wave 1 report.
)

is_allowed() {
  local f="$1"
  for a in "${ALLOW[@]}"; do [[ "$f" == "$a" ]] && return 0; done
  # The programme's own findings quote the ref constantly; they are the record.
  [[ "$f" == docs/* ]] && return 0
  # Tests that assert ABOUT the boundary must be able to name both sides.
  [[ "$f" == apps/mobile/test/* ]] && return 0
  return 1
}

violations=()
while IFS= read -r f; do
  is_allowed "$f" || violations+=("$f")
done < <(git grep -l --fixed-strings --untracked "$PROD_REF" -- . | sort)
# --untracked: without it, git grep scans TRACKED files only, so a new file
# carrying the ref passes this guard locally right up until the commit that
# makes CI red (this happened: ci.yml and qa-db-reset.sh, 2026-08-25, W1B-N6).
# Ignored files stay ignored; CI checkouts are unaffected.

if ((${#violations[@]})); then
  echo "FAIL — the production project ($PROD_REF) is named outside the allowlist:"
  printf '  %s\n' "${violations[@]}"
  echo
  echo "These files can reach production. Point them at QA (see"
  echo "apps/mobile/tool/qa_target.dart), or take the target from the"
  echo "environment with no default. Adding an allowlist entry is not a fix."
  exit 1
fi

echo "OK — no unallowlisted reference to the production project."

# Second, narrower assertion: no allowlisted refusal constant may drift into a
# usable production URL. Holding the bare ref to reject it is the point; holding
# 'https://<ref>.supabase.co' is a target.
for f in 'apps/mobile/tool/qa_target.dart' 'supabase/tests/security/lib.mjs' 'supabase/tests/ai/lib.mjs'; do
  if grep -q "https://$PROD_REF" "$f" 2>/dev/null; then
    echo "FAIL — $f holds a usable production URL, not just the ref it refuses."
    exit 1
  fi
done
echo "OK — every refusal constant is still only a refusal."
