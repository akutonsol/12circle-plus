# V5 autonomous run — 2026-10-07 — consolidated owner pack

**Fourth revision.** **Q6 closed by existing authority** (§183). **Q8, Q9 and Q10 answered
by the owner** and discharged in §191 — Q9 built the Guardian emergency-disable control under
Trust → AI Guardian; Q8 and Q10 ratified the existing state and changed no behaviour. Two new
questions arrived from continuing the frontier rather than from re-reading it: **Q11** and
**Q12** below. The §190 traversal and the §193/§194 design-requirement audits found **three
censuses that miscounted what they were describing**, which is why both new items came from
re-running a measurement rather than from new work.

**Third revision.** A full eleven-phase V5 traversal (§182) replaced the earlier P0-only
census and added the two items below, **Q6** and **Q7** — the single gates on the only two
phases that are partially executed. It also found **two recorded gates already satisfied**;
see §0b.

**Second revision.** The first version of this pack carried twelve items. **Six are now
closed** — by existing authority, by measuring the published artifacts, or because I had
re-asked something already answered. They are listed in §0 so the same questions are not
rediscovered later.

Nothing below blocked the run. Each entry states what was built, so "no change needed" is
a valid answer.

---

## 0 · CLOSED since the first revision — do not re-ask

| was | why it is closed |
|---|---|
| **A2 · should `60+` be a real bucket?** | **Already answered, by you.** The directive that authorized METRIC-17 says: *"Do not invent a 60+ bucket. Any genuinely 60+ records … must remain in the appropriate reconciliation/unknown handling rather than being silently assigned to an invented category."* That is exactly `age_out_of_range`. **I re-asked a question you had answered in the same message that set the task.** |
| **A3 · where are METRIC-16/18/19 ledgered?** | Resolved by evidence. The non-operational register is keyed by `(area, verb)` **capability** and its validator cross-checks every row against the approved matrix; a Dashboard **card** cannot be expressed in it. The programme ledger is the only coherent home. |
| **B1 · which subject owns a multi-assignment program's feedback?** | Resolved by evidence (§175.2). `generate_client_plan` (`121:221`) inserts a fresh program then **exactly one** assignment, so a generated plan is 1:1 with its client by construction; and `weekly_feedback` is `unique (program_id, week)`, so a template assigned to N clients cannot have one row per week **whichever** subject were chosen. Not a model to choose — an incoherent state. Now a monitored invariant in D17. |
| **B2 · should an unknown coaching mode require approval?** | Resolved by **authority**, then fixed (§175.1, migration 177). `product-bible:111` forbids bypassing the matrix for coach-guided clients, `:116` forbids a claim it cannot ground, `decision-log:18` licenses auto-apply **only** for AI/self-guided, and `MASTER_PRODUCT_DECISIONS:63` says of this very function that silently disabling the matrix is *"a hard-constraint violation… **No decision needed**"*. |
| **C2 · the untokenised severity colour** | Resolved by measuring the package (§176). The approved screens hold **zero `var(--adm-*)` references and 447 literal hex values**; `admin.tokens.css` is **derived from** them and **normalises** — `#f07a8c` ×80 vs `#f08a9b` ×15, six danger-tint alphas collapsed to one, `11px` chosen over `11.5px` as a scale step. Reading from the tokens is **conformance**, not deviation. §168.2 corrected. |
| **A1 · METRIC-02's weekly window** | **Superseded, and I asked the wrong question.** The data contract (`:98`) names the sub-questions the definition must settle, and the week is not among them. See **Q1** and **Q2**, which are. |

---

## 0b · CLOSED by the phase traversal (§182.1, §182.2)

| was | why it is closed |
|---|---|
| **`CONF-D7`** — the Admin role matrix, recorded as P5's gate and as *"the largest security specification gap"* | **Satisfied and implemented.** Migration **155**'s header records *"Owner (Julia) approved the complete 85-cell / 425-grant authorization policy"*. The matrix is seeded at **116 rows** with its authority named, `validate-admin-capability-matrix.mjs` holds it there, and D14 proves all **425** combinations. Every surface in this programme gates on it. |
| **Trust IA** — recorded as P5's gate and as P6's blocker (*"the surface with NO approved design"*) | **Satisfied.** The design publication postdates §97.2 and contains an authoritative six-item IA plus a **286 KB Trust screen** with named sections (`#overview`, `#ai-guardian`, `#security`, `#incidents`, `#audit`, `#trust-system`) and stated data requirements — **all four of which already have shipped surfaces** from the CONF-D8 work. |

