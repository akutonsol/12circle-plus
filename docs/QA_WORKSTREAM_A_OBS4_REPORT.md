# QA Workstream A — OBS-4: duplicate generated day titles

**Date:** 2026-08-24 · **Branch:** `chore/qa-environments-secure-ai-backend`
**Environment:** QA `eyqtldjqpgpljlqvpowh` only.
**Production `nxdbooufqzkpslkcogxc` was not contacted — see §7.**
**Baseline:** [`PHASE_2_WORKOUT_RECONCILIATION.md`](PHASE_2_WORKOUT_RECONCILIATION.md)
§10, taken as authoritative and not re-derived.

---

## 0. Summary

OBS-4 had already been fixed on disk and on QA by **migration 121**, written in the
Phase 2 session. This workstream verified that fix end to end rather than re-doing it —
and found that **the fix itself breached a Phase 1 security boundary**, along with two
sibling Phase 2 migrations. That is the substantive work delivered here.

| | Finding | Status |
|---|---|---|
| **OBS-4** | duplicate generated day titles | **closed** — verified live, end to end, 15/15 |
| **OBS-4-R1** | migration 121's `CREATE OR REPLACE` dropped the pinned `search_path` on the client-callable SECURITY DEFINER `generate_client_plan()` | **fixed** — migration 122 |
| **OBS-4-R2** | migrations 119/120 did the same to 13 more functions, one of them SECURITY DEFINER | **fixed** — same migration, same statement |
| **OBS-4-R3** | four trigger functions created by 119/120 were born with `EXECUTE TO PUBLIC`, escaping 116's schema-wide revoke | **fixed** — same migration |
| **OBS-4-R4** | `tool/qa_self_guided.dart` — a script named `qa_*` that calls `generate_client_plan()` — is hardcoded to **production** | **open, not mine to fix** — §8 |

No product decision was found to block OBS-4. Migration 052's contract was recovered
from the repository and preserved; no new naming convention was invented.

---

## 1. Root cause

### 1.1 The defect (recovered, not re-investigated)

Migration **052** added exactly one behaviour to `generate_client_plan()`: four
declarations and one counting loop that suffixes a day title `A`/`B`/`C` when its
training focus repeats in the split. Migration **077** rebuilt the function from **048**
— which predates 052 — and its own header says it *"Reproduces 048 verbatim + the bias
block"*. It did. 048 has no title rule, so 077 silently reverted 052.

The mechanism was only ever the generator's own suffixing: **there is no database
constraint on `program_workouts.title`**, despite 052's filename. Nothing in 077 reads,
depends on, or benefits from ambiguous titles. The regression is collateral from
branching off the wrong base.

### 1.2 What the two halves of OBS-4 were

052's stated motivation — session status keyed by `workout_title`, so starting one day
marked all its twins in progress — is the **identity** half, and Phase 2 already fixed it
better: `sessionStatusFor` keys by workout id with the title as a guarded pre-103
fallback. **That is untouched here** (verified, §4 and §6).

The **data-generation** half is independent of how status is keyed: three cards reading
"Full Body" is a defect in the generated data whatever the code does with them. That is
what 121 restores.

### 1.3 The root cause of the regressions this workstream found

`SET search_path` is part of a function's **definition**, not a grant. ACLs and ownership
survive `CREATE OR REPLACE`; `proconfig` does not. Migrations 116 §1 and 118 F-08
deliberately used `ALTER FUNCTION` so that no function body was touched — which means
every later `CREATE OR REPLACE` silently discards the pin.

**This is the same failure mode as OBS-4 itself, one layer down.** 077 reproduced a
function from an older base and dropped 052's rule; 119/120/121 reproduced functions
without repeating 116/118's clause and dropped the pin. Both were invisible in review
because the replacement looked complete on its own.

---

## 2. Evidence — before

### 2.1 The generator defect, reproduced read-only on QA

077's titling is `_plan_day_title(focus)` with no suffix rule, so it can be reproduced
exactly without any DDL, writes, or rollback:

