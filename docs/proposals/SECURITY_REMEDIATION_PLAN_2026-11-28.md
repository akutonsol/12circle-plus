# Security remediation plan: server-side authorization (Item 1, 2026-11-28)

**Status: PROPOSAL. Nothing here is authored as a migration file, applied, or run against any database.** Every SQL block is a draft for review. Applying any of it needs the owner's explicit authorization, a migration number (196–198 are already used on open branches, so ≥ 199), and the existing QA-window procedure. Sources:
- `docs/MIGRATION_CLASS_IDENTITY_RISKS_C14.md` (C14-MIG-01..07);
- the migrations at `integration/p0-flutter-stack-c15` @ `6d1611d` (`supabase/` unchanged since main `8f2c8a0`).

## 1. Trust boundary (verified 2026-11-28)
All three holes are **server-side**: the app is not the line of defence, because any holder of a valid JWT can call PostgREST directly.

| Object | Current rule (file:line) | What a signed-in user can do | App behaviour today |
|---|---|---|---|
| `conversations` UPDATE | `USING (participant_1 = auth.uid() OR participant_2 = auth.uid())`, with no `WITH CHECK` and no column restriction (`003_fk_and_rls_fixes.sql:73-76`) | A participant sets `participant_2` (or `participant_1`) to any user C. C then reads the whole thread through the messages SELECT policy, and its media through the 130 storage policy. **Privacy, possibly health content (coach–client chat).** | Writes only `last_message`, `last_message_at` (`messaging_service.dart:240`) |
| `messages` INSERT | `WITH CHECK (sender_id = auth.uid())` (`003:91-94`) | A user who knows a conversation id posts into it, and `trg_notify_on_message` pushes "New message from X" to participant_1 (QAX-SEC-04, P2) | FL-59c owner/epoch guards; sends only into conversations it read |
| `messages` UPDATE | `USING` participant check only, so `WITH CHECK` = `USING`; no column restriction (`003:96-104`) | A participant rewrites the other person's `content`/`sender_id`, or moves a message to another of their conversations (I-NOT-04 / H-19, P1) | Updates only `is_read` (`messaging_service.dart` `markAsRead`) |
| `workout_set_logs` ALL | `USING (user_id = auth.uid())` only (`001_full_ecosystem.sql:370`) | A user writes set rows into **another member's** session (the session's owner is never checked), occupying that member's `(session_id, set_id)` slots (C14-MIG-02) | `requireWorkoutOwner` before every set write (FL-59b) |
| `habit_logs` ALL | `USING (user_id = auth.uid())` (`003:226-229`) | A user logs against any `habit_id`, taking the owner's `(habit_id, date)` slot (C14-MIG-03) | `_mine(habitId)` guard (FL-59e) |
| RPCs (`award_points`, `penalize_points`, `generate_client_plan`, `get_or_create_conversation`, …) | answer for `auth.uid()`; no expected-uid parameter | After an account switch, a delayed client call runs as whoever is now signed in. Undetectable server-side (C14-MIG-05) | `forUid` / `_isOwnerSignedIn` checks |

**Client-side work in this pass** (RM-2) adds a static test that fails if app code ever writes participant, sender or conversation columns outside the RPC. That **does not** close any row above.

## 2. Proposed changes (drafts, in recommended order)

### R1-A: conversations participants immutable (closes the re-point; highest priority)
```sql
-- DRAFT — not a migration, not applied
CREATE OR REPLACE FUNCTION public.enforce_conversation_participants()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RETURN NEW; END IF;          -- service path unchanged
  IF NEW.participant_1 IS DISTINCT FROM OLD.participant_1
     OR NEW.participant_2 IS DISTINCT FROM OLD.participant_2 THEN
    RAISE EXCEPTION 'conversations: participants are immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_conversation_participants_immutable
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_conversation_participants();
```
App impact: none. The app never changes participants.

### R1-B: messages INSERT requires a participant (QAX-SEC-04)
```sql
-- DRAFT — not a migration, not applied
ALTER POLICY "authenticated can send messages" ON public.messages
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.conversations c
                 WHERE c.id = conversation_id
                   AND (SELECT auth.uid()) IN (c.participant_1, c.participant_2)));
```
App impact: none for legitimate sends. A refused send is already said and recorded (FL-59c/63b).

