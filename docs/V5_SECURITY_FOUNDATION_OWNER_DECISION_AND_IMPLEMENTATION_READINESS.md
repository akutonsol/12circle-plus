# V5 · SECURITY FOUNDATION — OWNER DECISION & IMPLEMENTATION READINESS

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** DOCUMENTATION-ONLY preparation package. No implementation, no migration, no mutation.

> **READY FOR IMPLEMENTATION PREPARATION — NOT AUTHORIZED FOR IMPLEMENTATION.**
> Authorization is blocked solely on the owner decisions in §2–§5.

---

## 1 · CURRENT STATE

| | |
|---|---|
| HEAD | `07f5bfb9115f74b3c3e262e1d0d3bc4607ffe99f` · 0 modified · 0 staged |
| QA | **90.0% — QA COMPLETE WITH OPEN FINDINGS** (18.90 / 21) |
| Open findings | **1 P0** (QAX-SEC-08) · **4 P1** (F-03b, QAX-SEC-09, SEC-PHI-9/10, SEC-AI-1) — **none closed** |
| V5 blockers | **6** (B1, B2, B3, B4, B5, B7) |
| Owner decisions | **23** · Architecture decisions **13** · Design dependencies **23** |
| Security Foundation | **scope exact; blocked on D1 only** |

### A material discovery made while assembling D1's evidence

**The team feature is half-built, and the missing half is exactly the consent step.**

| Step | Exists? | Evidence |
|---|---|---|
| Coach creates an invite | **YES** | `coach_business_screen.dart:256` — `coach_team_invites.insert({coach_id, email, role: 'assistant_coach'})`, then invokes `send-invite-email` |
| Invite carries acceptance state | **YES, structurally** | `coach_team_invites` has `email`, `role`, `token`, **`accepted boolean`** |
| **Anything converts an accepted invite into a membership** | **NO — nothing, anywhere** | **0 triggers** on either table · **0 functions** reference `coach_team_invites` · **no app code** writes `coach_team_members` |
| Roster reads memberships | **YES** | `coach_business_screen.dart:66` — `SELECT` only |

**Consequences, all three material to the decisions below:**

1. **No code in the application, edge functions, or database ever inserts into
   `coach_team_members`.** The only app reference is a `SELECT`. So a policy change that forbids
   lead-initiated inserts **would break nothing that currently works** — and it explains why the
   table holds 0 rows.
2. **The schema already expresses consent-based intent** — an invite addressed to an `email`, with a
   `token`, and an `accepted` flag. That is *schema* evidence of design intent, not an inference from
   UI wording. **But it is not a control:** `coach_team_invites` carries the *same* defect —
   `cmd=ALL`, `USING (coach_id = auth.uid())`, **`with_check` NULL** — so invites are themselves
   self-assertable, and nothing enforces the link.
3. **`role` has one observed value in practice: `'assistant_coach'`** (hard-coded at the invite call
   site). Concrete input to D1(iv).

### New observation — NEW-10 (LOW), recorded not fixed

`coach_business_screen.dart:256` writes the invite with `.catchError((_) {})` and then sends the
invitation email **regardless of whether the insert succeeded**. A failed invite is therefore
indistinguishable from a successful one, and the invitee receives an email for an invite that may
not exist. This is the same silent-failure class as CORR-1/CORR-2 (both since fixed). **Severity
LOW** — it affects a feature with no completion path. **Not remediated; added to the carry-forward.**

## 2 · D-D1 DECISION GATE — TRUST CONTAINER

### `TRUST = [INSERT OWNER DECISION HERE]` — **placeholder preserved, not filled**

**Exact question:** *"Is Trust a separate product surface, or are its capabilities implemented within
the Admin Control Center?"*

