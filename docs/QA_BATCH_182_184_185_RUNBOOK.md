# QA migration batch 182 → 195 — PROPOSAL, HELD

> **Status: HELD. Nothing in this document is authorized to run.** It is a proposal for the owner.
> The owner approved *route A* (182 → 186) **in principle** on 2026-10-25; that is not an
> authorization to apply anything, and **187–195 have no apply approval at all.** This document
> grants no approval and records no decision. Every approval and authorization it needs is listed
> in §4, separately from the technical prerequisites in §5.
>
> **Remote state, as last reported — not verified by this document.** CI's ENV-3 live ledger check in
> run `40445378227` (PR #14, commit `1eccbee`, 2026-10-27) reported QA's migration ledger as exactly
> **000–181 (182 rows)**: *L-2 applied but undeclared: 0*, *L-5 ledger rows 182 vs declared expected
> 182*. **Migrations 182–195 are therefore reported as unapplied on QA.** Writing this runbook did
> not contact QA or production and changed no remote state.
>
> **Who runs it:** the owner, or someone the owner authorizes. The Claude session that wrote it has
> no QA database credential and no linked CLI.
>
> The file keeps its original name for link stability. It now covers all fourteen migrations.
>
> **Status update 2026-10-28 — owner directions given in chat, NOT formally recorded:**
> - **SEQ-1 = Option 1** (2026-10-27): Stage 1 is applied before PR #14 merges.
> - **C-1**: 183 stays held while QA's exercise substrate is empty — the recorded 2026-10-25 condition is
>   not overridden. Threshold: `exercise_intelligence` count > 0, which is not an eligibility or approval
>   test. The owner accepts that the whole of Stage 1 stays held meanwhile, with no migration workaround.
> - **C-2**: the intended Stage 1 scope is 182–186.
>
> Because one `db push` cannot skip 183 (§2), **C-1 holds all of Stage 1 — 184 (P0) and 185 (P1) included
> — while the substrate is empty.** None of these directions takes effect until it is recorded through
> `MASTER_PRODUCT_DECISIONS.md` §2. Draft text: `GOVERNANCE_RECORDING_DRAFT_SEQ1_C1_C2.md`. Operator
> checklist: `QA_STAGE1_182_186_EXECUTION_PACKET.md`.

**Evidence labels used below**

| Label | Meaning |
|---|---|
| **[REPO]** | read from a tracked file at commit `1eccbee` |
| **[LOCAL]** | verified on a local loopback replay of the committed migrations (2026-10-26/27) — not QA |
| **[CI]** | reported by a GitHub Actions run against QA — named by run ID |
| **[PRIOR]** | an earlier authorized read-only QA observation — dated, possibly stale |
| **[UNVERIFIED]** | could not be verified without QA access or a remote command; re-confirm on the day |

---

## 1 · The fourteen migrations, in the only valid order

Two stages. **Stage 1** has route A's scope, as approved in principle. Under owner direction C-1 (not yet
recorded), 183 — and so the whole stage — is conditional on `exercise_intelligence` count > 0 (header). **Stage 2** is the PR #14 series. Stage 2
depends on Stage 1 (188 extends 186; 189 restates 124's wrapper over 186's engine).

