# QA → V5 TRANSITION RECONCILIATION

**Date:** 2026-09-27 · **HEAD:** `07f5bfb` · **Branch:** `reconcile/12circle-integrated`
**Type:** READ-ONLY transition gate. No remediation, no code change, no mutation.
**Scope:** 12 Circle Fitness only.

> **V5 IMPACT ANALYSIS HAS NOT STARTED.** No V5 requirement is assumed, invented or
> reconstructed. See §17.

---

## 1 · EXECUTIVE SUMMARY

QA is closed at **90.0% — QA COMPLETE WITH OPEN FINDINGS**. This document establishes what the
system actually *is* at `07f5bfb`, from repository and live-catalog evidence, and what must be
carried into the eventual V5 Impact Analysis.

**Three findings dominate this reconciliation, and two of them are absences:**

1. **The Trust module described in the mission brief (Trust → AI Guardian · Security ·
   Incidents · Audit Logs) has NO repository evidence of any kind.** Zero implementation files,
   and **zero mentions of "Trust", "AI Guardian" or "Incidents" across all seven design
   documents.** It is recorded **NOT CURRENTLY EVIDENCED** throughout. Reconciling designs that
   are not in this repository would be fabrication (§10, §11).
2. **There is no audit infrastructure whatsoever.** A live catalog sweep for
   `audit|log|event|incident|trust|moderation|report` returns only domain tables (`weight_logs`,
   `habit_logs`, …) and event tables. The existing exhaustion report already records *"Zero
   app-side or edge-function writes to any audit table."* **Trust → Audit Logs therefore has no
   backing store, and neither does any admin action.** This is the largest single gap between
   the intended Admin/Trust surface and the evidenced system.
3. **Admin is far smaller than the brief's module list implies** — 3 screens, 4 SECURITY
   DEFINER functions, 2 migrations. No Ecosystem, Users, Coaches or Clients admin module
   exists (§9).

**One reassuring security fact, newly verified live:** the **`admin` role cannot be
self-asserted.** `enforce_profile_privilege()`'s INSERT branch coerces any role outside
`('client','coach','vendor')` to `client`, and UPDATE raises without a privileged GUC. So
`is_admin()` is sound — while `coach` and `vendor` *are* self-assertable, which is exactly the
precondition behind SEC-PHI-9 and QAX-SEC-09.

**No finding was closed, downgraded or remediated in this mission.** The QA ledger is unchanged
at 18.90/21.

## 2 · AUTHORITATIVE QA STATE (carried forward, not recalculated)

| | |
|---|---|
| Final QA status | **90.0%** |
| QA state | **QA COMPLETE WITH OPEN FINDINGS** |
| Ledger | 18.90 / 21 — **15 COMPLETED · 5 PARTIAL · 1 BLOCKED · 0 NOT-APPLICABLE** |
| Superseded figures | 78.9%, 84%, 90.5%, 89.3% (the first two also carried an arithmetic error: divided by 19 while enumerating 21) |
| HEAD | `07f5bfb` · 0 modified · 0 staged |

**No evidence found in this mission changes the ledger.** Nothing here is grounds to
recalculate, so the percentage is carried forward unaltered.

## 3 · QA FINDINGS RECONCILIATION — against actual repository state

Every finding below was re-checked against the repository or the live catalog, not against
memory of prior turns.

| ID | Sev | Classification | Evidence type | Affected component | Root mechanism | Architectural? | Remediate before V5? |
|---|---|---|---|---|---|---|---|
| QAX-SEC-08 | **P0** | OPEN / PARTIALLY VERIFIED | **static + live-catalog** | `coach_team_members` → `user_profiles` | `FOR ALL USING` with no `WITH CHECK` | **YES** — defines what "team" means | **Decision yes; code no** |
| F-03b | **P1** | OPEN / PARTIALLY VERIFIED | static + live-catalog | `may_notify()` → `notifications` | same root as P0 | **YES** | Decision yes |
| QAX-SEC-09 | **P1** | OPEN / BLOCKED | static; untestable | `event_registrations` ← `events` | minimum-necessary over-disclosure | Partly | No |
| SEC-PHI-9 | **P1** | **OPEN / VERIFIED** | **dynamic (live-reproduced)** | `storage.objects` progress-photos | no status predicate | No | No |
| SEC-PHI-10 | **P1** | OPEN / INFERRED | static only | `score_events` | no status predicate | No | No |
| SEC-AI-1 | **P1** | OPEN / INFERRED | static | AI surface | AI disclosure posture | Partly | No |
| NEW-2 | P2 | OPEN / live-catalog-confirmed | static + live-catalog | `workout_program_assignments` → `can_read_program()` | `with_check` NULL; status ignored | Partly | No |
| NEW-5 | P2 | OPEN | static | `docs/proposed/SEC_PHI_1_*.sql` | proposal uses `security_invoker = on` | **YES** | **Yes — before applying that proposal** |
| NEW-7 | P2 | OPEN | static, assertion-replicated | billing spec suite | 3 stale `skip:` | No | No |
| QAT-1 / ENV-5 | P2 | OPEN | **executed (gate run)** | `tool/anon_least_privilege.py` | hardcoded refusal constant | No | No |
| NEW-8 | P3 | OPEN | **executed (6 gates run)** | `.github/workflows/ci.yml` | no `continue-on-error`; ENV-5 is step 1 | No | No |
| NEW-9 | P3 | OPEN | static | CI secrets | secrets unconfigured | No | No |
| NEW-3 | P3 | OPEN | live-catalog | `coach_reviews` | no relationship gate | No | No |
| K-01, K-02/K-06, K-03, K-04, K-05, K-07 | P2/P3 | OPEN | static (K-04 also live) | Stripe webhook · AI fns · booking · `event_registrations` | entitlement/idempotency gaps | Partly | No |