So **P5's four recorded gates are now one**, and **P6 is no longer blocked on design**.

---

## 1 · Open questions

**Q1 · In which timezone is "today" measured?** *(data contract `:98`, explicitly unsettled)*
METRIC-02 = Option 3 settled *which events count* and nothing else. The windows are
currently **UTC**, because that is the database's timezone. Migration 176 **publishes**
the boundaries rather than choosing — `day_start`, `week_start`, `month_start`,
`window_timezone` are columns, and the card renders *"Day begins 2026-10-07 00:00 UTC"*.
**Blocks:** nothing — the figures are correct and now self-describing. **Needed for:** a
DAU figure that matches how the business thinks about a day.

**Q2 · Does a coach or partner count as an "active user", or only clients?** *(same line)*
The counts are over **every** user with a Session, no role filter — as shipped. A filter
would be a business definition, so none was invented. **Blocks:** nothing.

**Q3 · Release the CI-ingestion path for METRIC-11?** Your ruling settled what the card
shows, and that is built. The **ingestion** path is a separate item the data contract
records at `:220` as `C · ARCHITECTURE`, citing `P10`'s *"installation forbidden"* and
`CONF-D9` — neither released. The registry starts empty and D16 asserts it is empty, so
nobody can seed it to make the dashboard look finished. **Blocks:** only live values on
that one card.

**Q4 · Merge the design branch, or keep commit-pinned citations?** `931218b` on
`design/12circle-plus-admin-dashboard` is **not an ancestor of this branch**. The token
layer is generated from it by `git show`, four documents carry a provenance block, and a
guard fails CI on any design citation that resolves nowhere. **Blocks:** nothing.

**Q6 · ~~The nine domain placements — the SOLE remaining gate on P5.~~ CLOSED BY EXISTING
AUTHORITY (§183).** Do not re-ask. Retained here only so the earlier revision's numbering
stays readable; the five-point authority check and the supersession-by-the-record's-own-terms
reasoning are in §183. *(§182.1)*
You reaffirmed the **six-item IA** and the **twelve domains** separately; reaffirming both
does not map one onto the other, and every navigation dropdown is closed in all four
screens. **Blocks:** the remaining Control Center scope, and therefore P6 → P7 behind it.
**Does not block:** anything already built — the metric surfaces, the token layer, the
panel, the attention queue and `/admin-metrics` are all live and CI-verified without it.

**Q7 · `D-1` — the SEC-W1 negative-control reconstruction mechanism.** *(§182)*
`§16.1` lists it under *"What remains owner-controlled"*, blocking *"QAX-SEC-08's fourth
rung — **and nothing else**"*. Three of its four rungs are held. **Blocks:** one rung of one
P1 finding. **Does not block:** any other P1 work, and nothing downstream.

**Q5 · Add a Phosphor icon dependency?** The inventory names **107 icons** across the Admin
pages. My implemented surface uses **one**, substituted with a Material fill-weight
equivalent and labelled as a substitution. **Blocks:** nothing today; the cost grows with
the Admin build-out.

---

## 1b · ANSWERED by the owner on 2026-10-07, and discharged

| id | ruling | what it changed |
|---|---|---|
| **Q8** · role assignment | *Keep Change Role restricted/unbuilt. Do NOT widen `admin_set_user_role` to `Users·Update` holders. `Users·Update` does not implicitly confer authorization-management authority. Preserve the existing 403.* | **No behaviour changed.** D18 §3's live assertion is promoted from evidence for an open question to the **ratchet for a ruling**, and its text says so: a failure now means a ruled boundary moved, not that the diagnosis is stale (§191.4). |
| **Q9** · Guardian emergency disablement | *Place the control under Trust → AI Guardian. Implement only the approved UI placement and required confirmation/A11 treatment. Do not broaden authorization.* | **BUILT** (§191.2). Gated `AI Guardian·manage` — `trust_lead` alone, proved live against the matrix. Only `'Disabled'` is reachable; the other three `A5` states have no approved affordance and the card says so. The control never asserts its own outcome — it re-reads the stored row. **D19 · 22/22 live.** |
| **Q10** · program-template authoring | *No surface for V5. Record the capability as deferred/unexposed unless existing governance requires another status.* | **No UI.** The escape clause applied: `non_operational` means *no write path*, and `B-22` already records Training as **implemented** with two working RPCs — an entry there would have asserted something false in the file whose purpose is to be true about the schema. The register is **unchanged**; the deferral is recorded as a **UI-exposure** deferral (§191.5). |

