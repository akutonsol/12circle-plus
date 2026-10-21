#!/usr/bin/env bash
# REL-36 / LRE-35 · the only sanctioned way to rebuild the QA database.
#
# `supabase db reset --linked` drops and rebuilds whatever project the CLI is
# currently linked to, then applies supabase/seeds/*.sql — which create accounts
# with published passwords. The CLI asks for no confirmation of the target, and
# the link lives in supabase/.temp/project-ref, a file that changes whenever
# anyone runs `supabase link` and (as of LRE-34) is no longer even tracked.
#
# So the target is verified here, out loud, before anything runs.
#
# This is the outer of two independent controls. The inner one is in the seed
# files themselves, which refuse a database that is not freshly reset. This
# script can be bypassed by typing the CLI command directly; that one cannot.
#
#   supabase/scripts/qa-db-reset.sh              # verify, prompt, reset
#   supabase/scripts/qa-db-reset.sh --check-only # verify the link and stop
set -euo pipefail

QA_REF='eyqtldjqpgpljlqvpowh'
QA_NAME='12Circle QA'

cd "$(git rev-parse --show-toplevel)"
REF_FILE='supabase/.temp/project-ref'
LINK_FILE='supabase/.temp/linked-project.json'

die() { echo; echo "  REFUSING — $1"; echo; exit 2; }

[[ -f "$REF_FILE" ]] || die "no linked project ($REF_FILE is absent).
  Link the QA project first:  supabase link --project-ref $QA_REF"

linked="$(tr -d '[:space:]' < "$REF_FILE")"

# Refusal is by allowlist: anything that is not the QA ref — production
# included — is refused identically. Naming the production ref here would add
# nothing but a copy of it (see the ENV-5 production-ref guard).
if [[ "$linked" != "$QA_REF" ]]; then
  die "the CLI is linked to project '$linked', which is NOT the QA project.
  This script will not reset, seed, or otherwise touch that project.
  A target is QA because its ref says so — never because a script, a file or a
  variable is named 'qa'.
  Expected: $QA_REF ($QA_NAME) · re-link:  supabase link --project-ref $QA_REF"
fi

# Cross-check the ref against the CLI's own record of what it linked, so a
# hand-edited project-ref file does not decide this on its own.
if [[ -f "$LINK_FILE" ]]; then
  if ! grep -qF "\"$QA_REF\"" "$LINK_FILE"; then
    die "$REF_FILE says $QA_REF but $LINK_FILE disagrees.
  Re-link deliberately:  supabase link --project-ref $QA_REF"
  fi
fi

echo "  Target verified: $linked ($QA_NAME)"
echo "  Config project_id: $(grep -E '^project_id' supabase/config.toml | head -1)"

if ! grep -qE "^project_id *= *\"$QA_REF\"" supabase/config.toml; then
  die "supabase/config.toml's project_id is not the QA project.
  The link and the committed config must agree before a reset."
fi

if [[ "${1:-}" == "--check-only" ]]; then
  echo "  --check-only: link verified, nothing was reset."
  exit 0
fi

cat <<WARN

  This DROPS AND REBUILDS the $QA_NAME database:
    - every table is recreated from supabase/migrations (123 files)
    - supabase/seeds/*.sql then create accounts with PUBLISHED passwords
    - all existing QA data is destroyed

WARN
read -r -p "  Type the project ref to confirm: " confirm
[[ "$confirm" == "$QA_REF" ]] || die "confirmation did not match. Nothing was done."

echo
echo "  Resetting $linked ..."
supabase db reset --linked
echo "  Done."
