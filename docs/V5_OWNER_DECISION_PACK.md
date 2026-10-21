# V5 — CONSOLIDATED OWNER / ARCHITECTURE DECISION PACK

**Prepared 2026-10-06 against QA frontier 166 · migrations 153–166 `VERIFIED_CLOSED` · CI green 6/6 ·
live regression 783/783 · AI 49/49 · characterizations 17/17 · Flutter 1704/1704 · production never
contacted.**

**This is a decision-preparation artifact. Nothing in it was implemented.** Every "FACT" below is
established from the repository, the approved design, the V5 record, the live QA schema or live QA data —
never from a capability name, a table name or a static reading where a live probe was available.

**Answer by filling in the response sheet at §J.** Each decision stands alone; answering a subset unlocks
that subset.

---

## A · EXECUTIVE FRONTIER

| | |
|---|---|
| Unresolved decisions | **28** |
| Owner decisions | **23** |
| Architecture decisions | **3** |
| Phase gates | **2** (`P5`, `P7`) |
| Infrastructure blockers | **1** (`QA_DB_URL`) |
| Capability grants still unresolved | **18 of 116** (16 × `B-23`, 2 × `CAP-1`) |

**Major branches blocked:** the Admin UI (`P5`), all 14 Dashboard KPI cards, Community moderation, the AI
Guardian runtime, and 16 write verbs.

**A correction to my previous report.** I stated that the approved build spec *"contains no mutate verb
anywhere."* **That is wrong for AI Guardian.** Spec §5 specifies *"Actions awaiting human approval"*,
*"Completed autonomous actions with audit trail"* and an **"Emergency Guardian disablement control"**. My
grep matched `approve` but not `approvals`, and `disable` was not in the list. **The claim held for Audit
logs and Security — which is what `B-20` rested on — but not for Guardian**, and `B-23-AI` below is written
on the corrected evidence.

---

## B · RECOMMENDED DECISION ORDER

Ranked by what each unlocks, not by ID.

| # | decision | unlocks |
|---|---|---|
| 1 | **`B-23-SYS` · `B-23-INT` · `B-23-AUD` · `B-23-SEC`** (one ruling, 12 grants) | closes 12 of 18 unresolved grants in a single answer |
| 2 | **`CAP-1-1`** moderation mechanism | Community's 2 grants, and the design's *"reports/moderation queue"* |
| 3 | **`B-23-AI-1`** Guardian policy authoring | 2 grants against a registry that already exists |
| 4 | **`B-17`** Guardian telemetry architecture | Guardian Manage + Approve, the Guardian KPI card, `policy_evaluation` |
| 5 | **`METRIC-12`** severity vocabulary | the attention queue, and resolves a live conflict between two authorities |
| 6 | **`METRIC-06a/b`** revenue | the highest-value KPI card |
| 7 | **`CONF-D6`** brand identity package | **`P5`** — and `P5` gates `P7` |
| 8 | the remaining narrow metric rulings | one KPI card each |

---

## C · OWNER DECISION PACK

### C.1 · `B-23` — the 16 undecided write verbs

**Shared fact.** The approved matrix grants these to one role each. None has a write path. §136 established
they are inert; this pack establishes **why each is inert**, which differs by area.

---

#### `B-23-SYS` · System × Create/Update/Manage/Approve → `operations_lead` (4 grants)

**FACTS ESTABLISHED**
- Backing resource is `observability_events`. It is **frozen**: `observability_events_freeze` blocks
  `DELETE`, blocks identity/occurrence mutation, and makes `payload` and `correlation_signature`
  **write-once**.
- `GRANT INSERT ... TO service_role` **only**. `authenticated` holds `SELECT`.
- Live: **112 rows, every one `component='metric'`** — one producer, system-owned.
- The approved design offers **status readouts only**: *"API health, database health, authentication,
  background jobs, notifications, integrations, uptime"*. **No control, queue or action.**
- No `retry`, `acknowledge`, `resolve` or similar operation exists anywhere in the schema.

**DECISION REQUIRED** — do System's four write verbs name any operation?

