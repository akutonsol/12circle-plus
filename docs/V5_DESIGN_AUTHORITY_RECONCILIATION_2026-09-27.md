# V5 DESIGN AUTHORITY RECONCILIATION

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** DOCUMENTATION-ONLY. No implementation, no remediation, no mutation.

> **IMPLEMENTATION REMAINS UNAUTHORIZED.**

---

## 0 · PROVENANCE NOTICE — READ FIRST

**No design artifact was attached to the mission that requested this reconciliation.** Verified:
HEAD `07f5bfb`, 0 modified, 0 staged, no new untracked files in the repository, and nothing added to
`~/Downloads` since the V5 specification (2026-09-26 22:54).

One plausibly-relevant file **already present** on disk was located and inventoried:

| | |
|---|---|
| File | `~/Downloads/12Circle_Admin_Control_Center_Dashboard_Build_Spec_V1.docx` |
| Size / date | 41,291 bytes · **2026-09-25 22:12** — *one day before the V5 specification* |
| Read in full | 166 paragraphs, ~1,343 words, 18 numbered sections |
| **Authority status** | **UNCONFIRMED** |

**Authority is marked UNCONFIRMED for three evidenced reasons, not as a formality:**

1. **The document is a brief, not a package.** Its own §16 "DESIGN HANDOFF REQUIREMENTS" *requests*
   an *"Approved screen package, component/state specifications, interaction behavior, responsive
   rules, typography and spacing, chart specifications, iconography, colour and status semantics,
   accessibility requirements, live-data mapping…"* — i.e. **it specifies what an approved handoff
   must contain, which means that handoff does not yet exist.** This is a design *input*, upstream
   of design authority.
2. **Its stated visual basis is absent.** It repeatedly cites *"the attached Fitonist dashboard
   reference"*. That reference is not on disk and was not supplied, so the visual foundation the
   document depends on cannot be inspected.
3. **It was not supplied to this mission.** Treating a file as approved design authority because it
   exists is precisely what Step 2 of the mission forbids: *"Do not assume a design file is
   authoritative merely because it exists."*

**Consequently this document inventories the Admin brief exactly and records what it advances, but
does not treat it as design authority, and B2 is not closed.** **No Trust artifact exists in any
form** — no file, and zero mentions of "Trust", "AI Guardian" or "Incidents" across the seven
repository design documents.

## 1 · DESIGN AUTHORITY INVENTORY

| Field | Value |
|---|---|
| **Name** | 12Circle Admin Control Center — Dashboard Build Specification |
| **Type** | **Build specification / visual direction brief** — *not* an approved screen package |
| **Version** | V1 — "VISUAL DIRECTION + PRODUCT REQUIREMENTS" (self-described) |
| **Date** | 2026-09-25 |
| **Source** | `~/Downloads/…docx` — **not attached to this mission; provenance and approval unconfirmed** |
| **Design area** | Admin Control Center only |
| **Screens included** | **NONE.** No screen frames, no wireframes, no visual comps. It describes an *intended* Overview dashboard and names operational views to be designed later (§13 steps 3–6) |
| **Flows included** | **NONE explicitly.** §13 step 4 names *"AI Guardian views and incident workflows"* as work to be done |
| **Components included** | Described, not specified: status strip, metric cards, time-range segmented controls, calendar/time card, bar+line charts, donut distribution, geographic visualization, compact top nav, search, admin identity control (§8) |
| **Data shown** | 12 Overview groups (§3) and 15 Admin data domains (§11) — see §2 |
| **User roles** | "authorized administrator" (§17); terminology **Coach · Client/Member · Wellness Partner · Community · Guardian · Ecosystem** (§9). **No role matrix, no permission model** |
| **Actions** | Guardian approval; **Emergency Guardian disablement**; clickable/traceable status indicators; search; time-range filtering |
| **Security-sensitive actions** | Emergency Guardian disablement · Guardian autonomous actions · Guardian approvals · sensitive-data access (§12) |
| **Audit-sensitive actions** | *"Every high-impact administrative action is auditable"* (§12) · *"Completed autonomous actions with audit trail"* (§5) · "Audit logs" as a data domain (§11) |
| **Dependencies** | **the Fitonist visual reference (absent)** · a locked 12Circle brand identity package (§9: *"once the final identity package is locked"*) · authoritative live data (§10) · existing repository architecture (§13 step 9) |

## 2 · ADMIN DESIGN MATRIX

Navigation the brief proposes (§2, **8 items**): Overview · Ecosystem · Users · Finance · Analytics ·
Security · AI Guardian · Operations.

Status legend: **SUPPORTED · PARTIALLY SUPPORTED · NOT SUPPORTED · NOT SPECIFIED · CONFLICT**

