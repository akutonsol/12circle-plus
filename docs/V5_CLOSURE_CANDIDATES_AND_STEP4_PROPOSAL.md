# V5 · SEC-04 and ENV-6 closure candidates · and a Step 4 definition proposal

**Nothing in this document has been applied.** `MASTER_REMEDIATION_REGISTRY.md` is unmodified, and
`git diff` proves it. Two promotions are **proposed for owner review**; a governance definition is
**proposed**, not adopted.

---

## 1 · `SEC-04` — evidence matrix

**The finding** (`registry:243`): *"SEC-04 / D-1D · 11 subject-scoped RPCs trusting a caller
uuid"*, remediated by *"116 — `can_act_for` / `can_act_on_program`; 13 engine functions renamed
`*_engine` behind authorized wrappers"*.

**Its class**: Security / authorization → `§2.1` requires **FIXED IN CODE · FIXED ON QA ·
VERIFIED LIVE · VERIFIED IN CI**. **No `VERIFIED END-TO-END`, so Step 4 does not gate it.**

**The originally recorded blocker** (`registry:1585`), which states the missing evidence exactly:

> *"SEC-04 (open regression F-J-01: `d04` has a documented blind spot on
> `materialize_program_week`'s wrapper; **needs migration 124 + I-MIG-03 class guard + live 403
> probe** — Wave 2)"*

### The three named requirements, checked individually

| requirement | state | evidence |
|---|---|---|
| **migration 124** | ✅ present | `supabase/migrations/124_wave_2a_security_regressions.sql` |
| **I-MIG-03 class guard** | ✅ exists **and runs** | `supabase/tests/security/migration-durability-guard.mjs`, referenced twice in `ci.yml`, reporting `[restored] materialize_program_week(authorization wrapper) established 116 → stripped 119 → restored 124` and `intact materialize_program_week can_act_on_program` |
| **live 403 probe** | ✅ present | `d04` §8 asserts `403` + `42501` + the member's own predicate for all five wrappers, including `materialize_program_week` |

**Why "class guard" and not I-MIG-03's closure is the right reading** — and this is not my
interpretation: the registry records the ambiguity *and the ruling*. §7.8's SEC-04 clause says
*"I-MIG-03 **class guard**"* where the SEC-09 clause says bare *"I-MIG-03"*, and *"the product
owner ruled on 2026-08-25 for **reading B**"* (`:1681-1686`). Under reading B SEC-04 needs the
**guard existing and running**, which it does.

**The blocker itself is closed**: `F-J-01 · P0 · ✅ VERIFIED_CLOSED 2026-08-27` (`:360`).

### What stops me recommending promotion outright

`SEC-04`'s status is recorded as **`OPEN`** (`:1719` — *"SEC-04 / SEC-R1 / SEC-R2 / SEC-R3 /
F-J-01 — unchanged, OPEN"*), and §2 defines `OPEN` as *"Suspected; needs a probe or a decision
before it can be classified."*

So two separate things are true, and conflating them would be the error:

* the **three requirements its own missing-evidence clause names are satisfied**;
* the row nonetheless sits at `OPEN`, and **whether `OPEN → VERIFIED_CLOSED` is a valid single
  transition** — rather than `OPEN → REMEDIATED → …` — is a closure-standard question I have no
  authority to answer.

**Proposed register change, for owner review only:** reclassify `SEC-04` out of `OPEN` on the
evidence above, to whichever state the owner rules the ladder permits. **I am not proposing a
specific target state**, because §2 does not establish that `OPEN` may jump to `VERIFIED_CLOSED`.

---

## 2 · `ENV-6` — evidence matrix

**The finding** (`registry:618`): *"ENV-6 · No CI, and the only workflow contacts production."*

**Current status**: **`REMEDIATED`** (`:1523`) — *"ci.yml has never run — commit+push required"*.
*(The `4` in that row is the **Task** column — Wave 1 batch task 4 — not a count of states.)*

**Its stated closure criterion** (`:1594`), verbatim:

> *"**ENV-6** (push-triggered runs proven; the row's own retest names a PR run — **closes at the
> first PR**)"*

