# V5 IMPLEMENTATION READINESS GATE

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** READ-ONLY governance gate. No implementation, no remediation, no mutation.

> **IMPLEMENTATION IS NOT PERFORMED IN THIS MISSION.** A GO result authorizes only the *next*
> controlled mission.

---

## 1 · EXECUTIVE SUMMARY

### FINAL DETERMINATION: **NOT READY FOR CONTROLLED V5 IMPLEMENTATION**

The standard applied is the one this gate sets: *can the product be built without silently
inventing requirements, architecture, security controls, data models, or design?* For the product
as a whole the answer is **no**, on four independent grounds:

1. **Audit does not exist and four V5 requirements depend on it.** No audit table under any name;
   zero audit writes. Trust → Audit Logs, the Admin audit domain, the agent action trail (V4 §5)
   and control evidence (V5 §3) all require it. Building any of them today means inventing the
   audit data model. **14 decisions must precede the first audit-dependent line of code** (§8).
2. **The Admin and Trust designs are not in this repository.** Measured: 0 mentions of Trust, AI
   Guardian or Incidents across all seven design documents. Implementing Admin/Trust now means
   inventing the design.
3. **The wearable platform boundary is undecided.** V3 requires an independently deployable
   product; the mobile app is direct-to-Supabase and the API is a thin 4-module service. Choosing
   the boundary is an architecture decision, not an implementation detail.
4. **The P0 is unremediated and gates the PHI surface** that V5's wearable health data would join.

### What this gate *did* resolve

**Gate 1 — the V5 naming conflict is nominal, not structural.** The document explicitly
establishes its own additive model in three dedicated rules: V3 §14, V4 §9, V5 §11 each state
that prior requirements remain in force and that the amendment supersedes only where it adds
specificity. **There is no internal contradiction that prevents implementation.** Only the
document's *name* needs owner confirmation. **CONF-02 downgraded: non-blocking.**

**Gate 2 — the 174-screen conflict is substantially resolved: the two numbers measure different
units.** `FINAL_SCREEN_INVENTORY.json` contains a `board_reconciliation` block (2026-09-24)
recording **`board_screens`: 156** and **`with_voice`: 169** — a *design-board* count. V5's own
source-of-truth hierarchy names "Approved Claude Design packages" as the design authority, so
"174 **approved** screens" refers to the **design board**, not repository routes. The repository's
91 routes / 148 surfaces measure implementation. **They were never the same unit.**

Supporting evidence: "174" appears **nowhere** in the repository as a screen count (all ten hits
are coincidental — a `1174` test total, `174 lines` of code, a session-id fragment). And the
discrepancy is **not staleness**: although `baseline_commit 0aa844a` is 76 commits behind HEAD,
its `routes: 91` matches a live count of 91 `GoRoute(` at `07f5bfb`.
**CONF-01 downgraded from "unverifiable baseline" to "the authoritative list lives outside the
repository."** A canonical approved-screen list remains a prerequisite.

### Counts

**9 V5 conflicts** (2 downgraded this gate, 0 closed) · **22 owner decisions** ·
**11 architecture decisions** · **1 P0 + 4 P1 carried forward, none closed or downgraded**.

**One workstream is specified well enough to authorize.** See §23.

## 2 · SOURCE-OF-TRUTH HIERARCHY

Established explicitly, per V5's GV-01/GV-02. **Conflicts are preserved, not reconciled.**

| Authority | Holder | Rank & rationale |
|---|---|---|
| **Product requirements** | **The attached V5 document** (V2 base + V3 + V4 + V5 amendments) | Sole product authority. Where it is silent or ambiguous, the answer is an **owner decision**, never an implementation choice |
| **Architecture** | **Not yet vested.** V5 states *recommended* separations (V3 §4); no architecture record exists for Admin, Trust, audit or the wearable boundary | **GAP** — the 24 open decisions are the missing architecture authority |
| **Security** | The QA security ledger + live database catalog | Strongest evidence layer. RLS on 91/91 tables, 0 anon grants, 0 mutable `search_path` — all catalog-verified. V4/V5 add OWASP/ASVS as the *target* baseline, which is **not yet adopted** |
| **QA** | `QA_COMPLETION_REPORT_2026-09-27.md` — **90.0%, QA COMPLETE WITH OPEN FINDINGS** | Authoritative on what is *verified*. Supersedes 78.9%/84%/90.5%/89.3% |
| **Design** | **Approved Claude Design packages — outside this repository** | The repo holds 7 design *reconciliation* documents and a board reconciliation, **not the approved packages**. This is why Gate 3 and Gate 11 are blocked |
| **Repository / current state** | `07f5bfb` + the live QA catalog | Authoritative on what *exists*. Where a document and the repository disagree, **the repository wins** |
| **Governance / change control** | This gate series + `MASTER_REMEDIATION_WAVES.md` (migration numbers **132+**, *"assigned at wave entry, never before"*) | Controls what may change. No change is authorized by this document |

**Precedence rule applied throughout:** V5 defines *what*; the repository defines *what is*; QA
defines *what is proven*; architecture and design authority are **absent for the V5 surface** and
must be vested before that surface is built.

## 3 · GATE RESULTS 1–15

