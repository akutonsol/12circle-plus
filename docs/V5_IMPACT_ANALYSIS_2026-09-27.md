# V5 IMPACT ANALYSIS

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** IMPACT ANALYSIS ONLY. No implementation, no remediation, no mutation.
**V5 source:** `12Circle_V5_Product_Ecosystem_Release_Sequencing_V5_Wearable_Intelligence_Platform.docx`
(335 paragraphs, ~4,362 words — read in full)

> **IMPLEMENTATION IS NOT AUTHORIZED.** Next gate: **V5 IMPLEMENTATION READINESS GATE**.

---

## 1 · EXECUTIVE SUMMARY

### What V5 actually is

The attached document is **not a single specification**. It is a **layered master with three
additive amendments**, and its own title differs from the filename:

| Layer | Own title | Content |
|---|---|---|
| Base | **"12CIRCLE+ V1 MASTER PRODUCT, ECOSYSTEM, OPERATIONS & RELEASE SEQUENCE — VERSION 2 — SOURCE OF TRUTH"** | source-of-truth hierarchy · 8 governance rules · **48-step master sequence** · 8 Guardian domains · autonomy L0–L3 · incident model · 4 QA personas · 11 value-adds · final release gate |
| V3 | "VERSION 3 AMENDMENT — WEARABLE INTELLIGENCE AS A STANDALONE PRODUCT" | wearable as an independently deployable **10-layer platform**, 10-step sequence, 14-item DoD |
| V4 | "VERSION 4 AMENDMENT — AI AGENT / AGENTIC SKILLS SECURITY & GOVERNANCE" | OWASP baseline · **Agentic Skills Top 10** · agent inventory · agent audit trail · agentic QA gate |
| V5 | "VERSION 5 AMENDMENT — SECURITY ASSURANCE, ASVS, SBOM & CONTROL MAPPING" | **ASVS 5.0.0** · **CycloneDX SBOM** · OpenCRE crosswalk · security assurance matrix · release-integrity chain |

Each amendment states it is **additive** and that prior requirements **remain in force**. So the
scope is the union of all four layers, not the V5 section alone.

### The four findings that dominate this analysis

1. **V5's central security additions land exactly on this system's verified weakest domains.**
   V5 §4–5 require a **versioned CycloneDX SBOM as release evidence**; QA established SBOM =
   **ABSENT** with no tooling installed, and CycloneDX appears in the repository *only inside my
   own QA reports*. V5 §3 and V4 §5 require **auditable control and agent-action evidence**; QA
   established **zero audit infrastructure of any kind**. These are not new risks V5 introduces —
   they are pre-existing gaps V5 promotes to release gates.

2. **The largest build surface in V5 is almost entirely unbuilt.** AI Guardian (8 domains, 4
   autonomy levels), Admin Control Center (13 domains), incident model, and observability
   (logs/metrics/traces/correlation IDs/alerting) are **NOT CURRENTLY EVIDENCED**, against an
   existing Admin of **3 screens** and **0 server-side observability tables**.

3. **Wearable Intelligence partially exists — at exactly one of ten layers.**
   `integrations_screen.dart` + `user_integrations` provide connection/consent for
   `apple_health`, `garmin`, `google_fit`, `polar`, `strava`, `myfitnesspal`, `spotify`. There is
   **no observation store, no ingestion, no normalization, no zones, no provenance, no API/SDK**.
   V3 additionally requires it to be a **standalone, independently deployable product** — an
   architectural boundary that does not exist anywhere in this repository.

4. **A governance-rule conflict that must not be silently reconciled.** V5's first
   non-negotiable rule is *"Protect the 174 approved existing screens."* The repository's own
   authoritative inventory (`docs/FINAL_SCREEN_INVENTORY.json`) records **91 routes**, 89 in a
   release build, and **148 surfaces of all kinds** — **no 174**. The document's own rule says
   conflicts between sources *"become explicit owner/architecture decisions; they are never
   silently reconciled."* Recorded as **CONF-01**, unresolved.

**One favourable alignment worth stating:** V5's QA-data-realism personas (QA Coach, Client A
active, Client B self-guided, Wellness Partner) map onto an existing fixture harness
(`setup-identities.mjs`, 4 identities) — but the **Wellness Partner** persona corresponds to the
`vendor` role, which has **0 users** in QA, and `events.vendor_id` is **NULL**, which is
precisely why QAX-SEC-09 is untestable.

**Counts:** 64 requirements analysed · 58 gaps · 24 architectural decisions (17 carried + 7 new)
· 9 conflicts · 31 security-impacting · 27 database-impacting.

## 2 · V5 REQUIREMENT INVENTORY

Classifications: **1** EXISTS · **2** PARTIALLY EXISTS · **3** NOT IMPLEMENTED · **4** CONFLICTS ·
**5** REQUIRES ARCH DECISION · **6** BLOCKED BY QA FINDING · **7** BLOCKED BY EXTERNAL DEPENDENCY ·
**8** V5 AMBIGUOUS · **9** NOT CURRENTLY EVIDENCED.

### 2a · Governance & source of truth (V2 head)

| ID | Requirement | Class | Evidence |
|---|---|---|---|
| GV-01 | Source-of-truth hierarchy: sequencing doc → repo → approved design → schema → QA evidence | **1** | all five exist; QA evidence is the strongest layer |
| GV-02 | Conflicts become explicit owner decisions, never silently reconciled | **1** | applied in this document (§16) |
| GV-03 | **Protect the 174 approved existing screens** | **4** | repo inventory says **91 routes / 148 surfaces**; no 174 → **CONF-01** |
| GV-04 | Design → approved handoff → Code is a controlled chain | **2** | 7 design docs exist; Admin/Trust designs **not in repo** |
| GV-05 | No hard-coded realistic-looking production data to populate screens | **1** | `is_demo` flag (110) + deterministic fixtures |
| GV-06 | **Never invent schema fields from designs; record DATA GAP** | **1** | contract guard enforces it — 91 tables/134 FKs, 3 allowlisted knowns |
| GV-07 | Security, authorization, privacy, integrity, observability, auditability are first-class | **2** | security/authz strong (RLS on 91/91); **observability + auditability absent** |
| GV-08 | AI agents: least privilege, allowlisted tools, action limits, audit logging, human approval | **3** | no agent runtime in product; `anon_least_privilege.py` is a QA tool, not a control |
| GV-09 | Every release needs rollback/feature-flag strategy + critical-journey evidence | **2** | rollback material in 29 docs; **feature flags: 0 files** |
| GV-10 | QA/staging data marked, controlled, resettable, authorization-tested | **2** | `is_demo` + fixtures exist; **reset path blocked** (shared-QA writes declined) |

### 2b · Master sequence (48 steps — those creating build surface)

