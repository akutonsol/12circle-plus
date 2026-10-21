# V5 · D-D1 + D1 + SECURITY FOUNDATION AUTHORIZATION ANALYSIS

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** DOCUMENTATION-ONLY. No implementation, no migration, no RLS change, no mutation.

> **IMPLEMENTATION REMAINS UNAUTHORIZED.**

---

## 1 · D-D1 — TRUST DECISION

### **STATUS: NOT RECORDED — THE DECISION FIELD WAS SUPPLIED UNFILLED**

The governing instruction contained:

```
TRUST = [INSERT OWNER DECISION HERE]
```

**The placeholder was not replaced, so no owner decision was supplied. I have not filled it in.**
Recording a decision on the owner's behalf — even one the evidence and the instruction's own
conditional block both point toward — would convert this governance chain's central discipline into
theatre. Every prior mission in this chain refused the same thing.

### The evidence, restated so the decision needs no further analysis

| Source | Finding |
|---|---|
| V5 specification | the word **"Trust" never appears** in 335 paragraphs |
| Admin build spec V1 | the word **"Trust" never appears**; it places **Security** and **AI Guardian** as top-level *Admin* nav items (§2) and *"Security & Governance"* — auth, authorization/RLS, admin actions, sensitive-data access, audit logs, security events — as an *Admin operational layer* (§6) |
| Repository | **0** trust/guardian/incident implementation files |
| Design artefacts | **0** mentions of Trust / AI Guardian / Incidents across 7 design documents; **no Trust package anywhere on disk** |
| Prior reconciliation | treating Trust as a separate surface would require **inventing** requirements — and the instruction explicitly forbids that |

**Of the four candidate readings, (B) "a subsection of Admin" and (C) "a governance/security layer
rather than a UI module" are the only ones with evidentiary support. (A) "a separate
product/module" has support in neither authoritative source. (D) "not required" is contradicted —
the *capabilities* are unambiguously required; only the *container* is unevidenced.**

### Pre-drafted record — enters the ledger on a one-word confirmation, not before

> **If the owner confirms "Trust capabilities are implemented within the Admin Control Center":**
> - Trust is **NOT** a separate product surface.
> - Trust capabilities become **Admin governance/security capabilities**.
> - **No** separate Trust application or navigation hierarchy is created.
> - **No** separate Trust design package is required — which removes **8 of the 23 design
>   dependencies** and **an entire build phase (P6)** from the implementation sequence.
> - Security, Incidents, Audit and AI Guardian remain within the Admin architecture unless V5
>   explicitly requires otherwise.
> - **CONF-D2 closes. D-D1 closes. Blocker count drops 6 → 6** (B2 still open on the Admin package),
>   but B2's *scope* shrinks by the whole Trust half.

> **If the owner decides Trust IS separate**, the additional design authority required is: a Trust
> product specification (V5 provides none), a Trust navigation hierarchy, and design packages for
> **Trust Home · AI Guardian · Security · Incidents · Audit Logs · Reviews · Policies · Alerts** —
> **8 surfaces, none of which exists in any form**, and 3 of which (Trust Home, Reviews, Policies)
> are not named in V5 either, so they would need requirements authored first.

## 2 · TEAM SEMANTICS — EVIDENCE

Gathered live from the QA catalog (read-only), not from memory or UI terminology.

### 2a · `coach_team_members` — complete structure

| Column | Type | Nullable |
|---|---|---|
| `id` | uuid | NO |
| `coach_id` | uuid | **NO** |
| `member_id` | uuid | **NO** |
| **`role`** | **text** | **NO** |
| `added_at` | timestamptz | YES |

| Property | Value |
|---|---|
| Policies on the table | **1** — `"Head coach manages team"` `FOR ALL USING (coach_id = auth.uid())`, **`with_check` NULL** |
| Role check in that policy | **NONE** — `has_role_check = false`; calls neither `is_coach_profile()` nor any `role` test |
| **Status column** | **DOES NOT EXIST** |
| Triggers | **0** |
| Check constraints | **0** |
| Grants to `authenticated` | **SELECT, INSERT, UPDATE, DELETE** (+ REFERENCES, TRIGGER, TRUNCATE) |
| Live rows | **0** |

**Newly surfaced and material to D1: the table already carries a `role text NOT NULL` column** —
so a per-membership role concept exists in the schema. It has **no check constraint and no enum**,
so any string satisfies it, and with 0 rows there is no data to infer a domain from. **Its intended
value set is unspecified.**

