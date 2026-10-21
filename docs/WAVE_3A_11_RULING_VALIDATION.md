# 3A-11 — governance ruling validation

| | |
|---|---|
| **Date** | 2026-09-09 |
| **Baseline** | `43b48a7d240efac7fb8f5ba54846267cd4375c45` · `chore/qa-environments-secure-ai-backend` |
| **Mode** | Read-only governance reconciliation. Nothing implemented. |
| **Verdict** | **RULING VALIDATED WITH CONDITIONS** |
| **Live QA** | four read-only queries in the prior audit; **none here**. Production not contacted. |
| **Files created** | this file only |

---

## 1. Executive summary

**The proposed package is supported. The reason given for it is only partly supported, and
one supporting claim in the readiness audit is wrong.**

The proposed ruling — *3A-11 = constraints + the minimum writer hardening required to
introduce them safely* — arrives at the right scope. But it justifies that scope with a
safety argument that survives for **one** of the three writers and fails for the other two.
Since the prompt asks explicitly to separate *"required by the requirement"* from
*"technically prudent"*, that distinction is the substance of this validation:

| Writer | Proposed justification | Actually supported by |
|---|---|---|
| `I-PAY-01` webhook upsert | required for safety | ✅ **required for safety** — proven below |
| `I-NUT-04` RPC | required for safety | ⚠ **required by the requirement**, not by safety |
| `I-NOT-05` RPC | required for safety | ⚠ **required by the requirement**, not by safety |

**Correction to the readiness audit.** `WAVE_3A_11_READINESS_AUDIT.md` §11 R-01 states that
adding the conversations pair index without the RPC *"turns a rare race into a user-visible
`23505` on opening a chat."* **That is false.** `getOrCreateConversationWith()` wraps the
insert in `try { … } catch (e) { reportError(…); return null; }`. A `23505` is caught, the
method returns `null`, and `chat_screen._init()` falls to `getSampleMessages()`. No `23505`
reaches the user. The failure is transient and self-healing on retry, whereas today's defect
is permanent and silent — so **the index alone strictly improves `I-NOT-05`.** The safety
argument for that RPC does not exist; the *requirement* argument does.

**What does support the package shape** is not the source cards' wording — they say
*"Recommended fix"*, which is advisory — but a precedent committed one commit ago:
**3A-10's waves row also reads `Files | —`, and 3A-10 legitimately shipped two Dart files,
three test files and a live suite** under a separate explicit authorization, in one commit
under the task id (`43b48a7`). That is this programme's own established practice for a
`Files | —` migration task, and it is what makes the proposed 3A-11 shape legitimate.

**R-02 is now resolvable on evidence, and the evidence is one-sided.** `Q-4` is defined at
`MASTER_QA_RECONCILIATION.md:508` as *"What does a high-risk PAR-Q result actually do?"* —
the PAR-Q policy question. It governs neither `I-NUT-03` nor `I-NUT-04`. The registry's
`Dep = Q-4` on their shared compressed row is a **documentation defect**, not a real gate.

---

## 2. Sources reviewed

