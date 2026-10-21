# DEC-3A-10 · Pre-reconciliation evidence set — 2026-09-09

Captured under **Ruling A** (owner, 2026-09-09), which requires the
[`DEC-3A-10`](DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md) §2.3 evidence set to be preserved
**before** migration 130 is edited.

**Nothing in this file was obtained by contacting any environment.** No SQL was executed, no
network request was made, and neither QA `eyqtldjqpgpljlqvpowh` nor production
`nxdbooufqzkpslkcogxc` was contacted by the session that wrote it. Ruling A's boundary
prohibits executing SQL against QA, and no QA database credential is available to this session
in any case.

---

## Part A — captured

### A.1 Live QA facts (provenance: relayed by the product owner)

**Provenance, stated precisely.** These facts were **relayed in prose by the product owner**
from a credentialed `psql` session on QA and are treated as authoritative for this task on the
owner's instruction. **This session did not observe the raw `psql` transcript**, and this file
is therefore *a record of what was relayed*, not a verbatim capture.
`COWORK_ENGINEERING_GOVERNANCE.md` §5 forbids converting an inference into live verification;
the distinction is recorded here rather than elided. **The verbatim transcript should be
attached to this file by the owner** — see B.0.

| # | Fact as relayed |
|---|---|
| 1 | `supabase_migrations.schema_migrations`: `max(version) = 129`; rows for `130` = **0**; versions 125–129 present |
| 2 | `storage.buckets`: `progress-photos` → **private**; `chat-media` → **private** |
| 3 | Four `chat-media` policies exist on `storage.objects` despite 130 not being ledgered: `conversation participants delete chat media`, `… read chat media`, `… update chat media`, `… upload chat media` |
| 4 | All four carry the authorization shape `shares_conversation_with(((storage.foldername(name))[1])::uuid)` |
| 5 | App upload path in `chat_screen.dart` is `messages/$uid/$timestamp.$ext` |
| 6 | The first path segment is therefore the literal `messages`, not a uuid — a path/policy contract mismatch |
| 7 | `public.shares_conversation_with(target_user uuid)` exists: `SECURITY DEFINER`, owner `postgres`, `STABLE`, `search_path=public`; checks whether `auth.uid()` and `target_user` are the participants of a `public.conversations` row |
| 8 | `public.conversations`: `id uuid NOT NULL`, `participant_1 uuid NULL`, `participant_2 uuid NULL`, `last_message text NULL`, `last_message_at timestamptz NULL`, `created_at timestamptz NULL` |
| 8 | `public.messages`: `id uuid NOT NULL`, `conversation_id uuid NULL`, `sender_id uuid NULL`, `content text NOT NULL`, `is_read boolean NULL`, `sent_at timestamptz NULL`, `metadata jsonb NULL` |
| 9 | RLS enabled on `conversations` and `messages` |
| 10 | `messages` RLS is conversation-based: participants read through conversation membership; authenticated users insert where `sender_id = auth.uid()`; participants may mark read |
| 11 | The app uploads chat media **before** the message row exists, and uses `getPublicUrl()` for chat media although `chat-media` is private |

### A.2 Repository state at capture (locally derived, no network)

| Item | Value |
|---|---|
| `git rev-parse HEAD` | `bbe0448ff4722b843324de9e888b00302f051b1e` |
| Branch | `chore/qa-environments-secure-ai-backend` |
| `git status --porcelain` | ` M apps/mobile/test/unit/product_contract_guard_test.dart`<br>` M supabase/expected_applied.json`<br>`?? docs/decisions/`<br>`?? supabase/migrations/130_private_storage_buckets.sql` |
| **`sha256` of `130_private_storage_buckets.sql` AS AUTHORED (pre-rewrite)** | **`01ecdc92393664fb25b415f889c6940f28e12e90cf1c451ffb4974e347be39b5`** |
| Size / lines, as authored | 2911 bytes · 102 lines · mtime 2026-09-01 14:51 |
| Migration 130 tracking state | **untracked** — never committed, no git history. Gate 0.7 is in violation while this holds |
| `expected_applied.json` declaration for QA | `applied_through: "129"`, `excluded: []`, `pending: { "130": … }` — *(uncommitted working-tree modification)* |

