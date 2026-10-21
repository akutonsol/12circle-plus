# Wave 3A task 3A-11 — execution evidence

| | |
|---|---|
| **Date** | 2026-09-09 |
| **Baseline** | `43b48a7d240efac7fb8f5ba54846267cd4375c45` · `chore/qa-environments-secure-ai-backend` |
| **Ruling** | Owner, 2026-09-09 — R-01 (constraints + writer hardening) and R-02 (`I-NUT-04` → 3A-11; `Q-4` a documentation defect), on the basis recorded in [`WAVE_3A_11_RULING_VALIDATION.md`](WAVE_3A_11_RULING_VALIDATION.md) §12 |
| **Status** | **IMPLEMENTED AND LOCALLY VERIFIED — NOT COMMITTED, NOT APPLIED** |
| **Live QA** | **Migration 131 NOT applied.** Ledger `max(version) = 130`; 0 of the 4 new indexes and 0 of the 2 new RPCs exist live. Read-only queries only. Production not contacted. |

---

## 1. Executive summary

3A-11 is implemented in two commit boundaries, because the repository's own
practice separates them: **`352ee68`** moved a frontier *after application* as a
one-file `chore(ENV-3):` commit, while **`26cc330`** declared a migration
`pending` *inside* its `fix(3A-9):` commit. This package follows both.

**Boundary 1 — the 130 frontier reconciliation** landed first and alone, and it
closed a divergence that had been red since the 3A-10 pass: ENV-3's live ledger
check moved from **L-2 FAIL / L-5 FAIL** to **L-1…L-5 all PASS**.

**Boundary 2 — 3A-11 proper**: migration 131 (four identity constraints + two
atomic `SECURITY DEFINER` writers), three writer conformance changes, a 27-test
static guard, a negative-control harness, a live probe suite that cannot run
until 131 is applied, and the `I-WMH-01` registry row that closes open item B4.

**Two things are worth the reader's attention over everything else:**

1. **A pre-existing guard caught a real gap in this work, and the fix was to
   correct the guard's model — proven, not asserted.** `SEC-024`'s *"every RPC
   the app calls is on the allowlist"* failed: it read migration 116's allowlist
   array only, and could not see that a function created by a *later* migration
   carries its own `GRANT`. The assertion was right; the model was incomplete.
   §6.2 records the mutation test proving the corrected guard still fails when
   the grant is removed.
2. **`I-PAY-01`'s own recommended fix is internally inconsistent, and this
   package resolves it explicitly rather than silently.** Workstream I asks for
   a *partial* unique index and, in the same sentence, an upsert with
   `onConflict: 'payment_id'`. PostgREST cannot infer a partial index from a
   bare column list, so the two halves cannot both hold. §4.4.

---

## 2. Baseline and commit boundaries

```
branch  chore/qa-environments-secure-ai-backend
HEAD    43b48a7d240efac7fb8f5ba54846267cd4375c45   (ahead of origin by 1, not pushed)
pre-existing, untouched:  docs/design/   ·  the three prior audit documents
```

**The commit boundary is NOT a preference — it is the repository's practice:**

| Precedent | Shape | What it establishes |
|---|---|---|
| `352ee68` `chore(ENV-3): move QA frontier to 129 after application` | 1 file, `expected_applied.json` only | a frontier move after application is **its own commit** |
| `26cc330` `fix(3A-9): implement migration 129 and I-COM-03` | migration + Dart + `expected_applied.json` | a `pending` declaration rides **inside** the migration's commit |

Therefore: **two commits**, listed in §11.

---

## 3. Boundary 1 — the 130 frontier reconciliation

**Change:** `supabase/expected_applied.json`, one line — `"applied_through": "129"` → `"130"`, and the now-satisfied `pending.130` entry removed. Nothing else in the file.

**Why it was outstanding:** migration 130 was applied to QA through a governed
`supabase db push` during the 3A-10 pass, but the frontier move was deliberately
excluded from that authorization. The manifest therefore declared 130 `pending`
while the ledger held it — recorded in `DEC-3A-10_EVIDENCE_2026-09-09.md` §E.5.

**Evidence, before and after, same check:**

