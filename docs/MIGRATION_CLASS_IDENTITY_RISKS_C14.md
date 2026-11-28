# Migration-class identity risks (P0-FL-62e, Cycle 14)

This is a read-only investigation of a detached checkout at `a446926` (integration/p0-flutter-stack-c13). I only read files and ran `git show/log/grep`. I did not edit, author or apply anything, ran no supabase/psql/network command, and touched no database. Every SQL block below is labelled **sketch — not a migration, not applied**. Repo paths are relative to the repository root. The Cycle-13 inventory and ledger are not on this tree; I read them read-only from branch `docs/beta-completion-ledger` @ `ee7d032`:
- `docs/IDENTITY_INVENTORY_CYCLE13.md`
- `docs/BETA_COMPLETION_LEDGER.md`

**Corrections to the brief, found while reading:**
1. **Migration 124 did not add a `WITH CHECK` to the `messages` UPDATE policy.** `124_wave_2a_security_regressions.sql:11` lists "messages UPDATE policy — requires a separate contract decision" as *out of scope*. No migration after 003 alters any `messages` policy.
2. **`workout_logs` has no `session_id` column.** Neither the baseline nor any later migration defines one.
3. **PD8 is recorded both ways in the repo.** It is cited as an owner decision in commit `20adcc4` / PR #45. The ledger still lists it as an open "Decision required". See C14-MIG-04.
4. **The slot half of "atomic availability cancel" is already server-side.** Migration 187 does it, and 187 is declared applied on QA. See C14-MIG-06.