The pre-rewrite text of migration 130 is preserved by that hash and is reproduced verbatim in
[`DEC-3A-10`](DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md) §1 and §3 for the predicate, and in
full below for the policy names that must be dropped:

```
conversation participants read chat media
conversation participants upload chat media
conversation participants update chat media
conversation participants delete chat media
```

### A.3 Local tooling posture

`psql`, `pg_ctl` and `postgres` are **not** on this machine's `PATH`. The `supabase` CLI is
present at `/opt/homebrew/bin/supabase`, and was **not** invoked — every useful invocation
(`migration list --linked`, `db dump`) contacts the linked project, which Ruling A prohibits.

---

## Part B — BLOCKED, not captured

`COWORK_ENGINEERING_GOVERNANCE.md` §5: *"If credentials are unavailable, do not work around the
restriction. Mark the verification **BLOCKED**. Do not convert an inference into live
verification."* Each item below is **BLOCKED**, with the exact read-only statement that would
capture it. **None was executed.**

| §2.3 item | Status | Exact read-only statement |
|---|---|---|
| 1 · verbatim `psql` transcript | **BLOCKED** — relayed in prose only (A.1). Owner to attach | *(attach the session transcript)* |
| 2 · ledger rows | **BLOCKED** | `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 20;` |
| 3 · bucket rows | **BLOCKED** | `SELECT id, name, public, created_at FROM storage.buckets WHERE id IN ('chat-media','progress-photos');` |
| 4 · **full policy text** | **BLOCKED — the highest-value missing item** | `SELECT polname, cmd, roles, qual, with_check FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE '%chat media%';` |
| 5 · function definition | **BLOCKED** | `SELECT pg_get_functiondef(p.oid), p.proowner::regrole, p.provolatile, p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='shares_conversation_with';` |
| 6 · **object count under the defective contract** | **BLOCKED — decides whether a data disposition is also needed** | `SELECT count(*) FROM storage.objects WHERE bucket_id='chat-media';` and `SELECT name FROM storage.objects WHERE bucket_id='chat-media' LIMIT 50;` |
| 7 · CLI ledger view | **BLOCKED** | `supabase migration list --linked` |
| 8 · git/file pins | **CAPTURED** (A.2) | — |
| 9 · timestamp/actor/mechanism of the out-of-band apply | **BLOCKED, and expected to remain partly undeterminable** | `SELECT id, created_at, updated_at FROM storage.buckets WHERE id IN ('chat-media','progress-photos');` bounds *when*. Postgres retains no authorship for `CREATE POLICY`, so **who** and **by what mechanism** are very likely unrecoverable |

**On item 9.** If the actor cannot be determined, that must be recorded as the finding rather
than left blank. `QA_CLOSURE_STANDARD.md` §7: residue *"is not only untidy; it is
indistinguishable from an intrusion."* An unattributable schema write to QA is itself an
ENV-class finding, and it is the reason item 6 matters — objects written under the defective
contract, if any exist, were written by an actor this repository cannot name.

**Item 6 is a live blocker on the next authorization**, not on this task: the rewritten
migration changes only policy, and whether existing `chat-media` objects must be migrated,
deleted or left in place cannot be decided without knowing whether any exist. See
[`DEC-3A-10`](DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md) §10.

---

## Part C — verbatim text of migration 130 AS AUTHORED (pre-rewrite)

**This is the only surviving copy.** Migration 130 was never committed, so it has no git
history; the rewrite authorized by Ruling A overwrites it in place and this section is the
sole record of what it said. Reproduced byte-for-byte.

`sha256 = 01ecdc92393664fb25b415f889c6940f28e12e90cf1c451ffb4974e347be39b5`