```sql
select s.label,
       (select array_agg(public._plan_day_title(f) order by o)
          from unnest(s.split) with ordinality t(f,o)) as titles_077,
       public.plan_day_titles(s.split)                 as titles_121
  from (values …) s(label, split);
```

| split | 077 (the defect) | 121 (052's rule) |
|---|---|---|
| 3-day | Full Body · **Full Body** · **Full Body** | Full Body A · Full Body B · Full Body C |
| 4-day | Upper Body · Lower Body · **Upper Body** · **Lower Body** | Upper Body A · Lower Body A · Upper Body B · Lower Body B |
| 5-day | Push Day · Pull Day · Leg Day · Upper Body · Lower Body | *unchanged — nothing repeats* |
| 6-day | Push · Pull · Leg · **Push** · **Pull** · **Leg** | Push Day A · Pull Day A · Leg Day A · Push Day B · Pull Day B · Leg Day B |
| 4-day + upper bias | Upper · Lower · **Upper** · **Upper** | Upper Body A · Lower Body · Upper Body B · Upper Body C |

The last row is the case 052 never saw — 077's bias block rewrites the **last** day
(`v_split[v_days] := v_focus_day`), manufacturing a duplicate a pre-bias titling would
miss. 121 titles from the split *as finally set*, which is 052's own rule applied to
077's own data.

Stored rows at the time of the Phase 2 investigation (baseline §10.4) — two
self-generated programs regressed:

```
211206c2…  3-day   "Full Body",  "Full Body",  "Full Body"
48099a62…  4-day   "Upper Body", "Lower Body", "Upper Body", "Lower Body"
4818d97f…  coach   unaffected (day-specific titles)
```

### 2.2 The Phase 1 regressions, live on QA

```sql
select p.oid::regprocedure, p.prosecdef from pg_proc p …
 where n.nspname='public' and p.prokind='f'
   and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c
                    where c like 'search_path=%');
```

**15 functions, mapping 1:1 to the three Phase 2 migrations, 2 of them SECURITY DEFINER:**

| Migration | Functions left with a mutable `search_path` |
|---|---|
| **119** | `_plan_day_exercises`, `_wk_int`, `_wk_jint`, `_wk_jnum`, `_wk_num`, `canonical_exercise_prescription`, `canonical_exercise_prescriptions`, `is_canonical_exercise_prescription`, `program_workouts_canonicalize`, **`materialize_program_week`** *(DEFINER)* |
| **120** | `workout_sessions_terminal_status`, `workout_set_logs_protect_history`, `workout_set_logs_require_identity` |
| **121** | **`generate_client_plan`** *(DEFINER)*, `plan_day_titles` |

Sibling functions 121 did *not* touch — `deactivate_self_generated_plan`, even the
non-definer `_plan_day_title` — still carried `search_path=public, pg_temp`, which is
what makes the attribution unambiguous.

Why it matters: a definer function without a pinned `search_path` resolves unqualified
names through the **caller's** `search_path`, so a caller who can create objects in a
schema earlier on that path can shadow a table or operator and have it executed with the
definer's rights. That is the exact hole 116 was written to close, and
`generate_client_plan()` is on 116's Class B client-callable allow-list.

And, from the same probe (SP-5):

```
FAIL SP-5  EXECUTE grants to PUBLIC or anon: 4
  program_workouts_canonicalize()    workout_sessions_terminal_status()
  workout_set_logs_protect_history() workout_set_logs_require_identity()
```

116 set `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` so future
functions would inherit the closed posture. Default privileges are recorded **per
creating role**, and the Phase 2 migrations were applied through the CLI's own login
role, so functions they created were born with Postgres's built-in `EXECUTE TO PUBLIC`.
All four are trigger functions and SECURITY INVOKER, so this was a **posture deviation,
not a live escalation** — a trigger function cannot be called directly, and EXECUTE on
one is checked at `CREATE TRIGGER`, not when it fires. The posture exists precisely so
nobody has to make that argument function by function.

---

## 3. The fix

### 3.1 OBS-4 itself — migration 121 (pre-existing, verified not re-authored)

Already on disk and already applied to QA when this workstream started. Verified rather
than rewritten:

1. **`public.plan_day_titles(text[])`** — 052's inline loop extracted into one authority,
   shared by the generator, the backfill and the regression suite.
2. **`generate_client_plan()`** — 077's body verbatim, with 052's rule put back, applied
   to the split **after** the bias block.
3. **Backfill** of already-generated rows, scoped to `coach_id IS NULL`; idempotent
   (after one pass no `(program_id, title)` group has `total > 1`).
4. `workout_sessions.workout_title` deliberately **not** rewritten — that column is
   history.
5. **No constraint, no lookup and no key on titles.** Title-based identity is not
   reintroduced.

Independently confirmed against the repository: `_plan_day_title`'s vocabulary is 047's,
the suffix form is 052's `chr(64 + occurrence)`, and no new convention was introduced.

### 3.2 The regressions — migration 122 *(new)*

`supabase/migrations/122_repin_function_search_path.sql` — the smallest architecturally
correct forward migration, because both halves are **Phase 1's own statements re-run**,
not new policy:

- **§1** — 118 F-08's loop verbatim: `ALTER FUNCTION … SET search_path = public, pg_temp`
  for every function in `public` that lacks a pin. No function body touched, no grant
  changed, no policy changed, idempotent.
- **§2** — 116's `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC` / `FROM
  anon`. Targets PUBLIC and anon only; the `authenticated` allow-list 116 granted,
  `service_role` and the owner are untouched.
- Both halves are **self-verifying**: the migration ends each section by re-querying the
  catalog and `RAISE EXCEPTION`-ing if anything is left behind. A repair that cannot fail
  is a repair nobody notices has stopped working.
- Carries a ROLLBACK note, per Phase 1 migration discipline.

**Historical migrations 052 and 077 were not modified. Neither were 119, 120 or 121** —
all three are already applied to QA, and the repo's own guard (SEC-027) forbids rewriting
an already-applied file. 122 is forward-only, which is also what a fresh environment
needs: applying 119 → 120 → 121 → 122 in order ends in the correct state.

---

## 4. Files and migrations changed

| File | Change |
|---|---|
| `supabase/migrations/122_repin_function_search_path.sql` | **new** — re-pins `search_path` on 15 functions and re-closes `EXECUTE` to PUBLIC/anon; self-verifying |
| `supabase/tests/security/function-search-path.sql` | **new** — 5 live assertions (SP-1…SP-5), rolls back |
| `supabase/tests/workout/plan-day-titles.sql` | **extended** — TITLE-13/14/15, an end-to-end run of the real generator |
| `apps/mobile/test/unit/phase1_security_boundary_test.dart` | **+2 tests** — SEC-028, the guard 119/120/121's review did not have |
| `supabase/migrations/121_restore_unique_plan_day_titles.sql` | **verified, unchanged** |
| `supabase/migrations/052`, `077`, `119`, `120` | **not touched** |

Preserved, and re-verified rather than assumed:

- **119/120 workout contracts** — all 20 `phase2-contract.sql` assertions still pass
  after 122, including the four trigger-backed ones whose functions 122 revoked PUBLIC
  EXECUTE from. The triggers still fire.
- **Workout-ID session identity** — `programSessionStatusProvider` / `sessionStatusFor`
  remain id-first with the title as a guarded fallback. Not read, not modified. WKT-208
  passes.
- **Phase 1 boundaries** — restored, not merely preserved. `can_read_program` untouched;
  anon still 401 on `program_workouts`.

---

## 5. Tests

### 5.1 Added

**`apps/mobile/test/unit/phase1_security_boundary_test.dart` — SEC-028, 2 tests**

- *"a function redefined after Phase 1 keeps its pinned search_path"* — the invariant is
  about the **end state of the chain**, not each file: a declaration may omit the clause
  only if a **later** migration re-pins generically. It finds the last generic sweep and
  asserts every function declared above it pins inline.
- *"the search_path re-pin verifies itself"* — 122 must contain a `RAISE EXCEPTION` and
  must not name production.

**Both new guards were proved to bite**, not merely to pass — a throwaway migration 123
was added and the tests were watched to fail:

```
migration 123 declares guard_probe() after the last search_path sweep (migration 122),
so it must carry `SET search_path = public, pg_temp` in its own header —
CREATE OR REPLACE discards the pin an ALTER put there
```

The same probe was run against the **pre-existing** day-title guard, which also failed
correctly on a 077-style redefinition. The probe migration was removed.

**`supabase/tests/workout/plan-day-titles.sql` — TITLE-13/14/15** — the previous 12
assertions pinned the rule and the stored data; these run `generate_client_plan()`
itself, as the QA test client, inside the rolled-back block, and read back what it wrote.
It is the only assertion that proves the **wiring** rather than the parts.

**`supabase/tests/security/function-search-path.sql` — SP-1…SP-5** — the posture, live.
Every one of these FAILED against QA before 122.

### 5.2 Results

| Suite | Result |
|---|---|
| `flutter test` (full) | **623 passed**, 0 failed |
| `npm run test:api` (unit + e2e) | **58 + 6 = 64 passed**, 0 failed |
| `plan-day-titles.sql` (live QA) | **15/15 PASS** |
| `phase2-contract.sql` (live QA) | **20/20 PASS** — unchanged by 122 |
| `function-search-path.sql` (live QA) | **5/5 PASS** — was 3/5 before 122 |
| `npm run test:security` | **could not run** — needs `QA_SERVICE`; `.env` and `.env.local` are both empty. Unchanged from the Phase 2 matrix; recorded, not silently skipped. §8. |

---

## 6. Live QA verification

### 6.1 The generator, end to end

```
PASS TITLE-13 generator produced a program → Upper Body A | Lower Body A | Upper Body B | Lower Body B
PASS TITLE-14 a freshly generated program has no duplicate day titles: 0 duplicated
PASS TITLE-15 titles use 052's vocabulary and suffix form: 0 off-contract
```

The probe raises at the end, so it rolled back. Confirmed afterwards: 3 programs, the
same 2 self-generated ids (`211206c2…`, `48099a62…`), 11 program days, 2 assignments —
**QA left exactly as found.**

### 6.2 Stored data

```
211206c2…  Full Body A  | Full Body B  | Full Body C
48099a62…  Upper Body A | Lower Body A | Upper Body B | Lower Body B
4818d97f…  Monday — Upper Push | Tuesday — Lower Pull | Thursday — Upper Pull | Friday — Lower Quad   (coach, untouched)
```

```
PASS TITLE-10 self-generated programs with duplicate day titles: 0
PASS TITLE-11 coach-authored titles left untouched: 0 suffixed
PASS TITLE-12 workout identity is the id, and it is unique
```

### 6.3 Client-facing REST re-probe, after 122

Same credentials and endpoints as the Phase 2 BEFORE run:

```
REST-1 anon   GET /program_workouts → 401          ← the 117 boundary, intact after the revoke
REST-2 client login                 → 200
REST-3 client GET /program_workouts → 200, 8 rows
        Monday     Upper Body A          Tuesday   Lower Body A
        Thursday   Upper Body B          Friday    Lower Body B
        Monday — Upper Push   Tuesday — Lower Pull   Thursday — Upper Pull   Friday — Lower Quad
REST-4 duplicate titles visible to the client: 0
```

### 6.4 Posture, after 122

```
PASS SP-1  unpinned SECURITY DEFINER functions: 0
PASS SP-2  unpinned functions of any kind: 0
PASS SP-3  functions pinned to a path other than public: 0
PASS SP-4  generate_client_plan + materialize_program_week re-pinned: 2/2
PASS SP-5  EXECUTE grants to PUBLIC or anon: 0
```

`generate_client_plan` ACL after 122: `{postgres=X, service_role=X, authenticated=X}` —
unchanged by the repair, and still carrying 052's rule (`prosrc like '%plan_day_titles%'`
→ true).

---

## 7. Production safety

**Production was never contacted.** Evidence, not assertion:

1. Every database interaction in this workstream went through
   `supabase db query --linked`. The linked ref is `eyqtldjqpgpljlqvpowh` (QA) in both
   `supabase/.temp/project-ref` and `supabase/config.toml:1`. The production ref
   `nxdbooufqzkpslkcogxc` appears nowhere in the CLI's link state.
2. The one HTTP probe (§6.3) built its base URL by reading
   `apps/mobile/dart_defines/qa.json` and **asserted** `'eyqtldjqpgpljlqvpowh' in URL`
   before issuing any request.
3. No file added or modified here contains the production ref
   (`grep -c` → 0 for 122, both probe files; the 3 hits in the Dart test file are
   pre-existing *negative* assertions that migrations must **not** name production).
4. SEC-027's *"no Phase 2 migration widens the Phase 1 authorization boundary"* asserts
   every migration ≥ 119 — now including 122 — does not name production, does not open a
   blanket policy, does not grant to anon, does not disable RLS. It passes.
5. **The `qa_*` Dart tools were deliberately not run.** See OBS-4-R4 below — they target
   production. All live verification here was done with SQL probes instead.

---

## 8. Remaining concerns

**OBS-4-R4 · `tool/qa_self_guided.dart` calls `generate_client_plan()` against
production.** Independently confirmed this workstream:

```
apps/mobile/tool/qa_entitlements.dart:27     const _url = 'https://nxdbooufqzkpslkcogxc.supabase.co';
apps/mobile/tool/qa_self_guided.dart:22      const _url = 'https://nxdbooufqzkpslkcogxc.supabase.co';
apps/mobile/tool/live_integration_test.dart:15 const _url = 'https://nxdbooufqzkpslkcogxc.supabase.co';
```

`qa_self_guided.dart:200` issues `POST /rest/v1/rpc/generate_client_plan`. That RPC
**supersedes assignments, deletes the caller's self-generated programs and writes new
ones.** An operator running a script named `qa_self_guided` to verify OBS-4 would have
regenerated a real user's program in production. This is why §6 used SQL probes. Already
raised as REL-18 by Workstream G; repeating it here because it sits directly on the
OBS-4 verification path. **Not fixed here — it is outside this workstream's mandate and
belongs with whoever owns the tooling.**

**Live security suite still not re-run.** `npm run test:security` needs `QA_SERVICE`,
which is not in this environment. `function-search-path.sql` covers the specific posture
122 touches, executed live, but it is not a substitute for D01–D06. Must be re-run before
Phase 2 sign-off — this is now more load-bearing than it was, because Phase 2 was shown
to have drifted the function posture without anyone noticing.

**Neither 121 nor 122 is in the migration ledger.** `supabase_migrations.schema_migrations`
on QA stops at **112**; everything from 113 onward — the Phase 1 security work included —
was applied by direct execution, so the ledger no longer describes the database. A fresh
environment built with `supabase db push` would apply 113–122 and arrive at the right
place, but QA cannot be reasoned about from the ledger. Worth reconciling before
production ever receives these.

**`workout_list_screen:315` still matches a browse card to a sample workout by title.**
Verified this workstream that both sides are in-repo constants — `_sampleWorkouts` and
`workoutServiceProvider.getSampleWorkouts()` — so the A/B/C suffixing on *generated*
titles cannot reach it. Not a live defect; a residual title-as-identity pattern worth
removing during UI work.

**`workout_sessions.workout_title` rows for renamed days still carry the old label.**
Intended — that column records what the client trained. A pre-migration-103 session (no
`workout_id`) will no longer match a renamed day by title.

**No product decision blocks OBS-4.** 052 is a recorded product decision that nothing
deliberately reversed, its client-facing rationale (a client must be able to tell
Monday's session from Thursday's) stands independently of how status is keyed, and its
vocabulary and suffix form were recovered from the repository. Nothing was invented, so
there was nothing to escalate.