**Migration environment facts used throughout:**
- **QA frontier** (`supabase/expected_applied.json:36`): `applied_through = "192"`. Versions 182–186 are `excluded` (not applied). 193–195 are `pending`.
- **Production:** not declared in that file; its history belongs to RELEASE_GATES 9B.2 (`expected_applied.json`, `_` notes).
- **`docs/QA_MIGRATION_DISCREPANCY_REPORT.md` does not exist** at `a446926`.
- **Taken numbers:** the highest authored file is `195_coach_bookings_need_coach_guided_access.sql`. Numbers 196, 197 and 198 are already used on open branches: `4b304bb`/`61c5c35` (196), `029e613` (197, PR #161), `779fe1b` (198, PR #167). None of them touches the objects below. New work would start at 199 or above, subject to the owner's numbering.

---

## C14-MIG-01 — `messages` INSERT has no participant check (QAX-SEC-04; inventory A-05 / W3)

**Current authoritative state.** Every `messages` policy comes from `003_fk_and_rls_fixes.sql`; no later migration changes one.
- **INSERT** `"authenticated can send messages"` (003:91-94): `WITH CHECK (sender_id = auth.uid())`. There is no membership test.
- **UPDATE** `"recipients can mark messages read"` (003:96-104): `USING (conversation_id IN (…participant_1 = auth.uid() OR participant_2 = auth.uid()))`. There is no `WITH CHECK`, so Postgres reuses `USING`, and there is no column restriction.
  - This is I-NOT-04 / H-19, rated P1 (`docs/MASTER_REMEDIATION_REGISTRY.md:1354`).
  - 124 deliberately left it alone (124:11), and 130 still calls it "a P1 still open" (`130_private_storage_buckets.sql:72-75`).
- **SELECT** (003:81-89): participants only.
- **Trigger** `trg_notify_on_message` (`004_notifications_and_triggers.sql:69-105`): SECURITY DEFINER, AFTER INSERT. It notifies "the other participant" as `CASE WHEN participant_1 = NEW.sender_id THEN participant_2 ELSE participant_1 END`, so a non-participant sender notifies `participant_1`.
- **Companion: participants can rewrite the conversation itself.** `conversations` UPDATE `"participants can update conversations"` (003:73-76) is also `USING`-only with no column restriction. `docs/decisions/DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md:433-444` (§6.3) records that a participant can **replace the other participant**, and the new user then reads the whole history and its media. Any participant-based message check is only as strong as this.
- **Conversation creation** is the RPC `get_or_create_conversation(other_user)` (`131_identity_constraints.sql:303-345`). It sets participant_1 to `auth.uid()` and accepts any other user, with no relationship requirement.
- **Table grants:** `authenticated` keeps its default table privileges. 118:262 revokes only from `anon`.

**Flutter call sites.**
- `apps/mobile/lib/features/messaging/data/messaging_service.dart`:
  - `sendMessage` at :198, with the insert at :218.
  - The `conversations` preview update at :236-240.
  - `markAsRead` at :283-296, which updates `is_read` where `sender_id != me`.
- `apps/mobile/lib/features/dashboard/domain/coach_triage_provider.dart:142` reads `messages`.

**Client-side mitigation (Cycle 13, P0-FL-59c).**
- `messaging_service.dart:16-19` (`_stillSignedIn`) and the check at :229 before the preview write.
- `chat_screen.dart:83-86`: `_owner` is fixed when the chat opens. The comment there states the gap: "the server accepts a message from any signed-in account into any conversation".
- `chat_screen.dart:102` (`_holds(epoch)`), plus re-checks before `sendMessage` at :335 and :465-468.

What this does not cover:
- Any direct PostgREST call with a valid JWT.
- The small gap between the synchronous check and the token the request carries.
- In the A-05/W3 switch case, the server could not tell the difference even with a participant check when account B is itself the other participant (for example the client's coach on the same device). That case needs an expected-uid assertion (C14-MIG-05).

**Exploit / failure scenario.**
- **INSERT.** An authenticated user X who knows the UUID of conversation A↔B inserts `{conversation_id, sender_id: X, content}`. A and B both see the message, and `participant_1` gets the push "New message from X".
  - This was reproduced in local replay: `docs/QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:440-452`, probe `supabase/tests/qa_exhaustion/probes.sql:68-70`, positive control POS-04 at :309.
  - QAX rates it P2 because no read path exposes the UUID to a non-participant.
- **UPDATE.** Participant A changes `content` or `sender_id` of B's messages, which is forged authorship. A can also move a message to another of A's conversations.
- **Conversations UPDATE.** A sets `participant_2 = C`, and C can then read all of the A↔B messages and media.

**Severity.**
- INSERT: security/authorization, P2.
- UPDATE: data integrity and audit, P1.
- Conversation re-point: privacy, with possible health content in coach–client chat. It has no rating; DEC-3A-10 asks for its own triage.

**Server change that would close it.**
- **INSERT:** require the sender to be a participant of `conversation_id`.
- **UPDATE:** add a BEFORE UPDATE authorship trigger modelled on `enforce_checkin_authorship` (114):
  - a non-sender may change only `is_read`;
  - `sender_id` and `conversation_id` can never change;
  - whether a sender may edit their own `content` is PD-B18.
- **`conversations`:** make `participant_1` and `participant_2` immutable for `authenticated`. `last_message` and `last_message_at` stay writable because the app needs them (DEC-3A-10 §6.3).

```sql
-- sketch — not a migration, not applied
ALTER POLICY "authenticated can send messages" ON public.messages
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = conversation_id
                   AND (SELECT auth.uid()) IN (c.participant_1, c.participant_2)));

CREATE OR REPLACE FUNCTION public.enforce_message_authorship() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RETURN NEW; END IF;          -- service path
  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id THEN
    RAISE EXCEPTION 'messages: sender and conversation are immutable' USING ERRCODE = '42501';
  END IF;
  IF (SELECT auth.uid()) IS DISTINCT FROM OLD.sender_id
     AND (to_jsonb(NEW) - 'is_read') IS DISTINCT FROM (to_jsonb(OLD) - 'is_read') THEN
    RAISE EXCEPTION 'messages: only is_read may change on another person''s message' USING ERRCODE = '42501';
  END IF;
  -- sender's own content edit: refused or allowed per PD-B18 (owner decision)
  RETURN NEW;
END $$;
-- + BEFORE UPDATE trigger on public.messages
-- + an equivalent BEFORE UPDATE trigger on public.conversations refusing any change
--   to participant_1/participant_2 by an authenticated caller.
```

**Dependencies.**
- INSERT half: no owner decision is needed ("OWNER DECISION REQUIRED: NO", `QA_AUTONOMOUS_EXHAUSTION_FINAL_REPORT.md:452`). No pending or excluded migration touches `messages` or `conversations`, so ordering is free. Verify by local replay with the QAX-SEC-04 probe plus POS-04.
- UPDATE content-edit half: PD-B18 (`docs/MASTER_PRODUCT_DECISIONS.md:203`), which says the security half "is not a decision".
- Conversations half: needs its own triage.

**Category.**
- INSERT and the security part of UPDATE: **C** (needs explicit authorization to author and apply).
- Sender-edit window: **A**.
- Conversation re-point: **B**.

---

## C14-MIG-02 — Set-log session ownership (A-01 / W4) and `workout_logs` duplicate filing

**Current authoritative state.**
- **Table:** `public.workout_set_logs` (`001_full_ecosystem.sql:158-169`). `session_id` references `workout_sessions(id) ON DELETE CASCADE`, and `user_id` is an independent column. **Nothing ties a set row's `user_id` to its session's `user_id`.**
- **Write policy** `"users manage own set logs"` (001:370): `FOR ALL USING (user_id = auth.uid())`. With no explicit `WITH CHECK`, that `USING` is reused, so `user_id = auth.uid()` is the only write condition. No later migration alters it.
- **Read policy** (100:81-84): owner or `is_active_coach_of(user_id)`.
- **Uniqueness:** `uq_workout_set_logs_set_identity` on `(session_id, set_id) WHERE set_id IS NOT NULL` (`106_workout_set_identity.sql:32-34`). 120 dropped the 051 ordinal index (`120_workout_set_identity_authority.sql:68`).
- **Triggers (120):**
  - `require_identity` (120:84-101) checks only that `set_id` is non-empty.
  - `protect_history` (120:117-146) blocks un-completing a set and moving it between sessions or instances.
  - PR detection (`190_pr_detection_confirmed_sets_only.sql:28-…`) notifies `NEW.user_id` and that user's coach.
  - None of these checks the session's owner.
- **Sessions:** `workout_sessions` `"users manage own sessions"` (001:368) is owner-only. Reads are owner or active coach (100:76-79).
- **`workout_logs`:** baseline columns only (`000_baseline_preexisting_tables.sql:100-110`): there is no `session_id` and no unique key besides the PK (000:233). The policy is `FOR ALL USING (user_id = auth.uid())` (003:191-194).
  - 118:126-133 says retiring the legacy `workouts`/`workout_logs` pair is "a data-model decision, not a security one".

**Flutter call sites.**
- `apps/mobile/lib/features/workout/data/workout_service.dart`:
  - `saveSetLog` / `_writeSetLog` at :156-219 does update-then-insert on `(session_id, set_id)` and inserts `user_id: uid`.
  - On a 23505 it re-tries the update and throws `'the row for this set was not updated'` (:214-217). That is exactly what happens when someone else's row holds the key.
  - `logWorkout` inserts into `workout_logs` (:63-78).
- `active_workout_screen.dart:164-166` and :793-795: `_logFiled` is an **in-memory** flag that stops a retried completion from filing twice.

**Client-side mitigation (P0-FL-59b).**
- `requireWorkoutOwner` (`workout_session_store.dart:150-158`) is called before every set write (`workout_service.dart:189`, :201) and before `logWorkout` (:66).
- The owner is fixed before any await (`workout_service.dart:118-121`).

What this does not cover:
- A direct API call with any JWT.
- `_logFiled` does not survive an app kill or restart, so a re-filed completion inserts a second `workout_logs` row.

**Exploit / failure scenario.**
- **Account switch (A-01/W4).** B's token writes A's set into A's session as `user_id = B`. The server accepts it. A's later save of that `set_id` then fails: 23505, then a 0-row update, then StateError "Could not save set". A cannot see B's row because reads are filtered by `user_id`.
- **Deliberate.** Anyone who can read A's session (A's active coach, since 100:76-79 lets the coach read the session id and snapshot) can pre-occupy A's predictable `set_id`s (`<instance>:s<n>`, 120 backfill comment). That blocks A's logging for the session and attaches foreign rows to it, which are cascade-deleted with it.
- **`workout_logs`.** One workout can be filed twice, which inflates the weekly count, streak and total (`workout_service.dart:388-425`).
- **Evidence level:** these scenarios come from reading the code. I found no replay probe for set-log ownership in `supabase/tests/qa_exhaustion/probes.sql`.

**Severity.** Data integrity and user impact (a lost set, a blocked session), around P2. Privacy impact is low because the victim's own rows stay unreadable to the attacker.

**Server change that would close it.**
- A set log may be written only into a session whose `user_id` is the caller's.
- For `workout_logs`: add a nullable `session_id` FK with a partial unique index, and have the client send it and treat 23505 as "already filed". That needs a client change. The alternative is to derive the log from session completion server-side, which is a data-model choice per 118.

```sql
-- sketch — not a migration, not applied
-- pre-flight (read-only): SELECT count(*) FROM workout_set_logs l JOIN workout_sessions s
--   ON s.id = l.session_id WHERE l.user_id IS DISTINCT FROM s.user_id;
ALTER POLICY "users manage own set logs" ON public.workout_set_logs
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.workout_sessions s
                 WHERE s.id = session_id AND s.user_id = (SELECT auth.uid())));

ALTER TABLE public.workout_logs ADD COLUMN IF NOT EXISTS session_id uuid
  REFERENCES public.workout_sessions(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_workout_logs_session
  ON public.workout_logs (session_id) WHERE session_id IS NOT NULL;
```

**Dependencies.**
- No owner product decision for the set-log half.
- Rows with a NULL `session_id` would fail the new `WITH CHECK` on UPDATE; decide whether that is acceptable after the pre-flight count.
- The `workout_logs` half needs a client change (send `session_id`) and the data-model call noted in 118.
- No pending or excluded migration touches these tables; ordering is free.

**Category.** Set-log half **C**. `workout_logs` half **C** plus engineering design.

---

## C14-MIG-03 — Habit-log and habit ownership (W28; ledger "habit ownership")

**Current authoritative state.**
- **Tables:** `client_habits` (001:119-131) and `habit_logs` (001:133-142, `UNIQUE(habit_id, logged_date)` at :141, FK to `client_habits` ON DELETE CASCADE, re-stated 003:220-223).
- There is no `habits`, `habit_completions` or `user_habits` table in any migration.
- **`habit_logs` write** `"users manage own habit logs"` (003:226-229, which replaces 001:362): `FOR ALL USING (user_id = auth.uid())`. **`habit_id` is not checked against the caller's habits.**
- **`habit_logs` coach read** (100:66-69): owner or active coach. This replaced 003:230-233, which was `USING (true)`.
- **`client_habits`** `"coach client habits"`:
  - 001:361: `USING (coach_id = auth.uid() OR client_id = auth.uid())`.
  - 185 alters the coach arm to require `is_active_coach_of(client_id)` (`185_coach_write_arms_require_active_relationship.sql:61-67`). **185 is excluded on QA, so not applied** (`expected_applied.json` excluded["185"]). On QA, the QAX-SEC-03 coach arm is therefore still live.
  - 185's own header says a client can still write a row naming an arbitrary `coach_id`.

**Flutter call sites.**
- `apps/mobile/lib/features/coach/data/coach_program_service.dart`:
  - `logHabit` upserts with `onConflict: 'habit_id,logged_date'`, `user_id = currentUser` (:400-412).
  - `addCustomHabit` (:467-485).
  - `assignHabits` (:357-385).
- `apps/mobile/lib/features/habits/domain/habit_provider.dart`: `toggleComplete` and `updateValue` (:194-261).

**Client-side mitigation (P0-FL-59e).**
- `habit_provider.dart:84-98`: `_owner` and `_isOwner`.
- `_mine(habitId)` at :167-175: refuses a habit not in this member's list (`HabitNotListed`, :68-73).
- Scoring is bound to `_owner` (:221-235).

What this does not cover:
- `logHabit` itself still reads `currentUser` at send time.
- A direct API call can log any `habit_id`.
- **W28** ("A's typed goal or habit saved to B", inventory row 52, PARTLY) is B writing *B's own* row with A's text. RLS ownership cannot detect that. Only an expected-uid assertion can (C14-MIG-05).

**Exploit / failure scenario.**
- X (or B after a switch) upserts a `habit_logs` row `{habit_id: <A's habit>, user_id: X, logged_date: today}`, which takes A's `(habit_id, date)` slot.
- A's own tick then conflicts. The ON CONFLICT UPDATE target is X's row, which A's `USING` does not admit, so the tick is expected to fail with an RLS or 23505 error. A's streak for that day is lost, and A's coach does not see X's row.
- This comes from reading the code, not a replay. There is no habit probe in `probes.sql`.
- On QA, without 185, any user can also insert `client_habits` for any client by naming themselves as coach (QAX-SEC-03, P1).

**Severity.** `habit_logs`: data integrity and user impact, around P2–P3. `client_habits` coach arm on QA: security P1, already tracked as QAX-SEC-03 and fixed by 185 once applied.

**Server change that would close it.** A habit log may be written only by the habit's client, for a habit whose `client_id` is the caller.

```sql
-- sketch — not a migration, not applied
-- pre-flight (read-only): SELECT count(*) FROM habit_logs l JOIN client_habits h
--   ON h.id = l.habit_id WHERE l.user_id IS DISTINCT FROM h.client_id;
ALTER POLICY "users manage own habit logs" ON public.habit_logs
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.client_habits h
                 WHERE h.id = habit_id AND h.client_id = (SELECT auth.uid())));
```

**Dependencies.**
- Apply 185 first (QAX-SEC-03). It belongs to the ordered batch 182→183→184→185→186 and waits on an owner-approved QA window (`expected_applied.json` excluded["185"].gate).
- Any further change to `"coach client habits"` must come after 185.
- No owner decision for the `habit_logs` half. W28 is not closable by RLS.

**Category.** `habit_logs` half **C**. `client_habits` half is C via the already-authored 185. W28 → C14-MIG-05 (B).

---

## C14-MIG-04 — Server-side PD8 (check-in resubmission after coach review; E-CHK-09)

**What PD8 is.**
- **E-CHK-09** (`docs/QA_WORKSTREAM_E_NUTRITION_CHECKIN_RECONCILIATION.md:695-702`, P3): resubmitting a `reviewed` check-in reverts it to `submitted`, keeps `feedback_message`/`reviewed_at`, and does not notify the coach. Its fix text: "decide whether re-submission is permitted".
- **EC-07** (`MASTER_REMEDIATION_REGISTRY.md:1392`) is the P1 parent.

**Decision status — conflicting records; I have not resolved this.**
- **Recorded as decided:**
  - Commit `20adcc4` (merged as `4e9bc0b`, an ancestor of HEAD) says "Owner decision PD8 (2026-11-09): a reviewed weekly check-in counts as completed for that week and cannot be resubmitted".
  - `apps/mobile/test/widget/checkin_loop_test.dart:337` repeats it.
- **Recorded as open:**
  - The ledger (`ee7d032`, "Decisions required (Julia)" #6) still lists "Check-in resubmission after review (PD8 / E-CHK-09; option A recommended)".
  - Its Cycle-13 behaviour list includes "PD8 reading (queue vs server)".
- **For this package: server-side PD8 is an OWNER DECISION and is undecided.** Whether the 2026-11-09 client-side ruling is recorded under §2 also needs Julia's confirmation.

**Current authoritative server state.**
- **`enforce_checkin_authorship()`** (BEFORE UPDATE, `114_rls_weekly_checkins.sql:52-108`, trigger :110-113):
  - In the client branch (:84-95), only `v_coach_cols[1:5]` are protected: feedback_message, feedback_recommendations, coach_name, reviewed_at, coach_id. **`status` is not.**
  - The only status rule refuses a transition *to* `reviewed` (:91-94).
  - Result: **a client may move a reviewed row back to `submitted` and overwrite every answer.**
- **Policies:** INSERT owner-only (114:150-152); UPDATE owner or active coach (114:155-163).
- **`trg_audit_phi_correction`** (`151_p2_b1_b4_emitters.sql:220-281`, owner decision B4) treats any client change to answer columns as an *authorized* PHI correction and audits it. B4 permits corrections; PD8 option A forbids resubmitting a reviewed week. **These two rules interact.**
- **Coach notification** `notify_coach_on_checkin` is AFTER INSERT only (004:164-167), so a resubmission notifies nobody.

**Flutter call sites and client-side mitigation.** All in `apps/mobile/lib/features/checkins/data/weekly_checkin_service.dart` unless noted:
- `weekStatus` treats `reviewed` as done (:109-112).
- `submitWeeklyCheckin` reads the row first (`_weekBeforeWrite`, :266-305) and throws `alreadyReviewedMessage` (:199-202, :308-309).
- `daily_checkin_screen.dart:160-170` shows that message.

What this does not cover:
- A direct API upsert.
- The read-then-upsert race: the coach reviews between :197 and the upsert at :204-229.
- **The pre-read fails open:** a failed lookup returns `reviewed: false` (:275-278, :301-303) and the upsert proceeds.
- If the server ever refuses, the upsert's catch (:230-236) returns a generic `false`, so the client would need a mapping for that error.

**Exploit / failure scenario.** A client resubmits a week the coach has replied to, by direct API or by the race or fail-open path. The answers the coach responded to are overwritten. The status is `submitted` while the reply still sits on the row, and the UI hides it. The week re-queues silently with no notification, and 151 audits the change as a legitimate correction.

**Severity.** Data integrity of the coach's reviewed record, plus user impact (a silent re-queue). E-CHK-09 rates it P3. With PD8 shipped client-side, the server change is defence-in-depth.

**Server change (depends on the decision).**
- **Option A** (matches the shipped client rule): in the client branch of `enforce_checkin_authorship`, refuse any change when `OLD.status = 'reviewed'`. This needs an explicit ruling on whether B4 corrections are still allowed on reviewed weeks.
- **Option B** (resubmission allowed): the trigger clears the review fields on `reviewed → submitted` (only the trigger can, because 114 blocks client writes to them) and adds an AFTER UPDATE coach-notification arm, as E-CHK-09 suggests.

```sql
-- sketch — not a migration, not applied (CREATE OR REPLACE of the whole 114 function, unchanged otherwise)
-- Option A, inside the  IF v_uid = OLD.user_id THEN  branch, before the existing checks:
  IF OLD.status = 'reviewed' THEN
    RAISE EXCEPTION 'weekly_checkins: a reviewed week is closed' USING ERRCODE = '42501';
  END IF;
-- Option B instead:
--   IF OLD.status = 'reviewed' AND NEW.status = 'submitted' THEN
--     NEW.feedback_message := NULL; NEW.feedback_recommendations := NULL;
--     NEW.reviewed_at := NULL;  -- (after the v_changed checks, so the client did not write them)
--   END IF;
--   + AFTER UPDATE trigger notifying the coach on reviewed->submitted.
```

**Dependencies.** Owner decision PD8 at server level, and its interaction with B4 (151). The Flutter error mapping for the server refusal. No pending migration touches `weekly_checkins`.

**Category: A** (owner decision), then **C** (authorization to apply).

---

## Related items in the same class

- **C14-MIG-05 — `p_expected_uid` on RPCs (A-11; also W28).**
  - **Current state:** at `a446926`, **no SQL function accepts an expected uid** (0 matches under `supabase/`). Dart has 37 `expectedUid` uses, all client-side.
  - **`auth.uid()`-scoped RPCs called from flows that can outlast an account switch:**
    - `award_points` (`035_scoring_engine.sql:78`)
    - `penalize_points` (`054_score_penalty.sql:8`)
    - `generate_client_plan` (`121_restore_unique_plan_day_titles.sql:97`, which deactivates and recreates the caller's habits and plan)
    - `deactivate_self_generated_plan` (`047_self_guided_plan_generator.sql:55`)
    - `get_or_create_conversation` (131:303)
  - **Client guards:** `score_engine.dart:22-28`, `coaching_mode_provider.dart:51-56`.
  - **Server change:** an optional `p_expected_uid uuid DEFAULT NULL` that raises 42501 when it differs from `auth.uid()`.
  - **Caveats:**
    - It changes signatures, which means overloads, PostgREST ambiguity, and re-granting through 116's allow-list (`116_rpc_execution_security.sql:436-…`; the grants are issued in a format() loop).
    - Direct table writes would need a different carrier, such as a request-header check in a trigger. That is an option, not designed.
  - **Category: B.**
- **C14-MIG-06 — Atomic availability cancel (inventory E8, "D-3, Julia").**
  - **Already server-side:** 187's AFTER trigger `coaching_calls_sync_slot` reopens the slot in the same statement that cancels the call (`187_booking_slot_integrity.sql:112-150`, :164-167). 187 is applied on QA per `expected_applied.json`, although 187's header at :4-5 still says "NOT APPLIED", which is stale.
  - **Still client-side and non-atomic:**
    - The cancel update (`coach_availability_screen.dart:281-287`).
    - A now-redundant slot update (`_reopenSlot`, :354-372).
    - The client `notifications` insert (:322-328).
  - **Server change:** a `cancel_coaching_call(p_call_id, p_expected_uid)` RPC that does the update and the notification in one transaction.
  - D-3 is not defined anywhere else in the files I read.
  - **Category: A** (D-3), then **C**.
- **C14-MIG-07 — Server-side challenge award / `auth.uid()` award gap (A-11, A-14, W24).**
  - **Current state:**
    - `award_points` credits `auth.uid()` and accepts any caller-chosen positive `p_points` and action (`035_scoring_engine.sql:78-136`; only `<= 0` is refused at :91).
    - `challenge_participants` `"users manage own participation"` lets a user set their own `current_progress` freely (001:388).
    - `live_challenge_service.dart:97-109` awards +100 when progress is at least 1.0. Its `_stillSignedIn` check (:111-119) is client-only. `ScoreEngine()` is built there without `forUid` (:86, :106).
  - **Server change:** derive points and challenge completion from source rows with triggers and remove client write access. That is ledger decision brief #9 (recommended: A, accept self-reported scores, for the closed beta; B, server-side scoring, before any public leaderboard). Otherwise, an expected-uid assertion (C14-MIG-05).
  - **Category: A**, then **B**.

---

## Summary

| ID | Item | Severity | Client mitigation | Server change needed | Category | Unblock requirement |
|---|---|---|---|---|---|---|
| C14-MIG-01 | `messages` INSERT participant check (QAX-SEC-04, A-05/W3); UPDATE authorship (I-NOT-04); `conversations` participant re-point | INSERT P2 security; UPDATE P1 integrity; re-point privacy (untriaged) | FL-59c owner/epoch guards (`chat_screen.dart:83-102`, `messaging_service.dart:16-19,229`); not effective against direct API | INSERT `WITH CHECK` membership; BEFORE UPDATE authorship trigger on `messages`; immutable participants on `conversations` | C (INSERT, UPDATE security); A (PD-B18 sender edit); B (re-point triage) | Owner authorization to author and apply (no decision needed for INSERT); PD-B18 for edit window; local replay QAX-SEC-04 + POS-04 |
| C14-MIG-02 | Set-log session ownership (A-01/W4); `workout_logs` duplicate filing | P2 integrity / user impact (static, not replayed) | `requireWorkoutOwner` (`workout_session_store.dart:150-158`); in-memory `_logFiled` | Set-log `WITH CHECK` on session owner; `workout_logs.session_id` + partial unique (new column) | C (+ design for `workout_logs`) | Pre-flight mismatch count; client change for `session_id`; authorization to apply |
| C14-MIG-03 | Habit-log ownership; `client_habits` coach arm; W28 | `habit_logs` P2–P3 integrity; `client_habits` P1 (QAX-SEC-03, on QA) | `_mine`/`_isOwner` (`habit_provider.dart:84-98,167-175`) | `habit_logs` `WITH CHECK` on `client_habits.client_id`; 185 for `client_habits` | C | Apply 185 first (owner QA window for 182→186); then authorization; W28 → MIG-05 |
| C14-MIG-04 | Server-side PD8 / E-CHK-09 | P3 integrity (defence-in-depth) | Pre-read and refuse (`weekly_checkin_service.dart:197-202`); fails open on lookup error (:301-303); race | 114 trigger: refuse change of a reviewed row (A), or clear review and notify (B) | A, then C | Owner ruling on server PD8 and its interaction with B4 (151); reconcile ledger #6 vs commit `20adcc4` |
| C14-MIG-05 | `p_expected_uid` on RPCs (A-11, W28) | Security-architecture (account-switch writes) | `forUid`/`_isOwnerSignedIn` checks | Optional expected-uid argument raising 42501; table-write carrier TBD | B | Design of signature/overload and grant strategy |
| C14-MIG-06 | Atomic availability cancel (E8, D-3) | Low: slot half closed by 187; notification non-atomic | Step-wise owner checks (`coach_availability_screen.dart:268-330`) | `cancel_coaching_call` RPC (call + notify in one transaction) | A, then C | D-3 owner decision |
| C14-MIG-07 | Server-side challenge award / award gap (A-14, W24) | Integrity of scores (self-awarded points) | `_stillSignedIn` (`live_challenge_service.dart:111-119`); `ScoreEngine.forUid` | Trigger-derived scoring, or expected-uid on `award_points` | A, then B | Decision brief #9 (accept for beta vs server-side) |

## What is NOT claimed

- Nothing was applied, authored or run against any database, and no live QA or production catalog was read. "Current state" means what the migrations in the repo declare. Whether QA matches is taken only from the declarations in `supabase/expected_applied.json`, which is not the ledger.
- The set-log and habit-log scenarios (C14-MIG-02 and C14-MIG-03) come from reading the code, not from a replay. In particular, the exact error A gets when the ON CONFLICT target row is someone else's was not verified. Only QAX-SEC-04 has a local-replay probe.
- No SQL sketch has been compiled, replayed or mutation-tested. None of them is a migration, and none has a number.
- I do not decide PD8, PD-B18, D-3 or brief #9, and I do not say whether the 2026-11-09 PD8 approval is recorded under §2.
- Production state is not assessed.
- The inventory IDs (A-01, A-05, A-11, A-14, W3, W4, W24, W28) were read from `docs/IDENTITY_INVENTORY_CYCLE13.md` on branch `docs/beta-completion-ledger` (`ee7d032`). They do not exist on the `a446926` tree.
- I did not check that migrations 196, 197 and 198 on the open branches stay free of conflicts beyond grepping them for the tables named here.