**OPTIONS**
1. **Non-operational.** Register alongside `B-20`'s six. No code; matrix unchanged; three-leg proof applied.
2. **Define an alert-acknowledgement surface.** New state + producer. This is new product behaviour you
   would be specifying.

**RECOMMENDATION — option 1.** The resource is write-once and system-produced, and the design offers no
affordance. This is `B-20`'s shape exactly.

**IMPLEMENTATION EFFECT** — 4 grants close with no migration.

---

#### `B-23-INT` · Integrations × Create/Update/Manage/Approve → `operations_lead` (4 grants)

**FACTS ESTABLISHED**
- Backing resource is `user_integrations` — **member-owned OAuth connections**, carrying `access_token` and
  `refresh_token` (the credentials §129.1 removed from the Admin projection).
- Base policy `user_own_integrations` is `FOR ALL USING (auth.uid() = user_id)` — **only the member** writes
  their own connection.
- Design offers status only: *"Connected devices, synchronization health, ingestion issues"*.
- **No disconnect / reconnect / retry / resync function exists.**
- The ingestion-health half is `WI-13`/`WI-15`, **deferred under `PD-G01`** (`APPROVED — FUTURE BUILD`).

**DECISION REQUIRED** — may an Admin act on a **member's** integration, and if so how?

**OPTIONS**
1. **Non-operational.** Admin sees connection status (already shipped as `admin_integration_connections`)
   and acts on nothing.
2. **Admin may disconnect a member's integration**, via a server-enforced RPC that clears `connected` and
   `disconnected_at` and **never reads or writes the tokens**. Audited as `admin_action`.
3. **Defer with `PD-G01`** until the wearable wave lands.

**RECOMMENDATION — option 1 now, revisit with `PD-G01`.** Option 2 is implementable and safe as scoped, but
disconnecting a member's own OAuth link is an action against a member's account that the design never asks
for. Nothing is lost by waiting.

**IMPLEMENTATION EFFECT** — option 1: 4 grants close, no migration. Option 2: one RPC + tests.

---

#### `B-23-AUD` · Audit logs × Create, Approve → `trust_lead` (2 grants)

**FACTS ESTABLISHED**
- `audit_events` is **append-only** (`trg_audit_events_freeze`, every caller incl. `service_role`), granted
  `SELECT` only, written **exclusively** through `audit_record_event()`.
- `audit_record_event()` **exists and is granted to `authenticated`** — so "Create" is *mechanically*
  possible, and is how every emitter in the system already writes.
- The design offers **no audit-authoring or audit-approval affordance**. `A13`/`A2` govern what may be
  emitted and by whom.
- **`Approve` has no referent at all** — nothing in the audit population carries an approval state.

**DECISION REQUIRED** — does `Create` mean an Admin may author an audit event, and does `Approve` mean
anything?

**OPTIONS**
1. **Both non-operational.** Audit events are emitted by the operations they record, never authored by hand.
2. **`Create` = a manual Trust annotation** — a new audit category an Admin may emit. This adds a 16th `A2`
   category, which is a **`D4` change**.

**RECOMMENDATION — option 1.** Option 2 would let a Trust lead author the record that audits Trust, and an
audit population whose entries can be hand-written is weaker evidence than one whose entries cannot.

**IMPLEMENTATION EFFECT** — 2 grants close with no migration.

---

#### `B-23-SEC` · Security × Create, Approve → `trust_lead` (2 grants)

**FACTS ESTABLISHED**
- Security is a **category filter over `audit_events`** (your `B-1` ruling: `authentication`,
  `authorization_denial`, `admin_action`, `audit_read`), served by `admin_security_events`, which is
  read-only.
- Same append-only base, same absence of any approval state.
- Spec: *"Security controls remain independent of the AI Guardian"* — so Security's verbs cannot borrow
  Guardian's approval semantics.

**DECISION REQUIRED** — as `B-23-AUD`.

**OPTIONS** — 1. Both non-operational. 2. Define a detector/threshold configuration resource (none exists).

**RECOMMENDATION — option 1**, matching `B-20`'s ruling on the same base table.

**IMPLEMENTATION EFFECT** — 2 grants close with no migration.

---

#### `B-23-AI-1` · AI Guardian × Create, Update → `trust_lead` (2 grants)

