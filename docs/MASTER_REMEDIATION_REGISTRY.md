# 12 Circle Fitness — Master Remediation Registry

**Wave 0 deliverable. The canonical finding ledger for the whole programme.**
**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environments:** QA `eyqtldjqpgpljlqvpowh` · Production `nxdbooufqzkpslkcogxc` — **not contacted during this reconciliation.**

> This document supersedes the per-workstream finding lists as the **tracking** artifact.
> It does not supersede them as **evidence**; every row points back to the report that
> proved it. Where this registry and a source report disagree on severity, status or
> classification, **this registry is authoritative and the deviation is stated.**

---

## 0. What this reconciliation did

| Step | Result |
|---|---|
| Reports read in full | `MASTER_QA_RECONCILIATION`, `REMEDIATION_EXECUTION_PLAN`, `PHASE_1_SECURITY_AUDIT`, `PHASE_2_WORKOUT_RECONCILIATION`, `WORKOUT_DOMAIN_CONTRACT`, `PHASE_2_WORKOUT_TEST_MATRIX`, `qa-environments`, and workstreams **A–N** (14 reports, ~11 000 lines) |
| Raw finding records ingested | **428** |
| Aliases collapsed | **118** |
| Canonical findings | **310** |
| Independently re-verified this session | 14 claims (§0.2) |
| Code changed | **none** |
| Migrations written | **none** |
| Environments contacted | **none** — no QA or production request was issued |

### 0.1 Evidence classes (used in every row)

| Mark | Meaning |
|---|---|
| **LIVE** | Reproduced against QA with a real request by the owning workstream |
| **SRC-V** | Proven from source **and re-verified in this session** against the current tree |
| **SRC** | Proven from source by the owning workstream; not re-derived here |
| **RPT** | Carried on the owning workstream's live reproduction |
| **OPEN** | Suspected; needs a probe or a decision before it can be classified |
| **UNVERIFIABLE** | Depends on production or on dashboard state that was deliberately not inspected |

### 0.2 Claims re-verified in this session

Fourteen load-bearing claims were re-derived against the current working tree, because
they gate the whole plan and the tree has moved under several workstreams.

| Claim | Source | Result |
|---|---|---|
| 20 migrations untracked, incl. 113–122 | LRE-03 | **CONFIRMED** — `git status` shows 20 `??`, `000` and `104`–`122` |
| 15 historical migrations edited in place | LRE-04 | **CONFIRMED** — 15 ` M`, list matches exactly |
| `APP_ENV` defaults to `prod` | LRE-01 / REL-07 | **CONFIRMED** — `app_env.dart:151` |
| Three Dart harnesses hardcode the production ref | LRE-02 / REL-18 / K-ENV-1 | **CONFIRMED** — `tool/live_integration_test.dart:15`, `qa_self_guided.dart:22`, `qa_entitlements.dart:27` |
| No CI beyond a production keep-alive ping | LRE-05 / N-01 | **CONFIRMED** — `.github/workflows/` holds one file |
| `materialize_program_week` lost its authorization guard | F-J-01 | **CONFIRMED** — 116 built a `can_act_on_program` wrapper over `*_engine`; `119:403` re-creates the public name as a bare `SECURITY DEFINER` body and `119:483` re-grants it to `authenticated`; `122` repins `search_path` by `ALTER FUNCTION` only and **does not restore the guard** |
| `derive_parq_risk` throws on the three literal flag appends | F-J-17 | **CONFIRMED** — `115:142,143,145` append untyped literals to a `text[]`; the indexed append at `:140` is typed and safe, so only pregnancy / postpartum / active-injury writes fail |
| `build_workout` throws whenever recovery < 60 | F-J-07 | **CONFIRMED** — `089:51` declares `rules text[]`; `089:55` appends the untyped literal `'RECOVERY_REDUCTION'` |
| Workout completion swallows persistence and celebrates anyway | EC-05 / N-07 | **CONFIRMED** — `active_workout_screen.dart:608` awaits `logWorkout` unguarded, `:611-619` wraps `completeSession` in `catch (_) {}` |
| `public.checkins` is created by no migration | CON-01 / I-CHK-01 / E-CHK-01 / M-02 | **CONFIRMED** — only `weekly_checkins` exists (`000:146`); `checkin_service.dart` and `coach_dashboard_screen.dart` both read `checkins` |
| Every A–N report is itself untracked | new | **CONFIRMED, and undercounted** — `docs/` held **29** untracked files, not 18. W1-T1 established that the whole untracked set is **96 files, not 62**: `git status` collapses a wholly-untracked directory into one entry, so `supabase/tests/` (25 files, every live security and AI probe) counted as a single item. All 96 are now tracked |
| Schema-contract guard exists and is wired | I | **CONFIRMED** — `npm run test:contract`, `supabase/tests/contract/known-violations.json` carries 2 relations + 8 columns |
| Live security / AI suites exist and are unwired | Phase 1, J, N | **CONFIRMED** — `supabase/tests/security/` (6 suites), `supabase/tests/ai/` (5 suites); neither runs in CI |
| Current mobile baseline | N (699) | **RE-MEASURED: 730 passed, 9 skipped, 0 failed** — the tree moved again after N |

**One correction to the reports, arising from this re-measurement:** every count quoted
in a workstream report (514 / 591 / 623 / 667 / 690 / 699 / 730) is a snapshot of a tree
that several sessions were writing to concurrently. **730/9/0 is the Wave 0 baseline.**
No count below 730 should be treated as a regression signal.

---

## 1. Canonical root-cause model

Prior workstreams produced five overlapping numbering schemes (`RC-1…RC-8` in the master
reconciliation, `RC-A…RC-D` in Phase 2, `C-1/C-2` in B, `RC-H1…RC-H5` in H, and
`RC-5/7/8/3/4/9/10/11/12` in I). They are **not** reconcilable by renumbering, because
several describe the same defect at different altitudes. The model below is canonical.
**Every prior ID maps into it; no prior ID survives as a tracking key.**

| ID | Root cause | Statement | Supersedes |
|---|---|---|---|
| **CRC-01** | **Schema-contract drift** | The application names relations and columns the database does not have. PostgREST validates the select list **before** authorization, so the answer is `400 / 42703` — never a permission error — and every call site converts it to an empty value. A typo is indistinguishable from a feature that was never built. | RC-H2; part of RC-5, RC-7 |
| **CRC-02** | **Undeclared payload contracts** | A payload or vocabulary crosses a boundary with no schema, no CHECK and no validator, and its writers and readers disagree. | RC-5, RC-A |
| **CRC-03** | **Failure returned as a legitimate value** | Two mechanically distinct halves. **C-1:** a thrown failure is caught and converted to `[]`/`null`/`false`/`0`/`{}`. **C-2:** no exception is ever thrown — PostgREST answers an RLS-filtered or id-missed write with **200 and zero rows**, so `await update(...); return true;` reports a write that never happened. | RC-7, RC-C |
| **CRC-04** | **Fabricated success** | Distinct from CRC-03: the fallback returns **fiction**, not emptiness — a ticket code for a row that was never written, invented coach messages, invented habit streaks, a fabricated `risk_level`, a synthetic `pending` check-in, a stated £0.00 balance. | RC-9, RC-H1 |
| **CRC-05** | **Degraded safety input, decision proceeds** | An input that constrains a safety decision fails to load, silently becomes the empty set, and the decision is made anyway — then recorded as a valid trace with a confidence score computed from the same emptied arrays. | new (B rule **S**) |
| **CRC-06** | **Human-readable label as authoritative identity** | A name, title or display code is used where a stable id belongs; or an identity model lives in application convention (check-then-insert) instead of in a UNIQUE index. | RC-6, RC-10, RC-B |
| **CRC-07** | **Default-open privilege, and controls applied by sweep** | Postgres and Supabase defaults grant broadly; migrations revoke `PUBLIC` only. Worse: a control applied by a **sweep** rather than at the point of definition is silently dropped by the next `CREATE OR REPLACE` — this has now happened to `search_path` (twice) **and to an authorization wrapper**. | RC-1, RC-3 |
| **CRC-08** | **Caller-supplied identity trusted** | A subject uuid, a `target_client_id`, a role claim or an empty-string bearer comparison decides whose data is read or written. | RC-4 |
| **CRC-09** | **Cross-user aggregate over per-user RLS** | A count, capacity or roster is computed by a client query against a table whose policy scopes rows to the caller. The query is not denied — it is **narrowed**, and a silently narrowed result is indistinguishable from a real one. | RC-11 |
| **CRC-10** | **Presentation shipped ahead of its write path** | Tabs with no data source, toggles with no consumer, screens with no route, engine functions with no caller, columns with no writer. No error is ever produced, because no call is ever made. | RC-H4 |
| **CRC-11** | **Two systems for one concept** | The newer, server-authoritative implementation was built and the older one was left running beside it. | RC-H5 |
| **CRC-12** | **Naive local time into `timestamptz`** | `DateTime.now().toIso8601String()` renders local time with no zone marker; Postgres reads it as UTC. Day-window reads are skewed in both directions. | RC-8 |
| **CRC-13** | **No mechanical gate** | Nothing automated watches the repository. No CI, no migration ledger, no artifact provenance, no rollback, no observability. **This is why every other root cause survived to be discovered by audit rather than by a red build.** | new (L, N) |
| **CRC-14** | **Fixtures and guards aimed at the wrong layer** | QA fixtures written against readers rather than the writer; 259 tests that execute a copy of the product; four guards written for a specific defect that cannot detect it because the defect moved one layer away. | RC-12 |

### 1.1 Dominance

| Root cause | Canonical findings | Share |
|---|---:|---:|
| CRC-03 Failure as value | 61 | 20% |
| CRC-13 No mechanical gate | 44 | 14% |
| CRC-10 Presentation ahead of write path | 38 | 12% |
| CRC-01 Schema-contract drift | 29 | 9% |
| CRC-07 Default-open / sweep-applied control | 24 | 8% |
| CRC-04 Fabricated success | 19 | 6% |
| CRC-11 Two systems for one concept | 18 | 6% |
| CRC-06 Label as identity | 17 | 5% |
| CRC-05 Degraded safety input | 15 | 5% |
| CRC-08 Caller-supplied identity | 14 | 5% |
| CRC-02 Undeclared payload contract | 13 | 4% |
| CRC-14 Guards at the wrong layer | 11 | 4% |
| CRC-12 Naive timestamps | 4 | 1% |
| CRC-09 Aggregate over per-user RLS | 3 | 1% |

**The single most important structural statement in this document:** CRC-13 is not
merely the largest cluster after the error contract — it is the **enabler of all the
others.** Phase 1 and Phase 2 closed 24 findings correctly and both were then partially
undone by a later migration that nothing was watching (§4). Until Wave 1 lands, every
remediation in this programme has the same half-life.

---

## 2. Canonical statuses

| Status | Meaning | Evidence required to enter it |
|---|---|---|
| `DISCOVERED` | Recorded, not yet triaged into a wave | a source report |
| `DUPLICATE` | Collapsed into a canonical ID | the alias map, §3 |
| `ALREADY_FIXED` | Closed before this reconciliation | see the evidence-state ladder in `QA_CLOSURE_STANDARD.md` |
| `FIX_IN_PROGRESS` | A named owner is mid-change in this tree | a working-tree diff |
| `BLOCKED_DECISION` | Cannot be built without product/business/clinical authority | a decision ID in `MASTER_PRODUCT_DECISIONS.md` |
| `BLOCKED_ENVIRONMENT` | Cannot be built or verified until an environment exists | an environment blocker ID, §8 |
| `READY_TO_REMEDIATE` | No blocker; assigned to a wave | a wave ID |
| `REMEDIATED` | Code/migration changed; not yet retested | FIXED IN CODE |
| `RETEST_REQUIRED` | Applied to QA; live assertion outstanding | FIXED ON QA |
| `VERIFIED_CLOSED` | Every required evidence state present | VERIFIED LIVE **and** VERIFIED IN CI |
| `DEFERRED` | Deliberately out of scope for this programme, with an owner and a date |
| `RELEASE_BLOCKER` | Not a code defect here; blocks a named release gate |

**As written at Wave 0, nothing in this registry was `VERIFIED_CLOSED`** — fifty-two
findings were `ALREADY_FIXED`, a weaker state, because the live suites that proved them
had not been re-run since the tree moved, and two of them were subsequently regressed.
**Update 2026-08-26 (§7.8):** Wave 1 put the suites in CI, and the green run at commit
`6d42b10` (271/271 live security across six suites) supplied the missing VERIFIED LIVE +
VERIFIED IN CI states. **23 rows are now `VERIFIED_CLOSED`** — exactly those whose class
evidence is fully present; every exclusion and its missing evidence is recorded in §7.8.

---

## 3. Deduplication map

118 aliases collapse into 61 canonical findings. **The alias must not be used as a
tracking key after this document.** Full list:

| Canonical | Aliases retired | Note |
|---|---|---|
| **I-CHK-01** | CON-01, EC-10 *(checkins half)*, E-CHK-01, M-02, H-21 *(evidence)* | `public.checkins` does not exist. Five workstreams, one defect |
| **I-LEG-03** | EC-10 *(coach_tips half)*, M-08 | `public.coach_tips` has never existed |
| **LRE-02** | REL-18, K-ENV-1, OBS-4-R4, N-05 | Three production-targeting harnesses. Found five times independently |
| **LRE-05** | REL-20, N-01 | No CI |
| **LRE-01** | REL-07 | `APP_ENV` defaults to production |
| **LRE-03** | HYG-01 *(partly — HYG-01 also covers untracked tests, now folded here)* | 20 untracked migrations |
| **LRE-04** | HYG-02, LRE-09 *(the 076 instance)* | 15 in-place-edited migrations |
| **LRE-34** | HYG-03, REL-34 | `supabase/.temp` tracked despite being ignored |
| **LRE-08** | REL-22 *(rollback half)*, LRE-10, LRE-11 | No rollback path; production history unreconciled |
| **LRE-06** | REL-23, M-B-2, D §7 D-1 *(infrastructure half)* | NestJS API has no deployment target |
| **LRE-07** | REL-33 | Android release signed with the debug keystore |
| **REL-04** | M-06, K-16, I-USR-01(b), I Q-8 | No account deletion, and the app states one exists |
| **REL-05** | D-K1, G D-1 | iOS purchase architecture |
| **K-01** | E-08, I-PAY-01, REL-24 *(idempotency half)*, N register #3 | Webhook re-grants session credits on redelivery |
| **I-WRK-01** | H-01, M-07, M R-2 | `workout_set_logs.created_at` does not exist |
| **I-COM-01** | H-02, M-04, M R-4 | Event registration writes `ticket_code`, then fabricates one |
| **I-COM-03** | H-03, M-09, M R-11 | `custom_exercises.approved_by` does not exist; approval always fails |
| **I-NUT-01** | E-13, E-NUT-04, F-J-03 | `ai-coaching-engine` reads `protein_g`/`carbs_g`/`fat_g` |
| **I-INT-01** | F-J-02 *(coaching-engine half)* | `user_profiles.goal` does not exist |
| **I-INT-02** | F-J-02 *(generator half)*, EC-02 *(input half)* | `ai-generate-workout` loses injuries in a query that fails on `goal`/`equipment` |
| **F-J-04** | E-12 | `recent()` orders five tables by a column they do not have |
| **F-J-12** | ENG-09, E-04 | `decision_traces` readable by every coach |
| **F-J-18/19** | E-11, E-CHK-07 | `ai-coach` ignores `target_client_id`; coach analyses describe the coach |
| **ENG-15** | F-J-15, M-01, ENV-01, D P-1, M B-1 | Zero Edge Functions deployed to QA |
| **ENG-17** | F-J-06, ENV-03, D P-6, J B-3 | Intelligence substrate unpopulated in QA |
| **ENG-16** | ENV-02, D P-5 | QA Vault `project_url` / `service_role_key` unset |
| **I-MIG-01** | A §8 *(ledger residual)* | 113–122 applied to QA, absent from `schema_migrations` |
| **CON-04** | Q-4, ENG-12, C A-5, J D-4, G §10 inherited, F-J-05 *(PAR-Q half)* | A high-risk PAR-Q constrains nothing |
| **E-NUT-05** | CON-08, F-J-26, F-J-05 *(allergy half)*, E Q-E5, J D-6 | Allergies never reach the meal-plan prompt |
| **CON-03** | Q-6, M §13 | `dietary_restrictions` — two serializers, one column, prod type unknown |
| **EC-03** | CON-02 | Onboarding marks itself complete after a failed save |
| **CON-06** | I-TYP-03, F-15 | ~52 naive-local timestamps |
| **E-NUT-01** | CON-09 | Barcode per-100 g logged as one serving |
| **CON-10** | F-08, F-09, F-13 *(as the parent record; F retains the three as children)* | Women's-health cycle computation |
| **E-09** | K-12, LRE-12, D P-3, REL-24 *(config half)* | No `[functions]` block; `verify_jwt` undeclared |
| **E-07** | K-21 | Caller-controlled redirect URLs, no allowlist |
| **K-28** | REL-35 | `Access-Control-Allow-Origin: '*'` on money-moving endpoints |
| **EC-01** | REL-26, LRE-27, LRE-28, EC-23 | No error-reporting sink or observability in any tier |
| **M-05** | REL-39, G D-6 | Integrations screen fakes a successful OAuth connection |
| **REL-08** | M-11, LRE-26 *(mobile half)* | No deep-link return path; reset and OAuth dead on iOS |
| **REL-06** | LRE-26 *(routes half)*, M-13 *(partly)* | `/qa-center` and `/mie-debugger` ship in release builds |
| **D §7 D-1** | E-NUT-06 *(backend half)*, REL-29 *(adjacent)* | Two parallel AI nutrition backends |
| **K-09** | H-12 *(capacity half)* | Coach plan capacity granted, never revoked, self-writable |
| **K-07** | M R-7 | A failed Stripe cancel still revokes local access, UI says "Switched to Free" |
| **EC-09** | M R-8 *(invite half)*, H §7 | Unverified writes reported as success |
| **EC-12** | M R-9 | Habit optimistic writes swallow failure, no rollback |
| **SEC-12** | D-04, R-03, H-12 *(demo half)* | `marketplace_coaches()` does not filter `is_demo` |
| **P-8** | K-ENV-2, K-ENV-3, K-ENV-4, M B-3 | No QA Stripe test-mode credentials, runbook or price ids |
| **P-11** | D §7 D-8 | No Anthropic spend cap in QA |
| **I-NOT-04** | H-19 | A conversation participant can rewrite the other party's message |
| **H-11** | H-15 *(dead-rule residue)* | Two "12 Circle Score" systems, one client-writable |
| *(19 further single-alias collapses)* | SEC-01↔D-01, SEC-02↔D-02, SEC-03↔D-03, SEC-04↔D-1D, SEC-08↔F-02↔Q-2, SEC-10↔D-05↔F-04, SEC-11↔D-06↔R-02, WRK-01/02↔WKA-01/02↔RC-B, WRK-03/04/05↔WKA-03↔RC-A, WRK-06↔ENG-03 *(engine half)*, WRK-07↔EC-G1, CON-05↔E-NUT-17↔SEC-04 *(nutrition arm)*, ENG-11↔C §3 layer 11, EC-10↔I-CHK-01/I-LEG-03, EC-02↔CRC-05 parent, N-07↔EC-05, H-20↔E-CHK-06, I-USR-01(a)↔I-WRK-03↔Q-7, LRE-42↔LRE-02 | recorded, individually unremarkable |

### 3.1 Findings the reports **contradict each other** on — resolved here

| Item | Disagreement | Resolution |
|---|---|---|
| `/checkins` route | Master reconciliation called it "a working check-in screen, orphaned". Workstream E found it is an **appointments calendar** that queries `coaching_calls`, reached from two entry points | **E is correct.** The master reading was wrong. The genuinely orphaned code is the *service layer* — `submitWeeklyCheckin` and ten sibling symbols have zero callers. Recorded as **E-CHK-05** + **E-CHK-02**, and the master's phrasing is retired |
| `ai_adjust_nutrition` "incorrect schema reference" | Reported three times, **not reproduced** three times | **NOT REPRODUCED — closed as a false positive.** `weekly_checkins.weight_kg` and `created_at` both exist. The real defect of that shape is `I-NUT-01` (`ai-coaching-engine`), and a *second* one is `I-NUT-02` (`user_profiles.goal` inside the same function). Do not re-open the original phrasing |
| `weekly_checkins` RLS | Phase 1 marked D-03 closed; E flagged that the closure was inferred, not probed | **E is right to flag it.** 114+118 are source-correct and `d03` asserts 27/27 — but that suite has not run since. Status stays `ALREADY_FIXED`, **not** `VERIFIED_CLOSED`, pending Wave 1's CI |
| `dietary_restrictions` column type | Code comment asserts `text[]`; QA probe says `text` | QA is `text`. **Production is unverified and must be confirmed before rollout** (Q-6). The forward migration must converge from either starting type |
| K-04 reproduction payload | K published a repro including `ticket_code` | **H is correct:** `ticket_code` does not exist, so K's payload fails rather than succeeds. Drop that field from the repro. The vulnerability is real; the published proof was wrong |
| Test baseline | 514 / 591 / 623 / 667 / 690 / 699 quoted across reports | All are snapshots of a concurrently-edited tree. **730 passed / 9 skipped / 0 failed** is the Wave 0 baseline, measured this session |

---

## 4. Already fixed, regressed, and not reproduced

### 4.1 `ALREADY_FIXED` — 52 findings. Do not re-open.

> **2026-08-26:** 13 of these rows (SEC-01, SEC-02, SEC-03, SEC-05, SEC-06, SEC-07,
> SEC-10, F-01, F-03, F-05, F-06, F-07, F-08) are promoted to `VERIFIED_CLOSED` on the
> live CI evidence at `6d42b10` — see **§7.8** for the promotion record, the rows that
> deliberately stay, and each row's remaining evidence gap. The tables below are the
> historical Wave 0 record and are not rewritten.
>
> **2026-08-25:** two further rows — **SEC-11** and **OBS-4** — are promoted on the live
> SQL evidence at `2a8d0b6`. **SEC-09 is not promoted**: FG-1 returned 5 PASS / 0 FAIL
> live, but the owner ruling of 2026-08-25 reads §7.8's "needs FG-1 + I-MIG-03" as
> requiring I-MIG-03 itself to reach `VERIFIED_CLOSED`, which it has not. SEC-09 stays
> `ALREADY_FIXED`. See **§7.9**, which records the ruling and why the remaining Phase 2
> rows deliberately stay.

**Phase 1 (security), closed by migrations 113–118 — evidence: 270/270 live assertions**

| Finding | What closed it |
|---|---|
| SEC-01 / D-01 · `coach_client_relationships` had no RLS | 113 — RLS + asymmetric activation model + `enforce_relationship_integrity` |
| SEC-02 / D-02 · role self-escalation | 115 — `enforce_profile_privilege` trigger pins 7 privilege columns; role vocabulary CHECK; `admin_set_user_role()` |
| SEC-03 / D-03 · `weekly_checkins` had no RLS | 114 — RLS + `enforce_checkin_authorship` split |
| SEC-04 / D-1D · 11 subject-scoped RPCs trusting a caller uuid | 116 — `can_act_for` / `can_act_on_program`; 13 engine functions renamed `*_engine` behind authorized wrappers |
| SEC-05 · `anon` could execute 98 of 100 functions | 116 — schema-wide `REVOKE` + a 50-name allowlist |
| SEC-06 / SEC-07 · AI and MIE substrate tables had no RLS | 117 |
| SEC-09 · 73 definer functions with a mutable `search_path` | 116 + 118 → 0 |
| SEC-10 / D-05 / F-04 · `coach_availability` `USING (true)` to PUBLIC | 118 |
| SEC-11 / D-06 / R-02 · client could rewrite a completed session | 120 — `workout_set_logs_protect_history`, `workout_sessions_terminal_status` |
| Q-4 client-computed PAR-Q risk | 115 — `derive_parq_risk` + `apply_parq_risk` made the classification server-authoritative ⚠ *see §4.2* |
| F-01 · `coach_client_workout_stats` unscoped view | 118 |
| F-03 · `notifications` INSERT `WITH CHECK (true)` | 118 + `may_notify()` |
| F-05, F-06, F-07, F-08 · blanket policies, no-`TO` policies, anon grants, invoker search_path | 118 |
| SEC-08 / F-02 / Q-2 · `public.workouts` had no RLS | 118 — made a read-only catalog rather than dropped, so retirement stays an open data-model decision |

**Phase 2 (workout contract), closed by 119–121 — evidence: 20/20 live assertions + 129 behavioural tests**

| Finding | What closed it |
|---|---|
| WRK-01 / WKA-01 · two live set-identity keys | 120 retires 051's ordinal unique index; `(session_id, set_id)` is the only key |
| WRK-02 / WKA-02 · swap inherits set identities → 23505 | `WorkoutExercise.replacedBy` mints fresh identities; uniqueness moved to workout scope |
| WRK-03/04/05 / WKA-03 · untyped `program_workouts.exercises`; String reps; 0 kg; lost rest | 119 — canonical prescription contract, canonicalizing trigger, `CHECK`, `weight_kg` nullable with `null ≠ 0` |
| WRK-06 · engine materialized no prescription | 119 — `materialize_program_week` emits `weight_kg: null` and **raises** rather than writing an empty workout |
| WRK-07 · workout providers returned `[]` on error | Phase 2 — `workout_provider.dart` now contains no `catch`; pinned by `EC-G1` ⚠ *the swallow moved down a layer — EC-11* |
| WKA-04 · "End Workout" left an orphaned `in_progress` row | Phase 2 — honest two-choice exit; ended sessions are `abandoned` ⚠ *resurrected through the error path — EC-05* |
| OBS-4 · duplicate generated day titles | 121 — `plan_day_titles()` restored as one authority, applied after 077's bias; backfill scoped to `coach_id IS NULL` |
| Session determinism, warm-up ack, set identity column, cursor, restoration seating, client-side completed-set immutability | 103, 105, 106, 107, 108 + `workout_restoration.dart` |
| OBS-4-R1/R2/R3 · 121/119/120 dropped pinned `search_path` on 14 functions; 4 trigger functions born `EXECUTE TO PUBLIC` | 122 |

**Other closures**

| Finding | Status |
|---|---|
| Community/messaging display-name reads | Closed — `public_profiles`, `conversation_participant_profiles` ⚠ *five client surfaces were never repointed — H-06* |
| Cross-project cron URLs (prod URL in 076/080) | Closed **in the working tree only** — Vault-resolved, fail-closed. ⚠ *uncommitted; see LRE-03/LRE-04* |
| Coach rating written by the client | Closed by design — a no-op behind 045's trigger and 115's PINNED class. Not a finding |
| "514 vs working-tree test count" | Not a defect |
| Memory note "RLS coach policies unfixed" | **Outdated** — superseded by 113–118 on QA. Production remains unpatched (REL-21) |

### 4.2 ⚠ `REGRESSION` — closed work that a later change undid. **Five findings. This is the most important section of this document.**

Every one of these was introduced by a *correct* later change that nobody was watching.
They are the direct, measurable cost of CRC-13.

| ID | What regressed | Introduced by | Mechanism | Sev |
|---|---|---|---|---|
| **F-J-01** | SEC-04's authorization guard on `materialize_program_week` | migration **119** | 116 renamed the engine body to `*_engine` and published a `can_act_on_program` wrapper under the public name. `119:403` re-created the public name as a **bare `SECURITY DEFINER` body** and `119:483` re-granted `EXECUTE` to `authenticated`. `122` repinned `search_path` with `ALTER FUNCTION` and never touched the body. **116's own header warned about exactly this escape.** Live: an unrelated authenticated client reaches the engine against another coach's program; with a real week number it `DELETE`s and rewrites that week's `program_workouts` | **P0** |
| **F-J-17** | Phase 1's PAR-Q server-authority fix (Q-4 / SEC-023) | migration **115** itself | `derive_parq_risk` appends three flags as **untyped literals** to a `text[]`. Postgres resolves `anyarray \|\| anyarray` and fails with `22P02 malformed array literal`. `apply_parq_risk` is a `BEFORE INSERT OR UPDATE` trigger, so the throw rejects the whole profile write. **A member cannot declare an injury, a pregnancy or a postpartum state.** The fix that made risk server-authoritative made risk unrecordable | **P0** |
| **F-J-07** | `build_workout`'s under-recovery rule | migration **089** (pre-existing, surfaced by J) | Identical shape. `recovery = 60` returns 200; `recovery = 59` returns `22P02`. **The single rule that protects an under-recovered member is the only rule in the function that cannot run** | **P0** |
| **EC-05 / N-07** | WKA-04 (orphaned `in_progress` session), closed by Phase 2 through the happy path | pre-existing error path, unchanged by Phase 2 | `active_workout_screen.dart:611-619` wraps `completeSession` in `catch (_) {}` and shows the celebration regardless; `:608` awaits `logWorkout`, whose whole body is `catch (_) {}`. The session stays `in_progress`, the Resume banner keeps offering a finished workout, and `workout_sessions_one_active_per_user` then constrains the next one. `EC-G1` passes because it does not read this file | **P1** |
| **EC-11** | WRK-07 (provider-layer swallow), closed by Phase 2 | pre-existing service layer | The swallow **moved down a layer rather than away**. `WorkoutService` holds 13 swallow sites; nine providers Phase 2 did not name are thin wrappers over them and are therefore error-blind by construction. `getCompletionRate() → 0` is a **fabricated** adherence figure shown to a coach | **P1** |

**The class fix, and it is mandatory:** a standing test asserting that no function
carrying an authorization wrapper, a `search_path` pin or a security trigger may be
redefined by a later migration without carrying them forward. `SEC-027` already does
exactly this for one function (`generate_client_plan` / `plan_day_titles`) and is the
strongest guard in the tree. Generalise it. **Tracked as `I-MIG-03` and scheduled in
Wave 2; it is the only reason to believe the next Phase-1-equivalent will hold.**

### 4.3 `NOT_REPRODUCED` — closed as false positives