| Interpretation | Evidence for | Evidence against |
|---|---|---|
| **(A) Separate product/module** | appears only in mission briefs | **V5: 0 occurrences of "Trust" in 335 paragraphs** · **Admin brief: 0 occurrences** · 0 implementation files · 0 design artefacts on disk |
| **(B) A subsection of Admin** | Admin brief §2 makes **Security** and **AI Guardian** top-level *Admin* nav items; §6 makes *"Security & Governance"* — auth, authorization/RLS, admin actions, sensitive-data access, **audit logs**, security events — an *Admin operational layer*; V5 places Guardian, incidents and audit under Admin/Guardian/observability | — |
| **(C) A governance/security layer, not a UI module** | V5's V4 amendment treats agentic governance as cross-cutting controls, not a screen set; §12 of the brief states governance as **principles** | needs a surface *somewhere* to be operable |
| **(D) Not currently required** | — | **contradicted** — the capabilities (Security, Incidents, Audit, Guardian) are unambiguously required; only the *container* is unevidenced |

**Only (B) and (C) have evidentiary support. (A) has none in either authoritative source.**

| What changes architecturally | Under (B) / (C) | Under (A) |
|---|---|---|
| Design dependencies | **23 → 15** (removes 8 Trust surfaces) | 23, **plus requirements must be authored** for Trust Home, Reviews, Policies — none is named in V5 |
| Build phases | **P6 (Trust) disappears**; capabilities fold into P5 (Admin) | P6 remains and needs a full specification + design package |
| Navigation | no separate hierarchy | a second top-level product surface |
| Permission model | one Admin role model (CONF-D7) | a second model, plus a "Trust operator" role that exists in neither V5 nor the repo |
| CONF-D2 | **closes** | stays open and widens |

**Downstream workstreams affected:** Design (8 packages), Admin, Trust, AI Guardian, Database
(whether Trust needs its own tables), QA (whether a Trust tier exists).

**No option selected.**

## 3 · D1(i) DECISION GATE — MAY A LEAD ADD A MEMBER UNILATERALLY?

**Evidence**

| Source | Finding |
|---|---|
| Current policy | `"Head coach manages team" FOR ALL USING (coach_id = auth.uid())`, **`with_check` NULL** → today **anyone** may insert, naming any victim as `member_id`, with **no role check at all** (`has_role_check = false`) |
| Application code | **no insert exists anywhere** — so no current behaviour depends on lead-initiated creation |
| `coach_team_invites` | schema expresses **invitation + acceptance** (`email`, `token`, `accepted`) — but is itself unhardened and **orphaned** from membership |
| In-schema precedent | `coach_client_relationships` INSERT `WITH CHECK`: a **client** may create `pending` or `active`; a **coach** may create only `pending`. Principle: *a party may not unilaterally conscript the other into an active relationship* |
| V5 | **silent** — no team concept exists in the specification |

| Supported option | Security consequence | Implementation consequence |
|---|---|---|
| **(a) Member-initiated only** — lead's write arm `with check (false)`; a second policy permits `member_id = auth.uid()` | **Closes the P0 and F-03b completely.** Forgery becomes impossible: you can only add yourself | **Breaks no current code.** Requires building the acceptance step (which does not exist) before teams are usable |
| **(b) Lead-initiated, pending-only** — lead may insert at a non-active status; member activates | Closes the P0 **only if** `is_team_lead_of()` also filters status (C7). Otherwise a `pending` row still grants PHI | **Requires a status column** — a schema change, own migration, backfill decision |
| **(c) Lead-initiated with role validation** — `with check (coach_id = auth.uid() AND is_coach_profile(coach_id))` | **LOOKS SUFFICIENT AND IS NOT.** `role='coach'` is **self-assertable at signup**, so this lowers the bar from "any account" to "any account that registered as a coach" — it does not close the forgery | Smallest diff; no schema change |
| **(d) Mutual consent** — invite + acceptance enforced, linking `coach_team_invites` → `coach_team_members` | Strongest; matches the schema's evident intent | Largest: requires hardening `coach_team_invites` too, plus the missing conversion mechanism |