| ID | Step | Requirement | Class | Evidence |
|---|---|---|---|---|
| SQ-01 | 1 | Finish current QA | **2** | **90.0%, QA COMPLETE WITH OPEN FINDINGS**; 1 P0 + 4 P1 open |
| SQ-02 | 2–3 | Ecosystem capability audit; architecture & data contracts for Coach ↔ Client ↔ **Wellness Partner** | **2** | coach/client modelled; **`vendor` has 0 users**, `events.vendor_id` NULL |
| SQ-03 | 5 | V1 scope / product contract | **9** | no scope contract artefact found |
| SQ-04 | 6 | Monetization strategy + approved screens | **2** | Stripe + 19 edge fns; **6 open K entitlement specs** |
| SQ-05 | 7 | Design system / component governance (tokens, states, a11y) | **2** | local `app_theme.dart` + `twelve_circle_theme.dart`; **no shared design system** |
| SQ-06 | 10 | Design-to-data extraction / schema mapping + DATA GAP | **1** | contract guard is exactly this mechanism |
| SQ-07 | 11 | QA personas: Coach, Client A, Client B, Wellness Partner | **2** | `setup-identities.mjs` 4 identities; Partner unpopulated |
| SQ-08 | 13 | Automated QA incl. security, authorization, mutation, a11y, cross-role | **2** | mutation testing + guards mature; **a11y and cross-role not evidenced** |
| SQ-09 | 15–16 | **Platform Admin architecture + Admin Control Center** (13 domains) | **3** | Admin = **3 screens**, 4 SECURITY DEFINER fns |
| SQ-10 | 17 | **Observability foundation** (logs, metrics, traces, health, audit events, correlation IDs, alerting, retention) | **3** | `app_failure.dart` + a `decision_traces` dir; **0 observability tables** |
| SQ-11 | 18–21 | **AI Guardian** architecture, implementation, safety controls, QA | **9** | 0 files |
| SQ-12 | 22–23 | Competitive analysis; missing screens/functionality | **2** | design-gap docs exist |
| SQ-13 | 24–28 | Wearable definition → design → data architecture → implementation → QA | **2** | see §2d |
| SQ-14 | 29 | **Feature flags / controlled rollout** | **3** | **0 files** |
| SQ-15 | 30 | Selective existing-screen migration with regression evidence | **5** | depends on CONF-01 |
| SQ-16 | 31 | Full data realism pass | **6** | needs fixture writes — **declined** |
| SQ-17 | 32 | Full-system reconciliation | **1** | completed (`RECONCILIATION_LOCAL_CLOUD_GITHUB.md`, transition doc) |
| SQ-18 | 33 | Security hardening (app/API/DB/RLS/auth/secrets/deps/AI/abuse/release) | **2** | RLS + DEFINER hardening strong; **deps: 7 high npm advisories** |
| SQ-19 | 34 | Privacy/compliance verification (minimization, consent, retention, export/deletion, auditability) | **2** | correction-rights + privacy matrix done; **auditability absent**; retention not evidenced |
| SQ-20 | 35 | Performance engineering | **9** | no performance evidence found |
| SQ-21 | 36 | Observability/analytics verification | **3** | depends on SQ-10 |
| SQ-22 | 37 | Accessibility QA | **9** | no a11y gate found |
| SQ-23 | 38 | Full visual/design QA | **2** | design-route matrices exist |
| SQ-24 | 39 | E2E journeys incl. **Admin** and **Wellness Partner** | **6** | `uix1-e2e` CI job exists but has **never executed** (secrets) |
| SQ-25 | 40 | Backward compatibility / migration verification | **1** | ENV-1/ENV-3/I-MIG-03 gates **PASS** (132 migrations, contiguous) |
| SQ-26 | 41 | CI/release verification incl. **security scans** | **2** | 7 jobs; **0 security-scan steps**; `static-guards` red |
| SQ-27 | 42 | **Backup / restore / disaster recovery** | **9** | `disaster_recovery`: 0 files; Supabase free tier, **no PITR** |
| SQ-28 | 43 | Release / rollback drill | **9** | no drill evidence |
| SQ-29 | 44–47 | RC freeze → final audit → identity transition → production release | **9** | not started |
| SQ-30 | 48 | Post-launch monitoring via Admin + Guardian | **3** | depends on SQ-09/SQ-11 |

### 2c · AI Guardian, Admin & incident model (V2)

| ID | Requirement | Class | Evidence |
|---|---|---|---|
| AG-01 | 8 Guardian domains: System Health · Security · Data Integrity · AI · Monetization · Wearable · Community · Release | **9** | none implemented |
| AG-02 | Autonomy L0 Observe / L1 Recommend / L2 allowlisted reversible / L3 human-required | **9** | no agent runtime |
| AG-03 | Guardian **must not** be able to disable core application security controls on emergency disablement | **5** | security is RLS-enforced in Postgres — *structurally* favourable, but unverified as a designed control |
| AG-04 | Incident record: what/when/scope/evidence/severity/cause/recommended/taken/actor/approval/resolution | **3** | **no incident table under any name** (live sweep) |
| AG-05 | Severity taxonomy Critical/High/Warning/Informational | **3** | no store |
| AG-06 | Agent findings traceable to evidence; confidence ≠ proof | **9** | no agent |
| AG-07 | False positives/negatives become Guardian QA findings | **9** | no agent |
| AD-01 | Admin Control Center over health, security, users, roles, payments, AI, wearables, database, incidents, releases, analytics, audit (**13 domains**) | **3** | 3 screens: dashboard, exercise review, observability |
| AD-02 | Operational roles + permissions + control boundaries | **2** | 5 roles; `admin` **not self-assertable** (verified); `content_manager` policy-recognised but unserved |
| AD-03 | Admin audit model | **3** | `admin_set_user_role()` (a privilege primitive) writes **no audit record** |

### 2d · Wearable Intelligence (V3)

| ID | Requirement | Class | Evidence |
|---|---|---|---|
| WI-01 | Wearable is a **reusable, independently deployable product platform** | **3** | no such boundary exists in this repo |
| WI-02 | Must operate independently of 12Circle+ mobile UI | **3** | — |
| WI-03 | Multiple device/data sources, not one manufacturer | **2** | `user_integrations.provider` already names 7 providers |
| WI-04 | Connector layer (device connection + authorization) | **2** | `integrations_screen.dart` + `user_integrations` (provider, connected, access/refresh token, connected_at, disconnected_at) |
| WI-05 | Ingestion layer (timestamps, source identity, ordering, retries, dedupe) | **3** | no ingestion path |
| WI-06 | Normalization to canonical records | **3** | no canonical record type |
| WI-07 | Intelligence layer: zones, workout context, derived metrics, quality, **Training Alignment** | **3** | no heart-rate or zone concept anywhere |
| WI-08 | **Raw observations separated from derived intelligence** | **3** | no observation table |
| WI-09 | **Provenance on every derived metric**: source, timestamp, calculation/version, quality | **3** | — |
| WI-10 | Real-time **and** historical paths | **3** | no realtime channel evidenced |
| WI-11 | Controlled API/SDK rather than screen coupling | **3** | API is a thin 4-module NestJS service |
| WI-12 | Storage layer with lifecycle controls; retention + deletion | **3** | — |
| WI-13 | Wearable observability (latency, ingestion failures, sync health, quality) | **3** | — |
| WI-14 | Security/privacy layer: consent, least privilege, sensitive-data boundaries, auditability | **3** | health data is PHI-class → inherits the whole PHI regime |
| WI-15 | Admin/Guardian wearable telemetry | **3** | — |
| WI-16 | Own versioning, test suite, docs, observability, security boundaries, release lifecycle | **5** | **repository-boundary decision** — new repo vs package vs module |
| WI-17 | Coach-facing **and** client-facing live + historical intelligence | **3** | — |
| WI-18 | Partner/future-product integration APIs; tenancy/isolation | **3** | no tenancy model |
| WI-19 | Monetization: internal · coach offering · white-label/API · SDK subscription · enterprise · premium analytics · device expansion | **8** | *"Commercial packaging, pricing, legal terms… remain product-owner decisions"* — V5 defers explicitly |
| WI-20 | Working name "12Circle Wearable Intelligence"; architecture must not depend on final name | **1** | no naming dependency exists yet |
| WI-21 | Never treat an observation as medical diagnosis | **5** | safety/labelling requirement; no surface yet |
| WI-22 | Handle stale/missing/duplicate/delayed/impossible/conflicting observations | **3** | — |
| WI-23 | Test permission revocation, reconnection, disconnect, partial sync, clock anomalies | **3** | `disconnected_at` exists; no sync concept |
| WI-24 | Zone calculations are regression-sensitive | **3** | — |
| WI-25 | **QA may use synthetic/replayable observations but they must enter through authoritative paths** | **3** | no path to enter through |