| Gate | Subject | Result |
|---|---|---|
| **1** | V5 source-of-truth conflict | **PASS with owner confirmation** — additive model explicitly established (V3 §14, V4 §9, V5 §11); no structural contradiction; name needs confirming |
| **2** | Approved screen inventory | **PASS in part** — different units (design board 156/169 vs repo 91/148); canonical approved list is a prerequisite |
| **3** | Admin readiness | **FAIL** — designs not in repository; data model and API contracts undefined |
| **4** | Trust / audit foundation | **FAIL** — 14 decisions must precede any audit-dependent work |
| **5** | Security / open QA findings | **CONDITIONAL** — P0 must precede team/PHI workstreams; others can ride the build |
| **6** | Wearable architecture | **FAIL** — boundary, store and canonical contract undecided |
| **7** | AI / agentic security | **FAIL** — nothing exists; depends on audit + observability |
| **8** | SBOM / release integrity | **PASS for build-time, FAIL for release-time** |
| **9** | Database / migration readiness | **FAIL** — entities undefined pending D4/D-V2/D-V3 |
| **10** | API / mobile readiness | **FAIL** — no contracts; boundary undecided |
| **11** | Design readiness | **FAIL** — Admin/Trust designs absent; 46 routes already without design |
| **12** | Skills-Agent build readiness | **PASS** — model defined (§17) |
| **13** | Remaining QA 10% | **PASS** — carry-forward matrix established (§5) |
| **14** | Implementation sequencing | **PASS** — sequence derived (§20) |
| **15** | Owner decisions | **PASS** — reconciled and separated (§18/§19) |

**5 pass · 2 partial · 8 fail.**

### Gate 1 detail — the four questions asked

| Question | Answer |
|---|---|
| Is this the intended V5 specification? | **OWNER DECISION REQUIRED.** Content is unambiguously the V5 material (it contains a section titled "VERSION 5 AMENDMENT — SECURITY ASSURANCE, ASVS, SBOM & CONTROL MAPPING"), but the document's own title is "V1 MASTER … VERSION 2" |
| Does it establish the V2→V3→V4→V5 relationship? | **YES, explicitly** — three dedicated source-of-truth rules (V3 §14, V4 §9, V5 §11) |
| Does its structure establish the additive model? | **YES** — each amendment opens by preserving the prior document and closes with a supersession rule limited to added specificity |
| Any contradiction preventing implementation? | **NO structural contradiction.** The only conflicts are external (CONF-01 screens, CONF-03 SBOM, CONF-04 boundary), not internal |

## 4 · V5 CONFLICTS

| ID | Conflict | Status this gate |
|---|---|---|
| **CONF-01** | "174 approved screens" vs repo 91/148 | **DOWNGRADED** — different units; 174 = design-board authority (nearest in-repo: 156/169 at 2026-09-24). Prerequisite: canonical list. **Owner** |
| **CONF-02** | Document titled "V1 Master V2"; handoff calls it V5 | **DOWNGRADED — non-blocking.** Additive model is internally explicit; naming still needs confirmation (and V5 SA-01/SA-12 themselves require version-qualified traceability). **Owner** |
| **CONF-03** | CycloneDX SBOM required as release evidence; SBOM absent, tooling forbidden | **OPEN** — release-time only (§16). **Owner** |
| **CONF-04** | Wearable must be independently deployable; mobile is direct-to-Supabase, API thin | **OPEN** — blocks Gates 6/9/10. **Architecture** |
| **CONF-05** | Audit/agent evidence required in 4 places; no audit store | **OPEN** — deepest dependency. **Architecture + Owner** |
| **CONF-06** | V5 expands Wellness Partner; `vendor` is self-assertable, QAX-SEC-09 untestable, 0 vendor users | **OPEN**. **Owner** |
| **CONF-07** | Admin Control Center 13 domains vs 3 screens; view pattern non-functional (NEW-5) | **OPEN**. **Architecture** |
| **CONF-08** | Admin/Trust designs assumed to exist; 0 mentions in 7 design docs | **OPEN** — blocks Gates 3/11. **Owner** |
| **CONF-09** | Security scans/SBOM/release-integrity/E2E required; 0 scans, 1 red gate blinding 6, 4 jobs never run | **OPEN**. **Architecture** |

**9 conflicts. 2 downgraded. 0 closed. 0 silently reconciled.**

## 5 · QA CARRY-FORWARD MATRIX (Gate 13 — the remaining 10%)