**Affected objects:** policy `"Head coach manages team"` · functions `is_team_lead_of()`,
`may_notify()` · policies `user_profiles` SELECT, `notifications` INSERT.
**Affected V5 requirements:** SQ-02/SQ-03 (ecosystem contract), AG-01 (Guardian alerting via
notifications).

## 4 · D1(ii) DECISION GATE — DOES MEMBERSHIP CARRY A STATUS LIFECYCLE?

**Evidence**

| Source | Finding |
|---|---|
| `coach_team_members` | **no status column.** Columns: `id`, `coach_id` NOT NULL, `member_id` NOT NULL, **`role` text NOT NULL**, `added_at` |
| Revocation today | **delete the row** — there is no "was a lead" state |
| `is_team_lead_of()` | **no status filter** — it cannot express revocation even if a status existed |
| `coach_client_relationships` | **has** status; revocation is `status='cancelled'`, and the row is never deleted |
| **SEC-PHI-9 (live-verified)** | proved that *authority outliving a status* is a real, reproduced exposure in the sibling model — a `cancelled` coach retained progress-photo access |
| `coach_team_invites` | has `accepted boolean` — a two-state acceptance flag, not a membership lifecycle |

| Supported option | Security consequence | Implementation consequence |
|---|---|---|
| **(1) No status — deletion is revocation** | Simplest; **no stale-authority risk by construction**. But loses audit history of prior membership, and deletion is irreversible | No schema change. **`is_team_lead_of()` needs no status filter** |
| **(2) Add status (e.g. pending / active / revoked)** | Enables consent flows and reversible revocation — **but only if every consumer filters it.** Adding a status without updating `is_team_lead_of()` and `may_notify()` **recreates SEC-PHI-9 on a new table** | Schema change + own migration + backfill decision (0 rows in QA; **production unknown**) + **both helpers must be updated in the same wave (C7/C8)** |

**The trap to state explicitly:** option (2) is the more capable design and the more dangerous one to
implement partially. SEC-PHI-9 is the proof — it is precisely "a status column exists and the
consumer ignores it."

**Affected V5 requirements:** none directly; V5 defines no team lifecycle. Audit interaction: a
revoked-vs-deleted choice affects what the audit trail can reconstruct (A5/A6).

## 5 · D1(iii) DECISION GATE — WHAT MAY A LEAD READ OF A MEMBER'S PROFILE?

**Evidence — this is the most precisely answerable of the three**

| Source | Finding |
|---|---|
| **Current grant** | `user_profiles` SELECT arm `is_team_lead_of(id)` grants **the entire row** — including **`parq_answers` (PAR-Q medical history)**, `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`, `membership_tier`, `stripe_details_submitted` |
| **What the only consumer actually reads** | `coach_business_screen.dart:67` embeds exactly **4 columns**: `first_name, last_name, email, avatar_url` |
| Gap | the grant exceeds the requirement by the **entire health and billing surface** |
| V5 | **silent** on team-lead entitlement |
| Admin brief | *"Sensitive data is minimized and exposed only when required"* (§12) — a principle, not a column list |
| Existing correction attempt | `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` proposes a 4-column view — but **NEW-5 established it is non-functional as written** (`security_invoker = on` + dropping the base arm ⇒ `200 []` for exactly the users it serves) |
| Precedent that works | `conversation_participant_profiles` — `security_invoker=off` + `security_barrier=true` + a predicate **inside** the view, 5 columns |

| Supported option | Security consequence | Implementation consequence |
|---|---|---|
| **(x) Nothing** — drop the `is_team_lead_of` arm entirely | Maximum reduction; **eliminates this PHI path** | The roster screen must read elsewhere; a view is still required for names/avatars |
| **(y) Four columns** (`first_name, last_name, email, avatar_url`) via a column-limited view | Matches the measured requirement exactly. **Still exposes every member's email** — PII, and an open product question | Requires the **corrected** view pattern (invoker `off` + barrier + predicate inside), and a **PostgREST embed rewrite**: the screen currently uses an embedded resource, which does not traverse a view — likely a two-step read |
| **(z) Whole row (status quo)** | **Retains the P0's PHI consequence even after the write path is hardened** | No change |

