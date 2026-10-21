# V5 — OWNER / DESIGN-AUTHORITY INPUT PACKAGE

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


**Prepared 2026-10-06 against QA frontier 170 · CI green 6/6 · live regression 844/844 · AI 49/49 ·
characterizations 17/17 · Flutter 1706/5 skipped · production never contacted · tree clean.**

**Nothing in this document was implemented.** No option was selected, no metric defined, no vocabulary
invented, no design artifact fabricated. Every fact is read from the governing source and cited.

---

## 0 · A CORRECTION I MUST LEAD WITH — `P5` IS FAR CLOSER THAN I REPORTED

My last two reports said `P5` was blocked on four missing design artifacts: the 11 Admin states, responsive
behaviour, component specifications and iconography.

**Three of those four are DELIVERED.** I was quoting the `CONF-D5` README, which describes what **four
screenshots** do not establish — **not** what the published design package contains. The package lives on
`origin/design/12circle-plus-admin-dashboard` and I had already ingested it once (§103).

| artifact | what I said | what is actually there |
|---|---|---|
| **Responsive** | "unspecified" | ✅ **`RESPONSIVE.md`** — five breakpoints (1439 · 1400 · 1199/1180 · 1100 · 900), tables scroll inside their card, no horizontal page scroll, `prefers-reduced-motion` removes animation |
| **Iconography** | "unspecified" | ✅ **`brand/icons/admin-icon-inventory.md`** — Phosphor Icons v2.1.1, `regular` default / `fill` for active, **107 icons enumerated with usage counts** |
| **Admin tokens** | implied missing | ✅ **`brand/tokens/admin.tokens.css|json`** + `admin.contrast.md` |
| **11 Admin states** | "ENUMERATED, NOT DESIGNED … no frames" | ⚠ **STALE.** `V5_ADMIN_DESIGN_HELIX_RECONCILIATION §1.4` already recorded this: **ten designed state patterns** exist |
| **Component specs** | "unspecified" | ⚠ **genuinely missing** — `COMPONENTS.md` says so itself |

**And `BOUNDARIES G` dissolves on inspection.** It asks whether the Admin's `--adm-*` tokens conflict with
the Helix tiers. They do not — `admin.tokens.css` ships **exactly** the values the application ships:
`#0a0a0b`, `#121215`, `#f4f3f6`, `#9b96a3`, `#7c3aed`, and all three of violet `#7C3AED` · amber `#E0A030` ·
green `#2FBF87`. **The design package's Admin tokens and the shipped implementation are the same token set**,
which is what `CONF-D6-B` locked.

---

## A · DESIGN AUTHORITY REQUIRED — the only two real gaps

### `DESIGN-01` · Two `A11` state frames

**FACTS.** `A11` requires eleven screen states. `SCREEN-INVENTORY.md` delivers **ten** designed patterns —
Loading · Empty · Error · Permission-denied · Degraded across all six pages, plus Unavailable · Stale ·
Offline · Skeleton · Read-only, with dedicated *"State system"* panels on People, Trust, Operations and
Settings. **Two `A11` states have no frame: `critical-incident` and `Guardian-approval-required`.** The
design also adds four states `A11` never named, preserved as approved capability under §102.

**REQUIRED.** Frames for those two states.

**DEPENDENCY NOTE — and I am retracting a claim.** I previously said responsive, components and iconography
*"follow from"* the state designs. **The governing record establishes no such dependency, and I should not
have asserted one.** The three are independent artifacts; two are already delivered.

**UNBLOCKS.** `Guardian-approval-required` is the state the `P7` approval queue will render. `critical-incident`
is the Incidents area's severity-`Critical` presentation.

**STATUS — DESIGN AUTHORITY REQUIRED.**

### `DESIGN-02` · Per-component specification sheets

**FACTS.** `COMPONENTS.md` enumerates the component set in use — shell (environment strip 34px, six-item nav
header, user menu, search), containers (card, panel, drawer, dialog, menu) and the rest, **≈30 types**. It
then states plainly: *"A separate per-component specification sheet (anatomy, variants, spacing annotations)
has **not** been produced. Listed as missing."* The Helix implementation ships **3** of ≈30 (`Button`,
`Card`, `MetricReadout`).

**REQUIRED.** Anatomy, variants and spacing per component — or a ruling that the six `.dc.html` screens are
sufficient specification and components may be derived from them.

**STATUS — DESIGN AUTHORITY REQUIRED.**

---

## B · OWNER DECISIONS — the twelve metric IDs

**There are 12 decision IDs across 11 cards** — Revenue carries two. I have previously said "eleven"; that is
the card count.

**§C.3 contains no recommendation lines and no approved answers**, so none of these is answered. **Two,
however, have their *semantic* half already settled by an owner direction in the record**, which I verified at
source rather than trusting the pack's paraphrase.

