# 12Circle Fitness — Master QA Findings Ledger

**Single source of truth for the remediation phase.** Supersedes the finding
lists in `QA_SECURITY_HIPAA_EXHAUSTION_REPORT.md` and
`QA_SECURITY_HIPAA_REMEDIATION_REPORT.md`, which remain valid as evidence.

**Branch** `chore/qa-environments-secure-ai-backend` · **HEAD at writing** `7847c4e`
**Baseline** 1,622 pass / 9 skipped / 0 analyzer errors / 35 guard tests
**Live evidence** QA `eyqtldjqpgpljlqvpowh`, read-only except one authorised
negative test (§D-02). Production **never contacted**.

> Not a HIPAA compliance certification. Controls needing legal review are
> marked OWNER DECISION.

---

## 1 · Status counts

| Status | Count |
|---|---|
| VERIFIED | 14 |
| FIXED | 6 |
| FALSE POSITIVE / RETRACTED | 9 |
| OPEN | 9 |
| BLOCKED | 5 |
| OWNER DECISION | 11 |
| NOT TESTABLE | 4 |

---

## 2 · FIXED

| ID | Fix | Evidence |
|---|---|---|
| SEC-PHI-2 | PHI screens no longer print DB errors | 3/3 mutations |
| ERR-2 | 38 raw-exception displays closed across 26 files | ERR-G2, 5/5 |
| SEC-VIDEO-1 | Video responses store an object path | VIDEO-G1, 4/4 |
| SEC-VOICE-2 | Voice notes store an object path; delete path re-normalised | VOICE-G2, 4/4 |
| OD-60 (error half) | Failed AI-memory deletion is reported | AIMEM-G1, 6/6 |
| LIFE-G1 | 54 `setState`-after-`await` crash sites guarded | 4/4 |

---

## 3 · VERIFIED (live, negative-tested)

| Control | Evidence |
|---|---|
| Anonymous least privilege | `42501` at GRANT level on every PHI table |
| Client ↔ client isolation | attacker → victim's PAR-Q/weight/photos = **0** |
| **Relationship revocation** | **former coach** (`status='cancelled'`) denied profile, PAR-Q, check-ins, weight, measurements, AI memories |
| **D-02 privilege escalation** | victim's own row: `role`, `membership_tier`, `marketplace_commission_rate`, `stripe_charges_enabled`, `is_demo` **all rejected `42501`**; control write (`first_name`) applied; attacker cross-user write returned **rows=0** |
| `invite_token` withholding | `42501` for all five identities **including admin**; no regression |
| RPC IDOR surface | every UUID-accepting fn → `42501` for attacker and coach |
| Admin function gating | `admin_platform_stats` / `admin_recent_users` admin-only |
| `is_admin()` | returns `false` to a non-admin |
| RLS coverage | **all 92 created tables** carry an RLS statement |
| `search_path` pinning | migration 118 catch-all loop |
| Migration reproducibility | clean rebuild reproduces observed protections |
| No analytics/telemetry/crash SDK | absent from `pubspec.yaml` |
| No PHI in logs | 0 interpolating `print`/`debugPrint`; release sink emits nothing |
| No PHI in URLs / local storage / notifications | routes static; 0 PHI persisted locally; 0 PHI in notification bodies |

---

## 4 · FALSE POSITIVE / RETRACTED

