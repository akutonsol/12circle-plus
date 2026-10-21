# 12 Circle Fitness — Remediation Progress Board

**Running status. Updated on every status change.**
**Last updated:** 2026-08-28 · **Wave 1 spine complete · Wave 2 P0 remediation live-verified · Workstream B **Phase B0** landed and closed (`ERR-1`/`EC-01`, runs #33 + #34) · `I-WRK-01` **VERIFIED LIVE** and closed (run #41, registry §7.15) · `UIX-1`/`M-03` **VERIFIED END-TO-END** and closed (run #49, registry §7.18) · 31 findings `VERIFIED_CLOSED` (registry §7.8, §7.9, §7.10, §7.12, §7.13, §7.15, §7.18) — the status table below counts 29; the difference is `F-J-12` and `I-WRK-01`, see their notes**

> **Update rules.** A status change here must be accompanied by the matching change in
> [`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md) and by the evidence
> [`QA_CLOSURE_STANDARD.md`](QA_CLOSURE_STANDARD.md) requires for that finding's class.
> **This board never leads the registry.**

---

## 1. Programme status

| | |
|---|---|
| **Current wave** | **1 — Custody, Environment & Release Safety · IN PROGRESS** |
| **Completed** | Wave 0 · W1-T1 · batch tasks 2–8 (task 9 blocked, EB-12) · W1B-N6…N9 CI-closed · **Phase 1 live re-verification: 271/271 at `6d42b10` → 23 rows `VERIFIED_CLOSED`** (registry §7.8) |
| **Next action** | Row-by-row **Phase 2 cohort reconciliation** against the AFTER matrix (registry §7.9). Then the **apply-123-to-QA** gate — fresh authorization, own pre-application state check. Also outstanding: task 8 wording · EB-12 (R-06 toggle) → Wave 1 exit review → Wave 2 2A (migration 124) |
| **Highest gate met** | **Gate 0 mechanics exist and are green** (`6d42b10`: static guards, Flutter, API, live security 271/271, AI, contract). Formal row-by-row gate scoring is the Wave 1 exit review |
| **Production contact** | **none, by any wave, at any point** |
| **Blocking on** | 8 critical-path decisions (§5) and 11 open environment blockers (§6; EB-1 resolved 2026-08-25) |

---

## 2. Wave board

| Wave | Name | Status | Findings | Entry met? | Exit gate |
|---|---|---|---|---:|---|
| **0** | Reconciliation | ✅ **COMPLETE** | 310 catalogued | — | — |
| **1** | Custody, Environment & Release Safety | 🟨 **IN PROGRESS** — W1-T1 done · batch committed · CI green · **23 rows VERIFIED_CLOSED at `6d42b10`** · **spine complete: W1-T2 (123 committed) + W1-T3 (QA ledger repaired 2026-08-25)** · remaining: apply 123 to QA (separate gate), task 8 (held), R-06 (EB-12), FG-1/FG-2 | 22 (+9 new, §11a) | ✅ yes | Gate 0, Gate 1 (partly) |
| **2** | Security Regression & Boundary Re-assertion | ⬜ blocked on Wave 1 | 9 | ❌ needs Wave 1 + EB-1 | Gate 2 (security) |
| **3A** | Schema-contract truth | ⬜ blocked on Wave 1 | 21 | ❌ | Gate 1 |
| **3B** | Error contract | ⬜ blocked on 3A | 26 | ❌ | Gate 2 (error) |
| **3C** | Fabrication removal | ⬜ blocked on 3B | 6 | ❌ · needs PD-B09, PD-B13 | Gate 2 |
| **4** | Core Member Journey | ⬜ blocked | 34 | ❌ · needs PD-B01, PD-B02, PD-B03, PD-B04, PD-B21 | Gate 2 (journey) |
| **5** | AI / Intelligence | ⬜ blocked | 64 | ❌ · needs EB-2/3/4/7, PD-A02, PD-D01, PD-D08, PD-A07 | Gate 3 |
| **6** | Billing & Entitlements | ⬜ blocked | 35 | ❌ · needs EB-5, PD-E01…PD-E08 | Gate 4 |
| **7** | Secondary Surfaces & Compliance | ⬜ blocked | 61 | ❌ · needs PD-B*, PD-D03…PD-D06, PD-F03 | Gate 4 |
| **8** | Testing Maturity & Release Engineering | ⬜ blocked | 48 | ❌ · needs EB-8, EB-11, PD-A17, PD-A25, PD-A26, PD-F04 | Gates 5, 7, 8 |
| **9** | Manual QA Gate | ⬜ blocked | — | ❌ · needs Gates 0–5 | Gate 6 |
| **10** | Production rollout | ⬜ blocked · **requires separate explicit authorization** | — | ❌ | Gate 9 |

---

## 3. Status counts

| Status | Count | Note |
|---|---:|---|
| `DISCOVERED` | 0 | all triaged in Wave 0 |
| `DUPLICATE` | 118 | collapsed; see registry §3. **Retired IDs must not be used as tracking keys** |
| `ALREADY_FIXED` | 37 | −2 at `2a8d0b6`: SEC-11, OBS-4 (registry §7.9). **SEC-09 stays** — owner ruling 2026-08-25: its closure needs I-MIG-03 `VERIFIED_CLOSED`, not only FG-1. The rest hold — the Phase 2 cohort needs a row-by-row map to the AFTER matrix, and `WRK-07`/`WKA-04` carry open regressions (`EC-11`, `EC-05`) |
| `FIX_IN_PROGRESS` | 0 | |
| `BLOCKED_DECISION` | 48 | 31 have a mechanical half that is **not** blocked · +1: W1B-N3 |
| `BLOCKED_ENVIRONMENT` | 24 | `R-06`→EB-12 in; `TST-1` out (VERIFIED_CLOSED) |
| `READY_TO_REMEDIATE` | 177 | −1: `ENV-3` → `REMEDIATED` (W1-T3, 2026-08-25) · **−1 at `388b5c1`: `SEC-R1` → `VERIFIED_CLOSED` (registry §7.10)**. `SEC-R2`/`SEC-R3` stay here understated: four of five evidence states present, `VERIFIED END-TO-END` outstanding, and §2 has no status for that position — owner ruling requested (§7.10) · **−1 at `80f248e`: `ERR-1`/`EC-01` → `VERIFIED_CLOSED` (registry §7.13)** · **−1 at `7b944aa`: `UIX-1`/`M-03` → `VERIFIED_CLOSED` (registry §7.18)** — this figure had been carrying `UIX-1` since §7.16 moved its status text to `REMEDIATED` without moving the count |
| `REMEDIATED` | 4 | `K-26` (D-1(L) pending), ENV-6 (PR run pending), `LRE-34`, `REL-36`, ~~`ENV-3`~~ *(promoted 2026-08-25)* *(plus the UIX-2 text half and `LRE-35` inside the `LRE-09…42` aggregate, counted at their parent rows)* |
| `RETEST_REQUIRED` | 0 | |
| **`VERIFIED_CLOSED`** | **29** | 23 at `6d42b10` (registry §7.8) **+3 at `2a8d0b6`** (registry §7.9): **ENV-3, SEC-11, OBS-4** · **+1 at `388b5c1`** (registry §7.10): **SEC-R1 / F-J-01** · **+1 at `80f248e`** (registry §7.13): **ERR-1 / EC-01**, carrying its alias **EC-23**. ⚠ **`F-J-12` (§7.12) and `I-WRK-01` (§7.15) are the 29th and 30th `VERIFIED_CLOSED` findings and neither is in this figure** — both are §7 P1 rows and that register has no per-row status field, so their current buckets cannot be determined from this repository. Left uncounted rather than guessed. `I-WRK-01` closed on **VERIFIED LIVE** at CI run **#41** `33129000361` — pre-fix `RESULT len=0` / `ASSERT-NONEMPTY FAIL` against `654b09c^`, post-fix `RESULT len=3` / `ASSERT-ALL PASS`, one live QA fixture, `CLEANUP verified remaining=0`. **+1 at `7b944aa`** (registry §7.18): **`UIX-1` / `M-03`**, closed on **VERIFIED END-TO-END** at CI run **#49** `33200559221` — the real `/appointments` route through the real `PaywallGate`, `A1 surface-reached=true` · `A1 paywall-locked=false` · `A2 coach-rendered=true` (`Coach P1 coach`, read from `public_profiles`) · `A3 ready-state=true` and its three negative arms · `ASSERT-ALL PASS`, with `CLEANUP verified availability=0 active-relationships=0` |
| `DEFERRED` | 0 | |
| `RELEASE_BLOCKER` | 56 | a gate attachment, not a severity — counted inside the rows above |
| **Canonical total** | **319** | 310 from 428 raw records + 9 Wave 1 batch discoveries (W1B-N1…N9). Status sum: 37+48+24+177+4+29 = 319 ✓ |

| Severity | Open | Fixed | Total |
|---|---:|---:|---:|
| **P0** | 42 | 12 | 54 |
| **P1** | 111 | 18 | 129 |
| **P2** | 121 | 14 | 135 |
| **P3** | 63 | 8 | 71 |
| **Total** | **337** | **52** | *(389 — exceeds 310 because 79 findings are counted at both a fixed-half and an open-half severity; each split is stated in its row)* |

---

## 4. Why nothing is `VERIFIED_CLOSED`

52 findings are `ALREADY_FIXED`. **None qualifies for `VERIFIED_CLOSED`,** and the reason
is the same for all of them:

- Their live evidence — 270 assertions for Phase 1, 20 for Phase 2 — was captured at a
  point in time and **has not been re-run since.** `npm run test:security` requires
  `QA_SERVICE`, which exists in no working copy (**EB-1**), and it runs in no CI
  (**ENV-6**).
- The posture has demonstrably drifted since: **five closed findings regressed**, three of
  them introduced by the very migrations that closed other findings (registry §4.2).

`ALREADY_FIXED` is therefore the honest state. It becomes `VERIFIED_CLOSED` in Wave 1,
when the suites execute in CI for the first time — **not before, and not by assertion.**

**Resolution, 2026-08-26:** that condition was met at CI commit `6d42b10` — 271/271 live
security across the six suites. Thirteen of the fifty-two promoted; the remaining
thirty-nine stay for exactly the reasons above (Phase 2's live suite still absent from
CI — FG-2; §4.2 regressions; decision-coupled halves). Registry §7.8 is the record.

---

## 5. Decision board

**8 of 73 are on the critical path.** Nothing in Waves 1, 2, 3A or 3B is blocked by any of
them — that was deliberate in the sequencing.

| Rank | Decision | Owner | Status | Stalls |
|---:|---|---|---|---|
| 1 | **PD-D08** — name a clinical owner | Julia | ⬜ **open · take this first** | Wave 5.7 |
| 2 | **PD-B01 + PD-B02** — daily vs weekly check-in; the canonical column family | Julia | ⬜ open | Wave 4 (12 findings) |
| 3 | **PD-A02** — the certification predicate | Julia + clinical | ⬜ open | Wave 5.2 · *and whether the substrate bootstrap is safe at all* |
| 4 | **PD-D01** — PAR-Q policy | **Clinical** | ⬜ open | Wave 5.7 |
| 5 | **PD-A17 + PD-A10** — where the API runs; which nutrition backend is canonical | Julia | ⬜ open | Waves 1 and 5 |
| 6 | **PD-A26 + PD-A25** — PITR vs forward-only; what beta is | Julia | ⬜ open | Wave 8, the whole rollout chain |
| 7 | **PD-F02** — launch platform | Julia | ⬜ open | whether PD-F01's weeks of IAP work are on the critical path |
| 8 | **PD-E07 + PD-E08** — is production billing real; which tier ladder is the target | Julia | ⬜ open | Wave 6 |

**Answered: 5** — **`PD-A23` (2026-08-28, option (b): the booking screen drops the PostgREST
embed and reads coach profiles in a second query against `public_profiles`; **no migration**;
owner column **engineering** — registry §7.16, rationale in
[`decision-log.md`](decision-log.md)). The second `ANSWERED` row; it does not close `UIX-1`,
whose class terminates at VERIFIED END-TO-END.** Plus **`PD-A05` (2026-08-27, option (a): decision-trace reads are scoped to subject +
`created_by` + active coach + `admin`; `content_manager` excluded — registry §7.11, rationale in
[`decision-log.md`](decision-log.md)). The first `ANSWERED` row in
[`MASTER_PRODUCT_DECISIONS.md`](MASTER_PRODUCT_DECISIONS.md); it does not close `F-J-12`, whose
authorized policy is not yet implemented.** Plus Q-A (the engine prescribes), Q-B (End Workout semantics), and three
questions that turn out to be settled by `product-bible.md` §6 and `decision-log.md` and
are therefore **findings, not decisions** (decisions doc §0.2).

**Open: 71** — A:24 *(−1: `PD-A05` answered 2026-08-27; −1: `PD-A23` answered 2026-08-28)* · B:27 · C:5 · D:8 · E:8 · F:4 · G:4 *(some groups overlap where a
decision needs two authorities).*

---

## 6. Environment blocker board

| ID | Blocker | Owner | Status | Blocks |
|---|---|---|---|---|
| **EB-1** | No `QA_SERVICE` key in any working copy | QA key holder | ✅ **RESOLVED 2026-08-25** — secrets provisioned; live-qa executed (surfaced W1B-N8) | 188 live assertions; every security closure |
| **EB-2** | Zero Edge Functions deployed to QA; `secrets: []` | DevOps | ⬜ open | Wave 5 entire |
| **EB-3** | QA Vault `project_url` / `service_role_key` unset | DevOps | ⬜ open | the coaching crons |
| **EB-4** | Intelligence substrate empty — 0 profiles / 621 exercises, 0 graph nodes | Content + PD-A02 | ⬜ open | any real engine decision |
| **EB-5** | No QA Stripe account, runbook, endpoint, secret or price ids | DevOps + finance | ⬜ open | Wave 6 entire |
| **EB-6** | `API_BASE_URL` empty everywhere; the API runs nowhere | PD-A17 | ⬜ open | the AI Nutrition Coach in all environments |
| **EB-7** | Resend sender domain unset — mail reaches only the account owner | DevOps | ⬜ open | every email test |
| **EB-8** | No Deno runtime; no `deno.json` in `supabase/` | DevOps | ⬜ open | all 19 Edge Function tests |
| **EB-9** | No runtime UI harness — no driver, no device | QA | ⬜ open | every UI finding's end-to-end evidence |
| **EB-10** | No QA content-editor or coach credential | QA key holder | ⬜ open | library re-measurement, H-06 coach half |
| **EB-11** | No staging environment, no `dart_defines/staging.json` | Release eng | ⬜ open | Gate 5 entire |
| **EB-12** | No Management API credential; HIBP state not exposed read-only. One owner dashboard action: QA → Authentication → Policies → "Prevent use of leaked passwords", record before/after | Product owner / DevOps | ⬜ **open · added by Wave 1 batch** | `R-06` (task 9) |

---

## 7. Gate board

| Gate | Rows | Met | Status |
|---|---:|---:|---|
| **Gate 0** — Merge to `main` | 14 | — | 🟨 CI exists and is green (`6d42b10`); formal row scoring at the Wave 1 exit review |
| **Gate 1** — QA promotion / contract truth | 9 | 0 | ❌ · **row 1.7 MET** (a member can write injuries / pregnancy / postpartum — F-J-17 live 8/8, runs #27 and #32) · 1.2 met via ENV-3 · blocked on 1.1 (Gate 0), 1.3, 1.4→1.5, 1.6, 1.8, 1.9 |
| **Gate 2** — Security & error contract | 13 | 0 | ❌ · row 2.2 (live suite) **executed 2026-08-26: 271/271** · **row 2.6 MET at run #32** (decision-trace reads scoped per PD-A05 (a), probe coach holding zero relationships — registry §7.12) · blocked on 2.1 (Gate 1), 2.3 (§4.2: `EC-05`/`EC-11` open), 2.5 (`E-NUT-17`), 2.7 (`I-NOT-04`, Q-10); error-contract rows 2.8–2.13 remain Wave 3B |
| **Gate 3** — AI enablement | 15 | 0 | ❌ · EB-2, EB-3, EB-4 |
| **Gate 4** — Commerce enablement | 14 | 0 | ❌ · EB-5 |
| **Gate 5** — RC → staging | 13 | 0 | ❌ · EB-11 |
| **Gate 6** — Manual QA sign-off | 8 | 0 | ❌ |
| **Gate 7** — TestFlight internal | 9 | 0 | ❌ |
| **Gate 8** — TestFlight external | 9 | 0 | ❌ |
| **Gate 9** — Submission → rollout | 15 | 0 | ❌ · **requires separate explicit authorization** |

---

## 8. Baselines — the numbers a regression is measured against

Measured **2026-08-24 in this session**, against the current working tree.

| Suite | Command | Result |
|---|---|---|
| Flutter | `cd apps/mobile && flutter test` | **730 passed · 9 skipped · 0 failed** |
| Flutter analyzer | `flutter analyze` | 0 errors · 15 warnings · 156 infos |
| API unit | `npm test --workspace apps/api` | 58 passed |
| API e2e | `npm run test:e2e --workspace apps/api` | 6 passed |
| Schema contract | `npm run test:contract` | exists · 2 relations + 8 columns allowlisted |
| **Live security** | `npm run test:security` | **NOT RUN — no `QA_SERVICE` (EB-1). 188 assertions across 6 suites** |
| **Live AI** | `npm run test:ai` | **NOT RUN — EB-1 / EB-2. 5 suites** |
| **Live workout SQL** | `supabase/scripts/live-evidence.sh` (FG-2) | **EXECUTED 2026-08-25 at `2a8d0b6` — FG-2a 20/20 · FG-2b 15/15 = 35.** The "32" was Workstream N's static, pre-execution inventory of the same two unchanged files; the executed count is authoritative (registry §7.9) |
| **Edge Function** | *(none exist)* | **0 — no Deno runtime (EB-8)** |

> **Every count quoted in a workstream report — 514 / 591 / 623 / 667 / 690 / 699 — is a
> snapshot of a tree that several sessions were writing to concurrently. `730 / 9 / 0` is
> the Wave 0 baseline. No count below 730 is a regression signal on its own.**

**Post-batch (2026-08-24, [`WAVE_1_BATCH_CLOSURE.md`](WAVE_1_BATCH_CLOSURE.md)):**
`flutter test` **750 / 9 / 0** (20 net-new tests, each shown failing against the restored
defect) · analyze 0 errors · API 58 + 6 · `npm run check:guards` 10/10. Measured by the
batch session against the uncommitted tree; **becomes the standing baseline only when
ci.yml reproduces it after the custody commit.** The three static guards were
independently re-run at the custody checkpoint (2026-08-25) and pass.

**Standing live baseline (2026-08-26, CI `6d42b10`):** live security **271/271** across
six suites (D-01 43/43 · D-02 40/40 · D-03 27/27 · 1D 54/54 · 1E 73/73 · 1F 34/34) ·
live AI suite pass (characterization level) · contract suite pass (allowlist intact) ·
overall workflow green. Any future count below these is a regression signal.

### 8.1 Suite composition — the number that matters more than the total

| Class | Tests | Share | Proves |
|---|---:|---:|---|
| Behavioural — runs the real code | 268 | 38% | the product behaves as asserted |
| Static source guards | 172 | 25% | the committed source cannot express a known hole |
| **Replica / self-referential** | **259** | **37%** | **nothing about the product** |

*(Measured by Workstream N at 699 total; the 31 tests added since have not been
reclassified. Replica conversion is Wave 8 item 8 — **convert, never delete**.)*

---

## 9. Working-tree custody — **CLOSED by W1-T1**

**Resolved 2026-08-24.** The programme is now represented in Git across five commits.

| Item | Wave 0 said | Actual | Status |
|---|---:|---:|---|
| Untracked migrations — incl. **113–118** (all Phase 1) and **119–122** (all Phase 2) | 20 | **20** | ✅ tracked |
| Historical migrations edited in place | 15 | **15** | ✅ tracked, isolated in one commit |
| Untracked Dart test files | 22 | **20** | ✅ tracked |
| Untracked Supabase QA harnesses | *not counted* | **25** | ✅ tracked |
| Untracked production source the app will not compile without | 2 | **2** | ✅ tracked |
| Untracked documents | 18 | **29** | ✅ tracked |
| **Total** | **62** | **96** | ✅ **0 untracked non-ignored files remain** |

**⚠ Wave 0 undercounted by 34 files.** `git status` collapses a wholly-untracked directory
into a single entry, and Wave 0 counted status lines rather than files. `supabase/tests/` —
25 files holding **every live security and AI probe in the repository** — appeared as one
line. Full correction in
[`WORKING_TREE_CUSTODY_MANIFEST.md`](WORKING_TREE_CUSTODY_MANIFEST.md) §1.1.

## 10. Regression watch

Permanently visible. A closed regression stays listed with its guard.

| ID | Regressed | By | Guard that should have caught it | Status |
|---|---|---|---|---|
| **F-J-01** | SEC-04's authorization guard on `materialize_program_week` | migration 119 | none existed — `d04` asserted 4 of 5 wrappers individually rather than the class | ⬜ **open** · Wave 2 |
| **F-J-17** | PAR-Q server-authority, by making risk unrecordable | migration 115 itself | no test executed `derive_parq_risk`; `SEC-023` pins its *text* | ⬜ open · Wave 2 |
| **F-J-07** | `build_workout`'s under-recovery rule | migration 089 | no engine test exists at all (`ENG-20`) | ⬜ open · Wave 2 |
| **EC-05 / N-07** | WKA-04, the orphaned `in_progress` session, through the error path | pre-existing; unchanged by Phase 2 | `EC-G1` **does not read `active_workout_screen.dart`** | ⬜ open · Wave 3B |
| **EC-11** | WRK-07 — the swallow moved one layer down | pre-existing service layer | `EC-G1` reads only `workout_provider.dart` | ⬜ open · Wave 3B |

**Class fix — `I-MIG-03`, Wave 2:** generalise `SEC-027` so that no migration may redefine
a function carrying an authorization wrapper, a `search_path` pin or a security trigger
without carrying them forward. **This is the only reason to expect the next
Phase-1-equivalent to hold.**

---

## 11. First parallel batch — task board

Wave 1's opening batch. Full justification in
[`MASTER_REMEDIATION_WAVES.md`](MASTER_REMEDIATION_WAVES.md) §"First safe parallel batch".

| # | Task | Findings | Owner | Status |
|---:|---|---|---|---|
| 1 | **Commit the tree** — 5 reviewable slices (§12) | ENV-1 | release eng | ✅ **COMPLETE** |
| 2 | `APP_ENV` → `dev`; prod constants out of the binary; ENV-012 inverted | ENV-4, `K-26` | mobile | ✅ **REMEDIATED** (2026-08-24) |
| 3 | Three harnesses take their target from env and refuse production | ENV-5 | mobile | ✅ **REMEDIATED** (2026-08-24) |
| 4 | `ci.yml` | ENV-6 | release eng | ✅ **REMEDIATED** — has never executed; first run requires the custody commit + push |
| 5 | `[functions.*] verify_jwt` per function | `E-09` | backend | ✅ **REMEDIATED** — deployment gated by **W1B-N5** (never `config push`) |
| 6 | `.temp` untracked; seed guard refuses a non-QA ref | `LRE-34`, `REL-36` | release eng | ✅ **REMEDIATED** — guards proven in a local container only |
| 7 | Release-mode route gate | REL-3 | mobile | ✅ **REMEDIATED** (incl. recorded affordance-gating scope extension) |
| 8 | Correct the false account-deletion claims | UIX-2 text half | mobile | 🟨 **REMEDIATED · wording REQUIRES_REVIEW** — replacement text promises an email deletion path (30-day window) with no recorded owner decision; **held for owner approval before commit** |
| 9 | Leaked-password protection on QA | `R-06` | DevOps | ⛔ **BLOCKED — EB-12.** Preserved; HIBP state unverified, not disproven. Owner dashboard action + recorded before/after required |

Closure evidence: [`WAVE_1_BATCH_CLOSURE.md`](WAVE_1_BATCH_CLOSURE.md). Statuses are
`REMEDIATED` (FIXED IN CODE), **not** `VERIFIED_CLOSED` — the tree is uncommitted, CI has
never run, and EB-1 still blocks the live suites.

### 11a. Wave 1 batch discoveries

Five new findings, **W1B-N1…W1B-N5**, registered in
[`MASTER_REMEDIATION_REGISTRY.md`](MASTER_REMEDIATION_REGISTRY.md) §7.7 with root causes
and waves. **W1B-N5 is a Wave 5.0 entry precondition:** the `[functions.*]` block may be
deployed only per function via `supabase functions deploy` — never `supabase config
push` — until `config.toml` is reconciled with QA's live configuration.

**Deliberately excluded from the first batch** — each is defensible and each is wrong:
migration 123 *(one analytical act, one owner, sequential)*; migration 124 *(numbers are
assigned; 123 lands first)*; the five schema column renames *(they share
`known-violations.json`, and three of them land in one file — they are the first batch of
Wave 3A, sequenced behind CI so the ratchet has something to enforce against)*.

---

## 12. W1-T1 — working-tree custody · **COMPLETE**

**Completed 2026-08-24.** Full inventory and rationale:
[`WORKING_TREE_CUSTODY_MANIFEST.md`](WORKING_TREE_CUSTODY_MANIFEST.md).

### The five commits

| # | Hash | Files | Commit |
|---:|---|---:|---|
| 1 | `f8f4490` | 30 | `docs: place the QA remediation programme under version control` |
| 2 | `2b3d857` | 20 | `db: track migrations 000 and 104-122, including all Phase 1 and Phase 2 work` |
| 3 | `99492df` | 25 | `db: track the in-place migration corrections, seed rebuild and QA CLI link` |
| 4 | `11fbc6a` | 20 | `app: track the workout-contract source, including two files the build requires` |
| 5 | `8e47f07` | 52 | `test: track every standing guard and QA harness in the programme` |
| | **total** | **147** | on top of `39ca39c` |

**Five slices, not the four Wave 0 proposed.** The 20 *new* migrations and the 15
*in-place-edited* ones were separated. Finding **ENV-2** (P0) requires enumerating the
semantic delta of each of the 15 for forward migration 123 — isolated, `git show 99492df`
**is** that enumeration input, permanently. Mixed into a 35-file commit it would have to be
re-derived at every review.

### Included

Wave 0 orchestration artifacts (6) · A–N evidence reports (14) · phase artifacts (6) ·
approved roadmaps (2) · migrations `000` and `104`–`122` (20, incl. all of Phase 1 and
Phase 2) · the 15 in-place-edited migrations · seeds (2) · `config.toml` · `.temp` CLI link
(7) · application source (18, incl. the 2 compilation-critical files) · `dart_defines/qa.json` ·
`ai-generate-workout/index.ts` · Dart guards (20) · Supabase QA harnesses (25) ·
`package.json` · `.gitignore`.

### Intentionally excluded — **left on disk, nothing deleted**

`dist/`, `apps/api/dist/`, `apps/mobile/build/`, `.dart_tool/`, `node_modules/` (build
output and caches) · `.env`, `.env.local`, `apps/api/.env` (local secrets — verified
ignored, and **no `.env` file is tracked**) · `supabase/tests/security/ids.json` (generated
fixture identities, newly ignored) · `.claude/settings.local.json` ·
`supabase/.temp/cli-latest`.

### Remaining untracked non-ignored files

**Zero.** `git status --short` is empty; `git diff HEAD --stat` is empty.

### Anomalies found during custody

1. **Wave 0 undercounted the untracked set by 34 files** — 62 reported, **96** actual.
   `git status` collapses a wholly-untracked directory into one entry and Wave 0 counted
   status lines. **`supabase/tests/` — 25 files holding every live security and AI probe —
   was counted as a single item.** Corrected here and in §9.
2. **`supabase/.temp/` was tracked *and* ignored.** `.gitignore:29` carries `**/.temp/`,
   but the eight files predate it and a tracked file overrides its ignore rule — `LRE-34`
   confirmed exactly as reported. Committing them **removed six production references and
   added none**: they move the CLI link from the production project to QA. Left
   uncommitted, a `git checkout` would have restored the **production** link. Untracking
   them properly is Wave 1 batch task 6.
3. **The seed diffs introduce QA fixture-account passwords not present in `HEAD`.** Three
   bcrypt-hashed literals for seeded fixture accounts; two are already published in
   `docs/`. Not production or third-party credentials. The real exposure is **`REL-36`** —
   `config.toml` runs the seeds on `supabase db reset` and nothing yet refuses a non-QA
   project ref. **`REL-36` is raised P2 → P1** and pulled into the Wave 1 batch.
4. **Two credential-shaped literals were found and cleared.** Both decode to
   `role=anon` — a QA publishable key in `dart_defines/qa.json`, and the pre-existing
   production publishable key in `tool/live_integration_test.dart` (which is finding
   `ENV-5`, unchanged and committed as-is). **No `service_role` key, no `sk_live_`/
   `sk_test_`, no `whsec_`, no `sk-ant-`, and no connection string with a password appears
   anywhere in the committed set.** Twelve further matches on the *name* `service_role_key`
   were each inspected and are Vault secret names, guard-test regexes or report prose.

### Verification

| Check | Result |
|---|---|
| `git status --short` | **empty** |
| `git diff HEAD --stat` | **empty** |
| Untracked non-ignored files | **0** |
| All 146 pre-existing candidates tracked | **yes, 0 missing** |
| `flutter test` | **730 passed · 9 skipped · 0 failed** — identical to the pre-custody baseline |
| `npm run test:api` | **58 + 6 passed** |
| Work lost | **none.** No reset, stash, clean, checkout, revert, delete or overwrite was performed |
| Production contacted | **no** |
| Any environment contacted | **no** |

*Commits 1–4 are not individually test-green: slice 4 lands application changes whose
matching test updates arrive in slice 5. This is correct for a custody split, which
optimises for recoverability, not for a green build at every intermediate SHA. Only `HEAD`
is asserted green, and it is.*

---

## 13. Change log

| Date | Change |
|---|---|
| 2026-08-24 | **Wave 0 complete.** 428 raw records reconciled to 310 canonical findings; 118 aliases retired; 14-cause root-cause model established; **5 regressions identified, 3 of them introduced by the migrations that closed other findings**; 52 findings confirmed `ALREADY_FIXED` and **none promoted to `VERIFIED_CLOSED`**; 73 decisions extracted; 11 environment blockers named; 10 gates defined; baseline re-measured at **730/9/0**. Six artifacts created. **No code, migration, test or configuration changed. No environment contacted.** |
| 2026-08-24 | **New finding, from Wave 0 rather than from A–N:** the approved `ROADMAP_AI_MONETIZATION_UNIT_ECONOMICS.md` commercial architecture and the implemented tier ladder do not match. Filed as **PD-E08** |
| 2026-08-24 | **W1-T1 complete.** 147 files placed under version control in five reviewable commits (`f8f4490`, `2b3d857`, `99492df`, `11fbc6a`, `8e47f07`). Working tree clean, zero untracked non-ignored files, suites at baseline (730/9/0 and 58+6). Wave 0's custody count corrected from 62 to **96**. `REL-36` raised P2 → P1. **Nothing deleted, reverted or discarded; no environment contacted.** |
| 2026-08-24 | **Three questions retired as already-answered** by `product-bible.md` §6 and `decision-log.md`: the engine's certification gate, LLM-derived `intensity_delta`, and the coach approval matrix. Each is reclassified from *open decision* to *contract violation* |
| 2026-08-24 | **Wave 1 parallel batch tasks 2–9 executed.** Tasks 2–8 `REMEDIATED` (task 8 wording `REQUIRES_REVIEW`); task 9 `BLOCKED` on new **EB-12**. Suites 750/9/0 · 58+6 · guards 10/10 (uncommitted tree). Five new findings **W1B-N1…N5** (registry §7.7); **W1B-N5 recorded as a Wave 5.0 entry precondition**. `REL-36`'s seed guard, the reset wrapper (`LRE-35`) and the edge-function config guard added. **No QA mutation; production not contacted.** Evidence: `WAVE_1_BATCH_CLOSURE.md` |
| 2026-08-25 | **Custody checkpoint prepared** (orchestrator). Batch reconciled against the tree; classifications confirmed; W1B-N1…N5 registered in registry §7.7; EB-12 added; counts moved (310→315 canonical, 8 `REMEDIATED`); config-push prohibition written into `config.toml`, `qa-environments.md` and Wave 5 prerequisites; commit slices prepared for owner execution. **Registry and this board updated together per the §1 update rule. No environment contacted.** |
| 2026-08-25 | **First CI run (`9319c67`) red on the production-ref guard** — `ci.yml` and `qa-db-reset.sh` named the production ref. Classified **B** (refusal/assertion references, no executable production path). Remediated by rewriting all three usages in QA-allowlist form with no production literal (artifact scan now fails on *any* foreign project ref) and adding `--untracked` to the guard scan, closing the local-green/CI-red blind spot. Filed + closed as **W1B-N6** (registry §7.7). Guards re-run locally: all green; the two files reproduce the CI failure under the corrected guard before the fix and pass after. **No commit/push performed; CI must reproduce. No environment contacted.** |
| 2026-08-25 | **CI run for `aac64b3` red on the ENV-4 inline check — filed and remediated as W1B-N7** (registry §7.7). The check's over-broad patterns matched doc placeholders in `app_env.dart` (lines 11/13) on the step's first-ever execution; W1B-N6's production-ref guard fix **passed in the same run** (its first CI evidence), as did migration hygiene, edge config, Flutter (incl. the new artifact allowlist scan) and API; live-qa was skipped by the failed dependency, so the EB-1 skip path remains unobserved. Fix: real-material-only patterns + an inline pattern self-test (placeholder-vs-real regression guard); comments remain scanned. Old/new behavior and self-test integrity demonstrated locally; all other static guards re-run green. **Prepared only — `.github/` is bridge-protected: corrected ci.yml staged at `docs/cowork/pending-cifix/ci.yml` for owner copy. No commit/push; no environment contacted.** |
| 2026-08-25 | **First live-qa execution (EB-1 resolved: `QA_URL`/`QA_ANON`/`QA_SERVICE` provisioned) reached the security suites and all six stopped at import: `ids.json missing` — filed and remediated as W1B-N8** (registry §7.7). `ids.json` is generated by `setup-identities.mjs` and deliberately untracked, so an ephemeral CI checkout can never hold it; the ci.yml live-qa job omitted the setup step the wave plan assigned to W1-B2. Fix: one creds-gated `setup-identities.mjs` step after the exact-host QA confirmation — idempotent, fixture-namespaced, no deletions; **the programme's first sanctioned standing QA write, explicitly authorized by the product owner 2026-08-25**. Harness untouched; ids.json stays untracked. Prepared via `docs/cowork/pending-cifix/ci.yml` (`.github/` is bridge-protected); **no commit/push; QA not contacted by the orchestrator; production not contacted.** CI must reproduce (expected: setup runs, six suites execute their 188 assertions) |
| 2026-08-25 | **Live security suites executed for the first time since Phase 1: 270/271.** The single FAIL is a fixture defect, filed and remediated as **W1B-N9** (registry §7.7): hosted Supabase Auth rejects `.test` domains at public `/auth/v1/signup` (`email_address_invalid`), so the D-02 public-signup probe 400'd before the trigger; the boundary itself is proven by the passing admin-API metadata probes. Fix: one line — probe address → `p1-signup-public@qa.12circlefitness.com`, the owner-confirmed controlled business domain. No assertion, harness, Auth config or other fixture changed. **No commit/push; QA not contacted by the orchestrator; production not contacted.** Closes at 271/271 in CI |
| 2026-08-26 | **Phase 1 live-evidence reconciliation (owner-approved).** CI at `6d42b10` green: live security 271/271 across all six suites, AI + contract suites pass, W1B-N9's fix verified on the real public signup route. **23 rows promoted to `VERIFIED_CLOSED`** — the programme's first — per the closure-standard class ladder: 13 Phase 1 `ALREADY_FIXED` rows, TST-1, ENV-1, ENV-4, ENV-5, E-09, REL-3, W1B-N6…N9 (full record + retained limitations: registry §7.8). Deliberately held: SEC-04 (F-J-01 blind spot), Q-4/SEC-R2, SEC-09, SEC-11 + Phase 2 cohort (FG-2), SEC-08 (Q-2), ENV-6 (PR run), LRE-34/REL-36/LRE-35, K-26 (D-1(L)), AI domain (EB-2), contract/3A. Two evidence gaps registered, not implemented: **FG-1** (function-search-path.sql into CI) and **FG-2** (workout SQL suite into CI). Count correction: ENV-1 re-bucketed out of READY (stale since W1-T1). `d151ee6` reviewed — reporting-only, no assertion weakened. **Documentation-only change; no environment contacted; production untouched.** |
| 2026-08-25 | **W1-T3 executed — QA migration ledger repaired.** Target independently confirmed as `eyqtldjqpgpljlqvpowh` (12Circle QA) from five agreeing local sources before the write; production not contacted. `supabase migration repair --status applied 113…122 --linked` inserted the ten missing version rows: **113–122 Local-only → Local + Remote**, **123 Local-only → Local-only**, diff exactly ten rows, no other migration-history row changed. **No migration was executed** and **migration 123 remains unapplied** — it is committed (`24187bf`) and locally validated only; excluding it is deliberate, since marking it applied would make a later `db push` skip it. ENV-3's prescribed ledger repair is satisfied → **`READY_TO_REMEDIATE` → `REMEDIATED`**; `VERIFIED_CLOSED` withheld because the CI check named in its own *Tests* field does not exist, and that check's predicate needs a ruling (ledger max 122 vs highest filename 123 is correct-by-design today). ENV-3 is the only status changed. Next gate — applying 123 to QA — requires fresh authorization. *(Date note: the three entries above are stamped 2026-08-26 in error; the true date of that work was 2026-08-25. Left as written rather than retroactively rewritten — flagged for the owner.)* |
| 2026-08-25 | **ENV-3 static contract implemented** (the corrected predicate, static half only). The Tests field's original wording is superseded by a dated additive amendment in the registry: a max-comparison cannot see a hole, asserts *authored == applied* — which 102 and 123 violate by design — and is environment-blind. Replaced by `RELEASE_GATES` 1.2 + 0.9 made mechanical: new `supabase/expected_applied.json` declares QA's frontier (**122**) with **123 explicitly pending**, not applied; new `supabase/scripts/check-migration-manifest.mjs` fails closed on eight declaration defects and reports authored-but-pending without failing; `check-migration-hygiene.sh` gains gate 0.9's missing contiguity half; all wired into `static-guards` (no credentials, no network). **ENV-3 remains `REMEDIATED`** — items 3–6 and 8 of the amended closure list are the live ledger comparison, still blocked on a QA DB credential (FG-1/FG-2 class). No environment contacted; 123 still unapplied and never written to `schema_migrations` to make a check pass. No status changed by this task. |
| 2026-08-25 | **First live SQL evidence executed — CI run `2a8d0b6`, QA `eyqtldjqpgpljlqvpowh`.** FG-1 **5 PASS/0 FAIL** (SP-1 0 unpinned definer · SP-2 0 unpinned of any kind · SP-3 0 pinned outside public · SP-4 2/2 re-pinned · SP-5 0 EXECUTE to PUBLIC/anon) · FG-2a **20/20** · FG-2b **15/15** · ENV-3 ledger **5/5** (L-1…L-4 all 0; L-5 123 rows vs 123 expected; INFO 123 authored and pending). **Verified QA migration state: 000–122 applied; migration 123 authored/committed and declared pending — NOT applied and NOT an applied ledger row.** No migration applied, no `db push`, no `schema_migrations` write; **production untouched**. **FG-2 count reconciled 32 → 35**: the 32 was Workstream N's static pre-execution inventory of the same two files, which have one commit in their history and no loops or conditionals; the executed 20+15 is authoritative and 20 corroborates the Phase 2 matrix's own "20/20 AFTER". N's frozen report is not rewritten. **Promoted to `VERIFIED_CLOSED`: ENV-3** (all eight amended criteria met), **SEC-11** (matrix maps it to AFTER-4a/b/c), **OBS-4** (FG-2b in full). **SEC-09 was drafted as a fourth promotion and withdrawn before commit** — the governance audit found §7.8's "needs FG-1 + I-MIG-03" ambiguous and escalated it rather than deciding; **owner ruling 2026-08-25 (reading B): SEC-09 needs FG-1 AND I-MIG-03 at `VERIFIED_CLOSED`**, so SEC-09 stays `ALREADY_FIXED` and I-MIG-03 stays open in records mode. FG-1's 5/5 remains recorded evidence — necessary, not sufficient (registry §7.9). **Held:** the remaining Phase 2 cohort pending a row-by-row AFTER map; `WRK-07`/`WKA-04` on open regressions `EC-11`/`EC-05`; SEC-04, SEC-R1/R2/R3, F-J-01 and I-MIG-03 unchanged. |
| 2026-08-27 | **Wave 2 P0 governance-ledger reconciliation (Step 2) — owner rulings applied.** Evidence: CI run **#27** (`33032108346`, head `388b5c16`, `success`) — every job and step green, including *Live security*, *Live AI*, *Contract*, *Negative control* and *Live SQL evidence* (FG-1 · FG-2a/b · **F-J-17 8/8** · **F-J-07 10/10** · ENV-3 ledger, frontier **127**). Owner rulings recorded verbatim in registry §7.10: §5.1 **does not** apply to F-J-01 (authorization/security class); FJ17-7 **does** satisfy §5.1's negative test; the 59/60/61 recovery pair **does** satisfy §5.1's negative/positive pair. **Promoted: SEC-R1 / F-J-01 → `VERIFIED_CLOSED`** — migration 124 plus `d04` §8's five-member class assertion with `KNOWN_OPEN` empty (the blind spot that created F-J-01 is now an enforced probe), `j04`-04C's live 403 against a real foreign program, and FG-1 SP-4/SP-5 for §5.2's redefinition clause; all four security-class states present. **NOT promoted: SEC-R2 / F-J-17 and SEC-R3 / F-J-07** — four of five states present, **`VERIFIED END-TO-END` absent**; §2.1 requires all five for an AI/safety-input finding and grants no implementation-time exceptions, and Step 4 is not authorized. Two gaps reported, not closed: **FG-3** (the 116 class's positive legs are asserted nowhere, so over-refusal is invisible) and the **status-vocabulary gap** — §2 has no term for *"every state but END-TO-END"*, so the two rows stay understated at `READY_TO_REMEDIATE` rather than carry a false evidence claim. **SEC-04** is now a consequential promotion candidate and was deliberately left untouched (outside the authorized rows). Counts: `VERIFIED_CLOSED` 26 → 27, `READY_TO_REMEDIATE` 180 → 179, total 319 unchanged. **Documentation only — no code, migration, test or configuration changed; no QA write; production not contacted.** |
| 2026-08-27 | **PD-A05 answered — option (a) — and `F-J-12` reconciled, not closed.** Product-owner ruling: `decision_traces` reads are scoped to **subject + `created_by` + the subject's active coach + `admin`**; **`content_manager` excluded**. **M-1** retains the `created_by` arm on the auditability rationale. **M-3** corrects a false premise carried in the PD-A05 and `F-J-12` rows — *"every sibling table chose 'active coach or admin'"* is not what the migrations say (093/095/096 use `admin + content_manager`; 091 and 089 add `coach`; **no sibling uses `admin` alone**); sibling policies stay separate decisions and were **not** changed. Workstream J's report is frozen evidence and was not rewritten. **M-4** classes `F-J-12` as **SECURITY / AUTHORIZATION** (§2.1 four-state ladder). **`F-J-12` remains OPEN:** applied migration **125** implements option **(b)** — one arm too wide — so FIXED IN CODE and FIXED ON QA are both **absent** against the authorized policy, and the (a)-distinguishing probe (`content_manager` reads nothing) does not exist and would fail today. Three further probes are missing: subject-reads-own, active-coach-positive, and `created_by`. **RLS policies have no durability guard at all** — the I-MIG-03 guard tracks function properties only. Migration 125 is deliberately left unchanged: reverting re-opens a live disclosure hole, and editing it in place would repeat `ENV-2`. The correction is a forward migration and is **not authorized by this ruling**. First `ANSWERED` decision in the programme. Counts: decisions answered 3 → 4, open 73 → 72; **finding status counts unchanged**. **Documentation only — no code, migration or test changed; no test run; no QA write; production not contacted.** |
| 2026-08-27 | **CI run #32 (`ae5be13`) — first fully green run of the Wave 2 P0 programme; evidence reconciled.** Verified against the GitHub API: `33040663330`, head `ae5be138`, `success`, all five jobs green — and **step 11 *Live SQL evidence* executed for the first time since the frontier moved to 128** (runs #30/#31 skipped it: steps are sequential and the AI suite failed at step 9). AI suite **49/49** (J-04 **16/16**), **17/17** characterized defects still reproduce, FG-1 5/5, FG-2a 20/20, FG-2b 15/15, F-J-17 8/8, F-J-07 10/10, **ENV-3 live ledger 129 = 129 with 0 missing / 0 undeclared / 0 stale / 0 holes and nothing pending**. **Promoted: `F-J-12` → `VERIFIED_CLOSED`** — all four SECURITY / AUTHORIZATION states present (class fixed by owner ruling M-4): migration 128; ENV-3's live ledger retires the last inference that 128's `schema_migrations` row exists; `content_manager` reads **0** where the identical probe read **90** at run #30 pre-128; the active-coach and `created_by` arms proved positively in `d05` §9. Retained limitations recorded, not waived: **RLS policies have no durability guard** (I-MIG-03 covers functions only), and J-04A's `neq` filter is NULL-rejecting. **Gate movement: 2.6 MET, 1.7 MET.** **NOT promoted:** `SEC-R2`/`SEC-R3` (unchanged — one state short, VERIFIED END-TO-END) · `ENV-3` and `SEC-11` (already `VERIFIED_CLOSED` since 2026-08-25) · `SEC-09` (FG-1 remains necessary-not-sufficient under the 2026-08-25 ruling) · **`I-MIG-03` escalated as an authority question** — its guard is fail-closed, `KNOWN_OPEN` empty and green, but no document states its closure criterion, and closing it closes SEC-09. `VERIFIED_CLOSED` 27 → 28; **the status-count table is deliberately NOT adjusted** — `F-J-12` is a §7 P1 row and that register has no per-row status field, so its current bucket cannot be determined from this repository. **Documentation only — no code, migration, test or policy changed; no QA write; production not contacted.** |
| 2026-08-27 | **Workstream B Phase B0 complete — `ERR-1`/`EC-01` → `VERIFIED_CLOSED`.** Owner ruling 2026-08-27 placed EC-01 in the **RELEASE / ENVIRONMENT** closure class, whose §2.1 ladder is **FIXED IN CODE · VERIFIED IN CI** and nothing more (the ruling is confined to EC-01 and does **not** extend to EC-05). Both states are now present. **FIXED IN CODE:** `580932f` — `AppFailure` + `reportFailure` sink, vendor-free per PD-A24, plus the seven pre-ERR-1 `print()` call sites converted (closing alias **EC-23**) and §5.1 category 1 (`ScoreEngine._award`/`_penalize`) wired. **VERIFIED IN CI, post-fix half:** run **#33** (`33043897947`, `580932f`) — `flutter analyze` + `flutter test` green, so the sink compiles in context and B0's gate holds. **VERIFIED IN CI, pre-fix half:** run **#34** (`33081949579`, `80f248e`) step 7 — the EC-23 guard demonstrably FAILS against a tree carrying the seven historical `print()` sites and PASSES against the byte-identically restored tree, **in CI**, which is what §2 requires and what §7.12's local algorithmic replay could not supply. **G-3 was not invoked** — a defective tree is recoverable from history, so this is genuine pre-fix evidence, and `ci.yml`'s job header was amended to keep it from being mis-filed as synthetic. The job's two red annotations (*1 passed 1 failed*, *3 passed 4 failed*) are the runner's log parser reacting to the installed mutations: **every step of every job in #34 is `success`** and there is **no `continue-on-error` in the workflow**; the real Flutter job is a separate job, green, with no test-failure annotation. Counts: `READY_TO_REMEDIATE` 179 → 178, `VERIFIED_CLOSED` 27 → 28, total 319 unchanged — **`ERR-1` is a §6 row with a status field, so unlike `F-J-12` it is mechanically countable**; the narrative figure of 29 exceeds the table by exactly `F-J-12`, which stays uncounted for the reason recorded in §7.12. **Documentation only — no code, migration, test, policy or acceptance criterion changed; no QA write; production not contacted.** |
| 2026-08-27 | **`I-WRK-01` tracking home established; `EC-11` dependency reconciled; VERIFIED LIVE recorded as a capability blocker (registry §7.14).** Owner rulings D-1 · D-2 · D-2(b) · D-2(c) · D-3 · D-4 · D-5. **D-1:** `I-WRK-01` now has a **§7.6 row** — canonical key only; `H-01`, `M-07`, `M R-2` stay retired aliases (§3, §10.5) and **no `H-01` row was created**. §6 was not used and could not be: §6 is the P0 register and this finding is P1/P2. **The row is evidence-only and deliberately NOT status-countable** — §7 carries no per-row status field, the same position already recorded for `F-J-12` in §3 above. **No status count moved and no total changed** (37+48+24+178+4+28 = 319 unchanged); §5 counts canonical findings rather than rows, and `I-WRK-01` was already inside the Data Contract domain's 33. Which bucket currently holds it **cannot be determined from this repository and was not guessed**. **D-2/D-2(c):** VERIFIED LIVE is required (class **Data contract / schema**; `getExerciseProgression()` is a real read path) and was **not waived** — the ERR-1 RELEASE/ENVIRONMENT ruling was not carried across, and SEC-R2/SEC-R3 precedent (§7.10) forbids an adjacent ruling waiving a state. The stronger pre-fix comparison was **not weakened and not substituted**: it **cannot be executed**, because **no CI job holds both a Flutter/Dart toolchain and a QA credential** (`flutter`/`negative-control` have Flutter and no QA secret; `live-qa` holds all four QA secrets and no Dart toolchain), `flutter test` in CI never reaches `integration_test/`, and no local toolchain or credential exists. **The D-2(b) QA-fixture authorization was NOT exercised** — no QA write and no QA read were performed. `I-WRK-01` is **NOT `VERIFIED_CLOSED`**: three of four required states present. **D-3:** `EC-11`'s `Dep` cell moves from `H-01 first` to **`I-WRK-01` + `I-COM-01` + `I-CHK-01`**, correcting both an under-scope against Workstream H:810 and the use of a retired alias as a tracking key. `EC-10` splits across `I-CHK-01` and `I-LEG-03` (§3); only the checkins half is recorded, and whether `I-LEG-03` also gates `EC-11` stays open, as do the two wider statements (Workstream H:796/868's Wave H-A batch; `MASTER_REMEDIATION_WAVES.md:260`'s "3A complete"). **`EC-11` NOT started; `H-02` NOT started; `WorkoutService` untouched.** **D-4/D-5 preserved, not resolved:** severity is P1 in Workstream I and P2 in Workstream H — the two sources disagree, so nothing is mechanically compelled; the site count is self-contradictory in Workstream I (2 sites / 1 site) while waves and the implementation agree on three, but §10.2 makes the A–N reports frozen evidence so the report was not rewritten. **Documentation only — no code, migration, test, policy, CI or acceptance criterion changed; no QA write; no QA read; production not contacted.** |
| 2026-08-28 | **`I-WRK-01` → `VERIFIED_CLOSED` on VERIFIED LIVE — CI run #41 `33129000361` at `8843c33` (registry §7.15).** §7.14 recorded VERIFIED LIVE as **ABSENT** for one reason — *no CI job holds both a Flutter/Dart toolchain and a QA credential* — and D-2/D-2(c) refused to waive it. **The missing capability was built and run.** The `wrk01-live` job (`ci.yml:448`) drives the real `WorkoutService().getExerciseProgression()` from `integration_test/wrk01_progression_live_test.dart` on a Linux desktop target under `xvfb`, **twice against one live QA fixture** — once at the run head and once at the real parent `654b09c^` = `acd2cc5`, whose `workout_service.dart:237,243,246` still name `created_at`, so **`G-3` was not invoked and this is not synthetic evidence**. **Observed PRE-FIX:** `FIXTURE present rows=4` · `SERVICE-CALLED getExerciseProgression` · `RESULT len=0` · `ASSERT-NONEMPTY FAIL`. **Observed POST-FIX, same fixture:** `FIXTURE seeded rows=4` · `SERVICE-CALLED getExerciseProgression` · `RESULT len=3` · `ASSERT-NONEMPTY PASS` · `ASSERT-ALL PASS`. **Closure-standard §7 hygiene:** `CLEANUP verified remaining=0` — proved by a read, not assumed from a `204`. All six jobs and `wrk01-live` steps 1–7 `success`. All four **Data contract / schema** states now present (§2.1); **no waiver, no exception, no criterion changed**, and the ERR-1 RELEASE/ENVIRONMENT ruling was again not carried across. **`VERIFIED END-TO-END` is NOT claimed** — §2 is explicit that VERIFIED LIVE does not prove the user-facing path reaches it. **Counts: none moved.** `I-WRK-01` is a §7 P1 row with no per-row status field, so like `F-J-12` it is **not mechanically countable**; the status table stays `37+48+24+178+4+28 = 319` and the narrative figure moves 29 → 30, the divergence now being exactly those two rows. **Provenance:** the repository-side facts were read at `8843c33`; the run/job/step outcomes and the literal marker lines were transcribed by the product owner from the raw job log under admin credentials (raw logs return HTTP 403 to this programme's read, as §7.13 already records) and were **not inferred** — the job conclusion, the green badge, the *2 tests passed, 1 failed* annotation, the harness's fail-closed control flow, source inspection and the post-fix result were each refused as substitutes for the PRE-FIX observation. **`EC-11` NOT started; `H-02`/`I-COM-01` NOT continued; `WorkoutService` untouched (`catch (` count 14).** **D-4 and D-5 remain unresolved and are carried forward unchanged.** **Documentation only — no application, SQL, migration, RLS, CI, fixture, probe or infrastructure file changed; no QA write and no QA read by this checkpoint; production not contacted.** |
| 2026-08-28 | **`PD-A23` answered — option (b) — and `UIX-1`/`M-03` remediated (Wave 3A task 3A-8; registry §7.16).** Two owner rulings preceded the work. **`PD-A23` = (b)**, owner column **engineering**: drop the PostgREST embed, read coach profiles in a second query against `public_profiles`, join in Dart, **no migration**; option (a) not implemented. **Closure class ruled before remediation — `UIX-1` = PRODUCT INTEGRITY / UI REACHABILITY**, whose §2.1 ladder is **FIXED IN CODE · VERIFIED IN CI · VERIFIED END-TO-END** and which the ruling states does **not** include `FIXED ON QA` or `VERIFIED LIVE`; neither is claimed. **Root cause, from the migrations:** `000_baseline_preexisting_tables.sql:237` makes `coach_client_relationships.coach_id` a FK to **`auth.users`**, and PostgREST cannot traverse a FK outside `public` — hence Workstream M's live `PGRST200` and a screen dead for every client. **FIXED IN CODE:** `booking_screen.dart` only. Two corrections inside it are recorded, not silent: `specialties` is `text[]` (`001:42`) and was cast `as String?` by code the broken embed had never exercised, normalised once at the join; and the `catch` presented a failed read as the confident `noSlots` answer, which is **invariants I-1 and I-5**, now a distinct honest state. **Guard:** the schema-contract guard was blind by construction — it drops bracketed spans whole and read only the first of three adjacent string literals — so `deriveForeignKeys()` plus an embed-resolution check and a two-anchor self-test were added to `supabase/tests/contract/`. Offline, deterministic, no credential; implemented inside the existing contract suite, so **no CI change was made**. *(Provenance correction, 2026-08-28 — registry §7.16 "Correction": this clause previously read "it runs inside `npm run test:contract`, already wired to `static-guards`". The invocation is `ci.yml:399` inside the **`live-qa`** job — `static-guards` has no contract step — and it is **credential-gated** by `if: steps.creds.outputs.present == 'true'`, so the step **skips**, leaving the job green, when the QA secrets are absent. The record described an unconditional static gate; the guard is a conditional one. No state, count, class or decision changed.)* **Evidence, same guard, only `booking_screen.dart` differing:** PRE-FIX (`f109f19`'s file) → `FAIL embed coach_client_relationships.coach_id … at booking_screen.dart:55 (embed 'coach:coach_id' -> auth.users)`, exit 1; POST-FIX → `PASS`, exit 0, `134 foreign keys` derived. The nine allowlist lines are byte-identical in both legs and `known-violations.json` was not edited. **Limitations recorded, not worked around:** the runs are **local**, so **VERIFIED IN CI is PENDING** (§4 — a suite that has never run in CI is not a closure), and **no Dart toolchain exists** on the device or in the container, so `flutter analyze`/`flutter test` did not run and the Dart edit is uncompiled. **`VERIFIED END-TO-END` is ABSENT** — Step 4 is not authorized to begin (§7.10) — so `UIX-1` moves `READY_TO_REMEDIATE` → **`REMEDIATED`**, **NOT `VERIFIED_CLOSED`**. **Counts: none moved** — `VERIFIED_CLOSED` stays 28, canonical total 319. **`EC-11` NOT started; `H-02`/`I-COM-01` NOT continued; `I-WRK-01` NOT reopened (`catch (` count 14); `checkin_screen.dart` NOT touched** (its identical-looking embed resolves into `public` and is not a defect); **`D-4`/`D-5` unchanged**. **No migration, schema, RLS, Edge Function, credential, secret or CI change; no QA write, no QA read; production not contacted.** |
| 2026-08-28 | **CI run #43 at `527438a` reconciled, and the `UIX-1` guard's CI location corrected (registry §7.16 "Correction").** Run #43 is `success` with all six jobs green. **Established:** the Dart edit **compiles in context** — the `flutter` job's steps are sequential and the workflow carries **0 `continue-on-error`**, so green means `flutter analyze` (run as `--no-fatal-infos --no-fatal-warnings`, i.e. no analyzer *errors*), `flutter test` and `flutter build web` all succeeded; and the **post-fix CI leg** of the new embed guard. **NOT established:** §2 defines VERIFIED IN CI as a check that *fails against the pre-fix tree* **and** passes against the post-fix tree, **in CI** — run #43 exercised the guard only against the **post-fix** tree, where there is no defect to find, so its discrimination never ran; only its two self-test anchors did. The pre-fix leg exists solely as a **local** run, and §7.13 already ruled that a local replay *"was honest but it was not 'in CI', and §2 requires 'in CI'"*. **`VERIFIED IN CI` therefore remains PENDING** and run #43 is retained as valid **post-fix** evidence. **Provenance correction:** the UIX-1 record stated the guard was *"already wired to the `static-guards` job"*. It is not — `npm run test:contract` is invoked at **`ci.yml:399` inside `live-qa`**, and that step is **credential-gated** (`if: steps.creds.outputs.present == 'true'`), so it **skips** while the job stays green when `QA_URL`/`QA_ANON`/`QA_SERVICE` are absent. The prior wording described an unconditional static gate; the guard is conditional — the §4 *"a guard nobody runs protects nobody"* concern, and the same class of mis-attribution corrected once before in `I-WRK-01`'s FIXED ON QA clause. **Whether the guard should stay credential-gated is a Gate B design question and was NOT decided, designed or started.** **`UIX-1` remains `REMEDIATED`, not `VERIFIED_CLOSED`; `VERIFIED END-TO-END` remains ABSENT** — not a CI state, and Step 4 is not authorized to begin (§7.10). **Counts unchanged:** `VERIFIED_CLOSED` 28, total 319. **Documentation only — no application, CI, migration, schema, RLS, function, fixture, probe, credential or secret change; no QA write, no QA read; production not contacted.** |
| 2026-08-28 | **`UIX-1`/`M-03` reaches `VERIFIED IN CI` — CI run #44 `33172886167` at `b1a19ae` (registry §7.17).** Gates B-1 and B-2 landed in `b1a19ae`; run #44 is terminal **`success`** with **all six jobs green, 0 skipped steps, 0 non-success steps and 0 `continue-on-error`** in the workflow. **B-2:** `npm run test:contract` moved out of `live-qa`, where it sat behind `if: steps.creds.outputs.present == 'true'`, into `static-guards`, where it has no `if` at all and is **not duplicated** (`live-qa` now contains 0 occurrences). The suite is offline — node builtins only, **no `process.env` read** — so the gate protected nothing while bounding the guard's reach: `known-violations.json` is the both-directions record for `I-WRK-01`, `I-INT-01`, `I-INT-02`, `I-COM-01`, `I-COM-03`, `I-CHK-01`, `I-LEG-03` and `I-NUT-01`, and behind it none was checked on a credential-less run (§4, *"a guard nobody runs protects nobody"*). **`secrets.QA_*` 18 → 15** — a narrowing, no secret added or rescoped. Evidence from the old placement is preserved as historical and conditional and is **not** retroactively reinterpreted. **B-1:** `uix1_negative_control.sh` as `negative-control` step 8, with `fetch-depth: 0` added so `f109f19` is reachable. **Observed (step level):** `static-guards` **step 7** *Schema contract guard* → `success`, and its YAML keys at `b1a19ae` are exactly `name` and `run` — **no `if`** — so it executed and could not be credential-skipped; `negative-control` **step 8** *UIX-1 — embed/FK contract guard* → `success`; `f109f19` is an ancestor of `b1a19ae` and carries the `coach:coach_id(` embed. **Entailed, not observed:** the harness's own output — raw job logs return **HTTP 403** — so the pre-fix non-zero exit, the literal assertion, the absence of any other `FAIL` line and the byte-identical restore are read from the step's exit status under `set -euo pipefail` with a `die` on every branch. **Owner ruling 2026-08-28: §7.13's entailment standard governs this rung** — the same standard that closed `ERR-1` — and it is **confined to this rung**; §7.15's literal-log requirement for `I-WRK-01`'s VERIFIED LIVE is untouched. **`G-3` NOT invoked:** `f109f19` is a real recoverable defective tree, so this is genuine pre-fix evidence, never to be filed beside the synthetic WKT-204 / M-1-M-2-M-3 steps. The red annotations under the green jobs are EC-23, WKT-204 and the I-WRK-01 probe's own expected shapes — the runner's Flutter log parser, as §7.13 established for run #34; **none relates to UIX-1**, whose guard is a node script. **`flutter`:** analyze, test and QA web build all `success` (analyze runs `--no-fatal-infos --no-fatal-warnings`, so this is no analyzer *errors*, not zero lints). **`VERIFIED END-TO-END` remains ABSENT** — not a CI state, Step 4 unauthorized (§7.10) — so `M-03` is **NOT `VERIFIED_CLOSED`** at **two of three** class states. **`M-03` stays `REMEDIATED`, now deliberately understated:** §2 has no term for *"every state but END-TO-END"*, and this is the **second instance** of the status-vocabulary gap §7.10 escalated for `SEC-R2`/`SEC-R3`; that owner ruling now governs two findings. **Counts unchanged:** `VERIFIED_CLOSED` 28, total 319. **Documentation only — no implementation, CI, test, migration, schema, RLS, function, fixture, probe, credential or secret change; no QA write, no QA read; production not contacted.** |
| 2026-08-28 | **`UIX-1`/`M-03` → `VERIFIED_CLOSED` on VERIFIED END-TO-END — CI run #49 `33200559221` at `7b944aa` (registry §7.18).** All **7** jobs `success`; the `uix1-e2e` job `98949037130` steps 1–7 all `success`. The driver pumps the real `CircleFitnessApp`, reads the real `routerProvider` and navigates `/appointments`, so the real `PaywallGate(required: ClientPlan.coachGuided)` is exercised — **BookingScreen was not mounted directly** and no mock, fake, web/Android/iOS or target substitution was used; the fixture is built under existing RLS with the committed `p1-victim`/`p1-coach` QA identities and **no service-role credential**. Step 6 entails, through a `set -euo pipefail` harness that requires each marker as a literal and separately checks the run's exit code: `A1 surface-reached=true` · `A1 paywall-locked=false` · **`A2 coach-rendered=true`** (`Coach P1 coach`, the exact `public_profiles` read the PGRST200 embed defect made impossible) · `A3 ready-state=true` and its three negative arms · `ASSERT-ALL PASS`; step 7 supplies §7 hygiene via the literal `CLEANUP verified availability=0 active-relationships=0`, proved **by a read**. **Owner ruling 2026-08-28: §7.13's entailment standard extends to this rung for this row** — raw logs still 403, so the markers are entailed from exit status plus harness source at the executed SHA, not literally read. **§7.15's literal-log requirement for `I-WRK-01` is untouched and the ruling does not reach `SEC-R2`/`SEC-R3`.** Two latent rendering defects, both masked by the original embed failure (which made `_BookingState.ready` unreachable), were exposed and repaired first: `aaa23c6` gave `_pumpUntil` an untyped catch that prints the exception under `UIX1-DIAG` and **`rethrow`s unchanged** (observability only — timeout, interval, finder, A1/A2/A3 and teardown byte-for-byte as before), which surfaced **`BoxConstraints forces an infinite width.`** on `_SlotCard`'s Book button; `7b944aa` added `minimumSize: const Size(0, 54)` to the existing `styleFrom`, overriding only the width component of the theme's full-width CTA minimum (`helix_theme_builder.dart:44`) — the assertion was **not** suppressed or caught, the themed 54px height is preserved and no fixed width was introduced. The later `child.hasSize` / `RenderSliverMultiBoxAdaptor` assertion was the downstream consequence, not the cause. **Counts: `READY_TO_REMEDIATE` 178 → 177, `VERIFIED_CLOSED` 28 → 29, total 319 unchanged** — `UIX-1` is a §6 P0 row with a status field and this transition *is* a closure, unlike the `REMEDIATED` move §7.16 recorded without a count. **`known-violations.json` untouched; no assertion weakened; zero `continue-on-error`. The status-vocabulary gap is unresolved and still governs `SEC-R2`/`SEC-R3`. `SEC-04`, `ENV-6`, `SEC-09`, `I-MIG-03`, `ENV-2`, `DAT-3`/`I-INT-01`, `PD-A09`, `D-4`/`D-5` all carried forward unchanged.** Production `nxdbooufqzkpslkcogxc` was not contacted. |
| 2026-08-28 | **`I-NUT-01` reaches `VERIFIED IN CI` — CI run #51 `33205917510` at `adc43a4` (registry §7.19).** Wave 3A tasks **3A-1/2/3** landed in `8b1fba3` (`I-NUT-01`, `I-INT-01`, `F-J-04` — one file, `supabase/functions/ai-coaching-engine/index.ts`), verified against the migrations rather than assumed: `nutrition_logs` is created by **006** (`calories/protein/carbs/fat/amount_g/logged_at`) and **012's richer `CREATE TABLE IF NOT EXISTS` never executes**, `user_profiles.fitness_goal` is defined in **000** while 001's `user_profiles` block is a shadow definition, and each substituted ordering key was confirmed present with `created_at` confirmed absent. `adc43a4` then wired `supabase/tests/contract/nut01_negative_control.sh` into the existing `negative-control` job — **one step, no new job, no credential, no network, no toolchain**, reusing the `fetch-depth: 0` checkout; `secrets.QA_*` stays 15 and `continue-on-error` stays 0. **Run #51: `success`, 7/7 jobs, every step `success`** — post-fix half bounded by `static-guards` step 7 (unconditional), pre-fix half by `negative-control` **step 9**, green on its first run, installing `2ad8c6c`'s Edge Function against the post-fix allowlist and requiring the three named `nutrition_logs.protein_g/carbs_g/fat_g` failures with no unrelated `FAIL`, then a byte-identical restore. **G-3 not invoked** — `2ad8c6c` is real recoverable history. Raw logs remain **403**, so the harness output is entailed from exit status plus source at the executed SHA (§7.13, confined to VERIFIED IN CI). **Regression, same run: `UIX-1` booking E2E and `I-WRK-01` live progression both `success`.** `known-violations.json` shrank **8 → 6** as the mechanical last step of the I-NUT-01 fix, per that file's own both-directions contract; nothing was added and no assertion weakened. **`I-NUT-01` is NOT `VERIFIED_CLOSED`** — class **Data contract / schema** also demands FIXED ON QA and VERIFIED LIVE, and `ENV-7` holds every Edge Function undeployed until Wave 5: two of four states. **`I-INT-01` NOT closed** — its `user_profiles.goal` allowlist entry still reproduces at `ai-generate-workout/index.ts:63`, which is `I-INT-02`/`DAT-2`, **task 3A-4**; the entry was kept and the row has no discriminating CI guard until 3A-4 lands (new dependency, absent from the wave plan). **`F-J-04` NOT closed** — `run.mjs` checks select columns and insert/update/upsert keys but **not filter columns** (`.order`/`.eq`/`.gte`), so no CI guard can see that defect or its regression; FIXED IN CODE only. **`EC-02` / rule S untouched** — `recent()`'s silent degradation is unchanged, its fail-closed half being `BLOCKED_DECISION` on **Q-5**. **Counts: none moved** — `I-NUT-01` and `F-J-04` are §7 rows with no per-row status field (the `F-J-12` precedent); `VERIFIED_CLOSED` stays **29**, total **319**. Production `nxdbooufqzkpslkcogxc` was not contacted; no QA read and no QA write. |
| 2026-08-30 | **`I-INT-02`/`DAT-2` and `I-INT-01`/`DAT-3` reach `VERIFIED IN CI` — CI run #53 `33326163269` at `5dfc59f` (registry §7.20).** Wave 3A task **3A-4** landed in `0a4b14d`: `ai-generate-workout/index.ts:63` dropped `goal` and `equipment`, neither of which exists on `user_profiles` (`000_baseline` defines `fitness_goal`; no `ADD COLUMN` since adds either; 001's `user_profiles` block is a shadow `CREATE TABLE IF NOT EXISTS`). PostgREST resolves the whole select before reading, so one phantom column 400'd the request and took `experience_level`, `training_location`, `has_injuries` and `injury_locations` (migration **013**) with it. `goal` needed no replacement — `fitness_goal` was already selected and already first in the coalesce; `equipment` was **repointed, not removed**, to `ai_profiles.preferences.available_equipment` (`074:13`), a row the handler already fetches in the same `Promise.all`. **The `?? 'Bodyweight'` / `?? 'general'` defaults are unchanged — that is ERR-2 / rule S, blocked on Q-5.** `5dfc59f` wired `int02_negative_control.sh` into the existing `negative-control` job — one step, no new job, no credential, no network, no toolchain. **Run #53: `success`, 7/7 jobs, every step `success`, all seven jobs carrying `head_sha 5dfc59f3c43a`** — post-fix half from `static-guards` step 7 (verified unconditional at the executed SHA: no job-level `if`, and the step has keys `name`/`run` only), pre-fix halves from `negative-control` **step 10** (I-INT-02, first run) and **step 9** (I-NUT-01, strengthened). **I-INT-01's evidence is shared, and the standard permits it:** §2.1 names this class's mechanism as *"`test:contract` with the allowlist entry removed"* and §2 defines the state generally; neither §2, §2.1 nor §4 requires a finding to own a dedicated harness. `8b1fba3` fixed `ai-coaching-engine:143` but could not complete the allowlist half while `user_profiles.goal` still reproduced at `ai-generate-workout:63` (`known (2 sites)` → `(1 site)`); 3A-4 removed that last site, the entry left the list, and `nut01_negative_control.sh` was **strengthened** to *require* the literal `user_profiles.goal is referenced but does not exist` against its pre-fix blob `2ad8c6c` — **the real parent of `8b1fba3`, so G-3 is not invoked**. `known-violations.json` 6 → 4; nothing added, no assertion weakened, zero `continue-on-error`. **Raw job logs and the run archive both return HTTP 403 and `gh` is absent**, so step conclusions and harness source at the executed SHA are observed while the harnesses' literal output is **not** — the §7.13 entailment standard, still confined to VERIFIED IN CI. **Regression at the same head: `UIX-1` booking E2E, `I-WRK-01` live progression, API, Flutter, Live QA and Static guards all `success`.** **Neither row is `VERIFIED_CLOSED`** — class **Data contract / schema** also demands FIXED ON QA and VERIFIED LIVE, and **`ENV-7`** holds all 19 Edge Functions undeployed to QA until Wave 5, so the fix has not reached the environment and no live probe is possible: two of four states each. **Counts: none moved** — both are §6 rows moving `READY_TO_REMEDIATE` → `REMEDIATED`, which §7.16 already settled is not a closure; `VERIFIED_CLOSED` stays **29** and the total **319**, with 177 still carrying both rows. Both are now **understated**, the third and fourth instances of the status-vocabulary gap §7.10 escalated for `SEC-R2`/`SEC-R3`. **`F-J-04` NOT advanced** (still FIXED IN CODE only — `run.mjs` does not inspect filter columns); **`Q-5` untouched**; **the `available_equipment` write-path gap remains open and unchanged** (074:13 declares the key, nothing writes it). Production `nxdbooufqzkpslkcogxc` was not contacted; no QA read and no QA write. |
| 2026-08-31 | **Wave 3A migration renumbering (B1) and `I-COM-03`(a) scope (B3) settled — governance only (registry §7.22).** Recorded at the 3A-9 implementation gate, which stopped before writing code. **B1:** `MASTER_REMEDIATION_WAVES.md` §0.2 assigned **126/127/128 to Wave 3A** and reserved 129+ for Wave 4+, but **Wave 2 had consumed all three** — `c7c1058` (`F-J-17`), `e909f9a` (`F-J-07`/SEC-R3), `f38841f` (`F-J-12`/PD-A05 (a)) — each taking the next contiguous number, the same practice used when §0.2's 125 assignment was spent and option (a) landed at 128 (§7.11). It was never written back into §0.2, so the next task read a false table. §0.2's three rows are **corrected to what the tree contains — nothing renumbered**, which Gate 0.9 forbids in terms (*"Do not renumber an existing migration to close a gap"*); Wave 3A moves to **129 → 130 → 131** and Wave 4+ to **132+**. **The numbers were derived, not chosen** — QA frontier is 128 and Gate 0.9 requires contiguity, so no other assignment exists. Each must still be declared `pending` in `expected_applied.json` when authored, and applying any to QA stays a separate gate, so **FIXED ON QA is not reachable for 3A-9/10/11 by authoring alone**. **B3:** §0.2 and the 3A-9 row read *"`custom_exercises.approved_by`"*, which the authoritative Workstream I entry contradicts — the live column is **`last_reviewed_by`** (exists since `083:36`) and the remediation is *"(a) `approved_by` → `last_reviewed_by`"*, cleared to *"land now"* ahead of Q-9. **Ruled: 3A-9 repoints `custom_exercise_service.dart:772`; no `approved_by` column is added.** Adding one would duplicate `last_reviewed_by`, leave unmoderated publishing untouched, and still clear the ledger — closure theatre. `I-COM-03` (b)+(c) stay **Q-9**-gated, Wave 7D. **No closure class ruled — `I-COM-03` remains OWNER RULING REQUIRED.** **Counts: none moved** — `VERIFIED_CLOSED` 29, canonical total 319. **No code, migration, test, CI, `known-violations.json` or Edge Function file touched; no finding changed status; §7.21 reserved for the unpushed `I-COM-01` VERIFIED IN CI record.** Still open and untouched: B2 (`I-WRK-02` wave/decision), B4 (`I-WMH-01` has no registry row), B5 (H-G2 retirement would drop a Wave 3B pin), B6 (no negative control exists for any remaining 3A item). |
| 2026-09-25 | **Autonomous QA exhaustion — DISCOVERY ONLY (registry §7.23; `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md`).** Status: **QA BLOCKED — EXECUTABLE SURFACE REMAINS** (QA host network-denied; no Flutter SDK). 23 new `QAX-*` rows: **2 P0** (`QAX-SEC-02` progress-photo exposure to any self-registered or former coach; `QAX-SEC-01` `assign_nutrition_plan` cross-member supersede), 5 P1, 9 P2, 6 P3 and a P4 pair (`QAX-H-01`/`QAX-H-02`). Two expansions (`E-15`, `REL-29`) and six recorded contradictions of prior statements. Evidence: a LOCAL-REPLAY of migrations 000–131 with mutation-tested probes (`supabase/tests/qa_exhaustion/`) and a static guard (`apps/mobile/tool/qa_exhaustion/`). **No production code, SQL, migration or copy changed.** |
| 2026-09-25 | **QA exhaustion Run 2 (registry §7.24; report §R2).** Flutter 3.44.4 now runs locally; the DB negative-control harness and all 7 per-finding negative controls PASS locally. **Fixed (client-side, each with a widget/unit test plus mutation evidence):** QAX-ERR-01, QAX-COR-01, QAX-COR-05, QAX-COR-06, QAX-COR-07, QAX-COR-08, QAX-ERR-02, QAX-SES-01, women's-health F-03, F-06, F-22, UIX-2 Terms claim. **New:** QAX-SEC-08 (**P0**, team-lead PHI read), QAX-SEC-09 (P1, vendor PHI read), QAX-BIL-01, QAX-SEC-10, QAX-UI-01/02/03. **Vacuous guards found and fixed:** UIX-2 deletion-claims, REL-3 release gate. Suite 822 → **857 passed / 9 skipped / 0 failed**; analyzer unchanged (0 errors). No migration; no QA/production contact. Status: **NOT EXHAUSTED.** |
