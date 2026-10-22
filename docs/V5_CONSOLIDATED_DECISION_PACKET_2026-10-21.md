# V5 · Consolidated blocker and decision packet
**2026-10-21 · branch `feat/v5-autonomous-team` · HEAD `08b3543` · written at that HEAD; since MERGED to `main` (PR #1, merge commit `d57dfa8`)**

**This document decides nothing.** It consolidates every blocker found across the autonomous phases
into one prioritised set. Authoritative records remain `MASTER_PRODUCT_DECISIONS.md`,
`decision-log.md`, `docs/adr/` (owner decisions), `MASTER_REMEDIATION_REGISTRY.md` (finding status),
`MASTER_REMEDIATION_WAVES.md` (sequencing), `RELEASE_GATES.md` (gates) and `QA_CLOSURE_STANDARD.md`
(closure evidence). No protected file was changed to produce it.

**Queue at the time of writing:** 41 tasks — **16 VERIFIED**, 18 `BLOCKED_OWNER`,
5 `BLOCKED_GOVERNANCE`, 2 `BLOCKED_EXTERNAL`, **0 eligible**. **No authorized implementation work
remains.** Everything below is prepared to resume on an answer.

## State update — later the same day (2026-10-21)

Written after the packet below, and **in addition to it, not instead of it**. Everything under this
heading was verified by command; the packet's own claims are left as written except where a header or
a retraction says otherwise.

* **The trunk exists.** PR #2 (555 commits) and PR #1 (65 commits) were merged to `main` with merge
  commits, so no history was rewritten. `main` is no longer frozen at `9dc7515`; CI on `main` was
  green on all 7 jobs at `d57dfa8`. The "0 merged PRs" figures below describe the repository *before*
  that date.
* **B-12 is retracted** (see its own entry): Helix's CI billing is not this repository's. CI works here.
* **The progress metric was decided** (findings §16): FIT interaction coverage is demoted, and six
  repository-derivable metrics replace it. **B-18 (`state.json` does not survive a clone) is mitigated for
  reporting only** — a fresh clone now derives blocked statuses from `tasks.json` — but completion is
  still not recoverable from the repository.
* **The check-in cluster was confirmed and built, but is NOT recorded.** The owner confirmed PD-B01,
  PD-B02 and PD-B03 in conversation on 2026-10-21. PR #4 implements two of the three, with no migration,
  and is **held**: by GOV-AUTH-1 a direction is not effective until recorded through
  `MASTER_PRODUCT_DECISIONS.md` §2. Four questions it did not settle are now queue items
  (`V5-PROD-008` to `V5-PROD-011`): the recording act, the weight field on locked anchor FIT-004,
  `hunger_level`/`compliance_percent` and `coach_tips`, and the `ai_adjust_nutrition` migration.
* **Unchanged by any of this:** `OD-QAX-2`, `OD-14` and `GOV-AUTH-1` are still `proposed`; no
  migration was applied (QA frontier 181, pending 182 and 183); no protected governance file was edited.

## Priority — by authorized work unlocked, not by severity

| # | Blocker | Unlocks | Group |
|---|---|---|---|
| **1** | **B-01 · CR-1** — the authoritative home for an `OD-*` answer | **4 workstreams**: both security decisions, the Bash CI gate's marker grammar, ledger provenance (`authorizationIsIncomplete`), and every future `OD-*` answer | 1 |
| **2** | **B-04** — does the registry or the ledger govern `QAX-SEC-03`? | the **one P1 implementable with no further decision**, if the registry governs | 3 |
| **3** | **B-02 · OD-QAX-2** + **B-09/B-10 scope** | `QAX-SEC-01` (P0) | 2 |
| **4** | **B-03 · OD-14** + **B-09/B-10** | `F-21`, and `QAX-SEC-03` if B-04 resolves that way | 2 |
| **5** | **B-06** | `QAX-SEC-02` formal closure (code already applied) | 2 |
| 6 | B-05, B-07, B-08, B-16, B-17, B-18 | registration, protection, reliability | 2–6 |
| 7 | B-11 … B-14 | external access; cannot be answered by a ruling alone | 5 |

---

# Group 1 · Foundational governance

## B-01 · CR-1 — where does an `OD-*` answer authoritatively live?

**Tasks:** `V5-GOV-010` (the decision), and it gates `V5-SEC-ODQ2`, `V5-SEC-OD14`, `V5-GRD-004`,
`V5-BASH-001`'s CI-gate proposal.

**The exact question.** Which document is the authoritative home for the answer to an `OD-*`
question, and what form must that record take so a machine can link the id to its answer?

**Why it is necessary.** The coordinator's decision gate can check only that a named record *exists,
is a regular file and is non-empty*. It cannot check that the record answers the question, because no
convention links an `OD-*` id to its answer. Until one exists, "authorized" cannot be verified — only
asserted. It is also the marker grammar the proposed Bash CI gate would have to validate.

**Authoritative evidence** (all re-measured at this HEAD):

| Fact | Value | Location |
|---|---|---|
| distinct `OD-*` ids in `docs/` | **74** | `git grep -ohE 'OD-[A-Z]*-?[0-9]+' -- docs/` |
| `OD-*` rows in the declared decision register | **0** | `MASTER_PRODUCT_DECISIONS.md` |
| `PD-A*` rows there / `ANSWERED` markers | 26 / 7 | same |
| its documented procedure | *"Update this document's row to `ANSWERED` with the date and the owner"* | `:286` — **there is no row to update** |
| `OD-*` refs in `ADR-W1-001` | **0** | the ADR that records the ruling for `OD-QAX-9` |
| registry-designated load-bearing ids | **11** (`OD-QAX-1` … `OD-QAX-11`) | `MASTER_REMEDIATION_REGISTRY.md` |
| ids referenced by the queue | **2** (`OD-QAX-2`, `OD-14`) | `.skills-agent/tasks.json` |
| ids carrying any status marker | **1 of 74** (`OD-38 — RESOLVED`, an ad-hoc heading in 3 docs + 1 second-hand mention, with no owner, date or option) | findings §14 |
| documents already holding owner rulings verbatim | **4** — `V5_PROGRAMME_DEFINITION.md:3043` (`D3`→mig 136), `V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` (`D1(i)-(iii)`→mig 132/133), `V5_SECURITY_FOUNDATION_WAVE1_FINAL_REPORT.md` (`D1` copy), `docs/adr/ADR-W1-001` (`D1` copy) | findings §9 |
| of those four, protected by the guard | **1** | measured with the guard itself |

**Competing options.**

| | **A** — `PD-A*` rows mapping to `OD-*` | **B** — `docs/adr/`, each ADR naming its `OD-*` ids | **C** — `decision-log.md` + machine-checkable structure |
|---|---|---|---|
| Ownership | strongest declared; rows carry an `owner:` field | good, with precedent: migrations 132/133 cite ADRs as authority | weakest — self-describes as *"a concise record… not a changelog"*, no ownership field |
| Backward compatibility | good for `PD-A*`; **ignores** the 4 documents already holding rulings | **good** — formalises what 132/133/136 already do | poor — `PD-A13` cites it as a *record* today, so the format change touches a live citation |
| Machine validation | feasible: pipe-tables, `ANSWERED` idiom used 7× | **cheapest** — `ADR-W1-001` already has a parseable `**Status:**` line; add `**Resolves:**` and the check is two greps | only after adding an id column that does not exist |
| Existing references | `OD-*` would live in two namespaces at once | one ADR per decision | answers would sit in both `decision-log.md` and ADRs |
| Migration cost | up to **74** rows, or an explicit scope limit | **2 documents** to amend, then a convention for new ADRs | every existing decision re-expressed |
| Duplicated-authority risk | **raises it** — a third namespace beside `PD-A*` and `D*` | **lowers it** | raises it |
| Protected files touched | `MASTER_PRODUCT_DECISIONS.md` | `docs/adr/` **+** protecting the two authorization docs (B-16) | `decision-log.md` |

**Recommendation (not a selection): Option B.** It is the only option that repairs the traceability
break instead of adding a namespace to it; it is already the authority applied migrations cite; its
machine check is the smallest; and its migration path is two documents rather than 74 rows.

**The scope sub-decision, required under any option.** Must the mechanism cover **all 74** ids, the
**11** the registry designates load-bearing, or the **2** blocking queued work? The migration cost
differs by more than an order of magnitude and cannot be inferred. *Recommended:* the **11**, because
that is the set the canonical finding ledger itself declares load-bearing, with the remaining 63
converted lazily when one is next cited.

**Staged migration plan once authorized** (prepared, not started):

1. **S1 — convention.** Add `**Resolves:** OD-x, OD-y` to the ADR template and to `ADR-W1-001`
   (which resolves `OD-QAX-9`). *Protected-file change: `docs/adr/`.*
2. **S2 — validator.** `supabase/scripts/check-decision-provenance.mjs`: every `OD-*` id named in the
   registry's `Owner?` column either resolves to exactly one ADR declaring it, or is reported
   unresolved. Offline, deterministic, no secrets.
3. **S3 — ledger link.** Extend `authorizationIsIncomplete()` so a record must be an ADR whose
   `Resolves:` line names the id — turning structural completeness into verified provenance and
   closing CR-1's standing caveat.
4. **S4 — backfill** the 11 (or 74) in priority order, each as its own reviewable diff.
5. **S5 — CI** adds S2 to `static-guards` (requires the separate authorization in B-17).

**Validation criteria:** S2 exits non-zero when an id has zero or two resolving ADRs; S3 rejects a
record that exists but does not declare the id (the current `authorizationIsIncomplete` accepts any
non-empty regular file — demonstrated: an arbitrary owner string and a non-date both authorize today);
`flow:selftest` extended and mutation-tested.

**Eligible after an answer:** `V5-GOV-010`, then S1–S4 as new tasks; `V5-GRD-004` becomes decidable.
**Still blocked after it:** `V5-SEC-ODQ2` and `V5-SEC-OD14` still need their own substantive answers
(B-02, B-03) — CR-1 only gives them somewhere to live.
**Protected artifacts affected:** yes — `docs/adr/` under B, or `MASTER_PRODUCT_DECISIONS.md` under A,
or `decision-log.md` under C. **Release/security posture:** indirectly, via B-17.

---

# Group 2 · Security-policy decisions

## B-02 · OD-QAX-2 — may a coach assign plans or programs to a `pending` client?

**Tasks:** `V5-SEC-ODQ2`. **Finding:** `QAX-SEC-01` (**P0**, registry `:3405`).

**Defect.** `assign_nutrition_plan` (migration 131) supersedes any member's active plan for any
caller: the definer `UPDATE` bypasses the RLS the direct path enforces. **131's own `COMMENT` states
it:** *"Deliberately not stricter than that policy — 3A-11 does not change who may write."*
**Existing remediation: none.** Measured by numeric version comparison, **0** migrations strictly
above 131 touch `assign_nutrition_plan`. **Formal status:** P0, `Owner? = OD-QAX-2`.
**Missing closure evidence:** everything — code, QA application, live verification, CI.

**Proposed answer (not authorized).** Option A — an active `coach_client_relationships` row required.
**Supporting evidence:** migration 113's consent model lets a coach open only a `pending` invite and
only the client cause `active`; its table `COMMENT` says *never grant a write path that lets one party
name the other without consent*. `is_active_coach_of()` (migration 100) supplies the predicate.
**Alternative:** a narrowed Option B permitting assignment to `pending` but not `cancelled`/former —
keeps any assign-before-acceptance flow working at the cost of a weaker consent model.

**Implementation and regression plan (prepared, not implemented).** Guard inside the definer
function, before the supersede `UPDATE`. Regression criteria: an unrelated caller refused `42501` with
the victim's active plan unchanged; a coach-created `pending` row does not authorize; `cancelled` does
not authorize; an active coach still assigns (**positive control**); `search_path`, grants and
`COMMENT` preserved per the Function Replacement Rule (CRC-07 / I-MIG-03 — `CREATE OR REPLACE`
preserves ACL and owner but **not** `proconfig` or body). Verification: `check-function-posture`,
`check:guards`, `check-migration-manifest`. Migration number taken at wave entry per waves §0.2
(*"Assigned at wave entry, never before"*, `:82`) — **not** pre-assigned — with its atomic `pending`
declaration.

**Exact decision required.** (1) Option A or a narrowed B. (2) `Q-A1`–`Q-A5`: direction/identity,
status domain, error semantics, whether the direct RLS policy path is also in scope, fixtures —
**these change the migration's shape, so the headline answer alone is insufficient to start.**
(3) B-08's date and owner. (4) B-01, for somewhere to record it.
**Eligible after:** `V5-SEC-ODQ2` implementation. **Still blocked:** QA application and live
verification (B-14). **Protected artifacts:** `supabase/migrations/` and `expected_applied.json` at
implementation time. **Security posture: yes — this is a P0 authorization change.**

## B-03 · OD-14 — programme creation authority

**Tasks:** `V5-SEC-OD14`. **Findings:** `F-21`, and `QAX-SEC-03` **if** B-04 resolves that way.

**Question.** Who may create a programme; is `is_coach_profile()` sufficient or must an active
`coach_client_relationships` row exist; and what happens to existing non-conforming rows?
**Existing remediation: none.** 4 of `QAX-SEC-03`'s six tables are untouched above 131;
`coaching_calls` (132, 134) and `workout_program_assignments` (175) appear only in unrelated
subqueries — **no write arm is fixed**. Migration 136 corrects only the `SEC-PHI-9/10` **read**
predicates. **Formal status:** `F-21` OPEN; `QAX-SEC-03` P1.

**Proposed answer (not authorized).** Only an active-relationship coach may create; an active row is
required; non-conforming rows are **quarantined pending review, not mutated**.
**Evidence:** `F21_BLAST_RADIUS.md §6` states the mechanism is free (113 supplies helper and pattern)
and the remainder is a product question. `ADR-W1-001` is partial overlap only — it names none of the
six tables and lists `SEC-PHI-9/10` out of scope. `V5_DECISION_RESOLUTION_2026-09-27.md:78` (row `D1`)
records the question **OPEN** with no owner answer, corroborating `proposed`.

**Framing hazard, recorded so an answer is not misread.** `OD-14` is framed two ways under one id:
`F21_BLAST_RADIUS.md §6` and `QA_TO_V5_TRANSITION_RECONCILIATION` treat it as *programme creation /
policy population*; row `D1` labels it *"team semantics; who may create a membership"* while citing
both `OD-14` and `OD-QAX-9`. The ledger follows the first. **An answer should state which framing it
answers.**

**Implementation and regression plan (prepared).** Per-command policies replacing the self-asserted
`coach_id = auth.uid()` write arms on the six tables, using the hardened idiom
`coach_client_relationships` already uses. Regression criteria, per table: a coach with no active
relationship cannot insert or update a row naming a victim; an active coach can; existing victim rows
cannot be blanked or hijacked; notification side effects do not fire for an unauthorized write. Plus
the quarantine contract once B-10 is answered.

**Exact decision required.** The three sub-questions; **B-09** (does sub-question 1 bind programme
*creation*, and is `coach_video_responses` in scope); **B-10** (which quarantine option `Q-1`/`Q-2`/`Q-3`
and **who holds reviewer authority**); B-08; B-01; and **B-04**, which decides whether `QAX-SEC-03` is
inside this decision at all. **Security posture: yes.**

## B-05 · `QAX-SEC-08` — `D1(iv)` unanswered, and a disputed second dependency

**Tasks:** `V5-EVD-SEC08`. **Finding:** `QAX-SEC-08` (**P0**, registry `:3459`).

**This finding's code is fixed and applied.** `OD-QAX-9` is defined as *"What a coaching 'team' is,
and how membership is consented"* (`QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:186`) — precisely what
`D1(i)/(ii)/(iii)` answered verbatim on 2026-09-27 in
`V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md`. Implemented by **migrations 132 and 133**, both
citing that document and `ADR-W1-001`; frontier **181**, so both are **applied**. **The registry's
`Owner? = OD-QAX-9` is therefore stale.**

**Genuinely open.** (a) `ADR-W1-001` records that **`D1(iv)` — the permitted `role` value set — was
not answered.** (b) `QA_FINAL_RECONCILIATION_REPORT.md:336` states this finding *"needs OD-14 **and**
OD-QAX-9"*; if that second dependency is real, part of it waits on B-03.
**Missing closure evidence:** the `QA_CLOSURE_STANDARD.md` §2.1 ladder beyond *FIXED ON QA* —
**VERIFIED LIVE** and **VERIFIED IN CI** — plus a registry re-status, which is a protected edit.

**Exact decision required.** Answer `D1(iv)`; confirm or withdraw the `OD-14` dependency; authorize
the registry update once ladder evidence exists. **Eligible after:** the registry annotation.
**Still blocked:** live verification (B-14). **Protected artifacts: yes** —
`MASTER_REMEDIATION_REGISTRY.md`.

## B-06 · `QAX-SEC-02` — id reconciliation and closure evidence

**Tasks:** `V5-EVD-SEC02`. **Finding:** `QAX-SEC-02` (**P0**, registry `:3404`).

**Code is fixed and applied.** Migration **136** drops and recreates *"coach reads client progress
photos"* on `storage.objects` for `bucket_id = 'progress-photos'`, under *"owner decision `D3`,
recorded verbatim in `V5_PROGRAMME_DEFINITION.md` section 19.1"* — `D3 — ANSWERED: YES, UNIFORMLY,
via (b) the is_active_coach_of(text) overload`. 136's own header names the defect as
`029_progress_photos_storage_rls.sql:41  NO STATUS  ← SEC-PHI-9` — the same policy, line and missing
status check `QAX-SEC-02` describes. Frontier 181, so **applied**.

**Therefore `QAX-SEC-02` and `SEC-PHI-9` are the same defect under two ids.** `OD-QAX-1` — *"Is 'coach'
(and 'vendor') a self-service role?"* — is a **broader standing question** that also governs
`QAX-H-01/02`; it is **not** what blocked this policy fix.
**Missing closure evidence:** the §2.1 ladder above *FIXED ON QA*, and an id reconciliation.
**Authorized work completable now: none** — both remaining steps touch the protected registry.

**Exact decision required.** (1) Rule that `QAX-SEC-02 ≡ SEC-PHI-9` (or state why not).
(2) Confirm `OD-QAX-1` is not a closure precondition for this row. (3) Authorize the registry
annotation once ladder evidence exists. **Protected artifacts: yes.** **Security posture:** it
*records* a posture already applied; it does not change one.

---

# Group 3 · Source-of-truth conflicts

## B-04 · Does the registry or the ledger govern `QAX-SEC-03`?

**Tasks:** `V5-GOV-009` (`BLOCKED_GOVERNANCE`), and it gates `V5-SEC-OD14`'s scope.
**This is the second-highest-value answer in the packet.**

| Source | Says | Standing |
|---|---|---|
| `MASTER_REMEDIATION_REGISTRY.md:3406`, §7.23, column **`Owner?`** | `QAX-SEC-03` · P1 · **`no`** — no owner decision required | declared authority for *"remediation scope and finding status"* |
| `.skills-agent/decisions.json` | `OD-14.blocks = ["QAX-SEC-03", "F-21"]` | **explicitly not a register** — its own header and the guard both refuse it as authorization |

**On whether `Owner? = no` is authoritative — the honest answer.** On a plain reading the registry
governs: it is the declared authority for finding status, the `Owner?` column is its own field, and
the ledger disclaims register status. **But no rule anywhere defines the `Owner?` column's semantics.**
The §7.23 header defines the *evidence class* and the entry status (*"All rows enter as `DISCOVERED`"*)
and says nothing about `Owner?`. So the column's meaning is inferred from its values
(`OD-QAX-1`, `OD-QAX-2`, `no`), not stated. **That inference is not the same as an authoritative rule**,
which is why this is presented rather than decided.
Against the plain reading: `F21_BLAST_RADIUS.md §6` calls `OD-14` *"the decision that is actually
needed"* for the very same subject matter — self-asserted `coach_id = auth.uid()` write arms.

**Both readings are coherent:** the policy **defect** may be implementable without a product decision
(registry), while the **authorization model** the corrected policy expresses is a product question
(`OD-14`).

**Consequences. If the registry governs:** `QAX-SEC-03` is implementable **now** — the only P1 in this
packet needing no further decision — and the ledger's `OD-14.blocks` entry is wrong and should be
narrowed to `F-21`. **If the ledger governs:** the registry row needs an `Owner?` correction, a
protected edit, and `QAX-SEC-03` waits on B-03.

**Minimum clarification requested.** One sentence stating which source governs the `Owner?` field,
**or** a rule defining that column's semantics. **Eligible after:** `V5-GOV-009`, and
`QAX-SEC-03` implementation if the registry governs. **Still blocked:** `F-21` either way.
**Protected artifacts:** only if the ledger governs. **Security posture: yes** — it decides whether a
P1 authorization fix may proceed.

## B-07 · CR-2 — *"all ten N-05 decisions"*

**Tasks:** `V5-GOV-011`. Full conflict record in findings §10.

**Standing instruction:** *"Preserve PD-A02, PD-A12, PD-A13, PD-A14, PD-A19, OD-40, and all ten N-05
decisions as standing user constraints"*, with the brief adding that the relationship to migrations
**113–122** is unresolved and must not be inferred.

**Repository evidence:** `MASTER_REMEDIATION_REGISTRY.md:204` records `N-05` in a list of **alias
collapses** — `LRE-02 ↔ REL-18 ↔ K-ENV-1 ↔ OBS-4-R4 ↔ N-05`; `:603` gives that finding's status as
**`LRE-02` · P0 · `VERIFIED_CLOSED` 2026-08-26**, three production-targeting test harnesses closed by
a `tool/qa_target.dart` allowlist refusal; the id originates in
`QA_WORKSTREAM_N_TEST_COVERAGE_REPORT.md` (8 occurrences). `N-05` appears in 9 files, **none** as a
set, **none** numbered, **none** linked to 113–122.

**What cannot be reconciled.** A **finding** vs **decisions**; **one** vs **ten**; **test targeting**
vs **migrations**. The nearest 113–122 touchpoint is `PD-A26` (*"reverse scripts for 113–128"*) — a
different range and subject. **No mapping exists and constructing one would invent authority.** The
ten are preserved as written and treated as binding meanwhile.

**Minimum clarification:** (a) list the ten ids, **or** (b) name the document holding them, **or**
(c) confirm `N-05` means the single closed finding and withdraw *"ten"* — **and** (d) state what
relationship to 113–122 was intended, if any. **Unlocks:** nothing mechanically; it removes a standing
ambiguity that currently qualifies every statement about `N-05`. **Protected artifacts: no.**

---

# Group 4 · CR-3, CR-4, CR-5

## B-08 · CR-3 — provenance: the date and the owner

Required under **every** option in B-01 and by both security decisions.
`authorizationIsIncomplete()` requires `owner`, `answeredAt` and an existing non-empty `record`;
**measured, an arbitrary owner string and a non-date both satisfy it today**, so provenance is
asserted, not verified. Only the owner can supply these. **Unlocks:** nothing alone; it is a component
of B-01, B-02, B-03. **Protected artifacts: no.**

## B-09 · CR-4 — `OD-14` scope

(1) Does sub-question 1 bind programme **creation**, or only assignment? (2) Is
`coach_video_responses` in scope? Both change the migration's shape and table set, so B-03 cannot be
implemented without them. **Tasks:** `V5-SEC-OD14`. **Security posture: yes.**

## B-10 · CR-5 — the quarantine contract

Which option (`Q-1`/`Q-2`/`Q-3`) applies to existing non-conforming rows, and **who holds reviewer
authority** (`Q-B5`). This is the load-bearing part of B-03: it decides whether legitimate production
data written before the tightening keeps working, is hidden, or is migrated. **No option is
choosable without naming the reviewer.** **Tasks:** `V5-SEC-OD14`. **Security posture: yes** — it
governs access to existing data.

## Pre-existing governance decisions, already packaged — not re-asked here

These 14 carry their own documented questions from earlier phases. They are listed so the packet is
complete, **without restating questions the owner has already received**, per the instruction not to
ask the same question twice.

| Task | Exact next action | Existing document |
|---|---|---|
| `V5-GOV-001` | rule on the decision record | FG-3 §2.1 request |
| `V5-GOV-002` | authorize edits 1, 2, 3 individually or in any subset | register reconciliation request |
| `V5-GOV-003` | decide per component | design authority request |
| `V5-GOV-004` | rule D2-4a or D2-4b | owner decision pack |
| `V5-GOV-005` / `V5-W2A-001` | rule the I-MIG-03 authority question and authorize Wave 2A | waves + registry §7.x |
| `V5-W2B-001` | authorize 2B after 2A completes | waves |
| `V5-GOV-006` / `V5-SECR-001` | choose route C1 or C2 and resolve the `:1805` conflict | closure-standard request |
| `V5-GOV-007` | rule (i) or (ii) — add a §2 status, or leave rows understated | registry `:1815-1828` |
| `V5-PROM-001` | rule which state `SEC-04` may move to from OPEN, then authorize the register edit | registry |
| `V5-PROM-002` | rule whether PR #1 satisfies *"the first PR"*, then authorize the register edit | registry |
| `V5-CON-003` | answer `CON-03-TYPE` (+`-COMMA`, `-ROLLOUT`) on the memo's §8 sheet | `V5_CON03_STORAGE_CONTRACT_DECISION_MEMO.md` |
| `V5-W3B-001` | write CON-03's migration (authorized) and resolve SEC-R2 via a live probe plus its C1 ruling | — |

---

# Group 5 · External access and credentials

**These cannot be answered by a ruling.** They need access, money, or a maintenance window.

| ID | Task | Need | Consequence while unmet |
|---|---|---|---|
| **B-11** | `V5-AUTO-002` | a supported agent entrypoint **and** a provisioned credential — *"must not be guessed"* | the runner adapter cannot begin; continuous autonomous operation remains unproven |
| **B-12** | `V5-INF-001` | resolve Actions billing at `github.com/settings/billing` | **no CI evidence can be produced for any finding**, so the ladder's *VERIFIED IN CI* rung is unreachable for everything in this packet |
| **B-13** | `V5-EVD-SEC08` | QA write authorization **and** wave authorization | the `QAX-SEC-08` lifecycle probe cannot run |
| **B-14** | `V5-SEC-ODQ2`, `V5-SEC-OD14`, migrations 182/183 | a QA apply window, plus 182's Option A approval and 183's PD-A01 decision | nothing can pass *FIXED ON QA* or *VERIFIED LIVE* |

**B-12 — CORRECTED 2026-10-21. The earlier text here was wrong and is retracted.**

It read: *"while Actions billing is unresolved, no finding in this packet can reach formal closure
regardless of which decisions are answered."* **That conflated two repositories.** `V5-INF-001`'s
billing blocker is about **Helix** — its own summary says *"Restore Helix hosted CI so PR #1 and PR #2
can report real check results"*, and the Helix repository is not even reachable from this account.

**`12circle-plus` CI works.** Measured 2026-10-21: 10 runs that day, and full-green runs across all
seven jobs on both `f316ced5` and `472dab69`. So the closure ladder's **VERIFIED IN CI** rung is
reachable here, and B-12 is **not** a critical path for anything in this packet.

What that changes: findings whose only outstanding rung was CI are closer to closable than this
document previously claimed. In particular `V5-PROM-001` (SEC-04) and `V5-PROM-002` (ENV-6) each
record that their stated criteria are already **MET**, and are blocked solely on authorization to edit
the protected registry — not on evidence that cannot be obtained.

What remains true: **VERIFIED LIVE** still needs QA access, which this session is prohibited from
using, so security-class findings still require the owner for that rung.

---

# Group 6 · Independent review, protection, and reliability

## B-15 · No independent reviewer has reviewed this work

**Every verification in these phases was performed by the same model in the same session as the
implementer.** The coordinator enforces *identity separation* (`assertIndependentVerifier`), not
independent judgment. **This must not be described as independent review.** A review package is
prepared at `docs/V5_INDEPENDENT_REVIEW_PACKAGE_2026-10-21.md`, listing baseline, diffs, claims
needing reproduction, commands, integrity checks and prohibited operations.
**Decision required:** who reviews, and whether `policy.requireAttestedIdentity` should be turned on —
it is deliberately `false` because no runner exists to mint identity tokens, and enabling it today
would block all verification. **Unlocks:** credible sign-off on the change set; **a commit decision
should not precede it.** **Protected artifacts: no.**

## B-16 · Protected-root adjustment (prepared, not applied)

**Task:** `V5-GRD-004`. **The mismatch, measured with the guard itself:** `MASTER_PRODUCT_DECISIONS.md`
and `decision-log.md` are **protected** and carry **no live `OD-*` authority**; the documents applied
migrations actually cite as authority are **unprotected**.

| Path | Why protect | Risk if left unprotected | Interference with legitimate work |
|---|---|---|---|
| `docs/V5_SECURITY_FOUNDATION_WAVE1_AUTHORIZATION.md` | holds `D1(i)-(iii)` verbatim; cited by applied migrations 132, 133 | a tool-layer write could alter a recorded owner ruling with no objection | **low** — a closed authorization record, rarely edited |
| `docs/V5_PROGRAMME_DEFINITION.md` | holds `D3` verbatim at `:3043`; cited by applied migration 136 | same | **high** — a large living document edited for many reasons unrelated to `D3`. Protecting the whole file to guard one section is a blunt instrument |
| `docs/V5_SECURITY_FOUNDATION_WAVE1_FINAL_REPORT.md` | a third copy of `D1` | divergence between copies | low, but **the better fix may be removing the duplicate**, which is itself an owner call since all three copies are currently cited |

**Regression tests and rollout.** Each added root must also be added to `EXPECTED_ROOTS` in the guard's
`--self-test` **in the same change** — the suite fails otherwise, which is the intended friction and is
already mutation-proven (removing a root from the config alone fails 2 assertions). Rollout: add the
low-interference path first, observe, then decide on `V5_PROGRAMME_DEFINITION.md` — or extract `D3`
into an ADR under B-01 option B and protect that instead, which removes the need entirely.
**Authorization needed:** widening the protected set changes what the guard refuses; the guard's own
design requires that to be a reviewable, authorized diff. **Not changed in this phase.**

## B-17 · The Bash exposure and the proposed CI gate

**Task:** `V5-BASH-001` (analysis VERIFIED; the gate is not implemented).
**Exposure, demonstrated three ways:** the hook returns **exit 0** for a `Bash` payload naming a
protected path; a shell redirect writes with no hook involvement; and
`printf y > "$(echo c3VwYWJhc2UvbWlncmF0aW9ucw== | base64 -d)/998.sql"` writes into the protected
directory while **the command text contains no protected path at all**.

| Option | Assurance | Bypass surface | Impact on legitimate work | Verdict |
|---|---|---|---|---|
| `permissions.deny` on `Bash` patterns | **low** | defeated by the base64 case; shell has unbounded spellings | high — breaks ordinary `npm`, `git`, `node` work | **reject** |
| a `PreToolUse` hook parsing shell | partial at best | classifying arbitrary shell is undecidable; a partial classifier that looks complete is worse than none | moderate + standing false confidence | **reject** |
| OS immutability (`chflags uchg`) | **high** | an unlock exists, and an agent can run it | breaks `git checkout`/`merge`/`rebase` on those paths | **defer** |
| **a CI gate on protected-path changes** | **high at the boundary that governs** | requires repo write + CI bypass | **none locally** | **propose** |
| a `pre-commit` convenience hook | none (bypassable) | n/a | none | propose, **labelled a convenience** |

**Why CI, in the repository's own words** — `.githooks/README.md`: *"There is no way to make a hook
mandatory from inside the repository — a hook is a convenience that fires before a mistake, not a
control. Anything that must not be bypassable belongs in CI, where `ci.yml` runs regardless of what a
working copy is configured to do."* The governance risk is an unauthorized change to an authority file
**landing**, which CI catches whatever wrote it.

**CI requirements:** a `static-guards` step computing changed protected paths and failing unless the
change carries a valid **authorization marker**. **Recovery strategy:** both the step and the hook are
additive; deleting them restores today's behaviour and neither can block a local build.
**Dependency on B-01 is exact:** the marker's grammar is a consequence of the decision home. Under
option B it is mechanically checkable (an ADR path plus the `OD-*` id it declares it resolves, both
greppable); under A or C the marker can only point into a prose table the gate cannot validate.
**Additional authorization beyond B-01:** adding a **required** CI gate changes what can merge.
**Not implemented.** No `permissions.deny` added; shell access unrestricted.

## B-18 · Completed task status does not survive a clone

**Task:** `V5-COORD-003`. `.skills-agent/state.json` is gitignored (`.gitignore:40`).
**Measured on a simulated fresh clone:** before this phase's fix, all 38 tasks read `READY` with 24
drift entries; **after** it, 25 statuses are correctly derived from declared blockers and drift is
**0** — but **11 tasks still read eligible that are VERIFIED in this checkout**, including
`V5-GRD-001` and `V5-EVD-MAP`. A new environment could redo completed work.

Derivation fixes *reporting*; it cannot recover *completion*, which is not in the repository at all.

| Option | Cost | Risk |
|---|---|---|
| commit `state.json` | merge conflicts on every concurrent claim; leases and tokens become reviewable noise | low correctness risk, high churn |
| record completion evidence in `tasks.json` (e.g. a `verifiedAt` + evidence ref per task) | one line per completion, reviewable | the queue file becomes both definition and log |
| derive from git history (commits/trailers) | no new file | this phase's work is **uncommitted**, so nothing would be derivable yet |
| accept the loss, document it | none | a fresh environment repeats work; honest but wasteful |

**Recommendation:** the second — completion is durable programme state and belongs in a reviewed file,
whereas leases and tokens are genuinely ephemeral. **Not implemented:** it changes what is committed
and reviewed. **Protected artifacts: no.**

---

# What is NOT blocked, and what is simply finished

* **No authorized implementation work remains.** The queue reports **0 eligible**. Nothing was
  manufactured to keep it active.
* `QAX-SEC-02` and `QAX-SEC-08` need **no code work** — their remediations are applied. What they need
  is registration and ladder evidence.
* `QAX-SEC-03` may need **no decision at all**, depending on B-04. That is why B-04 ranks second.
* Migrations 182 and 183 are **coherent and complete as authored**; their gates are owner approvals
  and a QA window, not missing work.