---

## 1c · NEW — two questions that came from re-running a measurement

| id | question | why it is yours, and what is already true |
|---|---|---|
| **Q11** · **What is churn?** | The published Control Center requirement list names **churn** between "revenue by stream" and "service health feed". It is **absent from the metric decision sheet's twelve IDs** — it was never put to you as a decision, so it is the one Dashboard requirement with no ruling at all. | It appears in the monetisation roadmap beside MRR and ARPU, and `COWORK` §8 forbids agents inventing monetisation, so no definition was chosen. The card now **states the absence with that reason** rather than leaving a blank (§194.1). A ruling needs: the denominator population, the window, and what event constitutes leaving. |
| **Q12** · **Is a Control Center audit tail wanted, or is the Trust deep-link the answer?** | The Dashboard requirement list ends with *"audit-log tail"*. `admin_audit_events` already backs it, so this is **buildable today** — but `SCREEN-INVENTORY` also states that *"every 'View audit history' link deep-links to Trust > Audit logs"*, which reads as the interaction model already answering it. | Nothing was built, because the two statements point different ways and duplicating the projection is a placement decision rather than a mechanical one. The Dashboard card states the absence and names Trust as where the projection lives. |

---

## 2 · New since the first revision

**N1 · A coach is now asked to approve an action the engine does not execute.**
A direct consequence of my own fix. `ENG-02`/`ENG-14` are remediated, so `evaluate_week`
now returns `needs_approval = true` for a coach-guided client — including for
`REPLACE_EXERCISES`. But `ENG-13` (P2, Wave 5, source-cited at `094:80-140`) records that
`regenerate_program` **implements only two of its own four actions**: it mutates
`volume_multiplier` and `is_deload`, and *"no exercise is ever substituted"*. So the
approval path is now live for a change that will not be applied. **This is strictly better
than the previous state** — the matrix was inert and changes auto-applied — but it is a
real seam, and it was not visible before the fix. **Decision:** prioritise `ENG-13`, or
accept the seam until Wave 5.

**N2 · `EC-03`'s end-to-end rung is not built.** `QA_CLOSURE_STANDARD` scores it in the
*"Error contract / false success"* class, which requires **VERIFIED END-TO-END** for a
user-facing state. `EC-04`'s rung now exists (a device probe reading the real accessibility
tree, new CI job `ec04-e2e`). EC-03's needs a driver that makes the save genuinely fail —
a harder fixture that touches onboarding. **Recorded as remaining frontier, not claimed.**

**N3 · INFRASTRUCTURE BLOCKER, local only.** `xcode-select -p` is
`/Library/Developer/CommandLineTools` and there is **no `Xcode.app`**, so `xcrun` cannot
find `xcodebuild` and the macOS desktop target cannot build on this machine. Installing
Xcode needs your machine and your password. **Blocks:** running device probes *locally*.
**Does not block:** CI, which has the Linux desktop target and runs them.

---

## 3 · Recorded debt — no decision needed unless you want it prioritised

| # | item |
|---|---|
| **D1** | Two legacy display coercions remain in `SEC-G4`'s shrinking allowlist — `observability_screen:62` and `admin_dashboard_screen:224` render a missing figure as `0` on the pre-token console. |
| **D2** | `_saveProgress` Phase 2 is still `catch (_) {}` — the progressive autosave, with `_finish()`'s full upsert as its backstop. |
| **D3** | **`MASTER_REMEDIATION_REGISTRY.md` is outside this run's mutation boundary and was not edited**, so `I-COM-01`, `EC-04`, `EC-03`, `ENG-02` and `ENG-14` still read `READY_TO_REMEDIATE`. `REMEDIATION_PROGRESS.md` cannot carry them either — it states *"This board never leads the registry."* Their evidence is §169–§177. |
| **D4** | `DESIGN-01` §2's `Guardian-approval-required` state remains unimplemented; that document deliberately stops short of specifying it. |