**Explicit answer to "is PAR-Q/health-sensitive information accessible": YES, today it is.** A
self-asserted team lead can read a member's `parq_answers`, weights, goal weight and transformation
photo URLs. **That is the P0's consequence and it is not remediated.**

**Affected objects:** `user_profiles` SELECT policy · `is_team_lead_of()` · the proposed
`team_member_profiles` view · `coach_business_screen.dart:67`.

## 6 · EVIDENCE SUPPORTING EACH OPTION — consolidated

| Decision | Strongest evidence available | What it does **not** establish |
|---|---|---|
| D-D1 | zero occurrences of "Trust" in both authoritative sources; both nest the capabilities in Admin | whether the owner *intends* a separate surface — an intent no artefact records |
| D1(i) | **no code inserts memberships** (so (a) is free of app impact); `coach_team_invites` shows consent intent; `coach_client_relationships` supplies a hardened precedent | which of the four the owner wants; (c) is a trap |
| D1(ii) | no status column; `is_team_lead_of()` has no status filter; **SEC-PHI-9 proves partial adoption is dangerous** | whether reversible revocation is a product requirement |
| D1(iii) | **the only consumer reads exactly 4 columns**; the grant is the whole row incl. PAR-Q | whether `email` should be visible to a team lead (a product/legal question, flagged in SEC_PHI_1) |

## 7 · EXACT SECURITY FOUNDATION BLAST RADIUS

Derived from the live catalog, read-only.

| Element | Exact scope |
|---|---|
| **Policies to change** | **1** — `public.coach_team_members` · `"Head coach manages team"` (`002_ecosystem_additions.sql:146`) |
| **SECURITY DEFINER functions affected** | **2** — `is_team_lead_of(uuid)` (no status filter), `may_notify(uuid)` (no status filter on either anchor) |
| **Dependent policies** | **2** — `user_profiles` SELECT (`"own profile or active coach reads profile"`, via `is_team_lead_of`) · `notifications` INSERT (`"notify a known counterparty"`, via `may_notify`) |
| **Nothing else in the schema references the table** | verified: 0 other policies, 0 other functions, 0 views, 0 triggers |
| Table facts | `role text NOT NULL` (unconstrained) · **no status column** · **0 triggers** · **0 check constraints** · grants to `authenticated`: SELECT/INSERT/UPDATE/DELETE · **0 live rows** |
| App code touching it | **1 site, read-only** — `coach_business_screen.dart:66` |
| Adjacent table, same defect, **out of scope** | `coach_team_invites` — `cmd=ALL`, `with_check` NULL; written at `coach_business_screen.dart:256` |
| Guard tests affected | `rls_policy_shape_guard_test.dart` (**SEC-G1**, baseline 15 → must **lower**) · `privilege_chain_guard_test.dart` (**CHAIN-G1**, baseline 1; **excludes `notifications`** — documented gap) |
| Migration band | **132+**, *"assigned at wave entry, never before"*; highest existing `131_identity_constraints.sql` |
| **Explicitly NOT in scope** | `hosts_event_for` / QAX-SEC-09 (D2) · SEC-PHI-9/10 predicates (D3) · `SEC_PHI_1` views (D17) · Admin · Trust · Guardian · wearable · monetization |

## 8 · PARAMETERIZED IMPLEMENTATION PLAN

**No migration is drafted.** The existing governance contract reserves migration numbers for wave
entry and the `WITH CHECK` expression *is* the owner decision — writing it would decide D1. This is a
patch **plan**, as instructed.

### Invariants — true under every option

