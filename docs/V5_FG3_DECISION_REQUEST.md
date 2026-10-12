# V5 · OWNER DECISION REQUEST — `FG-3`, the positive legs of the 116 wrapper class

> ## ✅ DECIDED BY THE OWNER, 2026-10-12 — assigned and implemented
>
> All six questions were answered. This document is kept as the record of what was asked and
> why; the answers and what was built from them are below. **One item remains open and it is
> not mine to close** — see `Q6`.
>
> | # | owner's decision | state |
> |---|---|---|
> | `Q1` | **Assign and proceed.** | **done** — `d23-fg3-positive-legs.mjs`, 21/21 |
> | `Q2` | positive callers: program-scoped → **the owning coach**, real non-NULL program; subject-scoped → **the subject themselves**, real non-NULL subject | **done** — §2 and §3 of D23 |
> | `Q3` | success evidence: **option C** — HTTP 200 **plus the expected engine-owned row(s)**, teardown verified by reading the database | **done, with one factual narrowing — see below** |
> | `Q4` | `service_role` is a **separate liveness test**, not authorization evidence | **done** — D23 §4, labelled in the assertion text itself |
> | `Q5` | isolated QA engine execution permitted, with side-effect assertions and verified teardown | **done** — D23 §5, teardown by exact id |
> | `Q6` | propose **option 3** for §2.1; do **not** amend the standard | **proposed, PENDING GOVERNANCE** — the standard is untouched |
>
> ### The narrowing in `Q3`, which the code forced and I did not choose
>
> Option C says *"200 plus the expected engine-owned row or rows"*. Establishing what that means
> per wrapper required reading the five engine bodies, and the answer is **not uniform** — three
> of the five **write nothing at all**:
>
> | engine | mutating statements | so the "expected effect" is |
> |---|---|---|
> | `predict_client_engine` (095) | **none** | the returned payload |
> | `assemble_weekly_review_engine` (096) | **none** | the returned payload |
> | `evaluate_week_engine` (094) | **none** | the returned payload |
> | `regenerate_program_engine` (094) | `UPDATE workout_programs.plan` + `INSERT decision_traces`, **only on the `applied` branch** | with `p_approved=false`: status `pending_approval` and **no write** |
> | `materialize_program_week_engine` (119) | `INSERT program_workouts` | the new rows, counted scoped to the fixture program |
>
> For the three read-only engines, asserting *"a row appeared"* would assert something the engine
> never promised. The payload is asserted instead. **This is a factual limit on how option C can
> apply, not a substitution of a different option**, and it is flagged here rather than quietly
> implemented. If you want the three read-only wrappers held to a different standard, say so.
>
> It also corrects something I wrote earlier: I had said each wrapper *"delegates to an engine
> that writes to four tables"*. **That was wrong.** The four INSERTs I had seen in migration 116
> belong to `generate_workout`, `create_weekly_review`, `record_prediction` and
> `snapshot_program_version` — **not** to these five engines.
>
> ### How the positive legs prove the *predicate*, not merely a 200
>
> Each is run as a **pair against the identical scope, varying only the caller**:
>
> * the owning coach / the subject → **200**
> * an unrelated authenticated user → **403 · `42501`**
>
> Same program id, same subject id, same arguments. The caller is the only variable, so the
> difference can only come from the relationship arm — which rules out the NULL arm (the scope is
> real and non-NULL in both), a `service_role` bypass (both are user JWTs), an admin shortcut
> (neither holds admin) and a malformed signature (a 403 and a 200 both prove it resolved).


**Status: owner assignment required. Nothing is implemented, and `FG-3` is not closed.**

`FG-3` is registered in `MASTER_REMEDIATION_REGISTRY.md`'s follow-up table, under a header that
reads *"recorded, **NOT implemented** (owner assignment required, no silent scope expansion)"*.
This document supplies the analysis so the assignment can be made, and stops there.

## 1 · What `FG-3` asks, verbatim

> | **FG-3** | Assert the **positive** legs of the 116 wrapper class: the owning coach → 200 and
> `service_role` → 200 for each of the five wrappers, so over-refusal is distinguishable from
> correct refusal | SEC-R1's *Live QA* field, third and second legs · the same limitation on the
> other four wrappers | Wave 2 (2A/2B), with the `d04` §8 class work |

