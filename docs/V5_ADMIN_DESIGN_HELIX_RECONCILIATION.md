# V5 — ADMIN DESIGN × HELIX × ARCHITECTURE RECONCILIATION

**Ingestion of `design/12circle-plus-admin-dashboard` (`931218b`) as the authoritative 12Circle+ Admin
Dashboard design package, reconciled against V5 architecture, governance and the Helix design system.**

**Analysis only. Nothing was implemented, rewritten, scaffolded or redesigned. V5 §102 governs throughout:
no approved capability is deleted, simplified, hidden or redesigned to fit the current architecture.**

---

## 0 · Headline results

| | |
|---|---|
| **Helix conformance** | **Far higher than expected. 11 of 11 shared colour roles match the shipped Helix theme EXACTLY**, as do the brand typeface and the signature easing curve. §2. |
| **Nocturne** | **Not Helix, not a Helix predecessor.** It is the *design tool's* baseline design-system runtime, shared across every 12Circle `.dc.html` artifact. **The bundle was located on disk.** §7. |
| **Trust IA** | **No longer absent.** The package designs the full Trust page. This closes one of the four §97.4 gates. §1. |
| **Domain placement** | **11 of 12 Admin domains are now placed by approved design.** `Database` is the one that is not. §1.3. |
| **The 11 states** | **No longer *"enumerated, not designed"*.** Ten state patterns are designed across all six pages. §1.4. |
| **Genuine conflict** | **One**: the approved Trust page contains `#ai-guardian`; `D11`/§19.2 rules *"AI Guardian … is **NOT** inside Trust."* §6.1. |

---

## 1 · Design capability inventory

Six approved pages, six-item IA — `Dashboard · People · Ecosystem · Trust · Operations · Settings` —
confirmed by `SCREEN-INVENTORY.md`, which also states the build spec's older eight-item nav *"is
historical and is **not** used"*. **The design package itself defers to `CONF-D1`.**

| Page | Sections |
|---|---|
| **Control Center** (Dashboard) | attention queue + drawer · Ecosystem snapshot · Ecosystem activity · Events & community · Security · AI Guardian · Wearable intelligence · QA & release · Recent admin activity · Installs / Age range / Impressions · Dashboard states · *"Requires architectural verification"* notes panel |
| **Ecosystem** | `#overview` `#community` `#events` `#training` `#monetization` `#wearables` + audit pattern |
| **People** | `#users` `#coaches` `#clients` `#partners` `#states` |
| **Trust** | `#overview` `#ai-guardian` `#security` (+`#sec-authz`) `#incidents` `#audit` (explorer, before/after) `#trust-system` |
| **Operations** | `#overview` `#releases` `#integrations` `#system` (+`#sys-events`) `#ops-system` |
| **Settings** | `#overview` `#organization` `#users` `#roles` `#platform` `#notifications` AI & intelligence `#privacy` `#security` `#integrations` `#billing` `#states` |

Two superseded designs (`Control Center v1`, `Admin Dashboard`) are preserved and labelled.

### 1.1 Components required by the approved pages

From `COMPONENTS.md`: environment strip (34px) · header with six-item nav · user menu · search · card ·
panel · drawer · dialog · menu · **table with sticky header and row actions** · stat tile · sparkline /
bar / line chart · severity badge · status pill · progress bar · timeline · **audit row with before/after
diff** · text · select · segmented control · switch (`role=switch`) · checkbox · radio · search · date
range · toast · inline error · empty state · skeleton · degraded banner · permission-denied panel ·
read-only banner.

**≈30 component types.** `COMPONENTS.md` records that a per-component specification sheet (anatomy,
variants, spacing annotations) **has not been produced** — listed as missing, §7.

### 1.2 Interactions

Attention queue opens a drawer · every *"View audit history"* deep-links to **Trust › Audit logs** ·
before/after diffs deep-link to a Trust audit event · Settings cross-links to Operations › System events,
Trust › Authorization and Trust › AI Guardian · global search and table filters · **row actions open
confirm dialogs for destructive changes**.

### 1.3 Domain placement — §97.4 gate 4, now largely answered by approved design

§91 ruled twelve Admin domains; §97.4 recorded **nine unplaced**. The approved pages place them:

| domain | placement | basis |
|---|---|---|
| Security · Incidents · Audit | **Trust** | `D11` **and** the approved Trust page |
| **Users** | **People** `#users` | approved design |
| **Roles** | **Settings** `#roles` | approved design |
| **Health** | **Operations** `#system` / `#sys-events` (+ Control Center tiles) | approved design |
| **Releases** | **Operations** `#releases` | approved design |
| **Wearables** | **Ecosystem** `#wearables` | approved design |
| **Payments** | **Ecosystem** `#monetization` **and** **Settings** `#billing` | approved design — **two placements, deliberate split (operational view vs configuration)** |
| **Analytics** | **Dashboard** (Installs / Age / Impressions) + **Ecosystem** `#overview` | approved design |
| **AI** | **Trust** `#ai-guardian` | approved design — **⚠ conflicts with `D11`/§19.2, see §6.1** |
| **Database** | **NOT PLACED** | no section in any approved page |

**Eleven of twelve placed. `Database` is unplaced and is NOT removed** — it remains an approved §91 domain
awaiting placement.

### 1.4 States — §97.4 gate 6 is now STALE

The record said the 11 states were *"ENUMERATED, NOT DESIGNED … no frames"*. **That is no longer true.**
`SCREEN-INVENTORY.md`: **Loading · Empty · Error · Permission (denied) · Degraded** in all six pages, plus
**Unavailable · Stale · Offline · Skeleton · Read-only**, with dedicated *"State system"* panels on People,
Trust, Operations and Settings and *"Dashboard states"* on the Control Center.

**Ten designed state patterns.** Against `A11`'s eleven, **two are not separately designed**:
**critical-incident** and **Guardian-approval-required**. They remain approved `A11` requirements with no
frame. The design also adds four states `A11` never named (Unavailable, Stale, Skeleton, Read-only) —
**preserved as approved capability under §102**.

---

## 2 · Helix conformance

### 2.1 Which Helix is authoritative — a correction that matters

Two artefacts both call themselves the 12Circle Helix theme:

| | |
|---|---|
| `/Users/dmac/Documents/projects/helix` → `src/themes/12circle.ts` | accent **`#9EF01A` electric lime**, Hanken Grotesk / Clash Display, `easing.spring`, pill buttons. Its own header says ***"FIRST PASS — values are meant to be tuned by design."*** |
| **`apps/mobile/lib/core/helix/` + `core/theme/twelve_circle_theme.dart`** | accent **`#7C3AED` violet**, **Schibsted Grotesk**, `Motion.emphasized`. **Conformance-tested in CI** by `design_token_conformance_test.dart`. |

**The in-repo Dart implementation is the live, enforced 12Circle Helix theme.** The standalone repo's
`12circle.ts` is a self-declared first pass and is **stale relative to the product**. The audit below is
against the enforced one.

### 2.2 Already Helix-conformant — 11/11 exact

| Admin token | value | Helix (`TwelveCircleTheme`) | match |
|---|---|---|---|
| `bg.canvas` | `#0a0a0b` | `bg` | ✅ |
| `bg.surface` | `#121215` | `surface` | ✅ |
| `bg.hover` | `#1b1b20` | `surfaceHigh` | ✅ |
| `text.primary` | `#f4f3f6` | `ink` | ✅ |
| `text.muted` | `#9b96a3` | `grey` | ✅ |
| `text.subtle` | `#8b8595` | `dim` | ✅ |
| `brand.violet` | `#7c3aed` | `violet` | ✅ |
| `brand.accent` | `#a78bfa` | `violetText` | ✅ |
| `status.success` | `#2fbf87` | `green` | ✅ |
| `status.warning` | `#e0a030` | `amber` | ✅ |
| `status.danger` | `#e8556d` | `red` | ✅ |

**Also exact:** typeface **Schibsted Grotesk** (Helix `fontDisplay`/`fontBody`/`fontNumeric`); hairlines
`rgba(255,255,255,0.08)` / `0.045` = Helix `border` `0x14FFFFFF` / `borderSubtle` `0x0BFFFFFF`; easing
`cubic-bezier(0.2,0,0,1)` = `Motion.emphasized`; `motion.fast` 120ms = `Motion.d120`.

**This is not a coincidence of taste — it is the same design system.** The Admin design and the shipped
mobile theme were authored from one identity. **Helix conformance on colour, type, hairline and signature
motion is already achieved.**

### 2.3 Requiring mapping / adaptation

| element | Admin | Helix | action |
|---|---|---|---|
| **Sunken surface** | `bg.inset` `#232326` (**lighter** than surface — a well on dark) | `surfaceSunken` `#070708` (**darker**) | **Different roles, same name family.** Map Admin `inset` to a new role; do **not** overload `surfaceSunken` |
| **Motion durations** | `base` 180ms, `slow` 240ms | `d120 · d200 · d300 · d450` | map `base`→`d200` (180≠200) or add primitives |
| **Radius** | `xs`4 `sm`6 `md`10 `lg`12 `xl`16 `2xl`20 `pill`999 | semantic `button/card/pill` only | Admin's 7-step ramp exceeds the 3-role contract |
| **Breakpoints** | tokens name 4 (1440/1200/900/768); pages use 6 (1439/1400/1199-1180/1100/900) | none in Helix | reconcile to one set, then add |

### 2.4 Requiring additive Helix extensions