| # | Invariant |
|---|---|
| C1 | One migration, **132+** band, number assigned at wave entry, single transaction |
| C2 | `DROP POLICY IF EXISTS` then `CREATE POLICY` — **the old policy must not remain alongside a new one**; multiple permissive policies OR together and would preserve the defect |
| C3 | The new policy **must carry an explicit `WITH CHECK`** — a `FOR ALL` policy with `USING` and no `WITH CHECK` reuses `USING` as the INSERT check. That reuse *is* the defect |
| C4 | **SELECT semantics preserved** for legitimate readers or `coach_business_screen.dart:66` breaks |
| C7 | **`is_team_lead_of()` re-examined in the same wave** — hardening the write path gives the helper no lifecycle |
| C8 | **`may_notify()` re-examined in the same wave** — F-03b shares the root; note its `coach_client_relationships` arm is a **separate residual** that this wave does not close |

### Where D1 changes the implementation — explicitly

| D1 answer | Migration content | Schema change? | Helper change? | App change? | Extra migration? |
|---|---|---|---|---|---|
| **(i)(a)** member-initiated | lead arm `with check (false)` + member-insert policy | **NO** | none required | **none** (nothing inserts today) | no |
| **(i)(b)** lead-initiated pending-only | `with check` constrains status | **YES — add status** | **YES — both helpers must filter status** | none | **YES** |
| **(i)(c)** role-validated | `with check (coach_id = auth.uid() AND is_coach_profile(coach_id))` | NO | none | none | no · **⚠ does not close the P0** |
| **(i)(d)** mutual consent | as (a) **plus** harden `coach_team_invites` + build the conversion mechanism | possibly | YES | **YES — acceptance flow must be built** | **YES** |
| **(ii)(1)** no status | — | NO | none | none | no |
| **(ii)(2)** status added | — | **YES** | **YES (C7/C8) — mandatory** | none | **YES** + backfill decision |
| **(iii)(x)** grant nothing | drop the `is_team_lead_of` arm from `user_profiles` SELECT | NO | none | **YES — roster needs another source** | view migration |
| **(iii)(y)** 4 columns | corrected view: `security_invoker = off` + `security_barrier = true` + predicate **inside** | NO | none | **YES — PostgREST embed → two-step read** | **YES** |
| **(iii)(z)** whole row | none | NO | none | none | no · **⚠ retains the PHI consequence** |

**Two combinations are flagged as unsafe-looking-safe:** `(i)(c)` alone, and `(ii)(2)` without
`(C7)`. Both leave the P0 substantially open while appearing addressed.

## 9 · VERIFICATION CONTRACT

| # | Verification | Expected PASS | FAIL means |
|---|---|---|---|
| **V1** | Non-member attempts `INSERT` naming a victim as `member_id` | **denied** (42501 / RLS violation) | fix ineffective |
| **V2** | A legitimately created membership still yields the roster read | **200 with rows** | **regression — the SEC-PHI-9 / NEW-5 lesson** |
| **V3** | Forged `notifications` INSERT to a stranger (F-03b) | **denied** | F-03b not closed |
| **V4** | Mutation-test every new/changed guard; classify KILLED / SURVIVED / **INVALID** | all **KILLED** | guard is vacuous |
| **V5** | SEC-G1 baseline | **lowered**, never raised | discipline breach |
| **V6** | CHAIN-G1 widened to include `notifications` | present | the F-03b gap persists |
| **V7** | Policy population re-derived **from the live catalog** | 37 policies / 34 tables reconciled | source-derived undercount (33) |
| **V8** | `user_profiles` SELECT still serves `id = auth.uid()` and `is_active_coach_of(id)` | **200** | clinical coach path broken |
| **V9** | Simulate before applying (replay harness) | simulated | **currently blocked — B10, no Docker. Flagged, not waived** |
| **V10** | Post-change catalog read confirms `with_check` is **non-null** | non-null | change did not take effect |

