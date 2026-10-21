# V5 FINAL DESIGN AUTHORITY RECONCILIATION

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** DOCUMENTATION-ONLY governance mission. No implementation, no mutation.

> **IMPLEMENTATION REMAINS UNAUTHORIZED.**

---

## 1 · ADMIN AUTHORITY

### Source

`~/Downloads/12Circle_Admin_Control_Center_Dashboard_Build_Spec_V1.docx` · 2026-09-25 · 41,291 bytes ·
166 paragraphs · 18 sections · **read in full.**

### Authority determination

**The brief is authoritative as a PRODUCT-REQUIREMENTS and DESIGN-DIRECTION input. It is not a
design package, and it cannot serve as design authority for implementation.** This is not a
formality — the document says so itself in §16, which *requests* the approved package.

Its contents, separated as required:

#### A. EXPLICIT PRODUCT REQUIREMENTS — **definitively established**

| # | Requirement | §ref |
|---|---|---|
| A1 | Admin is an **operational control center, not an analytics page** | §1 |
| A2 | Top-level navigation: **Overview · Ecosystem · Users · Finance · Analytics · Security · AI Guardian · Operations** (8) | §2 |
| A3 | Overview answers *"What is happening across 12Circle right now?"* across **12 data groups** | §3 |
| A4 | A **persistent system status strip**, live, severity-aware, clickable, traceable | §4 |
| A5 | **AI Guardian panel — 10 elements**, incl. state (Active/Monitoring/Degraded/Disabled), detections with evidence **and confidence**, recommended actions, actions awaiting approval, **completed autonomous actions with audit trail**, **emergency disablement** | §5 |
| A6 | **5 operational layers**: Executive Overview · Ecosystem · Operations · AI Guardian · Security & Governance | §6 |
| A7 | **Clear distinction between observation, recommendation, autonomous action, and human-approved action** | §5 |
| A8 | **No hard-coded KPI values in production**; every metric has a defined **source, calculation, freshness expectation, and authorization boundary** | §10 |
| A9 | **15 Admin data domains** (incl. Audit logs, AI Guardian telemetry) | §11 |
| A10 | **7 security & governance principles** — role-based least privilege · sensitive data minimized · every high-impact admin action auditable · AI agents do not inherit unrestricted admin authority · production-changing actions require policy gates and human approval where applicable · **security controls remain independent of the AI Guardian** · dashboard data must respect the same authorization boundaries as the underlying system | §12 |
| A11 | **11 required screen states** incl. degraded, unauthorized, no-permission, offline, critical-incident, Guardian-approval-required | §14 |
| A12 | **Additive build rule** — must not alter, delete or regress *"the existing 174 approved application screens"*; any dependency needing a change to an existing screen must be identified, documented, approved and regression-tested | §15 |
| A13 | QA uses **deterministic, clearly-marked relational data** | §10 |
| A14 | Success criterion: an authorized administrator understands platform health, users, revenue, engagement, security, Guardian status, incidents and ecosystem activity **without navigating the consumer application** | §17 |

#### B. DESIGN REQUIREMENTS — **directional, not specified**

Dark premium command-centre base · large rounded cards · high-contrast typography · 12Circle purple
primary accent with controlled secondary data accents · restrained colour so status stays meaningful ·
consistent radius/spacing/icon weight/chart treatment/control sizing · **severity differentiation
must not rely on colour alone** · dark is the primary Admin reference (§7); 11 reference elements to
retain (§8); 12Circle terminology — **Coach · Client/Member · Wellness Partner · Community ·
Guardian · Ecosystem** (§9).

**These are directions, not specifications.** No frame, component spec, token value, breakpoint,
interaction spec or measurement exists.

#### C. IMPLEMENTATION REQUIREMENTS

A **15-step build sequence** (§13). Steps 7–11 are notable because they encode governance the
existing programme already enforces: *map every metric to an authoritative source* → **identify
schema/data gaps before implementation** → build against the existing repository architecture →
connect real QA data and existing QA identities → **validate role-based access and RLS**.