**Evidence-type distribution, stated plainly:** of the six P0/P1 findings, **exactly one
(SEC-PHI-9) carries dynamic live reproduction.** Two are catalog-confirmed but unexecuted, two
are inferred, one is untestable. **No finding is treated as an implementation fact merely
because QA inferred it.**

## 4 · P0 / P1 RECONCILIATION (detail)

### QAX-SEC-08 · P0 · OPEN / PARTIALLY VERIFIED

| Field | Value |
|---|---|
| Root mechanism | `002:146` `CREATE POLICY "Head coach manages team" ON coach_team_members FOR ALL USING (coach_id = auth.uid())` — no `WITH CHECK`, so Postgres reuses `USING` as the INSERT check |
| Live confirmation | `pg_policies.with_check` **IS NULL**; `has_role_check = false` — the predicate calls neither `is_coach_profile()` nor any role test |
| Exploitability | **any authenticated account; no role required** |
| Affected data | `user_profiles` whole row — `parq_answers` (PAR-Q medical history), `weight_kg`, `goal_weight_kg`, `transformation_photo_urls`, `membership_tier`, billing flags |
| Security consequence | cross-user **PHI read** |
| Evidence type | static + live-catalog; **composed exploit NOT executed** (needs a write to shared QA) |
| Affects architecture | **YES** — it is a question about what a "team" *is*, not a bug |
| Affects V5 | **UNKNOWN** — cannot be determined without V5 |
| Remediation before V5 implementation | **The owner decision must precede implementation; the code fix need not precede analysis** |
| Can remain open during V5 *analysis* | **YES** |
| Dependencies | `is_team_lead_of()` · `user_profiles` SELECT policy · `may_notify()` (F-03b shares the root) |
| Owner decision required | **OD-14** (the policy population) + **OD-QAX-9** (team semantics) |

### F-03b · P1 · OPEN / PARTIALLY VERIFIED
Same root. `may_notify()` (SECURITY DEFINER) trusts `coach_team_members` and
`coach_client_relationships` at **any status** — live body read; **neither anchor filters
status**, and `coach_team_members` has no status column. Feeds `notifications` INSERT
`WITH CHECK (may_notify(recipient_id))` → attacker-controlled content in a victim's feed.
**One fix at `coach_team_members` closes both this and the P0.** Owner decision: OD-14/OD-QAX-9.

### QAX-SEC-09 · P1 · OPEN / BLOCKED
Vendor over-disclosure, **not attacker-forgeable**: `events` `FOR ALL` *does* carry a
`WITH CHECK` requiring `vendor_id = auth.uid()` **and** `role IN ('vendor','admin')`. Note
`role='vendor'` **is** self-assertable at signup (§8), so "legitimate vendor" is a low bar; the
binding constraint is the victim's voluntary registration. **Untestable with current fixtures:**
`events.vendor_id` is NULL on both QA events, so `hosts_event_for()` can never be true.

### SEC-PHI-9 · P1 · **OPEN / VERIFIED** (the only dynamically reproduced finding)
A `cancelled`-relationship coach signed a client's progress-photo object (200) while correctly
denied that client's profile, PAR-Q, check-ins, weights, measurements and AI data. Policy text
re-confirmed live: `storage.objects` "coach reads client progress photos" tests only that a
relationship **row exists**.

### SEC-PHI-10 · P1 · OPEN / INFERRED
`score_events` "coach reads client events" omits the status predicate — live-confirmed. **No
execution possible:** all 8 `score_events` rows belong to the *active*-relationship client
(where coach access is correct); the `cancelled` client has 0 rows. **Explicitly not recorded
as reproduced.**

### SEC-AI-1 · P1 · OPEN / INFERRED
Carried. The AI test tier could not execute (HTTPS egress). AI disclosure posture is owner-side.

## 5 · 12-ITEM REMEDIATION QUEUE RECONCILIATION

Columns: **Ind** = independent or consequence · **Sch** schema · **RLS** · **API** · **Mob**
mobile · **CI** · **Test** · **V5 req** · **Arch decision** · **During V5** = addressable
during V5 implementation.

