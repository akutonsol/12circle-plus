# V5 autonomous phase — governance findings and owner decision requests
**2026-10-21 · branch `feat/v5-autonomous-team` · HEAD `08b3543` · uncommitted**

**This is a REQUEST AND ANALYSIS document. It is not a register and it decides nothing.**
`MASTER_PRODUCT_DECISIONS.md`, `decision-log.md` and `docs/adr/` are authoritative for owner
decisions; `MASTER_REMEDIATION_REGISTRY.md` is authoritative for finding status;
`QA_CLOSURE_STANDARD.md` governs every status change. No protected register was edited to
produce this document, and nothing here promotes any decision to an authorized state.

Every count below was measured by command on the stated file at the stated HEAD, not asserted.

---

## 1 · CR-1 — where an `OD-*` answer can be recorded. **Resolved as a structural gap.**

The prior statement of CR-1 was *"no `ANSWERED` mechanism for `OD-*`"*. That is not quite right,
and the correction matters because it changes what the owner has to do.

The mechanism exists and is well defined. `MASTER_PRODUCT_DECISIONS.md` carries **7** `ANSWERED`
markers in the form

> `✅ ANSWERED <date> · option (x) · owner: <who>` *(record: decision-log.md; registry §N)*

and its own procedure at `:286` says: *"Update this document's row to `ANSWERED` with the date
and the owner."*

The gap is that **there is no row to update.** Measured in that file:

| | count |
|---|---|
| `PD-A*` decision rows | **26** |
| `OD-*` decision rows | **0** |
| occurrences of `OD-QAX-2` | **0** |
| occurrences of `OD-14` | **0** |

`OD-*` is a QA-era identifier namespace that was never migrated into the register. So the
documented procedure cannot be followed for either decision: it presupposes a row that does not
exist. `ADR-W1-001` shows the alternative precedent — a machine-readable `**Status:** ACCEPTED
(owner decisions supplied 2026-09-27)` line — but it names no `OD-*` id anywhere, so it cannot
be used to trace one either.

**Human action (smallest).** Choose ONE home for `OD-*` answers and say so once:

* **(a)** mint `PD-A27`/`PD-A28` rows in `MASTER_PRODUCT_DECISIONS.md` that carry the `OD-QAX-2`
  and `OD-14` questions, then answer them by the existing documented procedure; or
* **(b)** declare `docs/adr/` the home for `OD-*` answers and require each ADR to name the
  `OD-*` ids it resolves, so the link is machine-checkable; or
* **(c)** declare `decision-log.md` the home and adopt a fixed line format carrying the id.

All three touch protected files, so all three need explicit authorization. Until one is chosen,
`authorizationIsIncomplete()` can only check that a record **exists, is a regular file and is
non-empty** — it cannot check that the file answers the question. That limit is deliberate and is
commented in `scripts/skills-agent-coordinator.mjs`; option (b) is the only one of the three that
would make it mechanically checkable.

---

## 2 · CR-2 — *"all ten N-05 decisions"* does not resolve. **Flagged, not resolved.**

The standing constraint preserves *"all ten N-05 decisions"*. Measured across `docs/`, `N-05`
resolves to **one finding id, not a set of ten decisions**:

* `MASTER_REMEDIATION_REGISTRY.md:204` records `N-05` as an **alias collapse**:
  `LRE-02 = REL-18 = K-ENV-1 = OBS-4-R4 = N-05`.
* `:603` gives that finding's status: **`LRE-02` · P0 · `VERIFIED_CLOSED` 2026-08-26**, Wave 1 —
  three production-targeting test harnesses, closed by a `tool/qa_target.dart` allowlist refusal.
* `N-05` also appears in `QA_WORKSTREAM_N_TEST_COVERAGE_REPORT.md` (8 occurrences), which is
  where the id originates — a **test-coverage** workstream finding.

So `N-05` is a single, closed P0 finding about test harnesses targeting production. **No set of
ten decisions bearing that id exists in the repository.**

**On the 113–122 relationship, named in the brief as a known ambiguity.** There is no documented
relationship between `N-05`/`LRE-02` and migrations 113–122. The nearest thing is `PD-A26`, which
requires *"reverse scripts for 113–128, rehearsed on a QA clone"* — a different range and a
different subject (PITR and rollback blast radius, not test harnesses).

