# V5 DECISION RESOLUTION

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** DOCUMENTATION-ONLY. No implementation, no remediation, no mutation.

> **IMPLEMENTATION REMAINS UNAUTHORIZED.** This mission prepares the final authorization gate.

---

## 1 · EXECUTIVE SUMMARY

### Outcome

| | |
|---|---|
| Blockers before | **11** |
| **Fully or substantially resolved** | **5** — B6, B8, B9, B10, B11 |
| **Partially advanced** (core decision remains) | **5** — B1, B3, B4, B5, B7 |
| **Unresolved** | **1** — B2 (Admin/Trust design authority) |
| **Remaining blocking for the final gate** | **6** |
| Owner decisions | 22 → **21** (3 downgraded to confirmation-only) |
| Architecture decisions | 11 → **11**, plus audit decisions narrowed **14 → 7** |
| Design dependencies | **21** named surfaces |
| QA items carried | **19** |

### What V5 itself resolved, read from source rather than inferred

This mission's main advance is that **V5 specifies more than the earlier gates credited it with**:

1. **V5 supplies three explicit record field-sets.** Not one generic audit schema — *three distinct
   record types*, each with its own enumerated fields (§4). That answers 7 of the 14 audit
   decisions and reshapes A1: V5 implies **at least three record types**, not a single table.
2. **V5 names a "web/admin surface" distinct from the "mobile client" — three times.** B9/D6 moves
   from *unspecified* to *V5-indicated* (§12).
3. **V5 explicitly authorizes coach and client/member access to wearable intelligence, and gives
   Admin/Guardian "telemetry"** — a narrower category it deliberately distinguishes (§8).
4. **V5 explicitly defers retention** — *"subject to privacy and retention controls"* — so the
   absence of a retention rule is a **deliberate deferral**, not an omission to be filled.

### A correction to my own prior gate

**The readiness gate's decision A11 presented audit immutability as a V5 requirement. It is not.**
V5 contains **zero** occurrences of "immutable", "append-only" or "tamper". It requires
*auditability* and that *"agent findings must be traceable to evidence."* Immutability is a
**security principle I introduced**, and it is recorded here as an **architecture decision**, not a
V5 requirement. The distinction matters: presenting my own inference as the spec's demand is
exactly the failure this governance chain exists to prevent.

### What cannot be resolved here

**B2 — the Admin and Trust designs are not in this repository**, and this mission is
documentation-only. I can inventory what exists and name each absent surface as a design
dependency; I cannot resolve it, and I did not invent any screen. **21 surfaces are design
dependencies.**

## 2 · AUTHORITATIVE STATE (re-verified, not recalled)

| | Verified |
|---|---|
| HEAD | `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f` |
| Branch | `reconcile/12circle-integrated` · 0 modified · 0 staged |
| QA | **90.0% — QA COMPLETE WITH OPEN FINDINGS** · 18.90 / 21 |
| Readiness | **NOT READY FOR CONTROLLED V5 IMPLEMENTATION** |
| Open findings | 1 P0 (QAX-SEC-08) · 4 P1 (F-03b, QAX-SEC-09, SEC-PHI-9/10, SEC-AI-1) — **none closed here** |
| Governance docs | QA completion 576 · transition 467 · impact 690 · readiness 527 lines |

## 3 · DECISION LEDGER

`O` = owner · `A` = architecture · `Def?` = does the source already supply a default.

| ID | Cat | Question | Source | Current evidence | O | A | Def? | Depends | Downstream | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| CONF-01 | Governance | Canonical approved-screen list | V5 GV-03 | 5 distinct counts characterized (§11) | ✓ | | NO | — | SQ-30 migration; "protected" enforcement | **ANALYSIS COMPLETE; list required** |
| CONF-02 | Governance | Confirm document name/version | title vs filename | additive model explicit (V3 §14, V4 §9, V5 §11) | ✓ | | — | — | release traceability (SA-01/12) | **CONFIRMATION ONLY** |
| CONF-03 | Supply chain | Authorize SBOM tooling, or govern absence | V5 SA-04 | absent; release-time only | ✓ | | NO | — | release gate | **OPEN — release-time** |
| CONF-06 | Security | Harden the partner role before partner APIs? | V5 WI-18 | `vendor` self-assertable; QAX-SEC-09 open | ✓ | | NO | D2 | partner APIs | **OPEN** |
| CONF-08 | Design | Supply or commission Admin/Trust designs | V5 SQ-09 | **0 mentions in 7 design docs** | ✓ | | NO | — | **blocks Admin + Trust** | **UNRESOLVED** |
| D1 | Security | Team semantics; who may create a membership | QA OD-14/OD-QAX-9 | no `WITH CHECK`, no status, no trigger, **no role check** | ✓ | | NO | — | **P0 + F-03b fix** | **OPEN** |
| D2 | Security | Keep `coach`/`vendor` self-assertable? | QA | INSERT allows `client`/`coach`/`vendor` | ✓ | | NO | D1 | CONF-06 | **OPEN** |
| D3 | Security | Uniform `status='active'` predicate | QA | 2 of 5 policies omit it | | ✓ | **YES — option (b)** | — | SEC-PHI-9/10 | **OPEN, default documented** |
| **D4** | Data | Audit model | V5 AG-04/AD-03/AS-05/SA-03 | **V5 supplies 3 field-sets** (§4) | ✓ | ✓ | PARTIAL | — | **Trust, Admin audit, Guardian** | **PARTIALLY RESOLVED — 7 of 14 open** |
| D5 | API | Admin via API or direct Supabase | V5 AD-01 | API thin; mobile direct | ✓ | | NO | D6 | API workstream | **OPEN** |
| **D6** | Admin | Admin/Trust in-app or separate surface | V5 SA-02/SA-08 | **V5 names "web/admin surface" vs "mobile client" 3×** | ✓ | | **YES — V5-indicated: web** | — | mobile scope, D5 | **SUBSTANTIALLY RESOLVED — confirm** |
| D7 | Admin | Users/Coaches/Clients: modules or views | V5 AD-01 | only `admin_recent_users()` | ✓ | | NO | D4 | Admin data model | **OPEN** |
| D8 | Admin | `content_manager` admin surface | repo | 5 policies recognise it; 1 user; no screen | ✓ | | NO | D7 | Admin scope | **OPEN** |
| D9 | AI | Server-side AI entitlement | V5 V4 ctrl | **K-03: 0 checks in 3 sold fns** | | ✓ | **YES — V4 requires it** | — | monetization Guardian | **RESOLVED IN PRINCIPLE** |
| D10 | AI | AI disclosure posture | SEC-AI-1 | matrix complete | ✓ | | NO | — | privacy alignment | **OPEN** |
| D11 | Trust | Trust scope | V5 | **V5 names 4 areas** | ✓ | | **YES** | — | build scope | **RESOLVED — build open** |
| D12 | Audit | Audit read / immutability / retention | V5 §34, V4 §5 | **V5 defers retention; silent on immutability** | ✓ | ✓ | NO | D4 | A11–A14 | **OPEN** |
| D13 | CI/CD | `static-guards` fail-late | QA NEW-8 | 6 gates blinded, **all 6 pass locally** | | ✓ | **YES — reorder or continue-on-error** | QAT-1 | CI reliability | **OPEN, options documented** |
| D14 | CI/CD | Branch protection | V5 SA-11 | **unverified** — GitHub unreachable | | ✓ | NO | B11 | release integrity | **OPEN** |
| D15 | Testing | Derive guard population from live catalog | QA | 37 live vs 33 source | | ✓ | **YES** | — | guard accuracy | **OPEN, default documented** |
| D16 | Design | Extract shared design system now? | V5 SQ-05 | no shared dependency; **V3's standalone platform may be the "second product"** | ✓ | | NO | D-V1 | component governance | **OPEN** |
| D17 | Security | Fix `SEC_PHI_1` before applying | QA NEW-5 | `security_invoker = on` returns `200 []` | | ✓ | **YES — off + barrier + predicate** | D1 | Admin views | **OPEN, fix documented** |
| D-V1 | API/Arch | Wearable platform location/boundary | V3 §5 | mobile direct-to-Supabase; API thin | ✓ | ✓ | NO | — | **whole wearable stack** | **OPEN** |
| D-V2 | Data | Wearable store: shared or own | V3 §4 | — | ✓ | ✓ | NO | D-V1 | schema | **OPEN** |
| D-V3 | Data | Canonical observation + provenance contract | V3 §8.3 | **V5 supplies provenance fields** (§8) | ✓ | ✓ | PARTIAL | D-V2 | ingestion | **PARTIALLY RESOLVED** |
| **D-V4** | Security | Who may read wearable PHI | V3 §3, §10 | **V5 authorizes coach + client/member; Admin/Guardian = telemetry** | ✓ | | PARTIAL | D1, D3 | wearable authz | **PARTIALLY RESOLVED** |
| D-V5 | Security | Agent identity for the audit trail | V4 §5 | V5 says "agent identity" without defining it | ✓ | ✓ | PARTIAL | D4 | agent attribution | **OPEN** |
| D-V6 | CI/CD | SBOM toolchain and location | V5 SA-04 | **CycloneDX named by V5** | ✓ | | **YES — format is CycloneDX** | CONF-03 | release chain | **OPEN, format fixed** |
| D-V7 | Governance | Baseline mechanics once CONF-01 answered | V5 GV-03 | — | ✓ | | NO | CONF-01 | protection enforcement | **OPEN** |
| **A-NEW** | Audit | **Immutability of audit records** | **NOT V5 — my own prior inference** | V5: 0 hits for immutable/append-only/tamper | | ✓ | NO | D4 | audit integrity | **NEW ARCHITECTURE DECISION — reclassified** |

