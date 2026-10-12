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
