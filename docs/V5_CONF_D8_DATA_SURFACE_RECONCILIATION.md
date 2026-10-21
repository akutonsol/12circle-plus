# V5 · `CONF-D8` — ADMIN AREA → DATA-SURFACE RECONCILIATION

**Analysis only. Nothing was created, altered or authorized. No mapping is invented: an area is recorded
as backed only where a surface demonstrably exists and the record says what governs it.**

Baseline: QA 155 · the approved capability matrix live and verified (425/425, V5 §125) ·
`CONF-D8`'s mechanism half `VERIFIED_CLOSED`, its surface half open (§126).

## 0 · Method, and the two rules that shaped the result

**A name is not a surface.** `events` backing the *Events* area is evidence; `integrations` would have
backed *Integrations* but **does not exist**, and the UI showing an Integrations tab is not proof of a
database surface.

**An additive `OR admin_can(...)` arm is only safe where it does not restore something an existing policy
deliberately removes.** That is the whole of the `A13·1` problem (§126.2) and it recurs.

**One pattern is already adopted and decided**, and most of the harder cases resolve to it: `D7` ruled
**column-limited views over `user_profiles`, not distinct modules**, and five such views already ship —
`public_profiles`, `conversation_participant_profiles`, `event_attendee_profiles`,
`team_member_profiles`, `coach_client_workout_stats`, each `WITH (security_invoker = off)`. **The curated
view is not a new idea here; it is the house pattern.**

---

## 1 · ECOSYSTEM

### 1.1 Community — **EXISTING** (moderation sub-capability: ARCHITECTURE_EXTENSION)

| | |
|---|---|
| Surface | `community_posts` · `post_comments` · `post_reactions` · `community_groups` · `accountability_pods` — all exist, all RLS-enabled (2/2/2/1/3 policies) |
| Boundary today | **member-scoped** (`auth.uid()`), plus public-read arms |
| Can consume `admin_can`? | **Yes, additively on SELECT.** Nothing is deliberately excluded, so an OR arm restores nothing |
| Security | Admin read is a **new cross-user read of member content** — `CONF-D8`'s actual subject. Not PHI, but personal |
| Constraints | — |
| Extension | **The reports/moderation queue does not exist** (`CAP-1`, §102.3). Zero report/moderation tables for community content; `050` moderates the *exercise library*, a different object |

### 1.2 Events — **EXISTING**

`events` · `event_registrations` · `classes` · `class_bookings`, all RLS-enabled (2/4/2/3). Member- and
coach-scoped. **`K-04` governs registration integrity and is CI-verified 9/9** — an additive admin SELECT
arm does not touch its write path. Safe to consume `admin_can` on read.

### 1.3 Training — **EXISTING**, with a PHI caution

`workout_programs` (3) · `workouts` (1) · `workout_sessions` (3) · `workout_logs` (1), all RLS-enabled and
member-scoped. **Caution:** these are health-adjacent and sit under the PHI regime; `D17`'s fix-first
ruling and `SEC_PHI` apply to any view that redefines them. An **aggregate** admin surface (counts,
completion) raises nothing; a **row-level** admin read of a member's training history is a PHI disclosure
decision, not a mechanical one.

### 1.4 Monetization — **EXISTING** for entities · **ARCHITECTURE_EXTENSION** for the metrics

`subscriptions` (1) · `payments` (2) · `coach_packages` (2) exist. **But §99.2 established `subscriptions`
carries no amount and no currency** — so the *entities* are authorizable today while **revenue
decomposition is absent architecture**, and `PD-C03` (currency) plus the gross-vs-commission split remain
owner decisions.

### 1.5 Wearable intelligence — **EXISTING** (connections) · **ARCHITECTURE_EXTENSION** (ingestion health)

`user_integrations` (`011:29`) exists, RLS-enabled, member-scoped — it backs *"Apple HealthKit: Connected"*
and the device count. **Ingestion health (`~40 min behind`, error counts) is `WI-13`, which is deferred
under `PD-G01` and is NOT released.** The area splits exactly as §100.4 determined.

---

## 2 · TRUST

### 2.1 AI Guardian — **EXISTING** (`governance_policy*`) · **ARCHITECTURE_EXTENSION** (runtime) · plus `PD-A05`

