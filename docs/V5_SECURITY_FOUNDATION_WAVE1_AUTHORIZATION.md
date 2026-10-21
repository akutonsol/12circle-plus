# V5 · SECURITY FOUNDATION WAVE 1 — OWNER DECISIONS & AUTHORIZATION

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** Decision record + authorization. **No mutation performed in this document.**

---

## 1 · OWNER DECISIONS — RECORDED AS SUPPLIED

### D1(i) — Team membership creation: **NO**

> *"Membership must not be created unilaterally by a team lead. Membership must originate through the
> invite/consent flow and only become an active membership after the required acceptance/consent
> step."*

Maps to **option (a)/(d)** of the prepared option space — member-initiated / mutual consent.

### D1(ii) — Membership lifecycle: **YES**

> *"Use an explicit membership lifecycle. Do not treat the existence of a `coach_team_members` row
> alone as proof of active authorization."*
>
> **States: `invited` · `active` · `suspended` · `revoked`**
> *"Only ACTIVE membership may satisfy team-lead authorization checks."*
> *"The authorization helpers `is_team_lead_of()` and `may_notify()` must evaluate the lifecycle state
> rather than merely the existence of a row."*

Maps to **option (2)** — status added, **with the C7/C8 helper updates mandated explicitly by the
owner.** This closes the trap the package flagged: a status column whose consumers ignore it.

### D1(iii) — Team-lead profile access: **MINIMUM NECESSARY; PHI EXCLUDED**

> *"A team lead may access only the minimum member information required for legitimate
> team-management functions."*
> *"PAR-Q, medical conditions, and other health-sensitive/PHI information are NOT accessible through
> team-lead membership authorization."*
> *"Do not expose the full `user_profiles` row to team leads."*

Maps to **option (y)** — a column-limited surface, with PHI explicitly excluded.

### Verification authorization: **A — LIVE VERIFICATION AUTHORIZED**

> *"AUTHORIZE live verification against shared QA after implementation, provided all mutations remain
> strictly within the approved Security Foundation scope and the verification is reversible and
> governed by the existing QA contract."*

**This resolves the evidence gap that has constrained this programme since the P0 was found.** V1 and
V3 can now be executed rather than inferred.

### D-D1 — Trust container

```
TRUST = [INSERT OWNER DECISION HERE]
```
**Preserved unfilled, as instructed.** It does not gate this wave.

## 2 · V5 RECONCILIATION — **NO CONTRADICTION FOUND**

Checked each decision against the governing specification.

| Decision | V5 position | Verdict |
|---|---|---|
| D1(i) NO unilateral creation | **V5 defines no team concept** — 0 occurrences of "team"/"team lead" in 335 paragraphs. Nothing to contradict. V5's GV-07 makes *"security, authorization, privacy… first-class"*, and V5 SQ-03 requires *"authoritative data flows, permissions, events, contracts"* | **CONSISTENT** — additive to V5, aligned with its principles |
| D1(ii) lifecycle with 4 states | V5 is silent on team lifecycle. **It does model status elsewhere** — the Admin Incident Model uses an explicit severity enum, and V3 requires *"lifecycle controls"* on wearable storage | **CONSISTENT** — matches V5's pattern of explicit state |
| D1(ii) helpers must evaluate state | V5 requires *deterministic authorization* (V4 §8: *"Implementation → deterministic authorization"*) | **CONSISTENT — and directly satisfies a V5 control** |
| D1(iii) PHI excluded from team-lead access | V5 SQ-34 requires *"minimization… sensitive-data boundaries"*; Admin brief §12: *"Sensitive data is minimized and exposed only when required"* | **CONSISTENT — implements a V5 requirement** |
| Verification A | V5 GV-08/SQ-13 require authorization testing; V2's QA-realism model requires *"deterministic, clearly marked, resettable, authorization-tested"* QA data | **CONSISTENT** |

**No contradiction with V5, the Admin build spec, or any prior governance document.** Two of the four
decisions (D1(ii) helper evaluation, D1(iii) minimization) *implement* V5 requirements that were
previously unmet.

### One consequence that must be stated before mutation, not after

**D1(i) requires an invite/consent flow that does not exist.** Verified again this mission:

| Component | Status |
|---|---|
| Invite creation | **exists** — `coach_business_screen.dart:256` inserts `coach_team_invites` |
| `send-invite-email` | **delivers mail only** — its own header: *"The app inserts the invite row, then calls this to deliver the…"* |
| **Acceptance mechanism** | **DOES NOT EXIST** — 0 triggers, 0 functions, **no insert/update/delete of `coach_team_members` anywhere in the app or edge functions** |

