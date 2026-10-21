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

## The decision gate (added 2026-10-20)

`blockers` was free text. A task could declare `{kind:'owner', what:'an undecided
product contract'}` and `eligible()` would veto it — correctly — but nothing
linked that prose to a decision, and nothing cleared it when the decision was
answered. 16 of 19 tasks carried one, so that was 16 chances to forget in either
direction: a stale gate stalls real work, and a gate taken down early implements
a decision nobody made.

A blocker may now carry a decision id:

```json
{ "kind": "owner", "decision": "OD-QAX-2",
  "what": "may a coach assign to a pending client",
  "evidence": "docs/QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:179",
  "action": "owner answers OD-QAX-2 and it reaches implementation_authorized" }
```

`.skills-agent/decisions.json` holds the state. **It is not a governance
register** — `MASTER_PRODUCT_DECISIONS.md`, `decision-log.md` and `docs/adr/` are
authoritative; this mirrors them so the scheduler can refuse work instead of
relying on memory. Seven states, each a separate act:

`proposed` → `conflict_checked` → `accepted` → `recorded` →
**`implementation_authorized`** → `implementation_verified` → `promoted`

**Only `implementation_authorized` releases a gated task.** `accepted` and
`recorded` do not: accepting an answer and writing it down are not the same act
as authorizing the code change. Verified by `--self-test`, 9 cases.

**Fail-closed.** A decision id absent from the ledger, an entry with no `state`,
a non-string `state`, and a case-mismatched id all KEEP the veto. A typo must
never be the thing that authorizes a policy change. A blocker with no `decision`
field behaves exactly as before, so existing tasks are unaffected.

Entry points: `npm run flow` (status), `npm run flow:validate`,
`npm run flow:selftest`.

## The protected-path guard (added 2026-10-21)

`scripts/guard-protected-paths.mjs` is a `PreToolUse` hook, wired in
`.claude/settings.json` with a `*` matcher so the script — not the matcher —
decides. It refuses tool writes to the repository's authority files: the
migration set, the applied-state manifest, the governance decision records and
log, the remediation registry, wave authorization, the closure standard, the
release gates, the progress board, and `docs/adr/`.