### 2e · Agentic AI security (V4)

| ID | Requirement | Class | Evidence |
|---|---|---|---|
| AS-01 | OWASP guidance as a formal engineering baseline | **3** | **`asvs`: 0 files; `opencre`: 0 files**; no OWASP mapping artefact |
| AS-02 | Every agent/skill/tool/connector has explicit purpose, authority, data boundaries, allowed actions, failure behaviour, auditability, lifecycle owner | **3** | no product-side agent runtime |
| AS-03 | **OWASP Agentic Skills Top 10 (AST10)** evaluated per applicable skill | **3** | no evaluation artefact |
| AS-04 | Authoritative inventory of agents/skills/tools/connectors/permissions/scopes/versions/owners | **3** | none |
| AS-05 | **Agent action audit trail** — identity, skill, tool, input, authorization decision, action, result | **3** | **no audit store at all** |
| AS-06 | Agentic security QA gate (injection, privilege escalation, memory poisoning, runaway, containment, recovery) | **3** | prompt-injection testing not evidenced |
| AS-07 | Guardian within deterministic governance; recommendation ≠ enforcement | **5** | design principle; no implementation |
| AS-08 | Least privilege enforced **at runtime** for every agent/skill/tool | **3** | — |
| AS-09 | Separate model reasoning from authorized execution; explicit authorization at execution boundaries | **5** | — |
| AS-10 | Human approval for high-impact/destructive/financial/permission/credential/migration/irreversible actions | **5** | mirrors this programme's own governance; not a product control yet |
| AS-11 | Provenance, versioning, integrity checks, rollback for agentic skills and dependencies | **3** | — |
| AS-12 | Validate skill metadata/manifests; isolate risky execution | **3** | — |
| AS-13 | Deterministic emergency disablement + recovery | **3** | — |

### 2f · Security assurance, SBOM & control mapping (V5)

| ID | Requirement | Class | Evidence |
|---|---|---|---|
| SA-01 | **OWASP ASVS 5.0.0** as formal verification baseline, version-qualified identifiers | **3** | 0 ASVS references |
| SA-02 | OWASP mobile + API guidance mapped per surface (mobile, web/admin, backend, APIs/RPCs, wearable, partner) | **3** | no surface-to-control mapping |
| SA-03 | **Control evidence**: requirement, implementation location, test evidence, result, date/version, exception, owner. *"A generic statement that a control 'passes' is insufficient"* | **2** | this QA programme's evidence discipline already matches the spirit; **no formal matrix exists** |
| SA-04 | **Versioned CycloneDX SBOM** for application, build, runtime, third-party components | **3** | **SBOM ABSENT**; `cyclonedx` appears only in my own QA reports; tooling not installed |
| SA-05 | Release pipeline uses SBOM as release evidence; component diffs reviewable; vuln/licence/provenance/policy checks | **3** | **0 security-scan steps** in 7 CI jobs |
| SA-06 | SBOM retained with the release record; integrity/signing + verification | **3** | no release record artefact |
| SA-07 | **OWASP OpenCRE** crosswalk between requirements and standards | **3** | 0 references |
| SA-08 | **12Circle Security Assurance Matrix** — control → source → owner → test → evidence → status → gate, across mobile/web/API/wearable/Guardian/skills/data/supply-chain | **3** | does not exist |
| SA-09 | Guardian/Admin may consume security-assurance evidence as an operational signal | **3** | depends on SQ-11 + AD-01 |
| SA-10 | Security QA gate evaluates ASVS, mobile/API, agentic, AST10, supply-chain, **authorization/RLS**, privacy, evidence completeness | **2** | authorization/RLS + privacy are strong; the rest absent |
| SA-11 | **Release-integrity chain**: source revision → component inventory → SBOM → control verification → build artifact → deployment record → runtime monitoring | **3** | chain broken at component inventory onward |
| SA-12 | Identify exact standard/version used; final audit verifies current guidance | **3** | — |
| SA-13 | Release gate: *green tests alone are not security-ready* | **1** | **already this programme's stated position** — 90.0% with open findings, explicitly not a compliance claim |

**Total requirements inventoried: 64.**
**Classification distribution:** EXISTS **6** · PARTIALLY EXISTS **18** · NOT IMPLEMENTED **26** ·
CONFLICTS **1** · REQUIRES ARCH DECISION **9** · BLOCKED BY QA **3** · V5 AMBIGUOUS **2** ·
NOT CURRENTLY EVIDENCED **9**. *(Primary classification per requirement; several carry a
secondary.)* **Gaps = the 58 that are not EXISTS.**

## 3 · CURRENT-STATE RECONCILIATION

Verified at `07f5bfb`, not assumed:

| Area | Verified current state |
|---|---|
| Mobile | Flutter, **341 Dart files, 34 features, 91 GoRoutes**; `go_router`; Riverpod |
| API | **Thin NestJS** — 35 TS files, 4 modules (`config`, `auth`, `ai`, `users`) |
| Database | **91 public tables**, 134 FKs, 5 views; 132 migrations contiguous 000–131 |
| Auth | Supabase Auth; **5 roles** — `admin`, `client`, `coach`, `vendor`, `content_manager` |
| Authorization | RLS on **91/91**; 0 zero-policy; 0 anon grants; 0 mutable `search_path`; `admin` **not self-assertable**, `coach`/`vendor` **are** |
| Edge functions | **19** (6 AI, 5 enrichment, 5 Stripe, 3 messaging) |
| AI | 6 `ai_*` tables all RLS-enabled; **no server-side entitlement check** (K-03) |
| Admin | **3 screens**, 4 SECURITY DEFINER fns, 2 migrations |
| **Trust** | **DOES NOT EXIST** — 0 files, 0 design mentions |
| **Audit** | **NO infrastructure** — no audit table under any name; zero audit writes |
| Notifications | `notifications` + `may_notify()` — filters status on **no** anchor |
| Workflows | no orchestration engine |
| CI/CD | 7 jobs; 3 executed, 2 passed, **1 failed**, 4 never executed; **0 security scans** |
| Testing | mobile 1,675/9 · API 64 · contract PASS · security+AI **BLOCKED** |
| Design system | **local only**; no shared design-system dependency |
| **Wearable** | **connector/consent only** — `user_integrations` + `integrations_screen.dart` (7 providers) |
| Feature flags | **0 files** |
| Observability | `app_failure.dart` + `decision_traces` dir; **0 DB observability tables** |

## 4 · QA ↔ V5 RECONCILIATION