From `SEC-R1`'s *Live QA* field, which names three legs:

> An unrelated authenticated client → 403 on a program they do not own; **the owning coach → 200;
> `service_role` → 200**

**Only the first is asserted.** `d04` §8 proves every one of the five wrappers *refuses* an
unauthorized caller. Nothing proves any of them *admits* an authorized one.

**Why that is not pedantic.** A wrapper rewritten to `RAISE EXCEPTION` unconditionally — or a
predicate that silently became `false` — would pass `d04` §8 completely. The suite would be green,
the row would stay `VERIFIED_CLOSED`, and the engine would be unreachable by its legitimate
callers. `SEC-R1`'s *Dependencies* field is explicit that this matters on a clock:

> *"None to fix. Blocks nothing, but **must land before any Wave 5 engine work re-exercises this
> path**."*

## 2 · What I established, so it need not be re-derived

| fact | source |
|---|---|
| The five wrappers are `predict_client`, `assemble_weekly_review`, `evaluate_week`, `regenerate_program`, `materialize_program_week` | `d04` §8 `engineWrapperClass({establishedIn:'116'})` |
| Every wrapper has the same shape: guard → `RAISE EXCEPTION … ERRCODE '42501'` → delegate to its `_engine` | `116_rpc_execution_security.sql` |
| **No wrapper is exempt any more.** `KNOWN_OPEN` is `[]`; migration 124 restored the last stripped guard (`materialize_program_week`) | `migration-durability-guard.mjs:109`, `124_wave_2a_security_regressions.sql` |
| A coach-owned `workout_programs` fixture is already established practice | `d05-intelligence-substrate.mjs:116,164`, `d17:49` |
| On success the engines write to **`decision_traces`, `communications`, `predictions`, `program_versions`** | `116` engine bodies |
| Closure class is **Security / authorization** → requires FIXED IN CODE · FIXED ON QA · **VERIFIED LIVE** · VERIFIED IN CI | `QA_CLOSURE_STANDARD.md` §2.1 |

## 3 · Four things `FG-3` as written does not determine

### 3.1 · Two of the five wrappers have no "owning coach"

The class splits by predicate, and `FG-3`'s wording covers only one side:

| wrapper | guard | the authorized positive caller is… |
|---|---|---|
| `evaluate_week` · `regenerate_program` · `materialize_program_week` | `can_act_on_program(p_program_id)` | the program's `coach_id`, an assigned client, that client's active coach, or an admin |
| `predict_client` · `assemble_weekly_review` | **`can_act_for(p_subject)`** | **the subject themselves**, their active coach, or an admin — **there is no program and no owning coach** |

So *"the owning coach → 200 … for each of the five wrappers"* is not expressible for two of them.
**Decision needed:** which caller is the authorized positive path for the subject-scoped pair.

### 3.2 · A positive probe must not pass a NULL scope argument

Both predicates admit a NULL scope, deliberately and with comments saying so:

```sql
-- can_act_on_program(program)
SELECT (SELECT auth.uid()) IS NULL        -- service_role / engine
    OR program IS NULL                    -- ← passes
    OR public.is_admin()
    OR EXISTS (… p.coach_id = auth.uid())           -- the owning coach
    OR EXISTS (… a.client_id = auth.uid())          -- the assigned client
    OR EXISTS (… is_active_coach_of(a.client_id));  -- that client's active coach

-- can_act_for(subject)
SELECT (SELECT auth.uid()) IS NULL        -- service_role / engine
    OR subject IS NULL                    -- unscoped call, subject defaulted  ← passes
    OR subject = (SELECT auth.uid())
    OR public.is_active_coach_of(subject)
    OR public.is_admin();
```

These arms are **documented design, not defects** — they keep optional-parameter call sites
working and let the internal engine call through. But they mean a positive probe that passes
`NULL` **gets its 200 from the NULL arm and proves nothing about authorization**. `d04` §8's
existing negative probe already relies on the opposite property, passing a non-program uuid so the
predicate is false.

**Decision needed:** confirm the positive contract requires a **real program the caller owns** (or
a real subject the caller may act for), and that a NULL-scope 200 does **not** satisfy `FG-3`.