| ID | Why it was wrong |
|---|---|
| **SEC-DRIFT-1** | Migration `074:73–81` **does** create the RLS (`DO` loop, `format('%I')` over a `text[]`). Detection grep required table name + keyword on one line. Clean rebuild reproduces it; `deleteMemory` **is** constrained (`FOR ALL`). |
| **SEC-PHI-5** (RLS half) | All 92 tables covered once DO-loops are counted; Privacy §7's RLS claim is **substantiated**. |
| "3 tables had RLS disabled" | All three `DISABLE` lines are **inside comments** (rollback notes); each table is enabled by the same migration. |
| "115/119 regressed the P0 fixes" | Not reproducible. 115 **is** the D-02 fix; 119 is the workout prescription contract. Live test confirms escalation is blocked. |
| 53 "unpinned `search_path`" | Migration 118 pins every unpinned function. |
| `exercise_modifications` as PHI | No `user_id` (`42703`) — an exercise catalogue. |
| `coach_client_relationships` "unreadable" | Column-level grants; `select=*` fails only for the two withheld columns. |
| `marketplace_coaches` leaking PHI | `RETURNS TABLE` limits it to marketing columns. |
| `ai_nutrition_service` third-party egress | Posts to `_env.apiUri(...)` — **own infrastructure**. |
| **F-J-01** (`materialize_program_week` unguarded) | **Fixed by migration `124_wave_2a_security_regressions.sql`**, which restores the `can_act_on_program()` guard with a `RAISE EXCEPTION`. The carried-forward note blamed 115/119; 115 is the D-02 *fix*. |
| **F-J-17** (`derive_parq_risk` raises `22P02`) | **Not reproducible.** `PATCH {has_injuries:true, injury_locations:'knee'}` on the member's own row returned **200** and the `apply_parq_risk` trigger computed `risk_flags:'active_injuries'`. Row restored immediately. |

---

## 5 · OPEN — technical defects for the remediation queue

### SEC-PHI-1 — roster/vendor PHI boundary · **OPEN, PROPOSED**
The `102` policy's `is_team_lead_of` and `hosts_event_for` arms grant the
**entire** `user_profiles` row — `parq_answers`, weight, transformation photos,
billing. `is_team_lead_of` has **no status check** (no revocation path);
`hosts_event_for` gives an event vendor permanent access from one registration.

**Full affected-surface map (this phase):** every cross-user `user_profiles`
read was classified. Only **two** consume the widened arms, and each needs
exactly four columns:

| Surface | Columns consumed |
|---|---|
| `coach_business_screen.dart:67` (team roster) | `first_name, last_name, email, avatar_url` |
| `vendor_service.dart:41` (attendee list) | `first_name, last_name, email, avatar_url` |

All other cross-user reads correctly gate on `status='active'`
(`compliance_service:85`, `coach_dashboard_screen:62`, `score_service:89`,
`coach_triage_provider`) or are self-reads (`cancelCoach`, `intake_flow`).

→ `docs/proposed/SEC_PHI_1_roster_attendee_views.sql` (AUTHORED, UNNUMBERED).

### SEC-PHI-6 — pending coach requests cannot render *(new)* · **OPEN**
`getPendingRequests` reads `coach_client_relationships` where
`status='pending'`, then reads those clients' `user_profiles`. The `102` policy
only permits `is_active_coach_of`, which requires `status='active'`.
**Pending ≠ active by definition**, so the profile read returns `200 []`, and
`coach_dashboard_screen:933` renders
`'${profile['first_name'] ?? ''} …'.trim()` → **an empty name**. A coach
accepts or declines an anonymous request.

Second defect in the same query: it requests **`weight_kg`** — PHI — for people
who are merely *prospective* clients. Denied today; it would start returning
data if the policy were widened.

### SEC-PHI-7 — PAR-Q / medical history cannot be corrected *(new)* · **OPEN**
`parq_answers` is written **only** by the intake flow. `/intake` is reachable
only from login/signup when `onboarding_complete == false`; **no screen links
to it**. Privacy §5 Correction claims *"You may update your personal
information directly within the app."*

Clinical consequence: migration 115's `apply_parq_risk` trigger derives
`risk_score` / `risk_level` / `risk_flags` from `parq_answers`,
`medical_conditions`, `has_injuries`, `injury_locations`. Those feed
`auth_provider:98`, four sites in `client_detail_screen`, and the AI coach. A
member who develops a condition, injury or pregnancy **cannot update it**, so
the derived risk stays permanently stale.