**FACTS ESTABLISHED — this is the one with a live resource**
- `governance_policy`, `_version`, `_rule`, `_set`, `_set_member` (154) **exist, are mutable** (no freeze),
  and carry a write policy gated on `is_admin()`.
- 163 made the Admin layer's **read** effective; **writes remain `is_admin()` only**, so the `Create`/
  `Update` grants are inert.
- 154 is **documentation only** and §13 holds the deterministic layer authoritative — *"the registry must
  not become the enforcement point."* Authoring a policy **document** does not change authorization.
- Design §5 lists Guardian elements including *"Recommended actions"*; spec §6 names *"approvals, agent
  activity"*. Policy authoring itself is **not** named as a Guardian panel element.

**DECISION REQUIRED** — do Guardian `Create`/`Update` mean **authoring governance-policy documents** in the
154 registry?

**OPTIONS**
1. **Yes — Trust lead may author policy documents.** Implementable immediately: an additive write arm or RPC
   gated on `admin_can('AI Guardian','create'/'update')`, with `admin_action` audit. The registry stays
   documentation-only and §13 is untouched.
2. **No — the registry stays `is_admin()`-write.** Both grants register non-operational.
3. **Defer to `B-17`** and decide alongside the runtime.

**RECOMMENDATION — option 1.** It is the only `B-23` verb with an existing, mutable, correctly-scoped
resource; the registry was built for exactly this; and it creates no authorization authority because the
registry is not an enforcement point.

**IMPLEMENTATION EFFECT** — one migration (write arm + audit), `D15` coverage, 2 grants become effective.

---

#### `B-23-AI-2` · AI Guardian × Manage, Approve → `trust_lead` (2 grants)

**FACTS ESTABLISHED — the design DOES specify these**
- Spec §5: *"Persistent Guardian state: **Active / Monitoring / Degraded / Disabled**"*, *"Actions awaiting
  **human approval**"*, *"Completed autonomous actions with audit trail"*, **"Emergency Guardian disablement
  control"**.
- `A7`: *"Clear distinction between observation, recommendation, autonomous action, and human-approved
  action."*
- **No Guardian state store exists.** Nothing in the schema holds `Active/Monitoring/Degraded/Disabled`.
- **No pending-action queue exists.** Nothing holds an action awaiting approval.
- `A10`: Guardian must not hold admin authority; **emergency disablement is a product requirement**.

**DECISION REQUIRED** — none on *meaning*. The design already defines them: `Manage` = Guardian state
including emergency disablement; `Approve` = approving an action awaiting human approval. **What is missing
is the producer**, which is `B-17`.

**OPTIONS** — 1. Hold both until `B-17` resolves. 2. Build the state store and queue now as empty
substrates, ahead of the producer.

**RECOMMENDATION — option 1.** Building a queue with nothing to put in it invents the action shape.

**IMPLEMENTATION EFFECT** — these 2 grants are **dependent on `B-17`, not independently decidable**.

---

### C.2 · `CAP-1` / `B-10` — Community moderation

**FACTS ESTABLISHED**
- `community_posts` columns: `id, user_id, content, image_urls, post_type, likes_count, comments_count,
  created_at, updated_at`. **There is no visibility, status, hidden, removed or deleted column.**
  `post_comments` and `post_reactions` likewise.
- Write policy is `users manage own posts` / `users manage own comments`, `FOR ALL USING (user_id =
  auth.uid())` — **author-scoped**. Today only the author can edit or delete; a delete is a **hard delete**.
- **Zero report/moderation/flag/appeal tables exist for community content.** Migration 050 moderates the
  **exercise library** — a different object.
- **No moderation audit exists**, and no reason-code vocabulary is defined anywhere.
- The approved design names *"reports/moderation queue"* (spec §3) — an **affordance with no substrate**.
- Community content is readable by **any authenticated account** (your `B-18` ruling confirmed that posture).

**DECISION REQUIRED — three, and they are separable**

**`CAP-1-1` · What does moderation DO to content?**
1. **Hide, preserving the member's text.** Add a moderation state (`visible` / `hidden` / `removed`) plus
   actor and timestamp; the original `content` is never altered. Readers stop seeing it; the record survives
   for appeal and audit.
