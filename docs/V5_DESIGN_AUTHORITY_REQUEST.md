# V5 · DESIGN AUTHORITY REQUEST — `DESIGN-01` and `DESIGN-02`

> ## ✅ DECIDED BY THE OWNER, 2026-10-12
>
> | id | decision | state |
> |---|---|---|
> | `D2-1` | **`D2-1a`** — ratify the derived specifications as authoritative for the **24 components the approved screens actually depict** | **ratified** |
> | `D2-2` | **`D2-2b`** — ratify the depicted state patterns, specify the four genuinely absent, rule explicitly on the audit row | **partly closed — see the two halves below** |
> | `D1-1` | **option 2** — ratify the derived specifications as the frames for `critical-incident` and `Guardian-approval-required` | **ratified** |
> | `D1-2` | **option 1** — retain item-level `Critical` styling, no page-level escalation | **ratified, and already true in the code** |
> | `D1-3` | **option 2** — defer Guardian-approval behaviour until `P7` is ungated | **deferred, `P7` still gated** |
>
> ### `D2-1a` — what exactly was ratified
>
> `COMPONENT-SPECS.md` holds **24** `###` sections, one per depicted component. Worth stating
> plainly: that file is **not** in `931218b`. `931218b` is the approved *source* (screens,
> `COMPONENTS.md`, `SCREEN-INVENTORY.md`, `brand/tokens/admin.tokens.{css,json}`);
> `COMPONENT-SPECS.md` is this programme's **derivation from** it. `D2-1a` ratifies the derivation
> for the 24 depicted, and for nothing else.
>
> ### `D2-2b`, first half — the depicted components, ratified
>
> From the corrected measurement (§213.2), four of the nine are depicted and are ratified on the
> same basis as `D2-1a` — their screens show them:
>
> | component | class | evidence in `931218b` |
> |---|---|---|
> | `skeleton` | Feedback / state | *"Skeleton rows at real size. No layout jump."* |
> | permission-denied panel | Feedback / state | the state copy *"Permission restricted"* |
> | read-only banner | Feedback / state | *"Read-only"* state values, *"Decisions are read-only"* |
> | `timeline` | **Data, not a state pattern** | *"Event timeline"*, *"Incident timeline — today"*, each heading an `<ol>` |
>
> The decision calls these *"the four depicted state-pattern components"*. Three are exactly that;
> **`timeline` is a Data-class component**, ratified on the identical ground (its screens depict it)
> but named correctly here so the register does not record it as a state pattern.
>
> ### `D2-2b`, second half — the four absent, and the line I will not cross
>
> `COMPONENTS.md` ends with its own authority clause:
>
> > *"Specs (sizes, colours, radii) are the values in `../brand/tokens/admin.tokens.*`;
> > **interactive behaviour is in the page files**."*
>
> That splits the four cleanly, and the split is the answer to *"specify them from approved
> authority"*:
>
> | | authorized source | status |
> |---|---|---|
> | **visual values** — colour, radius, size, spacing | `admin.tokens.{css,json}` at `931218b`, which exist and carry `control` · `danger` · `warning` · `radius` · `size` · `space` | **derivable — approved authority covers it** |
> | **anatomy and behaviour** — what parts a `toast` has, where it appears, how long it persists; whether `date range` is two fields or a calendar; what `inline error` attaches to; `radio` grouping and keyboard model | *"the page files"* — **and the page files do not depict these four** | **NOT derivable. Nothing approved says it.** |
>
> So `COMPONENTS.md` **enumerates** the four — they appear once each, in a comma-separated list of
> names (*"…checkbox, radio, search, date range"*, *"toast, inline error, empty state…"*) — and
> routes their behaviour to a place that does not contain them. The enumeration is why they are in
> the 32; the routing is why they cannot be specified from it.
>
> **The decision authorizes the need for specification, not the visual details.** Per your own
> instruction, I am therefore requesting the minimum remaining design input rather than inventing
> it:
>
> #### `D2-3` · minimum remaining design input (NEW, open)
>
> For each of `radio`, `date range`, `toast`, `inline error` — **anatomy and behaviour only**;
> colours, radii and sizes are already settled by the tokens:
>
> 1. **`radio`** — is it used at all, or does `segmented control` (already depicted) cover every
>    single-choice case? If used: group orientation and whether a group has a visible label.
> 2. **`date range`** — two text inputs, a single range picker, or presets ("7 d / 30 d / custom")?
>    The screens show *"Permission changes · 7 d"*, which **suggests** presets, and a suggestion is
>    not a specification.
> 3. **`toast`** — placement, dismissal (auto after *n* seconds, manual, both), and whether it is
>    used for errors at all or only confirmations, given `inline error` exists separately.
> 4. **`inline error`** — what it attaches to (field, row, panel) and whether it replaces or
>    accompanies the content it reports on.
>
> #### `D2-4` · the audit row — posed explicitly, NOT resolved by me
>
> The enumeration names *"audit row with **before/after diff**"*. The screens depict the row's
> **field list** — *"Event, actor, resource, before/after, correlation"* — and **no diff UI**.
>
> **I am not treating a list of field names as a designed diff treatment.** Per your instruction,
> the question is left explicit:
>
> * `D2-4a` — the field list **is** the specification; the diff is rendered at implementer's
>   discretion from the tokens.
> * `D2-4b` — the diff **requires a designed treatment** (how a before/after pair is laid out,
>   truncated, and marked for added/removed/changed), and that design does not yet exist.
>
> ### `DESIGN-01` — all three
>
> * **`D1-1` (option 2) ratified.** The derived specifications are the frames for both states.
> * **`D1-2` (option 1) ratified — and already true.** `admin_attention_queue.dart` carries
>   item-level severity only; a search for page-level escalation (a page banner, an escalated
>   `appBar`, a page-wide severity colour) finds **none**. No code change was needed, and none was
>   made.
> * **`D1-3` (option 2) deferred.** Guardian-approval behaviour stays unimplemented while `P7` is
>   gated. **No approval queue was invented and no gated behaviour was built.**


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

