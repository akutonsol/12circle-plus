# QA Stage 1 execution packet — migrations 182 → 186 — HELD

> **HELD. This packet does not authorize execution.** It turns
> [`QA_BATCH_182_184_185_RUNBOOK.md`](QA_BATCH_182_184_185_RUNBOOK.md) §7.1, §7.3 and §8 into an operator
> checklist. It may be executed only after every sign-off in §1 is complete.
>
> **Preparation.** Written on `feat/engine-gate-approval-contract` at `a99231c`, 2026-10-27. **No QA or
> production access occurred and no migration was applied while preparing it.** Every command was checked
> against the local Supabase CLI 2.107.0 help text or the repository's own scripts. Nothing was run against
> a remote database.
>
> **Remote state, as last reported (not verified here):** CI's ENV-3 check in run `40445378227`
> (2026-10-27) reported QA's ledger as **000–181**; 182–195 are unapplied.

**Labels:** **[VERIFIED]** checked against the repository or local CLI help · **[UNVERIFIED]** not
checkable without the remote; the operator must confirm it in the window and **stop** if it differs.

---

## 1 · Decision record and sign-offs

### 1.1 Sequencing — recorded

| Item | Value |
|---|---|
| **SEQ-1 (runbook OA-1)** | **Option 1 — Stage 1 (182–186) is applied before PR #14 merges.** Owner direction given in chat, 2026-10-27. |
| Recording status | Recorded in this packet only. It is **not** yet recorded in `MASTER_PRODUCT_DECISIONS.md` or the decision log; that is a separate governance step. |
| Consequence | Stage 1 runs from a checkout of `main` that contains **only** migrations 000–186 (§3). PR #14 (`feat/engine-gate-approval-contract`) is **not** merged before Stage 1 is applied, declared and verified live. |

### 1.2 Required sign-offs — NONE GRANTED

The SEQ-1 decision above does **not** imply any of these. Execution may not start until all four are signed.

| ID | Approval | Granted by | Date | Signature / reference |
|---|---|---|---|---|
| **OA-2** | 182 Option A trade-off: content managers keep cross-owner visibility of private/draft certifications | ______ | ______ | ______ |
| **OA-3** | Stage 1 QA apply window (182 → 186): date, time window, named operator, and agreement that no other push, merge or CI run occurs during it | ______ | ______ | ______ |
| **OA-4** | 184's product consequence: a coach can no longer assign a nutrition plan to a client who has not accepted (no active relationship) | ______ | ______ | ______ |
| **OA-8** | The Stage 1 manifest declaration: a protected edit to `supabase/expected_applied.json` moving `applied_through` to `"186"` and removing the 182–186 `pending` entries, via the temporary `scripts/protected-paths.json` exception (reverted immediately) | ______ | ______ | ______ |

Not covered, and not to be assumed: Stage 2 (OA-5, OA-6, OA-7, OA-9), any rollback (OA-10), merging PR
#14, PD-A02, D-1, clinical sign-off, and `ENGINE_WEEK_GENERATION` — it stays **off**.

| Window details (fill in) | |
|---|---|
| Operator | ______ |
| Window start / end (UTC) | ______ / ______ |
| Evidence storage location (outside the repository; it will contain QA data) | ______ |

---

## 2 · Hard rules for the whole window

1. **Never** run `supabase db reset`, `supabase migration repair`, or `supabase db push --include-all`.
2. **Never** run any apply command from `feat/engine-gate-approval-contract` or any checkout containing PR
   #14 — it contains 187–195, and 187's approval demotion is irreversible (runbook §11).
3. **No other push, merge, `workflow_dispatch` or CI rerun on any branch** from §4.1 to the end of §7.
   CI's live jobs write fixtures to the same QA project.
4. Do not pass `--yes` to `db push`. The operator reads the CLI's own listing before confirming
   **[UNVERIFIED: whether `db push` prompts]**.
5. Read-only queries run only from the files in §5. They are SELECTs.
6. Any **STOP** below ends the window. Do not improvise, retry blindly, or continue to a later step.
   Report the evidence captured so far.

