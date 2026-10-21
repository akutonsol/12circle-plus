# V5 SECURITY FOUNDATION WAVE 1 — INDEPENDENT VERIFICATION (AGENT 3)

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` (unchanged) · **Verifier:** Agent 3, independent of Agent 2
**Mode:** authorization A (live, shared QA) · **Migration under review:** `132_team_membership_lifecycle.sql`

---

## 1 · DISPOSITION — EXPLICIT AND SPLIT

| | |
|---|---|
| **SECURITY VERIFICATION** | **PASS** — every assertion in the contract is live-proven; 12 adversarial attempts, 10 denied, 2 succeeded but are authorization-neutral |
| **WAVE 1 ACCEPTANCE** | **FAIL** — acceptance criterion 4 ("mobile, API and contract tiers green") is **not satisfied**; and a **fidelity gap against D1(i)** needs an owner ruling (§5) |

**The distinction is the point of this review.** The migration does what it was meant to do, and the
P0's forgery and PHI path are closed under live test. Wave 1 nonetheless **does not pass acceptance**,
on three grounds: two regression checks are red, two new (low) defects were introduced, and one design
choice inside the migration is **not actually authorized by the decision it cites**.

**Nothing was silently fixed. Nothing was omitted.**

## 2 · RE-VERIFICATION OF THE CORRECTED VIEW GRANTS

| Check | Result | Verdict |
|---|---|---|
| Table-level grants | `authenticated = SELECT` · `postgres`, `service_role` = full | **PASS** |
| **Column-level** grants for `authenticated`/`anon` other than SELECT | **0 rows** | **PASS** — no column-level bypass |
| Is the view auto-updatable? | **`is_updatable = YES`, `is_insertable_into = YES`** | **material** |
| A9 · `INSERT INTO team_member_profiles` as authenticated | `ERROR: permission denied for view` | **PASS** |
| A1 · `UPDATE … SET first_name='PWNED'` as authenticated | `ERROR: permission denied for view` | **PASS** |

**The view is confirmed SELECT-only for authenticated users.**

**Why this matters more than it first appears:** the view **is** auto-updatable and
`is_insertable_into`, and it runs `security_invoker = off` as `postgres` (which holds `BYPASSRLS`).
So **the grant is the only thing standing between an authenticated user and an unfiltered write into
`user_profiles`.** There is no second line of defence — no `WITH CHECK OPTION`, no RLS on the view.
That is precisely why the defect Agent 3 caught was serious, and why SEC-W1 pins the `REVOKE` as a
first-class assertion rather than a tidiness detail.

## 3 · VERIFICATION CONTRACT — FULL RE-RUN

Executed over the Postgres path with `SET LOCAL ROLE authenticated` + `request.jwt.claims`, which
**subjects** the session to RLS. Every test inside a transaction ending in `ROLLBACK`; **no fixture
persists**. Elevated privilege used only to seed fixtures, never to satisfy an authorization check.

| ID | Assertion | Actual | Verdict |
|---|---|---|---|
| V1 | forged membership naming a victim denied | RLS violation | **VERIFIED PASS** |
| V1b | member insert claiming `active` denied | RLS violation | **VERIFIED PASS** |
| V1c | `invited` insert permitted **and inert** | `INSERT 0 1`; lead=**f**, notify=**f**, view=**0** | **VERIFIED PASS** |
| V2 | ACTIVE lead → 4-column view | 1 row, `James\|Wilson\|james@community.test` | **VERIFIED PASS** |
| V2b | suspended / revoked do not authorize | f/0 · f/0 | **VERIFIED PASS** |
| V3 | forged notification via `invited` denied | RLS violation on `notifications` | **VERIFIED PASS** |
| V3b | notification via `active` permitted | `INSERT 0 1` | **VERIFIED PASS** |
| V8 | active coach still reads client **+ PAR-Q** | 1 row; `parq_answers` reachable = **t** | **VERIFIED PASS** |
| V8b | ACTIVE lead reads base profile | **0 rows** | **VERIFIED PASS** |
| V8c | stranger reads client | **0** | **VERIFIED PASS** |
| V10 | catalog state as designed | §2, §4 | **VERIFIED PASS** |
| **V9** | simulate-before-apply | **WAIVED** — Docker unavailable (B10). Not claimed as executed | **BLOCKED** |

## 4 · ADVERSARIAL / REGRESSION SUITE — 12 attempts

| ID | Attempt | Result | Verdict |
|---|---|---|---|
| A1 | `UPDATE` through the view | permission denied for view | **DENIED** |
| A2 | bypass the CHECK with `'ACTIVE'` (wrong case) | RLS violation | **DENIED** |
| A3 | self-membership (`coach_id = member_id`) | RLS violation | **DENIED** |
| A4 | UPDATE own `invited` row → `active` | `UPDATE 0`; status still `invited` | **DENIED** |
| A5 | **inject a row into an unwilling lead's roster** | **`INSERT 0 1` — SUCCEEDED** | **NEW DEFECT — see §5** |
| A6 | inject a duplicate | `duplicate key … coach_team_members_coach_id_member_id_key` | **DENIED** (bounded) |
| A7 | **member deletes their own row (leave team)** | **`DELETE 0` — row remains** | **NEW DEFECT — see §5** |
| A8 | lead deletes an injected row | `DELETE 1`, 0 remain | **mitigation available** |
| A9 | `INSERT` through the view | permission denied for view | **DENIED** |
| A10 | active lead names `parq_answers` directly | **0 rows** (and 0 for any column) | **DENIED** |
| — | every consumer of `is_team_lead_of` after 132 | **only** `team_member_profiles` | confirmed |
| — | any other path exposing `parq_answers` | only `apply_parq_risk` (a non-DEFINER trigger fn); **no view** | confirmed |

**Dependent-object sweep:** `coach_team_members` has **UNIQUE (coach_id, member_id)** and a PK on
`id`; `authenticated` holds broad column-level GRANTs on `user_profiles` (312 grant rows) — normal for
Supabase, where **RLS is the gate and GRANTs are permissive**, so the D1(iii) narrowing rests entirely
on RLS. That is worth knowing but is not a bypass: A10 confirms RLS holds.

## 5 · NEWLY DISCOVERED DEFECTS — RECORDED, NOT FIXED

### NEW-W1-01 · Roster injection into an unwilling lead · **LOW–MEDIUM**

Any authenticated user may insert an `invited` row naming **an arbitrary user** as `coach_id`. A5
proved the unwilling lead then sees it: `rows_visible_to_unwilling_lead = 1, status = invited`.

- **Grants the attacker nothing:** `is_team_lead_of` = **f**, `may_notify` = **f** (V1c/A5).
- **Bounded:** UNIQUE (coach_id, member_id) limits it to one row per (attacker, lead) pair (A6).
- **Mitigable:** the lead can delete it (A8).
- **Introduced by Wave 1.** Before 132 the write check was `coach_id = auth.uid()`, so an attacker
  could only name *themselves* as coach. The new member-originated policy adds the ability to name
  **someone else** as coach.
- **Impact:** unsolicited entries in a lead's roster UI; the profile columns will not render, because
  the view is ACTIVE-gated. Integrity/noise, not disclosure.

### NEW-W1-02 · A member cannot leave a team · **LOW**

A7: a member attempting to delete their own membership gets `DELETE 0` and the row remains. There is
**no member-side DELETE policy** — only `lead removes own team member`. So a member who self-originates
(or is left holding an injected row) has **no exit**; only the lead can remove it.

### **FIDELITY GAP · the INSERT policy is not what D1(i) authorized** — the most important item here

D1(i) states membership *"must originate through the **invite/consent flow** and only become an active
membership after the required acceptance/consent step."*

The implemented INSERT policy permits a member to originate a membership **with no invite in
existence**. It is not gated on `coach_team_invites` at all — and it cannot be, because the
invite→membership link does not exist (Wave 2).

So Wave 1 faithfully implements the **prohibition** in D1(i) (no unilateral lead creation, live-proven
V1) but adds a creation route D1(i) **does not describe**. Agent 2's ADR justified it as "inert",
which A5/V1c confirm for *authorization* — but inert is not the same as *authorized*. **Agent 3 does
not accept the justification as sufficient.**

> **OWNER RULING REQUIRED.** Either
> **(a)** accept member-origination as a harmless placeholder until Wave 2 links invites — it is
> authorization-neutral, bounded and mitigable, at the cost of NEW-W1-01/02; or
> **(b)** tighten the INSERT policy to `WITH CHECK (false)` until Wave 2 supplies the invite link,
> which removes both new defects and is the strictly faithful reading of D1(i). Teams are already
> non-functional (0 rows, no creation path), so (b) costs no working capability.
>
> **Agent 3's recommendation: (b)** — it matches D1(i) literally and eliminates both new defects.
> Not applied: changing it is a semantic decision about the consent model, which belongs to the owner.

## 6 · ROLLBACK VERIFICATION

The documented rollback was **executed** against live QA inside a transaction and then rolled back.

| Restored object | Matches captured pre-change state? |
|---|---|
| `coach_team_members` policy | **YES** — `Head coach manages team`, `ALL`, `USING (coach_id = auth.uid())`, `with_check (null)` |
| `is_team_lead_of()` | **YES** — no `status` reference |
| `user_profiles` SELECT policy | **YES** — all four arms incl. `is_team_lead_of(id)` |
| `status` column | **removed** (0) |
| `team_member_profiles` view | **removed** (0) |

**Post-rehearsal, Wave 1 is confirmed still applied:** status column present, 3 policies, view present,
`is_team_lead_of` filters `active`.

**ROLLBACK PATH: VERIFIED.** One caveat carried: R5 (`DROP COLUMN status`) is **lossy** — it discards
lifecycle state. Harmless at 0 rows; **production row count is unknown** (ADR-1).

## 7 · RECONCILIATION AGAINST ORIGINAL FINDINGS

### QAX-SEC-08 (P0) — closure criteria, item by item

| Original criterion | Evidence | Met? |
|---|---|---|
| Unilateral/forged insert denied live | **V1 DENIED** | **YES** |
| A non-`active` membership does not satisfy `is_team_lead_of()` | **V1c, V2b** — f at invited/suspended/revoked | **YES** |
| `user_profiles` PHI unreachable via the team-lead path | **V8b, A10** — 0 rows, incl. naming `parq_answers` | **YES** |
| Legitimate roster read intact | **V2** + roster two-step = 1 row | **YES** |
| SEC-G1 baseline lowered | **NO** — SEC-G1 reads migration text and cannot observe supersession; lowering it would make it fail. SEC-W1 pins the fix instead (D15) | **NO** |

### **DISPOSITION: QAX-SEC-08 — OPEN / PARTIALLY VERIFIED.** Not closed.

Four of five criteria are satisfied with live evidence. The fifth is not, and two further conditions
fail: the regression surface is red (§8) and the **fidelity gap** (§5) means the authorized decision is
not yet fully implemented. **Agent 3 declines to certify closure.**

### F-03b (P1)

| Criterion | Evidence | Met? |
|---|---|---|
| Forged `notifications` INSERT via team membership denied | **V3 DENIED** | **YES** |
| `may_notify()` requires `status='active'` on the team arm | verified in the function body; **V3b permits at `active`** | **YES** |
| CHAIN-G1 covers `notifications` | **NO** — not widened (its detector cannot resolve supersession, so widening would fail on that limitation, not on a defect) | **NO** |
| `may_notify()` sound overall | **NO** — the `coach_client_relationships` arm still matches at **ANY status** | **NO** |

### **DISPOSITION: F-03b — OPEN / PARTIALLY VERIFIED.** Team arm closed and live-proven; **the second
arm is untouched.** F-03b must not be described as closed.

### Untouched findings — unchanged and still OPEN

**QAX-SEC-09** — `hosts_event_for(id)` deliberately retained in the `user_profiles` policy and
verified still present. An event host still reaches the whole profile row. **Closing the P0 does not
make profile PHI safe.** · **SEC-PHI-9**, **SEC-PHI-10**, **SEC-AI-1** — different objects, decisions
D3/D10.

## 8 · ACCEPTANCE CRITERIA — AUDIT

| # | Criterion | Status |
|---|---|---|
| 1 | V1, V1b, V2, V2b, V3, V3b pass live | **MET** |
| 2 | V8 and V8b pass — clinical path unbroken, PHI unreachable | **MET** |
| 3 | V4 mutations KILLED · V5 baseline lowered · V6 CHAIN-G1 widened · V7 population re-derived · V10 catalog | **PARTIAL** — mutations 6/6 KILLED and V10 confirmed; **V5, V6, V7 not done** (all three depend on D15) |
| 4 | Mobile, API and contract tiers green at the new HEAD | **NOT MET** — 1 mobile test + 1 contract check red |
| 5 | Every verification fixture deleted, deletion verified | **MET** — all tests ended in `ROLLBACK`; 0 rows remain |
| 6 | ADR records ADR-1/2/3 + verbatim pre-change definitions | **MET** |
| 7 | Independent verifier ≠ implementer | **MET** — this report |
| 8 | No mutation outside the boundary | **MET** — 1 tracked file, 1 migration, 1 guard, docs |
| 9 | F-03b recorded as partial, not closed | **MET** |

**4 of 9 fully met is not the score — criteria 1, 2, 5, 6, 7, 8, 9 are met; 3 is partial; 4 is not
met.** Criterion 4 alone is disqualifying for acceptance.

## 9 · WHAT AGENT 3 DID NOT ACCEPT FROM AGENT 2

Recorded explicitly, because "Agent 2 wrote it" is not evidence:

1. **The "inert therefore fine" justification for member-origination** — rejected as insufficient
   (§5). Inertness was independently confirmed; authorization by D1(i) was not.
2. **The view's grant posture** — not taken on trust; re-checked at table **and column** level, and
   confirmed the view is auto-updatable so the grant is the sole defence (§2).
3. **"PHI is unreachable"** — not accepted from the policy text; tested by naming `parq_answers`
   directly as an **active** lead (A10) and by reading the base table (V8b).
4. **The rollback block** — not accepted as written; **executed** and diffed against the captured
   pre-change state (§6).
5. **The dependent-object list** — re-derived from the catalog after the migration rather than carried
   forward from the pre-change analysis (§4).

## 10 · OUTSTANDING ITEMS

| Item | Status |
|---|---|
| 1 mobile test red — SEC-027 matches migration 132's **comment**, not a grant | remediation **blocked** by a permission denial (two one-line options, both refused as *Security Test Removal*) |
| 1 contract check red — `team_member_profiles` not in the checker's declared `VIEWS` set | not attempted after those denials |
| **NEW-W1-01 / NEW-W1-02 / fidelity gap** | **recorded, not fixed** — awaiting the owner ruling in §5 |
| V5, V6, V7 (SEC-G1 baseline, CHAIN-G1 widening, catalog-derived population) | blocked on **D15** |
| V9 simulate-before-apply | waived and recorded (B10) |
| Production membership state | unknown; existing rows become `invited` (ADR-1) |

## 11 · RECOMMENDATION

1. **Rule on the §5 fidelity gap.** Agent 3 recommends **(b)** — `WITH CHECK (false)` until Wave 2 —
   which removes NEW-W1-01 and NEW-W1-02 and matches D1(i) literally, at no cost to working capability.
2. **Decide the two blocked one-line remediations** so the regression surface can go green. Until then
   Wave 1 **is not accepted** and should not be described as passing.
3. **Do not close QAX-SEC-08 or F-03b.** Both remain OPEN / PARTIALLY VERIFIED.
4. **Nothing is committed.** HEAD `07f5bfb`; commit, push and merge remain human-controlled.

---

*Independent verification by Agent 3. Security verification **PASS**; Wave 1 acceptance **FAIL**.
Two new defects and one decision-fidelity gap recorded, none fixed. 1 P0 and 4 P1 findings remain
**OPEN**. QA remains **90.0%** — unchanged, because no finding was verified closed. Shared QA carries
migration 132 (authorized); every test fixture was rolled back. No commit, push, merge or branch.*

---

# ADDENDUM B — Items 13 & 14 remediation and final acceptance (2026-09-27)

## B1 · Root causes — established, not assumed

### Item 13 — SEC-027

**Root cause:** the `phase2` loop in
`apps/mobile/test/unit/phase1_security_boundary_test.dart` asserted on **raw** `migrations[n]!.sql`.
Migration 132's header explains *why* it revokes the platform's default view grant, and to do so it
quotes that default. The raw-text assertion read the explanation as a grant.

**The established repository mechanism already existed in that same file:** `_stripComments` (line 66)
and `_flat` (line 74), and the sibling `search_path` test already used `_flat`. The failing test simply
did not. **No new mechanism was invented.**

**Owner decision required: NO.** Applying a file's own existing helper consistently is not a change of
security policy.

### Item 14 — view registration

**Root cause:** `supabase/tests/contract/schema.mjs` declares views in a **hand-maintained** `Set`, and
its own header states why: *"Views are not derived from DDL … their column set comes from a SELECT
list, not DDL."* It declared **5**; the live catalog holds **6**. It was incomplete by exactly the view
migration 132 added. **A harness completeness defect.**

**Owner decision required: NO.** Filling a declared inventory that the file documents as
hand-maintained changes no security property.

## B2 · Files changed

| File | Change |
|---|---|
| `apps/mobile/test/unit/phase1_security_boundary_test.dart` | **+26 / −3** — four DDL-shape checks now use `_flat`; **the production-ref check deliberately stays on raw text** (ENV-5: material "anywhere, comments included") |
| `supabase/tests/contract/schema.mjs` | **+12** — registered `team_member_profiles` with provenance |

**No migration changed.** 132 and 133 are byte-identical to what was applied. **No application code
changed.** **No security test removed, suppressed, or relaxed. No allowlist entry added** — the
contract's 3 known-violations list is unchanged.

## B3 · Proof that neither remediation weakened a control

The decisive evidence. Real defects were planted in DDL and the detector **still caught every one**:

| Mutation | Planted | Result |
|---|---|---|
| **MUT-A** | `GRANT SELECT ON public.coach_team_members TO anon;` | **CAUGHT** |
| **MUT-B** | `CREATE POLICY "x" … FOR SELECT USING (true);` | **CAUGHT** |
| **MUT-C** | `ALTER TABLE … DISABLE ROW LEVEL SECURITY;` | **CAUGHT** |
| **MUT-D** | the production ref **inside a comment** | **CAUGHT** — confirming that check remains on raw text |

MUT-D is the one that matters most: it proves the change was surgical. Comment-stripping applies
**only** to the four DDL-shape checks; ENV-5's stricter raw-text rule for the production ref is intact.

**Cumulative mutation score: 13/13 KILLED** (6 on migration 132, 3 on 133, 4 on SEC-027).

## B4 · Independent verification — all tiers

| Surface | Result |
|---|---|
| Mobile | **1,690 pass · 9 skipped · 0 fail** |
| SEC-W1 | **15 pass** |
| SEC-027 | **48 pass** |
| API unit / e2e | **58 pass / 6 pass** |
| Contract | **PASS** — 91 tables + **6 views** + 134 FKs; 3 known violations unchanged |
| Analyzer | 312 issues = the known baseline, **0 errors** |

**Catalog:** 3 policies on `coach_team_members` — INSERT `with_check = false`, SELECT and DELETE
unchanged. **Grants:** `authenticated = SELECT` only on the view; `anon` absent.
**Helpers:** both lifecycle-aware. **Behaviour spot-check:** unauthorized insert → RLS violation;
`UPDATE` through the view → permission denied.
**Rollback:** 133's inverse restores the prior policy exactly; 133 still applied after the rehearsal.
**Fixtures:** `ctm=0 invites=0 w1=0`.

## B5 · Acceptance gate

Items **1–15 green.** SEC-027 genuinely satisfied (B3). `team_member_profiles` correctly represented.
All security and adversarial tests remain active. Mutation tests remain effective. No control weakened.
Rollback verified. No scope expansion. No Admin, Trust, Guardian, Incidents, Audit, Wearable, Security
Center, V5 product or Wave 2 work began.

### **SECURITY VERIFICATION: PASS · WAVE 1 ACCEPTANCE: PASS**

## B6 · What acceptance does NOT mean — carried forward unchanged

**QAX-SEC-08 (P0) remains OPEN / PARTIALLY VERIFIED.** Four of its five original closure criteria are
satisfied with live evidence; the fifth — *"SEC-G1 baseline lowered"* — is **not**, because SEC-G1
reads migration text and cannot observe supersession, so lowering it would make it fail against text
still present in `002`. That is decision **D15**, outside Wave 1. **The P0 is not closed.**

Also still outstanding from the original authorization contract's criterion 3: **V5** (SEC-G1 baseline),
**V6** (CHAIN-G1 widened to `notifications`), **V7** (population re-derived from the live catalog) —
all three depend on D15. SEC-W1 compensates by pinning the corrected definitions directly, but it does
not discharge them.

**Unchanged and still OPEN:** **F-03b** (team arm closed; the `coach_client_relationships` any-status
arm untouched) · **QAX-SEC-09** / `hosts_event_for()` · **SEC-PHI-9** · **SEC-PHI-10** · **SEC-AI-1** ·
**NEW-W1-02** (a member cannot leave — unreachable now that origination is denied, recorded for Wave 2) ·
**NEW-10** (silent invite-insert failure).

**QA remains 90.0%** — unchanged, because no finding was verified closed.

---

# ADDENDUM C — D15 / SEC-G1 reconciliation (read-only, 2026-09-27)

## C1 · D15's exact definition and provenance

**D15, as recorded:** *"Should the guard population be derived from the live catalog rather than
migrations?"* — `QA_TO_V5_TRANSITION_RECONCILIATION_2026-09-27.md:340`. Evidence cited: **37 live vs
33 source**; cause: source counting missed 3 duplicate policies.

**Provenance — material:** D15 appears **only** in documents authored during this V5 governance chain.
It appears in **no pre-existing repository document**. It is a V5-chain construct, not a standing
owner decision inherited from the QA programme.

**A contradiction in my own records, surfaced rather than resolved by preference:**

| Record | Classification |
|---|---|
| `QA_TO_V5_TRANSITION…:340` | **OWNER REQUIRED: YES** |
| `V5_IMPACT_ANALYSIS…:587` | listed under **"Architecture:"** |
| `V5_DECISION_RESOLUTION…:92` | owner column **blank**, architecture column **✓**, default **YES**, status *"OPEN, default documented"* |

Two of three say architecture-with-a-documented-default; one says owner-required. **§C4 resolves this
on authoritative evidence, not by choosing the convenient entry.**

## C2 · Why SEC-G1 "cannot be satisfied" — and the correction to that claim

**SEC-G1 currently PASSES. 5 tests green.** Its assertion is
`expect(found.length, lessThanOrEqualTo(baseline))` — a **ceiling, not an equality**. A genuine
reduction in the population cannot break it.

So the earlier statement that SEC-G1 "fails" or "cannot be satisfied" was **imprecise, and is
corrected here**. What is true is narrower: **the baseline cannot be *lowered* truthfully**, because
the scan reads `supabase/migrations/*.sql` as text and `002_ecosystem_additions.sql` still contains

```sql
CREATE POLICY "Head coach manages team" ON coach_team_members FOR ALL USING (coach_id = auth.uid());
```

Migration 132 dropped that policy; the scan cannot observe a `DROP POLICY` in a later file. So
`found.length` remains 15, and setting `baseline = 14` would fail against text that is still present.

**Which historical definition SEC-G1 is still evaluating:** `002_ecosystem_additions.sql:146`.

**Category:** **stale test/harness — a supersession-blindness defect in the detector.** It is *not* an
implementation defect (the database is correct — 3 policies, INSERT `with_check = false`), *not* a
historical-migration problem (forward-only migrations are the repository's rule and 002 must not be
edited), and *not* a governance-documentation problem.

## C3 · The dependency chain — and where it actually breaks

The chain as previously stated was **D15 → SEC-G1 → QAX-SEC-08 → V5/V6/V7**. Tracing it against the
authoritative standard shows that chain is **wrong at its third link**.

`docs/QA_CLOSURE_STANDARD.md` §2.1 is tracked, pre-existing and authoritative:

> | **Security / authorization** | **FIXED IN CODE · FIXED ON QA · VERIFIED LIVE · VERIFIED IN CI** |
>
> *"`VERIFIED_CLOSED` requires every state its class demands. There are no partial closures and no
> exceptions granted at implementation time."*

**"SEC-G1 baseline lowered" is not one of the four required states.** That criterion originated in my
own Wave 1 authorization contract, not in the closure standard. **D15 therefore does not gate
QAX-SEC-08's closure.**

### What actually gates QAX-SEC-08 — evidence per required state

| Required state | Standard's definition | Status |
|---|---|---|
| **FIXED IN CODE** | *"exists in a **committed** diff"* | **NOT MET** — migrations 132/133 and SEC-W1 are **untracked**; nothing is committed |
| **FIXED ON QA** | applied and present in the live catalog | **MET** — 3 policies, `status` column, view all confirmed |
| **VERIFIED LIVE** | *"reproduces the secure behaviour **and the same probe demonstrably failed before the fix**"* | **PARTIAL** — the post-fix half is proven repeatedly; **the pre-fix half was never executed**, because the shared-QA write was declined at the time the P0 was found |
| **VERIFIED IN CI** | *"fails against the pre-fix tree and passes against the post-fix tree, **in CI**"* | **NOT MET** — SEC-W1 was created this wave and is uncommitted, so it has never run in CI; the last inspected run (`36093979157` @ `8641c17`) predates Wave 1 and had `static-guards` FAILING |

**Three of four states are unmet or partial, and none of them is D15.** V5/V6/V7 were likewise my own
contract items, not closure requirements.

**The pre-fix half of VERIFIED LIVE is obtainable** and is the highest-value missing evidence:
§5.2 prescribes exactly the method — *"security-sensitive probes use transaction rollback"*. Restoring
the pre-fix policy inside one transaction, demonstrating the forged insert **succeeds**, then rolling
back, would complete it with zero net mutation. **Not executed here: this mission is read-only.**

## C4 · Is D15 resolvable without owner input? — **YES**

The act D15 blocks is *"lower the baseline to reflect a genuine fix"*. Two **pre-existing, tracked**
sources already authorize that act explicitly:

1. **`docs/QA_EVIDENCE.md:1944`** — *"When one is genuinely fixed, its entry is deleted and the
   baseline lowered **in the same change** — the discipline the security ratchets already use."*
2. **SEC-G1's own header** (`rls_policy_shape_guard_test.dart:38`) — *"Measured 2026-09-23. **Lower it
   when policies are corrected under OD-14**; never raise it."*

Wave 1 corrected one member of that population under owner decisions D1(i)/(ii)/(iii), which are the
OD-14 / OD-QAX-9 ruling for that policy. So the precondition in SEC-G1's own instruction is satisfied.

**The mechanism** is likewise settled by established repository pattern rather than by a new decision:
named, reasoned exclusion entries are how this repository handles a corrected member of a tracked
population — `ERR-G2`'s `permitted`, `DEAD-G1`'s `known`, `CHAIN-G1`'s `known`. Same shape, same
discipline: the entry names what was corrected and why, and the number moves in the same change.

**Resolution of the §C1 contradiction:** the *architecture* classification is correct and the
transition document's "OWNER REQUIRED: YES" was **my error**. The evidence: the closure standard does
not make D15 a closure gate, and both the guard's own header and `QA_EVIDENCE.md` already authorize the
act. Nothing here asks the owner to choose a product behaviour.

## C5 · Proposed correction — presented, NOT applied

**Authorized by:** `QA_EVIDENCE.md:1944` + `rls_policy_shape_guard_test.dart:38` + established
allowlist pattern. **No owner decision required. No mutation performed.**

| Item | Detail |
|---|---|
| **Files affected** | `apps/mobile/test/unit/rls_policy_shape_guard_test.dart` — **one file** |
| **Exact change** | Add a named, reasoned `corrected` entry recording that `coach_team_members."Head coach manages team"` was dropped by migration 132 and replaced by three per-command policies with an explicit `WITH CHECK`; subtract recorded-corrected entries from `found`; lower `baseline` **15 → 14** in the same change. Add a self-test that the exclusion is **evidence-bearing** — it must name the superseding migration, and it must fail if that migration stops dropping the policy |
| **Security impact** | **None to the database.** Detection is *narrowed by exactly one policy that provably no longer exists*, and only on evidence of the superseding migration. The 14 remaining members stay tracked; the ceiling still fails on a 15th. `never raise it` preserved |
| **Rollback** | revert one test file (`git checkout --`); no migration, schema, policy or application change |
| **Verification contract** | (1) SEC-G1 passes at 14; (2) **mutation: restore the 002 policy shape in a later migration → SEC-G1 must FAIL**; (3) mutation: remove 132's `DROP POLICY` → the exclusion must become invalid and FAIL; (4) mutation: add a 15th distinct FOR-ALL policy → must FAIL; (5) SEC-G2 unaffected; (6) full mobile tier green; (7) SEC-W1 15/15 unaffected |
| **Independent-agent plan** | Agent 2 edits the guard · Agent 3 runs (2)–(4) adversarially and confirms no other population member was excluded · Agent 6 runs the full tier. **Agent 3 ≠ Agent 2** |

**V6 (widen CHAIN-G1 to `notifications`) is NOT included.** CHAIN-G1's chain-set detector has the same
supersession blindness, so widening it would fail on that limitation rather than on a defect. It needs
the same treatment and should be a separate, separately-verified change.

## C6 · Findings — preserved unchanged

**QAX-SEC-08: OPEN / PARTIALLY VERIFIED** · **F-03b: OPEN / PARTIALLY VERIFIED** · **QAX-SEC-09: OPEN**
· **SEC-PHI-9: OPEN** · **SEC-PHI-10: OPEN** · **SEC-AI-1: OPEN** · **NEW-W1-02: OPEN** ·
**NEW-10: OPEN**.

**Nothing was closed, downgraded or reinterpreted.** Wave 1 acceptance is **not** closure of the
security programme: it means one wave's scoped change was implemented and independently verified.
**QA remains 90.0%.**

---

# ADDENDUM D — PRE-FIX LIVE EVIDENCE (2026-09-27)

Obtained by the method `QA_CLOSURE_STANDARD.md` §5.2 prescribes: *"security-sensitive probes use
transaction rollback where possible."* **One transaction, ended in `ROLLBACK`. Zero net mutation.**

## D1 · The restored pre-fix state was the captured state

Verified in-transaction before probing, against `PRE_CHANGE_STATE.txt`:

| Object | Restored value | Matches capture |
|---|---|---|
| `coach_team_members` policy | `Head coach manages team` · `ALL` · **`with_check (null)`** | **YES** |
| `is_team_lead_of()` filters status | **f** | **YES** |
| `user_profiles` SELECT has the `is_team_lead_of` arm | **t** | **YES** |
| `may_notify()` team arm filters status | no | **YES** |

**One deliberate difference, stated rather than glossed:** the `status` column added by migration 132
remained present. It cannot affect this probe — the defect is the policy reusing `USING` as the INSERT
check — and the probe statement is byte-identical in both runs (`coach_id, member_id, role`). Dropping
the column would have made the transaction more invasive for no evidentiary gain.

## D2 · BEFORE / AFTER — the same probe, both halves

| Step | PRE-FIX (this addendum) | POST-FIX (Wave 1) |
|---|---|---|
| **1. Forged insert** `(coach_id = attacker, member_id = victim)` | **`INSERT 0 1` — SUCCEEDED**, 1 row | **DENIED** — `new row violates row-level security policy` |
| **2. `is_team_lead_of(victim)`** | **t** | **f** |
| **3. Read the victim's `user_profiles` row** | **1 row — READABLE** | **0 rows** |
| **4. `parq_answers` reachable (the PHI)** | **1 — REACHABLE** | **0** |
| **4b. `membership_tier` reachable** | **1 — REACHABLE** | 0 |
| **5. `may_notify(victim)`** *(F-03b team arm)* | **t** | **f** |
| **6. Forged notification INSERT** *(F-03b team arm)* | **`INSERT 0 1` — SUCCEEDED** | **DENIED** on `notifications` |

**Step 4 is the P0 itself**: an account with no role of any kind forged a membership and read another
member's **PAR-Q medical history**. That is now demonstrated live in both directions.

**Two precision notes, so the evidence is not over-read:**

- **`weight_kg` showed 0 pre-fix. That is NOT protection** — the row was fully readable (step 3 = 1
  row); that fixture's `weight_kg` is simply NULL. Recording it as a denial would be false.
- **The notification read-back returned 0 in both runs**, for the same correct reason: the *sender*
  cannot read a notification addressed to someone else. The assertion is the `INSERT 0 1`, not the
  read-back — identical treatment to the post-fix run.

## D3 · Agent 3 independent verification — no persistence

| Check | Result |
|---|---|
| Wave-1 policies restored | **3** — SELECT, INSERT, DELETE |
| Pre-fix policy leaked into the live state | **0** |
| Both helpers lifecycle-aware again | **t / t** |
| `user_profiles` `is_team_lead_of` arm | **f** (removed again) |
| INSERT policy | **`with_check = false`** |
| View grants | `authenticated = SELECT` only; `anon` absent |
| `coach_team_members` / `coach_team_invites` rows | **0 / 0** |
| Probe notifications (`PREFIX-PROBE`, `W1-*`, `WAVE1*`) | **0** |
| **Independent re-probe against current state** | **DENIED** — `new row violates row-level security policy` |

**No persistent database mutation occurred.**

## D4 · Effect on QAX-SEC-08 — one state advances, the finding does not close

`QA_CLOSURE_STANDARD.md` §2.1 requires four states for a security/authorization finding:

| Required state | Before this mission | Now |
|---|---|---|
| FIXED IN CODE | NOT MET | **NOT MET** — 132, 133 and SEC-W1 remain **untracked**; the standard requires a *committed* diff |
| FIXED ON QA | MET | **MET** |
| **VERIFIED LIVE** | **PARTIAL** | **✅ MET** — post-fix secure behaviour reproduced **and** the same probe demonstrably succeeded pre-fix |
| VERIFIED IN CI | NOT MET | **NOT MET** — SEC-W1 is uncommitted and has never executed in CI |

### **QAX-SEC-08 remains OPEN / PARTIALLY VERIFIED. Not closed.**

Two of four states are unmet. §2.1 is explicit: *"`VERIFIED_CLOSED` requires every state its class
demands. There are no partial closures and no exceptions granted at implementation time."*

**Exact remaining evidence for the next authorized mission:**

1. **FIXED IN CODE** — commit migrations 132 and 133, `team_membership_lifecycle_guard_test.dart`, the
   ADR, and the two harness corrections. **Requires explicit commit authorization** (human-controlled
   throughout this programme).
2. **VERIFIED IN CI** — SEC-W1 must execute in CI and pass, with a demonstrated failure against the
   pre-fix tree. Blocked behind: the commit above, plus **QAT-1** (`static-guards` is red, so the job
   aborts at step 1).

**F-03b:** its team arm now also has both halves of live evidence (steps 5–6). It remains
**OPEN / PARTIALLY VERIFIED** — the `coach_client_relationships` any-status arm is untouched, and its
own FIXED IN CODE / VERIFIED IN CI states are unmet for the same reasons.

## D5 · SEC-G1 baseline — PROPOSED ONLY, untouched

`rls_policy_shape_guard_test.dart` was **not modified** in this mission. The correction from Addendum C
§C5 remains proposed: a named `corrected` entry citing migration 132, subtract exactly one policy,
baseline **15 → 14**, the other 14 retained, never raised, with an evidence-bearing self-test.

## D6 · Findings — unchanged

QAX-SEC-08 · F-03b · QAX-SEC-09 · SEC-PHI-9 · SEC-PHI-10 · SEC-AI-1 · NEW-W1-02 · NEW-10 — **all
remain OPEN.** Nothing closed, downgraded or reinterpreted. **QA remains 90.0%.**