| | |
|---|---|
| Surface | `governance_policy` + 4 companions (migration 154), RLS-enabled, gated `is_admin() OR is_trust_operator()` |
| Can consume `admin_can`? | **Yes, additively** — 154 is new infrastructure, not a V5-ruled population, and nothing in its policy is an exclusion |
| Extension | **Guardian runtime state does not exist** — no `ai_agents`, no evaluation store. That is **`P7`** |
| ⚠ Separate constraint | **`decision_traces` exists** (`089:17`) and is governed by **`PD-A05`**, an *answered* owner decision about who may read a trace. **Any Guardian surface touching it inherits `PD-A05`, not the capability matrix** |

### 2.2 Security — **CURATED_VIEW_REQUIRED** · detectors are ARCHITECTURE_EXTENSION

**No `security_events` or `auth_events` table exists.** The Security area's content is a *projection* of
`audit_events` (authorization/authentication categories) — which carries the `A13·1` exclusion — plus
detectors that do not exist (*"sign-in anomalies"* has no detector, §98.2).

**So Security cannot attach to a base table.** It needs the same curated projection as *Audit logs* (§2.4),
and its anomaly content needs new architecture.

### 2.3 Incidents — **CURATED_VIEW_REQUIRED**

`audit_incidents` (1 policy) and `audit_incident_transitions` (1) exist. The existing policy is already
`is_admin() OR is_trust_operator() OR actor_identity = auth.uid() OR is_active_coach_of(actor_identity)` —
**no exclusion**, so an additive arm restores nothing.

**But the population carries `evidence jsonb` and a real `actor_identity`.** The approved matrix grants
`Viewer` **View** on Incidents, so an additive arm would expose an unbounded evidence blob to the
least-privileged role. **A projection omitting `evidence` is the least-privilege form**; the base table is
not. Recorded as a recommendation, **not a decision**.

### 2.4 Audit logs — **CURATED_VIEW_REQUIRED** · the hard constraint

`audit_events`, policy `A13·1`:

```sql
USING ( (public.is_admin()
         AND NOT (category = 'admin_action' AND actor_id = (SELECT auth.uid())))
        OR public.is_trust_operator() )
```

**`AND NOT` is a deliberate exclusion: an admin may not read their own `admin_action` rows.** Adding
`OR admin_can('Audit logs','view')` **restores exactly what the exclusion removes** for any Admin-layer
holder. **Forbidden**, and the instruction says so explicitly.

**The curated-view approach evaluated first, as directed, and it works:**

- a view over `audit_events` that **carries the `A13·1` exclusion in its own `WHERE`**, so the exclusion
  survives rather than being bypassed;
- `WITH (security_invoker = off)` — the established pattern (`101`, `110`);
- the **view** gated on `admin_can('Audit logs','view')`, so the Admin layer is authorized *separately*
  from the base table, which keeps its policy unchanged;
- subjects remain **pseudonymous** — `audit_events` carries `subject_pseudonym`, never a subject id, so
  **`A12` is preserved by construction** and no re-identification path is created;
- least privilege: `Viewer` sees the permitted population and nothing more.

**This is `CONF-D8`'s second option and `D7`'s adopted pattern, applied to the one case that cannot take
the first.**

---

## 3 · OPERATIONS

### 3.1 QA — **NO_BACKING_SURFACE**
No `qa_runs` or `test_results` table. The data exists **in GitHub Actions** (§98.2) and is not ingested.
Ingestion is additive architecture under **`P10`'s unresolved installation constraint**, which is not
released.

### 3.2 Releases — **NO_BACKING_SURFACE**
No `releases` or `deployments` table, and **no version registry anywhere** (§1.6/§6 of the data contract).

### 3.3 Integrations — **EXISTING** (connections) · **ARCHITECTURE_EXTENSION** (health)
`user_integrations` exists and is member-scoped; **no `integrations` table** for provider-level health.
`PD-B23` names the provider set. Same split as *Wearable intelligence*, and the two areas **share one
table** — worth noting, because an `admin_can` arm there serves both areas and must satisfy the stricter.

### 3.4 System — **EXISTING** (`observability_events`) · **ARCHITECTURE_EXTENSION**
`observability_events` (migration 145) exists, RLS-enabled, gated `is_admin() OR is_trust_operator()`, and
**carries no subject identifier at all** (D12·Q5) — so it is `A12`-safe by construction and can take an
additive arm. **`system_events` and `background_jobs` do not exist**; the six platform-health tiles have no
source (§99.2), and `PD-A24 = C` requires any build to be vendor-free.