### 3.3 · "→ 200" is not sufficient evidence by this programme's own standard

The repository's evidence rule is that **an HTTP status alone never proves a write or a denial**.
A wrapper returns `jsonb` from its engine; the engines write to four tables. So "200" could mean
the engine ran, or that it returned early having done nothing.

**Decision needed — what is the asserted successful outcome?** Three options, increasing in
strength and in side effects:

| option | asserts | side effect on QA |
|---|---|---|
| `A` | HTTP 200 and no `42501` | whatever the engine does, unasserted |
| `B` | 200 **plus a non-empty, shape-checked payload** | same as A, but a no-op engine is caught |
| `C` | 200 **plus the engine's own row landed** — a `+1` delta in `predictions` / `program_versions` / `decision_traces` / `communications` as applicable | the strongest, and writes rows other suites measure |

### 3.4 · What does `service_role → 200` prove?

`service_role` passes via the **`auth.uid() IS NULL`** arm — the "internal engine" arm. So that leg
demonstrates *the engine path is reachable*, which is a liveness property, **not an authorization
decision**. It would pass identically if every relationship arm were deleted.

**Decision needed:** is the `service_role` leg in scope for `FG-3`, and is it recorded as
liveness evidence rather than authorization evidence?

## 4 · The side-effect authorization, which is the real gate

A positive leg must execute the engine. `d04` §8 says why it declined to, for the then-unguarded
member:

> *"Calling `materialize_program_week` today would not test an authorization boundary — there is
> not one — it would **EXERCISE the open hole and write to QA through the engine**. Closure
> standard §5.2: where a security-sensitive probe cannot be made safe, the probe is not run and
> the limitation is recorded."*

The guard is now restored, so the first objection is gone — but the **write** remains. A positive
probe writes to `decision_traces` (currently **979** rows, which `j04` and `d05` §9 assert over),
`predictions`, `program_versions` and `communications`.

**Decision needed:** may an authorization probe execute the engine against QA, and under what
teardown obligation? The suites' established standard is D19's: **every fixture removed, and the
removal asserted by a read, never inferred from a `204`.**

## 5 · And a conflict in the closure standard that only you can resolve

`QA_CLOSURE_STANDARD.md` §2.1 defines **VERIFIED LIVE** as:

> *"A real request against QA reproduces the secure/correct behaviour, **and the same probe
> demonstrably failed before the fix**."*

**A positive leg cannot satisfy that as written.** Before the fix the wrapper had *no guard*, so
the owning coach received **200 then as well**. The pre-fix state was more permissive, not less:
there is no pre-fix failure to show, and manufacturing one would mean reverting an applied
migration, which §8 forbids.

The definition is authored for **denial** evidence. A positive leg is the opposite shape.

**Decision needed:** which standard governs a positive-path assertion. Options:

* `1` **VERIFIED IN CI is sufficient** for the positive legs — a standing guard that fails if the
  authorized caller stops succeeding — with VERIFIED LIVE retained for the denial legs only.
* `2` **A substitute pre-fix comparison** is accepted: the probe must fail against a deliberately
  broken predicate in an isolated harness (the `SEC-G11` / negative-control pattern), rather than
  against history.
* `3` **Amend §2.1** to state that the pre-fix-failure clause applies to denial evidence, and name
  what positive evidence requires.
* `4` Defer `FG-3`, and record that over-refusal remains undetectable until Wave 5 needs it.

## 6 · What is requested

1. **Assign `FG-3`** — or defer it with the Wave 5 dependency recorded.
2. **The authorized positive caller**, per predicate: program-scoped (§3.1 row 1) and
   subject-scoped (§3.1 row 2).
3. **The asserted successful outcome** — option `A`, `B` or `C` of §3.3.
4. **Whether the `service_role` leg is in scope**, and how it is classified (§3.4).
5. **Whether an authorization probe may execute the engine on QA**, and the teardown obligation
   (§4).
6. **Which evidence standard governs a positive leg** — §5, options `1`–`4`.

**Not requested, and not done:** any change to the five wrappers, to either predicate, to `d04`
§8, to the closure standard, or to `FG-3`'s registry row. No probe was run against QA for this
analysis beyond read-only inspection of committed migration source. **`FG-3` is not closed and is
not claimed to be.**