| # | Purpose | Depends on | Stage | Apply-time data change |
|---|---|---|---|---|
| **182** | `QAX-SEC-06` (certification half): `exercise_certifications` view and `exercise_certification(uuid)` scoped to `exercise_readable(id) OR is_content_editor()` | 058/083 | 1 | none |
| **183** | restores 119's empty-selection guard in `materialize_program_week_engine` | 119, 124 | 1 | none (body replaced by 186) |
| **184** | `QAX-SEC-01` (**P0**), OD-QAX-2: `assign_nutrition_plan` requires an **active** coach–client relationship | 100/137, 131 | 1 | none |
| **185** | `QAX-SEC-03`, OD-14: six coach write policies require an active relationship; four authored-row SELECT policies added | 100 | 1 | none |
| **186** | restores the programme engine: canonical prescription, all-or-nothing, `ENGINE_WEEK_EXISTS`, `FOR UPDATE` lock | 119, 124, **183** | 1 | none |
| **187** | exercise-intelligence **approval contract**: approval only through a signed-in content editor's fingerprinted review of all eight attribute groups; `review_attribute` dropped and recreated with `p_reviewed_fingerprint` | 090/091 | 2 | **ONE-WAY: every profile now `approved` that lacks fingerprinted reviews becomes `under_review`** (§11) |
| **188** | engine certification gate + session focus: `build_workout` requires `module` (`ENGINE_UNKNOWN_MODULE`), selects only certified-for-module **and** approved exercises, Push/Pull/Legs focus, one compound per focused session | **182, 186, 187** | 2 | none |
| **189** | `workout_programs.engine_selected` (sticky), `_engine_client_clearance` + logged `engine_client_clearance` RPC, assignment-time clearance guard | 124, 140/141, 115/126, **188** | 2 | adds column `engine_selected boolean NOT NULL DEFAULT false` |
| **190** | removes the client write arm from `"coaches manage assignments"`; explicit `WITH CHECK`; clients get a SELECT-only policy | **185** | 2 | none |
| **191** | `deactivate_self_generated_plan` deletes assignments before programmes (fixes the pre-existing `23503`) | 047/121 | 2 | none |
| **192** | programme ownership + provenance triggers; `_program_author_or_admin` on materialize/regenerate/snapshot; `can_read_program` narrowed | **189, 190** | 2 | none |
| **193** | caller context: `_api_caller()`; third-party callers refused with `ASSIGNMENT_NOT_AUTHORIZED` | **189, 192** | 2 | none |
| **194** | two visibility leaks: `ENGINE_ASSIGNMENT_UNVERIFIABLE`; SECURITY INVOKER `_assignment_api_write_scope` | **189, 192, 193** | 2 | none |
| **195** | one active assignment per client (`single_active_assignment` trigger, advisory lock, REPEATABLE READ refused); `retire_my_assignment` | **190, 193, 194** | 2 | none at apply — rows change only on later activations (§11) |

