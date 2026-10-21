-- 130_private_storage_buckets.sql
--
-- Wave 3A / task 3A-10.  H-04 + H-05.
--
-- REWRITTEN IN PLACE 2026-09-09 under owner Ruling A, recorded in
-- docs/decisions/DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md.  That ruling is an
-- explicit, recorded exception to QA_CLOSURE_STANDARD.md section 8 ("never
-- rewrite a migration in place unless the wave plan explicitly authorizes it")
-- and an amendment to the wave plan for task 3A-10.  Its basis, verbatim from
-- the ruling: gate 0.9 leaves no migration number available for 3A-10's
-- correction (131 is assigned to 3A-11, 132+ is unassigned), migration 130 is
-- not committed, and committing it in its defective form would permanently
-- encode a known-defective policy contract and foreclose the correction path.
--
-- The pre-rewrite text is preserved verbatim in
-- docs/decisions/DEC-3A-10_EVIDENCE_2026-09-09.md part C
-- (sha256 01ecdc92393664fb25b415f889c6940f28e12e90cf1c451ffb4974e347be39b5).
-- It was never committed, so that artifact is its only record.
--
-- ===========================================================================
-- WHY THE PREVIOUS VERSION OF THIS FILE WAS WRONG
-- ===========================================================================
--
-- It authorized chat-media with
--
--     public.shares_conversation_with( ((storage.foldername(name))[1])::uuid )
--
-- Three independent defects:
--
--   1. storage.foldername() returns every path segment EXCEPT the filename, so
--      for the client's path `messages/<uid>/<ts>.<ext>` element [1] is the
--      literal string 'messages'.  'messages'::uuid raises 22P02.
--
--   2. The cast RAISES rather than denies.  A policy predicate that errors
--      aborts the statement instead of evaluating false, and USING is applied
--      per candidate row -- so a single object whose first segment is not a
--      uuid breaks every read of the bucket, for every user.  Migration 029,
--      the progress-photos precedent, deliberately compares as text for
--      exactly this reason.  This file now does the same: NO cast is ever
--      applied to a path segment.
--
--   3. The identity was wrong, and that survives fixing 1 and 2.
--      shares_conversation_with(u) asks "do the caller and u share SOME
--      conversation?" -- a person-to-person predicate.  Keyed on a user id it
--      is not even satisfiable: an uploader's own upload evaluates
--      shares_conversation_with(auth.uid()), which is false unless a
--      conversation has the same person in both participant slots.  And a
--      uid-keyed folder holds that user's media from EVERY conversation, so
--      one shared conversation would disclose all of it.  These are body
--      photographs (QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md, H-04).
--
-- ===========================================================================
-- THE CANONICAL CONTRACT  (option C, approved by the owner 2026-09-09)
-- ===========================================================================
--
--     chat-media/messages/<conversation_id>/<uploader_uid>/<epoch>.<ext>
--
--   [1]  literal 'messages'   namespace, and a depth assertion
--   [2]  conversations.id     THE AUTHORIZATION IDENTITY
--   [3]  uploader's auth.uid()  attribution, and the scope of mutation
--   filename                  opaque; no policy ever parses it
--
-- Invariant:
--
--   Only an authenticated user who is a participant of conversation C may
--   upload, read or delete media associated with conversation C.
--
--   read    any participant of [2]                       (symmetric)
--   upload  a participant of [2], into their own [3]     (asymmetric)
--   delete  the uploader only  ([3] = auth.uid())        (asymmetric)
--   update  NO POLICY -- chat media is immutable.  The client uploads with
--           upsert:false.  Read is symmetric; mutation deliberately is not,
--           so this bucket does not reproduce I-NOT-04 / H-19 (a conversation
--           participant can rewrite the other party's message), which is a
--           P1 still open against the messages UPDATE policy.
--
-- Authorization is decidable BEFORE the message row exists -- it needs only
-- the conversation, which exists before the picker opens -- so the client
-- keeps uploading first and inserting the message second.  A message id in the
-- path would have inverted that and produced visible broken attachments.
--
-- No new column and no new table.  public.conversations already carries the
-- participant pair; messages.metadata already exists (migration 129).  The
-- only new object is the membership predicate below.
--
-- shares_conversation_with() is NOT modified, NOT dropped and NOT weakened.
-- It remains load-bearing for conversation_participant_profiles (102) and for
-- may_notify() (118, 129).  The predicate added here is additive.
--
-- ===========================================================================
-- CONVERGENCE -- required by Ruling A
-- ===========================================================================
--
-- QA carries this file's ORIGINAL objects out of band: both buckets are
-- already private and all four original chat-media policies exist, under the
-- names below, while supabase_migrations.schema_migrations has NO row for 130
-- (max(version) = 129).  The DDL was applied outside the mechanism that writes
-- the ledger row -- the hazard COWORK_ENGINEERING_GOVERNANCE.md section 18
-- names in advance.
--
-- This file must therefore repair that state when it is applied, not assume a
-- clean slate.  Every original policy name is dropped by name below before the
-- canonical set is created, INCLUDING the UPDATE policy, which is dropped and
-- deliberately NOT recreated.
--
-- Ruling A also forbids creating 130's ledger row by any means other than this
-- migration's own application: no INSERT, no `supabase migration repair`, no
-- migration-history repair.  QA's ledger stays at 129 and 130 stays declared
-- `pending` in supabase/expected_applied.json until it is really applied.
--
-- IDEMPOTENT AND REPLAY-SAFE.  Every statement is ON CONFLICT, CREATE OR
-- REPLACE, or DROP ... IF EXISTS followed by CREATE.  Running it twice, or
-- against the out-of-band state, produces the same end state.
--
-- NO ENVIRONMENT WAS CONTACTED IN AUTHORING THIS FILE.  It has not been
-- applied anywhere.  Application to QA is a separately authorized step.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The two buckets.  H-04 (chat-media) and H-05 (progress-photos).
--
-- Both hold body photography and MUST remain non-public.  ON CONFLICT DO
-- UPDATE re-asserts `public = false` even where a bucket already exists, so
-- this converges a bucket that was created public by any other route.
--
-- progress-photos' own owner/coach RLS is migration 029's and is not touched
-- here.  029 writes storage.objects policies FOR this bucket but never creates
-- it -- that gap is H-05, and this statement is its whole fix.
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public)
VALUES ('progress-photos', 'progress-photos', false)
ON CONFLICT (id) DO UPDATE
SET
  name   = EXCLUDED.name,
  public = EXCLUDED.public;

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', false)
ON CONFLICT (id) DO UPDATE
SET
  name   = EXCLUDED.name,
  public = EXCLUDED.public;

-- ---------------------------------------------------------------------------
-- 2. The membership predicate.
--
-- Takes TEXT, not uuid, and compares c.id::text to it.  That is the whole
-- point: the argument is an attacker-controlled path segment, and casting it
-- to uuid is what made the previous version raise instead of deny (defect 2
-- above).  Casting the COLUMN is always safe; casting the ARGUMENT is not.
-- Migration 029 established this shape ("r.client_id::text = (storage.
-- foldername(name))[1]") and it is followed deliberately.
--
-- Trade-off, stated: c.id::text = $1 cannot use the conversations primary-key
-- index.  The table is small and 029 made the same trade for the same reason.
--
-- SECURITY DEFINER because public.conversations carries its own RLS
-- ("participants can read conversations", migration 003).  Evaluated as the
-- caller from inside a storage.objects policy it would resolve nothing useful;
-- as definer it resolves the membership fact only and returns a boolean -- it
-- never projects a conversation row.
--
-- Fail-closed for an anonymous caller: auth.uid() is NULL, every comparison is
-- NULL, EXISTS is false.  participant_1/participant_2 are nullable and NULL
-- never equals a non-null uid, so a half-populated conversation authorizes
-- nobody.
--
-- Gate 0.14 / migration 122: SECURITY DEFINER with `SET search_path = public,
-- pg_temp`, revoked from PUBLIC and anon, granted only to authenticated.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_conversation_participant(conversation text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversations c
    WHERE c.id::text = conversation
      AND (   c.participant_1 = (SELECT auth.uid())
           OR c.participant_2 = (SELECT auth.uid()))
  );
$$;

REVOKE ALL ON FUNCTION public.is_conversation_participant(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(text) TO authenticated;

COMMENT ON FUNCTION public.is_conversation_participant(text) IS
  'True when the caller is one of the two participants of the conversation '
  'whose id is given as TEXT. Conversation-scoped membership predicate for the '
  'chat-media storage contract (DEC-3A-10). Takes text and compares '
  'conversations.id::text deliberately: the argument is an untrusted storage '
  'path segment and must never be cast to uuid. Distinct from '
  'shares_conversation_with(uuid), which is person-to-person and must not be '
  'used to authorize storage paths.';

-- ---------------------------------------------------------------------------
-- 3. Remove the out-of-band chat-media policies by name.
--
-- These four names are what QA carries today from the pre-rewrite version of
-- this file.  Dropping them by name is what makes this migration convergent
-- rather than additive.  The UPDATE policy is dropped and NOT recreated.
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "conversation participants read chat media"   ON storage.objects;
DROP POLICY IF EXISTS "conversation participants upload chat media" ON storage.objects;
DROP POLICY IF EXISTS "conversation participants update chat media" ON storage.objects;
DROP POLICY IF EXISTS "conversation participants delete chat media" ON storage.objects;

-- Also drop the canonical names, so re-running this file is a clean replace.
DROP POLICY IF EXISTS "chat media read by conversation participants"     ON storage.objects;
DROP POLICY IF EXISTS "chat media upload by conversation participants"   ON storage.objects;
DROP POLICY IF EXISTS "chat media delete by uploader"                    ON storage.objects;

-- ---------------------------------------------------------------------------
-- 4. The canonical policy set: SELECT, INSERT, DELETE.  No UPDATE.
--
-- Every policy asserts the same four structural facts before it asserts
-- authorization, so a malformed path is denied rather than misread:
--
--   bucket_id = 'chat-media'
--   array_length(storage.foldername(name), 1) = 3   exact depth
--   (storage.foldername(name))[1] = 'messages'      the namespace segment
--   is_conversation_participant((storage.foldername(name))[2])
--
-- array_length returns NULL for a path with no folder segments, and NULL = 3
-- is NULL, not true -- so a bare filename is denied.  A deeper path yields 4+
-- and is denied.  No branch of any predicate can raise.
--
-- `(SELECT auth.uid())::text` rather than 029's plain `auth.uid()::text`: the
-- scalar-subquery form is evaluated once as an InitPlan instead of once per
-- candidate row.  Same value, same type, same result; noted because it is a
-- deliberate departure from the 029 precedent this file otherwise follows.
--
-- CONSEQUENCE FOR ANY OBJECT ALREADY IN THE BUCKET, stated explicitly.  The
-- client's previous path was `messages/<uid>/<file>` -- two folder segments,
-- not three.  Under these policies such an object fails the depth assertion
-- for SELECT *and* for DELETE, so it becomes unreadable and, more importantly,
-- UNDELETABLE BY ANY end user; only a service-role/admin path can remove it.
-- Whether any such object exists is item B.6 of the evidence set and is
-- currently BLOCKED (no credential).  It MUST be answered before this
-- migration is applied: if the bucket is empty the point is moot, and if it is
-- not, a data disposition has to be decided first.  Deliberately no cleanup is
-- attempted here -- a migration that deletes user media without an explicit
-- ruling is out of scope for 3A-10.
-- ---------------------------------------------------------------------------

-- Read: any participant of the conversation.  Segment [3] is NOT consulted --
-- the recipient must be able to read what the other party sent.
CREATE POLICY "chat media read by conversation participants"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = 'messages'
    AND public.is_conversation_participant((storage.foldername(name))[2])
  );

-- Upload: a participant of the conversation, into their OWN uid segment.
-- The [3] clause is what stops one participant writing into the other's
-- folder and so mislabelling authorship.
CREATE POLICY "chat media upload by conversation participants"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat-media'
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = 'messages'
    AND public.is_conversation_participant((storage.foldername(name))[2])
    AND (storage.foldername(name))[3] = (SELECT auth.uid())::text
  );

-- Delete: the uploader only.  This is deliberately NOT symmetric -- it is the
-- storage analogue of the restriction I-NOT-04 / H-19 says the messages UPDATE
-- policy is missing, and it is also exactly the authorization the client needs
-- to clean up its own object when the subsequent message insert fails.
CREATE POLICY "chat media delete by uploader"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND array_length(storage.foldername(name), 1) = 3
    AND (storage.foldername(name))[1] = 'messages'
    AND public.is_conversation_participant((storage.foldername(name))[2])
    AND (storage.foldername(name))[3] = (SELECT auth.uid())::text
  );

-- NO UPDATE POLICY IS CREATED FOR chat-media, AND THAT IS DELIBERATE.
-- Chat media is immutable once sent.  With RLS enabled and no UPDATE policy,
-- every UPDATE on a chat-media object is denied, including an upsert that
-- would overwrite an existing object.  The client must keep upsert:false.
-- Do not add one to "make an upload work" -- an upload is an INSERT.

COMMIT;