```sql
-- Wave 3A / Task 3A-10
-- H-04 + H-05
--
-- Create the two private Storage buckets required by the mobile app.
-- Both buckets contain sensitive media and MUST remain non-public.
--
-- progress-photos:
--   Existing owner/coach RLS is supplied by migration 029.
--
-- chat-media:
--   Access is restricted to authenticated users who share the
--   conversation represented by the storage path.

INSERT INTO storage.buckets (id, name, public)
VALUES ('progress-photos', 'progress-photos', false)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = EXCLUDED.public;

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', false)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = EXCLUDED.public;

-- ---------------------------------------------------------------------------
-- chat-media authorization
-- ---------------------------------------------------------------------------
--
-- Storage paths are expected to identify the conversation/participant
-- target in the application contract. Access is granted only when the
-- authenticated caller shares a conversation with that target user.
--
-- The authorization primitive already exists in migration 102:
--   public.shares_conversation_with(target_user uuid)
--
-- It is SECURITY DEFINER and evaluates the caller's membership against
-- public.conversations without exposing conversation rows.

DROP POLICY IF EXISTS "conversation participants read chat media"
  ON storage.objects;

CREATE POLICY "conversation participants read chat media"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND public.shares_conversation_with(
      ((storage.foldername(name))[1])::uuid
    )
  );

DROP POLICY IF EXISTS "conversation participants upload chat media"
  ON storage.objects;

CREATE POLICY "conversation participants upload chat media"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'chat-media'
    AND public.shares_conversation_with(
      ((storage.foldername(name))[1])::uuid
    )
  );

DROP POLICY IF EXISTS "conversation participants update chat media"
  ON storage.objects;

CREATE POLICY "conversation participants update chat media"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND public.shares_conversation_with(
      ((storage.foldername(name))[1])::uuid
    )
  )
  WITH CHECK (
    bucket_id = 'chat-media'
    AND public.shares_conversation_with(
      ((storage.foldername(name))[1])::uuid
    )
  );

DROP POLICY IF EXISTS "conversation participants delete chat media"
  ON storage.objects;

CREATE POLICY "conversation participants delete chat media"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND public.shares_conversation_with(
      ((storage.foldername(name))[1])::uuid
    )
  );
```

---

## Part D — capture attempt, 2026-09-09 · **BLOCKED**

Owner authorized a read-only capture of evidence items B.6 (object count), B.6b (up to 50
object names) and B.4 (full `chat-media` policy `qual` / `with_check`), to be run as:

```
psql "$QA_DB_URL" \
  -c "SELECT count(*) FROM storage.objects WHERE bucket_id='chat-media';" \
  -c "SELECT name FROM storage.objects WHERE bucket_id='chat-media' LIMIT 50;" \
  -c "SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE '%chat media%';"
```

**The command was not executed. It could not be.** The agent session has no way to run it:

| Precondition | State |
|---|---|
| `psql` binary | **absent** — not on `PATH`, not at `/opt/homebrew/opt/libpq/bin`, `/usr/local/opt/libpq/bin`, or `/Applications/Postgres.app/…` |
| `$QA_DB_URL` | **not set** in the agent's environment |
| Any `QA_*` / `SUPABASE_*` / `PG*` / `DATABASE_*` variable | **none present** |
| The owner's credentialed terminal | **readable, not drivable.** The agent can read that panel's contents but cannot execute in it. At the time of this attempt the panel showed only a shell prompt — the command had not been run there |

**No workaround was attempted, deliberately.** `COWORK_ENGINEERING_GOVERNANCE.md` §5: *"If
credentials are unavailable, do not work around the restriction. Mark the verification
**BLOCKED**. Do not convert an inference into live verification."* Specifically **not** done:
`psql` was not installed (a system modification, unauthorized); the `supabase` CLI was not
substituted (it was not what was authorized, and it cannot answer these three questions); and
no PostgREST/anon-key path was used (the anon role cannot read `pg_policies` at all, so any
result from it would have been a different, weaker fact wearing this evidence item's name).

**One point of column naming, confirmed rather than guessed.** The owner's instruction
anticipated that the live view might expose `polname` instead of `policyname`. It does not:
`pg_policies` (the view) exposes `schemaname, tablename, policyname, permissive, roles, cmd,
qual, with_check`; `polname` is a column of `pg_policy` (the catalog table), which the query
does not select from. **The command is correct exactly as written and needs no adjustment.**

**Items B.4 and B.6 therefore remain BLOCKED**, and B.6 remains a hard precondition on applying
migration 130 — see [`DEC-3A-10`](DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md) §10.3. When the
owner runs the command, its output should be appended here as **Part E**, marked as *directly
observed live evidence* — a stronger provenance class than Part A's relayed facts.

---

## Part E — DIRECTLY OBSERVED live QA evidence, post-application (2026-09-09)

**Provenance class: directly observed** by the agent session through
`supabase db query --linked` (Management API, read-only unless stated) and the Storage/Auth
REST surface with the committed anon key and the committed `p1-*` fixture identities — a
stronger class than Part A's relayed facts. Target `eyqtldjqpgpljlqvpowh` (12Circle QA),
verified by `qa-db-reset.sh --check-only` before any write. Production not contacted.

### E.0 Application (owner-executed; the agent's own attempt was denied by the harness)

`supabase db push --linked --yes` — *"Applying migration 130_private_storage_buckets.sql… NOTICE:
policy "chat media read by conversation participants" … does not exist, skipping"* (×3, the
convergent drops of the canonical names) *"… Finished supabase db push."* Dry run beforehand
listed exactly one migration. The out-of-band apply is now dated: **`storage.buckets.created_at
= 2026-09-02 01:09:22Z`** for both buckets — evidence item 9, previously unrecoverable.