| Surface | Design exists | Design complete | V5 requirement | Data req | Role req | Action req | Audit req | API req | DB req | Security req | QA req | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Overview / Home** | brief only (§3) | **NO** — no frames | YES (AD-01) | 12 groups named | NOT SPECIFIED | status drill-down | NOT SPECIFIED | none exists | **observability store absent** | §12 principles | §13 step 12 | **NOT SUPPORTED** |
| **Users** | brief only (§2, §11) | **NO** | YES | "Users & identities" | NOT SPECIFIED | NOT SPECIFIED | **implied by §12** | `admin_recent_users()` only | PARTIAL | least privilege | — | **PARTIALLY SUPPORTED** |
| **Coaches** | **not a nav item** | NO | PARTIAL | "Coach/client relationships" | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | PARTIAL | — | — | **NOT SPECIFIED as a surface** |
| **Clients** | **not a nav item** | NO | PARTIAL | as above | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | PARTIAL — **PHI views blocked by NEW-5** | — | — | **NOT SPECIFIED as a surface** |
| **Ecosystem** | brief only (§6) | **NO** | **NOT SPECIFIED in V5** — V5 never defines "Ecosystem" as an Admin module | 9 sub-domains named (§6) | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | mixed | — | — | **NOT SUPPORTED** |
| **Exercise Review** | **not in brief** | — | YES | migration `050` | `is_admin` | implemented | **NOT SPECIFIED** | exists | **exists** | — | — | **CONFLICT — implemented but omitted from the brief's IA** |
| **Observability** | **not in brief** (closest: "Operations") | — | YES (SQ-10) | **0 DB tables** | `is_admin` | implemented | NOT SPECIFIED | none | **absent** | — | — | **CONFLICT — implemented but omitted; and unsupported by data** |
| **Security** | brief only (§2, §6) | **NO** | YES | auth/authz/RLS/admin actions/sensitive-data access/audit/security events (§6) | NOT SPECIFIED | NOT SPECIFIED | **YES (§12)** | none | **no product-facing posture store** | §12 | — | **NOT SUPPORTED** |
| **Incidents** | brief only (§6 "Operations", §5) | **NO** | YES — **11 fields + severity enum** | **no incident table** | NOT SPECIFIED | approval workflow | YES | none | **absent** | — | — | **NOT SUPPORTED** |
| **Audit Logs** | brief only (§11) | **NO** | YES — field-sets specified | **no audit table** | **NOT SPECIFIED — who may read is undefined** | NOT SPECIFIED | it *is* the requirement | none | **absent** | — | — | **NOT SUPPORTED** |
| **AI Guardian** | brief only (§5) — **the most detailed section: 10 elements** | **NO** — no frames | YES (8 domains, L0–L3) | detections, evidence, confidence, approvals, autonomous-action trail | NOT SPECIFIED | **approval · emergency disablement** | **YES (§5)** | none | **absent** | §12 | — | **NOT SUPPORTED** |
| **Settings / Configuration** | **not in brief** | — | **NOT SPECIFIED in V5** | — | — | — | — | — | — | — | **NOT SPECIFIED** |
| **Finance** | brief only (§2, §3) | **NO** | PARTIAL (V5 "payments") | MRR, subs, transactions, refunds | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | Stripe fns | PARTIAL | — | — | **PARTIALLY SUPPORTED — 6 open K specs** |
| **Analytics** | brief only (§2, §3) | **NO** | YES ("analytics") | DAU/WAU/retention | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | **absent** | — | — | **NOT SUPPORTED** |
| **Operations** | brief only (§6) | **NO** | PARTIAL | incidents, jobs, integrations, notifications, failures, performance, deployments | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | **absent** | — | — | **NOT SUPPORTED** |
| **Wearables (Admin view)** | brief only (§3, §11) | **NO** | YES (WI-15) | **"Connected devices, synchronization health, ingestion issues"** | NOT SPECIFIED | NOT SPECIFIED | NOT SPECIFIED | none | `user_integrations` only | **see §7** | — | **PARTIALLY SUPPORTED** |

**0 of 16 Admin surfaces have an approved design.** Two implemented surfaces (Exercise Review,
Observability) are **absent from the brief's information architecture** — recorded as conflicts, not
reconciled.

## 3 · TRUST DESIGN MATRIX

| Surface | Present in supplied design? | Established as a V5 requirement? | Status |
|---|---|---|---|
| **Trust Home** | **NO** | **NO** — not named in V5 | **NOT ESTABLISHED.** Appeared in a mission brief only; **not promoted** |
| **AI Guardian** | **as an Admin nav item and panel, not as a Trust surface** | **YES** — V5 §18–21 | **NOT SUPPORTED** |
| **Security** | **as an Admin nav item** | YES | **NOT SUPPORTED** |
| **Incidents** | **as an Admin operational layer** | YES (AG-04) | **NOT SUPPORTED** |
| **Audit Logs** | **as an Admin data domain** | YES | **NOT SUPPORTED** |
| **Reviews** | **NO** | **NO** — not named in V5 | **NOT ESTABLISHED; not promoted** |
| **Policies** | **NO** | **NO** — not named in V5 | **NOT ESTABLISHED; not promoted** |
| **Alerts** | partially — "System Alerts" (§3), "alerting" (V5 §17) | PARTIAL | **NOT SUPPORTED** |
| **Agent oversight** | **YES, in substance** — §5 Guardian Panel | YES (V4) | **NOT SUPPORTED** |
| **Security events** | named (§6) | YES | **NOT SUPPORTED** |
| **Governance controls** | §12 principles | YES | **NOT SUPPORTED** |