| QA item | Current status | V5 impact | Implementation dependency | Required evidence | When to retest | Closure criteria |
|---|---|---|---|---|---|---|
| **QAX-SEC-08** (P0) | OPEN / PARTIALLY VERIFIED | Ecosystem contract, Admin roles, wearable PHI | **Blocks** team/roster/PHI workstreams | live exploit + post-fix denial under real JWTs | immediately after the `WITH CHECK` lands | victim insert denied; legitimate team reads unbroken; SEC-G1 baseline lowered |
| **F-03b** (P1) | OPEN / PARTIALLY VERIFIED | Guardian alerting | Blocks Guardian notification emission | live `notifications` INSERT denial | same wave as P0 | forged notify denied; `may_notify` status-filtered |
| **QAX-SEC-09** (P1) | OPEN / BLOCKED | Wellness Partner, partner APIs | Blocks partner APIs | needs `events.vendor_id` fixture | before partner workstream | vendor sees only minimum-necessary attendee fields |
| **SEC-PHI-9** (P1) | **OPEN / VERIFIED** (live) | Wearable authz inherits the pattern | Should precede wearable authz | post-fix: former coach denied, active coach unbroken | before wearable storage | `cancelled` coach denied; **active-coach path proven unbroken** |
| **SEC-PHI-10** (P1) | OPEN / INFERRED | Same class | Same | `score_events` rows for the cancelled client | with SEC-PHI-9 | status predicate enforced + demonstrated |
| **SEC-AI-1** (P1) | OPEN / INFERRED | AI governance (V4/V5) | Blocks AI Guardian disclosure posture | owner ruling + implementation | AI workstream | disclosure matches implementation |
| **NEW-2** | OPEN | Programme data → Training Alignment | Concurrent | post-fix read denial | wearable/programme wave | `WITH CHECK` + status predicate |
| **NEW-5** | OPEN | Admin column-limited views | **Blocks** applying `SEC_PHI_1` | corrected view returns rows for team leads | before Admin views | both screens functional post-change |
| **NEW-7** (3 stale skips) | OPEN | Monetization QA | Concurrent | unskip K-12/K-ENV-1; **review K-09** | P1 wave | specs green as guards, not skips |
| **QAT-1 / NEW-8** | OPEN | CI is a V5 release gate | Blocks release-integrity | ENV-5 green; 6 gates executing **in CI** | CI wave | all 7 gates run and pass in CI |
| **NEW-9** | OPEN | E2E journeys (SQ-39) | Blocks E2E evidence | 4 live jobs executing | after secrets | live tier green in CI |
| **NEW-3** | OPEN | Community Guardian | Concurrent | relationship gate | later | reviews gated |
| **6 open K specs** | OPEN (K-04 live-confirmed) | **Monetization Guardian domain** | Blocks that domain | per-spec assertions green | monetization wave | all 6 unskipped and passing |
| **PHI table access (0.75)** | PARTIAL | Wearable PHI | — | per-table probes under real JWTs | after fixtures | boundary demonstrated per table |
| **Supply chain (0.75)** | PARTIAL | SA-04/05/06/11 | Blocks release | SBOM + Dart scan | release wave | SBOM in release record |
| **Test completeness (0.9)** | PARTIAL | SQ-08/SQ-13 | — | security + AI tiers at HEAD | after egress + fixture authz | 5 of 5 tiers verified |
| **AI/processors (0.5)** | PARTIAL | AI governance | — | owner disclosure ruling | AI wave | disclosure documented |
| **Privacy alignment (0.5)** | PARTIAL | SQ-34 | — | owner ruling | privacy wave | claims match reality |
| **Replay harness (0.5)** | **BLOCKED** | **Validating the P0 fix in simulation** | Should precede applying #1/#2 | Docker or local Postgres | before P1 wave | fix simulated before applied |

**The remaining 10% is carried, not closed.** No item is forced to closure before evidence exists.

## 6 · ADMIN READINESS — **BLOCKED**

| Area | Design available? | V5 req clear? | Data model clear? | API contract clear? | Permissions clear? | Audit req clear? | Impl ready? |
|---|---|---|---|---|---|---|---|
| Admin Home | **NO** (not in repo) | PARTIAL | NO | NO | YES (`is_admin`) | NO | **NO** |
| Ecosystem | **NO** | **NO** — term undefined in V5 | NO | NO | NO | NO | **NO** |
| Users | **NO** | YES (AD-01) | PARTIAL — `admin_recent_users()` exists | NO | YES | **NO** | **NO** |
| Coaches | **NO** | PARTIAL | PARTIAL | NO | YES | NO | **NO** |
| Clients | **NO** | PARTIAL | PARTIAL — PHI columns need limited views (**NEW-5 blocks the pattern**) | NO | YES | NO | **NO** |
| Trust | **NO** | YES (4 areas named) | **NO** | NO | NO | **NO** | **NO** |
| Security | **NO** | PARTIAL | **NO** — no product-facing posture store | NO | NO | NO | **NO** |
| Incidents | **NO** | YES (AG-04/05 fields + severity) | **NO** — no table | NO | NO | NO | **NO** |
| Audit Logs | **NO** | YES (V5 §3, V4 §5) | **NO** | NO | NO | **it *is* the requirement** | **NO** |
| AI Guardian | **NO** | YES (8 domains, L0–L3) | **NO** | NO | NO | **NO** | **NO** |
| Payments | **NO** | PARTIAL | PARTIAL — Stripe exists | NO | YES | NO | **NO** — 6 open K specs |
| Wearables | **NO** | YES (WI-15) | **NO** | NO | NO | NO | **NO** |
| Health / Database / Releases / Analytics | **NO** | PARTIAL | **NO** — 0 observability tables | NO | NO | NO | **NO** |

**0 of 13 Admin areas are implementation-ready.** Designs were not invented.

## 7 · TRUST READINESS — **BLOCKED**

| Trust area | Existing substrate | Missing |
|---|---|---|
| AI Guardian | `ai_reviews`, `ai_insights`, `explain-decision`, `decision_traces` dir | entire runtime, 8 domains, autonomy model, allowlists, approval gates, emergency disablement |
| Security | catalog is introspectable (this programme did so) | product-facing evidence store; the app cannot read `pg_policies` |
| Incidents | none | table, RLS, severity enum, evidence model, approval workflow, FP/FN loop |
| Audit Logs | **none — the data was never written** | **cannot be a view over existing data**; needs a write path at every audit-worthy action |

## 8 · AUDIT READINESS — **BLOCKED** (Gate 4)

**Can implementation begin safely without defining audit first? NO** — for any V5 feature that
depends on Audit Logs, the Admin audit domain, or the agent action trail. It **can** begin for
features with no audit dependency (§23).