### 2b · The complete dependency set — precise and small

| Consumer | Kind | Reads via | Status filter |
|---|---|---|---|
| `is_team_lead_of(uuid)` | SECURITY DEFINER function | direct | **NO** |
| `may_notify(uuid)` | SECURITY DEFINER function | direct | **NO** — the word *status* appears only in a comment about `class_bookings` |
| `user_profiles` · `"own profile or active coach reads profile"` | **SELECT policy** | via `is_team_lead_of` | — |
| `notifications` · `"notify a known counterparty"` | **INSERT policy** | via `may_notify` | — |

**That is the entire blast radius: 2 functions, 2 policies.** No other policy, function, view or
trigger in the schema references `coach_team_members`.

### 2c · The contrasting idiom — `coach_client_relationships`, fully hardened

The same schema contains a thoroughly hardened relationship model:

```sql
-- INSERT
WITH CHECK ( coach_id <> client_id
         AND is_coach_profile(coach_id)
         AND ( (client_id = auth.uid() AND initiated_by = 'client'
                AND status = ANY(ARRAY['pending','active']))
            OR (coach_id  = auth.uid() AND initiated_by = 'coach'
                AND status = 'pending') ) )
-- UPDATE
WITH CHECK ( client_id = auth.uid()
          OR (coach_id = auth.uid() AND (status <> 'active' OR initiated_by = 'client')) )
```
Plus **2 triggers**: `set_relationship_client_source`, `enforce_relationship_integrity`.

**The principle this encodes, stated as an observation:** *a party may not unilaterally conscript
the other into an active relationship.* A **client** may create a relationship at `pending` **or
`active`** (self-service onboarding); a **coach** may only create it at `pending`. Escalation to
`active` is further constrained by the UPDATE check and the integrity trigger.

### 2d · Terminology across all sources

| Term | V5 | Admin brief | Repository |
|---|---|---|---|
| "team" | **absent** | **absent** | `coach_team_members` |
| "team lead" | **absent** | **absent** | **not a role** — emergent from a row, via `is_team_lead_of()` |
| coach | *Trainer/Coach* | Coach | `role='coach'`, **self-assertable at signup** |
| client / member | *Client/Member* | Clients/Members | `role='client'`, self-assertable |
| Wellness Partner | *Wellness Partner* (5×) | Wellness Partners | **`vendor`** — **neither source uses this word**; 0 users |
| client membership | ecosystem contract (SQ-02/03) | data domain only | `coach_client_relationships.status` |
| vendor relationship | — | display only | `events.vendor_id` → `hosts_event_for()` → **full profile row** |

## 3 · D1 — THE FIVE QUESTIONS, ANSWERED FROM EVIDENCE

### Q1 · What relationship semantics are actually implemented today?

**Two mutually inconsistent models coexist:**

| | `coach_client_relationships` | `coach_team_members` |
|---|---|---|
| Lifecycle | **status-bearing** (pending/active/cancelled/declined) | **none — no status column** |
| Who may create | constrained by `initiated_by` + actor + status | **anyone** (`coach_id = auth.uid()`, no `WITH CHECK`) |
| Counterparty validated | **yes** — `is_coach_profile(coach_id)`, `coach_id <> client_id` | **no** |
| Escalation control | UPDATE `WITH CHECK` + integrity trigger | **none** |
| Revocation | set `status='cancelled'` | **delete the row** (no revoked state) |
| Per-membership role | no | **`role text NOT NULL`, unconstrained** |

### Q2 · What semantics does the security model *assume*?

This is the decisive question, and the answer is the defect:

**`is_team_lead_of()` assumes that the existence of a `coach_team_members` row is a trustworthy
authorization fact** — i.e. that such a row could only have been created by a legitimate process, and
that it remains valid indefinitely. **Neither assumption holds.** The row is self-assertable by any
authenticated account, and there is no state in which it is expired, revoked or pending.

**`may_notify()` makes the same assumption**, and additionally treats
`coach_client_relationships` at *any* status as sufficient.

**The consuming policy on `user_profiles` then assumes `is_team_lead_of()` means "is entitled to the
member's entire profile row"** — including `parq_answers` (PAR-Q medical history), `weight_kg`,
`goal_weight_kg`, `transformation_photo_urls`, `membership_tier` and billing flags.

**Stated precisely: membership is conflated with authority, and that authority has no lifecycle.**

### Q3 · Which semantics are explicitly specified?