### A structural finding about Trust

**The supplied Admin brief contains no "Trust" section, module, or navigation item.** Instead it
places AI Guardian, Security, Incidents and Audit Logs **inside Admin** — as nav items (§2) and
operational layers (§6). V5 likewise never uses the word "Trust".

**So "Trust" as a distinct product area is evidenced by neither V5 nor the supplied design.** It
originates in the mission briefs. This is a **material taxonomy question**, recorded as new owner
decision **D-D1** and not resolved: *are Security / Incidents / Audit / Guardian an Admin section
set (as the brief and V5 both structure them), or a separate "Trust" area?* The answer changes the
information architecture, the route structure, and the permission model.

**Trust Home, Reviews and Policies are explicitly NOT promoted to requirements.**

## 4 · V5 ↔ DESIGN RECONCILIATION

Original terminology is preserved; nothing is normalized silently.

| V5 requirement | Design requirement | Design evidence | Repository evidence | Conflict | Missing | Decision required | Implementation dependency |
|---|---|---|---|---|---|---|---|
| Admin over **13 domains**: health, security, users, roles, payments, AI, wearables, database, incidents, releases, analytics, audit | **8 nav items**: Overview, Ecosystem, Users, Finance, Analytics, Security, AI Guardian, Operations | §2 | 3 screens | **YES — taxonomy mismatch.** V5 "payments" ↔ design "Finance"; V5 "roles/database/releases" have no nav home; design "Ecosystem"/"Operations" have no V5 counterpart | roles, database, releases surfaces | **D-D1** | IA must be fixed before routing |
| Guardian autonomy **L0–L3** | *"Clear distinction between observation, recommendation, autonomous action, and human-approved action"* (§5) | §5 | none | **NO — the design matches V5's four levels in substance** | — | naming alignment | Guardian model |
| *"Emergency Guardian disablement must not disable core application security controls"* (AG-03) | *"Security controls remain independent of the AI Guardian"* (§12) + *"Emergency Guardian disablement control"* (§5) | §5, §12 | **RLS is enforced in Postgres, structurally independent** | **NO — design and V5 agree, and the current architecture already favours it** | proof as a designed control | architecture | Guardian |
| Incident record — 11 fields + severity enum | *"Recent detections with evidence and confidence"*, *"actions awaiting human approval"*, *"System Alerts: Critical, high, warning, informational"* (§3, §5) | §3, §5 | **no incident table** | **NO — design severity matches V5's enum exactly** | the table | A1/A2 | audit/incident schema |
| Agent action audit trail (V4 §5, 7 fields) | *"Completed autonomous actions with audit trail"* (§5) | §5 | **no audit store** | **NO — design asserts the requirement** | the store | A3 | audit |
| *"Never invent schema fields from designs. Record DATA GAP"* (GV-06) | *"Identify schema/data gaps before implementation"* (§13 step 8) · *"Every metric should have a defined source, calculation, freshness expectation, and authorization boundary"* (§10) | §10, §13 | contract guard enforces it | **NO — strong agreement** | — | — | data-gap workflow |
| No hard-coded data (GV-05) | *"No hard-coded KPI values in production"* (§10) | §10 | `is_demo` flag | **NO** | — | — | — |
| **"Protect the 174 approved existing screens"** (GV-03) | *"must not alter, delete, or regress the existing **174 approved application screens**"* (§15) | §15 | **91 routes / 148 surfaces; board 156/169** | **CONF-01 persists** — but see §11 finding | the canonical list | CONF-01 | SQ-30 scoping |
| Wellness Partner persona | *"Wellness Partners: Active partners, partner activity, offers/referrals/events"* (§3); terminology adopted (§9) | §3, §9 | **`vendor` role, 0 users, `events.vendor_id` NULL** | **partial** — design uses "Wellness Partner", repo uses `vendor`; **mapping still unstated** | the mapping | **D2** | partner work |
| Admin/Guardian **telemetry** (not member PHI) | *"Wearables: Connected devices, synchronization health, ingestion issues"* (§3) | §3 | `user_integrations` | **NO — the design asks for telemetry, consistent with V5** | — | — | **see §7** |
| Dashboard respects existing authorization | *"Dashboard data must respect the same authorization boundaries as the underlying system"* (§12) | §12 | **two views deliberately bypass RLS** (`security_invoker=off`) | **TENSION — see §5** | — | architecture | Admin data access |
| ASVS/mobile/API/web surfaces (SA-02) | dark **web** command centre, "without navigating through the consumer application" (§17) | §17 | — | **NO — corroborates D6's web reading** | — | D6 confirmation | Admin transport |

