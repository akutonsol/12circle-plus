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

---

## `Q6` · Proposal for §2.1 — **PENDING GOVERNANCE AUTHORIZATION**

> **The governing standard has NOT been amended.** `docs/QA_CLOSURE_STANDARD.md` is byte-identical
> to its state before this work. What follows is a *proposal*, as authorized — option 3 — and it
> takes effect only if the required governance authority adopts it. **Until then `FG-3` stays open
> and `VERIFIED LIVE` is not claimed for the positive legs.**

### The defect in the current wording

§2.1 defines one state as:

> **VERIFIED LIVE** — *"A real request against QA reproduces the secure/correct behaviour, **and
> the same probe demonstrably failed before the fix**."*

That second clause is written for a **denial**: you show the hole, you close it, you show the hole
is gone. It is exactly right there.

It cannot be satisfied by a **positive** authorization path, and not because the evidence is weak —
because the requirement is incoherent for that shape. If the pre-fix wrapper had **no guard**, then
before the fix the authorized caller was *admitted*, and a probe asserting "the owning coach is
admitted" **passed**. Demanding it *"demonstrably failed before the fix"* demands that the correct
behaviour was previously broken. For these five wrappers it was not: 116 added a guard where there
was none, so the positive path's observable outcome is **unchanged by the fix**. The only honest
ways to satisfy the clause as written are to fabricate a pre-fix failure or to leave the leg
permanently unverifiable.

### Proposed clarification — option 3

**(a) Scope the existing clause to denial evidence.** The *"same probe demonstrably failed before
the fix"* requirement applies where the evidence asserts that an unauthorized action is
**refused**. Unchanged in substance; it simply says what it already means.

**(b) Define a parallel contract for positive authorization paths.** A positive leg reaches
`VERIFIED LIVE` when all five hold:

1. **A real, non-NULL scope.** The caller holds the relationship the predicate names, against a
   fixture that exists.
2. **The caller is the only variable.** The same scope, the same arguments, a different caller →
   **refused with the authorization error**. This is what makes the admission attributable to the
   relationship arm instead of a permissive NULL branch, a privileged bypass, an admin shortcut or
   a signature that merely resolved.
3. **The expected effect is observed, scoped.** The engine-owned row or rows, counted against the
   fixture so unrelated concurrent activity cannot satisfy the assertion — or, **where the engine
   performs no writes**, the returned payload. Three of these five engines write nothing, so a
   contract demanding a row for every wrapper would be unmeetable by construction.
4. **Privileged callers are separate and labelled.** A `service_role` or internal-engine result is
   **liveness**, never authorization, because it passes the `auth.uid() IS NULL` arm and would
   survive the deletion of every relationship arm.
5. **Teardown is verified by reading.** Fixtures and engine side effects are removed and their
   absence confirmed by a read, not inferred from a delete status.

**(c) Say explicitly that (b) does not weaken (a).** A finding whose remediation *changed* a
positive outcome — where the authorized caller was wrongly refused before the fix — still owes the
before/after pair under (a). (b) applies only where the fix **added** a guard without altering the
authorized path's outcome.

### Why this is proposed now rather than argued abstractly

`d23-fg3-positive-legs.mjs` **already implements (b)**, at **21/21**, within the live suite's
**1146/1146 across 23 suites**. So the proposal is not a request to lower a bar; it is a request to
write down the bar that the evidence already clears. If governance adopts it, `FG-3`'s positive
legs are evidenced against a stated contract. If governance rejects it, the suite stays and the
`FG-3` row keeps its retained limitation — **no evidence is lost either way**, and nothing has been
closed on the strength of a proposal.

---

# DECISION RECORD · §2.1 / the `VERIFIED LIVE` row — **AWAITING AUTHORIZATION**

**Nothing below has been applied.** `docs/QA_CLOSURE_STANDARD.md` has **no commit touching it** in
this entire campaign (`git log e8d72bf..HEAD -- docs/QA_CLOSURE_STANDARD.md` → empty).

### 1 · Exact location

`docs/QA_CLOSURE_STANDARD.md`, **line 43** — the `VERIFIED LIVE` row of the state table in §2,
which §2.1 then requires for the **Security / authorization** finding class (line 50).

