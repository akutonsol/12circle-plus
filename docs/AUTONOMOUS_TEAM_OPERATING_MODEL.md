# 12Circle+ V5 Autonomous Team Operating Model

**Status:** implementation proposal on `feat/v5-autonomous-team`; not a production authorization and not a claim that agents are already running continuously.

## Mission

Operate V5 as a persistent, dependency-aware engineering team. Workers continue to the next eligible task after each completed task; they stop only for a genuine blocker, a safety/governance boundary, exhausted bounded recovery, or an explicit release gate. V5 product authority and the existing remediation waves, release gates, QA closure standard, CI guards, and owner decisions remain authoritative.

## Six operating requirements

1. **Persistent queue.** Every task has a stable ID, owner/worker role, dependencies, file and environment boundaries, acceptance checks, retry budget, evidence requirements, and a state. Queue state and worker leases must survive process restart. Claiming is atomic; duplicate claims are rejected.
2. **Dependency-aware coordinator.** Dispatch only tasks whose dependencies are verified complete. A blocked task does not pause unrelated eligible work. After completion, failure, or lease expiry, recompute the queue and claim the next eligible task automatically.
3. **Independent verification.** A worker cannot self-certify its own completion. An independent verifier checks the diff, sibling failure modes, negative controls, fixture reachability, cleanup, relevant static guards, and CI evidence. Completion means the named acceptance evidence exists—not merely that a local command was green.
4. **Blocker classification.** Classify issues as (a) ordinary engineering failure, (b) bounded retry/recovery, (c) external dependency, (d) owner decision, (e) governance/security prohibition, or (f) release-gate failure. Continue independent work for classes (c)–(f). Never guess an owner decision or bypass a prohibition.
5. **Durable handoff and recovery.** Persist claims, attempts, logs/artifact references, last known good state, failure classification, and next action. Expired leases become recoverable; retries are bounded; repeated failures become an actionable blocker instead of an infinite loop.
6. **Governed execution.** Least privilege, narrow file ownership, no overlapping migration numbers, no conflicting contract changes, no protected-register mutation without authorization, no production contact before separate Gate 9B authorization, no force-push, and no bypass of CI or QA verification. Before every QA write, independently confirm the linked project is QA.

## Task lifecycle

`READY -> CLAIMED -> IMPLEMENTED -> VERIFYING -> VERIFIED`

Exceptional states: `BLOCKED_OWNER`, `BLOCKED_EXTERNAL`, `BLOCKED_GOVERNANCE`, `RETRY_WAIT`, `FAILED_TERMINAL`. A worker may not move a task directly to `VERIFIED`. Only the independent verifier may do so with evidence references. `CLAIMED` and `VERIFYING` use leases. An expired lease is recoverable and does not imply success or failure.

## Worker roles and boundaries

- **Coordinator:** selects eligible tasks, enforces dependency and file/migration ownership, recovers expired leases, and dispatches work. It does not edit product code or approve its own tasks.
- **Implementer:** owns only the assigned paths and acceptance criteria. It may run local checks and repair ordinary failures within its retry budget. It may not change the task's scope, acceptance criteria, security boundary, or owner decisions.
- **Verifier:** independently reviews the diff and runs/checks acceptance evidence. Must search for sibling defects, validate test controls can reach the intended branch, check teardown, and reject saturated/unbounded counts where they can make assertions vacuous.
- **Integrator:** resolves conflicts on an integration branch, ensures CI evidence is attached, and keeps changes separate when dependencies or authority differ.
- **Governance/owner escalation:** requests one precise decision with options, exact proposed diff, impact, and blocked task IDs. Other eligible tasks continue.

## Hard stops

Stop the affected task and escalate when it requires: new authorization or policy, unresolved product semantics, modifying protected registers without permission, production access, weakening a guard, missing/ambiguous data authority, or a release-gate bypass. Do not stop unrelated work. Never interpret an absent secret or a green skipped job as successful live verification.

## V5-specific invariants

- `docs/MASTER_REMEDIATION_WAVES.md`, `docs/RELEASE_GATES.md`, and `docs/QA_CLOSURE_STANDARD.md` remain governing sources.
- QA project ref: `eyqtldjqpgpljlqvpowh`. Production project ref: `nxdbooufqzkpslkcogxc`. Production is prohibited until separately authorized at Gate 9B.
- Do not reconcile EC-02, weaken security guards, force-push, change visibility/billing/branch protection, or mutate protected registers without authorization.
- Preserve violet as canonical; do not use lime. Preserve the Q5 Phosphor pin unless reviewed evidence justifies a change. Do not widen role assignment authorization.
- Do not bypass PD-G01 or implement gated P3/P4, P7, or Wave 2 task 2B without authorization.
- Keep ENV-3 / FG table header governed by the actual register status and evidence. Preserve P5/P6 done, Q15 withdrawn, and Elevated mismatch unresolved as directed.
- Checkout: do not create a new checkout session after the client navigates away from the upgrade flow; inspect in-flight handling first.
- The FG-3 §2.1 closure-standard amendment, FG headers, D2-3/D2-4 decisions, SEC-09 authority, and Helix billing are distinct blockers. Do not silently resolve them.

