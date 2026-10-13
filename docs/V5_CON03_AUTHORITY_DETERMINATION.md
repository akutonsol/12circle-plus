# CON-03 · authority determination — **Outcome A**, and a correction to my own prior reports

**No registry edit was made.** `MASTER_REMEDIATION_REGISTRY.md`, `MASTER_PRODUCT_DECISIONS.md`,
`MASTER_REMEDIATION_WAVES.md` and `QA_CLOSURE_STANDARD.md` are untouched. No production contact, no
QA write, no migration. SEC-R2/SEC-R3 statuses and evidence counts unchanged.

---

## ⚠ Correction first — I classified CON-03 wrongly in four milestones

Milestones 6, 7, 11 and 12 recorded CON-03 as *"blocked by governance — needs the production column
type, and Gate 9B forbids reading it."* **That is wrong**, and three authoritative sources say so.

**How the error happened:** I read the registry's one-line summary —
`MASTER_REMEDIATION_REGISTRY.md:182`, *"`dietary_restrictions` — two serializers, one column, **prod
type unknown**"* — and treated *"prod type unknown"* as the blocker. I never traced it to
`MASTER_PRODUCT_DECISIONS.md`, **the document I myself established in Milestone 5 as the authority
for owner decisions**. I cited that document as authority and then did not consult it on a question
it governs.

---

## 2 · The authoritative requirement

### `PD-A22` — `docs/MASTER_PRODUCT_DECISIONS.md:136`

Table columns are `| ID | Decision | Blocks | Options | Recommendation | Proceed? | Owner | Wave |`.

| field | content |
|---|---|
| **Decision** | *"Production's `dietary_restrictions` column type. QA is `text`; the in-code comment asserts `text[]`, implying an out-of-band production change. **This is a fact-finding action requiring explicit authorization to read production**"* |
| **Blocks** | `CON-03`, `Q-6`, `ENV-11` |
| **Options** | *(a)* authorize a **read-only** production schema inspection · *(b)* **write the forward migration to converge from either starting type without inspecting** |
| **Recommendation** | *"**(b) now, (a) before rollout.** (b) is required regardless; (a) is a prerequisite for the production rollout plan, **not for QA work**"* |
| **Proceed?** | **"Yes — via (b)"** |
| **Owner** | **Julia** (§0: *"`Julia` denotes product authority"*) |
| **Wave** | 4 / 8 |

**Read precisely, because the distinction matters:** *"Yes — via (b)"* sits in the **Proceed?**
column, which §0 defines as *"Can engineering proceed?"* It is **not** a record that PD-A22 has been
answered. The document states of itself: *"**Nothing in this document is decided.** Where a
recommendation is possible it is given"* (`:6`), and PD-A22 is **not** listed in §0.1 *"Decisions
already closed — do not re-open"* (which names only `PD-A20`).

So: **the decision is open; proceeding is authorized.** Those are different things and both are true.

### Corroboration — two independent sources

* `docs/MASTER_REMEDIATION_WAVES.md:335` — *"`CON-03` (one serializer, one type; the forward
  migration must converge from **either** starting type **because production's is unknown**)"*
* `docs/MASTER_QA_RECONCILIATION.md:513` (`Q-6`) — *"**Production was not inspected and will not be
  without explicit authorization.** The forward migration must be written to converge from either
  starting type; **confirming prod's actual type is a prerequisite to a production rollout, not to
  QA work**."*

### Answering the central question exactly as posed

> *What evidence or decision is authorized to establish the column type governing CON-03, and is
> QA's column type permitted to govern this decision?*

**Neither type governs, and none needs to.** The authorized route (b) requires the forward migration
to **converge from either starting type**, which removes the need to establish *any* governing type
for the QA remediation. QA's type (`text`) is **not** elevated to govern — it is simply one of the
two starting points the migration must handle.

**No source grants permission to inspect production.** PD-A22 option (a) and `Q-6` both say the
opposite: explicit authorization would be required, and it has not been given. Gate 9B stands.

**Scope:** route (b) is specific to this column's forward migration. It does **not** generalize —
it is not a precedent that QA evidence may stand in for production evidence anywhere else, and
PD-A22's option (a) remains outstanding **for the production rollout plan**.

---

## 3 · Outcome

**Outcome A — explicitly authorized route, with a scope correction to the option as worded.**

The milestone's Outcome A is phrased as *"a QA-type ruling"*. The sources authorize something
narrower and better: **not** that QA's type governs, but that **no type need be established** for
the QA-side fix. Recorded that way rather than forced into the template.

* **Source** of authority: `PD-A22`'s **Proceed? = "Yes — via (b)"**, with *"(b) is required
  regardless"*, corroborated by `MASTER_REMEDIATION_WAVES.md:335` and `Q-6`.
* **Authorized role**, where named: **Julia** (product authority) owns PD-A22.
* **Not** authorization for a QA write or a live probe. Route (b) is a **forward migration**, and
  migrations are prohibited in this milestone — so the route is **authorized but unexecuted**.

---

## 4 · Permitted next action — the smallest step

**Write CON-03's forward migration under route (b)**: one type, one serializer, converging from
either `text` or `text[]` without inspecting production. That needs a migration-authorizing
milestone, not a new owner decision.

**What is NOT needed:** PD-A22's answer, production access, or a ruling that QA's type governs.

---

## 5 · Dependency verification — re-derived from source, not copied

| item | verified state | source |
|---|---|---|
| **CON-03** | **route authorized, NOT executed.** No longer classifiable as production-blocked | `PD-A22` · `WAVES:335` · `Q-6` |
| **SEC-R2** | **blocked.** Row still `❌ **absent**` for `VERIFIED END-TO-END`, *4 of 5 present* | `REGISTRY` SEC-R2 row |
| **3B ordering** | *"**Strictly ordered** — this is Workstream B's sequence and it is correct"*; 3B-0 → 3B-1 → 3B-2 → 3B-3 → 3B-4 → 3B-5 confirmed in order | `WAVES` §3B |
| **3B-1** | **NOT startable.** Needs CON-03 *resolved* (migration unwritten) **and** SEC-R2 (blocked). An independent audit agrees: *"❌ `SEC-R2` is not `VERIFIED_CLOSED` — four of five states"* | `WAVES:287` · `WAVE_3B_WRK07_EC11_EC05_AUDIT.md:96` |
| **3B-4** | **NOT startable.** Behind 3B-1; the only stated parallelism is 3B-2 ∥ 3B-4 | `WAVES` §3B |
| **SEC-R3** | **NOT startable.** Needs the 3B-4 service fix, then a probe, then its own per-row C1 acceptance | `V5_SECR3_FAILURE_PATH_READINESS.md` |

**The hypothesised sequence holds, with one amendment.** `CON-03 + SEC-R2 → 3B-1 → 3B-2 → 3B-3 →
3B-4 → SEC-R3` is confirmed — but **CON-03's contribution is no longer an owner decision; it is
unwritten work**. That changes what unblocks it, not where it sits.

**Resolving CON-03 does not make 3B-1 startable.** SEC-R2 independently blocks it.

---

## 6 · What this changes about "the shortest unblock"

Milestone 12 called CON-03 *"the shortest real unblock… the only one of the five that needs neither
a probe nor a prior row."* **The conclusion survives but the reasoning was wrong**: CON-03 is short
not because an owner decision is cheap, but because **no owner decision is needed at all** — only a
migration under an already-authorized route.

**SEC-R2 remains the binding constraint on 3B-1**, and it needs a live probe plus a per-row ruling.