**Decisions are listed separately even where related; none was collapsed.**

## 4 · BLOCKER B1 — AUDIT ARCHITECTURE · **PARTIALLY RESOLVED**

### What V5 specifies — quoted, not inferred

V5 defines **three distinct record types**, each with enumerated fields. This is the single most
useful finding of this mission, because it means the audit model is **partly specified already**.

**(a) Incident record** — V2 Admin Incident Model:
> *"Each incident records what happened, when, scope, evidence, severity, suspected cause,
> recommended action, action taken, actor/agent identity, approval status, and resolution."*

**11 fields.** Severity enum also specified: **Critical · High · Warning · Informational**.

**(b) Agent action audit trail** — V4 §5:
> *"For material agentic actions, retain sufficient evidence to reconstruct agent identity, skill,
> tool/API, relevant input/context, authorization decision, action, and result/error, subject to
> privacy and retention controls."*

**7 fields**, plus an explicit deferral of retention.

**(c) Security control evidence** — V5 §3:
> *"…retain the requirement, implementation location, automated/manual test evidence, result,
> date/version, exception or risk decision, and responsible owner."*

**7 fields.**

**(d) Observability components** — V2 §17 names *"structured logs, metrics, traces, health checks,
audit events, correlation IDs, alerting, retention and operational dashboards"* as required
components. So **correlation IDs are a V5 requirement**, though no format is given.

**Architectural consequence:** V5 describes **three record types, not one generic audit table**.
Any design collapsing them into one table is an architecture decision that must be justified
against these three field-sets — it is not implied by V5.

### The 14 audit decisions, re-scored against source

| # | Decision | Status after this mission |
|---|---|---|
| A1 | Schema topology | **INFORMED** — V5 implies ≥3 record types; collapsing them is an **architecture decision** |
| A2 | **Event taxonomy — what is "audit-worthy"** | **OPEN.** V5 says *"material agentic actions"* and *"material 12Circle security control"* without defining *material* → **OWNER DECISION REQUIRED** |
| A3 | **Write path** (trigger / application / both) | **OPEN — ARCHITECTURE DECISION REQUIRED.** V5 is silent |
| A4 | Actor identity | **INFORMED** — V5 requires *"actor/agent identity"*. **Residual hazard documented below** |
| A5 | Target/resource identity | **PARTIALLY INFORMED** — V5 requires *"scope"*; stable reference across deletion is architecture |
| A6 | **Before/after state** | **OPEN.** V5 never requires it → adding it is an architecture decision **with a PHI consequence** |
| A7 | Timestamp semantics | **PARTIALLY INFORMED** — V5 requires *"when"*; wearable rules (WI-23) make clock anomalies first-class |
| A8 | Source attribution | **INFORMED** — *"skill, tool/API"* for agents; SA-11 requires source revision in the release chain |
| A9 | Severity | **RESOLVED** — enum specified by V5 |
| A10 | Correlation / request ID | **RESOLVED as required**; format is architecture |
| A11 | **Immutability** | **RECLASSIFIED — NOT a V5 requirement** (0 hits). Now architecture decision **A-NEW** |
| A12 | **Retention** | **OPEN — OWNER DECISION REQUIRED.** V5 *explicitly defers*: *"subject to privacy and retention controls"*, and SQ-34 requires export/deletion, which can conflict with audit retention |
| A13 | **RLS / who may read audit** | **OPEN — OWNER + ARCHITECTURE.** V5 silent. Note the structural tension: admins are the audited party |
| A14 | **Trust visibility rules** | **OPEN.** Depends on A13 and D11 |

**14 → 7 open** (A2, A3, A6, A11/A-NEW, A12, A13, A14). **3 resolved, 4 informed.**

### The questions B1 asked, answered where evidence exists