#### D. REFERENCES TO EXTERNAL DESIGN MATERIAL

| Reference | Status |
|---|---|
| *"the attached Fitonist dashboard reference"* (§1, §18) | **MISSING — searched exhaustively, not found** |
| *"the 12Circle logo/mark and approved brand assets once the final identity package is locked"* (§9) | **NOT LOCKED — the brief states this itself** |
| *"Approved screen package"* (§16) | **NOT SUPPLIED — the brief requests it** |

#### E. OPEN QUESTIONS the brief raises but does not answer

Which of the 15 data domains get dedicated surfaces vs Overview cards · whether "Operations" and
"Ecosystem" are surfaces or groupings · what "high-impact" means for auditing · whether light mode
is required (§7: *"only if the product design system requires it"*) · where Exercise Review and
Observability (both implemented) belong.

#### F. ASSUMPTIONS the brief makes that the system does not currently satisfy

That uptime, API/DB/auth health, job status, MRR/refunds, DAU/WAU/retention, moderation queue, sync
health, delivery failures, Guardian detections and **audit logs** are all available. **None of these
data sources exists.** The brief anticipates this in §13 step 8.

#### G. UNSPECIFIED CAPABILITIES

**Disable/deactivate user · delete · export · impersonation · administrative override · account
recovery · admin session/login auditing · role matrix beyond "authorized administrator" · light/dark
decision · responsive breakpoints.** Recorded as UNSPECIFIED — **not inferred into existence**.

### What still requires each missing input

| Missing input | Blocks |
|---|---|
| **Approved screen package** | every Admin screen, state, component, interaction, measurement |
| **Fitonist reference** | the visual system's stated foundation (§1/§18) |
| **Brand identity package** | final logo/mark, token values, chart identity (§9) |
| **Owner confirmation** | the brief's authority status; the 8-vs-13 IA reconciliation; the role matrix; the 7 unspecified capabilities |

## 2 · TRUST AUTHORITY

### Evidence, recorded without inference

| Source | Finding |
|---|---|
| **V5 specification** | the word **"Trust" never appears.** V5 places Guardian (§18–21), Security Guardian, incidents (Admin Incident Model) and audit inside **Admin/Guardian/observability** |
| **Admin brief** | the word **"Trust" never appears.** It places **Security** and **AI Guardian** as top-level *Admin* nav items (§2), and *"Security & Governance"* — auth, authorization/RLS, admin actions, sensitive-data access, **audit logs**, security events — as an *Admin operational layer* (§6) |
| **Repository** | **0** implementation files for trust/guardian/incident; **0** mentions of Trust/AI Guardian/Incidents across 7 design documents |
| **Exhaustive disk search** | **no Trust artifact of any kind** in `~/Documents`, `~/Downloads`, `~/Desktop`, the repo, or `helix-design-references` |
| **Prior governance docs** | "Trust", "Trust Home", "Reviews", "Policies" originate in **mission briefs only** |

**Determination on the evidence: of the four candidate readings, (B) and (C) are supported and (A) is
not.** Both authoritative sources structure these capabilities **within Admin** (B), and V5's V4
amendment treats governance as a **cross-cutting control layer** rather than a UI module (C).
**(A) — a separate product/module — has no support in either source.** **(D)** is contradicted: the
*capabilities* (Security, Incidents, Audit, Guardian) are definitely required; only the *"Trust"
container* is unevidenced.

> **EXACT OWNER DECISION REQUIRED (D-D1):**
> *"Is Trust a separate product surface, or are its capabilities implemented within the Admin Control
> Center? Neither V5 nor the Admin build spec uses the word 'Trust'; both place Security, Incidents,
> Audit and AI Guardian inside Admin. If Trust is intended as a distinct surface, it requires its own
> specification and design package, because none exists."*

**Not answered here.** The capabilities are required regardless; only their container is undecided.

## 3 · ADMIN SURFACE INVENTORY

Built **only** from authoritative sources — V5 and the Admin brief. The previous 16-surface list is
**not** reused. `Auth?` = is the surface itself authoritatively established.