**Minimum architecture that MUST be decided before the first audit-dependent line of code —
14 decisions. None is made here.**

| # | Decision | Why it cannot be deferred |
|---|---|---|
| A1 | **Audit schema** — one generic event table vs per-domain tables | determines every downstream write and every RLS policy |
| A2 | **Event taxonomy** — what is "audit-worthy"; V5 says "material actions" without defining it | under-scoping silently loses evidence; over-scoping writes PHI into a second store |
| A3 | **Write path** — trigger-based, application-level, or both | a trigger cannot see application intent; an app-level write can be bypassed |
| A4 | **Actor identity** — human uid, service role, **and agent identity** (V4 §5) | today `auth.uid()` is NULL on the service-role path, so the highest-privilege actor is the least identifiable |
| A5 | **Target/resource identity** — how a subject row is referenced stably | rows are deleted; audit must outlive them |
| A6 | **Before/after state** — whether to store it, and how to avoid duplicating PHI | an audit row containing PAR-Q becomes a second PHI surface with its own boundary |
| A7 | **Timestamp semantics** — event time vs write time | wearable data (WI-23) makes clock anomalies a first-class concern |
| A8 | **Source** — surface/service/agent attribution | required for the release-integrity chain (SA-11) |
| A9 | **Severity** — the Critical/High/Warning/Informational enum (AG-05) | shared with incidents |
| A10 | **Correlation / request ID** — required by V5 SQ-10 | must be threaded before code is written, not after |
| A11 | **Immutability / history** — append-only, and enforced how | **an audit record editable by its subject is not audit**; today RLS is the only enforcement layer |
| A12 | **Retention** — duration and deletion interaction with data-subject rights | V5 SQ-34 requires export/deletion; audit retention can conflict with erasure |
| A13 | **RLS** — who may read audit rows | admins are the audited party; self-exculpatory reads must be prevented |
| A14 | **Privileged access + Trust visibility rules** | which Trust surfaces expose which audit rows to whom |

**Note the structural hazard in A4/A11:** `enforce_profile_privilege()` returns early when
`auth.uid()` IS NULL — the service-role path. Any audit design that relies on `auth.uid()` will
record the *least* about the *most* privileged actor. Documented, not solved.

## 9 · SECURITY READINESS — **PARTIAL / CONDITIONAL**

**Strong, catalog-verified foundation:** RLS enabled on **91/91** tables · 0 tables with RLS but
no policies · 0 `anon`/`PUBLIC` policies · 0 `anon` grants · 0 SECURITY DEFINER functions with a
mutable `search_path` · `admin` and `content_manager` **not self-assertable** (verified:
`enforce_profile_privilege()` coerces anything outside `('client','coach','vendor')` to `client`).

**Not sufficient for V5 as-is:**

| Gap | Consequence for V5 |
|---|---|
| **P0 QAX-SEC-08** — any authenticated account becomes a team lead and reads PHI; **no role check at all** | wearable health data would land on this surface |
| `coach`/`vendor` self-assertable | CONF-06 — partner APIs would build on an unhardened role |
| **No OWASP/ASVS adoption** — 0 references to ASVS or OpenCRE | V5 SA-01/SA-07 require them as the verification baseline |
| **No agentic security controls** | V4 AS-01…13 entirely absent |
| **No audit** | security events are unrecorded |

**Verification required after any security change:** live denial of the specific attack, live
proof the legitimate path still works (the SEC-PHI-9 lesson — the active-coach path must not
break), mutation testing of every new guard, and re-derivation of the guard population **from the
live catalog** rather than migration text.

## 10 · WEARABLE READINESS — **BLOCKED** (Gate 6)

| Element | Specified? | Evidence |
|---|---|---|
| Connector layer | **PARTIAL — exists** | `user_integrations` (provider, connected, access/refresh token, connected_at, disconnected_at) + `integrations_screen.dart` naming `apple_health`, `garmin`, `google_fit`, `polar`, `strava`, `myfitnesspal`, `spotify` |
| Consent | **PARTIAL** | connection implies consent; no granular scope model |
| Ingestion | **NO** | no ingestion path |
| Observation model | **NO** | no observation table |
| Normalization | **NO** | no canonical record type |
| Zones | **NO** | no heart-rate or zone concept anywhere |
| Intelligence / Training Alignment | **NO** | — |
| Provenance | **NO** | WI-09 requires source + timestamp + calculation version + quality |
| Storage boundary | **NO** | **D-V2 undecided** — shared Postgres or own store |
| **PHI access boundary** | **NO — and highest risk** | **D-V4 undecided**; lands on the surface with 2 verified boundary defects |
| Independent deployability | **NO** | **D-V1 undecided** — CONF-04 |
| API / service boundary | **NO** | API is thin; no SDK |
| Failure / retry model | **NO** | WI-22 requires stale/missing/duplicate/delayed/impossible/conflicting handling |

**Unresolved decisions: D-V1, D-V2, D-V3, D-V4** plus provider scope for V1 (**V5 ambiguous** —
"multiple sources", none named) and the medical-diagnosis labelling rule (WI-21).

## 11 · AI / AGENTIC READINESS — **BLOCKED** (Gate 7)