### 2 · Minimal before/after

Only the row's **"Means"** cell changes. The "Proves" and "Does not prove" cells, every other row,
and §2.1's class table are untouched.

```diff
-| **VERIFIED LIVE** | A real request against QA reproduces the *secure/correct* behaviour,
-**and the same probe demonstrably failed before the fix** | Policies, grants, triggers and
-PostgREST **compose** as intended | That the user-facing path reaches it, or that no collateral
-regression occurred |
+| **VERIFIED LIVE** | A real request against QA reproduces the *secure/correct* behaviour.
+**For DENIAL evidence, the same probe must demonstrably have failed before the fix.** For
+**POSITIVE authorization evidence** — where the fix ADDED a guard and the authorized caller's
+outcome is unchanged by it — the requirement is instead all five of: a real **non-NULL** scope;
+the **caller as the only variable** (same scope and arguments, an unrelated caller refused with
+the authorization error); the **expected effect asserted scoped** to the fixture, or the
+documented response contract where the engine performs no writes; **privileged callers tested
+separately and labelled liveness**; and **teardown verified by reading**, including after an
+induced failure. | Policies, grants, triggers and PostgREST **compose** as intended | That the
+user-facing path reaches it, or that no collateral regression occurred |
```

### 3 · Rationale

The existing clause is correct for a **denial**: show the hole, close it, show it gone. It is
**incoherent for a positive path**. Where migration 116 added a guard to a wrapper that had none,
the authorized caller was admitted *before* the fix too — so "the same probe demonstrably failed
before the fix" demands that the correct behaviour was previously broken. The only ways to satisfy
it as written are to **fabricate a pre-fix failure** or to leave the leg **permanently
unverifiable**.

### 4 · Security impact

**It does not lower the bar; it states one where none was statable.** The five conditions are
strictly more than the clause they replace *for this shape*, and the denial requirement is
unchanged — it is scoped, not weakened. Specifically:

* "caller as the only variable" is what rules out a permissive **NULL arm**, a **`service_role`
  bypass**, an **admin shortcut**, and a **malformed signature** — none of which the original
  clause addressed at all, because it never contemplated a positive leg.
* "privileged callers labelled liveness" writes down that a `service_role` 200 is **not**
  authorization evidence. That is a tightening.
* The read-only carve-out is **factual, not permissive**: three of the five engines contain **zero
  mutating statements**, so a row requirement would be unmeetable by construction and would push
  evidence toward something invented.

### 5 · Required evidence, and its actual status

| condition | status |
|---|---|
| real non-NULL scope | **MET** — `d23` §1 asserts the fixture's `coach_id` *is* the calling coach |
| caller as the only variable | **MET** — every leg paired, same ids, stranger → `403`/`42501` |
| scoped expected effect / contract | **MET** — `program_workouts` 0→1; plan `1.0→1.05` by value with week 1 locked; `decision_traces` by engine-returned id; `program_versions` scoped; read-only engines asserted against their declared contracts |
| privileged callers separate | **MET** — §4, labelled liveness in the assertion text |
| teardown verified by reading, incl. after failure | **MET** — §5 reads back; an injected throw leaves **0** fixtures |

Verified **2026-10-12**: `d23` **37/37**, live suite **1161/1161 across 23 suites**, five static
guards green.

### 6 · Decision requested

**Approve, reject, or amend** the diff in §2.

* **Approve** → `FG-3`'s positive legs are evidenced against a written contract, and `FG-3` can be
  assessed for closure on its merits. *It does not close automatically; the row still needs the
  `VERIFIED IN CI` and `FIXED ON QA` states §2.1 requires.*
* **Reject** → the standard stands unchanged, `d23` **stays** (it loses no evidence), and the
  `FG-3` row keeps its retained limitation permanently, because no positive leg can ever satisfy
  the clause as written.
* **Amend** → say which of the five conditions to change; the suite asserts each one separately,
  so they can be altered individually.

**Until one of these, `FG-3` is OPEN and `VERIFIED LIVE` is not claimed for the positive legs.**
