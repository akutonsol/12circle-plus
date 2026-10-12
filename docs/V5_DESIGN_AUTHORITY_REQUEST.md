# V5 · DESIGN AUTHORITY REQUEST — `DESIGN-01` and `DESIGN-02`

**Status: awaiting design authority. Nothing here is a specification, and nothing assumes the six
screens are sufficient.** Both items are recorded in `V5_OWNER_INPUT_PACKAGE.md` as
**`STATUS — DESIGN AUTHORITY REQUIRED`**. This document states exactly which artifacts are
missing, what the alternative on offer would actually imply, and which authority is needed — so
each can be answered without re-deriving the evidence.

> **PROVENANCE.** The approved design authority was published by commit **`931218b`** on
> `design/12circle-plus-admin-dashboard`, which is **not an ancestor of
> `reconcile/12circle-integrated`**. Citations below were made against that commit; read any of
> them with `git show 931218b:<path>`. This mirrors the note `check-design-citations.mjs`
> enforces (V5 §165), and is why file paths that are absent from this working tree are still
> quotable.

---

## Part I · `DESIGN-01` — the two `A11` state frames

`A11` requires eleven screen states. `SCREEN-INVENTORY.md` delivers **ten**. Two have no frame:
`critical-incident` and `Guardian-approval-required`.

**The position is not symmetric, and treating it as one wastes the decision.**

| | `critical-incident` | `Guardian-approval-required` |
|---|---|---|
| Specification | **complete** — `STATE-SPECS-A11.md` §1, every aspect cited to the approved design | **presentational half only** — §2 |
| Dependency | ***"No dependency. Every element exists."*** | **blocked on `P7`** — no approval-queue store exists |
| Implementation | **DONE** — `admin_attention_queue.dart`, title-case `Critical`, `--adm-color-status-danger-text`, literal zero copy *"none raised"* | renders the **Empty** pattern, which `SCREEN-INVENTORY.md` already designs |
| Asks below | **D1-1**, **D1-2** | **D1-1**, **D1-3** |

So **no engineering work is blocked on `DESIGN-01` today.** What is owed is visual approval and two
behavioural questions. `STATE-SPECS-A11.md` §4 records all three; they are restated here with the
question made answerable.

### `D1-1` · Visual frames for both states

**Missing artifact.** A designed frame for each state. `STATE-SPECS-A11.md` says of itself: *"It is
not a frame, and it does not replace one. Visual approval remains the design authority's."*

**What engineering cannot supply.** A specification derived from existing patterns is not an
approved composition. The derived spec may be faithful and still be the wrong design.

**Options.** `1` supply both frames · `2` ratify the derived specification as the frame, in writing
· `3` defer, and `critical-incident` continues to ship on the derived spec as it does today.

**What it blocks.** Nothing in engineering. It is an approval gap, not a build gap — and that is
worth stating plainly, because the item has sat in a queue of blockers that it does not belong in.

### `D1-2` · Does a `Critical` item escalate the page chrome?

**Missing artifact.** The populated-page treatment. The approved pages show `Critical` **only in
its zero case** outside the attention queue — *"Critical vulnerabilities — None"*, *"Critical
alerts — 0 — none raised"*, *"Critical findings — 0 — none open"*. The one populated instance is a
queue **item**. So whether a live `Critical` changes anything **above** the item — a page banner, a
strip colour, the environment strip — **is unobserved, not merely unstated.**

**What engineering cannot supply.** Inventing a banner is inventing UI where design authority is
absent. The item-level treatment was implementable precisely because it *was* observed; this is
not.

**Options.** `1` item-level only — a `Critical` item is styled, the page is not (**this is what
ships today**) · `2` escalate the page chrome, and supply its treatment · `3` defer.

**What it blocks.** Nothing currently rendering. It decides whether a future page-level escalation
is in scope at all.

### `D1-3` · Where does Guardian approval happen?

**Missing artifact.** The approval affordance. The drawer rule is explicit — *"Actions open the
item. Nothing is changed from this screen."* — so the Dashboard displays the state and does not
approve from it. **Where approval does happen is unspecified.**

**Not independent of `P7`.** `STATE-SPECS-A11.md` §3 is unusually direct: *"The state can be
specified. It cannot be made operational, and this document does not pretend otherwise."*
*"Awaiting human review — 2"* needs a queue of actions awaiting approval; **no such store
exists**, and what an approvable Guardian action *is*, what approving it *does*, and what
rejecting it *does* are established nowhere. `AI Guardian · Approve` is registered
**NON-OPERATIONAL** for exactly this reason; `B-17` supplied the state store only, which is why
`Manage` is operational and `Approve` is not.

**Options.** `1` answer the affordance now, to be built when `P7` lands · `2` defer until `P7` is
ungated · `3` rule that approval never happens in the Dashboard, which closes the question without
a frame.