**This is flagged and deliberately left unresolved.** The constraint is preserved as written and
treated as binding; it simply cannot be traced to ten decisions, and guessing which ten were meant
would manufacture authority. **Human action:** state what *"the ten N-05 decisions"* refers to, or
replace the phrase with the ids actually intended.

---

## 3 · A material source-of-truth conflict: is `QAX-SEC-03` governed by `OD-14`?

Two documents disagree, and this one is **not** reconciled here.

| Source | Says |
|---|---|
| `MASTER_REMEDIATION_REGISTRY.md:3406` (§7.23, column **`Owner?`**) | `QAX-SEC-03` · P1 · Authorization · **`no`** — i.e. no owner decision required |
| `.skills-agent/decisions.json` | `OD-14.blocks = ["QAX-SEC-03", "F-21"]` |

The registry is the declared authority for *"remediation scope and finding status"*. The decision
ledger is explicitly **not** a governance register — it says so in its own header and the guard
refuses to treat it as authorization. So on the face of it the registry governs and `QAX-SEC-03`
needs no owner decision.

Against that: `F21_BLAST_RADIUS.md §6` states that `OD-14` is *"the decision that is actually
needed"*, and the finding it discusses — self-asserted `coach_id = auth.uid()` write arms — is the
**same subject matter** as `QAX-SEC-03`. Both readings are defensible:

* the policy **defect** is implementable without a product decision (registry: `Owner? = no`), but
* the **authorization model** the corrected policy should express is a product question (`OD-14`).

**Consequence if resolved the registry's way:** `QAX-SEC-03` becomes implementable now, and the
queue's `V5-SEC-OD14` blocker is wrong. **If resolved the ledger's way:** the registry row needs an
`Owner?` correction, which is a protected-file edit.

**Human action:** state which source governs `QAX-SEC-03`. Do not let the two drift.
Recorded on the queue as **`V5-GOV-009` · `BLOCKED_GOVERNANCE`**.

---

## 4 · `OD-14` is framed two different ways, under one id

| Source | `OD-14` is… |
|---|---|
| `F21_BLAST_RADIUS.md §6` | **programme creation authority** — who may create a programme; is `is_coach_profile()` sufficient; what happens to non-conforming rows |
| `QA_TO_V5_TRANSITION_RECONCILIATION_2026-09-27.md` | **"the policy population"**, with **`OD-QAX-9`** separately being **"team semantics"** |
| `V5_DECISION_RESOLUTION_2026-09-27.md:78` (row `D1`) | **"Team semantics; who may create a membership"**, citing *both* `QA OD-14/OD-QAX-9` |

The ledger follows the first framing, which two of the three sources support. Row `D1` conflates
`OD-14` with `OD-QAX-9`; because it cites both ids it is imprecise rather than contradictory, so no
correction is proposed here. It is recorded so that an answer written against one framing is not
later read as answering the other.

`D1`'s status in that table is **`OPEN`** with no owner answer, which **corroborates** the ledger's
`proposed` state. Nothing in the repository answers `OD-14`.

---

## 5 · The decision ledger mirrors 2 of the 4 `OD-*` ids the registry actually depends on

From `MASTER_REMEDIATION_REGISTRY.md` §7.23 / §7.25, column `Owner?`:

| Finding | Registry says | In `.skills-agent/decisions.json`? |
|---|---|---|
| `QAX-SEC-01` | `OD-QAX-2` | **yes** — `proposed` |
| `QAX-SEC-02` | `OD-QAX-1` | **no** |
| `QAX-SEC-03` | `no` | — (see §3) |
| `QAX-SEC-08` | `OD-QAX-9` | **no** |

This is **not** currently a safety hole: the gate is fail-closed, so an absent id keeps the veto,
and `V5-EVD-SEC02` / `V5-EVD-SEC08` carry ordinary `kind: owner` blockers that veto them anyway.
It is a completeness gap — the mirror does not show the owner every decision the registry says is
load-bearing.

**Proposed, additive, non-authorizing:** add `OD-QAX-1` and `OD-QAX-9` to the ledger in state
`proposed`, `owner: null`, `record: null`. This grants nothing — `proposed` vetoes — and makes the
mirror complete. Not done in this phase: it is a change to the decision ledger, and §5 of the brief
forbids turning proposed intent into effective authorization. Listed here for one-line approval.

