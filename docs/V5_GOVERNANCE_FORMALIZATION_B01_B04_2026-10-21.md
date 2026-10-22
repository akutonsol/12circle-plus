# V5 · Governance formalization — B-01 / CR-1 and B-04 / QAX-SEC-03
**2026-10-21 · `feat/v5-autonomous-team` · HEAD `08b3543` · written at that HEAD; since MERGED to `main` (PR #1, merge commit `d57dfa8`)**

**Nothing in this document is decided, and no protected file was modified to produce it.**
Every claim is labelled **VERIFIED**, **PROPOSED**, **BLOCKED** or **UNVERIFIED**. The owner's
supplied directions are treated as *intended outcomes to be checked against the approved process*,
not as authorization — as the instruction requires.

---

## 1 · The approved governance process, as the repository actually defines it — **VERIFIED**

`MASTER_PRODUCT_DECISIONS.md` **§2 "Decision log discipline"** is the only documented procedure for
turning a decision into a recorded one. Quoted exactly:

> When a decision is taken:
> 1. Record the answer and the **why**, including the trade-off, in `decision-log.md` — **that file
>    is the standing record** …
> 2. Update **this document's** row to `ANSWERED` with the date and the owner.
> 3. Move every finding it blocked from `BLOCKED_DECISION` to `READY_TO_REMEDIATE` in
>    `MASTER_REMEDIATION_REGISTRY.md`.
> 4. Reflect the wave change in `REMEDIATION_PROGRESS.md`.
> 5. If the answer **reverses** an existing entry, mark the old row superseded rather than deleting it.

### 1.1 Two findings follow from this, and both block B-01 as written

**(a) The documented process names `decision-log.md`, not `docs/adr/`. — VERIFIED**
Step 1 calls `decision-log.md` *"the standing record"*. The owner's B-01 direction designates
`docs/adr/`. **These conflict.** B-01 is therefore not merely an implementation choice; adopting it
**amends §2**, and §2 lives in a protected file.

**(b) The process cannot be executed for an `OD-*` id at all. — VERIFIED**
Step 2 says *"update this document's row"*. `MASTER_PRODUCT_DECISIONS.md` contains **0** `OD-*` rows
(26 `PD-A*` rows, 7 `ANSWERED`). There is no row to update, for any of the 74 ids.

### 1.2 The process has been followed three times, and bypassed twice — **VERIFIED**

| Decision | Step 1 (`decision-log.md`)? | Where it actually lives | Cited by |
|---|---|---|---|
| `PD-A05` | **yes** — `decision-log.md:32` | + `MASTER_PRODUCT_DECISIONS` row `ANSWERED` | — |
| `PD-A23` | **yes** — `:42` | + row `ANSWERED` | — |
| `PD-A13` | **yes** — `:43` | + row `ANSWERED` | — |
| **`D1(i)–(iii)`** | **no** — 0 entries | `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` + `ADR-W1-001` + a third copy in `..._FINAL_REPORT.md` | applied migrations **132, 133** |
| **`D3`** | **no** — 0 entries | `V5_PROGRAMME_DEFINITION.md:3043` | applied migration **136** |

So the repository runs **two processes**: the documented `PD-A*` one, and an **undocumented** `D*`
one used for the security waves. The owner's B-01 direction effectively **formalizes the second**.
That is a defensible reading of what the repo already does — but it is a change to the documented
rule, not an application of it.

### 1.3 Who may approve, and how a direction becomes effective — **UNVERIFIED / gap**

Searched across `MASTER_PRODUCT_DECISIONS.md`, `QA_CLOSURE_STANDARD.md`, `MASTER_REMEDIATION_WAVES.md`
and `RELEASE_GATES.md` for any rule naming an approver or defining when a direction becomes
effective. **No such rule exists.** `QA_CLOSURE_STANDARD.md` declares it *"governs every status change
in `MASTER_REMEDIATION_REGISTRY.md`"* — findings, not decision records. §2 step 2 says a row records
*"the date and the owner"*, which presumes an owner but never defines who that is or what act
constitutes approval.

**Consequence.** There is no mechanism by which a direction stated in conversation becomes a recorded,
effective decision. This is the missing mechanism the instruction says to report rather than bypass.

---

## 2 · B-01 / CR-1 status — **BLOCKED by a missing authorization step**

**Not recorded. Not effective. Blocked.** Three things must happen before `docs/adr/` can become the
authoritative home, and none is within this task's authority:

1. **Amend §2 of `MASTER_PRODUCT_DECISIONS.md`** so the standing record for an `OD-*` answer is an ADR.
   Protected file.
2. **Establish an approval rule** (§1.3) — or accept that this very amendment has no defined approver,
   which is circular and should be resolved first.
3. **Decide the `PD-A*` question**: does the ADR home apply to `OD-*` only, or to all decisions? If
   only `OD-*`, the repository deliberately keeps two homes and §2 must say so explicitly.

### 2.1 The minimum governance change — **PROPOSED, not applied**

The repository has an established idiom for amending these documents, used five times:
`**Amendment, <date> — additive, nothing above rewritten.**` The minimum change follows it exactly.

**Proposed addition to `docs/MASTER_PRODUCT_DECISIONS.md`, after §2** *(exact text for owner review —
not written to the file)*:

```markdown
**Amendment, <DATE> — additive, nothing above rewritten.** §2 above remains the procedure for
`PD-A*` decisions. For an `OD-*` decision it is qualified, because §2 step 2 presumes a row in this
document and no `OD-*` row has ever existed here.

For an `OD-*` decision the standing record is **an ADR under `docs/adr/`**, which MUST carry a
`**Resolves:**` line naming every `OD-*` identifier it answers, and a `**Status:**` line. Steps 3,
4 and 5 of §2 are unchanged and still apply. Step 1's `decision-log.md` entry remains REQUIRED as
the one-line cross-reference, so the standing log stays complete; the ADR holds the full answer.

This amendment records WHERE an `OD-*` answer lives. It answers no `OD-*` question, and it does not
authorize any implementation.
```

**Why `decision-log.md` is retained as a cross-reference.** Dropping step 1 would break the only
index that currently spans decisions, and would silently reclassify `PD-A05`/`PD-A23`/`PD-A13`'s
home. Keeping a one-line pointer preserves §2's intent while moving the substance to the ADR.
**UNVERIFIED whether the owner wants this** — it is a choice inside B-01 that the direction did not
cover, and it is raised rather than assumed.

### 2.2 Stop condition reached

Per the instruction's stop conditions, I stopped before modifying protected files because *"the
approved governance process does not authorize the proposed change"* and *"the source of authority is
ambiguous"* (§1.3). **No protected file was touched.**

---

## 3 · The ADR schema and validation — **PROPOSED**

### 3.1 Schema

`ADR-W1-001` already carries a parseable `**Status:** ACCEPTED (owner decisions supplied 2026-09-27)`
line. The proposal adds two lines and changes nothing else:

```markdown
# ADR-<id> — <title>

**Status:** PROPOSED | ACCEPTED | SUPERSEDED-BY <adr-id>
**Resolves:** OD-QAX-9, OD-QAX-12          <- every identifier this ADR answers, comma-separated
**Authorized:** <owner> on <YYYY-MM-DD> in <record path>    <- omitted while Status is PROPOSED
```

**`Resolves:` is deliberately not `Related:`.** It is a claim of *authority over a question*, and the
validator treats it as such. An ADR that merely discusses an identifier must not list it.

### 3.2 Validation requirements — **PROPOSED, not implemented**

`supabase/scripts/check-decision-provenance.mjs`, offline, deterministic, no secrets. It must fail on:

| # | Condition | Why |
|---|---|---|
| V1 | an id in the authoritative inventory resolved by **zero** ADRs | the gap CR-1 exists to close |
| V2 | an id resolved by **two or more** ADRs without a `SUPERSEDED-BY` chain | conflicting answers |
| V3 | a **duplicate** id within one `Resolves:` line | ambiguity |
| V4 | an ADR resolving an id **not in the inventory** | invented authority |
| V5 | a referenced ADR that is **missing or structurally invalid** (no `Status:`, no `Resolves:`) | dangling reference |
| V6 | `Status:` **missing or not one of** the three permitted values | ambiguous status |
| V7 | `Status: ACCEPTED` with **no `Authorized:`** line | recorded but not authorized |
| V8 | an implementation (migration or task) citing an id whose ADR is **`PROPOSED`** | implementing an unauthorized decision |
| V9 | an implementation whose **scope exceeds** what the ADR's `Resolves:` covers | scope creep past the answer |

**Structural validity is kept strictly separate from substantive authorization.** V1–V6 are
structural: they can be decided by parsing. V7–V9 are authorization: V7 is checkable, **V8 and V9
are only partly checkable** — a machine can verify that an id is cited and its ADR is ACCEPTED; it
cannot verify that the ADR's *prose* authorizes the *specific* change. That residue is CR-1's
irreducible part and must be stated wherever this validator's output is used.

### 3.3 Tests for the validator — **PROPOSED, not written**

Fixture-driven, one temp directory per case, mirroring the guard's `--self-test` idiom (spawn the
real script, assert the exit code) and the coordinator's in-process assertions. Eight cases, matching
the instruction: well-formed **authorized**; well-formed but **proposed**; **missing**; **conflicting**
answers; **duplicate** id; an ADR that **does not** explicitly resolve a cited id; a valid record whose
**scope** does not cover the requested implementation; an **ambiguous/undefined `Owner?`** value.