**Evidence-class caveat:** V1 and V3 require **writes to shared QA**, previously declined. Either
authorization is granted for the verification window, or the wave ships on catalog-confirmed evidence
with the execution gap **explicitly recorded as a known limitation**. That is a decision, not an
oversight.

## 10 · REGRESSION / ADVERSARIAL TEST PLAN

| Class | Test | Rationale |
|---|---|---|
| **Regression** | roster read at `coach_business_screen.dart:66` returns the same shape | the only consumer |
| Regression | `user_profiles` self-read and active-coach read unaffected | V8 |
| Regression | full mobile tier (1,675 pass / 9 skipped), API tier (64), contract tier | no collateral damage |
| **Adversarial** | insert naming self as `coach_id` **and** a stranger as `member_id` | the original F-21 shape |
| Adversarial | **self-register as a coach first, then retry** | defeats option (c) — proves whether (c) actually closed anything |
| Adversarial | insert with `role` set to an arbitrary string | `role` is `text NOT NULL`, unconstrained |
| Adversarial | if a status is added, insert directly at `active` | the SEC-PHI-9 shape on a new table |
| Adversarial | if a status is added, insert `pending` then read `parq_answers` | proves whether C7 was honoured |
| Adversarial | **create a self-asserted `coach_team_invites` row** | the adjacent unhardened table — proves the wave's boundary is understood, not that it is fixed |
| Adversarial | chain: membership → `may_notify` → `notifications` | F-03b end-to-end |
| **Mutation** | revert the `WITH CHECK`; confirm the new guard **fails** | a guard that cannot fail protects nothing |
| **Mutation** | plant a 16th `FOR ALL`/no-`WITH CHECK` policy; confirm SEC-G1 catches it | detector non-vacuity |

## 11 · SKILLS-AGENT EXECUTION PLAN — post-decision, **not executed**

**Mutation boundary is narrow by design: the Security Foundation only.** Admin, Trust, AI Guardian,
Wearable Intelligence and all other V5 work are **outside the boundary** and no agent may pull them
in.

| # | Agent | Scope | Allowed files | Forbidden | Acceptance criteria | Rollback trigger |
|---|---|---|---|---|---|---|
| 1 | **Architecture** | ADR recording D1(i)(ii)(iii) and the selected option shapes | `docs/**` | any code/SQL | ADR cites the decision + the in-schema precedent; wave number requested | n/a |
| 2 | **Database** | the policy migration (+ status/view migrations **only if** D1 requires) | `supabase/migrations/132+*.sql` | app code, other tables, other findings | V10 + catalog-verified; single transaction | restore prior policy in one transaction |
| 3 | **Security** (independent) | adversarial + verification | `apps/mobile/test/**`, `docs/**` | **product code, migrations, policies** | **V1, V2, V3 pass**; §10 adversarial set executed; SA-03 evidence recorded | any of V1/V2/V3 fails |
| 4 | **Testing** | guard updates | `apps/mobile/test/**` | product code | V4, V5, V6, V7 | mutation SURVIVED |
| 5 | **Mobile** (conditional) | only if D1(iii)(x)/(y) changes the roster read | `coach_business_screen.dart` + tests | migrations, policies | roster renders; ERR-G2 respected | screen regression |
| 6 | **QA** | evidence ledger | `apps/mobile/test/**`, `docs/**` | product code | 3 tiers green at the new HEAD; ledger updated | tier regression |

**Sequence:** 1 → 2 → (3 ∥ 4) → 5 (conditional) → 6. **Agent 3 must not be the same actor as
Agent 2** — independent verification is a standing requirement.

**Standing constraints:** evidence-first (never infer a PASS) · no silent scope expansion · shrinking
allowlists never grow · migration numbers at wave entry only · a detector must be proven able to find
a planted defect before a zero result is believed · stop at a governance boundary rather than route
around it · **no agent answers an owner decision**.

## 12 · QA CARRY-FORWARD MATRIX

