# QA migration discrepancy report — migrations 182–186

**Date:** 2026-11-18 · **Environment:** QA `eyqtldjqpgpljlqvpowh` only (production was not contacted) ·
**Method:** read-only queries via `supabase db query --linked` / `supabase migration list --linked`; nothing
was applied, written or changed. Owner decisions are listed, not taken.

## 1. Bottom line

- QA's migration ledger and main's declared state **agree**. QA has 000–181 and 187–192. Main's
  `supabase/expected_applied.json` declares frontier **192**, with 182–186 **excluded** (each with a reason and a
  release gate) and 193–195 **pending**. There is **no ENV-3 discrepancy**, and `expected_applied.json` needs no
  correction.
- The real discrepancy is **security, not bookkeeping**. Because 184 and 185 are not applied, QAX-SEC-01 (P0) and
  QAX-SEC-03 (P1) are **live on QA today** (§4).
- Three records were wrong or stale:
  1. The cycle-5 ledger entry said main's manifest "still says applied_through 181". **That was false:** it was read
     from a stale local checkout. The entry is now corrected in place.
  2. The header comments of `184_…sql` and `185_…sql` still say "declared … pending … applied_through is 181". The
     manifest has since moved both to `excluded` under frontier 192. These are comment-only and stale.
  3. Live suites `d08-identity-constraints.mjs` (184) and `d24-coach-write-arms.mjs` (185) **skip** their strict halves
     while the manifest says not applied. That is correct behaviour, but it means neither hole is asserted closed
     anywhere live.

## 2. Authoritative applied history (QA `supabase_migrations.schema_migrations`, read 2026-11-18)

| Fact | Value |
|---|---|
| Ledger rows | **188** |
| Lowest / highest version | `000` / `192` |
| 000–181 | all 182 present, contiguous |
| Above 181 | **187, 188, 189, 190, 191, 192** (applied in the owner-approved window, Julia 2026-11-15, "187-192 only") |
| 182, 183, 184, 185, 186 | **absent** |
| 193, 194, 195 | absent (authored on main, declared `pending`) |
| Authored on `origin/main` | 196 files, `000`–`195` |

`supabase migration list --linked` shows the same picture: Local and Remote match through 181, then 182–186 local only.
(The 187–192 rows appear remote only because the CLI was run from the stale primary checkout.)

## 3. The five missing migrations

| # | File | What it does | Finding | Declared gate (manifest) |
|---|---|---|---|---|
| 182 | `182_scope_exercise_certifications.sql` | scopes the `exercise_certifications` definer view and `exercise_certification(uuid)` RPC to `exercise_readable(id) OR is_content_editor()` | QAX-SEC-06 (certification half) | owner approval of the Option A access trade-off, then a QA window |
| 183 | `183_restore_materialize_program_week_empty_selection_guard.sql` | restores 119's empty-selection guard, placed in the engine | PD-A01 | **never without 186 after it**; ordered batch 182→186 (route A, approved in principle 2026-10-25) |
| 184 | `184_assign_nutrition_plan_requires_active_relationship.sql` | `assign_nutrition_plan` refuses (42501) unless `is_active_coach_of(p_client_id)` | **QAX-SEC-01 (P0)**, OD-QAX-2 A | owner-approved QA window + pre-state check, then live suites and CI. Product consequence to accept: no plan before the client accepts |
| 185 | `185_coach_write_arms_require_active_relationship.sql` | the coach write arm of six tables' policies also requires `is_active_coach_of(client_id)`; four narrow SELECT policies keep authored rows readable | **QAX-SEC-03 (P1)** + policy half of F-21, OD-14 | owner-approved QA window, preceded by the header's read-only audit of rows that fail the new write test (reviewer = platform admin), then live suites and CI. **Apply after 184** |
| 186 | `186_restore_program_engine_prescription.sql` | replaces `materialize_program_week_engine` (canonical prescription, all-or-nothing, no silent overwrite, FOR UPDATE lock) | engine 23514 / zero-exercise days | the ordered batch; capture `pg_get_functiondef` of the engine first; flag `ENGINE_WEEK_GENERATION` stays OFF until verified |

**Dependencies, checked against the files:**

- 184 and 185 depend only on `public.is_active_coach_of(uuid)` (migration 100), which is live on QA.
- Neither depends on 182, 183 or 186.
- 187–192 (applied) do **not** touch any object 184/185 alter. 187 adds an index and slot triggers on `coaching_calls`,
  not policies.
- 195 (pending) adds a trigger on `coaching_calls`.
- So 184 and 185 still apply cleanly as authored on top of QA's current state.

## 4. The authorization gaps 184 and 185 close — live evidence

### 4.1 QAX-SEC-01 (P0) — closed by 184

**Live state:**
- `public.assign_nutrition_plan(uuid,int,int,int,int,int,text)`, SECURITY DEFINER, `search_path` pinned.
- EXECUTE is granted to `authenticated` and `service_role`.
- Definition md5 is `40bfd2a0d3fb17a0dbedd5dd918ef675`.
- The body checks only that `auth.uid()` is not null and `p_client_id` is not null. It contains **no** relationship
  check.

| | |
|---|---|
| Who | **any signed-in user**: client, coach, vendor or admin, related to the victim or not |
| What | for **any** `p_client_id`: an `UPDATE client_nutrition_plans SET is_active=false` that deactivates the victim's active plan, then an `INSERT` of a new active plan with `coach_id` = caller |
| Why RLS doesn't stop it | SECURITY DEFINER bypasses the table's RLS |
| Effect | the victim's real plan is replaced; the victim sees and follows a plan from someone who is not their coach |
| After 184 | one 42501 refusal unless the caller is the coach of an **active** relationship; pending, cancelled, ended and no-row all refused |