| Finding | V5 touches the area? | V5 depends on the behaviour? | V5 needs the boundary? | Remediate first? | Safe during V5 impl? | New security dependency? | New authz boundary? | New audit requirement? |
|---|---|---|---|---|---|---|---|---|
| **QAX-SEC-08** (P0) | **YES** — Coach↔Client ecosystem (SQ-02), Admin roles (AD-02), wearable role visibility (WI-14/17) | **YES** — team membership gates PHI | **YES** | **YES — before any feature reading `user_profiles` via team membership** | **NO** for team/roster work; yes elsewhere | **YES** — wearable health data would join the same PHI surface | **YES** | **YES** |
| **F-03b** (P1) | **YES** — Guardian alerting (AG-01), Admin notifications | **YES** — `may_notify` governs who can notify | **YES** | **YES if Guardian/Admin emits notifications** | conditional | **YES** | **YES** | **YES** |
| **QAX-SEC-09** (P1) | **YES** — **Wellness Partner** persona (SQ-02/SQ-07), partner APIs (WI-18) | **YES** — vendor↔attendee disclosure is the partner model | **YES** | **YES — V5 expands the vendor/partner role** | **NO** | **YES** | **YES** | **YES** |
| **SEC-PHI-9** (P1) | **YES** — wearable health data is the same PHI class | **YES** — relationship-status revocation | **YES** | **YES — the pattern would be inherited by wearable authz** | **NO** | **YES** | NO (existing) | **YES** |
| **SEC-PHI-10** (P1) | **YES** — same status-predicate class | **YES** | **YES** | **YES** | **NO** | **YES** | NO | **YES** |
| **SEC-AI-1** (P1) | **YES** — AI Guardian (SQ-11), AI governance (AS-01…13), AI disclosure | **YES** | **YES** | **YES — V4/V5 formalise AI governance** | **NO** | **YES** | **YES** | **YES** |
| **NEW-2** | YES — programme/assignment data | YES | YES | recommended | YES | NO | NO | YES |
| **NEW-5** (`SEC_PHI_1` non-functional) | YES — any column-limited Admin view | **YES — V5's Admin needs exactly this view pattern** | YES | **YES — do not apply it as written** | YES | NO | YES | NO |
| **NEW-7** (3 stale skips) | YES — monetization QA (SQ-04) | NO | NO | NO | YES | NO | NO | NO |
| **NEW-8 / QAT-1** | **YES — SQ-26 requires CI security verification** | YES | NO | **YES — CI is a V5 release gate** | YES | NO | NO | NO |
| **NEW-9** (live-QA never ran) | **YES — SQ-24 E2E journeys** | YES | NO | **YES** | YES | NO | NO | NO |
| **NEW-3** | YES — community/moderation Guardian | NO | NO | NO | YES | NO | NO | YES |
| **6 open K specs** | **YES — SQ-04/SQ-14 monetization + Monetization Guardian** | **YES — payment→entitlement consistency is a Guardian domain** | **YES** | **YES for the Monetization Guardian domain** | partial | **YES** | **YES** (K-04) | **YES** |
| **SBOM absent** | **YES — SA-04/05/06/11 make it a release gate** | **YES** | — | **YES** | NO | **YES** | NO | **YES** |
| **No audit infra** | **YES — AG-04, AD-03, AS-05, SA-03** | **YES** | **YES** | **YES** | **NO** | **YES** | **YES** | **it *is* the requirement** |

### The 12-item remediation queue vs V5

| # | Item | V5 elevates it? | Why |
|---|---|---|---|
| 1 | `coach_team_members` `WITH CHECK` | **YES** | gates P0 + F-03b; team semantics are an ecosystem contract (SQ-02) |
| 2 | Correct `SEC_PHI_1` | **YES** | V5's Admin requires column-limited views; the proposal is non-functional as written |
| 3 | QAT-1 / ENV-5 | **YES** | SQ-26 requires CI/release verification; the gate is currently red |
| 4 | `workout_program_assignments` | YES | programme data feeds Training Alignment (WI-07) |
| 5 | SEC-PHI-9/10 status predicate | **YES** | the pattern wearable authorization would inherit |
| 6 | Unskip K-12/K-ENV-1; review K-09 | YES | monetization QA evidence |
| 7 | 6 open K specs | **YES** | Monetization Guardian domain depends on this consistency |
| 8 | CI secrets | **YES** | SQ-24 E2E journeys cannot run without them |
| 9 | Guard rework | YES | SQ-08 automated QA |
| 10 | Supply chain (SBOM, 7 high, Dart scan) | **YES — hard gate** | SA-04/05/06/11 |
| 11 | Branch protection | **YES** | SA-11 release-integrity chain |
| 12 | Three QA fixtures | **YES** | SQ-07/SQ-16 personas + data realism |

**All 12 are elevated by V5. None was remediated.**

## 5 · ARCHITECTURE ↔ V5

| Area | Current | V5 target | Gap | Dependency | Decision required |
|---|---|---|---|---|---|
| Mobile | 341 files, 91 routes | + wearable UX, Admin/Trust surfaces, feature flags | large | design artefacts | D6, D-V2 |
| API | thin NestJS, 4 modules | wearable platform API/SDK, partner APIs, tenancy | **very large** | WI-11/16/18 | **D5, D-V1** |
| Database | 91 tables | + wearable raw/derived + audit + incidents + flags + assurance matrix | **very large** | §6 | D4, D-V3 |
| Auth | Supabase Auth, 5 roles | + partner/tenant identity, agent identity (AS-05) | medium | — | D-V4 |
| Authorization | RLS on 91/91 | + wearable authz, partner scoping, agent least privilege at runtime | large | P0 chain | D1, AS-08 |
| RLS | mature | extend to every new table | medium | migrations 132+ | D3 |
| Edge functions | 19 | + ingestion/normalization; or a separate service | large | WI-05/06 | **D-V1** |
| AI | 6 tables, no entitlement check | Guardian, governance, AST10, audit | **very large** | D9, D10 | AS-* |
| Admin | 3 screens | Control Center, 13 domains | **very large** | audit first | D4, D7 |
| Trust | **none** | AI Guardian · Security · Incidents · Audit Logs | **very large** | audit first | **D11** |
| Audit | **none** | audit events everywhere + agent action trail | **very large** | — | **D4, D12** |
| Notifications | `may_notify` forgeable | Guardian-driven alerting | medium | **F-03b** | D1 |
| Workflows | none | ingestion, retries, jobs, escalation | large | WI-05 | D-V1 |
| CI/CD | 7 jobs, 1 red, 0 scans | + SBOM, security scans, release-integrity chain | large | QAT-1 | D13, D14 |
| Testing | 3 of 5 tiers verified | + wearable, agentic security, a11y, performance, DR | large | egress, fixtures | D15 |
| Design system | local theme | governed components/tokens/states/a11y | medium | — | **D16** |

## 6 · DATABASE IMPACT INVENTORY (no migrations written)

| Need | Driven by | Detail |
|---|---|---|
| **New tables** | WI-08, AG-04, AS-04/05, SA-08, SQ-14 | wearable raw observations · canonical/normalized records · derived metrics · device/connection state · sync state · data-quality records · **audit events** · **incidents** · agent/skill inventory · agent action log · feature flags · security-control matrix · SBOM/release records · observability metrics |
| **New columns** | WI-09, WI-03 | provenance (source, calculation version, quality) on every derived metric; extend `user_integrations` for scopes/consent |
| **New relationships** | WI-17, WI-18 | observation → user → workout/session; partner/tenant → integration |
| **New indexes** | WI-10 | time-series on (user, timestamp); high-write ingestion paths |
| **New constraints** | WI-22 | impossible/duplicate observation rejection; ordering guarantees |
| **New enums** | AG-05, AG-02 | severity (Critical/High/Warning/Informational); autonomy level (L0–L3); provider; observation type |
| **New RLS policies** | WI-14, AG-04, AS-05 | every new table — health data is PHI-class; **audit records must not be editable by their subject** |
| **New authorization helpers** | WI-14, WI-18 | wearable-data access; partner/tenant scoping. **Must not repeat the status-less pattern of `is_team_lead_of()`** |
| **New triggers** | WI-09, AG-04 | provenance stamping; audit emission |
| **New functions** | WI-07 | zone calculation (**version-pinned** — regression-sensitive per WI-24) |
| **New migrations** | all | numbers **132+**, *"assigned at wave entry, never before"* |
| **Data migration/backfill** | WI-03 | existing `user_integrations` rows into the new connector model |
| **Audit records** | AG-04, AS-05, SA-03 | the largest single addition — a write path at **every** audit-worthy action |