---

## 6 · Decision request — `OD-QAX-2`

**Question.** May a coach assign plans or programs to a `pending` client?
**Blocks.** `QAX-SEC-01` (P0, security regression by remediation, `assign_nutrition_plan` in 131).
**Proposed answer (not authorized).** Option A — an active `coach_client_relationships` row is
required.

**Evidence already available.** Migration 113's consent model permits a coach to open only a
`pending` invite and lets only the client cause `active`; its table COMMENT says *never grant a
write path that lets one party name the other without consent*. A conflict check against the
protected decisions on 2026-10-20 found no conflict. `is_active_coach_of(uuid)` (migration 100)
already supplies the predicate, so the mechanism is free.

**Consequences.** Option A refuses assignment to `pending` clients, which is a behaviour change for
any flow that assigns before acceptance. The alternative (a narrowed Option B permitting assignment
to `pending` but not to `cancelled`/former) keeps that flow and accepts a weaker consent model.

**Exact human action.** (1) Resolve **CR-1** by naming where the answer is recorded. (2) Answer
`OD-QAX-2` with an option and supply **CR-3**'s date and owner. (3) Resolve the five open scope
questions `Q-A1`–`Q-A5` (direction/identity, status domain, error semantics, whether the direct RLS
policy path is in scope, fixtures) — these change the migration's shape, so answering the headline
question alone is not enough to start.

---

## 7 · Decision request — `OD-14`

**Question.** Programme creation authority: who may create a programme; is `is_coach_profile()`
sufficient or is an active `coach_client_relationships` row required; and what happens to existing
non-conforming rows?
**Blocks.** `F-21`, and — **disputed, see §3** — `QAX-SEC-03`.
**Proposed answer (not authorized).** Only an active-relationship coach may create; an active row is
required; existing non-conforming rows are **quarantined pending review, not mutated**.

**Evidence already available.** `F21_BLAST_RADIUS.md §6` states the mechanism is free because
migration 113 supplies both the helper and the pattern, and that the remaining question is a product
question about the relationship model. `ADR-W1-001` is partial overlap only: it names none of the
six `QAX-SEC-03` tables and lists `SEC-PHI-9/10` out of scope. Row `D1` of
`V5_DECISION_RESOLUTION_2026-09-27.md` records the question as `OPEN` with no owner answer.

**Consequences.** The quarantine arm is the load-bearing part: it determines whether legitimate
production data written before the tightening keeps working, is hidden, or is migrated. There may be
real production rows in that state, and no option can be chosen without deciding who reviews them.

**Exact human action.** (1) Resolve **CR-1**. (2) Answer the three sub-questions and supply **CR-3**'s
date and owner. (3) Resolve **CR-4** — does sub-question 1 bind programme *creation*, and is
`coach_video_responses` in scope. (4) Resolve **CR-5** — which quarantine option (`Q-1`/`Q-2`/`Q-3`)
and **who holds reviewer authority** (`Q-B5`). (5) Settle §3, since it decides whether `QAX-SEC-03`
is inside this decision at all.

---

## 8 · What this phase did NOT do

* No protected register, migration, or manifest was edited. No migration was applied.
* No decision was promoted. `OD-QAX-2` and `OD-14` remain `proposed`, `owner: null`, `record: null`.
* No finding status was changed. `QAX-SEC-01/02/03/08` keep their registry statuses.
* `CR-3`, `CR-4`, `CR-5` are unchanged and unanswerable from repository evidence: `CR-3` needs a date
  and an owner that only the owner can supply; `CR-4` and `CR-5` are product questions.

---
---

# Continuation, same day — CR-1 decision request, CR-2 conflict record, security classification

Added after the first part of this document. The first part said *"`OD-*` has no home."* That was
measured but incomplete, and the correction below changes the shape of the CR-1 decision. Everything
here was measured by command at HEAD `08b3543`.

## 9 · CR-1, corrected: three homes already exist, and three of the four are unprotected

The premise of §1 was that no mechanism records an `OD-*` answer. Measured more widely, the truth is
different and more awkward: **owner decisions are already recorded verbatim in four documents, and
applied migrations already cite them as their authority.** What does not exist is a single home, an
id that survives the journey, or protection on most of the files involved.