### E.1 Ledger

`SELECT version … ORDER BY version DESC LIMIT 3` → **130, 129, 128**. `supabase migration list
--linked` → `130 | 130 | 130` (Local · Remote · Time). **No `schema_migrations` row was written
by any means other than `db push`.** No migration 131 exists locally or remotely.

### E.2 Buckets

| id | public | created_at |
|---|---|---|
| `chat-media` | **false** | 2026-09-02 01:09:22Z |
| `progress-photos` | **false** | 2026-09-02 01:09:22Z |

`SELECT count(*) FROM storage.objects WHERE bucket_id='chat-media'` → **0** (before probes, and
again after cleanup).

### E.3 Policies — full live expressions (`pg_policies`, every policy naming `chat-media`)

| policyname | cmd | roles | expression |
|---|---|---|---|
| `chat media read by conversation participants` | SELECT | `{authenticated}` | USING `((bucket_id = 'chat-media'::text) AND (array_length(storage.foldername(name), 1) = 3) AND ((storage.foldername(name))[1] = 'messages'::text) AND is_conversation_participant((storage.foldername(name))[2]))` |
| `chat media upload by conversation participants` | INSERT | `{authenticated}` | WITH CHECK `(… same four clauses … AND ((storage.foldername(name))[3] = (( SELECT auth.uid() AS uid))::text))` |
| `chat media delete by uploader` | DELETE | `{authenticated}` | USING `(… same four clauses … AND ((storage.foldername(name))[3] = (( SELECT auth.uid() AS uid))::text))` |

**No UPDATE policy** references `chat-media` (query matched on name *and* on predicate text).
The four obsolete names (`conversation participants read/upload/update/delete chat media`)
→ **0 rows**. The only `::text` casts are of the literal `'chat-media'`, the literal
`'messages'` and of `auth.uid()`; **no path segment is cast to uuid.**

### E.4 Helper function

`public.is_conversation_participant(conversation text)` — `provolatile = s` (STABLE),
`prosecdef = true` (SECURITY DEFINER), `proconfig = {search_path=public, pg_temp}`, owner
`postgres`, ACL `{postgres=X, authenticated=X, service_role=X}` — no PUBLIC, no anon.
`pg_get_functiondef` matches the migration text exactly (`c.id::text = conversation`).
`shares_conversation_with(uuid)` is unchanged: STABLE, SECURITY DEFINER, `search_path=public`,
same ACL shape.

### E.5 Repository live suites

- **FG-1** `function-search-path.sql` (SEC-09 live half): **SP-1…SP-5 all PASS** with the new
  definer function present — 0 unpinned, 0 EXECUTE to PUBLIC/anon.
- **ENV-3 live ledger** (`env3-live-check.mjs` → `db query`): L-1 0 · **L-2 FAIL — applied but
  undeclared: 130** · L-3 0 · L-4 0 holes in 000–130 · **L-5 FAIL — 131 rows vs 130 declared**.
  **Expected and correct:** `expected_applied.json` still declares 130 `pending`, and this pass
  was instructed not to edit it. The repository's own precedent (`352ee68`, *"move QA frontier to
  129 after application"*) is a follow-up commit moving `applied_through` to 130. Until that
  lands, CI's live ledger step will fail on L-2/L-5 — by design, not by defect.

### E.6 Storage contract probes — `d07-chat-media-storage.mjs`, live, **39/39 PASS**

Identities: A = `p1-coach` (uploader), B = `p1-victim` (recipient), C = `p1-attacker`
(non-participant), plus anon. One fixture conversation A↔B created per run via PostgREST.