| # | Item | Root cause | Subsystem | Ind? | Sch | RLS | API | Mob | CI | Test | V5 req | Arch | During V5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `coach_team_members` `WITH CHECK` | missing INSERT check | DB/RLS | **root** | NO | **YES** | NO | NO | NO | YES | UNKNOWN | **YES** | YES |
| 2 | Correct `SEC_PHI_1` proposal | wrong `security_invoker` | DB/RLS + mobile | consequence of #1 | NO | **YES** | NO | **YES** | NO | YES | UNKNOWN | **YES** | YES |
| 3 | QAT-1 / ENV-5 repoint | hardcoded ref | tooling/CI | independent | NO | NO | NO | NO | **YES** | YES | NO | NO | YES |
| 4 | `workout_program_assignments` | `with_check` NULL; status ignored | DB/RLS | independent | NO | **YES** | NO | NO | NO | YES | UNKNOWN | YES | YES |
| 5 | SEC-PHI-9/10 status predicate | 029/035 predate the helper | DB/RLS + storage | independent | NO | **YES** | NO | NO | NO | YES | NO | YES | YES |
| 6 | Unskip K-12 / K-ENV-1; review K-09 | stale skips | tests | consequence | NO | NO | NO | NO | NO | **YES** | NO | NO | YES |
| 7 | The 6 open K specs | entitlement/idempotency | edge fns + mobile | independent | UNKNOWN | **YES** (K-04) | NO | **YES** | NO | YES | **UNKNOWN** | YES | YES |
| 8 | Configure CI secrets | secrets absent | CI | independent | NO | NO | NO | NO | **YES** | NO | NO | NO | YES |
| 9 | Guard rework (SEC-G1 → column shape; CHAIN-G1 → `notifications`) | name-based detector | tests | consequence of #1 | NO | NO | NO | NO | NO | **YES** | NO | NO | YES |
| 10 | Supply chain (SBOM, 7 high npm, Dart scan) | no tooling | build/deps | independent | NO | NO | **YES** | **YES** | **YES** | NO | NO | YES | YES |
| 11 | Branch protection (confirm, then enable) | unverified | release control | independent | NO | NO | NO | NO | **YES** | NO | NO | YES | YES |
| 12 | Three QA fixtures | missing data | QA env | independent | NO | NO | NO | NO | NO | **YES** | NO | NO | YES |

**Dependency structure:** items **2 and 9 are consequences of #1**; **6 is a consequence of
prior fixes already landing**. The remaining eight are independent. **Only #1 and #2 carry a
hard architectural decision that should precede implementation.** Nothing in this queue was
acted on.

## 6 · PARTIAL / BLOCKED DOMAIN RECONCILIATION

| Domain | Proven | Unproven | Blocker type | V5 analysis depends on it? | Exact evidence that closes it |
|---|---|---|---|---|---|
| **Test completeness (0.9)** | mobile, API, contract all VERIFIED PASS at HEAD | security + AI tiers at HEAD | **authorization** (shared-QA mutation) + **environmental** (HTTPS egress) | **NO** | run both tiers with egress restored and fixture-write authorization |
| **PHI table access (0.75)** | universal RLS coverage — 91 tables, 0 RLS-disabled, 0 zero-policy, 0 anon grants | per-table boundary *correctness* | **authorization** (needs writes) | **NO** | fixture rows + per-table probes under real JWTs |
| **Supply chain (0.75)** | SBOM definitively ABSENT (6/6 questions); npm advisories enumerated | component inventory; Dart-tree vulnerabilities | **tooling** (installation forbidden) | **NO** | authorization to install `syft`/`cyclonedx`; a Dart scanner |
| **AI / processors (0.5)** | data flows traced statically | disclosure posture | **evidence + owner decision** | **UNKNOWN** | an owner ruling on AI disclosure |
| **Privacy alignment (0.5)** | claim-vs-reality matrix complete | which claims the owner will stand behind | **owner decision** | **UNKNOWN** | owner ruling |
| **Replay harness (0.5) — BLOCKED** | diagnosis complete; purpose largely superseded by direct catalog introspection | fix-**simulation** of proposed policies | **environmental** (no Docker, no Postgres server) | **NO — but it is the natural place to validate #1 and #2 before applying them** | Docker or a local Postgres |

**None of the six blocks V5 Impact *Analysis*.** The replay harness is the one worth restoring
before V5 *implementation*, because it is where the P0's fix and the corrected SEC-PHI-1 would
be validated — and §11 records that one proposal already turned out to be non-functional.

## 7 · CURRENT-STATE ARCHITECTURE BASELINE (`07f5bfb`)

Derived from the repository and the live catalog. Where a document and the repository disagree,
**the repository wins**.