| Source | Section | What it says | Governance authority | Effect on R-01 / R-02 |
|---|---|---|---|---|
| `MASTER_REMEDIATION_WAVES.md` | §0.2 :81, §3A :262 | 131 → 3A-11; "identity constraints"; **`Files` = `—`** | **Governs sequencing and number assignment** — §0.1: *"assigned in this document … not negotiable at implementation time"* | R-01: the `—` is the whole apparent conflict |
| `MASTER_REMEDIATION_WAVES.md` | §3A :244 Findings | lists `I-NUT-04`, `I-WMH-01`, `I-NOT-05` **whole**, and `I-PAY-01` **"constraint half"** | same | **Cuts both ways** — §3.1 |
| `QA_WORKSTREAM_I…` | :337, :422, :448, :613 | four cards; each *"**Recommended fix**"*; `I-NUT-04` and `I-NOT-05` name RPCs; `I-PAY-01` names the upsert | **Evidence + recommendation**, frozen under registry §10.2. *Advisory on scope* | R-01: supports the writers as **requirement**, not as **mandate** |
| `QA_WORKSTREAM_I…` | `I-NUT-04` card | *"Product decision needed: **no**. Parallelizable: **yes**."* | source card | **R-02: decisive** |
| `QA_WORKSTREAM_I…` | `I-NUT-03` card | *"Product decision needed: **YES** — may the engine change a coach-assigned plan?"* | source card | R-02: the decision belongs to the sibling, and is **not** Q-4 |
| `MASTER_REMEDIATION_REGISTRY.md` | §7 preamble | **"Field compression"** — shared P1 rows carry one `Dep`, one `Wave` for several findings | registry's own rule | **R-02: explains the defect mechanically** |
| `MASTER_REMEDIATION_REGISTRY.md` | §7.4 :1406 | `I-NUT-03`,`I-NUT-04` · Dep **Q-4** · Wave **4** | compressed shared row | R-02: the contradiction |
| `MASTER_QA_RECONCILIATION.md` | :508 | **"Q-4 · What does a high-risk PAR-Q result actually do? (blocks CON-04)"** | the decision register | **R-02: Q-4 is about PAR-Q, not nutrition** |
| `MASTER_REMEDIATION_REGISTRY.md` | §1 :180, §4.1 :249 | `CON-04` = alias of `Q-4`; Q-4 closed by migration 115 with a regression | registry | R-02: confirms subject-matter mismatch |
| `QA_CLOSURE_STANDARD.md` | §2.1 | class ladders; **"`VERIFIED_CLOSED` requires every state its class demands. There are no partial closures"** | **governs closure** | **I-PAY-01: validates implement-now / close-later** |
| `QA_CLOSURE_STANDARD.md` | §8 :225 | migration numbers assigned in the waves doc | governs | confirms waves' authority on numbering only |
| `supabase/expected_applied.json` + `check-migration-manifest.mjs` | Rule 7 :160 | *"every authored version must be classified. Silence is not a state."* | **mechanical gate** | §6 |
| `git show 26cc330` (3A-9), `43b48a7` (3A-10) | — | **precedent: what a `Files` cell actually bounds** | practice, owner-authorized | **R-01: decisive** |
| `MASTER_REMEDIATION_REGISTRY.md` | §7.22 B4, B6 | `I-WMH-01` has no registry row; no negative control for any 3A item | registry's own open list | §7, §8 |

---

## 3. R-01 validation

### 3.1 The apparent conflict, stated precisely

The waves Findings list at :244 writes **`I-PAY-01` constraint half** — and writes
`I-NUT-04`, `I-WMH-01`, `I-NOT-05` with no qualifier. It also writes *"DAT-2 (column half)"*
and *"`H-06` (client half)"* elsewhere in the same list. **The document demonstrably knows
how to scope a subset and does so four times.**

That yields two irreconcilable readings of one document:

- **Reading A** — the three unqualified findings are in scope *whole*, RPCs included; only
  `I-PAY-01` is halved. Then `Files | —` is wrong.
- **Reading B** — the 3A-11 row's own text (*"identity constraints"*) plus `Files | —` is
  the scope. Then listing `I-NUT-04` whole is loose shorthand.

**Neither can be eliminated from the text.** This is an internal inconsistency in the
governing document, not a conflict between two documents — a sharper diagnosis than the
readiness audit's.

### 3.2 What resolves it: the 3A-10 precedent

| Task | waves `Files` cell | What the commit actually contained |
|---|---|---|
| **3A-9** (`26cc330`) | `custom_exercise_service.dart` | that Dart file · **`expected_applied.json`** · migration 129 — **3 files** |
| **3A-10** (`43b48a7`) | **`—`** | migration 130 · **`chat_media_path.dart`** · **`chat_screen.dart`** · 3 test files · `d07` live suite · `run.mjs` · 2 decision docs — **10 files** |

Two conclusions follow, and they are facts about this repository rather than inferences:

1. **The `Files` cell is not an exhaustive scope boundary.** 3A-10's cell said `—` and the
   task shipped ten files, owner-authorized, in one commit under the task id.
2. **`expected_applied.json` travels inside the migration task's commit** (3A-9 did exactly
   that) — which independently settles §6.