| criterion element | state | evidence |
|---|---|---|
| push-triggered runs proven | ✅ already recorded | the row's own text |
| **a PR run** | ✅ **satisfied** | **15** `pull_request` CI runs recorded, **9** successful; most recently `38330259334`, all seven jobs green |
| *"closes at the first PR"* | ✅ **satisfied** | **PR #1** is the repository's **only and first** pull request, created 2026-10-12T17:45:05Z |

**This is the stronger of the two candidates**, and it is worth being explicit about why: its
closure criterion is a **single stated condition**, that condition is **mechanically checkable**,
and it is **met**. No interpretation is required.

**One caveat I will not paper over**: PR #1 is the autonomous-team branch's own PR, opened during
this programme. The criterion says *"the first PR"* and does not qualify which — but an owner may
reasonably intend a PR of product work rather than of the queue infrastructure. **That is a reading
question, and it is the owner's.**

**Proposed register change, for owner review only:** promote `ENV-6` from `REMEDIATED` on the
evidence above, if the owner accepts PR #1 as satisfying *"the first PR"*.

---

## 3 · Step 4 — a definition proposal

### Established by the sources (quoted, not proposed)

| element | source |
|---|---|
| the verification chain: *"UI → state → service → authorization → API/function → database → persistence → response → UI state — with the correct **failure** behaviour, and the regression suite is green"* | `QA_CLOSURE_STANDARD.md` §2.1, `VERIFIED END-TO-END` row |
| what it proves: *"The feature works as a product"*; what remains: *"Nothing further; this is the terminal state"* | same row |
| it is **Step 4**, *"End-to-End Product Verification"*, and it **"is not authorized to begin"** | `registry:1802` |
| the consequence: *"no safety finding in this programme can reach `VERIFIED_CLOSED` before Step 4 runs"* | `registry:1805` |
| which classes require it | `§2.1`: AI/safety input (all five) · Error contract/false success (user-facing success) · Billing/entitlement (anything moving money). **Not** Security/authorization or Data contract/schema |
| a working precedent exists | `uix1_booking_e2e_test.dart` — *"UIX-1 / M-03 — VERIFIED END-TO-END runner"* — and `wrk01_progression_live_test.dart`, both CI jobs that sign in and traverse the real chain |

### NOT established by any source — these are the gaps

* **Entry criteria** for the phase. Nothing states what must be true before Step 4 may begin.
* **The approver.** No document ties any Step number to a role or a person. *"End-to-End Product
  Verification"* appears **exactly once** across `docs/`, in a parenthetical.
* **Scope of approval** — whether it permits verification only, or also code, data, register or
  release-status changes.
* **How authorization is recorded.**
* **How a row with missing evidence is handled** — this is the open status-vocabulary question
  (`V5-GOV-007`).

### Proposed definition — **subject to owner adoption**

> **Purpose.** Step 4 establishes `VERIFIED END-TO-END` for findings whose `§2.1` class demands it.
> It changes no other state and grants no other permission.
>
> **Entry criteria.** A row may enter Step 4 only when its other class states are already present,
> evidenced in the register.
>
> **Required evidence.** A probe of the kind already running for `UIX-1` and `I-WRK-01`: a real
> target, a signed-in identity, the full chain traversed, **and the failure leg asserted** — the
> §2.1 text requires *"the correct failure behaviour"*, not merely a success path. The regression
> suite must be green in the same run.
>
> **Environment.** **QA only**, confirmed as `eyqtldjqpgpljlqvpowh` from a tracked file before any
> write. **Production `nxdbooufqzkpslkcogxc` remains out of scope, and Gate 9B is unaffected by
> Step 4 authorization** — approving Step 4 must not be readable as opening Gate 9B.
>
> **Independence.** The implementer of a fix may not be its end-to-end verifier, and the approver
> of the phase may not be either. *(This mirrors the coordinator's own enforced separation; note
> that in this repository identity is self-asserted, so independence is recorded, not proven.)*
>
> **Recording.** Authorization is valid only as a dated, written record naming the approver and the
> scope, stored in a governance document — not inferred from an instruction, a prompt, or a green
> CI run.
>
> **Completion.** A row completes Step 4 when its probe passes in CI with the failure leg asserted
> and the evidence reference recorded in the register.
>
> **Rows with missing evidence** stay where they are. Step 4 authorization does not promote
> anything by itself.
>
> **Relation to existing gates.** Step 4 is **not** a release gate and does not alter Gates 0–9.
> It supplies one `§2.1` evidence state. Nothing in this proposal changes a gate's wording.