## 5 · SECURITY RECONCILIATION

Every security-sensitive Admin/Trust action the supplied design implies:

| Actor | Role | Resource | Action | Authorization check | RLS requirement | Audit required | Incident required | Reversibility | QA requirement |
|---|---|---|---|---|---|---|---|---|---|
| admin | `admin` | `user_profiles.role` | change a user's role | `admin_set_user_role()` + privileged GUC | existing; **`admin` not self-assertable — verified** | **YES — §12 "high-impact"; today it writes NONE** | on anomaly | reversible | permission + audit-emission test |
| admin | `admin` | user account | disable a user | **NOT SPECIFIED by design or V5** | **NOT SPECIFIED** | YES | — | **NOT SPECIFIED** | — |
| admin | `admin` | `coach_client_relationships` | change a coach/client relationship | **NOT SPECIFIED** | status + trigger exist | YES | — | reversible | — |
| admin | `admin` | `coach_team_members` | team leadership change | **NOT SPECIFIED — and this is the P0 surface** | **no `WITH CHECK`, no status, no role check** | YES | **YES** | reversible | **blocked by QAX-SEC-08** |
| admin | `admin` | PHI (`parq_answers`, weights, photos) | view client data | `is_admin()` | **column-limited views required — NEW-5 blocks the pattern** | **YES** | on bulk access | read-only | PHI boundary test |
| admin | `admin` | wearable data | view | **telemetry only per design + V5** | **D-V4 open** | YES | — | read-only | **see §7** |
| admin/Guardian | `admin`/agent | security incident | create / change state / resolve | **NOT SPECIFIED** | **no table** | **YES** | itself | — | lifecycle test |
| Trust/security operator | **role does not exist** | audit records | read | **NOT SPECIFIED — A13 open** | **not designed** | YES (read access is itself auditable) | — | read-only | **undesignable today** |
| **AI Guardian** | agent | production state | **autonomous action (L2)** | **allowlist + reversibility (V4)**; *"AI agents do not inherit unrestricted admin authority"* (§12) | agent least privilege | **YES — V4 §5 explicit** | **YES** | **must be reversible** | AST10 + runaway + containment |
| **AI Guardian** | agent | Guardian itself | **emergency disablement** | *"Security controls remain independent of the AI Guardian"* (§12) | **must not disable RLS** | **YES** | YES | reversible | AG-03 verification |
| admin | `admin` | policy / config | policy change | **NOT SPECIFIED** | — | YES | — | — | — |
| admin | `admin` | any record | **administrative override** | **NOT SPECIFIED by design or V5** | — | YES | YES | — | — |
| admin | `admin` | data | **export** | **NOT SPECIFIED** — §10 implies display only | — | **YES** | on bulk | n/a | — |
| admin | `admin` | data | **delete** | **NOT SPECIFIED** | — | YES | YES | **irreversible → V5 L3 human-required** | — |
| — | — | — | **impersonation** | **NOT PRESENT** in the design | — | — | — | — | **not designed; do not assume** |
| — | — | — | **account recovery / admin controls** | **NOT PRESENT** | — | — | — | — | **not designed** |

**Five security-sensitive capabilities a real Admin console normally needs — disable user, override,
export, delete, impersonate — are NOT SPECIFIED by either V5 or the supplied design.** They are
recorded as unspecified, **not inferred into existence**.

### The one substantive security tension found

§12 requires *"Dashboard data must respect the same authorization boundaries as the underlying
system."* But the repository's established pattern for cross-user display data is **deliberate RLS
bypass**: `public_profiles` and `conversation_participant_profiles` both set `security_invoker=off`
(owner `postgres`, `rolbypassrls = t`), which SEC-G4 documents as sound *because the column list is
curated*. An Admin console needs broad cross-user reads, so it will face exactly this choice.

**Recorded as an architecture decision, not resolved:** does Admin read through the caller's RLS
(requiring new admin-specific policies on many tables), or through curated `security_invoker=off`
views (matching the existing pattern but creating more RLS-bypassing surface)? **NEW-5 is the
cautionary precedent — the existing proposal for column-limited views is non-functional as written.**

## 6 · AUDIT RECONCILIATION

The three V5 record types are **kept separate**. The supplied design does not ask to merge them.