---

## 3 · The operator's `main` checkout — verify before anything that could apply a migration

Use a **dedicated** worktree, never the PR #14 branch.

```bash
git fetch origin
git worktree add ../12circle-plus-stage1 origin/main      # new directory, detached at origin/main
cd ../12circle-plus-stage1
```

| # | Check | Command | Expected | Record |
|---|---|---|---|---|
| C-1 | Commit | `git rev-parse HEAD` | the current `origin/main`; it was `760cefc47d6913291d2fca37f54db6e2315f2a96` on 2026-10-27 **[VERIFIED then]**. If it differs, every following check still decides. | ______ |
| C-2 | Clean tree | `git status --porcelain` | empty | ______ |
| C-3 | PR #14 not merged | `gh pr view 14 --repo akutonsol/12circle-plus --json state,mergedAt` | `"state":"OPEN"`, `"mergedAt":null` | ______ |
| C-4 | Migration count | `ls supabase/migrations/*.sql \| wc -l` | **187** (000–186) **[VERIFIED at `760cefc`]** | ______ |
| C-5 | Highest migration | `ls supabase/migrations/*.sql \| tail -1` | `supabase/migrations/186_restore_program_engine_prescription.sql` | ______ |
| C-6 | Nothing above 186 | `ls supabase/migrations \| grep -cE '^(18[7-9]\|19[0-9]\|[2-9][0-9][0-9])_'` | **0** | ______ |
| C-7 | Migration hygiene | `.github/scripts/check-migration-hygiene.sh` | exit 0; contiguous 000–186 | ______ |
| C-8 | Manifest state | `node -e 'const m=require("./supabase/expected_applied.json").environments.qa;console.log(m.applied_through, Object.keys(m.pending).join(","), m.excluded.length)'` | `181 182,183,184,185,186 0` **[VERIFIED at `760cefc`]** | ______ |
| C-9 | Manifest contract | `node supabase/scripts/check-migration-manifest.mjs` | exit 0 | ______ |

**STOP** on any mismatch. In particular, **STOP if C-4, C-5 or C-6 shows any file above 186**: the
checkout would apply Stage 2.

**Link the worktree to QA.** `supabase/.temp/` is git-ignored **[VERIFIED: `.gitignore:29`]**, so a new
worktree has no link:

```bash
supabase link --project-ref eyqtldjqpgpljlqvpowh          # [UNVERIFIED: may prompt for the DB password]
supabase/scripts/qa-db-reset.sh --check-only               # verifies the link, then exits — resets nothing
```

| # | Check | Expected | Record |
|---|---|---|---|
| C-10 | `--check-only` output | `--check-only: link verified, nothing was reset.` and exit 0. The script compares `supabase/.temp/project-ref`, the `.temp` link file and `config.toml`'s `project_id` against `eyqtldjqpgpljlqvpowh`, and exits at line 64 before any reset **[VERIFIED in the script]**. | ______ |
| C-11 | No CI run in flight on **any** branch | `gh run list --repo akutonsol/12circle-plus --limit 30 --json status,headBranch,databaseId -q '.[]\|select(.status!="completed")'` prints nothing | ______ |

**STOP** if C-10 refuses or C-11 shows anything in progress.

---

## 4 · Preflight — ledger, captures and audit (all read-only)

### 4.1 Ledger

```bash
supabase migration list --linked
```

| Expected | Record (paste verbatim) |
|---|---|
| Remote applied through **181**. 182, 183, 184, 185 and 186 appear **local only**. No remote version is absent locally. **[UNVERIFIED: exact output format for CLI 2.107.0]** | ______ |

**STOP** if any of 182–186 is already on the remote, or the remote has a version this checkout lacks.

### 4.2 Schema dump

```bash
supabase db dump --linked --schema public -f <evidence-dir>/qa_before_stage1.sql
```

| Expected | Record |
|---|---|
| file written, non-empty | path ______ · size ______ · `shasum -a 256` ______ |

