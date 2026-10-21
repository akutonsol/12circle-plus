# Wave 3A task 3A-11 — readiness / authorization audit

| | |
|---|---|
| **Date** | 2026-09-09 |
| **Baseline** | `43b48a7d240efac7fb8f5ba54846267cd4375c45` on `chore/qa-environments-secure-ai-backend` |
| **Mode** | Read-only audit. **Nothing implemented.** Migration 131 not created. |
| **Disposition** | **GOVERNANCE AMBIGUITY — two conflicts must be ruled before 3A-11 can be scoped** |
| **Live QA writes** | none. Six read-only queries. Production not contacted. |
| **Files created** | this file only |

---

## 1. Executive summary

3A-11 is **technically the most ready task in Wave 3A and the least ready governance
item.** Those two facts point in opposite directions and the second governs.

**Technically ready.** All four constraints it must add are genuinely absent — verified
live, not inferred — and all four would apply to QA **today with no dedupe pass**: zero
duplicate active nutrition plans, zero duplicate cycle-log pairs, zero ordering violations,
zero duplicate conversation pairs, zero duplicate `payment_id`s. The "after reconciling
existing duplicates" caveat that every source card carries is, on QA, already satisfied.

**Not ready to scope.** Two contradictions in the governing documents:

1. **The waves document scopes 3A-11 as migration-only** (`Files | —`). **Three of its four
   source cards require application or Edge-Function changes plus `SECURITY DEFINER` RPCs.**
   A constraint added without its writer fixed converts a silent data-integrity defect into
   a visible `23505` on a user's happy path.
2. **`I-NUT-04` is filed in two waves at once** — registry §7.4 says *Wave 4, blocked on
   Q-4*; the waves document says *3A-11*. Nothing reconciles them.

Plus two already-recorded open items that land squarely on this task: **`I-WMH-01` has no
registry row at all** (§7.22 item B4 — a quarter of 3A-11 has no tracking home), and **no
negative-control harness exists for any 3A-11 item** (B6 — which caps the reachable evidence
ceiling).