| Document | Carries | Cited by | Protected? |
|---|---|---|---|
| `V5_PROGRAMME_DEFINITION.md` §19.1 (`:3043`) | **`D3` — ANSWERED: YES, UNIFORMLY** verbatim | migration **136** | **no** |
| `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` | **`D1(i)/(ii)/(iii)`** verbatim; self-described *"Decision record + authorization"* | migrations **132**, **133** | **no** |
| `V5_SECURITY_FOUNDATION_WAVE1_FINAL_REPORT.md` | `D1(i)` verbatim — **a second copy** | — | **no** |
| `docs/adr/ADR-W1-001` | `D1(i)/(ii)/(iii)` verbatim — **a third copy** | migrations 132, 133 | **yes** |
| `MASTER_PRODUCT_DECISIONS.md` | 26 `PD-A*` rows, 7 `ANSWERED`, **0 `OD-*`** | — | **yes** |
| `decision-log.md` | `\| Date \| Decision \| Why \|` — **no id column, no status** | `PD-A13`'s record | **yes** |

Four consequences, each measured:

1. **The id does not survive.** A question escalated as `OD-QAX-9` was answered as `D1`. `ADR-W1-001`
   contains **0** occurrences of any `OD-*` id. Nothing mechanical connects the escalation to its
   answer; only prose in a third document does.
2. **`OD-*` is not a register namespace.** **74 distinct `OD-*` ids** exist across `docs/`, almost all
   as inline escalation markers in QA-era reports — `QA_EVIDENCE.md` alone has **182** mentions. There
   is **no file anywhere** that lists `OD-*` ids with a status, and a search for an `OD-*` id beside
   `ANSWERED`/`RESOLVED`/`OPEN` returns **nothing**. Of the 74, the registry names **11** as
   load-bearing owner dependencies (`OD-QAX-1` … `OD-QAX-11`); the queue references **2**.
3. **Duplicated authority already exists.** `D1`'s verbatim ruling sits in three documents. Two can
   be edited without the protected-path guard noticing.
4. **The guard protects the wrong set.** `MASTER_PRODUCT_DECISIONS.md` and `decision-log.md` are
   protected and carry **no live `OD-*` authority**; the three documents that *are* cited by applied
   migrations as authority are **unprotected**. See §13.

### The decision requested

Pick one home for an `OD-*` answer. Measured against the dimensions asked for:

| | **A** — new `PD-A*` rows mapping to `OD-*` | **B** — `docs/adr/`, each ADR naming its `OD-*` ids | **C** — `decision-log.md` with a machine-checkable format |
|---|---|---|---|
| **Authoritative ownership** | Strongest on paper: the file declares itself the authority for *"every unresolved decision… deduplicated and owned"*, and carries an `owner:` field per row | Good, with precedent: ADRs are already what migrations 132/133 cite | Weak: the file calls itself *"a concise record… not a changelog"*, with no ownership field |
| **Traceability `OD-*` → answer** | Indirect — needs a mapping column, and `OD-*` ids would live in two namespaces at once | **Direct**, if each ADR names the ids it resolves. Fixes the exact break in (1) | Direct only after adding an id column that does not exist |
| **Machine validation** | Feasible: rows are pipe-tables with a fixed `ANSWERED` idiom already used 7× | **Feasible and cheapest**: `ADR-W1-001` already has a parseable `**Status:** ACCEPTED` line; add a `**Resolves:**` line and the check is two greps | Feasible only after a format change; the current 3-column table cannot express it |
| **Compatibility with existing records** | Good for `PD-A*`; **ignores** the three documents that already hold live rulings | **Good** — formalises what 132/133 already do | Poor — `PD-A13` cites it as a *record* today, so the format change touches a live citation |
| **Protected-file changes** | `MASTER_PRODUCT_DECISIONS.md` (protected) | `docs/adr/` (protected) + protect the authorization docs | `decision-log.md` (protected) + a format change |
| **Migration path** | Up to **74** ids to mint, or an explicit scope limit to the **11** load-bearing ones | **2 documents to amend** (`ADR-W1-001` gains a `Resolves:` line; new ADRs follow), and the scope question is still open | Every existing decision re-expressed in a new format |
| **Conflict / duplication risk** | **Raises it**: a third namespace alongside `PD-A*` and `D*`, with `OD-*` ids still in prose | **Lowers it**: one ADR per decision, the pattern migrations already trust | Raises it: `decision-log.md` would hold answers that ADRs also hold |