### SAFE-1 — unknown clinical risk renders as the safest value *(new)* · **OPEN**
`client_detail_screen` at `:32`, `:74`, `:216`, `:799`:
`d['risk_level'] as String? ?? 'low'` and `d['has_injuries'] as bool? ?? false`.
**Absent data displays as "low risk" and "no injuries"** on the coach's screen,
and `_generateAiSummary` / `_generateActions` derive from the same map. This is
the F-15 / `CheckinKnown` class applied to clinical safety.

> **Supporting observation, from the live F-J-17 test.** With
> `parq_answers = {}`, a member carrying `has_injuries = true` derives
> `risk_score 0` / `risk_level 'low'` while `risk_flags` reads
> `active_injuries`. The coach's badge keys off `risk_level` (`:32`, `:74`,
> `:216`) and reads `risk_flags` only at `:801`. Whether an injury alone should
> escalate the *level* is a clinical question for the owner, not a defect QA
> may call — recorded so it is not lost.

### SEC-MEDIA-2 — transformation photos cannot be removed *(new)* · **OPEN**
`coach_business_screen:135–137` does `current.add(url)` and writes back —
**append only**. `_ProfileTab` receives `onAddCert`, `onRemoveCert`,
`onAddPhoto` and **no `onRemovePhoto`**. Certifications can be removed;
photographs of identifiable clients cannot. With OD-58 (public bucket) and no
account deletion, a client who withdraws consent has **no path** to removal.

### SEC-MEDIA-1 — avatars are enumerable · **OPEN**
`avatars` is public and the path is `"$uid/avatar.$ext"`. Anyone holding a UUID
fetches the photo unauthenticated. Shape-confirmed; not demonstrated live (no
fixture avatar).

### A11Y-1 — sub-44dp and unlabelled tap targets *(new)* · **OPEN**
**20** tappable children declare both dimensions with at least one < 44dp;
**14** of those also have no nearby `Semantics`. Confirmed samples:
`action_center_screen:193` (32×32, unlabelled toggle),
`activity_screen:111` (unlabelled avatar → `/profile`).
A broader sweep suggested ~342 unlabelled tap targets, but that detector has a
high false-positive rate and **that number is not a finding** — a proper audit
is required.

### SEC-VOICE-1(b) — `coach-media` is public · **FIXED_PENDING_MIGRATION**
Re-confirmed public live. Blast radius is now minimal: voice signs, video has
no reader, only OD-58 remains. Pre-SEC-VOICE-2 rows still hold live public URLs
until the bucket is privatised (backfill noted).

### No AI retention policy *(new)* · **OPEN**
No TTL, cleanup or expiry exists on `ai_memories`, `ai_conversations`,
`ai_insights`. Combined with no account-deletion path, "retained as long as
your account is active" (Privacy §6) is unbounded in practice.

---

## 6 · BLOCKED

| ID | Blocker |
|---|---|
| SEC-PHI-1 (apply) | migration number — `132+` at wave entry |
| SEC-VOICE-1(b) | migration number |
| SEC-PHI-3 / N-07 | RPC absent live (`PGRST202`); migration not applied |
| SEC-PHI-AUDIT | no audit table exists (`PGRST205` × 7); migration blocked |
| Runtime verification | **781 MiB free (96 %)**, Docker down, 0 simulators |

---

## 7 · OWNER DECISION