### The one decision that must come first

**Who may authorize Step 4?** The sources do not say. Until that is answered the phase cannot be
started by anyone, and this proposal cannot be adopted. See `V5-GOV-006`.

---

# `MILESTONE 9` · three decision records — and a correction that changes Decision C

## ⚠ Correction first: `UIX-1` and `M-03` are **not** Step-4-blocked. They closed on 2026-08-28.

Milestone 7 listed them among the rows Step 4 gates. **That was wrong**, and the error is one this
programme has named before: I read a **dated record of an earlier position** as a current-state
claim.

The lines I cited (`registry:2727`, `:2739` — *"VERIFIED END-TO-END is absent and `UIX-1` is NOT
`VERIFIED_CLOSED`"*) are a §7.x checkpoint record. **§7.18 supersedes them:**

> *"### 7.18 `UIX-1` / `M-03` VERIFIED END-TO-END and `VERIFIED_CLOSED` — 2026-08-28 · evidence:
> CI run **#49** `33200559221`"* — with the `UIX-1` job `98949037130`, *"steps 1–7 all `success`"*,
> and the rung moving **`ABSENT` → `PRESENT`**, status **`REMEDIATED` → `VERIFIED_CLOSED`**.

`:1060` confirms it independently: *"`M-03` · P0 · ✅ `VERIFIED_CLOSED` 2026-08-28"*.

**So `VERIFIED END-TO-END` has already been obtained and accepted in this programme — twice —
while "Step 4 is not authorized to begin" remained true.** That is the single most useful fact in
this milestone, and it reframes Decision C.

### How it was done — the exercised mechanism

§7.18 records *"the owner ruling that **extends §7.13's standard to this rung for this row**"*. And
§7.13's standard is a **per-row owner ruling on closure class and rung satisfaction**, stated with
a deliberate limit:

> *"Owner ruling 2026-08-27: EC-01 is **RELEASE / ENVIRONMENT**… The ruling is **explicitly
> confined to EC-01** and does **not** extend to EC-05 or any other error-contract /
> false-success finding."*

So the pattern, exercised twice: **(1)** a CI job supplies the rung's evidence; **(2)** an owner
ruling, confined to the named row, establishes that this evidence satisfies that rung; **(3)**
§2.1's row and §3 step 12 are cited verbatim before the promotion.

---

## Decision A · `ENV-6` and the first-PR criterion

**Criterion, verbatim** (`registry:1594`): *"push-triggered runs proven; the row's own retest names
a PR run — **closes at the first PR**"*. Status: **`REMEDIATED`** (`:1523`).

**PR history, verified:** PR **#1** is the repository's **only** pull request, created
2026-10-12T17:45:05Z. **15** `pull_request` CI runs recorded, **9** successful; most recent
`38332911288`, all seven jobs green.

| | **Interpretation A** — PR #1 satisfies it | **Interpretation B** — it does not |
|---|---|---|
| evidence for | The criterion says *"the first PR"* and **adds no qualifier**. PR #1 is the first PR, it is a real `pull_request` event, and its runs are green — the condition as written is met. The row's concern (`:618`) was *"No CI, and the only workflow contacts production"*; PR-triggered CI demonstrably exists now | The row's purpose was to prove CI works **for product change**. PR #1 carries this programme's own queue infrastructure; its green runs partly exercise guards written in the same PR. A criterion meant to retire *"No CI"* arguably wants a PR that CI was protecting, not one that added CI tooling |
| consequence if chosen | `ENV-6` promotes from `REMEDIATED` on evidence already in hand. **No further work.** | `ENV-6` stays `REMEDIATED` until a product-change PR runs. **No work is unblocked by waiting**, and the row remains understated |
| risk | A reader later disputes that an infrastructure PR counted | The row stays open indefinitely if product PRs remain blocked — which they currently are |

**I am not selecting.** Both readings are available on the text, and the distinction is about
intent, which the text does not record.

---

## Decision B · `SEC-04`'s status transition

| question | answer, with evidence |
|---|---|
| **1 · Are the technical requirements satisfied?** | **Yes.** `:1585` names three: migration 124 (`124_wave_2a_security_regressions.sql` present) · the I-MIG-03 **class guard** (`migration-durability-guard.mjs`, twice in `ci.yml`, reporting *"established 116 → stripped 119 → restored 124"*) · the live 403 probe (`d04` §8, all five wrappers). The blocker `F-J-01` is `VERIFIED_CLOSED` (`:360`) |
| **2 · Does the evidence support classifying it as remediated?** | **The four states its class needs appear present** — FIXED IN CODE (116+124), FIXED ON QA (ledger; frontier 181), VERIFIED LIVE (d04's 403 probe), VERIFIED IN CI (the class guard + d04). Its class is **Security / authorization**, which `§2.1` gives four states and **no `VERIFIED END-TO-END`** |
| **3 · Does the standard permit `OPEN` → `VERIFIED_CLOSED`?** | **The standard does not say.** §2 defines `OPEN` as *"Suspected; needs a probe or a decision before it can be classified"*, and `§3 step 12` says *"Mark `VERIFIED_CLOSED` only when §2.1's required states all exist"* — which is a condition on the states, not on the starting status. **No source establishes whether the ladder may be entered at `OPEN` and exited at `VERIFIED_CLOSED` in one move** |
| **4 · Is an intermediate transition required?** | **Unestablished — this is the decision.** The §7.13/§7.18 precedent shows rows moving `REMEDIATED → VERIFIED_CLOSED`, not `OPEN → VERIFIED_CLOSED`. That is evidence about practice, not a rule |
| **5 · Which authority must approve?** | A **protected-register edit**, so the product owner. The §7.13 pattern also requires the ruling to **cite §2.1's class row and §3 step 12 verbatim** and to be **confined to the named row** |

**Not recommended for direct closure.** The requirements are met; the ladder question is open.

---

## Decision C · Step 4 authority — **reframed by the precedent**

**What I asked for in Milestone 7/8:** define Step 4 as a programme phase and name its approver.

**What the evidence now shows is actually needed:** possibly **neither**. `VERIFIED END-TO-END` was
established twice — EC-01's rung at §7.13, `UIX-1`/`M-03`'s at §7.18 — **without Step 4 being
authorized**, by a per-row owner ruling plus a CI job.

So there are **two routes**, and choosing between them is the decision:

| | **C1 · the exercised route** | **C2 · the programme-phase route** |
|---|---|---|
| what it is | A per-row owner ruling extending §7.13's standard to the `VERIFIED END-TO-END` rung for `SEC-R2` and `SEC-R3`, with a CI e2e job supplying the evidence | Define Step 4 — entry criteria, approver, scope, recording — and authorize the phase |
| precedent | **Twice exercised**, §7.13 and §7.18 | **Never exercised**; the phase is named once in all of `docs/` and never defined |
| cost | One ruling per row, plus building the probes | A governance definition, then an authorization, then the probes |
| what it leaves | *"Step 4 is not authorized to begin"* stays true, and the structural claim *"no safety finding can reach `VERIFIED_CLOSED` before Step 4 runs"* becomes **inconsistent with practice** — because two rows already did | A general mechanism, and the structural claim becomes true again |
| risk | Ruling-by-ruling drift; the §7.13 pattern's own *"explicitly confined"* language exists to prevent that, so each ruling is narrow by design | A large definition written once, for a phase that may never be needed as a phase |

**Still unresolved either way, and not inferable:** who may issue such a ruling is **recorded in
practice** (*"the product owner ruled"*) but **never stated as a rule**; and the structural
sentence at `:1805` now conflicts with §7.18's outcome. **That conflict is recorded here, not
resolved.**

**Neither route opens Gate 9B.** Production `nxdbooufqzkpslkcogxc` stays out of scope, QA only, and
no release gate changes.
