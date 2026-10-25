# QA migration batch 182 → 183 → 184 → 185 → 186 — PROPOSAL, HELD

> **Status: HELD.** The owner approved *route A* in principle (2026-10-25) and authorized
> merging PR #12, which declared 186. **Applying this batch to QA is NOT authorized** and
> nothing below has been run. This file keeps its original name for link stability; it now
> covers all five migrations.
>
> **Who runs it:** the owner (or someone the owner authorizes). This Claude session has no QA
> database credential and no linked CLI.

## 1 · What the batch does

| # | Finding / purpose | Change | Live check that becomes strict |
|---|---|---|---|
| **182** | `QAX-SEC-06` (certification half) | `exercise_certifications` view and `exercise_certification(uuid)` RPC scoped to `exercise_readable(id) OR is_content_editor()` | none yet — replay probes only |
| **183** | restores 119's empty-selection guard in the engine | `materialize_program_week_engine` refuses an empty selection | superseded by 186 in the same push |
| **184** | `QAX-SEC-01` (**P0**), OD-QAX-2 | `assign_nutrition_plan` requires an **active** coach–client relationship | `d08` OD-QAX-2 refusals (5) |
| **185** | `QAX-SEC-03`, OD-14 | six coach write policies require an active relationship; authored rows stay readable | `d24` (25 skipped while pending) |
| **186** | the coach programme engine | canonical prescriptions, all-or-nothing, no silent overwrite, `FOR UPDATE` lock | `d25` (7 skipped while pending) |

The three live checks are registered in `supabase/tests/security/run.mjs` and **gated on
`supabase/tests/security/migration-state.mjs`**: while a migration is declared pending they make
no request and record each assertion as **SKIPPED — never a pass** (the runner prints `SKIP …
NOT A PASS` and totals skips separately). They turn strict in the change that moves the frontier.

## 2 · Order, and why it is fixed

- `supabase db push` applies every unapplied version **in order**. It cannot skip 183.
- **183 must be applied before 186**, never after: 186 replaces 183's body; applying 183 later
  (e.g. with `--include-all`) would put the broken engine back.
- 182, 184 and 185 do not depend on each other or on 183/186. Dependencies of all five are at
  or below 124 (`is_active_coach_of` 100/137, 131's partial index, 119's helpers and canonical
  check, 093's plan shape, 124's wrapper, `exercise_readable`/`is_content_editor` 058/083).
- **Never `supabase migration repair`** to make the ledger agree — the owner has ruled it out,
  and a ledger row written ahead of the SQL makes a later push skip the migration.

## 3 · Evidence to re-confirm on the day