| Claim | Verdict |
|---|---|
| `ai_adjust_nutrition` references an incorrect schema | **Not reproduced, three times independently.** Both columns exist. The real instances are I-NUT-01 and I-NUT-02 |
| `resumePosition` is corrupt | **Not a defect in itself.** Its inputs were — a stale cursor after a swap now misses cleanly (RC-B, closed) |
| A working `/checkins` screen exists but is orphaned | **Materially wrong** — see §3.1 |
| Migration 076's `created_at` schema defect | **Already corrected in the working tree** (`B2-6`). ⚠ *the correction is an in-place edit and does not self-apply — LRE-04* |
| Cross-tenant read/write in nutrition or check-in | **Not reproduced anywhere.** The one reachable subject-uuid surface (`ai-coach`'s `target_client_id`) fails **closed** |

---

## 5. Reconciliation summary — required table

Canonical findings only. Aliases excluded. `Fixed` counts §4.1 entries attributed to that
domain; the five §4.2 regressions are counted as **open**, in their domain, at their
current severity.

| Domain | Findings | P0 | P1 | P2 | P3 | Fixed | Blocked | Ready | Release blocker |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Security & Authorization | 34 | 3 | 5 | 8 | 4 | 14 | 2 | 15 | 3 |
| Workout & Session | 21 | 0 | 4 | 5 | 3 | 9 | 1 | 11 | 0 |
| Error Contract | 26 | 4 | 10 | 8 | 4 | 0 | 1 | 25 | 4 |
| AI / Intelligence Engine | 44 | 6 | 17 | 15 | 6 | 0 | 9 | 29 | 5 |
| Edge Functions | 20 | 2 | 3 | 10 | 5 | 0 | 5 | 15 | 2 |
| Nutrition | 19 | 1 | 6 | 9 | 3 | 0 | 5 | 14 | 1 |
| Check-In | 12 | 2 | 3 | 4 | 3 | 0 | 6 | 6 | 2 |
| Women's Health | 25 | 0 | 6 | 12 | 7 | 1 | 5 | 20 | 0 |
| Billing & Entitlements | 35 | 4 | 14 | 12 | 5 | 0 | 10 | 25 | 5 |
| Release & Environment | 46 | 12 | 18 | 11 | 5 | 0 | 6 | 40 | 24 |
| UI Reachability | 13 | 2 | 4 | 5 | 2 | 0 | 5 | 8 | 2 |
| Product Integrity | 21 | 0 | 5 | 6 | 10 | 3 | 5 | 16 | 3 |
| Data Contract | 33 | 5 | 12 | 12 | 4 | 0 | 8 | 25 | 2 |
| Testing | 11 | 1 | 4 | 4 | 2 | 0 | 3 | 8 | 3 |
| **Total** | **310** | **42** | **111** | **121** | **63** | **52** | **71** | **257** | **56** |

*Reading notes.* `Fixed` (52) and `Ready`/`Blocked` overlap by design: a fixed finding is
neither ready nor blocked, so `Ready + Blocked + Fixed` ≈ 380 > 310 because 70 findings
are counted in both `Blocked` and `Ready` — they are ready in part and blocked in part
(typically a mechanical half plus a decision-gated half). Every such split is stated in
the finding's own row. `Release blocker` is a **gate attachment**, not a severity: a P3
that blocks App Review is still a release blocker.

**Severity is assigned by impact, not by gate.** Where this registry departs from a
source report's rating, the deviation is recorded in the row. The two systematic
departures are: (a) Workstream G's iOS **build** blockers are rated P1 here, not P0 —
they block Gate 3 and nothing else, and rating them P0 alongside "AI prescribes without
knowing the injuries" destroys the meaning of the scale; (b) three findings rated P1 by
their owning workstream are raised to **P0** because a later workstream proved a safety
consequence (F-J-17, F-J-07, I-INT-02).

---

## 6. P0 register — full field set

Forty-two findings. Each is stated with the complete field set required by the
programme brief. **These are the findings that gate the plan.**

---

### SEC-R1 · `materialize_program_week` lost its authorization guard
`F-J-01` · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-27 *(migration 124 restored the wrapper; `d04` §8 asserts the 116 class read from migration source with `KNOWN_OPEN` empty — `materialize_program_week` probed, not exempted; `j04`-04C 403s an unrelated caller against a **real** foreign-owned program; FG-1 SP-4/SP-5 prove the redefinition preserved the `search_path` pin and the grant posture. CI run #27 at `388b5c1` — see §7.10. **Owner ruling 2026-08-27: §5.1 does not apply to F-J-01; it is governed as an authorization/security finding under SEC-R1.**)* · Wave 2

| Field | Value |
|---|---|
| **Source** | J (live) · re-verified **SRC-V** this session |
| **Root cause** | CRC-07 — a control applied by a sweep, dropped by the next definition |
| **Layer** | database / RPC |
| **Affected** | `supabase/migrations/119_workout_prescription_contract.sql:403,483`; `116_rpc_execution_security.sql:326,375`; `122_repin_function_search_path.sql` |
| **Security impact** | Any authenticated account reaches a `SECURITY DEFINER` engine body against **any** coach's program. With a real week number the call `DELETE`s and rewrites that week's `program_workouts`. All four sibling functions correctly return 403 — this one alone is open |
| **User impact** | A coach's programming for a real client can be destroyed and rewritten by an unrelated account |
| **Business impact** | Re-opens a P0 that Phase 1 closed and certified. Undermines the evidence value of the Phase 1 sign-off |
| **Dependencies** | None to fix. Blocks nothing, but must land before any Wave 5 engine work re-exercises this path |
| **Decision** | none |
| **Remediation** | Forward migration: restore the `can_act_on_program` wrapper over `materialize_program_week_engine`, `SET search_path = public, pg_temp`, re-`REVOKE` from the engine name. **Do not** edit 119 |
| **Parallel** | **YES** — one new migration, disjoint from every other file |
| **Owner** | database / security |
| **Tests** | Extend `supabase/tests/security/d04-rpc-execution.mjs` to assert **all five** 116 wrappers as a class, not individually. Add `I-MIG-03`'s standing source guard (§4.2) so a future `CREATE OR REPLACE` cannot repeat this |
| **Live QA** | An unrelated authenticated client → 403 on a program they do not own; the owning coach → 200; `service_role` → 200 |
| **Gate** | Gate 2 |
| **Evidence** | BEFORE: J's live probe, unrelated client reaches the body while 4 siblings 403. Re-derived from source this session |
| **Evidence AFTER** | 2026-08-27, CI run **#27** (`33032108346`, head `388b5c16`, conclusion `success`). *Live security suite* green — `d04` §8: the class has five members, every member has a probe, `materialize_program_week()` **refuses an unauthorized caller**, and `materialize_program_week_engine()` is unreachable by a client. *Live AI suite* green — `j04`-04C: HTTP 403 / `42501` against a real program owned by another coach. *Live SQL evidence* green — FG-1 SP-4 2/2 re-pinned, SP-5 zero EXECUTE to PUBLIC/anon. *Static guards* green — I-MIG-03 durability guard (records mode). **Retained limitation:** the row's *Live QA* field also names the positive legs (owning coach → 200, `service_role` → 200); no suite asserts them, so an over-refusing wrapper would look identical to a correct one. Registered as evidence gap **FG-3** (§7.10), not silently closed |

---

### SEC-R2 · The PAR-Q classifier throws — a member cannot declare an injury or a pregnancy
`F-J-17` · **P0** · `READY_TO_REMEDIATE` · Wave 2

| Field | Value |
|---|---|
| **Source** | J (live) · re-verified **SRC-V** |
| **Root cause** | CRC-05 + CRC-07 |
| **Layer** | database (trigger) |
| **Affected** | `115_profile_privilege_boundary.sql:142,143,145` (`v_flags := v_flags \|\| '<literal>'`), `:171` (`apply_parq_risk` `BEFORE INSERT OR UPDATE`) |
| **Security impact** | None directly — it fails closed by throwing |
| **User impact** | **`PATCH user_profiles {has_injuries:true, injury_locations:'left knee'}` is rejected with `22P02`.** Onboarding intake writes exactly these columns, so an injured, pregnant or postpartum member cannot complete onboarding at all — and CON-02/EC-03 then marks them onboarded with the data discarded |
| **Business impact** | The three highest-consequence safety declarations the product collects are unrecordable |
| **Dependencies** | **Blocks** every downstream safety finding (CON-04, E-NUT-05, F-J-05) — there is no point wiring a constraint to data that cannot be written. **Must precede Wave 5** |
| **Decision** | none — the cast is a defect fix, not a policy choice |
| **Remediation** | Cast the three literals to `::text` in a forward migration; backfill rows whose flags were silently never written. Grep the whole migration set for the same `array \|\| untyped-literal` shape |
| **Parallel** | **YES** — same migration as SEC-R1/SEC-R3 |
| **Owner** | database |
| **Tests** | A live assertion per flag: pregnancy / postpartum / injury each produce the flag and a `moderate`-or-higher level. Extend `SEC-023` (which pins the Dart and SQL classifiers in step) to assert the classifier **executes** |
| **Live QA** | The three writes succeed and produce the expected `risk_flags` |
| **Gate** | Gate 1 |
| **Evidence** | BEFORE: `22P02 malformed array literal: "active_injuries"`, J live |
| **Evidence AFTER** | 2026-08-27, CI run **#27** at `388b5c1`. FIXED IN CODE (migration 126) · FIXED ON QA (ENV-3 ledger L-1…L-5 green, frontier 127) · VERIFIED LIVE (`fj17-parq-risk-contract.sql` **8 PASS / 0 FAIL** in *Live SQL evidence*) · VERIFIED IN CI (`ai_decision_integrity_test.dart` class invariant; fails against the pre-fix shape). **VERIFIED END-TO-END is absent.** **NOT promoted** — §2.1 requires all five states for an AI/safety-input finding and Step 4 is not authorized. Owner ruling 2026-08-27 settles §5.1's test shape only (FJ17-7 is the negative test); it does not waive the fifth state. See §7.10 |

---

### SEC-R3 · `build_workout` throws whenever recovery is below the deload threshold
`F-J-07` · **P0** · `READY_TO_REMEDIATE` · Wave 2

| Field | Value |
|---|---|
| **Source** | J (live) · re-verified **SRC-V** |
| **Root cause** | CRC-05 |
| **Layer** | deterministic engine |
| **Affected** | `089_mie_decision_intelligence.sql:51` (`rules text[]`), `:55` |
| **User impact** | `recovery = 60` → 200; `recovery = 59` → `22P02`. **The only rule that protects an under-recovered member is the only rule in the function that cannot run** |
| **Business impact** | Product bible §3 — *"Injury signals and low recovery override progression"* — is unenforceable |
| **Dependencies** | Blocks Wave 5 engine verification |
| **Decision** | none |
| **Remediation** | `rules := rules \|\| 'RECOVERY_REDUCTION'::text` in a forward migration |
| **Parallel** | **YES** |
| **Owner** | database |
| **Tests** | `supabase/tests/ai/` assertion at recovery 59, 60, 61 |
| **Live QA** | `build_workout({recovery:59})` returns 200 with `RECOVERY_REDUCTION` in `rules` |
| **Gate** | Gate 2 |
| **Evidence AFTER** | 2026-08-27, CI run **#27** at `388b5c1`. FIXED IN CODE (migration 127 — the whole untyped-`text[]`-append class: `build_workout`, `evaluate_week_engine`, `predict_client_engine`) · FIXED ON QA (ENV-3 ledger green, frontier 127) · VERIFIED LIVE (`fj07-rule-accumulator-contract.sql` **10 PASS / 0 FAIL**; FJ07-1 recovery 59 → no `22P02` and `RECOVERY_REDUCTION` present, FJ07-2/3 recovery 60/61 → threshold not crossed) · VERIFIED IN CI (`j03-engine-boundary.mjs` rule-presence invariant, inverted from characterization at `388b5c1`; `ai_decision_integrity_test.dart` class invariant). **VERIFIED END-TO-END is absent.** **NOT promoted** — §2.1 requires all five states for an AI/safety-input finding and Step 4 is not authorized. Owner ruling 2026-08-27 settles §5.1's test shape only (59/60/61 is the negative/positive pair); it does not waive the fifth state. See §7.10 |

---

### ENV-1 · The entire remediation programme is untracked
`LRE-03` · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-26 *(W1-T1 custody + migration-hygiene guard green in CI at `6d42b10`; zero untracked non-ignored engineering files)* · Wave 1

| Field | Value |
|---|---|
| **Source** | L · re-verified **SRC-V** |
| **Root cause** | CRC-13 |
| **Layer** | repository |
| **Affected** | 20 untracked migrations (`000`, `104`–`122`) — **every Phase 1 security migration and every Phase 2 contract migration**; 22 untracked test files including all six live security suites' Dart guards; `workout_restoration.dart` and `workout_contract.dart`, both **production source the app does not compile without**; and **all 18 A–N reports** |
| **Security impact** | The complete P0 security remediation is one `git clean -fd` from non-existence. It cannot be reviewed, deployed from CI, or applied to production, because it exists nowhere but this working tree |
| **User impact** | none today |
| **Business impact** | Total loss of the programme's output on any tree accident |
| **Dependencies** | **Hard prerequisite for every other task in the programme.** Several Wave 1 tasks edit files that are currently modified-but-uncommitted; without a clean base they cannot be reviewed or reverted independently |
| **Decision** | none |
| **Remediation** | Commit in reviewable slices: (1) migrations 000+104–122, (2) test files, (3) the two `lib/` files, (4) docs. Nothing is deleted; nothing is squashed |
| **Parallel** | **NO — sequential, and it went first, alone** |
| **Closure evidence** | **FIXED IN CODE.** 147 files in five commits — `f8f4490`, `2b3d857`, `99492df`, `11fbc6a`, `8e47f07`. Working tree clean; 0 untracked non-ignored files; suites at baseline (730/9/0, 58+6). Full record: [`WORKING_TREE_CUSTODY_MANIFEST.md`](WORKING_TREE_CUSTODY_MANIFEST.md) and progress board §12. **Not `VERIFIED_CLOSED`** — its guard (Gate 0 row 0.7, `git status --porcelain supabase/migrations` empty in CI) does not exist until ENV-6 lands |
| **Owner** | release engineering |
| **Tests** | `git status --porcelain supabase/migrations` is empty, asserted in CI |
| **Live QA** | n/a |
| **Gate** | Gate 0 |

---

### ENV-2 · 15 already-applied migrations were edited in place
`LRE-04` (= HYG-02, LRE-09) · **P0** · `READY_TO_REMEDIATE` · Wave 1

| Field | Value |
|---|---|
| **Source** | L, master · re-verified **SRC-V** |
| **Root cause** | CRC-13 |
| **Affected** | `001, 002, 003, 009, 076, 080, 083, 084, 086, 087, 090, 091, 096, 097, 102` |
| **Security impact** | 076's cross-environment cron target — the fix that stopped a QA project POSTing to **production** Edge Functions with a service-role bearer — is an in-place edit. Any environment that already ran the old 076 still has the production target |
| **User impact** | Production silently retains every defect these edits fix, including 076's `created_at`→`started_at` bug, which raises on every scheduled run once Vault is configured |
| **Business impact** | Production cannot receive the corrections at all. This is the reason the security rollout is not yet writable |
| **Dependencies** | Requires ENV-1. **Blocks** LRE-08 → the production rollout chain |
| **Decision** | none |
| **Remediation** | Enumerate the semantic delta of each of the 15 and emit **one idempotent forward migration `123`** carrying every one. Keep the in-place edits for from-empty replay; never rely on them for promotion. Master's HYG-02 flagged this for 076 only — it applies to all fifteen |
| **Parallel** | **NO** — one owner must do the delta enumeration; splitting it guarantees a missed delta |
| **Owner** | database |
| **Tests** | A guard asserting no tracked migration is modified relative to its merge-base |
| **Live QA** | Replay 123 twice against QA; no-op the second time |
| **Gate** | Gate 0 → G-04 |

---

### ENV-3 · Migrations 113–122 are applied to QA but absent from the migration ledger
`I-MIG-01` · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-25 *(all eight amended closure criteria met; the live ledger check executed in CI at `2a8d0b6` — see §7.9)* · Wave 1

| Field | Value |
|---|---|
| **Source** | I, A |
| **Root cause** | CRC-13 |
| **Affected** | `supabase_migrations.schema_migrations` on QA stops at **112** |
| **Business impact** | QA cannot be reasoned about from its ledger. `supabase db push` would re-run all ten. **All ten were verified idempotent by I**, so a push today would be a no-op *in effect* — that is a property of how they were written, not of the process |
| **Dependencies** | Requires ENV-1 |
| **Remediation** | Insert the ten version rows into `schema_migrations` on **QA only**, after confirming the linked project is QA. Never touch production's ledger without the §9 rollout plan |
| **Parallel** | **YES**, after ENV-1 |
| **Tests** | A CI check that the ledger's max version equals the highest migration filename |
| **Live QA** | `supabase migration list --linked` shows local and remote in step |
| **Gate** | G-03 → G-09 |

**W1-T3 · QA ledger repair — executed 2026-08-25.** Owner-authorized; performed by the
product owner from the local Supabase CLI, because the orchestration session has no
network egress to the QA project and holds no QA credential (recorded at the time as
BLOCKED rather than worked around, per governance §5).

| | |
|---|---|
| **Target** | `eyqtldjqpgpljlqvpowh` — *12Circle QA*. Independently confirmed before the write from five agreeing local sources (`.temp/project-ref`, `.temp/linked-project.json`, `config.toml` `project_id`, `dart_defines/qa.json`, and `supabase/scripts/qa-db-reset.sh --check-only`), not from a variable name. Production `nxdbooufqzkpslkcogxc` was **not** the target and was not contacted |
| **Operation** | `supabase migration repair --status applied 113 114 115 116 117 118 119 120 121 122 --linked` — a ledger write only. **No migration was executed**, no `db push` was run, and no schema object changed |
| **Observed transition** | `113`–`122`: Local-only → **Local + Remote** · `123`: Local-only → **Local-only** (unchanged). Before/after captured as `/tmp/w1t3-before.txt` and `/tmp/w1t3-after.txt`; the diff contains exactly ten changed rows, versions 113–122, and no other migration-history row changed |
| **Migration 123** | **Deliberately excluded and still unapplied.** It is committed (`24187bf`) and locally validated only. Marking it applied would cause a later `supabase db push` to skip it, so the ENV-2 forward carry would never reach any environment. No claim is made here that 123's objects exist on QA |
| **Evidence state** | FIXED ON QA · VERIFIED LIVE (the row's own *Live QA* line — `migration list --linked` now shows 113–122 in step) |
| **Why not `VERIFIED_CLOSED`** | The closure standard's release/environment class requires **VERIFIED IN CI**, and this row's own *Tests* field names the specific check — "a CI check that the ledger's max version equals the highest migration filename". **That check does not exist.** Until it does, this row stays `REMEDIATED` |
| **Open question, not resolved here** | That prescribed check, as literally worded, would be **red today by design**: the ledger's max version is `122` while the highest migration filename is `123`, precisely because 123 is committed-but-unapplied. Its predicate therefore needs an owner ruling (compare against applied-and-intended, or gate it on the pending application of 123) before it can be implemented. Recorded, not decided |

**Amendment, 2026-08-25 — the Tests field, corrected and expanded.** The original
wording above ("a CI check that the ledger's max version equals the highest
migration filename") is preserved as written and is **superseded**, not deleted.
It is a specification defect: a max cannot see a hole in the middle of the
sequence; it asserts *authored == applied*, which this programme violates by
design (102 is withheld from production, 123 is committed-but-unapplied); and it
is environment-blind, so it cannot hold for QA and production at once during any
staged rollout. Read literally it is red today for a correct reason.

`RELEASE_GATES.md` row **1.2** already states the property properly — *"every
migration **applied to QA** is recorded in `schema_migrations`"* — and row 0.9
owns migration numbering. The corrected contract is those two, made mechanical:

| Term | Source of truth |
|---|---|
| `authored` | the migration files in `supabase/migrations/` |
| `declared` | `supabase/expected_applied.json` — per environment: the applied frontier, plus deliberately `pending` / `excluded` versions, each with a reason and the gate that releases it |
| `observed` | `supabase_migrations.schema_migrations`, the only authority on what is applied |

**Closure of ENV-3 requires all of:**

1. authored migration inventory validation — filenames, no duplicate numbers,
   and a contiguous sequence (gate 0.9, owned by `check-migration-hygiene.sh`);
2. an environment-specific expected-state declaration in which every authored
   migration is classified and every deviation carries a reason and a gate;
3. a live comparison of `declared` against `schema_migrations`, per environment;
4. detection of **missing expected migrations** (`declared − observed`);
5. detection of **unexpected applied migrations** (`observed − declared`) — the
   signal that catches an out-of-band apply;
6. detection of **stale ledger rows** (`observed − authored`) — a row whose file
   no longer exists means history was rewritten or a migration deleted;
7. detection of **skipped migration versions** — a hole in either the authored
   sequence or the applied set below the frontier;
8. **CI execution of the live ledger check**. A check that has never run in CI
   is not a gate (closure standard §4).

**Explicitly: a committed-but-pending migration is never inserted into
`schema_migrations` to satisfy this check.** Migration 123 is declared `pending`
for QA and its ledger row is created only by its actual, separately authorized
application. Writing it early would make a later `supabase db push` skip it, and
the ENV-2 forward carry would silently never reach any environment.

**Status when this amendment was written: `REMEDIATED`.** *(Resolved 2026-08-25 — see
the closure note at the end of this row.)* Items 1, 2 and the
static half of 7 are implemented and run in CI's `static-guards` job
(`check-migration-hygiene.sh` contiguity + `supabase/scripts/check-migration-manifest.mjs`).
Items 3–6, the applied-set half of 7, and item 8 are the **live half**, which is
not implemented: it needs a QA database credential in CI, the same blocker as
FG-1 and FG-2. `VERIFIED_CLOSED` is unavailable until that half executes.

**Closure, 2026-08-25 — evidence: the live QA run at commit `2a8d0b6`.** The QA
database credential was provisioned, the live evidence phase executed, and the
ledger comparison reported **5 PASS / 0 FAIL** against QA `eyqtldjqpgpljlqvpowh`:

| Criterion | Evidence |
|---|---|
| 1 · authored inventory (filenames, duplicates, contiguity) | `check-migration-hygiene.sh`, green in `static-guards` |
| 2 · environment-specific declaration, every migration classified | `supabase/expected_applied.json` + `check-migration-manifest.mjs`, green in `static-guards` |
| 3 · live comparison of declared vs `schema_migrations` | executed in CI at `2a8d0b6` |
| 4 · missing expected migrations | **L-1 = 0** |
| 5 · unexpected applied migrations | **L-2 = 0** |
| 6 · stale ledger rows | **L-3 = 0** |
| 7 · skipped versions | authored half: hygiene contiguity 000–123 · applied half: **L-4 = 0** holes in 000–122 |
| 8 · CI execution of the live check | the run itself |

L-5 read "ledger rows 123 vs declared expected 123" — that is **123 rows**
(versions 000–122 inclusive), not migration 123. The checker separately printed
`INFO authored and PENDING for qa (declared, not applied): 123`.

**Verified QA migration state: 000–122 applied; 123 authored, committed and
declared pending — not applied, and not present as an applied ledger row.**
Migration 123 was **not** applied at this checkpoint, no `db push` was run, and
nothing was written to `schema_migrations`. **Production `nxdbooufqzkpslkcogxc`
was not contacted.**

---

### ENV-4 · `APP_ENV` defaults to production
`LRE-01` (= REL-07) · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-26 *(Wave 1 batch task 2, [`WAVE_1_BATCH_CLOSURE.md`](WAVE_1_BATCH_CLOSURE.md); CI at `6d42b10`: ENV-4 static guard + env-ratchet tests + QA-bundle allowlist scan all green — see §7.8)* · Wave 1

| Field | Value |
|---|---|
| **Source** | L, G · re-verified **SRC-V** (`app_env.dart:151`) |
| **Root cause** | CRC-13 |
| **Security impact** | Any `flutter run`, `flutter build`, `flutter test` or IDE launch without `--dart-define-from-file` connects to **production**, using the anon and Stripe keys baked in at `app_env.dart:117-121`. **This is the highest-probability contamination path in the repository, because it requires no mistake — only an omission** |
| **Aggravation** | `qa_environment_isolation_test.dart` ENV-012 currently *codifies this as intended* ("the default run proves it resolves to production") |
| **Remediation** | Default `APP_ENV` to `dev`; make an absent `APP_ENV` a hard failure in a release build; move the prod URL/key into `dart_defines/prod.json` and delete `_prodSupabaseUrl`/`_prodSupabaseAnonKey`/`_prodStripePublishableKey`. **Invert ENV-012** to prove the default is *not* production |
| **Parallel** | **YES** — touches `app_env.dart`, `dart_defines/*`, and two test files, all disjoint from other Wave 1 tasks |
| **Tests** | `env_config_test.dart`: empty `APP_ENV` throws. Inverted ENV-012 |
| **Gate** | G-01 |

---

### ENV-5 · Three QA harnesses are hardcoded to production and perform destructive writes
`LRE-02` (= REL-18, K-ENV-1, OBS-4-R4, N-05) · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-26 *(Wave 1 batch task 3 — shared `tool/qa_target.dart` allowlist refusal, no defaults; CI at `6d42b10`: harness guard tests + `--untracked` production-ref guard green — see §7.8)* · Wave 1

| Field | Value |
|---|---|
| **Source** | L, G, K, A, N — **found five times independently** · re-verified **SRC-V** |
| **Affected** | `tool/live_integration_test.dart:15`, `tool/qa_self_guided.dart:22`, `tool/qa_entitlements.dart:27` |
| **Security impact** | 20+ `DELETE` calls between them; two delete an `auth.users` row via the admin API when `SERVICE_ROLE_KEY` is set. `qa_self_guided.dart:200` calls `generate_client_plan()`, which **supersedes assignments, deletes the caller's self-generated programs and writes new ones**. Their own headers call the target "the real Supabase **dev** instance" |
| **Business impact** | An operator running a script named `qa_entitlements` — the repository's own "Entitlement & Subscription QA certification harness" — signs up users and writes subscription rows **into production**. Workstream K could not run the one tool built for its mandate |
| **Remediation** | Repoint all three at `QA_URL`/`QA_ANON` with **no default**, and copy `supabase/tests/security/lib.mjs`'s production-ref refusal verbatim into each. Add a repo-wide CI guard failing on any occurrence of the production ref outside `app_env.dart`, the keep-alive workflow, and tests asserting *about* it |
| **Parallel** | **YES** |
| **Tests** | `harness_environment_guard_test.dart` ENV-020…022 already ratchet this — flip them from "records the contamination" to "asserts its absence" |
| **Gate** | G-02 |

---

### ENV-6 · No CI, and the only workflow contacts production
`LRE-05` (= REL-20, N-01) · **P0** · `REMEDIATED` *(2026-08-24, Wave 1 batch task 4 — `ci.yml` + three guard scripts exist in-tree; the workflow has **not yet executed** on any push/PR, so this row cannot advance past REMEDIATED until the branch is pushed; see [`WAVE_1_BATCH_CLOSURE.md`](WAVE_1_BATCH_CLOSURE.md))* · Wave 1

| Field | Value |
|---|---|
| **Source** | L, G, N · re-verified **SRC-V** |
| **Business impact** | 763+ executable tests, 188 live authorization assertions, 32 live workout assertions, and every static guard in the tree protect **only a developer who remembers to run them**. `npm test`, `test:security`, `test:ai`, `test:contract`, `check:web-secrets` all exist and are all manual. The live security suite — the best test asset in the repository, written to fail against the pre-remediation database — **has never run in CI and did not run in any workstream session** |
| **Dependencies** | Requires ENV-1 (there is nothing to gate until the tree is committed) |
| **Remediation** | One `ci.yml`: `flutter analyze`, `flutter test`, `npm run test:api`, `npm run check:web-secrets` on a QA web build, plus the migration-hygiene and production-ref guards. A second, environment-scoped job runs `test:security` / `test:ai` / `test:contract` against QA behind a repository secret |
| **Parallel** | **YES**, after ENV-1 |
| **Gate** | G-05 · **this is the single highest-leverage change in the programme** |

---

### ENV-7 · Zero Edge Functions are deployed to QA
`ENG-15` (= F-J-15, M-01, ENV-01) · **P0** · `BLOCKED_ENVIRONMENT` · Wave 5

All 19 functions return `404 NOT_FOUND` (**LIVE**, three workstreams). Every AI surface,
every payment path, invites and enrichment are dead on QA. `supabase secrets list`
returns `{"secrets":[]}`. **Deliberately not remediated before Wave 5:** deploying now
converts a visibly dead system into an invisibly wrong one, because every input defect
below (CRC-01, CRC-05) currently produces confident output with no error anywhere.
Sequencing per Workstream D §6 and J §11. **Gate:** Gate 2 · **Decision:** D-8 (spend cap), D-2 (nutrition backend).

---

### ENV-8 · The NestJS API has no deployment target in any environment
`LRE-06` (= REL-23, M B-2) · **P0** · `BLOCKED_DECISION` · Wave 1/5

No Dockerfile, compose file, `fly.toml`, `vercel.json`, `render.yaml` or Terraform
anywhere. `API_BASE_URL` is empty in `qa.json`, `prod.json` **and** the prod default
table. The AI Nutrition Coach — the flagship AI surface, and the best-tested layer in
the repository — is non-functional in every buildable environment, and the Anthropic
key's only sanctioned home is a process that runs nowhere. **Blocked on D-2** (platform,
cost, and whether the parallel Firebase/passport auth stack stays). **Gate:** G-06.

---

### ENV-9 · No database rollback path
`LRE-08` (= REL-22) · **P0** · `BLOCKED_DECISION` · Wave 1

Zero down migrations across 123 files; no documented or rehearsed restore; free tier
implies no PITR. The security rollout — the highest-value change pending — is a one-way
door, and migration 102's own header documents that it breaks older clients on the way
in. **Blocked on D-3** (pay for PITR, or accept forward-only). **Gate:** G-08 → G-09.

---

### ENV-10 · Android release builds are signed with the debug keystore
`LRE-07` (= REL-33) · **P0** · `READY_TO_REMEDIATE` · Wave 8

`build.gradle.kts:32` — `signingConfig = signingConfigs.getByName("debug")`, Flutter's
scaffold TODO still above it. If a debug-signed build ever reached a distribution
channel the signing identity is a well-known key that cannot be rotated; the app would
have to be republished under a new package name. **Gate:** G-07.

---

### ENV-11 · Production carries the unpatched P0 security defects
`REL-21` · **P0** · `RELEASE_BLOCKER` · Wave 1 output, Wave 10 execution

SEC-01…SEC-05 are properties of the migration source and are therefore live in
production. 113–122 close them **on QA only**. Compounding: by migration 083's own
header, `083/084/086/087/090/091/097/099` were *never applied in any environment* before
their in-place correction — so production probably has **no content pipeline, no
certification view, no `exercise_intelligence` table and no per-attribute review**. That
is the largest single schema divergence in the product. **No production rollout, and no
production-pointed build, until ENV-1→ENV-2→ENV-9→ENV-3 are closed.** Production was not
contacted; every statement here is **UNVERIFIABLE** and derived from source.

---

### DAT-1 · `public.checkins` does not exist; the entire check-in feature is non-functional
`I-CHK-01` (= CON-01, EC-10, E-CHK-01, M-02) · **P0** · `BLOCKED_DECISION` · Wave 4

| Field | Value |
|---|---|
| **Source** | Master (LIVE), B, E, I, M · re-verified **SRC-V** |
| **Root cause** | CRC-01, masked by CRC-03 |
| **Affected** | `checkin_service.dart` (6 call sites), `coach_dashboard_screen.dart:108`, `qa_suites.dart:807` |
| **Impact** | Not "some check-ins fail" — **no check-in can be created by the application at all.** The coach review queue, compliance scoring, the at-risk roster, the Insights panel, the AI coach's grounding packet, the check-in component of the 12 Circle Score and the nutrition auto-adjustment all consume a structurally empty input. `hasCheckedInThisWeek()` is permanently `false`; `getCheckinStreak()` permanently `0`. The **correct** writer, `WeeklyCheckinService.submitWeeklyCheckin()`, has **zero callers** (E-CHK-02) |
| **Compounding** | `weekly_checkins` carries two mutually exclusive column families (I-CHK-03) — the one writer uses the baseline set, four readers including two AI paths use the 001 set. **Repointing the write path today would still produce NULLs on every reader**, and the AI prompt would receive the literal string `undefined` |
| **Dependencies** | **Blocked on Q-1 and Q-2.** I-CHK-03 (column contract) must land **before** I-CHK-01 (rewire) |
| **Remediation** | Per Q-1's recommendation: retire `CheckinService`, migrate callers to `weekly_checkins`. Then the column family, then the form fields (weight — Q-3), then delete the orphans, then let read failures surface |
| **Parallel** | **NO** — one change, one root cause, strict internal order |
| **Tests** | Writer-keys ⊆ reader-keys guard; unreachable-store raises; coach queue count equals submitted check-ins for that coach's active clients |
| **Gate** | Gate 1 |

---

### DAT-2 · `ai-generate-workout` loses the user's injury data
`I-INT-02` (= F-J-02, EC-02) · **P0** · `REMEDIATED` (column half — 2026-08-30, Wave 3A task 3A-4, `0a4b14d`; **VERIFIED IN CI** at run #53, §7.20. Understated: two of four class states present, see the status note in §7.20) / `BLOCKED_DECISION` (fail-closed half — **Q-5**, untouched) · Wave 3/5

Selects `user_profiles.goal, equipment` — **neither column exists** — so the whole query
400s and the generator loses `has_injuries`, `injury_locations`, `experience_level` and
`training_location` **in the same failed request**. `{ data: null }` is returned without
throwing and `?? 'general'` / `?? {}` turns a hard schema error into a confident default.
**Every AI workout is generated for a "general"-goal, "Bodyweight"-equipped,
"intermediate" gym trainee with no injuries, whoever the member actually is** — while the
system prompt instructs the model to *"AVOID anything contraindicated by their injuries."*
Column fix: one line, no decision. **Fail-closed behaviour is Q-5 / rule S.**
**Tests:** stub the read to error → 502 and **no workout**; stub it to `[]` → a workout
*is* generated (proves rule S did not over-trigger). **Gate:** Gate 1.

---

### DAT-3 · `ai-coaching-engine`'s profile query 400s entirely
`I-INT-01` (= F-J-02) · **P0** · `REMEDIATED` *(2026-08-30 — code half in `8b1fba3`, Wave 3A task 3A-2; allowlist half in `0a4b14d`, task 3A-4; **VERIFIED IN CI** at run #53, §7.20. Understated: two of four class states present)* · Wave 3

Same mechanism, `user_profiles.goal`. One-line fix (`fitness_goal`). Already recorded in
`known-violations.json`; removing the entry is the last step of the fix and the guard
fails if either half is done alone.

**FIXED IN CODE:** `8b1fba3` — `ai-coaching-engine/index.ts:143` now selects `fitness_goal`.
Schema truth read from the migrations: `000_baseline` defines `"fitness_goal" "text"`, no
`ADD COLUMN` since adds `goal`, and 001's `user_profiles` block is a shadow
`CREATE TABLE IF NOT EXISTS` that never executes (001:74's `goal text` belongs to
`workout_programs`). **The allowlist half could not be completed by that commit** — the same
`user_profiles.goal` entry still reproduced at `ai-generate-workout/index.ts:63`, which is
`I-INT-02`'s file. Task **3A-4** (`0a4b14d`) removed that last site, and the entry was then
removed; the guard is checked in both directions, so neither half stands alone.
**VERIFIED IN CI: PRESENT** — run **#53** `33326163269` at `5dfc59f`, §7.20. **NOT
`VERIFIED_CLOSED`** — class **Data contract / schema** also requires FIXED ON QA and
VERIFIED LIVE where a read path exists, and `ENV-7` holds every Edge Function undeployed
until Wave 5.

---

### DAT-4 · Event registration writes a nonexistent column, then fabricates a ticket
`I-COM-01` (= H-02, M-04) · **P0** · `READY_TO_REMEDIATE` · Wave 3

`event_registrations.ticket_code` does not exist (the column is `qr_code`); the write
400s and a **"Demo fallback"** `catch` issues a ticket code for a row that was never
written. The user holds a ticket for an event they are not registered for. **Fix
together with `K-04`** — same table, different layer: K-04 is the missing `WITH CHECK`
that lets a member self-grant a *paid* ticket, this is the column name that makes *free*
registration fabricate one. **Drop `ticket_code` from K-04's published repro payload** —
it makes that request fail rather than succeed.

---

### DAT-5 · The coach check-in notification can never fire
`I-CHK-02` · **P0** · `BLOCKED_DECISION` · Wave 4

`trg_notify_coach_on_checkin` (004) returns early unless `weekly_checkins.coach_id` is
set. **No writer in the tree sets it**, so the trigger has never fired — and the
Dart-side notification was deliberately deleted in reliance on it. Blocked on Q-2.

---

### ERR-1 · There is no error-reporting sink anywhere
`EC-01` (= REL-26, LRE-27/28, **EC-23**) · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-27 *(Workstream B Phase **B0**. Closure class **RELEASE / ENVIRONMENT** by owner ruling 2026-08-27, so §2.1 requires **FIXED IN CODE · VERIFIED IN CI** and nothing more. **FIXED IN CODE:** `580932f` — `lib/core/observability/app_failure.dart` (`AppFailure`, `FailureSink`, `reportFailure`/`reportError`, vendor-free per PD-A24, which stays open and does not gate the interface). **VERIFIED IN CI, post-fix half:** run **#33** `33043897947` — `flutter analyze` and `flutter test` green, so the sink compiles in context and B0's gate holds: a deliberately-failed read reaches the installed sink, the error object keeps its identity, and a throwing sink cannot break its caller. **VERIFIED IN CI, pre-fix half:** run **#34** `33081949579` step 7 — the EC-23 guard demonstrably FAILS against a tree carrying the seven historical `print()` call sites and PASSES against the restored tree, in CI. **EC-23 closes with it as an alias (§3).**)* · Wave 3 · *(the "do this before any other error-contract work" sequencing note is retained below as the historical record of why B0 ran first)*

No Sentry, no Crashlytics, no logging package, no `debugPrint`, no `developer.log` in
`apps/mobile`. Seven `print()` calls, inert in release. **All 234 failure sites are
invisible twice over:** the user cannot tell a failure from an empty state, and neither
can the operator, ever, in any environment, after the fact. Every finding in the error
domain is currently unmeasurable in production, so no fix can be verified as effective
and no regression in one can be detected. **Additive, cannot change behaviour, blocks
nothing, unblocks everything.**

---

### ERR-2 · AI decision inputs degrade silently to empty
`EC-02` · **P0** · `READY_TO_REMEDIATE` · Wave 3 (source) / Wave 5 (verify)

`recent()` in `ai-coaching-engine` is literally `try { … return data ?? []; } catch {
return []; }` and ignores the destructured PostgREST `error` besides; `ai-generate-workout`
destructures six parallel reads as `{ data }` with `error` **never inspected**. A failed
read of `ai_memories` yields `injuries: []`. **Amplifier:** the confidence score is
computed from the lengths of those same silently-emptied arrays, so a failed read is
scored identically to a brand-new user — *the number that exists to tell a client how much
to trust the advice cannot tell the difference.* Governance: a trace recorded over
silently-degraded inputs is not an audit record, which voids the decision-log invariant.
**Contract: rule S.** Source fix is independent of deployment and lands now.

---

### ERR-3 · Onboarding marks itself complete after the save fails
`EC-03` (= CON-02) · **P0** · `READY_TO_REMEDIATE` · Wave 4

`intake_flow_screen.dart:215-228` — on a throw the handler explicitly writes
`{'onboarding_complete': true, 'onboarding_step': 0}` and routes to `/home`. PAR-Q
answers, medical conditions, injuries, allergies, dietary restrictions, goal, experience
**and consent** are discarded while the user is recorded as fully onboarded and can never
return. `_saveProgress` Phase 2 is `catch (_) {}`, dropping the whole step's data on any
one field's type rejection. **This is the parent of CON-04, E-NUT-05, ERR-2 and DAT-2 —
it is the reason `risk_*` is frequently null.** Depends on CON-03 (the serializer
mismatch is what triggers it today) and now also on SEC-R2 (the PAR-Q trigger throw is a
second trigger for the same fail-open).

---

### ERR-4 · Absent risk data renders to the coach as "low risk"
`EC-04` · **P0** · `READY_TO_REMEDIATE` · Wave 3

`client_detail_screen.dart` — `d['risk_level'] as String? ?? 'low'` at four call sites,
over a provider that already returns `null` for the entire profile on any read failure.
**"The read failed" and "the client is low risk" are the same pixel.** Combined with
ERR-3, *a coach is affirmatively told a client is low risk when the client's PAR-Q was
never saved.* The default points in exactly the wrong direction on a safety signal.
Display fix is independent and safe: render "not assessed", visually distinct from an
assessed `low`. **The policy half is CON-04 and stays blocked.**

---

### AI-1 · `materialize_program_week` has no caller anywhere in the app
`ENG-01` · **P0** · `READY_TO_REMEDIATE` · Wave 5

The Dynamic Program Builder plans, versions and saves an engine program; **nothing ever
materializes a week.** Its own success message tells the coach to "materialize week 1
from Coach Copilot / the client program view" — no such affordance exists in either
screen. An engine-generated program reaches the client with **zero `program_workouts`
rows**. CRC-10 at its most consequential.

---

### AI-2 · `weekly_feedback.subject_id` is never written
`ENG-02` · **P0** · `READY_TO_REMEDIATE` · Wave 5

One unwritten column silently disables four systems: `predict_client` always returns
`no_data`; `assemble_weekly_review` always returns `no_feedback`, so no weekly review can
ever be created from in-app feedback; `evaluate_week` reads `coaching_mode` through
`fb.subject_id` → NULL → **`needs_approval` never fires for coach-guided clients**,
silently disabling the approval matrix; and `regenerate_program` stamps
`decision_traces.subject_id` NULL, so a subject can never read the trace of their own
program change. **Fix the writer before generating any fixture data, or the fixtures
encode the defect** (CRC-14).

---

### AI-3 · Equipment vocabulary mismatch — the engine selects nothing even after the substrate is populated
`ENG-25` · **P0** · `READY_TO_REMEDIATE` · Wave 5

`score_exercise` tests `(p_context->'equipment') ? ex.equipment` — exact string
membership. The seeded library stores `equipment` as the first element of
`equipment_required`: `dumbbells`, `cable_machine`, `barbell`. Coach Copilot supplies
`['barbell','dumbbell','cable','machine','bodyweight']`. **Only `barbell` matches.**
Everything else scores `equipment_match = 0` and is rejected under
`EQUIPMENT_CONSTRAINT`. Sibling: **ENG-26**, five of ten warm-up pattern slugs never
match (`hinge` ≠ `hip-hinge`). **These two are why populating the substrate alone will
not make the engine work.**

---

### AI-4 · The intelligence substrate is unpopulated in QA
`ENG-17` (= F-J-06, ENV-03) · **P0** · `BLOCKED_DECISION` · Wave 5

`exercise_intelligence` holds 0 profiles against 621 exercises; the movement graph holds
0 nodes and 0 edges. `build_workout` answers **HTTP 200 with `selected: []`** — no error,
no status, no triggered rule (that is AI-5). Nine decision traces exist on QA and every
one is an empty decision. **This is not evidence of a broken engine.** Separately, the
only automated builder — `rebuild_exercise_intelligence()` — writes neither
`contraindications` nor `joint_stress`, the two columns the injury rule reads, so even a
fully populated substrate would leave `injury_compatibility = 100` for every exercise and
`INJURY_PREVENTION` unable to fire (**F-J-23**). **Blocked on D-1** (which review status
is engine-eligible) — under an `approved`-only rule, populating the substrate yields an
engine that still selects nothing until a human reviews 22+ exercises.

---

### AI-5 · An unplannable request returns HTTP 200 with an empty plan
`F-J-08` (= ENG-08 adjacent) · **P0** · `BLOCKED_DECISION` · Wave 5

`build_workout` cannot distinguish "no exercise fits" from "the substrate is empty" from
"the equipment vocabulary does not match", and reports all three as success. Migration
119 already chose *refuse* for `materialize_program_week`; whether `build_workout` agrees
is **D-2**.

---

### AI-6 · The PAR-Q classification and structured allergies are read by nothing
`F-J-05` (= CON-04 consumption half) · **P0** · `BLOCKED_DECISION` · Wave 5

`risk_level`, `risk_flags` (including `pregnancy`, `postpartum`,
`doctor_advised_no_exercise`) and `food_allergies` are captured, server-classified and
stored — and **no AI prompt reads them.** `score_exercise` has no PAR-Q dimension at all:
passing `risk_level: 'high'` changes no score by a single point. The nutrition coach that
produces meal plans and grocery lists receives **no subject context whatsoever**
(F-J-26). Mechanism is cheap and clear; **policy is D-4 and is clinical.**

---

### EDGE-1 · `notify-coach-email` has no authentication and injects unescaped attacker HTML
`E-01` · **P0** · `READY_TO_REMEDIATE` (as deletion) / `BLOCKED_DECISION` (as fix) · Wave 5

No auth of any kind; the platform default `verify_jwt = true` is satisfied by the
**published anon key**. Any internet caller can enumerate the coach roster size, cause an
email to **every coach**, and control the body — `client_name` and `client_email` are
interpolated **raw** into a 12 Circle–branded HTML template. A branded phishing link
delivered from the platform's own sender to every coach, repeatable at will. **The
function has no caller in the codebase.** Recommended: delete it (D-4 in Workstream D).
Not deployed to QA; **UNVERIFIABLE** whether it is deployed to production.

---

### EDGE-2 · `send-checkin-reminder` has no authentication and no idempotency
`E-02` · **P0** · `BLOCKED_DECISION` · Wave 5

The handler never reads the `Authorization` header, though its own file header states it
is invoked only by `pg_cron` with a service-role bearer. Any anon-key holder triggers, for
every active relationship whose client has not checked in this week, one `notifications`
row and one email. **No idempotency guard at all** — N invocations produce N notifications
and N emails per client. This re-opens at the function layer, with service-role privilege,
the notification-insert hole that 116 and 118 closed at the RPC and table layers.
**Decision D-5:** service-role gate, or move the sweep into SQL and remove the HTTP
surface entirely (recommended — it deletes the attack surface).

---

### BIL-1 · The webhook has no idempotency store; session credits are re-granted on every redelivery
`K-01` (= E-08, I-PAY-01, REL-24) · **P0** · `READY_TO_REMEDIATE` · Wave 6

`checkout.session.completed` for `kind='package'` performs `.insert()` — not `.upsert()`
— with no conflict target and no `stripe_event_id` ledger, and the handler 500s wholesale
if any later statement throws **after this insert has already committed**. Stripe retries
any non-2xx for ~3 days. **Every sibling write in the same handler uses
`upsert(..., {onConflict})`; this one line is the exception.** A single retried event
grants a second block of paid coaching sessions.

---

### BIL-2 · Paid AI features have no server-side entitlement check
`K-03` · **P0** · `READY_TO_REMEDIATE` · Wave 6

`PaywallGate` is client-side presentation. The AI Edge Functions and
`generate_client_plan()` perform no plan check, so a free account can consume paid AI
directly. Combined with **P-11** (no Anthropic spend cap in QA and no rate limit across
12 AI functions) this is an uncapped cost surface as well as an entitlement one.
**Programme invariant §16: the client UI is never the authority for entitlement.**

---

### BIL-3 · A paid event ticket can be self-granted — **and a vendor can harvest attendee PII**
`K-04` · **P0** · ✅ `VERIFIED_CLOSED` **2026-09-29** *(migrations 138 + 139 applied to QA; all
four Security / authorization rungs evidenced — see the evidence block below)* · **V5 P1 (pulled
forward from Wave 6 by OWNER DECISION A, 2026-09-29)** — identity and linkage unchanged; no new
finding ID allocated

**CLOSURE CLASS — OWNER RULING 2026-09-29: Security / authorization / database integrity.**
Recorded explicitly so the reason is not implicit. The vulnerability is the ability to alter the
authoritative registration identity/entitlement fields through the **database write path** and
thereby reach access belonging to another registration; the remediation is a PostgreSQL
integrity/authorization control — frozen registration and event identity, frozen QR/payment
fields, forced `paid = false` on client INSERT, trigger enforcement, policy `WITH CHECK`, and the
corrected function ACL. **The control is verified at the layer where the bypass exists and where
the remediation operates.** §2.1's **Billing / entitlement** "VERIFIED LIVE against Stripe test
mode" rung is therefore **NOT** required here merely because the finding carries the `BIL` prefix
or touches `paid`/`payment_id`. **This ruling does not claim Stripe or payment flows have been
verified generally; it governs the closure classification of `BIL-3`/`K-04` only.**

`event_registrations`' policy has no `WITH CHECK`, so a member sets `paid`/`payment_id`
themselves. **Fix in one change with DAT-4** — same table. Corrected repro: omit
`ticket_code`.

**IMPACT EXTENDED 2026-09-29 — the same missing `WITH CHECK` is an authorization defect, not
only a billing one.** `"vendors check in own event registrations"` is `FOR UPDATE` with no
`WITH CHECK`, so Postgres reuses `USING`, which constrains `event_id → vendor_id` and **never
`user_id`**. Since migration 135, `event_attendee_profiles` is gated solely by
`hosts_event_for()`, which trusts that column — so a self-registered vendor reassigns a
registration to any victim and reads their `first_name`, `last_name`, `email`, `avatar_url`.
Recorded in `V5_PROGRAMME_DEFINITION.md` §25; **that surface did not exist when K-04 was
written**, which is why the registry carried only the billing impact.

**EXECUTED PROOF ON QA, 2026-09-29** (§25.5 required one before remediation scoping; this
replaces the catalog-derived chain). `d11-event-registration-integrity.mjs`, **2/8** —
`user_id` rewritten to the victim (`204`, confirmed by service-role read-back) and the
victim's **email actually disclosed** through the view (`200 rows=1`); `paid` self-granted
(`204`); `qr_code` forged (`204`); registration moved between events (`204`). **No rollback
was performed to obtain this: the defect is live on QA and has never been remediated there.**

**REMEDIATION WRITTEN — `supabase/migrations/138_event_registration_integrity.sql`.**
`trg_registration_integrity` (the migration-113 trigger pattern, because a `WITH CHECK` sees
only the NEW row and cannot express immutability) freezes `user_id`, `event_id`, `qr_code`,
`paid`, `payment_id`; the missing `WITH CHECK` is added. Verified **8/8 on a disposable local
target**, including that the vendor's real check-in still works.

**APPLIED TO QA 2026-09-29 under owner authorization.** Remote ledger shows `138 | 138 | 138`;
the live catalog carries `trg_registration_integrity` (BEFORE INSERT OR UPDATE) and the policy
now reads `USING (…) WITH CHECK (…)`. 135/136/137 verified undisturbed in the same dump.

**VERIFIED LIVE — `d11` on QA after 138: 9/9.** `user_id` rewrite `403`; victim PII `200 rows=0`;
`paid` self-grant `403`; member INSERT `201` with `paid=false`; `qr_code` forge `403`; event move
`403`; **and the vendor's real check-in still `204 affected=1`.** A precondition assertion proves
the PII arm is not vacuous (`rows=0` before any attack). Full regression: **397/397 across 10
suites, zero aborts.** Fixtures cleaned: 0 leftover probe events, attacker role restored.

**ACL REGRESSION FOUND AND REPAIRED — migration 139, applied to QA 2026-09-29.** 138 created
`enforce_registration_integrity()` with no grant statement, leaving the default `EXECUTE` to
`PUBLIC`; the `FG-1/SP-5` ratchet caught it (`0` at `16ba19f`, `1` at `b700c30`). 139 revokes it,
matching the posture migration 113 sets for its own trigger function. QA ledger reads `139 | 139
| 139`; the live dump carries `REVOKE ALL ON FUNCTION … FROM PUBLIC` and no function in the
schema grants `EXECUTE` to `PUBLIC`/`anon`.

**VERIFIED IN CI — obtained.** CI run **36596636664** (`b700c30`) and run **36603451032**
(`c60bb89`) each executed `d11` at **9/9** inside a ten-suite live run, and the tree-sensitive
guard in `billing_entitlement_contract_test.dart` passed in the Flutter job of both. Run
36603451032 also shows **`PASS SP-5 EXECUTE grants to PUBLIC or anon: 0`**, so §5.2's
grants-preservation requirement is now discharged on QA.

**CLOSURE EVIDENCE — all four Security / authorization rungs, per §2.1.**

| Rung | Evidence |
|---|---|
| **FIXED IN CODE** | migrations **138** (trigger + `WITH CHECK`) and **139** (ACL repair), both committed |
| **FIXED ON QA** | ledger `139 \| 139 \| 139`; live dump carries the trigger, the `WITH CHECK` and `REVOKE ALL … FROM PUBLIC` |
| **VERIFIED LIVE** | `d11` on QA **2/8 before 138 → 9/9 after 139**; every verdict an HTTP status **plus** a service-role read-back; an anti-vacuity precondition proves the PII arm is not hollow. **No rollback was needed** — the defect was live on QA and had never been remediated there |
| **VERIFIED IN CI** | `d11` **9/9** in runs **36596636664** and **36603451032**, inside a ten-suite live run; the tree-sensitive guard in `billing_entitlement_contract_test.dart` passed in both Flutter jobs, and §35.3 proved that guard **fails** on a 138-less tree |

**§5.2 grants preservation — satisfied.** 138 left `enforce_registration_integrity()` with the
default `EXECUTE` to `PUBLIC`; `FG-1/SP-5` caught it (`0` at `16ba19f`, `1` at `b700c30`).
**Migration 139 restored the grant posture, and `SP-5` transitioned `1 → 0`**, confirmed
authoritatively by CI run **36603451032** (`PASS SP-5 EXECUTE grants to PUBLIC or anon: 0`), with
`FG-1` moving to `5 PASS · 0 FAIL`. The legitimate vendor check-in still returns
`204 affected=1`, so the control closes the bypass without breaking the feature.

**CI is GREEN — run `36605282711` at `3dc73bd`, all seven jobs `success`.** Step 10 passes,
`SP-5` reads `0`, `K-04` reads `9/9` inside `396/396` across ten suites, and `FG-2a` reads
`RESULT: PASS`.

`FG-2a` had been the sole remaining failure and was never this finding: it was a `SEC-11`/Phase-2
**test-precondition** defect — `phase2-contract.sql` hardcoded a shared real QA account and then
inserted an `in_progress` session for it, which `workout_sessions_one_active_per_user` refuses
once that account has a live session. It is fixed by giving the suite a deterministic demo
fixture that already satisfies the precondition; **no QA row was deleted or mutated and no
assertion was weakened.** `SEC-11`'s own finding (migration 120) is unaffected — the defect was in
its test asset, not in the control.

---

### BIL-4 · Session credits are granted but never consumed or enforced
`K-05` · **P0** · `READY_TO_REMEDIATE` · Wave 6

Nothing decrements a credit and nothing checks the balance before a session is booked.
With **K-25** (the credit table's UPDATE policy lets a coach rewrite the balance *and its
owner*) the paid-coaching ledger has neither an authoritative writer nor an authoritative
reader. Fix as one unit: a `book_coaching_session()` RPC consuming credits under a row
lock, plus the policy narrowing.

---

### UIX-1 · The booking screen is dead for every client
`M-03` · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-28 *(Wave 3A task 3A-8 — see §7.16; VERIFIED IN CI at run #44, §7.17; **VERIFIED END-TO-END at run #49** `33200559221` at `7b944aa`, §7.18. All three PRODUCT INTEGRITY / UI REACHABILITY states present)* · Wave 3

`/appointments` and `/book-call` issue a PostgREST embed (`coach:coach_id(...)`) with no
backing FK, so the query fails for every client. *Recommendation: drop the embed and read
coach profiles from `public_profiles`* — no migration, and it matches the pattern
`coach_relationship_service.dart` already uses.

**Closure class fixed by owner ruling 2026-08-28: PRODUCT INTEGRITY / UI REACHABILITY.**
`QA_CLOSURE_STANDARD.md` §2.1, that class's row verbatim — *"FIXED IN CODE · VERIFIED IN
CI · VERIFIED END-TO-END (a human or a driver reached the surface)"*. **Three states. The
ruling explicitly does not add `FIXED ON QA` or `VERIFIED LIVE` to this class**, and none
is claimed here. **PD-A23 answered 2026-08-28, option (b)** — engineering owner; recorded
in [`decision-log.md`](decision-log.md); option (a) was not implemented and no migration
was created.

**BEFORE (live, Workstream M §M-03, frozen evidence):**
`GET /rest/v1/coach_client_relationships?select=coach_id,status,pending_at,activated_at,coach:coach_id(...)`
→ `PGRST200` *"Searched for a foreign key relationship between 'coach_client_relationships'
and 'coach_id' in the schema 'public', but no matches were found."* The identical query
**without** the embed returned the client's real active relationship. Root cause read from
the migrations, not inferred: `000_baseline_preexisting_tables.sql:237` —
`coach_client_relationships_coach_id_fkey FOREIGN KEY (coach_id) REFERENCES auth.users(id)`.
PostgREST cannot traverse a foreign key whose target is outside `public`.

**FIXED IN CODE:** `booking_screen.dart` only — the embed is dropped, the relationship
query is unchanged apart from the embed, coach display fields are read in a second query
against `public_profiles` (`.inFilter('id', coachIds)`, migration 110 projects every field
this screen renders), and the two are joined in Dart, the pattern
`coach_relationship_service.dart:60–77` already uses. **No migration, no schema, no RLS.**

**Two corrections inside that file, both required for the remediation to function, both
recorded rather than silent.** (i) `user_profiles.specialties` is `text[]` (`001:42`) and
this screen renders it as a comma-separated `String?` it splits itself (`:512`). The embed
never returned, so the `as String?` cast had never executed; it would throw the moment the
read worked. Normalised once at the join. (ii) The `catch` set `_BookingState.noSlots` — a
failed read presented as a confident statement about the coach's availability, which is
**invariant I-1** (*"No user-facing success state … unless authoritative evidence confirms
the underlying operation succeeded"*) and **I-5** (*"An empty value is an answer. It must
never be a symptom"*). A failed load now renders a distinct honest state. Everything else —
state semantics, the pending/active/no-coach branches, the multi-coach picker, booking and
cancellation — is unchanged.

**VERIFIED IN CI: PRESENT** — CI run **#44** `33172886167` at `b1a19ae`, terminal
`success`, 2026-08-28. §2 requires a check that *"**fails against the pre-fix tree** and
passes against the post-fix tree, **in CI**"*. Both legs are now in CI, in one run:

* **Post-fix leg — directly observed.** `static-guards` step 7 *"Schema contract guard
  (relations, columns, embedded resources)"* → `success`. The step is **unconditional**:
  parsed from `ci.yml` at `b1a19ae` its keys are exactly `name` and `run`, with **no `if`**,
  and the job carries no job-level `if`. A skipped step reports `skipped`; this reported
  `success`, so it executed and passed and **cannot have been credential-skipped**.
* **Pre-fix leg — entailed, not directly read.** `negative-control` step 8 *"UIX-1 —
  embed/FK contract guard, pre-fix / post-fix evidence"* → `success`, running
  `apps/mobile/tool/negative_control/uix1_negative_control.sh`. Raw job logs return
  **HTTP 403 "Must have admin rights to Repository"**, so the harness's own output was
  **not read**. Under `set -euo pipefail` with a `die` on every branch, exit 0 is reachable
  only if all of the following held: the tree was clean; `git cat-file -e f109f19:<path>`
  succeeded, so `fetch-depth: 0` worked and the blob was reachable; the baseline run
  passed; the installed file carried `coach:coach_id(` **and** differed from the committed
  one, so the real pre-fix screen was installed; the pre-fix run exited **non-zero**; its
  output contained the literal assertion *"coach_client_relationships.coach_id is embedded
  but no foreign key reaches the public schema"*; **no other `FAIL` line was present**; the
  restore passed `git diff --quiet`, so it was byte-identical; and the post-fix run exited
  0.

**Owner ruling 2026-08-28: the §7.13 entailment standard governs this rung.** §7.13 closed
`ERR-1` on the same shape and recorded the position verbatim — the step's exit status *"is
reachable only if every assertion above held, and the harness source was read at the exact
committed SHA that CI executed"*, which it called **stronger for this harness, not weaker**.
Run #44 matches it on every axis and adds a directly-observed post-fix half that §7.13 did
not have. **The literal-log requirement applied to `I-WRK-01`'s VERIFIED LIVE rung (§7.15)
was NOT carried across, and this ruling does not disturb it.** See §7.17.

*(Provenance correction, 2026-08-28, owner-authorized — §7.16 "Correction". The paragraph
this replaces previously read that the guard *"runs inside `npm run test:contract`, already
wired to the `static-guards` job, so no CI change is needed; the rung opens on the next
run."* **Two things in that sentence were wrong.** At the time, `npm run test:contract` was
invoked at `ci.yml:399` inside the **`live-qa`** job, not `static-guards`, which contained
no contract step; and that invocation was **credential-gated** by
`if: steps.creds.outputs.present == 'true'`, so when `QA_URL`/`QA_ANON`/`QA_SERVICE` were
absent the step **skipped** while the job stayed green. The record described an
unconditional static gate; the guard was a conditional one. That correction stands as
written and is not rewritten by this update — the condition it described was **removed** by
owner ruling B-2 in `b1a19ae`, which moved the step to `static-guards` unconditionally, and
run #44 is the first run in which it was unconditional.)*

**VERIFIED END-TO-END: PRESENT** — CI run **#49** `33200559221` at `7b944aa`, terminal
`success`, all **7** jobs `success`, 2026-08-28. The class's third rung reads *"a human or a
driver reached the surface"*; the driver is `apps/mobile/integration_test/uix1_booking_e2e_test.dart`,
run by the `uix1-e2e` job (`98949037130`), steps 1–7 all `success`.

**The route is the real one and no substitution was made.** The driver pumps the real
`CircleFitnessApp` inside an `UncontrolledProviderScope`, reads the real `routerProvider`,
and navigates `router.go('/appointments')` — so `MaterialApp.router` → the real redirect →
`PaywallGate(required: ClientPlan.coachGuided)` → `BookingScreen` is the path actually
exercised. BookingScreen was **not** mounted directly; no mock, fake, stub, Chrome/web,
Android or iOS substitute was used; the entitlement is the real `client_plan()` reading the
same `coach_client_relationships` row the surface needs, and the fixture is created under
existing RLS with the committed `p1-victim` / `p1-coach` QA identities and **no
service-role credential**.

**What step 6 entails.** `apps/mobile/tool/negative_control/uix1_booking_e2e.sh` runs under
`set -euo pipefail` with a `die` on every branch, and it requires each acceptance marker as
a literal (`:88–120`). Exit 0 is reachable only if **all** of the following were present:
`BOOT ok` · `FIXTURE collision-check clean prior-active=0` · `FIXTURE relationship
active=1` · `FIXTURE availability rows=[1-9]` · `ROUTE navigated=/appointments` ·
**`A1 surface-reached=true`** · **`A1 paywall-locked=false`** · **`A2
coach-rendered=true`** · **`A3 ready-state=true`** · `A3 not-No Coach Selected Yet=true` ·
`A3 not-Couldn't load your bookings=true` · `A3 not-No Slots Available=true` ·
`ASSERT-ALL PASS` — **and** the Flutter run's own exit code `0`, checked separately
(`:120`), so a green exit alone would not have sufficed. `A2` is the coach identity
`Coach P1 coach`, read through `public_profiles` — the exact read the PGRST200 embed
defect made impossible. **Step 7** `success` supplies closure-standard §7 hygiene: the
harness requires the literal `CLEANUP verified availability=0 active-relationships=0`
(`:44`), so removal is proved **by a read**, not assumed from a `204`.

**Owner ruling 2026-08-28: the §7.13 entailment standard extends to this rung for this
row.** Raw job logs still return **HTTP 403 "Must have admin rights to Repository"**, so the
marker lines above were **not literally read by this programme** — they are entailed from
the step's exit status plus the harness source read at the executed SHA. That is the same
standard §7.13 applied to `ERR-1` and §7.17 applied to this row's VERIFIED IN CI rung, and
the owner has now extended it to VERIFIED END-TO-END for `UIX-1`. **Two boundaries are
preserved and are not disturbed by this extension:** §7.15's literal-log requirement for
`I-WRK-01`'s VERIFIED LIVE rung stands unchanged, and this ruling is confined to `UIX-1` —
it does not reach `SEC-R2`/`SEC-R3`, whose outstanding rung is also END-TO-END and whose
status remains exactly as §7.10 left it.

**Two rendering defects were exposed by this rung and repaired before it passed**, both
latent behind the original embed failure, which had made `_BookingState.ready` unreachable
so `_SlotCard` had never rendered at all:

* **The pump loop could not see a rendering exception.** `_pumpUntil` had no exception
  handling, so an exception thrown by `tester.pump()` propagated out before the finder, the
  marker and the `expect`, and run #47's A2 could not be adjudicated. `aaa23c6` wrapped the
  pump in an untyped `catch (error, stack)` that prints the type, the exception and the
  stack under a `UIX1-DIAG` prefix and **`rethrow`s unchanged** — observability only:
  timeout, interval, finder evaluation, return behaviour, A1/A2/A3 and teardown are
  byte-for-byte as before, nothing is swallowed and no assertion was weakened.
* **The slot card's Book button forced an infinite width.** The app's `ElevatedButton`
  theme is the full-width CTA style (`helix_theme_builder.dart:44` —
  `minimumSize: Size(double.infinity, 54)`, reached via `main.dart:115` →
  `TwelveCircleTheme.theme` → `HelixThemeBuilder.dark` `:69`), and an unset property in a
  local `styleFrom` falls through to it. In a bounded column that infinite `minWidth`
  clamps harmlessly to the parent's `maxWidth`; as a **non-flex child of `_SlotCard`'s
  `Row`** it does not, because `RenderFlex` lays inflexible children out with an unbounded
  main axis. The applied constraint was therefore `BoxConstraints(minWidth: Infinity)` and
  layout threw **`BoxConstraints forces an infinite width.`** — with the later
  `child.hasSize` / `RenderSliverMultiBoxAdaptor` assertion its downstream consequence, not
  its cause. `7b944aa` adds one property to the existing `styleFrom`,
  `minimumSize: const Size(0, 54)`, overriding **only** the fatal width component: the
  themed 54px height is preserved, the button hugs its content as the design intends, no
  fixed width was introduced, and the change matches the design system's own
  non-full-width idiom (`helix_theme_builder.dart:76`). **The assertion was not suppressed
  or caught; the invalid constraint no longer exists.**

**Status: `VERIFIED_CLOSED` 2026-08-28** — all three states the **PRODUCT INTEGRITY / UI
REACHABILITY** class demands are present, with no waiver, no exception, no substituted
target and no weakened assertion. **The status-vocabulary gap this row illustrated is
resolved for `UIX-1` by closure, not by ruling** — the gap itself remains open and still
governs `SEC-R2` and `SEC-R3`, and the owner ruling requested at §7.10 is still
outstanding for them. See §7.18.

---

### UIX-2 · No in-app account deletion, and the app states that there is
`REL-04` (= M-06, K-16, I-USR-01(b)) · **P0** · `BLOCKED_DECISION` · Wave 7

App Store Guideline 5.1.1(v) makes in-app deletion mandatory for any app supporting
account creation. Worse than absent: `help_center_screen.dart:45` instructs users to "Go
to Profile → Settings → Account → Delete Account" — **a path that does not exist** — and
the privacy-policy screen makes the same promise. Simultaneously a compliance blocker and
a false in-app statement. Compounded by **I-USR-01(a)**: 53 of 143 foreign keys restrict
deletes, so both program deletion and account deletion are blocked at the schema level
(Q-7). **Until it ships, correct the false help-centre and privacy-policy text** — that
half needs no decision and should land in Wave 1.

**2026-08-24 · Wave 1 batch task 8 — text half `REMEDIATED`, wording `REQUIRES_REVIEW`.**
The false in-app-path claims are removed and pinned by
`account_deletion_claims_test.dart`. The replacement text, however, promises an
**email-based deletion path** (support@/privacy@12circle.app, permanent removal within
30 days) — a user-facing support/policy commitment not traceable to a recorded owner
decision. The wording is held at the custody checkpoint for explicit owner approval or
substitution before commit. The feature half is unchanged: `BLOCKED_DECISION`, Wave 7.

---

### REL-1 · iOS build cannot be produced
`REL-01` + `REL-02` + `REL-03` · **P1** *(rated P0 by G; see §5 on gate-vs-impact)* · `READY_TO_REMEDIATE` · Wave 8

No CocoaPods integration (`flutter_local_notifications` and `record` ship no
`Package.swift`, so SPM alone cannot resolve the graph); `mobile_scanner 6.0.11` needs
iOS 15.5 against a declared target of 13.0, so `pod install` fails outright; no
`DEVELOPMENT_TEAM`, no entitlements, no profile, legacy `"iPhone Developer"` identity.

---

### REL-2 · Digital subscriptions sold through Stripe
`REL-05` (= D-K1) · **P0** · `BLOCKED_DECISION` · Wave 6/8

`self_guided` ($29/mo) and `ai_guided` ($59/mo) are digital services delivered in-app;
Guideline 3.1.1 requires IAP and `checkout_launcher.dart` redirects to hosted Stripe
Checkout. The coach subscription has a plausible 3.1.3(e) argument; the two digital tiers
almost certainly do not. **The single largest architectural item between the product and
iOS distribution.** Option (a) adds a *second* entitlement source of truth on top of a
webhook that is not yet idempotent — which is why K sequences it after BIL-1/BIL-2.
**Decision D-1.**

---

### REL-3 · QA tooling ships in release builds
`REL-06` (= LRE-26) · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-26 *(Wave 1 batch task 7 — compile-time `kQaToolingEnabled = !kReleaseMode` route gate + affordance gating (recorded scope extension); `release_route_gate_test.dart` executed in CI at `6d42b10` — see §7.8)* · Wave 1

`/qa-center` and `/mie-debugger` are wired unconditionally into the shipping router,
gated by neither `kReleaseMode` nor a role check. Only **4 uses of
`kReleaseMode`/`kDebugMode` exist in the entire client**, so the audit should be broad,
not limited to these two routes. *(The broad-audit instruction produced finding
**W1B-N2**, §7.7 — `/admin-exercise-review` and `/vendor-portal` carry no UI role
check.)*

---

### REL-4 · Password reset and OAuth have no return path on iOS
`REL-08` (= M-11) · **P0** · `READY_TO_REMEDIATE` · Wave 8

`redirectTo: kIsWeb ? … : null` at four call sites, no `CFBundleURLTypes`, no associated
domain. Sign in with Apple and Google Sign-In are both in `pubspec.yaml`, so this is the
primary sign-in path, not an edge case.

---

### REL-5 · No report / block / moderation surface for user-generated content
`REL-16` · **P0** · `BLOCKED_DECISION` · Wave 7

The app ships community and 1:1 messaging; an exhaustive search finds no report, block or
mute affordance anywhere in `lib/`. Guideline 1.2 requires a content filter, a report
mechanism, a block mechanism, a published EULA and a documented 24-hour response
commitment — the last of which is an **operational** commitment needing a named owner.
**Decision D-3.**

---

### REL-6 · No hosted privacy, terms or support URLs
`REL-17` · **P0** · `BLOCKED_DECISION` · Wave 7

All three exist only as in-app Flutter screens. Edge Functions default their redirect
targets to `https://12circle.app/...`, implying a domain this programme **cannot confirm
is registered or controlled** (D-4: canonical name and domain). Settings exposes Privacy
Policy and Help Center but not Terms of Service, though the screen exists.

---

### TST-1 · The live security suite has never executed
`N-01` (suite half) · **P0** · ✅ `VERIFIED_CLOSED` 2026-08-26 *(EB-1 resolved; the six suites executed in CI at `6d42b10` — 271/271. The row below is the historical statement)* · Wave 1

188 live authorization assertions across six suites, written to fail against the
pre-remediation database and to pass after — **not run in any workstream session**,
because `QA_SERVICE` is not present in any working copy. Phase 1's evidence is therefore
a point-in-time claim that nothing currently re-verifies, and §4.2 proves the posture has
drifted since. **Blocked on: a scoped QA service key in CI secrets.** This is the single
highest-value environment unblock in the programme.

---

*(P0 register continues — the remaining seven P0 rows are the second-order members of
clusters already stated in full: `E-NUT-05` allergens never reach the prompt (Wave 5,
blocked on D-6); `H-05` the `progress-photos` bucket exists in no migration so all
progress and onboarding photography fails (Wave 3); `I-CHK-03` the two `weekly_checkins`
column families (Wave 4, blocked on Q-2); `F-J-12` any coach reads every member's
decision traces (Wave 2, blocked on D-7); `K-ENV-1` folded into ENV-5; `P-8` no QA Stripe
credentials, runbook or price ids (Wave 6); `I-NOT-04`/`H-19` a conversation participant
can rewrite the other party's message text (Wave 2).)*

---

## 7. P1–P3 register

**Field compression.** Recording the full 20-field card for all 310 findings would produce
a document nobody reads, and the omitted fields are already stated in the owning report.
P1 rows below carry: ID · aliases · root cause · layer · impact · dependencies · decision ·
parallel · wave · gate. P2/P3 rows carry: ID · root cause · statement · wave · decision.
**Every finding's full evidence remains in its source report, which this row names.**

### 7.1 Security & Authorization

| ID | Alias | Sev | RC | Statement | Dep | Dec | ∥ | Wave |
|---|---|---|---|---|---|---|---|---|
| `I-MIG-03` | — | P1 | CRC-07 | `CREATE OR REPLACE` silently drops the `search_path` pin **and any authorization wrapper**. Correct today only because 122 sorts last. **The standing test for this is the class fix for §4.2** | ENV-1 | no | Y | 2 |
| `F-J-12` | ENG-09, E-04 | P1 | CRC-08 | ✅ **`VERIFIED_CLOSED` 2026-08-27** *(CI run **#32** at `ae5be13`)*. `decision_traces` SELECT granted an unscoped `role in (admin,content_manager,coach)` arm. **BEFORE:** a coach with **zero** relationship rows read all 9 traces across 2 unrelated subjects (Workstream J, live). **Remediation:** migration **128** — subject + `created_by` + `is_active_coach_of(subject_id)` + `is_admin()`, nothing else. **AFTER, live at run #32:** `content_manager` **0 rows** *(the same probe returned **90 rows** at run #30 `33038542118`, pre-128 — the required pre-fix failure)* · unrelated coach **0** · unrelated client **0** · subject **95/95** rows are their own · admin reads for audit · active coach and `created_by` arms both proved positively in `d05` §9. **Files:** `128_scope_decision_trace_reads_option_a.sql` (`f38841f`), `j04-provenance-authz.mjs` (`f38841f`, `ae5be13`), `d05-intelligence-substrate.mjs` §9 (`f38841f`), `expected_applied.json` (`fb36f18`). **Four required SECURITY / AUTHORIZATION states all present** — FIXED IN CODE · FIXED ON QA (ENV-3 live ledger 129=129 at run #32) · VERIFIED LIVE · VERIFIED IN CI. *(Premise correction, M-3, 2026-08-27: this row previously read "Every sibling table chose 'active coach or admin'". It does not — 093/095/096 use `admin + content_manager`, 091 and 089 add `coach`, and **no sibling uses `admin` alone**. Sibling policies are separate decisions and were NOT changed.)* **Closure class fixed by owner ruling M-4.** **Retained limitations:** (i) RLS policies are outside the I-MIG-03 durability guard, which tracks function properties only — this closure has **no standing guard** against silent replacement; (ii) J-04A's `created_by=neq` filter is NULL-rejecting, so a readable `created_by IS NULL` trace would be invisible to that negative control (none is readable under option (a) today). See §7.11 and §7.12 | — | ✅ **PD-A05 (a)** *(D-7 answered)* | Y | 2 |
| `I-NOT-04` | H-19 | P1 | CRC-07 | `messages` UPDATE policy has no `WITH CHECK` and no column restriction — a participant rewrites the other party's message text | — | **Q-10** | Y | 2 |
| `H-11` | H-15 | P1 | CRC-11 | Two "12 Circle Score" systems and two disagreeing leaderboards; `daily_scores` carries a `FOR ALL` policy and is **client-writable** | — | **Q-H4** | Y | 2/7 |
| `E-05` | — | P1 | CRC-08 | `generate-communication` returns the coach's private clinical assessment — compliance, risk factors, churn framing — to the **client**, who can call it with their own `communication_id` | ENV-7 | no | Y | 5 |
| `E-03` | — | P1 | CRC-07 | `enrich-exercise` is dead on arrival: it calls `seed_exercise` under the caller's JWT, and 116 revoked it. Every call spends a full Sonnet generation and then fails at the write. **Do not re-allowlist `seed_exercise`** | — | **D-3** | Y | 5 |
| `E-10` | — | P2 | CRC-08 | `ai-coaching-engine`'s service-role detection is fail-open on an unset env var — `authHeader === 'Bearer '` grants arbitrary-subject access. Non-constant-time secret compare | — | no | Y | 5 |
| `F-J-24/28` | — | P2 | CRC-08 | Two further fail-open comparisons in edge-function auth | — | no | Y | 5 |
| `E-NUT-17` | CON-05 | P2 | CRC-07 | `079:65`'s `GRANT EXECUTE … TO authenticated` on `ai_adjust_nutrition` still stands. Any selective re-application of 079 after 116 re-opens SEC-04's nutrition arm. Function is dead and its input column is never written | — | no | Y | 2 |
| `R-01` | — | P2 | CRC-08 | `award_points()` / `penalize_points()` take an arbitrary `p_points`, correctly scoped to `auth.uid()` — a member can award **themselves** any score | H-11 | Q-H4 | N | 7 |
| `SEC-12` | D-04, R-03 | P2 | CRC-10 | `marketplace_coaches()` does not filter `is_demo`; migration 110 states demo accounts are excluded from discovery and the RPC does not honour it. Live: 6 coaches returned, including 5 demo fixtures | — | **Q-H5** | Y | 7 |
| `R-04` | — | P3 | CRC-07 | `foods` accepts INSERT from any member (`WITH CHECK (true)`). Shared database by design; abuse surface is spam | — | moderation | Y | 7 |
| `E-NUT-08` | — | P2 | CRC-07 | Any authenticated user can poison the shared barcode cache | R-04 | no | Y | 5 |
| `R-05` | — | P3 | CRC-07 | `coaches can update client profiles` is broader than any screen needs. No escalation path remains after 115 | — | **Q-H1** | Y | 7 |
| `R-06` | — | P3 | — | Supabase Auth leaked-password protection is **disabled** on QA. One project setting, no code | — | no | Y | 1 |
| `R-07` | — | P3 | — | `pg_net` installed in `public` | — | no | Y | 8 |
| `R-08` | — | P3 | CRC-11 | The intake Dart still computes and submits `risk_*`; the server overrides it silently. Dead weight, pinned in step by `SEC-023` | SEC-R2 | no | Y | 4 |
| `E-15` | — | P3 | CRC-08 | `send-invite-email` is authenticated but not authorized — any signed-in account sends a branded invite to any address with an unvalidated token | — | **D-7(D)** | Y | 5 |
| `E-16` | — | P3 | CRC-08 | `explain-decision` lets the caller pick the audience | F-J-12 | D-7 | Y | 5 |
| `ENG-22` | — | P2 | CRC-08 | `explain-decision` reads under caller RLS but **writes the cache with service role** — with F-J-12, an unrelated coach can mint and permanently pin the client-facing explanation of another coach's client's workout | F-J-12 | D-7 | N | 5 |
| `E-14` | — | P3 | CRC-03 | Seven functions return raw exception text; `ai-coach` returns the **raw Anthropic error body** | — | no | Y | 5 |
| `K-25` | — | P1 | CRC-07 | `client_session_credits` UPDATE policy lets a coach rewrite the balance **and its owner** | K-05 | no | N | 6 |
| `K-26` | — | P1 | CRC-13 | The **production** build default ships a `pk_test_` publishable key. Either real money has never moved, or the constant is wrong | — | **D-1(L)** | Y | 1 |
| `REL-31` | — | P1 | CRC-07 | `avatars`, `coach-media` and `exercise-media` are **public buckets** — every object is world-readable by URL. Confirm no client media or PII is written to `coach-media` | — | privacy | Y | 7 |
| `REL-30` | — | P1 | CRC-08 | API verifies Supabase tokens with a shared HS256 secret; Supabase is migrating to asymmetric JWKS. This path breaks on that migration and cannot be rotated without redeploying | LRE-06 | D-2 | N | 8 |
| `REL-29` | — | P1 | CRC-11 | A second, parallel auth stack ships alongside the Supabase one — `firebase-admin`, `passport-jwt`, `bcryptjs`, `auth.controller`, `users.controller`. Unused authentication is unmaintained attack surface | — | **D-2** | Y | 8 |
| `REL-28` | — | P1 | CRC-07 | API: `enableCors({origin:true})` when `CORS_ORIGINS` is unset; no helmet, no rate limiting on a route that spends Anthropic credits; 12 MB body limit; `ValidationPipe` per-controller not global | LRE-06 | no | Y | 8 |
| `REL-36` | — | **P1** *(raised from P2 by W1-T1)* | CRC-13 | Seed files with published test passwords run on `supabase db reset`; add a guard refusing to seed a non-QA ref. **Raised because W1-T1 committed three bcrypt-hashed QA fixture passwords that were not previously in git history — the seed-target guard is now the only remaining control** | — | no | Y | 1 |
| `K-28` | REL-35 | P3 | CRC-07 | `Access-Control-Allow-Origin: '*'` on all five billing functions | — | no | Y | 6 |
| `E-07` | K-21 | P2 | CRC-08 | Caller-controlled `successUrl`/`cancelUrl`/`returnUrl` handed straight to Stripe — an open redirect with a trusted intermediary, with `{CHECKOUT_SESSION_ID}` appended to the attacker's URL | — | **D-6(D)** | Y | 6 |
| `E-06` | — | P2 | CRC-13 | Production URLs are the hardcoded default in four Edge Functions. A QA invite links a real recipient into **production signup** with a QA token. The SQL layer removed exactly this class deliberately; the function layer never did | — | no | Y | 5 |
| `H-06` | — | P1 | CRC-01 | Migration 102 closed the client→coach profile read; **four client surfaces and the coach's incoming-request list were never repointed.** A paying client is shown a product that behaves as if they have no coach; a coach must accept requests from an anonymous "New Client" | — | **Q-H1** (coach half only) | Y (client half) | 3 |
| `F-18` | — | P1 | CRC-08 | Cycle data leaves the user-isolation boundary through the AI coaching Edge Function — silently, no consent, no opt-out, `tracking_enabled` unhonoured | ENV-7 | **E-4(F)** | Y | 5 |

### 7.2 Error Contract

| ID | Sev | RC | Statement | Dep | Dec | ∥ | Wave |
|---|---|---|---|---|---|---|---|
| `EC-05`/`N-07` | P1 | CRC-03 | **§4.2 regression.** Completion swallows both persistence steps and shows the celebration | — | no | Y | 3B |
| `EC-06` | P1 | CRC-03 | A failed nutrition read returns zeroed totals, which are then **persisted as the day's score** — `_updatePoints` *sets* rather than increments, so one transient read failure permanently overwrites earned points | — | no | Y | 3B |
| `EC-07` | P1 | CRC-04 | A failed check-in read **fabricates a `pending` week**; re-submitting overwrites a *reviewed* check-in, resets `status`, hides the coach's feedback and re-notifies them | — | no | Y | 3B |
| `EC-08` | P1 | CRC-03 (C-2) | `submitCoachFeedback` returns `true` on a zero-row update. **The verification is present — `.select('user_id')` — and the check on it is missing. Two lines** | — | no | Y | 3B |
| `EC-09` | P1 | CRC-03 (C-2) | ~10 unverified writes reported as success, including `approveGlobalExercise`, `rejectGlobalExercise`, `platform_settings`, and **`addMemory('injury', …)` — a dropped safety input that silently never exists** | — | no | Y | 3B |
| `EC-11` | P1 | CRC-03 | **§4.2 regression.** `WorkoutService`'s 13 swallows sit beneath the providers Phase 2 fixed; `getCompletionRate()` fabricates adherence | **`I-WRK-01` + `I-COM-01` + `I-CHK-01`** *(owner ruling D-3, 2026-08-27 — §7.14. Was "H-01 first": under-scoped against Workstream H, and `H-01` is a retired alias, which §3 and §10.5 forbid as a tracking key)* | no | N | 3B |
| `EC-12` | P1 | CRC-03 | Habit writes optimistic, swallow, **no rollback**, then score from unpersisted state — the score and the habit log disagree permanently | — | no | Y | 3B |
| `EC-13` | P1 | CRC-03 | A failed message read renders as an empty conversation; `getUnreadCount() → 0` suppresses the badge that would prompt a second look | — | no | Y | 3B |
| `EC-14` | P1 | CRC-04 | Stripe Connect failures render as a real £0.00 balance and a disconnected account — the highest-trust number in the product, fabricated from a network error | — | no | Y | 3B |
| `EC-15` | P2 | CRC-03 | Silent entitlement downgrade. **The direction is correct — all three fail closed.** The defect is the silence: "denied" and "couldn't verify" are different answers (rule X) | — | no | Y | 3B |
| `EC-16` | P2 | CRC-03 | Plan generation failure ends onboarding silently; the client lands on Home with no program and no retry | EC-03 | no | Y | 4 |
| `EC-17` | P2 | CRC-04 | `detectRisks()` fabricates a risk assessment **and its parser cannot work** — `Uri.splitQueryString()` applied to JSON. Currently unreferenced: latent. Delete or rewrite; do not leave a broken safety-assessment API in the tree | — | **D-2(D)** | Y | 5 |
| `EC-18` | P2 | CRC-03 | A nested fallback retries without the join and discards both causes | — | no | Y | 3B |
| `EC-19` | P2 | CRC-03 | `custom_exercise_service.dart` — **54 swallow sites in 816 lines**, 23% of the repository total in 1.4% of its source. Needs one pass under the contract, not 54 decisions | — | no | N | 3B |
| `EC-20` | P2 | CRC-03 | Notification inserts swallowed throughout. **Sanctioned category** — needs rule **O** recording, not propagation | EC-01 | no | Y | 3A |
| `EC-21` | P2 | CRC-14 | The QA harness itself swallows: a `client_plan` failure becomes `ClientPlan.free`, so an entitlement probe certifies the wrong tier for a paying tester. **A QA tool that swallows produces false PASSes** | — | no | Y | 3B |
| `EC-22` | P2 | CRC-04 | The workout feedback dialog reports "submitted" on failure. `workout_feedback` is read by the AI engine as a recovery signal | — | no | Y | 3B |
| `EC-24` `EC-25` `EC-26` | P3 | CRC-03 | Sanctioned best-effort persistence (keep, add rule O); low-stakes provider `[]`s (fold into the L2 sweep); `_resnapshotSession` — **named as a model of an honest boolean, not a defect** | EC-01 | no | Y | 3B |
| `M-10` | P1 | CRC-04 | Success states that do not reflect persistence — "Invite sent!", "Switched to the Free plan." | EC-09, K-07 | no | Y | 3B |
| `M-12` | P2 | CRC-10 | Dead buttons with no-op handlers (class JOIN, QR) | — | **Q-M12** | Y | 7 |

### 7.3 AI / Intelligence Engine

| ID | Sev | RC | Statement | Dec | Wave |
|---|---|---|---|---|---|
| `ENG-03` | P1 | CRC-02 | **Coach Copilot invents a prescription in the UI** — `sets:3, reps:10, rest_seconds:90` for every exercise. 119 went to real lengths to stop the *engine* fabricating a prescription; the *presentation layer* fabricates one instead, and the canonicalizing trigger stamps it canonical | D-3 | 5 |
| `ENG-04` | P1 | CRC-11 | **Copilot approval destroys the client's program assignment** — `_approve()` calls `assignProgram`, which sets every existing `active` assignment to `replaced` | no | 5 |
| `ENG-05` | P2 | CRC-02 | Copilot writes lowercase `day_of_week`; `getTodaysWorkout()` matches capitalized names; 119's normalizer only rewrites `'1'..'7'`. A Copilot session can never be "today's workout" | no | 5 |
| `ENG-06` | P1 | CRC-02 | **Every session in a materialized week is identical.** `materialize_program_week` builds one context and reuses it for every day; `build_workout` is deterministic, so Push/Pull/Legs select the same exercises. **The split is a title** | no | 5 |
| `ENG-07` | P1 | CRC-10 | The certification and review pipeline **gates nothing** — no engine function filters `exercise_intelligence.status`. Draft, heuristic and AI-drafted intelligence is production truth. Product bible principle 4 unenforced | **D-1** | 5 |
| `ENG-10` | P1 | CRC-10 | **No client-facing surface for any engine output.** Nothing in `lib/` reads `decision_traces`, `predictions`, `communications` or `weekly_feedback` on the client side, though `communications`' RLS exists precisely to serve a client their `sent` reviews. Product bible §4 "show the grounding" is unimplemented for clients | scope | 5 |
| `ENG-11` | P1 | CRC-10 | `validate_week`, `build_workout` and `rank_exercises` have no UI caller. The cross-day safety validator — no back-to-back high-fatigue hinge days, ≤3 spinal-loading days/week — **never runs** | no | 5 |
| `ENG-13` | P2 | CRC-10 | `regenerate_program` implements two of its own four actions. `REPLACE_EXERCISES` (`INJURY_ADAPTATION`) and `REDUCE_COMPLEXITY` are never executed: **no exercise is ever substituted after an injury adaptation** | no | 5 |
| `ENG-14` | P2 | CRC-10 | The coach approval matrix is inert for the mode it protects (consequence of AI-2) | no | 5 |
| `ENG-18` | P2 | CRC-10 | The bootstrap has an undocumented ordering dependency and **no guard** — `seed_warmup_library()` silently `continue`s and reports success when run before `rebuild_movement_graph()` | no | 5 |
| `ENG-19` | P2 | CRC-03 | `build_workout` reports `warmup: []` with no signal distinguishing "needs no warm-up" from "the library was never seeded" | no | 5 |
| `ENG-20` | P1 | CRC-14 | **There is no engine test suite.** Zero tests exercise `score_exercise`, `build_workout`, `plan_program`, `evaluate_week`, `predict_client`, `assemble_weekly_review`, trace completeness or LLM groundedness | no | 8 |
| `ENG-21` | P3 | CRC-02 | `predict_client`'s arithmetic is unvalidated — an uncapped finish date, and a `confidence` that sums a pace ratio with two raw percentages | no | 5 |
| `ENG-23` `ENG-24` `ENG-26` | P3/P2 | — | Doc drift in the MIE bootstrap order; `rank_exercises` calls `score_exercise` 3× per candidate row; **warm-up pattern vocabulary mismatch — five of ten slugs never match** | no | 5 |
| `F-J-09` | P1 | CRC-05 | The rejection gates are **null-permissive** — a missing constraint value passes the gate | D-4 | 5 |
| `F-J-10` | P1 | CRC-05 | The AI generator names the deterministic engine as the load authority, **never calls it**, and records nothing | **D-8** | 5 |
| `F-J-13` | P1 | CRC-05 | A decision trace is **not an input snapshot and cannot be replayed** — `generate_workout` trusts `p_context` rather than resolving the subject's state server-side. The explainability guarantee is only as complete as the trace | D-8 | 5 |
| `F-J-14`/`F-J-25` | P2 | CRC-13 | Model identity is not recorded and not centrally pinned | D-8 | 5 |
| `F-J-16` | P1 | CRC-03 | The coaching-engine client **cannot report a failure** | no | 5 |
| `F-J-20` | P1 | CRC-04 | **A model refusal is not detected and is persisted as coaching** | no | 5 |
| `F-J-21` | P1 | CRC-13 | No Anthropic call anywhere is bounded by a timeout; no `AbortController` in any of the 19 functions | no | 5 |
| `F-J-22` | P1 | CRC-10 | The engine plans from unreviewed, model-authored intelligence | **D-1** | 5 |
| `F-J-23` | P1 | CRC-05 | `rebuild_exercise_intelligence()` writes neither `contraindications` nor `joint_stress` — the two columns the injury rule reads. **`INJURY_PREVENTION` could never fire even on a fully populated substrate** | D-1 | 5 |
| `F-J-26` | P1 | CRC-05 | The AI Nutrition Coach is given **no subject context at all** | D-6 | 5 |
| `F-J-18`/`F-J-19` | P2 | CRC-08 | Two subject-identity defects in coach-facing AI, both currently unreachable. **Fix before wiring `analyzeCheckins`/`detectRisks` into any screen** | **D-2(D)** | 5 |
| `F-J-27` | P2 | CRC-04 | A photo-derived calorie estimate is indistinguishable from a measured value | **D-5** | 5 |
| `F-J-29`/`F-J-30`/`F-J-31` | P2/P3 | — | Enrichment targeting; insight de-duplication by date; two smaller defects | no | 5 |
| `E-12`→`F-J-04` | P1 | CRC-05 | `recent()` orders five of nine context tables by a `created_at` they do not have, so the AI sees **nothing** for `workout_sessions`, `workout_set_logs`, `habit_logs` and `user_scores`. `progress_insight` is grounded on nothing, and the confidence score's `+28` and `+9` can never fire — **the flagship safety signal is wired to a constant** | no | 3A/5 |
| `E-13`→`I-NUT-01` | P1 | CRC-01 | `meal_suggestion` reads `protein_g`/`carbs_g`/`fat_g` on `nutrition_logs`; the columns are `protein`/`carbs`/`fat`. `remaining_*` equals the full day's target no matter how much was eaten, so the AI recommends three more full meals to someone who has hit their macros. **FIXED IN CODE:** `8b1fba3` (Wave 3A task 3A-1) — `ai-coaching-engine/index.ts:168` now selects `calories, protein, carbs, fat` and the three `sum()` keys follow it. Schema truth read from the migrations: `006_nutrition_logs.sql:10-15` names the columns `calories/protein/carbs/fat/amount_g/logged_at`, and **006 creates the table first, so 012's richer `CREATE TABLE IF NOT EXISTS` for the same name never executes**. The plan targets really are `*_g` (`client_nutrition_plans`, `001:5-8`) and were deliberately left alone; the prompt-facing `remaining_*_g` response keys are unchanged. The three `nutrition_logs` entries were removed from `known-violations.json` as the last step of the fix, per that file's own both-directions contract (allowlist 8 → 6). **VERIFIED IN CI: PRESENT** — CI run **#51** `33205917510` at `adc43a4`, `success`, 7/7 jobs. Post-fix half directly bounded by `static-guards` **step 7** (unconditional); pre-fix half by `negative-control` **step 9** *"I-NUT-01 — nutrition column guard, pre-fix / post-fix evidence"*, wired in `adc43a4` and green on its first run. **G-3 NOT invoked** — the pre-fix tree `2ad8c6c` is real recoverable history. See §7.19. **NOT `VERIFIED_CLOSED`** — the class is **Data contract / schema**, whose §2.1 ladder also requires FIXED ON QA and VERIFIED LIVE where a read path exists, and `ENV-7` holds every Edge Function undeployed until Wave 5. **No status count moved** — this is a §7 row and that register has no per-row status field (the `F-J-12` precedent, §7.12) | no | 3A |
| `E-17`…`E-20` | P3 | — | Enrichment writers record no actor; query-builder reuse; no timeout/retry/partial-progress contract on batch enrichers (25 serial Sonnet calls in one request); `ai-coach` drops its own audit row on failure | no | 5 |
| `A-3`/`B-1` | P2 | CRC-11 | `ai-coaching-engine`'s daily insight emits `focus` and `intensity_delta` from a Claude call, and both reach the active-workout load cue and `generate_client_plan`'s structure. Read strictly against product bible §6, **that is an LLM altering training** | **D-9** | 5 |

### 7.4 Nutrition · Check-In · Women's Health

| ID | Sev | RC | Statement | Dec | Wave |
|---|---|---|---|---|---|
| `E-NUT-01` | P1 | CRC-02 | Barcode scans record per-100 g macros as one serving — **and the test suite asserts the defective mapping as correct** | no | 4 |
| `E-NUT-02` | P1 | CRC-10 | No edit or delete path anywhere in nutrition, although RLS and grants permit both | **Q-E2** | 4 |
| `E-NUT-03` | P1 | CRC-12 | A meal logged on a past date is written to today and then **disappears from the screen the user is looking at** | no | 4 |
| `E-NUT-05` | **P0** | CRC-05 | **Allergies and dietary restrictions never reach the AI meal-plan generator.** It sends `Dietary restrictions: None` unless the user re-selects from six hard-coded chips. Materially worse than CON-08, which assumed the data reached the prompt and was merely unvalidated. **Loading the profile's allergies is unconditional and does not wait on the decision; only block-vs-annotate does** | **Q-E5 / D-6** | 4 |
| `E-NUT-06` | P1 | CRC-11 | Nutrition operates outside "the engine decides, AI explains" — five AI paths across two backends, none deterministic, none writing a decision trace | **Q-E6** | 5 |
| `E-NUT-07` | P2 | CRC-11 | `/meal-plan` and `/grocery-list` bypass the AI paywall | no | 6 |
| `E-NUT-09`…`E-NUT-16` | P2/P3 | CRC-10/03 | Cache never refreshes and fails silently; meal-log scoring not deduplicated; AI plans never persisted; generation errors become content; the AI-scan portion multiplier is dropped from the record; **water tracking is decorative while the coach-facing half exists**; two nutrition dashboards of unequal capability, one orphaned; unvalidated media type forwarded to a paid credential | **Q-E7** | 4/5 |
| `E-CHK-02` | P1 | CRC-10 | The correct check-in write path has **zero callers** | Q-1 | 4 |
| `E-CHK-03`/`I-CHK-03` | P1 | CRC-02 | Two mutually exclusive `weekly_checkins` column families; the writer and every reader disagree | **Q-2** | 4 |
| `E-CHK-04` | P1 | CRC-10 | The check-in form collects data it silently discards, and **never collects weight** — which is `ai_adjust_nutrition`'s only trend input | **Q-3/Q-E3** | 4 |
| `I-CHK-04` | P1 | CRC-14 | **The QA fixtures write the opposite column family and the wrong status, masking the defect they exist to exercise.** QA looks populated to the coach dashboard while the real write path produces rows those surfaces cannot read | Q-2 | 4 |
| `E-CHK-05`…`E-CHK-11` | P2/P3 | CRC-11/10/03 | `/checkins` is an appointments calendar filed as check-in; placeholder screens on live routes; the coach analysis analyses the coach; the in-app QA suite probes a table **and a column** that do not exist; re-submission semantics; read paths mask failure; the success dialog claims a notification that was never sent | **Q-E4** | 4/7 |
| `F-01`…`F-07` | P1/P2 | CRC-06/10 | No domain constraint on any cycle table; "last period" is the max `start_date` not the most recent *past* one; **re-opening the symptom sheet destroys the day's saved values** (live-verified); duplicate periods accumulate; `cycle_settings` is write-dead so predictions are permanently 28/5; writes silently no-op when signed out | no | 7 |
| `I-WMH-01` | P2 | CRC-06 | **Row added 2026-09-09 by the 3A-11 execution package, under the owner ruling recorded in `docs/WAVE_3A_11_RULING_VALIDATION.md` §12 — closing registry §7.22 open item **B4**, which recorded that this finding is named in `MASTER_REMEDIATION_WAVES.md` and in Workstream I but had no row here.** Placement is §7.4 (*Nutrition · Check-In · Women's Health*) because Workstream I files it as the **database-level complement** of the `F-01`/`F-04` app-level row directly above; no requirement semantics were changed and the statement below is Workstream I's. `cycle_logs` has PK + one FK + one non-unique index `(user_id, start_date DESC)` and **no unique constraint and no CHECK** — verified live on QA 2026-09-09. Expected contract: one period per start date; `end_date >= start_date`; periods do not overlap. None of the three is enforced, so a double tap inserts two periods for one day and `endCurrentPeriod()` closes only *the most recent* open period, leaving the older one open forever and every cycle-length figure computed over a corrupted series. `cycle_symptoms` already carries `UNIQUE (user_id, log_date)` and `cycle_settings` a `PRIMARY KEY (user_id)` — two of the three tables in this module were given an identity model and this one was not. **Source:** `QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md`:422 (P2; *Product decision needed: no; Parallelizable: yes*). **Existing migration responsible:** `033_womens_health.sql`. **Remediation:** migration **131** adds `cycle_logs_one_period_per_start` UNIQUE `(user_id, start_date)` and the CHECK `cycle_logs_end_on_or_after_start`; **the overlap EXCLUSION constraint is DEFERRED** by the same ruling — Workstream I conditions it on a dedupe pass and "overlapping periods" has no product definition. **No client change is required**, and none was made: the writer stays a plain insert and the index makes the double tap fail rather than duplicate. Closure class **Data contract / schema**; migration 131 is authored and **NOT applied** — `FIXED ON QA` is not claimable until a separately authorized application. **Complements** `F-01`, `F-04`. | no | 3A *(task 3A-11)* |
| `F-08`…`F-16` | P1/P2/P3 | CRC-02/04 | The fertile-window **label ignores the computed window** (wrong on 7 of 28 days); **no staleness bound — a 400-day-old log renders as fact**; `ovulation` used as both 1-based day and 0-based offset in one function; phases collapse at short cycles; the app can never report a late period; a future-dated start fabricates "Menstrual · Day 1"; out-of-range lengths silently clamped; DST-sensitive arithmetic; the calculation reads the clock internally | **E-1, E-2** | 7 |
| `F-19`…`F-25` | P2/P3 | CRC-02/10 | The cycle row is mislabeled as `recovery` in the AI context; no history surface; no edit/delete for a mis-logged period; "period ended" is silent; disclaimer below the fold; the gender gate only affects a subtitle **and hides a user's own data when unset**; captured symptom detail never displayed | **E-3, E-5** | 7 |

### 7.5 Billing & Entitlements

| ID | Sev | Statement | Dec | Wave |
|---|---|---|---|---|
| `K-02` | P1 | Renewals and payment failures are never reconciled; `payments` is not a ledger | — | 6 |
| `K-06` | P1 | Refunds and chargebacks revoke nothing | **D-K4** | 6 |
| `K-07` | P1 | A failed Stripe cancel still revokes local access — and the UI says "Switched to the Free plan" | D-K2 | 6 |
| `K-08` | P1 | Nothing prevents duplicate concurrent subscriptions. **The customer pays twice and `client_plan()` reports one plan** | **D-K9** | 6 |
| `K-09` | P1 | Coach plan capacity is granted, never revoked, and self-writable | **D-K8** | 6 |
| `K-10` | P1 | Coach messaging — a Coach-Guided-only capability — has no paid-state check | — | 6 |
| `K-11` | P1 | The first failed payment revokes access immediately | **D-K3** | 6 |
| `K-13` | P1 | Stripe customer creation races; a user can end up with two Stripe customers | — | 6 |
| `K-15` | P1 | Three-and-a-half tier representations, only one synchronized | — | 6 |
| `K-17` | P1 | Coach Connect readiness is cached and refreshed only when the coach looks at it | — | 6 |
| `K-19` | P1 | Coach revenue figures are structurally wrong | K-02 | 6 |
| `K-14`,`K-18`,`K-20` | P2 | Commission prices differently on one-time vs recurring; the global setting silently overrides the per-coach rate; a coach can zero their own commission by pre-inviting the lead | **D-K7** | 6 |
| `K-22`,`K-23`,`K-24`,`K-27` | P2 | One-time entitlements granted without checking `payment_status`; no event-ordering guard, so a stale update resurrects a cancelled subscription; abandoned checkouts leak pending payment rows; webhook failures are silent | — | 6 |
| `K-29`,`K-30` | P3 | Trials resolvable but not creatable; **`PaywallGate` fails open on error** | **D-K5** | 6 |
| `E-09` | P1 | No `[functions]` block in `config.toml`. **`stripe-webhook` will 401 every Stripe delivery** unless deployed with `--no-verify-jwt`, and `verify_jwt=true` on the other 18 is providing a false sense of protection — it is what makes EDGE-1 and EDGE-2 reachable by the internet rather than by nobody | — | 1 |

### 7.6 Release, Environment, Product Integrity, UI, Testing

| ID | Sev | Statement | Dec | Wave |
|---|---|---|---|---|
| `LRE-09`…`LRE-42` (34 rows) | P1–P3 | Secret manifest uncommitted and undiffable; function deps unpinned; deploys unautomated with no recorded SHA; no Vault runbook; no flavors or per-environment bundle ids; **beta is undefined** (D-4); build numbers manual; artifacts carry no provenance and the QA bundle carries production strings; no audit log; no rollback per layer; `.temp` tracked; reset wrapper unguarded; no root README or environment runbook; price-ID manifest uncommitted; Stripe mode unresolved per environment | D-1…D-6 (L) | 1/8 |
| `REL-09`…`REL-15` | P1 | No `PrivacyInfo.xcprivacy`; `ITSAppUsesNonExemptEncryption` absent; **three different app names and two diverging bundle identifiers** — fix before the App ID is registered, it is immutable afterwards; no build-number strategy | **D-4(G)** | 8 |
| `REL-24`…`REL-27` | P1 | Webhook event coverage and dead-lettering; `config.toml` declares no auth/redirect/email-template config so QA↔prod parity is unverifiable; **no crash reporting, analytics, APM, structured logging, uptime monitoring or alerting in any environment**; free-tier daily backups, no PITR, no rehearsed restore | **D-5(L)**, D-3 | 8 |
| `REL-32`,`REL-37`…`REL-48` | P2/P3 | Push permissions requested with no push infrastructure (`SCHEDULE_EXACT_ALARM` is commonly rejected); landscape permitted on a portrait-first UI; **180 occurrences of TODO/mock/placeholder/"coming soon" in `lib/`**; unlicensed remote placeholder imagery; no App Store Connect metadata; no iPad decision; no localisation declaration; no Fastlane; unused desktop scaffolds; **no accessibility audit though the product bible names accessibility a requirement** | scope | 8/9 |
| `H-04`,`H-05` | P1/P2 | `chat-media` and `progress-photos` buckets are referenced by shipped UI and passing widget tests and **created by no migration**. Migration 029 writes RLS *for* `progress-photos`, assuming a bucket it never creates. **Do not create either as a public bucket — both hold body photography** | no | 3A |
| `H-07`,`H-08`,`H-13`,`H-14` | P1/P2 | **The dominant product-integrity cluster (CRC-04).** An empty or unreachable conversation renders **four fabricated coach messages including training advice**; with no assigned habits the app invents **eight habits with invented multi-day streaks and schedules device reminders for them**; five fictional community groups, two pre-marked "Joined"; with no program, Home starts a hard-coded demo workout **credited to a fictional coach**. None is distinguishable from real data by looking at the screen, which is why all four survived six prior workstreams | **Q-H2, Q-H6** | 3C |
| `H-09`,`H-10`,`H-16`,`H-17`,`H-18` | P2/P3 | Challenges join but never progress and two tabs can never populate; six notification preferences persisted and honoured by nothing; **`/pods` (accountability pods, real tables, seeded data) and `/coach-client-workouts` are unreachable from anywhere**; three inert Settings controls; two 0-byte service files and 40 orphaned providers | **Q-H3, Q-H7, Q-H8** | 7 |
| `H-12` | P2 | The marketplace ranks demo fixtures and coaches who have closed their books alongside real ones | **Q-H5** | 7 |
| `I-USR-01`,`I-USR-02`,`I-USR-03` | P1/P2 | 53 of 143 FKs restrict deletes, blocking program **and** account deletion; `user_profiles.email` can never be updated after creation; **`user_profiles` models five concepts twice** | **Q-6, Q-7, Q-8** | 3A/7 |
| `I-NUT-03`,`I-NUT-04` | P1 | `ai_adjust_nutrition()` overwrites the coach's prescription in place, under the coach's name, destroying `notes`; no uniqueness on the active nutrition plan, so two rows make every reader's `maybeSingle()` 406 into a default | **Q-4** | 4 |
| `I-NOT-01`,`I-NOT-02`,`I-NOT-03`,`I-NOT-05`,`I-NOT-06` | P1/P2/P3 | `messages` has no `metadata` column so **every chat image message is silently discarded after upload**; `may_notify()` rejects the community and class notifications the app sends; two triggers notify the coach of the same completed workout; `conversations` has no unique constraint on the participant pair; the `notifications.type` vocabulary has 20 producers and 8 handled cases | no | 3A |
| `I-COM-02`…`I-COM-06` | P1/P2 | The vendor attendee list throws on the same nonexistent column; **global exercise publishing has no moderation gate and the moderation tool is broken**; class capacity, waitlist and enrolment are non-functional because three RLS-scoped operations are treated as global (CRC-09); `likes_count`/`comments_count` have no writer; `toggleReaction()` races its own unique constraint | **Q-9** | 3A/7 |
| `I-WRK-02`,`I-WRK-03` | P2 | PR detection is `AFTER INSERT` only while the writer is update-then-insert; `workout_sessions.program_workout_id` has no writer — **and must not be populated before Q-7, or `generate_client_plan()`'s delete starts failing with 23503 for any client who has trained** | **Q-7** | 4 |
| `I-LEG-01`,`I-LEG-02` | P1/P2 | "A completed workout" is modelled twice and dual-written non-atomically, with disjoint readers; four relations and two columns are fully dead | **Q-11, Q-12** | 7 |
| `I-MIG-02`,`I-TYP-01`,`I-TYP-02` | P2 | Both `ALTER`-added CHECKs are `NOT VALID`, and 119's `RAISE WARNING` naming un-canonicalisable rows was never acted on; nine column names carry different types in different tables; 92 enum-like text columns, 7 constrained | no | 3A |
| `M-13` | P2 | The in-app QA Center is broken by migration 113 — it uses `select('*')` where the new policy narrows the row | no | 7 |
| `N-06`,`N-08`,`N-09`,`N-10` | P1/P2/P3 | **259 tests (37% of the Flutter suite) execute no product code**; a live logic slip in the Phase-2 swap cursor path (`_currentSetId` is `''`, never null, so the null arm is dead); 19 Edge Functions with 0 tests and no Deno runtime installed; **three services bind `Supabase.instance.client` internally, so zero behavioural coverage is possible for any of them without a seam** — three P1 findings sit behind that one structural fact | no | 8 |
| **`I-WRK-01`** *(= `H-01`, `M-07`, `M R-2` — retired aliases, §3; **`H-01` is not a tracking key**)* | P1/P2 ⚠ | **Tracking home established by owner ruling D-1, 2026-08-27 (§7.14). Evidence-only row: §7 carries no per-row status field, so this row is NOT status-countable** — the F-J-12 precedent (§7.12, `REMEDIATION_PROGRESS.md` §3). `workout_set_logs.created_at` does not exist; the column is `logged_at` (`001_full_ecosystem.sql:158–168`). Three references in `getExerciseProgression()` named the phantom column; every caller swallowed the 400, so a headline strength-progression screen was permanently and convincingly empty. **FIXED IN CODE:** `654b09c` — `workout_service.dart:237,243,246` `created_at`→`logged_at` (+3/−3; `catch (` count 14→14, EC-11 untouched; no migration). **FIXED ON QA:** the column has existed as `logged_at` since 001, and its presence in the **live catalog** is evidenced by real read-only requests against QA — `QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md` §120–123, 2026-08-24: `workout_set_logs?select=logged_at` → **401 `42501`** *(permission denied — PostgREST resolves the column before it checks the grant, so this is a positive existence oracle)* and `workout_set_logs?select=created_at` → **400 `42703`** *(column does not exist)*. Corroborated by run **#35** `33092528474` step 11 *Live SQL evidence*, whose ENV-3 live ledger proves migrations **000–128** are applied to QA. *(Evidence correction, 2026-08-27, owner-authorized: this sentence previously credited the *Contract suite* with reading "QA's live catalog". It cannot — `supabase/tests/contract/run.mjs:5` states "Offline. Contacts no environment", and the file contains no network call and reads no credential. That evidence belongs to **VERIFIED IN CI**, where it is retained below. No state, count, class or dependency changed.)* **VERIFIED IN CI:** run **#35** (head `654b09c`, all five jobs `success`) — `flutter analyze`, `flutter test` (H-G1 green) and `npm run test:contract` green with **both** allowlist halves removed: `known-violations.json`'s `I-WRK-01` entry and `product_contract_guard_test.dart`'s H-G1 `knownMissing` entry. Both are checked in both directions, so removing either alone fails. **VERIFIED LIVE: PRESENT** — CI run **#41** `33129000361`, job `wrk01-live` `98714155399`, head `8843c33`, 2026-08-28. Closure class is **Data contract / schema**, whose §2.1 ladder requires *"VERIFIED LIVE where a read path exists"*, and a read path exists (`getExerciseProgression()` → the strength-progression surface). Owner ruling **D-2** refused to waive it and **D-2(c)** required the **actual read path** to fail against the pre-fix tree and pass against the fixed tree **on the same QA fixture**; the comparison was not weakened and no substitute was recorded. The capability blocker §7.14 recorded is now closed by the `wrk01-live` job (`ci.yml:448`), which runs the real `WorkoutService().getExerciseProgression()` from `integration_test/wrk01_progression_live_test.dart` on a Linux desktop target under `xvfb`, twice against one live QA fixture — once at the run head and once at the **real parent** `654b09c^` = `acd2cc5`, whose `workout_service.dart:237,243,246` still name `created_at`. **PRE-FIX (`acd2cc5`), observed in the run log:** `WRK01-MARK FIXTURE present rows=4` · `WRK01-MARK SERVICE-CALLED getExerciseProgression` · `WRK01-MARK RESULT len=0` · `WRK01-MARK ASSERT-NONEMPTY FAIL` — the same fixture, the real service, an empty result, and the non-empty expectation is the assertion that failed. **POST-FIX (`8843c33`, carrying `654b09c`), same fixture, same probe:** `WRK01-MARK FIXTURE seeded rows=4` · `WRK01-MARK SERVICE-CALLED getExerciseProgression` · `WRK01-MARK RESULT len=3` · `WRK01-MARK ASSERT-NONEMPTY PASS` · `WRK01-MARK ASSERT-ALL PASS`. **QA hygiene (closure standard §7):** `WRK01-MARK CLEANUP verified remaining=0` — every fixture row is enumerated and removed and the removal is proved **by a read**, not assumed from a `204`. All six jobs `success`; `wrk01-live` steps 1–7 all `success`. See §7.15. **Status: `VERIFIED_CLOSED` 2026-08-28** — all four states the **Data contract / schema** class demands are present, with no waiver and no exception. **The row remains evidence-only and is NOT status-countable, and no status count was moved** — §7 carries no per-row status field (D-1, §7.14; the `F-J-12` precedent, §7.12 and `REMEDIATION_PROGRESS.md` §3). Which bucket the status table currently holds `I-WRK-01` in still **cannot be determined from this repository and was not guessed**. **§10 one-line test — if this defect were reintroduced tomorrow by a plausible, well-intentioned change, what exactly goes red, and where does someone see it:** three mechanized guards, all standing. **(i)** `npm run test:contract` in `static-guards` — `known-violations.json` carries **no** `workout_set_logs.created_at` entry and is checked in **both** directions, so re-naming the phantom column fails the job and there is no allowlist route back. **(ii)** H-G1 in `product_contract_guard_test.dart` — the `knownMissing` map no longer holds the entry, so *"no phantom column outside the recorded allowlist"* fails in the `flutter` job. **(iii)** `wrk01-live` step 6 — the post-fix leg asserts `RESULT len=3` against a live QA fixture through the real service, so a regression both static guards missed still turns the job red. None of the three is "someone would notice". ⚠ **D-4 unresolved:** Workstream I rates this **P1** (`QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md:740`), Workstream H rates the same defect **P2** (`QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md:319`). §5 requires a departure from a source rating to be recorded in the row; the two source reports disagree with each other, so no rating is mechanically compelled and none is chosen here. ⚠ **D-5 unresolved:** Workstream I states the site count as both *"(Dart, 2 sites)"* (`:1132`) and *"(1 site)"* (`:1239`); `MASTER_REMEDIATION_WAVES.md:241` and the implementation both say **three** (`:237,243,246`). Waves and implementation agree; the workstream report is wrong in both of its statements — but correcting frozen A–N evidence is outside §10.2, so it is recorded, not rewritten. | no | 3A *(task 3A-5)* |

---

### 7.7 Wave 1 batch amendment — 2026-08-24/25

Recorded at the Wave 1 batch custody checkpoint. Closure evidence:
[`WAVE_1_BATCH_CLOSURE.md`](WAVE_1_BATCH_CLOSURE.md). Nothing here rewrites a
historical report; the A–N reports and Wave 0 text above are unchanged.

**Status movements (batch tasks 2–9).** `REMEDIATED` = FIXED IN CODE only; the tree is
not yet committed/pushed, CI has never executed, and EB-1 still blocks the live suites,
so nothing here is `VERIFIED_CLOSED` *(status as written at the 2026-08-24 checkpoint —
the custody commit, the CI executions and EB-1's resolution are recorded in the
W1B-N6…N8 rows below and the progress-board changelog)*:

| Finding | Task | New status |
|---|---|---|
| ENV-4, `K-26` | 2 | `REMEDIATED` |
| ENV-5 | 3 | `REMEDIATED` |
| ENV-6 | 4 | `REMEDIATED` *(ci.yml has never run — commit+push required)* |
| `E-09` | 5 | `REMEDIATED` *(deployment of the block is gated by **W1B-N5** below)* |
| `LRE-34`, `REL-36`, `LRE-35` *(the reset-wrapper row inside `LRE-09…42`)* | 6 | `REMEDIATED` *(seed/link guards proven in a local container only, never against QA)* |
| REL-3 | 7 | `REMEDIATED` |
| UIX-2 *(text half only)* | 8 | `REMEDIATED` — replacement wording `REQUIRES_REVIEW` by owner (see the UIX-2 row) |
| `R-06` | 9 | `BLOCKED_ENVIRONMENT` (**EB-12**) — no Management credential; current HIBP state unverifiable read-only; premise unverified, not disproven |

**New findings.** Per §10.4: each carries an ID, a CRC from §1, and a wave.

| ID | Sev | RC | Statement | Dep | Dec | ∥ | Wave |
|---|---|---|---|---|---|---|---|
| **W1B-N1** | P1 | CRC-13 | `supabase/STRIPE_SETUP.md` instructs `supabase link --project-ref <production>` — a committed runbook that points the CLI at production. Allowlisted **with an explanatory comment** in `check-production-refs.sh` so CI is honest rather than red; the allowlist entry is a marker of the defect, not an acceptance of it | EB-5 | no | Y | 6 *(6.0 replaces the runbook with the QA Stripe runbook; remove the allowlist entry in the same change)* |
| **W1B-N2** | P2 | CRC-07 | `/admin-exercise-review` and `/vendor-portal` are registered unconditionally and their screens contain no role check (four sibling admin screens each have one). Server-side RLS is the real control, so this is attack surface + UX, not presumed exposure — confirm against Phase 1 policies, then gate the UI | — | no | Y | 2 *(RLS confirmation)* / 7 *(UI gate)* |
| **W1B-N3** | P2 | CRC-10 | `privacy_policy_screen.dart` §5 claims data export "from Profile → Settings → Account" and "in JSON or CSV format on request" — the same nonexistent path UIX-2 removed for deletion, asserted for a different right. Left standing deliberately: task 8's authority covered only the deletion half | — | **owner** (whether export ships, or the claim is corrected) | Y | 7B |
| **W1B-N4** | P3 | CRC-13 | `supabase-keepalive.yml`'s header claims the anon key "is already shipped inside the mobile app binary + `app_constants.dart`" — untrue since ENV-4. The workflow is the one production-targeting file in the tree and no batch task owns it; not edited | — | no | Y | 8 |
| **W1B-N5** | P2 | CRC-13 | `supabase config push` writes the **entire** `config.toml` to the linked project, and the file deliberately declares almost no `[auth]`/`[db]` settings — a push to deploy the new `[functions.*]` block would silently reset QA's live auth configuration to CLI defaults. Until `config.toml` is reconciled with QA's live configuration and the reconciliation is recorded, the `[functions.*]` block may be deployed **only** per function via `supabase functions deploy` (the mechanism the existing release architecture already uses). Guidance recorded in `config.toml`, `docs/qa-environments.md` and the Wave 5 prerequisites | — | no | N | **5.0 — entry precondition** |
| **W1B-N6** | P2 | CRC-14 | `check-production-refs.sh` scanned with `git grep`, which reads **tracked files only** — so `ci.yml` and `qa-db-reset.sh` passed the guard locally while untracked (custody checkpoint, 2026-08-25) and failed it in CI the moment the custody commit made them tracked (run for `9319c67`). The two flagged usages were refusal/assertion references, not executable production paths (classification B): both were rewritten in QA-allowlist form with no production literal (the ci.yml artifact scan is now strictly stronger — it fails on *any* non-QA project ref), and the guard now scans `--untracked`, demonstrated to catch what the old invocation missed. **Remediated in the same change** (2026-08-25); CI must reproduce | — | no | N | 1 *(closed with the CI-red fix)* |
| **W1B-N7** | P2 | CRC-14 | The ENV-4 inline CI check matched **documentation placeholders** as credential material: its patterns (`supabase\.co`, `pk_(test|live)_`) flagged `YOUR_QA_REF.supabase.co` and `pk_test_...` in `app_env.dart`'s usage comment, failing the `aac64b3` run's static-guards job at the step's **first-ever execution** (run 1 died at step 1, so steps 2–4 had never run — same class as W1B-N6: two tasks verified alone, integrated only in CI). Root cause: guard aimed at the wrong layer — shape-of-material was not part of the pattern. Remediated by matching **real material only** (20-char lowercase-alphanumeric project host · `eyJ`+20 token chars · `pk_(test|live)_`+24 alphanumerics) with comments still scanned — a real key pasted into a comment still fails — plus an **inline pattern self-test** asserting real-shaped fixtures match and the aac64b3 placeholder shapes do not, so a weakened pattern fails the guard itself. Residual sub-threshold coverage: the production-ref guard and the QA-artifact allowlist scan. Old check shown failing on the current file; new check passes it, catches planted real material in comments, and the self-test catches a crippled pattern arm. **Remediated in the same change** (2026-08-25); CI must reproduce | — | no | N | 1 *(closed with the ENV-4 guard fix)* |
| **W1B-N8** | P2 | CRC-14 | With EB-1's secrets finally provisioned, the live-qa job reached the security suites for the first time and all six died at import: `ids.json missing`. The file is the generated map of the four fixture-identity UUIDs, written by `setup-identities.mjs`, gitignored by design (`.gitignore:34`; W1-T1 custody manifest; README: "generated, not authored") — so an ephemeral CI checkout can never contain it. The wave plan named the setup script as part of W1-B2's QA requirements; the ci.yml implementation omitted the step — the same first-joint-execution class as W1B-N6/N7. Remediated by one creds-gated step after the exact-host QA confirmation: `node supabase/tests/security/setup-identities.mjs` (idempotent: creates-or-repairs the four `p1-*@qa.12circle.test` identities, `is_demo`, seeds three P1-FIXTURE victim rows only if absent; no deletions). **This is the programme's first sanctioned standing QA write — explicitly authorized by the product owner 2026-08-25.** Harness untouched; ids.json stays untracked. CI must reproduce | EB-1 (resolved) | owner authorization RECORDED | N | 1 *(closed with the CI step)* |
| **W1B-N9** | P3 | CRC-14 | **Test-fixture defect, not a security defect.** The first full live run scored 270/271; the one FAIL, D-02 "public signup cannot mint an admin", never reached the boundary: hosted Supabase Auth rejects example/test domains at the public `/auth/v1/signup` route (`email_address_invalid` — docs: "Example and test domains are currently not supported"), so the probe's `@qa.12circle.test` address 400s before `handle_new_user()` fires. The security contract itself is proven by the three admin-API metadata probes in the same suite (role=admin/content_manager/superuser all degrade to `client`; migration 115's clamp is source-controlled), and the suite correctly failed closed on the unexpected status rather than counting an unexercised probe as a pass. Remediated by one line (`d02-role-escalation.mjs:127`): probe address → `p1-signup-public@qa.12circlefitness.com` — the owner-confirmed controlled business domain (2026-08-25), so a confirmation email can never reach a third party; the fixed-address + pre-delete/post-delete cleanup pattern is unchanged. No assertion logic, harness, Auth configuration or other fixture touched. Closes when CI shows 271/271 | — | owner domain confirmation RECORDED | N | 1 *(closed with the fixture fix)* |

---

### 7.8 Phase 1 live-evidence reconciliation — 2026-08-26 · evidence: CI run at `6d42b10`

Owner-approved promotion record. Evidence for every row below: the green CI run at
commit `6d42b10` — live security **271/271** across the six suites (D-01 43/43 ·
D-02 40/40 · D-03 27/27 · 1D 54/54 · 1E 73/73 · 1F 34/34), live AI suite passed
(characterization level — see holds), contract suite passed (allowlist intact), overall
workflow green. The suites were written to fail against the pre-remediation database
(`supabase/tests/security/README.md`), so this run supplies **VERIFIED LIVE** and
**VERIFIED IN CI** in one artifact. Commit `d151ee6` (suite failure accounting) was
reviewed at reconciliation: reporting-only, no assertion weakened.

**Promoted to `VERIFIED_CLOSED` — 23 rows:**

| Row | From | Closing evidence at `6d42b10` |
|---|---|---|
| SEC-01 | ALREADY_FIXED | D-01 43/43 |
| SEC-02 | ALREADY_FIXED | D-02 40/40 — including, for the first time, the real public `/auth/v1/signup` route (post-W1B-N9) |
| SEC-03 | ALREADY_FIXED | D-03 27/27 |
| SEC-05 | ALREADY_FIXED | 1D 54/54. **Retained limitation:** the anon-executability probes are a finite list; the full-catalog class assertion is **Wave 2 task 2B** |
| SEC-06 | ALREADY_FIXED | 1E 73/73 |
| SEC-07 | ALREADY_FIXED | 1E 73/73 |
| SEC-10 | ALREADY_FIXED | 1F §5 |
| F-01 | ALREADY_FIXED | 1F §2 |
| F-03 | ALREADY_FIXED | 1F §4 |
| F-05 | ALREADY_FIXED | 1F §5 |
| F-06 | ALREADY_FIXED | 1F sweep |
| F-07 | ALREADY_FIXED | 1F §6 |
| F-08 | ALREADY_FIXED | 1F sweep |
| TST-1 | BLOCKED_ENVIRONMENT (EB-1) | the suite itself executed in CI — its own closure criterion |
| ENV-1 | REMEDIATED (W1-T1) | migration-hygiene guard green in CI; zero untracked engineering files |
| ENV-4 | REMEDIATED | ENV-4 static guard + env-ratchet tests + QA-bundle allowlist scan |
| ENV-5 | REMEDIATED | harness guard tests + `--untracked` production-ref guard |
| E-09 | REMEDIATED | edge-function config guard 5/5. **Deployment of the block remains gated by open W1B-N5** |
| REL-3 | REMEDIATED | `release_route_gate_test.dart` executed in CI |
| W1B-N6 | REMEDIATED | production-ref guard green in CI on the corrected tree |
| W1B-N7 | REMEDIATED | ENV-4 step green incl. its pattern self-test |
| W1B-N8 | REMEDIATED | setup-identities ran in CI; all six suites executed |
| W1B-N9 | REMEDIATED | 271/271 — its stated closure criterion |

**Deliberately NOT promoted — the row's missing evidence, exactly:** SEC-04 *(open
regression F-J-01: d04 has a documented blind spot on `materialize_program_week`'s
wrapper; needs migration 124 + I-MIG-03 class guard + live 403 probe — Wave 2)* ·
Q-4/PAR-Q closure *(SEC-R2 open: legitimate flag writes throw; needs 124 casts + live
three-flag write probe)* · SEC-09 *(REST suites cannot assert catalog `search_path`
state; `function-search-path.sql` is not wired into CI; needs FG-1 + I-MIG-03)* ·
SEC-11 and the 12 Phase 2 closures *(their live evidence is the 32-assertion workout SQL
suite, which has never run in CI; needs FG-2 — behavioural Dart halves did run)* ·
SEC-08 *(mechanical half live-verified in 1F §3; row stays open on decision Q-2)* ·
ENV-6 *(push-triggered runs proven; the row's own retest names a PR run — closes at the
first PR)* · LRE-34 / REL-36 / LRE-35 *(no CI guard exercises them; container-only
evidence)* · K-26 *(mechanical half CI-verified; row stays on D-1(L))* · UIX-2 text half
*(held uncommitted for owner wording)* · R-06 *(BLOCKED, EB-12)* · W1B-N1…N5 *(open by
design: N5 is the Wave 5.0 gate; N1→6.0, N2→2/7, N3→7B, N4→8)* · every AI-domain row
*(the AI suite pass is characterization-level; zero functions deployed — EB-2;
BLOCKED_ENVIRONMENT stands)* · every contract/3A row *(the contract suite passed **with**
the allowlist — it proves the recorded-defect state, not closure)*.

**Follow-up evidence gaps — recorded, NOT implemented (owner assignment required, no
silent scope expansion):**

| ID | Gap | Covers | Suggested home |
|---|---|---|---|
| **FG-1** | Wire `supabase/tests/security/function-search-path.sql` into the live-qa CI job with a DB-credential path | SEC-09 promotion · I-MIG-03's live half | Wave 2 (2B) |
| **FG-2** | Wire the 32-assertion workout SQL suite (`supabase/tests/workout/*.sql`) into the live-qa CI job | SEC-11 + the Phase 2 re-verification cohort | Wave 2 retest scope |

**Production statement (closure standard §6):** Production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to
it. No migration was applied, reverted or pushed to it. No Edge Function was deployed to
it. The linked project remained `eyqtldjqpgpljlqvpowh` throughout. This reconciliation
changed governance documents only.

---

### 7.9 Live SQL evidence reconciliation — 2026-08-25 · evidence: CI run at `2a8d0b6`

The first execution of the SQL-level evidence phase (FG-1, FG-2, ENV-3 live),
against QA `eyqtldjqpgpljlqvpowh`. Every suite is one DO block that ends by
RAISEing its report, so all four rolled back: **no migration was applied, no
`db push` was run, nothing was written to `schema_migrations`, and production
`nxdbooufqzkpslkcogxc` was not contacted.**

| Suite | Result | Observed |
|---|---|---|
| **FG-1** · `function-search-path.sql` (SEC-09 live half) | **5 PASS / 0 FAIL** | SP-1 unpinned SECURITY DEFINER functions **0** · SP-2 unpinned functions of any kind **0** · SP-3 functions pinned outside `public` **0** · SP-4 `generate_client_plan` + `materialize_program_week` re-pinned **2/2** · SP-5 EXECUTE grants to PUBLIC or anon **0** |
| **FG-2a** · `phase2-contract.sql` (SEC-11 / Phase 2) | **20 PASS / 0 FAIL** | the AFTER-1…AFTER-8 matrix |
| **FG-2b** · `plan-day-titles.sql` (OBS-4 / migration 121) | **15 PASS / 0 FAIL** | — |
| **ENV-3** · live ledger comparison | **5 PASS / 0 FAIL** | L-1 0 · L-2 0 · L-3 0 · L-4 0 · L-5 123 rows vs 123 expected · INFO 123 authored and pending |

**Verified QA migration state: 000–122 applied; migration 123 authored, committed
and declared pending — not applied, not an applied ledger row.**

#### The FG-2 assertion count — 32 reconciled to 35

The two numbers describe the same two files, and the discrepancy is a counting
method, not a grouping:

- **32** originates in `QA_WORKSTREAM_N_TEST_COVERAGE_REPORT.md` §"Live workout
  SQL", a **static inventory taken without running the suite** — its own row
  reads "not run — no credentials". It propagated from there into the custody
  manifest and the progress board's baseline table.
- **20 + 15 = 35** is what the unchanged files actually emitted when executed.
- The files have **one commit in their entire history** (`8e47f07`, W1-T1
  custody) and are byte-identical to what N inventoried, so suite growth is
  excluded. Neither contains a loop or a conditional block, so emission is
  deterministic — the same files always emit the same 35 lines.
- Static counting of these files is demonstrably unreliable: three independent
  static attempts produced 32 (N), and — at the FG-2 wiring checkpoint — 25 by
  counting `case when … then 'PASS'` ternaries, because the suites build report
  lines in more than one syntactic shape.
- **20 corroborates independently.** `PHASE_2_WORKOUT_TEST_MATRIX.md` records
  "20/20 AFTER assertions PASS" and `PHASE_2_WORKOUT_RECONCILIATION.md` repeats
  it. FG-2a's 20 is that same AFTER set, re-verified live in CI.

**Resolution: the executed count is authoritative — FG-2 is 35 assertions
(FG-2a 20 + FG-2b 15).** Workstream N's report is frozen evidence and is not
rewritten; its 32 is superseded, and the forward-looking references in this
registry and on the progress board are corrected. 32 was never a different
grouping.

#### Promoted to `VERIFIED_CLOSED` — 2 rows

| Row | Class ladder | Evidence at `2a8d0b6` |
|---|---|---|
| **SEC-11** · a client could rewrite a completed session | as above | FG-2a. The matrix maps this finding to **AFTER-4a/4b/4c**, "completed history is immutable", and `phase2-contract.sql` asserts directly that a completed set cannot be un-completed. Not inferred from the suite passing as a whole |
| **OBS-4** · duplicate generated day titles | as above | FG-2b in full — 15/15. `plan-day-titles.sql` exists solely to pin migration 121's `plan_day_titles()` authority |

#### Owner ruling, 2026-08-25 — SEC-09's closure criterion. Additive amendment.

**The ambiguity, as it was documented.** §7.8 held SEC-09 for "needs FG-1 +
I-MIG-03". The reconciliation as first drafted read that bare finding ID as the
**class guard existing and running** rather than as I-MIG-03's own closure, and
promoted SEC-09 on FG-1's 5/5. The final governance audit of this checkpoint
found that reading contestable and could not resolve it from the repository:
§4.2 tracks the standing test itself as `I-MIG-03` and §7.8's follow-up table
pairs "SEC-09 promotion · I-MIG-03's live half" *(reading A)*, while §7.8's
SEC-04 clause two lines above says "I-MIG-03 **class guard**" explicitly where
the SEC-09 clause says bare "I-MIG-03" *(reading B)*. The ambiguity was
preserved and escalated rather than decided.

**The ruling.** The product owner ruled on 2026-08-25 for **reading B**: §7.8
distinguishes "I-MIG-03 class guard" from a bare "I-MIG-03", and the repository
does not provide sufficient authority to reinterpret the bare finding ID as
merely the class guard. **SEC-09 `VERIFIED_CLOSED` therefore requires FG-1 live
evidence AND I-MIG-03 itself at `VERIFIED_CLOSED`.**

**Effect on this checkpoint.** The SEC-09 promotion is **withdrawn**. SEC-09
remains **`ALREADY_FIXED`**, not `VERIFIED_CLOSED`. I-MIG-03 remains **open, in
records mode**, and is not promoted. **FG-1's 5 PASS / 0 FAIL stands as recorded
live evidence** — SP-1 and SP-2 assert the class schema-wide with 0 unpinned
functions of any kind, and SP-4 answers the one item the static durability guard
flagged as "claimed by 122's dynamic sweep — NOT statically verifiable, live
evidence is FG-1", 2/2. That evidence is not rescinded and is not re-run; under
this ruling it is **necessary but not sufficient** for SEC-09's closure. SEC-09
closes when I-MIG-03 closes — currently Wave 2 task 2A, where the durability
guard moves from recording the posture to enforcing it.

**Quotation correction.** An earlier draft of this section quoted §4.2 as "the
only reason to expect the next Phase-1-equivalent to hold". §4.2 reads, verbatim:
"the only reason to believe the next Phase-1-equivalent will hold". The
paraphrase never appeared in a committed revision; it is corrected here.

#### Deliberately NOT promoted

- **The remaining Phase 2 cohort** (WRK-01…WRK-06 and the session-determinism
  group). FG-2a's 20 assertions are the AFTER matrix and they passed, but
  promoting these rows requires mapping **each** registry row to its specific
  AFTER ids in `PHASE_2_WORKOUT_TEST_MATRIX.md` — a row-by-row reconciliation,
  not a bulk inference from one green suite. That is the next checkpoint.
- **WRK-07** and **WKA-04** are excluded outright: §4.1 already flags them with
  open regressions (`EC-11`, `EC-05`), and both are Dart error-contract halves
  no SQL assertion reaches. They stay until Wave 3B.
- **OBS-4-R1/R2/R3** — live-supported by FG-1's SP-1/SP-2/SP-4, but they sit
  inside a combined §4.1 row; splitting it belongs to the same row-by-row pass.
- **SEC-04 / SEC-R1 / SEC-R2 / SEC-R3 / F-J-01** — unchanged, OPEN. Nothing in
  this run touches them; migration 124 does not exist.
- **SEC-09** — **withdrawn from the promotion set by the owner ruling above.** FG-1's
  live half is done and recorded; the row waits on I-MIG-03's own closure.
- **I-MIG-03** — unchanged: CI-verified in records mode, enforcement deferred to 2A.
  Under the ruling above it is now also SEC-09's remaining gate.

---

### 7.10 Wave 2 P0 safety/authorization closure reconciliation — 2026-08-27 · evidence: CI run **#27** at `388b5c1`

Scope: the three Wave 2 P0 rows only — **SEC-R1 / F-J-01**, **SEC-R2 / F-J-17**,
**SEC-R3 / F-J-07**. No other row's status was examined or changed. This
reconciliation changed governance documents only.

#### The human-authority rulings, recorded as provided

The product owner ruled on 2026-08-27, in response to the `BLOCKED — AUTHORITY
REQUIRED` report raised at the preceding checkpoint. Recorded verbatim; not
reinterpreted.

1. **F-J-17 / SEC-R2 ruling: YES.** FJ17-7 satisfies the required §5.1 negative
   test.
2. **F-J-07 / SEC-R3 ruling: YES.** The 59/60/61 recovery threshold pair
   satisfies the required §5.1 negative/positive safety test.
3. **F-J-01 / SEC-R1 ruling: NO.** §5.1 does **not** apply to F-J-01. F-J-01 is
   governed as an authorization/security finding under SEC-R1.

**Where this ruling is recorded, and the gap.** It is recorded here, following
the in-repository precedent set by *"Owner ruling, 2026-08-25 — SEC-09's closure
criterion"* (§7.9) — the only established location for an owner ruling on
closure criteria. The repository has **no dedicated register for §5.1 / evidence
-sufficiency authority decisions**: `decision-log.md` is scoped to product and
architecture decisions ("why is it built this way?"), and
`MASTER_PRODUCT_DECISIONS.md` §2's discipline attaches to rows that exist in
that document — these rulings have none. **No new location was invented.** The
gap is reported for owner assignment.

#### The evidence — CI run #27

`33032108346` · head `388b5c16` · event `push` · conclusion **`success`** ·
2026-08-27T02:04:05Z. Every job and every step green: *Static guards* (incl.
I-MIG-03 durability guard, records mode; ENV-3 static contract), *API*,
*Flutter* (analyze + test + QA bundle scans), *Negative control* (harness
self-test; M-1/M-2/M-3 mutate → declared FAIL set → restore → 20/20; WKT-204),
and *Live QA suites* — **Live security suite**, **Live AI suite**, **Contract
suite**, **Live SQL evidence** (FG-1, FG-2a, FG-2b, **F-J-17**, **F-J-07**,
ENV-3 ledger). `live-evidence.sh` fails the step on any `FAIL` line and on a
missing report banner, so a green step means 0 FAIL with the report actually
produced — a connection error cannot read as a pass.

| Row | FIXED IN CODE | FIXED ON QA | VERIFIED LIVE | VERIFIED IN CI | VERIFIED END-TO-END | §2.1 class → required |
|---|---|---|---|---|---|---|
| **SEC-R1** | ✅ 124 | ✅ ledger 127 | ✅ d04 §8 + j04-04C | ✅ same run | n/a | Security / authorization → **4 of 4 present** |
| **SEC-R2** | ✅ 126 | ✅ ledger 127 | ✅ FJ17 8/8 | ✅ Dart class invariant | ❌ **absent** | AI / safety input → **4 of 5 present** |
| **SEC-R3** | ✅ 127 | ✅ ledger 127 | ✅ FJ07 10/10 | ✅ j03 inversion + Dart | ❌ **absent** | AI / safety input → **4 of 5 present** |

#### Promoted to `VERIFIED_CLOSED` — 1 row

| Row | From | Closing evidence at `388b5c1` |
|---|---|---|
| **SEC-R1** · `materialize_program_week` lost its authorization guard | `READY_TO_REMEDIATE` | Migration **124** restored the `can_act_on_program` wrapper over `materialize_program_week_engine`, re-`REVOKE`d from `PUBLIC, anon` and re-pinned `search_path`. The row's own *Tests* field is satisfied in both halves: `d04` §8 asserts the **class** — the five 116 wrappers read from the migration source at run time, not hand-copied — and with `KNOWN_OPEN = []` the exemption map is empty, so `materialize_program_week` is **probed and refuses**, the precise blind spot that let F-J-01 exist; the I-MIG-03 standing source guard runs in *Static guards*. `j04`-04C independently 403s an unrelated caller against a **real** foreign-owned program (week 99, non-destructive). §5.2's redefinition clause is met by FG-1 SP-4 (2/2 re-pinned) and SP-5 (0 EXECUTE to PUBLIC/anon). Owner ruling 3 above places the row in the **Security / authorization** class, whose four required states are all present |

**Retained limitation, recorded not waived.** SEC-R1's *Live QA* field names
three probes; two run. The positive legs — owning coach → 200, `service_role`
→ 200 — are asserted nowhere, so a wrapper that refuses *everyone* would be
indistinguishable from a correct one by the current evidence. §2.1's four
security states do not require the positive leg and §5.1's negative+positive
requirement was ruled inapplicable to this row, so this is a probe-completeness
limitation rather than a missing state — registered as **FG-3** below, in the
same form §7.8 used for SEC-05's retained limitation.

#### Deliberately NOT promoted — the missing evidence, exactly

- **SEC-R2 / F-J-17** and **SEC-R3 / F-J-07** — **one state short: VERIFIED
  END-TO-END.** Both are safety findings under §5.1 (PAR-Q risk and flags;
  recovery state), which places them in §2.1's **AI / safety input** class:
  *"all five. A safety input is never closed on source review"*. §2.1 closes
  with *"`VERIFIED_CLOSED` requires every state its class demands. There are no
  partial closures and no exceptions granted at implementation time"*, and §3
  step 12 repeats it. The owner's rulings 1 and 2 resolve the **shape of the
  §5.1 test** — the question that was escalated — and are honoured in full; they
  do not speak to the fifth state, and this reconciliation will not read a
  waiver into them. VERIFIED END-TO-END is Step 4 (End-to-End Product
  Verification), which is not authorized to begin. The consequence is
  structural, not incidental: **no safety finding in this programme can reach
  `VERIFIED_CLOSED` before Step 4 runs.**
- **SEC-04** — untouched. §7.8 held it on the F-J-01 blind spot, which SEC-R1's
  closure now resolves, so it is a **consequential promotion candidate**; it is
  outside the three rows this ruling authorizes and is **not** promoted here.
  Assigned to the next checkpoint.
- **I-MIG-03** — unchanged, open, records mode. The guard ran green in CI #27 but
  its own closure criterion is enforcement, Wave 2 task 2A. Under the
  2026-08-25 owner ruling it also remains SEC-09's gate; **SEC-09 unchanged**.
- Every other row — not examined.

#### Status-vocabulary gap — owner ruling required

SEC-R2 and SEC-R3 hold **four of five** states, and §2's status table has no
term for that position: `REMEDIATED` means *"not yet retested"* and
`RETEST_REQUIRED` means *"live assertion outstanding"*, and **both statements
are now false** for these two rows, while `VERIFIED_CLOSED` requires the fifth
state. Moving them to either would put a false evidence claim on the board, and
§2 of `QA_CLOSURE_STANDARD.md` forbids using the five states loosely in any
report or status board. Inventing a sixth status would be a governance decision
this session has no authority to take. **The rows therefore stay at
`READY_TO_REMEDIATE`** — an understatement, whose entry evidence (a wave ID)
remains true — with their full evidence recorded in the row and here. The owner
is asked to choose: (i) add a status to §2 for *"every state but END-TO-END"*,
or (ii) leave the rows understated until Step 4 closes them.

Note that §5 of this registry's summary table and the progress board's severity
table were **not** adjusted: neither was adjusted by the 23-row promotion at
`6d42b10` or the 3-row promotion at `2a8d0b6`, and changing the counting rule
here would be an invention. The discrepancy is pre-existing and is reported, not
silently fixed.

#### Follow-up evidence gap — recorded, NOT implemented

| ID | Gap | Covers | Suggested home |
|---|---|---|---|
| **FG-3** | Assert the **positive** legs of the 116 wrapper class: the owning coach → 200 and `service_role` → 200 for each of the five wrappers, so over-refusal is distinguishable from correct refusal | SEC-R1's *Live QA* field, third and second legs · the same limitation on the other four wrappers | Wave 2 (2A/2B), with the d04 §8 class work |

#### Board effect

`VERIFIED_CLOSED` **26 → 27** · `READY_TO_REMEDIATE` **180 → 179** · canonical
total **319** unchanged (37 + 48 + 24 + 179 + 4 + 27 = 319).

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc`
was not contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request
was issued to it. No migration was applied, reverted or pushed to any
environment. No QA write was performed by this reconciliation. The evidence
cited is CI run #27, which had already executed. This checkpoint changed
governance documents only.

---

### 7.11 PD-A05 ruling and F-J-12 reconciliation — 2026-08-27 · governance only

Scope: **`F-J-12` only**, plus the PD-A05 row it depends on. No other row's status was
examined or changed. No code, migration, test or environment was touched.

#### The ruling, recorded as provided

The product owner ruled on 2026-08-27:

- **PD-A05: OPTION (A)** — `decision_traces` reads are scoped to **subject + the subject's
  active coach + `admin`**. `content_manager` is **not** included.
- **M-1: `created_by` is RETAINED.** The option text was silent on this arm; the silence
  is resolved in favour of retention, on the auditability rationale — a coach must not
  lose the audit record of a decision they themselves made when a relationship ends.
- **M-3: correct the false sibling-policy premise in the governance record.** Sibling
  policies remain **separate decisions**; they are **not** changed by this ruling.
- **M-4: `F-J-12` is a SECURITY / AUTHORIZATION closure-class finding**, subject to the
  authoritative closure standard.

Recorded in `MASTER_PRODUCT_DECISIONS.md` (row `PD-A05` → `ANSWERED`, with the corrected
premise) and in `decision-log.md` (the answer, the *why*, and the accepted trade-off) —
the location `MASTER_PRODUCT_DECISIONS.md` §2 step 1 prescribes. This is the programme's
**first** `ANSWERED` decision row; the document's "nothing here is decided" banner is
qualified by a dated additive amendment rather than rewritten.

#### The premise correction (M-3), measured from the migrations

| Table | Migration | Subject arm | Coach arm | Staff arm |
|---|---|---|---|---|
| `predictions` | 095 | `subject_id = auth.uid()` | program ownership | `admin` + `content_manager` |
| `program_versions` | 093 | — | program ownership | `admin` + `content_manager` |
| `communications` | 096 | subject, `status='sent'` only | `coach_id = auth.uid()` | `admin` + `content_manager` |
| `intelligence_attribute_reviews` | 091 | — | — | `admin` + `content_manager` + `coach` |
| `decision_traces` | 089 *(the defect)* | subject + creator | none | `admin` + `content_manager` + `coach` |

**No sibling table uses `admin` alone**, and no sibling coach arm uses
`is_active_coach_of`. The claim to the contrary appeared in the PD-A05 row, in the
`F-J-12` row of §7.1, and in `QA_WORKSTREAM_J_AI_DECISION_INTEGRITY_REPORT.md`. The two
governance records are corrected in place. **Workstream J's report is frozen evidence and
is not rewritten** — the same treatment §7.9 gave Workstream N's superseded count. Its
premise is superseded by this section.

#### Implementation vs authorized policy — they do not match

| Read arm | 089 *(defect)* | **Option (a) — AUTHORIZED** | Applied migration **125** |
|---|---|---|---|
| subject | ✔ | ✔ | ✔ |
| `created_by` | ✔ | ✔ *(M-1)* | ✔ |
| active coach of subject | ✘ | ✔ | ✔ |
| `admin` | ✔ | ✔ | ✔ |
| **`content_manager`** | ✔ | **✘** | **✔ ← divergence** |
| any `coach` | ✔ **← the defect** | ✘ | ✘ *(removed)* |

**Migration 125 is option (b) plus the retained creator arm.** It is committed
(`992dafe`), applied to QA, and its live assertion is green — but it is **not the
authorized policy**. One arm too wide.

**125 is left unchanged, deliberately.** Reverting it would re-open F-J-12 — a live,
proven, health-adjacent disclosure hole on a project with self-serve coach signup — while
the correction is prepared; editing it in place would create a sixteenth instance of
`ENV-2`'s in-place-edit defect (`CRC-13`). 125 is a strict subset of 089 on every arm, so
the interim posture is never wider than what QA carried before it. The correction is a
**forward migration**, and it is **not authorized by this ruling** — see below.

#### Evidence by closure rung — SECURITY / AUTHORIZATION class (§2.1: four states)

Measured against the **authorized** policy, option (a):

| State | Present? | Basis |
|---|---|---|
| FIXED IN CODE | ❌ | No migration implements option (a). 125 implements (b) |
| FIXED ON QA | ❌ | QA carries (b) — ENV-3 ledger frontier 127, green |
| VERIFIED LIVE | 🟨 partial | The non-distinguishing arms are proven; the (a)-distinguishing arm is not asserted at all |
| VERIFIED IN CI | 🟨 partial | Same assertions, same gap |

Probe-by-probe, against the checklist in the authorization:

| Probe | Proven? | Where |
|---|---|---|
| Unrelated / non-authorized coach **cannot** read | ✅ | `j04`-04A invariant, with `relCount === 0` asserted as the control. CI run #27 |
| Unrelated client **cannot** read | ✅ | `j04`-04A invariant. CI run #27 |
| `anon` **cannot** read | ✅ | `d05` §1. CI run #27 |
| `admin` **can** read | ✅ | `j04`-04B — `p1-admin` carries `role='admin'` (`lib.mjs` `IDENT`), so this probes the admin arm and not a staff arm generally. CI run #27 |
| No client may write or delete a trace | ✅ | `d05` §3, incl. "not even an admin can hand-write a decision trace" |
| **Subject can read their own traces** | ❌ **not asserted anywhere** | — |
| **Active coach CAN read the subject's traces** *(positive leg)* | ❌ **not asserted anywhere** | — |
| **`content_manager` CANNOT read** *(option (a)'s distinguishing arm)* | ❌ **not asserted, and would FAIL today** | No `content_manager` fixture exists — `IDENT` holds exactly four identities: victim, attacker, coach, admin |
| **`created_by` can read** *(the M-1 arm)* | ❌ **not asserted anywhere** | — |
| **Policy durability** | ❌ **no rung exists** | The I-MIG-03 durability guard tracks *function* properties only — `auth-wrapper`, `search-path-pin`, `security-definer`. **RLS policies are outside its coverage entirely**, and Gate 0.14's wording does not name them. 125 itself `DROP POLICY … CREATE POLICY` under a **new name**; nothing would have caught a weaker replacement |

**The evidence that exists proves the defect is closed. It does not distinguish option (a)
from option (b) in either direction.** Every assertion currently green holds identically
under both.

#### Governance state

**`F-J-12` is NOT promoted and remains OPEN.** Two of four required states are absent and
two are partial. Under §2.1 — *"`VERIFIED_CLOSED` requires every state its class demands.
There are no partial closures and no exceptions granted at implementation time"* — and §3
step 12, the ruling alone closes nothing. **The standing rule that implementation does not
itself establish authorization is preserved and is now demonstrated in both directions:**
migration 125 existing did not authorize option (b), and PD-A05 being answered does not
close `F-J-12`.

**Board counts are unchanged.** `F-J-12` is a §7 P1 row and the register carries no
per-row status field; none is invented here. `MASTER_PRODUCT_DECISIONS.md` §2 step 3
("move every finding it blocked from `BLOCKED_DECISION` to `READY_TO_REMEDIATE`") is
**reported as not executable** for that reason, rather than approximated.

**PD-A05's answer also releases the decision dependency recorded on `E-04`, `E-16` and
`ENG-22`** (all cite D-7). Their rows are **deliberately not edited** — they are outside
the row this ruling names, and a follow-up reconciliation is the correct place for them.
`ENG-22` in particular should be re-examined once option (a) is implemented: it reads
under caller RLS and writes the explanation cache with **service role**, so a narrower
read arm changes its exposure materially.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No migration was applied, reverted or pushed to any environment. No QA write.
No test was run, added, weakened or rewritten. This checkpoint changed governance
documents only.

---

### 7.12 Run #32 evidence reconciliation — 2026-08-27 · evidence: CI run **#32** at `ae5be13`

The first fully green run since the Wave 2 P0 work began. Verified independently
against the GitHub API, not read off a dashboard: run **#32** `33040663330`,
head `ae5be138`, conclusion **`success`**, all five jobs green — and **step 11,
*Live SQL evidence*, executed for the first time since the QA frontier moved to
128.** Runs #30 and #31 never reached it: the steps are sequential and the AI
suite failed at step 9, so steps 10–11 were skipped. That is why this run
supplies evidence the two before it could not.

**This section changes the status of exactly one row.** A green run is not a
closure; `live-evidence.sh` says so in its own footer, and §4 of the closure
standard says it twice.

#### What run #32 executed

| Suite | Result |
|---|---|
| Live security (six suites, incl. `d05` §9) | pass |
| Live AI — J-01 7/7 · J-02 15/15 · J-03 8/8 · **J-04 16/16** · J-05 3/3 | **49/49** |
| Characterized defects still reproducing | **17/17** — none silently vanished |
| Contract suite | pass (with the allowlist — it proves the recorded-defect state, not closure) |
| FG-1 function search-path posture | 5/5 |
| FG-2a phase-2 workout contract · FG-2b plan day titles | 20/20 · 15/15 |
| F-J-17 PAR-Q contract · F-J-07 rule accumulator | 8/8 · 10/10 |
| **ENV-3 live ledger** | **5/5 — 129 declared = 129 observed · 0 missing · 0 undeclared · 0 stale · 0 holes in 000–128 · pending: none** |

No migration was applied by the run, nothing was written to `schema_migrations`,
every SQL suite rolled itself back, and production was not contacted.

#### Promoted to `VERIFIED_CLOSED` — 1 row

| Row | From | Closing evidence at `ae5be13` |
|---|---|---|
| **`F-J-12`** · `decision_traces` readable by every coach | OPEN | All four **SECURITY / AUTHORIZATION** states now present — the class was fixed by owner ruling **M-4**, and §2.1 requires exactly these four. **FIXED IN CODE**: migration 128. **FIXED ON QA**: ENV-3's live ledger at this run reconciles 129 = 129 through 128 with no hole, which retires the one inference §7.11 left open — 128's `schema_migrations` row is now *observed*, not assumed. **VERIFIED LIVE**: `content_manager` reads **0** rows where the identical probe read **90** at run #30 pre-128; unrelated coach 0; unrelated client 0; the subject reads 95/95 of their own; the active-coach and `created_by` arms proved positively in `d05` §9. **VERIFIED IN CI**: the same run, against #30's recorded red on the same assertion. §5.2's redefinition clause is met by the post-application catalog read-back (one SELECT policy, zero write policies, four arms, no `content_manager`); §5.2's *"test the class, not the instance"* clause is satisfied by owner ruling **M-3**, which scoped sibling policies as separate decisions rather than leaving them unconsidered |

**Retained limitations, recorded not waived.** (i) **RLS policies have no
durability guard.** The I-MIG-03 guard tracks *function* properties —
`auth-wrapper`, `search-path-pin`, `security-definer` — and Gate 0.14's wording
does not name policies. Nothing in this repository would notice a later
migration replacing this policy with a weaker one, which is F-J-01's exact
mechanism. (ii) J-04A's `created_by=neq` filter is NULL-rejecting, so a readable
`created_by IS NULL` trace would be invisible to that negative control; none is
readable under option (a), and J-04B's *"every trace names a subject and a
creator"* invariant holds, so there is no live weakening today.

#### Gate movement

- **Gate 2.6** — *"`decision_traces` reads are scoped to subject + active coach
  (+ admin if PD-A05 so decides) · live, with a probe coach holding zero
  relationships"* — **MET.** Run #32 satisfies the mechanism exactly: the probe
  coach's zero-relationship state is itself asserted, and PD-A05 decided admin
  **in** and `content_manager` **out**.
- **Gate 1.7** — *"a member can write `has_injuries`, `injury_locations`, a
  pregnancy and a postpartum state without error · live QA assertion"* —
  **MET**, re-confirmed by F-J-17's 8/8 at this run.
- No other gate row moved. **Gate 2 remains blocked** on 2.1 (Gate 1), 2.3 (the
  §4.2 regressions), 2.5, and 2.7–2.13.

#### Deliberately NOT promoted — the missing evidence, exactly

- **`SEC-R2` / F-J-17** and **`SEC-R3` / F-J-07** — unchanged. Their live
  evidence re-ran green (8/8, 10/10), which refreshes but does not extend it.
  Both remain **one state short: VERIFIED END-TO-END**, required by §2.1's
  *AI / safety input* class. Step 4 is not authorized, and §7.10's
  status-vocabulary gap is still open.
- **`ENV-3`** and **`SEC-11`** — **already `VERIFIED_CLOSED`** (2026-08-25,
  §7.9). Run #32 re-confirms them; there is nothing to advance. ENV-3's live
  ledger passing here is used as *evidence for F-J-12's FIXED ON QA rung*, not
  as a fresh closure.
- **`SEC-09`** — unchanged, `ALREADY_FIXED`. FG-1's 5/5 re-ran green, and under
  the owner ruling of 2026-08-25 that evidence is **necessary but not
  sufficient**: SEC-09 closes when **I-MIG-03** reaches `VERIFIED_CLOSED`.
- **`I-MIG-03`** — unchanged, and **escalated as an authority question**, not
  decided here. Its §4.2 mandate is a standing guard that no function carrying
  an authorization wrapper, a `search_path` pin or a security trigger may be
  redefined without carrying them forward. That guard now exists, is
  **fail-closed**, has `KNOWN_OPEN = []`, self-tests green, and passed at run
  #32 — so its *behaviour* is enforcing. But its `ci.yml` step is still titled
  *"records mode"*, and **no document in this repository states I-MIG-03's
  closure criterion**. Because closing it also closes SEC-09 by the standing
  owner ruling, this reconciliation will not infer that criterion. See §M of
  the accompanying report.
- **`SEC-04`** — still a consequential promotion candidate from SEC-R1's
  closure; outside the rows any ruling has named. Unchanged.
- **`E-04`, `E-16`, `ENG-22`** — their `D-7` dependency is discharged by
  PD-A05's answer; their rows are not edited here and await their own
  reconciliation. `ENG-22` should be re-examined on its merits now that the read
  arm is narrow: it reads under caller RLS and writes the explanation cache with
  **service role**.
- Every other row — not examined.

#### Board effect

`VERIFIED_CLOSED` **27 → 28**. **The status-count table on the progress board is
NOT adjusted**, and that is deliberate: `F-J-12` is a §7 P1 row and the P1–P3
register carries **no per-row status field**, so which bucket the count
currently holds it in cannot be determined from this repository. Inventing a
bucket to make an arithmetic line balance is exactly the failure this programme
exists to prevent. The gap is reported, and it is the same gap that made
`MASTER_PRODUCT_DECISIONS.md` §2 step 3 inexecutable in §7.11.

**Production statement (closure standard §6):** production
`nxdbooufqzkpslkcogxc` was not contacted. No migration was applied, reverted or
pushed to any environment. No QA write was performed by this reconciliation. The
evidence cited is CI run #32, which had already executed. This checkpoint
changed governance documents only.

---

### 7.13 ERR-1 / EC-01 closure — 2026-08-27 · evidence: CI runs **#33** `580932f` and **#34** `80f248e`

One row closes here. Nothing else was examined or changed.

#### The governing rule, cited before the promotion

- **Closure class.** Owner ruling 2026-08-27: EC-01 is **RELEASE / ENVIRONMENT** —
  an internal platform observability capability with no user-facing success
  state of its own. The ruling is explicitly confined to EC-01 and does **not**
  extend to EC-05 or any other error-contract / false-success finding.
- **`QA_CLOSURE_STANDARD.md` §2.1**, that class's row, verbatim:
  *"FIXED IN CODE · **VERIFIED IN CI** — an environment guard that is not
  mechanized is not a guard."* Two states, and no VERIFIED END-TO-END.
- **§3 step 12:** *"Mark `VERIFIED_CLOSED` only when §2.1's required states all
  exist."* §2.1 adds: *"There are no partial closures and no exceptions granted
  at implementation time."*
- **§2**, the definition this checkpoint had to satisfy: VERIFIED IN CI is
  *"An automated check **fails against the pre-fix tree and passes against the
  post-fix tree, in CI**."*

**On the tension with §2 of this registry**, whose status table gives
`VERIFIED_CLOSED`'s entry evidence as "VERIFIED LIVE **and** VERIFIED IN CI":
§3 step 12 routes closure through §2.1's *class* ladder, and the programme has
already applied that reading five times — **ENV-1, ENV-4, ENV-5, REL-3 and
TST-1** were all promoted in §7.8 on CI evidence with no VERIFIED LIVE rung,
because their class does not demand one. This closure follows that precedent
rather than creating a criterion.

#### Evidence, independently verified against the GitHub API

| | Run #33 | Run #34 |
|---|---|---|
| id | `33043897947` | `33081949579` |
| head | `580932fc1313…` | `80f248e5656d…` |
| conclusion | `success` | `success` |
| supplies | the **post-fix / behavioural** half | the **pre-fix / historical** half |

**Post-fix half (run #33).** `flutter analyze` and `flutter test` both green, so
the sink compiles in context and every assertion in `error_sink_test.dart`
passed — B0's gate, *"suites green; a deliberately-failed read appears in the
sink"*, together with the error object keeping its identity and a throwing sink
being unable to break its caller.

**Pre-fix half (run #34), which is what this checkpoint added.** The negative
control at `apps/mobile/tool/negative_control/ec23_negative_control.sh`, wired
as **step 7** of the negative-control job, and that step's conclusion is
**`success`**. Its exit status is reachable only through the whole chain:
baseline guard PASS → mutator inserts one `print()` beneath each of the seven
`reportError()` call sites and **refuses to continue unless exactly seven
anchors matched** → the harness independently recounts and requires exactly
**seven** offenders in `lib/` → the guard run exits **non-zero**, required by
`[[ "$RC" -ne 0 ]] || die` rather than tolerated → the output must contain the
named assertion `no print() call site remains in lib/`, so an unrelated compile
or test failure would `die` instead of passing → both files restored and
verified **byte-identical** by `git diff --quiet … || die` → guard PASS again.
Any link failing exits the step non-zero.

**This is not G-3 synthetic evidence and must not be filed as such.** G-3 covers
the case where *"no defective tree is recoverable from history"*. Here one is —
the seven `print()` call sites live at `fabf495` and every commit before
`580932f` — so this is a genuine pre-fix / post-fix demonstration of a guard.
G-3 was not invoked. `ci.yml`'s job header was amended in `80f248e` to say so,
precisely so this step is never later mis-filed alongside the WKT-204 and
M-1/M-2/M-3 steps, which *are* of that class.

**It also supersedes a weaker artefact.** §7.12's predecessor evidence for this
guard was a **local algorithmic replay** — the guard's logic run by hand against
`fabf495` (7 offenders) and the post-fix tree (0). That replay was honest but it
was not "in CI", and §2 requires "in CI". Run #34 replaces it. The replay is
recorded here as superseded, not deleted.

#### On the two red annotations in run #34 — they are not failed CI

The negative-control job carries two `failure`-level annotations, *"1 test
passed, 1 failed."* (EC-23, step 7) and *"3 tests passed, 4 failed."*
(WKT-204, step 6). **Every step of every job in run #34 is `success`**, and
there is **no `continue-on-error` anywhere in the workflow** (0 occurrences at
`80f248e`). These annotations are the runner's test-log parser reacting to
Flutter's stdout while the mutation is installed; the step conclusion, not the
annotation, is authoritative. The EC-23 figure is in fact a confirmed
*prediction*: the EC-23 group holds exactly two tests, the mutation was designed
to break exactly one of them and to leave `reportError` in place so the other
still passes — **one passed, one failed** is the declared outcome, observed.

**The real suite is independently clean.** The *Flutter — analyze, test, QA web
build* job is a separate job, its `flutter analyze` and `flutter test` steps are
`success`, and its annotation set contains **only** the Node-20 deprecation
warning — no test-failure annotation at all. Nothing is masked.

**Limitation, recorded.** Raw job logs return **HTTP 403** to an unauthenticated
read, so the assertion-level log text was not read directly. The evidence used
instead is stronger for this harness, not weaker: the step's exit status is
reachable only if every assertion above held, and the harness source was read at
the exact committed SHA that CI executed.

#### Promoted to `VERIFIED_CLOSED` — 1 row

| Row | From | Closing evidence |
|---|---|---|
| **`ERR-1` / `EC-01`** (= REL-26, LRE-27/28, **EC-23**) · P0 | `READY_TO_REMEDIATE` | Both states its RELEASE / ENVIRONMENT class demands: **FIXED IN CODE** (`580932f`) and **VERIFIED IN CI** in the strict §2 sense — fails against the pre-fix tree (#34 step 7) and passes against the post-fix tree (#33, and #34's baseline and restored runs) |

**`EC-23` closes with it**: §3 records it as an alias of EC-01, so it carries no
separate row and no separate count.

#### What this closure does NOT do

- **It does not touch `EC-05`.** The owner ruling is confined to EC-01 by its own
  terms; EC-05 remains governed by its own class, which requires VERIFIED
  END-TO-END for a user-facing success state.
- Phase **B0**'s remaining scope is unchanged: the §5.1 categories beyond
  category 1 are not wired, because classifying the ~234 swallow sites is
  **Phase B4**.
- No other row's status was examined. `I-MIG-03`/`SEC-09`, RLS-policy
  durability, the status-vocabulary gap, `SEC-04`, `E-04`/`E-16`/`ENG-22` and
  the CI step-ordering question are all untouched and remain open.

#### Board effect — mechanically reconciled, and one divergence retained

`ERR-1` is a **§6 P0 row that carries a status field**, so unlike `F-J-12` its
movement is mechanically countable and the table is updated:
`READY_TO_REMEDIATE` **179 → 178**, `VERIFIED_CLOSED` **27 → 28**, total
**319** unchanged (37 + 48 + 24 + 178 + 4 + 28 = 319).

**The narrative count is 29, and the table says 28. That divergence is exactly
`F-J-12` and it is deliberate**, carried forward from §7.12: `F-J-12` is a §7
P1 row and that register has **no per-row status field**, so which bucket the
table currently holds it in cannot be determined from this repository. It is
left uncounted rather than guessed at.

**Production statement (closure standard §6):** production
`nxdbooufqzkpslkcogxc` was not contacted. No migration was applied, reverted or
pushed. No QA write. The evidence cited is CI runs #33 and #34, which had
already executed. This checkpoint changed governance documents only.

---

### 7.14 `I-WRK-01` tracking home, `EC-11` dependency reconciliation, and the VERIFIED LIVE capability blocker — 2026-08-27 · governance only

Owner rulings **D-1 · D-2 · D-2(b) · D-2(c) · D-3 · D-4 · D-5**, 2026-08-27. **Documentation
only — no code, migration, test, policy, CI or acceptance criterion changed; no QA write;
no QA read; production not contacted.** No status was promoted and **no count was moved**.

#### D-1 · `I-WRK-01` now has a tracking home

Before this checkpoint `I-WRK-01` appeared exactly **once** in this registry — §3 line 167,
the alias map, which has no status column. It had no §6 row, no §7 row and no
progress-board row, so there was no legitimate place to record its evidence.

A **§7.6 row** is now established. Constraints applied:

* **Canonical key is `I-WRK-01`.** `H-01`, `M-07` and `M R-2` remain retired aliases (§3).
  **No `H-01` row was created and none may be**, per §3 (*"The alias must not be used as a
  tracking key after this document"*) and §10.5.
* **§6 was not used and could not be.** §6 is the **P0** register; this finding is P1/P2.
* **The row is evidence-only and is NOT status-countable.** §7's tables carry no per-row
  status field. This is the established position, not a new one: `REMEDIATION_PROGRESS.md`
  §3 already records that `F-J-12` is `VERIFIED_CLOSED` and *"is NOT in this figure … a §7
  P1 row and that register has no per-row status field, so its current bucket cannot be
  determined from this repository. Left uncounted rather than guessed."* The same applies
  here, and with more force: `I-WRK-01` is not closed at all.
* **Arithmetic unchanged.** §5 counts *canonical findings*, not rows — `I-WRK-01` was
  already inside the `Data Contract` domain's 33. Adding a row changes no total, and the
  progress board's status counts (37 + 48 + 24 + 178 + 4 + 28 = 319) are untouched. Which
  bucket currently holds `I-WRK-01` **cannot be determined from this repository and was not
  guessed.**

**Structural note, recorded because the ruling has wider reach than one finding.** Six
canonical findings sit in §3 with no row anywhere else in this registry — `I-LEG-03`,
**`I-WRK-01`**, `ENG-16`, `CON-06`, `CON-10`, `M-05`. (A seventh, `I-COM-03`, is covered by
the range row `I-COM-02`…`I-COM-06`.) D-1 was ruled for `I-WRK-01`; **the other five are
untouched and remain without a tracking home.**

#### D-2 / D-2(b) / D-2(c) · VERIFIED LIVE is required, and cannot currently be obtained

Closure class is **Data contract / schema**. `QA_CLOSURE_STANDARD.md` §2.1 requires
FIXED IN CODE · FIXED ON QA · VERIFIED IN CI · **VERIFIED LIVE where a read path exists**.
A read path exists (`getExerciseProgression()` → the strength-progression surface).
**D-2 refuses to waive it.** The ERR-1 / EC-01 RELEASE-ENVIRONMENT ruling was **not**
applied here; precedent forbids it anyway — SEC-R2 and SEC-R3 (§7.10) record that an owner
ruling on an adjacent question *"does not waive the fifth state"*.

**D-2(c)** requires the stronger comparison: the **actual read path** must fail against the
pre-fix tree and succeed against the fixed tree, on the same QA fixture. It was not
weakened, and no substitute was recorded as evidence.

**The comparison cannot be performed with the infrastructure this repository has.** The
architecture supports it; the capability does not. Established mechanically:

| Requirement | State |
|---|---|
| A mechanism that executes the real Dart service against a live project | **EXISTS** — `apps/mobile/integration_test/service_logic_test.dart` drives real service classes after `Supabase.initialize`, and post-ENV-4 `AppEnv` has no production default. `WorkoutService`'s `Supabase.instance.client` binding resolves correctly under it |
| A QA fixture for `workout_set_logs` | **REACHABLE IN PRINCIPLE** — `001:370` `"users manage own set logs" FOR ALL TO authenticated USING (user_id = auth.uid())`, so a fixture identity can insert and read its own rows. `supabase/tests/workout/phase2-contract.sql` already creates and rolls back `workout_set_logs` probe rows |
| **A CI job holding both a Flutter/Dart toolchain and a QA credential** | **DOES NOT EXIST.** `flutter` and `negative-control` have Flutter and **no** QA secret; `live-qa` holds `QA_URL`, `QA_ANON`, `QA_SERVICE`, `QA_DB_URL` and has **no** Dart toolchain. The two capabilities are in disjoint jobs |
| CI executing `integration_test/` | **DOES NOT** — the `flutter test` step runs with no path, which covers `test/` only; `integration_test/` additionally needs a device target |
| A local toolchain | **ABSENT** — no `flutter`/`dart` on the device VM or in the cloud container; both SDK archives return HTTP 000 (egress refused), re-verified 2026-08-27 |
| A local QA credential | **ABSENT** — `QA_URL`/`QA_ANON`/`QA_SERVICE`/`QA_DB_URL` all unset. Acquiring one was **not** attempted: D-2(b) authorizes a QA *write*, not credential acquisition |

**Minimum missing capability, stated so it can be authorized or refused as one item:** a CI
job that has a Flutter toolchain **and** a QA credential **and** a device target, running
`integration_test/` twice — once at `654b09c` and once at `654b09c^` — against one
rollback-scoped `workout_set_logs` fixture. Note that granting it widens QA credential
scope beyond the single job `ci.yml` currently confines it to, which is a security-boundary
change and was **not** made here.

`VERIFIED LIVE` is therefore recorded as **ABSENT**, and `I-WRK-01` stays
**NOT `VERIFIED_CLOSED`** with three of four required states present. §2.1 line 59 —
*"There are no partial closures and no exceptions granted at implementation time."*

#### D-3 · `EC-11`'s dependency reconciled

**Before:** §7.2's `EC-11` row carried `Dep` = **`H-01 first`**.
**After:** `Dep` = **`I-WRK-01` + `I-COM-01` + `I-CHK-01`**.

Two defects were corrected in one edit:

1. **Under-scoped.** `QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md:810` — *"closing EC-11's
   swallows before **H-01, H-02 and EC-10** converts silent empty states into permanent
   visible errors across the workout, event and check-in surfaces at once."* D-3 rules this
   the authoritative sequencing constraint.
2. **Retired alias used as a tracking key.** `H-01` is retired (§3:167); §10.5 closes the
   alias map. The cell is now written in canonical keys. This translation is compelled by
   §3, not chosen: `H-01` → `I-WRK-01`; `H-02` → `I-COM-01` (§3:168).

**`EC-10` needs a note, because it does not resolve to one canonical finding.** §3 splits it
across **`I-CHK-01`** (*checkins half*, §3:151) and **`I-LEG-03`** (*coach_tips half*,
§3:154). Workstream H's sentence names *"check-in surfaces"*, which maps to the checkins
half, so `I-CHK-01` is recorded. **Whether `I-LEG-03` also gates `EC-11` is NOT decided
here** and remains open.

**Two wider statements were left standing and not reconciled**, because D-3 authorized one
resolution and choosing between the remainder is a further ruling:
`QA_WORKSTREAM_H…:796` / `:868` gate `EC-11` on the whole **Wave H-A** batch (H-01, H-02,
H-03, H-05, H-06 client half — a set that does **not** contain EC-10), and
`MASTER_REMEDIATION_WAVES.md:260` states Wave 3B's prerequisite as **"3A complete (the H
dependency)"**, the widest statement in the programme and the only wave-level one.

**`EC-11` is not authorized to start.** `npm run test:contract` on this tree returns nine
allowlist entries — `checkins` (`I-CHK-01`, 7 sites), `coach_tips` (`I-LEG-03`),
`event_registrations.ticket_code` (`I-COM-01`), `custom_exercises.approved_by`,
`user_profiles.goal`, `user_profiles.equipment` and three `nutrition_logs` columns. **EC-11
was not started; `WorkoutService` was not touched.**

#### D-4 · Severity discrepancy — PRESERVED, NOT RESOLVED

Workstream I rates `I-WRK-01` **P1** (`…_I_DATA_CONTRACT_REPORT.md:740`); Workstream H rates
the same defect **P2** (`…_H_PRODUCT_INTEGRITY_REPORT.md:319`). §5 requires a departure from
a source rating to be recorded in the row — but here the two **source reports disagree with
each other**, so no rating is mechanically compelled. The row carries `P1/P2 ⚠`. **Owner
authority required.**

#### D-5 · Site-count discrepancy — PRESERVED, NOT RESOLVED

Workstream I states the count as both *"(Dart, 2 sites)"* (`:1132`) and *"(1 site)"*
(`:1239`). `MASTER_REMEDIATION_WAVES.md:241` and the landed implementation both say
**three** (`workout_service.dart:237,243,246`). Waves and implementation agree and the
workstream report contradicts itself, so the *fact* is settled — but §10.2 makes the A–N
reports frozen evidence (*"Update the row, not a report"*), so the report was **not
rewritten**. Recorded here instead.

*(Reconciling note: the guard-visible site count and the source-line count are different
measurements. `run.mjs` and H-G1 both key on the `.from(` line, so one call site with a
`select` and an `order` counts once to the guards and twice in source. This explains the
shape of the disagreement; it does not tell us which number either report intended.)*

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No migration was applied, reverted or pushed. **No QA write and no QA read were
performed** — the D-2(b) fixture authorization was not exercised, because the probe it
serves cannot be executed. The evidence cited is CI run **#35** `33092528474`, which had
already executed. This checkpoint changed governance documents only.

---

### 7.15 `I-WRK-01` VERIFIED LIVE closure — 2026-08-28 · evidence: CI run **#41** `33129000361` at `8843c33`

One row closes here. Nothing else was examined or changed. **Documentation only — no
application, SQL, migration, RLS, CI, fixture, probe or infrastructure file was touched; no
QA write and no QA read were performed by this checkpoint; production was not contacted.**

#### What this checkpoint supplies, and what §7.14 was missing

§7.14 (D-2 / D-2(c)) required the **actual read path** to fail against the pre-fix tree and
pass against the fixed tree **on the same QA fixture**, refused to waive it, and recorded
`VERIFIED LIVE` as **ABSENT** for one reason only: *"no CI job holds both a Flutter/Dart
toolchain and a QA credential"*, so the comparison **could not be executed**. Nothing about
the criterion is changed here. **The missing capability was built and run**, and run #41
supplies the one thing every prior checkpoint lacked — **the literal PRE-FIX runtime
observation**.

The closure class is unchanged: **Data contract / schema**, whose §2.1 ladder is
FIXED IN CODE · FIXED ON QA · VERIFIED IN CI · **VERIFIED LIVE where a read path exists**.
`getExerciseProgression()` is a read path, so the fourth rung was owed. **No waiver was
introduced, no exception was granted, and no closure criterion was modified.** The
`ERR-1`/`EC-01` RELEASE-ENVIRONMENT ruling was again **not** carried across, and the
SEC-R2 / SEC-R3 precedent (§7.10) — *an owner ruling on an adjacent question "does not
waive the fifth state"* — was again respected.

#### The mechanism, read at the committed SHA that CI executed

| Component | At `8843c33` |
|---|---|
| Job | `wrk01-live` · `ci.yml:448` · *"I-WRK-01 — live progression read path (pre-fix / post-fix)"* · `needs: [live-qa]` · `if: needs.live-qa.outputs.creds == 'true'` |
| Probe | `apps/mobile/integration_test/wrk01_progression_live_test.dart` — calls the **real** `WorkoutService().getExerciseProgression()`, not a replica |
| Driver | `apps/mobile/tool/negative_control/wrk01_live_probe.sh` under `xvfb-run`, Linux desktop target |
| Pre-fix tree | `PRE_FIX_REF=654b09c^` = **`acd2cc5`**, whose `workout_service.dart:237,243,246` still name `created_at`. A real defective tree exists in history, so **`G-3` was not invoked and this is not synthetic evidence** |
| Fixture | One `workout_set_logs` fixture keyed `WRK01-PROBE-$PROBE_RUN_ID`, written by the committed QA-only `is_demo` identity `p1-victim@qa.12circle.test` under `001:370` (*"users manage own set logs"*) |
| Credential posture | `wrk01-live` references **zero** `secrets.*`. All **18** `secrets.QA_*` references in the workflow remain confined to `live-qa` (`ci.yml:321`–`:437`, inside `live-qa`'s `304`–`447` span). **No `QA_SERVICE` and no direct database access were added to `wrk01-live`, and no new secret was introduced** |
| `continue-on-error` | **0 occurrences** in the workflow, so no step conclusion is masked |

#### Observed evidence — the literal marker lines

**PRE-FIX leg, at `acd2cc5`:**

```
WRK01-MARK FIXTURE present rows=4
WRK01-MARK SERVICE-CALLED getExerciseProgression
WRK01-MARK RESULT len=0
WRK01-MARK ASSERT-NONEMPTY FAIL
```

**POST-FIX leg, same fixture, same probe, at `8843c33`:**

```
WRK01-MARK FIXTURE seeded rows=4
WRK01-MARK SERVICE-CALLED getExerciseProgression
WRK01-MARK RESULT len=3
WRK01-MARK ASSERT-NONEMPTY PASS
WRK01-MARK ASSERT-ALL PASS
```

**Cleanup:**

```
WRK01-MARK CLEANUP verified remaining=0
```

Run-level: all six jobs `success`; `wrk01-live` steps 1–7 all `success`.

#### Observed evidence versus conclusion — stated separately, because §2 turns on it

**Observed** (the marker lines above and the run/job/step outcomes): the same four fixture
rows were present to both legs · both legs reached the real `getExerciseProgression()` ·
the pre-fix call **returned** `[]` rather than throwing · the non-empty expectation is the
assertion that **failed** pre-fix · the post-fix call returned **3** progression points and
every assertion passed · **0** fixture rows survived teardown.

**Concluded from it** — and labelled as conclusion, not as observation: the defect was in
the column name the service read and nothing else, because only the tree changed between
the two legs; and policies, grants, triggers and PostgREST **compose** as §2 says VERIFIED
LIVE proves, because a real request against QA reproduced the correct behaviour where the
identical request against the pre-fix tree did not.

**Not claimed.** §2 is explicit that VERIFIED LIVE *"does not prove … that the user-facing
path reaches it, or that no collateral regression occurred."* **`VERIFIED END-TO-END` is
NOT claimed for `I-WRK-01`** — no human or driver reached the strength-progression surface,
and its class does not require one.

#### Evidence provenance, recorded

The **repository-side** facts in this subsection — the job definition, the probe source,
the pre-fix ref and its `created_at` references, the discrimination gates, the guard state,
the credential posture and the absence of `continue-on-error` — were read directly at
`8843c33` when this subsection was written.

The **run-side** facts — the run and job ids, the step outcomes and the literal marker
lines — were **transcribed by the product owner from the raw job log** retrieved with
repository admin credentials (`gh run view 33129000361 --job 98714155399 --log`). Raw job
logs return **HTTP 403** to this programme's unauthenticated read, exactly as recorded in
§7.13's limitation note. The owner supplied them as authoritative runtime evidence. **They
were not inferred**, and the alternatives that *would* have been inference were explicitly
refused at the gate: the job conclusion, the green run summary, the
*"2 tests passed, 1 failed"* check-run annotation, the harness's fail-closed control flow,
source inspection of the probe, and the post-fix result were each rejected as substitutes
for the PRE-FIX observation before it was supplied.

#### The discrimination that makes the pre-fix leg evidence rather than noise

`wrk01_live_probe.sh:149–163` gates the pre-fix leg with eight assertions, each of which
aborts the job. Recorded because it is what separates *"the fix works"* from *"the runner
was broken"*: the pre-fix run must have initialised Supabase (`BOOT ok`) and authenticated
(`AUTH ok`); it must have seen the **same** fixture (`FIXTURE present rows=4`); it must have
reached the real service (`SERVICE-CALLED getExerciseProgression`); it must have **returned**
rather than thrown (`RESULT len=`), because a throw is not the historical signature; it must
have returned **empty** (`RESULT len=0`), or the harness `die`s on the grounds that a pre-fix
tree returning data is not evidence; the failing assertion must be the **non-empty** one
(`ASSERT-NONEMPTY FAIL`); and `PRE_RC` must be non-zero, because *"a pre-fix tree that passes
is not evidence."* This is context for the observed lines, **not a substitute for them**.

#### Promoted to `VERIFIED_CLOSED` — 1 row, uncounted

| Row | From | Closing evidence |
|---|---|---|
| **`I-WRK-01`** (= `H-01`, `M-07`, `M R-2` — retired aliases, §3) · §7.6 · P1/P2 ⚠ | NOT `VERIFIED_CLOSED`, three of four states | All four **Data contract / schema** states: **FIXED IN CODE** (`654b09c`) · **FIXED ON QA** (`logged_at` present in QA's live catalog, §7.6) · **VERIFIED IN CI** (run #35, both allowlist halves removed and checked in both directions) · **VERIFIED LIVE** (run #41 — pre-fix `RESULT len=0` / `ASSERT-NONEMPTY FAIL`, post-fix `RESULT len=3` / `ASSERT-ALL PASS`, one fixture, real service, `CLEANUP verified remaining=0`) |

#### Board effect — no count moved, and the divergence widens by one

**`I-WRK-01` is a §7 P1 row and the P1–P3 register carries no per-row status field**, so its
movement is **not** mechanically countable. This is the `F-J-12` position (§7.12,
`REMEDIATION_PROGRESS.md` §3) and D-1 already applied it to this row. The status table is
therefore **deliberately NOT adjusted**: `37 + 48 + 24 + 178 + 4 + 28 = 319`, unchanged. §5
counts canonical findings rather than rows, and `I-WRK-01` was already inside the Data
Contract domain's 33, so no domain total changes either. Which bucket the table currently
holds `I-WRK-01` in **cannot be determined from this repository and was not guessed.**

The narrative `VERIFIED_CLOSED` figure moves **29 → 30**, and the table still says **28**.
**The divergence is now exactly two rows — `F-J-12` and `I-WRK-01` — and it is deliberate**,
for the same reason in both cases. It is disclosed on the progress board rather than
resolved by a guess.

#### What this closure does NOT do

- **`EC-11` is not started and `WorkoutService` was not touched** — `catch (` count remains
  **14**. `EC-11`'s `Dep` cell is unchanged and still reads `I-WRK-01` + `I-COM-01` +
  `I-CHK-01` (D-3); **two of its three dependencies remain open**, so satisfying one does
  not release it.
- **`H-02` / `I-COM-01` is not continued and not closed.** Its closure class has never been
  ruled and remains an open authority question.
- **`D-4` and `D-5` remain unresolved** and are carried forward unchanged. The severity
  disagreement (Workstream I **P1** / Workstream H **P2**) and the self-contradictory site
  count are preserved, not resolved: closure on the evidence ladder does not settle either,
  and §10.2 keeps the A–N reports frozen.
- **No closure criterion, status vocabulary, tracking model or acceptance criterion was
  modified**, and **no waiver was introduced**.
- No other row's status was examined. `I-COM-02`, `I-CHK-01`, `I-LEG-03`, `EC-10`, `SEC-04`,
  `I-MIG-03`/`SEC-09` and the remaining five findings without a tracking home (§7.14) are
  untouched and remain open.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it.
No migration was applied, reverted or pushed to it. No Edge Function was deployed to it. The
linked project remained `eyqtldjqpgpljlqvpowh` throughout. The QA writes cited are those of
run #41's own fixture lifecycle under the D-2(b) authorization, which had already executed
and which proved its own teardown; **this checkpoint performed no QA write and no QA read**
and changed governance documents only.

---

### 7.16 `PD-A23` answered and `UIX-1` / `M-03` remediated — 2026-08-28 · owner rulings + Wave 3A task 3A-8

Two owner rulings and one implementation. **No migration, schema, RLS, Edge Function,
credential, secret or CI change; production not contacted; no QA write and no QA read.**
No status count was moved and **nothing is promoted to `VERIFIED_CLOSED`.**

#### The two rulings, recorded before anything was built

- **`PD-A23` = option (b)**, product owner, 2026-08-28, owner column **engineering**.
  Drop the PostgREST embed; read coach profiles in a second query against
  `public_profiles`; join in Dart; **no migration**; option (a) not implemented.
  Recorded in [`decision-log.md`](decision-log.md) and the register row marked
  `ANSWERED`, per `MASTER_PRODUCT_DECISIONS.md` §2 steps 1 and 2. Step 3 is a no-op —
  `UIX-1` was already `READY_TO_REMEDIATE`, never `BLOCKED_DECISION` — and step 4 is the
  progress-board entry accompanying this subsection.
- **`UIX-1` / `M-03` closure class = PRODUCT INTEGRITY / UI REACHABILITY**, product
  owner, 2026-08-28. §2.1's row verbatim: *"FIXED IN CODE · VERIFIED IN CI · VERIFIED
  END-TO-END (a human or a driver reached the surface)"*. The ruling states that
  `FIXED ON QA` and `VERIFIED LIVE` are **not** part of this class, and neither is
  claimed. **This is the first closure class this programme has assigned to a row before
  its remediation rather than after**, and it was requested precisely because the
  §7.15 experience showed the rung question is owner-reserved.

**Why the class was not inferred.** The prior gate established that no document assigned
one: every explicit assignment in this repository — `EC-01` (RELEASE / ENVIRONMENT),
`F-J-12` (SECURITY / AUTHORIZATION, ruling M-4), `I-WRK-01` (Data contract / schema,
ruling D-2) — came from an owner ruling, never from a domain heading. §5's fourteen
*domains* and §2.1's eight *classes* are different taxonomies and no rule maps one to the
other; `EC-01` sits in the Error Contract domain and was ruled RELEASE / ENVIRONMENT.

#### Root cause, read from the migrations

`000_baseline_preexisting_tables.sql:237` —
`coach_client_relationships_coach_id_fkey FOREIGN KEY (coach_id) REFERENCES auth.users(id)`.
PostgREST resolves an embedded resource through a foreign key and **cannot traverse one
whose target is outside the `public` schema**, so `coach:coach_id(...)` was answered
`PGRST200` before any row was read. Workstream M recorded the live error and the
embed-free control returning the client's real active relationship (`…_M_…REPORT.md`
§M-03) — that is the BEFORE state, and it is frozen evidence under §10.2.

**The FK is the only one of its kind that the client embeds.** Derived from the migration
set: **134** foreign-key pairs; every other embedded column in `apps/mobile/lib`,
`apps/api/src` and `supabase/functions` resolves into `public` — `coaching_calls.coach_id`,
`classes.coach_id`, `community_posts.user_id`, `post_comments.user_id`,
`accountability_pods.coach_id`, `coach_reviews.client_id`, `weekly_checkins.user_id` and
`coach_team_members.member_id` all reference `public.user_profiles`. **`checkin_screen.dart:118`
carries the identical `coach:coach_id(...)` spelling and is NOT a defect** — its FK lands in
`public` — so it was not touched, and no allowlist entry was needed for it.

#### The guard — built because the existing one is blind by construction

Workstream M's own §10 recorded the gap: *"there is no test asserting that a screen's query
shape matches the live schema, which is exactly the class of bug M-02/M-03/M-04/M-07/M-09
belong to."* Two structural reasons the schema-contract guard could not see this one:

1. `run.mjs`'s `selectColumns()` drops bracketed spans whole, because they are an embedded
   resource's own column list — so the embed head was never examined.
2. Its select matcher reads **one string literal**. Dart concatenates adjacent literals, and
   this defect was written across three of them, so only `'coach_id, status, pending_at,
   activated_at, '` was ever parsed.

The guard added closes both, and closes them for the **class**, not the instance:

| Piece | Where |
|---|---|
| `deriveForeignKeys()` — replays `ALTER TABLE … FOREIGN KEY` and column-level `REFERENCES` in file order, returning the referenced schema and table | `supabase/tests/contract/schema.mjs` |
| `selectSpecJoined()` — joins adjacent string literals across the whole `.select(…)` argument. **Used only by the embed check**; the column check's input is deliberately unchanged, so no existing verdict moves | `supabase/tests/contract/run.mjs` |
| `embedHeads()` + the check — every head spelled `alias:column` or a bare column must resolve through a FK whose target schema is `public`. A head spelled `relation!hint` names the relation and is covered by the existing relation pass | `supabase/tests/contract/run.mjs` |
| Self-test — two anchors read from the migrations (`coach_client_relationships.coach_id` must be `auth`, `coaching_calls.coach_id` must be `public`). A guard that silently parsed nothing would otherwise pass forever (§4) | `supabase/tests/contract/run.mjs` |

It is **offline and deterministic**: it contacts no environment, reads no credential, and
derives everything from `supabase/migrations` and the source tree. It is implemented inside
the existing contract suite, so **no CI change was made**; its CI invocation is
`npm run test:contract` at **`ci.yml:399`, inside the `live-qa` job**, and that step is
**credential-gated** — `if: steps.creds.outputs.present == 'true'`. The suite being offline
and its invocation being credential-gated are separate facts, and both are stated here
because the second one bounds when the guard actually runs. Whether it should remain so
gated is a **Gate B** design question and is **not decided here**.

#### Pre-fix / post-fix evidence — the guard's own demonstration

Both legs run the **same** guard; only `booking_screen.dart` differs. The pre-fix leg used
the file exactly as committed at `f109f19`, restored byte-identically afterwards
(`bd57f50092d8e5af` before and after).

**PRE-FIX — `f109f19`'s `booking_screen.dart`, exit status 1:**

```
  FAIL   embed    coach_client_relationships.coach_id is embedded but no foreign key reaches the public schema
           at apps/mobile/lib/features/booking/presentation/booking_screen.dart:55 (embed 'coach:coach_id' -> auth.users)

FAIL  1 contract violation(s)
```

**POST-FIX — the remediated file, exit status 0:**

```
Schema contract guard — 91 tables + 5 views + 134 foreign keys derived from supabase/migrations
…
PASS  no unknown relation or column outside the 9-entry known-violations allowlist
```

**The nine allowlist lines are byte-identical in both legs** — `checkins`, `coach_tips`,
`custom_exercises.approved_by`, `event_registrations.ticket_code`, `user_profiles.goal`,
three `nutrition_logs` columns and `user_profiles.equipment`. No other finding's evidence
moved, and `known-violations.json` was not edited.

**Observed versus concluded, stated separately.** *Observed:* the two guard runs above and
their exit statuses; the 134 FK pairs and the two anchor targets; the nine unchanged
allowlist lines. *Concluded:* that the remediated screen will now resolve coach profiles
live — which is a conclusion, not an observation, and is exactly what the class's
VERIFIED END-TO-END rung exists to test.

**Limitation, recorded and not worked around.** Both legs above are **local** runs. §4 is
explicit that *"a passing suite that has never run in CI"* is not a closure, so
**VERIFIED IN CI is recorded as PENDING, not satisfied**. CI run **#43** has since supplied
the **post-fix leg** and nothing more; the **pre-fix leg has never executed in CI** and is
outstanding. See the Correction below. There
is also **no Dart or Flutter toolchain** on the device or in the cloud container (SDK
archives return HTTP 000, re-verified 2026-08-28), so `flutter analyze` and `flutter test`
could not run and **the Dart edit has not been compiled**. Brace, paren and bracket balance
was checked mechanically as a floor, which is not a substitute for the analyzer.

#### Correction, 2026-08-28 — where the guard actually runs, and run #43's scope

**Additive. Nothing above is rewritten as though it had always read this way**; the three
affected sentences carry their own inline correction markers, and this block is the record
of what changed and why.

**What the prior record said.** Three statements introduced by this checkpoint claimed the
new embed guard *"runs inside `npm run test:contract`, already wired to the `static-guards`
job, so no CI change is needed"*, and that VERIFIED IN CI stayed PENDING only *"until
`static-guards` executes on this tree"*. The progress-board row carried the same claim.

**What the repository actually shows, read at `527438a`.**

| | |
|---|---|
| Invocation | `npm run test:contract` at **`ci.yml:399`** |
| Owning job | **`live-qa`** — *"Live QA suites (security / AI / contract)"*, `needs: [static-guards]`, `environment: qa` |
| Step condition | **`if: steps.creds.outputs.present == 'true'`** |
| `static-guards` | contains **no** contract step — its steps are the production-ref guard, migration hygiene, the I-MIG-03 records-mode guard, the ENV-3 declaration, the Edge-Function JWT posture check and the ENV-4 check |

**Why the distinction matters, stated plainly.** `creds` is computed from `QA_URL`,
`QA_ANON` and `QA_SERVICE`. When they are absent the step **skips**, and a skipped step
leaves its job green — the workflow already emits a `::notice` saying the live suites were
skipped. The prior wording described an unconditional static gate that runs on every push;
the guard is in fact **conditional on QA credentials being provisioned**. That is the §4
concern — *"A guard nobody runs protects nobody"* — and recording a conditional guard as an
unconditional one overstates the standing protection behind `UIX-1`. The same class of
mis-attribution was corrected once before in this registry, in `I-WRK-01`'s FIXED ON QA
clause (§7.6, 2026-08-27), and is corrected the same way here.

**What is NOT changed by this correction.** The guard's code, its offline character, its
pre-fix/post-fix behaviour, `PD-A23` option (b), the PRODUCT INTEGRITY / UI REACHABILITY
closure-class ruling, the observed-versus-concluded split, the §6 production statement, and
every count. **`UIX-1` remains `REMEDIATED`, not `VERIFIED_CLOSED`**; `VERIFIED_CLOSED`
stays **28** and the canonical total stays **319**. No unrelated row was examined.

#### CI run **#43** at `527438a` — what it establishes, and what it does not

Owner-supplied: run **#43**, *"fix(UIX-1): read booking coach profiles from public_profiles
(PD-A23 b)"*, **Success**, with all six jobs green — *Static guards*, *Flutter — analyze,
test, QA web build*, *API — unit + e2e*, *Negative control*, *Live QA suites*, and
*I-WRK-01 — live progression read path*. Repository-side facts below were read at
`527438a`; the run outcomes were transcribed by the product owner, as in §7.15.

**Established.**

- **The Dart edit compiles in context.** The `flutter` job's steps are sequential and the
  workflow carries **0 `continue-on-error`** at `527438a`, so a green job means
  `flutter analyze`, `flutter test` and `flutter build web` all succeeded. Precision worth
  keeping: the step is `flutter analyze --no-fatal-infos --no-fatal-warnings`
  (`ci.yml:22`), so this is *no analyzer **errors***, not *no lints*.
- **The post-fix CI leg of the guard.** `live-qa` green with the Contract-suite step
  reached — inferred, and labelled as inference, from `wrk01-live` being green rather than
  skipped, since that job's own `if: needs.live-qa.outputs.creds == 'true'` can only be
  true when the same `creds` gate the Contract step uses is true. A **step-level**
  conclusion would settle it directly and was not obtainable: raw job logs and the run API
  both return **HTTP 403** to this programme's read.
- **No unrelated scope moved.** `527438a` changed **0** files under `.github`,
  `supabase/migrations`, `supabase/functions`, `config.toml`, `apps/api` and
  `dart_defines`, and `known-violations.json` is untouched — the nine allowlist entries are
  unmoved.

**NOT established — and this is the reason the rung stays shut.** §2 defines VERIFIED IN CI
as a check that *"**fails against the pre-fix tree** and passes against the post-fix tree,
**in CI**."* Run #43 exercised the guard against the **post-fix** tree only, where there is
no embed defect to find. **The guard's discrimination was not exercised in CI**; what ran
were its two self-test anchors — `coach_client_relationships.coach_id` must resolve to
`auth`, `coaching_calls.coach_id` to `public` — which prove the parser is not silently
parsing nothing (the §4 floor) but are not a pre-fix failure. The pre-fix leg exists only
as a local run, and §7.13 has already ruled on precisely that: a local replay *"was honest
but it was not 'in CI', and §2 requires 'in CI'."*

**Consequently: run #43 is valid post-fix evidence and is retained as such. The pre-fix CI
leg is outstanding.** Supplying it is **Gate B** — a `ci.yml` change and a negative-control
harness of the `ec23_negative_control.sh` shape, against a real recoverable defective tree
(`f109f19`'s `booking_screen.dart`, so **`G-3` would not be invoked**) — and **Gate B was
not started, designed or authorized here.**

**`VERIFIED END-TO-END` is unaffected.** It is not a CI state and no run can supply it: the
class requires *"a human or a driver reached the surface"*, and Step 4 is not authorized to
begin (§7.10). It remains **ABSENT**, with no waiver and no substitute.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it.
No migration was applied, reverted or pushed to it. No Edge Function was deployed to it.
The linked project remained `eyqtldjqpgpljlqvpowh` throughout. The evidence cited is CI run
#43, which had already executed. **No QA write and no QA read were performed by this
correction**, and it changed governance documents only.

#### What this checkpoint does NOT do

- **`VERIFIED END-TO-END` is absent and `UIX-1` is NOT `VERIFIED_CLOSED`.** Step 4 is not
  authorized to begin (§7.10), and the structural consequence recorded there for SEC-R2 and
  SEC-R3 applies here too: a row in a class that terminates END-TO-END cannot close before
  Step 4 runs. No waiver was sought and no substitute was recorded.
- **No status count was moved.** `UIX-1` is a §6 P0 row and therefore *is* mechanically
  countable — unlike `F-J-12` and `I-WRK-01` — but it moved from `READY_TO_REMEDIATE` to
  `REMEDIATED`, and §2's table counts neither transition as a closure. `VERIFIED_CLOSED`
  stays **28** and the canonical total stays **319**.
- **`EC-11` not started; `H-02` / `I-COM-01` not continued; `I-WRK-01` not reopened.**
  `workout_service.dart` untouched, `catch (` count **14**.
- **`checkin_screen.dart` not touched.** Its embed resolves and is not a defect.
- **`D-4` and `D-5` unchanged.** The remaining Wave 3A tasks — 3A-1/2/3 (`I-NUT-01`,
  `I-INT-01`, `F-J-04`), 3A-4, 3A-6, 3A-7, 3A-9/10/11 — were not examined or started.
- **No other row's status was examined.**

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it.
No migration was applied, reverted or pushed to it. No Edge Function was deployed to it —
`ENV-7` remains `BLOCKED_ENVIRONMENT` and deliberately undeployed. The linked project
remained `eyqtldjqpgpljlqvpowh` throughout. **No QA write and no QA read were performed by
this checkpoint**; every run cited above is offline.

---

### 7.17 `UIX-1` / `M-03` VERIFIED IN CI — 2026-08-28 · evidence: CI run **#44** `33172886167` at `b1a19ae`

One rung opens here. **Nothing is promoted to `VERIFIED_CLOSED`, no count moves, and no
governance rule is reinterpreted.** Gates B-1 and B-2 landed in `b1a19ae`
(`ci(UIX-1): add pre-fix negative control and unconditional contract guard`); this
subsection records what the first run of that tree established.

#### The owner ruling this rung turned on

§7.16 recorded `VERIFIED IN CI` as **PENDING** because run #43 met the embed guard only on
the fixed tree, and §2 requires a check that *"**fails against the pre-fix tree** and passes
against the post-fix tree, **in CI**"*. Raw job logs return **HTTP 403 "Must have admin
rights to Repository"**, so the question was which evidence standard governs a harness whose
output cannot be read.

**Owner ruling, 2026-08-28: §7.13's entailment standard governs.** §7.13 closed `ERR-1` on
exactly this shape and stated the position verbatim — the step's exit status *"is reachable
only if every assertion above held, and the harness source was read at the exact committed
SHA that CI executed"*, which it called **stronger for this harness, not weaker**. The
ruling is confined to this rung. **It does NOT disturb §7.15**, where the literal marker
lines were required for `I-WRK-01`'s VERIFIED LIVE and the fail-closed control flow was
explicitly refused as a substitute; that refusal stands, and the two rungs are not the same
question.

#### B-2 · the contract guard is now unconditional

`npm run test:contract` moved out of `live-qa`, where it sat behind
`if: steps.creds.outputs.present == 'true'`, into `static-guards`, where it has no `if` at
all. **Not duplicated** — `live-qa` at `b1a19ae` contains **0** occurrences of
`test:contract`, and a comment there records the move. The suite is offline: it imports only
node builtins and `./schema.mjs`, reads **no** environment variable, and ran in
`static-guards` with no `npm ci`.

Why it mattered, recorded because it bounded the guard's reach: `known-violations.json` is
the both-directions record for **`I-WRK-01`, `I-INT-01`, `I-INT-02`, `I-COM-01`, `I-COM-03`,
`I-CHK-01`, `I-LEG-03` and `I-NUT-01`**, and behind the old gate none of them was checked on
a run without QA secrets, with nothing going red to say so — `QA_CLOSURE_STANDARD.md` §4,
*"A guard nobody runs protects nobody."* **`secrets.QA_*` references fall 18 → 15**: the step
no longer receives credentials it never read. That is a narrowing of credential exposure; no
secret was added, rescoped or widened.

**Evidence produced under the old placement is preserved as historical and conditional and
is NOT retroactively reinterpreted.**

#### B-1 · the pre-fix harness

`apps/mobile/tool/negative_control/uix1_negative_control.sh`, wired as **step 8** of the
`negative-control` job, whose checkout gained `fetch-depth: 0` so the pre-fix blob is
reachable. It follows `ec23_negative_control.sh`: install the pre-fix file, require the
declared failure, restore byte-identically, require the pass again.

#### Observed versus entailed — stated separately, because the ruling turns on it

**Directly observed** (GitHub API, job and **step** level):

| | |
|---|---|
| Run | **#44** `33172886167`, attempt 1, head `b1a19ae9`, **`completed` / `success`** |
| Jobs | all **six** `success` — Static guards · Flutter · API · Negative control · Live QA suites · I-WRK-01 live probe |
| Post-fix leg | `static-guards` **step 7** *"Schema contract guard (relations, columns, embedded resources)"* → `success` |
| Pre-fix leg | `negative-control` **step 8** *"UIX-1 — embed/FK contract guard, pre-fix / post-fix evidence"* → `success` |
| Masking | **0** non-success steps, **0** skipped steps, **0** `continue-on-error` occurrences in the workflow |
| Unconditionality | the `static-guards` step's YAML keys at `b1a19ae` are exactly `name` and `run` — **no `if`** — and the job carries no job-level `if`. A skipped step reports `skipped`; this reported `success` |
| `f109f19` | `git merge-base --is-ancestor f109f19 b1a19ae` is true, and that tree's `booking_screen.dart` carries the `coach:coach_id(` embed |

**Entailed from the step's exit status and the harness source read at the executed SHA — a
conclusion, not an observation.** Under `set -euo pipefail` with a `die` on every branch,
exit 0 is reachable only if: the tree was clean; `git cat-file -e f109f19:<path>` succeeded,
so `fetch-depth: 0` worked; the baseline run passed; the installed file carried
`coach:coach_id(` **and** differed from the committed one, so the real pre-fix screen was
installed; the pre-fix run exited **non-zero**; its output contained the literal assertion
*"coach_client_relationships.coach_id is embedded but no foreign key reaches the public
schema"*; **no other `FAIL` line was present**, so an unrelated defect could not be laundered
into UIX-1 evidence; the restore passed `git diff --quiet`; and the post-fix run exited 0.

**Limitation, recorded not waived: the harness's own output was never read.** Raw job logs
return HTTP 403 to this programme, exactly as §7.13 recorded for run #34.

#### `G-3` is NOT invoked

`f109f19` is a real commit in this branch's history carrying the actual defect, so a
defective tree is **recoverable** and this is genuine pre-fix evidence. G-3 covers the case
where no defective tree is recoverable. The harness header and the `ci.yml` step comment both
say so, so this step is never mis-filed beside the **WKT-204** and **M-1/M-2/M-3** steps,
which *are* of that synthetic class.

#### The red annotations under the green jobs are not failed CI

`negative-control` carries `[failure] 1 test passed, 1 failed.` (**EC-23**) and
`[failure] 3 tests passed, 4 failed.` (**WKT-204**); the `I-WRK-01` job carries
`[failure] 2 tests passed, 1 failed.` — its probe's own expected pre-fix shape. These are the
runner's Flutter test-log parser reacting to those harnesses' installed mutations, the same
reading §7.13 established for run #34. **Every step of every job in #44 is `success` and the
workflow contains no `continue-on-error`.** **None of them relates to UIX-1**: its guard is a
node script, whose output is never parsed into a test annotation. The remaining annotations
are the Node-20 deprecation warning.

#### Rung movement — one rung, no promotion, no count

| Row | Rung | From | To |
|---|---|---|---|
| **`UIX-1`** / `M-03` · §6 · P0 · class **PRODUCT INTEGRITY / UI REACHABILITY** | VERIFIED IN CI | PENDING | **PRESENT** (run #44) |

**`VERIFIED END-TO-END` remains ABSENT.** It is not a CI state — §2.1 requires *"a human or a
driver reached the surface"* — and Step 4 is not authorized to begin (§7.10). No CI result
can supply it, none was substituted, and no waiver was created. **`UIX-1` is NOT
`VERIFIED_CLOSED`**: two of three class states present.

**No count moves.** `VERIFIED_CLOSED` stays **28** and the canonical total stays **319**
(37 + 48 + 24 + 178 + 4 + 28). `M-03` was `REMEDIATED` before this checkpoint and is
`REMEDIATED` after it: §2's status table has no term for *"every state but END-TO-END"*, so
the row is left **understated** rather than moved to a status whose entry evidence would be
false. **That is the second instance of the status-vocabulary gap §7.10 escalated for
`SEC-R2`/`SEC-R3`**, and the owner ruling requested there is now outstanding for two
findings, not one.

#### What this checkpoint does NOT do

- **No implementation, CI, test, migration, schema, RLS, Edge Function, fixture, probe,
  credential or secret change.** Governance documents only.
- **Step 4 / end-to-end verification not begun** and not inferred.
- **`I-WRK-01` untouched** — §7.15's literal-log requirement is unchanged, and run #44's
  `wrk01-live` job is that finding's own probe, not evidence for this one.
- **`EC-11` not started; `H-02`/`I-COM-01` not continued; `checkin_screen.dart` and
  `workout_service.dart` untouched (`catch (` count **14**); `D-4`/`D-5` unchanged.**
- No other row's status was examined. The remaining Wave 3A tasks — 3A-1/2/3, 3A-4, 3A-6,
  3A-7, 3A-9/10/11 — are unstarted.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it.
No migration was applied, reverted or pushed to it. No Edge Function was deployed to it.
The linked project remained `eyqtldjqpgpljlqvpowh` throughout. The evidence cited is CI run
**#44**, which had already executed. **No QA write and no QA read were performed by this
checkpoint**, and it changed governance documents only.

---

## 8. Environment blockers

| ID | Blocker | Blocks | Owner | Wave |
|---|---|---|---|---|
| **EB-1** | `QA_SERVICE` (a scoped QA service-role key) exists in no working copy | `npm run test:security` (188 assertions), `test:ai` live half, `setup-identities.mjs`. **Phase 1's evidence cannot be re-verified, and §4.2 proves it has drifted** | whoever holds the QA keys | 1 — **RESOLVED 2026-08-25**: `QA_URL`/`QA_ANON`/`QA_SERVICE` provisioned as repository secrets; the live-qa job executed for the first time (surfacing W1B-N8) |
| **EB-2** | Zero Edge Functions deployed to QA; `supabase secrets list` → `{"secrets":[]}` | Every AI, payment, invite and enrichment surface. 10 of J's findings and the whole of D's smoke matrix | DevOps | 5 |
| **EB-3** | QA Vault `project_url` / `service_role_key` unset | The coaching crons (fail-closed, correctly, so they are inert). **QA values only — the migration comment exists because a production URL was once pasted in** | DevOps | 5 |
| **EB-4** | Intelligence substrate unpopulated (0 profiles / 621 exercises; 0 graph nodes and edges) | Any real engine decision; AI-5, F-J-09, F-J-22 | Content owner + **D-1** | 5 |
| **EB-5** | No Stripe test-mode account, QA webhook endpoint, QA signing secret, or five QA price ids; `STRIPE_PK` empty in `qa.json`; the runbooks name **production only** and there is no QA equivalent | Every dynamic billing assertion in Workstream K. The embedded-checkout path is untestable in the only safe environment | DevOps + finance | 6 |
| **EB-6** | `API_BASE_URL` empty in every environment; the NestJS API runs nowhere | The AI Nutrition Coach in **all** environments | **D-2(L)** | 1/5 |
| **EB-7** | Resend sender domain unset — the default delivers **only** to the Resend account owner | Every email test is a silent no-op against any other recipient | DevOps | 5 |
| **EB-8** | No Deno runtime; no `deno.json`, import map or lockfile in `supabase/` | Any Edge Function test. **Standing up `deno test` with mocked `fetch` would convert two-thirds of D's smoke matrix into CI** | DevOps | 8 |
| **EB-9** | No runtime UI harness — no integration-test driver, no device | Every UI finding in M is static + query-replay evidence; none was observed on a running screen | QA | 9 |
| **EB-10** | No QA content-editor or coach credential available to the workstreams | Re-measuring the exercise library, the certification pipeline, and the coach half of H-06 | whoever holds the QA keys | 5 |
| **EB-11** | No staging environment and no `dart_defines/staging.json` | Gate 2 in its entirety. **Beta is currently undefined** (D-4 in L) | release engineering | 8 |
| **EB-12** *(added 2026-08-24, Wave 1 batch)* | No Supabase Management API credential in any working copy, and `GET /auth/v1/settings` does not expose HIBP state — the CLI's keychain token is off-limits per governance | `R-06` (leaked-password protection). One dashboard action by the owner: QA project → Authentication → Policies → enable "Prevent use of leaked passwords", then record before/after in `WAVE_1_BATCH_CLOSURE.md` §3 | product owner / DevOps | 1 |

---

## 9. Production exposure register

Production `nxdbooufqzkpslkcogxc` was **not contacted** by this reconciliation or by any
workstream. Everything here is **UNVERIFIABLE** and derived from source. It is recorded
so the rollout plan has an input; **nothing here is authorization to act.**

| # | Exposure | Evidence class |
|---|---|---|
| 1 | **SEC-01…SEC-05 are live in production.** They are properties of the migration source. 113–122 close them on QA only | SRC |
| 2 | Migrations `083/084/086/087/090/091/097/099` state in their own headers that they were *never applied in any environment* before their in-place correction. **Production therefore probably has no content pipeline, no certification view, no `exercise_intelligence` table and no per-attribute review** — the largest single schema divergence in the product | SRC |
| 3 | 076's `B2-6` correction and its Vault-based cron retarget **do not self-apply** to an environment that already ran the old 076. Production may still POST to production Edge Functions from a cron created by a QA replay, and `ai_cron_generate` raises on every scheduled run once Vault is configured | SRC |
| 4 | Migration 109 (`auth.users` trigger) is deliberately not auto-applied. It is written name-agnostic and idempotent, so it is safe — applying it is a separate decision | SRC |
| 5 | Migration 102 must not reach production until every beta build reads display names from `public_profiles` / `conversation_participant_profiles` — **and H-06 proves five surfaces still do not** | SRC + LIVE |
| 6 | `dietary_restrictions` is `text` on QA; the in-code comment asserts the live column is `text[]`, implying an out-of-band production change. **Q-6** | LIVE (QA) + UNVERIFIABLE (prod) |
| 7 | `supabase/STRIPE_CONNECT_SETUP.md` claims `stripe-connect`, `create-checkout` and `stripe-webhook` are "already deployed" — a documentation assertion of unknown age. **If true, E-06, E-07, K-01 and E-14 are live in production today, and K-01 is a financial defect** | UNVERIFIABLE |
| 8 | The production Stripe slot holds a `pk_test_` publishable key. Either real money has never moved, or the constant is wrong. **D-1(L)** determines whether existing subscription records are real | SRC |
| 9 | Production's `supabase_migrations.schema_migrations` has never been dumped or reconciled against source | UNVERIFIABLE |
| 10 | The daily keep-alive GitHub workflow is the **only** automation that contacts production, and it is the only workflow in the repository | SRC-V |

---

### 7.18 `UIX-1` / `M-03` VERIFIED END-TO-END and `VERIFIED_CLOSED` — 2026-08-28 · evidence: CI run **#49** `33200559221` at `7b944aa`

The last rung of the **PRODUCT INTEGRITY / UI REACHABILITY** class opens here and the row
closes. **One count moves. Nothing else is promoted, no other row is examined, and no
governance rule is reinterpreted beyond the single owner ruling recorded below.**

#### The run

| Field | Value |
|---|---|
| Run | **#49** · `33200559221` · event `push` · branch `chore/qa-environments-secure-ai-backend` |
| Head | `7b944aaa5c4e37bcddaeb70940e79a2991b97232` |
| Conclusion | `success` · **7 of 7 jobs `success`** |
| Jobs | Static guards · API — unit + e2e · Flutter — analyze, test, QA web build · Negative control — synthetic pre-fix-equivalent evidence · Live QA suites (security / AI / contract) · **UIX-1 — booking surface end-to-end (real route, real paywall)** · I-WRK-01 — live progression read path (pre-fix / post-fix) |
| UIX-1 job | `98949037130` · `success` · steps 1–7 all `success` |

Verified against the GitHub REST API read-only (`runs/33200559221` and its `jobs`, both
HTTP 200); the run's `head_sha` was checked to equal the repository's HEAD rather than
taken from the badge.

#### Rung movement

| Row | Rung | From | To |
|---|---|---|---|
| **`UIX-1`** / `M-03` · §6 · P0 · class **PRODUCT INTEGRITY / UI REACHABILITY** | VERIFIED END-TO-END | ABSENT | **PRESENT** (run #49) |
| **`UIX-1`** / `M-03` | Status | `REMEDIATED` (understated) | **`VERIFIED_CLOSED`** |

The evidence, the entailment basis, the owner ruling that extends §7.13's standard to this
rung for this row, and the two rendering defects repaired along the way are recorded in
full in the §6 row and are not duplicated here.

#### Counts

`UIX-1` is a **§6 P0 row with a status field**, so unlike `F-J-12` (§7.12) and `I-WRK-01`
(§7.15) it **is** mechanically countable, and this transition **is** a closure — which the
`REMEDIATED` transition recorded at §7.16 was not. The source bucket is
`READY_TO_REMEDIATE`, because §7.16 and §7.17 both deliberately left the table unmoved when
the row went `READY_TO_REMEDIATE` → `REMEDIATED`; the row's status text moved, the count did
not, so the figure of 178 has been carrying it since.

| | Before | After |
|---|---:|---:|
| `READY_TO_REMEDIATE` | 178 | **177** |
| `VERIFIED_CLOSED` | 28 | **29** |
| Canonical total | 319 | **319** |

`37 + 48 + 24 + 177 + 4 + 29 = 319` ✓. The narrative figure moves **30 → 31**; the
divergence from the table is still exactly `F-J-12` and `I-WRK-01`, both uncounted for the
reason §7.12 and §7.15 record.

#### What this checkpoint does NOT do

- **It does not extend the entailment ruling beyond `UIX-1`.** §7.15's literal-log
  requirement for `I-WRK-01`'s VERIFIED LIVE rung is untouched, and `SEC-R2`/`SEC-R3` keep
  their §7.10 position: four of five states, END-TO-END outstanding, understated at
  `READY_TO_REMEDIATE`, owner ruling still requested.
- **It does not resolve the status-vocabulary gap.** `UIX-1` left that position by closing,
  not by a ruling. The gap still governs two findings.
- **It does not promote `SEC-04`, `ENV-6`, `SEC-09` or `I-MIG-03`,** and does not touch the
  `I-MIG-03` / `SEC-09` authority question, `ENV-2`'s apply-123-to-QA gate, `DAT-3` /
  `I-INT-01`'s open closure-class and `PD-A09` questions, or `D-4` / `D-5` — all carried
  forward unchanged.
- **No other row's status was examined.** The remaining Wave 3A tasks — 3A-1/2/3
  (`I-NUT-01`, `I-INT-01`, `F-J-04`), 3A-4, 3A-6, 3A-7, 3A-9/10/11 — were not started.
- **`known-violations.json` was not modified**, no allowlist entry was added or removed, no
  assertion was weakened, and the workflow still contains **zero** `continue-on-error`.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it;
no migration was applied, reverted or pushed to it; no Edge Function was deployed to it.
The linked project remained `eyqtldjqpgpljlqvpowh`. The QA writes in this closure are the
`uix1-e2e` job's own run-scoped fixture, created and retired inside CI under existing RLS
with no service-role credential, and proved removed by a read.

---

### 7.19 `I-NUT-01` VERIFIED IN CI — 2026-08-28 · evidence: CI run **#51** `33205917510` at `adc43a4`

One rung opens for **one** row. **Nothing is promoted to `VERIFIED_CLOSED`, no count moves,
`I-INT-01` and `F-J-04` are explicitly NOT closed, and no governance rule is reinterpreted.**

#### The run

| Field | Value |
|---|---|
| Run | **#51** · `33205917510` · event `push` · attempt 1 · branch `chore/qa-environments-secure-ai-backend` |
| Head | `adc43a42ed682d29eb43c30396e0c00c21388455` |
| Conclusion | `success` · **7 of 7 jobs `success`**, every step `success` |
| New step | `negative-control` **step 9** — *"I-NUT-01 — nutrition column guard, pre-fix / post-fix evidence"* → `success` on its first run |

Verified read-only against the GitHub REST API (`runs/33205917510` and its `jobs`, both
HTTP 200); `head_sha` was checked to equal the repository HEAD rather than taken from a badge.

#### Both halves of §2, in one run

* **Post-fix half — directly bounded.** `static-guards` **step 7** *"Schema contract guard
  (relations, columns, embedded resources)"* → `success`. The step is **unconditional** (owner
  ruling B-2, `b1a19ae`): a skipped step reports `skipped`, this reported `success`, so it
  executed and passed and cannot have been credential-skipped.
* **Pre-fix half — `negative-control` step 9.** `supabase/tests/contract/nut01_negative_control.sh`
  installs `ai-coaching-engine/index.ts` from `2ad8c6c` against the **post-fix** allowlist and
  requires the guard to fail. Under `set -euo pipefail` with a `die` on every branch, exit 0 is
  reachable only if: the tree was clean and nothing staged; `git cat-file -e 2ad8c6c:<path>`
  succeeded, so `fetch-depth: 0` worked; the baseline guard passed; the installed file carried
  the literal `protein_g, carbs_g, fat_g').eq('user_id'` **and** differed from the committed one;
  the pre-fix run exited **non-zero**; its output contained all three of
  `column   nutrition_logs.protein_g is referenced but does not exist` and the `carbs_g` /
  `fat_g` equivalents; **no other `FAIL` line was present**; the restore passed
  `git diff --quiet`, so it was byte-identical; and the post-fix run exited 0.

**`G-3` is NOT invoked.** `2ad8c6c` is a real ancestor carrying the actual defect, so this is
genuine pre-fix evidence and must never be filed alongside the WKT-204 and M-1/M-2/M-3 steps.

**Entailment, not literal log text.** Raw job logs still return **HTTP 403 "Must have admin
rights to Repository"** (job- and run-level, re-attempted at this checkpoint), so the harness's
own output was **not read**. The step's exit status plus the harness source read at the executed
SHA is the §7.13 standard, unchanged and confined to VERIFIED IN CI — §7.15's literal-log
requirement for `I-WRK-01`'s VERIFIED LIVE rung remains untouched, and §7.18's extension to the
END-TO-END rung remains confined to `UIX-1`.

#### Regression, same run

| Job | Result |
|---|---|
| `UIX-1` — booking surface end-to-end (real route, real paywall) | `success`, steps 6 and 7 |
| `I-WRK-01` — live progression read path (pre-fix / post-fix) | `success`, steps 6 and 7 |
| Static guards · API unit+e2e · Flutter analyze/test/QA web build · Live QA suites | all `success`, every step |

Both previously-closed rows still hold on the new tree; neither was re-opened, re-verified nor
re-counted.

#### Rung movement

| Row | Rung | From | To |
|---|---|---|---|
| **`I-NUT-01`** *(= E-13, E-NUT-04, F-J-03)* · §7 · P1 · CRC-01 · class **Data contract / schema** | VERIFIED IN CI | ABSENT | **PRESENT** (run #51) |

**Not `VERIFIED_CLOSED`.** §2.1's Data contract / schema ladder also requires **FIXED ON QA**
and **VERIFIED LIVE where a read path exists**. `ENV-7` holds all 19 Edge Functions undeployed
to QA — deliberately, until Wave 5 — so neither state is reachable today, and no waiver was
sought. **Two of four states present.**

#### Counts

**None moved.** `I-NUT-01` is a §7 table row and that register carries **no per-row status
field**, so like `F-J-12` (§7.12) and `I-WRK-01` (§7.15) it is not mechanically countable.
`VERIFIED_CLOSED` stays **29**; the canonical total stays **319** (37 + 48 + 24 + 177 + 4 + 29).

#### Explicitly NOT closed by this checkpoint

- **`I-INT-01`** — `8b1fba3` corrected `ai-coaching-engine`'s read to `fitness_goal` (`000`
  defines `fitness_goal`; 001's `user_profiles` block is a shadow `CREATE TABLE IF NOT EXISTS`
  that never executes). But its allowlist entry `user_profiles.goal` **still reproduces** at
  `ai-generate-workout/index.ts:63`, which belongs to `I-INT-02` / `DAT-2` — **task 3A-4**. The
  negative control shows it directly: `(2 sites)` pre-fix, `(1 site)` post-fix. The entry was
  therefore **kept**, correctly, and **`I-INT-01` has no discriminating CI guard until 3A-4
  lands.** Newly recorded dependency; it was not in the wave plan.
- **`F-J-04`** — `8b1fba3` gave `recent()` per-table ordering keys (`user_scores`→`updated_at`,
  `workout_sessions`→`started_at`, `nutrition_logs`/`habit_logs`/`workout_set_logs`→`logged_at`),
  each key confirmed present and `created_at` confirmed absent in the first `CREATE TABLE` for
  that name, and repaired the two projections that read the same phantom column. **`nutrition_logs`
  is the fifth of the "five of nine" this row never named** — hidden because 012's definition is a
  no-op. But `run.mjs` checks `select` columns and `insert/update/upsert` payload keys and **does
  not check filter columns** (`.order`, `.eq`, `.gte`), so **no guard in CI can see this defect or
  its regression.** `F-J-04` is FIXED IN CODE only.
- **`EC-02` / rule S was not touched.** `recent()`'s `{ data } ?? []` / `catch { return [] }`
  degradation is unchanged: that is ERR-2, whose fail-closed behaviour is `BLOCKED_DECISION` on
  **Q-5** (`DAT-2`'s row). Task 3A-3's phrasing overlaps it; only the ordering half was
  implemented and the response-policy half was left to its own blocked row.
- **No allowlist change, no assertion weakened, zero `continue-on-error`, `secrets.QA_*`
  unchanged at 15.** `adc43a4` adds one step to an existing job — no new job, no credential, no
  network, no toolchain — and reuses the `fetch-depth: 0` checkout already there.
- **No other row's status was examined**; `PD-A09`, the status-vocabulary ruling for
  `SEC-R2`/`SEC-R3`, `SEC-04`, `ENV-6`, `SEC-09`/`I-MIG-03`, `ENV-2`, `D-4`/`D-5` are carried
  forward unchanged.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it; no
migration was applied, reverted or pushed to it; no Edge Function was deployed to it. The linked
project remained `eyqtldjqpgpljlqvpowh`. This checkpoint performed no QA read and no QA write;
`nut01_negative_control.sh` is offline — `node supabase/tests/contract/run.mjs` imports only node
builtins and reads no environment variable.

---

### 7.20 `I-INT-02` / `DAT-2` and `I-INT-01` / `DAT-3` VERIFIED IN CI — 2026-08-30 · evidence: CI run **#53** `33326163269` at `5dfc59f`

One rung opens for **two** rows. **Nothing is promoted to `VERIFIED_CLOSED`, no count moves,
`F-J-04` is not advanced, `Q-5` is untouched, and no governance rule is reinterpreted.**

#### The run — independently verified, not accepted from a summary

| Field | Value |
|---|---|
| Run | **#53** · `33326163269` · event `push` · attempt **1** · created 2026-08-30T17:45:55Z |
| Head | `5dfc59f3c43a079a7a232921c8e3b93d9a33a5f9` — equal to the repository HEAD **and** to `refs/heads/chore/qa-environments-secure-ai-backend` |
| Conclusion | `success` · **7 of 7 jobs `success`**, every enumerated step `success` |
| New step | `negative-control` **step 10** — *"I-INT-02 — profile column guard, pre-fix / post-fix evidence"* → `success` on its first run |

Read read-only from the GitHub REST API (`runs/33326163269` and its `jobs`, both HTTP 200).
Every one of the seven jobs carries `head_sha 5dfc59f3c43a`, so the run corresponds to this
tree and not to an earlier one.

#### The workflow was verified at the executed SHA, not in the working tree

`git show 5dfc59f:.github/workflows/ci.yml`:

* `static-guards` carries **no job-level `if`**, and its *Schema contract guard (relations,
  columns, embedded resources)* step has keys `name` and `run` only — **no `if`**. A skipped
  step reports `skipped`; this reported `success`, so it executed and cannot have been
  credential-skipped.
* `negative-control` carries no job-level `if`, checks out with **`fetch-depth: 0`**, and
  wires `uix1_negative_control.sh` (329), `nut01_negative_control.sh` (340) and
  `int02_negative_control.sh` (350).
* The workflow contains **zero** `continue-on-error`.

#### `I-INT-02` / `DAT-2` — both halves of §2

**The defect.** `ai-generate-workout/index.ts:63` selected `fitness_goal, goal, equipment,
experience_level, training_location, has_injuries, injury_locations` from `user_profiles`.
Neither `goal` nor `equipment` exists there: `000_baseline` defines `fitness_goal`; none of
the 26 `ADD COLUMN` migrations adds either name; 001's `user_profiles` block is a shadow
`CREATE TABLE IF NOT EXISTS` that never executes. PostgREST resolves the whole select before
reading, so one phantom column 400'd the entire request and took `experience_level`,
`training_location`, `has_injuries` and `injury_locations` — all real, migration **013**'s
multi-column ALTER — down with it.

**The fix (`0a4b14d`).** Both phantom names dropped. `goal` needed no replacement:
`fitness_goal` is authoritative and was already selected and already first in the coalesce,
so `?? profile?.goal` was a fallback to a column that never existed. `equipment` was
**repointed, not removed** — `074_ai_coaching_layer.sql:13` declares `ai_profiles.preferences`
as `{favorite_exercises, disliked_exercises, available_equipment, training_days}`, and this
handler already fetches `ai_profiles.select('goals, preferences')` in the same `Promise.all`,
so it now reads `preferences.available_equipment`, the jsonb drill the file already uses for
`goals.secondary_goal`. **The `?? 'Bodyweight'` and `?? 'general'` defaults are unchanged** —
whether a missing input may be defaulted at all is ERR-2 / rule S, blocked on **Q-5**.

**Post-fix half — directly bounded.** `static-guards` step 7 → `success`, unconditional (above).
§2.1 names this class's mechanism verbatim: *"VERIFIED IN CI (`test:contract` with the
allowlist entry removed)"*. The `user_profiles.equipment` entry **was** removed in `0a4b14d`;
`known-violations.json` fell 6 → 4.

**Pre-fix half — `negative-control` step 10.** `int02_negative_control.sh`, read at the
executed SHA, runs under `set -euo pipefail` with a `die` on every branch. Exit 0 is reachable
only if: the tree was clean and nothing staged; `git cat-file -e c678102:<path>` succeeded, so
`fetch-depth: 0` worked; the baseline guard passed; the installed file carried the literal
`select('fitness_goal, goal, equipment,` **and** differed from the committed one; the pre-fix
run exited **non-zero**; its output contained **both** `column   user_profiles.goal is
referenced but does not exist` and the `equipment` equivalent; **no other `FAIL` line was
present**; the restore passed `git diff --quiet`; and the post-fix run exited 0.

#### `I-INT-01` / `DAT-3` — the shared-evidence question, answered from the standard

The governing text was checked rather than assumed. **§2.1 states this class's VERIFIED IN CI
mechanism explicitly — *"`test:contract` with the allowlist entry removed"* — and §2 defines
the state generally as *"An automated check fails against the pre-fix tree and passes against
the post-fix tree, in CI"*. Neither §2, §2.1 nor §4 requires a finding to own a dedicated
harness, and no rule anywhere in `QA_CLOSURE_STANDARD.md` speaks of per-finding or standalone
controls.** What §4 does prohibit was checked one by one and none applies:

| §4 prohibition | Why it does not apply |
|---|---|
| *"A guard that does not read the file where the defect lives."* | The harness installs the actual `ai-coaching-engine/index.ts`, the file where `I-INT-01`'s defect lived, and the guard names the site `:123` |
| *"A ratchet that cannot see the defect's shape."* | The guard resolves `table.column` against migration-derived schema and names `user_profiles.goal` exactly |
| *"An allowlist entry."* | The entry was **removed**, and the list is checked in both directions — a removal without the fix fails as loudly as a fix without the removal |
| *"A passing suite that has never run in CI."* | It ran, in CI, at run #53 |
| *"A green build after weakening a test."* | The harness was **strengthened**: a fourth required literal was added, not a tolerance |

**The chain.** `8b1fba3` (task 3A-2) corrected `ai-coaching-engine/index.ts:143` to
`fitness_goal`. That commit could **not** complete the allowlist half, because the same
`user_profiles.goal` entry still reproduced at `ai-generate-workout/index.ts:63` — the guard
reported it as `known (2 sites)` pre-3A-4 and `(1 site)` after. Task **3A-4** removed that last
site, so the entry left the list. That removal made the co-resident defect visible inside the
existing I-NUT-01 harness, whose pre-fix blob is `2ad8c6c` — **the real parent of `8b1fba3`,
so it is `I-INT-01`'s genuine pre-fix tree and `G-3` is NOT invoked.** Rather than tolerate the
new failure, `nut01_negative_control.sh` now **requires** it (line 109): `grep -Fq "column
user_profiles.goal is referenced but does not exist" || die`. `negative-control` **step 9** →
`success` at run #53, so that literal was present against the pre-fix tree; `static-guards`
step 7 → `success` supplies the post-fix half with the entry gone.

**Determination: `I-INT-01` satisfies §2's VERIFIED IN CI.** The evidence is shared with
`I-NUT-01`'s harness, and the standard permits that: it specifies *what must be demonstrated*,
not *how many scripts must demonstrate it*. A separate harness was **not** created, because
§10.4's discipline is to add mechanism only where the standard requires it and none does here.

#### Rung movement

| Row | Register | Rung | From | To |
|---|---|---|---|---|
| **`I-INT-02`** / `DAT-2` · §6 · P0 · class **Data contract / schema** | §6 | VERIFIED IN CI | ABSENT | **PRESENT** (run #53) |
| **`I-INT-01`** / `DAT-3` · §6 · P0 · class **Data contract / schema** | §6 | VERIFIED IN CI | ABSENT | **PRESENT** (run #53) |

Both rows move `READY_TO_REMEDIATE` → `REMEDIATED`, which is now **understated for both** —
they carry FIXED IN CODE *and* VERIFIED IN CI, and §2's status table has no term for that
position. This is the **third and fourth instance of the status-vocabulary gap §7.10 escalated
for `SEC-R2`/`SEC-R3`** and §7.16 recorded for `UIX-1`; the owner ruling requested there is now
outstanding for four findings. Nothing is waived.

#### Counts

**None moved.** §7.16 settled the precedent for exactly this transition: a §6 row moving
`READY_TO_REMEDIATE` → `REMEDIATED` is not a closure, and §2's status table counts neither
transition. `VERIFIED_CLOSED` stays **29**; the canonical total stays **319**
(37 + 48 + 24 + 177 + 4 + 29). The `READY_TO_REMEDIATE` figure of 177 continues to carry both
rows, exactly as it carried `UIX-1` between §7.16 and §7.18.

#### `VERIFIED_CLOSED` is unavailable for both, and why

§2.1's **Data contract / schema** ladder is *"FIXED IN CODE · FIXED ON QA · VERIFIED IN CI ·
VERIFIED LIVE where a read path exists"*, and §2.1 closes with *"`VERIFIED_CLOSED` requires
every state its class demands. There are no partial closures and no exceptions granted at
implementation time."* **Two of four are present for each row.**

* **FIXED ON QA: ABSENT.** §2 defines it as *"The migration, function or configuration is
  **applied to QA** and the object exists in the live catalog."* The changed artifacts are
  Edge Functions, and **`ENV-7`** — *"Zero Edge Functions are deployed to QA"*, all 19
  returning `404 NOT_FOUND` — holds them undeployed **deliberately until Wave 5**: its row
  states that deploying earlier *"converts a visibly dead system into an invisibly wrong one"*.
  The columns these functions read do exist in QA (ENV-3's live ledger), but the **fix** has
  not reached the environment.
* **VERIFIED LIVE: ABSENT, and blocked by the same cause.** §2 requires *"A real request
  against QA [that] reproduces the secure/correct behaviour, and the same probe demonstrably
  failed before the fix"*. A request to an undeployed function cannot be made. No substitute
  was recorded and no waiver was sought.

#### Evidence classes — what was and was not observed

**Directly observed:** the run, job and step conclusions, and the head SHA of every job, via
the REST API. **Source-derived:** the workflow, both harnesses and the schema, all read at the
executed SHA `5dfc59f` or in the migrations. **NOT observed:** the harnesses' literal output.
Raw job logs and the run-level archive both return **HTTP 403 "Must have admin rights to
Repository"** — re-attempted at this checkpoint for the `static-guards` and `negative-control`
jobs and for the run zip — and `gh` is not installed in this environment. The marker lines
above are **entailed** from each step's exit status plus the harness source at the executed
SHA, which is the §7.13 standard, unchanged and still confined to VERIFIED IN CI. §7.15's
literal-log requirement for `I-WRK-01`'s VERIFIED LIVE rung is untouched, and §7.18's extension
to the END-TO-END rung remains confined to `UIX-1`. **No QA runtime and no production runtime
behaviour is claimed by this checkpoint.**

#### Regression, same run

| Job | Result |
|---|---|
| `UIX-1` — booking surface end-to-end (real route, real paywall) | `success`, steps 6 and 7 |
| `I-WRK-01` — live progression read path (pre-fix / post-fix) | `success`, steps 6 and 7 |
| Static guards (7 steps) · API — unit + e2e · Flutter — analyze, test, QA web build (6 steps) · Live QA suites (6 steps) | all `success` |

Both previously-closed rows still hold on this tree. Neither was re-opened, re-verified nor
re-counted, and nothing beyond "these suites were green at `5dfc59f`" is inferred from them.

#### What this checkpoint does NOT do

- **`F-J-04` is not advanced.** It remains **FIXED IN CODE only**: `run.mjs` checks `select`
  columns and `insert`/`update`/`upsert` payload keys and **does not inspect filter columns**
  (`.order`, `.eq`, `.gte`), so no CI guard can see that defect or its regression. No
  filter-column guard was built.
- **`Q-5` is untouched.** `recent()`'s `{ data } ?? []` / `catch { return [] }` degradation is
  unchanged, and `DAT-2`'s fail-closed half stays `BLOCKED_DECISION`.
- **The `available_equipment` write-path gap stays open and unchanged.** `074:13` declares the
  key; **nothing in the tree writes it**. The read is schema-correct and points at the declared
  store, but that store has no writer. Recorded for owner triage — §10.4 requires an ID, a
  root cause from §1 and a wave, and none was invented here.
- **No implementation file, migration, guard, harness, workflow or allowlist was modified by
  this checkpoint**, and no other row's status was examined.

**Production statement (closure standard §6):** production `nxdbooufqzkpslkcogxc` was not
contacted. No REST, RPC, Auth, Storage, Realtime or Edge Function request was issued to it; no
migration was applied, reverted or pushed to it; no Edge Function was deployed to it. The
linked project remained `eyqtldjqpgpljlqvpowh`. This checkpoint performed **no QA read and no
QA write**; both contract harnesses are offline — `node supabase/tests/contract/run.mjs`
imports only node builtins and reads no environment variable.

---

### 7.22 Wave 3A migration renumbering (B1) and `I-COM-03`(a) scope (B3) — 2026-08-31 · governance only

Recorded at the 3A-9 implementation gate, which stopped before writing code because both
questions below had to be settled first. **Governance only. No code, migration, test, CI,
`known-violations.json` or Edge Function file was touched. No count moved —
`VERIFIED_CLOSED` stays 29, canonical total stays 319. No closure class was ruled and no
finding changed status.** §7.21 is reserved for the `I-COM-01` / `DAT-4` VERIFIED IN CI
record authored 2026-08-31 against CI run #55, which exists but has not yet reached this
branch; it keeps its number and is not renumbered here.

**B1 — migration numbering.** `MASTER_REMEDIATION_WAVES.md` §0.2 assigned **126/127/128 to
Wave 3A** (tasks 3A-9/3A-10/3A-11) and reserved **129+ for Wave 4+**, under the rule that
numbers *"are assigned in this document and are not negotiable at implementation time"*.
**Wave 2 consumed all three:** `126_parq_risk_flag_typed_append.sql` (`F-J-17`, `c7c1058`),
`127_typed_rule_accumulator_appends.sql` (`F-J-07`/SEC-R3, `e909f9a`),
`128_scope_decision_trace_reads_option_a.sql` (`F-J-12`/PD-A05 option (a), `f38841f`).
Each took the next contiguous number at authoring time — the same practice already applied
when §0.2's 125 assignment was spent and option (a) landed at 128 (§7.11). The practice was
never written back into §0.2, which is why the next task read a table that was false.

The correction is **not a renumbering**. Gate 0.9 (`RELEASE_GATES.md` row 0.9, enforced by
`.github/scripts/check-migration-hygiene.sh`) fails on duplicate prefixes *and* on gaps, and
states in terms: *"Do not renumber an existing migration to close a gap."* §0.2's 126/127/128
rows are therefore **corrected to describe what the tree contains**, and Wave 3A's three
migrations are reassigned to **129 → 130 → 131**, with Wave 4+'s floor moved to **132+**.

**The numbers were derived, not chosen.** The QA frontier is 128 (`expected_applied.json`:
`applied_through: "128"`, `excluded: []`, `pending: []`; ENV-3 live ledger 129 declared =
129 observed, 0 holes in 000–128) and Gate 0.9 requires a contiguous authored sequence.
129/130/131 are the only values that satisfy both constraints simultaneously; no other
assignment exists.

**Unchanged by this amendment:** authoring a migration does not apply it. Each of 129/130/131
must be declared in `expected_applied.json` as `pending`, with a reason and the gate that
releases it, at the moment it is authored — *"every authored version must appear in exactly
one of those three states. Silence is not a state."* Applying any of them to QA remains a
separate authorization gate, so **FIXED ON QA is not reachable for 3A-9/3A-10/3A-11 by
authoring alone**, and the §2.1 classes those findings will eventually be ruled into
(Data contract / schema; Security / authorization for `may_notify()` and the two private
body-photography buckets) each require it.

**B3 — `I-COM-03`(a) scope.** §0.2's 126 row and the 3A-9 task row both read
*"`custom_exercises.approved_by`"*, which reads as an instruction to ADD that column. The
authoritative source contradicts it. `QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md` §I-COM-03
records the live DDL as *"`submission_status`, `submitted_at`, `approved_at`,
`last_reviewed_at`, `last_reviewed_by` — no `approved_by`"* and gives the remediation as
**"(a) `approved_by` → `last_reviewed_by`"**; its dependency graph adds *"Q-9 → I-COM-03
(moderated?) ── (a) approved_by→last_reviewed_by **can land now**; (b)+(c) must land
together"*. `last_reviewed_by uuid references user_profiles(id)` has existed since
`083_exercise_content_pipeline.sql:36`. The only site naming the phantom column is
`custom_exercise_service.dart:772` (`'approved_by': _uid`), inside `approveGlobalExercise()`.

**Ruling: 3A-9 repoints the client write to `last_reviewed_by`. No `approved_by` column is
added, by migration or otherwise.** Adding one would create a second reviewer column beside
`last_reviewed_by`, leave the actual `I-COM-03` defect — unmoderated global publishing —
untouched, and still permit `known-violations.json` and the H-G1 allowlist entry to be
cleared: a change that clears the ledger while closing nothing. Both routes clear the same
two ledger entries, because H-G1 asserts on the *client reference*, not on the column.

**Explicitly not settled here.** `I-COM-03` parts **(b)** (`submitForGlobalLibrary()` writing
`'pending'`) and **(c)** (the CHECK plus the visibility trigger) remain **Q-9-gated** and
**Wave 7D**; Workstream I records them as non-parallelizable with each other. `I-COM-03`'s
closure class has never been ruled and is **not** ruled here — **CLOSURE CLASS — OWNER
RULING REQUIRED**. Nothing in this section advances any finding's status.

**Still open, deliberately untouched by this gate:** B2 (`I-WRK-02` is filed Wave 4 / Q-7 at
registry §7.6 though Workstream I lists it as independent, no-decision, mechanical, and Q-7's
own dependents are `I-USR-01` and `I-WRK-03`) · B4 (`I-WMH-01` is named in
`MASTER_REMEDIATION_WAVES.md` and in Workstream I but has **no row in this registry**) ·
B5 (retiring guard H-G2 when `messages.metadata` lands would also retire its second test,
which pins a Wave 3B error-contract defect unrelated to `I-NOT-01`) · B6 (no negative-control
harness exists for any remaining Wave 3A item, so the reachable ceiling is FIXED IN CODE +
static CI verification unless one is built).

---

### 7.23 Autonomous QA exhaustion — discovery additions — 2026-09-25 · evidence: `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md`

**Additive only. No existing row is edited or re-statused.** Evidence class for every DB row below
is **LOCAL-REPLAY** (committed migrations 000–131 replayed locally; report §15). **None is VERIFIED
LIVE**: the QA host was network-denied to this session. All rows enter as `DISCOVERED`.

| ID | Sev | Class | Finding | Evidence | Owner? |
|---|---|---|---|---|---|
| `QAX-SEC-02` | **P0** | Security / PHI | `progress-photos` coach read policy (029) has no status check. A self-registered coach who self-creates a `pending` relationship, or any former coach, reads any client's body photos. Reachable on QA since 130 created the bucket. | LOCAL-REPLAY, mutation-tested | OD-QAX-1 |
| `QAX-SEC-01` | **P0** | Security (regression by remediation) | `assign_nutrition_plan` (131) supersedes any member's active plan for any caller. The definer UPDATE bypasses RLS that the direct path enforces. | LOCAL-REPLAY differential, mutation-tested | OD-QAX-2 |
| `QAX-SEC-03` | P1 | Authorization | Self-asserted `coach_id = auth.uid()` write arms on `client_habits`, `action_items`, `coaching_calls`, `coach_video_responses`, `client_nutrition_plans`, `workout_program_assignments`. The victim sees the rows and gets notifications, and a program can be hijacked or blanked. | LOCAL-REPLAY, mutation-tested | no |
| `QAX-SEC-05` | P1 | Authorization / integrity | `exercise-media` update/delete are not owner-scoped | LOCAL-REPLAY, mutation-tested | no |
| `QAX-SEC-07` | P1 | Authorization (Edge) | `enrich-exercise-*` gate on self-selectable `coach`, then write the global library as service role; confidence >90 auto-approves | STATIC | OD-QAX-3 |
| `QAX-PRV-01` | P1 | Privacy / legal | Privacy Policy correction, provider (Expo listed; Anthropic/Resend/Stripe missing), wearable and security claims are inaccurate | STATIC | OD-QAX-4 |
| `QAX-PRV-02` | P1 | Privacy / processor | Injuries, allergies, DOB, gender, weight, cycle, check-in and food images go to Anthropic undisclosed. **Extends `F-18`/`PD-D06`.** | STATIC | OD-QAX-5 |
| `QAX-SEC-04` | P2 | Authorization | `messages` INSERT has no conversation-membership check | LOCAL-REPLAY, mutation-tested | no |
| `QAX-SEC-06` | P2 | Confidentiality | `exercises` definer view has no WHERE and exposes private/draft `custom_exercises` | LOCAL-REPLAY, mutation-tested | no |
| `QAX-COR-01` | P2 | Correction / false success | Personal Info: cleared `phone`, `height_cm`, `weight_kg`, `weight_goal_kg`, `gender` never sent; `?? 0` writes 0 | STATIC + LOCAL-REPLAY; static guard mutation-tested | no |
| `QAX-COR-03` | P2 | Correction | No post-onboarding edit path for medical conditions, injuries, allergies, dietary restrictions, PAR-Q | STATIC | OD-QAX-6 |
| `QAX-COR-05` | P2 | Correction / integrity | `nutrition_logs` has no edit or delete; quick-add ungated, so duplicates | STATIC | no |
| `QAX-COR-07` | P2 | Correction / PHI | Gallery progress photos undeletable; baseline replace deletes before upload | STATIC | no |
| `QAX-SES-01` | P2 | Session / PHI | Mobile logout keeps 12 non-autoDispose per-user providers alive across accounts | STATIC (runtime not demonstrated) | no |
| `QAX-PRV-03` | P2 | Auditability | No audit trail for PHI corrections (0 audit tables) | LOCAL-REPLAY | OD-QAX-7 |
| `QAX-REG-01` | P2 | Governance | ID collision: Phase-1F `F-01/03/05/06/07/08` `VERIFIED_CLOSED` vs open Workstream-F women's-health `F-01…F-08` (F-03 P1 still open in code) | STATIC | OD-QAX-8 |
| `QAX-COR-02` | P3 | Correction | Set correction: reps and weight not clearable; "corrected" shown before persist | STATIC | no |
| `QAX-COR-04` | P3 | Correction / AI | Injury `ai_memories` never retracted on correction | LOCAL-REPLAY | no |
| `QAX-COR-06` | P3 | Error contract | Weight/measurement saves fail silently; stuck spinner on null uid; no edit/delete | STATIC | no |
| `QAX-COR-08` | P3 | Correction / error | Goals: "Mark achieved" irreversible; complete/delete unguarded | STATIC | no |
| `QAX-ERR-01` | P3 | Error contract | Cycle sheets: thrown write errors leave the sheet open with no message; post-131 duplicate date = `23505` | LOCAL-REPLAY + STATIC | no |
| `QAX-ERR-02` | P3 | Error contract | Coach habit assign non-atomic / null-uid success; coach feedback success on 0 rows | STATIC | no |
| `QAX-H-01`/`QAX-H-02` | P4 | Hardening | 13+ age gate client-only; coach self-registration unvetted | STATIC | OD-QAX-1 |

**Expanded (same IDs, no new row):** `E-15` also has unescaped name and token HTML/attribute
injection. `REL-29` has a concrete chain: register `role:'admin'` accepted; `GET /users`
returns bcrypt hashes; JWT secret falls back to `'your-secret-key'`.

**Recorded contradictions of prior statements:** see report §13. The source documents are not edited.
- R-1 `F-06` failure-path wording
- R-2 Workstream E "Sound"
- R-3 H-05 / 130 on 029's coach scope
- R-4 I-NOT-04 "no cross-tenant write"
- R-5 Phase 1 §8 and Workstream I on the `exercises` view
- R-6 131 / 3A-11 "reproduces the existing policy exactly"

**Re-observed, no status change made:**
- `SEC-R2` does not reproduce on the 000–131 local replay.
- `R-01`, `F-03`, `F-05`, `EC-12`, `EC-22`, `EDGE-1`, `EDGE-2`, `K-09` remain open.

**Handoff note:** the reports the 2026-09-25 handoff named as authoritative
(`QA_CORRECTION_RIGHTS_EXHAUSTION_REPORT.md` and four others) exist in no commit. Their claims were
re-derived, not inherited.

### 7.24 Autonomous QA exhaustion Run 2 — client-side remediation and new findings — 2026-09-25 · evidence: `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md` §R2

**Additive; §7.23 rows keep their IDs.** Flutter 3.44.4 (CI's version) became available locally, and the
repo's DB negative-control harness plus all seven per-finding negative controls now run locally
and **PASS**. **No migration was authored** (132+ is assigned at wave entry). QA was not contacted
(network-denied).

**New rows** (all `DISCOVERED`, LOCAL-REPLAY unless noted):

| ID | Sev | Finding | Evidence | Owner? |
|---|---|---|---|---|
| `QAX-SEC-08` | **P0** | A self-registered coach inserts `coach_team_members(coach_id=self, member_id=<anyone>)`, which the policy allows; `is_team_lead_of()` then exposes the full `user_profiles` row (medical conditions, PAR-Q, phone). No app code writes this table. | LR + mutation-tested; FIX-08 contract non-vacuous | OD-QAX-9 |
| `QAX-SEC-09` | P1 | A self-selected vendor reads the full profile (medical / PAR-Q / DOB) of anyone who registers for their event (`hosts_event_for` arm) | LR + mutation-tested | OD-QAX-10 |
| `QAX-BIL-01` | P2 | Vendor event delete is one tap, no confirmation. The FK cascade removes paid registrations; the `payments` row survives with `event_id = NULL`. | LR | OD-QAX-11 |
| `QAX-SEC-10` | P3 | Any signed-in user uploads into any coach's folder of the public `coach-media` bucket (INSERT checks bucket only) | LR + mutation-tested | no |
| `QAX-UI-01` / `QAX-UI-02` | P3 / P4 | Weight sheet date/unit row overflows at every width ≤414 px; ruler ticks overflow 2 px | widget repro, `tool/qa_exhaustion/` | no (layout owner) |
| `QAX-UI-03` | P4 | 8 `use_build_context_synchronously` sites, classified | analyzer + read | no |

**Status changes (FIXED IN CODE + widget/unit test + mutation; not LIVE; not device-verified):**
- `QAX-ERR-01` (`b0954f5`), `QAX-COR-01` (`fdbd67b`), `QAX-COR-07` replace-loss half (`7e1507e`), `QAX-COR-06` (`fa593a7`), `QAX-COR-05` quick-add half (`81dcf1f`), `QAX-COR-08` error half (`50c5437`), `QAX-SES-01` (`fb0a012`, class guard).
- `QAX-ERR-02` non-atomic half (`4df390b`): static only; the atomic half is BLOCKED (RPC).
- **Existing rows:**
  - **Women's-health `F-03`** (`fc29b41`)
  - `F-06` thrown/signed-out halves and `F-22` (`b0954f5`)
  - Workstream B `goal_service.updateProgress` (`50c5437`)
  - **`UIX-2` text half reopened and closed again** (`810430d`): the Terms still claimed in-app deletion, and the guard was vacuous for that wording.
- `QAX-COR-02` reclassified P3 → P4 plus OD-QAX-12. The failure *is* surfaced after an optimistic confirmation, by documented design.

**Guard audit (report §R2-10):** 23 guards mutation-audited. 7 were vacuous or blind to the
regression they name, and all 7 are fixed and re-proven:
- `UIX-2` deletion claims
- `REL-3` release gate
- `EC-G5` ratchet (slack + one-line shape; EC-G5b added)
- `I-G1/I-G2` (later-migration blind; I-G6 added)
- `AI-J-001` (later-redeclaration blind)
- `K/TIER` (wrong-occurrence substring)
- `A-G1` (file-level)

The six `spec_*` files (133 tests) import nothing from `lib/`: the known copy-of-product class.

**Recorded contradictions (report §R2-4):**
- R-12 H-06 "the policy is correct"
- R-13 sweep "0 warnings" (16 on a clean checkout)
- R-15 the UIX-2 guard
- R-20 the REL-3 guard

**Status line:** 12CIRCLE FITNESS QA — NOT EXHAUSTED (report §R2 CURRENT STATUS).

## 10. How to use this registry

1. **Never mark `VERIFIED_CLOSED` from a code diff.** The evidence ladder in
   `QA_CLOSURE_STANDARD.md` is mandatory and has five distinct states.
2. **Update the row, not a report.** The A–N reports are frozen evidence. When a finding
   moves, this file and `REMEDIATION_PROGRESS.md` move.
3. **A regression re-opens a row; it does not create one.** §4.2 is the pattern. Add the
   regressing change to the row's evidence and reset the status.
4. **A new finding needs an ID, a root cause from §1, and a wave.** If it does not map to
   a CRC, that is a signal the root-cause model is incomplete — extend §1 deliberately
   rather than filing an orphan.
5. **The alias map (§3) is closed.** Do not resurrect a retired ID.

**Companion documents:** [`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) ·
[`MASTER_PRODUCT_DECISIONS.md`](MASTER_PRODUCT_DECISIONS.md) ·
[`RELEASE_GATES.md`](RELEASE_GATES.md) ·
[`QA_CLOSURE_STANDARD.md`](QA_CLOSURE_STANDARD.md) ·
[`REMEDIATION_PROGRESS.md`](REMEDIATION_PROGRESS.md)
