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

## 7 · Owner input requested

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