| Fact | Last evidence | Re-confirm with |
|---|---|---|
| QA ledger is exactly 000–181; 182–186 not applied | CI ENV-3, run `40234124646` (PR #12): *L-2 applied but undeclared: 0*, *L-5 182 vs 182*, pending 182–186 | `supabase migration list --linked` |
| 185 restricts no existing coach's row | read-only count 2026-10-25: **0 of 17** rows across the six tables lack an active relationship | the audit queries in 185's header |
| Intelligence substrate | read-only count 2026-10-25: **0** `exercise_intelligence` rows (621 exercises) | `select count(*) from exercise_intelligence` |

## 4 · Steps (nothing else may push, merge or rerun CI on any branch from step 1 to step 7)

1. **Verify the target.** `supabase/scripts/qa-db-reset.sh --check-only` (verifies and stops) or
   `supabase/.temp/project-ref` = `eyqtldjqpgpljlqvpowh`. Never `db reset`.
2. **Confirm the ledger**: `supabase migration list --linked` shows applied through **181** and
   182–186 local-only. Anything else: stop.
3. **Capture the before state**: `supabase db dump --linked --schema public -f qa_before_182_186.sql`,
   plus `pg_get_functiondef` of `materialize_program_week_engine(uuid,integer,jsonb)`,
   `assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)` and
   `exercise_certification(uuid)`, and `pg_get_viewdef('public.exercise_certifications')`.
4. **Dry run, then push**: `supabase db push --linked --dry-run` must list exactly **182, 183, 184,
   185, 186** in that order; then `supabase db push --linked`.
5. **Read back the catalog, not just the ledger**:
   - `assign_nutrition_plan` body contains `is_active_coach_of(p_client_id)`;
   - `materialize_program_week_engine` body contains `ENGINE_NO_SELECTION` and `FOR UPDATE`;
   - the six policies' `qual`/`with_check` contain `is_active_coach_of`, and the four
     `authoring coach reads own …` SELECT policies exist;
   - `exercise_certifications` view definition contains `exercise_readable`;
   - the engine and wrapper still pin `search_path`; `authenticated` cannot execute the engine.
6. **Declare it** — on the owner's authorization, a PR that moves `applied_through` to `"186"` and
   empties `pending` (a protected edit). This is what makes `d08`'s refusals, `d24` and `d25`
   strict. Until it merges, CI's ENV-3 is red (applied but undeclared) — which is why nothing else
   runs in between.
7. **Verify live, alone**: the manifest PR's CI run. Expected:
   - `d08` OD-QAX-2 refusals **PASS** (unrelated, pending, cancelled refused; victim's plan untouched);
   - `d24`: **every executed assertion passes and none is skipped.** (While 185 is pending it makes
     no assertions and records 25 named skips; once applied it executes the relationship-fixture
     read-backs, the 18 refusals by row count, the 6 active-coach positive controls and the
     authored-row check. Do not compare against a fixed total — read "0 failed, 0 skipped".)
   - `d25`: with **0** substrate rows → refusal `ENGINE_NO_SELECTION` and **0 days**, coach-edited
     week preserved, malformed prescription refused, a signed-in **non-owner** refused `42501`; the
     *complete prescription*, *second generation* and *genuine second coach* checks stay
     **SKIPPED** and say so (EB-4; QA has no second-coach fixture). Every executed assertion passes.
   - The runner's closing line lists the skipped total; for `d24` it must be **0**, for `d25` it is
     expected to be non-zero until EB-4 is populated and a second-coach fixture exists.
   A red `Live QA suites` job is the signal to roll back.

## 5 · Rollback (per migration, from the step-3 captures)

| # | Rollback | Limitation |
|---|---|---|
| 186 | re-create the captured engine definition | reinstates the broken engine (empty days / 23514) |
| 183 | nothing separate — 186's rollback restores the pre-183 body if that is what was captured | — |
| 185 | `ALTER POLICY` back to the old `USING`/`WITH CHECK`, `DROP` the four added SELECT policies (verified identical on replay) | reopens `QAX-SEC-03` |
| 184 | re-create the captured function (131 body) | **reopens the P0** |
| 182 | re-create the captured view and RPC (verified identical on replay) | `COMMENT` texts stay changed |

Then `supabase migration repair --status reverted <versions> --linked` **only after** the catalog
read-back confirms each rollback, and restore the manifest.

## 6 · Kept visible, deliberately

- **EB-4 — intelligence content.** QA has **0** `exercise_intelligence` rows. With 186 applied the
  engine correctly *refuses* rather than writing empty days, but it cannot *generate* until the
  substrate is populated through the Content Center pipeline (`beta-readiness.md` §0–§1: rebuild
  graph → AI-enrich intelligence → knowledge review), which needs the enrichment edge function
  deployed and its key set. Content-owner task; decision `D-1`.
- **Production is not part of this and its state is unverifiable.** Its ledger has never been
  reconciled (`REL-21`, release gate 9B.2); it has reportedly not received 113–122 and probably has
  no `exercise_intelligence` table. No production push until ENV-1 → ENV-2 → ENV-9 → ENV-3 close.
- **The feature flag `ENGINE_WEEK_GENERATION` stays off** in every build until steps 5–7 pass.
- **Coverage still missing after the batch:** `QAX-SEC-06`'s `exercises`-view half has no
  migration; 182 has no live check; ENV-3 compares versions, not bodies.

## 7 · After the batch — the coach-to-client walk-through (separately authorized)

With EB-4 populated and a **non-deployed** QA build run with
`--dart-define-from-file=dart_defines/qa.json --dart-define=ENGINE_WEEK_GENERATION=true`:
a QA coach plans, creates and generates week 1 → sees every day with sets×reps and no invented
load in Programs → assigns it to an active client → the client sees those days in the workout tab
and starts one. *(Activity's "today" only matches if today's name is one of the generated days.)*
`V5-PROD-012` (nothing advances `current_week`) stays a separate owner decision.

## 8 · Corrections carried from earlier versions

- Members' plans (`generate_client_plan`) never depended on the substrate; only the coach engine did.
- 183 is safe to apply (it only refuses empty selections and nothing reachable calls the engine);
  the earlier "hold 183 for the substrate" reasoning was wrong.