| Admin/Trust action (from the design) | Audit event required? | Event type | Actor | Target | Action | Result | Timestamp | Correlation | Evidence | Retention | Read access |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Change user role | **YES** — §12 "high-impact" | **audit event** | admin | user | role change | old→new | required | required (V5 §17) | — | **OWNER (A12)** | **OPEN (A13)** |
| View PHI / sensitive data | **YES** — §6 "sensitive-data access" is a named Security domain | **audit event** | admin | member record | read | fields accessed | required | required | — | OWNER | OPEN |
| Guardian **autonomous action** | **YES** — §5 "with audit trail"; V4 §5 | **agent action trail** (7 fields) | **agent identity — D-V5 open** | resource | action | result/error | required | required | input/context + authorization decision | **V5 defers** | OPEN |
| Guardian **approval** granted | **YES** | **incident record** field ("approval status") | admin | incident | approve | — | required | required | evidence + confidence | OWNER | OPEN |
| **Emergency Guardian disablement** | **YES** — highest-impact control in the design | **audit event + incident** | admin | Guardian | disable | — | required | required | reason | OWNER | OPEN |
| Incident state change / resolution | **YES** | **incident record** (11 fields, V5 enum) | admin/agent | incident | transition | resolution | required | required | evidence | OWNER | OPEN |
| Security event detection | **YES** | **incident record** | agent | resource | detect | severity | required | required | evidence; *"confidence is not proof"* | OWNER | OPEN |
| Policy / config change | **YES** by §12 | audit event | admin | config | change | old→new | required | required | — | OWNER | OPEN |
| Admin login / session | **NOT SPECIFIED** | — | — | — | — | — | — | — | — | — | — |

**What the design adds to B1:** it **enumerates concrete audit-requiring actions** where V5 gave
only the principle *"every high-impact administrative action is auditable."* That converts A2 (event
taxonomy) from wholly undefined to **partially enumerated** — 8 action classes now have a design
basis. **A2 remains an owner decision** because "high-impact" is still not defined, and the design
adds no field specifications of its own.

**Immutability:** **still NOT a V5 requirement and NOT a design requirement.** The supplied brief
contains no immutability, append-only or tamper-evidence language. It remains **architecture
decision A-NEW**, correctly labelled.

## 7 · WEARABLE PHI RECONCILIATION

Every wearable occurrence in the supplied design:

| Occurrence | Section | Data named | Raw or derived | PHI? | Telemetry? | Coach-facing? | Client-facing? |
|---|---|---|---|---|---|---|---|
| *"Wearables: Connected devices, synchronization health, ingestion issues"* | §3 Overview | device count, sync health, ingestion errors | **neither — operational metadata** | **NO** | **YES** | no | no |
| *"Wearables/integrations"* | §11 data domain | integration records | metadata | NO | YES | no | no |
| *"Wearable Guardian"* equivalent — ingestion/sync monitoring | §6 Operations | ingestion, failures | metadata | NO | YES | no | no |

**Finding — the design corroborates V5's distinction rather than widening it.** V5 gives Admin and
Guardian *"telemetry"* while giving *coach-facing* and *client/member-facing* intelligence to those
roles. **The supplied Admin design asks only for device counts, synchronization health and ingestion
issues — no heart rate, no zones, no member-level observations.** Admin and Guardian therefore
remain **telemetry-only** on the evidence of both sources.

| Question | Answer from source |
|---|---|
| Who can see it | Admin: **telemetry only** (design + V5 agree) |
| What data | connected devices, sync health, ingestion issues |
| Raw or derived | **neither** — operational metadata about the integration |
| Is it PHI | **No**, as scoped. Device *existence* is arguably sensitive but no physiological value is displayed |
| Telemetry | **Yes** |
| Coach-facing intelligence | **Not in this design** — V5 authorizes it separately (V3 §3) |
| Client-facing | Not in this design |
| Admin/Guardian telemetry only | **YES — corroborated by two independent sources** |
| Export possible | **NOT SPECIFIED** |
| Audit required | **YES** — §6 names "sensitive-data access" as a Security domain |

**B5 advances: the Admin arm is now evidenced as telemetry-only.** **D-V4 remains open** for the
questions the design does not touch: does "coach" mean active-only, and may a Partner ever see
member-level wearable data?

## 8 · TEAM SEMANTICS RECONCILIATION

| Term searched | Present in the supplied design? |
|---|---|
| "team" / "team lead" | **ABSENT** — the words do not appear |
| "coach" | present as a persona and in *"Coach/client relationships"* (§11) |
| "member" / "client" | present as *"Clients/Members"* (§3), *"Client/Member"* (§9) |
| relationship management | **only as a data domain** (§11) — no management UI, no actions |
| team assignment / team management | **ABSENT** |
| administrative override | **ABSENT** |

**The supplied design does NOT establish team semantics.** It names *"Coach/client relationships"* as
a **data domain to display**, with no actions, no lifecycle, and no mention of teams or team leads.

**Therefore D1 REMAINS OPEN**, and deliberately so: inferring team semantics from the absence of a UI
term, or from the presence of a data-domain label, would be exactly the *"invent the answer from UI
terminology alone"* failure the mission warns against.

| Finding | Effect of the supplied design |
|---|---|
| **QAX-SEC-08** (P0) | **none** — no team concept in the design; the P0 is untouched and still gates PHI |
| **F-03b** | **none** — notifications appear only as delivery metrics (§3), not as an authorization model |
| **SEC-PHI-9** | **none** — no coach-status lifecycle in the design |
| **QAX-SEC-09** | **partial** — "Wellness Partners" adopted as terminology (§3, §9), but never mapped to `vendor` and given no permissions |

## 9 · VENDOR RECONCILIATION

