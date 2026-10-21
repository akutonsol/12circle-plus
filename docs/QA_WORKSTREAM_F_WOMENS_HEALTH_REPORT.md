# 12 Circle Fitness — AI QA Workstream F
## Women's Health (Module 18) — Functional & Data Architecture Audit

**Environment:** QA (`eyqtldjqpgpljlqvpowh`) only. Production (`nxdbooufqzkpslkcogxc`) **not contacted**.
**Date:** 2026-08-24
**Scope:** Cycle tracking, history, phase derivation, fertile window, symptoms, phase guidance
(recovery / training / nutrition), notifications, coach visibility, editing, persistence, date
handling, stale/missing data, privacy/RLS, disclaimer placement, tests.

**Method:**
1. Source read of every Women's Health artefact — migration `033_womens_health.sql`, the three Dart
   files under `apps/mobile/lib/features/womens_health/`, the home-screen consumer, the AI coaching
   Edge Function, and every migration/test/tool that touches `cycle_logs` / `cycle_symptoms` /
   `cycle_settings`.
2. **Executable verification** of the calculation layer — a new characterization test
   ([cycle_phase_logic_test.dart](../apps/mobile/test/unit/cycle_phase_logic_test.dart), 16 tests,
   all passing) that exercises `computeCycleStatus` across every phase boundary, both fertile-window
   predicates, cycle lengths 21–40, and log ages up to 1000 days.
3. **Live read/write probing against QA** with the seeded `test@12circle.app` and
   `coach@12circle.app` accounts plus the anon key. Every write used a `QA-F` marker and was
   reverted; final state verified empty for both accounts on all three tables (§Cleanup).

**Authority note:** there is no Women's Health section in `docs/product-bible.md` and no feature
blueprint — consistent with `MASTER_QA_RECONCILIATION.md` §1, which records area C as **ABSENT**.
Every requirement cited below traces to migration comments, existing code behaviour, or a prior
canonical finding. **No clinical parameter was changed, no medical claim was authored, and no
treatment protocol was invented.** Items that require a clinical or product ruling are isolated in
category **E** and left open.

---

## RESULT SUMMARY

| # | Area | Result |
|---|---|---|
| 1 | Cycle tracking | **PARTIAL** — logging works; no validation, no dedupe (F-01, F-04) |
| 2 | Cycle history | **ABSENT** — no history UI exists; `getPeriods` is only ever called with `limit: 1` (F-20) |
| 3 | Current phase | **FAIL** — unbounded extrapolation fabricates a confident phase from year-old data (F-09) |
| 4 | Fertile window | **FAIL** — UI label ignores the computed window; wrong on 7 of 28 days (F-08) |
| 5 | Symptoms | **FAIL** — re-opening the sheet destroys the day's saved values (F-03, live-verified) |
| 6 | Recovery guidance | PASS (static copy, correctly phase-gated) — but inherits the wrong phase from F-09/F-11 |
| 7 | Training guidance | PASS (same caveat) |
| 8 | Nutrition guidance | PASS (same caveat) |
| 9 | Notifications | **ABSENT** — no cycle notification exists in any migration, trigger, or client path |
| 10 | Coach visibility | **PASS** — coach reads return `[]` even with data present and an explicit `user_id` filter |
| 11 | Data editing | **ABSENT** — no edit or delete path for a mis-logged period (F-21) |
| 12 | Persistence | **PARTIAL** — server-side and correct, but writes silently no-op and errors are swallowed (F-06) |
| 13 | Date/time handling | **PARTIAL** — local-time throughout; DST-sensitive day arithmetic (F-15) |
| 14 | Stale-data handling | **FAIL** — no staleness bound at any age (F-09) |
| 15 | Missing-data handling | **PASS** — null last-period yields `unknown` + a correct "not tracking" state |
| 16 | Privacy / RLS | **PASS at the table boundary** — but cycle data leaves it via the AI Edge Function (F-18) |
| 17 | Medical disclaimer | **PARTIAL** — present but below the fold, and absent from every other surface (F-23) |
| 18 | Tests | **WAS ZERO** — no test, QA suite, or live tool referenced the subsystem. Addressed, see §Test change |