| Specified | By whom |
|---|---|
| Coach ↔ Client/Member ↔ Wellness Partner as the **ecosystem triad** | V5 SQ-02/SQ-03 |
| Client-membership lifecycle | the repository, via `coach_client_relationships.status` + triggers |
| That a coach may not unilaterally create an *active* client relationship | that table's `WITH CHECK` |
| That `admin` / `content_manager` are **not self-assertable**; `client`/`coach`/`vendor` **are** | `enforce_profile_privilege()` |

### Q4 · Which semantics are missing?

1. **What a "team" is.** No source defines it. V5 has three personas and **no team concept at all**.
2. **Who may create a membership** — unilateral by the lead, member-initiated, or mutual.
3. **Whether membership has a lifecycle** (pending / active / revoked).
4. **What a team lead is entitled to read** — the current answer is *the entire profile, including
   PAR-Q*, which no source states as intended.
5. **The value domain of `coach_team_members.role`** — `NOT NULL text` with no constraint.
6. **Whether "team" and "coach–client relationship" are distinct concepts or one concept with two
   implementations.**
7. **Whether Wellness Partner maps to `vendor`** — neither V5 nor the brief uses the word `vendor`.

### Q5 · The exact owner decision required

> **D1 — TEAM SEMANTICS (unanswered; no default exists in any source):**
>
> *"Define what a 'team' is in 12Circle and who may create a `coach_team_members` row:*
> *(i) **Creation** — may a lead add a member unilaterally, must the member initiate, or must both
> consent? Note the schema already contains a precedent in `coach_client_relationships`, where a
> coach may only create a `pending` row while the client may create `pending` or `active`.*
> *(ii) **Lifecycle** — does membership carry a status (pending/active/revoked), or does removal mean
> deleting the row? Without a status there is no revocation state, and `is_team_lead_of()` cannot
> express "was a lead".*
> *(iii) **Entitlement** — should being a team lead grant any read of a member's profile, and if so
> which columns? Today it grants the whole row, including PAR-Q medical history.*
> *(iv) **`role` column** — what is its permitted value set?*
> *(v) **Relationship to `coach_client_relationships`** — are these two distinct concepts, or should
> teams be expressed through the already-hardened relationship model?"*
>
> **Consequence of delay:** the P0 (QAX-SEC-08) and P1 (F-03b) both remain open, and **one change
> closes both**. Governance: **OD-14** (the policy population) and **OD-QAX-9** (team semantics).
>
> **An existing model, recorded as a model and not a recommendation:** the Cloud workstream's
> `fixsim/QAX-SEC-08.sql` proposes `with check (false)` on the lead's arm plus a member-initiated
> insert policy. It aligns with the `coach_client_relationships` precedent. **It is not an approved
> policy.**

**D1 REMAINS OPEN.** No semantics were inferred from UI terminology; "team lead" appears in no
authoritative source, and `coach_team_members.role` was not assumed to encode it.

## 4 · P0 / P1 RELATIONSHIP IMPACT

| Finding | Dependency on D1 | Closed by the same change? |
|---|---|---|
| **QAX-SEC-08** (P0) — self-assert → `is_team_lead_of` → full `user_profiles` PHI read | **Total.** The fix *is* the answer to D1(i)–(iii) | — |
| **F-03b** (P1) — `may_notify()` trusts the same table → forged `notifications` INSERT | **Total.** Same root | **YES — one `WITH CHECK` closes both** |
| **SEC-PHI-9** (P1, live-verified) — storage policy checks row existence, not `status` | **Pattern-level.** Different table; **same class of defect** (authority outliving lifecycle) | No — needs its own status predicate |
| **SEC-PHI-10** (P1, inferred) — `score_events`, same omission | Pattern-level | No |
| **QAX-SEC-09** (P1, blocked) — `hosts_event_for()` → full profile row for an event host | **Partial** — depends on **D2** (is `vendor` self-assertable?) rather than D1 | No |
| **SEC-AI-1** (P1) | None | No |

**Residual after a D1-driven fix, stated so it is not overlooked:** `user_profiles`' SELECT policy
has **four** arms — `id = auth.uid()`, `is_active_coach_of(id)`, `is_team_lead_of(id)`,
`hosts_event_for(id)`. Hardening `coach_team_members` closes the **third** arm's forgeability. The
**fourth** (`hosts_event_for`) still grants an event host the entire profile row, and that is
**QAX-SEC-09 / D2 — not covered by the P0 fix.** Anyone reading "the P0 is fixed" as "profile PHI is
now safe" would be wrong.