The design establishes **display-only** partner capability. No vendor *action* is specified.

| Vendor action | Resource | Authorization | PHI exposure | Audit | Incident | RLS | QA |
|---|---|---|---|---|---|---|---|
| *(none specified)* | — | — | — | — | — | — | — |
| **Admin views** partner activity | *"Active partners, partner activity, offers/referrals/events"* (§3) | `is_admin()` | **NOT SPECIFIED** — the underlying `hosts_event_for()` grants the **full `user_profiles` row incl. PAR-Q** | **YES** — §6 sensitive-data access | on anomaly | existing | **QAX-SEC-09 blocked** |

**D2 and B7 REMAIN OPEN.** The design neither grants vendors new capability nor addresses the
`hosts_event_for()` full-row arm. §10's pre-V5 hardening classification stands unchanged.

## 10 · CONFLICT REGISTER

| ID | Conflict | Evidence | Impact | Options | Owner | Status |
|---|---|---|---|---|---|---|
| **CONF-D1** | **Admin IA mismatch** — design's 8 nav items vs V5's 13 Admin domains; V5's roles/database/releases have no nav home; design's Ecosystem/Operations have no V5 counterpart | brief §2/§6 vs V5 SQ-16 | routing, permissions and the audit surface all key off IA | (a) adopt the 8-item nav and map 13 domains beneath (b) extend nav (c) owner reconciles both lists | **Owner** | **OPEN (D-D1)** |
| **CONF-D2** | **"Trust" is evidenced by neither V5 nor the supplied design** — both place Security/Incidents/Audit/Guardian **inside Admin** | 0 occurrences in both | whether Trust is a product area at all | (a) Admin section set (b) separate Trust area | **Owner** | **OPEN (D-D1)** |
| **CONF-D3** | **Two implemented Admin surfaces are absent from the brief's IA** — Exercise Review (`/admin-exercise-review`, migration 050) and Observability (`/observability`) | router + brief §2 | existing working surfaces could be orphaned or duplicated | (a) add to IA (b) deprecate (c) fold into Operations | **Owner** | **OPEN** |
| **CONF-D4** | **The supplied document is a brief, not an approved package** — its own §16 requests the package | brief §16 | **B2 cannot close** | supply the package | **Owner** | **OPEN** |
| **CONF-D5** | **The cited visual basis is absent** — *"the attached Fitonist dashboard reference"* | brief §1/§18; not on disk | visual system unspecifiable; also raises a derivation question the brief itself flags (*"not a screen-by-screen copy"*) | supply the reference | **Owner** | **OPEN** |
| **CONF-D6** | **Brand identity not locked** — *"once the final identity package is locked"* | brief §9 | final visual system blocked; V5 SQ-46 is the identity transition | supply or defer | **Owner** | **OPEN** |
| **CONF-D7** | **Admin authorization model unspecified** — no role matrix; only "authorized administrator" | brief throughout | `content_manager` (5 policies) and any ops roles unplaced | (a) `admin` only (b) add ops roles | **Owner** | **OPEN** |
| **CONF-D8** | **§12 "respect the same authorization boundaries" vs the repo's deliberate RLS-bypass view pattern** | brief §12 vs SEC-G4 | determines whether Admin needs new RLS policies or curated views | (a) caller RLS + admin policies (b) curated `security_invoker=off` views | **Architecture** | **OPEN** |
| **CONF-01** | 174 vs 91/148/156/169 | V5 GV-03 **and now brief §15** | protection unenforceable | see §11 | **Owner** | **OPEN — corroborated** |

**9 design-side conflicts (8 new), none resolved silently.**

## 11 · A NEW DATA POINT ON CONF-01

**The brief independently states the same figure:** *"It must not alter, delete, or regress the
existing **174 approved application screens**"* (§15) — in a document dated **2026-09-25**, one day
*before* the V5 specification.

**This is genuine new evidence: 174 is a deliberate, owner-held figure appearing in two independent
documents, not a typo in one.** It still has **no corroboration in the repository** (91 routes /
89 release / 148 surfaces / 156 board / 169 with voice), so **CONF-01 is strengthened as a real
baseline claim while remaining unresolved as to unit and membership.** The owner decision is
unchanged: publish the list and state its unit.

## 12 · DECISION LEDGER — B1 · B2 · B3 · B4 · B5 · B7