---

## 4 · SETTINGS

### 4.1 Organization — **NO_BACKING_SURFACE**
**No `organizations` or `organization_settings` table exists.** The approved Settings page shows an
Organization profile; nothing backs it.

### 4.2 Users — **CURATED_VIEW_REQUIRED**, and this is already ruled

`user_profiles` exists with **9 policies** and `enforce_profile_privilege()` guarding `role`,
`membership_tier`, `marketplace_commission_rate`, `stripe_charges_enabled`, `is_demo`.

> **`D7` already decided this area: *"COLUMN-LIMITED VIEWS over `user_profiles`, not distinct modules …
> column-limited views enforce least privilege at the data layer."*** Five such views already ship.

**So the Admin Users surface is a column-limited view gated on `admin_can('Users','view')` — not an arm on
`user_profiles` itself.** `Support`'s single non-View grant, `Users · Update`, must therefore write through
a constrained path that **cannot touch the privilege columns** `enforce_profile_privilege()` protects.
**That is the sharpest write-path question in the matrix.**

### 4.3 Roles — **EXISTING**, read-only, and the write boundary must not move

`admin_role_assignments` (2 policies) and `admin_role_capabilities` (2) exist from migration 153. The
approved matrix gives **every role `View` only** on this area.

**Reads may consume `admin_can('Roles','view')` additively. Writes must remain on legacy `is_admin()`,
exactly as 153 built them.** D13 proves a Viewer is refused both tables with 403/403. **The capability
matrix does not authorize self-grant or self-promotion, and nothing here may create that authority.**

### 4.4 Configuration — **EXISTING**, with a pre-existing defect worth flagging

`platform_settings` (migration 039) exists with two policies. **Its read policy is
`FOR SELECT TO authenticated USING (true)` — every authenticated user can read platform settings today.**
Writes are admin-gated.

**That is a pre-existing posture, not something this work introduces**, and an `admin_can` arm would
*narrow* nothing because the table is already world-readable to authenticated callers. **Recorded as an
observation for the owner; no change proposed here.** The area also holds one key only (§99).

---

## 5 · Consolidated classification