**None of these is a conflict. Each is a token Helix does not yet carry.**

1. **Colour roles (4):** `bg.raised` `#16161a` · `bg.inset` `#232326` · `text.secondary` `#d0ccd6` ·
   **`status.info` `#7cb8f0`** — Helix has no `info` role at all.
2. **Status *text* and *tint* variants:** `successText/Tint`, `warningText/Tint/Border`,
   `dangerText/Tint/Border`, `text.onWarning`. Helix carries one flat value per status. **The Admin
   contrast table proves these are required, not decorative** — `brand.violet` is 3.5:1 and *"never used
   for text"*, which is exactly why `brand.accent` and the `*Text` variants exist.
3. **A type scale.** Helix Tier-2 carries font *families* only; Admin defines **10 named steps**
   (`overline … display`) with size/line/weight/tracking. This belongs in Tier 1 or a new Tier-2 group.
4. **Density/size tokens:** `control` 44px, `controlCompact` 40px, `rowList` 52px, `rowRich` 64px,
   `envStrip` 34px, icon sm/md/lg.
5. **Admin shadow semantics:** `menu · edge · divider · header` — structural insets, not Helix's
   elevation ramp `sm/md/lg/glow`. **Both are needed; neither replaces the other.**
6. **Z-index scale:** header 10 · menu 20 · dialog 50 · toast 60.
7. **Components.** Helix ships **three** (`Button`, `Card`, `MetricReadout`); Admin requires **≈30**.
   This is the single largest additive gap.
8. **Icons.** Phosphor Icons **v2.1.1**, `regular` default / `fill` for active, **107 icons** in use.
   Helix specifies no icon system.

### 2.5 Elements relying on a different design-system runtime

All eight `.dc.html` files link `_ds/nocturne-…/styles.css` and `_ds_bundle.js` (§7). **Measured
dependence on it is effectively nil:** Nocturne's accent `#9184d9` appears **0 times**; Nocturne class
names (`.btn .nav .tag .field .seg`) appear **0 times**; `.card` once. The approved pages carry **6,274
raw hex and 22,109 raw px values** of their own.

