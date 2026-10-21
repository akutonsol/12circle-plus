# Q6 · the nine domain placements — retrieved, and found already determined

**Asked:** retrieve the exact nine unresolved domain-placement questions, their options and
the governing evidence, and present them as one decision table. **Do not infer or invent
mappings. Do not implement until the selections are recorded.**

**Found:** the premise no longer holds. **There are not nine open placements.** Every domain
has a published section home, and the one placement question the design authority itself
records was answered by `METRIC-19` on 2026-10-07. **Nothing is implemented here**, and no
mapping is inferred — each row below cites the artifact that states it.

---

## 1 · Why the count was nine, and why it is stale

§97.4 recorded P5 as blocked on *"nine domain placements"*, and §10457 explains the
reasoning: *"the owner reaffirmed the six-item IA **and** the twelve domains; reaffirming
both does not map one onto the other, and **every dropdown is closed in all four
screens**."*

That was true when written. **Two things happened afterwards:**

1. **The design authority was published** (commit `931218b`), and it is not four screens
   with closed dropdowns — it is **six screens with their sections enumerated in writing**.
   `SCREEN-INVENTORY.md` carries an explicit `Page → Top-level nav → Sections on the page`
   table, and states that *"the older eight-item navigation in the build spec … is
   historical and is **not** used."*
2. **The owner answered the one genuine placement question** — see §3.

So the mapping §10457 said nobody had performed **is published**, and the gap it describes
is closed by the artifact rather than by a decision.

---

## 2 · The mapping, as published — all 17 matrix areas

The authoritative IA is **six items** (`CONF-D1`, answered at §91.1): *Dashboard · People ·
Ecosystem · Trust · Operations · Settings*. The authorization matrix (migration 155,
"Owner (Julia) approved the complete 85-cell / 425-grant authorization policy" — 17 areas ×
5 verbs = 85 cells × 5 roles = 425 grants) carries **17 areas**. Every one has a home:

| # | Matrix area | Published section home | IA page | Evidence |
|---|---|---|---|---|
| 1 | **AI Guardian** | `#ai-guardian` | **Trust** | SCREEN-INVENTORY Trust row; Dashboard also carries an "AI Guardian" card |
| 2 | **Audit logs** | `#audit` (explorer, `#audit-event` before/after) | **Trust** | Trust row; Dashboard "Recent admin activity"; *"every 'View audit history' link deep-links to Trust > Audit logs"* |
| 3 | **Community** | `#community` | **Ecosystem** | Ecosystem row; Dashboard "Events & community" |
| 4 | **Configuration** | `#platform` (General), `#notifications`, AI & intelligence, `#privacy`, `#billing` | **Settings** | Settings row |
| 5 | **Events** | `#events` | **Ecosystem** | Ecosystem row; Dashboard "Events & community" |
| 6 | **Incidents** | `#incidents` | **Trust** | Trust row; Dashboard attention queue |
| 7 | **Integrations** | `#integrations` (health) · `#integrations` (configuration) | **Operations** · **Settings** | Operations + Settings rows — see §4 |
| 8 | **Monetization** | `#monetization` | **Ecosystem** | Ecosystem row; Dashboard revenue |
| 9 | **Organization** | `#organization` | **Settings** | Settings row |
| 10 | **QA** | "QA & release" | **Dashboard** | Control Center row |
| 11 | **Releases** | `#releases` | **Operations** | Operations row |
| 12 | **Roles** | `#roles` (Roles & permissions) | **Settings** | Settings row |
| 13 | **Security** | `#security` incl. `#sec-authz` · `#security` (configuration) | **Trust** · **Settings** | Trust + Settings rows — see §4 |
| 14 | **System** | `#system` (`#sys-events`) | **Operations** | Operations row; *"Settings links across to Operations > System events"* |
| 15 | **Training** | `#training` | **Ecosystem** | Ecosystem row |
| 16 | **Users** | `#users`, `#coaches`, `#clients`, `#partners` · `#users` (Administrators) | **People** · **Settings** | People + Settings rows — see §4 |
| 17 | **Wearable intelligence** | `#wearables` | **Ecosystem** | Ecosystem row; Dashboard card |