**This is not a contradiction — it is a scope boundary.** The decisions' *security* content is fully
implementable now; the *feature enablement* is separate work. Therefore:

| Wave | Content | Rationale |
|---|---|---|
| **WAVE 1 (authorized below)** | Deny unilateral creation · add the lifecycle · make both helpers evaluate it · remove PHI from the team-lead path | Pure security hardening. **No functional regression: teams are already non-functional** — 0 rows, no creation path |
| **WAVE 2 (not authorized)** | Harden `coach_team_invites` · build acceptance → membership conversion · the app acceptance surface | Feature enablement; needs its own scope and design |

**Explicit and important:** after Wave 1, **no membership can be created by anyone** until Wave 2
builds the consent path. That is the *current de facto state* (the table has 0 rows and no writer), so
Wave 1 removes a vulnerability without removing a working capability. Stated so it cannot be
discovered as a surprise.

## 3 · UPDATED IMPLEMENTATION CONTRACT — now concrete

**Migration band:** highest existing is `131_identity_constraints.sql` → **Wave 1 occupies `132`+**,
numbers assigned at wave entry.

**Specification only — no SQL is applied, and none is written into the repository by this document.**

### M1 · Lifecycle column (`coach_team_members`)

- Add `status text NOT NULL` with a **CHECK constraint** limited to `('invited','active','suspended','revoked')`.
- **Default for new rows: `invited`** — per D1(ii), existence must not imply authorization.
- **Existing-row treatment: `invited`, NOT `active`.** This is **determined by the owner's own
  decision**, not chosen here: *"Do not treat the existence of a `coach_team_members` row alone as
  proof of active authorization."* Grandfathering to `active` would contradict that sentence and would
  silently bless any already-forged row.
  **Operational consequence, flagged:** QA holds **0 rows**; **production state is unknown** (production
  has never been contacted, correctly). If production holds memberships, their team-lead access stops
  at this migration. **→ ADR sub-decision ADR-1.**
- Also add a CHECK constraining `role` (currently `text NOT NULL`, unconstrained; only observed value
  is `'assistant_coach'`). **→ ADR sub-decision ADR-2.**

### M2 · Replace the defective policy

- `DROP POLICY IF EXISTS "Head coach manages team" ON public.coach_team_members;` **then** recreate —
  the old policy must not survive alongside a new one (permissive policies OR together).