**Recommendation, not a selection.** **Option B** is technically strongest on this evidence: it is the
only option that fixes the traceability break in (1) rather than adding a namespace to it, it is
already the authority applied migrations cite, its machine check is the smallest, and its migration
path is two documents rather than 74 rows. **The owner must still choose.** Nothing here is
implemented, no decision status changed, and no authorization home was created.

**A second question the owner must answer either way:** does the chosen home cover **all 74** `OD-*`
ids, only the **11** the registry names as load-bearing, or only the **2** currently blocking queued
work? The migration path differs by more than an order of magnitude between those answers, and it
cannot be inferred.

**Also required under any option — `CR-3`:** the date and the owner. No option supplies them.

---

## 10 · CR-2 — conflict record. Not reconciled.

**The exact standing instruction.** *"Preserve PD-A02, PD-A12, PD-A13, PD-A14, PD-A19, OD-40, and all
ten N-05 decisions as standing user constraints."* And, from the current brief: *"The N-05 wording has
a known ambiguity concerning its relationship to migrations 113–122. Flag the ambiguity wherever
relevant; do not silently resolve it."*

**The exact repository evidence.**

* `MASTER_REMEDIATION_REGISTRY.md:204` records `N-05` inside a list of **alias collapses**:
  `LRE-02 ↔ REL-18 ↔ K-ENV-1 ↔ OBS-4-R4 ↔ N-05`, annotated *"recorded, individually unremarkable"*.
* `:603` gives that finding's status: **`LRE-02` · P0 · `VERIFIED_CLOSED` 2026-08-26**, Wave 1 —
  *"shared `tool/qa_target.dart` allowlist refusal, no defaults"*, three production-targeting test
  harnesses.
* `N-05` originates in `QA_WORKSTREAM_N_TEST_COVERAGE_REPORT.md` (**8** occurrences) — a
  **test-coverage** workstream.
* Searching `docs/` for `N-05` returns **9 files**; none presents it as a set, none numbers it, and
  **none associates it with migrations 113–122**.

**What cannot be reconciled.** The instruction treats `N-05` as **ten decisions**. The repository
records it as **one finding**, closed, about test harnesses — a different kind of object (a finding,
not a decision), a different cardinality (one, not ten), and a different subject (test targeting, not
migrations). The nearest thing touching 113–122 is `PD-A26`, which requires *"reverse scripts for
113–128, rehearsed on a QA clone"* — a different range and a different subject (PITR and rollback
blast radius). **No mapping from the instruction to the evidence exists, and constructing one would
invent authority.** The ten are therefore preserved as written and treated as binding, while being
untraceable.

**The minimum clarification required.** One of:
(a) the ten ids actually intended, listed; or
(b) the document that contains the ten, named; or
(c) confirmation that `N-05` means the single closed finding `LRE-02`, in which case the word *"ten"*
should be withdrawn; **and** (d) what relationship to migrations 113–122 was intended, if any.

**Nothing was modified to resolve this.** No protected decision file was touched and no migration
authorization was altered.

---

## 11 · Security findings, classified by what actually blocks them

The decisive evidence is that **three of these four defects already have landed, applied
remediations**, recorded under `D*` ids rather than their `OD-*` ids. The registry rows still read as
though nothing had happened, because nothing re-statused them.

### `QAX-SEC-02` — **code defect: FIXED and APPLIED. Blocker is registration, not governance.**

Registry `:3404` shows it P0 with `Owner? = OD-QAX-1`, as if unremediated.
Measured: **migration 136** (`136_uniform_active_relationship_predicate.sql`) drops and recreates
*"coach reads client progress photos"* on `storage.objects` for `bucket_id = 'progress-photos'`,
under *"owner decision `D3`, recorded verbatim in `docs/V5_PROGRAMME_DEFINITION.md` section 19.1 —
`D3` — ANSWERED: YES, UNIFORMLY, via (b) the `is_active_coach_of(text)` overload."* Its own header
names the defect as **`029_progress_photos_storage_rls.sql:41 NO STATUS ← SEC-PHI-9`** — the same
policy, the same line, the same missing status check that `QAX-SEC-02` describes. Frontier is **181**,
so 136 is **applied**.
**Therefore:** `QAX-SEC-02` and `SEC-PHI-9` are the same defect under two ids, and it is fixed in code
and applied. `OD-QAX-1` — *"Is 'coach' (and 'vendor') a self-service role?"* — is a **broader standing
question** (it also governs `QAX-H-01/02`), not the thing that blocked this policy fix.
**Remaining to close:** an id reconciliation (`QAX-SEC-02` ≡ `SEC-PHI-9`), and the closure-ladder
evidence `QA_CLOSURE_STANDARD.md` §2.1 demands for a security finding. **Status not changed here.**