| # | Group | Area | Backing surface | Classification |
|---|---|---|---|---|
| 1 | Ecosystem | Community | `community_posts` + 4 | **EXISTING** (+ `CAP-1` extension) |
| 2 | Ecosystem | Events | `events` + 3 | **EXISTING** |
| 3 | Ecosystem | Training | `workout_*` ×4 | **EXISTING** (PHI caution) |
| 4 | Ecosystem | Monetization | `subscriptions`, `payments`, `coach_packages` | **EXISTING** + **ARCHITECTURE_EXTENSION** |
| 5 | Ecosystem | Wearable intelligence | `user_integrations` | **EXISTING** + **ARCHITECTURE_EXTENSION** (`WI-13`, `PD-G01`) |
| 6 | Trust | AI Guardian | `governance_policy` ×5 | **EXISTING** + **ARCHITECTURE_EXTENSION** (`P7`) + `PD-A05` |
| 7 | Trust | Security | — (projection of `audit_events`) | **CURATED_VIEW_REQUIRED** |
| 8 | Trust | Incidents | `audit_incidents` ×2 | **CURATED_VIEW_REQUIRED** |
| 9 | Trust | **Audit logs** | `audit_events` | **CURATED_VIEW_REQUIRED** — `A13·1` hard constraint |
| 10 | Operations | QA | — | **NO_BACKING_SURFACE** (`P10`) |
| 11 | Operations | Releases | — | **NO_BACKING_SURFACE** |
| 12 | Operations | Integrations | `user_integrations` (shared with #5) | **EXISTING** + **ARCHITECTURE_EXTENSION** |
| 13 | Operations | System | `observability_events` | **EXISTING** + **ARCHITECTURE_EXTENSION** |
| 14 | Settings | Organization | — | **NO_BACKING_SURFACE** |
| 15 | Settings | Users | `user_profiles` | **CURATED_VIEW_REQUIRED** — `D7` already rules it |
| 16 | Settings | Roles | `admin_role_*` | **EXISTING** (read only; writes stay `is_admin()`) |
| 17 | Settings | Configuration | `platform_settings` | **EXISTING** (⚠ already world-readable) |

**7 EXISTING · 4 CURATED_VIEW_REQUIRED · 3 NO_BACKING_SURFACE · 3 EXISTING-plus-extension** (4, 5, 12, 13
carry both, counted once above).

## 6 · What this makes implementable, and what it does not

**Implementable without an owner decision — 7 areas** can take an additive `OR admin_can(area,'view')` arm
on SELECT, because nothing in their policies is an exclusion and no V5 ruling governs them otherwise:
Community · Events · Training (aggregate) · Monetization (entities) · Wearable/Integrations (connections) ·
System · Roles (read).

**Needs a curated view — 4 areas**, three of them because the base population carries something the Admin
layer should not receive wholesale (`A13·1`'s exclusion, unbounded `evidence`, `user_profiles`' privilege
columns). **`D7` already adopted this pattern and five such views ship.**

**Needs architecture before authorization — 3 areas** have nothing to authorize.

## 7 · Boundaries, stated precisely

1. **`Audit logs` / `Security` view design** — the projection must carry the `A13·1` exclusion in its own
   predicate. **Architecture/security decision: approve the curated-view approach, or rule that the
   exclusion does not apply to the Admin layer.** The first preserves the control; the second changes it.
2. **`Users · Update` for `Support`** — the one non-View grant outside Trust/Operations. It must not reach
   the columns `enforce_profile_privilege()` protects. **Write-path design + security review.**
3. **Training row-level admin read** — aggregate is mechanical; per-member history is a **PHI disclosure
   decision**.
4. **`Incidents` evidence exposure to `Viewer`** — projection or base table.
5. **`platform_settings` is world-readable to authenticated callers** — pre-existing; owner's call.
6. `CAP-1` · `PD-C03` · `P7` · `PD-G01` · `P10` · `PD-A05` — unchanged, each already parked.

**Nothing was created. No policy, view, migration or grant was written. `CONF-D8` remains open.**

---

# 8 · IMPLEMENTATION EVIDENCE — what was built, verified and left alone

Owner authorization **2026-10-05**, on the classification above. Scope was explicit: implement the areas
classified safe, build the minimum curated projection for `Audit logs`, change nothing else, and **test the
actual resulting data access, not merely function return values.**

Section 7's boundaries are **not** superseded by this section. Boundary 1 is now answered for `Audit logs`
and still open for `Security`; boundaries 2–6 are untouched and carried forward to V5 §129.4.

## 8.1 The mechanism half — `VERIFIED_CLOSED`

| element | state | evidence |
|---|---|---|
| graded authorization mechanism | **`VERIFIED_CLOSED`** | migration **153** · `admin_role_assignments`, `admin_role_capabilities`, `is_admin_member()`, `admin_can(area, verb)` |
| governance policy registry | **`VERIFIED_CLOSED`** | migration **154** · documentation layer only; it is **not** the enforcement point |
| the approved capability matrix | **owner-approved** | `ADMIN-CAPABILITY-MATRIX.json`, authority **Julia**, 17 areas × 5 verbs × 5 roles |
| matrix arithmetic | **85 cells · 425 grants** | **116 true · 309 false · 0 unresolved** |
| seeded to the database | **`VERIFIED_CLOSED`** | migration **155** · 116 `INSERT`s, generated from the matrix file, verbs lowercased to match 153's `CHECK` |
| every grant verified live | **425/425** | `D14` 8/8 — expectations read **from the matrix file**, so the test cannot drift from the policy |
| separation and least privilege | **20/20** | `D13` — `is_admin_member()` true while `is_admin()` false; Trust and erasure separation; no self-escalation |

**Deny-by-default was proven live before any policy existed** — the mechanism granted nothing while
`admin_role_capabilities` was empty.

## 8.2 The seven authorized additive surfaces — migration 156

Sixteen **new** permissive `SELECT` policies. No existing policy was edited, dropped or replaced, so nothing
any existing policy allows or denies changed: PostgreSQL ORs permissive policies, and a new one can only
widen. The widening is exactly the approved matrix.

| # | area | surface | consumes |
|---|---|---|---|
| 1 | Community | `community_posts`, `post_comments`, `post_reactions`, `community_groups`, `accountability_pods` | `admin_can('Community','view')` |
| 2 | Events | `events`, `event_registrations`, `classes`, `class_bookings` | `admin_can('Events','view')` |
| 3 | Training | **aggregate view only** — `admin_training_overview` | `admin_can('Training','view')` |
| 4 | Monetization | `subscriptions`, `payments`, `coach_packages` | `admin_can('Monetization','view')` |
| 5 | Wearable / Integrations | `admin_integration_connections` (157) over the **shared** `user_integrations` | `admin_can('Wearable intelligence','view')` **AND** `admin_can('Integrations','view')` |
| 6 | System | `observability_events` | `admin_can('System','view')` |
| 7 | Settings › Roles | `admin_role_assignments`, `admin_role_capabilities` — **READ only** | `admin_can('Roles','view')` |

**The stricter authorization is an `AND`, and it is proven behaviourally.** Both areas grant View to all five
roles today, so an `AND` and an `OR` are indistinguishable by observation. `D15` withdraws the `Integrations`
grant only, asserts the shared surface **closes** while the `Wearable` grant remains true, restores the row
and re-asserts the grid at 116. An `OR` would still have returned the row.

**Settings › Roles created no write authority.** Writes remain on legacy `is_admin()` exactly as 153 built
them, and `D15` asserts a Viewer's role-assignment `INSERT` is refused (403). This honours the owner's
constraint that the matrix must not become role-management authority.

**Training is aggregate-only, by construction.** `admin_training_overview` exposes four counts and no member
row, no `user_id` and no free text. `D15` asserts the projection has exactly those four keys, that
`user_id` / `workout_id` / `notes` cannot be selected, and that a Viewer still reads **0 of 9**
row-level `workout_sessions`. The row-level boundary is parked, not quietly crossed.

## 8.3 The curated `Audit logs` projection — the hard constraint, honoured

`A13·1`'s exclusion is `AND NOT (category = 'admin_action' AND actor_id = (SELECT auth.uid()))`. An additive
`OR admin_can('Audit logs','view')` arm on `audit_events` would have **restored exactly what that clause
removes**. It was not added. `audit_events`' own policy is untouched.

`admin_audit_events` instead carries the exclusion **in its own predicate**:

| property | how it is achieved | verified |
|---|---|---|
| `A13·1` preserved | the exclusion is reproduced verbatim in the view's `WHERE` | **the reader's own 128 `admin_action` rows are excluded** |
| `A13·1` stays **narrow** | the exclusion names only the reader's own rows | **the other 69 remain visible** |
| gated by the matrix | `WHERE admin_can('Audit logs','view')` — the view is self-gating | **closes for `Support`**, whose grant is `false` |
| base protection intact | no arm was added to `audit_events` | **a Viewer still reads 0 of 1000** directly |
| `A12` by construction | projects `subject_pseudonym` and **never resolves it** | `subject_id` unselectable; `audit_identity_map` 403 |
| no new resolver | **no `audit_identity_map` join exists in the view** | — |

**Why the view must not resolve.** §19.3 rules that **no standing party** may resolve a pseudonym and that
resolution *"occurs INSIDE THE AUDIT READ PATH"*. A view is a standing resolver by definition — precisely the
argument migration 142 used to keep the active-coach arm out of a table policy. Callers needing `subject_id`
keep using the 146/152 `SECURITY DEFINER` path.

**The column set was conformed, not invented.** It is the established projection of those read paths
(`id, actor_id, action, occurred_at, outcome, category, actor_provenance, correlation_id`) with
`subject_pseudonym` standing where they return the resolved `subject_id`. `correlation_signature` and
`correlation_key_id` are deliberately absent — write-once integrity material, exposed to no reader anywhere.

**`Security` is NOT implemented.** Its content is a **category filter** over the same population, and **no
authority maps `A2`'s 15 categories to the `Security` area.** Choosing that mapping would be inventing
scope. It is carried to V5 §129.4 as its own boundary.

## 8.4 A credential disclosure I introduced, and the lesson that must survive

**156 was wrong.** It put a blanket `SELECT` arm on `user_integrations`, which carries **`access_token` and
`refresh_token`**. The approved matrix grants that area to **all five roles**, so the arm would have handed
every **Viewer, Support agent and Content editor** live OAuth bearer tokens for every user's wearable
account — credentials that permit impersonating the user against the upstream provider.

Found by auditing **all sixteen** tables for secret-bearing columns. `user_integrations` was the **only** one;
`payments` and `subscriptions` hold Stripe **identifiers**, which are references, useless without the Stripe
secret key, and legitimately part of a reconciliation surface.

**Migration 157** withdrew the arm and replaced it with a column-limited `D7`-pattern view exposing
`id, user_id, provider, connected, connected_at, disconnected_at` and **neither token**. `D15` asserts both
columns return `42703 column does not exist`.

**No approved capability was lost (§102).** The design displays connection *status*; every field of it
survives. A token could not be rendered usefully if the design asked for one.

**The lesson, stated so it outlives this migration:**

1. **`user_integrations` contains bearer credentials.** Treat it as a secret store, not a reporting table.
2. **A blanket `SELECT` arm on a credential-bearing table is unsafe**, however narrow the role that receives
   it, because the grant is to the *table*, not to the columns the UI happens to render.
3. **Credential-bearing surfaces require the `D7` column-limited view pattern**, so the credential is absent
   from the projection rather than merely unrequested.
4. **Remediation stays forward-only.** 156 was already applied; `check-migration-hygiene.sh` forbids editing
   an applied migration in place, on Wave 0's finding that in-place edits made *"replay from empty"* and
   *"what production actually ran"* diverge.
5. **Audit every table in a batch for secret columns before granting it**, not the ones that look risky.
   The regex that first reported "clean" was broken and I printed its answer; see §129.3.

## 8.5 A write escalation the same two migrations left behind — migration 158

156 and 157 revoked from `PUBLIC` and `anon` but **not from `authenticated`**. Supabase ships
`ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO authenticated`, so each new view was **born holding
`INSERT`, `UPDATE` and `DELETE`**, and the later `GRANT SELECT` does not take them away.

Both single-table views are **auto-updatable** and run `security_invoker = off`, so a write through them
executes **as the view owner**, where base-table RLS does not apply.

**Proven on QA before the fix:** a user holding only the Admin-layer **`viewer`** role — View yes, Update
**explicitly no** — issued a `DELETE` through `admin_integration_connections` and **removed another user's
integration row**. `user_own_integrations` (`auth.uid() = user_id`) did not apply.

**Audit immutability was not breached.** `trg_audit_events_freeze` raises on `UPDATE`/`DELETE` regardless of
privilege, and triggers fire for the table owner too. Defence in depth held where it existed; it did not
exist on `user_integrations`, which is where the escalation landed.

**Caught by `SEC-018`**, the standing guard — not by me. Migration **158** revokes `ALL` from
`PUBLIC, anon, authenticated` on all three views and re-grants `SELECT`.

## 8.6 Verification — the full ladder

| rung | state |
|---|---|
| FIXED IN CODE | ✅ migrations 156 · 157 · 158 |
| **FIXED ON QA** | ✅ applied; ledger carries 156, 157, 158; `expected_applied.json` frontier **158** — manifest and ledger agree |
| **VERIFIED LIVE** | ✅ **`D15` 60/60** · `D13` 20/20 · `D14` 8/8 (all 425) · full live regression **573/573 across 15 suites**, the fourteen prior suites unchanged at 513 |
| **VERIFIED IN CI** | ✅ **`d4a0b46` green, 6/6 jobs** — the preceding `9681ff6` was red on `SEC-018`, which is how §129.2 surfaced |

Flutter **1704/1704** after 158 (**1703 passed, 1 failed** before it, the failure being `SEC-018`).

**`D15` tests data access, not booleans** — decisive 0→N pairs against the service-role count on
`event_registrations` (0→2), `class_bookings` (0→1), `subscriptions` (0→58) and `observability_events`
(0→69), because PostgREST answers `200` with `[]` when RLS filters everything.

## 8.7 What was NOT built, and must not be inferred as built

**`CONF-D8` is NOT closed.** Nine of seventeen areas now have an authorization surface. The remaining eight,
and every parked write path, are enumerated individually in **V5 §129.4**. A "no backing surface" area
received **no invented table and no speculative authorization layer**, per the owner's instruction.

**The seven pre-existing broad-read tables were not touched.** See **V5 §129.5** — a separate finding with its
own provenance, which **predates this work** and is **not** a 156/157/158 regression.
