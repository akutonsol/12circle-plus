# V5 · Owner decision pack — Q11 · Q12, and the carried queue

> ## ANSWERED 2026-10-07 — both decisions are now owner-ruled and implemented
>
> **Q11 = Option B**, subscription churn, event-based. **Q12 = Option A**, actor-anonymous
> audit tail. Both are implemented and verified in **§197**; this pack is retained as the
> evidence record that produced them, and the options below are **historical**, not open.
>
> | | ruling | implementation | evidence |
> |---|---|---|---|
> | **Q11** | cancellations during the month ÷ active at month start | migration `180`: `subscriptions.canceled_at` nullable, **no backfill**; writer = the existing `stripe-webhook` `customer.subscription.deleted` handler; rate **NULL** until any cancellation is ever recorded | **D20 · 23/23 live**, incl. the decisive pair (numerator `0` with rate `NULL`) and the transition to a **real** `0` once capture is proven |
> | **Q12** | action · category · outcome · timestamp · disclosure; **no actor names** | `_RecentAdminActivity` on the Control Center, reading the existing `admin_audit_events` | **D20 §6** proves the projection carries **no name or email column at all**, so the constraint is enforced by the surface and not only by the widget |
>
> Recorded as **METRIC-20** in `V5_METRIC_DECISION_SHEET.md`.
>
> **§202 added `Q15` and `Q16`** — both open in the programme record and **absent from this
> pack**, found by traversing `BOUNDARIES.md`, the design's own list of unresolved boundaries,
> which no earlier pass had reconciled against this queue. They are carried items rather than
> new discoveries, and the omission was mine.
>
> `Q13` remains **unresolved and unpatched** by explicit
> instruction, now with narrowing evidence. **`Q14`'s premise is WITHDRAWN** — it rested on a
> reading I took while my own test fixture was live; see §197.4 and the queue below.

**This pack as written implemented nothing.** Q11 and Q12 were retrieved, evidenced and
optioned; no definition was chosen, no duplicate audit projection was built, and the Trust
deep-link was not touched.

One **correction of fact** was made, because it was a misstatement rather than a decision: the
Control Center's "not shown" card said the audit tail belongs on Trust. The approved screen
renders a tail *here*. See Q12 §1.

---

## Q11 · What is churn?

### 1 · The exact governing requirement

`SCREEN-INVENTORY.md` at `931218b`, line 33 — the Dashboard's *"Data each page needs (approved
design requirement; implementation/architecture capability required)"*:

> *"**Dashboard:** user counts by role; DAU/WAU/MAU; revenue by stream; **churn**; service
> health feed (six tiles); AI Guardian autonomy level and findings; wearable sync status; QA and
> release status (from CI); install, age-range and impression series; audit-log tail."*

### 2 · What the design says beyond that: nothing

**`churn` appears exactly ONCE in the entire approved design corpus** — that word, in that
line. Measured across all 116 design documents at `931218b`:

| source | churn mentions |
|---|---|
| `SCREEN-INVENTORY.md` | **1** (the line above) |
| all six `.dc.html` screens | **0** |
| `BOUNDARIES.md`, `COMPONENTS.md`, `PROVENANCE.md`, `RESPONSIVE.md`, `README.md` | **0** |
| `12CIRCLE_ADMIN_CONTROL_CENTER_DASHBOARD_BUILD_SPEC_V1.docx` | **0** |

**There is no label, no sample value, no unit and no tile.** This matters because it removes the
method that settled the two most recent metric questions: METRIC-06b and §193's "Clients served"
were both resolved by reading the approved card's own arithmetic (2210/141 = 15.7, not 13.5).
**For churn there is no number to read.**

The build spec's Revenue section instead names: *"MRR, subscriptions, transactions, refunds,
revenue trend, monetization activity"* — **churn is not among them.**

### 3 · Is there existing V5 authority? No.

* **Absent from `V5_METRIC_DECISION_SHEET.md` entirely** — zero mentions. The sheet carries
  twelve IDs (METRIC-02 · 03 · 05 · 06a · 06b · 11 · 12 · 13 · 14 · 16 · 17 · 18 · 19). Churn
  was **never put to you as a decision**, which makes it the only Dashboard requirement with no
  ruling in either direction.