Each must be **mutation-tested** — the suite must fail when the rule it asserts is removed. This is
not pro forma: of the assertions written in earlier phases, **four initially passed while the thing
they tested was deleted**, and were only found by breaking the code on purpose.

**Not written in this task.** They would test a schema no record yet uses; every case would fail by
construction, and a red suite asserting an unauthorized schema is worse than none.

---

## 4 · Scope — the 11 and the 74 — **VERIFIED inventory, PROPOSED plan**

### 4.1 The 11 load-bearing identifiers are unambiguous — **VERIFIED**

Extracted mechanically from the `Owner?` column of the registry's two QAX tables (headers at
`:3402` and `:3457`). **12 rows, 11 distinct ids** — `OD-QAX-1` is cited twice.

| `OD-*` | Finding(s) | Registry line |
|---|---|---|
| `OD-QAX-1` | `QAX-SEC-02`; `QAX-H-01`/`QAX-H-02` | 3404, 3426 |
| `OD-QAX-2` | `QAX-SEC-01` | 3405 |
| `OD-QAX-3` | `QAX-SEC-07` | 3408 |
| `OD-QAX-4` | `QAX-PRV-01` | 3409 |
| `OD-QAX-5` | `QAX-PRV-02` | 3410 |
| `OD-QAX-6` | `QAX-COR-03` | 3414 |
| `OD-QAX-7` | `QAX-PRV-03` | 3418 |
| `OD-QAX-8` | `QAX-REG-01` | 3419 |
| `OD-QAX-9` | `QAX-SEC-08` | 3459 |
| `OD-QAX-10` | `QAX-SEC-09` | 3460 |
| `OD-QAX-11` | `QAX-BIL-01` | 3461 |