### R1-C: messages UPDATE authorship (I-NOT-04)
A BEFORE UPDATE trigger with these rules:
- `sender_id` and `conversation_id` are immutable.
- A non-sender may change only `is_read`.
- Whether a sender may edit their own `content` is **PD-B18 (owner decision)**. Until it is decided, the safe draft refuses content edits by anyone, because the app has no edit feature today.

```sql
-- DRAFT — not a migration, not applied
CREATE OR REPLACE FUNCTION public.enforce_message_authorship()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id THEN
    RAISE EXCEPTION 'messages: sender and conversation are immutable' USING ERRCODE = '42501';
  END IF;
  IF (to_jsonb(NEW) - 'is_read') IS DISTINCT FROM (to_jsonb(OLD) - 'is_read') THEN
    RAISE EXCEPTION 'messages: only is_read may change' USING ERRCODE = '42501';  -- PD-B18 may relax this for the sender
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_message_authorship
  BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.enforce_message_authorship();
```

### R1-D: set-log session ownership (C14-MIG-02, set-log half)
```sql
-- DRAFT — not a migration, not applied
-- pre-flight (read-only, owner-authorized environment only):
--   SELECT count(*) FROM workout_set_logs l JOIN workout_sessions s ON s.id = l.session_id
--   WHERE l.user_id IS DISTINCT FROM s.user_id;
ALTER POLICY "users manage own set logs" ON public.workout_set_logs
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.workout_sessions s
                 WHERE s.id = session_id AND s.user_id = (SELECT auth.uid())));
```
The `workout_logs.session_id` duplicate-filing half is held back. It needs a new column, a client change and the data-model call noted in 118.

### R1-E: habit-log ownership (C14-MIG-03)
```sql
-- DRAFT — not a migration, not applied; AFTER 185 (QAX-SEC-03) is applied in the owner-approved 182→186 window
ALTER POLICY "users manage own habit logs" ON public.habit_logs
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.client_habits h
                 WHERE h.id = habit_id AND h.client_id = (SELECT auth.uid())));
```

### R1-F: expected uid on RPCs (C14-MIG-05)
This is not drafted, because it needs an architecture decision. Adding `p_expected_uid uuid DEFAULT NULL` changes signatures, which means:
- PostgREST overload ambiguity;
- re-granting through 116's format()-loop allow-list (see the "RPC grants hide in format() loops" lesson);
- a different carrier for direct table writes.

## 3. Verification plan (once authorized)
1. **Pre-flight:** read-only counts (R1-D, R1-E) in the authorized environment.
2. **Local replay first:** replay 000→head plus the new file on a disposable database, then run:
   - the QAX-SEC-04 probe and its positive control POS-04;
   - new probes for re-point (expect 42501), cross-session set logs (42501) and foreign habit logs (42501);
   - positive controls: normal send, mark read, preview update, own set log, own habit log.
3. **Guards:** migration hygiene, durability, the ENV-3 declaration (`supabase/expected_applied.json`), function posture (definer `search_path`, anon EXECUTE), the schema contract guard and the live security suite.
4. **QA:** apply only in the owner-approved window, by the documented procedure, never `supabase db push` (it would also push 182/183/186/193–195). Then re-run the live security suite.

## 4. Authorization request (for the owner)
| # | Needed | Blocks | Recommendation (not a decision) |
|---|---|---|---|
| 1 | Authorize authoring migration(s) ≥ 199 for R1-A, R1-B and R1-C (strict form), and their local replay | the conversation re-point (privacy), QAX-SEC-04, I-NOT-04 | **Authorize R1-A first**: smallest change, no product choice, highest exposure |
| 2 | PD-B18: may a sender edit their own message, and for how long? | relaxing R1-C | Keep "no edits" for beta (the app has no edit feature) |
| 3 | Authorize R1-D, with the pre-flight count | set-log cross-session writes | Authorize; no product choice |
| 4 | The owner-approved QA window for 182→186, then R1-E | QAX-SEC-03 (P1, live on QA), habit logs | Schedule the window; 185 first |
| 5 | Architecture decision on R1-F | server-side detection of account-switch writes | Defer until after beta; client guards are in place |
| 6 | Server-side PD8 (option A, matching the shipped client rule) and its B4 interaction | reviewed check-ins overwritten by direct API | Option A, with B4 corrections still allowed on submitted (not reviewed) weeks |