| # | Area | Current state | Evidence | Known constraints | Open issues | V5 impact potential |
|---|---|---|---|---|---|---|
| 1 | **Mobile** | Flutter; **341 Dart files, 34 features**; `go_router`; Riverpod | `find`/router | role-routed at `/home` vs `/admin-dashboard` | 2 dead duplicate screens (DEAD-G1) | **HIGH** |
| 2 | **Backend/API** | **Thin NestJS** — 35 TS files, 4 modules (`config`, `auth`, `ai`, `users`) | `apps/api/src` | not the primary data path | narrow surface | MEDIUM |
| 3 | **Database** | Postgres/Supabase, **91 public tables**, 134 FKs, 5 views | live catalog + contract guard (agree exactly) | — | — | **HIGH** |
| 4 | **Supabase/Postgres** | 132 migrations, contiguous 000–131; **19 edge functions** | ENV-1 gate PASS | migration numbers 132+ reserved for waves | — | **HIGH** |
| 5 | **RLS** | enabled on **all 91** tables; 0 zero-policy; 0 anon grants | live catalog | 37 `FOR ALL`/no-`WITH CHECK` policies across 34 tables | **P0 + F-03b + NEW-2** | **HIGH** |
| 6 | **Authentication** | Supabase Auth, email/password; JWT | `auth_provider.dart` | — | — | MEDIUM |
| 7 | **Authorization** | RLS-first + SECURITY DEFINER helpers; **5 roles** — `admin`, `client`, `coach`, `vendor`, `content_manager` | live `user_profiles.role`; policy scan | **`admin`/`content_manager` NOT self-assertable; `coach`/`vendor` ARE** | role vocabulary wider than commonly documented (4) | **HIGH** |
| 8 | **AI systems** | 6 AI edge fns + 5 enrichment fns; 6 `ai_*` tables, all RLS-enabled with 1 policy each | live catalog; `ls` | **no server-side plan check** (K-03) | SEC-AI-1, K-03 | **HIGH** |
| 9 | **Admin** | **3 screens** (dashboard, exercise review, observability); **4 SECURITY DEFINER fns**; 2 migrations | `find`, router, live catalog | `is_admin()` = `role='admin'` | **no Ecosystem/Users/Coaches/Clients module** | **HIGH** |
| 10 | **Trust / security module** | **DOES NOT EXIST** | 0 files; 0 design mentions | — | entire module unevidenced | **HIGH** |
| 11 | **Notifications** | `notifications` table; INSERT gated by `may_notify()` | live catalog | `may_notify` trusts forgeable anchors | **F-03b** | **HIGH** |
| 12 | **Workflows** | no orchestration engine; logic in edge fns + mobile | `ls supabase/functions` | — | — | MEDIUM |
| 13 | **CI/CD** | 1 workflow, **7 jobs**; `static-guards` red; 4 jobs never executed | run `36093979157`; gates run locally | ENV-5 is step 1, no `continue-on-error` | NEW-8, NEW-9, QAT-1 | MEDIUM |
| 14 | **Testing** | mobile **142 test files / 1,675 pass / 9 skipped**; API 64; contract offline; security+AI blocked | executed this programme | 3 stale skips | NEW-7 | MEDIUM |
| 15 | **Migrations** | 132 files, unique, contiguous; **132+ reserved** | ENV-1 + ENV-3 gates PASS | numbers assigned at wave entry only | — | **HIGH** |
| 16 | **Config/env boundaries** | `QA_URL`/`QA_ANON`/`QA_SERVICE`/`QA_DIRECT_DB_URL` local; ENV-4/ENV-5 gates; `resolveQaTarget()` with no default | gates run; `app_env.dart` | prod ref must never be a default | **QAT-1** | MEDIUM |
| 17 | **Design system / UI** | **local only** — `app_theme.dart` + `twelve_circle_theme.dart`. **No `helix`/design-system dependency** | `pubspec.yaml` | — | — | **HIGH** |
| 18 | **Existing Admin designs** | **NOT CURRENTLY EVIDENCED** as a module set — see §9/§11 | 7 design docs; 0 Trust mentions | — | designs referenced in the brief are not in this repo | **HIGH** |
| 19 | **Client/coach relationships** | `coach_client_relationships` (status-bearing, trigger-protected) **and** `coach_team_members` (no status, no trigger) | live catalog | **two incompatible idioms** | **P0** | **HIGH** |
| 20 | **Audit/logging** | **NO audit infrastructure** — no audit table under any name; "Zero app-side or edge-function writes to any audit table" | live sweep; exhaustion report | observability screen exists but is not an audit trail | **blocks Trust → Audit Logs entirely** | **HIGH** |

## 8 · DATABASE / SECURITY RECONCILIATION

| Control | Evidenced state |
|---|---|
| RLS coverage | **91/91** tables enabled; **0** zero-policy; **0** anon or `PUBLIC` policies; **0** anon grants |
| Policy structure | 37 `FOR ALL`/no-`WITH CHECK` across 34 tables; the 18 look-alikes remain **DISPROVED** for the F-21 class (all compare `user_id`) |
| Authorization helpers | `is_admin`, `is_coach_profile`, `is_active_coach_of` (**requires `status='active'`**), `is_team_lead_of` (**no status**), `hosts_event_for`, `may_notify`, `can_read_program`, `can_act_on_program`, `shares_conversation_with` — **0** with a mutable `search_path` |
| Coach/member relationships | `coach_client_relationships`: status + `WITH CHECK` + `trg_relationship_integrity`. `coach_team_members`: **single `FOR ALL USING`, 0 triggers, 0 check constraints** |
| Admin authorization | 4 SECURITY DEFINER fns; `is_admin()` = `role='admin'`; **role coerced to `client` at INSERT unless in `('client','coach','vendor')`** → `admin` **not** self-assertable |
| Trust authorization | **NOT CURRENTLY EVIDENCED** — no Trust tables, policies or helpers |
| Audit authorization | **NOT CURRENTLY EVIDENCED** — nothing to authorize |
| Notification authorization | `notifications` INSERT `WITH CHECK (may_notify(recipient_id))`; `may_notify` filters status on **no** anchor |
| AI authorization | 6 `ai_*` tables, RLS enabled, `user_id = auth.uid()` with `WITH CHECK`; **no server-side entitlement check in the AI edge functions** |
| Sensitive-data boundaries | `user_profiles` SELECT = `id = auth.uid() OR is_active_coach_of(id) OR is_team_lead_of(id) OR hosts_event_for(id)`. Buckets: `progress-photos` + `chat-media` private; `avatars`, `coach-media`, `exercise-media` **public** |

### The `coach_team_members` architectural dependency — documented, not fixed