**27 requirements carry database impact.** No schema was designed, and no migration number was
assigned.

## 7 · SECURITY IMPACT

**31 requirements are security-impacting.** The security-first review, per V5 feature class:

| Feature class | Who can access | Sensitive data | Role/permission | Must be audited | Abuse potential | QA finding affected |
|---|---|---|---|---|---|---|
| **Wearable observations** | owner; coach?; partner?; admin? — **V5 AMBIGUOUS** | **health data — PHI class** (HR, zones, intensity) | new helper needed | ingestion, access, export, deletion | continuous physiological surveillance of a member | **SEC-PHI-9/10 pattern would be inherited** |
| **Coach-facing live intelligence** | active coach only? former coach? | PHI | `is_active_coach_of` | access | **a `cancelled` coach retaining live HR access is SEC-PHI-9 repeated on live data** | SEC-PHI-9 |
| **Partner APIs** | approved partners/tenants | PHI + PII | tenancy model absent | all access | cross-tenant leakage | **QAX-SEC-09** |
| **Admin Control Center** | `admin` | everything incl. PHI | `is_admin()` — **sound, not self-assertable** | **every admin action** | broad PHI read with no trail | AD-03 |
| **Role assignment** | admin | privilege | `admin_set_user_role()` | **currently writes NO audit record** | silent privilege escalation | AD-03 |
| **AI Guardian** | agent identity | telemetry + PHI-adjacent | agent least privilege (AS-08) | **every material action** (AS-05) | prompt injection; runaway; over-privilege | **SEC-AI-1** |
| **Guardian L2 autonomous actions** | agent | production state | allowlist + reversibility | approval + result | an over-broad allowlist becomes an unaudited production actor | AS-10 |
| **Notifications/alerting** | Guardian → users | content | `may_notify` | delivery | **F-03b makes `notifications` INSERT forgeable today** | **F-03b** |
| **Incidents** | admin/Guardian | evidence incl. PHI | none exists | creation, state change | evidence tampering | AG-04 |
| **Feature flags** | admin/Guardian L2 | — | none exists | every toggle | disabling a security control via a flag | AG-03 |
| **Monetization/entitlement** | member | payment | entitlement checks | grants, refunds | **K-04: self-granted paid registration (live-confirmed)** | 6 K specs |
| **Team relationships** | any authenticated | **PHI via chain** | **none — `has_role_check = false`** | membership changes | **the P0** | **QAX-SEC-08** |

**The single most important security observation:** V5 introduces **continuous physiological
data** (heart rate, zones, intensity) into a system whose **two verified PHI-boundary defects are
exactly about relationship status not being checked** (SEC-PHI-9 verified live, SEC-PHI-10
inferred) and whose **P0 lets any authenticated account become a "team lead" and read PHI**.
Wearable data would land on that surface. **Recorded, not remediated.**

## 8 · ADMIN IMPACT

| V5 Admin requirement | Current | Required build surface |
|---|---|---|
| Control Center over 13 domains | 3 screens | 10+ new surfaces; most need new data stores first |
| Health / database / releases / analytics domains | none | observability foundation (SQ-10) **first** |
| Users / roles domain | `admin_recent_users()`, `admin_set_user_role()` | list/filter/detail surfaces; **column-limited PHI views — and NEW-5 shows the existing proposal for that pattern is non-functional** |
| Payments domain | Stripe fns | reconciliation surface; **blocked by 6 open K specs** |
| AI domain | 6 `ai_*` tables | Guardian surfaces |
| Wearables domain | `user_integrations` only | depends on the whole WI stack |
| Incidents domain | **nothing** | new table + RLS + surface |
| **Audit domain** | **nothing** | **write path at every audit-worthy action — the deepest dependency** |
| Operational roles/permissions | 5 roles; `content_manager` unserved | decide whether ops roles are new roles or scoped admin |

## 9 · TRUST IMPACT

Current: **Trust does not exist** — 0 implementation files, 0 design mentions in the repo.

| Trust area | Existing substrate | Gap |
|---|---|---|
| **AI Guardian** | `ai_reviews`, `ai_insights`, `explain-decision` edge fn, `decision_traces` dir | the entire Guardian runtime, 8 domains, autonomy model, allowlists, approval gates, emergency disablement |
| **Security** | RLS state is introspectable from the catalog (this programme did exactly that) | **no product-facing store** — the app cannot read `pg_policies`; a security posture surface needs its own evidence store |
| **Incidents** | none | table, RLS, severity enum, evidence model, approval workflow, false-positive loop |
| **Audit Logs** | **none — and the data was never written** | **cannot be built as a view over existing data.** Requires a new write path at every audit-worthy action, touching schema, RLS, and every privileged mutation |

## 10 · AI IMPACT

| V5 requirement | Current | Gap |
|---|---|---|
| Guardian: 8 domains, L0–L3 autonomy | no agent runtime | entire build |
| AST10 evaluation per skill | 0 artefacts | inventory + evaluation + gate |
| Agent action audit trail | **no audit store** | blocked on D4 |
| Least privilege at runtime | — | runtime enforcement model |
| Recommendation ≠ enforcement | — | deterministic boundary |
| Emergency disablement not disabling core security | RLS is enforced in Postgres, structurally independent of an app-layer agent | verify as a designed control (AG-03) |
| Existing AI entitlement | **K-03: 0 `active_membership`/`client_plan` in all three sold AI functions** | server-side entitlement (D9) |
| AI disclosure posture | SEC-AI-1 open | owner decision (D10) |

## 11 · DESIGN IMPACT

**The Admin/Trust designs referenced in the brief are not in this repository** — measured: 0
mentions of "Trust", "AI Guardian" or "Incidents" across all seven design documents. **I cannot
reconcile designs I cannot see, and I have not invented them.**

What can be stated from repository evidence:

| Design reality | Evidence | Implication |
|---|---|---|
| 45 routes with design, **46 without** | `FINAL_SCREEN_INVENTORY.json` | roughly half the existing surface has no design frame |
| 287 interactions present vs **600 declared** | same | large declared-vs-built delta |
| 110 fit anchors: 19 complete, 56 partial, **32 zero coverage** | same | — |
| 7 orphan routes, 6 unreachable anchors | same | — |
| **"174 approved screens" not corroborated** | 91 routes / 148 surfaces | **CONF-01** |
| Governing rule already defined | *"A designed anchor that is unimplemented is an IMPLEMENTATION gap, not a missing screen. A required surface with no design frame is a DESIGN COMMISSION."* | V5's SQ-23 should adopt this existing rule |
| Error-state constraint | ERR-G2 — 38 raw-exception sites closed; admin console **parses** `42501` rather than displaying | any new Admin/Trust error state must not print raw exceptions |

## 12 · API IMPACT

Current API is a **thin 4-module NestJS service** and is **not** the primary data path — mobile
talks directly to Supabase. V5 requires a **wearable platform API/SDK with stable contracts,
versioning, tenancy/isolation and usage telemetry** (WI-11/16/18), plus partner APIs.