| Surface | Source | Source type | Auth? | Design status | V5 req | Data req | Security req | Audit req | Open decision |
|---|---|---|---|---|---|---|---|---|---|
| **Overview** | brief §2/§3 | product req | **YES** | **NO PACKAGE** | YES (AD-01) | 12 groups — **most sources absent** | §12 | NOT SPECIFIED | metric→source mapping |
| **Ecosystem** | brief §2/§6 | product req | **YES (brief only — absent from V5)** | NO PACKAGE | **NOT in V5** | 9 sub-domains | §12 | NOT SPECIFIED | surface or grouping? |
| **Users** | brief §2/§11 · V5 AD-01 | both | **YES** | NO PACKAGE | YES | `admin_recent_users()` only | least privilege | **YES (§12)** | **role matrix; PHI columns** |
| **Finance** | brief §2/§3 | product req | **YES** | NO PACKAGE | YES (V5 "payments") | Stripe; **6 open K specs** | §12 | NOT SPECIFIED | reconciliation scope |
| **Analytics** | brief §2/§3 | product req | **YES** | NO PACKAGE | YES | **absent** | §12 | NOT SPECIFIED | — |
| **Security** | brief §2/§6 · V5 | both | **YES** | NO PACKAGE | YES | **no posture store** | §12 | **YES** | Trust container (D-D1) |
| **AI Guardian** | brief §2/§5 · V5 §18–21 | both — **most detailed** | **YES** | NO PACKAGE | YES (8 domains, L0–L3) | **absent** | §12 + V4 | **YES** | autonomy allowlist |
| **Operations** | brief §2/§6 | product req | **YES** | NO PACKAGE | PARTIAL | incidents/jobs/integrations/notifications/failures/performance/deployments — **absent** | §12 | **YES (incidents)** | surface or grouping? |
| **Audit Logs** | brief §11 · V5 | both | **YES as a data domain** | NO PACKAGE | YES | **no table** | §12 | **it is the requirement** | **A2/A12/A13** |
| **Incidents** | brief §5/§6 · V5 AG-04 | both | **YES** | NO PACKAGE | YES — **11 fields + severity enum** | **no table** | §12 | **YES** | A1 |
| **Wearables (Admin)** | brief §3/§11 · V5 WI-15 | both | **YES** | NO PACKAGE | YES | `user_integrations` only | **telemetry only** | YES | — |
| *Exercise Review* | **repository only** | implementation | **NO — absent from both sources** | implemented | YES | **exists** (migration 050) | `is_admin` | NOT SPECIFIED | **CONF-D3: keep, deprecate, or fold?** |
| *Observability* | **repository only** | implementation | **NO — absent from both sources** | implemented | YES (SQ-10) | **0 DB tables** | `is_admin` | NOT SPECIFIED | **CONF-D3** |

**11 authoritatively-established surfaces + 2 implemented-but-unestablished. 0 have an approved
design package.** Surfaces previously listed that are **not** authoritatively established and are
therefore **excluded**: Coaches, Clients, Settings/Configuration, Trust Home, Reviews, Policies.

## 4 · 174-SCREEN AUTHORITY STATUS

### **CONF-01 = OWNER CONFIRMATION REQUIRED**

**Does the supplied design authority contain a canonical screen inventory? No.** Searched: the Admin
brief (references the figure in §15, lists no screens), `docs/design/` (1 file — a consumer UI
audit), `helix-design-references/12circle fitness/` (consumer app board, 19 files), and all
`.dc.html` board exports found on disk (consumer mobile app; community portal). **None enumerates
174 screens.**

| Count | Unit | Authority |
|---|---|---|
| **91** | `GoRoute(` entries — verified live at HEAD | Repository (implementation) |
| **89** | routes in a release build | Repository |
| **148** | surfaces of all kinds (routes + modals/sheets/state variants) | Repository |
| **156** | Claude Design board screens, 2026-09-24 | Design board |
| **169** | board screens **including voice variants** | Design board |
| **174** | *"approved application screens"* — **V5 GV-03 and Admin brief §15** | **Owner assertion — uncorroborated by any inventory** |