**Consequence for implementation:** the pages are **not** token-driven — `admin.tokens.*` was
*reverse-extracted* from them (`PROVENANCE.md`: *"Extracted from the six approved pages by counting values
actually used … Derived, not invented"*). Implementation must bind to tokens, so **the extraction is the
bridge, and it must be validated value-by-value against the pages before it is trusted.**

### 2.6 Genuine design-system conflicts

**None on values.** Two authority questions:

- **Which Helix is canonical** (§2.1). The standalone repo's lime first-pass contradicts the enforced
  violet theme. **Leaving both is the real risk** — a future consumer could bind to the wrong one.
- **Where Admin tokens live.** `BOUNDARIES.md` item G already records *"Admin tokens (`--adm-*`) vs
  Fitness Helix tiers | Architecture question | Both documented, no merge."* **Not merged here.**

---

## 3 · Current V5 architecture support

Unchanged from the data contract (§11) and §102.6, and **nothing is removed for lack of support**:

| served today | partial | no source |
|---|---|---|
| Total users · role counts · Recent admin activity · Security/audit/incidents (`audit_events`, `audit_incidents`, shipped + CI-verified) · Age (`date_of_birth`) · pods/posts · events · sessions/check-ins · wearable **connections** (`user_integrations`) | Wellness partners (no approval state) · Active coaches/clients (window undefined) · QA & release (exists in CI, not ingested) | DAU/WAU/MAU · Revenue decomposition · Platform health · AI Guardian · wearable **ingestion health** · Installs · Impressions · notification delivery · community moderation queue |

The design package reaches the same conclusion independently — the Control Center carries a *"Requires
architectural verification"* panel naming: no known admin data layer; service health; AI Guardian not in
code; **wearables are Android-first so HealthKit and Apple Watch need confirming**; CI cannot be read by
the app; audit log assumes an append-only store.

> **New finding from that panel.** *"Wearables are Android-first"* — yet the approved Wearable tile shows
> **Apple HealthKit** and **Apple Watch** as connected. `user_integrations.provider` is free text and
> `PD-B23` names Strava/WHOOP/Garmin/Polar/Spotify/MyFitnessPal — **not HealthKit**. The capability is
> **preserved**; platform coverage needs confirming against `WI-01`/`WI-08`.

---

## 4 · Additive architecture extensions required

Beyond §102.6's register, the six-page package adds:

| # | capability | extension | new? |
|---|---|---|---|
| E-1 | **Trust audit explorer with before/after diff** | `audit_events.delta` **already exists** (migration 150, `A6`). A read/query surface and deep-link addressing are needed | mostly **supported** |
| E-2 | **Deep-link addressing** — every audit link targets a Trust audit event | stable public identifiers for audit rows; `A12` constrains what an identifier may expose | new |
| E-3 | **Destructive-action confirm dialogs + row actions** | each is a privileged write ⇒ `CONF-D7` cell **and** an `A10` audit emitter | new |
| E-4 | **Settings configuration surfaces** (org, platform, notifications, AI, privacy, security, integrations, billing) | a settings/config store with change audit. `platform_settings` exists (`039`) but covers one key | largely new |
| E-5 | **Coach verification · client assignment · partner onboarding** | state machines on People | new |
| E-6 | **Releases + environments + integrations health** | ingest CI; `P10` constraint applies | new |
| E-7 | **Global search across users, events, incidents** | cross-domain search respecting `A10` boundaries | new |

---

## 5 · Security / RLS / governance implications

1. **`A10` governs the whole surface** — *"dashboard data must respect the same authorization boundaries
   as the underlying system."* `CONF-D8` remains open and remains behind `CONF-D7`.
2. **Every row action and confirm dialog is a privileged write** ⇒ a `CONF-D7` cell and an audit emitter.
   The Settings page alone adds eight configuration domains.
3. **The audit explorer's before/after diff is the sharpest PHI surface in the package.** Migration 150
   deliberately **excludes** `phi_correction` and the five occurrence categories from `delta`. **A Trust
   explorer that rendered a diff for those categories would defeat `A6`'s exclusion.** Preserved; not
   designed; a boundary.
4. **The `A12` re-identification boundary (§102.5) applies to People, Trust and the attention queue** —
   the design shows named accounts while the Event population carries a pseudonym.
5. **`#sec-authz` (Trust › Authorization)** reads directly onto the `CONF-D7` matrix — the design assumes
   a surface for a model that does not yet exist.
6. **Contrast is specified and self-enforcing** — `admin.contrast.md` gives measured ratios and the rule
   that `text.disabled` and `brand.violet` are *never* used for text. **Adopt as an accessibility gate.**

---

## 6 · Genuine owner decisions

### 6.1 NEW — AI Guardian inside Trust (§102 governance exception)

| | |
|---|---|
| **Approved design** | Trust page section **`#ai-guardian`**; Settings cross-links to *"Trust › AI Guardian"* |
| **Governing V5 authority** | `D11` / §19.2 — *"Trust's scope = Security · Incidents · Audit Logs. **AI Guardian remains P7 and is NOT inside Trust.**"* |
| **Nature** | A **scope/phase** conflict, not a security one. The approved design places a P7 capability inside the P6/Trust surface |
| **Disposition** | **Capability PRESERVED. Not implemented, not deleted, not relocated.** §102: preserve · name the conflict · name the authority · **stop** |
| **Decision required** | Does the approved design supersede §19.2's exclusion, or does AI Guardian render elsewhere? **Owner.** |

### 6.2 Design-system authority

**Which Helix is canonical** — the standalone repo's lime first-pass or the enforced in-repo violet theme
(§2.1) — and **where Admin tokens live** (`BOUNDARIES.md` G). **Design-system authority decisions.**

### 6.3 Carried forward, unchanged

The five of §100.5 · `PD-C03` · `CAP-1`'s policy question · the `A12` boundary (§102.5) ·
`BOUNDARIES.md` A–G. **None resolved here.**

### 6.4 Explicitly NOT owner decisions

**`Database` domain placement** (§1.3) — a design placement question. **Token extensions** (§2.4) —
additive design-system work. **Critical-incident and Guardian-approval-required state frames** (§1.4) —
design work against an existing `A11` requirement.

---

## 7 · Missing design-system artifacts and dependencies

### 7.1 Nocturne — identified from evidence

**Nocturne is the design tool's baseline design-system runtime. It is NOT Helix and NOT a Helix
predecessor.**

| evidence | finding |
|---|---|
| Occurrences of "nocturne" | **0** in Helix (src + dist), **0** in the 12circle-fitness repository, **9** in the design package |
| **The bundle was located** | `/Users/dmac/Desktop/community-portal/_ds/nocturne-042b8c43-…/` and `/Users/dmac/Desktop/mobile-app/_ds/nocturne-042b8c43-…/` |
| **Same instance UUID** | shared by the **Admin dashboard**, the **12Circle Mobile App** design and the **community portal** designs ⇒ one tool-level system, not an Admin dependency |
| Its own `readme.md` | *"Nocturne is a quiet, compact dark interface … a single accent **#9184d9**"*, Inter, 8px radii, Phosphor icons, `.btn/.tag/.field/.card/.nav`, *"derived from `theme.json`"* |
| Token namespace | `--color-bg/--color-text/--color-neutral-100…900` (OKLCH ramps) — **disjoint** from Helix's `--color-surface/--color-text-primary/…` |
| `support.js` | *"GENERATED from **dc-runtime**/src/*.ts"*, requires `window.React` |
| `image-slot.js` | *"@ds-adherence-ignore — **omelette starter** scaffold"* |

**Classification: an unrelated, tool-level dependency of the design artifacts.** It is **not renamed, not
substituted, and not assumed to be Helix.** It is required only to *view* the `.dc.html` files at full
fidelity; **it is not a product runtime and must not be shipped.**

**Status: available but not published.** The bundle is on the Desktop, outside the repository. It was
**not** copied into the design branch — that is a publication decision outside this analysis task.

### 7.2 Other missing artifacts

| missing | source |
|---|---|
| Per-component specification sheets (anatomy, variants, spacing) | `COMPONENTS.md` — *"has **not** been produced"* |
| Admin phone layout below 480px | `RESPONSIVE.md` — *"has **not** been separately designed"* |
| Logo: light-ground variant, one-colour, icon-only crop, clear-space, minimum size, transparency check | `brand/README.md` |
| `critical-incident` and `Guardian-approval-required` state frames | §1.4 vs `A11` |
| `mobile/` design authority | out of scope by instruction |
| `_backup-admin-cc-pre-panels.dc.html.txt` | referenced by `PROVENANCE.md` |

---

## 8 · Implementation boundaries and sequencing

**No implementation is authorized. P5 remains gated.**

**Gate movement from this ingestion — two of four §97.4 gates move:**

| gate | before | after |
|---|---|---|
| `CONF-D6` identity package | OPEN — no tokens | **NARROWED, not closed.** Tokens now exist and match Helix 11/11; but they are **derived**, and the logo package is incomplete (§7.2). **A derived extraction is not an owner lock.** |
| `CONF-D7` role matrix | OPEN | **OPEN, unchanged** — and `#sec-authz` now has a surface awaiting it |
| **Trust IA** | **OPEN — external design authority** | ✅ **CLOSED.** The Trust page is designed |
| Nine domain placements | OPEN | **11 of 12 placed**; `Database` outstanding |

**Sequence the evidence supports** — no step authorized by this document:

1. **Validate the token extraction** against the six pages value-by-value (§2.5). Everything downstream
   binds to it.
2. **Resolve §6.1** (AI Guardian in Trust) and **§6.2** (canonical Helix) — both block structure.
3. **`CONF-D7`**, which unblocks `CONF-D8` and every row action, confirm dialog and `#sec-authz`.
4. **Additive Helix extensions** (§2.4) — tokens first, then the ≈30 components.
5. **`CONF-D9` architecture** per §102.6 and §4, in the order the data contract gives.
6. **P5 only when its gates are satisfied.**

**Nothing in this reconciliation removes, simplifies, hides or redesigns any approved capability.
`PD-G01`, `PD-A24` and `P10` are not released. No migration, application file, schema change or
production contact.**

---

# PART II — CLOSURE PASS (V5 §104)

**Every evidence-supported closure step worked through. Analysis only; §102 governs. No capability removed,
simplified, hidden or redesigned.**

## 9 · `CONF-D6` — the engineering half CLOSES, the authority half does NOT

§103 said validating the token extraction was the first task. **Done, quantitatively.**

### 9.1 The extraction is faithful — measured, not asserted

| check | result |
|---|---|
| hex tokens in `admin.tokens.json` found in the approved pages | **22 / 22** |
| rgba tokens found | **11 / 11** — `line.hairline` alone appears **2,364** times, `line.default` **1,068** |
| distinct hex values used across the six pages | 39 |
| **total hex occurrences covered by the token set** | **6,057 / 6,200 = 97.7%** |
| the 12 most-used values | **all 12 tokenised** |

**Residue, named rather than glossed:** two untokenised values above 20 uses — `#f08a9b` (×52, a near
neighbour of `status.dangerText #f07a8c`) and `#b8b3c0` (×35, between `text.secondary` and `text.muted`) —
plus 17 low-use distinct values totalling ~2.3%.

**Conclusion: `PROVENANCE.md`'s claim — *"Extracted … by counting values actually used · Derived, not
invented"* — is TRUE and now verified.** The token set is a trustworthy basis for implementation, and the
2.3% residue is a bounded tidy-up, not a defect.

### 9.2 What this closes, and what it explicitly does not

**CLOSES (engineering):** the tokens are accurate, complete to 97.7%, and **conform 11/11 to the enforced
Helix theme** (§2.2). Nothing further is needed to *trust* them.

**DOES NOT CLOSE (authority):** `CONF-D6` requires a ***locked identity package***. Still outstanding, from
`brand/README.md` and the handoff report:

- logo **light-ground** variant · **one-colour** variant · **icon-only / app-icon** crop · **clear-space**
  rule · **minimum size** · transparency check — *"none are invented here"*;
- and the owner's designation that **these derived tokens ARE the locked package**.

> **A derived extraction is evidence of what the design does. It is not an owner lock on what the brand
> is.** That distinction is the whole of `CONF-D6`'s remainder and is **not** collapsed here.

## 10 · `CONF-D7` — a real matrix exists; the remaining requirement is now exact

**The approved Settings › Roles & permissions page contains an actual role matrix.** This is the single
largest movement on `CONF-D7` since it was raised.

### 10.1 What the design establishes

**Five Admin roles**, with description, user count, level and status:

| role | description | level |
|---|---|---|
| **Trust lead** | *"Security, AI oversight and audit"* | Full |
| **Operations lead** | *"QA, releases, integrations, system"* | — |
| **Support** | *"Members and bookings, read-mostly"* | Limited |
| **Content editor** | *"Community and training content"* | — |
| **Viewer** | *"Read-only across the admin"* | Read-only |

**Five permission verbs:** `View · Create · Update · Manage · Approve`.

**Fourteen permission areas, grouped by the IA** — Ecosystem (Community · Events · Training ·
Monetization · Wearable intelligence) · Trust (AI Guardian · Security · Incidents · Audit logs) ·
Operations (QA · Releases · Integrations · System).

**So the shape of `CONF-D7` is answered: roles × areas × verbs, with a level summary.**

### 10.2 The precise remaining requirement — a vocabulary that does not match the database

**The designed Admin roles are NOT the enforced database roles.** `user_profiles_role_check` (147:49)
enforces seven: `client · coach · vendor · admin · content_manager · trust_operator · erasure_executor`.

| design role | database role | relationship |
|---|---|---|
| Trust lead | `trust_operator` | plausible, **not stated** |
| Content editor | `content_manager` | plausible, **not stated** |
| Operations lead · Support · Viewer | — | **no database equivalent** |
| — | **`erasure_executor`** | **no design equivalent** — yet it exclusively holds severance (`146:118`, `152:183`) |
| — | `client` · `coach` · `vendor` | appear in the design as **subjects**, not Admin actors |

**What remains to close `CONF-D7`, stated exactly:**

1. **Are the five design roles a SEPARATE Admin role layer above the seven database roles, or a
   replacement vocabulary for them?** Everything else depends on this and it is **not inferable**.
2. **Where does `erasure_executor` appear?** It holds the most destructive capability in the system and
   has no designed surface.
3. **The matrix cells.** The design renders the grid; the per-cell grants were not extractable from the
   static markup and are **not invented here**.
4. **Reconciliation with the nine enforced sites** (§98.1) — e.g. `A13·1` excludes an admin from reading
   their **own** `admin_action` rows; no design role expresses that.

**`CONF-D7` remains OPEN — but it is no longer *"no role matrix"*. It is a vocabulary-reconciliation
decision with a designed matrix on one side and shipped enforcement on the other. Owner.**

### 10.3 A second, larger finding — Trust › Authorization implies a policy registry

The approved `#sec-authz` surface logs: `Who · Role · Resource · Did what · Result · **Under policy** ·
When · **Risk**`, with **named policies — `RB-01 · admin`, `RB-04 · roster only`, `RB-06 · support read`,
`RB-09 · trust manage`** — and principals including **`Outreach worker · AI agent`**.

Against the shipped `audit_events` (142 + 150):

| design column | support |
|---|---|
| Who · Did what · Result · When | ✅ `actor_id` · `action` · **`outcome`** · `occurred_at` |
| **Resource** | ⛔ no column |
| **Under policy (`RB-nn`)** | ⛔ **no policy registry exists anywhere in the record** |
| **Risk** | ⛔ no column |
| **AI agent as principal** | ⚠ partially — `actor_provenance` has `system`, but no agent identity |

**This is a substantial additive requirement and it is `CONF-D7`-adjacent**: a named, versioned policy
registry is precisely what makes a role matrix enforceable and auditable. **Recorded; not designed.**

## 11 · Domain placement — CLOSED at 12 / 12

§103.3 left **`Database`** as the one unplaced domain. **It is placed: Operations › System.**

> Operations › System — *"The infrastructure 12Circle+ runs on"* — lists **Application · Uptime 30d
> 99.97% · API p95 212 ms · Database 41% capacity · 118 connections · Jobs 18 running / 42 queued / 2
> failed · Workers 6/6 · Storage 62%**, with the Control Center carrying a `Database · Operational`
> health tile.

**All twelve §91 domains are now placed by approved design. `Database` was never removed while its
placement was unresolved** — §102 held, and the evidence then resolved it.

## 12 · Wearables — RESOLVED, and the design package's own note is the thing that was wrong

§103 flagged a tension: the package's *"Requires architectural verification"* panel says **wearables are
Android-first**, while the approved tile shows **Apple HealthKit** and **Apple Watch**.

**The approved roadmap settles it, repeatedly and explicitly:**

> `ROADMAP_WEARABLE_INTELLIGENCE.md:7` — ***"First platform: Apple Watch / Apple HealthKit"***
> `:95` **W1 — HealthKit Foundation** · `:99` *"a secure, explicit connection between 12Circle and Apple
> HealthKit"* · `:378` **W8 — Apple Watch Companion Experience** · `:443` ***"Apple Watch/HealthKit is the
> first implementation."*** `:452` shows the provider abstraction — *Apple/HealthKit · Health Connect ·
> Other*.

**So the approved Admin design is CORRECT and consistent with `WI-01`/`WI-08`. The package's
"Android-first" note is mistaken** — and it is a **design-time annotation, not design authority**, so
correcting it changes no approved capability.

**Corroborating:** `apps/mobile/pubspec.yaml` has **no** health, wearable, fitness or sensor dependency —
there is no wearable integration on either platform yet, exactly as `PD-G01` (approved, implementation not
authorized) requires.

**Neither capability is removed.** HealthKit and Apple Watch stand as approved design; the ingestion-health
half still waits on `WI-13` under `PD-G01` (§102.6). **This closes the §103 wearable question.**

## 13 · AI Guardian inside Trust — full §102 characterization

| field | finding |
|---|---|
| **Design capability** | A full Trust › AI Guardian area — *"Oversight of AI agents, workflows and the policies that govern them"*: Policy center · Overview · AI activity · **Policies · Policy detail** · AI incidents · Incident detail · Guardian health · Evaluation engine. Metrics: policy set **v3.14 · 28 active policies**, median decision time 41 ms, **agents without a policy: 0**, 6 AI systems monitored, 14 active agents, 22 workflows, 31,440 AI requests / 14,206 AI actions per 24 h, decisions blocked 38 / escalated 2 / failed 4 |
| **Design source** | `12Circle Admin Pages - Trust.dc.html` `#ai-guardian`; cross-linked from Settings |
| **Governing authority** | `D11` / §19.2 — *"Trust's scope = Security · Incidents · Audit Logs. **AI Guardian remains P7 and is NOT inside Trust.**"* |
| **Nature of the conflict** | **Scope / phase, not security.** Both readings are legible and **neither is adopted here**: (a) the Trust area is *governance oversight of AI*, which is a Trust function, and P7 is the Guardian *product capability* — compatible; (b) §19.2's exclusion is explicit and names AI Guardian directly — incompatible. **The record does not disambiguate, so this is not inferable.** |
| **Governance pull toward the design** | *"Agents without a policy: 0"* and a versioned policy set directly operationalize `A10` — *"AI agents do not inherit unrestricted admin authority"* and *"security controls remain independent of the AI Guardian"*. **Observed, not adopted as an argument.** |
| **Architecture support** | **None.** No `policies`, `ai_agents` or agent-registry table exists. The policy registry is also what `#sec-authz` needs (§10.3) — **one additive capability serving two approved surfaces** |
| **Security / RLS** | Guardian oversight reads across all members ⇒ `CONF-D8`. Any Guardian *control* (emergency disablement, `A5`) is a privileged write ⇒ `CONF-D7` cell + `A10` audit emitter |
| **Disposition** | **PRESERVED. Not implemented, not deleted, not relocated, not redesigned.** |
| **Decision required** | Does the approved design supersede §19.2's exclusion, or does Guardian oversight render elsewhere? **Owner. This is a stop.** |

## 14 · Remaining approved Admin capabilities — governance / security audit

| surface | status | note |
|---|---|---|
| Trust › Security · Incidents · Audit explorer | **SUPPORTED** | `audit_events`, `audit_incidents`, `delta` (150) shipped + CI-verified. ⚠ `delta` **excludes** `phi_correction` and the five occurrence categories — a diff view must honour that exclusion |
| Trust › Authorization `#sec-authz` | **ADDITIVE** | needs resource · policy registry · risk (§10.3) |
| Operations › System | **ADDITIVE** | no `system_events`, `background_jobs`; health per `PD-A24 = C`, vendor-free |
| Operations › Releases · Integrations | **ADDITIVE** | no `releases`/`integrations` tables; CI ingestion under the **`P10`** constraint |
| People › Users | **SUPPORTED** | `user_profiles`, `admin_recent_users()` |
| People › Coaches · Clients | **PARTIAL** | `coach_client_relationships` exists; **no coach-verification state** |
| People › Partners | **ADDITIVE** | no approval state — §100.5 owner decision |
| Ecosystem › Community | **ADDITIVE** | `community_posts`/`comments`/`groups`/`accountability_pods` exist; **no reports/moderation queue** — `CAP-1` |
| Ecosystem › Events · Training | **SUPPORTED** | `events`, `event_registrations` (`K-04` CI-verified), `workout_*` |
| Ecosystem › Monetization | **ADDITIVE** | no local amounts (§99.2) |
| Ecosystem › Wearables | **PARTIAL** | connections via `user_integrations`; ingestion health = `WI-13` under `PD-G01` |
| Settings (11 sections) | **ADDITIVE** | only `platform_settings` exists, one key. **No `organizations` table.** Every write is a `CONF-D7` cell + `A10` emitter |
| Global search | **ADDITIVE** | cross-domain, must respect `A10` |

**Confirmed absent:** `organizations`, `coach_verification`, `partner_approval`, `integrations`,
`releases`, `policies`, `ai_agents`, `system_events`, `background_jobs`, `moderation_reports`.
**Every one is an approved capability and none is removed — §102's union, not the intersection.**

**A design-side governance signal worth adopting:** the Wearables page states its own rule —
***"System health first. Member-level data only where your role permits it."*** The approved design is
already written in `A10`'s terms.

## 15 · Nocturne and the canonical-Helix question — unchanged, restated

**Nocturne remains a design-runtime dependency, not Helix.** Not renamed, not substituted, not assumed.
It is required only to render the `.dc.html` artifacts at full fidelity and **must not ship as a product
runtime**. No new evidence in this pass alters §7.1.

**The canonical-Helix question is NOT resolved by inference.** The standalone repo's lime `12circle.ts`
(self-declared *"FIRST PASS"*) versus the enforced in-repo violet theme is recorded as a **design-system
authority boundary**. The Admin design's 11/11 conformance to the in-repo theme is *evidence*, not a
ruling.

---

# PART III — POLICY REGISTRY SPECIFICATION AND EVIDENCE AUDIT (V5 §105)

**Specification and reconciliation only. Nothing implemented. §102 governs. The seven enforced database
roles and their security properties are preserved untouched, and no naming mapping is asserted.**

## 16 · The policy registry — full architecture requirement

Two approved surfaces require it independently (§10.3). This section specifies the **minimum authoritative
model** they imply, taken from the artifacts, **not invented**.

### 16.1 What the approved surfaces actually show

**Trust › AI Guardian › Policies** — a table with columns `Policy · Category · Scope · Status · Version ·
Updated · Last evaluated · Violations`:

| policy | category | scope | status | version | violations |
|---|---|---|---|---|---|
| Export scope limits | Data access | All agents | Active | **v7** | 9 |
| Bulk messaging approval | Human approval | Outreach | Active | v3 | 2 |
| Health data minimisation | Privacy | — | Active | v5 | 0 |
| Model allow-list | Model usage | — | Active | v11 | — |
| Moderation escalation | Safety | Moderator | **Draft** | v2 | — |

**Policy detail** — `Export scope limits · v7` · **Effective** `3 Sep 2026 · 09:00` · **Owner**
`Priya Raman · Trust` · **Rules** `2 — record count ≤ 50 · roster match` · **Violations 30 d** `9, all
blocked` · actions `View rules · **Compare versions** · Edit draft`.

**Evaluation and audit history** — three event kinds, verbatim:

- `Blocked · Report builder · 1,240 records requested — 14:19 today · **INC-2041**` *(an evaluation,
  linked to an incident)*
- `v7 took effect — limit lowered from 200 to 50 — 3 Sep 09:00 · Priya Raman` *(a version transition with
  a readable delta and an actor)*
- `v6 retired after review — 29 Aug · **Security review board**` *(retirement, by a body not an individual)*

**Trust › Authorization** — `Who · Role · Resource · Did what · Result · **Under policy** · When · Risk`,
policies cited as **`RB-01 · admin`**, **`RB-04 · roster only`**, **`RB-06 · support read`**,
**`RB-09 · trust manage`**.

**Trust › AI incident detail** — `AIN-118` · AI action `Export client records · CSV` · **Policy result
`Blocked` · `DA-07 v7`** · Affected resource.

**Guardian health** — **`policy set v3.14 · 28 active policies`**, `median decision time 41 ms`,
**`agents without a policy: 0`**, `last full evaluation 4 min ago`.

### 16.2 An identifier scheme the artifacts are internally consistent with — READING, not ruling

`DA-07 v7` appears as the policy result for an **export** block; `Export scope limits` is category **Data
access** at **v7** with violations *"all blocked"*. **On this evidence the coded and named forms are the
same policy**, implying one registry with category-prefixed codes — `DA-` data access, `RB-` role-based,
and presumably others for Human approval, Privacy, Model usage, Safety.

**This is a reading of the artifacts' internal consistency, offered as a reading. It is NOT asserted as
the model, and no code-to-category mapping is invented.** Confirmation belongs to design authority.

### 16.3 Minimum authoritative model

Seven entities. **Every field below is traceable to an artifact above; nothing is added for completeness.**

| # | entity | fields the design requires |
|---|---|---|
| **1** | **`policy`** | stable id · **code** (`DA-07`, `RB-01`) · name · **category** (Data access · Human approval · Privacy · Model usage · Safety · Role-based) · **scope/applicability** (All agents · Outreach · Moderator · a role) · **owner** (principal + area) · lifecycle status (**Active · Draft · Retired**) · current version pointer |
| **2** | **`policy_version`** | policy · **monotonic version** (v1…v11) · **effective_from** (date **and** time) · authored_by · **retired_at / retired_by** (an individual **or a body** — *"Security review board"*) · a **human-readable change note** (*"limit lowered from 200 to 50"*) |
| **3** | **`policy_rule`** | version · ordinal · predicate (*"record count ≤ 50"*, *"roster match"*). **Count is displayed (`Rules 2`), so rules are first-class rows, not an opaque blob** |
| **4** | **`policy_set`** | **set version (`v3.14`)** · membership of policy_versions · active count · **last full evaluation** · median decision time. **A policy set is versioned independently of its policies** — the design shows both |
| **5** | **`principal`** | the subject a policy binds: a human (role + identity) **or an AI agent** (`Report builder`, `Outreach worker`, `Content moderator`) with a **workflow** and an **agent/system registry** (6 systems · 14 agents · 22 workflows). *"Agents without a policy: 0"* **requires completeness to be computable** |
| **6** | **`resource`** | the object acted upon — `Client records` · `Billing plans` · `Agent credential` · `Member profile` · `Email campaign`. A **typed resource reference**, not free text, since it is filtered and reported on |
| **7** | **`policy_evaluation`** | policy_version · principal · resource · action · **decision** (Allowed · **Blocked** · Escalated · Failed) · **risk** (High · Medium · Low) · quantified detail (*"1,240 records requested"*) · occurred_at · **optional incident link** (`INC-2041`) |

**Two identifier schemes for incidents are visible — `INC-2041` and `AIN-118` — and they are not
reconciled by the artifacts. Recorded, not resolved.**

### 16.4 Reconciliation against the five existing V5 models

#### (a) Authorization model — **the registry must NOT become the enforcement point**

Today authorization is enforced by SQL: `is_admin()` · `is_trust_operator()` · `is_erasure_executor()`
and **202 `CREATE POLICY` statements**, across the nine sites of §98.1 — all live- and CI-verified at
484/484.

**The registry names and versions what is currently implicit in function bodies and RLS predicates.**
That is a genuine gain in auditability. **But moving enforcement out of RLS into an application-layer
registry would be a security regression** — it would relocate the control that §63's catalog audit, the
484 assertions and the whole `D-01`/`D-02`/`D-03` remediation history rest on.

> **Constraint, stated so it cannot be lost: RLS remains the enforcement floor. The registry is the
> DECLARED model plus the EVALUATION LOG. It may describe and audit; it must not replace.** Any design
> that made the registry authoritative over RLS reaches a **security boundary** and requires an explicit
> decision.

#### (b) RLS model — a fourth naming collision

**"Policy" already has a precise, load-bearing meaning here: a Postgres RLS policy, 202 of them.** The
approved design uses "policy" for an authorization/governance policy. §7 of the commission lists three
such collisions (`D5`, `D6`, `A14`); **this is a fourth and the most dangerous**, because a careless
reading of *"28 active policies"* against *"202 policies"* invites exactly the wrong conclusion.
**Recommend distinct vocabulary at the point of implementation — e.g. `governance_policy` — decided by
design-system/architecture authority, not here.**

#### (c) Audit model — **the crux, and it touches a standing constraint**

`audit_events` (142 + 150) supplies `actor_id · action · **outcome** · occurred_at · category ·
correlation_id · delta`. It **lacks resource, policy and risk** (§10.3).

`policy_evaluation` is event-shaped, high-volume (*"31,440 AI requests / 14,206 AI actions"* per 24 h) and
operational. **`D4 · A1` fixed FOUR audit populations, and the standing instruction is: do not invent
audit populations.** So there are exactly two admissible directions, and **choosing between them is an
architecture decision inside `CONF-D9`, not a liberty**:

1. **Extend `audit_events`** with resource / policy / risk. But `A11` makes it **append-only with a freeze
   that refuses UPDATE and DELETE to every caller including `service_role`**, and `A2`'s category list is
   fixed at 15 by `R-1`. Adding a 16th category is a `D4` change.
2. **A separate operational store** outside the audit populations, with the audit arm emitting only on
   material events (a block, an escalation, a version transition).

**Direction (2) preserves `A11`/`A2` untouched and is the lower-risk reading — but it is NOT chosen here.**

#### (d) Guardian model — supplies the missing half of `A5`/`A7`

`A5` requires *"recent detections with evidence and confidence"*, *"completed autonomous actions with
audit trail"*; `A7` requires the distinction between **observation · recommendation · autonomous action ·
human-approved action**. **The registry is what makes `A7` recordable** — *"under which policy"* is the
field that distinguishes an autonomous action from a policy-governed one. **Gated behind the §104.6
AI-Guardian-in-Trust authority conflict; the capability stays preserved.**

#### (e) Role model — **the registry cannot be built before `CONF-D7`**

`RB-01 · admin`, `RB-06 · support read`, `RB-09 · trust manage` reference **roles**. `RB-06` cites
**`Support`** — a *designed* Admin role with **no database equivalent** (§10.2).

> **Therefore the policy registry is strictly downstream of `CONF-D7`'s one question.** Building it first
> would force the five-versus-seven vocabulary decision by implementation default — precisely what the
> standing instruction forbids. **No mapping is asserted: `Trust lead`→`trust_operator` and
> `Content editor`→`content_manager` remain UNMADE, and `Operations lead`, `Support`, `Viewer` and
> `erasure_executor` are given no invented equivalents.**

### 16.5 Supported versus additive

| element | status |
|---|---|
| who · action · outcome · when | ✅ `audit_events` |
| incident record, severity, evidence, approval, resolution | ✅ `audit_incidents` (143) |
| before/after delta | ✅ migration 150 — **with `A6`'s exclusions intact** |
| **resource · policy reference · risk** | ⛔ additive |
| **policy · policy_version · policy_rule · policy_set** | ⛔ additive — nothing exists |
| **agent / workflow registry** | ⛔ additive — no `ai_agents` table |
| **human-readable incident references** (`INC-`, `AIN-`) | ⛔ additive — `audit_incidents.id` is a uuid |
| **reviewer assignment** (`Unassigned`) | ⛔ additive — `actor_identity` is the actor, not a reviewer |
| **policy evaluation stream** | ⛔ additive, **and constrained by (c)** |

### 16.6 Controls that must not be weakened to supply this

1. **`A11` append-only + freeze** — no UPDATE/DELETE path may be opened to carry evaluation state.
2. **`A2`'s 15 categories** — fixed by `R-1`; a 16th is a `D4` change, not an implementation detail.
3. **`A12` pseudonymisation** — evaluations name resources like *"Client records"* and *"Member profile"*.
   **A policy-evaluation stream that recorded subject identities in the clear would create exactly the
   re-identification path `A12` closes** (§102.5). **This is the sharpest privacy risk in the registry.**
4. **`A6`'s delta exclusions** — `phi_correction` and the five occurrence categories (§104.7).
5. **RLS as the enforcement floor** — (a) above.
6. **`A10`** — *"security controls remain independent of the AI Guardian"*. **A registry that governed both
   Guardian policy and human authorization would couple them.** `RB-` and `DA-` families being one
   registry (§16.2) is therefore not a neutral detail — **it is an `A10` question.**

## 17 · Risk ≠ Severity — new evidence bearing on §100.5 decision 3

The attention-queue severity conflict was framed as `CRITICAL/HIGH/MEDIUM/LOW` (screens) against
`Critical/High/Warning/Informational` (spec + shipped `143:70`).

**New evidence: the design uses a separate `Risk` axis with values `High · Medium · Low`** — on
authorization events and on AI incidents (`AIN-118` High · `AIN-117` Medium · `AIN-112` Low) — **alongside
`Status` (Investigating · Open · Resolved)**.

**So `Risk` and `Severity` are distinct dimensions in the approved design.** This **narrows** decision 3
again: part of what looked like a severity-vocabulary conflict may be a *risk* axis that the shipped enum
was never meant to carry. **Not resolved — the attention queue's own labels remain unreconciled, and this
is the owner's decision.**

## 18 · Evidence audit of the standing boundaries

| boundary | new evidence this pass | status |
|---|---|---|
| **`CONF-D7`** one question | the registry is **strictly downstream** of it (§16.4e) — raising the cost of deferring | **OPEN — owner.** No mapping asserted |
| **`CONF-D6`** identity lock | none. §104.1 stands: extraction validated 97.7%, logo package still incomplete | **OPEN — owner** |
| **Canonical Helix** | **dating, below** | **OPEN — design-system authority** |
| **Admin token location** | `BOUNDARIES.md` G unchanged — *"Both documented, no merge"* | **OPEN — design-system authority** |
| **AI Guardian in Trust** | the Guardian surface is the **policy registry's other consumer**, deepening the dependency | **OPEN — owner. Preserved, not relocated** |
| **§100.5 five** | decision 3 narrowed by §17; others unchanged | **OPEN — owner** |
| **`PD-C03`** | none | **OPEN — pre-existing** |
| **`CAP-1`** | none beyond §103.5's corroboration | **OPEN — narrow policy question** |
| **`A12` re-identification** | **materially sharpened** — §16.6(3): the evaluation stream is a second, larger re-identification surface | **OPEN — security boundary** |

### 18.1 Canonical Helix — dated, not decided

| artifact | last change | note |
|---|---|---|
| `helix/src/themes/12circle.ts` (lime `#9EF01A`) | **2026-07-09** — the initial *"Helix Design System v0.1"* commit; repo HEAD 2026-07-19 | never updated since scaffolding; self-declared *"FIRST PASS"* |
| `apps/mobile/lib/core/helix/` + `twelve_circle_theme.dart` (violet) | **2026-09-22** — ***"Phase 4a — adopt the authoritative design tokens in Helix Tier 1-3"*** | 2½ months newer; **its own commit says it adopted the authoritative tokens**; CI-conformance-tested |
| dependency link between them | **none** — no `@helix/design-system` declaration anywhere in this repository | the Dart tiers are a **parallel implementation**, not a consumer |

**A coherent chronology on the evidence:** one authoritative 12Circle token set existed by 2026-09-22;
the mobile app adopted it; the Admin design package (2026-10-04) expresses the same set — which is why the
match is 11/11. The standalone lime theme predates all of it.

> **This dates the artifacts. It does not decide which is canonical going forward, nor whether the
> standalone repo is updated, retired or re-pointed. That is design-system authority. Not resolved by
> inference.**

## 19 · Frontier

**No boundary was crossed and none was resolved by inference.**

**OWNER:** `CONF-D7`'s one question — *separate layer or replacement vocabulary* — now **blocking the
policy registry as well** · **AI Guardian in Trust** · `CONF-D6`'s identity lock · the five of §100.5
(3 narrowed twice) · `PD-C03` · `CAP-1`'s policy question.
**DESIGN-SYSTEM AUTHORITY:** canonical Helix · Admin token location · **governance-policy naming**
(§16.4b).
**SECURITY:** the `A12` boundary, now with a **second and larger surface** — the policy-evaluation stream
(§16.6.3) · and **whether the registry may ever be authoritative over RLS** (§16.4a).
**ARCHITECTURE (`CONF-D9`, behind `CONF-D7`):** the seven-entity registry · the audit-population direction
(§16.4c) · the ten absent tables · Helix token/component extensions.

**No capability removed, simplified, hidden, relocated or redesigned. The seven enforced database roles
and their security properties are untouched. `PD-G01`, `PD-A24`, `P10` not released. Nocturne unchanged.
No migration, no application file, no schema change, no production contact.**

---

# PART IV — AUTONOMOUS CONTINUATION (V5 §106)

**All independent paths worked to their boundaries. Evidence gathering, archaeology and additive planning
only. §102 applied without exception. The seven enforced database roles and their security behaviour are
untouched; no role mapping is asserted anywhere below.**

## 20 · `CONF-D7` — evidence gathered, and the question is LARGER than stated

### 20.1 The strongest narrowing available — two vocabularies, two populations

| surface | its own words | vocabulary shown |
|---|---|---|
| **People › Users** | *"**Everyone with a 12Circle+ account, across every role**"* | member roles — `Amara Osei · **Client** · Active · Coach-guided` |
| **Settings › Administrators** | *"**People who can sign in to the admin**, and what they can reach"* | Admin roles — `Priya Raman · **Trust lead** · Full`, `Tomas Vidal · **Support** · Limited`, `admin.ops@… · **Operations lead**`, `Lena Fischer · **Content editor** · Suspended` |

**The approved design applies the two vocabularies to two different populations, on two different pages,
with different column semantics** (`Role`=Client vs `Role`=Trust lead; `Access`=Full/Limited). **They are
nowhere presented as alternatives to each other.**

### 20.2 Why this still does not decide the question — and reveals a third reading

The seven enforced roles split into **three member roles** (`client · coach · vendor`) and **four
admin-class roles** (`admin · content_manager · trust_operator · erasure_executor`). §20.1's evidence
speaks to the *member* three. **It says nothing about the four.**

**Three readings now stand, not two:**

| # | reading | what it implies |
|---|---|---|
| **1** | **Separate layer.** Five Admin roles sit above all seven; the four admin-class roles remain the enforcement substrate | two systems to keep in step forever |
| **2** | **Replacement.** The five replace the seven entirely | contradicts §20.1 — `Client` is shown as a live member role |
| **3** | **PARTIAL replacement** — the five replace the **four admin-class** roles while `client · coach · vendor` persist as member roles | **fits every piece of evidence found, and was not in the original framing** |

**Reading 3 was not available when `CONF-D7` was narrowed at §104.2. The question must be re-put to the
owner in three-way form, not two-way.**

### 20.3 Two further facts that the evidence surfaces and does not settle

**(a) `Platform admin` is a sixth label.** It appears **exactly once per page — six times, always the
signed-in identity in the header** (`D. Mac · Platform admin`) — and **never in the Administrators
table**. It is not among the five designed roles. Whether it is a sixth Admin role, a generic label, or
the DB `admin` role surfacing, **the artifacts do not say.**

**(b) `erasure_executor` has NO designed surface — confirmed exhaustively.** Searching all eight pages:
`erasure` **0** · `right to be forgotten` **0** · and every one of the 15 `sever` hits is **"Severity"** or
"severe", **not severance**. A single `Delete account…` row action exists, which is **not**
`audit_sever_identity()`. **The role that exclusively holds severance (`146:118`, `152:183`) is absent
from the approved Admin design.**

### 20.4 Boundary

**`CONF-D7` cannot be decided from evidence and is the stop.** No mapping is asserted:
`Trust lead`→`trust_operator`, `Content editor`→`content_manager`, and any equivalent for
`Operations lead`, `Support`, `Viewer` or `erasure_executor` **remain unmade.** The seven enforced roles
and their security behaviour stand unchanged.

## 21 · Canonical Helix — the implementation-authority chain IS established; system canonicity is NOT

**New evidence, from repository archaeology rather than inference.**

The Phase 4a commit (`175a617`, 2026-09-22) states its own authority:

> *"`IMPLEMENT-THIS.md` section 4: **'Tokens go into Helix Tier 1-3 as written there. No parallel
> theme.'** Values come from `manifest.json` `tokens` (the board's rendered CSS, **the package's declared
> source of truth**), cross-checked against `PHASE-2-DESIGN-SYSTEM.md`. Intake:
> `docs/DESIGN_INTAKE_REPORT.md`."*