### 4.2 A consequence the direction did not anticipate — **VERIFIED**

**`OD-14` is NOT one of the 11.** It appears **nowhere** in the registry's `Owner?` column. Yet it is
one of only two ids the task queue blocks on, and it governs `F-21` and — disputed, see §5 —
`QAX-SEC-03`.

**So migrating "the 11" would not give `OD-14` a home**, and B-02/B-03 would remain unrecordable.
**Recommended, for owner decision:** initial scope = **the 11 + `OD-14`** (twelve). Raised rather than
assumed; the direction says eleven.

### 4.3 Traceability for all 74 — **VERIFIED inventory, PROPOSED retention rule**

Generated mechanically (`git grep` over `docs/`, one row per identifier). Measured:

* **74** distinct identifiers
* **11** load-bearing
* **4** carry any status marker anywhere: `OD-14` **OPEN** (`F21_BLAST_RADIUS.md:3`), `OD-38`
  **RESOLVED** (`FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:10`), `OD-QAX-1` **OPEN**
  (`QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:108`), `OD-QAX-9` **OPEN**
  (`V5_DECISION_RESOLUTION_2026-09-27.md:78`)
* **70** have **no status anywhere** — recorded as `unknown`, **never invented**

**A contradiction this surfaced — VERIFIED.** `OD-QAX-9` is marked **OPEN** at
`V5_DECISION_RESOLUTION_2026-09-27.md:78` while its answer is recorded verbatim as `D1(i)–(iii)` in
`V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` and implemented by applied migrations 132/133. The
repository asserts both. This is precisely what a `Resolves:` line prevents, and it is evidence for
B-01's direction rather than against it.