```
coach_team_members                      ← FOR ALL USING (coach_id = auth.uid())
  │                                       with_check = NULL, 0 triggers, 0 checks,
  │                                       NO role check (has_role_check = false)
  ├─► is_team_lead_of(target)           ← SECURITY DEFINER, **no status condition**
  │     └─► user_profiles SELECT arm    ← whole row: PAR-Q, weights, photos, billing   [P0]
  │     └─► team_member_profiles        ← proposed view; still calls is_team_lead_of()  [NEW-5]
  └─► may_notify(recipient)             ← SECURITY DEFINER, status filtered on no anchor
        └─► notifications INSERT        ← attacker-controlled content to any victim     [F-03b]
```

**Architectural reading:** `coach_team_members` is consumed as an **authorization fact** by two
independent SECURITY DEFINER helpers, while being the **only** relationship table with no
status column, no `WITH CHECK`, no trigger and no role check. Two consumers inherit from one
unguarded producer — so **"what a team is" is an architectural decision (OD-QAX-9), not a
bug fix**, and any V5 work touching teams, rosters or notifications inherits it.

## 9 · ADMIN RECONCILIATION

**Evidenced Admin surface — the complete inventory:**

| Section from the brief | Design status | Implementation status | Evidence |
|---|---|---|---|
| Admin Home | **NOT CURRENTLY EVIDENCED** | `/admin-dashboard` exists (`admin_dashboard_screen.dart`) — a dashboard, not a defined "Home" module | router:234 |
| Ecosystem | **NOT CURRENTLY EVIDENCED** | **absent** | no file, no route |
| Trust | **NOT CURRENTLY EVIDENCED** | **absent** | 0 files, 0 design mentions |
| Users | **NOT CURRENTLY EVIDENCED** | **partial primitive only** — `admin_recent_users()`, `admin_set_user_role()` | live catalog |
| Coaches | **NOT CURRENTLY EVIDENCED** | **absent** as an admin module | — |
| Clients | **NOT CURRENTLY EVIDENCED** | **absent** as an admin module | — |
| *(evidenced, not in the brief)* Exercise review | — | **exists** — `/admin-exercise-review`, migration `050_admin_exercise_moderation.sql` | router:235 |
| *(evidenced, not in the brief)* Observability | — | **exists** — `/observability` | router:237 |

**Backend dependencies that exist:** `is_admin()`, `admin_platform_stats()`,
`admin_recent_users()`, `admin_set_user_role()`, migrations `019_admin_dashboard.sql` and
`050_admin_exercise_moderation.sql`.

**Permissions:** `role = 'admin'`, **not self-assertable** (§8). Admin provisioning requires
either `admin_set_user_role()` under `circle12.privileged_role_write = 'on'` or the
service-role path (`enforce_profile_privilege` returns early when `auth.uid()` IS NULL).

**Security implications for any Admin expansion:** `admin_dashboard_screen.dart` is already
recorded in ERR-G2's allowlist as **parsing** `42501` for its "not an admin" branch — it
displays nothing. Any new admin surface must preserve that: an admin console is exactly where a
raw PostgREST error would leak table and column names to a non-admin audience.

**Audit requirements: entirely unmet.** No admin action is recorded anywhere (§8, §10).
`admin_set_user_role()` — a privilege-escalation primitive — **writes no audit record.**

**Unresolved questions:** what an "Ecosystem" module is; whether Users/Coaches/Clients are
distinct modules or views over `user_profiles`; whether `content_manager` gets an admin surface.

## 10 · TRUST RECONCILIATION

> **STATUS: NOT CURRENTLY EVIDENCED — in full.** No implementation file, no table, no policy,
> no helper, no API, and **no mention of "Trust", "AI Guardian" or "Incidents" in any of the
> seven design documents.** The hierarchy below is reproduced *from the mission brief* solely
> to record what does not yet exist. **It is not evidence, and nothing here is a design or an
> implementation commitment.**

| Trust area | UI requirement (per brief) | Required data | Required API/service | Required permission | Required audit event | Current status |
|---|---|---|---|---|---|---|
| **AI Guardian** | oversight of AI behaviour/safety | AI decision + safety records. **Partial substrate exists**: `ai_reviews`, `ai_insights`, `explain-decision` edge fn | none exists | none exists | none exists | **NOT CURRENTLY EVIDENCED** |
| **Security** | posture / control view | RLS + policy state. **Substrate exists only as catalog introspection** — no product-facing store | none exists | none exists | none exists | **NOT CURRENTLY EVIDENCED** |
| **Incidents** | incident register | **no incident table under any name** (live sweep) | none exists | none exists | none exists | **NOT CURRENTLY EVIDENCED** |
| **Audit Logs** | audit trail | **no audit table under any name; zero audit writes anywhere** | none exists | none exists | — *(it **is** the audit event)* | **NOT CURRENTLY EVIDENCED** |

**The critical consequence:** **Audit Logs cannot be built as a read-only view over existing
data, because the data has never been written.** Every other Trust page could in principle be
assembled from existing substrate; Audit Logs requires a **new write path at every
audit-worthy action** — which means it touches schema, RLS, and every admin and privileged
mutation. That is the single largest architectural implication in this document.

**No API was invented here. No permission was assumed. Nothing is solved.**

## 11 · DESIGN ↔ SYSTEM RECONCILIATION

