# V5 · REGISTER RECONCILIATION REQUEST — one stale clause in `PD-A05`

**This document changes nothing.** `MASTER_PRODUCT_DECISIONS.md` is under a standing
do-not-modify constraint, so the finding below is reported for **owner-authorized**
reconciliation rather than corrected. The register is unmodified: 281 lines, last touched by
`527438a`, which is not this programme's work.

---

## The clause

`docs/MASTER_PRODUCT_DECISIONS.md:119`, at the end of row **`PD-A05`**:

> **Not yet implemented:** applied migration 125 implements option (b); see registry §7.11

## Why it is stale

It was true when written and has since been superseded. The owner answered `PD-A05` as
**option (a)**; migration **125** implemented option (b); migration **128** then implemented
option (a) and is the policy in force.

| evidence | what it establishes |
|---|---|
| `supabase/migrations/128_scope_decision_trace_reads_option_a.sql` | Creates `"dtrace read own/creator/active-coach/admin"` — `subject_id` OR `created_by` OR `is_active_coach_of(subject_id)` OR `public.is_admin()`. `content_manager` is not granted. Its header states it enforces *"PD-A05 **option (a)**, as ruled by the product owner on 2026-08-27"*. |
| `MASTER_REMEDIATION_REGISTRY.md` row `F-J-12` | ✅ **`VERIFIED_CLOSED` 2026-08-27** (CI run **#32** at `ae5be13`), **all four** SECURITY/AUTHORIZATION states present — FIXED IN CODE · FIXED ON QA · VERIFIED LIVE · VERIFIED IN CI. Decision column reads ✅ **PD-A05 (a)**. |
| the same row, live evidence | `content_manager` reads **0** rows where the identical probe read **90** pre-128; unrelated coach 0; unrelated client 0; subject 95/95 of their own. |
| `MASTER_REMEDIATION_REGISTRY.md` (§7.11 narrative) | *"when §0.2's 125 assignment was spent and **option (a) landed at 128**"*. |
| `SEC-G11` (new, this programme) | 14 assertions pinning 128's shape arm by arm, including that `content_manager` is not granted and that no bare role-class arm exists. Negative-controlled on two vectors. |

**125 was not edited, and should not be.** Its own successor says why: *"an in-place edit of an
applied migration is ENV-2 / CRC-13 — the defect this programme is remediating."* 128 is the
forward correction. So the implementation history is correct; only the register's closing clause
describes a state that no longer exists.

## Why this is worth your attention rather than a footnote

**The clause reads as unbuilt authorized work.** I found it while sweeping for exactly that —
decisions the owner has answered that nobody has implemented — and it was the only hit. Acting on
it would have meant **re-implementing a `VERIFIED_CLOSED` P1 security finding**, which is both
wasted work and a live risk: a "re-implementation" of a policy that is already correct is an
opportunity to get it wrong.

The investigation is what established it was stale. That is the argument for reconciling the
clause rather than leaving it: the next reader has to repeat the same investigation to reach the
same conclusion, and may not.

## What is requested

Authorization to replace the single clause

> **Not yet implemented:** applied migration 125 implements option (b); see registry §7.11

with a statement of the current state, for example

> **IMPLEMENTED:** migration **125** implemented option (b); migration **128**
> (`128_scope_decision_trace_reads_option_a.sql`) implements the ruled **option (a)** and is in
> force. `F-J-12` is `VERIFIED_CLOSED` (CI run #32, `ae5be13`) with all four
> SECURITY/AUTHORIZATION states present. Pinned by `SEC-G11`. See registry §7.11.

**Scope of the request, deliberately narrow.** One clause in one row. **No** change to the
ruling, the option text, the recommendation, the premise correction, `M-1`, `M-3`, `M-4`, the
dependency column, the owner column, or any other row. **No** change to the 73-decision count.
Nothing else in the register is proposed for edit, and no other register is touched.

**Not requested:** any change to migrations 125 or 128, to `F-J-12`'s closure state, or to the
`MASTER_REMEDIATION_REGISTRY` row — which is already correct.

## A second, separate note — not part of this request

The same `F-J-12` row carries a **retained limitation** that was **not** stale:

> *"RLS policies are outside the I-MIG-03 durability guard, which tracks function properties
> only — this closure has **no standing guard** against silent replacement."*

`SEC-G11` now supplies that guard at the **test** level, wired into CI with a two-vector negative
control. It does **not** close the limitation as written, because the limitation is about the
**I-MIG-03 durability guard / Gate 0.14**, and both migration 128 and registry §7.11 record
whether that gate should cover policies as an **open governance question**. That question is
untouched and remains open.

Whether the registry's limitation (i) should now be annotated to reference `SEC-G11` is a
separate authorization, on a separate register, and is **not** requested here.

---

# Second item — the `FG-1`/`FG-2` blocker has lifted, and three records still say it has not

**Found while reassessing the frontier**, not by looking for it: `FG-3` looked like executable
work, and checking why it was not led to the table it sits in.

## The three stale claims

`MASTER_REMEDIATION_REGISTRY.md`, above the `FG` table:

> **Follow-up evidence gaps — recorded, NOT implemented (owner assignment required, no silent
> scope expansion):**

That header is **correct for `FG-3`** and **stale for `FG-1` and `FG-2`**. Both are implemented and
running. The table's *Suggested home* column still reads "Wave 2 (2B)" / "Wave 2 retest scope" for
work that has already landed.

`supabase/expected_applied.json` carried the matching claim, which **has been corrected** in this
commit because that file is the manifest rather than a master register:

> ~~"The live half of this contract … is **NOT implemented**. It needs a QA database credential in
> CI, the same blocker as FG-1/FG-2. Until it runs, ENV-3 stays REMEDIATED."~~

## The evidence

CI run **`38194730786`** (`c3f4ff1`), job *Live QA suites*, step **"Live SQL evidence — FG-1, FG-2,
ENV-3 ledger"** — conclusion **`success`**. `QA_DB_URL` is provisioned (it appears in the job env as
`QA_DB_URL: ***`), so `live-evidence.sh` took its live path rather than its skip path. The step's
own output names each suite it ran:

| marker in the log | what it is |
|---|---|
| `FG-1 · function search_path posture (SEC-09 live half)` | `FG-1` |
| `FG-2a · Phase 2 workout contract (SEC-11 / Phase 2 live half)` | `FG-2` |
| `FG-2b · generated plan day titles (OBS-4 / migration 121)` | `FG-2` |
| `ENV-3 · live ledger comparison` | `ENV-3`'s live half |
| `ENV-3 · declared vs observed vs authored` | the declared-vs-real comparison |

`live-evidence.sh` is explicit about the alternative: without `QA_DB_URL` it emits
`::notice title=Live SQL evidence skipped::… FG-1, FG-2 and the ENV-3 live ledger check did NOT
run.` **That notice is absent and the suites' own headers are present**, which is what
distinguishes "ran" from "skipped" here — a `success` conclusion alone would not, because the skip
path also succeeds.

## What this changes, and what it does not

**`FG-3` remains genuinely unimplemented**, and its header still governs it. It asks for the
**positive** legs of the 116-wrapper class — owning coach → 200, `service_role` → 200 — *"so
over-refusal is distinguishable from correct refusal"*. That gap is real: with only the negative
legs asserted, **a wrapper that refused everyone would pass**. I did **not** implement it, because
the table requires owner assignment and doing so anyway is the "silent scope expansion" the same
sentence forbids.

## What is requested

Three things, all on `MASTER_REMEDIATION_REGISTRY.md`, none taken here:

1. **Scope the `FG` table header to `FG-3`**, or annotate `FG-1`/`FG-2` as implemented with the
   run above as evidence.
2. ~~**Decide whether `ENV-3` may be promoted beyond `REMEDIATED`.**~~ **WITHDRAWN,
   2026-10-12 — the request was based on my own error.** `ENV-3` is **not** pending promotion:
   `MASTER_REMEDIATION_REGISTRY.md` records it **`VERIFIED_CLOSED` on 2026-08-25** (§7.9, CI run at
   `2a8d0b6`), when the live evidence phase first executed against QA — *"ENV-3 and SEC-11 —
   already `VERIFIED_CLOSED` … there is nothing to advance"* (§2045). I took the word `REMEDIATED`
   from `expected_applied.json`'s own stale note and did not check the register's status field
   against it. **Nothing is requested here.**
3. **Assign `FG-3`**, or record it as deferred for V1.

**Not requested:** any change to `FG-1`/`FG-2`'s implementations, to `live-evidence.sh`, or to the
`QA_DB_URL` secret.

**And a correction to this document's own framing.** It previously said *"no claim that `ENV-3`
**is** closed — only that the condition it named has been observed to pass."* That was too
cautious in the wrong direction: `ENV-3` **is** closed, and has been since 2026-08-25. The
"blocker has lifted" finding in §206.12 was true but **not news** — `FG-1`, `FG-2` and `ENV-3`'s
live half all first executed six weeks before I observed them running. What remains accurate from
that section is narrower: **the `FG` table header still describes `FG-1` and `FG-2` as "NOT
implemented"**, and that is the one part of item 1 that stands.


---

## Evidence update, 2026-10-12 — the `FG` table header, verified at the step level

Item 1 previously rested on §7.9's narrative (*"the live evidence phase executed"*). That is a
record of one run in August. It has now been verified **against a named CI run's step
conclusions**, which is a different and stronger thing.

**`MASTER_REMEDIATION_REGISTRY.md:1603`** reads:

> **Follow-up evidence gaps — recorded, NOT implemented (owner assignment required, no silent
> scope expansion):**

and the table under it lists:

| ID | gap as worded |
|---|---|
| **`FG-1`** | *"Wire `supabase/tests/security/function-search-path.sql` into the live-qa CI job with a DB-credential path"* |
| **`FG-2`** | *"Wire the 32-assertion workout SQL suite (`supabase/tests/workout/*.sql`) into the live-qa CI job"* |

Both are worded as **wiring tasks**. So the question is not whether a suite passed — it is whether
the wiring exists. It does:

* `.github/workflows/ci.yml` carries the step **`Live SQL evidence — FG-1, FG-2, ENV-3 ledger`**,
  with `env: QA_DB_URL: ${{ secrets.QA_DB_URL }}`, running `supabase/scripts/live-evidence.sh`.
* That script's own manifest names `FG1='supabase/tests/security/function-search-path.sql'`,
  `FG2A='…/workout/phase2-contract.sql'` and `FG2B='…/workout/plan-day-titles.sql'` — i.e. exactly
  the two gaps' targets.
* The step is gated `if: steps.creds.outputs.present == 'true'`, so **without the secret it is
  skipped at the workflow level** and the script's own skip notice never even prints. Its
  conclusion therefore distinguishes "ran" from "was not provisioned".
* In run **`38275560994`** (commit `5b6206f`), job *Live QA suites*, that step's conclusion is
  **`success`** — not `skipped`.

So `QA_DB_URL` is provisioned, the gate passed, and **`FG-1`, `FG-2` and the ENV-3 live ledger
execute in CI today.** The header's *"NOT implemented"* is stale for both rows.

**Still not requesting closure, and not editing the register.** Two reasons:

1. *"Wired and passing"* is not the same as *"the finding it covers is closed"*. `FG-1` covers
   **`SEC-09` promotion** and `I-MIG-03`'s unverifiable pin; `FG-2` covers **`SEC-11`** and the
   Phase-2 re-verification. Whether those promote is a §2.1 judgement under the closure ladder,
   and it is yours. A green step is evidence toward it, not the ruling.
2. The header also carries *"owner assignment required, no silent scope expansion"* — language
   about **authority**, not about implementation state. Even once the factual half is corrected,
   that half may still be the owner's intent.

**The exact edit requested** — nothing more:

> Replace the header's *"recorded, NOT implemented (owner assignment required, …)"* for the `FG-1`
> and `FG-2` rows with *"implemented and running in CI (step `Live SQL evidence — FG-1, FG-2,
> ENV-3 ledger`); the findings they cover remain open pending a §2.1 promotion ruling"*.

**Authorization needed:** explicit owner approval to edit
`docs/MASTER_REMEDIATION_REGISTRY.md`, which is a protected register. **It has not been edited.**

**One stale comment noted, not changed.** `.github/workflows/ci.yml` still calls this *"the
FG-1/FG-2 blocker"* in the ENV-3 static-guard step's comment, and `I-MIG-03` prints *"live evidence
is FG-1"*. Both describe a blocker that has lifted. They are comments in a workflow file, not
register entries, and editing CI configuration was not part of this instruction — so they are
reported rather than touched.

---

## `SEC-09` and `SEC-11`, 2026-10-12 — **neither is awaiting the `FG` header**

I previously listed *"whether `SEC-09`/`SEC-11` promote"* among the outstanding owner decisions.
**That was wrong on both counts**, and reading the register's own status rows rather than reasoning
from the `FG` rows' *Covers* column settles it.

### `SEC-11` — **already closed**

> *"**2026-08-25:** two further rows — **SEC-11** and **OBS-4** — are promoted on the live SQL
> evidence at `2a8d0b6`."* (`:229`)
> *"**`ENV-3`** and **`SEC-11`** — **already `VERIFIED_CLOSED`** … there is nothing to advance."*
> (`:2045`)

**Status: already closed with a stale request.** Nothing is requested. This is the **second** item
I asked you to promote that the register had already closed on 2026-08-25 — `ENV-3` was the first.
Both mistakes came from the same habit: reading a *follow-up gap's* `Covers` column as if it
described the covered row's current state.

### `SEC-09` — **decided, and gated on something else entirely**

> *"**SEC-09** — **withdrawn from the promotion set by the owner ruling above.** FG-1's live half is
> done and recorded; the row waits on **I-MIG-03's own closure**."* (`:1721`)
> *"unchanged, `ALREADY_FIXED`. FG-1's 5/5 re-ran green, and under the owner ruling of 2026-08-25
> that evidence is **necessary but not sufficient**: SEC-09 closes when **I-MIG-03** reaches
> `VERIFIED_CLOSED`."* (`:2049`)
> *"**SEC-09 is not promoted**: FG-1 returned 5 PASS / 0 FAIL live, but the owner ruling … requires
> I-MIG-03 itself to reach `VERIFIED_CLOSED`, which it has not."* (`:229`)

So `FG-1` going green **cannot** promote `SEC-09` — you already ruled that evidence necessary but
not sufficient. Its gate is `I-MIG-03`, which is *"CI-verified in records mode, enforcement deferred
to 2A"* and *"escalated as an authority question, not decided"*.

**Status: blocked by a specific dependency** — `I-MIG-03`'s closure, which is itself
architecture-gated (Wave 2A enforcement) **and** carries an undecided authority question. **Not an
`FG`-header matter, and not requested here.**

### What this leaves of the `FG` header request

Only the **factual** half, unchanged from the evidence above: the header says
*"NOT implemented"* for two rows whose wiring demonstrably runs in CI. Correcting that wording
does **not** promote anything — `SEC-11` is closed, `SEC-09` is gated on `I-MIG-03`, and `ENV-3` is
closed. That is now an argument **for** the edit being narrow and safe, not for deferring it.

**Status: evidence complete, authorization missing.** The register remains **untouched**.

---

# DECISION-READY · the `FG` headers — **three edits, none taken**

There are **two** headers carrying *"recorded, NOT implemented"*, not one, and they need different
treatment. Both are in `docs/MASTER_REMEDIATION_REGISTRY.md`, a **protected register**, and
**neither has been edited.**

### Edit 1 — `:1603`, the `FG-1`/`FG-2` header

> *"**Follow-up evidence gaps — recorded, NOT implemented (owner assignment required, no silent
> scope expansion):**"*

Both rows are **wiring** tasks, and the wiring exists: CI step `Live SQL evidence — FG-1, FG-2,
ENV-3 ledger`, gated `if: steps.creds.outputs.present == 'true'`, conclusion **`success`** in run
**`38281191465`**.

```diff
-**Follow-up evidence gaps — recorded, NOT implemented (owner assignment required, no
-silent scope expansion):**
+**Follow-up evidence gaps — WIRED AND RUNNING IN CI (step `Live SQL evidence — FG-1,
+FG-2, ENV-3 ledger`). The findings they cover are unaffected by this and remain as
+their own rows state; no silent scope expansion:**
```

**Promotes nothing** — every row it bears on is already settled elsewhere: `SEC-11`
`VERIFIED_CLOSED` (2026-08-25), `ENV-3` `VERIFIED_CLOSED` (2026-08-25), `SEC-09` `ALREADY_FIXED`
and gated on `I-MIG-03`.

### Edit 2 — `:1836`, the `FG-3` header

> *"#### Follow-up evidence gap — recorded, NOT implemented"*

`FG-3` **is** implemented (`d23-fg3-positive-legs.mjs`, **37/37**, inside a **1161/1161** live
suite). Its **closure** is a separate matter and is **not** being requested.

```diff
-#### Follow-up evidence gap — recorded, NOT implemented
+#### Follow-up evidence gap — EVIDENCE IMPLEMENTED; CLOSURE BLOCKED ON §2.1
+
+Implemented 2026-10-12 as `supabase/tests/security/d23-fg3-positive-legs.mjs` (37/37).
+**This does NOT close FG-3.** `QA_CLOSURE_STANDARD.md` §2.1 requires VERIFIED LIVE for
+the Security / authorization class, and its clause *"the same probe demonstrably failed
+before the fix"* cannot be satisfied by a positive leg where the fix ADDED a guard. The
+amendment is proposed in `V5_FG3_DECISION_REQUEST.md` and is **unauthorized**. FG-3
+stays OPEN.
```

This is the edit the instruction guards against most directly, so it is written to make closure
*harder* to assert, not easier: it names the blocker inside the register itself.

### Edit 3 — `:1840`, `FG-3`'s row text, which your own later decisions superseded

The row reads:

> *"Assert the **positive** legs … the owning coach → 200 **and `service_role` → 200** for each of
> the five wrappers"*

Two parts of that are now contradicted by decisions **you made afterwards**:

| row says | your 2026-10-12 decision |
|---|---|
| `service_role` → 200 as a **positive leg** | *"`service_role` is a **separate liveness test, never authorization evidence**"* |
| **the owning coach** for *each of the five* | program-scoped → owning coach; **subject-scoped → the subject themselves**. `predict_client` and `assemble_weekly_review` have no owning coach |

```diff
-| **FG-3** | Assert the **positive** legs of the 116 wrapper class: the owning coach → 200
-and `service_role` → 200 for each of the five wrappers, so over-refusal is
-distinguishable from correct refusal |
+| **FG-3** | Assert the **positive** legs of the 116 wrapper class: for the three
+program-scoped wrappers the **owning coach** → 200, for the two subject-scoped the
+**subject themselves** → 200, each paired with a same-scope refusal, so over-refusal is
+distinguishable from correct refusal. `service_role` is tested **separately as liveness,
+not as authorization evidence** (owner decision, 2026-10-12) |
```

**Leaving this unedited is also a defensible choice** — the row is a historical statement of what
was registered in August. I am not arguing for it; I am recording that the register currently asks
for evidence the owner has since ruled is not evidence, and letting you decide which document
moves.

### Authorization required

Explicit approval to edit `docs/MASTER_REMEDIATION_REGISTRY.md` for **edits 1, 2, 3 — individually
or in any subset**. All three are **evidence complete, authorization missing**. The register is
**untouched**.

---

# `V5-REC-002` · two source-of-truth conflicts found during queue reconciliation

Both were found by reading the current checkout, and **neither is resolved here**. Each needs an
authorized decision about *which document moves*.

## Conflict 1 — the queue cited an authority that does not exist

`.skills-agent/tasks.json` declared:

```
"queueAuthority": "V5_WORKSTREAM_REGISTRY_AND_MASTER_REMEDIATION_WAVES"
```

**There is no `V5_WORKSTREAM_REGISTRY`.** It is not a tracked file under any spelling
(`git ls-files | grep -iE 'workstream.*regist|regist.*workstream'` → empty), and no document in
`docs/` carries that title. `MASTER_REMEDIATION_WAVES.md` does exist.

**Taken here, because it is the queue's own metadata and not a governed register:** the field now
names the three documents the tasks actually cite — `MASTER_REMEDIATION_WAVES.md`,
`RELEASE_GATES.md`, `MASTER_REMEDIATION_REGISTRY.md` — with the prior text preserved in a note.

**The question that remains yours:** was a `V5_WORKSTREAM_REGISTRY` ever intended to exist? If so,
the three-document substitute is a stopgap and that register still needs writing. If not, the
phantom name should also be removed wherever else it appears.

## Conflict 2 — the authoritative wave plan stops 50 migrations short of the repository

`MASTER_REMEDIATION_WAVES.md` maps migration numbers to waves, and its mapping **ends at 131**
(Wave 3A — tasks 3A-9, 3A-10, 3A-11).

The repository is far past that: `check-migration-manifest.mjs` reports **182 authored
migration(s): 000–181**, frontier **181**. So **51 migrations exist beyond the plan's mapping.**

This is not a numbering error; it is a scope statement that reality overtook. The consequence for
this milestone is concrete: **an inventory derived only from the wave plan would omit 51
migrations of real work**, and an inventory claiming to cover "remaining work" cannot be built from
a plan that ends fifty migrations ago.

**Not taken here.** `MASTER_REMEDIATION_WAVES.md` is the authoritative sequence this programme is
required to preserve, and extending its mapping is a planning decision, not a transcription.

**The decision requested** — one of:

| option | consequence |
|---|---|
| **a** extend the wave mapping to 181 | the plan becomes a usable forward inventory again; someone must assign 132–181 to waves, which is real planning work |
| **b** declare the mapping historical and closed at 131 | honest, and the plan stops being a forward planning instrument; a successor inventory is then required |
| **c** supersede the document | the wave *sequence* is preserved as the governing order while the migration mapping moves elsewhere |

**No edit was made to `MASTER_REMEDIATION_WAVES.md`.**

## What was deliberately NOT enumerated

The registry carries **319 canonical rows** (`37 + 48 + 24 + 177 + 4 + 29`), and it states of
itself that *"the `P1–P3` register carries no per-row status field, so its movement is **not
mechanically countable**"*. A per-row queue therefore cannot be derived from it **without
inventing statuses**, which is the one thing the reconciliation brief forbids.

So the queue holds the ten tasks for which direct repository evidence exists, and the row-by-row
pass stays where the registry already defers it. **That is a stated limit of this inventory, not an
omission by oversight.**

---

# `MILESTONE 4` · migration reconciliation — **and a correction to Conflict 2**

## ⚠ Conflict 2, as I reported it, was not a conflict

Milestone 3 recorded that *"`MASTER_REMEDIATION_WAVES.md` maps migrations only to 131 while the
frontier is 181 — 51 migrations beyond the plan"*. **That was a misreading of the document, and
the cause was my own regex.**

I matched the pre-assignment table with `^\| \*\*1[0-9][0-9]\*\* \| [0-9A-C]+ \|`, which captures
only rows of that exact shape, and then treated *absence from that table* as *absence from the
plan*. The table's **own final row** says otherwise:

```
| **132+** | 4+ | Assigned at wave entry, never before |
```

So migrations **132 and above are outside the pre-assignment scope by the plan's explicit rule** —
not missing from it. §0.2 states the convention directly, and the 2026-08-31 amendment restates
it: *"Wave 4+'s floor moves to **132+**. The numbers are not chosen…"*

Two further artefacts of the same careless extraction: the "150" I counted as a migration is
*"150 sites are invisible to it (N-03)"* — a code-site count — and the "188" is inside a long
`W1-B2` table cell, not a migration assignment.

**Of the brief's three options, the evidence supports `C`:** the plan and the manifest use
different, stated conventions, and there is nothing to amend. **No decision is required on this
point.** `A` and `B` both rest on a discrepancy that does not exist.

## The reconciliation, machine-checkable

`scripts/check-migration-wave-coverage.mjs` (also `--json`) derives this from tracked files only:

| | |
|---|---|
| authored | **182**, range **000–181**, **contiguous** |
| pre-programme (`< 123`) | **123** — below the plan's first assigned row |
| pre-assigned (`123–131`) | **9** — waves 1, 2, 3A |
| outside by rule (`≥ 132`) | **50** — *"assigned at wave entry, never before"* |
| **unexplained** | **0** |
| declared in the manifest | **all** — `environments.qa.applied_through = 181`, `excluded: []`, `pending: {}` |
| applied / verified status | **NOT ESTABLISHED by this tool** — the manifest declares *intent*, not outcome |

The tool refuses to infer status from a migration's number or from a file existing, and reports the
applied state as not established rather than guessing it.

**Incidentally, it also independently confirms the QA target from a tracked file:**
`environments.qa.ref = eyqtldjqpgpljlqvpowh`.

### Three bugs in my own tool, each caught by running it

1. It reported **123 "unexplained"** migrations — 000–122 — because I assumed everything below the
   `132+` floor must be pre-assigned. The table also has a **lower** bound: its first row is 123,
   and everything before that is pre-programme history.
2. It reported **all 182 as undeclared**, because I invented a per-file key format for
   `expected_applied.json`. The manifest declares an `applied_through` frontier plus
   `pending`/`excluded` — it never enumerates migrations.
3. After fixing that, it *still* reported all 182 undeclared, because `applied_through` is the
   **string** `"181"` and `Number.isInteger` rejected it. My own debug print showed it unquoted and
   I misread my own output.

Each would have shipped as a "finding". They are recorded because the pattern — a tool's defect
presented as a discovery — is the same one that produced the Conflict 2 error in the first place.

## Conflict 1 — the registry investigation

| explanation | evidence |
|---|---|
| renamed or moved | **no.** `git log --all --diff-filter=A` over every branch finds no file ever added under any workstream-registry spelling |
| superseded by an existing register | **no evidence either way.** Nothing records such a decision |
| intended but never committed | **consistent with the evidence, unproven** |
| referenced erroneously by queue metadata | **consistent, and the origin is identified**: the string entered in `fd86823` *"feat(v5): seed autonomous team bootstrap queue"*, whose message is a single line with **no body and no rationale** |

**What the evidence does NOT establish**, and I will not infer it: whether a
`V5_WORKSTREAM_REGISTRY` was ever intended to exist, and **who authorized the authoritative
workstream source**. A search finding no file says nothing about intent.

### Decision required — authoritative workstream source

| option | consequence |
|---|---|
| **1** the three cited documents **are** the authority | the queue is already correct; `fd86823`'s string was simply an error. Cheapest, and loses nothing if a register was never intended |
| **2** a `V5_WORKSTREAM_REGISTRY` **should exist** | the three-document citation is a stopgap; that register must be written, and the queue re-cited to it |
| **3** a different existing register is the authority | name it; the queue is re-cited and the other documents demoted to sources |

**Affected:** `.skills-agent/tasks.json` (`policy.queueAuthority`), every task's `sources`,
`scripts/skills-agent-inventory-check.mjs` (which enforces that cited authority resolves).
**Risk of deferring:** low — the queue cites documents that demonstrably govern it, and the
unresolved authority question is recorded rather than hidden.

---

# `MILESTONE 5` · queue authority resolved from the documents' own scope statements

## My Milestone-3 correction was itself incomplete

Milestone 3 replaced `fd86823`'s phantom `V5_WORKSTREAM_REGISTRY` with **three** documents. That
was better than a fiction and still **wrong by omission**: it cited no authority for **owner
decisions** or for **closure evidence**, two of the five things the queue depends on.

Reading each candidate's own header settles it without inference:

| concern | governing document | its own words |
|---|---|---|
| workstream sequencing | `MASTER_REMEDIATION_WAVES.md` | *"The dependency-aware execution plan"* |
| release gates | `RELEASE_GATES.md` | *"Gate 0 through Gate 9"* |
| remediation scope and finding status | `MASTER_REMEDIATION_REGISTRY.md` | *"The canonical finding ledger for the whole programme"* |
| **owner decisions** | `MASTER_PRODUCT_DECISIONS.md` | *"Every unresolved decision extracted from workstreams A–N, deduplicated and owned"* |
| **closure evidence** | `QA_CLOSURE_STANDARD.md` | *"What 'closed' means, and what it does not"* · *"Governs every status change in `MASTER_REMEDIATION_REGISTRY.md`"* |

These are not five documents I selected. **All five declare themselves "Wave 0 deliverable", and
they cross-reference each other as companions** — `MASTER_REMEDIATION_REGISTRY` names all four
others; `QA_CLOSURE_STANDARD` names three; `RELEASE_GATES` names two. It is a closed,
self-declaring set.

So naming five rather than three **changes no governed decision** and is the smallest correction
the existing authority supports. Taken, with provenance preserved in `policy.queueAuthorityNote`,
and `policy.authorityScope` now records which document governs what, quoting each header.

**The owner question is narrowed, not answered.** The five Wave 0 deliverables demonstrably cover
all five concerns, so **nothing is missing for coverage** — which is evidence for option `1` (the
cited documents *are* the authority). But evidence of absence still cannot establish intent:
whether a `V5_WORKSTREAM_REGISTRY` was *meant* to exist remains yours to say.

## Blockers revalidated — all seven still current

| task | revalidation evidence | still blocked |
|---|---|---|
| `V5-AUTO-002` | `claude` CLI absent; `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` unset; `~/.claude/.credentials.json` absent; **0** self-hosted runners | **yes** |
| `V5-GOV-001` | §2.1 line 43 still reads *"and the same probe demonstrably failed before the fix"*; last touched by `57335da`, which predates this campaign | **yes** |
| `V5-GOV-002` | **2** occurrences of *"recorded, NOT implemented"* remain in the register | **yes** |
| `V5-GOV-003` / `V5-GOV-004` | guard: *"no specification exists for the 4 components awaiting D2-3"* | **yes** |
| `V5-GOV-005` | register still reads *"CI-verified in records mode, enforcement deferred to 2A"* and *"SEC-09 closes when I-MIG-03 reaches VERIFIED_CLOSED"* | **yes** |
| `V5-INF-001` | Helix latest run still `38184333945` (2026-10-11), sole failure annotation still the billing message; no new run because no new push | **yes** |

**No blocker was resolved by new evidence, and none was converted into eligible work.**

## Eligibility: zero, verified

All ten tasks: 3 `VERIFIED`, 2 `BLOCKED_EXTERNAL`, 1 `BLOCKED_GOVERNANCE`, 4 `BLOCKED_OWNER`.
**No task is eligible**, and every blocked task retains its dependency edges — a test asserts that
blocked-ness is never manufactured by deleting them.

---

# `MILESTONE 6` · the queue was not the backlog

## The finding

The ten-task queue modelled the autonomous-team infrastructure and the governance blockers and
**nothing else**. It contained **zero product remediation work**, against a registry board of
**~177 `READY_TO_REMEDIATE`** rows (canonical total **319** = `37 + 48 + 24 + 177 + 4 + 29`).

So the previous milestones' "zero eligible tasks" was true of the queue and **misleading about the
programme**. Five wave-level product tasks are now represented.

## Why none of it is executable — traced link by link, not asserted

| path | blocked by | evidence |
|---|---|---|
| **Wave 2A** (I-MIG-03 enforcement) | owner | registry: *"CI-verified in records mode, enforcement deferred to 2A"*, authority question *"escalated… not decided"* |
| **Wave 2B** (class guard) | sequence + gate | plan: *"2A → live re-verification → 2B's assertions promoted"* |
| **SEC-R2 / SEC-R3** | owner | both read **`4 of 5 present`** with `VERIFIED END-TO-END` **❌ absent**; *"VERIFIED END-TO-END is Step 4"* and **"Step 4 is not authorized"** appears three times |
| **CON-03** | governance | *"`dietary_restrictions` — two serializers, one column, **prod type unknown**"*. Establishing it means reading **production**, which Gate 9B forbids |
| **Wave 3B-1** | both of the above | plan: *"Depends on CON-03 … and on SEC-R2"* |

**Wave 3A is implemented**: migrations `129_notification_contract_and_pr_timing`,
`130_private_storage_buckets`, `131_identity_constraints` exist and match tasks 3A-9/10/11.

**Wave 3B-0 is complete as specified, and its apparent gap is not one.** `AppFailure` and
`reportFailure()` exist, and `reportFailure` has **zero call sites** — which looks like unfinished
wiring until the file's own scope statement is read: it closes *"the capability half"*, while
*"classifying and wiring the remaining ~234 swallow sites is **Phase B4** … deliberately NOT done
here."* EC-23's visible half is also done: **zero** bare `print()` calls remain in `lib/`, and the
analyzer reports **0** `avoid_print`.

## Queue state

**15 tasks · 0 eligible.** 3 `VERIFIED` · 2 `BLOCKED_EXTERNAL` · 2 `BLOCKED_GOVERNANCE` ·
5 `BLOCKED_OWNER` · 3 `READY` but gated behind unmet dependencies.

`V5-SECR-001` and `V5-CON-003` have **no dependency edges** and are blocked by **authorization**
instead — recorded as blockers rather than as fake edges, and a test asserts exactly that.

## Still not a per-row enumeration

The ~177 rows are **not** expanded individually. The registry states that the `P1–P3` register
carries no per-row status field and *"its movement is not mechanically countable"*, so a per-row
queue cannot be derived without inventing statuses. These five are the **wave-level** work at the
current frontier, each traced to the plan or the registry.