| | |
|---|---|
| **WHAT EXISTS** | 6 `ai_*` tables (RLS-enabled, `user_id = auth.uid()` with `WITH CHECK`), 6 AI edge functions, `explain-decision`, a `decision_traces` directory, `app_failure.dart` |
| **WHAT DOES NOT EXIST** | AI Guardian runtime · 8 Guardian domains · autonomy L0–L3 · agent/skill/tool inventory · **agent action audit trail** · runtime least privilege · tool allowlists · approval gates · agent incidents · human escalation · emergency disablement · AST10 evaluation · prompt-injection tests |
| **MUST BE DECIDED** | agent identity for audit (**D-V5**); recommendation-vs-enforcement boundary (AS-07/09); L2 allowlist contents (**V5 gives only two examples** — retry a job, disable an approved flag); AG-03 — how emergency disablement is proven not to disable core security controls |
| **MUST BE DESIGNED** | Guardian surfaces, incident/approval workflows — **and no design exists** |
| **MUST BE BUILT** | audit store first, then observability, then Guardian |
| **MUST BE TESTED** | injection, privilege escalation, unauthorized tool/data access, malicious skills, supply-chain change, metadata abuse, memory/context poisoning, weak isolation, runaway/cascading behaviour, unsafe external communication, disablement, rollback, containment, recovery |
| **Existing related finding** | **K-03 — all three *sold* AI functions have 0 `active_membership`/`client_plan` checks** |