| Finding | Evidence status | Affected by this remediation? | Exact retest | Closure evidence required | Remaining blocker |
|---|---|---|---|---|---|
| **QAX-SEC-08** P0 | OPEN / PARTIALLY VERIFIED | **YES — it is the target** | V1, V2, V8 | forged insert denied **+** legitimate read intact **+** SEC-G1 lowered | **D1**; shared-QA write authz for V1 |
| **F-03b** P1 | OPEN / PARTIALLY VERIFIED | **YES — same root** | V3, V6 | forged notify denied **+** `may_notify` status-filtered on **both** anchors | **D1**; write authz |
| **QAX-SEC-09** P1 | OPEN / **BLOCKED** | **NO — separate path (`hosts_event_for`)** | vendor probe | minimum-necessary attendee fields | **D2** + `events.vendor_id` fixture |
| **SEC-PHI-9** P1 | **OPEN / VERIFIED** (live) | **NO — different table; same class** | former-coach deny + active-coach intact | both proven live | **D3** |
| **SEC-PHI-10** P1 | OPEN / INFERRED | NO | `score_events` probe | predicate enforced **and demonstrated** | **D3** + fixture |
| **SEC-AI-1** P1 | OPEN / INFERRED | NO | — | disclosure matches implementation | **D10** |
| **NEW-2** P2 | OPEN | NO | post-fix read denial | `WITH CHECK` + status predicate | — |
| **NEW-5** P2 | OPEN | **YES if D1(iii)(y)** — it is the view pattern | corrected view returns rows | both screens functional | **D17** |
| **NEW-7** P2 | OPEN (3 stale) | NO | unskip K-12/K-ENV-1 | specs act as guards; **K-09 reviewed** (proxy assertion) | — |
| **NEW-10** LOW **(new)** | OPEN | NO | invite insert failure surfaces | failure reported to the coach | — |
| QAT-1 · NEW-8 · NEW-9 | P2/P3 | NO | CI run | 7 gates execute **in CI** | env/config |
| NEW-3 P3 | OPEN | NO | — | reviews gated | — |
| K-01 · K-02/K-06 · K-03 · K-04 · K-05 · K-07 | P2/P3 | **K-04 partially — it is an RLS defect of the same class** | spec assertions | all 6 unskipped and passing | D9 |

**Partial domains carried:** PHI table access 0.75 · supply chain 0.75 · test completeness 0.9 ·
AI/processors 0.5 · privacy alignment 0.5 · **replay harness 0.5 (blocked — and V9 needs it)**.

**QA remains 18.90 / 21 = 90.0%. Nothing was closed, and the percentage was not increased.**

## 13 · V5 DEPENDENCY MAP

```
OWNER DECISIONS
  ├─ D-D1 (Trust container) ──► removes 8 design deps + phase P6 under (B)/(C)
  └─ D1(i)(ii)(iii) ──────────► SECURITY FOUNDATION  ◄── the only design-free workstream
                                      │
                                      ├─► closes QAX-SEC-08 (P0)
                                      ├─► closes F-03b (P1)
                                      └─► does NOT close QAX-SEC-09 (hosts_event_for, D2)
                                          does NOT close SEC-PHI-9/10 (D3)
D4 + A2/A12/A13 (AUDIT) ──► Admin audit ──► Trust capabilities ──► AI Guardian
        (deepest chain; 7 decisions open)
CONF-D4/D5/D6 (DESIGN) ──► Admin ──► (Trust under (A)) ──► Guardian UI
D-V1/V2/V3/V4 (WEARABLE) ──► ingestion ──► intelligence ──► mobile UX ──► partner APIs
CONF-03/D-V6/D14 (RELEASE) ──► SBOM ──► release-integrity chain
B10 (Docker) ──► V9 simulate-before-apply        [evidence only, not implementation]
B11 (egress/secrets) ──► security+AI tiers, E2E  [evidence only]
```