| Question | Answer |
|---|---|
| What actions must be audited? | **OWNER DECISION (A2).** V5 requires audit for: privileged/AI-agent material actions (GV-08, AS-05), incidents (AG-04), and control verification (SA-03). The *enumeration* is undefined |
| Which actors? | human users, service role, **and agents** (V5 *"actor/agent identity"*) |
| Which resources? | V5 requires *"scope"*; specific resource list undefined |
| Minimum event fields | **SPECIFIED — see (a)/(b)/(c) above** |
| What must be immutable? | **V5 DOES NOT SAY.** Architecture decision A-NEW |
| Retention | **V5 EXPLICITLY DEFERS → OWNER DECISION** |
| Access model / who may read | **OPEN (A13)** |
| Does Admin role management require an audit event? | **YES by V5's own logic** — GV-08 and V4 require audit for permission-changing actions. **Today `admin_set_user_role()` writes none** |
| Do Trust actions require audit events? | **YES** — Trust includes Audit Logs and incident approval status (AG-04) |
| Do AI agent actions require audit events? | **YES — explicitly (V4 §5)** |
| Do security incidents require audit events? | **YES** — the incident record *is* the audit artefact (AG-04) |
| Do wearable PHI access events require audit? | **YES by implication** — V3 §4 Security/Privacy Layer requires *"auditability"*; V5 does not enumerate which accesses → **partially open** |
| Audit ↔ incidents relationship | **V5 keeps them distinct**: incidents carry investigation state (suspected cause, recommended action, approval status, resolution); audit events are the factual record. An incident **references** evidence |
| Audit ↔ agent action history | **V5 treats the agent trail as its own record type** (b), distinct from incidents |

**Residual hazard, documented not solved:** `enforce_profile_privilege()` returns early when
`auth.uid()` IS NULL — the service-role path. Any audit design keyed on `auth.uid()` will record
the **least** about the **most privileged** actor. This constrains A3 and A4.

## 5 · BLOCKER B2 — ADMIN / TRUST DESIGN AUTHORITY · **UNRESOLVED**

**Accessibility to the governance workflow: the approved design packages are NOT in this
repository.** The repo holds design *reconciliation* documents and a board reconciliation, not the
packages themselves. Measured: **0 mentions of "Trust", "AI Guardian" or "Incidents"** across all
seven design documents.

### ADMIN inventory

| Surface | Design | V5 req clear | Data req clear | Authz clear | Audit req clear |
|---|---|---|---|---|---|
| Home Dashboard | **MISSING** | PARTIAL | NO | YES (`is_admin`) | NO |
| Users | **MISSING** | YES | PARTIAL (`admin_recent_users()`) | YES | **YES — required** |
| Coaches | **MISSING** | PARTIAL | PARTIAL | YES | YES |
| Clients | **MISSING** | PARTIAL | PARTIAL — PHI views blocked by NEW-5 | YES | YES |
| Ecosystem | **MISSING** | **NO — term undefined in V5** | NO | NO | NO |
| **Exercise Review** | **PARTIAL — implemented** | YES | **YES** (migration 050) | YES | NO |
| **Observability** | **PARTIAL — implemented** | PARTIAL | **NO** — 0 DB tables | YES | NO |
| Security | **MISSING** | PARTIAL | NO | NO | NO |
| Incidents | **MISSING** | YES (11 fields) | **NO** — no table | NO | YES |
| Audit Logs | **MISSING** | YES (field-sets) | **NO** | NO | it *is* the requirement |
| AI Guardian | **MISSING** | YES (8 domains, L0–L3) | NO | NO | YES |
| Settings / Configuration | **MISSING** | **NO** | NO | NO | NO |
| Payments / Roles / Wearables / Health / Releases / Analytics / Database | **MISSING** | PARTIAL | NO | PARTIAL | YES |

### TRUST inventory

| Surface | Design | V5 req clear | Data req clear | Authz clear | Audit req clear |
|---|---|---|---|---|---|
| Trust Home | **MISSING** | **NO — not named in V5** | NO | NO | NO |
| AI Guardian | **MISSING** | YES | NO | NO | YES |
| Security | **MISSING** | PARTIAL | NO | NO | NO |
| Incidents | **MISSING** | YES | NO | NO | YES |
| Audit Logs | **MISSING** | YES | NO | NO | itself |
| Reviews | **MISSING** | **NO — not named in V5** | NO | NO | NO |
| Policies | **MISSING** | **NO — not named in V5** | NO | NO | NO |
| Alerts | **MISSING** | PARTIAL (V2 §17 "alerting") | NO | NO | NO |

**21 design dependencies.** Two Admin surfaces are implemented (Exercise Review, Observability) but
neither has an approved design package in the repo. **Trust Home, Reviews and Policies are named in
the mission brief but not in V5** — recorded, not adopted as requirements.

## 6 · BLOCKER B3 — WEARABLE ARCHITECTURE · **PARTIALLY RESOLVED**

| # | Layer | Status | V5-specified? | Decision required |
|---|---|---|---|---|
| 1 | **Connector** | **EXISTS (partial)** — `user_integrations` (provider, connected, access/refresh token, connected_at, disconnected_at); `integrations_screen.dart` names `apple_health`, `garmin`, `google_fit`, `polar`, `strava`, `myfitnesspal`, `spotify` | YES (V3 §4) | provider scope for V1 — **V5 AMBIGUOUS** |
| 2 | **Consent** | **PARTIAL** — connection implies consent; no granular scopes | YES (V3 §4 Security/Privacy) | scope granularity — **A** |
| 3 | Ingestion | **MISSING** | YES — timestamps, source identity, ordering, retries, dedupe | **D-V1** |
| 4 | Observation | **MISSING** | YES — raw separated from derived (WI-08) | **D-V3** |
| 5 | Normalization | **MISSING** | YES — canonical records | **D-V3** |
| 6 | Intelligence | **MISSING** | YES — zones, workout context, derived metrics, quality, **Training Alignment** | **D-V3** |
| 7 | Zones | **MISSING** | YES — personalized; **regression-sensitive (WI-24)** | version-pinning — **A** |
| 8 | **Provenance** | **MISSING** | **YES — fields specified: source, timestamp, calculation/version, quality indicators** | storage form — **A** |
| 9 | Storage | **MISSING** | YES — raw/derived with lifecycle controls | **D-V2** |
| 10 | **Access / PHI boundary** | **MISSING** | **PARTIAL — see §8** | **D-V4** |

**Resolved without implementation:** the layer inventory is now exact; **provenance fields are
specified by V5** (4 fields), so D-V3 is partially resolved; and the connector layer is confirmed to
already exist with 7 providers, so V5's "multiple data sources" requirement (WI-03) is **already
partially satisfied**.

**Still required:** D-V1 (boundary), D-V2 (store), D-V3 (canonical contract), D-V4 (PHI access),
plus V1 provider scope and the medical-diagnosis labelling rule (WI-21).

## 7 · BLOCKER B4 — TEAM SEMANTICS · **PARTIALLY RESOLVED**

### The current model, established from live evidence (descriptive, not a proposal)

| Term | Repository meaning | Evidence |
|---|---|---|
| `client` | default role; self-assertable | `enforce_profile_privilege()` INSERT branch |
| `coach` | **self-assertable at signup** | same — `('client','coach','vendor')` survive |
| `vendor` | **self-assertable at signup**; 0 users in QA | same; live `user_profiles` |
| `admin` | **NOT self-assertable** — coerced to `client`; changed only via `admin_set_user_role()` under a privileged GUC | verified live |
| `content_manager` | **NOT self-assertable**; recognised by **5 policies**; 1 user; **no screen** | live catalog |
| "team lead" | **not a role** — an *emergent* property of a `coach_team_members` row | `is_team_lead_of()` |
| `coach_team_members` | membership table with **no status column, no `WITH CHECK`, 0 triggers, 0 check constraints, no role check** | live catalog |
| `coach_client_relationships` | the *other* relationship model — status-bearing, `WITH CHECK`, `trg_relationship_integrity` | live catalog |
| "client membership" | expressed by `coach_client_relationships.status` | — |