**Seven design documents exist** — `DESIGN_TO_IMPLEMENTATION_FINAL_MATRIX`, `SCREEN_DESIGN_GAPS`,
`DESIGN_IMPLEMENTATION_RECONCILIATION`, `DESIGN_ROUTE_IMPLEMENTATION_MATRIX`,
`DESIGN_CAPABILITY_GAPS`, `DESIGN_INTAKE_REPORT`, `FINAL_NEW_SCREEN_DESIGN_COMMISSION`.

**Measured coverage of the Admin/Trust surface: essentially none.** Mentions of `admin` are
incidental (4 / 0 / 1 / 6 / 0 across the five inspected); mentions of **Trust = 0, AI Guardian =
0, Incidents = 0** in every one. No document contains an Admin section vocabulary
(Home/Ecosystem/Trust/Users/Coaches/Clients).

> **I cannot reconcile Admin/Trust designs against the system, because those designs are not in
> this repository.** The brief refers to Admin design work "already produced with Claude
> Design"; if it exists, it is held outside this repo. Producing a design-to-system matrix from
> the brief's section list would mean **inventing the designs I was asked to reconcile.** It is
> recorded as a prerequisite in §18 instead.

**What can be stated now — the requirements any such design will collide with:**

| Design requirement that any Admin/Trust surface will imply | Can the evidenced system support it? |
|---|---|
| Show an audit trail of admin actions | **NO** — no audit store, no writes (§10) |
| List/filter all users with PHI-adjacent columns | **PARTIAL** — `admin_recent_users()` exists; broad PHI reads would need a new column-limited surface, and `public_profiles` is deliberately non-PHI |
| Show security posture (RLS/policy state) | **NO** product-facing store — catalog introspection is not exposed to the app |
| Incident register | **NO** table |
| AI oversight | **PARTIAL** — `ai_reviews`, `ai_insights`, `explain-decision` exist; no aggregation surface |
| Empty / loading / error states | **CONSTRAINT** — error states must not print raw exceptions (ERR-G2, 38 sites closed; admin console explicitly parses rather than displays) |
| Role-gated navigation | **YES** — router already branches on `role == 'admin'` |
| Change a user's role | **YES** — `admin_set_user_role()`; but it writes **no audit record** |

## 12 · ARCHITECTURAL DECISION INVENTORY

| # | Cat | Question | Why it matters | Current evidence | Options (only where already evidenced) | Dependencies | Owner |
|---|---|---|---|---|---|---|---|
| D1 | SECURITY | What is a "team", and who may create a membership? | Gates the **P0** and **F-03b** with one change | `coach_team_members`: no `WITH CHECK`/status/trigger/role check | Cloud's model: lead may not insert, member may (`with check (false)` + a member-join policy) — **a model, not approved** | OD-14, OD-QAX-9 | **YES** |
| D2 | SECURITY | Should `coach`/`vendor` stay self-assertable at signup? | `is_coach_profile()` means "claimed at registration"; precondition for SEC-PHI-9 and QAX-SEC-09 | `enforce_profile_privilege` INSERT allows `client`/`coach`/`vendor` | — | D1 | **YES** |
| D3 | DATA | Do relationship-consuming policies require `status='active'` uniformly? | SEC-PHI-9/10; 2 of 5 policies omit it | live catalog | (a) inline predicate (b) `is_active_coach_of(text)` overload — **(b) recommended** | — | YES |
| D4 | DATABASE | **Is there an audit log, and what is audit-worthy?** | **Blocks Trust → Audit Logs entirely**; touches schema + RLS + every privileged mutation | **no audit table; zero audit writes** | — | Trust scope | **YES** |
| D5 | API | Does Admin/Trust go through the NestJS API or direct to Supabase? | The API is thin (4 modules); Admin today is direct-to-Supabase | `apps/api/src` | — | Admin scope | **YES** |
| D6 | MOBILE | Is Admin/Trust in the Flutter app or a separate surface? | 34 features, `go_router`, role-branched | router:216 | — | D5 | **YES** |
| D7 | ADMIN | Are Users/Coaches/Clients distinct modules or views over `user_profiles`? | Determines whether new column-limited views are needed | only `admin_recent_users()` exists | — | D4 | **YES** |
| D8 | ADMIN | Does `content_manager` get an admin surface? | A real, policy-recognised role (5 policies) that no screen serves | live catalog | — | D7 | YES |
| D9 | AI | Must AI edge functions enforce entitlement server-side? | K-03: all three sold AI fns check auth but not plan | 0 `active_membership`/`client_plan` in all three | — | — | YES |
| D10 | AI | What AI processing is disclosed to members? | SEC-AI-1; privacy alignment | matrix complete | — | — | **YES** |
| D11 | TRUST | **What is Trust's actual scope?** | Nothing is evidenced; scope determines everything downstream | **0 files, 0 design mentions** | — | D4 | **YES** |
| D12 | AUDIT | Who may read audit records, and are they immutable/retained? | Audit that is editable by its subject is not audit | nothing exists | — | D4 | **YES** |
| D13 | CI/CD | Should `static-guards` fail-late so one gate cannot blind six? | NEW-8; six gates currently unevaluated in CI (**all six pass locally**) | gates run | reorder, or `continue-on-error` per step | QAT-1 | YES |
| D14 | CI/CD | Enable branch protection on `main`? | No required checks today; `static-guards` red cannot block a merge | **unverified** — GitHub unreachable | — | — | YES |
| D15 | TESTING | Should the guard population be derived from the live catalog rather than migrations? | Source counting missed 3 duplicate policies | 37 live vs 33 source | — | — | YES |
| D16 | DESIGN | Is the local theme extracted toward a shared design system now or later? | Standing directive: **extract on the second product, not the first** | no `helix` dependency | — | — | YES |
| D17 | SECURITY | Fix `SEC_PHI_1` before applying it? | **As written it returns `200 []` for the users it serves** | NEW-5 | `security_invoker = off` + `security_barrier` + predicate in the view | D1 | YES |