### `QAX-SEC-08` — **code defect: FIXED and APPLIED. Its owner decision WAS supplied.**

Registry `:3459` shows it P0 with `Owner? = OD-QAX-9`.
Measured: `OD-QAX-9` is defined as *"What a coaching 'team' is, and how membership is consented"*
(`QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:186`). That is precisely what **`D1(i)/(ii)/(iii)`** answer,
verbatim, dated **2026-09-27**, in `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` — *"Membership must
not be created unilaterally by a team lead… only become active after the required acceptance/consent
step"*, the four states, and the non-PHI column limit. Implemented by **migrations 132 and 133**, both
**applied**, both citing that document and `ADR-W1-001` as their authority.
**Therefore:** the decision `OD-QAX-9` asks for has been supplied and executed. The `Owner?` column is
stale.
**Genuinely still open:** `ADR-W1-001` records that **`D1(iv)` — the permitted `role` value set — was
not answered**; and `QA_FINAL_RECONCILIATION_REPORT.md:336` states `QAX-SEC-08` *"needs OD-14 **and**
OD-QAX-9"*, so if that second dependency is real, `OD-14` still gates part of it. **Status not
changed here.**

### `QAX-SEC-01` — **genuinely blocked on `OD-QAX-2`. No migration exists.**

Registry `:3405`, P0, `Owner? = OD-QAX-2`. Measured: **no migration above 131 touches
`assign_nutrition_plan`**; the only match is **131** itself, which is the migration that *introduced*
the regression. No authored fix exists.
**Therefore:** a real code defect, unimplemented, correctly blocked. `OD-QAX-2` is unanswered, and its
five scope questions `Q-A1`–`Q-A5` change the migration's shape, so the headline answer alone is
insufficient to start. Queue: `V5-SEC-ODQ2`, `BLOCKED_OWNER`.

### `QAX-SEC-03` — **genuinely unimplemented; its governance status is the §3 conflict.**

Registry `:3406`, P1, `Owner? = **no**`. Measured: **no migration mentions `QAX-SEC-03`**, and none of
the six named tables' self-asserted `coach_id = auth.uid()` write arms has an authored fix above 131.
**Therefore:** unimplemented. Whether it may proceed now turns entirely on §3 — the registry says no
owner decision is needed; the ledger says `OD-14` blocks it. **If the registry governs, this is the
one P1 that could be implemented without any further decision**, and that is the single highest-value
thing an owner ruling would unlock here. Queue: `V5-GOV-009`, `BLOCKED_GOVERNANCE`.

### Implementation plan and regression criteria for the blocked pair

Prepared so that an answer can be executed immediately, and **not** implemented.

**`QAX-SEC-01`** — guard inside the definer function, before the supersede `UPDATE`; mechanism is
`is_active_coach_of()` from migration 100, pattern from 113. Regression criteria: an unrelated caller
is refused `42501` and the victim's active plan is unchanged; a coach-created `pending` row does not
authorize; `cancelled` does not authorize; an active coach still assigns (positive control);
`search_path`, grants and `COMMENT` preserved per the Function Replacement Rule (CRC-07 / I-MIG-03 —
`CREATE OR REPLACE` preserves ACL and owner but **not** `proconfig` or body). Verification:
`check-function-posture`, `check:guards`, `check-migration-manifest`.
**`QAX-SEC-03`** — per-command policies replacing the self-asserted arms on the six tables, the
hardened idiom `coach_client_relationships` already uses. Regression criteria: for each of the six
tables, a coach with no active relationship cannot insert or update a row naming a victim; an active
coach can; the victim's existing rows cannot be blanked or hijacked; notification side effects do not
fire for an unauthorized write.
**Both** take the next contiguous migration number at wave entry per `MASTER_REMEDIATION_WAVES.md`
§0.2 — **not** chosen in advance — and enter `expected_applied.json` as `pending` with a reason and a
gate, in the same atomic change.