`DESIGN_INTAKE_REPORT.md` completes the chain:

- the **authoritative** Mobile package — `12circle-fitness-new-screens.zip`, sha256
  `d4438803deee…88d32`, `manifest.json` → **`sourceOfTruth: design`**, *"READY FOR CLAUDE CODE"*.
  **No longer on disk**; the intake report is now the only record of it — the same pattern as the 41 KB
  Build Spec original;
- the legacy `fitness-app-board/` — ***"REJECTED as implementation authority … must not be merged,
  reconciled, or used as visual authority"***, **but** its `PHASE-2-DESIGN-SYSTEM.md` retains a scoped
  role: its *"SPECIFICATION ONLY"* banner *"scopes to that one document, and `IMPLEMENT-THIS.md` … points
  **at** that document for token values."*

**What this establishes as evidence:** the declared implementation-authority chain is
**design package `manifest.json` (`sourceOfTruth: design`) → `IMPLEMENT-THIS.md` → Dart Helix Tier 1-3**,
carrying an explicit ***"No parallel theme"*** directive. **The standalone `/projects/helix` repository
appears nowhere in it** — no dependency declaration, no mention in the intake report, none in the CI
workflow, none in the conformance test.

**What it does NOT establish:** whether the standalone repository is the canonical *design system* going
forward, and whether it should be updated, retired or re-pointed. The global direction treats
`/projects/helix` as the reusable cross-product system; this repository's own chain implements into Dart
tiers. **Both can be true. Which governs is a design-system authority decision and is NOT resolved by
recency, visual preference or inference.** Neither system was rewritten.