**Every question marked `WAITING FOR V5 IMPACT ANALYSIS`:** D5, D6, D7, D8, D11 — each depends
on scope that only V5 defines. **No decision was made in this mission to close the report.**

## 13 · QA → V5 TRANSITION MATRIX

| QA finding / observation | Current component | V5 area potentially affected | Impact type | Dependency | Requires decision? | Requires remediation? | Waiting for V5? |
|---|---|---|---|---|---|---|---|
| QAX-SEC-08 (P0) | `coach_team_members` → `user_profiles` | **UNKNOWN** | Security / PHI | D1 | **YES** | YES | **YES** |
| F-03b | `may_notify` → `notifications` | **UNKNOWN** | Security | D1 | **YES** | YES | **YES** |
| QAX-SEC-09 | `event_registrations` | **UNKNOWN** | Privacy | D2 | YES | YES | **YES** |
| SEC-PHI-9 | `storage.objects` | **UNKNOWN** | Security / PHI | D3 | YES | YES | **YES** |
| SEC-PHI-10 | `score_events` | **UNKNOWN** | Security | D3 | YES | YES | **YES** |
| SEC-AI-1 | AI surface | **UNKNOWN** | Privacy | D10 | **YES** | UNKNOWN | **YES** |
| **No audit infrastructure** | entire system | **Trust → Audit Logs** *(named in the brief, not V5-derived)* | **Architecture** | D4, D12 | **YES** | YES | **YES** |
| **Trust not evidenced** | — | Trust | Architecture | D11 | **YES** | NO | **YES** |
| Admin is 3 screens | `features/admin` | Admin | Architecture | D5–D8 | **YES** | NO | **YES** |
| Two relationship idioms | `coach_client_relationships` vs `coach_team_members` | **UNKNOWN** | Architecture | D1 | **YES** | YES | **YES** |
| `coach`/`vendor` self-assertable | `enforce_profile_privilege` | **UNKNOWN** | Security | D2 | **YES** | UNKNOWN | **YES** |
| `content_manager` unserved | `user_profiles.role` | Admin | Product | D8 | YES | NO | **YES** |
| NEW-2 | `workout_program_assignments` | **UNKNOWN** | Security / IP | — | YES | YES | **YES** |
| NEW-5 | `docs/proposed/SEC_PHI_1` | **UNKNOWN** | Security | D17 | YES | **YES** | NO |
| NEW-7 (3 stale skips) | billing specs | **UNKNOWN** | Test integrity | — | NO | YES | NO |
| NEW-8 + QAT-1 | `ci.yml`, `anon_least_privilege.py` | CI/CD | Process | D13 | YES | YES | NO |
| NEW-9 | CI secrets | CI/CD | Process | — | YES | YES | NO |
| 6 open K specs | Stripe/AI/booking | **UNKNOWN** | Functional / entitlement | D9 | YES | YES | **YES** |
| SBOM absent | build | **UNKNOWN** | Supply chain | — | YES | YES | NO |
| No shared design system | mobile theme | **UNKNOWN** | Design | D16 | YES | NO | **YES** |
| Branch protection unverified | GitHub | Release control | Process | D14 | YES | UNKNOWN | NO |

**`UNKNOWN` is used literally**, wherever the answer depends on V5 scope that has not been
provided. It is **not** a placeholder for a guess.

## 14 · KNOWN BLOCKERS

| Blocker | Type | Blocks | What closes it |
|---|---|---|---|
| Shared-QA writes declined | **authorization** | P0/F-03b/NEW-2 execution; `test:security`; per-table PHI demos | authorization to create QA fixtures |
| **HTTPS egress (443) unavailable** | **environmental** | `test:ai`; `test:security`; branch-protection verification | egress restored *(Postgres path works)* |
| CI secrets absent | configuration | 4 live-QA jobs | configuring repo secrets |
| No Docker / no Postgres server | environmental | replay **fix-simulation** | Docker or local Postgres |
| SBOM tooling forbidden | tooling | SBOM; Dart vulnerability scan | authorization to install |
| Missing fixtures (3) | data | team-lead arm; event-host arm; SEC-PHI-10 | 1 `coach_team_members` row; 1 `events.vendor_id`; `score_events` for the cancelled client |
| **Admin/Trust designs not in repo** | **evidence** | §11 design↔system reconciliation | the design artifacts, or their location |
| Owner decisions (D1–D17) | decision | the whole remediation queue | owner rulings |

## 15 · KNOWN DEPENDENCIES

1. **P0 → F-03b → NEW-5** share one root (`coach_team_members`). One change closes the first
   two; the third inherits the helper regardless.
2. **Trust → Audit Logs → D4 (audit schema)** — the deepest chain: no Trust audit page can exist
   until an audit write path exists at every audit-worthy action.
3. **Admin expansion → D4** — admin actions (notably `admin_set_user_role()`, a
   privilege-escalation primitive) currently write no audit record.