| ID | card | exact question | options | producer today | status |
|---|---|---|---|---|---|
| **METRIC-02** | Active users / DAU | does a **sign-in with no Session** count as active? | 1 Session only · 2 sign-in counts · 3 both, shown separately | none | OWNER |
| **METRIC-03** | Active coaches | *"this month"* = **calendar month** or **trailing 30 days**? | 1 calendar · 2 trailing 30d | `coach_client_relationships` | OWNER |
| **METRIC-05** | Wellness partners | the **approval state machine** — *"9 awaiting approval"* implies states the schema lacks | 1 define now · 2 total only · 3 `A11` for the sub-count | `user_profiles role='vendor'` | OWNER |
| **METRIC-06a** | Revenue | **`PD-C03` currency** — `'usd'` hardcoded; card shows **£** | 1 single-currency USD + explicit FX · 2 multi-currency | `payments.amount_cents` | OWNER |
| **METRIC-06b** | Revenue | is *"coaching"* **gross** or **platform commission**? | 1 all three (gross/commission/net) · 2 gross only · 3 net only | `marketplace_commission_rate` 0.10 | OWNER — **see note ①** |
| **METRIC-11** | QA & release | **V5 gate ledger** or **CI status**? They disagree (CI green, 8 of 15 gates FAIL) | 1 CI · 2 gate ledger · 3 both, labelled | GitHub Actions | OWNER |
| **METRIC-12** | Attention queue | severity vocabulary: approved UI `CRITICAL/HIGH/MEDIUM/LOW` vs shipped `Critical/High/Warning/Informational` (`143:70`) | 1 UI adopts shipped enum · 2 change the enum (**`D4`/`A11` population change**) · 3 display-map | `audit_incidents.severity` | OWNER |
| **METRIC-13** | Ecosystem activity | what a *"pod"* is (`86 pods`) | 1 `accountability_pods` · 2 `community_groups` · 3 other | both tables exist | OWNER |
| **METRIC-14** | Events / community | which *"74% attendance"* means | 1 registrations ÷ capacity · 2 attended ÷ registered (**no attendance column**) · 3 bookings ÷ capacity | `event_registrations` | OWNER |
| **METRIC-16** | Installs | `PD-A24`=`C` forecloses an analytics vendor; is reading **our own** consoles that? | 1 not a vendor · 2 it is — `A11` empty · 3 manual entry | external | OWNER |
| **METRIC-17** | Age demographics | is the 4th bucket **60+** or **unknown**? | 1 60+ · 2 unknown · 3 five buckets | `user_profiles.date_of_birth` | OWNER |
| **METRIC-18** | Impressions | **which impression** — store-listing, marketing, or in-app? | 1 in-app · 2 store-listing · 3 marketing · 4 `A11` empty | none | OWNER — **see note ②** |

**① `METRIC-06b` — the decomposition is already ruled.** Direction **`I`** (ledger `:12344`): *"Admin must
distinguish **gross coaching revenue · platform commission · net/platform revenue**. `marketplace_commission_rate`
(0.10) is the commission input. **Calculation and source definitions must be explicit before implementation;
no monetary value is fabricated.**"* So **option 1 is the recorded direction**; what remains is the
calculation definition the direction itself demands. `COWORK` §8 forbids an agent inventing it.

**② `METRIC-18` — the term is already defined.** Direction **`K`** (ledger `:12345`): impressions are
***"eligible content renders/views, held distinct from reach · unique viewers · clicks · engagement ·
sessions"***. That **supersedes** the earlier reconciliation line (`:12134`) saying *"the term appears in no
V5 source"*, which predates it. **So option 1 is the recorded definition**; what blocks `METRIC-18` is a
**producer** — no impression event exists — not its meaning.

**The four cards needing no decision remain intact and their producers are live**, verified this run:
Total users → `admin_user_overview` · Recent admin activity → `admin_audit_events` · Security →
`admin_security_events` · AI Guardian (read-only) → `governance_policy` + `guardian_state`.

### `METRIC-19` *(new, from the design package's own boundary list)*

**`BOUNDARIES B`** — the build spec names a **Notifications Overview** group; **no corresponding area exists
on the approved Dashboard, and `Notifications` is not one of the 17 matrix areas.** The requirement is kept,
placement is not decided. **Not previously in my record.**
**OPTIONS** — 1 place it under Operations · 2 place it on the Dashboard · 3 confirm it is out of scope for V1.
**STATUS — OWNER.**

---

## C · OWNER DECISIONS — CAP-1 vocabulary

### `CAP-1-REASON`

**FACTS.** 170 ships `moderation_reason` and `content_reports.reason` as **free text**. I searched the
governing record for a reason-code vocabulary: **none exists.** The only near-hit is `PD-A06`, which is about
the planning engine and unrelated.

**EXACT QUESTION.** Should moderation and report reasons be a **fixed vocabulary**, and if so, what are the
exact values?

**OPTIONS** — 1 keep free text · 2 fixed list (**the values must come from you**) · 3 fixed list with a free-text
"other".

**SECURITY NOTE.** The reason is written by staff about a member. 170 deliberately keeps it **out of the audit
delta** for that reason; only the state transition is recorded.