| ID | Decision |
|---|---|
| SEC-AI-1 | Disclose **Anthropic**, **Resend**, **Google/YouTube** and **OpenFoodFacts** as processors. Privacy §3 names only Supabase, Expo, analytics. Identifiable injuries, pain, allergies, `cycle_logs`, weight and nutrition reach Anthropic. |
| SEC-PHI-4 | Terms §9 and Privacy §5 Access promise controls at *Profile → Settings → Account* that do not exist. Privacy §5 Deletion is accurate. |
| SEC-PHI-7 (product half) | Should PAR-Q be editable post-intake? *Clinical — AG-10 may not decide.* |
| SAFE-1 (product half) | Should unknown clinical risk display as "unknown" rather than "low"? *Clinical.* |
| SEC-PHI-1 residual | Should an event vendor receive an attendee's **email**? |
| OD-57 / OD-59 | Build the video player and coach feedback view, or remove. |
| OD-58 | May `transformation_photo_urls` stay public? |
| OD-60 (design half) | Is a hidden long-press an adequate control over health data? |
| OD-61 | `marketplace_coaches` exposes `plan_tier`/`rank_score` to all authenticated. |
| OD-62 *(new)* | Should `getPendingRequests` request `weight_kg` for prospects at all? |
| Data retention | Confirm the operational 30-day purge process behind the email channel. |

---

## 8 · NOT TESTABLE

| Item | Why |
|---|---|
| `is_active_coach_of` arm | no **active** fixture relationship; the one that exists is `cancelled` |
| `is_team_lead_of` / `hosts_event_for` arms | `coach_team_members` and `event_registrations` are **empty** |
| 22 PHI tables | 0 rows for every identity — an empty table cannot demonstrate a boundary |
| Private-vs-absent buckets | the `__nope__` control returns the same response |

All four lift with **`QA_SERVICE`** plus three seed rows.

---

## 9 · Recommended remediation order

1. **SEC-PHI-6** — code-only, no migration. A coach cannot read a prospect's
   name today; this is broken in production now.
2. **SAFE-1** — clinical defaults, once the owner rules.
3. **SEC-MEDIA-2** — add `onRemovePhoto`; mirrors the existing `onRemoveCert`.
4. **Wave entry** → SEC-VOICE-1(b), then SEC-PHI-1 (**prototype the PostgREST
   embedding change first**), then N-07 + `assessment_access_log`.
5. **SEC-PHI-7** — reachable intake edit, or correct Privacy §5.
6. **A11Y-1** — the 20 confirmed targets; commission a real audit for the rest.
7. Owner decisions in §7, **SEC-AI-1 first**.
8. **Provide `QA_SERVICE` + 3 seed rows** — converts §8 from untestable to tested.
9. **Reclaim disk** — runtime blocked across four phases.

---

## 9b · PHASE 2 ADDENDUM — correction rights, storage revocation, injection

**Baseline at close:** 1,625 pass / 9 skipped / 0 analyzer errors / 36 guards.
**Git:** `0fc5f5e` on `chore/qa-environments-secure-ai-backend`; tree clean except
another workstream's untracked `d09-assessment-access.mjs`; second worktree
`wrk02-negative-control` untouched. **Disk 788 MiB (96 %) — runtime still blocked.**

### Findings discovered this phase

| ID | Finding | Status |
|---|---|---|
| **SEC-PHI-9** | **A coach keeps access to a client's PROGRESS PHOTOGRAPHS after the relationship ends.** `029:36` tests only that a relationship *row exists* — no status predicate — so `pending`, `declined` and `cancelled` all satisfy it, and the row is never deleted, only set to `cancelled`. | **FAILED — VERIFIED LIVE** |
| **SEC-PHI-10** | `score_events` "coach reads client events" (`035:183`) has the identical missing predicate. | **INCONCLUSIVE** (fixture has 0 rows) |
| **SEC-PHI-8** | **The correction right exists in the database and is unreachable in the app.** | **FAILED (product surface)** |
| `user_badges` `USING (true)` | Any authenticated member could read another's achievements. | **INCONCLUSIVE** (no data) |

**SEC-PHI-9 live evidence** — throwaway object uploaded by the owner, probed,
removed; net state change none:

| Actor | Sign the object | Note |
|---|---|---|
| owner | **200 SIGNED** | baseline |
| attacker | 400 not_found | denied ✓ |
| **coach (`cancelled`)** | **200 SIGNED** | **the finding** |
| admin | 400 not_found | denied ✓ |
| anon (public route) | Bucket not found | **`progress-photos` is PRIVATE** — resolves a prior NOT TESTABLE |
| attacker DELETE | 400 Unauthorized | ✓ |
| owner DELETE | 200, verified gone | cleanup ✓ |

→ `docs/proposed/SEC_PHI_9_progress_photo_revocation.sql` (AUTHORED, UNNUMBERED),
covering both policies and documenting the **cast hazard** migration 130 records:
`is_active_coach_of` takes `uuid`, and a raising cast on a path segment aborts
every read of the bucket for every user. Two safe alternatives are set out.

### SEC-PHI-8 — the correction right, category by category

**Live-verified with reversible writes; every row restored (`MATCHES ORIGINAL: True`).**

| Category | DB permits correction? | App exposes it? |
|---|---|---|
| first/last name | ✓ | ✓ |
| gender, date_of_birth, phone | ✓ | **set only — cannot be cleared** |
| height, weight, goal weight | ✓ | **set only — cannot be cleared** |
| **email** | ✓ (DB) | **✗ no path anywhere** (`auth.updateUser` is password-only) |
| **PAR-Q, medical_conditions, dietary_restrictions, food_allergies** | **✓ all permitted** | **✗ intake-only; `/intake` is unreachable post-onboarding** |
| weight_logs, body_measurements, nutrition_logs, cycle_logs, cycle_symptoms | UPDATE ✓, **DELETE ✓** | **✗ neither offered** |
| weekly_checkins | UPDATE ✓, **DELETE denied `42501`** | update only — **a deliberate, correct exception** |
| ai_memories | ✓ | ✓ (long-press only — OD-60) |

The guarded-write pattern is the mechanism:
`if (_phoneCtrl.text.trim().isNotEmpty) payload['phone'] = …` — clearing a wrong
value writes nothing and the old value persists. **Erasure is part of
correction.**

Answering the directive's questions 8 and 9 directly: the capability is
**implemented but unreachable**, not intentionally withheld.
`enforce_profile_privilege` deliberately blocks role/billing/Stripe columns
while permitting every health field, and `weekly_checkins` DELETE is
deliberately denied — the schema author *did* reason about this, which makes
the remaining grants look intended rather than accidental.

**End-to-end erasure proof** (net state change none, 1 row → 1 row):
member INSERT own record → **201**; **attacker DELETE on the member's real row
→ 0 rows deleted**; owner DELETE → **1 row deleted**. RLS enforces on DELETE,
not only SELECT.

### Controls VERIFIED this phase

| Control | Evidence |
|---|---|
| Cross-user DELETE isolation | attacker deleted **0** of the owner's real rows |
| Storage cross-user read | attacker and admin both denied; owner permitted |
| Storage cross-user delete | attacker `400 Unauthorized` |
| `progress-photos` is private | anon public route refused on an object known to exist |
| **PostgREST filter injection** | comma, paren+`or`, quote, null-byte payloads all return **0 rows** (literal text); `weekly_checkins` stays 0 **regardless of filter** |
| Deep-link surface | **none** — 2 intent-filters, both `MAIN`/`LAUNCHER`; no custom scheme/host; no id-bearing routes |
| Search surfaces | `.ilike` hits are exercise/food **catalogues**; `.or()` filters self-scope to `auth.currentUser.id` |
| Admin boundary | admin reads **0** of the member's PHI and is denied their storage objects |
| Signed-URL lifetime | uniformly 3600 s across voice, chat, progress photos |

### Retracted / not reported this phase

- **`badges` `USING (true)`** — a catalogue of 11 badge definitions, not user
  data. **FALSE POSITIVE.**
- **`%`/`*` returning 621 rows** — legitimate wildcard on a public catalogue;
  identical to the unfiltered count, so no escalation.
