# N-07 Coach Client Assessment — implementation status

**Date** 2026-09-24 · **Baseline** `7ee8b47` · Design-independent work only, per the owner
ruling: *"Do not invent or implement the UI from the design system yet… Continue only with
design-independent work that does not establish or alter the N-07 UI."*

**No UI was written. No production screen was modified. No migration was created.**

---

## 1 · What was delivered

| Artifact | Path | State |
|---|---|---|
| Narrow assessment read path + audit log (SQL) | `docs/proposed/N07_assessment_access.sql` | **Authored, unnumbered, not applied** |
| Security regression suite | `supabase/tests/security/d09-assessment-access.mjs` | **Authored, not registered in `run.mjs`** |

Both are deliberately staged rather than landed — see §4.

## 2 · The authorization finding (owner decision required)

**The rule you specified already exists server-side — and is wider than the rule.**

Migration `102_restrict_user_profiles.sql` replaced the original
`USING (true)` with:

```sql
USING ( id = auth.uid()
     OR public.is_active_coach_of(id)
     OR public.is_team_lead_of(id)     -- head coach, via coach_team_members
     OR public.hosts_event_for(id) )   -- ANY event vendor the client registered with
```

Intake writes **32 columns onto `user_profiles`**, including `parq_answers`, `risk_level`,
`risk_score`, `medical_conditions`, `has_injuries`, `injury_locations`,
`injury_description`, `food_allergies`. The policy grants the **whole row**.

102's own header shows why the last two predicates exist — *"a head coach viewing their own
team roster (coach_business_screen)"* and *"an event host viewing their attendee list
(vendor_portal_screen)"*. Those surfaces need **names**. They receive the clinical columns
as well.

**Consequence:** today an event vendor can read the PAR-Q answers and injury history of
anyone who registered for their event, and the N-07 copy *"Only you and Amara can see this"*
would be untrue on the base-table path.

**Approach taken (your ruling: "add a narrow assessment path"):** additive only. The
proposed SQL adds `get_client_assessment(uuid)` admitting **`is_active_coach_of` alone** —
not team leads, not event hosts — and does **not** touch 102's policy, so the roster and
attendee screens keep working.

**Still open:** the base-table exposure is unchanged. The RPC does not fix it and never
claimed to. `d09` §7 asserts it as **S-N07-a**, expected to fail, so it cannot be quietly
forgotten. Narrowing it is a separate decision with regression cost on two coach/vendor
screens.

## 3 · Audit logging — built, per your ruling

`assessment_access_log` records **coach, client, event, timestamp**. Design decisions worth
stating:

- **Logged before the read returns.** If the insert fails the read does not happen — an
  unlogged access would falsify the on-screen claim.
- **Append-only.** No `UPDATE`/`DELETE` policy for `authenticated`, and both are revoked.
  An audit trail a caller can edit is not an audit trail. `d09` §6 asserts this.
- **The subject can read their own log.** This makes *"Opening it is logged"* verifiable by
  the person it protects, rather than merely asserted at them.
- **Self-access is not routed through the RPC.** A client reads their own intake through the
  existing own-profile policy — no definer escalation, no audit noise (QA-3).

With this applied, the full copy is accurate:
> "Only you and Amara can see this. Opening it is logged."

…**for the N-07 path**. It remains inaccurate with respect to the base-table exposure in §2
until that is ruled on.

## 4 · Why nothing was landed

| Gate | Evidence |
|---|---|
| **Migration number** | `docs/MASTER_REMEDIATION_WAVES.md` §0.2: `132+ … Assigned at wave entry, never before`. N-07 is a new commission, not a wave-entry task, so the number cannot be self-assigned |
| **Hygiene guard** | `.github/scripts/check-migration-hygiene.sh` fails on any untracked or modified file in `supabase/migrations/` — *"an untracked migration is a schema change that exists on somebody's laptop and nowhere else."* Creating the file implies committing it in the same change |
| **`run.mjs` registration** | Deferred so the suite, the migration and its number land atomically. Precedent: `d08` is registered and fails by design pending migration 131 |
| **UI** | Owner ruling — wait for the finalized N-07 design |
| **Client Detail row** | `client_detail_screen.dart` is being modified by a concurrent session right now, alongside 15 other screens |

## 5 · QA coverage

| # | Requirement | Covered | Where |
|---|---|---|---|
| 1 | Assigned coach can access | ✅ | `d09` §1 |
| 2 | Unassigned coach cannot | ✅ | `d09` §2 — incl. **relationship-ended revokes immediately** |
| 3 | Client can still access own info | ✅ | `d09` §3 |
| 4 | Missing/empty data renders honestly | ✅ | `d09` §4 — `has_assessment` distinguishes *no profile* from *intake never completed* |
| 5 | Assessment row on Client Detail | ⛔ | UI — blocked (design + concurrency) |
| 6 | Navigation opens N-07 | ⛔ | UI — blocked |
| 7 | No leak via providers/APIs/caching/logs/alternate routes | ⚠️ partial | `d09` §5 covers direct table, anon and `public_profiles`. **Provider/caching checks belong with the UI** |
| 8 | Audit event persisted and observable | ✅ | `d09` §6 |

**None of these has been executed.** They require `QA_URL`/`QA_ANON`/`QA_SERVICE` and the
migration applied. Status is `AUTHORED`, never `VERIFIED`.

## 6 · Schema/code mismatch found in passing

`intake_data.dart` models `medicalConditions`, `injuryLocations` and `dietaryRestrictions`
as `List<String>`, and treats `risk_flags` as a list. **All four columns are `TEXT`**, not
`text[]`. The proposed function's return types follow the **database**, which is
authoritative. A list flattened into `TEXT` round-trips badly and is worth a separate look —
it is not in N-07's scope.

*(All 36 column names and types in the proposed SQL were verified against the migrations
before writing; five type errors were caught and corrected in the process.)*

## 7 · Next steps

1. **Owner:** assign a migration number at wave entry → rename, move to
   `supabase/migrations/`, register `d09` in `run.mjs`, commit together.
2. **Owner:** rule on the §2 base-table exposure (S-N07-a).
3. **Design:** supply the finalized N-07 frame.
4. **Then:** build the screen against the design, add the Client Detail row once the
   concurrent session's changes land, and add provider/caching leak tests (QA-7).
5. **Then:** run `npm run test:security` against QA and record real results.