Dependencies are taken from each migration's header **[REPO]**. Every migration was replayed in order on
a loopback cluster, with its positive suite and a negative control on the prefix before it **[LOCAL]**
(see PR #14's description). Nothing above is verified on QA.

**Transactions.** 184–195 each wrap their body in one `BEGIN … COMMIT` **[REPO]**. 182 and 183 have no
explicit transaction; how the CLI wraps a file without one is **[UNVERIFIED]**. A failure part-way
through a push leaves every *earlier* migration applied — the push is not one transaction across files
**[UNVERIFIED for this CLI version; treat as true]**.

---

## 2 · How the apply command behaves — what is and is not verified

- **No CI job or repository script applies migrations.** `ci.yml` and `supabase-keepalive.yml` are the
  only workflows; `ci.yml:617` and `supabase/scripts/live-evidence.sh:34` state they run no `db push` or
  `repair` **[REPO]**. Applying is a manual operator action.
- **`supabase db push` has no "apply up to version N" option.** CLI 2.107.0's help lists only
  `--include-all`, `--include-roles`, `--include-seed`, `--dry-run`, `--db-url`, `--linked`, `--local`,
  `--password`, plus the global `--workdir` **[REPO-adjacent: local CLI help, no remote call]**.
  `supabase migration up` has the same scoping (`--include-all`, `--db-url`, `--linked`, `--local`).
- **What a push applies is decided by the migration files in the project directory it runs from**,
  compared with the remote history table. It applies every local version newer than the remote's
  latest, in order **[PRIOR: recorded 2026-10-25; behaviour not re-observed against a remote here]**.
  Consequences:
  - run from a checkout of **`main` @ `760cefc`** (187 files, 000–186) → Stage 1 only **[REPO]**;
  - run from **this branch or any commit containing PR #14** (196 files, 000–195) → **all fourteen**,
    including 187's one-way demotion **[REPO]**.
- **`--include-all`** would also apply a *lower* unapplied version out of order. Never use it here: it
  is how 183 could land after 186 and reinstate the broken engine.
- **`--dry-run` is the control.** It must list exactly the stage's versions, in order, before the real
  push. Its output format is **[UNVERIFIED]** for this CLI version.
- **Never `supabase migration repair` to make the ledger agree** (owner ruling). A history row written
  ahead of the SQL makes a later push skip the migration. §11 mentions `repair` only as a post-rollback
  step that itself needs explicit authorization.

---

## 3 · Decision point SEQ-1 — Stage 1 before PR #14 merges, or after?

**Not decided here.** This is an owner decision. Both options use only manual applies (§2).

| | **Option A — Stage 1 before PR #14 merges** | **Option B — Stage 1 after PR #14 merges** |
|---|---|---|
| Where Stage 1 is pushed from | `main` @ `760cefc`, which holds exactly 000–186 **[REPO]** — a plain push cannot reach 187 | `main` would hold 000–195 **[REPO]**. Stage 1 alone needs a separate checkout at `760cefc` (or `--workdir` at a directory with only 000–186). **A plain push from `main` applies all fourteen.** |
| Accidental 187 demotion risk | low — 187 is not in the directory | **high** — one wrong directory applies 187 (irreversible, §11) and 188 (breaks old app builds, §6) |
| App on QA between merge and Stage 2 | unchanged: `main` builds stay paired with a ≤186 database | builds from `main` would contain PR #14's app code, which **needs 189**: Copilot fails closed for **every** client until Stage 2 lands (§6) |
| Manifest work | Stage 1 manifest PR moves the frontier to 186 on `main`. PR #14's `expected_applied.json` then **conflicts** (its 182–186 entries are removed on `main`) and must be updated: a protected edit, a push, and a CI run with standing QA fixture writes | PR #14 merges as is; one manifest PR per stage on `main` |
| Verification of PR #14 | PR #14's CI re-runs against a QA at frontier 186, with `d08`, `d24`, `d25` strict — extra evidence before merge | PR #14 is merged on evidence from a frontier-181 QA only |
| Fit with the in-principle approval | matches route A (182 → 186) exactly | route A becomes a sub-step of a larger tree |
| Cost | an extra update + CI cycle on PR #14 | a separate checkout discipline for every Stage 1 command |

**Option B2** — merge PR #14, then apply 182–195 in one window: fewest steps, largest blast radius;
Stage 1 is never verified on its own, and route A's approval does not cover 187–195.

**Engineering note, not a decision:** on the evidence above, Option A carries the least irreversible risk
because the directory a push runs from physically cannot contain 187. The owner may weigh the extra
PR #14 cycle differently.

---

## 4 · Owner approvals and execution authorizations (none granted by this document)

| # | Decision or authorization | Needed for |
|---|---|---|
| OA-1 | **SEQ-1** (§3): Option A, B or B2 | everything below |
| OA-2 | **182 Option A trade-off** — content managers keep cross-owner visibility of private/draft certifications (`expected_applied.json` 182 gate) | Stage 1 |
| OA-3 | **Stage 1 QA apply window** (182 → 186) — date, operator, and that no other CI run or push happens in it | Stage 1 |
| OA-4 | Acceptance of **184**'s product consequence — a coach can no longer assign a plan to a client who has not accepted | Stage 1 |
| OA-5 | **Stage 2 QA apply window** (187 → 195) — separate from OA-3 | Stage 2 |
| OA-6 | Acceptance of **187's one-way demotion** of the number counted in §7.2 (even if zero), knowing it is not reversible without a further decision (§11) | Stage 2 |
| OA-7 | Acceptance of the consequences recorded in `expected_applied.json` for 189 (clearance criteria as a walkthrough restriction — **not** clinical), 190 (no client assignment writes), 192 (non-authors lose generate/regenerate/snapshot; new coach loses read of a previous coach's programme), 195 (prior active assignments become `replaced` on the next activation) | Stage 2 |
| OA-8 | **Manifest declarations** — the protected edits only, to `supabase/expected_applied.json` via the temporary `scripts/protected-paths.json` exception, one per stage. **Creating, pushing and opening** each declaration PR (a QA-writing CI run) and **merging** it into `main` are separate authorizations (packet DP-1, DP-2). | after each stage |
| OA-9 | **Distribution of a paired app build** to QA testers (§6) | Stage 2 |
| OA-10 | Any **rollback**, and any `migration repair --status reverted` that follows one | §11 only |

**Every approval above, and SEQ-1, C-1 and C-2, must be recorded through `MASTER_PRODUCT_DECISIONS.md` §2
before the stage it gates is executed.** A direction in chat is intent, not authorization
(`V5_OWNER_AUTHORITY_DIRECTION_2026-10-21.md` §1). The acceptable evidence for a sign-off is defined in the
packet, §1.2.

Not decided by any of the above, and not claimed: **PD-A02**, the **D-1** wording conflict, **clinical
sign-off** (no clinical owner exists — `MASTER_PRODUCT_DECISIONS` §D), and enabling
**`ENGINE_WEEK_GENERATION`** anywhere.

---

## 5 · Technical prerequisites (necessary, not sufficient — §4 still applies)

| # | Prerequisite | Status |
|---|---|---|
| TP-1 | The operator has a QA DB credential and a CLI linked to `eyqtldjqpgpljlqvpowh`. The full tool and access list (git, authenticated `gh`, Supabase CLI 2.107.0 or re-checked flags, Node, `psql`, password and connection string never written down) is in packet §1.3. | **[UNVERIFIED]** |
| TP-2 | No CI run is in progress on **any** branch for the whole window (shared QA fixtures, `trunk-and-ci` rule) | check on the day |
| TP-3 | The checkout the push runs from contains exactly the stage's migrations (§2, §3) | check on the day |
| TP-4 | **The live AI suite must be updated before 188 is declared applied.** `supabase/tests/ai/j03-engine-boundary.mjs` calls `build_workout` **without `module`** and asserts `status < 300` at lines 21, 27, 32 and 39 **[REPO]**; a fifth module-less call, `generate_workout` at line 95, runs only with `AI_ALLOW_WRITES=1`, which `ci.yml` does not set **[REPO]**. After 188 those calls are refused with `ENGINE_UNKNOWN_MODULE`, so the `Live AI suite` step would turn red. `j04-provenance-authz.mjs:228` is a refusal test that should be unaffected, because the subject check precedes the engine **[REPO reading — not executed]**. **Addressed locally:** commit `b2b65e9` (`test(ai): include module in engine boundary calls`, not pushed) adds `module: 'workout_builder'` inside `p_context` at those four calls and at line 95; no assertion changed. The key is ignored by the pre-188 `build_workout` (127) and `score_exercise` (087), which read only named keys **[REPO]**. **Not yet validated against any database with 188 applied, and not yet run by CI.** | **addressed locally — unvalidated** |
| TP-5 | A paired app build exists (§6) | PR #14 head `1eccbee` contains it **[REPO]** |
| TP-6 | Captures storage: a private location **outside the repository** for dumps and query output (they contain QA data) | operator |

Suites checked and expected to be unaffected by Stage 2 **[REPO reading — not executed against QA]**:
`d04` and `d05` already send `module` (PR #14); `d05`'s and `d17`'s service-role assignment fixtures
name a programme owned by the same coach (192 passes them); `d17`'s two active assignments of one
programme belong to **different** clients (195 is per client).

---

## 6 · App ↔ database pairing (Stage 2)

Mobile code on `main` and on PR #14 calls the changed RPCs differently **[REPO, `git grep` at `760cefc` vs `1eccbee`]**:

| App build | DB ≤ 186 | DB with 187 | DB with 188 | DB with 189 |
|---|---|---|---|---|
| **`main` (`760cefc`)** — no `module`; `review_attribute` without fingerprint; no clearance read | works | an **Approve** is refused (`INTEL_REVIEW_FINGERPRINT_REQUIRED`); rejections still work | **Copilot and the MIE debugger are refused** (`ENGINE_UNKNOWN_MODULE`) | Copilot already refused (188) |
| **PR #14 (`1eccbee`)** — `module: 'workout_builder'`; fingerprint sent when returned; reads `engine_client_clearance` | `module` ignored; Approve hidden (no fingerprint returned); **Copilot refuses every client** (clearance RPC missing → fail-closed) | Approve works with fingerprint | works | works |

So Stage 2 and the `1eccbee`-or-later build go together. Program Builder's "Generate week 1" does not send
`module` — 188's engine sets `program_generator` itself — and it stays behind the flag.

**Verifying a compatible build without enabling the flag**

1. The build's source commit contains `1eccbee`: `git merge-base --is-ancestor 1eccbee <build-commit>`.
2. At that commit, `coach_copilot_screen.dart` and `mie_debugger_screen.dart` contain `'module': 'workout_builder'`,
   and `custom_exercise_service.dart` contains `p_reviewed_fingerprint`.
3. The build command passes `--dart-define-from-file=dart_defines/qa.json` and **no**
   `--dart-define=ENGINE_WEEK_GENERATION=…`. The flag is `bool.fromEnvironment(…, defaultValue: false)`
   (`engine_generation.dart:27`) **[REPO]**.
4. On the device, Program Builder shows **no** "Generate week 1" control: it renders only when the flag is
   on (`dynamic_program_builder_screen.dart:197`) **[REPO]**.
5. After Stage 2: Copilot shows the clearance refusal for an uncleared QA client. The review screen shows
   each attribute's value, and Approve appears only where a fingerprint is returned.

---

## 7 · Preflight — read-only checks and captures

Read-only SQL, run in the window against the linked QA database. Store the output per TP-6. **Any result
outside the "expected" column is a stop condition** until the owner re-approves on the new number.

### 7.1 Both stages

- Target: `supabase/scripts/qa-db-reset.sh --check-only` (verifies the link and stops), or
  `supabase/.temp/project-ref` = `eyqtldjqpgpljlqvpowh`. **Never `db reset`.**
- Ledger: `supabase migration list --linked` — expected: applied through **181** before Stage 1;
  through **186** before Stage 2.
- Schema dump: `supabase db dump --linked --schema public -f qa_before_<stage>.sql`.
- Function and policy capture, without guessing signatures:

```sql
select p.oid::regprocedure as fn, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = any (array[
   -- Stage 1
   'exercise_certification','assign_nutrition_plan','materialize_program_week_engine',
   -- Stage 2 (also captures 186's engine again, as the 188 baseline)
   'build_workout','materialize_program_week','generate_workout','review_attribute',
   'review_intelligence','finalize_intelligence','attribute_review_state_engine',
   'intelligence_review_queue_engine','can_read_program','regenerate_program',
   'snapshot_program_version','deactivate_self_generated_plan','can_act_on_program']);
select pg_get_viewdef('public.exercise_certifications'::regclass, true);
select * from pg_policies where schemaname = 'public' and tablename in (
  'client_habits','action_items','coaching_calls','coach_video_responses',
  'client_nutrition_plans','workout_program_assignments');
select tgrelid::regclass, tgname from pg_trigger where not tgisinternal
   and tgrelid in ('public.workout_program_assignments'::regclass, 'public.workout_programs'::regclass,
                   'public.program_workouts'::regclass, 'public.exercise_intelligence'::regclass);
```

### 7.2 Before 187 — approval state that 187 will change

```sql
select status, count(*) from public.exercise_intelligence group by status order by 1;
select count(*) from public.intelligence_attribute_reviews;
-- the exact rows 187 will demote (keep this list with the captures — §11 depends on it):
select exercise_id from public.exercise_intelligence where status = 'approved' order by 1;
```

**Expected effect:** every row currently `approved` becomes `under_review`. A pre-187 review carries no
fingerprint, so none meets the contract; the local upgrade check `U02` proves a pre-187 *human-reviewed*
approval is withdrawn too **[LOCAL]**. 187 prints `NOTICE 187: N approved intelligence profile(s) … are
now under_review`; **N must equal the `approved` count above.**
Last observation: **0** `exercise_intelligence` rows (621 exercises) **[PRIOR, 2026-10-25]** — so the
expected N is 0, but recount.

### 7.3 Before 185 — rows that fail the new write test

From 185's header, one query per table. Expected **0** in every table. Last observation: **0 of 17**
**[PRIOR, 2026-10-25]**.

```sql
select 'client_habits' t, count(*) from public.client_habits x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'action_items', count(*) from public.action_items x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'coaching_calls', count(*) from public.coaching_calls x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'coach_video_responses', count(*) from public.coach_video_responses x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'client_nutrition_plans', count(*) from public.client_nutrition_plans x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active')
union all select 'workout_program_assignments', count(*) from public.workout_program_assignments x where x.coach_id is not null and not exists (select 1 from public.coach_client_relationships r where r.coach_id = x.coach_id and r.client_id = x.client_id and r.status = 'active');
```

*All six tables carry `coach_id` and `client_id` — `001` (habits, nutrition plans, assignments), `002`
(coaching calls, video responses), `017` (action items) **[REPO]**.*

### 7.4 Before 192 — legacy cross-coach assignments (optional audit)

```sql
select count(*) from public.workout_program_assignments a
  join public.workout_programs p on p.id = a.program_id
 where a.status = 'active' and a.coach_id is distinct from p.coach_id;
```

192 deletes or rewrites none of these rows. They lose read and authoring rights, and can block engine
marking (192 header, "RESIDUAL").

### 7.5 Before 195 — clients with more than one active assignment

```sql
select client_id, count(*) from public.workout_program_assignments
 where status = 'active' group by 1 having count(*) > 1;
```

Expected **0 rows**. Last observation: 2 assignment rows (1 active, 1 superseded), **0 duplicates**
**[PRIOR, 2026-10-26]**. 195 does not resolve existing duplicates at apply; the next activation for that
client does (§11). Any duplicate found needs the owner's per-case acceptance (OA-7).

---

## 8 · Stage 1 — 182 → 186

Nothing else may push, merge or rerun CI on **any** branch from step 1 to step 7.

1. **Target and ledger** (§7.1): applied through **181**; 182–186 local-only. Anything else → stop.
2. **Preflight** §7.1 captures and §7.3.
   **Substrate gate (C-1) — HARD STOP:** `select count(*) from public.exercise_intelligence` must be
   **> 0** (the current threshold, per owner direction 2026-10-28 — it does **not** establish that any
   exercise is eligible or approved). If it is 0, 183 may not be applied, and one push cannot skip it, so **the whole batch stops
   here** and the owner is asked for direction. No workaround.
   **No pause between migrations:** the push below applies 182–186 in one command, so every condition is
   settled before step 4 or the batch does not run (packet §6.0).
3. **Dry run** from the checkout chosen under SEQ-1: `supabase db push --linked --dry-run` must list
   exactly **182, 183, 184, 185, 186**, in that order. Anything else → stop.
4. **Push**: `supabase db push --linked`. Any error → stop; do not retry blindly (§1, partial apply).
5. **Read back the catalog, not just the ledger:**
   - `assign_nutrition_plan` body contains `is_active_coach_of(p_client_id)`;
   - `materialize_program_week_engine` body contains `ENGINE_NO_SELECTION` and `FOR UPDATE`;
   - the **seven** altered policies across **six** tables (`coaching_calls` has two) have
     `qual`/`with_check` containing `is_active_coach_of`, and the four
     `authoring coach reads own …` SELECT policies exist;
   - `exercise_certifications` view definition contains `exercise_readable`;
   - the engine and wrapper still pin `search_path`; `authenticated` cannot execute the engine.
6. **Declare it**: the protected edit (OA-8) moving `applied_through` to `"186"` and removing the 182–186
   pending entries; its PR is created and pushed under DP-1 and merged under DP-2 — three separate
   authorizations. Until it merges, CI's ENV-3 is red (*applied but undeclared*) — which is why nothing else runs.
7. **Verify live, alone** — that PR's CI run (§10, frontier 186). A red `Live QA suites` job → stop;
   rollback is a separate decision (OA-10).

## 9 · Stage 2 — 187 → 195

Same window rules. Precondition: Stage 1 declared and verified live; TP-4 done; paired build ready (§6).

1. **Target and ledger**: applied through **186**; 187–195 local-only.
2. **Preflight** §7.1 captures, §7.2, §7.4, §7.5. Re-confirm OA-6 against the §7.2 number.
3. **Dry run** must list exactly **187 … 195**, in order.
4. **Push.** Watch for 187's `NOTICE`; N must equal §7.2's `approved` count. A mismatch is a stop
   condition, but 187 has already committed by then (§11).
5. **Read back, per migration:**

| # | Read-back |
|---|---|
| 187 | triggers `intel_enforce_approval`, `intel_review_stamp`, `intel_review_invalidate` exist; `review_attribute` has 6 arguments ending `p_reviewed_fingerprint`; `select count(*) … where status = 'approved'` = **0** |
| 188 | `build_workout` body contains `ENGINE_UNKNOWN_MODULE`; `_engine_pattern_key`, `_engine_focus_patterns`, `_engine_in_focus` exist; the engine body contains `ENGINE_INSUFFICIENT_ELIGIBLE` and `program_generator` |
| 189 | `workout_programs.engine_selected` is `boolean not null default false`; triggers `engine_selected_sticky` and `engine_assignment_guard` exist; `engine_client_clearance` is executable by `authenticated`, `_engine_client_clearance` is not |
| 190 | `"clients read own program assignments"` is `SELECT`; `"coaches manage assignments"` has a `with_check` and no `client_id = auth.uid()` arm |
| 191 | `deactivate_self_generated_plan` deletes from `workout_program_assignments` **before** `workout_programs` |
| 192 | triggers `program_workouts_provenance` and `assignment_program_ownership` exist; `materialize_program_week` body calls `_program_author_or_admin` |
| 193 | `_api_caller` exists; both guard bodies contain `ASSIGNMENT_NOT_AUTHORIZED` |
| 194 | trigger `assignment_api_write_scope` exists and its function has `prosecdef = false` (INVOKER); `_engine_marking_block` exists |
| 195 | trigger `single_active_assignment` exists; `retire_my_assignment` is executable by `authenticated` only; the §7.5 duplicate query returns what it returned before |
| all | every new or replaced function pins `search_path` (`proconfig`); `anon` has no EXECUTE on any of them |

6. **Declare it** (OA-8): a PR moving `applied_through` to `"195"` and emptying `pending`.
7. **Verify live, alone** — that PR's CI run (§10, frontier 195). Then the paired build check (§6, step 5).

---

## 10 · Live suites — skipped today, and what becomes an assertion

Today (run `40445378227` **[CI]**): **1,163/1,163** asserted, **38 SKIPPED** — skipped checks are not
passes. Gating is `supabase/tests/security/migration-state.mjs`, driven by the **manifest** — so checks
turn strict when the manifest PR merges, not when SQL is applied.

| Gate | Suite (file) | Skipped today | After the frontier passes it |
|---|---|---|---|
| 184 | `3A-11` (`d08-identity-constraints.mjs:270`) | 5 — unrelated / pending / cancelled coach refused (42501); victim's plan untouched ×2 | all 5 **asserted** |
| 185 | `D24` (`d24-coach-write-arms.mjs:47`) | 25 — 18 refusals, 6 active-coach positive controls, authored-row check | all **asserted**; expected **0 skipped** in D24 |
| 186 | `D25` (`d25-program-engine.mjs:45`) | 7 engine checks | depends on the substrate (`d25:120–147`). **Populated** (the only case Stage 1 runs in, under C-1): all six engine checks **asserted**; skipped (not passes): the empty-substrate refusal check and the 188 check. **Empty** (reference): **4 asserted** — refusal with no day written, coach-edited week, malformed prescription, non-owner 42501; **4 skipped** — canonical prescription and second generation (EB-4), the 188 check, the second coach. |
| 188 | `D25` (`d25-program-engine.mjs:100,181`) | *(inside the 186 gate today)* | substrate measured by per-focus `build_workout`; `ENGINE_UNKNOWN_MODULE` **asserted** |
| — | `D25` | 1 — "a genuine SECOND COACH" | **stays skipped**: QA has no second-coach fixture. Not a pass. |

Also expected at frontier 195:
- **No live suite covers 187, 189, 190, 191, 192, 193, 194 or 195.** Their only evidence is the local
  replays and negative controls **[LOCAL]**. A green run at frontier 195 does **not** verify them.
- **`Live AI suite` (`j03`) turns red at 188** unless TP-4 is done first.
- With the substrate empty (§7.2), D25's generation checks assert the refusal path
  (`ENGINE_NO_SELECTION` / `ENGINE_INSUFFICIENT_ELIGIBLE`), not a successful week. In that case the
  canonical-prescription and second-generation checks are **skipped, not passed**.

---

## 11 · Rollback and recovery — limits stated, nothing promised

**No rollback of any migration in this batch has been rehearsed**, locally or on QA. The Stage 1 rows
were checked for body-identity on a replay; nothing for 187–195 was.

| # | Recovery path (from §7 captures) | Limitation |
|---|---|---|
| 182 | re-create the captured view and RPC | `COMMENT` texts stay changed |
| 183 | none separately; 186's capture covers the engine | — |
| 184 | re-create the captured 131 body | **reopens the P0** |
| 185 | `ALTER POLICY` back; drop the four SELECT policies | reopens `QAX-SEC-03` |
| 186 | re-create the captured engine | reinstates the broken engine (empty days / 23514) |
| **187** | drop the three triggers; re-create the captured functions, including the old 5-argument `review_attribute` | **The demotion is not reversible by rollback.** Restoring a status needs the §7.2 list **and** an owner decision to re-approve without fingerprinted review — which is what 187 exists to prevent. Reviews recorded after 187 carry fingerprints that the old functions ignore. |
| 188 | re-create the captured `build_workout` and engine; drop the three helpers | old app builds work again; PR #14 builds keep sending `module` (ignored) |
| 189 | drop both triggers, then the functions; dropping the column loses every `engine_selected` mark | the sticky trigger refuses `true → false` for **every** writer, owner included, so it must go first. Removing the mark removes the clearance guard. |
| 190 | `ALTER POLICY` back; drop the client SELECT policy | **reopens the client self-assignment defect** |
| 191 | re-create the captured body | reinstates the `23503` failure |
| 192–194 | drop the triggers/functions they added; re-create captured `materialize_program_week`, `regenerate_program`, `snapshot_program_version`, `can_read_program` | reopens the ownership and leak findings; must be reversed **in reverse order** (194, 193, 192) |
| **195** | drop the trigger and three functions | assignments already marked `replaced` **stay replaced** — data changes are not undone |

After any rollback, a `supabase migration repair --status reverted <versions> --linked` is required only
once the catalog read-back confirms the rollback, and only under OA-10. The manifest must then be restored
(OA-8).

---

## 12 · Kept visible, deliberately

- **Content (EB-4) blocks the walkthrough, and must follow 187.** The seeded library has **0** exercises
  eligible for Program Builder: none has alternatives, a `program_generator` certification, and eight
  fingerprinted attribute approvals **[LOCAL count on the seed; QA last seen with 0 intelligence rows,
  PRIOR 2026-10-25]**. Reviews recorded **before** 187 do not count after it, so content review belongs
  after Stage 2. Content-owner task.
  **Compatible with C-1, stated so it is not misread:** C-1's threshold needs `exercise_intelligence` rows to
  **exist** before Stage 1 (any status, e.g. AI-enriched drafts). **Reviewing and approving** them still
  belongs after 187, or the approvals are demoted.
- **Governance and clinical sign-off are unresolved.** PD-A02 is not recorded and D-1 is not resolved;
  the 189 clearance rule is a walkthrough scope restriction, not a clinical assessment.
- **Production is out of scope.** Its state is unverifiable (`REL-21`, gate 9B.2). No production push until
  ENV-1 → ENV-2 → ENV-9 → ENV-3 close.
- **`ENGINE_WEEK_GENERATION` stays off** in every build until both stages are applied, declared and
  verified live — and then only in a non-deployed QA build, under its own authorization.
- **Coverage still missing after the batch:** `QAX-SEC-06`'s `exercises`-view half has no migration; 182
  has no live check; ENV-3 compares versions, not bodies; 187 and 189–195 have no live suite (§10).
- **Known local-test documentation mismatch:** `supabase/tests/local/engine_gate_replay.sh`'s header says
  it needs 187 + 188. Checks D14, E01 and E02 need **189+** (3/73 fail on a 000–188 replay; 73/73 from
  000–190) **[LOCAL]**.

## 13 · After both stages — the coach-to-client walkthrough (separately authorized)

Needs: both stages applied, declared and verified; EB-4 content approved through 187's review path; a QA
client **cleared** by 189's rule (completed intake, explicit no-injury status, complete low-risk PAR-Q,
no medical advice); and a **non-deployed** QA build from a `1eccbee`-or-later commit run with
`--dart-define-from-file=dart_defines/qa.json --dart-define=ENGINE_WEEK_GENERATION=true`. Flow: a QA coach
plans, creates and generates week 1 → sees each day's sets × reps with no invented load → assigns it to
the cleared client → the client sees those days and starts one. *(Activity's "today" matches only if
today's name is one of the generated days.)* `V5-PROD-012` (nothing advances `current_week`) stays a
separate owner decision.

## 14 · Unresolved questions and claims not verifiable locally

1. SEQ-1 (§3) — owner decision.
2. Whether the CLI wraps 182/183 (no explicit transaction) in one, and whether a multi-file push is one
   transaction — **[UNVERIFIED]**; this runbook assumes it is not.
3. The exact `--dry-run` output format for CLI 2.107.0 against a remote — **[UNVERIFIED]**.
4. That a push applies only versions newer than the remote's latest (§2) — **[PRIOR]**, not re-observed.
5. Current QA counts for §7.2–§7.5 — all **[PRIOR]** or unknown; recount on the day.
6. j03/j04 behaviour after 188 is predicted from the source, not executed (TP-4).
7. That no app path other than those in §6 calls the changed RPCs — checked by `git grep` of
   `apps/mobile/lib` only; edge functions were not re-audited for 187–195.

## 15 · Corrections carried from earlier versions

- Members' plans (`generate_client_plan`) never depended on the substrate; only the coach engine did.
- 183 is safe to apply (it only refuses empty selections and nothing reachable calls the engine); the
  earlier "hold 183 for the substrate" reasoning was wrong.
  **Conflict preserved, 2026-10-28:** that technical view is unchanged, but owner direction **C-1**
  reaffirms the recorded condition — 183 is held while the substrate is empty. Governance decides
  execution, so C-1 governs once recorded. Neither text is deleted.
- This version extends the 182 → 186 proposal to 195, splits it into two stages, and replaces the single
  "push everything pending" step with a stage-scoped push whose scope depends on SEQ-1.