## 22 · Admin tokens — four distinct layers, and the design authority itself declares the question open

| layer | artifact | status |
|---|---|---|
| **1 · Source design authority** | the six approved `.dc.html` pages | **authoritative** — `CONF-D4`; `PROVENANCE.md`: *"Owner-approved designs … Design authority"* |
| **2 · Derived extraction** | `brand/tokens/admin.tokens.{json,css}` | **derived, validated 97.7%** (§104.1). *"Derived, not invented."* **Not canonical** |
| **3 · Implementation token source** | `apps/mobile/lib/core/helix/` Tier 1-3 | the declared implementation target (§21), CI-conformance-tested |
| **4 · Runtime design-system dependency** | Nocturne `_ds` bundle | **design-tool only; must not ship** (§23) |

**The design package declares the alignment question itself.** Handoff §6: *"**One** violet `#7C3AED` /
accent `#A78BFA`, dark ground, Schibsted Grotesk, Phosphor icons, status semantics, 4.5:1 text contrast,
44px controls, 2px focus ring. **Admin tokens (`--adm-*`) are documented**; Mobile uses the Helix
three-tier system."* And §8 lists ***"Admin vs Helix token alignment"*** among its **unresolved
boundaries**.

> **So the design authority asserts ONE shared identity — corroborating the 11/11 measurement as a
> declaration, not a coincidence — while positioning `--adm-*` as *documentation* and leaving the token
> home explicitly open.** The boundary is confirmed by the design authority, not merely declined by me.

