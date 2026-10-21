# 12Circle+ Admin Control Center — Dashboard Build Specification V1

**Owner-provided design/product authority artifact. Durable, unaltered, authoritative.**

| | |
|---|---|
| **Brand** | **12Circle** |
| **Product** | **12Circle+** |
| **Product tagline** | **Connecting Coaches. Clients. Communities.** |
| **Surface** | **Admin Control Center** |
| **Artifact** | **12Circle Admin Control Center Dashboard Build Specification V1** |
| **Status** | **Owner-provided / approved design-product authority** |
| **Purpose** | Admin visual direction, information architecture, operational scope, required states, design handoff requirements, and build protections |
| **File** | [`12CIRCLE_ADMIN_CONTROL_CENTER_DASHBOARD_BUILD_SPEC_V1.docx`](12CIRCLE_ADMIN_CONTROL_CENTER_DASHBOARD_BUILD_SPEC_V1.docx) |

The document's own masthead reads **"12CIRCLE ADMIN CONTROL CENTER · DASHBOARD BUILD SPECIFICATION ·
V1 — VISUAL DIRECTION + PRODUCT REQUIREMENTS"**, under the line
**"12Circle+: Connecting Coaches. Clients. Communities."**

## Why it is here

It is committed so it is reachable from the repository — and from GitHub — during the later Admin and
Mobile design audit and implementation. **It is stored byte-for-byte as supplied: not rewritten,
reformatted, summarised, or altered.** Where any derived document in `docs/` paraphrases it, **this file
governs.**

## Naming — read before writing anything that names the product

- **12Circle** is the **brand**. **12Circle+** is the **product** offered under it.
- **The product is not "12Circle Fitness".** Do not introduce *Fitness* into the product name. The
  repository directory and the mobile application bundle carry older names; **those are pre-existing
  identifiers, not the product name**, and this artifact does not rename them.
- Use the specification's own terminology (§9): **Coach · Client/Member · Wellness Partner · Community ·
  Guardian · Ecosystem**.

## Design basis — Fitonist is the inspiration, not the identity

The specification is explicit, and the distinction must be preserved in anything built from it:

> *"Design basis: the attached Fitonist dashboard reference. The 12Circle Admin Control Center should use
> the same overall visual language … **while introducing a distinct 12Circle visual identity and
> information architecture**."* — masthead
>
> *"Use the attached dashboard as the **visual foundation, not as a screen-by-screen copy**."* — §1

**The resulting Admin product is a 12Circle+ product and must not be described as Fitonist.** §9 requires
12Circle branding, terminology, visual motif and *"distinctive 12Circle data visualizations rather than
reproducing the reference charts exactly"*.

## What the document contains

**18 numbered sections plus a five-level appendix** — 186 paragraphs, ~1,406 words:

| § | content |
|---|---|
| 1 | Design principle — *"an operational control center, not merely an analytics page"* |
| 2 | Primary Admin navigation — 8 items proposed |
| **3** | **Overview dashboard — the 12 data groups**: Platform Health · Active Users · Revenue · AI Guardian · Security · Community · Training · Wellness Partners · **Engagement (DAU, WAU, retention)** · Notifications · **Wearables (connected devices, synchronization health, ingestion issues)** · System Alerts |
| 4 | Top system status strip — *"live, severity-aware, clickable, and traceable"* |
| 5 | AI Guardian panel — state **Active / Monitoring / Degraded / Disabled**, detections with evidence and confidence, approvals, autonomous-action audit trail, **emergency disablement**, and the *"clear distinction between observation, recommendation, autonomous action, and human-approved action"* |
| 6 | Five operational layers |
| 7 · 8 · 9 | Visual system · reference elements to retain · **12Circle flare** |
| **10** | **Live data requirement** — *"**No hard-coded KPI values in production**"*; *"QA environment should use deterministic, clearly marked relational data"*; *"**Every metric should have a defined source, calculation, freshness expectation, and authorization boundary**"* |
| 11 | **15 Admin data domains** |
| 12 | **Security & governance** — role-based least privilege · sensitive data minimised · every high-impact administrative action auditable · AI agents do not inherit unrestricted admin authority · policy gates and human approval · security controls independent of the Guardian · *"**Dashboard data must respect the same authorization boundaries as the underlying system**"* |
| 13 | 15-step build sequence |
| **14** | **11 required screen states** — populated · empty · loading · partial-data · error · degraded-system · unauthorized · no-permission · offline/disconnected · critical-incident · Guardian-approval-required |
| **15** | **Build protection rule** — *"The Admin Control Center is **additive**. It must not alter, delete, or regress the existing **174 approved application screens**."* |
| 16 | Design handoff requirements — 13 items |
| 17 | Success criteria |
| 18 | Design direction summary + **LEVEL 1–5** (Executive Overview · Ecosystem · Operations · AI Guardian · Security & Governance) |

## Provenance — and a version distinction that matters

| | |
|---|---|
| Supplied as | `12Circle+_Admin_Control_Center_Dashboard_Build_Spec_V1.docx` |
| Size | **424,144 bytes** (largely embedded RobotoMono/Roboto font files; **no images**) |
| SHA-256 | `2b564ce633ac21b6c04f0960b221b7aa5121faedb1df8bfc9166204f5d368a68` |
| Verified | byte-identical to the supplied source (`shasum -a 256` + `cmp`) |
| Committed | 2026-09-30 |

> ### ⚠ This is NOT the file the programme record's `A1`–`A14` were read from
>
> `V5_DESIGN_AUTHORITY_RECONCILIATION_2026-09-27.md:27` inventories
> `12Circle_Admin_Control_Center_Dashboard_Build_Spec_V1.docx` — **41,291 bytes, 2026-09-25, 166
> paragraphs, ~1,343 words**, read from `~/Downloads` and never committed.
>
> **This file is larger and later: `12Circle+_…`, 424,144 bytes, 186 paragraphs, ~1,406 words.** Both are
> "V1". **This one is the committed, durable artifact and governs.** No claim is made here that the two are
> identical — they are not the same file, and the earlier one is no longer on disk to diff. The sections
> underpinning `A1`–`A14` are all present in this file and were read in full before it was committed.

## Related

- `docs/design/admin-control-center/` — the owner-supplied **approved Dashboard screenshots**, which are
  the **design authority** for the screens shown (`CONF-D4`, closed at V5 §97).
- `docs/V5_ADMIN_DASHBOARD_DATA_CONTRACT.md` §11 — the 14 Dashboard areas reconciled against existing
  authority, including this specification's §3, §10, §12 and §14.
- `docs/V5_ADMIN_TRUST_DESIGN_COMMISSION.md` · `docs/V5_PROGRAMME_DEFINITION.md` §§97–100.

**This README describes the artifact. It does not interpret, extend or supersede it.**