**Structurally favourable and worth preserving:** application security is enforced by **RLS in
Postgres**, independent of any app-layer agent — so AG-03 ("emergency Guardian disablement must
not disable core application security controls") is *structurally* satisfied today. It is **not
verified as a designed control**, and any future app-layer authorization would weaken it.

## 12 · DATABASE READINESS — **BLOCKED** (Gate 9)

27 database-impacting requirements. Entities cannot be specified until **D4** (audit), **D-V2**
(wearable store) and **D-V3** (canonical contract) are decided.

| Category | Requires decision before migration work |
|---|---|
| New entities | **YES** — wearable raw/canonical/derived, device/sync/quality state, audit events, incidents, agent+skill inventory, agent action log, feature flags, security-control matrix, SBOM/release records, observability metrics |
| Relationships | **YES** — observation→user→workout/session; partner/tenant→integration |
| Indexes | **YES** — time-series on (user, timestamp); high-write ingestion |
| Constraints | **YES** — impossible/duplicate rejection, ordering |
| Enums | **YES** — severity, autonomy level, provider, observation type |
| RLS | **YES** — every new table; **audit not editable by its subject** |
| Authorization helpers | **YES** — must not repeat the status-less `is_team_lead_of()` pattern |
| Audit records | **YES** — A1–A14 |
| Provenance | **YES** — WI-09, version-pinned zone calculations (WI-24) |
| Migration numbers | **132+, assigned at wave entry only** |
| Backfill | `user_integrations` → new connector model |

## 13 · API READINESS — **BLOCKED** (Gate 10)

| V5 domain | Required API | Current | Missing | Authorization | Data contract | Errors | Loading | Offline | Audit |
|---|---|---|---|---|---|---|---|---|---|
| Wearable platform | versioned API + SDK, tenancy, usage telemetry | thin NestJS (4 modules); mobile direct-to-Supabase | **all** | **D-V4 undecided** | **D-V3 undecided** | undefined | undefined | undefined — realtime + historical (WI-10) | **required** |
| Partner APIs | authorized partner access | none | all | no tenancy model | undefined | undefined | undefined | n/a | required |
| Admin Control Center | 13 domains | 4 SECURITY DEFINER fns | most | `is_admin()` sound | undefined | **must not print raw exceptions (ERR-G2)** | undefined | n/a | **required** |
| Trust | 4 areas | none | all | undefined | undefined | undefined | undefined | n/a | **required** |
| Guardian | detection/telemetry/actions | none | all | agent least privilege | undefined | undefined | n/a | n/a | **required** |
| Audit query | read audit | none | all | **A13 undecided** | **A1 undecided** | undefined | undefined | n/a | itself |

**No endpoint was invented.** The gating question is **D5** (Admin via API or direct Supabase) and
**D-V1** (wearable boundary).

## 14 · MOBILE READINESS — **BLOCKED**

Wearable UX (connection exists; live HR, zones, workout context, post-workout, disconnected,
data-quality states do not) · Admin/Trust surfaces (**D6** undecided, designs absent) · feature
flags (**0 files**) · realtime path (none evidenced). Existing constraints carried: 2 dead
duplicate screens (DEAD-G1), ERR-G2 error-copy rules, 34 declared providers never consumed,
**46 routes already without design**.

## 15 · DESIGN READINESS — **BLOCKED** (Gate 11)

| Category | Items |
|---|---|
| **DESIGN COMPLETE** | 45 of 91 routes have a design frame; board reconciliation records 156 board screens / 169 with voice variants (2026-09-24) |
| **DESIGN PARTIAL** | 110 fit anchors — **19 complete, 56 partial, 32 zero coverage**; 287 of 600 declared interactions present |
| **DESIGN MISSING** | **46 routes without design**; 48 items in `section2_design_commission`; **N-07 "Coach client assessment (intake/PAR-Q review)" is missing from the board, priority P0, blocked by OD-30** |
| **DESIGN CONFLICTING WITH V5** | CONF-01 units (now understood, list still needed) |
| **DESIGN NOT IN REPOSITORY** | **Admin Home · Ecosystem · Users · Coaches · Clients · Trust · Security · Incidents · Audit Logs · AI Guardian** — 0 mentions of Trust/AI Guardian/Incidents across 7 design docs |

**Must be finalized before implementation:** every Admin/Trust design listed above, plus the
canonical approved-screen list. **Nothing was redesigned in this gate.**

**Adopt the repository's existing rule** rather than inventing one — *"A designed anchor that is
unimplemented is an IMPLEMENTATION gap, not a missing screen. A required surface with no design
frame is a DESIGN COMMISSION."*

## 16 · SBOM / RELEASE-INTEGRITY READINESS (Gate 8)

**The separation the gate asks for, and it is the operative finding:**

| | Requirements | Readiness |
|---|---|---|
| **BUILD-TIME** | writing code; running tests; migrations; RLS; local verification | **READY — no SBOM dependency.** Nothing in V5 requires an SBOM to *write* code |
| **RELEASE-TIME** | SA-04 versioned CycloneDX SBOM · SA-05 component diff + vuln/licence/provenance/policy checks · SA-06 retention + signing · SA-11 release-integrity chain · SA-01 ASVS · SA-07 OpenCRE · SA-08 assurance matrix | **NOT READY** — SBOM absent, tooling not installed (installation currently forbidden), 0 CI security-scan steps, chain broken after "source revision" |

**Conclusion: V5 implementation may begin before the release-integrity architecture is defined,
provided no release is attempted.** The risk of deferring is rework — the assurance matrix (SA-08)
wants control→requirement→evidence→owner mapping *per control*, which is cheaper to capture as
controls are built than to reconstruct afterwards. **Recommendation recorded, not enacted:** have
the security workstream emit SA-03-shaped evidence from the first wave.

## 17 · SKILLS-AGENT ORCHESTRATION READINESS — **READY** (Gate 12)

The established Skills-Agent workflow continues. **No agent may redefine V5.**

| Workstream | Responsibility | Inputs | Outputs | Dependencies | Allowed mutations | Required verification | Handoff condition |
|---|---|---|---|---|---|---|---|
| **Product / V5** | interpret V5; raise ambiguities | V5 doc | requirement IDs, ambiguity register | — | **docs only** | owner sign-off on ambiguities | requirement accepted, no invention |
| **Architecture** | structure; resolve D-items | V5, repo, QA ledger | ADRs, contracts, boundaries | Product | **docs only** | peer + security review | ADR approved |
| **Database** | schema, RLS, migrations | ADRs | migrations **132+**, policies | Architecture, D4/D-V2/D-V3 | `supabase/migrations/**` | **live catalog** verification; mutation-tested policies | migration applied + catalog-verified |
| **Security** | verify controls — **independent of implementation** | everything | findings, control evidence (SA-03) | all | **tests + docs only; never product code** | live denial + live legitimate-path proof | no open P0/P1 in the wave's scope |
| **Backend / API** | services, contracts | ADRs | API + SDK | D5/D-V1 | `apps/api/**`, `supabase/functions/**` | contract tests | contracts published |
| **Mobile** | Flutter surfaces | designs, contracts | screens, providers | Design, API | `apps/mobile/lib/**` | widget + guard tests; ERR-G2 compliance | design-QA pass |
| **Admin / UI** | Control Center | designs, contracts | admin surfaces | Audit, Design | `apps/mobile/lib/features/admin/**` | permission + audit tests | audit emitted per action |
| **Trust** | 4 Trust areas | designs, audit schema | Trust surfaces | **Audit first** | scoped | audit + RLS tests | evidence model verified |
| **AI** | Guardian + agentic controls | V4/V5 controls | Guardian, allowlists, tiers | Audit, Observability | scoped | AST10 + injection tests | agentic QA gate passed |
| **Design** | experience | V5, product | approved packages | Product | design artifacts | design QA | package approved + in repo |
| **Testing** | build the suites | requirements | tests across 5 tiers | all | `**/test/**` | **detector non-vacuity proven** | tiers green at HEAD |
| **QA** | verify correctness | implementation | QA ledger | Testing | **evidence only** | executed evidence, never inferred | domain disposition recorded |
| **Verification / Evidence** | whole-system + release evidence | all | release record, assurance matrix | all | docs only | reproducible | gate passed |

**Governance constraints carried from this programme:** migration numbers assigned at wave entry
only · no allowlist entry to silence a gate · shrinking allowlists never grow · every guard
mutation-tested · a detector must be proven able to find a planted defect before a zero result is
believed · never convert "not tested" into PASS.

## 18 · OWNER DECISIONS (22)

| ID | Question | V5 ref | Consequence of delay |
|---|---|---|---|
| CONF-01 | Canonical approved-screen list | GV-03 | "protected" is unenforceable |
| CONF-02 | Confirm document name/version | SA-01/12 | traceability gap in release evidence |
| CONF-03 | Authorize SBOM tooling, or govern absence as accepted risk | SA-04/05/06 | release gate unmeetable |
| CONF-06 | Harden `vendor` before partner APIs? | WI-18 | partner APIs on an untested role |
| CONF-08 | Supply Admin/Trust designs or commission them | SQ-09/AD-01 | **blocks Admin + Trust entirely** |
| D1 | Team semantics / who may create a membership | SQ-02 | **P0 + F-03b stay open** |
| D2 | Keep `coach`/`vendor` self-assertable? | SQ-02 | CONF-06 persists |
| **D4** | **Audit log + audit-worthy actions** | AG-04, AD-03, AS-05, SA-03 | **blocks Trust, Admin audit, Guardian** |
| D5 | Admin via API or direct Supabase | AD-01 | API workstream cannot start |
| D6 | Admin/Trust in-app or separate surface | AD-01 | mobile scope undefined |
| D7 | Users/Coaches/Clients: modules or views | AD-01 | Admin data model undefined |
| D8 | `content_manager` admin surface? | AD-02 | a policy-recognised role stays unserved |
| D10 | AI disclosure posture | SEC-AI-1 | privacy alignment stays partial |
| D11 | Trust scope | Trust | largely resolved by V5; build scope open |
| D12 | Audit read/immutability/retention | SA-03 | audit design incomplete (A11–A13) |
| D16 | Extract shared design system now? | SQ-05 | **note: V3's standalone wearable platform may itself be the "second product" that triggers extraction** |
| D-V1 | Wearable platform location/boundary | WI-01/16 | **blocks the whole wearable stack** |
| D-V2 | Wearable store: shared Postgres or own | WI-12 | schema cannot be specified |
| D-V3 | Canonical observation + provenance contract | WI-08/09 | ingestion cannot be built |
| D-V4 | Who may read wearable PHI | WI-14 | authorization cannot be designed |
| D-V5 | Agent identity for the audit trail | AS-05 | agent actions unattributable |
| D-V6 | SBOM toolchain and where it runs | SA-04 | release chain incomplete |

## 19 · ARCHITECTURE DECISIONS (11)

CONF-04 (wearable deployability) · CONF-05 (audit as architecture) · CONF-07 (Admin scale) ·
CONF-09 (CI release gates) · D3 (uniform status predicate) · D9 (server-side AI entitlement —
*V4/V5 resolve this in principle; implementation open*) · D13 (`static-guards` fail-late) ·
D14 (branch protection) · D15 (derive guard population from the live catalog) · D17 (fix
`SEC_PHI_1` before applying) · D-V7 (governance baseline mechanics once CONF-01 is answered).

**Implementation decisions** — widget composition, file layout, test structure, naming within an
approved contract — are **delegated to the implementing agents under governance** and deliberately
not enumerated here. Recording them would convert delegation into pre-specification.

## 20 · REQUIRED IMPLEMENTATION SEQUENCE (Gate 14 — derived, not assumed)

```
0. GOVERNANCE        CONF-01, CONF-02 · wave numbers 132+ · CONF-08 designs commissioned
        ↓
1. SECURITY FOUNDATION   queue 1–5: coach_team_members WITH CHECK (closes P0 + F-03b)
                         corrected SEC_PHI_1 · status predicates · workout_program_assignments
        ↓            [needs D1, D3, D17 · ideally replay-simulated first]
2. AUDIT + OBSERVABILITY  A1–A14 decided → audit schema, RLS, write path → observability store
        ↓            [needs D4, D12 — THE critical path]
3. BACKEND / WEARABLE PLATFORM   boundary → store → canonical contracts → ingestion → normalization
        ↓            [needs D-V1, D-V2, D-V3]
4. CORE PRODUCT      intelligence layer: zones, workout context, Training Alignment, provenance
        ↓
5. ADMIN             Control Center on (2)'s stores        [needs D5, D6, D7 + designs]
        ↓
6. TRUST             Security · Incidents · Audit Logs      [needs (2) and (5)]
        ↓
7. AI GUARDIAN       8 domains, L0–L3, allowlists, approval gates, agent audit trail  [needs D-V5]
        ↓
8. MOBILE            wearable UX + states · Admin/Trust surfaces · feature flags
        ↓
9. INTEGRATION       12Circle+ consumes the platform via contracts · partner APIs + tenancy [CONF-06]
        ↓
10. FULL QA          5 tiers · wearable QA · agentic security QA · a11y · performance
        ↓
11. RELEASE          SBOM · assurance matrix · release-integrity chain · DR + rollback drills
```

**Runs in parallel with 1–2:** monetization / the 6 open K specs (entitlement defects, K-04
live-confirmed) and the CI gate repair (QAT-1, D13).
**Differs from the example sequence given in the brief:** **audit precedes backend**, because
three later phases consume it; and **security foundation precedes everything**, because the P0
gates the PHI surface. No dates, durations or story points — V5 defines none.

## 21 · BLOCKING CONDITIONS

| # | Blocker | Blocks | Cleared by |
|---|---|---|---|
| **B1** | **D4 + A1–A14 — audit architecture undecided** | Trust, Admin audit, Guardian, agent trail | owner + architecture decision |
| **B2** | **Admin/Trust designs not in repository** (CONF-08) | Admin, Trust, Guardian UI | supply or commission the packages |
| **B3** | **D-V1/D-V2/D-V3 — wearable boundary, store, contract** (CONF-04) | entire wearable stack | architecture decision |
| **B4** | **D1 — team semantics** | P0 + F-03b fix; any team/PHI feature | owner decision |
| **B5** | **D-V4 — who may read wearable PHI** | wearable authorization | owner decision |
| **B6** | **CONF-01 — canonical approved-screen list** | "protected screen" enforcement, SQ-30 migration | owner supplies the list |
| **B7** | **CONF-06 — `vendor` hardening** | partner APIs, Wellness Partner persona | owner decision |
| **B8** | **CONF-03/D-V6 — SBOM toolchain** | **release only**, not build | owner authorization |
| **B9** | **D5/D6 — Admin surface + transport** | Admin, Trust, mobile scope | owner decision |
| **B10** | Replay harness blocked (Docker) | simulating the P0 fix before applying it | environment |
| **B11** | HTTPS egress + CI secrets | security/AI tiers, E2E journeys | environment + configuration |

## 22 · FINAL GO / NO-GO

### **NOT READY FOR CONTROLLED V5 IMPLEMENTATION**

Against the stated standard, the product cannot be built today without inventing: the audit data
model (B1), the Admin/Trust design (B2), the wearable platform architecture (B3), and the wearable
PHI authorization boundary (B5).

**This is not a negative finding about V5 or the system.** V5 is internally coherent and
explicitly additive (Gate 1), and the security foundation is unusually well evidenced — RLS on
91/91 tables, verified from the live catalog. What is missing is **decision and design authority
for the new surface**, which is exactly what a readiness gate exists to detect before code is
written.

**11 blocking conditions. 8 of 11 clear through decisions the owner already holds; 3 are
environmental.**

## 23 · EXACT NEXT AUTHORIZED STEP

**Nothing is authorized by this document.** The next mission, when the owner chooses to open it,
has exactly one candidate scope that is specified well enough to proceed — and it is **not** a V5
feature:

> **Candidate first workstream — SECURITY FOUNDATION (queue items 1–5), pending D1 only.**
>
> | | |
> |---|---|
> | Why it qualifies | fully specified by existing QA evidence; requires **no** V5 design, **no** new data model, **no** new architecture |
> | Why it should be first | the **P0 gates the PHI surface** that V5's wearable health data would join, and one change closes both the P0 and F-03b |
> | Authorization boundary | `supabase/migrations/132+` (number assigned at wave entry) · the two corrected `docs/proposed/*.sql` files · guard tests under `apps/mobile/test/**` — **and nothing else** |
> | Prerequisites | **D1** (team semantics) + **D3**, **D17**; ideally B10 cleared so the fix is replay-simulated first |
> | Required verification | live denial of the forged insert · **live proof the legitimate team/coach paths still work** · mutation-test every new guard · re-derive the SEC-G1 population from the live catalog · lower the baseline, never raise it |
> | Agents | Architecture (ADR) → Database (migration) → Security (independent verification) → QA (evidence) |
> | Explicitly excluded | Admin · Trust · Guardian · wearable · any V5 feature |

**Recommended owner action before any implementation mission:** decide **D1** and **D4**, and
supply **CONF-01** (the approved-screen list) and **CONF-08** (the Admin/Trust designs). Those
four clear 6 of the 11 blockers and unblock phases 1, 2, 5 and 6.

---

## FINAL ADVERSARIAL REVIEW

| Challenge | Outcome |
|---|---|
| 1. Any requirement ambiguous? | **Yes — 8 preserved** (§24 of the impact analysis), incl. audit granularity, L2 allowlist contents, "applicable" ASVS scope, wearable provider scope |
| 2. Any source-of-truth conflict unresolved? | **Yes — 9**, of which 2 downgraded this gate. None silently reconciled |
| 3. Any major design missing? | **Yes — all 10 Admin/Trust areas**, plus 46 routes and N-07 (P0, missing from board) |
| 4. Trust sufficiently defined? | **Scope yes (V5 names 4 areas); build no.** Depends on audit |
| 5. Audit sufficiently defined? | **NO — 14 decisions outstanding.** The single deepest blocker |
| 6. Security foundation sufficient? | **Sufficient as a base, not as a target.** P0 open; no ASVS/OWASP adoption; no agentic controls |
| 7. P0/P1 properly carried forward? | **Yes — §5**, none closed or downgraded; SEC-PHI-9 remains the only VERIFIED one |
| 8. Database sufficiently specified? | **NO** — pending D4/D-V2/D-V3 |
| 9. API contracts sufficiently specified? | **NO** — none exist; no endpoint invented |
| 10. Mobile sufficiently specified? | **NO** — designs absent, D6 open |
| 11. Wearable boundaries sufficiently specified? | **NO** — D-V1/V2/V3/V4 |
| 12. AI/agentic sufficiently specified? | **NO** — nothing exists; depends on audit |
| 13. Release-integrity sufficiently specified? | **NO for release; irrelevant for build** — the build/release split is the operative finding (§16) |
| 14. Skills Agents incorporated? | **Yes — §17**, 13 workstreams with allowed mutations and handoff conditions |
| 15. Can the remaining QA 10% be carried through the build? | **Yes — §5**, with retest points and closure criteria; nothing forced closed |
| 16. Owner vs implementation decisions separated? | **Yes — §18 (22 owner) / §19 (11 architecture)**; implementation decisions deliberately delegated, not enumerated |
| 17. Did I make a decision belonging to the product owner? | **No.** CONF-01 and CONF-02 were **downgraded on evidence** (different units; explicit additive rules) — the owner still confirms the list and the name. No D-item was decided |
| 18. Did I implement anything? | **No** — documentation only; all database access read-only |
| *Extra:* did I declare READY because a narrow slice is buildable? | **No.** The verdict is NOT READY; the security-foundation slice is recorded as a *candidate* for the next mission and is explicitly not a V5 feature |

---

*Read-only readiness gate. **NOT READY FOR CONTROLLED V5 IMPLEMENTATION** — 11 blocking
conditions. QA remains 90.0% with 1 P0 and 4 P1 open. No code, schema, policy, CI, design or
database change was made. Implementation is not authorized.*