| Blocker | Previous status | New evidence from the supplied design | What was resolved | What remains | Owner decision | Architecture decision | Design dependency | Implementation dependency |
|---|---|---|---|---|---|---|---|---|
| **B1 Audit** | PARTIALLY ADVANCED (14→7 open) | **8 audit-requiring action classes enumerated** (§5, §6, §12); severity language matches V5's enum; *"completed autonomous actions with audit trail"* | **A2 moves from undefined to partially enumerated** | A2 definition of "high-impact", A3 write path, A6 before/after, A11/A-NEW immutability, A12 retention, A13 read access, A14 visibility | **A2, A12, A13** | **A1, A3, A6, A-NEW** | audit surface frames | schema before Admin/Trust |
| **B2 Design authority** | UNRESOLVED | **an Admin *brief* located (authority UNCONFIRMED); no approved package; no Trust artifact; visual reference absent** | **partially informed** — IA intent, data domains, states, security principles, build sequence are now known | **the approved screen package**, the Fitonist reference, brand identity, all Trust artifacts | **CONF-D4, CONF-D5, CONF-D6** | — | **23 dependencies** | Admin, Trust, Guardian UI |
| **B3 Wearable arch** | PARTIALLY ADVANCED | **none** — design touches only integration telemetry | nothing | D-V1, D-V2, D-V3 | D-V1, D-V2 | D-V1, D-V3 | wearable UX | whole stack |
| **B4 Team semantics** | PARTIALLY ADVANCED | **none** — "team"/"team lead" absent; relationships appear only as a data domain | nothing | **D1 entirely** | **D1, D2** | — | — | **P0 fix; any team/PHI feature** |
| **B5 Wearable PHI** | PARTIALLY ADVANCED | **Admin arm = telemetry only, corroborated** (device count, sync health, ingestion issues) | **the Admin/Guardian arm** | coach active-only?; Partner scope; export; `content_manager`; Trust operator | **D-V4** | — | — | wearable authz |
| **B7 Vendor** | PARTIALLY ADVANCED | Wellness Partner adopted as terminology; **no vendor action, no mapping to `vendor`** | nothing | D2; `hosts_event_for()` narrowing | **D2** | — | — | partner APIs |

**Blockers resolved this mission: 0.** **B1 and B5 advanced; B2 partially informed; B3, B4, B7
unchanged.** **Blockers remaining: 6.** The count is not reduced, because no closure condition was
met — an inventoried brief is not an approved design package.

## 13 · UPDATED DEPENDENCY GRAPH

```
V5 SPECIFICATION  (governing)
        │
        ▼
DESIGN AUTHORITY  ◄── ✗ NOT ESTABLISHED
   ├─ Admin brief V1 ......... present, authority UNCONFIRMED, no frames  [CONF-D4]
   ├─ Fitonist visual ref .... ABSENT                                     [CONF-D5]
   ├─ Brand identity ......... NOT LOCKED                                 [CONF-D6]
   ├─ Approved screen pkg .... ABSENT — requested by the brief's own §16
   └─ Trust artifacts ........ ABSENT ENTIRELY
        │
        ▼
ARCHITECTURE   [D-D1 IA · CONF-D7 role matrix · CONF-D8 RLS-vs-views · A1/A3 · D-V1/V2/V3]
        │
        ▼
AUDIT  ◄── critical path; 8 action classes now enumerated, 7 decisions open
        │        (A2, A12, A13 owner · A1, A3, A6, A-NEW architecture)
        ▼
DATABASE  ── audit tables · incidents · observability · wearable · flags
        │
        ▼
API  [D5 transport · D-V1 wearable boundary]
        │
        ▼
SECURITY FOUNDATION  ◄── D1 only; INDEPENDENT of design; gates every PHI feature
        │
        ├────────────┬────────────┬─────────────┐
        ▼            ▼            ▼             ▼
      ADMIN      (TRUST?)    AI GUARDIAN    WEARABLE
   [designs]   [CONF-D2 —   [audit+observ.] [D-V1/V2/V3/V4]
               may not be
               a separate
                 area]
        │            │            │             │
        └────────────┴────────────┴─────────────┘
                        ▼
                     MOBILE  [D6 — V5 indicates a web/admin surface, so Admin may not be here]
                        ▼
                      QA  ── 19 items carried; B10/B11 gate evidence only
                        ▼
                   RELEASE  [CONF-03 SBOM · D-V6 · D14]
```

**Strict dependencies:** design → Admin/Trust/Guardian UI · audit → Admin audit, Trust, Guardian ·
D1 → Security Foundation → every PHI feature · D-V1 → wearable stack.
**Parallelizable:** **Security Foundation** (needs no design), monetization/6 K specs, CI gate repair
(QAT-1/D13), audit *architecture decisions*, wearable architecture decisions.
**Not on the implementation critical path:** B8, B10, B11.

## 14 · ADVERSARIAL DESIGN REVIEW