**What it blocks.** `P7`. It does not block anything outside it. **Inventing the queue to make
this frame "complete" is the one thing that must not happen**, and this request does not.

---

## Part II · `DESIGN-02` — per-component specification sheets

### What exists, measured

`COMPONENTS.md` enumerates the component set in use and then states: *"A separate per-component
specification sheet (anatomy, variants, spacing annotations) has **not** been produced. Listed as
missing."*

| | count |
|---|---|
| Component types enumerated in `COMPONENTS.md` | **32** (shell 4 · containers 5 · data 8 · inputs 8 · feedback 7) |
| With a `###` specification section in `COMPONENT-SPECS.md` | **24** |
| Enumerated types with **no** specification section | **9** |
| Specification sections that are **design-authority approved** | **0** |

That last row is the actual gap, and it is easy to miss because `COMPONENT-SPECS.md` looks like the
missing sheet. It is not. Its own provenance section is titled **"derived, not designed"**, and it
derives from the screens' **inline styles** because *"the referenced `_ds/nocturne-…` bundle is
**absent from the package** (0 files)"*.

**The nine with no specification section:** timeline · audit row with before/after diff · radio ·
date range · toast · inline error · skeleton · permission-denied panel · read-only banner.
*(timeline, radio and toast appear once each as a passing mention, with no section.)*

### What the six-screen alternative would actually imply — and the measured problem with it

The alternative `COMPONENTS.md` offers is *"a ruling that the six `.dc.html` screens are sufficient
specification and components may be derived from them."*

**For the 24 already derived, that ruling is close to a formality.** It would convert
`COMPONENT-SPECS.md` from an engineering derivation into the authority, which is a real and useful
decision — it is what the Flutter admin surfaces are already built against.

**For the remaining nine, it supplies nothing, and that is measurable.** Searching all seven
`screens/*.dc.html` sources at `931218b`:

| probed term | occurrences across the screens |
|---|---|
| `toast` | **0** |
| `skeleton` | **0** |
| `type="radio"` | **0** |
| `date` | **0** |
| `timeline` | **0** |
| `read-only` | **0** |
| `permission` | **0** |

**A component that is not in the screens cannot be derived from them.** So "the screens suffice"
would leave those nine with **no authority at all** — not with derived authority. It is not
equivalent to supplying the sheet, and the difference is nine components, several of which are
`A11` state surfaces (`skeleton`, `permission-denied panel`, `read-only banner`) that
`SCREEN-INVENTORY.md` designs as *patterns* while `COMPONENTS.md` also lists them as *components*.

### A note on the "3 of ≈30" figure, to prevent a category error

`V5_OWNER_INPUT_PACKAGE.md` records *"The Helix implementation ships **3** of ≈30."* That compares
two different axes and should not be read as 10% progress toward `DESIGN-02`:

* **Helix** is the brand-neutral **React** design system. It ships `Button`, `Card`,
  `MetricReadout` and now `Icon` — **4**.
* **The Admin dashboard is Flutter** (`apps/mobile/lib/features/admin/presentation/`), built
  against `COMPONENT-SPECS.md`'s derived values, not against Helix's React components.

Adding `Icon` under `Q5` therefore moved the Helix count 3 → 4 and moved `DESIGN-02` **not at all**,
because `DESIGN-02`'s gap is the **specification**, not an implementation count. Counting a
component derived without an approved spec as progress against the item that asks for approved
specs would be the inference the standing constraints forbid.

### Options

`1` **supply the per-component sheet** — anatomy, variants, spacing annotations, for all 32 ·
`2` **rule that the six screens suffice** for the 24 that are derivable, **and** supply or defer
the nine that are not in the screens *(this is option 2 made honest; the ruling as written in
`COMPONENTS.md` does not distinguish them)* ·
`3` **ratify `COMPONENT-SPECS.md` as authoritative** for the 24 and record the nine as out of scope
for V1 ·
`4` defer.

**What it blocks.** No current surface — the Flutter admin pages ship against the derived values.
It governs whether those values are **authoritative** or **provisional**, and therefore whether a
later visual correction is a bug or a change.

---

## Part III · What authority is needed

| ask | authority | can engineering proceed without it? |
|---|---|---|
| `D1-1` frames | **design authority** (visual approval) | yes — `critical-incident` already ships on the derived spec |
| `D1-2` escalation | **design authority** (unobserved treatment) | yes — item-level only is the current behaviour |
| `D1-3` approval affordance | **design authority + `P7` gate** | no, for `P7`; yes for everything else |
| `DESIGN-02` sheet / ruling | **design authority** | yes — surfaces ship against derived values |

**None of the four blocks currently executable engineering work.** They decide whether what ships
is authorized or merely unobjected-to. That distinction is the reason this request exists rather
than a build plan.

**Nothing in this document specifies a frame, a component or a behaviour**, and the six screens are
not assumed sufficient — Part II measures the point at which they stop being sufficient, and names
the nine components where that happens.
