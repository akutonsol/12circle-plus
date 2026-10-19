# Contract-guard write-site coverage — DECISION BRIEF

**Status: OWNER INPUT REQUESTED. Nothing here is decided and nothing was implemented beyond
making the existing limit visible.** No application write site, serializer, migration, RLS
policy or finding status was touched. No broader analysis was built.

**Prepared** 2026-10-13 against `f8d5b33b00d41cb8c31f83623e5955219e61a1aa`, branch
`feat/v5-autonomous-team`, tree clean.

---

## 1 · The question

> **Does the project fund resolving payload column keys across function boundaries in the
> schema-contract guard, or formally accept the documented coverage limit?**

This is a scope-and-cost question, not a correctness question: the guard is not wrong about
anything it reports. It simply analyses less than its name suggests, and until now said nothing
about the difference.

---

## 1a · What the guard proves, and what it does not

**It proves,** for the 143 write sites whose payload is an inline literal, plus every
`.from('relation')` and every `.select('a, b, c')` **within its two scan roots** —
`apps/mobile/lib` and `supabase/functions` (`run.mjs:37`):

- the relation exists in the schema derived from `supabase/migrations`;
- every selected column exists;
- every payload key written at that call site exists;
- every embedded resource resolves through a real foreign key to the public schema.

A violation in any of those fails the build. That has been verified by mutation: an inline
`.upsert({'zzz_bad_inline_col': 1})` produces
*"column `user_profiles.zzz_bad_inline_col` is referenced but does not exist"* and exit 1.

**It does not prove** anything about the column keys of the other 31 sites. Specifically:

- it does **not** resolve a payload assembled in a helper and spread in (`..._data.toSupabase()`);
- it does **not** resolve a payload passed by identifier (`.insert(payload)`) — there key
  extraction never engages at all, and the site is skipped silently;
- it therefore performs **no dataflow analysis of any kind**, and none is claimed. A green run is
  evidence about 143 sites, not 174.
- it is a **static** check against migration-derived schema. It says nothing about RLS, about
  whether a write is authorized, or about whether a failure is surfaced to the user — CON-03 is
  precisely a case where a type mismatch was swallowed by `catch (_) {}`.
- it says nothing about code **outside its two scan roots**. `run.mjs:37` sets
  `ROOTS = ['apps/mobile/lib', 'supabase/functions']`, and its own comment records that
  `apps/api/src` was a third root until the NestJS retirement (V5 §55). Anything added outside
  those two paths is unscanned, and the 174 denominator would not grow to include it — so **174
  is the number of write sites the guard can see, not the number the product contains.**
  (This correction came out of verifying the brief: an earlier draft said the roots were
  `apps/` broadly, which overstated them. It is also one reason my first standalone count
  reported 81 — it walked all of `apps/`, including the vendored plugin tree.)

## 2 · Current coverage, measured

`npm run test:contract` now prints, deterministically across runs:

```
COVERAGE  write sites 174: 143 fully analysed, 11 with a spread (literal keys only),
                           20 opaque (payload by variable)
COVERAGE  31 write site(s) contribute column keys this guard CANNOT see.
PASS  … — scope: 143 of 174 write sites fully analysed, 31 NOT (see COVERAGE)
```

- **143 of 174 (82 %)** fully analysed — an inline `{...}` payload whose keys are all checked.
- **11 partial** — a spread (`{...data, 'coach_id': uid}`): the literal keys *are* checked, the
  spread's are not, so the site looks covered.
- **20 opaque** — `.insert(payload)`: the body is an identifier, there is no `{`, key extraction
  never engages, and the site is skipped **in silence**.

Internally consistent: 143 + 11 + 20 = 174, and 11 + 20 = 31 = the number of rows
`--list-unseen` prints. Both asserted by test.

---

## 3 · The limitation, precisely

The guard reads keys only at **brace depth 1** of the payload. That is a sound rule for an
inline literal — depth > 1 is a nested JSONB value, not a column — but it means a payload
assembled anywhere other than the call site is invisible. Verified by paired mutation:

| mutation | result |
|---|---|
| inline `.upsert({'zzz_bad_inline_col': 1})` | **FAIL**, correctly: *"column `user_profiles.zzz_bad_inline_col` is referenced but does not exist"* |
| the same key added to `toSupabase()`, spread in at `intake_flow_screen.dart:280` | **PASS**, blind |

**Pass/fail semantics are unchanged** by the coverage work, proven by equivalence against the
pre-change runner: clean tree `0`/`0`, planted inline violation `1`/`1`.

---

## 4 · What is unseen, and why it matters where it does

The 31 sites, grouped. Sensitivity is taken from the governing documents, not assigned here.

| table | sites | note |
|---|---|---|
| `user_profiles` | 3 — `intake_flow_screen.dart:171`, `:280`, `personal_info_screen.dart:228` | **named in `SECURITY_LEDGER_PHI.md`.** `:171` and `:280` are the two **CON-03** serializers |
| `subscriptions` | 2 — `stripe-webhook/index.ts:71`, `:190` | **billing / entitlement**, the heaviest evidence class in `QA_CLOSURE_STANDARD.md` §2.1 |
| `messages` | 1 — `messaging_service.dart:165` | named in the PHI ledger |
| `weekly_feedback` | 1 — `coach_program_service.dart:109` | named in the PHI ledger |
| `coach_packages` | 4 — `package_service.dart:77,79,142,144` | commerce-adjacent |
| `custom_exercises` | 3 · `workout_programs`/`program_workouts` | 4 · coach-authored content |
| `workout_set_logs` | 2 · `daily_scores` 1 · `client_habits` 1 | member training data |
| `events`/`event_sessions` | 4 · `challenges` 1 · `foods` 1 · `notifications` 1 · `ai_reviews` 1 · `coach_exercise_media` 1 | lower sensitivity |

