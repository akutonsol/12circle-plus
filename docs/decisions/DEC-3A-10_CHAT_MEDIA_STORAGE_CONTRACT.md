# DEC-3A-10 · Chat-media storage contract

| | |
|---|---|
| **Status** | **APPLIED TO QA AND IMPLEMENTED (owner-authorized pass, 2026-09-09) — awaiting commit authorization.** Ruling A (§9.1) → 130 rewritten in place (§10) → applied by the owner via `supabase db push` → live-verified (§12, evidence Part E) → Flutter client conformed → guards inverted/added → 789/789 Flutter, 41/41 live storage probes (owner review 2026-09-09). **Not done / not authorized:** commit, push, `expected_applied.json` frontier move, migration 131, `WRK-07`, `EC-11`, `EC-05`, Wave 3B. |
| **Date** | 2026-09-09 |
| **Wave / task** | Wave 3A, task **3A-10** (migration **130**) |
| **Findings** | `H-04` (chat-media bucket), `H-05` (progress-photos bucket), and a **new defect** found by this analysis: the chat-media authorization predicate does not match the application's storage path |
| **Related** | `I-NOT-01` (migration 129, `messages.metadata`), `I-NOT-04`/`H-19` (P1, open — a participant can rewrite the other party's message), `I-NOT-05` (no UNIQUE on the conversation participant pair, migration 131), `ENV-3` (`supabase/expected_applied.json`), Gate **1.6** (`RELEASE_GATES.md`) |
| **Owners implicated** | DB + SEC (migration 130), JOURNEY (chat client), QA (guards), ARCH (`docs/decision-log.md` pointer, migration-number authority) |

> **Naming note.** `docs/decisions/` did not exist before this memo. The filename follows the
> two conventions this repository already has: `SCREAMING_SNAKE_CASE.md` for governance and
> decision artifacts under `docs/`, and the wave task id (`3A-10`) used by
> `MASTER_REMEDIATION_WAVES.md` §0.2 and by the migration headers. A pointer row in
> `docs/decision-log.md` is **not** written here — that file is ARCH-owned
> (`COWORK_FILE_OWNERSHIP.md` §3) and adding to it needs orchestrator authorization.

---

## 1. Problem

Migration `130_private_storage_buckets.sql` creates the two private buckets the mobile app
already uses and authorizes `chat-media` with

```sql
public.shares_conversation_with( ((storage.foldername(name))[1])::uuid )
```

The application uploads chat photos to

```text
messages/<uploader-uid>/<epoch-millis>.<ext>
```
`apps/mobile/lib/features/messaging/presentation/chat_screen.dart:146`

`storage.foldername()` returns every path segment **except** the filename, so for that path
`[1]` is the literal string `messages`. The policy therefore casts `'messages'` to `uuid`.

The two halves of the contract — the path the client writes and the identity the policy
reads — were authored independently and never reconciled. Beyond the immediate mismatch,
the identity the policy names (**a user**) is not the identity the invariant requires
(**a conversation**), so correcting the segment index alone would not make the policy correct.

---

## 2. Live QA evidence (authoritative, credentialed psql session, 2026-09-09)

| Fact | Value |
|---|---|
| `supabase_migrations.schema_migrations` | `max(version) = 129`; **`130` count = 0**; 125–129 present |
| `storage.buckets` | `progress-photos` → **private**; `chat-media` → **private** |
| `storage.objects` policies on `chat-media` | four, named exactly as migration 130 names them: *conversation participants* **read / upload / update / delete** *chat media* |
| Predicate shape, all four | `shares_conversation_with(((storage.foldername(name))[1])::uuid)` |
| `public.shares_conversation_with(target_user uuid)` | exists; `SECURITY DEFINER`, owner `postgres`, `STABLE`, `search_path=public`; tests `auth.uid()` and `target_user` against the participant pair of a `public.conversations` row |
| `public.conversations` | `id uuid NOT NULL`, `participant_1 uuid NULL`, `participant_2 uuid NULL`, `last_message text`, `last_message_at timestamptz`, `created_at timestamptz` |
| `public.messages` | `id uuid NOT NULL`, `conversation_id uuid NULL`, `sender_id uuid NULL`, `content text NOT NULL`, `is_read boolean`, `sent_at timestamptz`, **`metadata jsonb`** (added by 129) |
| RLS | enabled on `conversations` and `messages` |
| `messages` policies | read via conversation membership; insert requires `sender_id = auth.uid()`; participants may mark read |

### 2.1 Migration-history divergence — recorded, NOT repaired

Migration 130 is **not ledgered**, yet **its objects exist live**: both buckets are private
and all four of its policies are present, under its exact policy names. The DDL of 130
reached QA out of band, without a `schema_migrations` row.

`supabase/expected_applied.json` currently declares `130` as `pending` — "authored above the
frontier, deliberately not yet applied". Against the **ledger** that declaration is true.
Against **reality** it is false: the objects are there. The ENV-3 static guard reconciles the
declaration against the authored tree, and the live half (declaration vs. `schema_migrations`)
is not implemented, so **both guards stay green while QA holds unledgered, wrongly-shaped
security policy**. That gap is recorded here as an ENV-class finding.

**No repair was performed and none is proposed in this memo.** The ledger was not touched,
no `schema_migrations` row was inserted, no live policy was altered, no bucket was recreated,
`supabase db push` was not run and migration history was not repaired. Reconciling the
divergence is an owner decision with its own authorization.

### 2.2 Governance gate — the ledger divergence *(added 2026-09-09, owner-directed)*

The owner directed that this divergence be resolved as its own governance question before
any schema change. Answered below **only from repository documents plus the §2 live evidence.**
No repair mechanism is invented here, and none is proposed.

**(1) What the repository considers authoritative.** The ENV-3 amendment
(`MASTER_REMEDIATION_REGISTRY.md` §ENV-3) defines exactly three terms, and they are not
interchangeable:

| Term | Source of truth |
|---|---|
| `authored` | the files in `supabase/migrations/` |
| `declared` | `supabase/expected_applied.json` |
| `observed` | `supabase_migrations.schema_migrations` — **"the only authority on what is applied"** |

`expected_applied.json`'s own header states it plainly: *"This file is NOT a ledger.
`supabase_migrations.schema_migrations` is the ledger and the only authority on what IS
applied."* **Authoritative migration history is therefore the ledger, and nothing else.**
The file tree is authorship; the manifest is intent.

**(2) What live QA currently contains.** Both buckets private; all four `chat-media` policies
present under migration 130's exact policy names, carrying 130's defective predicate; ledger
`max(version) = 129` with no row for 130. QA holds **130's DDL without 130's ledger row.**

**(3) Why the state is divergent.** 130's DDL was executed against QA out of band — outside
the migration mechanism that writes the ledger row. `COWORK_ENGINEERING_GOVERNANCE.md` §18
names this exact hazard in advance: *"Never assume a migration applied manually to QA is
automatically represented in remote migration history."* `QA_WORKSTREAM_L…` §122 records the
same mechanism as the programme's original cause: every paste script *"applies schema
**without writing to `supabase_migrations.schema_migrations`**. The ledger and the database
diverge by construction."* This is a recurrence of that class, not a new phenomenon.

**The divergence is currently invisible to every existing guard, and that is provable.**
ENV-3's live ledger check has five detectors: L-1 `declared − observed`, L-2 `observed −
declared` (*"the signal that catches an out-of-band apply"*), L-3 stale rows, L-4 holes, L-5
count. Declared says 130 is `pending`; observed says 130 is absent. **They agree**, so
L-1…L-5 all report 0 and the check is green. Every detector compares the ledger to the
manifest; **no detector compares either to the live catalog.** An out-of-band apply that also
skipped the ledger falls in the blind spot between them. That is a specification gap in
ENV-3 of the same kind the 2026-08-25 amendment already found in its original *Tests* field —
and ENV-3 is `VERIFIED_CLOSED`, so the gap sits under a closed finding.

**(4) Can it be safely reconciled by reworking 130 in place?** **Technically yes; and that is
not the same as permitted.** Technically: 130 opens every policy with `DROP POLICY IF EXISTS`,
so a corrected 130 is convergent — applying it to QA replaces the defective policies with the
canonical set regardless of what is there now. That convergence depends on 130 **not** being
ledgered as applied, which it is not. But see (5): technical convergence is not authorization,
and the §7.1 reasoning of the first draft of this memo overstated the basis. It is corrected
below.

**(5) Repository conventions bearing on that approach — one of them prohibitive.**

- **`QA_CLOSURE_STANDARD.md` §8, working-tree discipline:** *"**Never rewrite a migration in
  place unless the wave plan explicitly authorizes it.** **Prefer additive forward
  migrations.**"* The rule is **unconditional**. It carves out no exception for a migration
  that is untracked, uncommitted, or unledgered. **`MASTER_REMEDIATION_WAVES.md` §0.2 assigns
  130's contents to task 3A-10; it does not authorize rewriting 130.** No document in this
  repository authorizes it. **The approach is therefore currently prohibited, and the first
  draft of §7.1 was wrong to reason from 130 being untracked/unledgered to permission.
  That inference is withdrawn.**
- **Gate 0.7** (`RELEASE_GATES.md`) requires `git status --porcelain supabase/migrations` to be
  empty. 130 is untracked, so **the tree is in violation of Gate 0.7 right now** and cannot
  merge to `main` in this state.
- **Gate 0.8** requires *"No tracked migration modified relative to its merge-base."* **The
  moment 130 is committed, editing it becomes a Gate 0.8 violation.** Commit order therefore
  decides which remedies remain available, and committing 130 as-authored closes the
  in-place option permanently.
- **Gate 0.9 / `check-migration-hygiene.sh`:** the authored sequence must stay contiguous and
  *"Do not renumber an existing migration to close a gap."*
- **`COWORK_ENGINEERING_GOVERNANCE.md` §7:** an adjacent defect is fixed *"only if it is
  necessary, authorized, and within boundary; otherwise create a new finding."* §19: *"If
  blocked, report the blocker rather than improvising."*

**(6) Do `expected_applied.json` semantics support `pending` while the objects are live?**
**Yes — literally, and that is precisely the defect.** Its four rules define `pending` as
*"authored versions ABOVE the frontier, deliberately not yet applied"*, and every rule is
expressed against the ledger. Measured against the ledger the declaration is **true**. The
manifest has **no term for the live catalog**, so it cannot be false about it and cannot
detect it. The declaration is simultaneously **valid and materially misleading**, and the
manifest is not the instrument that can fix this. Amending the `130` entry to narrate the
divergence would be a reason-text change only; it would not change the guard's verdict, and
`expected_applied.json` is not modified by this memo.

**(7) Correct governance treatment before any schema change.** In order:

1. **Preserve the evidence** (§2.3) — the divergence is currently unreproducible from the
   repository alone.
2. **Record it as a finding**, because §7 requires a discovered adjacent defect to be recorded
   and classified rather than absorbed into the current task.
3. **Obtain the owner ruling** on which reconciliation path is taken.
4. **Only then** touch migration 130.

The tree must not be committed ahead of step 3: committing 130 as-authored triggers Gate 0.8
and forecloses the in-place path (see (5)).

**(8) Is manual ledger insertion available?** **No. The repository forbids it, in terms, twice,
and the ban is load-bearing.**

- `MASTER_REMEDIATION_REGISTRY.md` §ENV-3: *"**Explicitly: a committed-but-pending migration
  is never inserted into `schema_migrations` to satisfy this check.**"*
- `supabase/expected_applied.json`, the `130` gate text already in the working tree: *"Its
  `schema_migrations` row must be created by migration application; **it must never be
  inserted ahead of application to satisfy the manifest.**"*

A **documented repair mechanism does exist** and must not be misapplied here. **W1-T3**
(2026-08-25, registry §ENV-3) ran `supabase migration repair --status applied 113…122 --linked`
— owner-authorized, QA only, target independently confirmed from five agreeing local sources,
before/after captured, diff verified as exactly ten rows. Its precondition is that the
migrations being repaired are **correct and genuinely applied**. Migration 130 is genuinely
applied but **defective**, so the precedent does not extend to it, and W1-T3's own stated
reason for **excluding** migration 123 from that repair applies to 130 with full force:
*"Marking it applied would cause a later `supabase db push` to skip it, so the ENV-2 forward
carry would never reach any environment."* **Ledgering 130 would canonicalize the defective
policy as the applied state and make the corrected 130 unreachable.** It is the one action
that would convert a recoverable divergence into a permanent one.

**(9) Classification — a combination, not one label.** All three, for different parts:

| Instrument | What it carries | Why |
|---|---|---|
| **This decision memo (ADR)** | The storage contract (§6) **and** the ruling on how the divergence is reconciled | §5's *"prefer additive forward migrations"* is departed from only by an explicit, recorded decision |
| **A new finding** — ENV-class, sibling to `I-MIG-01`/`ENV-3` | (a) 130's DDL live and unledgered; (b) **ENV-3's live check cannot detect a ledger-skipping out-of-band apply** | §7 requires a discovered adjacent defect to be recorded and classified. (b) is the more durable defect: it is the missing detector, and it sits under a `VERIFIED_CLOSED` finding |
| **A durability-guard gap, recorded not fixed** | `chat-media`'s policies have no standing guard | `migration-durability-guard.mjs` tracks **function** properties only. Registry §7.12 already records *"RLS policies have no durability guard"* as a retained limitation of `F-J-12`. The same limitation covers these policies |
| **Not** a release-gate exception | — | Gate **1.6** (*buckets exist and are private*) is **not** being waived, deferred or exempted. It is unmet and stays unmet |

**(10) Authorization required before the next step.** The exact wording the owner must provide is set out verbatim in §9.

### 2.3 Evidence to preserve before any reconciliation

Required before anything changes, because none of it can be reconstructed afterwards and the
repository cannot currently reproduce it:

1. The `psql` transcript already captured, retained verbatim as a dated artifact under `docs/`.
2. `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 20;`
3. `SELECT id, name, public, created_at FROM storage.buckets WHERE id IN ('chat-media','progress-photos');`
4. Full `pg_policies` rows for `storage.objects` where the policy name matches the four
   `chat-media` names — `polname`, `cmd`, `roles`, and the **complete `qual` / `with_check`
   text**, so the deployed predicate is preserved exactly as it stands.
5. `pg_get_functiondef` for `public.shares_conversation_with(uuid)`, plus its owner, volatility
   and `proconfig`.
6. `SELECT count(*) FROM storage.objects WHERE bucket_id = 'chat-media';` — establishes whether
   any object exists under the defective contract, which decides whether a migration path also
   needs a data disposition.
7. `supabase migration list --linked` output, showing 130 Local-only.
8. `git rev-parse HEAD`, `git status --porcelain`, and the `sha256sum` of the current
   `130_private_storage_buckets.sql`, pinning the exact file text this analysis describes.
9. The timestamp and, if determinable, the actor and mechanism of the out-of-band apply.
   `storage.buckets.created_at` bounds it. **If it is not determinable, record that it is not
   determinable** — an unattributable schema write to QA is itself the finding, and
   `QA_CLOSURE_STANDARD.md` §7 is explicit that residue *"is indistinguishable from an
   intrusion."*

All of items 2–7 are **read-only**. None was executed by this task.

---

## 3. The current broken contract

Three distinct defects, in increasing order of severity.

**(a) Path/policy mismatch — chat media is wholly non-functional.**
`[1]` is `'messages'`, never a uuid. `'messages'::uuid` raises `22P02`
(*invalid input syntax for type uuid*).

**(b) The cast raises rather than denies.**
An error inside a policy predicate aborts the statement; it does not evaluate to false. So
every `chat-media` insert, select, update and delete errors out. Worse, `USING` is evaluated
per candidate row: a single object in the bucket whose first segment is not a uuid makes
**every** list/select against the bucket fail, for **every** user. Migration 029 — the
`progress-photos` precedent in this same repository — deliberately compares as text
(`(storage.foldername(name))[1] = auth.uid()::text`) and therefore denies instead of raising.
130 departs from that precedent without saying why.

**(c) Uploader UID is not conversation authorization — the real security defect.**
This survives any fix to (a) and (b), and it is the reason this memo exists.

`shares_conversation_with(u)` answers *"do the caller and `u` share **some** conversation?"*
It is a **person-to-person** predicate. The invariant requires a **conversation-scoped** one.
With a UID in the path:

- **The uploader cannot upload.** For their own folder the argument is `auth.uid()`, and
  `shares_conversation_with(self)` is true only if a conversation exists with the caller in
  *both* participant slots. It does not, so INSERT is denied.
- **The recipient cannot read what they received.** If the path instead named the *recipient*,
  the recipient's own read evaluates `shares_conversation_with(self)` — false again. The
  predicate is not satisfiable symmetrically for upload and read: no single UID makes both work.
- **Cross-conversation disclosure.** A UID-keyed folder holds *all* of that user's chat media,
  from *every* conversation. `shares_conversation_with` is true if the caller shares **any**
  conversation with the folder owner. A coach who shares a conversation with a client can
  therefore read media that client exchanged with a *different* coach. One shared conversation
  buys the whole folder. This is a genuine confidentiality break, and these are body photographs
  (`QA_WORKSTREAM_H_PRODUCT_INTEGRITY_REPORT.md` H-04: *"form-check photos are body images"*).

**(d) URL strategy contradicts the bucket.** `chat_screen.dart:151` calls `getPublicUrl()` on a
bucket that is private. The URL resolves to a 400/404 for every viewer. Photo messages would
render as broken images even with correct policies.

**(e) Metadata shape is stated three different ways.** The client writes
`{'image_url': <url>}` (`chat_screen.dart:157`); migration 129's `COMMENT ON COLUMN
public.messages.metadata` says the path writes `{"type":"image","url":...}`; the tests assert
`metadata['image_url']` (`spec_community_challenge_test.dart:196`,
`test/widget/message_bubble_test.dart`). No single declaration is authoritative.

**(f) The silent-failure half of H-04 is still open.** `_sendPhoto` ignores
`sendMessage()`'s boolean return (`chat_screen.dart:154`), so a failed insert after a
successful upload shows the user nothing and leaves the object orphaned.

---

## 4. Security invariant

> **Only an authenticated user who is a participant of conversation *C* may upload, read,
> update or delete media associated with conversation *C*.**

Two corollaries this memo treats as binding:

1. **Authorization is conversation-scoped, never person-scoped.** Sharing *a* conversation
   with someone must not grant access to media from their *other* conversations.
2. **The invariant is not weakened to fit the current path.** The path changes.

A third property is adopted deliberately, by analogy to the still-open P1 `I-NOT-04`/`H-19`
(*a conversation participant can rewrite the other party's message text*): **the storage layer
must not ship that defect's twin.** Read is symmetric across participants; **mutation is not** —
only the uploader may remove their own object, and nothing may overwrite one.

---

## 5. Options considered

All four assume the bucket stays private and `shares_conversation_with()` is left untouched
(it is load-bearing for `conversation_participant_profiles` in 102 and for `may_notify()` in
118/129, and nothing here may weaken it).

### Option A — `messages/<user-id>/<file>` *(the shipped path)*

| # | Dimension | Assessment |
|---|---|---|
| 1 | Upload path | `messages/<uploader-uid>/<ts>.<ext>` — as shipped |
| 2 | Policy must extract | `[2]` (a uid). `[1]` is the literal `messages`; today the policy wrongly reads `[1]` |
| 3 | Authorizable before the message row exists | Yes |
| 4 | `conversations` sufficient | Yes for the predicate — but the predicate answers the wrong question |
| 5 | `messages` sufficient | Not consulted |
| 6 | Upload/read/update/delete all safely expressible | **No.** No single UID satisfies both upload and read (§3c). Would need two different predicates keyed on who the uid is, i.e. a per-operation asymmetry the storage layer cannot see |
| 7 | Identity leakage | **Yes** — the path is a user id, and it co-locates every conversation's media in one folder |
| 8 | Current Flutter ordering supports it | Yes (it is the current ordering) |
| 9 | Private-URL app change needed | Yes — `getPublicUrl` → `createSignedUrl` |
| 10 | Migration implications | Index fix + text comparison. Does not repair the identity error |
| 11 | Test implications | Guards would have to encode a rule that is wrong |
| 12 | Races / orphans | Same as any upload-first flow |
| 13 | Compatible with existing RLS model | **No** — `messages`/`conversations` RLS is conversation-scoped; this is person-scoped |

**REJECTED.** It is the defect, not a fix. Cross-conversation disclosure (§3c) is disqualifying
on its own, and the upload/read asymmetry means it cannot even be made to function.

### Option B — `messages/<conversation-id>/<file>`

| # | Dimension | Assessment |
|---|---|---|
| 1 | Upload path | `messages/<conversation-id>/<ts>.<ext>` |
| 2 | Policy must extract | `[1] = 'messages'` (shape assertion) and `[2]` = conversation id |
| 3 | Authorizable before the message row exists | **Yes.** The conversation exists before the picker opens — `_sendPhoto` returns early when `_conversationId == null` (`chat_screen.dart:136`) |
| 4 | `conversations` sufficient | **Yes** — `id` + the participant pair is exactly the membership fact needed |
| 5 | `messages` sufficient | Not consulted for authorization; `metadata` carries the object path |
| 6 | Upload/read/update/delete all safely expressible | **Yes**, one predicate, symmetric for both participants — but it makes *mutation* symmetric too: either participant could delete or overwrite the other's media (the `H-19` twin) |
| 7 | Identity leakage | **No user id in the path.** The conversation id is opaque and already known to both participants; it is not a capability — membership is still checked |
| 8 | Current Flutter ordering supports it | **Yes** — path construction only; no reordering |
| 9 | Private-URL app change needed | Yes |
| 10 | Migration implications | One new `SECURITY DEFINER` membership predicate; four rewritten policies |
| 11 | Test implications | Moderate — see §7.3 |
| 12 | Races / orphans | Upload-first can orphan an object if the insert fails; the object is inert (private, unreferenced) and the uploader can delete it |
| 13 | Compatible with existing RLS model | **Yes** — identical scoping to the `messages` SELECT policy |

**Viable.** Rejected only in favour of C, which adds an integrity property at negligible cost.

### Option C — `messages/<conversation-id>/<uploader-uid>/<file>` — **RECOMMENDED**

| # | Dimension | Assessment |
|---|---|---|
| 1 | Upload path | `messages/<conversation-id>/<uploader-uid>/<ts>.<ext>` |
| 2 | Policy must extract | `[1] = 'messages'`; `[2]` = conversation id (membership); `[3]` = uploader uid (mutation only) |
| 3 | Authorizable before the message row exists | **Yes**, same as B |
| 4 | `conversations` sufficient | **Yes** |
| 5 | `messages` sufficient | **Yes** — not consulted for authorization |
| 6 | Upload/read/update/delete all safely expressible | **Yes, and asymmetrically where that is correct.** Read = any participant. Insert = a participant, into their own uid segment. Delete = the uploader only. Update = **no policy at all** (objects immutable) |
| 7 | Identity leakage | The path carries the uploader's uid. In a 1:1 conversation both parties already know each other, so this discloses nothing new to a reader; it is not co-location — the folder is scoped to one conversation. Cost accepted for the attribution it buys |
| 8 | Current Flutter ordering supports it | **Yes** — both values are in hand at `_sendPhoto` |
| 9 | Private-URL app change needed | Yes |
| 10 | Migration implications | Same as B, plus a `[3]` clause on the write policies and **no** UPDATE policy |
| 11 | Test implications | Same as B plus two negative cases (B cannot delete A's object; B cannot upload into A's segment) |
| 12 | Races / orphans | Same as B; uploader-scoped DELETE is exactly the authorization the failure path needs to clean up after itself |
| 13 | Compatible with existing RLS model | **Yes**, and it is strictly stronger than the `messages` UPDATE policy, whose missing restriction is the open P1 `I-NOT-04` |

### Option D — `messages/<message-id>/<file>`

| # | Dimension | Assessment |
|---|---|---|
| 1 | Upload path | `messages/<message-id>/<ts>.<ext>` |
| 2 | Policy must extract | `[2]` = message id, then resolve message → conversation → participants |
| 3 | Authorizable before the message row exists | **No — this is fatal.** The row is the authorization source, so it must exist first. A client-minted uuid authorizes nothing: the predicate finds no row and denies |
| 4 | `conversations` sufficient | Only transitively, through `messages` |
| 5 | `messages` sufficient | Yes as data, but it forces the ordering inversion in (3) |
| 6 | Upload/read/update/delete all safely expressible | Only by inserting the message first and then mutating it — which routes the attachment through the `messages` UPDATE policy, i.e. straight through open P1 `I-NOT-04` |
| 7 | Identity leakage | No uid in the path |
| 8 | Current Flutter ordering supports it | **No** — requires insert-returning-id, then upload, then update |
| 9 | Private-URL app change needed | Yes |
| 10 | Migration implications | A predicate that reads `messages` from inside a `storage.objects` policy — a second `SECURITY DEFINER` hop across two RLS-protected tables |
| 11 | Test implications | Largest surface, including partial-state cases |
| 12 | Races / orphans | **Worst.** A message row exists announcing an attachment that may never arrive: a permanently broken image in the transcript, visible to the recipient, with no way to distinguish "uploading" from "lost" |
| 13 | Compatible with existing RLS model | Technically yes, structurally worst |

**REJECTED.** It inverts the ordering, depends on the one policy the programme has an open
P1 against, and converts orphaned *objects* (invisible) into orphaned *messages* (visible).

---

## 6. Recommended canonical contract — Option C

### 6.1 Definition

| Element | Decision |
|---|---|
| **Bucket** | `chat-media`, **private** (`public = false`) — unchanged from 130 |
| **Canonical path** | `messages/<conversation_id>/<uploader_uid>/<epoch_millis>.<ext>` |
| **Segments** | `[1]` literal `messages` — namespace + depth assertion · `[2]` `conversations.id` — **the authorization identity** · `[3]` `auth.uid()` of the uploader — attribution and mutation scope · filename — opaque, never parsed by a policy |
| **Authorization identity** | **The conversation**, resolved from segment `[2]`. Never the uploader, never the recipient |
| **Upload (INSERT)** | caller is a participant of `[2]` **and** `[3] = auth.uid()::text` |
| **Read (SELECT)** | caller is a participant of `[2]`. Symmetric; `[3]` is not consulted |
| **Update (UPDATE)** | **no policy — chat media is immutable.** Client keeps `upsert: false`. 130's existing UPDATE policy is dropped and not recreated |
| **Delete (DELETE)** | caller is a participant of `[2]` **and** `[3] = auth.uid()::text` — the uploader only |
| **URL strategy** | `createSignedUrl(path, ttl)` at render time. **Never** `getPublicUrl`. No URL is ever persisted |
| **Upload ordering** | **Upload first, then insert the message.** Authorization needs only the conversation, which exists beforehand; inserting first would create the visible-broken-attachment failure of Option D |
| **Orphan handling** | On a failed insert the client deletes the object it just uploaded (uploader-scoped DELETE authorizes exactly this) and surfaces the failure. Residual orphans are inert: private bucket, unreferenced, participant-scoped. A retention sweep is explicitly **out of scope** |
| **Message metadata** | Stores the **object path**, not a URL: `{"type":"image","bucket":"chat-media","storage_path":"messages/<conv>/<uid>/<file>"}` in `messages.metadata` (the column 129 added). A signed URL expires; persisting one bakes in a dead link and writes a time-limited credential into a row |
| **New column or table** | **None.** `conversations` already carries the participant pair; `messages.metadata` already exists. The only new object is one predicate function |

### 6.2 Why this is the safest option

1. **It matches the invariant literally.** The authorization identity in the path *is* the
   conversation. §4's corollary 1 holds by construction: media from a different conversation
   lives under a different `[2]` and is unreachable.
2. **It is fail-closed by shape.** Text comparison throughout — no cast of attacker-controlled
   path data — so a malformed path *denies* instead of raising, and one bad object cannot
   break the bucket for everyone (§3b). This is migration 029's established shape.
3. **It does not create the `H-19` twin.** Read symmetric, mutation uploader-scoped, no
   overwrite at all. The storage layer is strictly stricter than the `messages` UPDATE policy
   the programme still has an open P1 against.
4. **It costs no schema.** No column, no table, no change to `shares_conversation_with()`, no
   change to `messages`/`conversations` RLS.
5. **It costs no reordering.** The client already holds `_conversationId` and the uid at the
   upload site; only the path string and the URL call change.
6. **It is the same scoping the rest of messaging already uses**, so there is one membership
   rule in the system rather than two.

### 6.3 Known limits — stated, not hidden

- **`conversations` row mutability bounds the invariant.** `003_fk_and_rls_fixes.sql:73-76`
  gives participants UPDATE on `conversations` with a `USING` clause and no column
  restriction; Postgres reuses `USING` as the `WITH CHECK`, so a participant may **replace the
  other participant** with an arbitrary user, who then inherits read access to that
  conversation's messages *and* its media. This is pre-existing, it already applies to the
  `messages` SELECT policy, and it is the same "no `WITH CHECK`" pattern as `I-NOT-04`. It is
  **not introduced** by this contract and is **not** fixed by it — no conversation-scoped model
  can be stronger than conversation membership. Recorded here as a companion finding needing
  its own triage; the app depends on that policy to write `last_message`/`last_message_at`,
  so it cannot simply be dropped.
- **No UNIQUE on the participant pair** (`I-NOT-05`, migration 131 / task 3A-11). Duplicate
  conversations for the same pair scatter media across two `[2]` values. Correctness only —
  both remain participant-scoped — but 131 is a soft dependency.
- **No revocation path.** Participants are fixed columns with no removal flow, so there is no
  "left the conversation" state to enforce today.
- **`c.id::text = <segment>` does not use the `conversations` primary-key index.** Accepted:
  the table is small, and this is the same trade migration 029 made for the same reason.

---

## 7. What would be required (NOT authorized, NOT implemented)

### 7.1 Migration — rework 130 in place, before application

**Disposition: reworking 130 in place is the only technically convergent path, and it is NOT
currently permitted. It requires an explicit wave-plan authorization that does not yet exist.**

> **Correction, 2026-09-09.** The first draft of this section reasoned from *"130 is untracked
> and unledgered"* to *"the in-place-edit prohibition does not apply"*. **That inference is
> withdrawn.** `QA_CLOSURE_STANDARD.md` §8 is unconditional — *"Never rewrite a migration in
> place unless the wave plan explicitly authorizes it"* — and carves out no exception for an
> untracked or unapplied file. The technical analysis below stands; the claim of permission
> does not. See §2.2(4)–(5).

Why in place, rather than a superseding migration, **if** it is authorized:

- **A superseding migration is not available.** `MASTER_REMEDIATION_WAVES.md` §0.2 assigns
  **131** to task 3A-11 and states 132+ are *"assigned at wave entry, never before"*. Numbers
  are *"assigned in this document and are not negotiable at implementation time."* Taking 131
  or 132 requires an ARCH amendment; renumbering is forbidden outright by Gate 0.9
  (`check-migration-hygiene.sh`: *"Do not renumber an existing migration to close a gap"*).
  **§8's *"Prefer additive forward migrations"* is therefore departed from here for a stated
  reason — no number is available — and that departure is exactly what the owner is being
  asked to rule on, not something this memo may assume.**
- **The corrected 130 is convergent, because QA already holds the wrong policies out of band
  (§2.1).** It must `DROP POLICY IF EXISTS` all four legacy names — including the UPDATE
  policy, which is dropped and **not** recreated — before creating the canonical set. 130
  already opens each policy with a `DROP … IF EXISTS`; that property must be preserved and
  extended, so applying the corrected file converges QA regardless of the ledger question.
- **Sequencing is load-bearing.** Gate 0.8 forbids modifying a *tracked* migration relative to
  its merge-base. 130 is untracked today, so **committing 130 as-authored would foreclose the
  in-place path permanently.** The ruling must precede the commit.

Content the reworked 130 would need:

1. Both bucket rows unchanged: `public = false`, `ON CONFLICT DO UPDATE` (idempotent; already correct).
2. A **new** predicate, additive — `shares_conversation_with()` is untouched:
   `public.is_conversation_participant(conversation text) RETURNS boolean`, `LANGUAGE sql`,
   `STABLE`, `SECURITY DEFINER`, `SET search_path = public, pg_temp`,
   `REVOKE ALL … FROM PUBLIC`, `GRANT EXECUTE … TO authenticated`, with a `COMMENT`.
   Body: `SELECT EXISTS (SELECT 1 FROM public.conversations c WHERE c.id::text = conversation
   AND (c.participant_1 = auth.uid() OR c.participant_2 = auth.uid()))`. **`text` argument and
   `c.id::text` comparison** — never a cast of the path segment (§3b, §6.2.2). Anonymous callers
   get `auth.uid() IS NULL`, every comparison NULL, `EXISTS` false.
3. Four `DROP POLICY IF EXISTS` for the legacy names.
4. Three policies created — SELECT, INSERT, DELETE. **No UPDATE policy.** Each asserts
   `bucket_id = 'chat-media'`, `array_length(storage.foldername(name), 1) = 3`,
   `(storage.foldername(name))[1] = 'messages'`, and
   `public.is_conversation_participant((storage.foldername(name))[2])`; INSERT and DELETE add
   `(storage.foldername(name))[3] = auth.uid()::text`.
5. Header stating the path contract verbatim, the departure from `shares_conversation_with`,
   and the §2.1 divergence.

Guard checks the reworked file must pass before commit (verify, do not assume): the I-MIG-03
durability guard tracks **function** redefinitions, not policies, and the new function is a
first definition carrying `SECURITY DEFINER` + a pinned `search_path` from the outset — so it
should register no strip event, but `migration-durability-guard.mjs --self-test` and the
records-mode run must both be executed. `check-migration-hygiene.sh` requires the file be
committed and the sequence stay contiguous at 130.

**Not proposed and not done:** rerunning 130, inserting a `schema_migrations` row, altering
live policies, dropping or recreating buckets, `supabase db push`, `supabase migration repair`,
authoring 131 or 132.

### 7.2 Flutter changes (eventual)

All in `apps/mobile/lib/features/messaging/`; each is deferred.

1. **Extract a pure path builder** — e.g. `ChatMediaPath.build({conversationId, uploaderId, timestamp, ext})` returning `messages/$conversationId/$uploaderId/$timestamp.$ext` — so the contract is unit-testable without a Supabase client (the N-10 "no seam" problem).
2. **`chat_screen.dart:146`** — build the path from the conversation id + uid instead of `messages/$uid/...`.
3. **`chat_screen.dart:151-153`** — delete the `getPublicUrl` call. Nothing derives a URL at upload time.
4. **`chat_screen.dart:157`** — write `{'type':'image','bucket':'chat-media','storage_path': path}`; retire the `image_url` key. Update migration 129's `COMMENT ON COLUMN messages.metadata` in the same change so all three declarations agree (§3e).
5. **`chat_screen.dart:154`** — check `sendMessage()`'s return; on `false`, `storage.from('chat-media').remove([path])` and show the failure. Closes the silent-failure half of `H-04`. **Note:** this is a return-value check in `chat_screen.dart`, not a change to `messaging_service.dart`'s `catch` blocks — `EC-11` stays untouched and unreopened.
6. **Render path** (`chat_screen.dart:255`, `_MessageBubble`, `widgets/message_bubble.dart`) — resolve `storage_path` through `createSignedUrl(path, ttl)` at render time, cache per message for the TTL, and render an explicit error state on failure. **No fabricated placeholder** (the `H-07`/`H-08` fabrication class).
7. **Backward compatibility** — decide explicitly whether legacy `image_url` metadata rows are read. QA holds none that ever worked (`I-NOT-01`: every image message before 129 was discarded by a 400), so the honest default is: **no legacy read path**. Owner call.
8. Keep `upsert: false` — required by the no-UPDATE-policy decision.

### 7.3 Tests required

**Static guards** (`apps/mobile/test/unit/product_contract_guard_test.dart`, `supabase/tests/`):

1. The chat upload path in `lib/` matches the canonical four-part shape and names the conversation id — a regex guard that fails on any reversion to `messages/$uid/`.
2. **No `getPublicUrl` against a private bucket** — extend the existing bucket scanner (H-G3) so `chat-media` and `progress-photos` are asserted private *and* never publicly addressed.
3. **No `::uuid` cast applied to a `storage.foldername(...)` expression in any migration** — the abort class of §3b, permanently.
4. Every `chat-media` policy references `is_conversation_participant` and **no** `chat-media` policy references `shares_conversation_with`.
5. **Segment-index agreement**: parse the segment index used by the SQL policies and the segment count produced by the Dart path builder, and assert they describe the same path. This is the guard that would have caught the original defect.
6. `chat-media` has exactly three policies — SELECT, INSERT, DELETE — and no UPDATE policy.
7. H-G3 `knownMissing` stays empty (already staged in the working tree).

**Unit / widget:**

8. Path builder: shape, ordering, extension handling, and rejection of an empty conversation id.
9. Metadata shape: `sendMessage` receives `storage_path`, never a URL.
10. Bubble renders from a resolved signed URL; on resolution failure it shows an error state and **not** a fabricated image.

**Live QA probe** (a gated job in the `live-qa` family, following `wrk01-live`'s shape; this is Gate **1.6**'s *"live bucket probe in CI's QA job"*):

11. Both buckets report `public = false`.
12. Participant A uploads to `messages/<conv>/<A>/f.jpg` → **allowed**.
13. Participant B reads that object → **allowed**.
14. Non-participant C reads it → **denied**.
15. B uploads into `messages/<conv>/<A>/…` → **denied** (uid segment).
16. B deletes A's object → **denied**.
17. A deletes A's object → **allowed**.
18. A uploads to a conversation A is not in → **denied**.
19. Malformed path `messages/not-a-uuid/x/f.jpg` → **denied, and denial is not an error** (the §3b regression test).
20. An overwrite attempt against an existing object → **denied** (no UPDATE policy).
21. Fixtures enumerated and removed, removal **proved by a read** — `QA_CLOSURE_STANDARD.md` §7.

---

## 8. Implementation prerequisites

1. **Owner ruling on the §2.1/§2.2 ledger divergence** — how the unledgered live application of 130's DDL is reconciled. This memo does not choose, and no ledger repair may precede that ruling. Manual ledger insertion is not available (§2.2(8)).
2. **Explicit wave-plan authorization to rewrite migration 130 in place**, which `QA_CLOSURE_STANDARD.md` §8 requires and which no current document provides (DB + SEC owners, ARCH for the wave-plan amendment). See §9.1.
3. **Confirmation that no new migration number is taken** — 131 belongs to 3A-11; 132+ is unassigned.
4. **Owner call on legacy `image_url` metadata** (§7.2.7).
5. **JOURNEY authorization for the chat client changes**, with `EC-11` explicitly out of scope and `messaging_service.dart`'s error handling untouched.
6. **QA authorization for the live storage probe job** and its QA credentials (the standing EB-1 secrets dependency).
7. Registry/waves/progress rows for `H-04`, `H-05` and the new predicate defect are ARCH-owned and are **not** written by this memo.

---

## 9. Authorization gate

**This memo stops here.** The next action in any direction — editing 130, committing 130,
executing SQL, or touching the ledger — requires the owner to grant, in writing, one of the
two rulings below. Nothing else in this memo may be acted on first.

### 9.1 Ruling A — recommended

> **Ruling A (recommended).** The out-of-band application of migration 130's DDL to QA is
> recorded as an ENV-class finding, together with the ENV-3 detector gap that let it pass
> unseen. **No `schema_migrations` row is written for 130 by any means** — not by `INSERT`, not
> by `supabase migration repair`. QA's ledger stays at 129 and 130 stays declared `pending`.
>
> Migration **130 is authorized to be rewritten in place**, as an explicit exception to
> `QA_CLOSURE_STANDARD.md` §8, on the stated ground that Gate 0.9 leaves no migration number
> available (131 is assigned to task 3A-11; 132+ is unassigned) and the file is not yet
> committed. This authorization is an amendment to the wave plan for task 3A-10 and is
> recorded as such.
>
> The rewritten 130 must be convergent — `DROP POLICY IF EXISTS` for all four existing
> `chat-media` policy names before creating the canonical set — so that applying it repairs
> QA's live state regardless of the ledger.
>
> The §2.3 evidence must be captured and committed **before** 130 is edited. 130 must not be
> committed in its current form, because Gate 0.8 would then foreclose this path.
>
> This ruling authorizes **documentation and the migration rewrite only**. It does **not**
> authorize applying 130 to QA, modifying Flutter, creating migration 131, reopening `WRK-07`,
> starting `EC-11`, or beginning Wave 3B. Application of the rewritten 130 is a separate
> authorization with its own pre-application QA-state check.

### 9.2 Ruling B — the alternative, stated so the choice is real

> **Ruling B.** Migration 130 is left exactly as authored and is committed. The correction is
> carried by a **new forward migration**, and `MASTER_REMEDIATION_WAVES.md` §0.2 is amended to
> assign it a number, with ARCH owning the amendment.

**Trade-off, stated honestly.** Ruling B keeps `QA_CLOSURE_STANDARD.md` §8's *"prefer additive
forward migrations"* intact and needs no exception. Its cost is that it permanently commits a
migration whose only purpose is to install a policy set the very next migration removes —
placing a known cross-conversation disclosure into the authored history as an intended state,
and requiring a wave-plan renumbering that §0.2 says is *"not negotiable at implementation
time."* Ruling A is preferred because 130 has never been committed and the defect need never
enter the authored history at all — but it is preferred **only if the owner grants the §8
exception explicitly**, which is the whole of this gate.

---

## 10. Execution record — Ruling A, 2026-09-09

**Ruling A approved by the product owner, 2026-09-09.** Recorded here as an **amendment to the
wave plan for task 3A-10**, per the ruling's own instruction. Its stated basis: Gate 0.9 leaves
no migration number available for 3A-10's correction (131 is assigned to 3A-11, 132+ is
unassigned); migration 130 is not committed; and committing it in its defective form would
permanently encode the known-defective policy contract and foreclose the correction path.
This is the *explicit wave-plan authorization* that `QA_CLOSURE_STANDARD.md` §8 requires, and
§2.2(5)'s finding — that no such authorization existed — is now satisfied.

### 10.1 Evidence preserved first

[`DEC-3A-10_EVIDENCE_2026-09-09.md`](DEC-3A-10_EVIDENCE_2026-09-09.md). Part A captures the
relayed live facts and the repository pins; **Part C preserves the pre-rewrite text of
migration 130 verbatim** — it was never committed, so that artifact is its only record
(`sha256 01ecdc92…be39b5`, hash-verified at capture). Part B marks seven items **BLOCKED** for
want of a QA credential, each with the exact read-only statement that would capture it. No SQL
was executed and no environment was contacted.

### 10.2 Migration 130 as rewritten

Bucket rows unchanged (both `public = false`, `ON CONFLICT DO UPDATE`). Added
`public.is_conversation_participant(conversation **text**)` — `STABLE`, `SECURITY DEFINER`,
`SET search_path = public, pg_temp`, revoked from `PUBLIC, anon`, granted to `authenticated`,
comparing `c.id::text = conversation` so **no cast is ever applied to a path segment**. All four
out-of-band policy names dropped (the UPDATE one dropped and **not** recreated), plus the three
canonical names dropped for clean replace. Three policies created — SELECT (any participant),
INSERT and DELETE (participant **and** `[3] = auth.uid()::text`). **No UPDATE policy.** Every
policy asserts `bucket_id`, exact depth 3, the literal `messages` segment, and conversation
membership, in that order. `shares_conversation_with()` untouched.

### 10.3 Consequence recorded during the rewrite — a new gate on application

The previous client path had **two** folder segments (`messages/<uid>/<file>`). Under the new
policies such an object fails the depth assertion for SELECT *and* DELETE, so any object already
written under the old contract becomes unreadable **and undeletable by any end user** — only a
service-role path could remove it. **Evidence item B.6 (`count(*)` of `chat-media` objects) is
therefore a hard precondition on applying 130, not merely a nice-to-have.** If the bucket is
non-empty, a data disposition must be ruled on first. The migration deliberately attempts no
cleanup: deleting user media without an explicit ruling is outside task 3A-10.

### 10.4 Static validation performed *(no environment contacted)*

| Check | Result |
|---|---|
| I-MIG-03 durability guard — `--self-test` | **PASS**, 7/7 |
| I-MIG-03 durability guard — records mode | **PASS (enforcing)** — 0 unrecorded, 0 known-open, 1 sweep-claimed. 130 introduces no strip event |
| ENV-3 static manifest (`check-migration-manifest.mjs`) | **PASS** — 131 authored, QA frontier 129, **130 declared `pending`** |
| Offline contract suite (`npm run test:contract`) | **PASS** — 3-entry allowlist unchanged |
| `product_contract_guard_test.dart` | **9/9 PASS**, incl. H-G3 with `knownMissing = {}` |
| `check-migration-hygiene.sh` | filenames **OK** · numbers unique **OK** · sequence contiguous 000–129 **OK** · **clean-tree check FAILS** — 130 is untracked, and committing it is not authorized. Pre-existing Gate 0.7 state, unchanged by this task |
| Structural audit of the SQL | `BEGIN`/`COMMIT` balanced · `$$` balanced · 3 `CREATE POLICY` · 7 `DROP POLICY IF EXISTS` · 0 `FOR UPDATE` · **0 `::uuid` in executable text** · 0 uses of `shares_conversation_with` as an authorizer |

**Not performed, and it matters:** no SQL parser or Postgres instance exists on this machine
(`psql`, `pg_ctl`, `postgres` all absent), so **the file has never been parsed by Postgres.**
Every check above is textual. Syntactic validity is asserted only by construction and by
following migrations 029/102/122/129's established shapes.

---

## 11. Status

**IMPLEMENTED AND LIVE-VERIFIED ON QA — NOT COMMITTED.** See §12 for the execution record and
`DEC-3A-10_EVIDENCE_2026-09-09.md` Part E for the directly observed evidence. Out of scope and
untouched: `WRK-07`, `EC-11`, `EC-05`, Wave 3B, migration 131, `expected_applied.json`, the
locked UI designs, `docs/design/**`. No ledger row was written by any means other than
`db push`; no migration repair; production not contacted.

---

---

## 12. Execution record — application, verification, client (2026-09-09)

**Application.** Owner-authorized. The agent's `supabase db push --linked --yes` was denied by the
harness permission classifier and the owner ran the identical command from the credentialed
terminal; three `NOTICE … does not exist, skipping` lines are the convergent drops of the
canonical names. Dry run beforehand listed only 130. **Ledger: 130 · 129 · 128.** No row written
by any other means. Full record: [`DEC-3A-10_EVIDENCE_2026-09-09.md`](DEC-3A-10_EVIDENCE_2026-09-09.md) Part E.

**Live verification (directly observed).** Buckets both private; three policies with the exact
expressions §6.1 specifies; no UPDATE policy; four obsolete names absent; helper STABLE /
SECURITY DEFINER / `search_path=public, pg_temp` / no PUBLIC-or-anon grant; FG-1 5/5; **41/41**
storage probes across upload/read/sign/overwrite/malformed/delete for participant, recipient,
non-participant and anon — the hostile/WAF-layer case restored by owner ruling and labelled as
WAF evidence only, existence proved by database-backed LIST, and the run-1 stale read attributed
to the CDN by an observed `cf-cache-status: HIT` (evidence E.6a); `chat-media` = 0 objects and 0 fixture conversations after cleanup.

**Client (Phase D).** `chat_media_path.dart` (new, pure): the path builder and the metadata keys.
`chat_screen.dart`: upload → message → uploader-scoped cleanup on a `false` from `sendMessage()`
→ explicit failure, never success; `upsert: false` retained; `getPublicUrl` removed; image
messages store `{type: image, media_path: <path>}` and render through a per-path memoized
`createSignedUrl(path, 3600)` with explicit signing/loading/failed states. `messaging_service.dart`
untouched (`EC-11` pin intact).

**Guards.** H-G2's second test inverted from characterization to requirement — result checked,
ordering `build → upload → send`, cleanup by exact path, `reportError` on cleanup failure, no
upsert, failure surfaced. New H-G5 (12 tests): **Dart folder depth == SQL `array_length`
assertion** (the guard that would have caught the original defect), segment roles, exactly
SELECT/INSERT/DELETE, uploader clause on writes only, no uuid cast of a path segment in any
migration, helper posture, both buckets private, no `getPublicUrl` on a private bucket, bucket
name spelled once, path-not-URL metadata, old path gone. `chat_media_path_test.dart` (12).
`spec_community_challenge_test.dart` MSG-002 moved to `media_path`. `d07-chat-media-storage.mjs`
registered in `run.mjs`. Negative control: every H-G2/H-G5 predicate is absent from the pre-fix
`chat_screen.dart` at `bbe0448`.

**Results.** `flutter test` **789 passed / 9 skipped / 0 failed** · `flutter analyze` 0 errors, 15
warnings, 160 infos (baseline; none in touched files; CI runs `--no-fatal-infos
--no-fatal-warnings`) · contract, durability, ENV-3 static all green · hygiene fails only on the
untracked 130 (commit pending).

**Open, deliberately.** (1) `expected_applied.json` must move `applied_through` to 130 — the
`352ee68` precedent — and this pass was instructed not to; until then the ENV-3 **live** check
fails L-2/L-5 by design. (2) Migration 129's `COMMENT ON COLUMN messages.metadata` still
describes `{"type":"image","url":…}`; 129 is applied and may not be edited, so the correction
belongs to a future migration. (3) §6.3's `conversations` UPDATE `WITH CHECK` gap remains a
companion finding. (4) The signed-URL memo is per screen instance with a 3600 s TTL; a screen
held open longer than that shows a broken-image state until reopened.

---