* `ROADMAP_AI_MONETIZATION_UNIT_ECONOMICS.md` — **"Status: Approved roadmap direction"** — names
  it three times, each as a bare bullet with no definition:
  * §"Business metrics": `churn`, beside contribution margin, gross margin, CAC, LTV, LTV:CAC,
    break-even member count
  * `churn modeling`, under simulation
  * §"**Retention**": **`monthly churn`**, beside `annual retention` and `cohort retention`
* `COWORK` §8 **forbids agents inventing monetisation**, and `V5_PROGRAMME_DEFINITION:12131`
  already records this class: *"the roadmap names MRR/ARPU/churn but not the split. **Owner —
  and `COWORK` §8 forbids agents inventing monetization**."*

`monthly churn` is the single most definition-adjacent phrase in the corpus. It fixes a
**window** and neither a **population** nor a **leave-event**.

### 4 · The data evidence — measured on QA, read-only

**The only cancellation timestamp in the entire schema** is
`coach_client_relationships.cancelled_at` (migration `025:19`). There is **no**
`subscriptions.canceled_at` / `ended_at`, **no** subscription-history or membership-events
table, and **no CHECK** on `subscriptions.status`.

`subscriptions` (`022:14`, plus `023`/`038`) carries: `kind`, `coach_id`, `status` (default
`'incomplete'`), `current_period_end`, `cancel_at_period_end`, `plan_tier`, `created_at`,
`updated_at`.

Measured on QA today:

| population | observed |
|---|---|
| `subscriptions` | **173 rows, every one `status = 'active'`** |
| `subscriptions.cancel_at_period_end = true` | **0** |
| `subscriptions.current_period_end` populated | 173 |
| `coach_client_relationships` | 175 — **174 `active`, 1 `cancelled`** |
| `coach_client_relationships.cancelled_at` populated | **0 — including the cancelled row** |

**Three consequences, stated rather than worked around:**

1. **No churn is observable today in any form.** Zero cancellations carry a date, zero
   subscriptions are flagged to lapse, and every subscription is active. Whatever definition you
   rule, the figure's first honest value is an `A11` empty state, not a number.
2. **The one cancelled relationship has no `cancelled_at`.** A `status` of `'cancelled'` with a
   null timestamp means the single leave-event in the database is **invisible to any windowed
   measure**. That is a data-integrity gap independent of churn, and it is reported, not patched
   — a NOT NULL or a trigger here would be inventing a write contract.
3. **`subscriptions.kind` is `'app'` on all 173 rows**, while `022:17-19`'s own comments document
   the vocabulary as `'coach' | 'self_guided' | 'ai_guided'`. There is **no CHECK**, so the drift
   is reachable and unrecorded. A churn-by-plan breakdown therefore has **no plan signal on QA**.
   Carried below as **`Q13`** — it is a vocabulary question, which is yours.

`subscriptions` is **not read by any admin surface or by the admin Dart layer today**; §178's
revenue reads `payments`, not `subscriptions`.

### 5 · The smallest set of viable interpretations — not a recommendation

Each is stated with what it would measure, what it needs, and what it cannot see. **I am not
selecting one**; every one of them picks a population and a leave-event, which is product
authority.

| option | definition | needs | cannot see |
|---|---|---|---|
| **A · Subscription churn, state-based** | share of `subscriptions` not `active` at the end of a month | nothing new — readable today | *when* anyone left; it is a snapshot, so a member who left and rejoined inside the window is invisible. Yields **0%** on QA now, which is a true state and a misleading figure. |
| **B · Subscription churn, event-based** | cancellations in a month ÷ active at month start | **a new column** — `subscriptions.canceled_at`, plus a writer to set it | nothing, once populated — but it is **not retrospective**: every month before the column exists is permanently unmeasurable. |
| **C · Coach-relationship churn** | `coach_client_relationships` cancelled in a month ÷ active at month start | **backfill of `cancelled_at`**, which is null on every row including the cancelled one | membership churn. This measures *leaving a coach*, not *leaving 12 Circle* — a client who changes coach would count as churned. |
| **D · Activity churn** | members with a Session last month and none this month | nothing new | anything about paying. It also collides with **`Q2`** (whether coaches and partners count as active) and with **`Q1`** (which timezone bounds a month). |
| **E · Defer, render `A11` empty** | no figure; the card states that no churn definition is ruled | nothing | — this is **what is shipped today** (§194), so choosing it is a no-op and the honest default. |