**NO RECOMMENDATION — the governing record contains none, and inventing categories is what §141/§142
established must not be done. STATUS — OWNER.**

### `CAP-1-APPEAL`

**FACTS.** I re-checked whether any source now opens appeals. The only mention anywhere is
`QA_CORRECTION_RIGHTS_EXHAUSTION_REPORT:247`, recording that *"no correction/appeal workflow exists"* for
coach-authored records — **a finding that none exists, not an authorization to build one.**

**STATUS — DEFERRED, unchanged. No appeal workflow was designed.**

---

## D · PHASE GATE

**`P7`** — gated. Guardian **Manage** is operational (169); **Approve** is non-operational pending the action
queue, which `P7` supplies. The three-leg proof is preserved and runs every suite: the grant still answers, no
write path is gated on it, the resource is unmoved. **No approval queue was invented.**

---

## E · INFRASTRUCTURE BLOCKER

> **CORRECTED 2026-10-12 — this section described a blocker that has lifted.** It is kept, struck
> through, because the correction is the point: a working document asserting a *current* blocker
> decays silently, and this one did for weeks.
>
> ~~`QA_DB_URL` — a CI secret, absent here. Blocks `FG-1`, `FG-2` and ENV-3's live half.~~
>
> **`QA_DB_URL` is provisioned.** CI's step **`Live SQL evidence — FG-1, FG-2, ENV-3 ledger`** is
> gated `if: steps.creds.outputs.present == 'true'`, so without the secret it is skipped at the
> workflow level. In run **`38281191465`** its conclusion is **`success`**, not `skipped` — so the
> secret exists and all three suites execute in CI.
>
> **And `ENV-3` is not waiting on anything:** `MASTER_REMEDIATION_REGISTRY.md` records it
> **`VERIFIED_CLOSED` on 2026-08-25** (§7.9, CI run at `2a8d0b6`), restated at §2045 as *"already
> `VERIFIED_CLOSED` … there is nothing to advance."*
>
> What remains true: `FG-1` and `FG-2` are **wiring** gaps whose wiring now exists, and the `FG`
> table header still describes them as *"NOT implemented"*. Correcting that header is an edit to a
> **protected register** and is requested in `V5_REGISTER_RECONCILIATION_REQUEST.md`, not taken here.

**The static half is verified and passes every run**: `check-migration-manifest.mjs` reports
**182 authored migration(s): 000–181**, frontier **181**, manifest and ledger agreeing. *(This
previously read "all 171 migrations declared, 000–170" — a true statement at the time that the
migration tree outgrew; the figure above is the guard's own current output.)* **Nothing was
fabricated to stand in for the live comparison.**

---

## F · NO NEW EXECUTABLE WORK

One disciplined frontier sweep was run. **No independently executable authorized work was found**, and none
was manufactured: no migration was created to advance the number, no matrix entry altered, no placeholder UI
or design artifact produced.

---

## G · RECOMMENDED ORDER OF RESOLUTION

| # | input | unlocks |
|---|---|---|
| 1 | **`DESIGN-02`** component specs *(or a ruling that the six screens suffice)* | the largest `P5` surface — ≈27 unimplemented components |
| 2 | **`METRIC-12`** severity | the attention queue, and resolves two authorities disagreeing in shipped code |
| 3 | **`METRIC-06a` + `06b`** revenue | the highest-value card; the decomposition is already ruled, only the calculation is owed |
| 4 | **`DESIGN-01`** two state frames | `critical-incident` now; `Guardian-approval-required` pairs with `P7` |
| 5 | the remaining eight metric IDs | one card each, independent of each other |
| 6 | **`CAP-1-REASON`** | a vocabulary refinement; moderation already works without it |
| 7 | **`QA_DB_URL`** | moves ENV-3 to `VERIFIED_CLOSED` |

---

## H · RESPONSE SHEET

```
DESIGN-01  : two A11 state frames (critical-incident, Guardian-approval-required)  — supply / commission / defer
DESIGN-02  : per-component specs — supply / commission / "six screens suffice" / defer

METRIC-02  : Option __      METRIC-13  : Option __
METRIC-03  : Option __      METRIC-14  : Option __
METRIC-05  : Option __      METRIC-16  : Option __
METRIC-06a : Option __      METRIC-17  : Option __
METRIC-06b : Option __  (direction I already indicates 1)
METRIC-11  : Option __      METRIC-18  : Option __  (direction K already defines it as in-app renders)
METRIC-12  : Option __      METRIC-19  : Option __  (Notifications placement — NEW)

METRIC-06b-CALC : the gross/commission/net calculation definition ______________
METRIC-18-PROD  : the impression producer — does one get built? ______________

CAP-1-REASON : Option __   (1 free text · 2 fixed list: ______ · 3 fixed + other)
CAP-1-APPEAL : unchanged (deferred) — confirm? Y / N

QA_DB_URL    : add as a CI secret? Y / N
```