| ENV-3 live ledger | Before | After |
|---|---|---|
| L-1 missing from ledger | PASS 0 | PASS 0 |
| L-2 applied but undeclared | **FAIL — 1: `130`** | **PASS 0** |
| L-3 stale ledger rows | PASS 0 | PASS 0 |
| L-4 holes in the applied sequence | PASS 0 | PASS 0 |
| L-5 ledger rows vs declared | **FAIL — 131 vs 130** | **PASS — 131 vs 131** |

The live QA frontier was verified as legitimately 130 first: `max(version) = 130`,
`supabase migration list --linked` showing `130 | 130 | 130`, and no ledger row
written by anything but the governed push.

---

## 4. Boundary 2 — migration 131

`supabase/migrations/131_identity_constraints.sql` ·
`sha256 5bd4016997346451192fcbe6908319089e3045199e28789140c694d6dfe46ac8`

### 4.1 The four constraints

| Finding | Object | Definition |
|---|---|---|
| **I-NUT-04** | `client_nutrition_plans_one_active_per_client` | `UNIQUE (client_id) WHERE is_active` — **partial**: the contract is "one *active* plan", and superseded rows are history |
| **I-WMH-01** | `cycle_logs_one_period_per_start` | `UNIQUE (user_id, start_date)` |
| **I-WMH-01** | `cycle_logs_end_on_or_after_start` | `CHECK (end_date IS NULL OR end_date >= start_date)`, added **VALID** |
| **I-NOT-05** | `conversations_unique_participant_pair` | `UNIQUE (least(p1,p2), greatest(p1,p2))` — the pair is **unordered** |
| **I-PAY-01** | `client_session_credits_unique_payment` | `UNIQUE (payment_id)` — see §4.4 |

All four are `CREATE UNIQUE INDEX IF NOT EXISTS`; the CHECK is guarded on
`pg_constraint`. Replay-safe by construction.

### 4.2 Data compatibility — checked live before authoring

| Constraint | Blocking rows on QA | Table rows |
|---|---|---|
| one active plan per client | **0** | 2 |
| one cycle period per start date | **0** | 0 |
| `end_date >= start_date` | **0** | 0 |
| unique conversation pair | **0** (and 0 NULL participants) | 1 |
| unique `payment_id` | **0** | 0 |

**No dedupe pass is required for QA.** The CHECK is therefore added **VALID**
rather than `NOT VALID` — `I-MIG-02` already records two `ALTER`-added CHECKs in
this tree that are `NOT VALID` and were never validated, and this file does not
add a third. **Production is a different question**: its data is unreadable to
this programme (`REL-21`) and a production rollout must dedupe first. Out of scope.

### 4.3 The two atomic writers

Both are `SECURITY DEFINER`, `VOLATILE`, `SET search_path = public, pg_temp`,
`REVOKE ALL … FROM PUBLIC, anon`, `GRANT EXECUTE … TO authenticated`, no dynamic SQL.

**`assign_nutrition_plan(...) → uuid`** — supersede + insert in one transaction.
`coach_id` is taken from `auth.uid()` and **is not a parameter**, so no caller can
attribute a plan to another coach.

> **Authorization decision, stated because it is deliberate.** This reproduces
> the existing policy exactly and does **not** tighten it. `"coach client
> nutrition"` is `FOR ALL USING (coach_id = auth.uid() OR client_id =
> auth.uid())`; taking `coach_id` from `auth.uid()` satisfies its write arm by
> construction. The RPC deliberately does **not** require
> `is_active_coach_of(p_client_id)`: that would be **stricter** than the policy
> it replaces and would break a coach assigning a plan before the relationship
> row reaches `'active'`. 3A-11 is an identity/atomicity task and is not
> authorized to change who may write. **Observation recorded, not fixed:** that
> underlying policy is loose — it authorizes on a self-asserted `coach_id`
> rather than on a relationship. That is a pre-existing finding's territory.

**`get_or_create_conversation(other_user uuid) → uuid`** — `INSERT … ON CONFLICT
(least, greatest) DO NOTHING`, then read the winner's row when the insert
returned none. `participant_1` is `auth.uid()` and is not a parameter, so a
caller can only create a conversation they are in — exactly what `"participants
can insert conversations"` permits. Refuses a self-conversation and an
unauthenticated caller (`42501`).

### 4.4 `I-PAY-01` — a deviation from the source card, stated