**The sharpest consequence is evidentiary, not a live bug.** `toSupabase()` and
`toSupabasePartial()` are the subject of CON-03, so **a green contract guard was never evidence
about the very functions that finding concerns** — and it had been cited as a passing control
while blind to them. That is now stated on the verdict line itself.

**No claim is made that any of the 31 sites contains a defect.** They are unverified, which is
not the same as wrong.

### 4a · Intersection with gated code

| area | intersects? | consequence |
|---|---|---|
| **CON-03** | **Yes, directly.** `intake_flow_screen.dart:171` and `:280` are the `toSupabasePartial()` / `toSupabase()` sites | CON-03 is `BLOCKED_OWNER` on `CON-03-TYPE`. Resolving these keys statically now would check them against a column type that the pending decision may change, so **Option B should not touch them before `CON-03-TYPE` is answered** |
| **Billing** | **Yes.** `stripe-webhook/index.ts:71` upsert and `:190` update on `subscriptions` | `QA_CLOSURE_STANDARD.md` §2.1 puts billing in the heaviest evidence class. Reading these is safe; **changing them is not in scope here** and would need its own authorization |
| **Wave 3B / SEC-R3** | **No.** | This work touches no failure-reporting call site, no `AppFailure` wiring, and no service-layer sweep |
| **SEC-R2 / SEC-04** | **No.** | Static only; no QA probe, no live write, no migration |
| **RLS / policies / roles** | **No.** | The guard reads schema; it changes nothing and asserts nothing about authorization |

**So Option B is partially gated:** its highest-value targets are the two CON-03 sites, and those
are behind `CON-03-TYPE`. The remaining 29 are not gated, but they are also the lower-value half.

---

## 5 · Options

### A · Accept the limit, as now documented (no further work)
The guard reports its own scope; the verdict line cannot be quoted as completeness; the sites
are listable with `--list-unseen`.
- **Cost:** none. **Risk:** 31 sites, including PHI and billing writes, keep no static
  column-contract check. A future column rename could break them silently.

### B · Narrow, convention-bound resolution
Resolve two shapes only: a payload map assigned to a local variable **in the same function**,
and a spread of a same-file helper returning a map literal.
- **Cost:** moderate; a bounded single-file analysis, no general dataflow.
- **Covers:** most of the 20 opaque and 11 spread sites, including both CON-03 ones.
- **Risk:** false positives would **break CI for everyone**, which is why this was not done
  unilaterally. Needs its own mutation suite before it may be trusted.

### C · Full cross-file dataflow analysis
- **Cost:** high — effectively a small Dart/TS analyser, and a maintenance burden.
- **Risk:** highest false-positive surface. Not proportionate to the finding.

### D · Verify at the database instead
Let the live contract suites catch column mismatches at execution time rather than statically.
- **Cost:** none to build; already partly true.
- **Risk:** needs QA credentials and authorization (the FG-1/FG-2 blocker), and an execution-time
  failure is exactly what CON-03 shows can be swallowed by a `catch (_) {}`. **A runtime check
  cannot substitute for a static one where the failure path is silent.**

---

## 6 · Recommendation

**Option A now, Option B scoped as its own authorized task.** Reasons:

1. The honesty defect is already fixed — the guard no longer overstates itself, which was the
   actual problem found.
2. B's value concentrates on the `user_profiles` and `subscriptions` sites, and the
   `user_profiles` ones are **CON-03**, which is blocked on `CON-03-TYPE` anyway. Resolving them
   statically before the storage contract is decided would verify keys against a schema that may
   be about to change.
3. B must not be merged without its own mutation suite; a false positive in this guard stops
   every push. That makes it a task with acceptance criteria, not an incidental improvement.
4. C and D are not proportionate — C in cost, D because it cannot see a swallowed failure.

**This is a recommendation. It is not a decision, and no option has been implemented.**

---

## 7 · The minimum owner decision needed before any implementation

**One answer unblocks this: `COVERAGE-OPT` — A, B, C or D.** Nothing else is required to begin,
and nothing may begin without it.

Two answers are needed only if that answer is **B**: whether B runs before or after
`CON-03-TYPE` (because B's best targets are the CON-03 serializers), and whether an unresolved
PHI or billing site should **fail** rather than report. If the answer is A, C or D, those two
questions fall away.

### Owner input requested

```
COVERAGE-OPT   : Option __    (A accept · B narrow resolution · C full dataflow · D runtime only)

COVERAGE-B-WHEN: if B — before or after CON-03-TYPE is answered?   before / after

COVERAGE-GATE  : should an unseen PHI or billing write site FAIL the guard
                 rather than be reported?                          Y / N
                 (today it reports; 31 pre-existing sites would fail CI on Y)
```

## 8 · Boundary

No application write site, CON-03 serializer, migration, RLS policy, role or security policy
changed. No QA probe, QA write or production operation. No credential accessed. No finding
promoted and no evidence count altered. Pass/fail semantics of the guard are unchanged and
proven equivalent to the pre-change runner. PR #1 remains open, draft and unmerged.