**Two observations that are evidence, not advice.** The roadmap's own phrase is *"monthly
churn"* under *"Retention"*, which fits **B** and **C**'s shape and not **A**'s. And **B** is the
only option that is correct going forward and silent about the past, so the cost of deferring is
measured in months of unrecoverable history.

---

## Q12 · The Control Center audit tail

### 1 · The two exact sources — and they are not in conflict

**`SCREEN-INVENTORY.md` line 29, "Interactions expected", verbatim:**

> *"Attention queue opens a drawer; **every "View audit history" link deep-links to Trust >
> Audit logs**; before/after diffs deep-link to a Trust audit event; Settings links across to
> Operations > System events, Trust > Authorization and Trust > AI Guardian; global search and
> filters on tables; row actions open confirm dialogs for destructive changes."*

**`SCREEN-INVENTORY.md` line 33, the Dashboard requirement:** *"… audit-log tail."*

**And the approved Control Center screen itself renders the section.** `12Circle Admin Control
Center.dc.html` at `931218b` carries **"Recent admin activity"** → **"Audit log"**, with four
sample rows:

| row | label | time |
|---|---|---|
| *"J. Park changed Coach role → Senior coach"* | Permission change | 10:41 |
| *"Guardian flagged an AI plan for review"* | System · AI Guardian | 09:58 |
| *"D. Mac signed in"* | Admin login · MFA | 09:02 |
| *"Release 4.2.0 deployed to staging"* | Release · CI | Sat |

**So the apparent conflict dissolves.** The interaction line governs a **link**; the requirement
and the screen place a **tail**. The design asks for both, and my earlier §194 note — that the
projection belongs on Trust — was wrong about placement and is corrected.

**The screen's own "Requires architectural verification" panel already flags it:** *"Audit log.
Recent activity assumes an append-only admin audit table. Unconfirmed."* That store now exists.

### 2 · What is actually blocking it: the four designed rows, not the placement

`admin_audit_events` (`156`) projects `id, actor_id, subject_pseudonym, action, occurred_at,
outcome, category, actor_provenance, correlation_id`, gated `admin_can('Audit logs','view')`,
and carries **`A13·1`** in its own predicate:

```sql
AND NOT (e.category = 'admin_action' AND e.actor_id = (SELECT auth.uid()))
```

`audit_events.category` is a **15-value CHECK** (`152`): `phi_read`, `phi_correction`,
`financial`, `incident`, `agent_action`, `control_evidence`, `admin_action`,
`observability_audit`, `authentication`, `authorization_denial`, `billing_entitlement`,
`relationship_change`, `storage_media_access`, `export_deletion`, `audit_read`.

Mapping the four designed rows against that:

| designed row | category | status |
|---|---|---|
| role change | `admin_action` | **exists** — but excluded from its *own* actor by `A13·1`, so the tail is deliberately incomplete for its reader |
| Guardian finding | `agent_action` | **category exists, producer does not** — the Guardian runtime is `B-17` / `P7` |
| admin sign-in | `authentication` | **exists** — but *"MFA"* is not a recorded fact |
| release deployed | *"Release · CI"* | **no such category.** Release state lives in `release_status` (`173`), a separate registry. **A release is not an audit event** under the ruled vocabulary. |