**Retention rule (PROPOSED).** For each of the 63 not migrated initially: keep `id`, `first
reference`, `occurrence count`, `files`, `status (unknown unless stated)`, and `disposition`
(`migrated` | `deferred` | `obsolete — with evidence`). **No identifier is discarded, renamed,
merged, or bulk-reclassified.** `obsolete` requires a citation, never an inference.

The full 74-row inventory is **Appendix A**.

---

## 5 · B-04 — the `Owner?` field — **BLOCKED pending an owner rule**

### 5.1 Verification of the reported claims

| Claim | Result |
|---|---|
| registry says `QAX-SEC-03` `Owner? = no` | **VERIFIED** — `:3406` |
| task ledger treats `OD-14` as blocking it | **VERIFIED** — `.skills-agent/decisions.json`, `OD-14.blocks = ["QAX-SEC-03","F-21"]` |
| no documented rule defines `Owner?` | **VERIFIED** — the string appears only as two table headers (`:3402`, `:3457`); it is never described in prose anywhere in `docs/` |

### 5.2 A **third** attribution, not previously reported — **VERIFIED**

The source document for these findings, `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md`, §12 *"All owner
decisions"* at **`:671`**, defines:

> `| OD-QAX-2 | May a coach assign plans or programs to a pending client (**SEC-01/03 fix shape**)? |`

and at **`:82`** lists `QAX-SEC-03`'s own dependency column as **`migration`** — not an `OD-*` id,
not `no`. At **`:418`**: *"`QAX-SEC-03` (the underlying policy) should be fixed in the same wave."*

**So three sources attribute QAX-SEC-03's decision dependency three different ways:**

| Source | Attribution | Standing |
|---|---|---|
| `MASTER_REMEDIATION_REGISTRY.md:3406` | **`no`** | declared authority for finding status |
| `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:671` | **`OD-QAX-2`** covers the *"SEC-01/03 fix shape"* | the source report the registry transcribes |
| `.skills-agent/decisions.json` | **`OD-14`** | **not a register** — disclaims it, and the guard refuses it as authorization |

**A coherent reading exists and is NOT asserted as fact:** the registry's `no` may be faithful to the
source — `QAX-SEC-03` needs no decision *of its own* because `OD-QAX-2` already governs the fix shape
for both SEC-01 and SEC-03. Under that reading the **task ledger is the outlier and is wrong**.

**I must disclose that the ledger entry is my own artifact.** `OD-14.blocks = ["QAX-SEC-03","F-21"]`
was authored by me in an earlier phase. It is the **least supported** of the three attributions, and
its only basis is subject-matter similarity in `F21_BLAST_RADIUS.md §6`. **It should not be relied on,
and it may need correcting rather than ruling on.**

### 5.3 Proposed rule — **PROPOSED, for owner review; deliberately not chosen to unblock work**

Answering the eight required questions:

1. **What does `Owner?` mean?** *Proposed:* "Does closing this finding require an owner **decision**
   that is not already recorded, and if so which?"
2. **Which property?** *Proposed:* **decision dependency** — not ownership, not assignment, and
   **not implementation permission**.
3. **Which document defines it?** *Proposed:* `MASTER_REMEDIATION_REGISTRY.md`, by an additive
   amendment to the §7.23 / §7.25 table preambles, which already define the evidence class and entry
   status for those tables and are the natural home.
4. **Does `no` permit implementation?** *Proposed:* **No — `no` means only that no owner decision is
   recorded as a dependency in this column.** It is **not** an authorization to implement. Wave entry,
   migration numbering (`MASTER_REMEDIATION_WAVES.md §0.2`) and `QA_CLOSURE_STANDARD.md` still govern.
   This is the consequential half of the rule, and it is the reading that does **not** unblock work.
5. **Conflicting registry vs ledger?** *Proposed:* **the registry governs**, and the ledger is a
   mirror that must be corrected to match — never the reverse. The ledger already disclaims register
   status, and the protected-path guard already refuses it as authorization, so this codifies
   existing behaviour rather than creating it.