**This is the single largest architectural question in V5** (D-V1): the wearable platform must be
independently deployable and must not depend on 12Circle+ screens — which the current
direct-to-Supabase mobile architecture does not accommodate. Options exist (expand NestJS · new
service · separate repo + SDK) but **the evidence does not select one**, so no choice is made here.

## 13 · MOBILE IMPACT

| Requirement | Impact |
|---|---|
| Wearable live UX (connection, permissions, live HR, zones, workout context, post-workout, errors, disconnected, data-quality states) | **new** — `integrations_screen.dart` covers connection only |
| Consume the platform via contracts, **not** duplicated logic (WI-06) | constrains where wearable logic may live |
| Coach + client live/historical surfaces | new |
| Admin/Trust surfaces (if in-app — **D6 unresolved**) | potentially very large |
| Feature flags | **0 files** today |
| Real-time path | no realtime channel evidenced |
| Existing constraints | 2 dead duplicate screens (DEAD-G1); ERR-G2 error-copy rules; 34 providers never consumed |

## 14 · CI/CD IMPACT

| V5 requirement | Current | Gap |
|---|---|---|
| Security scans in CI (SQ-26) | **0 scan steps** in 7 jobs | add; but see NEW-8 |
| SBOM generation + validation + diffing (SA-04/05) | **none** | new pipeline stage; **tooling not installed** |
| Release-integrity chain (SA-11) | broken after source revision | build/deployment records, signing |
| E2E journey evidence (SQ-24) | 4 jobs **never executed** | CI secrets (NEW-9) |
| Reproducible builds, signing, artifacts (SQ-26) | not evidenced | — |
| Backup/restore/DR (SQ-27) | **0 files**; free tier, **no PITR** | — |
| Release/rollback drill (SQ-28) | no drill evidence | — |
| Gate reliability | **ENV-5 fails at step 1 and blinds 6 gates** (all 6 verified passing locally) | D13 |
| Branch protection | **unverified** — GitHub unreachable | D14 |

## 15 · ARCHITECTURAL DECISION RECONCILIATION

### Carried decisions D1–D17

| ID | V5 affected? | V5 resolves it? | Still unresolved? | Owner |
|---|---|---|---|---|
| D1 team semantics | **YES** — SQ-02 ecosystem contract | **NO** | **YES** | **YES** |
| D2 self-assertable coach/vendor | **YES** — Wellness Partner + partner APIs | **NO** | **YES** | **YES** |
| D3 uniform status predicate | **YES** — wearable authz inherits it | **NO** | **YES** | YES |
| **D4 audit log + audit-worthy actions** | **YES — V5 requires it in four places** (AG-04, AD-03, AS-05, SA-03) | **PARTIALLY — V5 establishes the requirement but not the schema or granularity** | **YES** | **YES** |
| D5 Admin via API or direct Supabase | **YES** | **NO** | **YES** | **YES** |
| D6 Admin/Trust in-app or separate | **YES** | **NO** | **YES** | **YES** |
| D7 Users/Coaches/Clients modules or views | **YES** — AD-01 | **NO** | **YES** | **YES** |
| D8 `content_manager` surface | YES | **NO** | **YES** | YES |
| D9 server-side AI entitlement | **YES** — Monetization Guardian | **YES — V4/V5 require deterministic authorization at execution boundaries** | **resolved in principle; implementation open** | YES |
| D10 AI disclosure | **YES** | **NO** | **YES** | **YES** |
| **D11 Trust scope** | **YES — V5 defines it**: AI Guardian · Security · Incidents · Audit Logs | **LARGELY YES** | scope resolved; **build unresolved** | YES |
| D12 audit read/immutability/retention | **YES** | **PARTIALLY** — retention/privacy referenced, specifics absent | **YES** | **YES** |
| D13 `static-guards` fail-late | YES — SQ-26 | **NO** | **YES** | YES |
| D14 branch protection | YES — SA-11 | **NO** (implied) | **YES** | YES |
| D15 guard population from live catalog | YES | **NO** | **YES** | YES |
| **D16 extract shared design system** | **YES — SQ-05 component governance** | **NO** | **YES** | **YES** — note the standing directive: *extract on the second product, not the first*; **V3's standalone wearable platform may itself be that second product** |
| D17 fix `SEC_PHI_1` before applying | **YES** — Admin needs the view pattern | **NO** | **YES** | YES |

### New decisions created by V5

| ID | Cat | Question | Why it matters | Owner |
|---|---|---|---|---|
| **D-V1** | API/ARCH | **Where does the wearable platform live** — expand NestJS, new service, or separate repo + SDK? | WI-01/16 require independent deployability; current mobile is direct-to-Supabase | **YES** |
| **D-V2** | DATA | Does the wearable platform share this Postgres instance or own its store? | tenancy, isolation, RLS reuse, partner exposure | **YES** |
| **D-V3** | DATA | Canonical observation + derived-metric contract, and the provenance/version model | WI-08/09; regression-sensitive zones (WI-24) | **YES** |
| **D-V4** | SECURITY | Who may see a member's wearable data — active coach only, partners, admin? | it is PHI-class and lands on a surface with 2 verified boundary defects | **YES** |
| **D-V5** | SECURITY | Agent identity model for the audit trail (AS-05) | an agent action must be attributable | **YES** |
| **D-V6** | CI/CD | SBOM toolchain and where it runs | SA-04/05/06; tooling absent and installation currently forbidden | **YES** |
| **D-V7** | GOVERNANCE | **Resolve CONF-01 — is the protected baseline 174, or 91 routes / 148 surfaces?** | it is a *non-negotiable* governance rule resting on an uncorroborated number | **YES** |

**Total: 24 decisions (17 carried + 7 new). No decision was made in this mission.**

## 16 · V5 CONFLICT REGISTER

| ID | Conflict | Evidence | Impact | Options | Owner | Status |
|---|---|---|---|---|---|---|
| **CONF-01** | **V5 vs repository:** "Protect the 174 approved existing screens" | inventory: **91 routes, 89 release, 148 surfaces**; no 174 | a non-negotiable rule rests on an unverifiable baseline | (a) 174 counts a different unit — reconcile definitions; (b) restate the rule against the 148/91 inventory; (c) produce the 174 list | **Owner** | **OPEN** |
| **CONF-02** | **V5 vs its own identity:** document title says *"V1 MASTER … VERSION 2"*; filename and handoff say **V5** | title vs filename | version-qualified traceability is itself a V5 requirement (SA-01/SA-12) | clarify canonical name/version | **Owner** | **OPEN** |
| **CONF-03** | **V5 vs QA:** SBOM required as release evidence (SA-04/05/06) | SBOM **ABSENT**; tooling not installed; installation currently forbidden | release gate unmeetable today | authorize tooling, or govern as an accepted risk | **Owner** | **OPEN** |
| **CONF-04** | **V5 vs architecture:** wearable must be independently deployable and not depend on 12Circle+ screens | mobile is **direct-to-Supabase**; API is thin (4 modules) | the largest structural change in V5 | **D-V1** | Architecture | **OPEN** |
| **CONF-05** | **V5 vs database:** audit/agent-action evidence required in 4 places | **no audit table anywhere; zero audit writes** | blocks Trust → Audit Logs, Admin audit, agent trail | **D4, D12** | Architecture + Owner | **OPEN** |
| **CONF-06** | **V5 vs security model:** V5 expands the **Wellness Partner / vendor** role | `role='vendor'` is **self-assertable at signup**; QAX-SEC-09 open; 0 vendor users; `events.vendor_id` NULL | partner APIs would build on an unhardened, untested role | **D2** | **Owner** | **OPEN** |
| **CONF-07** | **V5 vs existing Admin:** Control Center over 13 domains | Admin = **3 screens**; column-limited view pattern **non-functional as proposed (NEW-5)** | Admin is effectively greenfield | D5, D7, D17 | Architecture | **OPEN** |
| **CONF-08** | **V5 vs existing design:** Admin/Trust designs assumed to exist | **0 mentions of Trust/AI Guardian/Incidents** in 7 design docs | design↔system reconciliation cannot be performed | supply the artefacts or commission | **Owner** | **OPEN** |
| **CONF-09** | **V5 vs CI/CD:** security scans, SBOM, release-integrity chain, E2E journey evidence | 7 jobs, **0 scans**, 1 red gate blinding 6, **4 jobs never executed** | release gates unmeetable today | D13, D14, NEW-9 | Architecture | **OPEN** |