**174 appears in two independent owner documents one day apart, so it is a deliberate figure rather
than a transcription error.** It remains unmatched by every inventory that exists. **It is not
reinterpreted here, and neither 169 nor 174 is declared authoritative.**

> **EXACT CONFIRMATION REQUIRED:**
> *"Please provide the canonical approved-screen inventory/version that defines the 174 screens
> referenced by V5 §GV-03 and the Admin build spec §15 — as a named, versioned artefact — and state
> which unit it counts (routes, surfaces, board frames, or board frames including voice variants).
> Until it exists, the additive build rule (§15 / GV-03) cannot be enforced or regression-verified,
> and SQ-30 selective migration cannot be scoped."*

**Also relevant, and a lead rather than a conclusion:** `od38` in `FINAL_SCREEN_INVENTORY.json`
records a reproducible package format — *"12Circle Fitness - Complete Board.dc.html (110 .phone
frames)"*, 110 reference images regenerated by `capture-references.mjs`, **held in a session
scratchpad and "not copied into the repo."** If the 174 list exists anywhere, that pipeline is the
most likely place to regenerate it from.

## 5 · BRAND / VISUAL AUTHORITY

### **REFERENCE DESIGN = MISSING**

**The Fitonist dashboard reference was searched for exhaustively across `~/Documents`, `~/Downloads`
and `~/Desktop` and does not exist on this machine.** It is not substituted with anything.

| Element | Supplied? | Evidence |
|---|---|---|
| **Fitonist reference** | **MISSING** | no file matching `*fitonist*` anywhere |
| Logo | **PARTIAL** | `apps/mobile/assets/images/12circle-logo.png` exists; brief §9 says the identity package is **not locked** |
| Typography | **NOT SUPPLIED** | direction only — *"high-contrast white/light typography"* |
| Colour tokens | **NOT SUPPLIED** | direction only — *"12Circle purple as a primary brand accent"*; **no token values** |
| Spacing | **NOT SUPPLIED** | *"consistent spacing"*; no scale |
| Components | **NOT SUPPLIED** | 11 elements *named* (§8), none specified |
| Navigation | **PARTIAL** | 8 items named; no interaction or responsive spec |
| Iconography | **NOT SUPPLIED** | *"consistent icon weight"* |
| States | **ENUMERATED, NOT DESIGNED** | 11 states listed (§14); no frames |
| Accessibility | **PRINCIPLE ONLY** | *"must support accessibility and severity differentiation without relying on colour alone"* (§7) |
| Responsive behaviour | **NOT SUPPLIED** | requested in the handoff list (§16) |
| Existing product theme | **EXISTS but is mobile/consumer** | `app_theme.dart`, `twelve_circle_theme.dart`; **no shared design-system dependency** |

**Candidate reference imagery exists but is unidentified — reported as a lead, not a conclusion:**
`~/Desktop/projects/12CIRCLE/screens/` holds `12-circle-dashboard-dark.webp`,
`12-circle-dashboard-white.webp`, `dashboard-v3.png`, `dashboardv2.webp`, `gym-dashboard.webp` and
related video. A dark dashboard image is consistent with the brief's description, **but none is
named "Fitonist" and none is identified as the cited reference**, so I cannot and do not treat any of
them as the design basis. **Owner confirmation required (CONF-D5).**

## 6 · ADMIN SECURITY RECONCILIATION

Every privileged capability the brief **explicitly describes**:

| Action | Actor | Resource | Authorization | Audit | Security impact | Data impact | V5 support | Implementation dependency |
|---|---|---|---|---|---|---|---|---|
| **Emergency Guardian disablement** | admin | AI Guardian | **UNSPECIFIED** — control exists (§5); no permission stated | **REQUIRED** (§12 high-impact) | **highest in the brief.** §12 requires security controls stay independent of Guardian; V5 AG-03 the same | none direct | **YES** (V5 §20) | Guardian + audit; **AG-03 verification** |
| **Approve a Guardian action** | admin | pending action | **UNSPECIFIED** | **REQUIRED** — incident "approval status" | authorizes an autonomous production action | varies | **YES** (V5 L1/L3) | incident schema |
| **Guardian autonomous action (L2)** | agent | production state | **allowlist + reversibility**; *"AI agents do not inherit unrestricted admin authority"* (§12) | **REQUIRED** — *"completed autonomous actions with audit trail"* (§5) | an over-broad allowlist creates an unaudited production actor | varies | **YES** (V4) | agent trail; **D-V5 agent identity** |
| **View sensitive data** | admin | member records | `is_admin()` + *"sensitive data is minimized and exposed only when required"* (§12) | **REQUIRED** — §6 names *"sensitive-data access"* | broad PHI read | **PHI** | YES | **column-limited views — NEW-5 blocks the pattern** |
| **View audit logs** | admin | audit records | **UNSPECIFIED — A13 open**; admins are the audited party | read is itself auditable | self-exculpatory reads | evidence | YES | audit schema |
| **Incident management** | admin/agent | incidents | **UNSPECIFIED** | **REQUIRED** | evidence tampering | evidence | **YES** — 11 fields + enum | incident schema |
| **Status drill-down** | admin | operational detail | `is_admin()` | NOT SPECIFIED | low | telemetry | YES | observability store |
| **Role management** | admin | `user_profiles.role` | **implied by domain (§11 "Users & identities"), not specified** | **REQUIRED** (§12) — **today `admin_set_user_role()` writes NONE** | privilege escalation | privilege | YES | audit write path |
| **User administration** | admin | user accounts | **UNSPECIFIED** | REQUIRED | — | — | PARTIAL | — |
| Disable / deactivate | — | — | **UNSPECIFIED** | UNSPECIFIED | — | — | **NOT SPECIFIED** | — |
| Delete | — | — | **UNSPECIFIED** | UNSPECIFIED | irreversible → V5 L3 human-required | — | **NOT SPECIFIED** | — |
| Export | — | — | **UNSPECIFIED** | UNSPECIFIED | bulk PHI egress | **PHI** | **NOT SPECIFIED** | — |
| Impersonation | — | — | **NOT PRESENT in the brief** | — | — | — | **NOT SPECIFIED** | **do not assume** |
| Administrative override | — | — | **NOT PRESENT** | — | — | — | **NOT SPECIFIED** | — |
| Account recovery | — | — | **NOT PRESENT** | — | — | — | **NOT SPECIFIED** | — |

**9 capabilities described · 6 UNSPECIFIED or absent.** No behaviour was invented. Note the pattern:
**the brief consistently states that high-impact actions must be audited, while specifying no
authorization model for any of them** — the role matrix gap (CONF-D7) is the single largest security
specification gap in the Admin surface.

## 7 · D1 RECONCILIATION — TEAM SEMANTICS

D1 is independent of the design package, so it was reconciled on its own evidence.

| Term | V5 | Admin brief | Repository (live catalog) |
|---|---|---|---|
| "team" | **absent** | **absent** | `coach_team_members` table |
| "team lead" | **absent** | **absent** | **not a role** — emergent from a `coach_team_members` row via `is_team_lead_of()` |
| coach | **Trainer/Coach** persona | Coach persona; *"Coach/client relationships"* data domain | `role='coach'`, **self-assertable at signup** |
| client / member | **Client/Member** | Clients/Members | `role='client'`, self-assertable |
| Wellness Partner | **Wellness Partner** (5 mentions) | Wellness Partners (§3, §9) | **`vendor`** — V5 and the brief **never use this word**; 0 users |
| client membership | — | data domain only | `coach_client_relationships.status` — status-bearing, `WITH CHECK`, `trg_relationship_integrity` |
| relationship semantics | ecosystem contract (SQ-02/03) | **display only**, no actions | **two incompatible idioms** |

### Determination: **neither V5 nor the repository answers D1**