**Therefore the proposed package shape — migration + writer conformance + tests + evidence,
one commit under 3A-11 — is supported by established practice**, and Reading B's `Files | —`
objection is answered.

**But note what the precedent does *not* license.** 3A-10's client changes were *unavoidable*:
migration 130 changed the storage path contract, so the pre-existing client code would have
been broken by the migration. That is a genuine "required to safely implement". Whether each
3A-11 writer meets that same bar is a separate question, answered next.

### 3.3 Component-by-component validation

**A · Migration 131 constraints — `REQUIRED BY 3A-11`.**
Both waves rows name them; three of four exist in no other form. Unambiguous.

**B · `I-NUT-04` atomic `SECURITY DEFINER` RPC — `REQUIRED BY 3A-11` (not required for safety).**
Workstream I's fix is *"partial UNIQUE … **and** move the coach's deactivate+insert into a
single `SECURITY DEFINER` RPC"* — one fix in two parts.
*Safety analysis, done rather than assumed:* `coach_program_service.dart:253-277` has **zero
`catch`**; `client_detail_screen.dart:1784` awaits it with no `try`, then shows *"Nutrition
plan saved!"*. On a throw the exception unwinds before the snackbar, so **no false success is
produced** — `_saving` is left `true` and the sheet hangs. With the index and no RPC, a
`23505` can only arise where the deactivate was RLS-narrowed — a case that today produces
**two active rows → `maybeSingle()` 406 → silent default macros**. Both outcomes are bad;
neither is clearly worse. **The constraint does not make this defect worse. The RPC is the
requirement's other half, not a safety prerequisite.**