**Headline:** privacy at the table boundary is genuinely solid and re-verified stronger than the
baseline claimed — `anon` is denied at the `GRANT` level, not merely by RLS. The subsystem's real
problem is that **the presentation layer and the calculation layer disagree**, and that the
calculation layer will assert a confident current phase from data of unlimited age. All three
previously reported functional concerns are **CONFIRMED and unfixed**. Separately, cycle data does
leave the user-isolation boundary — through the AI coaching Edge Function, not through RLS.

---

## VERIFICATION OF THE KNOWN BASELINE

| Prior claim | Verdict | Evidence |
|---|---|---|
| Privacy / isolation is working | **CONFIRMED (and stronger)** | Coach reads of `cycle_logs`/`cycle_symptoms`/`cycle_settings` returned `[]` *with client data present* and an explicit `user_id=eq.<client>` filter. Forged insert using another user's `user_id` → **403** `new row violates row-level security policy`. |
| Cycle rows protected from coach / unrelated / anon access | **CONFIRMED (and stronger)** | Anon is refused at the privilege level, before RLS: **HTTP 401 / `42501` permission denied for table** on all three tables. `anon` holds no `SELECT` grant at all. |
| Guidance has a not-medical-advice disclaimer | **CONFIRMED, placement inadequate** | Text exists at `womens_health_screen.dart:52-55`, but it is the last child of the `ListView` — below three guidance cards and the check-in list, so off-screen at first paint. Absent from the home tile, the period sheet, and the symptom sheet (F-23). |
| Fertile-window display not using the computed window | **CONFIRMED — unfixed** | F-08. Verified in test: 6 false-positive days + 1 false-negative day per 28-day cycle. |
| Stale cycle data producing a fabricated current phase | **CONFIRMED — unfixed** | F-09. A 400-day-old log yields `hasData=true`, "Follicular · Day 9 · Next period in 20 days". |
| Symptom sheet overwriting daily values with defaults | **CONFIRMED — unfixed, reproduced live** | F-03. `["QA-F"], energy 99, mood -5` → `[], energy 3, mood 3` on a second save. |

`MASTER_QA_RECONCILIATION.md` CON-10 and `REMEDIATION_EXECUTION_PLAN.md` step 3H remain **NOT
FIXED** — `cycle_phase.dart` is unmodified on this branch. This audit widens CON-10 from two
mechanical defects to the set below, and confirms its parenthetical that the cycle tables *do* have
RLS.

---

## CALCULATION INVENTORY