---

## 12 · The Bash exposure, reassessed against CR-1

The analysis in `AUTONOMOUS_TEAM_OPERATING_MODEL.md` stands unchanged and is not restated. One thing
changes: §9 sharpens what the proposed CI gate's **authorization marker** would have to be.

The marker must name an authorizing record, and the gate must be able to resolve it. Under **option B**
that is mechanically checkable — an ADR path plus the `OD-*` id it declares it resolves, both greppable.
Under **A** or **C** the marker can only be a pointer into a prose table, which the gate cannot
validate without the format change each option requires.

So the dependency is precise: **the CI gate cannot be specified, let alone implemented, until CR-1 is
answered**, because the marker's grammar is a consequence of the choice. Two further approvals are
needed beyond CR-1 — adding a **required** CI gate changes what can merge, and protecting the
authorization documents (§13) changes what the guard refuses. Neither is taken here. No
`permissions.deny` rule was added and shell access was not restricted.

---

## 13 · New finding — the guard protects decision documents that carry no live authority, and not the ones that do

Measured with the guard itself:

| Document | Carries live owner authority cited by an applied migration? | Guard verdict |
|---|---|---|
| `V5_PROGRAMME_DEFINITION.md` §19.1 (`D3` → migration 136) | **yes** | **unprotected** |
| `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` (`D1` → 132, 133) | **yes** | **unprotected** |
| `V5_SECURITY_FOUNDATION_WAVE1_FINAL_REPORT.md` (`D1`, second copy) | duplicate of the above | **unprotected** |
| `docs/adr/ADR-W1-001` (`D1`, third copy) | yes | protected |
| `MASTER_PRODUCT_DECISIONS.md` | no `OD-*` authority at all | protected |
| `decision-log.md` | no id column | protected |

The guard's eleven roots were chosen from the documents that *declare* themselves authoritative. The
documents that applied migrations actually *cite* as their authority were not among them. A tool-layer
write could therefore alter the recorded text of a live owner ruling — `D1(i)` or `D3` — without the
guard objecting, in two of the three places it is recorded.

**Not changed here.** Adding roots to `scripts/protected-paths.json` widens what the guard refuses,
which is exactly the kind of change its own design says must be a reviewable, authorized diff — and
the self-test's `EXPECTED_ROOTS` list must be amended in the same commit or the suite fails, which is
the intended friction. Proposed for approval: add the two unprotected authorization documents. The
third (`FINAL_REPORT`) is a report, and the better fix for it may be removing the duplicate rather
than protecting it — which is itself an owner call, since all three copies are currently cited.

### §11 precision note — how "no authored fix" was measured

The claim is easy to get wrong with a glob: `supabase/migrations/1[3-8][0-9]_*.sql` **matches 131
itself**, which is the migration that introduced `QAX-SEC-01`. Re-measured by parsing each version
number and comparing numerically:

* **`assign_nutrition_plan`** — **0** migrations strictly above 131 touch it. 131's own `COMMENT`
  states the defect in its own words: *"Deliberately not stricter than that policy — 3A-11 does not
  change who may write."*
* **`QAX-SEC-03`'s six tables** — `client_habits`, `action_items`, `coach_video_responses` and
  `client_nutrition_plans` are touched by **0** migrations above 131. `coaching_calls` appears in
  **2** (132 and 134) and `workout_program_assignments` in **1** (175), but **none is a policy fix for
  a self-asserted write arm**: 132 and 134 reference `coaching_calls` inside an unrelated `EXISTS`
  subquery on the notification path, and 175 reads `workout_program_assignments` for weekly-feedback
  subject integrity.
* **Migration 136 is not a partial fix for either.** Its own population statement enumerates five
  inline relationship-consuming predicates and names the two it corrects — `029_progress_photos
  _storage_rls.sql:41` (**SEC-PHI-9**) and `035_scoring_engine.sql:184` (**SEC-PHI-10**) — both
  **read** predicates. It changes no write arm.