2. **Hard delete.** Use the existing delete path, extended to `content_editor`. Simplest; destroys evidence
   and makes appeal impossible.
3. **Edit the text in place.** Literal reading of `Update`. **Staff could silently alter what a member
   said.**

*Recommendation — option 1.* It is the only one that satisfies the design's *"queue"* (a queue needs a state
to move through), preserves evidence for the audit `A10` requires, and never puts words in a member's mouth.

**`CAP-1-2` · Do reports need a backing resource?**
1. **Yes** — a `content_reports` table (reporter, target, reason, state). The design names a *reports*
   queue, so without it the queue has no input.
2. **No** — moderation is staff-initiated only; the queue lists flagged content from some other signal.

*Recommendation — option 1*, because the design says "reports/moderation queue" and option 2 leaves the word
*reports* unimplemented.

**`CAP-1-3` · What does `Create` mean for `content_editor`?**
1. **Nothing** — `Create` is non-operational for Community; staff do not post.
2. **Platform-authored posts** — staff may post as the platform (needs an authorship concept that does not
   exist).

*Recommendation — option 1.* No design element shows platform-authored community content.

**Dependent sub-decisions, only if `CAP-1-1` = 1:** reason codes (free text vs fixed vocabulary — **the
vocabulary would have to come from you**, as with `approval_status` and `events.status`), and whether
appeals are in scope (nothing in the record mentions appeals).

**IMPLEMENTATION EFFECT** — options 1/1/1 authorize: one migration adding moderation state + a reports
table, a server-enforced moderation RPC gated on `admin_can('Community','update')` with immutable
`admin_action` audit, and `D15` coverage. **Community's 2 grants close.**

---

### C.3 · Dashboard metrics — 14 KPI cards

**Shared fact.** The data contract (§10) states: *"Every one of the fourteen has at least one open business
definition."* §11.3's reconciliation then applied existing authority and reduced ~30 apparent decisions to
**11**. **Four cards need nothing** — Total users, Recent admin activity, Security, AI Guardian (as a
read-only card).

