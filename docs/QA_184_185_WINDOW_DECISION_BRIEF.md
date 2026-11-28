# Owner decision brief: a QA window for migrations 184 and 185

**For:** Julia · **Prepared:** 2026-11-19 · **Status:** decision requested. **Nothing has been applied, and nothing will be
without your explicit go.**
Evidence base: `docs/QA_MIGRATION_DISCREPANCY_REPORT.md` (read-only QA queries, 2026-11-18).

## 1. Why this matters

Two authorization holes are **live on QA today**, because 184 and 185 were authored but never applied. QA holds 000–181 and
187–192.

| Hole | Severity | What any signed-in user can do on QA now | Closed by |
|---|---|---|---|
| QAX-SEC-01 | **P0** | Call `assign_nutrition_plan` for **any** client: it switches off their active plan and installs one naming the caller as coach. SECURITY DEFINER, so RLS doesn't apply | 184 |
| QAX-SEC-03 | **P1** | Insert, then update or delete, rows naming **any** client on six tables, just by writing `coach_id` = themselves: `client_habits`, `client_nutrition_plans`, `workout_program_assignments`, `coaching_calls` (two policies), `action_items` and `coach_video_responses` | 185 |

Neither hole is in production's scope here; production was not examined. QA is where beta testers and walkthroughs would run.

## 2. The decision

1. **Approve a QA window: yes or no.**
2. If yes, **which sequence:**

| | **Option S: security first (184 → 185 only)** | **Option R: the manifest's batch (182 → 183 → 184 → 185 → 186)** |
|---|---|---|
| Closes | QAX-SEC-01 and QAX-SEC-03 | the same, plus QAX-SEC-06 (certification scoping, 182) and the programme-engine repairs (183 and 186) |
| Extra approvals needed | none beyond this window | **182's access trade-off (Option A):** content managers keep cross-owner visibility of private and draft certifications |
| Dependencies | 184 and 185 depend only on `is_active_coach_of` (migration 100, live) | 183 must **never** be applied without 186 straight after it; capture the engine definition first |
| Size and risk | small: one function body, six policy predicates, four added read policies | larger: also replaces the programme engine. The `ENGINE_WEEK_GENERATION` flag must stay OFF until 186 is read back and verified |
| Later work | 182, 183 and 186 still need their own window | none of 182–186 left |

**My recommendation:** Option S. It closes the two security holes with the smallest change, and doesn't wait on the separate
182 decision. This is a recommendation only; the choice is yours.

## 3. Product consequences you accept by approving (either option)

- **The rule:** a coach can no longer assign a nutrition plan, habits, a programme, a call, an action item or a video response to a
  client whose relationship is **not active**. That includes invited clients who haven't accepted yet.
- **Effect on today's app (read only, not executed):** every coaching-write screen takes its client from the coach's
  **active** roster (`coachClientsProvider`, `status = 'active'`): the client page's programme, nutrition and habits;
  the copilot's programme assignment; video responses. So no current screen should start failing. A coach whose
  relationship ends while a screen is open would be refused, which is correct.
- **Existing data:** existing rows are **kept, not changed**. A coach can still **read** rows they authored but can no longer
  change them without an active relationship.
- **What stays open:**
  - **F-21:** `workout_programs` "coaches manage programs" is not changed.
  - **Client-side `coach_id` attribution:** a client can still write their own row naming an arbitrary `coach_id`.

## 4. Risks and how each is handled

| Risk | Handling |
|---|---|
| Applying more than intended | **Never `supabase db push`**: it would also apply 182, 183, 186 and the pending 193–195. Apply the exact files one at a time, each with its `schema_migrations` row in the same transaction. That is the method the owner-approved 187–192 window used on 2026-11-15 |
| Wrong project | A first step that stops unless the linked ref is QA `eyqtldjqpgpljlqvpowh` and is never `nxdbooufqzkpslkcogxc` |
| Existing rows that fail the new write test | 185's header has read-only audit queries (one count per table). Run them **inside** the window, reviewed by the platform admin, before applying 185. Nothing is deleted or rewritten either way |
| **CI turns red on every open branch** | `expected_applied.json` declares 184 and 185 *excluded*. Once they're applied, CI's ENV-3 live check (`supabase/scripts/env3-live-check.mjs`) fails **L-2 "applied but undeclared"** and **L-5 "ledger rows vs declared expected"** on **every** branch whose manifest still excludes them. That is all open PRs (#160–#191) and main. The manifest change must therefore land on `main` straight after the window, and open PRs need `main` merged in. **That merge is yours**; I won't do it. Plan the window when you can merge that one change promptly |
| Live suites collide | Run the live security suites **alone** (one runner per QA project), or a fixture clash reads like a PHI hole |
| Production drift | QA ahead of production is the existing state; production reconciliation is RELEASE_GATES 9B.2 and out of scope here |

## 5. Validation steps (both options)

1. **Pre-state, read-only, saved as evidence:**
   - QA ledger: 188 rows, max 192, none of 182–186;
   - `assign_nutrition_plan` md5 `40bfd2a0d3fb17a0dbedd5dd918ef675`, with its full definition saved;
   - the seven current policy predicates (listed in the discrepancy report §4.2);
   - the 185 audit counts (platform-admin review).
2. **Apply 184.** Read back: the body contains `is_active_coach_of`, the grants are unchanged, and ledger row 184 exists.
3. **Apply 185.** Read back: six predicates changed, four "authoring coach reads own …" policies present, and ledger row 185 exists.
4. **Same change set:** remove 184 and 185 from `excluded` in `expected_applied.json`, and correct the two stale header
   comments ("applied_through 181").
5. **Live suites, run alone:**
   - `d08-identity-constraints` (184) and `d24-coach-write-arms` (185) switch from *skip* to *strict*;
   - they include an active-coach positive control per table;
   - every other suite must stay green.
6. **CI 7/7** on the change that updates the manifest, then on `main` after your merge.
7. **Optional, recommended:** a short walkthrough on a device or simulator. A coach assigns a plan and habits to an active client; a pending client's assignment is refused with the app's error. This would be the first live-integration evidence for J6.

## 6. Rollback plan (complete, because neither migration changes any row)

- **185, one transaction:**
  - `ALTER POLICY` each of the six back to the saved predicate;
  - `DROP POLICY` the four added SELECT policies;
  - delete ledger row 185.
- **184, one transaction:**
  - re-run the saved `assign_nutrition_plan` definition;
  - restate its REVOKE/GRANT;
  - delete ledger row 184.
- **Then:** revert the manifest change. Rows written between apply and rollback remain.
- **Rollback triggers:**
  - a positive control fails, meaning a legitimate active coach is refused;
  - an audit count shows rows you don't want frozen;
  - an app flow breaks in the walkthrough.

## 7. What I need from you

- **Approve or decline** a QA window.
- **If approving, choose:**
  - **S** or **R**;
  - for **R** only, also approve 182's Option A trade-off;
  - **when you can merge** the manifest change to `main` right after the window.

Until then this stays read-only: no apply, no `schema_migrations` write, no policy or function change, and no
`expected_applied.json` edit.
