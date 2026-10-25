# QA migration batch — PROPOSAL, HELD

> **Status: HELD by the owner (2026-10-25).** *"Do not apply the migration batch yet … hold the QA
> migration runbook as a proposal."* Nothing in this document has been run. It changes nothing on QA
> or production, and it does not authorize a change to `supabase/expected_applied.json`.
>
> **This revision corrects the first version (merged in PR #10).** Two of its claims were wrong and
> are withdrawn — see §1. Everything below was re-verified on **local replays only** (a scratch
> PostgreSQL on loopback, the repo shim, the committed migrations unmodified); none of it is QA
> evidence.

## 1 · Corrections to the first version

| First version said | What is verified | Source |
|---|---|---|
| *"Every programme materialization on QA already writes empty training days"*, and *"if production matches, real members may be getting empty training days"* | **Withdrawn.** Members' plans come from `generate_client_plan`, whose exercises are a fixed list per training split (`_plan_day_exercises`, migration 119) and **do not touch the intelligence substrate**. On a 000–181 replay with 0 profiles, a member plan has 4 days with 6/5/6/5 exercises. | replay probe E1 |
| 183 must be held back because applying it *"would make programme generation fail visibly on QA and the live workout checks go red"* | **Withdrawn.** `materialize_program_week` — the only function 183 changes — has **no caller** in the app, the edge functions, the live security/AI suites or CI. Applying 183 cannot break a user flow or a live check today. | `grep` across `apps/mobile/lib`, `supabase/functions`, `supabase/tests`, `.github` |
| Apply 182, 184, 185 by hand and record them with `supabase migration repair` | **Withdrawn as the recommendation.** `migration repair` writes the ledger without proving the SQL ran; it is only defensible after a catalog check, and with 183 no longer a blocker it is unnecessary (§4). | owner instruction 2026-10-25 |

## 2 · What the coaching engine actually does (000–181 replay, i.e. QA's declared state)

| Case | Result |
|---|---|
| Member plan (`generate_client_plan`, called by onboarding and the coaching-mode switch) | **Works** — real exercises, independent of the substrate |
| Coach Copilot (`generate_workout`), substrate empty (QA has **0** `exercise_intelligence` rows — read-only count, 2026-10-25) | 0 exercises selected; the app shows a banner and refuses to assign |
| Coach Copilot, substrate populated (one default profile per exercise) | 5 exercises selected — works |
| Program engine (`materialize_program_week`), substrate **empty** | writes 3 days with **0** exercises and reports `sessions_created: 3` |
| Program engine, substrate **populated** | **fails** with `23514` — the engine writes `{id, name, pattern, score}` with no sets/reps, which the canonical-prescription `CHECK` on `program_workouts` rejects |

**Why — a code defect AND a data gap, independently.** 093 wrote the engine; 116 renamed it to
`materialize_program_week_engine` behind an authorization wrapper; **119** replaced the public function
with a body that raised on an empty selection *and* mapped the selection into the canonical
prescription; **124** restored 116's wrapper, which delegates to the engine — still **093's body** — so
both of 119's fixes were lost. Populating the substrate (registry `EB-4`) turns "empty days" into
"`23514`". It does not make the engine work.

**Who can reach it today: nobody.** The coach Program Builder (`/program-designer`) saves a programme
with a plan and **no days**, and until this change told coaches to *"materialize week 1 from Coach
Copilot / the client program view"* — a step no screen performs. That is the reachable product defect,
and it is fixed in app code (see the product changes in the same PR): the message now says the
programme has no training days, and the Assign Program sheet will not offer a programme known to have
none.

## 3 · Migration 183 — what it does, what it does not, and its real prerequisites

- **Does:** restores 119's empty-selection guard inside the engine, where the `INSERT` happens.
- **Does not:** restore 119's canonical prescription mapping. With 183 alone, an empty substrate
  raises (correct) and a populated one still fails `23514`.
- **Safe to apply?** Yes — nothing calls the function it changes (§1).
- **Prerequisites for a WORKING program engine** (none of which 183 provides):
  1. a new migration that restores the prescription mapping into the engine (structure only,
     `weight_kg: null`, per PD-A01's interim contract), verified with a populated-substrate positive
     control;
  2. `EB-4` — the substrate populated through the Content Center's intelligence enrichment
     (`beta-readiness.md` §0–§1), a content-owner task with decision `D-1`;
  3. a product decision on whether the Program Builder materializes at all, and from which screen —
     today no screen does.

## 4 · 182, 184, 185 — independence, order, rollback (verified on replay)

Starting from a 000–181 replay (`lr_q`) and applying each file **as one transaction** in the order
182 → 184 → 185, **without 183**:

| Check | Result |
|---|---|
| All three apply | **yes** |
| `od_qax2_od14_replay.sh` (47 assertions) | **47/47 PASS** |
| QA-exhaustion probes `QAX-SEC-01`, `QAX-SEC-03.*` (6) | **PASS** |
| `QAX-SEC-06` certification probes (view, RPC, anon, summary, sweep) | **PASS** |
| `QAX-SEC-06` **`exercises` view** probe | **FAIL — not covered by 182.** The registry row for `QAX-SEC-06` is about the `exercises` view; 182 closes only the certification half. No migration closes the main half. |
| Rollback 185 (`ALTER POLICY` back + `DROP` the four new policies) | **policies identical** to the 000–181 state |
| Rollback 184 (re-run the captured pre-change definition) | relationship check gone; `anon` no / `authenticated` yes — as before |
| Rollback 182 (re-run the captured view and RPC definitions) | **view and RPC bodies identical** to pre-change |

**Dependencies:** 184 needs `is_active_coach_of(uuid)` (100, disambiguated by 137) and 131's partial
unique index; 185 needs the exact policy names listed in it; 182 needs `exercise_readable()` and
`is_content_editor()` (058/083). All are ≤ 181. 184 and 185 do not depend on each other or on 182.

**Rollback limitations:** `COMMENT` texts set by 182 and 184 stay changed unless restored separately;
184's rollback reopens the P0; rollbacks need the pre-change definitions captured **before** applying
(`pg_get_viewdef` / `pg_get_functiondef`, or a schema-only dump).

**What could not be verified from here:** that QA's catalog matches the committed migrations (ENV-2/3
history). The CI `ENV-3` step compares the declared frontier with the live ledger and has been green
at **181**; it does not compare function or policy bodies.

## 5 · Proposed batch, when the owner chooses to release it

1. **182 → 183 → 184 → 185 via `supabase db push`**, which needs no ledger repair because all four are
   applied for real. (183 is included because it is safe and because leaving it out is what forced the
   repair step.) Capture pre-change definitions first.
2. Verify the catalog, not just the ledger: function bodies and the six policies, read back.
3. Update `expected_applied.json` (frontier 185, nothing pending) — **on the owner's explicit
   authorization**, as a protected edit — which also makes `d08`'s refusal checks strict.
4. Run the live suites alone and record *VERIFIED LIVE*.

Not proposed until the owner says so. **Production is not part of any of this.**