**No conflict was resolved.** V5's own governance rule GV-02 requires exactly this treatment.

## 17 · V5 DEPENDENCY GRAPH

```
CONF-01/02 (governance baseline)  ──► gates what "protected" and "V5" even mean
        │
D4 AUDIT SCHEMA  ◄── the deepest dependency; 4 V5 requirements need it
        │
        ├──► Admin audit domain ──► Admin Control Center (13 domains)
        ├──► Incidents ──────────► Trust → Incidents
        ├──► Agent action trail ─► AI Guardian (AS-05) ──► Guardian QA
        └──► Trust → Audit Logs
OBSERVABILITY FOUNDATION (SQ-10)  ──► Admin health/analytics ──► Release Guardian
        │
P0 (coach_team_members) ──► is_team_lead_of ──► user_profiles PHI
        │                └──► may_notify ──► notifications ──► Guardian alerting (F-03b)
        └──► SEC_PHI_1 view pattern (NEW-5) ──► Admin column-limited views

WEARABLE  (D-V1 boundary ──► D-V2 store ──► D-V3 contract)
   Connector (PARTIAL: user_integrations, 7 providers)
        └──► Ingestion ──► Normalization ──► Intelligence (zones, Training Alignment)
                   │              │
                   │              └──► provenance + calculation version (WI-09/24)
                   └──► Storage ──► RLS/authz (D-V4) ──► API/SDK (WI-11)
                                   └──► Mobile coach+client surfaces
                                   └──► Partner APIs (needs tenancy; CONF-06)
                                   └──► Admin/Guardian wearable telemetry
SUPPLY CHAIN: SBOM tooling (D-V6) ──► CI stage ──► release-integrity chain (SA-11)
                                              └──► requires QAT-1 fixed + branch protection
TESTING: CI secrets (NEW-9) ──► E2E journeys (SQ-24); egress ──► security/AI tiers
```

**Critical path:** `CONF-01/02 → D4 audit schema → observability → Admin/Trust/Guardian`, and in
parallel `D-V1 wearable boundary → D-V2/D-V3 → the rest of the wearable stack`. **The P0 fix
gates any feature reading PHI through team membership.**

## 18 · IMPLEMENTATION PHASING (proposed sequence, dependency-derived — no dates)

Only phases the evidence supports. **No date, duration or story point is assigned; V5 defines none.**

| Phase | Contents | Entry condition |
|---|---|---|
| **P0 · GOVERNANCE** | Resolve CONF-01, CONF-02; confirm protected baseline; assign wave migration numbers 132+ | owner decisions |
| **P1 · FOUNDATION / SECURITY** | Queue items 1–5: `coach_team_members` `WITH CHECK` (closes P0 + F-03b); corrected `SEC_PHI_1`; status predicates; `workout_program_assignments` | D1, D3, D17 |
| **P2 · DATA (AUDIT + OBSERVABILITY)** | Audit event schema + RLS (audit not editable by its subject); incidents; observability store | **D4, D12** |
| **P3 · BACKEND** | Wearable platform boundary; ingestion/normalization; canonical contracts | **D-V1, D-V2, D-V3** |
| **P4 · CORE PRODUCT** | Intelligence layer (zones, workout context, Training Alignment); provenance + calculation versioning | P3 |
| **P5 · ADMIN** | Control Center over the 13 domains, on P2's stores | P2, D5–D7 |
| **P6 · TRUST** | Security · Incidents · Audit Logs surfaces | P2, P5, D11 |
| **P7 · AI GUARDIAN** | 8 domains, autonomy L0–L3, allowlists, approval gates, emergency disablement, agent audit trail | P2, P6, AS-*, D-V5 |
| **P8 · MOBILE** | Wearable UX + states; Admin/Trust surfaces if in-app; feature flags | P4, D6, designs |
| **P9 · INTEGRATION** | 12Circle+ consumes the platform via contracts; partner APIs + tenancy | P3–P8, CONF-06 |
| **P10 · QA & SUPPLY CHAIN** | Wearable QA, agentic security QA, a11y, performance, SBOM + release-integrity chain, DR/rollback drills | D-V6, CI secrets, egress |

**Monetization (SQ-04/SQ-14) runs alongside P1–P2**, because its 6 open K specs are entitlement
defects and K-04 is a live-confirmed authorization defect.

## 19 · IMPLEMENTATION READINESS MATRIX

| V5 area | Readiness |
|---|---|
| Governance baseline | **BLOCKED BY V5 AMBIGUITY** (CONF-01, CONF-02) |
| Security foundation (queue 1–5) | **READY FOR IMPLEMENTATION ANALYSIS** — blocked on decision D1 for build |
| Audit / observability | **BLOCKED BY DECISION** (D4, D12) |
| Wearable platform | **BLOCKED BY ARCHITECTURE** (D-V1, D-V2, D-V3) |
| Wearable client UX | **BLOCKED BY MISSING DESIGN** |
| Admin Control Center | **BLOCKED BY DECISION + MISSING DESIGN** (D5–D7, CONF-08) |
| Trust | **BLOCKED BY DECISION + MISSING DESIGN** (D11, CONF-08) |
| AI Guardian | **BLOCKED BY ARCHITECTURE** (audit + observability first) |
| AI entitlement (K-03) | **READY FOR IMPLEMENTATION ANALYSIS** |
| Monetization / K specs | **READY FOR IMPLEMENTATION ANALYSIS** |
| Partner / Wellness Partner | **BLOCKED BY QA** (QAX-SEC-09) **+ DECISION** (D2) |
| Feature flags | **READY FOR IMPLEMENTATION ANALYSIS** |
| SBOM / supply chain | **BLOCKED BY EXTERNAL DEPENDENCY** (tooling authorization) |
| CI/CD gates | **READY FOR IMPLEMENTATION ANALYSIS** (QAT-1, D13) |
| E2E journeys | **BLOCKED BY EXTERNAL DEPENDENCY** (CI secrets, egress) |
| Design system governance | **BLOCKED BY DECISION** (D16) |
| Backup / DR / rollback drills | **BLOCKED BY EXTERNAL DEPENDENCY** (free tier, no PITR) |

**The product as a whole is NOT ready for implementation.** Four areas are ready for
*implementation analysis* only.

## 20 · OPEN QUESTIONS