### 4.3 Function, view, policy and privilege captures

Save as `<evidence-dir>/s1_capture.sql` and run per §5:

```sql
select p.oid::regprocedure as fn, p.prosecdef, p.proconfig, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('exercise_certification','assign_nutrition_plan',
                     'materialize_program_week_engine','materialize_program_week')
 order by 1;

select pg_get_viewdef('public.exercise_certifications'::regclass, true) as exercise_certifications_view;

select tablename, policyname, cmd, roles, qual, with_check
  from pg_policies
 where schemaname = 'public'
   and tablename in ('client_habits','action_items','coaching_calls','coach_video_responses',
                     'client_nutrition_plans','workout_program_assignments')
 order by tablename, policyname;

select r.rolname,
       has_function_privilege(r.rolname, 'public.materialize_program_week_engine(uuid,integer,jsonb)', 'EXECUTE') as engine,
       has_function_privilege(r.rolname, 'public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)', 'EXECUTE') as assign_plan,
       has_function_privilege(r.rolname, 'public.exercise_certification(uuid)', 'EXECUTE') as cert_rpc
  from pg_roles r where r.rolname in ('anon','authenticated','service_role') order by 1;
```

The signatures are taken from migrations 182, 184 and 186 **[VERIFIED]**. If a signature is missing on QA,
the cast fails: **STOP** — the catalog is not what the runbook assumes.

| Capture | Expected | Record |
|---|---|---|
| functions | 4 rows (one per name, unless overloaded) | rows ______ · file ______ |
| view | one definition | ______ |
| policies | includes the 7 policies 185 alters (§6) | rows ______ |
| privileges | 3 rows | ______ |

### 4.4 185 audit — rows that fail the new write test

Save as `<evidence-dir>/s1_audit_185.sql`. All six tables carry `coach_id` and `client_id` **[VERIFIED:
migrations 001, 002, 017]**.

```sql
select 'client_habits' t, count(*) from public.client_habits x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'action_items', count(*) from public.action_items x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'coaching_calls', count(*) from public.coaching_calls x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'coach_video_responses', count(*) from public.coach_video_responses x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'client_nutrition_plans', count(*) from public.client_nutrition_plans x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'workout_program_assignments', count(*) from public.workout_program_assignments x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active');
```

| Table | Expected | Record |
|---|---|---|
| client_habits | 0 | ______ |
| action_items | 0 | ______ |
| coaching_calls | 0 | ______ |
| coach_video_responses | 0 | ______ |
| client_nutrition_plans | 0 | ______ |
| workout_program_assignments | 0 | ______ |

Last observation: **0 of 17** rows **[2026-10-25, read-only, possibly stale]**. **STOP** if any count is
non-zero: those coaches would lose write access to existing rows. The owner must decide before 185 is
applied.

### 4.5 Informational — intelligence substrate (sets the D25 expectation in §7)

```sql
select count(*) as exercise_intelligence_rows from public.exercise_intelligence;
select count(*) as exercises from public.exercises;
```

| Expected | Record |
|---|---|
| last seen **0** rows / **621** exercises **[2026-10-25]** — not a stop condition | ______ / ______ |

---

## 5 · How to run the read-only SQL files

**Preferred — read-only enforced by the server.** Use a QA connection string held by the operator, not
committed and not echoed:

```bash
PGOPTIONS='-c default_transaction_read_only=on' psql "$QA_DB_URL" -X -v ON_ERROR_STOP=1 \
  -f <evidence-dir>/<file>.sql -o <evidence-dir>/<file>.out
```

`default_transaction_read_only=on` makes any write fail **[standard PostgreSQL behaviour]**. Whether the
QA pooler honours `PGOPTIONS` is **[UNVERIFIED]**. Confirm first with
`psql … -c 'show default_transaction_read_only'`, which must print `on`.

**Alternative — CLI.** `supabase db query --linked -f <file>.sql -o csv` exists in CLI 2.107.0 and runs
"via Management API" **[VERIFIED: help text]**. Whether it enforces read-only is **[UNVERIFIED]**; it is
read-only here only because the files contain SELECTs.