## 5 · SECURITY FOUNDATION SCOPE

Derived from the live catalog, so the blast radius is exact rather than estimated.

| Element | Precise scope |
|---|---|
| **Affected policy** | **1** — `coach_team_members` · `"Head coach manages team"` (`002_ecosystem_additions.sql:146`) |
| **Affected helper functions** | **2** — `is_team_lead_of(uuid)`, `may_notify(uuid)` — both SECURITY DEFINER, both without a status filter |
| **Affected PHI access paths** | **1** — `user_profiles` SELECT, third arm → whole row incl. `parq_answers`, `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`, `membership_tier`, billing flags |
| **Affected notification paths** | **1** — `notifications` INSERT `WITH CHECK (may_notify(recipient_id))` |
| **Affected tests** | `test/unit/rls_policy_shape_guard_test.dart` (**SEC-G1**, baseline 15 → must be **lowered**, never raised) · `test/unit/privilege_chain_guard_test.dart` (**CHAIN-G1**, baseline 1; **table filter excludes `notifications` — the documented gap**) |
| **Affected guard tests** | SEC-G1, CHAIN-G1; and the population should be **re-derived from the live catalog** (37 policies / 34 tables) rather than migration text (D15) |
| **Migration sequence** | next wave number in the **132+** band, *"assigned at wave entry, never before"* (`MASTER_REMEDIATION_WAVES.md`). Highest existing: `131_identity_constraints.sql` |
| **Rollback requirements** | policy-only change → reversible by restoring the prior policy definition; **no data migration, no backfill** (table has 0 rows in QA). A `DROP POLICY` / `CREATE POLICY` pair in one transaction |
| **Verification requirements** | see §6 |
| **NOT in scope** | `hosts_event_for` / QAX-SEC-09 (D2) · SEC-PHI-9/10 status predicates (D3) · `SEC_PHI_1` views (D17, **non-functional as written**) · anything Admin, Trust, Guardian or wearable |

## 6 · EXACT REMEDIATION CONTRACT

**This contract is PARAMETERIZED BY D1 and cannot be finalized until D1 is answered.** The exact
`WITH CHECK` expression is precisely the content of the owner decision, so specifying it here would
be deciding D1.

### Invariant across every D1 option

| # | Requirement |
|---|---|
| C1 | One migration in the **132+** band, number assigned at wave entry. Single transaction |
| C2 | `DROP POLICY IF EXISTS "Head coach manages team" ON public.coach_team_members;` then recreate — **the current policy must not be left in place alongside a new one**, or the permissive OR-semantics of multiple policies would preserve the defect |
| C3 | The recreated policy **must carry an explicit `WITH CHECK`**. A `FOR ALL` policy with `USING` and no `WITH CHECK` reuses `USING` as the INSERT check — that is the defect |
| C4 | **SELECT semantics must be preserved** for legitimate readers, or the team roster screen (`coach_business_screen.dart:67`) breaks |
| C5 | If D1 introduces a status column, that is a **schema change requiring its own migration** and a backfill decision (0 rows in QA, unknown in production) |
| C6 | If D1 constrains `role`, add a CHECK constraint or enum — currently `text NOT NULL`, unconstrained |
| C7 | **`is_team_lead_of()` must be re-examined in the same wave.** Hardening the write path does not give the helper a lifecycle; if D1 adds a status, the helper must filter it, or revocation still will not work |
| C8 | **`may_notify()` must be re-examined in the same wave** — F-03b shares the root; hardening the table closes the forgery, but `may_notify` also trusts `coach_client_relationships` at **any status**, which is a *separate* residual arm |

### The three option shapes D1 could produce

| Option | Shape (illustrative of the option space, **not a recommendation**) | Consequence |
|---|---|---|
| **(a) Member-initiated** | lead's arm `with check (false)`; a second policy lets `member_id = auth.uid()` insert | Matches the `coach_client_relationships` precedent. **Breaks any UI where a lead adds a member** — and `coach_business_screen.dart` would need review |
| **(b) Lead-initiated, pending-only** | lead may insert with a status of `pending`; member activates | **Requires a status column (C5)** and a helper change (C7) |
| **(c) Lead-initiated with role validation** | `with check (coach_id = auth.uid() AND is_coach_profile(coach_id))` | Smallest change, but **`role='coach'` is self-assertable at signup**, so it does not close the forgery — it only raises the bar to "register as a coach first" |

**Option (c) is recorded specifically to note that it looks sufficient and is not.** That is exactly
the trap the earlier `SEC_PHI_1` proposal fell into.