### V5's terminology

V5 uses **Trainer/Coach ↔ Client/Member ↔ Wellness Partner**. It **never uses the words `vendor`,
`team lead`, `team`, or `content_manager`.** So:

- **Wellness Partner ↔ `vendor` is an INFERENCE, not a V5 mapping** → **OWNER DECISION**.
- **V5 provides no team model at all.** The entire "team"/"team lead" concept is a repository
  construct with no V5 counterpart → **the canonical semantic model is an OWNER DECISION (D1)**,
  and V5 supplies no default.

### Finding linkage

| Finding | Semantic root |
|---|---|
| **QAX-SEC-08** (P0) | "team lead" is emergent from a self-assertable row, and `is_team_lead_of()` carries no status — so a *membership* grants a *PHI read* |
| **F-03b** | `may_notify()` treats both relationship tables as authorization facts at any status |
| **SEC-PHI-9** | `coach` authority outlives `coach_client_relationships.status` in 2 of 5 policies |
| **QAX-SEC-09** | `vendor` authority derives from event ownership, and `vendor` is self-assertable |

**The common semantic defect: membership is conflated with authority, and authority has no
lifecycle in `coach_team_members`.** Stated as an observation; **no policy was changed and no
remediation performed.**

## 8 · BLOCKER B5 — WEARABLE PHI ACCESS · **PARTIALLY RESOLVED**

### What V5 specifies

- *"Coach-facing live and historical intelligence"* — **coach access authorized** (V3 §3)
- *"Client/member-facing live and historical intelligence"* — **member access authorized** (V3 §3)
- *"Partner/future-product integration APIs"* — partner access **via APIs**, scope unspecified
- *"Admin and Guardian telemetry"* — **Admin and Guardian receive *telemetry*, which V5
  distinguishes from member-facing intelligence**
- *"Ensure sensitive health/wearable data is not exposed through unauthorized **Admin, Coach,
  Partner, or client** paths"* (V3 §10) — all four are explicitly named as potential unauthorized
  paths

### Access matrix — **only V5-supported cells are filled**

| Role | Can view | Can write | Can export | Can share | Can administer | Audit required |
|---|---|---|---|---|---|---|
| **client / member** | **YES** — own (V3 §3) | own observations via connector | **UNRESOLVED** — SQ-34 requires export generally | **UNRESOLVED** | n/a | **YES** (V3 §4) |
| **coach** | **YES** — client's live + historical (V3 §3). **Active-only? UNRESOLVED** — but SEC-PHI-9/10 make status the decisive question | NO | **UNRESOLVED** | **UNRESOLVED** | NO | **YES** |
| **team lead** | **UNRESOLVED — V5 has no team concept** | — | — | — | — | — |
| **admin** | **TELEMETRY only per V5**; member-level PHI **UNRESOLVED** and explicitly listed as a potential unauthorized path | NO | **UNRESOLVED** | **UNRESOLVED** | platform config | **YES** |
| **vendor / Wellness Partner** | **UNRESOLVED** — partner APIs authorized in principle; scope undefined; mapping to `vendor` unconfirmed | NO | **UNRESOLVED** | **UNRESOLVED** | NO | **YES** |
| **content_manager** | **UNRESOLVED — V5 never mentions this role** | — | — | — | — | — |
| **AI agent / Guardian** | **TELEMETRY only per V5**; least privilege required (V4) | **NO** unless allowlisted + reversible (L2) | NO | NO | NO | **YES — V4 §5 explicit** |
| **Trust / security operator** | **UNRESOLVED — not a defined role in repo or V5** | — | — | — | — | — |

**7 of 8 roles have at least one unresolved column. Nothing was inferred from convenience, and no
permission was granted.** **D-V4 remains required**, now with a much narrower question: *does
"coach" mean active-only, and do Admin/Partner ever see member-level PHI rather than telemetry?*

## 9 · BLOCKER B6 — CANONICAL SCREEN INVENTORY · **RESOLVED (as analysis)**

| Number | Represents | Source | Authority |
|---|---|---|---|
| **91** | `GoRoute(` entries in `app_router.dart` — navigable routes | `FINAL_SCREEN_INVENTORY.json` `counts.routes`; **verified live at HEAD = 91** | Repository (implementation) |
| **89** | routes present in a release build (2 debug/QA-only) | `counts.routes_release_build` | Repository |
| **148** | "surfaces of all kinds" — routes + modals/sheets/state variants | `counts.surfaces_all_kinds` | Repository |
| **156** | screens on the Claude Design board, 2026-09-24 | `board_reconciliation.board_screens` | **Design** |
| **169** | board screens **including voice variants** | `board_reconciliation.with_voice` | **Design** |
| **174** | "approved existing screens" | **V5 GV-03 only — appears nowhere in the repository** | **V5 / owner assertion** |