| ID | card | exact question | options |
|---|---|---|---|
| **METRIC-02** | Active users / DAU | does a **sign-in with no Session** count as active? | 1 Session only (`product-bible` §5: Session = one day's workout) · 2 sign-in counts · 3 both, shown separately |
| **METRIC-03** | Active coaches | *"this month"* = **calendar month** or **trailing 30 days**? (the approved screens use both) | 1 calendar · 2 trailing 30d |
| **METRIC-05** | Wellness partners | the **approval state machine** — *"9 awaiting approval"* implies states the schema does not have | 1 define now (needs the state list from you) · 2 drop the sub-count, show total only · 3 defer the card's second line to an `A11` state |
| **METRIC-06a** | Revenue | **`PD-C03` currency** — `'usd'` is hardcoded everywhere; the card shows **£** | 1 record single-currency USD + explicit FX for display · 2 multi-currency (large) |
| **METRIC-06b** | Revenue | is *"coaching"* **gross** or **platform commission**? | 1 show all three (gross / commission / net) — your earlier direction already approved this decomposition · 2 gross only · 3 net only |
| **METRIC-11** | QA & release | does the card show the **V5 gate ledger** or **CI status**? They disagree today (CI green, 8 of 15 gates FAIL) | 1 CI · 2 gate ledger · 3 both, labelled |
| **METRIC-12** | Attention queue | **severity vocabulary conflict.** Approved UI shows `CRITICAL/HIGH/MEDIUM/LOW`; the **shipped, V5-specified** CHECK is `Critical/High/Warning/Informational` (`143:70`) | 1 UI adopts the shipped enum · 2 change the enum (**a `D4`/`A11` population change — not done unilaterally**) · 3 display-map the two |
| **METRIC-13** | Ecosystem activity | what a *"pod"* is (`86 pods`) — `accountability_pods` exists but the count does not match | 1 `accountability_pods` · 2 `community_groups` · 3 something else you define |
| **METRIC-14** | Events / community | which *"74% attendance"* means | 1 registrations ÷ capacity · 2 attended ÷ registered (**no attendance column exists**) · 3 bookings ÷ capacity |
| **METRIC-16** | Installs | `PD-A24` = `C` forecloses an **analytics vendor**; is reading **our own** store consoles that? Console credentials are also an **account boundary** | 1 not a vendor — authorize console ingestion · 2 it is — card renders `A11` empty · 3 manual periodic entry |
| **METRIC-17** | Age demographics | is the 4th bucket **60+** or **unknown**? | 1 60+ · 2 unknown · 3 both (5 buckets) |
| **METRIC-18** | Impressions | **which impression** — store-listing, marketing, or in-app? Plus ⚠ the approved panel declares a runtime dependency on **`flagcdn.com`**, third-party egress from an authenticated admin surface | 1 in-app (your earlier direction: *eligible content renders*) · 2 store-listing · 3 marketing · 4 card renders `A11` empty |

**`METRIC-18` carries a security note independent of the metric choice:** the approved panel's world map
pulls flag assets from `flagcdn.com`. Whichever option you pick, **third-party egress from the Admin surface
is a separate posture decision** — self-host the flag assets, or accept the egress.

---

### C.4 · Other owner decisions

| ID | item | question | recommendation |
|---|---|---|---|
| **PD-A19** | admin/content_manager assignment governance | no admin UI, no second-person approval; *"whoever holds `service_role`"* creates the first admin | needed before `P5` ships role management |
| **PD-A24** | observability vendor posture | ruled `C`; `METRIC-16`/`METRIC-18` test its edge | no new decision unless you take `METRIC-16` option 1 |
| **CONF-D6** | brand identity / design-token package | **this is `P5`'s remaining blocker** (see §E) | supply or commission the token package |
| **K-07** | defect: a failed Stripe cancel still revokes local access, UI says *"Switched to Free"* | a real defect in the registry, **not** a decision — remediation authority exists | authorize remediation; it is independent of every decision here |

---

## D · ARCHITECTURE DECISION PACK

### `B-17` · AI Guardian telemetry architecture

**FACTS ESTABLISHED**
- **`policy_evaluation` does not exist as a table.** 154's comment records the ruling that it *"goes to
  `observability_events`"* — so the **home is decided**; the **producer is not**. **No policy engine emits
  evaluations.**
- `observability_events`: 112 live rows, **all `component='metric'`**. Frozen, `INSERT` to `service_role`
  only, carries **no subject identifier** (`D12`·Q5).
- `decision_traces`: **691 live rows**, RLS-enabled, read scope narrowed by 125 under **`PD-A05`
  (ANSWERED)** — `content_manager` is the role the ruling deliberately withholds.
- **No Guardian state store** and **no pending-action queue** exist.
- `A10`: Guardian must not hold admin authority; **security controls remain independent of the Guardian**.
- **`P7` is gated on `P5`.**

**DECISION REQUIRED** — what produces Guardian runtime telemetry, and does any of it land before `P7`?

**OPTIONS**
1. **Guardian state store only, now.** A small `guardian_state` table (the `A5` vocabulary) plus an
   emergency-disablement RPC. Satisfies `A10`'s named product requirement and the design's control, and
   unlocks `B-23-AI-2`'s `Manage`. Leaves `Approve` and the action queue to `P7`.
2. **Full runtime now** — state, action queue, evaluation producer. Large, and `P7`-gated.
3. **Hold everything for `P7`.** Guardian card renders `A11` states; `B-23-AI-2` stays deferred.

**RECOMMENDATION — option 1.** `A10` names emergency disablement as a product requirement rather than a
Guardian feature, the state vocabulary is already fixed by `A5`, and it is the smallest increment that makes
an approved control real. Option 2 requires inventing the action shape; option 3 leaves a named safety
control unbuilt.

**IMPLEMENTATION EFFECT** — option 1: one migration, one RPC, `D15` coverage; Guardian `Manage` becomes
effective; the Guardian KPI card gains its state field.

### `ARCH-02` · `policy_evaluation` producer

**FACT** — the destination is ruled (`observability_events`); nothing emits. **DECISION** — is there to be a
policy engine at all before `P7`? **RECOMMENDATION** — no; this follows `B-17` and should not be decided
separately.

### `ARCH-03` · Helix cross-product design system

**FACT** — blocked on external design-system authority throughout the record. **No decision is owed to this
programme**; recorded for completeness.

---

## E · PHASE-GATED ITEMS

### `P5` — Admin UI. **The blocking set has shrunk and this is worth your attention.**

§91.8 recorded five live inputs. Three have since discharged:

| input | then | now |
|---|---|---|
| 1 · approved Admin screen package | OUTSTANDING (`CONF-D4`) | ✅ **you closed `CONF-D4`** — the screenshots are the approved design authority |
| 2 · Fitonist reference | blocked on artefact delivery | ✅ **delivered and committed** |
| 3 · brand identity package | blocked on artefact delivery | ⛔ **`CONF-D6` — still outstanding** |
| 5 · `CONF-D7` Admin role matrix | OUTSTANDING | ✅ **closed; the 425-grant matrix is seeded and verified** |
| nine unplaced domains | OUTSTANDING | ✅ **all 17 areas classified (§127) and accepted** |

**`P5`'s remaining blocker is `CONF-D6`** plus the completeness gaps the design README itself names: token
values, the 11 Admin states, responsive behaviour, component specs and iconography. **Supplying `CONF-D6`
is the single highest-leverage decision in this pack** — it is the only one that unlocks a phase.

### `P7` — gated on `P5`. No decision or implementation is owed until `P5` opens.

---

## F · INFRASTRUCTURE / PERMISSION BLOCKERS

| item | exact prerequisite |
|---|---|
| `FG-1` · `FG-2` · ENV-3 live half | **`QA_DB_URL` as a CI secret.** All three are SQL, not REST; `QA_DB_URL` is unset in this environment and `live-evidence.sh` is written to skip without it. Adding the secret moves ENV-3 from `REMEDIATED` to `VERIFIED_CLOSED`. |
| `LRE-34` · `REL-36` · `LRE-35` | Verification requires a **QA reset/reseed**, which destroys the fixture identities and the audit population every live suite depends on. **Not authorized and not safe** without a disposable environment. |
| Docker-dependent verification | Unavailable here; behavioural verification is used instead, which `QA_CLOSURE_STANDARD` §5.2 rates higher. |

---

## G · INTENTIONALLY DEFERRED / NON-OPERATIONAL — no implementation owed

| item | why nothing is owed |
|---|---|
| `B-20`'s 4 + `B-21c`'s 2 (6 grants) | **Ruled non-operational**, registered, and proven on three legs every run: the grant still answers, no write path is gated on it, the resource refuses mutation |
| `B-5`/`B-6` · QA, Releases | **Deferred by your decision** to an `A11` empty state. The card ships; no producer was invented |
| `B-7` · Organization | **The gap is in the DESIGN** — zero mentions in the build spec, invisible in all four screens. Nothing approved exists to build |
| Configuration | `B-8`: **confirmed by design.** `platform_settings` holds one row the checkout needs |
| `B-3` · Training row-level | **Confirmed privacy boundary.** Aggregate-only, asserted every run |
| Engine-substrate test fixtures | **Declined deliberately** — seeding `movement_nodes` would fabricate the substrate the assertions are about |

---

## H · DEPENDENCY GRAPH

```
CONF-D6 ──────────────► P5 ──────────────► P7 ──────► Guardian action queue
                         │                              │
                         │                              └── B-23-AI-2 · Approve
                         └── PD-A19 (role mgmt UI)

B-17 (opt 1) ─────────► guardian_state ──► B-23-AI-2 · Manage
                                        └► METRIC-09 Guardian card state

CAP-1-1 ──┬─► CAP-1-2 (reports) ──► moderation queue ──► Community Create/Update (2 grants)
          └─► reason codes · appeals

B-23-AI-1 ──► governance-policy authoring (2 grants)      [no dependencies]
B-23-SYS/INT/AUD/SEC ──► 12 grants close                  [no dependencies]

METRIC-12 ──► attention queue ──► Dashboard "Needs your attention"
METRIC-06a/b ──► revenue card
PD-A24 ──► METRIC-16 ──► METRIC-18 (+ flagcdn egress posture)
QA_DB_URL ──► FG-1 · FG-2 · ENV-3 live ──► ENV-3 VERIFIED_CLOSED
```

**Highest unlock value:** `CONF-D6` (a phase) · the single `B-23` non-operational ruling (12 grants) ·
`CAP-1-1` (a design capability with a named queue) · `B-17` option 1 (a named safety control).

---

## I · NEXT AUTONOMOUS IMPLEMENTATION WAVE

With the recommended options supplied, the following becomes executable **without further questions**:

1. Register 12 `B-23` grants non-operational; extend the three-leg proof. *(no migration)*
2. `B-23-AI-1` — governance-policy authoring arm + audit + `D15`. *(1 migration)*
3. `B-17` option 1 — `guardian_state` + emergency-disablement RPC + `D15`; Guardian `Manage` effective.
   *(1 migration)*
4. `CAP-1` — moderation state + `content_reports` + moderation RPC with immutable audit + `D15`; Community's
   2 grants close. *(1–2 migrations)*
5. `K-07` remediation — independent of every decision here.
6. Any metric whose definition is supplied — each is a view or aggregate on the authorized `admin_can`
   pattern.

**Grid effect if all recommendations are taken: unresolved grants fall from 18 to 2** (Guardian
`Manage`/`Approve`, pending `B-17`/`P7`).

---

## J · OWNER RESPONSE SHEET

Fill in option numbers. Blank = defer.

```
B-23-SYS   : Option __     (1 non-operational · 2 define alert acknowledgement)
B-23-INT   : Option __     (1 non-operational · 2 admin disconnect · 3 defer with PD-G01)
B-23-AUD   : Option __     (1 non-operational · 2 manual Trust annotation = D4 change)
B-23-SEC   : Option __     (1 non-operational · 2 detector/threshold resource)
B-23-AI-1  : Option __     (1 Trust lead authors policy docs · 2 non-operational · 3 defer to B-17)
B-23-AI-2  : Option __     (1 hold for B-17 · 2 build substrates now)

CAP-1-1    : Option __     (1 hide, preserve text · 2 hard delete · 3 edit in place)
CAP-1-2    : Option __     (1 content_reports table · 2 staff-initiated only)
CAP-1-3    : Option __     (1 Create non-operational · 2 platform-authored posts)
CAP-1-REASON : free text / fixed list ______   (only if CAP-1-1 = 1)
CAP-1-APPEAL : in scope? Y / N                 (only if CAP-1-1 = 1)

B-17       : Option __     (1 state store only · 2 full runtime · 3 hold for P7)

METRIC-02  : Option __     (1 Session only · 2 sign-in · 3 both)
METRIC-03  : Option __     (1 calendar month · 2 trailing 30 days)
METRIC-05  : Option __     (1 define states · 2 total only · 3 A11 for the sub-count)
METRIC-06a : Option __     (1 single-currency USD + FX display · 2 multi-currency)
METRIC-06b : Option __     (1 gross/commission/net · 2 gross only · 3 net only)
METRIC-11  : Option __     (1 CI · 2 V5 gate ledger · 3 both labelled)
METRIC-12  : Option __     (1 UI adopts shipped enum · 2 change enum (D4) · 3 display-map)
METRIC-13  : Option __     (1 accountability_pods · 2 community_groups · 3 other: ______)
METRIC-14  : Option __     (1 registrations÷capacity · 2 attended÷registered · 3 bookings÷capacity)
METRIC-16  : Option __     (1 authorize console ingestion · 2 A11 empty · 3 manual entry)
METRIC-17  : Option __     (1 60+ · 2 unknown · 3 five buckets)
METRIC-18  : Option __     (1 in-app renders · 2 store-listing · 3 marketing · 4 A11 empty)
METRIC-18-EGRESS : self-host flags / accept flagcdn.com egress   ______

CONF-D6    : supply token package?  Y / N / commissioned
PD-A19     : Option __     (role-assignment governance — needed before P5 ships role management)
K-07       : authorize remediation?  Y / N
QA_DB_URL  : add as CI secret?  Y / N
```