### Verification contract — required regardless of which option D1 selects

| # | Verification | Why |
|---|---|---|
| V1 | **Live denial** of the forged insert (victim named as `member_id` by a non-member) | proves the fix |
| V2 | **Live proof the legitimate path still works** — a properly created membership still grants the roster read | **the SEC-PHI-9 lesson**: a fix that breaks the legitimate path is a regression, and the earlier `SEC_PHI_1` proposal would have returned `200 []` to exactly the users it served |
| V3 | **Live denial** of the forged `notifications` INSERT (F-03b) | proves the second finding closed |
| V4 | **Mutation-test every new or changed guard**; classify KILLED / SURVIVED / **INVALID** | a guard that cannot fail protects nothing |
| V5 | **Lower** SEC-G1's baseline; never raise it | shrinking-allowlist discipline |
| V6 | **Widen CHAIN-G1 to include `notifications`** | its table filter currently excludes it — the documented gap that would have missed F-03b |
| V7 | **Re-derive the policy population from the live catalog** | source counting reports 33; the catalog holds **37 across 34 tables** (3 tables carry two matching policies) |
| V8 | Confirm `user_profiles` SELECT still serves `id = auth.uid()` and `is_active_coach_of(id)` | the clinical coach path must not break |
| V9 | **Simulate before applying**, ideally via the replay harness | blocked today (B10, no Docker) — **flagged, not waived** |

**Evidence class note:** V1 and V3 require **writes to shared QA**, which were declined earlier in
this programme. Either that authorization is granted for the verification window, or the fix ships
on catalog-confirmed evidence with the execution gap **explicitly recorded** — a decision, not an
oversight.

## 7 · SKILLS-AGENT HANDOFF CONTRACT — Security Foundation (prepared, **not executed**)

| Agent | Scope | Allowed files | Allowed mutations | Forbidden | Required tests | Security verification | QA evidence | Handoff condition | Rollback condition |
|---|---|---|---|---|---|---|---|---|---|
| **Architecture** | ADR recording D1's answer and the chosen option shape | `docs/**` | documentation only | any code, any SQL | — | — | ADR cites D1 + the in-schema precedent | **ADR approved by owner** | n/a |
| **Database** | the single policy migration | `supabase/migrations/132+*.sql` **only** | one migration, one transaction | app code, other migrations, other tables, **no schema change unless D1 requires a status column** | policy mutation tests | — | **live catalog** shows `with_check` non-null | migration applied **and** catalog-verified | restore prior policy definition in a single transaction |
| **Security** | **independent** verification | `apps/mobile/test/**`, `docs/**` | tests + docs only | **product code, migrations, policies** | V1–V8 | **V1 deny · V2 legitimate-path · V3 deny** | per-control SA-03 record (requirement, location, test, result, date, owner) | **no open P0/P1 in wave scope**; V2 passes | any of V1/V2/V3 fails |
| **QA** | evidence ledger | `apps/mobile/test/**`, `docs/**` | tests + docs | product code | full mobile + API + contract tiers | — | **executed** evidence, never inferred | tiers green at the new HEAD | tier regression |
| **Mobile** | **only if** D1's option changes the roster write path | `coach_business_screen.dart` + tests | minimal | migrations, policies | widget + guard tests | ERR-G2 compliance | design-QA n/a (no design change) | roster read/write still correct | screen regression |

**Standing constraints carried:** no agent may redefine V5 or answer an owner decision · migration
numbers at wave entry only · shrinking allowlists never grow · every guard mutation-tested · a
detector must be proven able to find a planted defect before a zero result is believed · never
convert "not tested" into PASS · stop at a governance boundary rather than route around it.

## 8 · QA CARRY-FORWARD — 19 items, **none closed**