**One asymmetry worth recording:** the Mobile package carried a machine-readable `manifest.json` with
`sourceOfTruth`; **the Admin package carries no equivalent — 0 files declare `sourceOfTruth` or
`handoffVersion`.** Its authority rests on prose plus the pages themselves.

## 23 · Nocturne — located and documented, unchanged

**Documented, not copied; no `.dc.html` modified; not renamed or substituted.**

| file | bytes | sha256 (first 16) |
|---|---|---|
| `styles.css` | 13,029 | `6fea354710ec4e3b…` |
| `_ds_bundle.js` | 300 | `aceb66bfea8c86f6…` |
| `_ds_manifest.json` | 7,480 | `232f36fe241f1d1d…` |
| `readme.md` | 8,307 | `dcc4460813d2feb7…` |
| `_adherence.oxlintrc.json` | 4,195 | `06186bb46f06c0fa…` |

Present at **two** locations — `~/Desktop/community-portal/_ds/nocturne-042b8c43-…/` and
`~/Desktop/mobile-app/_ds/nocturne-042b8c43-…/` — **byte-identical in both**. Manifest: namespace
`Nocturne_noctur`, **`themes: []`**, **`fonts: []`**, `source: spa`.

**`themes: []` is confirming evidence**: Nocturne declares no themes, so it is not a product theme system
and not Helix. **It remains an artifact/rendering dependency.** Whether to vendor it into the design
branch for offline fidelity is a **publication decision**, not taken here.