- New write semantics per D1(i): **the lead's arm must not permit INSERT.** Member-originated
  creation only, and a member may not self-assert `active` (that is Wave 2's acceptance step).
- **SELECT must remain available to the lead**, or the roster read at `coach_business_screen.dart:66`
  breaks.
- The recreated policy **must carry an explicit `WITH CHECK`** — the absent `WITH CHECK` is the defect.

### M3 · `is_team_lead_of()` — lifecycle-aware

Per D1(ii), must require `status = 'active'`. SECURITY DEFINER and `search_path` pinning preserved.

### M4 · `may_notify()` — lifecycle-aware

Per D1(ii), its `coach_team_members` arm must require `status = 'active'`.
**Residual recorded, not closed:** `may_notify()` *also* trusts `coach_client_relationships` at **any
status**. That arm is **F-03b's second half and is out of Wave 1 scope** (D3). Wave 1 closes the
team-membership forgery path; it does not make `may_notify()` wholly sound.

### M5 · Remove PHI from the team-lead path

Per D1(iii): the `is_team_lead_of(id)` arm must no longer grant the whole `user_profiles` row.
- Narrow the `user_profiles` SELECT policy accordingly.
- Provide a column-limited surface for the roster using the **corrected** pattern —
  `security_invoker = off` + `security_barrier = true` + the predicate **inside** the view. **Not** the
  `security_invoker = on` form in `docs/proposed/SEC_PHI_1_roster_attendee_views.sql`, which **NEW-5
  established returns `200 []` for exactly the users it serves.**
- Measured requirement: the only consumer reads **`first_name, last_name, email, avatar_url`**.
  **`email` is PII and its inclusion is a product question** flagged in SEC_PHI_1 — including it
  preserves current behaviour; excluding it is more minimizing. **→ ADR sub-decision ADR-3.**
- **No health, body-composition or billing column may appear** — PHI exclusion is absolute per D1(iii).

### M6 · App change (conditional on M5's shape)

`coach_business_screen.dart:67` uses a **PostgREST embedded resource**
(`user_profiles!coach_team_members_member_id_fkey(...)`). Embeds resolve against the base table and
**do not traverse a view**, so this likely becomes a two-step read. Scope: that one call site + tests.

### M7 · Guard updates

- **SEC-G1** baseline **lowered** (15 → 14); never raised.
- **CHAIN-G1** widened to include **`notifications`** — the documented gap that would have missed F-03b.
- Population **re-derived from the live catalog** (37 policies / 34 tables), not migration text.

### Three ADR sub-decisions Agent 1 must record before Agent 2 proceeds

| ID | Question | Default if unstated |
|---|---|---|
| **ADR-1** | Existing-row status on migration | **`invited`** — compelled by D1(ii)'s wording; flag that production team-lead access would stop |
| **ADR-2** | Permitted `role` values | at minimum `'assistant_coach'` (the only observed value) |
| **ADR-3** | Is `email` within "minimum necessary"? | include, preserving current roster behaviour; exclusion is the more minimizing option |

## 4 · UPDATED QA CLOSURE CRITERIA

| Finding | Closure criteria — updated for these decisions | Closable in Wave 1? |
|---|---|---|
| **QAX-SEC-08** (P0) | (1) unilateral lead insert **denied live**; (2) a non-`active` membership **does not** satisfy `is_team_lead_of()`; (3) `user_profiles` **PHI unreachable** via the team-lead path; (4) legitimate roster read intact; (5) SEC-G1 lowered | **YES** |
| **F-03b** (P1) | (1) forged `notifications` INSERT via team membership **denied live**; (2) `may_notify()` requires `status='active'` on the team arm; (3) CHAIN-G1 covers `notifications`. **Note:** the `coach_client_relationships` any-status arm remains open (D3) | **PARTIAL — team arm only.** Do not mark F-03b closed until the second arm is addressed |
| **QAX-SEC-09** (P1) | unchanged — `hosts_event_for()` is a **separate** profile path | **NO** (D2) |
| **SEC-PHI-9 / 10** (P1) | unchanged — different tables, same class | **NO** (D3) |
| **SEC-AI-1** (P1) | unchanged | **NO** (D10) |
| **NEW-5** (P2) | the corrected view pattern is **used** by M5 and returns rows for team leads | **YES, implicitly** |
| **NEW-10** (LOW) | out of scope | NO |

**QA remains 90.0% — QA COMPLETE WITH OPEN FINDINGS. All P0/P1 findings remain OPEN until
independently verified closed.** Wave 1 does not change the percentage; verified closures will.

## 5 · VERIFICATION SEQUENCE — live, per authorization A

Executed **after** implementation, by the **independent** Security agent (not the implementer), inside
the Security Foundation scope, reversible per the QA contract.

| # | Verification | Expected | Reversibility |
|---|---|---|---|
| **V1** | Lead (or any account) attempts to insert a membership naming a victim | **DENIED** | no row created |
| **V1b** | Member-originated insert attempts `status='active'` directly | **DENIED** | no row created |
| **V2** | A membership seeded to `active` yields the roster read | **200 + rows** | fixture deleted, deletion verified |
| **V2b** | Same membership at `invited` / `suspended` / `revoked` | **roster denies** | fixture deleted |
| **V3** | Forged `notifications` INSERT via a non-`active` membership | **DENIED** | no row created |
| **V3b** | `notifications` INSERT via an `active` membership | **permitted** | row deleted, deletion verified |
| **V4** | Mutation-test every new/changed guard — KILLED / SURVIVED / **INVALID** | all **KILLED** | n/a |
| **V5** | SEC-G1 baseline lowered, never raised | 14 | n/a |
| **V6** | CHAIN-G1 includes `notifications` | present | n/a |
| **V7** | Population re-derived from the live catalog | 37 / 34 reconciled | n/a |
| **V8** | `user_profiles` still serves `id = auth.uid()` and `is_active_coach_of(id)` | **200** | n/a |
| **V8b** | **`parq_answers` unreachable** via the team-lead path at **any** status | **denied / absent** | n/a |
| **V9** | Simulate-before-apply (replay harness) | **WAIVED — recorded.** Blocked by B10 (no Docker). Live verification A substantially compensates | n/a |
| **V10** | Catalog confirms `with_check` non-null; `status` CHECK present; both helpers filter status | confirmed | n/a |

**Every fixture created for verification must be deleted and its deletion verified** — the standing
practice from the SEC-PHI-9 probe.

## 6 · MUTATION BOUNDARY — confirmed

**PERMITTED**

| Path | Limit |
|---|---|
| `supabase/migrations/132+*.sql` | Wave 1 migrations only |
| `apps/mobile/lib/features/coach/presentation/coach_business_screen.dart` | **only** the roster read (M6), if M5 requires it |
| `apps/mobile/test/**` | guard + regression tests |
| `docs/**` | ADR, evidence, ledger updates |

**FORBIDDEN** — Admin · Trust · AI Guardian · Wearable Intelligence · monetization / K specs ·
`hosts_event_for` / QAX-SEC-09 · SEC-PHI-9/10 predicates · `coach_team_invites` hardening (Wave 2) ·
CI/CD · tooling installation · production · any other V5 work · **any table other than
`coach_team_members` and the `user_profiles` SELECT policy + its new view**.

**No silent scope expansion.** Any discovery requiring a change outside this boundary stops the wave
and is reported.

## 7 · ROLLBACK — confirmed

| Migration | Rollback |
|---|---|
| M2 policy | restore the prior policy definition in a single transaction |
| M3 / M4 helpers | `CREATE OR REPLACE` back to the prior bodies (captured verbatim in the ADR **before** change) |
| M5 policy + view | restore the prior `user_profiles` SELECT policy; `DROP VIEW` |
| **M1 status column** | **the only non-trivial one.** `DROP COLUMN` discards lifecycle state. If Wave 1 is reverted after rows exist, that state is lost — acceptable while QA holds 0 rows; **ADR-1 must state the production position** |
| M6 app change | `git revert` of that commit |

**Pre-flight requirement:** the ADR must capture the **verbatim current definitions** of the policy,
both helper functions, and the `user_profiles` SELECT policy, so rollback is exact rather than
reconstructed.

## 8 · ACCEPTANCE CRITERIA

Wave 1 is accepted when **all** hold:

1. **V1, V1b, V2, V2b, V3, V3b pass live** — the deny *and* permit paths both proven.
2. **V8 and V8b pass** — the clinical coach path unbroken; **PHI unreachable via team-lead at any status**.
3. **V4 all KILLED** · **V5 lowered** · **V6 present** · **V7 reconciled** · **V10 confirmed**.
4. Mobile (1,675/9), API (64) and contract tiers green at the new HEAD.
5. Every verification fixture deleted, deletion verified.
6. ADR records ADR-1/2/3 and the verbatim pre-change definitions.
7. Independent verifier ≠ implementer.
8. **No mutation outside §6.**
9. QA ledger updated; **F-03b recorded as PARTIALLY addressed, not closed**.

**Failure of any of 1–3 triggers rollback per §7.**

## 9 · AUTHORIZATION

### **SECURITY FOUNDATION IMPLEMENTATION WAVE 1: AUTHORIZED**

| Condition | Status |
|---|---|
| D1(i) answered | ✔ **NO — no unilateral creation** |
| D1(ii) answered with states | ✔ **invited / active / suspended / revoked; active-only authorization; both helpers must evaluate** |
| D1(iii) answered incl. PHI | ✔ **minimum necessary; PHI excluded; no full row** |
| Verification authorization | ✔ **A — live, reversible, in-scope** |
| V5 contradiction check | ✔ **none found** (§2) |
| Migration band | ✔ 132+, assigned at wave entry |
| Mutation boundary | ✔ confirmed (§6) |
| Rollback | ✔ confirmed (§7) |
| Acceptance criteria | ✔ confirmed (§8) |
| Independent verification | ✔ required |
| D-D1 | not applicable to this wave |

**No mutation has been performed. This document authorizes the next mission; it does not execute it.**

---

*QA remains **90.0% — QA COMPLETE WITH OPEN FINDINGS**. 1 P0 and 4 P1 remain **OPEN** until
independently verified closed. Wave 1 closes the P0's forgeability and F-03b's **team arm only**;
`hosts_event_for()` (QAX-SEC-09) remains a separate `user_profiles` PHI path and is **not** addressed
here. HEAD `07f5bfb`, 0 modified, 0 staged. No code, schema, migration, RLS, CI or database change was
made by this document; all database access was read-only.*