| QA ID | Sev | Status | Closure criteria | Satisfied? |
|---|---|---|---|---|
| **QAX-SEC-08** | **P0** | OPEN / PARTIALLY VERIFIED | forged insert denied live **+** legitimate team read intact **+** SEC-G1 baseline lowered | **NO** |
| **F-03b** | P1 | OPEN / PARTIALLY VERIFIED | forged notify denied live **+** `may_notify` status-filtered on **both** anchors | **NO** |
| **QAX-SEC-09** | P1 | OPEN / **BLOCKED** | vendor sees only minimum-necessary attendee fields; needs an `events.vendor_id` fixture | **NO** |
| **SEC-PHI-9** | P1 | **OPEN / VERIFIED** | former coach denied **and active coach unbroken**, both live | **NO** |
| **SEC-PHI-10** | P1 | OPEN / INFERRED | status predicate enforced **and demonstrated**; needs `score_events` for the cancelled client | **NO** |
| **SEC-AI-1** | P1 | OPEN / INFERRED | disclosure matches implementation | **NO** |
| NEW-2 · NEW-5 · NEW-7 · NEW-3 · QAT-1 · NEW-8 · NEW-9 | P2/P3 | OPEN | per prior ledger | **NO** |
| K-01 · K-02/K-06 · K-03 · K-04 · K-05 · K-07 | P2/P3 | OPEN (K-04 live-confirmed) | specs unskipped and passing | **NO** |

**Partial domains carried:** PHI table access 0.75 · supply chain 0.75 · test completeness 0.9 ·
AI/processors 0.5 · privacy alignment 0.5 · **replay harness 0.5 (blocked — and §6 V9 needs it)**.

**The 90% residue has not disappeared.** QA remains **18.90 / 21 = 90.0%**, and the remaining 10% is
carried through the V5 lifecycle with retest points intact.

## 9 · REMAINING V5 BLOCKERS

| Blocker | Status | Gating input |
|---|---|---|
| **B1 Audit** | ADVANCED — 10 action classes enumerated; **7 decisions open** | D4, A2, A12, A13 + architecture A1/A3/A6/A-NEW |
| **B2 Design authority** | **OPEN** — Admin package NOT SUPPLIED; Fitonist MISSING; brand NOT LOCKED; no Trust artefact | CONF-D4/D5/D6 (+ **D-D1 would remove the Trust half**) |
| **B3 Wearable** | OPEN | D-V1, D-V2, D-V3 |
| **B4 Team semantics** | **OPEN — fully reconciled this mission; decision formulated (§3 Q5)** | **D1** |
| **B5 Wearable PHI** | ADVANCED — Admin/Guardian arm evidenced telemetry-only | D-V4 |
| **B7 Vendor** | OPEN | D2 |

**Blockers: 6 · resolved this mission: 0 · Owner decisions: 23 · Architecture decisions: 13 ·
Design dependencies: 23.**

**No count was reduced.** B4 is now fully *analysed* — its evidence is complete and its decision is
formulated to the point of being answerable in one sitting — but analysis is not closure.

## 10 · IMPLEMENTATION AUTHORIZATION STATUS

### **SECURITY FOUNDATION: NOT YET AUTHORIZED**

**One input blocks it: D1.** Everything else this workstream needs now exists —

| Prerequisite | Status |
|---|---|
| Blast radius | **✔ exact** — 1 policy, 2 functions, 2 dependent policies |
| Scope boundary | **✔** — §5, with explicit exclusions |
| Migration band | **✔** — 132+, assigned at wave entry |
| Rollback | **✔** — policy-only, reversible, no backfill |
| Verification contract | **✔** — V1–V9 |
| Skills-Agent contract | **✔** — 5 agents, files, mutations, handoff and rollback conditions |
| Design dependency | **✔ NONE** — this workstream needs no design artefact at all |
| **D1 — the exact `WITH CHECK` expression** | **✘ UNANSWERED** |

**Why the contract cannot simply be completed:** the `WITH CHECK` expression *is* the answer to D1.
Choosing it would decide who may create a team membership, whether membership has a lifecycle, and
what a lead may read — three product decisions, not implementation details. §6 therefore gives the
option *space* and the invariants, and stops there.

**One caution worth stating plainly:** option (c) — adding `is_coach_profile(coach_id)` — is the
smallest change and **looks sufficient without being sufficient**, because `role='coach'` is
self-assertable at signup. It would convert the P0 from "any account" to "any account that registered
as a coach", which is a lower bar than it appears. This is the same shape of error as the earlier
`SEC_PHI_1` proposal, which would have silently returned `200 []` to the users it was written to
serve.

---

**D-D1 TRUST DECISION: NOT RECORDED** — field supplied unfilled; evidence assembled and the record
pre-drafted for confirmation.
**D1: OPEN** — fully reconciled; decision formulated.
**SECURITY FOUNDATION: NOT YET AUTHORIZED** — blocked solely on D1.

---

*Documentation-only. QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**; 1 P0 and 4 P1 open, none
closed or downgraded. No owner decision was taken. No policy, migration, schema, RLS, code, CI or
database change was made; all database access was read-only. **Implementation remains
unauthorized.***