V5 supplies **no team model at all** — it has three personas and no team concept. The brief adds
nothing: "team" and "team lead" do not appear, and relationships appear only as a data domain to
display. The repository supplies a *mechanism* without semantics: `coach_team_members` has **no
status column, no `WITH CHECK`, 0 triggers, 0 check constraints and no role check**
(`has_role_check = false`), while `coach_client_relationships` — the other relationship model — has
all of them.

**The semantic defect, stated as an observation:** *membership is conflated with authority, and
authority has no lifecycle in `coach_team_members`.* Two SECURITY DEFINER helpers
(`is_team_lead_of()`, `may_notify()`) consume that table as an authorization fact.

| Finding | Dependency on D1 |
|---|---|
| **QAX-SEC-08** (P0) | a self-assertable membership row yields a **full `user_profiles` PHI read** |
| **F-03b** (P1) | `may_notify()` trusts the same table at any status |
| **SEC-PHI-9** (P1) | same class in the *other* relationship model — coach authority outliving `status` |
| **QAX-SEC-09** (P1) | vendor authority derives from event ownership, and `vendor` is self-assertable |

> **EXACT OWNER DECISION (D1):**
> *"Define what a 'team' is in 12Circle and who may create a `coach_team_members` row. Specifically:
> (i) may a coach add a member unilaterally, or must the member consent? (ii) does membership carry
> a status lifecycle (pending/active/revoked) as `coach_client_relationships` does? (iii) should
> being a team lead grant any read of a member's profile — and if so, which columns, given the row
> currently grants PAR-Q and all health data?*
> *Consequence of delay: the P0 (QAX-SEC-08) and F-03b both remain open, and one change closes both.
> A model exists from the Cloud workstream — lead may not insert (`with check (false)`), member may
> join — but it is a model, not an approved policy (OD-14 / OD-QAX-9)."*

**Not answered here. No policy was changed and no remediation performed.**

## 8 · AUDIT RECONCILIATION (B1)

V5's three record categories are kept **separate**; **no additional mandatory record type is
invented**.

| Privileged action | Audit required | Event type | Actor | Target | Action | Result | Timestamp | Trace/correlation | Retention | Read access |
|---|---|---|---|---|---|---|---|---|---|---|
| Role change | **YES** | **audit event** | admin | user | role change | old→new | required | required (V5 §17) | **OWNER (A12)** | **OPEN (A13)** |
| Sensitive-data / PHI view | **YES** (§6) | **audit event** | admin | member record | read | fields accessed | required | required | OWNER | OPEN |
| Audit-log read | **YES** | **audit event** | admin | audit records | read | — | required | required | OWNER | **OPEN — admins are the audited party** |
| Guardian autonomous action | **YES** (§5, V4 §5) | **agent action trail** (7 fields) | **agent identity — D-V5** | resource | action | result/error | required | required | **V5 defers** | OPEN |
| Guardian approval | **YES** | **incident record** ("approval status") | admin | incident | approve | — | required | required | OWNER | OPEN |
| **Emergency Guardian disablement** | **YES** | **audit event + incident** | admin | Guardian | disable | — | required | required | OWNER | OPEN |
| Incident state change | **YES** | **incident record** (11 fields + enum) | admin/agent | incident | transition | resolution | required | required | OWNER | OPEN |
| Security event detection | **YES** | **incident record** | agent | resource | detect | severity | required | required | OWNER | OPEN |
| Policy / config change | **YES** (§12) | audit event | admin | config | change | old→new | required | required | OWNER | OPEN |
| Control verification | **YES** (V5 §3) | **control evidence** (7 fields) | owner/agent | control | verify | result | date/version | — | — | — |
| Admin login / session | **NOT SPECIFIED** | — | — | — | — | — | — | — | — | — |

**B1 status: 10 audit-requiring action classes now enumerated from authoritative sources** (up from
8 last mission, +audit-log read and +control verification). **7 decisions remain open:** A2
(definition of "high-impact"/"material"), A3 (write path), A6 (before/after state), **A11/A-NEW**,
A12 (retention — **V5 explicitly defers**), A13 (read access), A14 (visibility).