Workstream I:448 recommends *"a partial unique index `WHERE payment_id IS NOT
NULL`"* and, in the same sentence, *"change the insert to `upsert … onConflict:
'payment_id'`"*. **Those two halves cannot both hold.** PostgREST's `on_conflict`
carries column names only and no index predicate, so Postgres cannot infer a
**partial** index from `ON CONFLICT (payment_id)` and the recommended upsert
would fail with *"there is no unique or exclusion constraint matching the ON
CONFLICT specification"*.

**A plain unique index gives identical semantics and is inferrable.** Postgres
treats NULLs as **distinct** in a unique index by default, so a nullable column
already admits unlimited NULL rows — a manual grant carrying no payment stays
insertable, exactly as the partial predicate intended. The card's stated
**contract** ("one `checkout.session.completed` grants one credit block") is
preserved in full; only the mechanism differs, and it differs so that the card's
own recommended upsert can work. Recorded in the migration header and pinned by
guard `I-G1`.

### 4.5 Structural checks (no Postgres available locally)

`BEGIN`/`COMMIT` balanced · `$$` balanced (6) · 4 `CREATE UNIQUE INDEX`, all
`IF NOT EXISTS` · 2 functions · **0** ledger writes · **0** policy statements ·
**0** `DROP` · **0** dynamic SQL · **0** `EXCLUDE USING` · **0** `NOT VALID` ·
tables touched are exactly the four the findings name.

**Not performed:** the file has never been parsed by Postgres — `psql`,
`pg_ctl` and `postgres` are absent from this machine. Every check above is
textual. The `least`/`greatest` expression index and the `ON CONFLICT` inference
on it are the two constructs whose first real validation will be application.

---

## 5. Writer conformance

| Finding | File | Change |
|---|---|---|
| **I-NOT-05** | `messaging_service.dart` | both `getOrCreateConversationWith` and `getOrCreateCoachClientConversation` now delegate to one private `_getOrCreateConversation` helper calling `get_or_create_conversation`. **Zero inserts into `conversations` remain in the file.** The `String?` return contract and `reportError`-then-`null` handling are unchanged, so no caller starts reading a failure as success |
| **I-NUT-04** | `coach_program_service.dart` | `assignNutritionPlan` calls `assign_nutrition_plan`; the deactivate-then-insert pair is gone; `coach_id` is no longer passed. The notification insert after it is untouched |
| **I-PAY-01** | `stripe-webhook/index.ts` | the bare `.insert()` becomes `.upsert(…, { onConflict: 'payment_id', ignoreDuplicates: true })`. **`ignoreDuplicates` — `ON CONFLICT DO NOTHING` — not a merge**: the grant is money already given and `sessions_used` may have advanced, so a redelivery must be a complete no-op rather than a rewrite of a block being consumed |

---

## 6. Tests and guards

### 6.1 New

**`apps/mobile/test/unit/identity_constraint_guard_test.dart` — 27 tests, I-G1…I-G5.**
These exist because **`npm run test:contract` derives tables, columns and foreign
keys and is blind to UNIQUE indexes and CHECK constraints** — nothing in this
repository would have noticed if migration 131's constraints were deleted.

| Group | Pins |
|---|---|
| **I-G1** | each constraint by table *and* exact column expression; all four idempotent; the `I-PAY-01` index is **not** partial |
| **I-G2** | both RPCs: `SECURITY DEFINER`, pinned `search_path`, `VOLATILE`, `42501` refusal, revoked from PUBLIC/anon, granted to authenticated, no dynamic SQL; `coach_id`/`participant_1` come from `auth.uid()` and are not parameters; the race is *resolved*, not raced |
| **I-G3** | no `conversations` insert survives in `messaging_service.dart`; both entry points collapse onto one arbiter; a failure is still `null`; the coach writer is one RPC |
| **I-G4** | the credit grant upserts and never re-inserts; `ignoreDuplicates` present; the handler's three other conflict targets still present |
| **I-G5** | no `EXCLUDE USING`, no `NOT VALID`, no policy change, exactly the four tables, and **no migration in the tree writes `supabase_migrations`** |

**`apps/mobile/tool/negative_control/i3a11_negative_control.sh`** — reverts the
three writers to `43b48a7` and removes 131, requires the guard to **fail**,
restores byte-identically, requires the **pass** again. Follows
`icom01_negative_control.sh` exactly. **The pre-fix state is real, not
synthetic** — every defect predates this task (`023/024`, `033`, `000`, `028`)
— so **G-3 is not invoked**.

> **It has not been executed.** Its first act is `git diff --quiet` on each
> writer, so it correctly refuses a dirty tree; like every sibling harness it
> runs in CI against a committed tree. The same evidence was gathered read-only
> against `43b48a7` instead: migration 131 **absent**; both RPCs **absent** from
> every migration; `messaging_service.dart` carrying **2** `conversations`
> inserts and **0** RPC calls; `coach_program_service.dart` **0** RPC calls;
> the webhook carrying `.insert(` and **0** `ignoreDuplicates`. Every I-G1…I-G4
> assertion therefore fails against that tree.

**`supabase/tests/security/d08-identity-constraints.mjs`** — the live probe
suite, registered in `run.mjs`. **It cannot pass until 131 is applied, and that
is stated in its own header and at its registration.** It proves each arbiter
directly (duplicate → `23505`), that two simultaneous `get_or_create_conversation`
callers converge on one row, that exactly one active plan survives two assigns,
that a manual credit grant with no payment still inserts, and that neither RPC
is executable by `anon`. `I-PAY-01`'s Stripe replay is **not simulated and no
Stripe evidence is claimed** — the suite asserts only the database arbiter.

### 6.2 One existing guard corrected — with proof it was not weakened

`SEC-024` *"every RPC the app calls is on the allowlist"* **failed** on first
run: `Actual: ['assign_nutrition_plan', 'get_or_create_conversation']`.

**The assertion was right and the model was incomplete.** Migration 116 does
`REVOKE EXECUTE ON ALL FUNCTIONS … FROM PUBLIC/anon/authenticated` plus
`ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` **and
`anon`** — not from `authenticated`, which never held a default grant. A
function created by a *later* migration is therefore born unreachable and must
carry its own `GRANT EXECUTE … TO authenticated`. Migrations **129**
(`may_notify`) and **130** (`is_conversation_participant`) already do exactly
that; 3A-11's two RPCs are simply the first such functions the client calls
through `.rpc()`, which is why the gap surfaces only now.

The guard now unions 116's allowlist with functions granted `EXECUTE` to
`authenticated` by **any** migration. **Proof it still bites:**

| Tree | Result |
|---|---|
| as implemented | `+48: All tests passed!` |
| **GRANT statements removed from 131 (mutation)** | **`+47 -1: Some tests failed` · `Actual: ['assign_nutrition_plan', 'get_or_create_conversation']`** |
| restored (`sha256 5bd40169…`) | `+48: All tests passed!` |

An RPC the app calls that holds no `EXECUTE` grant **anywhere** still fails.
Only the set of places a grant may come from was corrected.

### 6.3 Results — exact commands

| Command | Result |
|---|---|
| `flutter test test/unit/identity_constraint_guard_test.dart` | **+27 PASS** |
| `flutter test test/unit/phase1_security_boundary_test.dart` | **+48 PASS** |
| `flutter test` (full) | **819 passed / 9 skipped / 0 failed** (was 792 at baseline; +27 new) |
| `flutter analyze` | **0 errors**, 15 warnings, 160 infos — baseline unchanged, none in touched files |
| `npm run test:contract` | **PASS** |
| `check-migration-manifest.mjs` (ENV-3 static) | **PASS** — frontier 130, `131` declared pending |
| `migration-durability-guard.mjs --self-test` | **PASS** |
| `migration-durability-guard.mjs` (records) | **PASS (enforcing)** — 0 unrecorded |
| `check-migration-hygiene.sh` | filenames / uniqueness / contiguity **OK**; clean-tree **FAIL** — 131 untracked, pre-commit |
| ENV-3 **live** ledger | **L-1…L-5 all PASS**; `INFO authored and PENDING: 131` |
| `node --check` d08, run.mjs | **OK** |
| `deno check` stripe-webhook | **NOT RUN** — Deno is not installed (N-09 class limitation). The TypeScript edit is not type-checked |

---

## 7. `I-WMH-01` registry row (open item B4)

Added to **§7.4 *Nutrition · Check-In · Women's Health***, immediately after the
`F-01`…`F-07` row, because Workstream I files `I-WMH-01` as the
**database-level complement** of that app-level row (*"Complements: F-01, F-04
(app-level). This is the database-level complement they did not cover."*).
Column format matches the section (`ID | Sev | RC | Statement | Dec | Wave`):
**P2 · CRC-06 · Dec `no` · Wave `3A (task 3A-11)`**. The statement is
Workstream I's in substance; **no requirement semantics were changed**. One line
added; nothing else in the registry touched.

---

## 8. Live QA verification

**Migration 131 NOT applied to QA.** Verified read-only after all local work:

```
ledger_max = 130   ·   new indexes live = 0/4   ·   new RPCs live = 0/2
```

Read-only queries only: ledger, `pg_constraint`, `pg_indexes`,
`information_schema.columns`, `pg_policies`, `pg_proc`, row counts, and the
ENV-3 generated comparison (a self-rolling-back `DO` block). **No `db push`, no
manual SQL, no ledger write, no `migration repair`, no data mutation, no policy
change.** Production not contacted.

*(One transient `502` from the Management API's login-role init occurred on a
read-only query and succeeded on retry. Recorded because it appeared in the
session, not because it changed anything.)*

---

## 9. Residual risks

1. **131 has never been parsed by Postgres.** No local instance exists. The
   `least`/`greatest` expression index and the `ON CONFLICT` inference over it
   are the two constructs that will first be validated by application.
2. **`deno check` did not run** — the webhook TypeScript edit is unverified by a
   type checker (N-09).
3. **`d08` cannot pass until 131 is applied**, and is registered in `run.mjs` in
   that state deliberately. A runner invocation before application will show it
   red; that is the pre-fix reading, not a defect.
4. **`I-PAY-01` terminal closure is deferred** — Stripe test mode does not exist
   (`P-8`). §10.
5. **The `"coach client nutrition"` policy remains loose** (§4.3) — authorizing
   on a self-asserted `coach_id` rather than a relationship. Pre-existing;
   deliberately not changed by an identity/atomicity task.
6. **Production dedupe is unaddressed** and must precede any production rollout.
7. The negative-control harness is unexecuted until commit (§6.1).

---

## 10. `I-PAY-01` disposition

```
IMPLEMENTED                      · migration 131 index + webhook upsert
VERIFIED TO AVAILABLE EXTENT     · static guards I-G1/I-G4 green;
                                   the database arbiter is asserted by d08,
                                   which cannot run until 131 is applied
TERMINAL CLOSURE DEFERRED — STRIPE TEST MODE UNAVAILABLE (P-8); Wave 6, K-01
```
No Stripe evidence is claimed anywhere in this package.

---

## 11. Proposed commit boundaries

**Commit 1 — `chore(ENV-3): reconcile QA migration frontier to 130`** — `de20ea75`
```
supabase/expected_applied.json          (ONLY file; 1 insertion, 1 deletion)
```
Its whole content is `"applied_through": "129"` → `"130"`, reconciling the
declaration with the ledger for a migration **already applied** to QA on
2026-09-09 through a governed `supabase db push`. `pending` is `{}` in this
commit — the migration-131 declaration belongs to Commit 2 and is not present
here. Verified against the commit's **own** extracted tree (not the working
tree): 131 authored migrations, highest `130_private_storage_buckets.sql`, ENV-3
static guard `frontier 130 · PENDING (none) · OK`.

> **Correction, recorded rather than silently fixed.** An earlier revision of
> this section described Commit 1 as *"frontier 129 -> 130 only"* while the
> working tree carried the frontier move **and** the 131 declaration in one
> file — a state from which that commit could not be formed. The pre-commit
> audit caught it. The two edits were separated under a bounded authorization:
> the 131 block was removed, Commit 1 was made, and the block was restored
> byte-identically (`sha256 9c28736d…`) for Commit 2.

**Commit 2 — `fix(3A-11): identity constraints (migration 131), atomic writers, guards`**
```
supabase/migrations/131_identity_constraints.sql          (new)
supabase/expected_applied.json                            (declare 131 pending)
apps/mobile/lib/features/messaging/data/messaging_service.dart
apps/mobile/lib/features/coach/data/coach_program_service.dart
supabase/functions/stripe-webhook/index.ts
apps/mobile/test/unit/identity_constraint_guard_test.dart (new)
apps/mobile/test/unit/phase1_security_boundary_test.dart  (SEC-024 model)
apps/mobile/tool/negative_control/i3a11_negative_control.sh (new)
supabase/tests/security/d08-identity-constraints.mjs      (new)
supabase/tests/security/run.mjs
docs/MASTER_REMEDIATION_REGISTRY.md                       (I-WMH-01 row, B4)
docs/WAVE_3A_11_EXECUTION_EVIDENCE.md                     (this file)
```

**The two boundaries are intentional**, following the repository's own practice:
a frontier move *after application* is its own commit (`352ee68`), while a
`pending` declaration rides *inside* its migration's commit (`26cc330`).
**Migration 131 has NOT been applied to QA** — the ledger remains at 130 and
neither commit changes that.

**Excluded from both:** `docs/design/**` · the three prior audit documents
(`WAVE_3A_11_READINESS_AUDIT.md`, `WAVE_3A_11_RULING_VALIDATION.md`,
`WAVE_3B_WRK07_EC11_EC05_AUDIT.md`) unless the owner wants them committed
alongside.

---

## 12. Next action

**Apply migration 131 to QA** — a separate authorization with its own
pre-application state check, exactly as migration 130's was. It must re-verify
the §4.2 blocking counts immediately before pushing, then run `d08` and record
its results. Nothing in this package may be treated as `FIXED ON QA` until then.

---

## 13. Migration 131 application attempt — 2026-09-09 (FAILED, then unblocked)

**Authorization boundary.** The owner authorized applying 131 to QA through the
sanctioned route only, and separately authorized one bounded QA-data cleanup
scoped to two named conversation rows. Nothing else in this section was
permitted: no migration repair, no `schema_migrations` write, no out-of-band
SQL, no production contact.

### 13.1 Preflight — PASS

`HEAD` = `7c2266c0346f6da0e50eba16d5c58fa0a64f0e09`, identical to `origin`.
`131_identity_constraints.sql` byte-identical to the committed blob
(sha256 `5bd40169…ac8`). Declared `applied_through` = `130` with `131` in
`pending`. Live frontier **130**, `131` ledger row absent, **zero of seven**
131 objects present. Linked project `eyqtldjqpgpljlqvpowh`; production
`nxdbooufqzkpslkcogxc` unlinked.

### 13.2 Application — FAILED, clean rollback

Command: `supabase db push --linked --yes` (the only authorized route).

```
ERROR: could not create unique index "conversations_unique_participant_pair" (SQLSTATE 23505)
Key (LEAST(participant_1, participant_2), GREATEST(participant_1, participant_2))=
  (1c89c873-3c58-41e0-aebe-1fd6948ded5d, ce81ea42-a05f-47a2-a8a3-de87ca4fa822) is duplicated.
At statement: 7
```

The migration runs in one transaction and rolled back whole: frontier stayed
**130**, no `131` row, zero 131 objects. Statements 1–6 had succeeded
in-transaction and were discarded with it. There was no partial state and
nothing to repair.

### 13.3 The blocker, and why §4.2 did not predict it

§4.2's zero-dedupe verification was accurate when taken. The blocking rows did
not exist then — they were created **afterwards, by running `d08` against the
deliberately un-migrated database**. `d08-identity-constraints.mjs:162` proves
the pair index directly:

```js
const dup = await rest(A.jwt, 'conversations', {
  method: 'POST', prefer: 'return=minimal',
  body: { participant_1: B.uid, participant_2: A.uid },
});
check('a direct duplicate-pair insert is refused by the index', uniqueViolation(dup), …);
```

There is no `cleanup.push` for it, and correctly so **once 131 is applied**:
the insert is refused and no row exists to clean. With 131 unapplied the insert
returns `201`, and `Prefer: return=minimal` means the suite never learns the new
id — so it *cannot* register it. The cleanup block iterates the registered
`cleanup` array only, which is why its `every fixture removed … remaining=0`
claim was truthful while this row persisted. The leak exists **only** in the
pre-131 window.

Attribution is one-to-one with the two live-suite executions of 2026-09-09:

| CI run | Live QA suites | leaked row | created |
|---|---|---|---|
| 34402447206 (20:40) | skipped — Static guards failed | — | — |
| 34404901620 (21:05) | ran | `04a409ea-422a-460d-9e22-0393b3328520` | 21:07:21Z |
| 34410026228 (22:01) | ran | `fdd97e88-1be1-40d3-af18-dbdb6928fec8` | 22:02:33Z |

The leak reproduces on **any** pre-131 `d08` run, local or CI: `QA_SERVICE` is
optional in this suite (`process.env.QA_SERVICE || null`) and governs only
whether the *registered* fixtures are removed, so it cannot affect a row that
was never registered. The two observed rows correlate one-to-one with the two
CI live-suite executions above, and no local `d08` run occurred — the local
logs contain no `D08-FIXTURE` marker.

### 13.4 Authorized cleanup

Six predicates were verified independently before deleting: both ids existed;
both were the exact `p1-victim@qa.12circle.test` / `p1-coach@qa.12circle.test`
pair; both had **0** messages; both had `last_message` NULL; both participants
are QA seed personas; and `to_jsonb(row)` minus the six known columns was `{}`,
proving no unrelated payload. `conversations` has exactly one FK dependent —
`messages.conversation_id`, `ON DELETE CASCADE` — which the zero-message guard
renders inert.

```sql
delete from public.conversations
where id in ('04a409ea-422a-460d-9e22-0393b3328520',
             'fdd97e88-1be1-40d3-af18-dbdb6928fec8')
  and (select count(*) from public.messages m
        where m.conversation_id = conversations.id) = 0;
```

`RETURNING` reported exactly those two ids and no others.

### 13.5 Read-back

Both ids absent. `conversations` 3 → **1**; `messages` 25 → **25** (unchanged —
nothing cascaded). Survivor `6b40c911-094b-4229-a2fd-47dbe4657b6b` intact with
its 25 messages. Duplicate participant pairs **0**. No rows created since the
baseline. Frontier **130**, `131` row **absent**, 131 objects **0** — the
cleanup touched data only, never the ledger or the schema.

All six 131 prerequisites are now clear: active-plan dupes 0 · cycle
`(user_id, start_date)` dupes 0 · invalid cycle date ranges 0 · unordered pair
dupes 0 · `payment_id` dupes 0 · `participant_2 IS NULL` 0.

### 13.6 Standing condition

**Migration 131 remains UNAPPLIED** and was not retried in this task. The
harness leak is recorded, not remediated — `d07` and `d08` were read only.
Because the leak reproduces on any pre-131 CI run that reaches the live suites,
the environment can be re-contaminated by a push before 131 is applied; the
blocking count must therefore be re-verified immediately before the next
attempt, as §12 already requires. **Production was not contacted.**

---

## 14. Migration 131 application — 2026-09-19 (SUCCEEDED)

**Authorization boundary.** The owner explicitly authorized executing the
previously drafted 12-step migration-only plan against the linked QA project
only, with `expected_applied.json`, production, and unrelated files excluded
from mutation, and commit/push withheld pending separate authorization.

### 14.1 Immediate pre-push re-check

All six blocking predicates re-verified at **0** immediately before pushing
(active-plan dupes, cycle `(user_id, start_date)` dupes, invalid cycle dates,
conversation-pair dupes, `payment_id` dupes, `participant_2 IS NULL`); frontier
**130**, `131` row **absent** — unchanged since §13.

### 14.2 Application — SUCCEEDED

Command: `supabase db push --linked --yes` (the sole sanctioned route).
Output: `Applying migration 131_identity_constraints.sql... Finished supabase
db push.` No repair operation, no manual `schema_migrations` write, no
production access.

### 14.3 Ledger verification

Live frontier **131**. `schema_migrations` contains **132** rows, `000`–`131`,
contiguous, no gap, no `132`. Matches the authored set exactly (132 files,
`000`–`131`, confirmed by direct enumeration of `supabase/migrations/`).

### 14.4 Structural verification — every object, by definition

| Object | Verified definition |
|---|---|
| `client_nutrition_plans_one_active_per_client` | `UNIQUE (client_id) WHERE is_active` |
| `cycle_logs_one_period_per_start` | `UNIQUE (user_id, start_date)` |
| `cycle_logs_end_on_or_after_start` | `CHECK (end_date IS NULL OR end_date >= start_date)`, `convalidated = true` |
| `conversations_unique_participant_pair` | `UNIQUE (LEAST(participant_1, participant_2), GREATEST(participant_1, participant_2))` |
| `client_session_credits_unique_payment` | `UNIQUE (payment_id)` |
| `assign_nutrition_plan` | `prosecdef=true`, `provolatile='v'`, `search_path=public, pg_temp`; `anon`/`PUBLIC` EXECUTE = false, `authenticated` EXECUTE = true |
| `get_or_create_conversation` | same posture as above |

All seven match the authored migration exactly. No unexpected privilege
expansion on either function.

### 14.5 Positive and negative probes — `d08-identity-constraints.mjs`

Run directly (self-contained; does not require `run.mjs` or
`setup-identities.mjs` — the four fixture identities already existed and
`signIn` only needs password auth). Result: **24/24 passed.**

The previously observed `PGRST202` on `public.assign_nutrition_plan` is
**gone** — the RPC now returns `200`. All five integrity rules refuse their
prohibited operation, with the classification captured per case:

| Rule | Refusal | Code |
|---|---|---|
| A. second active nutrition plan | direct insert refused by partial index | `23505` |
| B. duplicate cycle-log period | double tap refused | `23505` |
| C. `end_date < start_date` | insert refused | `23514` |
| D. duplicate participant pair (either ordering) | direct insert refused | `23505` |
| E. duplicate `payment_id` | second grant refused | `23505` |

RPC authorization: `get_or_create_conversation` refused to `anon` (`401`);
`assign_nutrition_plan` refused to `anon`; self-conversation refused;
`coach_id`/`participant_1` proven to come from `auth.uid()`, never a supplied
value. Two simultaneous callers converged on one conversation id (race proof).
I-PAY-01's Stripe-replay boundary is unchanged — DB arbiter proven, Stripe
replay explicitly not simulated (P-8), deferred to Wave 6/K-01 as before.

### 14.6 Regression

| Check | Result |
|---|---|
| `migration-durability-guard.mjs` | PASS — 0 unrecorded regression |
| `npm run check:guards` (prod-refs, migration hygiene, edge-function config) | PASS |
| `identity_constraint_guard_test.dart` + `product_contract_guard_test.dart` | PASS — 48/48 |
| `ec23_negative_control.sh` | PASS — mutated tree correctly failed (7 pre-ERR-1 sites), restore was byte-exact, restored tree passed |
| `d07-chat-media-storage.mjs` | PASS — 42/42, unchanged |
| `d08-identity-constraints.mjs` | PASS — 24/24 (see 14.5) |

### 14.7 ENV-3 — discrepancy flagged, NOT reconciled

Live frontier is now **131**. `expected_applied.json` still declares
`applied_through: "130"` with `131` in `pending`. **This file was deliberately
NOT modified in this task** — the owner's authorization for this execution
explicitly excluded it. The declared/observed mismatch is a known, expected
consequence of applying the migration without touching the manifest in the
same step, exactly as ENV-3's own governing comment anticipates: *"a version
applied without being declared here fails."* Reconciling `applied_through` to
`131` and clearing `pending` requires its own separate authorization.

### 14.8 Fixture cleanup

`conversations` total **1** (only the pre-existing 25-message survivor,
`6b40c911-…`, intact); zero d08-created rows remain for either fixture
identity in `client_nutrition_plans`, `cycle_logs`, `client_session_credits`,
or `payments`; duplicate participant pairs **0**. Two unrelated
`client_nutrition_plans` rows were found and independently confirmed
pre-existing (owned by a different persona, `client_id
5470a95f-bcae-4e01-b2be-7c16964fa432`, created 2026-08-24, unrelated to either
d08 fixture identity) — correctly left untouched.

### 14.9 Standing state

**Migration 131 is now APPLIED to QA.** No commit was made — none was
authorized in this task. `expected_applied.json` is unmodified.
**Production was not contacted.** QA credentials used to run `d08`/`d07`
(fetched via `supabase projects api-keys`, staged only in the session
scratchpad) were deleted immediately after the live probes completed.