6. **Evidence to make the `QAX-SEC-03` policy effective?** An authorized answer to whichever decision
   genuinely governs it (§5.2), an authored migration at a number taken at wave entry, its atomic
   `pending` declaration, and the `QA_CLOSURE_STANDARD.md` §2.1 ladder. **Unchanged by this rule.**
7. **Who approves, and where recorded?** The owner, in an additive amendment to the registry
   preamble — **and this depends on §1.3, which has no answer.**
8. **Coordinator behaviour while unresolved?** **Unchanged: `QAX-SEC-03` stays blocked.** Its task
   `V5-GOV-009` remains `BLOCKED_GOVERNANCE`; the decision gate stays fail-closed. Verified this run:
   queue 41 tasks, 0 eligible, ledger `authorized: []`.

**Consequences.** Under this rule `QAX-SEC-03` is **not** unblocked by `Owner? = no`; it is unblocked
only by resolving §5.2 and then obtaining the governing answer. **If the owner prefers a rule under
which `no` does permit implementation, that is a materially different and more permissive rule**, and
it should be recorded as such rather than arrived at by inference.

### 5.4 The separate decision this requires

Establishing `Owner?`'s meaning is **itself a decision** with no home (§1.3) and no row. It therefore
**depends on B-01**. B-04 cannot be recorded before B-01 is answered — unless the owner records it as
a registry amendment under the existing additive-note idiom, which is the narrower path and is
**PROPOSED** here.

---

## 6 · OD-QAX-2, OD-14, OD-QAX-9, D1(i)–(iv) kept distinct — **VERIFIED**

| Question | Answer | Basis |
|---|---|---|
| Does CR-1 answer `OD-QAX-2` or `OD-14`? | **No.** It decides only *where* an answer would live. | by construction |
| Does `OD-QAX-2` have an effective answer? | **No.** `proposed`, `owner: null`, `record: null`. | `.skills-agent/decisions.json`, re-verified |
| What does `OD-14` govern? | Programme creation authority / policy population. | `F21_BLAST_RADIUS.md §6`; `QA_TO_V5_TRANSITION_RECONCILIATION` calls it *"the policy population"* vs `OD-QAX-9` *"team semantics"* |
| Does `OD-14` apply to `QAX-SEC-03`? | **Disputed — see §5.2.** Three attributions. Not resolved here. | — |
| Does `OD-14` apply to `QAX-SEC-08`? | **Claimed once:** `QA_FINAL_RECONCILIATION_REPORT.md:336` — *"Needs OD-14 + OD-QAX-9"*. Unconfirmed elsewhere. | single source |
| Do `D1(i)–(iii)` answer `OD-QAX-9`? | **Substantively yes; formally undeclared.** `OD-QAX-9` is defined as *"What a coaching 'team' is, and how membership is consented"* (`:186`) — exactly what `D1(i)–(iii)` answer verbatim. But **`ADR-W1-001` contains 0 occurrences of `OD-QAX-9`**: the link is inferred from subject matter, never declared. | measured |
| Do they answer `OD-14`? | **No.** `D1(i)–(iii)` concern `coach_team_members` lifecycle, not programme creation. | ADR text |
| Is `D1(iv)` resolved? | **No.** *"`D1(iv)` — the permitted `role` value set — was not answered"* — `ADR-W1-001:71`. | quoted |

**Not merged, not promoted.** In particular, an answered `OD-QAX-9` does **not** authorize any
`QAX-SEC-08` implementation beyond what `D1(i)–(iii)` state, and `D1(iv)` remains open.

---

## 7 · Migration and rollback plan — **PROPOSED, not started**

| Stage | Change | Protected? | Gate |
|---|---|---|---|
| **S0** | record the §2 amendment (§2.1) **and** the approval rule (§1.3) | **yes** — `MASTER_PRODUCT_DECISIONS.md` | owner authorization; **B-01 blocks here** |
| **S1** | add `**Resolves:**` + `**Authorized:**` to `ADR-W1-001` (resolves `OD-QAX-9`); update the ADR template | **yes** — `docs/adr/` | S0 |
| **S2** | write `check-decision-provenance.mjs` (V1–V9) + its eight mutation-tested fixtures | no | S0 (schema must be fixed first) |
| **S3** | extend `authorizationIsIncomplete()` to require the record be an ADR whose `Resolves:` names the id — turning structural completeness into verified provenance, closing CR-1's standing caveat | no | S2 |
| **S4** | backfill the 11 (+`OD-14`, §4.2), one reviewable diff each | **yes** — `docs/adr/` | S1 |
| **S5** | add S2 to CI `static-guards` | **yes** — `.github/` | separate authorization (B-17) |