## 5. Static validation of the drafts (2026-11-28, Stage 2–3; nothing executed against any database)
These are checks against every server and app path that writes these tables, at `integration/p0-flutter-stack-rem1` @ `cfbac7c`.

| Draft | Paths checked | Result |
|---|---|---|
| R1-A (participants immutable) | `get_or_create_conversation` (`131:303-345`) is SECURITY DEFINER and only `INSERT … ON CONFLICT DO NOTHING` on the least/greatest unique pair; no migration or Edge Function `UPDATE`s conversations; the app updates only `last_message`, `last_message_at` (`messaging_service.dart:240`) | **No legitimate path changes participants** → safe |
| R1-B (INSERT requires a participant) | The app sends only into conversations it read through the participant SELECT; `trg_notify_on_message` (`004:69-105`) is AFTER INSERT and only reads | Safe; a refused send is already said and recorded (FL-59c/63b) |
| R1-C strict (only `is_read` may change) | The app's `markAsRead` writes only `{'is_read': true}` (`messaging_service.dart:289`); there are **no** BEFORE UPDATE triggers on `messages` or `conversations` (so there is no `updated_at` rewrite that would trip the jsonb comparison); the columns are id, conversation_id, sender_id, content, is_read, sent_at, metadata (129); the app has no edit feature | Safe |
| R1-D (set log ⇒ own session) | All app writes carry the bound `session_id` and run behind `requireWorkoutOwner` (`workout_service.dart:185-215`); server writes to `workout_set_logs` exist only in one-time migration backfills (`051:10`, `120:58`); trigger 129 is AFTER (notifications) | Safe for the app. Rows with a NULL `session_id` could not be updated; the pre-flight count decides whether any exist |
| R1-E (habit log ⇒ own habit) | The app's `logHabit` lives in `coach_program_service.dart` (SEC-R3, **not modified**); the server policy needs no client change | Re-check after 185, in the window |

Note on the unique pair index (131): the conversation re-point is still possible today, but only towards a user the caller does not already share a conversation with.

### Rollback (each draft is independently reversible)
```sql
-- DRAFT rollback — not applied
DROP TRIGGER IF EXISTS trg_conversation_participants_immutable ON public.conversations;
DROP FUNCTION IF EXISTS public.enforce_conversation_participants();
ALTER POLICY "authenticated can send messages" ON public.messages WITH CHECK (sender_id = auth.uid());
DROP TRIGGER IF EXISTS trg_message_authorship ON public.messages;
DROP FUNCTION IF EXISTS public.enforce_message_authorship();
ALTER POLICY "users manage own set logs" ON public.workout_set_logs USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

### Pre-flight (read-only, in the authorized environment only)
```sql
-- conversations whose participants are not a pair the app could have made (diagnostic only)
SELECT count(*) FROM public.conversations WHERE participant_1 = participant_2 OR participant_1 IS NULL OR participant_2 IS NULL;
-- messages from a non-participant (would be refused by R1-B going forward; existing rows untouched)
SELECT count(*) FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id
 WHERE m.sender_id NOT IN (c.participant_1, c.participant_2);
-- set logs not owned like their session (R1-D)
SELECT count(*) FROM public.workout_set_logs l LEFT JOIN public.workout_sessions s ON s.id = l.session_id
 WHERE l.session_id IS NULL OR l.user_id IS DISTINCT FROM s.user_id;
```

### Execution, once authorized
1. Author the file(s) as migration **≥ 199**; 196–198 are already used on open branches.
2. Declare them in `supabase/expected_applied.json` as `pending`.
3. Local replay on a disposable database: existing harness plus the new probes and positive controls.
4. Open a PR and get CI green.
5. Apply to the authorized environment using the documented manual procedure. **Never `supabase db push`**: it would also push 182/183/186/193–195.
6. Run the live security suite.
7. Move the frontier and record the exact migration versions.