**Parallelizable with the Security Foundation:** monetization / the 6 open K specs · CI gate repair
(QAT-1, D13) · audit **architecture decisions** · wearable **architecture decisions**.

## 14 · EXACT AUTHORIZATION CONDITIONS FOR BEGINNING MUTATION

Mutation may begin when **all** of the following hold:

| # | Condition | Status |
|---|---|---|
| 1 | **D1(i)** answered — who may create a membership | **✘ AWAITING OWNER** |
| 2 | **D1(ii)** answered — status lifecycle, with states enumerated if yes | **✘ AWAITING OWNER** |
| 3 | **D1(iii)** answered — what a lead may read, explicitly addressing PAR-Q | **✘ AWAITING OWNER** |
| 4 | Wave migration number assigned in the 132+ band | ✔ procedure defined; number assigned at wave entry |
| 5 | Architecture ADR approved recording 1–3 | ✔ contract defined (Agent 1) |
| 6 | Mutation boundary accepted — Security Foundation **only** | ✔ §11 |
| 7 | Verification authorization — either shared-QA writes for V1/V3, **or** explicit acceptance of catalog-only evidence | **✘ OWNER — one line** |
| 8 | Independent verifier distinct from implementer | ✔ §11 |
| 9 | D-D1 answered | **✘ AWAITING OWNER** — *does not block the Security Foundation*, only Admin/Trust scope |

**Conditions 4, 5, 6 and 8 are satisfied. Conditions 1, 2, 3 and 7 are the gate.**

---

## SUMMARY

### Completely ready
Blast radius (1 policy, 2 functions, 2 dependent policies, verified live) · scope boundary with
explicit exclusions · migration band and procedure · rollback (policy-only, reversible, **no
backfill** — 0 rows) · a 10-point verification contract · a 12-case regression/adversarial plan ·
a 6-agent execution plan with acceptance and rollback criteria · **no design dependency whatsoever**.

### Waiting only on owner decisions
**D1(i), D1(ii), D1(iii)** — and one line on **verification authorization** (condition 7).
**D-D1** separately gates Admin/Trust scope but **not** this workstream.

### Environmentally blocked (evidence, not implementation)
**B10** Docker → V9 simulate-before-apply · **B11** HTTPS egress + CI secrets → security/AI tiers and
E2E journeys · shared-QA write authorization → live V1/V3 execution.

### The decisions the owner must provide
1. **D1(i)** — may a lead add a member unilaterally? *(Note: no code inserts memberships today, so
   the most restrictive option breaks nothing.)*
2. **D1(ii)** — does membership carry a status lifecycle? If yes, enumerate the states. *(Note: adding
   a status without updating both helpers recreates SEC-PHI-9 on a new table.)*
3. **D1(iii)** — what may a lead read? *(Note: today it is the whole row including PAR-Q; the only
   consumer reads 4 columns.)*
4. **Condition 7** — live verification against shared QA, or catalog-only evidence with the gap
   recorded.
5. *(Separately, for Admin/Trust scope)* **D-D1**.

### The exact next authorized mission once supplied
**V5 SECURITY FOUNDATION IMPLEMENTATION WAVE 1** — Agent 1 (Architecture ADR) → Agent 2 (single
policy migration in the 132+ band) → Agents 3 & 4 (independent security verification + guard updates)
→ Agent 5 (conditional mobile) → Agent 6 (QA evidence). Mutation boundary: the Security Foundation
only. Success = V1–V10, with V9 explicitly waived-and-recorded if Docker remains unavailable.

---

*Documentation-only. QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**; 1 P0 and 4 P1 open, none
closed or downgraded. The P0 is **not** fixed, and fixing `coach_team_members` will **not** establish
that all `user_profiles` PHI is safe — `hosts_event_for()` remains a separate profile-access path
(QAX-SEC-09 / D2). No owner decision was taken. No policy, migration, schema, RLS, code, CI or
database change was made; all database access was read-only. **Implementation remains
unauthorized.***