## 24 · Policy registry — entity-by-entity trace

| # | entity | existing support | additive requirement | blocked by |
|---|---|---|---|---|
| 1 | **`policy`** | none | code · category · scope · owner · lifecycle | **D7** (scope cites roles) · naming (§16.4b) |
| 2 | **`policy_version`** | none | monotonic version · `effective_from` · retired_by (**individual or body**) · change note | — |
| 3 | **`policy_rule`** | none | first-class predicate rows | — |
| 4 | **`policy_set`** | none | independent set version (`v3.14`) · membership · last full evaluation | — |
| 5 | **`principal`** | `user_profiles.role` (7) + `actor_provenance` (`grounded/asserted/system`) | **agent + workflow registry**; *"agents without a policy: 0"* needs completeness | **D7** · `A10` |
| 6 | **`resource`** | `audit_events.action` is free text; no resource column | **typed** resource reference | **A12** (§26) |
| 7 | **`policy_evaluation`** | who/action/**outcome**/when | resource · policy ref · **risk** · quantified detail · incident link | **D7 · A12 · §25** |

**Cross-check against the five models is unchanged from §16.4** and confirmed by this trace: the registry
**describes and audits; RLS and the SQL predicates of §98.1 remain the enforcement floor.** Nothing here
proposes moving enforcement.

## 25 · Audit population — A versus B, consequences characterized

**Neither is selected. The constraints are symmetric and the decision is architectural.**

| | **A · extend the audit architecture** | **B · separate operational store** |
|---|---|---|
| `A1` four populations | **adds to an existing population** — no fifth invented | **creates a non-audit store** — arguably no audit population added at all, but that reading must be ratified, not assumed |
| `A2` 15 categories | needs a **16th** for evaluations ⇒ **a `D4` change**, not an implementation detail | none needed |
| `A11` append-only + freeze | evaluations are append-only by nature — **fits**; but policy *state* (Draft→Active→Retired) is **mutable**, and `A11` refuses UPDATE to every caller incl. `service_role` ⇒ **state cannot live in the frozen population** | mutable state is natural |
| `A6` delta exclusions | must be honoured for any diff | unaffected |
| `A12` | inherits pseudonymisation **by construction** — a real safety advantage | **must re-implement it**; §26 |
| `A13` read path | inherits `audit_read_events()` + `R-1`'s `audit_read` emission | needs its own read authorization |
| volume | 31,440 req/24 h into a **6-year** population | can carry `operational_90d` |
| retention | `audit_6y` | D12 already defines **`operational_90d`** (`145:54`) |

**The decisive tension, stated plainly:** **A** gives `A12` and `A13` for free but collides with `A2`'s
fixed category list, `A11`'s immutability for mutable policy state, and six-year retention of
high-volume operational data. **B** fits volume, retention and mutability but **must re-earn `A12` and
`A13` from scratch — the controls most expensive to get right.**

**A hybrid is visible in the evidence and is not proposed as the answer:** policy *state* in an
operational store; *material* events (a block, an escalation, a version transition) emitted into the
existing audit population under an existing category. **Whether that avoids a 16th category is exactly
the question only `D4` authority can answer.**

## 26 · `A12` — the minimum privacy-preserving representation

**Built only from mechanisms that already exist. No new identity-resolution path is created.**

| element | minimum representation | mechanism already present |
|---|---|---|
| **Subject** | `subject_pseudonym` — **never a name or email inline** | `142` |
| **Actor / principal** | real identity is acceptable. **`A12` protects SUBJECTS, not ACTORS** — administrators and agents are actors, and `audit_events.actor_id` already carries a real uuid | `142` · `A13·1` |
| **Resource** | **typed class + count** — `Client records ×1,240` — never an enumerated list of subjects | new, typed |
| **Quantity** | the count itself is non-identifying and is the point of the control | — |
| **Re-identification** | **only** via the definer path, role-gated, **emitting `audit_read`** — i.e. an explicit audited action in the UI, never inline rendering | `146` · `152` · `R-1` |
| **Incident linkage** | link by pseudonym + incident id, never by subject identity | `143` |
| **Retention** | reuse D12's **`operational_90d`** rather than inventing a class | `145:54` |
| **Severance** | on severance the pseudonym is severed and evaluation rows become **permanently unresolvable** — correct, and requires **no deletion**, preserving `A11` | `152` S-2 |

**The capability survives intact at this representation**: *"38 failed sign-ins on one coach account from
3 countries"* renders as pseudonym + count + geo-count; *"Export client records · 1,240 records
requested"* as typed resource + quantity. **Neither needs a cleartext subject.**

> **Remaining `A12` decision — genuinely an authority question:** does the Trust operator's
> *"resolve identity"* action exist on these surfaces at all, and if so under which role? That is a
> `CONF-D7` **and** security-authority question. **`A12` is not weakened to answer it.**

## 27 · AI Guardian in Trust — new evidence, still unresolved

**The design package subordinates itself to V5 on governance.** Handoff §5: ***"Owner-approved designs are
visual authority. V5 decisions are product/governance authority."***

This cuts toward `D11`/§19.2 — placement of a capability within a phase's scope is a governance question,
and the package says V5 governs those. **But it does not settle it**, because the owner has already
treated the same design as authoritative for **information architecture** (`CONF-D1`'s six-item IA, §91),
and whether "which area a capability lives in" is IA or governance is **precisely the ambiguity.**

**Evidence recorded; conflict unresolved; capability preserved — not deleted, relocated, hidden,
redesigned, nor the governance decision reinterpreted.**

## 28 · Architecture extension register

| # | capability | existing support | missing | security / RLS | authorization | migration | owner decision | authorized? |
|---|---|---|---|---|---|---|---|---|
| 1 | **Policy registry** (7 entities) | none | §24 | registry must not become enforcement (§16.4a) | **D7** | additive | **D7** + `D4` on §25 | **NO** |
| 2 | **Policy naming** distinct from RLS | — | vocabulary | 202 RLS policies collide | — | — | design-system authority | **NO** |
| 3 | **Risk axis** | none | `High/Medium/Low`, distinct from severity | — | — | additive | §100.5 #3 | **NO** |
| 4 | **Guardian policy-set telemetry** | none | set version, median decision time, completeness | `A10` independence | **D7** | additive | §27 conflict | **NO** |
| 5 | **Agent / workflow registry** | `actor_provenance='system'` only | agent identity, workflow | `A10` | **D7** | additive | §27 | **NO** |
| 6 | **Notification telemetry** | `notifications` (read only) | sent/delivered/failed/pending | recipient identity ⇒ `A12` | — | additive | none | **NO** |
| 7 | **Community reporting / moderation** | posts/comments/groups/pods | report + moderator state machine | moderator cross-user read ⇒ `CONF-D8` | **D7** | additive | `CAP-1` policy | **NO** |
| 8 | **Wearable ingestion health** | `user_integrations` (connections) | `WI-13` telemetry | PHI-class (`WI-14`) | — | additive | **`PD-G01` not released** | **NO** |
| 9 | **Revenue decomposition** | `payments.amount_cents` only | local amounts, MRR, churn | financial | — | additive | gross-vs-commission · `PD-C03` | **NO** |
| 10 | **Helix token extensions** | 11/11 colour match | 4 roles incl. `status.info`, status tint/text/border, type scale, density, z-index, shadows | — | — | — | token home (§22) | **NO** |
| 11 | **Helix components** | 3 (`Button`,`Card`,`MetricReadout`) | **≈30** | — | — | — | design-system authority | **NO** |
| 12 | **Phosphor icon system** | none in Helix | v2.1.1, 107 icons | — | — | — | design-system authority | **NO** |
| 13 | **Human-readable incident refs** | `uuid` only | `INC-`/`AIN-` schemes, **two, unreconciled** | — | — | additive | which scheme | **NO** |
| 14 | **Reviewer assignment** | `actor_identity` (actor) | reviewer + `Unassigned` | — | **D7** | additive | none | **NO** |
| 15 | **Settings configuration** (11 sections) | `platform_settings` (1 key); **no `organizations`**) | config store + change audit | every write is `A10`-auditable | **D7** | additive | none | **NO** |
| 16 | **Coach verification · partner approval** | `onboarding_complete/step` only | state machines | — | **D7** | additive | partner approval (§100.5) | **NO** |
| 17 | **Platform health store** | none | probes + status, **vendor-free** (`PD-A24`=`C`) | — | — | additive | none | **NO** |
| 18 | **CI / release ingestion** | CI produces it | ingestion path | **`P10` not released** | — | additive | CI vs gate ledger | **NO** |
| 19 | **DAU/WAU/MAU rollup** | sessions, check-ins | daily distinct-user rollup | member-derived ⇒ aggregates only | — | additive | "active" definition | **NO** |
| 20 | **Global search** | none | cross-domain index | must respect `A10` | **D7** | additive | none | **NO** |