### `DESIGN-02` is TWO decisions, and answering it as one cannot work

The ruling `COMPONENTS.md` offers — *"the six screens are sufficient specification"* — does not
distinguish the components the screens **depict** from the ones they **do not**. Measured across
the six non-superseded `screens/*.dc.html` at `931218b`, all nine undepicted components return
**zero** occurrences: `toast` · `skeleton` · `type="radio"` · `date` · `timeline` · `read-only` ·
`permission` · `audit row` · `before/after` / `diff`. So a single ruling would silently decide two
different things, and one of them it cannot decide at all.

#### `D2-1` · Are the six screens authoritative for the components they DO depict?

**Scope: the 24 with a specification section in `COMPONENT-SPECS.md`.** These are derived from the
screens' inline styles — the only available source, since the referenced `_ds/nocturne-…` bundle is
absent from the package (0 files). The Flutter admin surfaces already ship against these values.

| option | consequence |
|---|---|
| `D2-1a` **ratify** — the screens are authoritative, and `COMPONENT-SPECS.md` is their faithful derivation | the shipped values become authorized. A later visual correction is a **change**, not a bug |
| `D2-1b` **supply the sheet** for these 24 — anatomy, variants, spacing annotations | the derivation is replaced by designed specification; any divergence found becomes a **bug** |
| `D2-1c` **defer** | surfaces keep shipping against values that are provisional rather than authorized |

**What engineering cannot supply:** whether a faithful derivation is the *intended* design. The
derivation can be accurate and still be the wrong composition.

> ## ⚠ CORRECTION, 2026-10-12 — the "all nine measure zero" claim was wrong
>
> An earlier revision of this document, and two checkpoint reports, stated that **all nine**
> undepicted components return **zero** occurrences across the six screens. **That measurement was
> produced by a broken command.** The screen filenames contain spaces; the probe iterated them with
> an unquoted `for f in $SCREENS`, so `git show` received one malformed path and failed on every
> iteration. **Every zero was a failed command, not an absent term** — and it is the same shape as
> the other defects this programme has recorded: output that cannot distinguish "nothing found"
> from "nothing ran".
>
> Re-measured with a line-based loop and **positive controls** that prove the probe works
> (`card` 16, `Settings` 35, `div` 2159):
>
> | component | occurrences | context | verdict |
> |---|---|---|---|
> | `timeline` | **6** | *"Event timeline"*, *"Timeline and audit history"*, *"Incident timeline — today"*, each heading an `<ol>` | **depicted** |
> | `skeleton` | **3** | *"Skeleton rows at real size. No layout jump."* | **depicted** — the state pattern |
> | permission-denied | **34** | includes the state copy *"Permission restricted"*; the rest are a metric and a table caption | **depicted** — the state pattern |
> | read-only | **5** | *"Read-only"* as state values; *"Decisions are read-only; no override from this page"* | **depicted** — the state pattern |
> | audit row w/ before-after diff | **1** | *"Event, actor, resource, before/after, correlation"* — the row's **field list**, not a rendered diff | **partial** |
> | `type="radio"` · date range · toast · inline error | **0** | — | **genuinely absent** |
>
> **So the undepicted set is four, possibly five — not nine.** `SCREEN-INVENTORY.md:25` independently
> corroborates three of them: *"Permission (denied)… Offline and **Skeleton** (Ecosystem, People),
> **Read-only** (Operations, Settings, Trust)"*, with "State system" panels on four pages showing the
> patterns side by side.
>
> The decision below is reframed accordingly. **The error was mine, it was reported twice, and the
> corrected set makes `D2-2` materially smaller.**

#### `D2-2` · What authority governs the components the screens do NOT depict?

**This is the decision `D2-1` cannot reach.** A component absent from the screens cannot be derived
from them, so *"the screens suffice"* leaves these nine with **no authority at all** — not with
derived authority. Three of the nine are `A11` **state surfaces** (`skeleton`,
`permission-denied panel`, `read-only banner`) that `SCREEN-INVENTORY.md` designs as *patterns*
while `COMPONENTS.md` also lists them as *components*, so for those the question is partly whether
the pattern already is the specification.

| option | consequence |
|---|---|
| `D2-2a` **ratify the depicted four as specified by their screens** — `timeline`, `skeleton`, permission-denied, read-only — and supply specifications for the **four genuinely absent** (`radio`, date range, `toast`, inline error) | closes `DESIGN-02` completely, and the ratification half is nearly free because the screens and `SCREEN-INVENTORY.md` agree |
| `D2-2b` as `D2-2a`, **plus a ruling on the audit row**: the screens name its fields (*"Event, actor, resource, before/after, correlation"*) but depict no diff UI, so say whether the field list is the specification or the diff needs one | the only genuinely ambiguous member, decided explicitly rather than by omission |
| `D2-2c` **record the four absent as out of scope for V1** | `DESIGN-02` closes as scoped-out. Any later need reopens it |
| `D2-2d` **defer** | they stay unspecified and unowned |

**Engineering has built none of the nine against an invented spec**, and will not. Where one is
needed, the absence is the finding.

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
