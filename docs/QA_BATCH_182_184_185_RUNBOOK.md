# QA apply runbook — migrations 182, 184, 185 (183 deliberately held back)

> **For the owner to run.** This session has no QA database credential and no linked CLI, so it
> cannot apply migrations; it can only read through the QA service key already in the shell. Everything
> here changes the **shared QA project** (`eyqtldjqpgpljlqvpowh`). **Nothing in this runbook has been run.**
> Written 2026-10-25 after the read-only pre-checks in §1.

## 0 · What changes, in one table

| Migration | Closes | What it does | Rollback |
|---|---|---|---|
| **182** | `QAX-SEC-06` (cert half) | Scopes `exercise_certifications` and `exercise_certification(uuid)` to `exercise_readable(id) OR is_content_editor()` | restore the captured pre-change definitions (§4) |
| **184** | `QAX-SEC-01` (**P0**) | `assign_nutrition_plan` refuses unless the caller is the coach of an **active** relationship | re-run the `CREATE OR REPLACE` from migration `131` |
| **185** | `QAX-SEC-03` | Six coach write policies also require an active relationship; four narrow `SELECT` policies keep authored rows readable | `ALTER POLICY` back to the old `USING`; `DROP POLICY` the four new ones (§4) |
| **183** | — | **NOT in this batch.** See §2. | n/a |

## 1 · Pre-check results (read-only, QA, 2026-10-25)

| Check | Result | Meaning |
|---|---|---|
| Rows 185 would stop a coach editing (`coach_id` set, no **active** relationship) across the six tables | **0** of 17 (`client_habits` 10, `coaching_calls` 3, `client_nutrition_plans` 2, `workout_program_assignments` 2, `action_items` 0, `coach_video_responses` 0) | 185 changes no existing coach's ability to edit. The quarantine arm of `OD-14` is **moot on QA**. |
| QA relationships | 288 rows: 287 `active`, 1 `cancelled`, 0 `pending` | The live suites' coaches have active relationships; nothing depends on a pending one. |
| `exercise_intelligence` rows | **0** (621 exercises) | **This is why 183 is held back — §2.** |
| Ledger frontier | **not read** (the ledger is not exposed over the REST API). CI's `ENV-3 · declared vs observed vs authored` has been green at frontier `181`, and is the evidence. | Re-confirm with `supabase migration list --linked` before applying (§3 step 2). |

## 2 · Why 183 is held back — and what that means for the batch

`build_workout` selects candidates by an **inner join** of `exercises` and `exercise_intelligence`
(`087`/`127`). With **0** profiles the candidate pool is empty **today**, so every programme
materialization on QA already writes **empty training days and reports them as created**. Migration 183
turns that into an error. That is the correct behaviour — and it would make programme generation fail
visibly on QA (and the live workout checks go red) until the substrate is populated, which is registry
item `EB-4`, a Wave 5 prerequisite owned by the content owner with decision `D-1`.

So 183 waits for `EB-4`, and the batch is **182, 184, 185** — which is supported by the repo's own
model: `expected_applied.json` has an `excluded` bucket for *"authored versions at or below the
frontier that are deliberately not applied here"*, each with a reason and the gate that releases it.

> **Separate product finding, for the owner:** until `EB-4` is resolved, the workout engine selects
> nothing on QA, and (if production matches) for real members too. The empty days it writes are
> exactly what 183 would stop. This is not caused or fixed by this batch.

## 3 · Steps

Do not push, merge or rerun CI on **any** branch between step 1 and step 8 — QA is shared and an
overlapping run collides with the apply.

1. **Verify the target.** `supabase/scripts/qa-db-reset.sh --check-only` (it only verifies the link and
   stops), or confirm `supabase/.temp/project-ref` reads `eyqtldjqpgpljlqvpowh`. Never run
   `supabase db reset` or `supabase db push` here.
2. **Confirm the ledger.** `supabase migration list --linked` → applied through **181**, and 182–185
   shown as local-only. If it shows anything else, stop.
3. **Capture the before state** (this is what makes §4 possible):
   `supabase db dump --linked --schema public -f qa_before_182_184_185.sql`
   (read-only), and keep the file.
4. **Apply the three files, each as one transaction, in order**, with the QA connection string:
   `psql "$QA_DB_URL" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/182_scope_exercise_certifications.sql`
   then `…/184_assign_nutrition_plan_requires_active_relationship.sql`, then
   `…/185_coach_write_arms_require_active_relationship.sql`. (182 has no `BEGIN`/`COMMIT` of its own,
   hence `-1`; 184 and 185 carry their own.) **Do not use `db push`** — it would also apply 183.
5. **Record them in the ledger:** `supabase migration repair --status applied 182 184 185 --linked`.
   This is a ledger write only — the same operation the repo used for 113–122 (registry §7).
   **Leave 183 unrecorded.**
6. **Update the manifest and merge it immediately** — a PR touching `supabase/expected_applied.json`
   (a protected file, so Claude edits it under the sanctioned `exceptions` mechanism on request):
   `applied_through: "185"`; `pending: {}`; and add
   `excluded: {"183": {reason: "empty-selection guard; QA has 0 exercise_intelligence profiles, so applying it would make every programme generation fail", gate: "EB-4 — the intelligence substrate is populated"}}`.
   The live `ENV-3` check compares the manifest with the real ledger, so **until this merges a CI run
   is red** (applied but undeclared) — which is why nothing else runs in the meantime.
7. **That same manifest change makes the `d08` OD-QAX-2 refusal checks strict**: they are gated on the
   manifest no longer listing `184` as pending (`d08-identity-constraints.mjs`).
8. **Verify, alone:** let CI run the live suites on the manifest PR. Expect `d08` to pass with the
   refusals now asserted (unrelated, pending and cancelled coaches refused `42501`, victim's plan
   untouched), `d01`/`d17`/`d05` unchanged, and no other run in flight. A red `Live QA suites` job is
   the signal to roll back (§4).

## 4 · Rollback

- **184:** `CREATE OR REPLACE FUNCTION public.assign_nutrition_plan(…)` with the body from
  `supabase/migrations/131_identity_constraints.sql` §5 (the version with no relationship check), then
  its `REVOKE`/`GRANT`/`COMMENT` lines.
- **185:** for each of `client_habits "coach client habits"`, `coaching_calls "Coach and client can see
  calls"` and `"calls_participant_access"`, `client_nutrition_plans "coach client nutrition"` and
  `workout_program_assignments "coaches manage assignments"`: `ALTER POLICY … USING (coach_id =
  auth.uid() OR client_id = auth.uid())`; `action_items "coach manages assigned action items"`:
  `USING (coach_id = auth.uid())`; `coach_video_responses "Coach can insert video responses"`:
  `WITH CHECK (coach_id = auth.uid())`. Then `DROP POLICY` the four added `SELECT` policies
  (`authoring coach reads own client habits / coaching calls / client nutrition plans / program
  assignments`).
- **182:** the original `exercise_certifications` view and `exercise_certification(uuid)` definitions
  are in `qa_before_182_184_185.sql` (step 3).
- After any rollback: `supabase migration repair --status reverted <versions> --linked`, and restore
  the manifest.

## 5 · After the batch

`QAX-SEC-01` (P0), `QAX-SEC-03` and `QAX-SEC-06` move from *LOCAL-REPLAY VERIFIED* to *FIXED ON QA*,
and to *VERIFIED LIVE* once step 8 is green; *VERIFIED IN CI* is the green run itself. They stay open
until the evidence is recorded in the registry. **Production is not touched**, and its migration
ledger is still unreconciled (`REL-21`).