4. **`SEC_PHI_1` → P0 fix** — the views inherit `is_team_lead_of()`, so applying them before D1
   leaves name/email enumeration open.
5. **Guard rework → P0 fix** — SEC-G1's population should be re-derived from the live catalog.
6. **Replay harness → validating #1 and #2** — the natural place to simulate both before
   applying either, and one proposal has already proved non-functional.

## 16 · V5 QUESTIONS THAT CANNOT YET BE ANSWERED

Each requires V5 scope that has **not** been provided, and none is guessed at here:

1. Which V5 areas touch teams, rosters or notifications — i.e. whether V5 inherits the P0?
2. Does V5 require an audit trail, and at what granularity?
3. What is Trust's scope, and which of its four areas are in V5?
4. Are Admin Users/Coaches/Clients distinct modules or views?
5. Does Admin/Trust run through the NestJS API or direct to Supabase?
6. Is Admin/Trust inside the Flutter app or a separate surface?
7. Does V5 change the role model (e.g. serve `content_manager`, or restrict self-assertable `coach`/`vendor`)?
8. Does V5 require server-side AI entitlement (K-03)?
9. Which PHI columns must new Admin surfaces expose — and to whom?
10. Does V5 change the billing/entitlement model the 6 open K specs describe?

## 17 · V5 IMPACT ANALYSIS HAS NOT STARTED

**Explicit statement.** No V5 Impact Analysis was performed. **No V5 requirement was assumed,
invented, or reconstructed from memory.** The V5 document was neither attached nor requested.
Every V5-dependent cell in §13 reads `UNKNOWN`, and §16 lists the questions rather than
answering them. The Trust hierarchy in §10 is reproduced **from the mission brief only**, to
record its absence from the repository — it is not treated as a V5 requirement or a design.

## 18 · PREREQUISITES FOR BEGINNING V5 IMPACT ANALYSIS

| # | Prerequisite | Why | Blocking? |
|---|---|---|---|
| 1 | **The V5 document itself** | nothing in §13/§16 can be resolved without it | **YES** |
| 2 | **The Admin/Trust design artifacts, or their location** | §11 cannot be completed from this repository; they are not in it | **YES, for design↔system reconciliation** |
| 3 | Owner ruling on **D4 (audit)** | the deepest architectural dependency; changes schema, RLS and every privileged mutation | **YES, if Trust/Admin is in V5 scope** |
| 4 | Owner ruling on **D1 (team semantics)** | gates the P0 and F-03b | Not for *analysis*; **yes for implementation** |
| 5 | Owner ruling on **D11 (Trust scope)** | determines whether §10's absences matter | **YES, if Trust is in V5** |
| 6 | Confirmation that the QA ledger stands at 18.90/21 | the V5 baseline | YES |
| — | *Not prerequisites:* egress, Docker, SBOM tooling, CI secrets, QA fixtures | they block **evidence**, not analysis | NO |

**Readiness assessment:** the system is **ready for V5 Impact Analysis to begin** once item 1 is
supplied, with the caveat that items 2, 3 and 5 will gate the Admin/Trust portion of that
analysis. **This is not a statement of readiness for V5 implementation**, which requires the
owner decisions in §12 and the remediation queue in §5.

---

## FINAL ADVERSARIAL REVIEW

| Challenge | Outcome |
|---|---|
| 1. Treated a QA inference as an implementation fact? | **No.** §3 carries an evidence-type column; SEC-PHI-9 is the only P0/P1 marked VERIFIED |
| 2. Closed an open security finding? | **No.** All 6 P0/P1 remain open with unchanged classifications |
| 3. Recommended remediation? | **No.** §5 and §12 *inventory* without prescribing; the one "recommended" note (D3 option b) is carried from prior QA, not new |
| 4. Inferred a V5 requirement? | **No.** Every V5 cell is `UNKNOWN`; §17 is explicit |
| 5. Assumed an API exists because a design expects it? | **No** — and this was the main risk. Trust is marked **NOT CURRENTLY EVIDENCED** four times over; no API was invented |
| 6. Assumed a permission exists because a screen requires it? | **No.** Admin permissions were read from the live catalog (4 fns); Trust permissions recorded as non-existent |
| 7. Overlooked Admin/Trust security implications? | **No** — §9 records the ERR-G2 constraint and that `admin_set_user_role()` writes no audit record |
| 8. Overlooked audit requirements? | **No** — it is the headline finding (§10, D4) |
| 9. Overlooked database dependencies? | **No** — §8 and §15 |
| 10. Overlooked migration dependencies? | **No** — 132 files, contiguous, **132+ reserved, assigned at wave entry only** |
| 11. Confused current implementation with intended architecture? | **Corrected during the pass.** The brief's Admin module list and Trust hierarchy are *intent*; §9/§10 record them as unevidenced rather than as current state |
| 12. Relied on stale documentation over repository evidence? | **No.** Where they conflict the repository wins — e.g. the role vocabulary is **5** roles (live data + policies), not the 4 commonly documented |
| 13. Modified anything? | **No** — documentation only |
| 14. Crossed a shared-QA boundary? | **No** — all queries read-only under `default_transaction_read_only=on`; `test:security` deliberately not run |

---

*Read-only transition gate. QA ledger unchanged at 18.90/21 = 90.0%. 1 P0 and 4 P1 findings
remain open and unremediated. V5 Impact Analysis has not started.*
