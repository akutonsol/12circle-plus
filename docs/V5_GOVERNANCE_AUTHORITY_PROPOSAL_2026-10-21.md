# V5 · Governance authority — approval rule, B-01 amendment, `Owner?` definition
**2026-10-21 · `feat/v5-autonomous-team` · HEAD `08b3543` · written at that HEAD; since MERGED to `main` (PR #1, merge commit `d57dfa8`)**

**Nothing here is approved and no protected file was modified.** Every conclusion is labelled
**VERIFIED**, **PROPOSED**, **BLOCKED** or **UNVERIFIED**. Drafts are given as exact text for review,
written to no file.

---

## 1 · The approval-authority gap, stated precisely — **VERIFIED**

The previous report said *"no documented rule establishes who may approve"*. That is true of a
**written rule**, and it understated what exists: there is a **fully exercised precedent**, three
weeks old, and it maps exactly onto the documented procedure.

### 1.1 The procedure exists and has been executed end to end — **VERIFIED**

`MASTER_PRODUCT_DECISIONS.md` §2 lists five steps. Commit **`08e27f7`** — *"docs(PD-A13): record the
owner answer through all five of §2's steps"* — touched exactly the four files those steps name:

| §2 step | File | Touched by `08e27f7` |
|---|---|---|
| 1 · record answer + why | `decision-log.md` | +1 line |
| 2 · row → `ANSWERED` + date + owner | `MASTER_PRODUCT_DECISIONS.md` | +13/−1 |
| 3 · move blocked findings | `MASTER_REMEDIATION_REGISTRY.md` | +39/−1 |
| 4 · reflect the wave change | `REMEDIATION_PROGRESS.md` | +7/−3 |
| 5 · mark superseded if reversing | `decision-log.md` *"Superseded / revised"* | n/a — nothing reversed |

So the question is **not** *"is there a process?"* — it is *"who is entitled to trigger it, and what
act counts as approval?"*

### 1.2 What the repository does and does not establish — **VERIFIED**

| Question | Direct evidence | Status |
|---|---|---|
| Is an approver *named*? | parsing the 8-column decision table: **26** `PD-A*` rows, of which **22 name `Julia`** (15 bare + 7 as `Julia + privacy/coaching/engineering/compliance/clinical`) and **4 name `engineering`** | **named, not defined** |
| Is an approving *role* used? | *"`PD-A13` is `ANSWERED` **by the product owner** on 2026-10-19"*; `decision-log.md:43` *"(PD-A13, option (a), product owner, 2026-10-19)"*; `ADR-W1-001:3` *"owner decisions supplied 2026-09-27"*; the authorization doc's §1 heading *"OWNER DECISIONS — RECORDED AS SUPPLIED"* | **role label used 4×** |
| Is `Julia` equated with *"the product owner"*? | **nothing** | **UNVERIFIED** |
| Is *"product owner"* defined — person, role, authority? | **nothing** | **UNVERIFIED** |
| What act constitutes approval? | **nothing written.** Observed: the owner states an answer, an agent records it through §2, and the **commit** is the durable artifact. The owner's statement itself leaves no artifact | **practice only** |
| Who may approve a change to §2 itself? | **nothing** | **UNVERIFIED — this is B-01's blocker** |
| How are source conflicts resolved? | **nothing** | **UNVERIFIED** |

### 1.3 One structural fact that already functions as an approval control — **VERIFIED**

All four files §2's steps touch are **protected roots**: `decision-log.md`,
`MASTER_PRODUCT_DECISIONS.md`, `MASTER_REMEDIATION_REGISTRY.md`, `REMEDIATION_PROGRESS.md`
(measured with the guard itself). **An agent cannot execute §2 through the tool layer at all** —
every step is refused. Recording a decision is therefore already a human or explicitly-excepted act.

This matters for the proposal: the missing piece is *attribution and evidence of the owner's act*,
not an enforcement mechanism. One already exists, and `Bash` remains its documented hole.

### 1.4 The irreducible gap — **BLOCKED, and not closable in code**

**The owner's directions reach this session as conversation.** No repository rule makes a
conversational direction an effective decision, and **I cannot verify that the speaker is the person
the register calls `Julia` or *"the product owner"***. That binding is an identity claim about the
real world. **It is a human decision and I will not synthesise it** — no invented role, credential,
approver list, or signing scheme appears below.

What *can* be proposed is the recording and attribution discipline around whatever identity the owner
declares. That is §2 of this document.

---

## 2 · Proposed decision-authority rule — **PROPOSED**

Answering the ten required questions. **Grounded in observed precedent, not invented**; every
assumption not supported by the repository is flagged **[UNSUPPORTED — owner must supply]**.

| # | Question | Proposed answer | Basis |
|---|---|---|---|
| 1 | Who may **propose**? | Anyone — agent or human. A proposal carries no authority, so the right to make one needs no gate. Proposals live outside the protected registers. | current practice; this document is one |
| 2 | Who may **approve**? | **The product owner**, the role label the repository already uses for the approving act. **[UNSUPPORTED — owner must bind this label to an identity.]** No alternative approver, delegate or quorum is proposed. | 4 attributions |
| 3 | What **evidence** establishes the approver is authorized? | **[UNSUPPORTED.]** Nothing in the repository can establish it. *Proposed minimum:* the owner states, once, in a record they control, which identity holds the role — and that statement becomes the root of trust. Everything after it is checkable; it is not. | — |
| 4 | How is approval **recorded and attributed**? | Exactly as `08e27f7` did: the five §2 steps, plus a commit whose message attests which steps were performed. Attribution is the existing idiom `ANSWERED <date> · option (x) · owner: <who>` with a `(record: …)` pointer. **Addition proposed:** the commit SHA becomes the citable evidence of the recording act, since the owner's statement leaves none. | `08e27f7`; PD-A05/A23/A13 |
| 5 | When does it become **effective**? | When **all applicable §2 steps are complete and committed** — not when the owner speaks, and not when an agent writes one file. A half-recorded decision is not effective. This matches `QA_CLOSURE_STANDARD.md`'s *"no partial closures"* principle. | §2; closure standard |
| 6 | How are **proposed / approved / superseded / withdrawn / unresolved** represented? | `proposed` → outside the registers. `approved` → `ANSWERED` + record pointer. `superseded` → §2 step 5's *"Superseded / revised"* section, **marked, never deleted**. **`withdrawn` has no representation today** — *proposed:* `WITHDRAWN <date> · owner: <who>` in the same idiom, with the original text retained. `unresolved` → the row exists with no `ANSWERED` marker. | §2 step 5; the section exists and is empty |
| 7 | How are **source conflicts** resolved? | *Proposed:* the document that declares itself authoritative **for that subject** governs, and every other copy is a mirror corrected to match — never the reverse. Where two documents both claim the subject, it is an owner decision, recorded as one. **[PARTLY UNSUPPORTED]** — the self-declaration convention exists, the precedence rule does not. | the five Wave-0 docs each declare scope |
| 8 | What happens when an amendment changes the **process itself**? | **[UNSUPPORTED — the core gap.]** *Proposed:* a process amendment is a decision in its own right, recorded by the same five steps, and **must state that it is a process change** so it is never mistaken for a substantive answer. It cannot be bundled with a decision it enables. | — |
| 9 | How is approving a **mechanism** distinguished from approving a **policy**? | *Proposed, and load-bearing:* a mechanism amendment says where answers live; it answers nothing. Enforced three ways — (a) the amendment text must carry the sentence *"This answers no `OD-*` question and authorizes no implementation"*; (b) an ADR authorizes only the identifiers in its `Resolves:` line; (c) validator rules V7–V9 below. | drafted in §3 |
| 10 | What **machine-checkable** conditions prevent an unapproved or ambiguous decision authorizing implementation? | The eleven checks in §6. **Hard limit, stated plainly:** a machine can verify an identifier is cited, its ADR exists, parses, is `ACCEPTED`, and names that identifier. **It cannot verify that the ADR's prose authorizes the specific change.** That residue is CR-1's irreducible part and must be disclosed wherever the validator's output is used. | §6 |

### 2.1 The smallest possible owner approval request

Three sentences, which is the whole of what cannot be derived:

1. *"The product owner is `<identity>`, and directions I give in this channel are authoritative."*
2. *"A process amendment requires my approval, recorded by §2's five steps with a note that it is a process change."*
3. *"Where two source documents conflict, `<rule>`."* — or *"bring each conflict to me."*

Nothing else in this document needs an answer that the repository cannot supply.

---

## 3 · B-01 / CR-1 — exact additive amendment — **PROPOSED, not applied**

Follows the repository's own idiom, used five times (*"Amendment, <date> — additive, nothing above
rewritten"*). **Exact text for review. Written to no file.**

```markdown
**Amendment, <DATE> — additive, nothing above rewritten.** §2 above is unchanged and remains the
procedure for every decision. This amendment qualifies it for one namespace.

**1 · Scope of this amendment.** It applies to `OD-*` decisions ONLY. `PD-A*` decisions — including
`PD-A05`, `PD-A23` and `PD-A13`, already `ANSWERED` — keep §2 exactly as written and remain
authoritative for their existing scope. Nothing above is restated, narrowed or re-homed.

**2 · Why a qualification is needed.** §2 step 2 says "update this document's row". No `OD-*` row has
ever existed in this document, so the procedure cannot be executed for an `OD-*` identifier as
written. This closes that gap rather than replacing the procedure.

**3 · The standing record for an `OD-*` answer is an ADR under `docs/adr/`.** Each such ADR MUST
carry:

    **Status:**     PROPOSED | ACCEPTED | SUPERSEDED-BY <adr-id> | WITHDRAWN
    **Resolves:**   <comma-separated OD-* identifiers this ADR answers>
    **Authorized:** <owner> on <YYYY-MM-DD>, recorded at <commit-or-path>
                    (omitted while Status is PROPOSED)

`Resolves:` is a claim of authority over a question. An ADR that merely discusses an identifier MUST
NOT list it.

**4 · §2's other steps are unchanged and still apply.** Step 1's `decision-log.md` entry remains
REQUIRED as a one-line cross-reference naming the identifier and its ADR, so the standing log stays
a complete index; the ADR holds the full answer and reasoning. Steps 3, 4 and 5 apply unchanged.

**5 · Existing `D1` and `D3` rulings are LINKED, never rewritten.** Their recorded text in
`V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md`, `V5_SECURITY_FOUNDATION_WAVE1_FINAL_REPORT.md`,
`V5_PROGRAMME_DEFINITION.md` §19.1 and `ADR-W1-001` stays byte-for-byte as it is, in place, with its
original date and context. Migration of such a ruling means adding a `Resolves:` line to the ADR that
already records it — or creating an ADR that cites the existing record as its source. No historical
wording is edited, moved or reinterpreted.

**6 · Scope limit on authorization.** An ADR authorizes implementation ONLY for the identifiers in
its `Resolves:` line, and only to the extent its own decision text states. An `ACCEPTED` status is
not a general authorization for the finding, the table, or any related work. A finding touched by two
identifiers needs both answered.

**7 · This amendment records WHERE an `OD-*` answer lives. It answers no `OD-*` question and
authorizes no implementation.**
```

### 3.1 The three questions this draft had to decide, and why — **PROPOSED**

* **`OD-*` only, not all decisions.** Extending ADRs to `PD-A*` would silently re-home three already
  `ANSWERED` decisions and contradict §2 for rows that followed it correctly. Deliberately two homes,
  stated explicitly rather than left implicit.
* **`decision-log.md` kept as the index.** Dropping step 1 would destroy the only cross-decision
  index and make `PD-A13`'s own `(record: decision-log.md)` pointer false. **UNVERIFIED whether the
  owner wants this** — the direction did not cover it.
* **Link, don't move, `D1`/`D3`.** Any rewriting risks altering meaning, and §9 of the prior report
  showed `D1` already exists in three copies; moving it would create a fourth divergence.

---

## 4 · Initial migration scope — the 11, and `OD-14` — **VERIFIED inventory, PROPOSED scope**

### 4.1 The 11, mechanically extracted from the registry's `Owner?` column — **VERIFIED**

12 rows, 11 distinct identifiers (`OD-QAX-1` cited twice).

| `OD-*` | Finding(s) | Registry line | Status stated anywhere |
|---|---|---|---|
| `OD-QAX-1` | `QAX-SEC-02`; `QAX-H-01`/`QAX-H-02` | 3404, 3426 | **OPEN** (`QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:108`) |
| `OD-QAX-2` | `QAX-SEC-01` | 3405 | *unknown* |
| `OD-QAX-3` | `QAX-SEC-07` | 3408 | *unknown* |
| `OD-QAX-4` | `QAX-PRV-01` | 3409 | *unknown* |
| `OD-QAX-5` | `QAX-PRV-02` | 3410 | *unknown* |
| `OD-QAX-6` | `QAX-COR-03` | 3414 | *unknown* |
| `OD-QAX-7` | `QAX-PRV-03` | 3418 | *unknown* |
| `OD-QAX-8` | `QAX-REG-01` | 3419 | *unknown* |
| `OD-QAX-9` | `QAX-SEC-08` | 3459 | **OPEN** (`V5_DECISION_RESOLUTION_2026-09-27.md:78`) — **contradicted**, see §5 |
| `OD-QAX-10` | `QAX-SEC-09` | 3460 | *unknown* |
| `OD-QAX-11` | `QAX-BIL-01` | 3461 | *unknown* |

### 4.2 `OD-14` is not among them — **VERIFIED**

`grep` of the `Owner?` column: **0** occurrences of `OD-14`. It is nonetheless one of only two
identifiers the task queue blocks on, governs `F-21`, and sits at the centre of the §5 dispute.

| | **Scope A — the 11 only** | **Scope B — the 11 + `OD-14`** |
|---|---|---|
| Fidelity to the direction | **exact** — the owner said eleven | adds one the owner did not name |
| Traceability | `OD-14` keeps *unknown* disposition in the 74-inventory; still discoverable, still unresolved | `OD-14` gains a home and a `Resolves:` target |
| Blocked work | `V5-SEC-OD14` and `F-21` **stay unrecordable** — an answer to `OD-14` would have nowhere to live, so B-03 cannot complete even after the owner answers it | `OD-14` becomes recordable; B-03 can complete on an answer |
| Consistency | the registry's `Owner?` column becomes the definition of "load-bearing", which is defensible and mechanical | "load-bearing" becomes *registry column ∪ queue blockers* — a second criterion needing its own definition |
| Cost | 11 ADR targets | 12 |

**Recommendation: Scope B (the 11 + `OD-14`) — PROPOSED, requiring explicit confirmation.**
Rationale: under Scope A the single most consequential open decision in the programme has no
authoritative home, so answering it still would not unblock the work. **The difference is material
and I have not applied it** — the direction says eleven, and §4.2 is a request to confirm twelve.

### 4.3 Traceability for all 74 — **VERIFIED**

Full inventory is Appendix A of `docs/V5_GOVERNANCE_FORMALIZATION_B01_B04_2026-10-21.md`, generated
mechanically: **74** identifiers, **11** load-bearing, **4** with any status marker, **70** recorded
`unknown`. No status was invented. Retention rule for the 62–63 not migrated initially: keep `id`,
first reference, occurrence count, file count, status (`unknown` unless stated) and `disposition`
(`migrated` | `deferred` | `obsolete — with citation`). **No identifier discarded, renamed, merged or
bulk-reclassified**; `obsolete` requires a citation, never an inference.

---

## 5 · Workstream D — the three attributions and the `OD-QAX-9` contradiction

### 5.1 `QAX-SEC-03` — reconciliation table — **VERIFIED facts, conflict OPEN**

| # | Source passage | Exact content | Nature |
|---|---|---|---|
| 1 | `MASTER_REMEDIATION_REGISTRY.md:3406` | `QAX-SEC-03` · P1 · Authorization · … · `Owner?` = **`no`** | **AUTHORITATIVE** — declared authority for *"remediation scope and finding status"*; but the `Owner?` field's meaning is itself undefined (§7) |
| 2 | `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:671` | `\| OD-QAX-2 \| May a coach assign plans or programs to a pending client (**SEC-01/03 fix shape**)? \|` | **INFORMATIVE** — the source report the registry transcribes; a report, not a register |
| 2b | same, `:82` | `\| QAX-SEC-03 self-asserted coach_id writes (6 tables) \| P1 \| VERIFIED · BLOCKED \| LR + MUT \| **migration** \|` — dependency is **`migration`**, not an `OD-*` id, not `no` | **INFORMATIVE** |
| 2c | same, `:418` | *"`QAX-SEC-03` (the underlying policy) should be fixed in the same wave"* | **INFORMATIVE** |
| 3 | `.skills-agent/decisions.json`, `OD-14.blocks` | `["QAX-SEC-03", "F-21"]` | **AGENT-AUTHORED** — written by me; basis is subject-matter similarity in `F21_BLAST_RADIUS.md §6` only. The ledger disclaims register status, and the guard refuses it as authorization. **Now carries a `blocksDisputed` disclosure recording exactly this.** |

**The unresolved question:** which decision, if any, must be answered before `QAX-SEC-03`'s policy may
be implemented — none (`no`), `OD-QAX-2` (whose stated scope includes the *"SEC-01/03 fix shape"*), or
`OD-14`?

**What depends on it:** `QAX-SEC-03` (P1, six tables with self-asserted `coach_id = auth.uid()` write
arms), task `V5-GOV-009`, and the scope of `V5-SEC-OD14`.

**Minimum correction supported by authority: none for sources 1 and 2.** Both say what they say, and
choosing between them is the owner's call. **For source 3, a correction IS supported**: it is
agent-authored, not transcribed, and no register supports it. The minimum correction would be to
narrow `OD-14.blocks` to `["F-21"]`. **I have not applied it**, because doing so would resolve the
three-way conflict by deleting one side — deciding B-04 by inference, which is forbidden. The
disclosure note was added instead; it changes no gate behaviour (verified: `authorized: []`,
`V5-GOV-009` still `BLOCKED_GOVERNANCE`, 0 eligible).

### 5.2 `OD-QAX-9` status contradiction — **VERIFIED, OPEN**

| Source | Says | Nature |
|---|---|---|
| `V5_DECISION_RESOLUTION_2026-09-27.md:78` (row `D1`) | status **`OPEN`**, owner-answered column **`NO`** | **INFORMATIVE** — a dated analysis table |
| `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` | `D1(i)/(ii)/(iii)` **verbatim as supplied**, dated **2026-09-27**; §1 heading *"OWNER DECISIONS — RECORDED AS SUPPLIED"*; 5 `D1(i)` references | **AUTHORITATIVE in practice** — migrations 132/133 cite it as their authority |
| `docs/adr/ADR-W1-001` | `Status: ACCEPTED (owner decisions supplied 2026-09-27)`; **0 occurrences of `OD-QAX-9`** | **AUTHORITATIVE for the decision, silent on the identifier** |
| applied migrations 132, 133 | cite both documents; frontier **181**, so applied | **implementation evidence** |

**Both are dated 2026-09-27.** The likely explanation — *not asserted* — is that the table was written
before the rulings were supplied the same day and never updated.

**The unresolved question:** is `OD-QAX-9` answered? Substantively its subject (*"What a coaching
'team' is, and how membership is consented"*, `:186`) is exactly what `D1(i)–(iii)` answer. Formally
**nothing links the identifier to the answer** — the ADR never names it.

**What depends on it:** `QAX-SEC-08`'s registry `Owner?` value, and whether `D1(iv)` (the permitted
`role` value set, **confirmed unanswered** at `ADR-W1-001:71`) is the only open part.

**Minimum correction, and it is genuinely available:** adding `**Resolves:** OD-QAX-9` to
`ADR-W1-001` would close the formal gap **without changing any ruling's meaning** — the ADR already
records the answer; the line only names the question it answers. **Blocked** because `docs/adr/` is
protected and the §3 amendment establishing the `Resolves:` convention is not approved. This is the
single highest-value protected edit available once B-01 is answered.

---

## 6 · `Owner?` — exact proposed registry preamble — **PROPOSED, not applied**

Reverified: the string `Owner?` occurs **only** as two table headers (`:3402`, `:3457`) and is
**never described in prose** anywhere in `docs/`. Its values are **`no`** (14 rows) or an
`OD-QAX-*` identifier (12 rows).

**Exact text for review, to be added to the §7.23 / §7.25 table preambles. Written to no file.**

```markdown
**Additive note, <DATE> — nothing above rewritten. Definition of the `Owner?` column.**

`Owner?` records a **decision dependency**: whether closing this finding requires an owner decision
that is not already recorded, and if so which one. It is NOT ownership, NOT assignment, and NOT
implementation permission.

* An `OD-*` value names a decision this finding depends on. It MUST resolve to an authoritative
  record — an ADR whose `Resolves:` line names that identifier and whose `Status:` is `ACCEPTED`
  (see `MASTER_PRODUCT_DECISIONS.md` §2, as amended). An `OD-*` value with no such record is an
  UNRESOLVED dependency and the finding stays blocked.
* **`no` means "no owner-decision dependency is recorded in this column". It does NOT mean
  implementation is permitted.** Wave entry (`MASTER_REMEDIATION_WAVES.md` §0.2), migration
  numbering, and the closure ladder (`QA_CLOSURE_STANDARD.md` §2.1) continue to govern
  independently, as does any dependency recorded elsewhere in this registry.
* **Missing or empty** is treated as UNRESOLVED, not as `no`.
* **Disputed** — where another document attributes a different dependency to the same finding — the
  finding stays blocked until the owner rules. This registry governs the field; other documents are
  mirrors to be corrected to match it, never the reverse.
* **`.skills-agent/decisions.json` is a MIRROR of decision state for scheduling only.** It is not a
  register and carries no authority. Where it disagrees with this registry, this registry governs and
  the mirror is corrected.
* **Amending this definition** requires the same authority as any other change to this document.
```

**Consequences, stated so the conservative default is visible.** Under this definition
`Owner? = no` does **not** unblock `QAX-SEC-03`; it is unblocked only by resolving §5.1 and then
obtaining whatever answer genuinely governs. **This is deliberately the reading that does not
unblock work.** A more permissive rule — under which `no` does permit implementation — is materially
different, and per the instruction it requires its own explicit, separately recorded decision.
**This proposal is not approved**, and it **does not** declare that `OD-14` governs `QAX-SEC-03`: no
authoritative record establishes that relationship.

---

## 7 · Machine validation specification — **PROPOSED, not implemented**

`supabase/scripts/check-decision-provenance.mjs`. Offline, deterministic, no secrets, no network.

| # | Check | Class | Fails when |
|---|---|---|---|
| V1 | missing ADR link | structural | an inventory identifier is resolved by **zero** ADRs |
| V2 | conflicting answers | structural | an identifier is resolved by **≥2** ADRs with no `SUPERSEDED-BY` chain |
| V3 | duplicate identifier | structural | an id appears twice in one `Resolves:` line |
| V4 | unknown identifier | structural | an ADR resolves an id **absent from the inventory** |
| V5 | invalid ADR | structural | a referenced ADR is missing, or lacks `Status:` / `Resolves:` |
| V6 | ambiguous status | structural | `Status:` missing or not one of the four permitted values |
| V7 | recorded ≠ authorized | **authorization** | `Status: ACCEPTED` with no `Authorized:` line |
| V8 | proposed must not authorize | **authorization** | an implementation cites an id whose ADR is `PROPOSED` |
| V9 | scope overreach | **authorization** | an implementation cites an id the ADR does not `Resolves:` |
| V10 | withdrawn / superseded | **authorization** | an implementation cites an id whose ADR is `WITHDRAWN` or `SUPERSEDED-BY` without following the chain |
| V11 | unresolved `Owner?` | **source** | a registry `Owner?` cell is empty, or holds an `OD-*` id failing V1/V7 |
| V12 | `no` without authorization elsewhere | **source** | `Owner? = no` is cited as the sole basis for implementing — reported, since `no` is not an authorization |
| V13 | unresolved approval authority | **meta** | the approval-authority rule (§2) is not recorded — **every authorization check above is then advisory only, and must say so** |

**Structural validity is strictly separate from substantive authorization.** V1–V6 are decidable by
parsing. V7–V12 check *recorded* authorization. **None can verify that an ADR's prose authorizes a
specific change** — a machine sees that an id is named and a status is `ACCEPTED`, nothing more.
V13 exists so the validator cannot be mistaken for authority while §1.4 is open.

### 7.1 Test plan — **PROPOSED, not written, and deliberately so**

Eleven fixture cases, one temp directory each, spawning the real script and asserting the exit code —
the idiom the guard's `--self-test` already uses (60 assertions) and the coordinator's in-process
assertions complement:

valid authorized ADR · proposed ADR must not authorize · missing identifier · duplicate identifier ·
conflicting answers · accepted ADR that does not resolve the cited id · resolves but scope does not
authorize · unresolved `Owner?` · `Owner? = no` with no authorization elsewhere · withdrawn/superseded
decision · unresolved approval-authority rule.

**Each must be mutation-tested** — the suite must fail when the rule it asserts is deleted. This is
not ceremony: of the assertions written in earlier phases, **four initially passed while the thing
they tested had been removed**, and were found only by breaking the code on purpose.

**Not written in this phase.** They would test a schema no record uses and an authority rule that does
not exist; every case would fail by construction, and a red suite asserting an unapproved schema
would be worse than none. **No new authorization mechanism was added or activated.**

---

## 8 · Protected files that would change if approved — **none changed now**

| File | Change | Gate |
|---|---|---|
| `docs/MASTER_PRODUCT_DECISIONS.md` | the §3 amendment; and the approval-authority rule (§2) | **B-01 + §1.4** |
| `docs/MASTER_REMEDIATION_REGISTRY.md` | the §6 `Owner?` preamble | **B-04**; recording may itself need B-01 |
| `docs/adr/` | `Resolves:`/`Authorized:`/`Status:` lines; `ADR-W1-001` gains `Resolves: OD-QAX-9`; ADR template | B-01 |
| `docs/decision-log.md` | one cross-reference line per `OD-*` answer | B-01 |
| `docs/REMEDIATION_PROGRESS.md` | §2 step 4, per decision recorded | per decision |
| `.github/workflows/ci.yml` | add the validator to `static-guards` | separate authorization |

**Verified this phase: all 11 protected roots and `.github/` are CLEAN. Protected-root list unchanged
at 11 roots, `exceptions: []`.**

---

## 9 · Correction to this document's own figures

An earlier draft of §1.2 said the `Owner` column names `Julia` in **38** rows with 5
`engineering`. **That was wrong.** It came from a loose `grep` that matched `| Julia… |` across
several tables and non-`Owner` cells. Re-measured by parsing the 8-column decision table and reading
the second-to-last cell: **26 `PD-A*` rows — 22 name `Julia`, 4 name `engineering`.** The
conclusion is unchanged (a named owner exists and is never bound to the `"product owner"` role
label), but the figure is corrected here rather than quietly restated, and the verification note on
`V5-GOV-014` recorded the superseded number.

This is the fourth measurement error found and corrected across these phases — after a glob matching
131, an `OD-38` status claim, and a verification note recording "confirmed" on a zero-result grep.
A reviewer should assume more remain and treat every figure as a claim to re-measure.
