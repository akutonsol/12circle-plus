# ADR-W1-001 — Team membership lifecycle and authorization

**Status:** ACCEPTED (owner decisions supplied 2026-09-27) · **Wave:** Security Foundation Wave 1
**Migration:** `132_team_membership_lifecycle.sql` · **Base HEAD:** `07f5bfb`

## Context

`coach_team_members` carried `"Head coach manages team" FOR ALL USING (coach_id = auth.uid())` with
**no `WITH CHECK`**. Postgres reuses `USING` as the INSERT check, so any authenticated account could
insert a row naming itself `coach_id` and any victim `member_id`. Two SECURITY DEFINER helpers
consumed that row as an authorization fact, neither filtering any lifecycle state — because none
existed. That composed into **QAX-SEC-08 (P0)**, a cross-user PHI read of the whole `user_profiles`
row including `parq_answers`, and **F-03b (P1)**, a forged `notifications` INSERT.

## Owner decisions (verbatim, 2026-09-27)

- **D1(i) — NO.** *"Membership must not be created unilaterally by a team lead. Membership must
  originate through the invite/consent flow and only become an active membership after the required
  acceptance/consent step."*
- **D1(ii) — YES.** States **`invited` · `active` · `suspended` · `revoked`**. *"Only ACTIVE
  membership may satisfy team-lead authorization checks."* *"The authorization helpers
  `is_team_lead_of()` and `may_notify()` must evaluate the lifecycle state rather than merely the
  existence of a row."*
- **D1(iii)** — *"minimum member information required for legitimate team-management functions"*;
  *"PAR-Q, medical conditions, and other health-sensitive/PHI information are NOT accessible through
  team-lead membership authorization"*; *"Do not expose the full `user_profiles` row to team leads."*
- **Verification: A** — live verification against shared QA authorized, in-scope and reversible.

## Decision

1. Add `status text NOT NULL DEFAULT 'invited'` with a CHECK limited to the four owner states.
2. Replace the single `FOR ALL` policy with **explicit per-command policies** — the hardened idiom
   already used by `coach_client_relationships`. **No INSERT path permits a lead to create a
   membership, and no path permits self-activation.**
3. `is_team_lead_of()` requires `status = 'active'`.
4. `may_notify()`'s team arm requires `status = 'active'`.
5. Remove the `is_team_lead_of(id)` arm from the `user_profiles` SELECT policy; serve the roster
   from a column-limited view carrying **4 non-PHI columns**.

### Why no UPDATE policy

Status transitions (`invited → active`) are the acceptance step, which **does not exist** — there is
no invite-acceptance mechanism anywhere (0 triggers, 0 functions, no writer). Granting an RLS UPDATE
path now would create an ungoverned activation route, defeating D1(i). Removal remains available to
the lead via DELETE, the pre-existing capability. **Activation is Wave 2's governed conversion.**

### Why member-originated INSERT is permitted but inert

D1(i) requires membership to *originate* through invite/consent. The INSERT policy admits only
`member_id = auth.uid()` at `status = 'invited'`. Because both helpers now require `'active'`, such a
row **grants nothing to anyone** — it cannot satisfy `is_team_lead_of()` and cannot satisfy
`may_notify()`. This is what makes the lifecycle load-bearing rather than decorative, and it closes
the reverse direction of F-03b (a member self-asserting onto a stranger's team to gain a notify
channel).

## Sub-decisions

### ADR-1 — Existing-row status: **`invited`**

**Compelled by D1(ii)**, not chosen here: *"Do not treat the existence of a `coach_team_members` row
alone as proof of active authorization."* Grandfathering to `active` would bless any already-forged
row. The column is added `NOT NULL DEFAULT 'invited'`, so any pre-existing row becomes `invited`.

**Operational consequence, stated explicitly:** QA holds **0 rows** (verified). **Production state is
unknown — production has never been contacted.** If production holds memberships, their team-lead
authorization stops at this migration until Wave 2 provides an acceptance path. This is the
security-correct outcome under D1(ii) and is recorded for the owner rather than silently accepted.

### ADR-2 — `role` values: **NOT CONSTRAINED in Wave 1**

The owner answered D1(i), (ii) and (iii). **D1(iv) — the permitted `role` value set — was not
answered.** Adding a CHECK constraint would decide an unanswered question, so it is **deferred to
Wave 2**. Recorded evidence for that later decision: the column already defaults to
`'assistant_coach'`, and `coach_business_screen.dart:256` hard-codes the same value when creating an
invite. The column remains `text NOT NULL` as it is today — **no regression, no new constraint.**

### ADR-3 — `email` in the minimum-necessary view: **INCLUDED, flagged**

D1(iii) excludes *"PAR-Q, medical conditions, and other health-sensitive/PHI information"* and
forbids *"the full `user_profiles` row"*. `email` is PII, not PHI. The only consumer
(`coach_business_screen.dart:67`) renders exactly `first_name, last_name, email, avatar_url`.
Including those four satisfies D1(iii) while preserving an already-authorized flow; excluding `email`
would regress the roster display, which the owner did not ask for.

**Residual product question, carried not resolved:** whether a team lead should see a member's email
address. `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` raised the same question for event
vendors. Removing it later is a one-line view change.

## Rollback — verbatim pre-change definitions

Captured live before any change; reproduced here so rollback is exact rather than reconstructed.