## Independent verification checklist

Before a task can be marked verified:
- Confirm task ID, claimed paths, base SHA, and resulting diff.
- Check sibling call sites and related assertions, not only the reported line.
- Ensure positive and negative controls are valid and the intended branch is reachable.
- Ensure database counts are scoped and fail closed when the result is saturated at an API/page cap.
- Verify fixture cleanup by reading state after teardown.
- Run relevant local checks, then rely on actual CI checks and reviewed artifacts for gate status.
- Distinguish `FIXED IN CODE`, `VERIFIED IN CI`, `FIXED ON QA`, and `VERIFIED LIVE`; never promote one state by implication.

## Rollout sequence

1. Land and test the queue/coordinator contract on an isolated branch.
2. Connect the coordinator to the existing Skills-Agent/Claude Code runner; do not invent a provider or credential. The adapter must pass a bounded task envelope and return structured status/evidence.
3. Seed the queue from the current V5 registry/waves only after reconciling current task IDs and dependencies against the live branch. Never copy stale counts from snapshots.
4. Run in dry-run mode and prove atomic claims, dependency blocking, independent-task progress, expired-lease recovery, retry limits, and governance stops.
5. Enable bounded execution for non-gated tasks. Preserve human approval for owner decisions and explicit release gates.

**Current limitation:** this repository change can establish the operating contract and scheduler mechanics, but it cannot itself keep a Claude Code process alive or launch provider agents unless the actual runner/credentials and a durable execution host are connected. That integration must be demonstrated by a real run before claiming continuous autonomous operation.

---

## `V5-AUTO-001` — runner inspection finding (2026-10-12, commit `3216bfe`)

**Conclusion: there is no Skills-Agent runner in this repository or in the operator's Claude
configuration. Step 4 of Milestone 1 is externally blocked, and no adapter was written.**

### What was inspected, and what was found

| location | result |
|---|---|
| `.claude/settings.json` | a **permissions allowlist only** — `permissions.allow` entries and `additionalDirectories`. No hook, agent, runner or provider configuration of any kind |
| `.claude/` | contains exactly `settings.json` and `settings.local.json`. **No `hooks/`, `agents/`, or `skills/`** |
| `.github/workflows/` | **no** workflow references an agent launch, `claude` invocation, or `SKILLS_AGENT_*` variable |
| `scripts/` | the coordinator is the only Skills-Agent script; nothing else launches anything |
| `package.json` | no script entrypoint for the agent or coordinator |
| `~/.claude/skills` | `frontend-design` and `synced` — ordinary operator skills, **not** a task runner |
| `~/.claude/plugins` | marketplace and cache data only |

The coordinator states the same thing in its own header: *"This process schedules bounded tasks;
**it does not launch Claude Code by itself.** A runner adapter must consume `claim` output and
submit structured completion or blocker events."* So the absence is by design, not an oversight.

### Execution host and persistence boundary

* **Coordinator state persists.** `.skills-agent/state.json` is written atomically (temp file +
  `rename`) under an exclusive `wx` lock. Every command is a separate OS process, so the test suite's
  restart scenario is a genuine process boundary, not a simulated one. State survives worker exit
  **and** coordinator exit.
* **Execution does not persist, because there is no execution.** Nothing keeps a worker alive
  between commands. The coordinator is a scheduler reading and writing a file; the "workers" are
  whatever invokes it.

### The exact external blocker

To connect a real runner, three things are needed and **none is present**:

1. **A runner entrypoint** — a documented command or API that starts a bounded agent with a task
   envelope and returns structured completion.
2. **Credentials** for that runner, which must not be invented or guessed.
3. **A durable execution host** that outlives a single worker, since this machine's shell does not.

Until those exist, `V5-AUTO-002` (the adapter) cannot begin. That is recorded on the queue as
`BLOCKED_EXTERNAL` rather than attempted.

### One honest limit on the independence guarantee

The coordinator now refuses to record the same identity as both implementer and verifier, and
refuses the `pid:` fallback for verification. **That is enforcement of what is recorded, not proof
of who acted.** Identity is still self-asserted through `SKILLS_AGENT_ID`; a single operator
running both roles under two names will satisfy the check. Genuine independence requires the
runner to inject identity the worker cannot set — which is part of what the missing integration
must supply, and is stated here rather than implied away.
