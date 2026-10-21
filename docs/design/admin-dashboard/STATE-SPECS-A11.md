# `DESIGN-01` — THE TWO UNDESIGNED `A11` STATES

> **PROVENANCE — where the cited design artifacts actually are.** The approved
> 12Circle+ design authority was published by commit **`931218b`** on the branch
> **`design/12circle-plus-admin-dashboard`**, which is **not an ancestor of
> `reconcile/12circle-integrated`**. So `admin.tokens.css`, `admin.tokens.json`,
> `admin.contrast.md`, `admin-icon-inventory.md`, `RESPONSIVE.md`, `SCREEN-INVENTORY.md`,
> `COMPONENTS.md` and the `screens/` sources named below are **not in this branch's
> working tree**. Read any of them with:
>
> ```
> git show 931218b:docs/design/brand/tokens/admin.tokens.css
> ```
>
> Every citation in this document was made against that commit. `check-design-citations.mjs`
> enforces this note's presence — see V5 §165.


**`A11` requires eleven screen states. `SCREEN-INVENTORY.md` delivers ten** — Loading · Empty · Error ·
Permission-denied · Degraded across all six pages, plus Unavailable · Stale · Offline · Skeleton · Read-only,
with dedicated *"State system"* panels on People, Trust, Operations and Settings.

**Two have no frame: `critical-incident` and `Guardian-approval-required`.**

## What this document is, and what it is not

**It is a specification derived from patterns the approved pages already contain**, in the same way
`COMPONENT-SPECS.md` derives component anatomy from inline styles. Both states already appear in the approved
design **as content**; what is missing is their treatment **as a state pattern**.

**It is not a frame, and it does not replace one.** Visual approval remains the design authority's. Where the
design establishes nothing, this records a dependency rather than inventing behaviour — which is why §3 below
stops rather than finishing the Guardian case.

---

## 1 · `critical-incident`

### Precedent in the approved design

| page | observed |
|---|---|
| Control Center | attention queue item — **`Critical`** · *"Security · 14 min ago · Open"* · *"38 failed sign-ins on one coach account from 3 countries"* · action **Investigate** |
| Control Center | Security card — *"Critical vulnerabilities — None"* |
| Trust | *"Critical alerts — 0 — none raised"* |
| Operations | *"Critical findings — 0 — none open"* |

**So the design already specifies both poles**: the populated critical case (attention queue) **and** its
zero case (*"none raised"* / *"none open"* / *"None"*), which is the state pattern.

### Specification

| aspect | value | source |
|---|---|---|
| Severity label | **`Critical`** — title case | the shipped `A2`/`143:70` enum, and what the attention queue renders |
| Severity colour | `--adm-color-status-danger-text` `#f07a8c` (7.4:1 on canvas) | `admin.contrast.md` |
| Container | card — `background #121215` → `--adm-color-bg-surface`, `border-radius 16px` → `--adm-radius-xl`, inset ring `rgba(255,255,255,0.08)` | `COMPONENT-SPECS.md` › Card |
| Badge | status pill, `border-radius 999px`, `letter-spacing 0.08em`, `font-weight 600` | `COMPONENT-SPECS.md` › Severity badge |
| Icon | `ph-fill ph-warning-circle` — the fill weight already used for active/critical (21 uses) | `admin-icon-inventory.md` |
| Zero state | the literal copy the design uses: **"None"** · **"none raised"** · **"none open"** — *not* an empty panel | three pages, consistently |
| Action | a single primary action per item (**Investigate**), never bulk | attention queue |
| Read-only | the drawer footer is explicit: *"Actions open the item. **Nothing is changed from this screen.**"* | `CONF-D5` README |
| Responsive | at ≤900px the item collapses to single column, 44px touch target | `RESPONSIVE.md` |

**No dependency.** Every element exists. `audit_incidents.severity` already ships the `Critical` value, and
`admin_incidents` (170) already projects `severity` to the Admin layer.

---

## 2 · `Guardian-approval-required`

### Precedent in the approved design

| page | observed |
|---|---|
| Control Center | Guardian card — autonomy ladder *"Observe · Analyze · Recommend · Reversible action · Human only"*, **"Awaiting human review — 2"**, *"Recommendations · 24 h — 17"* |
| Control Center | attention queue — **`High`** · *"AI Guardian · 2 h ago · **Awaiting human**"* · *"Guardian recommends pausing an AI plan that rai…"* |
| Operations | a capability row **"Approve — Approve a release"** |
| Settings | the capability matrix rendered with **Update · Manage · Approve** columns |

### Specification — the presentational half

| aspect | value | source |
|---|---|---|
| Label | **"Awaiting human review"** (counter) · **"Awaiting human"** (queue item) | Control Center, both verbatim |
| Severity in the queue | **`High`**, not `Critical` | attention queue |
| Autonomy ladder | five rungs, **"Human only"** terminal | Guardian card |
| Icon | `ph-fill ph-seal-check` for approved, `ph-fill ph-warning-circle` for awaiting | `admin-icon-inventory.md` |
| Guardian state coupling | the card also carries Guardian state — **Active / Monitoring / Degraded / Disabled** (`A5`), now backed by `guardian_state` (migration 169) | `A5` · Build Spec §5 |
| Read-only | same drawer rule: the state **displays**; it does not approve from the Dashboard | `CONF-D5` README |

### 3 · WHERE THIS STOPS — the dependency, recorded rather than invented

**The state can be specified. It cannot be made operational, and this document does not pretend otherwise.**

*"Awaiting human review — 2"* requires a **queue of actions awaiting approval**. **No such store exists**, and
the action's shape — what an approvable Guardian action *is*, what approving it *does*, what rejecting it
*does* — is established nowhere in the record.

- **`AI Guardian · Approve` is registered NON-OPERATIONAL** for exactly this reason, with its three-leg proof
  running every suite.
- **`P7` owns the queue.** It remains gated.
- **`B-17` supplied the state store only** — `guardian_state` and emergency disablement — which is why
  `AI Guardian · Manage` is operational and `Approve` is not.

**Inventing the queue to make this frame "complete" is precisely what must not be done.** The presentational
specification above is usable the day `P7` supplies the data; until then the panel renders its **Empty**
pattern, which `SCREEN-INVENTORY.md` already designs.

---

## 4 · What remains owed to the design authority

| # | item | why engineering cannot supply it |
|---|---|---|
| D1-1 | **Visual frames** for both states | a specification is not a frame; approval is the design authority's |
| D1-2 | The **critical-incident escalation treatment** — whether a `Critical` item changes the page chrome (banner, strip colour) or only the item | the pages show `Critical` **only in the zero case** outside the attention queue, so the populated page treatment is unobserved |
| D1-3 | The **Guardian approval affordance** — the drawer says *"Nothing is changed from this screen"*, so where approval happens is unspecified | depends on `P7` |