**Areas with no published section home: NONE.**

---

## 3 · The one placement the design authority itself recorded — already answered

The package's own `BOUNDARIES.md` lists **seven** unresolved boundaries (A–G) and exactly
**one** is a placement:

> **B** | *Notifications Overview group is in the spec; no corresponding area on the
> approved Dashboard* | **Owner decision required (placement)** | *Requirement kept; no
> placement invented*

That became **`METRIC-19`** in the decision sheet — recorded there as *"new, from the design
package's own boundary list"*, with options *1 place it under Operations · 2 place it on the
Dashboard · 3 out of scope for V1*.

**You answered it: `METRIC-19 = Option 3` — out of scope for V1. Nothing authored.**

So the sole placement question the design authority raises is closed, by you, on
2026-10-07.

---

## 4 · Three domains appear twice — and that is not an ambiguity

`Integrations`, `Security` and `Users` each appear under two IA pages. The published section
labels disambiguate them, and the pattern is consistent: **an operational view and a
configuration surface are different sections of the same domain.**

| domain | operational view | configuration surface |
|---|---|---|
| Integrations | **Operations** `#integrations` — health | **Settings** `#integrations` — connection config |
| Security | **Trust** `#security`, `#sec-authz` — events and authorization | **Settings** `#security` — security settings |
| Users | **People** `#users`/`#coaches`/`#clients`/`#partners` — the member population | **Settings** `#users` — Administrators |

The inventory confirms the split is deliberate: *"Settings links across to Operations >
System events, Trust > Authorization and Trust > AI Guardian."* Settings holds the
configuration and **links out** to the operational view.

**No selection is required to resolve these**, and none is invented here.

---

## 5 · The other six boundaries, for completeness — five already closed

| # | Boundary | State |
|---|---|---|
| **A** | Attention severity — `Critical/High/Warning/Informational` vs screens' `CRITICAL/HIGH/MEDIUM/LOW` | **CLOSED** — `METRIC-12` dissolved by evidence: `CRITICAL` appears zero times; the queue uses the shipped enum |
| **C** | spec "Platform Health" vs approved "Infrastructure" | **OPEN** — design/product reconciliation, **not** a placement |
| **D** | `PD-C03` currency | **CLOSED** — `METRIC-06a = Option 1`, USD source + explicit recorded FX |
| **E** | partner approval states · coaching gross vs commission · attention severity · `PD-A24` console ingestion · which impressions | **CLOSED** — `METRIC-05=2`, `METRIC-06b=1`, `METRIC-12`, `METRIC-16=2`, `METRIC-18` direction `K` |
| **F** | Admin data layer · AI Guardian · service health · CI feed · wearable coverage · append-only audit store | **PARTLY CLOSED** — data layer, AI Guardian, audit store and the CI surface are built (156–178); **service health** and **wearable coverage** remain (the latter under `PD-G01`) |
| **G** | Admin `--adm-*` tokens vs Helix tiers | **CLOSED** — §176: the token set is a deliberate normalisation of the screens' literals, and `CONF-D6-B` locked the Helix token authority |

---

## 6 · What this means for P5, and what is NOT claimed

**P5's last recorded gate is satisfied by published authority rather than by a new
decision.** Combined with §182.1 (`CONF-D6` resolved; `CONF-D7` satisfied and implemented)
and §182.2 (Trust IA satisfied), **none of P5's four recorded gates remains open.**

**Nothing was implemented for Q6, and no mapping was inferred.** Every row cites the
artifact that states it. Two things that are genuinely open are named rather than folded in:
**`BOUNDARIES C`** (Platform Health vs Infrastructure — a design/product reconciliation) and
**`BOUNDARIES F`**'s remainder (service health; wearable coverage, which is `PD-G01`).

**This document records a reconciliation. It is not an owner selection**, and no placement is
treated as authorized by it.