**What it covers.** `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, and any other
tool whose input carries its destination as a **string** — at any depth, inside
arrays or objects, under any key name. An unrecognised tool is not assumed safe:
its input is scanned the same way. Reads stay allowed, and a multi-file operation
is denied if **any** target is protected.

The rule is deliberately inverted. An earlier version kept an allow-list of
path-shaped key names, and an independent review reproduced six payloads that
named a protected file and were **allowed** — arrays under a known key, the
plural `file_paths`, and key names nobody had enumerated (`outfile`, `to`). A key
allow-list can only enumerate the shapes someone thought of. Now **every** string
is a candidate destination except those under a known content-bearing key
(`content`, `new_string`, `old_string`, `command`, …) or implausible as one path
(empty, multi-line, over 4096 characters), and the **decision is made by
resolution**: a candidate denies only if it resolves inside a protected root. So
a note whose body quotes `supabase/migrations/131_x.sql` is still writable.

**This is not comprehensive interception of every possible future tool or payload
schema**, and it should not be described as such. A tool that carried its
destination under a content key, encoded it, or derived it at run time would not
be seen. The claim is narrower and checkable: a destination appearing as a plain
string in the payload is checked.

**What it does NOT cover, and this is not a detail.**

* **`Bash` is outside the boundary.** A shell command can write any file;
  classifying arbitrary shell is not attempted. `printf x >
  supabase/migrations/999.sql` is **not** stopped. The guard allows `Bash`
  explicitly rather than pretending otherwise.
* Any other process, an editor, or git itself.
**Verified intercepting, 2026-10-21.** Both tools were observed denied by the
hook itself, distinguishable from a tool-level rejection by Claude Code's own
prefix:

```
PreToolUse:Write hook error: [node ".../guard-protected-paths.mjs"]: BLOCKED ...
PreToolUse:Edit  hook error: [node ".../guard-protected-paths.mjs"]: BLOCKED ...
```

Targets were a temporary fixture added to `protected` for the test and removed
after; no real protected file was written to, and all eleven protected roots
hashed identical before and after.

**A correction.** An earlier note here claimed the hook "loads at session start,
so wiring it does not protect the session that wired it." **That was wrong** — it
became active without a restart. The earlier inconclusive probe had used an
`Edit` with an anchor that does not exist, and Claude Code validates that anchor
*before* invoking the hook, so the call was rejected as `String to replace not
found` and the hook never ran. **An impossible-anchor Edit cannot test the hook.**
Use a `Write`, or an `Edit` with a valid anchor against a disposable fixture.

So this reduces the chance of an *accidental* authority-file edit through the
normal tool path. It is **not** an operating-system or sandbox boundary, and
nothing here makes such an edit impossible.

**Why the exception list is a tracked file.** The queue's `paths` field and
`.skills-agent/decisions.json` are **not** accepted as authorization: the same
agent writes both, so trusting them is circular. The only exception mechanism is
`scripts/protected-paths.json`, which is git-tracked — lifting a protection is a
reviewable diff, not a runtime assertion. The guard fails closed if that config
is missing or malformed.

## Authorization provenance — what the ledger can and cannot prove

An `implementation_authorized` entry must also declare `owner`, `answeredAt` and
a `record` naming a **non-empty regular file**; otherwise the gate stays shut. A
directory and an empty file are both rejected — `existsSync` alone accepted them,
which a review caught. That
raises the bar from editing one word to asserting four things, one of them a real
file.

It is **not** proof of provenance, and the gap is structural: there is no
machine-checkable link from an `OD-*` id to an authoritative record here.
Verified, not assumed — `MASTER_PRODUCT_DECISIONS.md` carries 7 `ANSWERED`
markers and **no row** for `OD-QAX-2` or `OD-14`; `decision-log.md` embeds ids in
prose; `docs/adr/ADR-W1-001` has a machine-readable Status line and mentions no
`OD-*` id at all. Matching prose would manufacture confidence, so no such check
exists. **A reviewer must still read the named record.** This is CR-1.

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

---

## Milestone 2 — infrastructure facts (2026-10-12, commit `d421fcd`)

**Headline: capability A does not exist in this environment, so no runner was built.** Capability
C does exist, which means the blocker is *agent invocation*, not hosting. Everything buildable
without A was built.

| # | capability | state | evidence |
|---|---|---|---|
| **A** | agent invocation / provider integration | **ABSENT** | no `claude` binary on `PATH`, in `/usr/local/bin`, `/opt/homebrew/bin`, `~/.claude/local`, `~/.local/bin`, `/Applications`, or any nvm bin. `ANTHROPIC_API_KEY`, `CLAUDE_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` all unset; `~/.claude/.credentials.json` absent |
| **B** | trusted worker identity | **CONTRACT ONLY** | identity is self-asserted. Attestation hook implemented and tested; it becomes a boundary only when the key lives where the worker cannot read it |
| **C** | durable execution / supervision | **AVAILABLE, UNUSED** | `launchd` user agents are in use on this host (e.g. `com.cytolab.pathos-3100.plist`). **0** self-hosted GitHub runners; GitHub-hosted runners are ephemeral per job; `docker` installed but the daemon is not running |
| **D** | persistent queue + crash recovery | **WORKING** | atomic write (`tmp` + `rename`) under an exclusive `wx` lock; restart recovery covered by tests 3 and 8 |
| **E** | independent verifier invocation + enforcement | **PARTIAL** | three of four attacks refused; renaming still works without attestation — see below |
| **F** | structured result / evidence capture | **WORKING** | `verified` requires an evidence reference matching URL / `artifact:` / `ci:` / `commit:`; evidence now also records `identityTrust` and `implementedBy` |
| **G** | retry / timeout / cancellation | **WORKING** | bounded leases, expiry recovery to the correct state, retry budget terminating with a recorded reason |
| **H** | automatic dispatch of the next eligible task | **WORKING** | verifying a dependency makes dependents eligible; demonstrated on the real queue in Milestone 1 |
| **I** | monitoring / safe shutdown | **PARTIAL** | `status` and `recover` report honestly; there is no supervisor to shut down, because there is no long-running process |

### What the identity boundary actually withstands

Probed adversarially, not assumed:

| attack | result |
|---|---|
| implementer replays its own lease token as a `verified` event | **refused** — token mismatch |
| verify without declaring `SKILLS_AGENT_ROLE=verifier` | **refused** |
| a third party spends somebody else's verification lease | **refused** — the lease is bound to the claiming identity |
| **implementer renames itself and claims verification** | **SUCCEEDS** |

The last one is the real limit and is **not** described as cryptographic independence. It cannot
be closed by the coordinator alone: both roles run in the same shell, so any secret the
coordinator checks is a secret the worker can read.

### The smallest safe integration boundary

Rather than build a framework around a provider that is not present, the coordinator now accepts
identity **provenance**:

```
SKILLS_AGENT_ATTESTATION_KEY   held by the RUNNER, never by the worker
SKILLS_AGENT_IDENTITY_TOKEN    HMAC-SHA256(`${taskId}:${role}:${identity}`), minted by the runner
policy.requireAttestedIdentity makes an unattested verification a refusal
```

With no key configured nothing changes and identity records as `self-asserted` — the current
behaviour, now **visible in the evidence instead of only in prose**. With a key, a forged token, a
token minted for a different identity, and a missing token are each refused, and the trust level
is carried into the evidence record.

**This is a contract, not yet a boundary.** While the runner and the worker share a process tree,
a worker can read the key. It becomes real when a runner holds it out of reach — which is exactly
the missing prerequisite below.

### The precise missing prerequisite

To run genuine autonomous execution, three things are needed. **One of the three now exists.**

1. **An agent invocation mechanism** — a supported, authorized way to start a bounded agent with a
   task envelope and collect a structured result. **Missing.**
2. **A credential for it**, which must not be guessed or fabricated. **Missing.**
3. **A durable execution host** that outlives a worker. **Available** (`launchd` on this host), but
   there is nothing to supervise until 1 and 2 exist.

Until 1 and 2 are supplied, **continuous autonomous execution is not operational and is not
claimed.** `V5-AUTO-002` stays `BLOCKED_EXTERNAL`.

## The guard's self-test (added 2026-10-21)

`npm run guard:selftest` → `scripts/guard-protected-paths.mjs --self-test`. **57 assertions.**

It **spawns the real script** on each payload rather than calling its functions, because the
decision this guard makes is an exit code from a process fed JSON on stdin — the contract is
where the six reproduced bypasses lived, so that is what is asserted.

What it covers: the six formerly-permitted payload shapes; spellings of one destination
(`./`, absolute, `..` traversal, double slash, trailing space, an unenumerated key, three levels
of nesting, an unknown tool, a `MultiEdit` with one protected target of two); all eleven
protected roots, against a **written-out expected list**; unclassifiable payloads; six
false-positive cases that must stay allowed; the five documented gaps, asserted as `ALLOW` so
that closing one fails the suite and forces the header to be updated with it; the config
fail-closed shapes; the `exceptions` mechanism; and the **G-3 symlink case**.

**It was mutation-tested, and two of its own defects were found that way.**

| mutation | caught? |
|---|---|
| remove `docs/adr` from the config | **was NOT caught** → fixed |
| config gains an unlisted root | yes |
| revert to a key allow-list | yes |
| drop `content` from `CONTENT_KEYS` | yes |
| ignore `exceptions` | yes |
| `within()` back to lexical `path.resolve` (G-3) | **was NOT caught** → fixed |
| remove the 4096-char bound | **was NOT caught** → fixed |
| remove the newline test | **was NOT caught** → fixed |
| revert the empty-`protected` check | yes |

The first defect: the root loop iterated `readConfig().protected`, so deleting a root deleted its
own assertion — 51 passed before the deletion, 50 passed after, **green both times**. The roots
are now written out in the test and compared against the config in both directions.

The second: the gap assertions used `a\n<path>` and `'a'.repeat(4097)`, neither of which resolves
into a protected root even when treated as a path, so removing a carve-out left the suite green.
They now use forms that resolve inside `supabase/migrations` the moment they are considered.

A test that stays green when the thing it tests is deleted is worse than no test, because it
reports assurance that does not exist. Both were found by breaking the guard on purpose and
checking the suite noticed — which is the only way either would have surfaced.

**Also fixed (behaviour change).** `readConfig()` rejected a non-array and an array containing an
empty string, but **accepted an empty array** — `[].some(...)` is false — while its own error
message said *"non-empty"*. Measured: `{"protected":[],"exceptions":[]}` allowed a write to every
one of the eleven roots. An empty list is not how a protection is lifted; `exceptions` is, and
removing one root deliberately still works. It now fails closed. Revertible by one condition.

## The `Bash` exposure — mapped, with a bounded proposal (2026-10-21)

**This section is a PROPOSAL. Nothing in it is approved, and no permission was changed.**

### The exposure, demonstrated rather than asserted

1. The hook's own verdict on `{"tool_name":"Bash","tool_input":{"command":"printf x >
   supabase/migrations/999.sql"}}` is **exit 0 — allow**. `Bash` is in `UNENFORCEABLE`.
2. A shell redirect writes the file with no hook involvement of any kind.
3. The destination need not appear in the command text at all. `printf y > "$(echo
   c3VwYWJhc2UvbWlncmF0aW9ucw== | base64 -d)/998.sql"` writes into the protected directory while
   the command string contains no protected path. **Any control that matches command text is
   defeated by this, and shell offers unboundedly many spellings of it.**

### Options, with what each costs legitimate autonomous work

| option | assurance | cost | verdict |
|---|---|---|---|
| `permissions.deny` patterns on `Bash` | **low** — defeated by (3) above; shell is Turing-complete | high: breaks ordinary `npm`, `git`, `node` work and produces false refusals | **reject** |
| a `PreToolUse` hook that parses shell | partial at best; classifying arbitrary shell is not decidable, and a partial classifier that *looks* complete is worse than none | moderate, plus a standing false-confidence risk | **reject** |
| OS immutability (`chflags uchg`, `chmod -w`) on the eleven roots | **high** — applies to every writer | breaks `git checkout`, `merge` and `rebase` on those paths; needs a documented unlock, and an unlock that exists is a step an agent can take | **defer** — real, but it fights git |
| **a CI gate on protected-path changes** | **high at the boundary that governs** | **none locally** | **propose** |
| a local `pre-commit` convenience hook | none (bypassable) | none | propose, **labelled as a convenience** |

### Why CI, in the repository's own words

`.githooks/README.md` already settles this: *"There is no way to make a hook mandatory from inside
the repository — a hook is a convenience that fires before a mistake, not a control. Anything that
must not be bypassable belongs in CI, where `ci.yml` runs regardless of what a working copy is
configured to do."*

That doctrine applies exactly. The governance risk is not a transient local edit — it is an
unauthorized change to an authority file **landing**. A CI gate catches that regardless of whether
the write came from a tool, a shell redirect, an editor, or git itself, and it cannot be switched
off from inside a working copy.

### The bounded proposal

1. A `static-guards` step that computes the protected paths changed in the push/PR and fails unless
   the change carries an explicit authorization marker (a commit trailer naming the authorizing
   decision, or a matching entry in `scripts/protected-paths.json` `exceptions`).
2. A `pre-commit` convenience hook in `.githooks/` that warns on the same condition, documented as
   a convenience and not a control, per the README's doctrine.
3. Tests: a fixture commit touching a protected path **without** a marker must fail the gate; one
   **with** a valid marker must pass; a commit touching nothing protected must be unaffected.
4. Rollback: both are additive. Removing the CI step and the hook file restores today's behaviour,
   and neither can block a local build.

**Not implemented in this phase.** It adds a required CI gate, which changes what can merge — a
governance act needing explicit authorization. It also needs an owner decision on what counts as a
valid authorization marker, which is the same question as **CR-1** (§1 of
`V5_AUTONOMOUS_PHASE_2026-10-21_FINDINGS.md`): until `OD-*` answers have a declared home, a marker
pointing at one cannot be validated.

**Until then the exposure stands, and is stated rather than mitigated:** the protected-path guard
reduces accidental authority-file edits through the tool layer. It is not a sandbox, `Bash` is
outside it, and no local control can close that.

## `block` — recording a veto the CLI could not reach (added 2026-10-21)

`node scripts/skills-agent-coordinator.mjs block <task-id> <owner|external|governance> [note]`

**The gap it closes.** `validate` reports a task that declares an unresolved blocker while sitting
in a runnable status, and says the status *"should be corrected"* — but there was no way to correct
it. `event` requires a lease token; a lease comes only from `claim`; `claim` selects on `eligible()`,
which the blocker itself vetoes. So the one status the queue most needs to record was the one the
CLI could not reach, and the existing `BLOCKED_*` rows in `state.json` had to be seeded by hand.
Found on `V5-GOV-009` during this phase.

It takes **no lease**, deliberately: a task this applies to cannot be claimed, so requiring one
would require something unobtainable. It does require `SKILLS_AGENT_ID`, so the record names who
declared the block.

**It cannot park runnable work.** The task must already declare an unresolved blocker, and must not
hold a live lease. Both refusals are in `blockRefusalReason()`, which is extracted precisely so the
`--self-test` asserts the *rule* rather than trusting that the CLI path applies it; each refusal was
mutation-tested and each mutation fails the suite.

Recording a block is not deciding one. The blocker's `what`, `evidence` and `action` still come from
`tasks.json`, and `eligible()` vetoes the task either way — this only stops the status field from
lying about why.