**Rollback.** S2/S3 are additive code: deleting the script and reverting one function restores current
behaviour. S1/S4 add lines to ADRs and **delete nothing**; rollback removes the added lines, leaving
every historical ruling byte-intact. S0 uses the additive-amendment idiom (*"nothing above
rewritten"*), so rollback is removing the amendment block. **No historical decision record is ever
rewritten or deleted at any stage** — `D1`'s and `D3`'s original text and context are preserved
exactly, in place.

---

## 8 · Appendix A — traceability inventory, all 74 identifiers

Generated mechanically; `unknown` is recorded where the repository states no status.
| `OD-*` | load-bearing | finding | status in repo | occurrences | files | first reference |
|---|---|---|---|---|---|---|
| `OD-1` | no | — | *unknown* | 6 | 3 | `docs/DESIGN_INTAKE_REPORT.md:243` |
| `OD-2` | no | — | *unknown* | 3 | 2 | `docs/DESIGN_INTAKE_REPORT.md:251` |
| `OD-3` | no | — | *unknown* | 3 | 2 | `docs/DESIGN_INTAKE_REPORT.md:256` |
| `OD-4` | no | — | *unknown* | 12 | 6 | `docs/DESIGN_INTAKE_REPORT.md:261` |
| `OD-5` | no | — | *unknown* | 4 | 2 | `docs/DESIGN_INTAKE_REPORT.md:100` |
| `OD-6` | no | — | *unknown* | 3 | 2 | `docs/DESIGN_INTAKE_REPORT.md:269` |
| `OD-7` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5896` |
| `OD-8` | no | — | *unknown* | 21 | 3 | `docs/QA_EVIDENCE.md:217` |
| `OD-9` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5898` |
| `OD-10` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2292` |
| `OD-11` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5900` |
| `OD-12` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:63` |
| `OD-13` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5883` |
| `OD-14` | no | — | **OPEN** | 33 | 12 | `docs/AUTONOMOUS_TEAM_OPERATING_MODEL.md:153` |
| `OD-15` | no | — | *unknown* | 8 | 1 | `docs/QA_EVIDENCE.md:860` |
| `OD-16` | no | — | *unknown* | 17 | 1 | `docs/QA_EVIDENCE.md:993` |
| `OD-17` | no | — | *unknown* | 5 | 1 | `docs/QA_EVIDENCE.md:1247` |
| `OD-18` | no | — | *unknown* | 6 | 1 | `docs/QA_EVIDENCE.md:1345` |
| `OD-19` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5908` |
| `OD-20` | no | — | *unknown* | 4 | 1 | `docs/QA_EVIDENCE.md:1565` |
| `OD-21` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2096` |
| `OD-22` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2280` |
| `OD-23` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2288` |
| `OD-24` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2568` |
| `OD-25` | no | — | *unknown* | 6 | 3 | `docs/QA_EVIDENCE.md:2577` |
| `OD-26` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2734` |
| `OD-27` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:2734` |
| `OD-28` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:3071` |
| `OD-29` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:3150` |
| `OD-30` | no | — | *unknown* | 31 | 8 | `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:105` |
| `OD-31` | no | — | *unknown* | 13 | 5 | `docs/MISSING_CLIENT_SCREENS.md:93` |
| `OD-32` | no | — | *unknown* | 13 | 7 | `docs/DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX.md:159` |
| `OD-33` | no | — | *unknown* | 9 | 5 | `docs/MISSING_CLIENT_SCREENS.md:54` |
| `OD-34` | no | — | *unknown* | 9 | 5 | `docs/MISSING_CLIENT_SCREENS.md:77` |
| `OD-35` | no | — | *unknown* | 13 | 5 | `docs/MISSING_CLIENT_SCREENS.md:153` |
| `OD-36` | no | — | *unknown* | 7 | 5 | `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:40` |
| `OD-37` | no | — | *unknown* | 6 | 3 | `docs/MISSING_SCREEN_SUMMARY.md:104` |
| `OD-38` | no | — | **RESOLVED** | 8 | 7 | `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:10` |
| `OD-39` | no | — | *unknown* | 4 | 3 | `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:37` |
| `OD-40` | no | — | *unknown* | 7 | 4 | `docs/FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:80` |
| `OD-41` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:4035` |
| `OD-42` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:4347` |
| `OD-43` | no | — | *unknown* | 3 | 1 | `docs/QA_EVIDENCE.md:4428` |
| `OD-44` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:4425` |
| `OD-45` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:4525` |
| `OD-46` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:4527` |
| `OD-47` | no | — | *unknown* | 1 | 1 | `docs/QA_EVIDENCE.md:4707` |
| `OD-48` | no | — | *unknown* | 4 | 1 | `docs/QA_EVIDENCE.md:4758` |
| `OD-49` | no | — | *unknown* | 1 | 1 | `docs/QA_EVIDENCE.md:4837` |
| `OD-50` | no | — | *unknown* | 1 | 1 | `docs/QA_EVIDENCE.md:4998` |
| `OD-51` | no | — | *unknown* | 5 | 2 | `docs/QA_EVIDENCE.md:5233` |
| `OD-52` | no | — | *unknown* | 2 | 1 | `docs/QA_EVIDENCE.md:5265` |
| `OD-53` | no | — | *unknown* | 1 | 1 | `docs/QA_EVIDENCE.md:5616` |
| `OD-54` | no | — | *unknown* | 2 | 2 | `docs/QA_EVIDENCE.md:5667` |
| `OD-55` | no | — | *unknown* | 1 | 1 | `docs/QA_EVIDENCE.md:5701` |
| `OD-56` | no | — | *unknown* | 13 | 4 | `docs/QA_EVIDENCE.md:5748` |
| `OD-57` | no | — | *unknown* | 20 | 6 | `docs/QA_MASTER_FINDINGS_LEDGER.md:201` |
| `OD-58` | no | — | *unknown* | 20 | 7 | `docs/QA_COMPLETION_REPORT_2026-09-27.md:442` |
| `OD-59` | no | — | *unknown* | 13 | 5 | `docs/QA_MASTER_FINDINGS_LEDGER.md:201` |
| `OD-60` | no | — | *unknown* | 16 | 4 | `docs/QA_CORRECTION_RIGHTS_EXHAUSTION_REPORT.md:88` |
| `OD-61` | no | — | *unknown* | 7 | 3 | `docs/QA_MASTER_FINDINGS_LEDGER.md:204` |
| `OD-62` | no | — | *unknown* | 2 | 2 | `docs/QA_MASTER_FINDINGS_LEDGER.md:205` |
| `OD-QAX-1` | **yes** | QAX-SEC-02 | **OPEN** | 12 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3404` |
| `OD-QAX-2` | **yes** | QAX-SEC-01 | *unknown* | 8 | 3 | `docs/AUTONOMOUS_TEAM_OPERATING_MODEL.md:44` |
| `OD-QAX-3` | **yes** | QAX-SEC-07 | *unknown* | 5 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3408` |
| `OD-QAX-4` | **yes** | QAX-PRV-01 | *unknown* | 3 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3409` |
| `OD-QAX-5` | **yes** | QAX-PRV-02 | *unknown* | 3 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3410` |
| `OD-QAX-6` | **yes** | QAX-COR-03 | *unknown* | 4 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3414` |
| `OD-QAX-7` | **yes** | QAX-PRV-03 | *unknown* | 4 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3418` |
| `OD-QAX-8` | **yes** | QAX-REG-01 | *unknown* | 4 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3419` |
| `OD-QAX-9` | **yes** | QAX-SEC-08 | **OPEN** | 15 | 10 | `docs/MASTER_REMEDIATION_REGISTRY.md:3459` |
| `OD-QAX-10` | **yes** | QAX-SEC-09 | *unknown* | 3 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3460` |
| `OD-QAX-11` | **yes** | QAX-BIL-01 | *unknown* | 3 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3461` |
| `OD-QAX-12` | no | — | *unknown* | 4 | 2 | `docs/MASTER_REMEDIATION_REGISTRY.md:3474` |