| Invariant | Observed |
|---|---|
| A uploads `messages/<conv>/<A>/<file>` | **200** |
| B uploads into A's uid segment | **400** `42501/AccessDenied` "new row violates row-level security policy" |
| C (non-participant) uploads, even into own segment | **400** AccessDenied |
| Old two-segment `messages/<uid>/<file>` | **400** AccessDenied |
| Anonymous upload | **400** |
| A reads own; **B reads A's (symmetric read)** | **200 / 200** |
| C reads | **400** `NoSuchKey` (invisible under RLS) |
| Anonymous read; `/object/public/` form | **400 / 400** |
| B creates a signed URL; signed URL serves without JWT | **200 / 200** |
| C creates a signed URL | **400** NoSuchKey |
| A overwrites own object with `x-upsert: true` | **400** AccessDenied — content unchanged on re-read |
| B overwrites A's; plain re-upload to existing path | **400 / 400** |
| Malformed: non-uuid conv, non-uuid uid, 4-deep, 2-deep, wrong namespace, bare file, uuid+garbage (both segments) | **all 400 AccessDenied — no 5xx, no `22P02`, no "invalid input syntax"** |
| LIST of the conversation prefix still works after all malformed attempts | **200** (the original one-bad-object-breaks-the-bucket defect is closed) |
| B deletes A's; C deletes A's | **400 / 400**, object still listed for A |
| A deletes own | **200**, then absent from a DB-backed list |

Run 1 recorded two false negatives on "proved by a read": a download of a just-deleted
object answered 200 from the CDN while the DB-backed list already showed zero and
`storage.objects` counted 0. The suite's proof-of-existence was changed to LIST (database-backed);
run 2 was 39/39. A "hostile" path containing `DROP TABLE` was answered by Cloudflare's WAF
(403 HTML) rather than by our policy and was replaced by uuid-with-trailing-garbage cases,
which exercise the text comparison itself.

### E.6a Run 3 (owner ruling, review mode) — **41/41 PASS**, hostile case restored and labelled

Per the owner's Decision 1 the hostile `messages/'; DROP TABLE x; --/<A>/bad.txt` case was
**restored alongside** the two uuid-with-trailing-garbage cases, as its own category. Observed:
upload **403**, read **403**, both classified by the suite as **"WAF-layer denial; request did not
reach Storage policy"** (HTML body from Cloudflare). **This case does not prove Storage-policy
evaluation and is not labelled as if it did.** The policy's text comparison is proven by the two
garbage-suffix cases, whose denial bodies carry Postgres' *"new row violates row-level security
policy"* — a message that exists only if the policy ran.

**Diagnostic header capture on the post-delete GET** (not an assertion): `GET
/object/authenticated/chat-media/<pathA>` **after** A's successful DELETE and after the
database-backed LIST showed the object gone → **`200`, `cf-cache-status: HIT`**, `age` absent,
`cache-control: no-cache`. That is the direct evidence that the run-1 "still readable" result was
a CDN cache hit and not a policy failure. Classification for this file: **observed CDN behaviour**,
distinct from Storage-policy behaviour (E.3, E.6) and WAF-layer behaviour (above).

Fixture conversation `9afb8d85-…` removed via `db query` (guarded, `NOT EXISTS` messages) → 1
deleted; re-read → fixture conversations **0**, `chat-media` objects **0**, ledger max **130**.

### E.7 Cleanup — closure standard §7, proved by a read

Every object the suite created was removed by its uploader and confirmed absent by LIST.
`storage.objects` for `chat-media` → **0**. The two fixture conversation rows
(`8889bf4b-…`, `89150dcc-…`; users have no DELETE policy on `conversations`) were removed via
`db query` with a guard on the exact participant pair and `NOT EXISTS` messages → **2 deleted**;
re-read → **0**; any conversation between `p1-*` identities → **0**. Nothing else was written.

---

## Status

**Migration 130 applied to QA by the owner (Ruling A + application authorization, 2026-09-09).**
Agent writes to QA in this pass, all fixture-scoped and all proved removed by a read (E.7): probe
objects in `chat-media`, two `conversations` rows. No ledger row was written by any means other
than `db push`. Production not contacted. Nothing committed, nothing pushed.
