#!/usr/bin/env bash
# ENV-1 / ENV-2 · migration hygiene.
#
# Gate 0 row 0.7. Wave 0 found 20 migrations sitting untracked in the working
# tree, plus 15 historical migrations edited in place — a tree whose migration
# directory does not match its history cannot be promoted, because "replay from
# empty" and "what production actually ran" have quietly diverged.
#
#   .github/scripts/check-migration-hygiene.sh    (or: npm run check:migrations)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
DIR=supabase/migrations
fail=0

# 1. Nothing untracked or modified. In CI this is near-tautological; run locally
#    it is the check that would have caught ENV-1 before it became 20 files.
dirty="$(git status --porcelain -- "$DIR")"
if [[ -n "$dirty" ]]; then
  echo "FAIL — $DIR is not clean:"
  echo "$dirty"
  echo "Every migration must be committed. An untracked migration is a schema"
  echo "change that exists on somebody's laptop and nowhere else."
  fail=1
else
  echo "OK — $DIR is clean and fully tracked."
fi

# 2. Every migration is NNN_snake_case.sql, so ordering is total and readable.
bad="$(git ls-files "$DIR" | xargs -n1 basename | grep -vE '^[0-9]{3}_[a-z0-9_]+\.sql$' || true)"
if [[ -n "$bad" ]]; then
  echo "FAIL — migration filenames do not match NNN_name.sql:"
  echo "$bad"
  fail=1
else
  echo "OK — all migration filenames conform."
fi

# 3. No two migrations share a number. Two files claiming 118 will apply in an
#    order nobody chose, and a CREATE OR REPLACE in the loser silently wins.
dupes="$(git ls-files "$DIR" | xargs -n1 basename | sed -E 's/^([0-9]{3})_.*/\1/' | sort | uniq -d || true)"
if [[ -n "$dupes" ]]; then
  echo "FAIL — duplicate migration numbers: $dupes"
  fail=1
else
  echo "OK — migration numbers are unique ($(git ls-files "$DIR" | wc -l | tr -d ' ') migrations)."
fi


# 4. The sequence is contiguous. Gate 0.9's other half.
#
#    A hole means either a number was skipped when the migration was authored,
#    or a migration that once existed has been deleted. Both make the numbering
#    stop describing the history it claims to describe, and both are invisible
#    to the duplicate check above -- 118 twice and 119 missing are different
#    defects with the same symptom at a glance.
#
#    Contiguity of the AUTHORED set is owned here, not by the ENV-3 manifest
#    guard: that guard reconciles the declaration against the tree and assumes
#    the tree is already well-formed. One rule, one owner.
nums="$(git ls-files "$DIR" | xargs -n1 basename | sed -E 's/^([0-9]{3})_.*/\1/' | sort -u)"
if [[ -n "$nums" ]]; then
  first="$(head -1 <<<"$nums")"
  last="$(tail -1 <<<"$nums")"
  full="$(seq "$((10#$first))" "$((10#$last))" | awk '{printf "%03d\n", $1}' | sort)"
  missing="$(comm -13 <(printf '%s\n' "$nums") <(printf '%s\n' "$full") || true)"
  if [[ -n "$missing" ]]; then
    echo "FAIL — the migration sequence has gaps between $first and $last:"
    printf '  %s\n' $missing
    echo "A skipped or deleted number makes the ordering stop describing the"
    echo "history. Do not renumber an existing migration to close a gap."
    fail=1
  else
    echo "OK   — the migration sequence is contiguous ($first-$last)."
  fi
fi

exit $fail