Every derived value in the subsystem, per the required breakdown. There is exactly one calculation
site: `computeCycleStatus()` in
[cycle_phase.dart:37-79](../apps/mobile/lib/features/womens_health/domain/cycle_phase.dart#L37-L79).
It is pure except for an internal `DateTime.now()`.

### Shared inputs

| Input | Source | Fallback when missing |
|---|---|---|
| `lastPeriodStart` | `cycle_logs.start_date`, **`ORDER BY start_date DESC LIMIT 1`** (`cycle_provider.dart:16`) | `null` → `CyclePhase.unknown` |
| `cycleLength` | `cycle_settings.avg_cycle_length` | **28** — and always 28 in practice (F-05) |
| `periodLength` | `cycle_settings.avg_period_length` | **5** — and always 5 in practice (F-05) |
| "today" | `DateTime.now()`, local, truncated to midnight | n/a |

### 1. Cycle day

- **Formula:** `daysSince = today − start`; `cycleDay = (daysSince < 0 ? 0 : daysSince % cl) + 1`
- **Date assumptions:** both operands truncated to local midnight; `.inDays` on local `DateTime`s.
- **Stale behaviour:** **none — the modulo extrapolates forever.** No age bound at any value (tested to 1000 days).
- **Missing behaviour:** correct — `unknown`, `cycleDay = 0`, `hasData = false`.
- **UI:** ring fill `cycleDay / cycleLength`, big numeral, and `"{Phase} · Day {n}"` on the home tile.

### 2. Phase

- **Source:** `cycleDay`, `cl`, `pl`. `ovulation = cl − 14`.
- **Formula:** `cycleDay ≤ pl` → menstrual · `cycleDay < ovulation−1` → follicular ·
  `cycleDay ≤ ovulation+1` → ovulation · else luteal.
- **Verified map (28/5):** menstrual 1–5, follicular 6–12, ovulation 13–15, luteal 16–28.
- **Degenerate at short cycles:** follicular requires `cl ≥ pl + 17`. At `cl=21, pl=5` follicular is
  **unreachable**; at `cl=21, pl=10` both follicular **and** ovulation are unreachable (F-11).
- **Stale behaviour:** inherits the unbounded modulo — a phase is always asserted.
- **Missing behaviour:** `unknown`, with a dedicated "Not tracking / Log a period to begin" guide. Correct.

### 3. Fertile window

- **Formula:** `fertileStart = cycleStart + (ovulation − 3)`, `fertileEnd = cycleStart + (ovulation + 1)`,
  where both addends are **0-based day offsets**.
- **Verified (28/5):** cycle days **12–16** (5 days), centred on day 14.
- **UI:** the computed window is **never read**. `womens_health_screen.dart:114` renders
  "Fertile window now" from `phase == ovulation || phase == follicular` instead (F-08).
- **Stale behaviour:** extrapolated like everything else; a fertile window is emitted for a cycle
  that was inferred, not observed.
- **Missing behaviour:** `null` start/end. Correct.

### 4. Next period

- **Formula:** `currentCycleStart = start + (daysSince ÷ cl) × cl`; `nextStart = currentCycleStart + cl`.
- **Verified property:** `daysUntilNextPeriod ∈ [1, cl]` **always** (exhaustively checked for
  `cl` 21–40 × 200 ages). It can never be `≤ 0`, so the `'Period expected today'` branch at
  `womens_health_screen.dart:110-111` is **unreachable** and the app can never report an overdue
  period (F-12).
- **Stale behaviour:** the prediction silently rolls forward into a fresh imaginary cycle rather than
  going late — this is the mechanism by which staleness is hidden from the user.

### 5. Guidance (recovery / training / nutrition)

- **Source:** `phaseGuides`, a `const Map<CyclePhase, PhaseGuide>` of static copy.
- **Formula:** direct lookup by phase. **Not** a function of cycle day, symptoms, energy, mood, flow,
  training history, or any logged data — verified in test.
- **Stale/missing:** gated behind `status.hasData`, so no guidance renders without a logged period.
  This gating is correct and is the subsystem's best-behaved path.
- **Assessment:** the copy is general-wellness in register and carries a disclaimer. **Not evaluated
  for clinical accuracy — out of scope and not this workstream's authority.** Its defect is
  upstream: it is selected by a phase that may be fabricated (F-09) or unreachable (F-11).

---

## FINDINGS

### A. Data integrity

#### F-01 — [P1] No domain constraint exists on any cycle table
- **Expected:** migration `033_womens_health.sql` documents the ranges in comments —
  `energy int, -- 1..5`, `mood int, -- 1..5`, `flow text, -- none|light|medium|heavy`.
- **Actual:** not one of them is enforced. No `CHECK`, no date ordering, no uniqueness on periods.
- **Reproduction (live QA, all reverted, every call returned `201`):**

  | Probe | Result |
  |---|---|
  | `cycle_logs.start_date = 2027-08-24` (a year in the future) | **201 accepted** |
  | `cycle_logs` with `end_date 2026-08-01` < `start_date 2026-08-20` | **201 accepted** |
  | third identical `cycle_logs` row, same `start_date` | **201 accepted** |
  | `cycle_settings avg_cycle_length = 0, avg_period_length = -3` | **201 accepted** |
  | `cycle_symptoms energy = 99, mood = -5, flow = 'bogus'` | **201 accepted** |

- **Impact:** the client is the only validator, and it validates almost nothing. Feeds F-02 and F-13.
- **Fix direction:** `CHECK (energy BETWEEN 1 AND 5)`, same for `mood`; `CHECK (flow IN (...))`;
  `CHECK (end_date IS NULL OR end_date >= start_date)`; `CHECK (start_date <= current_date)`;
  positive-range checks on both `cycle_settings` lengths; `UNIQUE (user_id, start_date)` on `cycle_logs`.

#### F-02 — [P1] "Last period" is the maximum `start_date`, not the most recent *past* period
- **Actual:** `cycle_provider.dart:16` takes `ORDER BY start_date DESC LIMIT 1`. Combined with F-01,
  any future-dated row becomes the authoritative "last period start".
- **Evidence:** live QA read after the F-01 probe returned the `2027-08-24` row **first**.
- **Impact:** the entire derived status is computed from a date that has not happened, via F-13.
- **Fix direction:** filter `start_date <= current_date` at the query, independently of the DB constraint.

#### F-03 — [P1] Re-opening the symptom sheet destroys the day's saved values
- **Expected:** an upsert keyed `UNIQUE (user_id, log_date)` implies the day's check-in is editable.
- **Actual:** `_symptomsSheet` (`womens_health_screen.dart:195-240`) initialises
  `selected = {}`, `energy = 3`, `mood = 3` and **never loads the existing row**. `logSymptoms`
  always sends `symptoms`, `energy` and `mood`, so saving twice in one day overwrites the first save
  with defaults. `todaySymptomsProvider` — which fetches exactly this row — exists at
  `cycle_provider.dart:33` and **has no consumer anywhere in the codebase**.
- **Reproduction (live QA, reverted):** stored `symptoms=["QA-F"], energy=99, mood=-5, flow="bogus"`;
  re-sent the sheet's default payload → row became `symptoms=[], energy=3, mood=3, flow="bogus"`.
  `flow` and `notes` survive only because the UI never sends them — a coincidence, not a safeguard.
- **Impact:** silent, unrecoverable loss of the user's own health log. Worst finding in the subsystem
  from a user-trust standpoint. **CONFIRMS the prior report.**
- **Fix direction:** seed the sheet from `todaySymptomsProvider` before first paint; keep the write
  as a full upsert once it is seeded.

#### F-04 — [P2] Duplicate period rows accumulate silently
- `logPeriod` (`cycle_service.dart:44`) uses `insert`, not `upsert`, and there is no unique key
  (F-01). Logging the same start twice yields two rows. Live-verified: three identical rows.
- With no history UI (F-20) and no delete path (F-21), the user cannot see or clean this up.

#### F-05 — [P2] `cycle_settings` is write-dead; predictions are permanently 28/5
- `CycleService.saveSettings()` has **no caller anywhere in the app**. There is no UI to set cycle or
  period length, and nothing derives an average from `cycle_logs` history.
- The table comment states "*averages used for predictions*" — unimplemented. Every user is
  permanently 28/5 regardless of their actual cycle, which then drives F-11 for anyone shorter.
- The audit's "cycle history" area has no consumer for the same reason: `getPeriods` supports
  `limit: 12` but is only ever called with `limit: 1`.

#### F-06 — [P2] Writes silently no-op when signed out, and errors are swallowed
- Every `CycleService` mutator opens `if (uid == null) return;` — a signed-out or
  token-expired write is discarded with no error and no signal.
- Both sheets `await` the write, then bump the refresh provider and `Navigator.pop` **with no
  try/catch and no success/failure feedback**. An RLS or network failure closes the sheet exactly
  as a success does. Same class as CON-11/WRK-07 ("errors stop masquerading as empty").

#### F-07 — [P3] `tracking_enabled` is never read or written
- Declared in `033_womens_health.sql:35`, referenced nowhere in the app or any function. There is no
  way to turn tracking off — which becomes material given F-18.

### B. Calculation correctness

#### F-08 — [P1] The fertile-window label ignores the computed fertile window
- **Expected:** `CycleStatus.fertileStart` / `fertileEnd` are computed precisely so the UI can say
  whether today is in the window.
- **Actual:** `womens_health_screen.dart:114` renders "Fertile window now" from
  `s.phase == CyclePhase.ovulation || s.phase == CyclePhase.follicular`. The computed window is
  never referenced by any widget.
- **Verified divergence (28/5), from the new test:**

  | Cycle day | Computed window | UI label | |
  |---|---|---|---|
  | 6 – 11 | outside | **"Fertile window now"** | 6 false-positive days |
  | 12 – 15 | inside | "Fertile window now" | agree |
  | 16 | **inside** | *(silent — luteal)* | 1 false-negative day |

- **Impact:** the label is wrong on **7 of 28 days**, and wrong in the permissive direction for six
  of them. Two different fertility answers ship in one screen. **CONFIRMS the prior report.**
- **Fix direction:** derive the label from `fertileStart`/`fertileEnd`. This is a pure display fix
  and does **not** require the Q-5 clinical ruling — whatever window product chooses, the UI should
  render *that* window.

#### F-09 — [P1] No staleness bound — a fabricated current phase is presented as fact
- **Actual:** `daysSince % cl` extrapolates indefinitely. Nothing anywhere records or checks the age
  of the source log.
- **Verified:**

  | Log age | Reported |
  |---|---|
  | 45 days | Luteal · Day 18 · next in 11 |
  | 90 days | Follicular · Day 7 · next in 22 |
  | 200 days | Menstrual · Day 5 · next in 24 |
  | **400 days** | **Follicular · Day 9 · next in 20**, `hasData = true` |

- **Impact:** a *prediction* built on a single year-old data point renders identically to a
  same-day observation — same ring, same day number, same confident guidance cards, no
  qualification. This is compounded by F-12: because the prediction can never go overdue, there is
  no natural signal that tracking has lapsed. **CONFIRMS the prior report.**
- **Fix direction:** the *mechanism* is a defect and is fixable now — carry the source log's age in
  `CycleStatus` and degrade the UI past a threshold. **The threshold value is a product call — E-2.**

#### F-10 — [P2] `ovulation` is used as a 1-based cycle day and as a 0-based offset in the same function
- The classifier compares `ovulation` against `cycleDay` (1-based) → ovulation day = **14**.
  The window arithmetic adds `ovulation` to `cycleStart` as a 0-based offset → ovulation day = **15**.
- **Net effect:** the comment describes `ovulation−3 … ovulation+1` (asymmetric, mostly *before*
  ovulation) but the window actually delivered is day 14 **± 2** — two days *after* the labelled
  ovulation day. The code does not implement its own stated intent.
- The window's *width and placement* are a clinical parameter (**E-1 / Q-5**). This internal
  self-disagreement is not — it is a unit bug and should be fixed regardless of the Q-5 outcome.

#### F-11 — [P2] Phases collapse at short cycles; the fertile window can land inside "Menstrual"
- Follicular is reachable only when `cl ≥ pl + 17`. Verified:
  - `cl=21, pl=5` → reachable phases `{menstrual, ovulation, luteal}` — **follicular never occurs**.
  - `cl=21, pl=10` → `{menstrual, luteal}` — follicular *and* ovulation never occur, **and** the
    computed fertile window (cycle days 5–9) falls entirely inside a screen reading
    **"Menstrual · Rest & restore"**.
- A 21-day cycle is inside the code's own clamp range, so this is in-contract input, not an extreme.
- Today this is masked by F-05 (everyone is 28/5) — it becomes live the moment settings are wired up.
- **Fix direction:** derive phase from the window/ovulation anchor rather than a chain of independent
  thresholds, and make the boundaries total across the clamp range.

#### F-12 — [P2] The app can never report a late period; the "expected today" branch is dead code
- `daysUntilNextPeriod ∈ [1, cl]` by construction — exhaustively verified. The
  `'Period expected today'` string at `womens_health_screen.dart:110-111` cannot render.
- **Impact:** at the moment a period becomes overdue, the app silently starts a new predicted cycle
  and resets to "Day 1 · Menstrual" instead of surfacing that the prediction has lapsed. This is the
  mechanism that makes F-09 invisible.

#### F-13 — [P2] A future-dated start fabricates "Menstrual · Day 1"
- `daysSince < 0` clamps `dayIndex` to `0`, so the guard produces a confident wrong answer instead of
  refusing. Verified: a start 10 days in the future → `hasData=true`, Menstrual, Day 1, with a
  fertile window three weeks out.
- Not reachable via the date picker (`lastDate: DateTime.now()`), but fully reachable via the REST
  API, which F-01 confirms accepts it. Reached in practice through F-02.
- **Fix direction:** return `unknown` for a future start.

#### F-14 — [P3] Out-of-range lengths are silently clamped
- `cycleLength.clamp(21, 40)` / `periodLength.clamp(2, 10)`. With F-01 the DB will hold `0` / `-3`,
  which the client silently rewrites to 21 / 2 with no indication that the stored value is being
  ignored. Clamping is reasonable; doing it invisibly over invalid persisted data is not.

#### F-15 — [P3] Local-time day arithmetic is DST-sensitive
- `DateTime(y,m,d).difference(...).inDays` on **local** `DateTime`s returns 23 h or 25 h days across
  a DST transition, so `.inDays` can truncate one day short. Affects `daysSince`, `cycleDay`, and
  `daysUntilNextPeriod` for users in DST zones.
- Directly in scope for **Phase 3C (CON-06/CON-07)** — "UTC everywhere, explicit local day
  boundaries, a shared helper and a guard test". Route this through that shared helper rather than
  patching it here.

#### F-16 — [P3] The calculation reads the clock internally
- `computeCycleStatus` and `CycleStatus.daysUntilNextPeriod` both call `DateTime.now()` directly, so
  the function cannot be tested at a fixed date (the new test works around this by expressing every
  case relative to today) and the status never invalidates at midnight — a screen left open across
  midnight keeps yesterday's cycle day.
- **Fix direction:** an injectable `DateTime now` parameter defaulting to `DateTime.now()`.

### C. Privacy / security

#### F-17 — **PASS** — table-level isolation re-verified, and stronger than the baseline claimed
- All three tables have RLS enabled with `FOR ALL TO authenticated USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid())`. No coach policy, no service-role policy, no view exposes them.
  No later migration (100, 112, 117, 118) alters them — verified by grep across all 122 migrations.
- **Live QA results:**

  | Probe | Result |
  |---|---|
  | anon `GET` on each of the three tables | **401 / `42501` permission denied** — no `SELECT` grant to `anon` at all |
  | coach `GET cycle_logs` unfiltered, with client data present | `200 []` |
  | coach `GET cycle_logs?user_id=eq.<client>` | `200 []` |
  | coach `GET cycle_symptoms` / `cycle_settings` targeting the client | `200 []` |
  | client `INSERT` with `user_id` = coach's id | **403** RLS violation |

- Note the anon result is a **stronger** guarantee than RLS: the privilege is absent, so the policy
  is never even reached. Cycle data is not exposed by the D-01 forged-relationship escalation either,
  since no policy consults `coach_client_relationships`.

#### F-18 — [P1] Cycle data leaves the isolation boundary through the AI coaching Edge Function
- **Actual:** `supabase/functions/ai-coaching-engine/index.ts:133` reads the user's 5 most recent
  `cycle_logs` rows using the **service-role client** (`createClient(SUPABASE_URL,
  SUPABASE_SERVICE_KEY)`, line 112) — RLS bypassed by design — and line 169 places the newest row
  into the LLM prompt context:

  ```ts
  recovery: feedback?.[0] ?? cycles?.[0] ?? {},
  ```

- The row is passed whole, so `id` and `user_id` ship to the model alongside the menstrual dates.
- **No consent gate, no disclosure, and no opt-out.** `cycle_settings.tracking_enabled` — the one
  field that could express a user preference — is never consulted (F-07). Nothing in the Women's
  Health UI indicates that cycle data is used by the AI coach.
- **Mitigating:** the generated output persists to `ai_insights`, which is `own ai data` RLS
  (migration 074) — so a **coach still cannot read it**. The exposure is to the LLM provider, not to
  another user of the platform.
- **Assessment:** this is the one place where the otherwise-clean privacy story breaks. Menstrual
  data is among the most sensitive categories a fitness product holds, and it is the only health
  category in this app given a dedicated privacy boundary — which the Edge Function then crosses.
- **Fix direction:** gate the `cycle_logs` read on `tracking_enabled`, project only the fields
  actually needed (never `id`/`user_id`), and add an explicit consent surface.
  **Whether cycle data may be sent to a third-party model at all is a product/privacy ruling — E-4.**

#### F-19 — [P2] The cycle row is mislabeled as `recovery` and included only by accident
- The same expression, `feedback?.[0] ?? cycles?.[0] ?? {}`, means a `cycle_logs` row
  (`{id, user_id, start_date, end_date, created_at}`) is handed to the model under the key
  `recovery` — a slot otherwise filled by a `workout_feedback` row with an entirely different shape.
- It is therefore included **only when the user has no recent workout feedback**, which is not a
  cycle-aware rule. So the model receives menstrual dates described as a recovery signal, sometimes,
  for reasons unrelated to the cycle. Both a correctness defect and a second-order privacy one:
  data is disclosed by a code path that does not read as a cycle-data path.

### D. UX

#### F-20 — [P2] No cycle history surface exists
- `getPeriods(limit: 12)` supports it; the only call site passes `limit: 1`. The user cannot see
  which periods are logged, confirm a save, or notice duplicates (F-04) or bad dates (F-02).
- This is the audit's "cycle history" area, and it is **absent**, not defective.

#### F-21 — [P2] No edit or delete path for a mis-logged period
- `CycleService` exposes no update-by-id and no delete. A wrong start date can only be "corrected"
  by logging another row, which adds to the problem. `endCurrentPeriod` is the sole mutation of an
  existing row.
- RLS permits `DELETE` (`FOR ALL`), so this is purely a missing client affordance.

#### F-22 — [P2] "Period ended" is silent, and no-ops when there is no open period
- `endCurrentPeriod` looks for the newest row with `end_date IS NULL`; if there is none it returns
  without acting. The button still dismisses the sheet as though it succeeded (F-06).

#### F-23 — [P3] Disclaimer placement
- The disclaimer is the **last** child of the screen's `ListView`, after the phase header, action
  row, three guidance cards, and the recent-check-ins card — off-screen at first paint on a phone.
- It does not appear on: the **home tile** (which renders phase + cycle day, so it makes a cycle
  claim outside the disclaimed screen), the log-period sheet, or the symptom sheet.
- Given F-08's "Fertile window now" label, the disclaimer's proximity to the fertility claim matters
  more than its presence. **Placement policy — see E-3.**

#### F-24 — [P3] The gender gate only affects a subtitle
- `home_screen.dart:723` computes `isFemale`, but the Women's Health tile renders unconditionally and
  `/womens-health` (`app_router.dart:278`) has no guard. `isFemale` gates only `whHasData`, so a
  user whose `gender` is unset sees "Track your cycle" **even when they have cycle data logged** —
  their own data is hidden from them by a profile field. **Gating policy — E-5.**

#### F-25 — [P3] Captured symptom detail is never displayed
- Recent check-ins shows `log_date` + symptom names only. `energy`, `mood`, `flow` and `notes` are
  collected (or schema-supported) and stored, but appear in no view — no trend, no per-day detail.
  `flow` and `notes` have no input control at all despite existing in the schema.

### E. Product / clinical-policy decisions — **NOT decided here**

These require product/clinical authority. Recorded, not acted on. **E-1 and E-2 are the open
`Q-5` from `MASTER_QA_RECONCILIATION.md`, restated with evidence.**

| ID | Decision | Current behaviour | Why it is not an engineering call |
|---|---|---|---|
| **E-1** | Fertile-window definition | Cycle days 12–16 — 5 days, day 14 ± 2, i.e. two days *after* the labelled ovulation day | The conventional window is 6 days ending on ovulation day. Both width and placement are clinical parameters. Note this is separable from F-08 (render whatever window is chosen) and F-10 (implement it consistently). |
| **E-2** | May a *predicted* phase be shown as the *current* one, and at what log age does it go stale? | Unbounded — a 400-day-old log renders as fact | The mechanism (F-09) is a defect and is fixable now. The **threshold** and the degraded presentation are product calls. |
| **E-3** | Should fertility/conception information appear in a fitness product at all, and if so with what framing and disclaimer placement? | "Fertile window now" shown inline; disclaimer below the fold | Fertility framing carries contraceptive-misuse risk regardless of disclaimer wording. Placement and prominence are a policy decision (F-23). |
| **E-4** | May cycle data be sent to a third-party LLM, and under what consent? | Sent silently via the Edge Function, no consent, no opt-out (F-18) | A privacy/legal determination. The engineering fixes (field projection, `tracking_enabled` gate) are ready either way. |
| **E-5** | Who sees the Women's Health surface? | Tile and route shown to everyone; `gender` gates only a subtitle string, and hides a user's own data when unset (F-24) | Gender-gating a health feature is a product/inclusion decision, not a bug fix. |

---

## Test change (the one non-discovery action)

**Before this audit the Women's Health subsystem had zero test coverage** — no file under
`apps/mobile/test/` referenced cycle logic, `qa_suites.dart` has no Women's Health suite (its suites
are Auth, Entitlements, Database, Scoring, Community, Workout, Nutrition + stubs), and neither
`tool/live_integration_test.dart` nor `tool/qa_self_guided.dart` touches the cycle tables.