---

## 6 · Execution

### 6.1 Dry run — from the verified `main` worktree

```bash
supabase db push --linked --dry-run
```

| Expected | Record (paste verbatim) |
|---|---|
| lists exactly **182, 183, 184, 185, 186**, in that order, and nothing else **[UNVERIFIED: output format]** | ______ |

**STOP** if the list contains anything else, is in a different order, or cannot be read with certainty.

### 6.2 Apply — only after OA-2, OA-3, OA-4 and OA-8 are signed (§1.2)

```bash
supabase db push --linked
```

| Field | Record |
|---|---|
| start / end (UTC) | ______ / ______ |
| exit code | ______ |
| full output (verbatim, to the evidence store) | ______ |

**STOP on any error.** 184, 185 and 186 each run as one transaction; 182 and 183 have no explicit one
**[VERIFIED in the files]**. Whether the CLI wraps them, or the whole push, in a transaction is
**[UNVERIFIED]**: **assume a failure leaves earlier migrations applied.** Run §4.1's ledger command again,
record exactly which versions are now remote, and stop. Recovery is a separate decision (§8).

### 6.3 Catalog read-backs (the catalog decides, not the ledger)

Save as `<evidence-dir>/s1_readback.sql` and run per §5:

```sql
-- R-1 184: active relationship required
select pg_get_functiondef('public.assign_nutrition_plan(uuid,integer,integer,integer,integer,integer,text)'::regprocedure)
       ~ 'is_active_coach_of\(p_client_id\)' as r1_assign_requires_active;

-- R-2 186: engine is the restored body
select d ~ 'ENGINE_NO_SELECTION' as r2a_no_selection, d ~* 'for update' as r2b_for_update
  from (select pg_get_functiondef('public.materialize_program_week_engine(uuid,integer,jsonb)'::regprocedure) d) s;

-- R-3 185: the seven altered policies now require an active relationship
select tablename, policyname,
       coalesce(qual,'') ~ 'is_active_coach_of' or coalesce(with_check,'') ~ 'is_active_coach_of' as r3_active_required
  from pg_policies where schemaname = 'public' and policyname in (
   'coach client habits','coach manages assigned action items','calls_participant_access',
   'Coach and client can see calls','Coach can insert video responses','coach client nutrition',
   'coaches manage assignments') order by 1, 2;

-- R-4 185: the four authoring-coach SELECT policies exist
select policyname, cmd from pg_policies where schemaname = 'public' and policyname in (
  'authoring coach reads own client habits','authoring coach reads own coaching calls',
  'authoring coach reads own client nutrition plans','authoring coach reads own program assignments')
 order by 1;

-- R-5 182: the view is scoped
select pg_get_viewdef('public.exercise_certifications'::regclass, true) ~ 'exercise_readable' as r5_view_scoped;

-- R-6 posture: search_path pinned; authenticated cannot execute the engine
select p.oid::regprocedure, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('materialize_program_week_engine','materialize_program_week',
                                              'assign_nutrition_plan','exercise_certification');
select has_function_privilege('authenticated','public.materialize_program_week_engine(uuid,integer,jsonb)','EXECUTE')
       as r6_authenticated_can_execute_engine;
```

| # | Expected | Record |
|---|---|---|
| R-1 | `true` | ______ |
| R-2 | `true`, `true` | ______ |
| R-3 | 7 rows, all `true` | ______ |
| R-4 | 4 rows, all `SELECT` | ______ |
| R-5 | `true` | ______ |
| R-6 | every row's `proconfig` contains `search_path=`; the privilege check is `false` | ______ |
| Ledger (§4.1 command again) | remote applied through **186** | ______ |

The policy names in R-3 and R-4 are taken from migration 185 **[VERIFIED]**. **STOP** on any mismatch:
rollback is a separate decision (§8).

---

## 7 · Declare and verify live — two separate steps

### 7.1 Manifest declaration (OA-8)