```sql
-- POLICY (coach_team_members)
CREATE POLICY "Head coach manages team" ON public.coach_team_members
  FOR ALL TO authenticated USING (coach_id = auth.uid());
  -- WITH CHECK: (null)

-- is_team_lead_of
CREATE OR REPLACE FUNCTION public.is_team_lead_of(target_user uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.coach_team_members t
    WHERE t.coach_id = auth.uid() AND t.member_id = target_user
  );
$function$;

-- may_notify: team arm, pre-change (full body in
-- scratchpad wave1/PRE_CHANGE_STATE.txt)
--     OR EXISTS (SELECT 1 FROM public.coach_team_members t
--                 WHERE (t.coach_id = (SELECT auth.uid()) AND t.member_id = recipient)
--                    OR (t.member_id = (SELECT auth.uid()) AND t.coach_id = recipient))

-- user_profiles SELECT
CREATE POLICY "own profile or active coach reads profile" ON public.user_profiles
  FOR SELECT TO authenticated
  USING ((id = auth.uid()) OR is_active_coach_of(id) OR is_team_lead_of(id) OR hosts_event_for(id));
```

Rollback order: M5 policy → drop view → M4 → M3 → M2 policies → M1 (`DROP CONSTRAINT`, `DROP COLUMN`).
**M1 is the only lossy step** — dropping the column discards lifecycle state. Safe while row count is 0.

## Pre-change state (verified live, read-only)

| Fact | Value |
|---|---|
| `coach_team_members` rows | **0** |
| `coach_team_invites` rows | **0** |
| Columns | `id` (default `gen_random_uuid()`), `coach_id` NOT NULL, `member_id` NOT NULL, `role` NOT NULL default `'assistant_coach'`, `added_at` default `now()` |
| Policies on the table | 1 (`FOR ALL`, `with_check` NULL) |
| Triggers / CHECK constraints | **0 / 0** |
| Functions reading the table | 2 — `is_team_lead_of`, `may_notify` |
| Dependent policies | 2 — `user_profiles` SELECT, `notifications` INSERT |
| Writers in app/edge code | **0** — only a SELECT at `coach_business_screen.dart:66` |

## Out of scope (Wave 2 or other waves)

`coach_team_invites` hardening · invite→membership conversion · acceptance UI · `role` CHECK (ADR-2) ·
`may_notify()`'s `coach_client_relationships` any-status arm (**F-03b's second half**) ·
`hosts_event_for()` / QAX-SEC-09 · SEC-PHI-9/10 · Admin · Trust · Guardian · Wearable.

---

# ADDENDUM A — Wave 1 fidelity remediation (2026-09-27)

**Trigger:** Agent 3's independent verification recorded a **fidelity gap**: the INSERT policy created
by migration 132 permits a member to originate a membership with **no invite in existence**, which
enabled NEW-W1-01 (injection of an unsolicited row naming an arbitrary lead) and left NEW-W1-02 (a
member cannot leave).

## A1 · Is the required enforcement already authorized? — **YES**

D1(i), verbatim:

> **NO.** *"Membership must not be created unilaterally by a team lead. Membership must originate
> through the invite/consent flow and only become an active membership after the required
> acceptance/consent step."*

The decision has **two** clauses, and only the first is scoped to leads:

1. *"must not be created unilaterally by a team lead"* — a prohibition on the lead.
2. *"Membership must originate through the invite/consent flow"* — **unscoped.** It constrains
   membership **origination as such**, not origination by a particular party.

Clause 2 is a positive requirement. The invite/consent flow **does not exist** — verified again:
0 triggers on either team table, 0 functions referencing `coach_team_invites`, and no code anywhere
that writes `coach_team_members`. Therefore **no origination currently satisfies clause 2**, and
denying origination is the literal enforcement of the recorded decision.

**The counter-reading, stated so the owner can reject this if it is wrong:** one could read D1(i) as
answering *only* the question asked ("may a lead add a member unilaterally?") and therefore leaving
member-origination unaddressed. **That reading does not survive clause 2**, which is a universal
statement about how membership must originate and is not limited to leads. Agent 1 therefore finds
**no ambiguity requiring owner input**, and records the counter-reading rather than suppressing it.

**No new owner decision is invented. No reinterpretation of D1(i) is made.** The enforcement is
narrower than the previous implementation in exactly the direction clause 2 requires.

## A2 · Remediation contract — the smallest change

Replace the INSERT policy with one that admits nothing until Wave 2 supplies the consent link.

- An explicit policy with `WITH CHECK (false)` is used rather than dropping the policy outright.
  Dropping it would also deny INSERT (RLS defaults to deny with no policy), but a named policy makes
  the intent visible **in the catalog**, so a future reader sees a deliberate closure rather than an
  omission — and the guard can pin it.
- **Nothing else changes.** The lifecycle column, the CHECK, the SELECT policy, the DELETE policy,
  both helpers, the view, its grants and the `user_profiles` policy are all untouched.

## A3 · Effect on the two recorded defects

| Defect | Effect |
|---|---|
| **NEW-W1-01** roster injection | **ELIMINATED** — no INSERT path remains for any caller |
| **NEW-W1-02** member cannot leave | **UNREACHABLE in Wave 1** — no membership can be created, so none can need leaving. **Recorded, not fixed**: whether a member has a right to leave a team is a semantic question no owner decision addresses, and answering it would be deciding for the owner. Carried to Wave 2 alongside the consent flow |

## A4 · Rollback

Addendum rollback is the inverse of one policy:

```sql
DROP POLICY IF EXISTS "membership originates only through the consent flow"
  ON public.coach_team_members;
CREATE POLICY "member originates own membership"
  ON public.coach_team_members FOR INSERT TO authenticated
  WITH CHECK (member_id = auth.uid() AND coach_id <> member_id AND status = 'invited');
```

Migration 132's rollback block (verified by rehearsal) is unaffected and is **not** redone.