**Conclusion: three different authorities measuring three different units** — implementation (91/89/148),
design board (156/169), and V5's protection baseline (174). **Not staleness**: `baseline_commit
0aa844a` is 76 commits behind HEAD, yet its `routes: 91` matches the live count exactly.

**169 → 174 is a gap of 5.** Plausible explanations exist (board growth after 2026-09-24; a
different variant-counting rule) but **the repository contains no evidence to choose between them,
so none is chosen.**

> **EXACT OWNER DECISION REQUIRED (CONF-01):** *"Publish the authoritative list of the 174 approved
> screens — as a named, versioned artefact committed to or referenced from the repository — and
> state which unit it counts (routes, surfaces, board frames, or board frames including voice
> variants). Until it exists, GV-03 ('protect the 174 approved existing screens') cannot be
> enforced or verified, and SQ-30 selective migration cannot be scoped."*

**Neither 169 nor 174 is declared authoritative here.**

## 10 · BLOCKER B7 — VENDOR HARDENING · **PARTIALLY RESOLVED**

| Aspect | Current evidence |
|---|---|
| Role semantics | `vendor` = event host / marketplace seller. **V5 never uses the word** |
| Registration | **self-assertable at signup** (`enforce_profile_privilege` permits `vendor` at INSERT) |
| Permissions | `events` `FOR ALL` **has** a `WITH CHECK` requiring `vendor_id = auth.uid()` **and** `role IN ('vendor','admin')` (020:18–26) — **this part is correctly hardened** |
| Event permissions | vendor manages own events; `event_registrations` has 2 vendor policies (SELECT, UPDATE) scoped by event ownership |
| Profile visibility | `hosts_event_for()` grants the **whole `user_profiles` row** to an event host — **the SEC-PHI-1 arm**, incl. `parq_answers` |
| Notification permissions | `may_notify()` does **not** include a vendor arm |
| PHI exposure | **`hosts_event_for()` → full profile row → PAR-Q.** Untestable today: `events.vendor_id` is **NULL** on both QA events |
| QA findings | **QAX-SEC-09** (P1, OPEN/BLOCKED); SEC-PHI-1 proposal exists but **NEW-5 shows it is non-functional as written** |
| V5 impact | Wellness Partner is 1 of 3 ecosystem personas (SQ-02), a QA persona (SQ-07), an E2E journey (SQ-24), and a partner-API consumer (WI-18) |

**Classification of the required hardening:**

| Item | Phase |
|---|---|
| Narrow `hosts_event_for()` to column-limited data (drop the full-row arm) | **PRE-V5 PREREQUISITE** — V5 expands the partner persona onto this exact arm |
| Corrected `SEC_PHI_1` (invoker `off` + barrier + predicate in view) | **PRE-V5 PREREQUISITE** (D17) |
| Decide whether `vendor` stays self-assertable (D2) | **PRE-V5 PREREQUISITE** — owner decision |
| Partner tenancy / API scoping | **V5 WORKSTREAM** |
| Live QAX-SEC-09 reproduction + post-fix denial | **POST-V5 VERIFICATION** — needs an `events.vendor_id` fixture |

**Nothing was fixed.**

## 11 · BLOCKER B8 — SBOM / RELEASE TOOLCHAIN · **RESOLVED (confirmed)**

**V5's wording confirms the build/release split:** *"**Production releases** shall generate a
versioned CycloneDX Software Bill of Materials…"* — the obligation attaches to **release**, not to
writing code.

| Question | V5 answer |
|---|---|
| Exact requirement | a **versioned CycloneDX SBOM** for applicable application, build, runtime and third-party components (SA-04) |
| **Format** | **CycloneDX — specified by name.** Not an open decision |
| Generation point | *"production releases"* → release pipeline. **Exact stage is an architecture decision** |
| Validation point | *"The release process shall validate the SBOM"* (SA-05) |
| Artifact retention | *"SBOM evidence shall be retained with the release record"* (SA-05) — **implies a release-record artefact that does not exist** |
| Release gate | *"The release pipeline shall use the SBOM as release evidence"*; added/removed/changed components **reviewable**; vulnerability, dependency, licensing, provenance and policy checks per the project's defined release policy — **which does not yet exist** |
| Provenance / integrity | *"appropriate integrity/signing and verification controls"* (SA-04); SA-11 chain: source revision → component inventory → SBOM → control verification → build artifact → deployment record → runtime monitoring |

**CONFIRMED: B8 is a RELEASE-TIME blocker, not a BUILD-TIME blocker.** Implementation may proceed
before the release-integrity architecture exists, **provided no release is attempted.**

**Two artefacts V5 requires that do not exist and are not tooling:** a **defined release policy**
and a **release record**. Both are documentation/architecture, creatable without installing
anything. **Not created here** (documentation-only mission, and they belong to the release
workstream). **Recorded recommendation:** have the security workstream emit SA-03-shaped control
evidence from the first wave, since reconstructing it later is more expensive.

## 12 · BLOCKER B9 — ADMIN SURFACE / TRANSPORT · **SUBSTANTIALLY RESOLVED**

**V5 names a web/admin surface distinct from the mobile client — three times:**

> SA-02: *"Security verification shall be mapped to the relevant product surface: **mobile client,
> web/admin surface**, backend services, APIs/RPCs, wearable APIs, partner APIs, and platform
> integrations."*
> SA-08: *"The matrix should identify which controls apply to **mobile, web/admin**, API, wearable,
> AI Guardian, agentic skills, data, and supply-chain surfaces."*
> SA-01: *"…applicable 12Circle+ **web**, API, service, and security-sensitive application surfaces."*

| Question | Determination |
|---|---|
| Mobile? | **Not indicated** for Admin. V5 consistently separates "mobile client" from "web/admin" |
| **Web?** | **V5-INDICATED** — named three times as its own surface |
| Separate application? | **Implied** by "web/admin surface" being enumerated alongside mobile; **not stated as an architecture requirement** |
| Existing API? | **UNRESOLVED (D5)** — the NestJS service is thin (4 modules) and not the primary data path |
| Supabase direct? | **UNRESOLVED (D5)** — this is how mobile and today's Admin screens work |
| New backend services? | **UNRESOLVED (D5)** |
| Role enforcement location | **Evidence-supported default: Postgres RLS + `is_admin()`**, which is verified sound (`admin` not self-assertable). Moving enforcement to an app layer would **weaken** AG-03's structural guarantee |
| Audit location | **UNRESOLVED — depends on A3** (trigger vs application write path) |

> **EXACT OWNER DECISION (D6, now narrowed):** *"V5 names a 'web/admin surface' separately from the
> 'mobile client' in three places. Confirm that Admin and Trust are a **web** surface rather than
> Flutter screens — and if so, whether it is a new application or an added target of the existing
> Flutter codebase."*

**Consequence of each option (described, not chosen):** a web surface means a new build/deploy/CI
target and a second client of the same RLS boundary, but keeps the 341-file mobile app free of
13 Admin domains; an in-app surface reuses existing auth/routing/theme and the 91-route structure,
but ships Admin code to every member's device — which for PHI-bearing admin views is a materially
larger attack surface.

## 13 · BLOCKER B10 — REPLAY HARNESS · **RESOLVED (as specification)**

**Why it is required:** to validate a *proposed* policy change **before** applying it. NEW-5 is the
proof of value — `SEC_PHI_1` would have returned `200 []` for exactly the users it serves, and only
simulation or live testing would have caught it. Cloud's existing harness targets loopback Postgres
`127.0.0.1:55433`, refuses to start if `QA_DB_URL`/`QA_SERVICE_ROLE_KEY`/`DATABASE_URL`/
`SUPABASE_DB_URL` is set, and its own header states it *"is NOT evidence about QA."*

| What must be replayed | Content |
|---|---|
| **Security scenarios** | the P0 chain (self-assert → `is_team_lead_of` → `user_profiles`); F-03b (`may_notify` → `notifications`); SEC-PHI-9/10 status predicates; NEW-2 (`can_read_program`); K-04 self-granted registration |
| **Authorization decisions** | per-role deny/allow for every new policy, **including the legitimate path** (the SEC-PHI-9 lesson) |
| **AI actions** | agent tool invocations against allowlists; L2 reversibility; L3 refusal |
| **Incidents** | detection → evidence → severity → approval → resolution transitions |
| **Audit events** | that each audit-worthy action emits exactly one record with the required fields |
| **Regression cases** | the 37 `FOR ALL`/no-`WITH CHECK` policies; the 3 stale skips once unskipped; every shrinking allowlist |
| **Required fixtures** | a `coach_team_members` row · an `events.vendor_id` · `score_events` for the cancelled-relationship client · one active + one cancelled relationship · a self-registered coach · a wearable observation stream (replayable, entering through authoritative paths per WI-25) |

**Specification is complete without implementation.** Remaining dependency is environmental
(Docker or a local Postgres) — **B11**, not a design gap.

## 14 · BLOCKER B11 — EGRESS / CI SECRETS · **RESOLVED (as classification)**

| Issue | Classification | Rationale |
|---|---|---|
| **HTTPS egress unavailable** (443 → HTTP 000; Postgres path works) | **ENVIRONMENT BLOCKER** | a property of this workstation, not of the product. Blocks `test:ai`, `test:security`, GitHub API verification |
| **CI secrets absent** | **QA-EVIDENCE + RELEASE BLOCKER** | 4 live-QA jobs have never executed → no live E2E evidence (SQ-24) and no release evidence chain |
| **Live-QA jobs never executed** | **QA-EVIDENCE BLOCKER** | *unexecuted ≠ failing*; asserting either way without running them would be manufactured evidence |
| **Shared-QA writes declined** | **AUTHORIZATION BLOCKER** | governance, not environment |
| **Docker / no Postgres server** | **ENVIRONMENT BLOCKER** | blocks B10 fix-simulation |
| **SBOM tooling forbidden** | **RELEASE BLOCKER** | §11 |

**What is a PRODUCT blocker: none of the above.** No item in B11 is a defect in the product. **This
materially narrows the readiness picture: B10 and B11 do not block V5 implementation — they block
*evidence* and *release*.**

## 15 · OWNER DECISIONS — exact formulations (21 remaining)

Each is stated so it can be answered without further analysis. **Consequences are described; no
product decision is selected.**

| ID | Exact question | Why it matters | Options supported by evidence | Consequence of delay |
|---|---|---|---|---|
| CONF-01 | Publish the authoritative 174-screen list and state its unit | GV-03 unenforceable without it | (a) reconcile to board frames (156/169) (b) restate against 91/148 (c) publish a new list | SQ-30 cannot be scoped |
| CONF-02 | Confirm the document's canonical name/version | SA-01/12 require version-qualified traceability | (a) "V1 Master V2+V3+V4+V5" (b) rename to V5 | release evidence ambiguity |
| CONF-03 | Authorize SBOM tooling, or accept the gap as a governed risk | SA-04 is a release gate | (a) authorize `syft`/`cyclonedx`/`trivy` (b) documented risk acceptance | no release possible |
| CONF-06 | Harden the partner role before partner APIs? | V5 expands the persona onto the `hosts_event_for()` full-row arm | (a) harden first (b) build behind a flag (c) defer | partner APIs on an unhardened role |
| CONF-08 | Supply or commission the 21 Admin/Trust design surfaces | **blocks Admin + Trust entirely** | (a) supply existing packages (b) commission | two phases cannot start |
| D1 | Who may create a `coach_team_members` row, and does membership carry a status lifecycle? | **closes the P0 and F-03b together** | Cloud's model: lead may not insert (`with check (false)`), member may — **a model, not approved** | P0 stays open |
| D2 | Do `coach` and `vendor` remain self-assertable at signup? | every `is_coach_profile()` check inherits it | (a) keep (b) require verification (c) keep for coach, restrict vendor | CONF-06 persists |
| D4/A2 | **Define "audit-worthy"** — enumerate the actions that must emit an audit event | V5 says *"material"* without defining it | V5 names 3 record types + their fields as the starting point | audit cannot be designed |
| D4/A12 | **Audit retention period**, and its precedence over erasure requests | V5 **explicitly defers**; SQ-34 requires export/deletion | — | retention vs erasure conflict unresolved |
| D4/A13 | Who may read audit records? | admins are the audited party | (a) admin-only (b) segregated audit role (c) Trust-operator role | audit RLS undesignable |
| D5 | Does Admin reach data via the NestJS API or direct Supabase? | determines whether the API workstream exists | (a) direct Supabase + RLS (matches today) (b) via API | API scope undefined |
| D6 | Confirm Admin/Trust as a **web** surface (V5-indicated) — new app or added target? | scope of mobile vs web workstreams | (a) separate web app (b) Flutter web target (c) in-app | §12 |
| D7 | Are Users/Coaches/Clients distinct Admin modules or views over `user_profiles`? | determines whether new column-limited views are needed | — | Admin data model undefined |
| D8 | Does `content_manager` get an Admin surface? | a policy-recognised role (5 policies) with no screen | (a) yes (b) no (c) fold into admin | role stays unserved |
| D10 | What AI processing is disclosed to members? | SEC-AI-1; privacy alignment | matrix complete and ready to rule on | privacy stays partial |
| D12 | Audit read/immutability/retention posture | A11–A14 | see A-NEW | audit incomplete |
| D16 | Does the standalone wearable platform trigger design-system extraction? | standing directive: *extract on the second product* | (a) treat it as product #2 → extract (b) defer | possible rework |
| D-V1 | Where does the wearable platform live? | **blocks the whole wearable stack** | (a) expand NestJS (b) new service (c) separate repo + SDK | wearable cannot start |
| D-V2 | Shared Postgres or its own store? | tenancy, RLS reuse, partner exposure | (a) shared (b) separate | schema unspecifiable |
| D-V4 | Does "coach" mean active-only, and do Admin/Partner ever see member-level wearable PHI or only telemetry? | **PHI boundary on a surface with 2 verified defects** | V5 authorizes coach + member; Admin/Guardian = telemetry | authz undesignable |
| D-V5 | What identity represents an agent in the audit trail? | agent actions must be attributable | — | agent trail undesignable |

**Downgraded to confirmation-only: CONF-02, D6, D11.**

## 16 · ARCHITECTURE DECISIONS (11 + 1 new)

| ID | Constrained by V5? | Status |
|---|---|---|
| CONF-04 wearable deployability | **YES** — V3 §5 requires independence from 12Circle+ screens | **ARCHITECTURE DECISION REQUIRED** (D-V1) |
| CONF-05 audit as architecture | **PARTIALLY** — 3 field-sets given; topology and write path not | **REQUIRED** (A1, A3) |
| CONF-07 Admin scale | NO | **REQUIRED** |
| CONF-09 CI release gates | **YES** — SA-11 specifies the chain order | **REQUIRED** — chain is prescriptive |
| D3 uniform status predicate | NO | **default documented** — option (b), a text-taking `is_active_coach_of(text)` that returns false rather than raising |
| D9 server-side AI entitlement | **YES** — V4 requires deterministic authorization at execution boundaries | **RESOLVED IN PRINCIPLE**; implementation open |
| D13 `static-guards` fail-late | NO | **options documented** — reorder, or per-step `continue-on-error` |
| D14 branch protection | **YES** — SA-11 implies gate enforcement | **REQUIRED** — blocked on B11 verification |
| D15 guard population from live catalog | NO | **default documented** — 37 live vs 33 source |
| D17 fix `SEC_PHI_1` first | NO | **fix documented** — `security_invoker = off` + `security_barrier = true` + predicate inside the view |
| D-V3 canonical contract | **PARTIALLY** — provenance fields specified | **PARTIALLY RESOLVED** |
| **A-NEW audit immutability** | **NO — V5 is silent (0 hits)** | **NEW ARCHITECTURE DECISION.** Reclassified from a misattributed V5 requirement |

**Owner product decisions (§15) are separated from architecture decisions (this section).
Implementation decisions — widget composition, file layout, naming inside an approved contract —
remain delegated to the implementing agents under governance and are deliberately not enumerated.**

## 17 · QA CARRY-FORWARD (19 items — none closed)

| QA ID | Sev | Status | V5 domain | Component | Remediation phase | Retest point | Evidence required | Closure criteria |
|---|---|---|---|---|---|---|---|---|
| QAX-SEC-08 | **P0** | OPEN / PARTIALLY VERIFIED | Ecosystem, Admin, wearable PHI | `coach_team_members` → `user_profiles` | **P1 Security Foundation** | on migration apply | live forged-insert denial + legitimate team read intact | victim insert denied; SEC-G1 baseline lowered |
| F-03b | P1 | OPEN / PARTIALLY VERIFIED | Guardian alerting | `may_notify` → `notifications` | **P1** | same wave | live forged-notify denial | `may_notify` status-filtered |
| QAX-SEC-09 | P1 | OPEN / **BLOCKED** | Wellness Partner, partner APIs | `hosts_event_for`, `event_registrations` | **P1 (pre-V5 per §10)** | after vendor fixture | live vendor probe | minimum-necessary attendee fields only |
| SEC-PHI-9 | P1 | **OPEN / VERIFIED** | Wearable authz pattern | `storage.objects` 029 | **P1** | before wearable storage | former-coach denied **and active-coach unbroken** | both proven live |
| SEC-PHI-10 | P1 | OPEN / INFERRED | Same | `score_events` 035 | **P1** | with SEC-PHI-9 | `score_events` for cancelled client | predicate enforced + demonstrated |
| SEC-AI-1 | P1 | OPEN / INFERRED | AI governance | AI surface | **P7** | AI wave | owner ruling + implementation | disclosure matches implementation |
| NEW-2 | P2 | OPEN | Programme data / Training Alignment | `workout_program_assignments`, `can_read_program` | P1 or P4 | on fix | post-fix read denial | `WITH CHECK` + status predicate |
| NEW-5 | P2 | OPEN | Admin PHI views | `docs/proposed/SEC_PHI_1_*.sql` | **P1 — before applying** | on corrected apply | both screens functional | team-lead view returns rows |
| NEW-7 | P2 | OPEN (3 stale) | Monetization QA | billing specs | P1 | on unskip | K-12/K-ENV-1 green; **K-09 reviewed** | specs act as guards |
| QAT-1 | P2 | OPEN | CI release gate | `anon_least_privilege.py` | **CI wave (parallel)** | on CI run | ENV-5 green | all 7 gates execute in CI |
| NEW-8 | P3 | OPEN (latent) | CI reliability | `ci.yml` | CI wave | on CI run | 6 gates executing **in CI** | one failure cannot blind six |
| NEW-9 | P3 | OPEN | E2E journeys | CI secrets | CI wave | after secrets | 4 live jobs executing | live tier green |
| NEW-3 | P3 | OPEN | Community Guardian | `coach_reviews`, `recalc_coach_rating` | P9 | later | relationship gate | reviews gated |
| K-01 | P2 | OPEN | Monetization Guardian | `stripe-webhook` | **parallel P1–P2** | on fix | processed-event store | idempotent on redelivery |
| K-02/K-06 | P2 | OPEN | Same | `stripe-webhook` | parallel | on fix | 4 events handled | renewals/refunds/disputes reconciled |
| K-03 | P2 | OPEN | AI entitlement (D9) | 3 AI edge fns | parallel | on fix | plan check present | entitlement enforced server-side |
| K-04 | P2 | OPEN / **live-confirmed** | Monetization + authz | `event_registrations` | **P1** (it is an RLS defect) | on migration | self-grant denied | `WITH CHECK` present |
| K-05 | P3 | OPEN | Monetization | `booking_screen.dart` | parallel | on fix | credit drawdown | credits consumed |
| K-07 | P2 | OPEN | Monetization | `cancel-subscription` | parallel | on fix | failed cancel does not revoke | local state consistent |

**Partial domains carried:** PHI table access 0.75 · supply chain 0.75 · test completeness 0.9 ·
AI/processors 0.5 · privacy alignment 0.5 · replay harness 0.5 (blocked).
**Nothing was closed because it is now associated with V5.**

## 18 · BUILD DEPENDENCY GRAPH

| Node | Blocked by | Blocks | Can run in parallel with | Must precede |
|---|---|---|---|---|
| **DECISIONS** (CONF-01/02, D1, D4, D6, D-V1/V2/V4) | owner | everything | — | all build |
| **DESIGNS** (21 surfaces, CONF-08) | owner/design | Admin, Trust, Guardian UI, wearable UX | decisions | P5–P8 |
| **ARCHITECTURE** (ADRs for A1/A3, D-V1/V2/V3) | decisions | data, API | designs | P2–P3 |
| **SECURITY FOUNDATION** (queue 1–5, K-04) | **D1, D3, D17** | any PHI/team feature | monetization, CI wave | **everything touching PHI** |
| **DATA / AUDIT** (A1–A14) | **D4, D12, A-NEW** | Admin audit, Trust, Guardian, agent trail | wearable store | P5, P6, P7 |
| **OBSERVABILITY** | architecture | Admin health/analytics, Release Guardian | audit | P5 |
| **API** (wearable platform, partner) | **D-V1, D5** | mobile wearable, partner APIs | audit | P4, P9 |
| **ADMIN** | audit, designs, D5/D6/D7 | Trust | — | P6 |
| **TRUST** | audit, Admin, designs, D11 | Guardian UI | — | P7 |
| **AI GUARDIAN** | audit, observability, D-V5, AS-* | — | — | P10 |
| **WEARABLE** | D-V1/V2/V3/V4 | mobile wearable UX, partner APIs | audit, Admin | P8, P9 |
| **MOBILE** | designs, API contracts, D6 | integration | Admin (if web) | P9 |
| **QA** | all implementation; B10/B11 for full evidence | release | continuous | P11 |
| **RELEASE** | CONF-03, D-V6, D14, QA | — | — | — |

**Critical path (unchanged, now better evidenced):**
`D1 → Security Foundation` and `D4 → Audit → Admin → Trust → Guardian`, with
`D-V1 → wearable stack` running in parallel.
**Newly established:** **B10 and B11 are *not* on the implementation critical path** — they gate
evidence and release only (§14).

## 19 · SKILLS-AGENT WORKSTREAM CONTRACTS (13, prepared — not executed)

Common to all: **may not redefine V5**; must record evidence, not inference; must stop at a
governance boundary rather than route around it; migration numbers assigned **at wave entry only**;
shrinking allowlists never grow; every guard mutation-tested; a detector must be proven able to
find a planted defect before a zero result is believed.

| # | Workstream | Objective | Inputs | Dependencies | Allowed mutations | Forbidden | Required tests | Required evidence | Handoff criteria |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Governance / V5** | interpret V5; maintain the ambiguity register | V5 doc, 5 governance docs | — | `docs/**` | any code | — | requirement→V5-section trace | owner sign-off on ambiguities |
| 2 | **Architecture** | ADRs resolving A1/A3, D-V1/V2/V3, CONF-04/05/07/09 | V5, repo, QA ledger | WS1 | `docs/**` | any code | — | ADR citing evidence per decision | ADR approved by owner where product-facing |
| 3 | **Security** | verify controls **independently of implementation** | all | all | `**/test/**`, `docs/**` | **product code, policies** | live deny + **live legitimate-path** proof; mutation tests | per-control SA-03 record | no open P0/P1 in wave scope |
| 4 | **Database** | schema, RLS, migrations | ADRs | WS2, D4/D-V2 | `supabase/migrations/**` | app code | policy mutation tests | **live catalog** verification | migration applied + catalog-verified |
| 5 | **Backend / API** | services, contracts, SDK | ADRs, contracts | WS2/WS4, D5/D-V1 | `apps/api/**`, `supabase/functions/**` | migrations, mobile | contract + unit + e2e | contract published + versioned | contracts consumable |
| 6 | **Mobile** | Flutter surfaces | designs, contracts | WS5, WS11, D6 | `apps/mobile/lib/**` | migrations, API | widget + guard tests; **ERR-G2 compliance** | design-QA pass | design parity evidenced |
| 7 | **Admin** | Control Center (13 domains) | designs, contracts | **WS4 audit**, WS11 | admin surface only | migrations | permission + **audit emission** tests | audit record per action | every action audited |
| 8 | **Trust** | Security · Incidents · Audit Logs | designs, audit schema | **WS7**, WS4 | trust surface only | migrations | audit + RLS tests | evidence model verified | incident lifecycle proven |
| 9 | **AI Guardian** | 8 domains, L0–L3, allowlists, action tiers | V4/V5 controls | WS4, WS8, D-V5 | guardian surface + config | **production actions outside the L2 allowlist** | AST10 + injection + runaway + containment | agent action trail per action | agentic QA gate passed |
| 10 | **Wearables** | connector→intelligence platform | D-V1/V2/V3/V4, contracts | WS2, WS4 | platform boundary per D-V1 | mobile presentation | ingestion, normalization, **zone regression**, provenance | provenance + calc version on every derived metric | contracts stable + versioned |
| 11 | **Design** | approved packages for the 21 surfaces | V5, product | WS1, CONF-08 | design artifacts, `docs/**` | any code | — | package versioned **in repo** | package approved |
| 12 | **QA** | verify correctness across 5 tiers | implementation | all | `**/test/**`, `docs/**` | product code | all 5 tiers | **executed** evidence, never inferred | domain disposition recorded |
| 13 | **Release / CI** | SBOM, release policy, release record, integrity chain | CONF-03, D-V6, D14 | WS12 | `.github/**`, `docs/**` | product code | pipeline verification | SBOM + release record + chain | release gate evidenced |

## 20 · ADVERSARIAL REVIEW

| Challenge | Outcome |
|---|---|
| Did repository evidence actually support each resolution? | **Yes** — B6 from `FINAL_SCREEN_INVENTORY.json`, B3/B4/B7 from the live catalog, B9/B5/B8/B1 from quoted V5 text |
| Did V5 actually specify what I attributed to it? | **One failure found and corrected** — **A11 immutability was my inference, not V5** (0 hits). Reclassified as A-NEW |
| Did I infer a product decision? | **No.** 21 owner decisions are formulated, none answered. **CONF-01 explicitly refuses to declare 169 or 174 authoritative** |
| Did I convert a design assumption into architecture? | **No** — all 21 Admin/Trust surfaces are marked MISSING; Trust Home/Reviews/Policies flagged as **not named in V5** rather than adopted |
| Did I close a QA finding? | **No** — 19 items carried; SEC-PHI-9 remains the only VERIFIED one |
| Did I authorize implementation? | **No** |
| New security boundary created? | **Yes, identified not created** — wearable PHI (D-V4), partner API tenancy, audit read model (A13) |
| Requires an audit event? | **Yes** — admin role management (today emits none), Trust actions, agent actions, incidents, wearable PHI access |
| Affects PHI? | **Yes** — D-V4, B7's `hosts_event_for()` full-row arm, A6 (before/after state could duplicate PHI into audit) |
| Affects RLS? | **Yes** — D1, D3, D17, A13, every new table |
| Affects agent autonomy? | **Yes** — D-V5, the L2 allowlist (V5 gives only two examples), AG-03 |
| Affects release integrity? | **Yes** — CONF-03, D-V6, D14; and V5 requires a **release policy** and **release record** that do not exist |
| Did I collapse related-but-distinct decisions? | **No** — audit is tracked as A1–A14 separately from D4/D12 |
| Did I overstate what was resolved? | **Checked.** 5 resolved, 5 *partially advanced*, 1 unresolved — B1/B3/B4/B5/B7 are **not** counted as resolved because their core decisions remain |

---

## 21 · FINAL READINESS REASSESSMENT

| | |
|---|---|
| Blockers before | **11** |
| Resolved | **5** — B6 (analysis), B8 (confirmed release-time), B9 (V5-indicated web), B10 (specified), B11 (classified) |
| Partially advanced | **5** — B1 (14→7 audit decisions), B3 (layers exact; provenance specified), B4 (current model documented), B5 (coach + member authorized), B7 (hardening classified) |
| Unresolved | **1** — B2 |
| **Remaining blocking** | **6** — B2 + the decision cores of B1, B3, B4, B5, B7 |
| Owner decisions remaining | **21** (3 confirmation-only) |
| Architecture decisions remaining | **11 + 1 new (A-NEW)** |
| Design dependencies | **21** |
| QA items carried | **19** |

### **NOT READY — OWNER / ARCHITECTURE INPUT REQUIRED**

Six blockers remain and **every one turns on a decision or artefact only the owner or an
architecture authority can supply** — not on further analysis. This mission extracted everything
the evidence and V5 text could yield; continuing to analyse would produce invention, not progress.

**Four inputs clear five of the six remaining blockers:**

1. **D1** — team semantics → clears B4, unblocks the P0/F-03b fix and the Security Foundation wave.
2. **D4 + A2/A12/A13** — audit taxonomy, retention, read model → clears B1, unblocks Admin, Trust, Guardian.
3. **CONF-08** — the 21 Admin/Trust design surfaces → clears B2.
4. **D-V1/D-V2/D-V4** — wearable boundary, store, PHI access → clears B3 and B5.

**B7** additionally needs **D2** (whether `vendor` stays self-assertable).

**Not on the critical path:** B8 (release-time only), B10 and B11 (evidence and release, not
implementation).

---

*Documentation-only mission. QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**; 1 P0 and 4 P1
open, none closed or downgraded. No code, schema, migration, RLS, policy, design, CI or database
change was made. No owner decision was taken. **Implementation remains unauthorized.***
