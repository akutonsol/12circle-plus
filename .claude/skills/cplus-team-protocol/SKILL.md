---
name: cplus-team-protocol
description: How the 12circle-plus specialist team splits, assigns, isolates, integrates and reports work. Use when leading or delegating any multi-part 12circle-plus task, when integrating branches from several specialists, or when a delegated task returns. Not for the separate "12Circle" community-platform product (its 12circle-* skills do not apply here).
---

# 12circle-plus team protocol

12circle-plus is a **Flutter (Riverpod) + Supabase coaching app** (`apps/mobile`, `supabase/`).
The source of truth for scope and state is the repo, not memory or old reports:
`docs/BETA_COMPLETION_LEDGER.md`, `docs/CONTROLLED_BETA_SCOPE.md`,
`docs/BETA_RELEASE_RUNBOOK.md`, `docs/WEEK1_ACCEPTANCE_WALKTHROUGH.md`,
`docs/MASTER_PRODUCT_DECISIONS.md`, `docs/decision-log.md`, `docs/RELEASE_GATES.md`.
(Until PR #164 merges, the ledger, scope, runbook and walkthrough live on branch
`docs/beta-completion-ledger`: `git show origin/docs/beta-completion-ledger:docs/<file>`.)
The `12circle-*` skills (01–14, source-of-truth, design-to-code …) describe a **different product**
(a community platform) and must not be applied here.

## Roles

| Agent (`.claude/agents/`) | Edits | Owns |
|---|---|---|
| main session = **technical lead** | integration only | breakdown, assignment, contracts, merge-readiness, reporting |
| `cplus-flutter-engineer` | `apps/mobile/**` | screens, navigation, providers, services, widget/unit tests |
| `cplus-supabase-engineer` | `supabase/**` (migrations via the protected-path procedure), `scripts/protected-paths.json` exceptions | schema, RLS, RPCs, Edge Functions, replay tests |
| `cplus-security-reviewer` | none (reviews; may add replay/test files on request) | authorization, privacy, data-access review |
| `cplus-qa-verifier` | tests only, never the code under test | independent verification, negative tests, evidence |
| `cplus-ux-reviewer` | none | loading/empty/error states, accessibility, consistency |

Integration / release work (merge-tree simulation, full-suite + guard runs, runbook upkeep) stays
with the lead: it needs the whole picture and never touches product code.

## Breaking work down

1. Start from **verified** `origin/main` (never the primary checkout — it sits on a stale branch).
2. One **package** = one branch = one PR = one owner. A package names: goal, acceptance criteria,
   the exact files/dirs it may change, the API/DB contract it depends on, and the tests that prove it.
3. When Flutter and backend both change, write the **contract first** (table/column/RPC signature,
   error codes, RLS expectation) in the package; the backend package lands or is replay-proven
   before the Flutter package relies on it.
4. Anything needing a migration *applied*, a deploy, a QA write, or a product decision is
   **blocked**, not guessed — record it and move to independent work.

## Isolation and conflicting edits

- Launch implementers with `isolation: "worktree"` (or a dedicated worktree under
  `.claude/worktrees/`). Never two writers on the same files.
- Every migration PR edits `supabase/expected_applied.json`; only **one** open migration
  package at a time, or stack them (each PR names its predecessor).
- One CI run at a time against QA (the live suites share fixtures). The pre-push hook refuses a
  push while CI runs on that branch.

## What every delegated task must return

```
WORK PERFORMED   one paragraph
FILES INSPECTED  paths
FILES CHANGED    paths (created / modified)
BRANCH / COMMIT  name + SHA (or "none")
TESTS            exact commands and their actual results (counts), incl. the failing baseline on main
REMAINING        open issues, blockers (class: engineering / decision / migration / external / manual QA)
HANDOFFS         who needs what next
```

A task assignment is not evidence. A green local command is not CI. The lead verifies the diff
and re-runs or reads the evidence before reporting anything as done.

## Hard boundaries (all agents)

No merges, no auto-merge, no migration applied to QA or production, no deploys, no QA writes
beyond CI's existing fixtures, no production access, no secrets printed, no force-push, never touch
PR #14, never edit Women's Health / fertility / cycle areas, never make Julia's product decisions.
Protected paths (`scripts/protected-paths.json`) are edited only by opening an exact-path
exception and closing it in the same PR.