1. Is the protected baseline 174, or the inventory's 91 routes / 148 surfaces? (CONF-01)
2. Is this document "V5" or "V1 Master Version 2+amendments"? (CONF-02)
3. Where does the wearable platform live, and does it share this database? (D-V1/D-V2)
4. Who may read a member's wearable health data? (D-V4)
5. What is audit-worthy, and what are audit retention/immutability rules? (D4/D12)
6. Are Admin/Trust in the Flutter app or a separate surface? (D6)
7. Does the Wellness Partner role get hardened before partner APIs? (D2/CONF-06)
8. Is the standalone wearable platform the "second product" that triggers design-system extraction? (D16)
9. What agent identity appears in the audit trail? (D-V5)
10. Which wearable providers are in V1 scope — all 7 already named, or a subset? (**V5 AMBIGUOUS**)
11. Does "Wellness Partner" equal the existing `vendor` role, or a new role? (**V5 AMBIGUOUS**)
12. Where do the Admin/Trust design artefacts live? (CONF-08)

## 21 · OWNER DECISIONS REQUIRED

**Owner:** CONF-01, CONF-02, CONF-03, CONF-06, CONF-08 · D1, D2, D4, D5, D6, D7, D10, D11, D12,
D16 · D-V1, D-V2, D-V3, D-V4, D-V5, D-V6, D-V7.
**Architecture:** CONF-04, CONF-05, CONF-07, CONF-09 · D3, D8, D9, D13, D14, D15, D17.

## 22 · ITEMS BLOCKED BY QA

| Item | Blocking finding |
|---|---|
| Partner / Wellness Partner APIs | **QAX-SEC-09** (untestable: `events.vendor_id` NULL) |
| Any feature reading PHI via team membership | **QAX-SEC-08** (P0) |
| Guardian/Admin notification emission | **F-03b** |
| Wearable authorization design | **SEC-PHI-9 (verified)** + **SEC-PHI-10** — the pattern it would inherit |
| Admin column-limited PHI views | **NEW-5** — the proposal is non-functional as written |
| Monetization Guardian domain | **6 open K specs**, incl. live-confirmed **K-04** |
| AI governance | **SEC-AI-1**, **K-03** |
| Full data realism (SQ-31) | fixture writes **declined** |
| E2E journeys (SQ-39) | **NEW-9** + HTTPS egress |

## 23 · ITEMS BLOCKED BY ARCHITECTURE

Wearable platform boundary (CONF-04) · audit schema (CONF-05) · Admin Control Center
(CONF-07) · AI Guardian (needs audit + observability) · partner tenancy/isolation · release-integrity
chain (CONF-09) · observability foundation.

## 24 · ITEMS BLOCKED BY V5 AMBIGUITY

| Item | Ambiguity |
|---|---|
| Protected screen baseline | **174 vs 91/148** — CONF-01 |
| Document version identity | title vs filename — CONF-02 |
| Wearable commercialization | V5 explicitly defers packaging/pricing/legal/data-processing to the owner (WI-19) |
| Wellness Partner ↔ `vendor` | never equated in V5 |
| Wearable provider scope for V1 | V5 says "multiple sources", names none |
| "Applicable" ASVS/OWASP controls | V5 repeatedly scopes by *applicable* without defining applicability |
| Audit granularity | "material actions" undefined |
| Guardian L2 allowlist contents | only two examples given (retry a job, disable an approved flag) |

**Each is marked V5 AMBIGUITY — OWNER DECISION REQUIRED. None was invented or filled.**

## 25 · RECOMMENDED NEXT GATE

**V5 IMPLEMENTATION READINESS GATE.** Entry conditions, derived from this analysis:

1. **Resolve CONF-01 and CONF-02** — the governance baseline and document identity; everything
   labelled "protected" depends on them.
2. **Decide D4 (audit) and D12 (audit read/immutability/retention)** — four V5 requirements and
   three phases sit on it.
3. **Decide D-V1/D-V2/D-V3** — the wearable platform boundary, store and canonical contract.
4. **Supply the Admin/Trust design artefacts, or commission them** (CONF-08).
5. **Decide D1** (team semantics) so the P0 fix can be scheduled with a wave migration number.
6. **Rule on CONF-03** — authorize SBOM tooling or govern its absence as an accepted risk.
7. **Confirm the agentic build model** (below) and the workstream split.

### Agentic build architecture — preserved

The established agentic workflow continues. The responsibility model this programme has been
operating under, restated for V5:

| Layer | Responsibility |
|---|---|
| **V5** | **WHAT** we are building — the product specification |
| **Architecture** | **HOW** it should be structured |
| **Design** | how the product experience should work |
| **Implementation agents** | build only authorized work |
| **Security agents** | verify security controls — **independent of implementation** |
| **QA agents** | verify functional correctness |
| **Database agents** | verify data/migration safety |
| **Design QA** | verify UI against approved design |
| **Integration verification** | verify the system as a whole |
| **Governance** | controls what may be changed |

**No implementation agent may silently change product requirements. No agent independently
redefines V5.** Specialized agents will be required per phase in §18 — most acutely: a database
agent for P2/P3 (audit + wearable schema), an independent security agent for P1/P7 (the P0 chain
and agentic controls), and a design-QA agent once the Admin/Trust artefacts exist.

---

## FINAL ADVERSARIAL REVIEW

| Challenge | Outcome |
|---|---|
| 1. Read all of V5? | **Yes** — all 335 paragraphs / ~4,362 words; all four layers (V2 base + V3 + V4 + V5) |
| 2. Accounted for every major section? | **Yes** — §2a–2f map the source-of-truth hierarchy, 8 governance rules, 48-step sequence, Guardian domains, autonomy model, incident model, QA personas, value-adds, release gate, and all of V3/V4/V5 |
| 3. Invented a requirement? | **No.** Every row cites a V5 section; ambiguities are marked, not filled |
| 4. Invented an API? | **No.** The wearable API/SDK is recorded as **NOT IMPLEMENTED** with the boundary as an open decision (D-V1) |
| 5. Invented a database structure? | **No.** §6 is an impact *inventory*; no schema designed, no migration number assigned |
| 6. Assumed Trust exists? | **No** — 0 files, 0 design mentions, stated four times |
| 7. Assumed Audit Logs exist? | **No** — verified absent by live catalog sweep; recorded as the deepest dependency |
| 8. Assumed Admin functionality exists? | **No** — measured at 3 screens and 4 functions |
| 9. Ignored a QA finding? | **No** — all 6 P0/P1 and all 12 queue items mapped in §4 |
| 10. Remediated anything? | **No** — 0 code changes, 0 migrations, read-only DB access |
| 11. Altered architecture? | **No** |
| 12. Made an architectural decision without authority? | **No** — 24 decisions recorded as open; none taken |
| 13. Distinguished V5 requirements from implementation choices? | **Yes** — options are listed only where V5 or existing evidence supplies them (e.g. CONF-01 options); the phasing is labelled *proposed* |
| 14. Preserved UNKNOWN/ambiguous items? | **Yes** — §24 holds 8; V5's own deferral of commercial terms is preserved as WI-19 |
| 15. Preserved the agentic workflow? | **Yes** — §25 |
| 16. Identified where specialized agents are required? | **Yes** — §25, per phase |
| 17. Identified what must happen before implementation authorization? | **Yes** — §25's 7 entry conditions |
| *Extra:* did I treat the brief's Trust hierarchy as evidence? | **No** — it is reproduced only to record its absence, as in the prior transition document |
| *Extra:* did I let "174" pass unchallenged because V5 calls it non-negotiable? | **No** — measured against the repository and raised as CONF-01 |

---

*V5 Impact Analysis only. Implementation is NOT authorized. QA remains at 90.0% with 1 P0 and
4 P1 findings open. No code, schema, policy, CI, design or database change was made.*