**And all four name the actor.** `actor_id` is in the projection as a raw uuid; the Trust audit
card **renders no actor at all** today, which is the standing precedent. Naming *"J. Park"*
requires resolving `actor_id → user_profiles`, making a dashboard a **standing resolver of actor
identity**. For completeness about what does *not* forbid it: **`B-4` is scoped to Incidents**
(*"withhold `evidence` AND `actor_identity`"*, implemented in `160`'s `admin_incidents`), and
**§19.3 governs pseudonyms** — the *subject* is pseudonymised, the *actor* is not. So actor
naming is **unruled**, not prohibited, and that is precisely why it is yours.

### 3 · Options

| option | what ships | implications |
|---|---|---|
| **A · Build the tail, actor-anonymous** | the last N `admin_audit_events` rows showing action · category · outcome · time, plus `A13·1`'s disclosure. No actor name. | **No new surface, no new grant, no schema.** Consistent with the Trust precedent. Two of four designed row types simply will not appear (no producer / no category), and the rows that do appear will not read like the design's samples, which are written as sentences naming people. |
| **B · Build the tail, actor-named** | as A, plus resolving `actor_id` to a name | Matches the design's samples. Makes the Control Center the **first** standing resolver of actor identity in this layer, and that is a privacy posture change — not forbidden by `B-4` or §19.3, and not authorized by them either. Would want its own capability review. |
| **C · Link only** | no tail; the card states the projection is on Trust and links there | What the page did before §194. Satisfies the *"Interactions expected"* line and **not** the Dashboard requirement or the rendered section. |
| **D · Defer, state the absence** | what is shipped today, with the corrected reason naming the producer and category gaps | Nothing is built on an unruled identity posture; the gap is visible rather than silent. |

### 4 · Recommendation

**Option A**, with **D** as its honest interim — and the reasoning is narrow enough to state in
one line: *A is the only option that needs no new authority.* It reuses an existing gated
projection, adds no grant and no schema, keeps the actor-identity posture exactly where every
other audit surface in this layer already has it, and renders the two row types that have both a
category and a producer. The two it omits are omitted **because they do not exist**, which the
card can say.

**I am not recommending B**, and the reason is a posture rather than a preference: a figure that
names people is cheap to add and extremely hard to take back, and the record authorizes it
nowhere. If the sample rows' sentence form is the point of the requirement, that is worth
deciding deliberately rather than inheriting from a mock-up.

**Nothing was built either way.** Today's card states the absence with the corrected reason.

---

## Carried unresolved decisions

| id | question | blocks |
|---|---|---|
| **Q1** | In which timezone is "today" measured? METRIC-02 settled *which events count* and nothing else. Windows are **UTC** and migration 176 **publishes** them (`day_start`, `week_start`, `month_start`, `window_timezone`); the card renders *"Day begins … 00:00 UTC"*. | **Nothing.** Figures are correct and self-describing. Needed for a DAU that matches how the business thinks about a day — and for **Q11 option D**. |
| **Q2** | Does a coach or partner count as an "active user", or only clients? Counts are over **every** user with a Session, no role filter, as shipped. | **Nothing.** Also an input to **Q11 option D**. |
| **Q3** | Release METRIC-11's CI ingestion (`P10` / `CONF-D9`). `release_status` (173) and `admin_release_status` exist and accept recorded verdicts; nothing ingests from CI. | The *automatic* half of "QA and release status (from CI)". The registry and surface are built. |
| **Q4** | Merge the design branch, or keep commit-pinned citations? **54 citations resolve at `931218b`**, 5 in-tree, **0 dangling**, guarded by `check-design-citations.mjs`. | **Nothing.** A convenience and provenance question. |
| **Q5** | The Phosphor icon dependency — 107 icons eventually, 1 today. | **Nothing.** |
| **Q7** | **`D-1`** — the SEC-W1 negative-control reconstruction mechanism. | **`QAX-SEC-08`'s fourth rung, and nothing else.** Three of four rungs hold. |
| ~~**Q11**~~ | **ANSWERED — Option B.** Recorded as `METRIC-20`; implemented in §197. | — |
| ~~**Q12**~~ | **ANSWERED — Option A.** Implemented in §197. | — |
| **Q13 · CARRIED, explicitly not to be decided or patched** | **`subscriptions.kind` carries `'app'` on all 173 QA rows**, while `022:17-19` documents `'coach' \| 'self_guided' \| 'ai_guided'`. There is **no CHECK**. Which is authoritative — the comment, or the data? | Any plan-level breakdown, including **Q11 by plan**. Not blocking anything built: no admin surface reads `subscriptions`. |
| **Q14 · PREMISE WITHDRAWN on evidence (§197.4)** | I reported *"one cancelled relationship has no `cancelled_at`"*. **That reading was taken while one of my own fixtures was live** — `D01` flips a relationship to `cancelled` during its run, and at `d01:217`/`:232` it sets `cancelled_at` explicitly. Measured with no suite running: **176 relationships, every one `active`, `cancelled_at` populated on zero rows** — an empty population, not a writer gap. And there is no gap: **three production paths** set it in the same write as the status (`coach_relationship_service.dart:104`, `profile_screen.dart:918`, `intake_flow_screen.dart:4188`). | **Nothing.** A `NOT NULL` or trigger would now be a policy choice with no observed defect behind it. Kept visible rather than deleted, because a question put to an owner on a bad measurement should be corrected where it was asked. |

| **Q15 · CARRIED — and it was missing from this pack** | **Which attention severity vocabulary is authoritative?** `BOUNDARIES.md` row **A**: *"spec says Critical / High / Warning / Informational; approved screens show CRITICAL / HIGH / MEDIUM / LOW"*, classified *"owner decision required"*. | **Nothing is at risk today.** The shipped enum is the spec's four, enforced by a CHECK (`143:70`), and `_severityColor` renders an unrecognised value **neutrally rather than guessing it into a danger colour** — so a `MEDIUM` arriving would be legible, not mis-coloured. The record already narrowed this three times (§12132): spec and shipped enum agree, `Risk` is a distinct axis, and **a fifth value — `"Severity set to Elevated"` — appears in Trust**, so the design's own vocabulary is not internally settled. |
| **Q16 · CARRIED — also missing from this pack** | **Which Helix theme is canonical?** `BOUNDARIES.md` row **G** calls `--adm-*` versus the Helix tiers an *"architecture question"*, and §103.2 found something sharper: **two artefacts both claim to be the 12Circle Helix theme.** The in-repo Dart implementation (`core/helix/` + `twelve_circle_theme.dart`) is **violet, Schibsted Grotesk, conformance-tested in CI**; `/Users/dmac/Documents/projects/helix`'s `src/themes/12circle.ts` is **electric lime `#9EF01A`**, Hanken Grotesk / Clash Display, and its own header says *"FIRST PASS — values are meant to be tuned by design."* §103.1 also established that **eleven of eleven shared colour roles match** between the Admin tokens and the in-repo theme — *"one design system, not two that happen to agree."* | **Nothing in this repository**; the enforced in-repo theme is the live one. It matters for **whatever consumes Helix next**: a future product binding to the lime first pass would import a different brand. §103.2's own words: *"Which is canonical is a design-system authority decision and is not made here."* |

**Recorded debt, no decision needed unless you want it prioritised:** `EC-02`'s registry
contradiction (`:709` `BLOCKED_DECISION` on Q-5 against `:782` *"lands now"*) remains
deliberately unreconciled per §4-H. Debts D1–D4 stand.

---

## What remains executable without these decisions

**Within P5 and P6: nothing.** That is a measured claim, not a shrug — it was arrived at twice:

* **§190.1's surface inventory, recounted from code.** Every `admin_*` **view** in the schema is
  read by the app (12 of 12). Of 13 `admin_*` **functions**, 9 are called; the 4 that are not are
  each refused for a recorded reason — two program-template RPCs with no approved affordance
  (`Q10`), `admin_set_user_role` (`Q8`), `admin_set_guardian_state` **now built** (`Q9`).
* **§193–§195's requirement traversal**, re-run against the published *"Data each page needs"*
  list for all six pages. It found three censuses that miscounted, all now closed: People's
  fourth requirement (**built** — migration 179), Settings' prose count (code was already
  right), and the Control Center's seven unstated absences (**now stated**).

**Outside P5/P6, every branch is blocked by a boundary that is not Q11 or Q12:**

| branch | blocked by | kind |
|---|---|---|
| **P7 · AI Guardian** | **`B-17`** — the runtime half is `ARCHITECTURE_EXTENSION` with *"Decision required: architecture"*, and the non-operational register states the Guardian action's **shape is undefined** | architecture |
| **P1**'s fourth rung | **`Q7` / `D-1`** | owner |
| **P3 → P4 → P8 → P9** | **`PD-G01`** — *"APPROVED — FUTURE BUILD · implementation NOT AUTHORIZED"* | governing authority |
| **P10** | the *"installation forbidden"* constraint | external / infrastructure |
| **`ENV-3`**'s live ledger rung | needs **`QA_DB_URL`** in CI. The ledger *was* observed locally (`179 \| 179`, matching `expected_applied.json`), but parsing CLI output is the weaker method `env3-live-check.mjs` explicitly rejects, so the rung is not claimed | infrastructure |
| **`EC-03`** | **closed**, including its END-TO-END rung and a CI negative control | — |

**So Q11 and Q12 block exactly their own two Dashboard requirements and nothing else.** Neither
is on any other phase's critical path, and no other branch is waiting on them.

**Production was not contacted at any point.**