### 4.2 QAX-SEC-03 (P1) — closed by 185

Live policies (role `authenticated`) are all in the pre-185 form:

| Table | Policy (cmd) | Live predicate |
|---|---|---|
| `client_habits` | "coach client habits" (ALL) | `coach_id = auth.uid() OR client_id = auth.uid()` |
| `client_nutrition_plans` | "coach client nutrition" (ALL) | `coach_id = auth.uid() OR client_id = auth.uid()` |
| `workout_program_assignments` | "coaches manage assignments" (ALL) | `coach_id = auth.uid() OR client_id = auth.uid()` |
| `coaching_calls` | "Coach and client can see calls" (ALL) | `coach_id = auth.uid() OR client_id = auth.uid()` |
| `coaching_calls` | "calls_participant_access" (ALL) | `auth.uid() = coach_id OR auth.uid() = client_id` |
| `action_items` | "coach manages assigned action items" (ALL) | `coach_id = auth.uid()` |
| `coach_video_responses` | "Coach can insert video responses" (INSERT) | CHECK `coach_id = auth.uid()` |

| | |
|---|---|
| Who | any signed-in user |
| What | INSERT (and then UPDATE/DELETE) rows on these six tables naming **any** client, just by writing `coach_id` = themselves. `coach_id` is a column the caller supplies |
| Effect | habits, nutrition plans, programme assignments, calls, action items and video responses appear on a victim's account from someone who is not their coach. Notifications fire where triggers exist |
| After 185 | the coach arm also requires `is_active_coach_of(client_id)`; the client arm is unchanged; existing rows are preserved and stay readable by their author |

**Not closed by 185, as the file states:**
- `workout_programs` "coaches manage programs" (F-21 stays open).
- A client writing a row on their own arm that names an arbitrary `coach_id`.
- SECURITY DEFINER writers other than `assign_nutrition_plan`.

## 5. Proposed safe, reversible QA application sequence (for Julia's decision — nothing applied)

**Never use `supabase db push` for this.** It would also apply 182, 183, 186 and the pending 193–195, each of which has
its own gate. Apply exact files one at a time, the way the 187–192 window was run: each migration plus its
`schema_migrations` row in one transaction, stopping on the first error.

### Option S — security-first window: 184 → 185 only

Consistent with the manifest: neither gate requires the full batch, and 186's batch rule binds only 182/183/186.

1. **Target check.** The linked ref is QA, never `nxdbooufqzkpslkcogxc`.
2. **Pre-state, read-only, saved as evidence:**
   - ledger = 188 rows, max 192, none of 182–186;
   - `assign_nutrition_plan` md5 = `40bfd2a0…`, with its full `pg_get_functiondef` saved;
   - the §4.2 predicates snapshot;
   - the 185 header's per-table counts of rows failing the new write test, reviewed by the platform admin.
3. **Apply 184.** Read back: the body contains `is_active_coach_of`, the ACL is unchanged, and ledger row 184 exists.
4. **Apply 185.** Read back: six predicates altered, four "authoring coach reads own …" SELECT policies present, and
   ledger row 185 exists.
5. **Same change set:** remove 184/185 from `excluded` in `expected_applied.json`. They are ≤ frontier 192, so removing
   them declares them applied.
   - Correct the two stale header comments in the same change.
   - Until this lands on main, CI's ENV-3 check will report 184/185 as "applied but declared excluded" on every
     branch. Merging is the owner's call.
6. **Verify.** Run the live suites **alone** (one runner per QA project). `d08` and `d24` then run their strict
   halves, including the active-coach positive controls. Then run CI.

**Rollback** (complete, because neither migration mutates any row):
- **185:** in one transaction, `ALTER POLICY` each of the six back to the §4.2 predicate, `DROP POLICY` the four
  added SELECT policies, and delete ledger row 185.
- **184:** in one transaction, re-run the saved pre-state definition, restate REVOKE/GRANT, and delete ledger row 184.

Rows written between apply and rollback remain.

### Option R — manifest route A: 182 → 183 → 184 → 185 → 186 in one window

- Needs the additional owner approval of 182's Option A trade-off.
- 183 is applied only with 186 straight after it.
- Capture the `materialize_program_week_engine` definition first.
- `ENGINE_WEEK_GENERATION` stays OFF until 186 is read back and verified.
- Same per-file method, read-backs, manifest change, live suites and CI as Option S.

**Product consequences to accept at apply time** (both options): a coach cannot assign a plan, habits, a programme, a
call, an action item or a video response to a client whose relationship is not **active**. That includes invited
clients who have not yet accepted. No device or simulator walkthrough of that consequence has been done.

## 6. Decisions for Julia (not taken here)

1. Approve a QA window, and choose **Option S** (184/185 now; 182/183/186 later) or **Option R** (the full batch).
2. Accept the active-relationship product consequence above.
3. Option R only: approve 182's access trade-off.

## 7. What was deliberately not done

- No migration applied.
- No `schema_migrations` row written.
- No policy or function changed.
- `expected_applied.json` was not modified. It is already accurate, and it moves only with an actual apply.
- The 185 header audit queries were **not** run. The file restricts them to the approved window, with the platform
  admin as reviewer.
- Production was not contacted.