And one hard sequencing constraint nobody has stated yet: **authoring migration 131 forces
an edit to `supabase/expected_applied.json`** (the static guard's Rule 7 — *"Silence is not
a state"*), a file that is currently both excluded from every recent authorization **and
materially divergent** (it declares 130 `pending` while 130 is applied). **The 130 frontier
move must land before 131 is authored**, or the manifest is edited twice for two reasons in
one change.

---

## 2. Baseline

```
branch   chore/qa-environments-secure-ai-backend
HEAD     43b48a7d240efac7fb8f5ba54846267cd4375c45      (matches expected)
origin   bbe0448ff4722b843324de9e888b00302f051b1e      (ahead 1, not pushed)
tree      M supabase/expected_applied.json             PRE-EXISTING — untouched
         ?? docs/WAVE_3B_WRK07_EC11_EC05_AUDIT.md      prior audit, untouched
         ?? docs/design/                               PRE-EXISTING — untouched
highest authored migration: 130_private_storage_buckets.sql
manifest: applied_through 129 · excluded [] · pending ["130"]
```
Production `nxdbooufqzkpslkcogxc` **was not contacted**.

---

## 3. Governing sources

| Rank | Source | What it governs |
|---|---|---|
| **PRIMARY (scope + number)** | `MASTER_REMEDIATION_WAVES.md` §0.2 line 81, §Wave 3A line 262 | Assigns migration **131** to task **3A-11**; names the four constraints; `Files` column = `—` |
| **PRIMARY (requirement text)** | `QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md` §4.2–4.8 | The four source cards: `I-NUT-04` :337, `I-WMH-01` :422, `I-PAY-01` :448, `I-NOT-05` :613 — each with *Recommended fix*, and I §1138–1141's ordering block |
| **SECONDARY** | `MASTER_REMEDIATION_REGISTRY.md` §1 (CRC-06), §7.4 :1406, §7.5 :929, §7.22 | Root cause; per-finding wave/dependency; the open B2/B4/B5/B6 items |
| **SECONDARY** | `QA_CLOSURE_STANDARD.md` §2.1 | The closure ladder per finding class |
| **SECONDARY** | `supabase/expected_applied.json` + `check-migration-manifest.mjs` Rule 7 | The manifest obligation a new migration creates |
| **SECONDARY** | `docs/decisions/DEC-3A-10_CHAT_MEDIA_STORAGE_CONTRACT.md` §6.3 | Records 131 as a **soft dependency** of the chat-media contract |
| **CONFLICTS** | see §11 — **R-01** (scope) and **R-02** (`I-NUT-04`'s wave) | |

---

## 4. 3A-11 requirement matrix

`CRC-06` — *"an identity model that lives in application convention (check-then-insert)
instead of in a UNIQUE index"* — is the shared root cause of all four.

### 4.1 `I-NUT-04` · P1 · at most one active nutrition plan per client

| | |
|---|---|
| **Source** | Workstream I :337 |
| **Acceptance** | `CREATE UNIQUE INDEX … ON client_nutrition_plans (client_id) WHERE is_active` **and** the coach's deactivate+insert becomes one atomic `SECURITY DEFINER` RPC |
| **Domain** | DB + **Flutter** |
| **DB impact** | one partial unique index; one new RPC |
| **Client impact** | `coach_program_service.dart:263-277` — currently **two non-atomic statements** (`update … is_active=false`, then `insert`) |
| **Security** | the RPC bypasses RLS by construction → needs its own authorization check + pinned `search_path` |
| **Tests** | contract guard for the index; a test that a second active row is rejected; RPC atomicity |
| **Evidence** | FIXED IN CODE · FIXED ON QA · VERIFIED IN CI · VERIFIED LIVE (a read path exists — four readers) |
| **Dependency** | **DISPUTED** — registry says Q-4 / Wave 4; waves says 3A-11 (**R-02**) |
| **Authorization** | ⛔ blocked on R-01 + R-02 |

### 4.2 `I-WMH-01` · P2 · `cycle_logs` identity and ordering

| | |
|---|---|
| **Source** | Workstream I :422 |
| **Acceptance** | `UNIQUE (user_id, start_date)`; `CHECK (end_date IS NULL OR end_date >= start_date)`; **and, after a dedupe pass, an exclusion constraint on overlapping ranges** |
| **Domain** | DB only |
| **Client impact** | **none required** — `cycle_service.dart:44` `logPeriod()` stays a plain insert; the index makes the double-tap fail instead of duplicating |
| **Security** | none |
| **Tests** | contract guard; duplicate-start rejection; `end_date < start_date` rejection |
| **Evidence** | Data contract / schema ladder |
| **Dependency** | none |
| **Authorization** | ⚠ **has no registry row** (B4 / **R-03**) — severity and closure class are of record nowhere |
| **Note** | the **only** genuinely migration-only member of 3A-11 |

### 4.3 `I-NOT-05` · P2 · one conversation per participant pair

| | |
|---|---|
| **Source** | Workstream I :613 |
| **Acceptance** | `CREATE UNIQUE INDEX ON conversations (least(participant_1,participant_2), greatest(participant_1,participant_2))` **and** both Dart paths collapse onto one `SECURITY DEFINER` get-or-create RPC |
| **Domain** | DB + **Flutter** |
| **Client impact** | `messaging_service.dart:87` `getOrCreateConversationWith()` and `:117` `getOrCreateCoachClientConversation()` — **two independent check-then-insert paths for the same pair** |
| **Security** | the RPC bypasses RLS on a table with 3 policies → own authorization check + pinned `search_path` |
| **Interaction** | **improves migration 130.** DEC-3A-10 §6.3 records that duplicate conversations scatter chat media across two different `[2]` path segments; 131 removes that |
| **Evidence** | Data contract / schema ladder |
| **Dependency** | none |
| **Authorization** | ⛔ blocked on R-01 |

### 4.4 `I-PAY-01` (constraint half) · P1 · idempotent session-credit grant

| | |
|---|---|
| **Source** | Workstream I :448; registry :166/:929 files the parent `K-01` as **P0, Wave 6** |
| **Acceptance** | partial `UNIQUE (payment_id) WHERE payment_id IS NOT NULL` **and** the webhook insert becomes `upsert … onConflict:'payment_id'` |
| **Domain** | DB + **Edge Function** |
| **Client impact** | `supabase/functions/stripe-webhook/index.ts:130` — a bare `.insert(...)`. **Every other write in the same handler is already idempotent** (`payments` UPDATE…WHERE id; `subscriptions` upsert on `stripe_subscription_id`; `coach_client_relationships` upsert on the party pair, visible at :126; `event_registrations` upsert on `(event_id,user_id)`). This one write was never given a conflict target |
| **Security / money** | **this is the only member that moves money.** Class = **Billing / entitlement** |
| **Evidence ceiling** | that class requires *VERIFIED LIVE against Stripe **test mode*** and *VERIFIED END-TO-END for anything that moves money*. **`P-8` records that no QA Stripe test-mode credentials, runbook or price ids exist** (Wave 6). **The class ladder therefore cannot be completed inside Wave 3A** |
| **Dependency** | the constraint half is independent; the closure belongs with `K-01` in Wave 6 |
| **Authorization** | ⛔ blocked on R-01; closure deferred regardless (**R-07**) |

---

## 5. Current implementation trace

| Requirement | Classification | Evidence |
|---|---|---|
| `client_nutrition_plans` partial UNIQUE | **NOT IMPLEMENTED** | live: PK + 2 FKs only; `pg_indexes` shows only `_pkey` |
| atomic nutrition-plan RPC | **NOT IMPLEMENTED** | `coach_program_service.dart:263-277` is still two statements |
| `cycle_logs` UNIQUE + CHECK | **NOT IMPLEMENTED** | live: PK + 1 FK; only `idx_cycle_logs_user (user_id, start_date DESC)` — **non-unique** |
| `conversations` pair UNIQUE | **NOT IMPLEMENTED** | live: PK + 2 FKs; only `conversations_pkey` |
| get-or-create conversation RPC | **NOT IMPLEMENTED** | both Dart paths present and independent |
| `client_session_credits` UNIQUE(payment_id) | **NOT IMPLEMENTED** | live: PK + 4 FKs, **zero UNIQUE**; indexes are `_pkey` + two non-unique |
| webhook upsert | **NOT IMPLEMENTED** | `stripe-webhook/index.ts:130` bare insert |
| migration 131 | **NOT IMPLEMENTED** | highest authored is 130; no draft anywhere |
| tracking row for `I-WMH-01` | **GOVERNANCE GAP** | §7.22 B4, confirmed |
| negative control for any 3A-11 item | **TEST/EVIDENCE GAP** | §7.22 B6, confirmed — see §8 |
| RLS on all four tables | **ALREADY IMPLEMENTED** | live: all four `relrowsecurity = true`; policies 1 / 1 / 3 / 3 |

**Nothing that 3A-11 must deliver exists.** Every finding reproduces exactly as Workstream I
described it, verified against both the source and the live QA catalog.

---

## 6. Migration 131 analysis

**Required: YES.** Three of the four requirements are index/constraint DDL that exists in no
other form. Read-only findings:

| Question | Answer |
|---|---|
| Specified anywhere as SQL? | **No.** Only a one-line description at waves :81 and :262. No draft, no header, nothing in `supabase/migrations`. Its content must be derived from the four Workstream I cards |
| Schema changes | 1 partial unique index (nutrition), 1 unique + 1 CHECK (+ optional exclusion constraint) (cycle_logs), 1 functional unique index on `least`/`greatest` (conversations), 1 partial unique index (session credits) |
| Data changes | **None required on QA** — see the blocker check below. Production unknown (`REL-21`) |
| RLS changes | **None.** All four tables already have RLS enabled with policies; 131 adds no policy |
| Functions/triggers | **Two `SECURITY DEFINER` RPCs** if R-01 is ruled to include the writer halves; **none** if 131 is constraint-only |
| Ordering / 130 dependency | **No functional dependency.** 130 is applied (ledger 130); 131 is the next contiguous number, satisfying Gate 0.9. 131 *improves* 130's contract (§4.3) |
| Out-of-band state | **None.** Unlike 130, nothing has been pre-applied: every target constraint is verifiably absent |
| Rollback / convergence | Every statement should be `IF NOT EXISTS` / idempotent. Index creation is reversible by `DROP INDEX`; the CHECK by `DROP CONSTRAINT`. Consider `NOT VALID` for the CHECK if production rows resist — but note `I-MIG-02` already records that both `ALTER`-added CHECKs in the tree are `NOT VALID` and never validated |
| Ledger behaviour | Row created **only** by real application via `supabase db push`. No `INSERT`, no `migration repair` — the same rule that governed 130 |
| Authoring authorized today? | **NO.** Every recent authorization has excluded it explicitly, and this pass forbids it |

### 6.1 Blocker check — would the constraints apply cleanly? *(live, read-only)*

| Constraint | Blocking rows on QA | Table rows |
|---|---|---|
| `client_nutrition_plans (client_id) WHERE is_active` | **0** clients with >1 active | 2 |
| `cycle_logs UNIQUE (user_id, start_date)` | **0** duplicate pairs | 0 |
| `cycle_logs CHECK (end_date >= start_date)` | **0** violations | 0 |
| `conversations UNIQUE (least, greatest)` | **0** duplicate pairs · **0** NULL participants | 1 |
| `client_session_credits UNIQUE (payment_id)` | **0** duplicate ids | 0 |

**All four apply cleanly to QA today. No dedupe pass is required.** This retires the largest
implementation risk the source cards anticipated — *for QA only*. Production's data is
unreadable to this programme (`REL-21`, registry §9 exposure 2), so the dedupe step must
survive in the production rollout plan even though QA does not need it.

**Caveat worth stating plainly:** three of the four tables are nearly empty (0, 0, 1 rows).
That makes the constraints cheap to add and **also** means QA will not exercise them. A
live probe that *proves* the constraint rejects a duplicate must create its own fixture.

---

## 7. Security readiness

**The constraints themselves carry no security risk.** They add no policy, no grant, no
role, and no new read path. The security surface of 3A-11 is entirely in the **two RPCs**,
and only if R-01 is ruled to include them.

| Concern | Assessment |
|---|---|
| Unauthenticated access | unchanged — RLS already enabled on all four tables |
| Unauthorized authenticated access | **the live question.** A `SECURITY DEFINER` get-or-create RPC bypasses `conversations`' 3 policies by construction. It must verify the caller is one of the pair it is creating, or any authenticated user can open a conversation with anyone |
| Ownership boundary | the nutrition RPC must verify the caller is the client's coach — `client_nutrition_plans` has exactly **1** policy; the RPC must not be laxer than it |
| `search_path` | both RPCs must be born with `SET search_path = public, pg_temp` (gate 0.14, migration 122 convention). A definer function with a mutable path resolves through the *caller's* path |
| Grants | `REVOKE ALL … FROM PUBLIC, anon` + `GRANT EXECUTE … TO authenticated`, per 102/118/129/130 |
| Durability | both RPCs enter the **I-MIG-03** guard's tracked set from their first definition; FG-1's SP-1…SP-5 will assert them on the next live run |
| Replay / duplicate requests | this is what 3A-11 *is*: the four constraints are the arbiter that check-then-insert never had |
| Transaction boundaries | the nutrition RPC's whole purpose is to make deactivate+insert atomic |
| Service-role boundary | the Stripe webhook runs as service role and is unaffected by RLS; its fix is the `onConflict` target, not a policy |
| Client bypass | after 131 the database refuses the duplicate regardless of client behaviour — that is the point of CRC-06 |
| Production/debug separation | not applicable |

**Live evidence required before closure, and not yet authorized:** a probe per constraint
that creates a fixture, attempts the duplicate, observes `23505`, and removes the fixture
proving removal by a read (closure standard §7). The `d07` suite written for 3A-10 is a
usable template.

---

## 8. Test / evidence gap analysis

| Layer | Exists today | Proves | Does not prove |
|---|---|---|---|
| Contract guard (`test:contract`) | derives 91 tables + 5 views + **134 FKs** from migrations | that referenced relations/columns exist | **nothing about UNIQUE indexes or CHECKs** — it models FKs, not uniqueness |
| `billing_entitlement_contract_test.dart` | names `client_session_credits` | entitlement arithmetic | not the `payment_id` uniqueness |
| `ai_decision_integrity_test.dart`, `j01-input-assembly.mjs` | name `client_nutrition_plans` / `cycle_logs` | AI input assembly | not uniqueness |
| Negative-control harnesses | **six** exist (`ec23`, `icom01`, `uix1`×2, `wrk01`, `wrk02`) + two contract (`int02`, `nut01`), all wired to the `negative-control` CI job | the pattern is established and copyable | **none covers any 3A-11 finding** (B6) |
| Live SQL suites | FG-1, FG-2a/b, ENV-3, F-J-07/17 | function posture, workout contract, ledger | no constraint assertions |

**Missing, and each is required by the Data contract / schema ladder:**

1. a static guard asserting the four constraints exist in the migration source;
2. a live probe per constraint (fixture → duplicate → `23505` → cleanup proved by read);
3. a **negative control** per finding — the pre-fix leg that makes VERIFIED IN CI mean
   something (B6);
4. an atomicity test for the nutrition RPC (a failed insert must not leave the client with
   **no** active plan — failure mode (a) in the source card);
5. a Stripe **test-mode** replay proving a redelivered webhook grants one credit block —
   **impossible today**, `P-8`.

---

## 9. Downstream dependency analysis

| Item | Depends on 3A-11? | Exact dependency | Hard or conditional |
|---|---|---|---|
| **3B-1** (`ERR-2/3/4`) | **NO — not directly** | Wave 3B's *wave-level* prerequisite is *"3A complete"*, of which 3A-11 is the last task. 3B-1's own stated dependencies are **CON-03** and **SEC-R2** | **HARD** at the wave gate, **not** an item-level dependency |
| **3B-2** (`EC-08/09/12`) | **NO — not directly** | same wave-level gate only | **HARD** at the wave gate |
| **`EC-05`** | **NO — not directly** | gated by the wave prerequisite *and* by 3B's strict stage order (it is 3B-3, behind 3B-1 and 3B-2) | **HARD**, but 3A-11 is the *smaller* of its two blockers |
| **`EC-11`** | **NO — not directly** | gated by the wave prerequisite, by stage order (3B-4, last), **and** by owner ruling D-3's own dependency `I-WRK-01` + `I-COM-01` + `I-CHK-01`, two of which are still open | **HARD ×3**. 3A-11 is the least of its blockers |

**Discrepancy flagged, not corrected.** The previous audit
(`WAVE_3B_WRK07_EC11_EC05_AUDIT.md` §4.2) presented 3A-11 as *a* blocker of Wave 3B. That
is correct but incomplete, and could be read as implying 3A-11 is *the* blocker. It is not:

> **Completing 3A-11 unlocks nothing on its own.** It satisfies one of three independent
> gates. `EC-05` would still be blocked by 3B-1 and 3B-2; `EC-11` would still be blocked by
> stage order **and** by two open contract-allowlist dependencies. Anyone authorizing 3A-11
> in order to reach `EC-05`/`EC-11` should know they are buying **one of three** locks.

---

## 10. Authorization boundary

### A · Safe / already authorized
*(nothing in this list requires a new ruling; nothing in it was done here)*

- Reading the four source cards, the registry, the waves document and the live catalog.
- Read-only QA queries against `pg_constraint`, `pg_indexes`, `pg_policies`, and row counts.
- This audit document.

### B · Requires a new explicit authorization

| Item | Why |
|---|---|
| **Ruling on R-01** — is 3A-11 constraint-only, or constraints + writers/RPCs? | The waves row and the source cards disagree. **This must be answered first: it determines everything else** |
| **Ruling on R-02** — `I-NUT-04`'s wave and its Q-4 dependency | Filed in two waves at once |
| **Authoring migration 131** | Excluded by every recent authorization |
| **Editing `supabase/expected_applied.json`** | **Mandatory and coupled** — Rule 7 makes an undeclared 131 fail the static guard (**R-05**) |
| Two `SECURITY DEFINER` RPCs | Only if R-01 includes writers; security-sensitive, SEC review |
| `coach_program_service.dart`, `messaging_service.dart` changes | Only if R-01 includes writers |
| `stripe-webhook/index.ts` upsert | Edge Function + money; BILL owner |
| Applying 131 to QA | A separate gate with its own pre-application state check, exactly as 130 had |
| New guards, live probes, negative controls | New test files |
| Opening a registry row for `I-WMH-01` (B4) | ARCH-owned |

### C · Must remain deferred

| Item | Why |
|---|---|
| `I-PAY-01` **closure** | Billing class needs Stripe test mode; `P-8` says it does not exist. Wave 6 with `K-01` |
| The `cycle_logs` **exclusion constraint** | The source card conditions it on a dedupe pass; needs a product statement on what "overlapping periods" means |
| `I-NUT-03` (`ai_adjust_nutrition` in-place overwrite) | Same registry row as `I-NUT-04` but a different defect; Q-4-gated |
| Any Wave 3B work | Unchanged |
| Production rollout of 131 | `REL-21`; production ledger never reconciled |
| The 130 frontier move | Owner follow-up — but it **must precede** 131 (**R-05**) |

> **"3A-11 is a prerequisite for Wave 3B" is not authorization to do whatever 3A-11
> requires.** It establishes need, not permission — the same distinction Ruling A drew for
> migration 130.

---

## 11. Risks, ambiguities and conflicts

### R-01 · **CONFLICT** · 3A-11's scope · P1
`MASTER_REMEDIATION_WAVES.md:262` gives 3A-11 `Files | —` and describes it purely as
constraints. Three of four source cards require more:
`I-NUT-04` — *"move the coach's deactivate+insert into a single `SECURITY DEFINER` RPC"*;
`I-NOT-05` — *"collapse both Dart paths onto one `SECURITY DEFINER` get-or-create RPC"*;
`I-PAY-01` — *"change the insert to `upsert … onConflict: 'payment_id'`"*.
**Why it matters, concretely:** adding `UNIQUE (user_id, start_date)` to `cycle_logs`
without touching the writer is *correct* — the double tap starts failing instead of
duplicating. Adding the conversations pair index without collapsing the two check-then-insert
paths turns a rare race into a **user-visible `23505` on opening a chat**. Constraint-first
is safe for some members and a new defect for others. **Not decidable from the documents.**

### R-02 · **CONFLICT** · `I-NUT-04` is filed in two waves · P1
Registry §7.4 :1406 — `I-NUT-03`,`I-NUT-04` · Dep **Q-4** · Wave **4**.
Waves :244 and :262 — `I-NUT-04` in Wave **3A**, task 3A-11.
Same class as the already-open **B2** (`I-WRK-02` filed Wave 4/Q-7 in the registry while
Workstream I calls it independent and mechanical). Note the two findings share one registry
row, so the row's `Q-4` may attach to `I-NUT-03` alone — **plausible, unstated, not assumed
here.**

### R-03 · **GOVERNANCE GAP** · `I-WMH-01` has no registry row · P2
Recorded as §7.22 item **B4** and confirmed at this HEAD. A quarter of 3A-11 has no
tracking home, no severity of record, and no closure class.

### R-04 · **FAVOURABLE** · no dedupe required on QA · informational
§6.1. Retires the source cards' largest anticipated risk — for QA. Production unknown.

### R-05 · **AUTHORIZATION COLLISION** · the manifest is coupled to authoring 131 · P1
`check-migration-manifest.mjs` Rule 7: *"every authored version must be classified. Silence
is not a state."* Authoring 131 without declaring it **fails `static-guards` immediately**.
So `expected_applied.json` **must** be edited in the same change — a file that is currently
(a) excluded by every recent authorization, (b) carrying a pre-existing uncommitted
modification, and (c) **materially divergent**: it declares 130 `pending` while 130 is
applied, leaving ENV-3's live check red on L-2/L-5.
**Sequencing consequence: move the 130 frontier first, then author 131.** Otherwise one
edit to that file carries two unrelated reasons and the manifest's history stops explaining
itself.

### R-06 · **EVIDENCE CEILING** · no negative control for any 3A-11 item · P2
§7.22 item **B6**, confirmed. Without one, the reachable ceiling per finding is FIXED IN
CODE + FIXED ON QA + static CI. The six existing harnesses make this cheap to fix, not free.

### R-07 · **CLOSURE CLASS** · 3A-11 spans two ladders, one unreachable · P2
`I-NUT-04`/`I-WMH-01`/`I-NOT-05` are **Data contract / schema**. `I-PAY-01` is **Billing /
entitlement**, whose ladder demands Stripe **test mode** and END-TO-END for anything moving
money — and `P-8` records that none of it exists. **`I-PAY-01`'s constraint half can be
authored and applied in 3A-11; its closure cannot happen before Wave 6.** Bundling it
without saying so would leave 3A-11 permanently unclosable.

### R-08 · **RISK** · near-empty tables mean QA will not exercise the constraints · P3
0, 0, 1 and 2 rows. Any live proof must create its own fixture (§7).

---

## 12. Exact remaining work

**Everything.** Nothing 3A-11 must deliver exists. In dependency order:

1. Ruling on **R-01** (scope) and **R-02** (`I-NUT-04`'s wave).
2. ARCH opens a registry row for `I-WMH-01` (**R-03**).
3. The 130 frontier move lands (**R-05**), unblocking the manifest.
4. Migration 131 authored — 4 constraints, + 2 RPCs iff R-01 says so.
5. `expected_applied.json` declares 131 `pending`.
6. Writer changes iff R-01 says so — 2 Dart sites + 1 Edge Function.
7. Static guards + negative controls (**R-06**).
8. Separately authorized application to QA, then live probes.
9. `I-PAY-01` closure deferred to Wave 6 (**R-07**).

---

## 13. Proposed 3A-11 execution sequence

Bounded so it can be handed to an implementing agent as-is. **Steps 0–1 are governance and
must complete first.**

| # | Action | Files / systems | Authorization | Evidence produced | Tests | Stop condition |
|---|---|---|---|---|---|---|
| **0** | Owner rules R-01 and R-02; ARCH opens the `I-WMH-01` row | `MASTER_REMEDIATION_WAVES.md`, `MASTER_REMEDIATION_REGISTRY.md` | **owner + ARCH** | the two rulings, recorded | — | any ruling that widens 3A-11 beyond the four findings |
| **1** | Move the 130 frontier to `applied_through: "130"` | `supabase/expected_applied.json` | **owner (separate)** | ENV-3 live L-2/L-5 green | ENV-3 static + live | manifest guard fails |
| **2** | Author migration 131 — constraints only, idempotent, no policy, no grant | `supabase/migrations/131_*.sql` | **owner + DB/SEC** | the file | hygiene, durability guard | any constraint needs a dedupe on QA *(none does today — re-verify)* |
| **3** | Declare 131 `pending` | `supabase/expected_applied.json` | **same as step 2** | manifest green | `check-migration-manifest.mjs` | undeclared migration fails `static-guards` |
| **4** | *(iff R-01 = constraints + writers)* Two `SECURITY DEFINER` RPCs in 131 — own authorization check, `SET search_path = public, pg_temp`, revoked from `PUBLIC, anon`, granted to `authenticated` | same migration | **SEC review** | function definitions | FG-1 SP-1…SP-5; I-MIG-03 | an RPC laxer than the RLS policy it bypasses |
| **5** | *(iff step 4)* Repoint the writers | `coach_program_service.dart`, `messaging_service.dart`, `stripe-webhook/index.ts` | **JOURNEY + BILL** | diffs | unit + contract guards | any change outside these three |
| **6** | Static guard: the four constraints exist in migration source; the writers use the RPCs | `apps/mobile/test/unit/*`, `supabase/tests/contract/*` | **QA** | guard file | fails pre-fix, passes post-fix | a guard that only string-matches |
| **7** | Negative control per finding (**B6**) | `apps/mobile/tool/negative_control/` or `supabase/tests/contract/` | **QA** | pre-fix red / post-fix green | wired to the `negative-control` job | no pre-fix tree available |
| **8** | Apply 131 to QA via `supabase db push` | live QA | **owner, separate gate** | ledger 131 | pre-application state check | ledger already shows 131 |
| **9** | Live probes: fixture → duplicate → `23505` → cleanup proved by read | new suite modelled on `d07` | **QA** | per-constraint pass | closure standard §7 | any fixture left behind |
| **10** | Record; defer `I-PAY-01` closure to Wave 6 | registry, progress | **ARCH** | status rows | — | claiming `I-PAY-01` closed |

**Never, at any step:** `migration repair` · manual `schema_migrations` write · `db reset` ·
renumbering · editing `expected_applied.json` for any reason but steps 1 and 3 ·
`docs/design/**` · any Wave 3B work.

---

## 14. Recommended authorization decision

**Do not authorize 3A-11 implementation yet. Authorize step 0 only.**

R-01 is not a technicality. Constraint-first is *safe* for `cycle_logs` and *unsafe* for
`conversations`: adding the pair index while two independent check-then-insert paths remain
converts a rare silent race into a visible `23505` when a user opens a chat — the same
"silent defect becomes a permanent visible error" hazard that keeps `EC-11` blocked, and the
reason Workstream H:810 exists.

When R-01 is ruled, the recommended shape is:

> **3A-11 = the four constraints + the two RPCs + the webhook `onConflict`, authored
> together in migration 131 and its three writer files, with `I-PAY-01`'s *closure*
> explicitly deferred to Wave 6.**

That matches all four source cards, keeps each constraint landing with its writer, and is
honest that one member cannot be closed inside 3A.

**And it should be said plainly:** completing 3A-11 unlocks **one of three** locks on Wave
3B (§9). It is worth doing on its own merits — four live data-integrity defects, one of
which touches money — but not as a shortcut to `EC-05` or `EC-11`.

---

## 15. Exact next action

**Rule on R-01:** is 3A-11 *constraints only*, or *constraints + the two `SECURITY DEFINER`
RPCs + the webhook `onConflict`*?

Everything else in §13 is sequenced behind that one answer, and no file may be created or
changed until it is given.