**Twenty extensions. Implementation authorized for none. Eleven are blocked by `CONF-D7` alone.**

---

# PART V — `CONF-D7` DECIDED · DERIVED MAPPING (V5 §107)

## 29 · The owner decision

> **`CONF-D7` = Option 3 — PARTIAL REPLACEMENT.** The five approved Admin roles are the product/Admin-facing
> authorization vocabulary **for the four existing admin-class roles**; the member-role vocabulary remains
> for the member populations. **The seven database roles and their enforcement semantics are preserved** —
> this authorizes no replacement, deletion, rename, weakening or collapse. The exact mapping is **to be
> derived and documented without changing enforcement** until separately authorized.
> **`erasure_executor` remains a distinct security role** with its existing severance authority; it must
> **not** be mapped into the five ordinary Admin roles, nor given a normal Admin UI surface merely to
> complete the matrix — **its absence from the designed Administrators surface is intentional.**
> **`Platform admin` is a UI identity/display label**, not a sixth Admin role, unless repository evidence
> establishes a distinct authorization principal.

**`CONF-D7` is CLOSED.** Everything below is derivation and documentation under it. **No enforcement
changed.**

## 30 · `Platform admin` — the evidence test the ruling conditions on

**Searched the whole repository: 10 occurrences of "Platform admin" — every one of them in V5 documents I
wrote, describing the design observation. In `supabase/` and `apps/`: ZERO.** No `platform_admin` role
value, claim, predicate or grant exists anywhere.

**Verdict: the evidence does NOT establish a distinct authorization principal. `Platform admin` is a UI
identity/display label**, exactly as the ruling's default provides. **Settled.**

## 31 · The derived mapping — and the finding it produces

**Enforcement footprint of the four admin-class roles, measured:**

| DB role | inline RLS role-lists | dedicated predicate | used at |
|---|---|---|---|
| `admin` | **14** | `is_admin()` | 019, 144, 145, 151, 147 + 14 RLS clauses |
| `content_manager` | **9** | **NONE** | 089, 091, 095, 096 — inline `role in ('admin','content_manager',…)` only |
| `trust_operator` | 1 | `is_trust_operator()` | 144, 145, 151 |
| `erasure_executor` | 1 | `is_erasure_executor()` | **146, 152 — severance, exclusively** |

**The derived mapping, documented and NOT applied:**

| Admin role | design scope | enforcement counterpart today | basis |
|---|---|---|---|
| **Trust lead** | *"Security, AI oversight and audit"* · Full | **`trust_operator`** | the three sites gated `is_admin() OR is_trust_operator()` (144 control evidence · 145 observability · 151 incident open) are exactly this scope |
| **Content editor** | *"Community and training content"* | **`content_manager`** | its nine inline grants are the intelligence/communication/content domains (089, 091, 095, 096) |
| **Operations lead** | *"QA, releases, integrations, system"* | **NONE** | no predicate, no role; and the surfaces themselves have no tables |
| **Support** | *"Members and bookings, read-mostly"* · **Limited** | **NONE** | — |
| **Viewer** | *"Read-only across the admin"* · **Read-only** | **NONE** | — |

> **These two mappings are derived under explicit owner authorization and documented. They are NOT
> applied — no grant, predicate, policy or migration changes. `erasure_executor` is mapped to nothing, as
> ruled.**

### 31.1 The consequence — the Access levels have no enforcement substrate

**`is_admin()` is binary**: `SELECT EXISTS (… WHERE id = auth.uid() AND role = 'admin')`. **And there is no
graded authorization mechanism anywhere in the schema** — searched: `read_only` **0**, `readonly` **0**,
`limited` **0**, `access_level` **0**, `permission` **0** in any role/admin sense.

**Therefore, on today's substrate, three of the five Admin roles can only be expressed by granting full
`admin`** — which would make the design's **`Limited`** and **`Read-only`** access levels
**unenforceable**, and would hand a `Viewer` the same database authority as a Trust lead.

> **This is a security finding, and it is the real consequence of the `CONF-D7` decision. Implementing the
> Admin layer naively — mapping every unmapped Admin role onto `admin` — would be a privilege escalation
> relative to the approved design's own intent. It must not be done.**

**So the blocker across the register shifts from *"`CONF-D7` is undecided"* to a single, precise, additive
requirement: a GRADED ADMIN AUTHORIZATION MECHANISM.** Eleven register entries were blocked by `D7`;
**they are now blocked by this one thing instead.**

### 31.2 Where the graded mechanism must live — RLS, not the registry

§16.4(a) established that the policy registry **must not become the enforcement point**; RLS and the SQL
predicates of §98.1 remain the floor. **That constraint decides the shape of the fix, not its content:**

- the graded mechanism must be expressed **in SQL predicates and RLS** — the same place `is_admin()`,
  `is_trust_operator()` and `is_erasure_executor()` already live;
- the **policy registry describes and audits it** (`RB-01 · admin`, `RB-06 · support read`,
  `RB-09 · trust manage` are exactly those predicates, named and versioned);
- **the registry is therefore the documentation layer for the graded mechanism, not its implementation** —
  which is both what §105 required and what makes `RB-nn` coherent.

**A consistency gap falls out of the same analysis:** `content_manager` is the only admin-class role with
**no dedicated predicate function**, carried instead by nine inline `role in (…)` lists. If `Content
editor` maps to it, that asymmetry becomes load-bearing. **Recorded as additive; not changed.**

## 32 · `CONF-D8` — its input now exists

§90.5 placed `CONF-D8` behind `CONF-D7`. **`CONF-D7` is now decided, so the input exists** and §90.4's
*"plausibly inside §19's delegation once their inputs exist"* becomes live.

**What the evidence now says:** `CONF-D8`'s two candidate answers were *"caller-RLS + new admin policies"*
**or** *"curated bypassing views"*. The `019` precedent is the second — `SECURITY DEFINER` + `is_admin()`,
*"rather than loosen per-table RLS"*. **But §31.1 shows that precedent cannot express `Limited` or
`Read-only` either**, because its gate is the same binary predicate. **So `CONF-D8` and the graded
mechanism are the same problem**, and a curated-view answer must still carry a graded gate.

**`CONF-D8` is NOT declared decided here.** Choosing between extending RLS per Admin role and widening the
definer-view pattern with graded gates is a genuine architectural choice with different security
properties, and §19's delegation is a historical grant whose reach to this question is not established in
the record. **This is the next architectural decision point.**

## 33 · Register — the eleven `D7`-blocked entries, reassessed

| # | entry | was | now |
|---|---|---|---|
| 1 | Policy registry | D7 | **graded mechanism** + audit-population (`D4`) |
| 5 | Principal / agent registry | D7 | **unblocked in part** — human principals now have a vocabulary; **AI agents still `A10`/§27** |
| 7 | Policy evaluation | D7 | **`A12` + audit-population** |
| 4 | Guardian policy-set telemetry | D7 | **§27 Guardian-in-Trust conflict** |
| 7′ | Community moderation (`CAP-1`) | D7 | **graded mechanism** (moderator ≈ Content editor scope) + `CAP-1` policy question |
| 14 | Reviewer assignment | D7 | **unblocked** — a reviewer is an Admin-role holder |
| 15 | Settings configuration | D7 | **graded mechanism** — every write is `A10`-auditable |
| 16 | Coach verification · partner approval | D7 | **graded mechanism** + partner-approval owner decision |
| 20 | Global search | D7 | **graded mechanism** — scope follows the role |
| 6 | Resource model | D7 | **`A12`** (§26) |
| 2 | Policy naming | — | design-system authority (unchanged) |

**Net: `CONF-D7` closing converts eleven distinct blockers into three — the graded mechanism, the
audit-population decision, and `A12` — plus the standing Guardian conflict.**

## 34 · `A12` — the question §26 left open is now partly answered

§26 left one item open: *does a "resolve identity" action exist on these surfaces, and under which role?*

**The `D7` decision answers the second half in principle:** it would be an **Admin-role** capability, and
by scope **`Trust lead`** is the only one of the five whose description (*"Security, AI oversight and
audit"*) covers it. **Its enforcement counterpart is `trust_operator`, which already holds the
`audit_read_events()` definer path and the `A13·1` read policy.** So the capability has a home that
requires **no new identity path** — exactly §26's constraint.

**Still open, and still a security-authority question:** whether the action exists on the **attention
queue** and **People** surfaces at all, as opposed to only inside Trust › Audit. **`A12` is not weakened
to settle it.**