Until the declaration merges, CI's ENV-3 check reports *applied but undeclared* and fails, which is
expected. That is why rule 3 holds until the end of this section.

- A change on `main` (not on PR #14) sets `applied_through` to `"186"` and removes the `pending` entries
  182–186. It is a protected edit: add the temporary `scripts/protected-paths.json` exception, make the
  edit, revert the exception, and confirm `scripts/protected-paths.json` has no net diff.
- `node supabase/scripts/check-migration-manifest.mjs` and
  `node scripts/check-migration-wave-coverage.mjs --check` pass locally.

| Field | Record |
|---|---|
| declaration PR / commit | ______ |
| protected-paths.json net diff | none ______ |

### 7.2 Live verification — that PR's CI run, alone

| Suite | Expected at frontier 186 | Record |
|---|---|---|
| ENV-3 (Live SQL evidence) | L-1…L-5 pass; ledger rows **187** vs declared expected **187** | ______ |
| `3A-11` (`d08`) | the 5 OD-QAX-2 checks **asserted and passing**; **0** skipped from the 184 gate | ______ |
| `D24` (`d24`) | **0 failed, 0 skipped**; all of its assertions executed | ______ |
| `D25` (`d25`) | the 6 engine checks **asserted**. With an empty substrate (§4.5) the generation check passes on the refusal path (`ENGINE_NO_SELECTION`, 0 days). **Still skipped, correctly:** the 188 `ENGINE_UNKNOWN_MODULE` check (gated on 188) and "a genuine SECOND COACH" (no fixture). | ______ |
| Run totals | 0 failed; skipped total recorded, not counted as passed | ______ |
| `Live AI suite` | passes (pre-188: `module` keys are irrelevant here) | ______ |

A red `Live QA suites` job: **STOP.** Do not re-run to get green; a rerun is itself a QA-writing CI run
and needs the single-run rule.

---

## 8 · If something fails — recovery is NOT authorized by this packet

Per runbook §11, from the §4.3 captures. **Not rehearsed for Stage 1 or any other stage.** Any rollback
needs **OA-10**.

| # | Path | Limitation |
|---|---|---|
| 182 | re-create the captured view and RPC | `COMMENT` texts stay changed |
| 183 | covered by 186's captured engine | — |
| 184 | re-create the captured body | **reopens the P0** |
| 185 | `ALTER POLICY` back; drop the four SELECT policies | reopens `QAX-SEC-03` |
| 186 | re-create the captured engine | reinstates empty days / 23514 |

`supabase migration repair --status reverted …` follows a rollback **only** after the catalog read-back
confirms it, and only under OA-10. The manifest is then restored (OA-8).

---

## 9 · After Stage 1 — next steps, each separately authorized

1. **Update PR #14.** Its `expected_applied.json` still lists 182–186 as pending; after §7.1 merges, that
   conflicts with `main` **[inferred from adjacent edits; not test-merged]**. Updating it is a protected
   edit, plus a push and a CI run with standing QA writes.
2. PR #14's CI re-runs at frontier 186 (D24, D25 and d08 strict). This is extra evidence before any merge.
3. **Stage 2 (187–195)** follows runbook §9, with its own approvals (OA-5, OA-6, OA-7, OA-9). Merge PR
   #14 at or just before the Stage 2 window, so builds from `main` are not mismatched with QA (runbook §6).

---

## 10 · Unverified items the operator must confirm in the window

1. Output format of `migration list --linked` and `db push --dry-run` (§4.1, §6.1).
2. Whether `db push` prompts before applying (§2 rule 4).
3. Whether `supabase link` prompts for the database password in a new worktree (§3).
4. Transaction wrapping of 182/183 and of a multi-file push (§6.2) — assume none.
5. Whether `PGOPTIONS` read-only is honoured by the QA connection, and whether `db query --linked`
   enforces read-only (§5).
6. That `db push` applies only versions newer than the remote's latest **[earlier observation,
   2026-10-25]** — the dry run (§6.1) is the control.
7. Every count in §4.4 and §4.5 — the previous values are dated and may be stale.