`QAX-SEC-01` and `QAX-SEC-03` are therefore unremediated in code, and `QAX-SEC-02`'s read defect is
remediated and applied. That asymmetry is the whole of the classification in §11.

### Correction to this phase's own verification record

`V5-SEC-PLAN`'s verification note recorded the wave-numbering rule as *"confirmed"* on a
case-sensitive `grep` that returned **0**. The rule does exist — `MASTER_REMEDIATION_WAVES.md:82`
reads `| **132+** | 4+ | Assigned at wave entry, never before |`, with `:91` adding *"The numbers are
not chosen"* — so the substance of the citation holds, but it was recorded as verified on a check
that had printed zero. Noted here because a verification record that overstates what a command
returned is the same class of defect as the inert self-test assertions found earlier, and should be
corrected in the record rather than quietly re-measured.

---

## 14 · Correction to §9 — one `OD-*` id *does* carry a status, and it proves the point rather than refuting it

§9 said *"there is no file anywhere that lists `OD-*` ids with a status, and a search for an `OD-*` id
beside `ANSWERED`/`RESOLVED`/`OPEN` returns nothing."* **The second half of that is wrong.** Measured
again, four documents carry such a line, all for the same id:

| Location | Form |
|---|---|
| `FINAL_NEW_SCREEN_DESIGN_COMMISSION.md:10` | `## 0 · OD-38 — RESOLVED` (a markdown heading) |
| `FINAL_SCREEN_INVENTORY.md:6` | `## 0 · OD-38 — RESOLVED` (the same heading, duplicated) |
| `FUTURE_SCREEN_CAPABILITIES.md:16` | a table row: `**OD-38** … **RESOLVED** — 110/110 regenerated` |
| `QA_EVIDENCE.md:5942` | second-hand: `OD-38 … **marked RESOLVED** in that document` |

So **1 of 74** `OD-*` ids has a status marker. It does not change the recommendation, and it sharpens
why the decision is needed:

* The form is an **ad-hoc markdown heading**, not a row in any register. Nothing parses it.
* It records **no owner, no date, and no option chosen** — so it satisfies none of what
  `authorizationIsIncomplete()` requires, and could not authorize a gated task even if the ledger
  named it.
* It is **duplicated across three documents plus one second-hand mention**, the same
  divergence-by-copying already measured for `D1` in §9.
* All four files are **unprotected**.

`OD-38` is therefore a precedent for the problem, not a solution: it shows that when someone needed
to mark an `OD-*` resolved, no mechanism existed, so they wrote a heading. Every option in §9's table
is still open; nothing here selects one.

## 15 · Workstream E — migration integrity rests on git alone

Measured: **no migration checksum or lock register exists.** The only `.lock` file in the repository
is `apps/mobile/pubspec.lock`. An earlier search appeared to find one, but
`174_admin_release_status_authorized_shape.sql` had merely matched the pattern `sha` inside the word
*shape* — a false positive, corrected here.

Integrity therefore rests on git blob identity:

* **182** — blob `e0ed4ac6eb59`, unmodified in the working tree
* **183** — blob `b0b9a30da3ba`, unmodified in the working tree
* frontier **181**, `excluded: []`, **184** authored files, every above-frontier version declared in
  exactly one bucket, every declaration backed by a file

This is coherent and sufficient **while history is never rewritten**, which is a standing constraint.
It is worth stating that no repo-local check would detect a migration's content changing under a
force-push, because the manifest records *which* versions are expected, not *what they contain*.
Adding a content register is **not** proposed: it would duplicate what git already guarantees under
the no-rewrite rule, and a second source of truth for migration content is exactly the kind of
duplication §9 is about.

**Evidence required before 182 or 183 may be applied** — neither is satisfied:

* **182** — owner approval of the Option A access trade-off (content managers retain cross-owner
  private/draft certification visibility), then a QA apply window.
* **183** — review of the guard's placement in the engine rather than the 124 wrapper, **plus** a
  decision on the separate canonicalizer/validator defect that currently makes any non-empty
  materialization fail with `23514` and so blocks 183's positive control (**PD-A01**), then a QA
  apply window.

Both gates are recorded in `expected_applied.json` and neither was altered. **No offline check is
missing for these two.** What is missing is live evidence, which is prohibited here: the closure
ladder's *FIXED ON QA* and *VERIFIED LIVE* rungs cannot be reached from this environment at all.
