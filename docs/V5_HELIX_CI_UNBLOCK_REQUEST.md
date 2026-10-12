# V5 · OWNER ACTION REQUEST — unblock hosted CI on `helix-design-system`

**Status: infrastructure blocked. Not a workflow defect, and not something I can fix.**

## The blocker, exactly

Every workflow run on `akutonsol/helix-design-system` fails **before any step executes**. The
jobs API reports `steps: []`, and the reason is only visible as a check-run annotation:

> *"The job was not started because recent account payments have failed or your spending limit
> needs to be increased. Please check the 'Billing & plans' section in your settings"*

Observed on every run of both PRs, including `1887e76`, `c5b60d6` and `57d10c8`.

**Why it affects this repository and not the product repository:**

| repo | visibility | Actions minutes | result |
|---|---|---|---|
| `akutonsol/12circlefitness` | **public** | free | CI runs; green at `2af72f1` |
| `akutonsol/helix-design-system` | **private** | **paid** | blocked before step 1 |

**How to tell this apart from a failing workflow**, because they look identical in the PR UI: a
real failure has step conclusions; this has **none**. `gh run view --log` returns *"log not
found"*. The annotation is reachable only via
`gh api repos/<owner>/<repo>/check-runs/<job_id>/annotations`.

## Is billing the ONLY failure? — investigated, and yes

The question worth answering before asking you to pay for anything: is a workflow defect hiding
behind the billing refusal, so that fixing billing just reveals a second problem?

**No, and the evidence is in what GitHub did before it declined.**

| observation | what it rules out |
|---|---|
| a job exists, named **"Theme contract (12circle)"** — that string comes from the workflow's own `name:` | the YAML parsed and the job definition resolved |
| `steps: 0` | the job was created and then **never allocated a runner** — it did not start and fail, it never started |
| `event=pull_request` on the run | the trigger matched; `on:` is correct |
| the only `failure` annotation is the billing message | **no `Invalid workflow file`** — a malformed workflow produces that instead, and produces no job at all |
| every step's content already ran green in a clean clone on Node 20 | the steps themselves are not the problem |

So the sequence is: parsed → trigger matched → job resolved → **runner refused**. The workflow is
sound; only the allocation is blocked. Fixing billing should produce a real run, not a new error.

The committed configuration is also minimal and was re-read for this check:

```yaml
on:
  push:
    branches: [main]      # main only — a branch is built once, via its PR
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read          # read-only; no token escalation
```

## The minimum owner action

**Resolve the Actions billing** — either update the failed payment method or raise the Actions
spending limit.

**Exact location.** `akutonsol` is a **User** account, not an organisation (`gh api users/akutonsol`
→ `"type": "User"`), and it owns this repository directly. So this is **personal account billing**,
not repository or organisation settings:

> **<https://github.com/settings/billing>** → *Plans and usage* / *Payment information* → clear the
> failed payment, and check the **Actions** spending limit is above zero.

*(Repository → Settings has no billing page; looking there is the usual wrong turn.)*

**I did not read your billing to confirm which of the two it is.** The API returns `404` without the
`user` OAuth scope, and `gh` offers to request it — **expanding my token's scope to read your
account billing is not something I will do unauthorized.** The annotation names both causes
("payments have failed **or** your spending limit needs to be increased"), and that page shows
which. That is the whole fix. It requires **no change to this
repository**, no change to the workflow, and no disclosure decision.

Nothing else is needed: the workflow is already correct and already verified to work (below), and
it is deliberately cheap — one job, one Node version, no matrix, no secrets, `concurrency` with
`cancel-in-progress`, and `push` limited to `main` so a branch is built once via its PR rather
than twice.

## Two alternatives, neither recommended, and one needing separate authorization

| option | what it costs you |
|---|---|
| **Make the repository public** | eliminates the billing dependency entirely, since public repos get free minutes. **This is a disclosure decision, not a billing one — it is NOT equivalent to the fix above, and I am not treating it as the default.** It would need explicit authorization, and I have not changed visibility or proposed it as the minimum. |
| **Add a self-hosted runner** | no paid minutes, but it introduces infrastructure to maintain and a runner with repository access. Disproportionate for a 15-second type-check-and-build job. |

**I have not changed visibility, billing, or payment configuration, and will not.**

## What stands in for hosted CI until then

Per the `LOCALLY_VERIFIED` instruction: a **fresh clone** of the pushed SHA on **Node 20**, running
the workflow's exact step sequence — `npm ci` → `npm run typecheck` → `npm run build` →
`npm run check:12circle` → `scripts/selftest-12circle-guard.sh`. All steps pass.

| branch | SHA | result |
|---|---|---|
| `fix/12circle-violet-theme` (PR #1) | `c5b60d6` | all steps pass · check **67/67** on this branch |
| `feat/phosphor-icons` (PR #2) | `57d10c8` | all steps pass · check **88/88** |

Re-verified in place at the current working tree: build exit 0, **88/88**, generated
`dist/themes/12circle.css` contains the violet and **zero** lime occurrences, the four-theme
registry intact, `12circle` distinct from `12circle-communities`, Phosphor pinned exactly at
`2.1.10` with `CalendarDots` and all eight `fill`-weight glyphs resolving.

**This is local evidence. It is not hosted CI, and it is not described as green.**

## On merging, since the question will come up

`main` carries **no branch protection** — `gh api …/branches/main/protection` returns
`404 Branch not protected`. So there are no required status checks, and the failing check does
**not** technically block a merge; both PRs report `MERGEABLE` with `mergeStateStatus UNSTABLE`,
where the single `FAILURE` is the never-started job.

**That makes merging possible, not advisable, and it is not mine to do.** Merging would land
changes whose only hosted evidence is a job that never ran. I have not merged either PR and will
not without a separate instruction.

## Requested

1. **Resolve Actions billing** — the minimum action, no repository change.
2. *Or* explicitly authorize a **visibility change**, understanding it is a disclosure decision.
3. Separately, say whether either PR should be **merged** on local evidence alone, or held until
   hosted CI can run.
