# V5 · Owner authority direction — received, recorded as PROPOSED

**Received 2026-10-21 · branch `feat/v5-autonomous-team` · HEAD `08b3543` · uncommitted, unpushed**

**STATUS: PROPOSED — NOT YET EFFECTIVE.** This file is the auditable artifact of what the owner
supplied. It is **not** a governance register, and creating it does not make the direction effective.
By the direction's own sentence 2, a protected governance decision becomes effective **only** after it
is recorded through the approved procedure (`MASTER_PRODUCT_DECISIONS.md` §2) with owner attribution,
decision scope, status and auditable repository evidence. **That recording has not happened**, because
every file §2's steps touch is a protected root and refuses tool writes (measured: exit 2 on all four;
`exceptions: []`).

This file exists because the direction requires *"auditable repository evidence"* and an owner
statement made in conversation leaves no artifact of its own. It supplies the candidate evidence; it
does not supply the authorization.

---

## 1 · The direction, verbatim

> **1. Decision authority:** Julia, acting as the 12Circle+ product owner, is the decision authority
> for product and governance decisions within her established scope; Claude Code may propose,
> document, validate, and implement decisions only after the applicable authorization requirements
> are satisfied.
>
> **2. Approval and recording:** An owner direction provided in this conversation expresses intended
> direction, but a protected governance decision becomes effective only after it is recorded through
> the approved governance procedure, with the required owner attribution, decision scope, status, and
> auditable repository evidence. Changes to the governance procedure itself require explicit owner
> approval and must be identified as process amendments.
>
> **3. Conflicting sources:** When authoritative sources conflict or the authority of a record is
> uncertain, Claude must preserve the existing state, identify the conflict, and request an explicit
> owner resolution rather than infer which source prevails. Until resolved, dependent implementation
> remains blocked.

---

## 2 · What this closes — **three gaps, now supplied**

| Gap previously labelled UNSUPPORTED | Now |
|---|---|
| **Who may approve?** The role label *"product owner"* was used 4× and defined nowhere; `Julia` appeared in 22 of 26 `Owner` cells and was never equated with the role. | **SUPPLIED** — Julia, acting as product owner, is the decision authority. |
| **How are source conflicts resolved?** No precedence rule existed. | **SUPPLIED** — preserve state, identify the conflict, request explicit owner resolution; **never infer which source prevails**. Dependent implementation stays blocked. |
| **What happens when an amendment changes the process itself?** Nothing written. | **SUPPLIED** — explicit owner approval required, and it **must be identified as a process amendment**. |

**One binding is implicit rather than stated.** Sentence 1 names Julia in the third person; sentence 2
says *"An owner direction provided in this conversation"*. Taken together they treat this channel as
carrying owner directions, which is the reasonable reading and the one adopted here. It is recorded as
**implicit** rather than asserted as explicit.

**One term remains undefined.** *"within her established scope"* is not defined anywhere in the
repository. It is not load-bearing for anything currently queued, and no boundary has been inferred
for it. Flagged, not resolved.

---

## 3 · What this does NOT do — **VERIFIED by reading the direction against the queue**

1. **It does not make itself effective.** The authority rule is a change to the governance procedure —
   it supplies what §2 lacks — so by sentence 2 it requires explicit owner approval **and** must be
   recorded as a process amendment. The owner has supplied its *content*; the *recording act* has not
   occurred.
2. **It does not approve the B-01 amendment.** It says nothing about `docs/adr/`, the `Resolves:`
   convention, or whether ADRs become authoritative for `OD-*` answers. `V5-GOV-012` stays blocked.
3. **It does not resolve the initial migration scope.** Nothing about 11 versus 12 identifiers.
   `V5-GOV-016` stays blocked.
4. **It does not adopt the `Owner?` definition.** `V5-GOV-013` stays blocked.
5. **It does not answer `OD-QAX-2` or `OD-14`.** Both remain `proposed`, `owner: null`, `record: null`.
6. **It does not authorize any protected-file edit.** Naming the decision authority is not the same as
   granting the tool layer write access to a protected root, and the only sanctioned exception
   mechanism — an entry in `scripts/protected-paths.json` — remains deliberately empty.
7. **Sentence 3 actively confirms that `QAX-SEC-03` stays blocked**, and that the agent-authored
   `OD-14.blocks` entry must **not** be narrowed to resolve the three-way attribution conflict. The
   restraint previously exercised there was correct and is now a rule.

---

## 4 · Exact process-amendment text, for approval — **PROPOSED, written to no protected file**

This records the authority rule itself. It is labelled a process amendment, as sentence 2 requires.

```markdown
**Amendment, <DATE> — additive, nothing above rewritten. THIS IS A PROCESS AMENDMENT.**
It changes how decisions are approved and recorded. It answers no product question, resolves no
finding, and authorizes no implementation.

**§2.1 Decision authority.** Julia, acting as the 12Circle+ product owner, is the decision authority
for product and governance decisions within her established scope. No other party may approve a
decision, and no agent may approve one on her behalf.

**§2.2 When a direction becomes effective.** An owner direction expresses intended direction. A
protected governance decision becomes effective ONLY when it has been recorded through §2's steps
carrying all four of:
  * owner attribution — the named authority and the date;
  * decision scope — exactly what the decision does and does not cover;
  * status — one of PROPOSED | ANSWERED | SUPERSEDED | WITHDRAWN;
  * auditable repository evidence — the commit, or a cited record, that captures the recording act.
A direction that is not yet recorded is not effective, and nothing may be implemented on it.

**§2.3 Process amendments.** A change to this procedure requires explicit owner approval and MUST be
identified as a process amendment in its own heading, so it can never be mistaken for a substantive
answer. It may not be bundled with a decision it enables.

**§2.4 Conflicting sources.** Where authoritative sources conflict, or the authority of a record is
uncertain, the existing state is PRESERVED, the conflict is identified, and an explicit owner
resolution is requested. No agent may infer which source prevails. Until the owner resolves it,
dependent implementation remains BLOCKED.

**§2.5 Agent permissions.** An agent may propose, document and validate at any time. It may
implement only after the authorization requirements applicable to that change are satisfied.
```

### 4.1 The two distinct acts still required

Recording this needs **both**, and they are different asks:

**(a) Approve the text above** — a reply naming it, or an edited version.

**(b) Enable the recording.** All four §2 files refuse tool writes (exit 2). Either:
   * **the owner performs the edits** — the cleanest path, since the owner is the attributed
     authority and the act then needs no delegation; or
   * **the owner authorizes a narrow, time-bounded protected-path exception** for the specific files,
     added to `scripts/protected-paths.json` as a reviewable diff. Note the circularity: that
     exception is itself a protected-configuration change, and widening the guard is exactly the kind
     of act the guard exists to make visible.

**I have not chosen between these and have not prepared an exception entry.** Sentence 1 permits
implementation only once authorization requirements are satisfied, and the requirement for a
protected-root write has not been established.

---

## 5 · Queue effect — **no task became eligible**

`V5-GOV-015`'s blocker changes character rather than clearing: the **approver is now identified**, and
what remains is the **recording act**. It stays `BLOCKED_OWNER`. No other task's blocker is touched.

Verified after recording this file: queue unchanged in substance — `authorized: []`, drift `[]`,
**0 eligible**, `OD-QAX-2` and `OD-14` still `proposed` with `owner: null`.