**C · `I-NOT-05` Dart writer changes — `REQUIRED BY 3A-11` (and the readiness audit's safety claim is withdrawn).**
Workstream I: *"UNIQUE INDEX … **and** collapse both Dart paths onto one `SECURITY DEFINER`
get-or-create RPC."*
*Safety analysis:* `messaging_service.dart:87-114` wraps the insert in `try … catch (e) {
reportError(…); return null; }`. A `23505` is **caught**; `chat_screen._init()` receives
`null` and falls to `getSampleMessages()`. **No `23505` reaches the user.** The failure is
transient and self-healing on retry; today's defect is permanent, silent history
fragmentation. **The index alone strictly improves this finding.**
⚠ **This falsifies `WAVE_3A_11_READINESS_AUDIT.md` §11 R-01's central example.** Recorded
here; that document is not rewritten.
*(Second-order note, not a blocker: the fallback lands in `getSampleMessages()` — the H-07
fabrication path, an independent open P1. The constraint does not create it.)*

**D · `I-PAY-01` webhook upsert — `REQUIRED TO SAFELY IMPLEMENT 3A-11`. The only one.**
`stripe-webhook/index.ts:130` is a bare `.insert()`; `:157-159` is
`catch (e) { return new Response(\`Handler error: ${e}\`, { status: 500 }); }`.
**Stripe retries every non-2xx.** So adding `UNIQUE (payment_id)` without the upsert makes a
redelivered `checkout.session.completed` raise `23505` → **HTTP 500** → Stripe retries →
`23505` again → **the endpoint fails permanently for that event**, for up to Stripe's full
retry window. Every prior write in the handler is already idempotent (`payments` UPDATE…WHERE;
`subscriptions` upsert; `coach_client_relationships` upsert at :126; `event_registrations`
upsert), so each retry redoes them and dies at the same line.
**Today's defect is a silent duplicate credit grant that returns 200. Constraint-only
converts that into a permanently failing production webhook.** That is a genuine
constraint-induced regression, and it is the one component whose coupling is mandatory.

**E · Tests / guards / probes — `REQUIRED TO SAFELY IMPLEMENT 3A-11`.** §8.

### 3.4 R-01 verdict

**VALIDATED WITH CONDITIONS.** The package shape is supported — by the 3A-10 precedent, and
by Workstream I's fixes being single fixes in two parts. The blanket justification
*"required to safely introduce the constraints"* is **not** supported: it holds for
`I-PAY-01` alone. The ruling should be issued on the correct basis, because the basis
determines what a future reader may generalise from it.

---

## 4. R-02 validation

**Resolvable on evidence. Not a genuine ambiguity — a documentation defect.**

| Step | Evidence |
|---|---|
| The contradiction | registry §7.4 :1406 — shared row `I-NUT-03`,`I-NUT-04` · Dep **Q-4** · Wave **4**; waves :244/:262 — `I-NUT-04` in 3A-11 |
| The mechanism | registry §7 preamble: **"Field compression"** — shared P1 rows carry **one** `Dep` and **one** `Wave` for several findings |
| **What Q-4 actually is** | `MASTER_QA_RECONCILIATION.md:508` — **"Q-4 · What does a high-risk PAR-Q result actually do? (blocks CON-04)"**; registry :180 confirms `CON-04` ↔ `Q-4`; :249 records it closed by migration 115 |
| Subject-matter test | **Q-4 governs PAR-Q risk policy. It has no bearing on nutrition-plan uniqueness — or on `ai_adjust_nutrition`** |
| `I-NUT-04`'s own card | *"Product decision needed: **no**. Parallelizable: **yes**."* |
| `I-NUT-03`'s own card | *"Product decision needed: **YES** — may the engine change a coach-assigned plan at all…"* · *"Parallelizable: no"* — a real decision, but **an unnumbered one, not Q-4** |
| Precedent for the fix | owner ruling **D-3** (§7.14) corrected `EC-11`'s wrong `Dep` cell; open item **B2** records the identical defect for `I-WRK-02` |

**Finding:** the `Q-4` on that row is wrong for **both** findings — `I-NUT-04` needs no
decision, and `I-NUT-03`'s decision is a different, unnumbered question. `Wave 4` is
likewise contradicted for `I-NUT-04` by the waves document, which governs sequencing.

**Verdict: `I-NUT-04` belongs to 3A-11.** The evidence is one-sided. But the repository's own
convention is that a wrong `Dep`/`Wave` cell is corrected by **owner ruling recorded in the
registry** (D-3's shape), never by an implementer's inference — so this needs a one-line
ruling, which the evidence above makes cheap.

**`I-NUT-03` stays out of 3A-11** — different defect, real product decision, not parallelizable.

---

## 5. `I-PAY-01` validation

The four gates the prompt asks to separate are genuinely separate here:

| Gate | State | Authority |
|---|---|---|
| **Implementation** | ✅ can happen in 3A-11 — migration + `onConflict`, and §3.3.D makes the pair mandatory | waves :244 assigns the **"constraint half"** to 3A |
| **QA verification** | ⚠ partial — a duplicate-`payment_id` rejection is provable on QA; a **Stripe redelivery** is not | — |
| **Closure** | ❌ **unreachable in Wave 3A** | Billing class needs *VERIFIED LIVE against Stripe **test mode*** + *END-TO-END for anything that moves money*; **`P-8` records no QA Stripe test-mode credentials, runbook or price ids exist** (Wave 6) |
| **Production rollout** | ❌ out of scope | `REL-21` |

**Does the standard permit implementation now and closure later?** **Yes, explicitly.**
`QA_CLOSURE_STANDARD.md` §2.1: *"`VERIFIED_CLOSED` requires every state its class demands.
There are no partial closures."* — closure is all-or-nothing, but the states are a **ladder**
and intermediate statuses are the norm. Precedents in the registry: `UIX-1` sat at
`REMEDIATED` with END-TO-END absent; `SEC-R2`/`SEC-R3` sit at four of five states.

**Verdict: VALIDATED.** `I-PAY-01`'s constraint + upsert are authorable in 3A-11 and reach
`REMEDIATED`; **`VERIFIED_CLOSED` is deferred to Wave 6 with `K-01`.** The one condition:
**the ruling must say so explicitly**, or 3A-11 becomes permanently unclosable and the
programme inherits a task that can never exit.

---

## 6. `expected_applied.json` validation

| Question | Answer |
|---|---|
| Does Rule 7 require the update? | **Yes.** `check-migration-manifest.mjs:160` — *"every authored version must be classified. Silence is not a state."* An authored-but-undeclared 131 **fails `static-guards`** |
| Exactly when? | **At authoring time**, not at application. Registry §7.22: *"Each remains subject to `expected_applied.json` declaration as `pending` at authoring time."* |
| Same commit / package? | **Yes — by precedent.** 3A-9 (`26cc330`) committed `expected_applied.json` **with** migration 129 |
| Can it be separated into a prior baseline reconciliation? | **Partly, and it should be.** Two *different* edits are pending on that file: **(a)** the **130 frontier move** (`applied_through` 129 → 130), an owner follow-up outstanding since the 3A-10 pass and the reason ENV-3's live check is red on L-2/L-5; **(b)** declaring **131 `pending`**. These are unrelated. **(a) must land first, on its own**, or one edit carries two reasons and the manifest stops explaining itself |
| Separate authorization? | **Yes, for both.** The file has been explicitly excluded from every recent authorization and currently carries a pre-existing uncommitted modification |

**Verdict: VALIDATED, with a sequencing condition** — frontier move first as its own change;
131's `pending` declaration inside the 3A-11 commit.

---

## 7. `I-WMH-01` validation

| Question | Answer |
|---|---|
| Authoritative source | `QA_WORKSTREAM_I_DATA_CONTRACT_REPORT.md:422` — the only full card. P2 |
| Registry row | **None.** Confirmed by §7.22's own *"Still open"* list, item **B4**: *"`I-WMH-01` is named in `MASTER_REMEDIATION_WAVES.md` and in Workstream I but has **no row in this registry**"* |
| Intended wave | Wave 3A / 3A-11 — waves :244 and :262 |
| Documentation defect? | **Yes**, and already self-reported. Not newly discovered here |
| Required for 3A-11 *execution*? | **No.** The migration can be written and applied without it |
| Required for 3A-11 *closure*? | **Yes.** With no row there is no status field, no severity of record and no closure class — the finding cannot be moved to any status because there is nothing to move |
| Separate authorization? | **Yes — ARCH.** The registry is ARCH-owned (`COWORK_FILE_OWNERSHIP.md` §3) |

**Verdict: VALIDATED as reported.** Sequencing note: ARCH should open the row **before**
implementation, so the work has somewhere to land — but it does not block authoring.

---

## 8. Test / evidence validation

| Class | Item | Basis |
|---|---|---|
| **MANDATORY** | Static guard: the four constraints exist in migration source | Data contract class requires VERIFIED IN CI; **`test:contract` models tables/columns/FKs and cannot see a UNIQUE index or a CHECK** — nothing today would notice their removal |
| **MANDATORY** | Negative control per finding | Closure standard §4 — *a check that has never failed against the pre-fix tree proves nothing*. **B6 records that none exists for any 3A item** |
| **MANDATORY** | Live duplicate-rejection probe per constraint (fixture → duplicate → `23505` → cleanup **proved by a read**) | §2.1 *"VERIFIED LIVE where a read path exists"*; §7 hygiene. Template: the `d07` suite from 3A-10 |
| **SAFETY-CRITICAL** | Webhook replay test — a redelivered event grants **one** credit block | §3.3.D: constraint-only makes the endpoint fail permanently. This is the test that proves the coupling worked |
| **SAFETY-CRITICAL** | RPC authorization tests — a non-participant cannot open a conversation; a non-coach cannot assign a plan | Both RPCs are `SECURITY DEFINER` and bypass RLS on tables carrying 3 and 1 policies |
| **SAFETY-CRITICAL** | RPC posture: `SECURITY DEFINER` · `SET search_path = public, pg_temp` · `REVOKE … FROM PUBLIC, anon` · `GRANT … TO authenticated` | Gate 0.14; migration 122 convention; both enter the **I-MIG-03** tracked set and FG-1 SP-1…SP-5 |
| **SAFETY-CRITICAL** | Nutrition RPC atomicity — a failed insert must not leave the client with **no** active plan | Source-card failure mode (a); the defect the RPC exists to fix |
| **RECOMMENDED** | Concurrency test on the conversations RPC (two simultaneous get-or-create → one row) | Proves the arbiter; not closure-blocking |
| **RECOMMENDED** | Flutter writer unit tests | `messaging_service.dart` has no seam today (N-10 class) |
| **UNAVAILABLE** | Stripe **test-mode** live verification | **`P-8`** — no QA Stripe credentials, runbook or price ids. Wave 6 |
| **DEFERRED** | `cycle_logs` exclusion constraint + its overlap tests | Source card conditions it on a dedupe pass and it needs a product statement on what "overlapping periods" means |
| **DEFERRED** | Production rollout evidence | `REL-21` |

**One evidence note worth stating:** the four target tables hold **2, 0, 1 and 0 rows** on QA.
The constraints are therefore cheap to add **and QA will never exercise them incidentally**.
Every live proof must create its own fixture and remove it — there is no ambient data to
lean on.

---

## 9. Final proposed authorization boundary

### A · Authorized 3A-11 implementation
1. `supabase/migrations/131_*.sql` — the four constraints, idempotent, no policy, no grant.
2. In the same migration: two `SECURITY DEFINER` RPCs (nutrition atomic assign;
   conversation get-or-create) with the §8 posture.
3. `apps/mobile/lib/features/coach/data/coach_program_service.dart` — call the RPC.
4. `apps/mobile/lib/features/messaging/data/messaging_service.dart` — both paths onto the RPC.
5. `supabase/functions/stripe-webhook/index.ts:130` — `insert` → `upsert … onConflict:'payment_id'`.
6. `supabase/expected_applied.json` — declare **131** `pending` (only this).

### B · Required QA / security verification
7. Static guard for the four constraints + the RPC posture.
8. Negative control per finding (B6).
9. Live duplicate-rejection probes, fixtures removed and removal proved by a read.
10. RPC authorization + atomicity tests.
11. Application of 131 to QA — **a separate gate with its own pre-application state check.**

### C · Required governance / documentation
12. **Owner ruling on R-01**, stated on the correct basis (§3.4).
13. **Owner ruling on R-02** — `I-NUT-04` → 3A-11; the `Q-4` cell is a defect (§4).
14. **ARCH opens a registry row for `I-WMH-01`** (B4).
15. **Explicit statement that `I-PAY-01` reaches `REMEDIATED`, not `VERIFIED_CLOSED`** (§5).

### D · Deferred
`I-PAY-01` closure (Wave 6, `K-01`) · `cycle_logs` exclusion constraint · `I-NUT-03` ·
production rollout · all Wave 3B.

### E · Must NOT be included
Migration 132+ · `migration repair` · manual `schema_migrations` writes · `db reset` ·
renumbering · `known-violations.json` · `docs/design/**` · **the 130 frontier move** (§6 —
its own change, first) · any `EC-05`/`EC-11`/`WRK-07` work · `workout_service.dart`.

### F · Requires a separate human ruling
Items 12–15, **and** any decision to proceed with a subset (e.g. constraints-only for
`I-WMH-01` while the others wait) — that is a re-scoping, not an implementation choice.

---

## 10. Downstream impact

| Item | Current status | Depends on 3A-11? | Does completing 3A-11 remove the block? | Remaining blockers |
|---|---|---|---|---|
| **3B-1** (`ERR-2/3/4`) | not started | only via the wave gate *"3A complete"* | **No** | `SEC-R2` not `VERIFIED_CLOSED`; `CON-03` |
| **3B-2** (`EC-08/09/12`) | three open P1 rows | only via the wave gate | **No** | 3B-1 precedes it in the strict order |
| **`EC-05`/`N-07`** | live, unpinned | only via the wave gate | **No** | 3B-1 · 3B-2 (stage order) · **no test seam** (N-07/R-4) |
| **`EC-11`** | live, 14 sites | only via the wave gate | **No** | stage order (3B-4, last) · **`I-COM-01` + `I-CHK-01` still in the allowlist** (ruling D-3) |
| **`WRK-07`** | provider half closed; **screen half live** | **No — none** | **No** | its own L4 obligation; **no tracking row** (N-02) |

**Stated plainly:** 3A-11 satisfies **one of three** independent gates on Wave 3B and
**none** of `WRK-07`'s. It is worth doing for its own four live defects — one of which
touches money — and not as a route to `EC-05` or `EC-11`.

---

## 11. Unresolved governance questions

| # | Question | Who |
|---|---|---|
| **U-1** | R-01's *basis*: the package is right, the safety justification holds only for `I-PAY-01` (§3.3). Issue the ruling on the correct basis | Owner |
| **U-2** | R-02: confirm `I-NUT-04` → 3A-11 and record `Q-4` as a defect on the shared row (§4) | Owner + ARCH |
| **U-3** | `I-NUT-03`'s product decision is real but **unnumbered** — it has no Q-id anywhere | ARCH |
| **U-4** | `I-WMH-01` registry row (B4) | ARCH |
| **U-5** | `I-PAY-01`'s terminal status inside 3A-11 must be named `REMEDIATED` up front (§5) | Owner |
| **U-6** | Does `I-WMH-01`'s **exclusion constraint** belong to 3A-11 or a later wave? Its card conditions it on a dedupe pass and an undefined product meaning of "overlapping" | Owner |
| **U-7** | Sequencing: the 130 frontier move must land before 131 (§6) | Owner |

---

## 12. Recommended ruling

**Accept the proposed package. Amend its stated basis. Add four conditions.**

> **3A-11 = migration 131 (four identity constraints + two `SECURITY DEFINER` RPCs) + the
> three writer conformance changes + guards, negative controls and live probes, committed as
> one package under task 3A-11.**
>
> **Basis, corrected:** (i) Workstream I states each fix as a **single fix in two parts** —
> index *and* writer; and (ii) **3A-10's precedent** establishes that a `Files | —` migration
> task in Wave 3A may carry its client conformance under one commit with separate explicit
> authorization. The blanket claim that every writer is *"required to safely introduce the
> constraint"* is **true only of `I-PAY-01`**, where constraint-only converts a silent
> duplicate grant into a permanently failing Stripe webhook.
>
> **Conditions:**
> 1. **`I-PAY-01` reaches `REMEDIATED`, not `VERIFIED_CLOSED`** — Stripe test mode does not
>    exist (`P-8`); closure travels to Wave 6 with `K-01`.
> 2. **`I-NUT-04` is confirmed to 3A-11** and the `Q-4` dependency on registry §7.4 :1406 is
>    recorded as a documentation defect — `Q-4` is the PAR-Q question and governs neither
>    nutrition finding.
> 3. **ARCH opens a registry row for `I-WMH-01`** before implementation.
> 4. **The 130 frontier move lands first**, as its own change, before `expected_applied.json`
>    is touched for 131.
>
> **Not authorized by this ruling:** applying 131 to QA (its own gate), the `cycle_logs`
> exclusion constraint, `I-NUT-03`, production rollout, and any Wave 3B work.

---

## 13. Exact next implementation package

Only after U-1, U-2, U-4, U-5 and U-7 are answered.

| # | Action | Files | Evidence | Stop condition |
|---|---|---|---|---|
| 1 | 130 frontier move — `applied_through: "130"` | `expected_applied.json` | ENV-3 live L-2/L-5 green | manifest guard fails |
| 2 | Author 131 — four constraints, idempotent | `supabase/migrations/131_*.sql` | file + hygiene + durability guard | any constraint needs a dedupe on QA *(none does today — re-verify first)* |
| 3 | Add the two RPCs to 131 with the §8 posture | same file | FG-1 SP-1…SP-5 assertable | an RPC laxer than the RLS policy it bypasses |
| 4 | Declare 131 `pending` | `expected_applied.json` | manifest green | undeclared migration fails `static-guards` |
| 5 | Repoint the three writers | `coach_program_service.dart`, `messaging_service.dart`, `stripe-webhook/index.ts` | diffs | any file outside these three |
| 6 | Static guard + negative control per finding | `apps/mobile/test/**`, `supabase/tests/**` | fails pre-fix, passes post-fix | a guard that only string-matches |
| 7 | **STOP.** Report; request application authorization | — | package report | — |
| 8 | *(separate gate)* Apply 131 to QA; run live probes; cleanup proved by a read | live QA | ledger 131 + probe results | any fixture left behind |

**Never:** `migration repair` · manual `schema_migrations` write · `db reset` · renumbering ·
touching `expected_applied.json` for any reason but steps 1 and 4 · `docs/design/**` ·
`workout_service.dart` · any Wave 3B work.