Added [apps/mobile/test/unit/cycle_phase_logic_test.dart](../apps/mobile/test/unit/cycle_phase_logic_test.dart)
— 16 characterization tests, **all passing**, test-only, no production code touched.

They lock in the behaviour that exists **today** so remediation step 3H has a real
fails-before/passes-after signal. Assertions that encode a defect are commented `DEFECT: F-xx` and
are **expected to flip** when 3H lands; that is the purpose of a characterization test, not an
endorsement. The file header says so explicitly.

Suite status: `flutter analyze` clean on the new file; `flutter test` → **610 passing**. One
unrelated failure, `test/unit/error_contract_guard_test.dart`, is an untracked file from a
concurrent workstream that appeared mid-run and passes in isolation — not connected to this work.

---

## Recommended sequencing

Ordered by user impact and by what unblocks what. Nothing here is applied.

| Priority | Items | Note |
|---|---|---|
| **1** | F-03 | Silent destruction of the user's own health log. Small, self-contained, no policy input needed — seed the sheet from the provider that already exists. |
| **2** | F-08 | Render the computed window. Pure display fix; **does not wait on Q-5/E-1**. |
| **3** | F-09 mechanism + F-13 + F-02 | This is remediation step **3H**. Carry log age in `CycleStatus` and refuse to extrapolate from a future start. The staleness *threshold* waits on E-2; everything else does not. |
| **4** | F-01 | One migration adds every missing `CHECK` and the `UNIQUE (user_id, start_date)` that also closes F-04. Cheap, and it makes the client fixes enforceable. |
| **5** | F-18 / F-19 | Project only needed fields, honour `tracking_enabled`, stop passing a cycle row as `recovery`. Consent surface waits on E-4. |
| **6** | F-10, F-11, F-12 | Rewrite the phase/window derivation off a single ovulation anchor so the boundaries are total and self-consistent. F-11 is latent only while F-05 keeps everyone at 28/5. |
| **7** | F-05, F-20, F-21, F-06, F-22 | The missing product surfaces: settings, history, edit/delete, and real save/error feedback. |
| **8** | F-15, F-16 | Fold into **Phase 3C**'s shared date helper; add clock injection at the same time. |
| **9** | F-23, F-24, F-25, F-07, F-14 | Presentation and polish; F-23/F-24 follow E-3/E-5. |

---

## Cleanup

Six probe rows were written to QA and all were deleted (`204`). Post-cleanup verification, read as
**both** the client and the coach:

```
client cycle_logs: []     coach cycle_logs: []
client cycle_symptoms: [] coach cycle_symptoms: []
client cycle_settings: [] coach cycle_settings: []
```

All three tables are back to the empty state observed at the start. Production was never contacted.
No production code was modified; the only file added is the test above.