**Immutability:** **NOT a V5 requirement and NOT a brief requirement.** Zero occurrences of
immutable/append-only/tamper in either document. It remains **ARCHITECTURE DECISION (A-NEW)**.

## 9 · CONFLICT REGISTER — evidence-backed only

| ID | Source A | Source B | Conflict | Why it matters | Decision required |
|---|---|---|---|---|---|
| **CONF-01** | V5 GV-03 + brief §15 (**174**) | repo: 91 / 89 / 148; board 156 / 169 | no inventory matches 174 | the additive build rule cannot be enforced or regression-verified | **OWNER — §4** |
| **CONF-D1** | brief §2 (**8 nav items**) | V5 SQ-16 (**13 Admin domains**) | roles/database/releases have no nav home; Ecosystem/Operations have no V5 counterpart | IA drives routing, permissions and the audit surface | **OWNER (D-D1)** |
| **CONF-D2** | V5 (**no "Trust"**) | brief (**no "Trust"**); mission briefs (Trust as an area) | Trust container unevidenced while its capabilities are required | determines whether a whole product area exists | **OWNER — §2** |
| **CONF-D3** | repository (Exercise Review, Observability **implemented**) | brief §2 IA (**both absent**) | two working Admin surfaces are outside the authoritative IA | risk of orphaning or duplicating them | **OWNER** |
| **CONF-D4** | brief §16 (**requests** the approved package) | mission framing (brief as design authority) | a brief cannot serve as design authority | **B2 cannot close** | **OWNER** |
| **CONF-D5** | brief §1/§18 (*"attached Fitonist reference"*) | disk: **not found**; unidentified dashboard imagery on Desktop | the stated visual foundation is absent | visual system unspecifiable | **OWNER** |
| **CONF-D6** | brief §9 (*"once the final identity package is locked"*) | no locked package | brand not final | token values, chart identity blocked | **OWNER** |
| **CONF-D7** | brief §12 (role-based least privilege) | brief: **no role matrix**; repo has 5 roles incl. unserved `content_manager` | every privileged action lacks a stated permission | **largest security specification gap** | **OWNER** |
| **CONF-D8** | brief §12 (*"respect the same authorization boundaries"*) | repo: `public_profiles` / `conversation_participant_profiles` deliberately bypass RLS (`security_invoker=off`), documented sound by SEC-G4 | Admin needs broad cross-user reads | caller-RLS + new admin policies, **or** curated bypassing views | **ARCHITECTURE** |
| **CONF-D9** | brief §10 (every metric has a defined source) | repo: no observability/audit/analytics stores | **most Overview metrics have no possible source today** | Overview is unbuildable as specified | **ARCHITECTURE** |

**10 conflicts. None resolved silently.**

## 10 · SKILLS-AGENT DEPENDENCY UPDATES (13 prepared · not executed)

| Workstream | Required design input | Required V5 input | Required architecture input | Blocking decisions | Allowed mutations | Forbidden | Test requirements | Handoff evidence |
|---|---|---|---|---|---|---|---|---|
| **Admin** | **approved screen package (ABSENT)** · Fitonist ref · brand tokens · 11 state frames | AD-01, SQ-15/16, brief A1–A14 | IA (D-D1) · role matrix (CONF-D7) · data-access model (CONF-D8) | **CONF-D4/D5/D6/D7, D-D1, D5, D6** | admin surface files only | migrations, RLS | permission + **audit-emission** tests | every privileged action emits its record |
| **Trust / Governance** | **none exists** | **none — V5 has no Trust** | **container decision (D-D1)** | **CONF-D2 — may not be a surface at all** | none until decided | everything | — | **CANNOT START** |
| **Design** | Fitonist ref · brand package | GV-04, SQ-07/09, brief §16 | — | CONF-D5, CONF-D6, CONF-01 | design artifacts, `docs/**` | any code | — | **versioned package committed to the repo** |
| **Security** | — | §12 principles, V4 controls | trust boundaries · agent least privilege | **D1**, D2, D-V4, D-V5 | `**/test/**`, `docs/**` | **product code, policies** | live deny **+ live legitimate-path** proof; mutation tests | per-control SA-03 evidence |
| **Database** | metric→source map (§10) | 3 record field-sets; 15 data domains | **A1, A3, A6, A-NEW** | **D4, A2, A12, A13** | `supabase/migrations/**` (132+) | app code | policy mutation tests; **live catalog** verification | catalog-verified migration |
| **API** | — | AD-01, WI-11 | **D5, D-V1** | D5, D-V1 | `apps/api/**`, `supabase/functions/**` | migrations, mobile | contract tests | versioned contracts |
| **QA** | approved package (for design QA) | SQ-08/13/39 | — | B10, B11 for full evidence | `**/test/**`, `docs/**` | product code | all 5 tiers | **executed** evidence, never inferred |