- A third "missing status" policy — the sweep found exactly five inline
  relationship policies; **three correctly check status**.

### Mutation testing

**REVOKE-G1 — 5/5 killed:** a third policy losing its status check; the helper
dropping `status='active'`; the helper dropping `coach_id = auth.uid()`; a known
offender fixed but left in the allowlist; **an offender hidden by commenting it
out** (the guard strips line comments first, because commented rollback SQL has
been mistaken for active SQL in this programme before).

### Tests that could NOT be performed

| Test | Blocker |
|---|---|
| ACTIVE-coach storage read (SEC-PHI-9 regression) | no `status='active'` fixture → **`QA_SERVICE`** |
| `score_events` / `user_badges` exposure | fixture has 0 rows → **`QA_SERVICE`** |
| Team-lead / event-host arms | driving tables empty → **`QA_SERVICE`** |
| Schema/policy introspection | **Docker down** |
| Any app runtime | **disk 788 MiB** |

---

## 10 · Exhaustion assessment

This phase ran further sweeps across authorization, media, AI, data-subject
rights, PHI egress and accessibility. It produced **six new findings**
(SEC-PHI-6, SEC-PHI-7, SAFE-1, SEC-MEDIA-2, A11Y-1, AI retention), **one new
live verification** (D-02), and **five retractions** — so the surface was *not*
exhausted when the previous report said so.

The signal is now changing: the final sweeps (analytics, HTTP egress, export
paths, notification bodies) returned either already-covered results or false
positives. Two detectors in this phase had to be tightened before their output
was usable, and one candidate count (~342 a11y) was discarded as unreliable
rather than reported.

**Status after Phase 1: SECURITY QA EXHAUSTED FOR THAT PHASE.**

### Phase 2 re-assessment

That status was premature. Phase 2 produced **four more findings**, one of them
the most serious authorization failure found in the whole programme
(**SEC-PHI-9**, verified live), plus nine newly verified controls. Static
sweeping was *not* exhausted; what was missing was a different question —
"does revocation hold for **storage** as it does for tables?" — which no prior
sweep had asked.

The signal now: this phase's last four probes (deep links, search surfaces,
filter injection, admin boundary) all returned **VERIFIED SAFE or FALSE
POSITIVE**, and the remaining untested items are blocked on credentials or
environment rather than on analysis.

**Every executable class in this environment is now examined or explicitly
classified.** What remains needs a capability, not more sweeping:

| Unblocks | What it would enable |
|---|---|
| **`QA_SERVICE` + 3 seed rows** (one `active` relationship, one `coach_team_members`, one `event_registrations`) | SEC-PHI-9 regression test, SEC-PHI-10, `user_badges`, the three `102` arms, 22 undemonstrated tables |
| **Docker** | schema/policy introspection; direct RLS flag reads |
| **~10 GiB disk** | all app runtime verification |
| **Wave entry (`132+`)** | SEC-PHI-9/10, SEC-PHI-1, SEC-VOICE-1(b), N-07, SEC-PHI-AUDIT |

**SECURITY / HIPAA QA EXECUTABLY EXHAUSTED — OPEN FINDINGS REMAIN.**

Not "all findings fixed", and not a claim of HIPAA compliance. **SEC-PHI-9 is
an unmitigated live authorization failure on body photographs** and should lead
the next remediation wave.

### Recommended next QA phase

1. Obtain `QA_SERVICE`; seed the three fixture rows. This is the single highest-
   leverage action available and it gates six open items.
2. Wave-entry numbering for `SEC_PHI_9_progress_photo_revocation.sql` — but
   **resolve the cast hazard and seed an active relationship first**, or the fix
   may break legitimate coach access with no test able to detect it.
3. Then SEC-PHI-1, SEC-VOICE-1(b), N-07 + audit log.
4. Owner decisions, SEC-AI-1 first.