| # | Challenge | Finding |
|---|---|---|
| 1 | Does any screen expose more data than V5 permits? | **No over-exposure found.** Wearables are scoped to telemetry; §12 minimizes sensitive data. **But** PHI-bearing Users/Clients views are implied without a column model, and the enabling view pattern is **non-functional (NEW-5)** |
| 2 | Does any action bypass a defined role boundary? | **Not explicitly** — but **no role matrix exists** (CONF-D7), so boundaries cannot be checked. Recorded as unverifiable, not as clean |
| 3 | Does any Admin action lack audit requirements? | **Yes** — admin login/session not specified; and disable/override/export/delete are **not specified at all**, so their audit needs are undefined |
| 4 | Does Trust gain undocumented authority? | **Trust does not exist in either source.** No authority granted — and I did not create the area |
| 5 | Does AI Guardian gain undocumented authority? | **Bounded, not undocumented.** §12: *"AI agents do not inherit unrestricted admin authority"*; §5 separates observation/recommendation/autonomous/approved, matching L0–L3. **Emergency disablement is the highest-impact control and needs AG-03 verification** |
| 6 | Does a design imply an unsupported database structure? | **Yes — extensively.** Audit logs, incidents, observability/health metrics, analytics, Guardian telemetry: **none exists.** §13 step 8 anticipates this |
| 7 | Does a design imply a non-existent backend/API? | **Yes** — all 12 Overview groups and 15 data domains need read APIs; the NestJS service is thin (4 modules) and no Admin API exists |
| 8 | Does a design accidentally resolve an owner decision? | **Two near-misses, both refused.** It *corroborates* D6 (web command centre, §17) and **restates 174** (§15) — neither is treated as a resolution; both remain owner confirmations |
| 9 | Does a design create PHI exposure? | **Potentially** — Users/Clients Admin views over `user_profiles`. Mitigated in principle by §12 minimization; **unquantified because no column list exists** |
| 10 | Does a design create an RLS requirement? | **Yes — a significant one.** §12 requires Admin to respect existing authorization boundaries, which collides with the repo's `security_invoker=off` pattern (**CONF-D8**) |
| 11 | Does a design conflict with an existing QA finding? | **Yes — three.** NEW-5 (the view pattern it needs is broken), QAX-SEC-08 (team leadership surface is the P0), QAX-SEC-09 (partner activity rests on the full-row `hosts_event_for()` arm) |
| 12 | Does a design create a new incident/audit requirement? | **Yes** — 8 audit-requiring action classes and a full incident lifecycle with approval states |
| 13 | Does the design assume data the system does not possess? | **Yes, pervasively** — uptime, API/DB/auth health, job status, MRR/refund aggregates, DAU/WAU/retention, moderation queue, sync health, delivery failures, Guardian detections, audit logs. **§10's requirement that every metric have a defined source is currently unmeetable for most of them** |

**13 challenges, 11 material findings. None fixed.**

## 15 · FINAL PRE-AUTHORIZATION ASSESSMENT

| Metric | Before | After |
|---|---|---|
| Blockers | 6 | **6** |
| Blockers resolved this mission | — | **0** (B1, B5 advanced; B2 partially informed) |
| Owner decisions | 21 | **23** (+D-D1 Admin IA/Trust taxonomy, +CONF-D7 role matrix) |
| Architecture decisions | 11 + 1 | **12 + 1** (+CONF-D8 Admin RLS vs curated views) |
| Design dependencies | 21 | **23** (+ Fitonist reference, + brand identity package) |
| QA items carried | 19 | **19** — none closed |

### **NO — SPECIFIC INPUTS REMAIN**

**The system is NOT ready for the final V5 implementation authorization gate.**

The decisive reason is narrow and factual: **the supplied artifact is a design *brief*, not design
authority.** Its own §16 requests the approved package; its cited visual reference is absent; the
brand identity is explicitly not locked; and **no Trust artifact exists in any form.** Implementing
Admin from this document would require inventing every screen, state, component and permission it
describes but does not specify — which is the exact failure mode this gate exists to prevent.

**What this mission did add, concretely:** the Admin information architecture *intent*, 15 data
domains, 11 required screen states, 7 security-and-governance principles, a 15-step build sequence,
**8 enumerated audit-requiring action classes**, and **corroboration that Admin/Guardian wearable
access is telemetry-only**. That is real progress on B1 and B5 and on understanding B2 — it is not
closure of any blocker.

**Inputs required, in dependency order:**

1. **Confirm or reject** `12Circle_Admin_Control_Center_Dashboard_Build_Spec_V1.docx` as an
   authoritative *input* (it is not a package) — **CONF-D4**.
2. **Supply the approved Admin screen package**, the **Fitonist visual reference**, and the **brand
   identity package** — CONF-D4/D5/D6.
3. **Supply Trust artifacts, or rule that Trust is not a separate area** — **CONF-D2 / D-D1**.
4. **Reconcile the Admin IA** — 8 nav items vs 13 V5 domains, and place Exercise Review and
   Observability — D-D1 / CONF-D3.
5. **Define the Admin role matrix** — CONF-D7.
6. **Decide D1** (team semantics) — independent of all design work, and it unblocks the one
   workstream that needs no design.
7. **Decide D4 / A2 / A12 / A13** (audit) — now better informed by the 8 enumerated action classes.
8. **Decide D-V1 / D-V2 / D-V4** (wearable) and **D2** (vendor).

---

*Documentation-only. QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**; 1 P0 and 4 P1 open, none
closed or downgraded. No design was altered, reinterpreted, or invented. No owner decision was
taken. No code, schema, migration, RLS, CI or database change was made. **Implementation remains
unauthorized.***