**Unchanged constraint:** no Skills Agent may redefine V5 or an approved design decision.

## 11 · FINAL READINESS STATUS

| Blocker | Status after this mission |
|---|---|
| **B1 Audit** | **ADVANCED** — 10 action classes enumerated; **7 decisions remain** (A2, A3, A6, A-NEW, A12, A13, A14) |
| **B2 Design authority** | **OPEN** — brief classified A–G and confirmed an *input*; **approved package NOT SUPPLIED** (searched exhaustively); Fitonist **MISSING**; brand **NOT LOCKED**; **no Trust artifact** |
| **B3 Wearable** | **OPEN** — unchanged; the brief touches only integration telemetry |
| **B4 Team semantics** | **OPEN** — **neither V5, the brief, nor the repository answers D1**; exact decision formulated (§7) |
| **B5 Wearable PHI** | **ADVANCED** — Admin/Guardian arm evidenced as **telemetry-only** by two sources; coach-active-only, Partner scope, export, `content_manager` remain open (D-V4) |
| **B7 Vendor** | **OPEN** — brief adopts "Wellness Partner" terminology, grants no capability, never maps to `vendor` |

| Metric | Before | After |
|---|---|---|
| Blockers resolved | — | **0** |
| Blockers remaining | 6 | **6** |
| Owner decisions | 23 | **23** |
| Architecture decisions | 12 + 1 | **13** (CONF-D9 added; A-NEW retained) |
| Design dependencies | 23 | **23** |
| QA items carried | 19 | **19 — none closed** |

### **NOT READY — SPECIFIC INPUTS REMAIN**

**No blocker closed, and the count was not reduced.** What this mission produced is *authority
clarity* rather than authority itself: the Admin brief is now precisely classified (14 established
product requirements, 7 unspecified capabilities, 3 missing external inputs), the Trust question is
reduced to a single binary owner decision with the evidence laid out, the 174 confirmation is
formulated exactly, and D1 is proven unanswerable from any existing source.

**Two findings materially narrow the remaining work:**

1. **Trust may not be a product area at all.** Neither authoritative source uses the word, and both
   place its capabilities inside Admin. If the owner confirms (B), the "Trust" build surface
   disappears and its capabilities become Admin sections — removing an entire phase.
2. **D1 is fully independent of every design input.** It can be decided today, and doing so unblocks
   the Security Foundation workstream — the one workstream that needs no design at all.

**Inputs required, in dependency order:** (1) the approved Admin screen package; (2) the Fitonist
reference; (3) the brand identity package; (4) **D-D1** — Trust container + Admin IA; (5)
**CONF-D7** — the Admin role matrix; (6) **CONF-01** — the canonical 174 inventory; (7) **D1**;
(8) **D4 / A2 / A12 / A13**; (9) **D-V1 / D-V2 / D-V4** and **D2**.

---

*Documentation-only. QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**; 1 P0 and 4 P1 open, none
closed or downgraded. No design was altered, substituted, reinterpreted or invented; the missing
Fitonist reference was not replaced with another design system. No owner decision was taken. No
code, schema, migration, RLS, CI or database change was made. **Implementation remains
unauthorized.***
